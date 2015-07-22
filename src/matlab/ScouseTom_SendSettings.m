function [ Ard,OKFLAG ] = ScouseTom_SendSettings( Ard,ExpSetup)
%ScouseTom_SendSettings Sends the information of the protocol, time to inject
%per protocol line etc. to the arduino in the agreed fashion

%
% Data is sent in the form <###> with confirmation.
% Inputs:
%   Ard - Arduino Serial Object
%   ExpSetup - Structure containing all experiment settings. namely :
%
%   Prt - vector for injection protocol, must be pairs and less than max
%   channel 37. Nx2
%   N_elec - number of electrodes, used in contact impedance measurement.
%   So this should equal the highest numbered electrode you are using.
%   InjectionTime - Time in ms for each injection pair before switching to
%   the next. Must be greater than 1 ms (5 ms for safety) and less than
%   half an hour (32 bit int)
%   ContactImpedanceTime - InjectionTime but for contact impedance check
%   only.
%
%   Outputs:
%   Flag - goodness flag, low is bad
%% Some variables

CScommerrmsg='!E';
CSsettingserrmsg='!S';
CScommOKmsg='+OK';
OKFLAG=0;

%% Parse inputs

%this is badly coded and incomplete....

%disp('Checking your ExpSetup...');

[settingsgood,ExpSetup]=ScouseTom_ValidateExpSetup(ExpSetup);

if settingsgood
    %disp('Validated ok! :)');
else
    warning('Bad input settings, not doing anything!');
    return
end

%if no bad electrodes were flagged or missed

if ~(isfield(ExpSetup,'Bad_Elec')) %if the field exists
    N_badelec=0;
    BadElectrodes=[];
else
    if isempty(ExpSetup.Bad_Elec) % and some bad ones have been enterred
        N_badelec=0;
        BadElectrodes=[];
    else
        N_badelec=length(ExpSetup.Bad_Elec);
        BadElectrodes=ExpSetup.Bad_Elec;
    end
end




%% get some of the settings in this

N_prt = size(ExpSetup.Protocol,1);
N_freq= size(ExpSetup.Freq,1);

if (ExpSetup.StimulatorPulseWidth ==0 || ExpSetup.StimulatorTriggerOffset ==0 || ExpSetup.StimulatorTriggerTime ==0)
    Stimmode=0;
else
    Stimmode=1;
end

% fprintf('Number of lines in protocol : %d\n',N_prt);
% fprintf('Number of frequencies : %d\n',N_freq);

if N_freq == 1
    injmodestr='SingleFreqMode';
else
    injmodestr='MultiFreqMode';
end

fprintf('Controller will use : %s\n',injmodestr);

if Stimmode
    fprintf('Stimulation in ON at %.2f V with %dms repeat and %d us pulsewidth\n',ExpSetup.Info.StimulatorVoltage, ExpSetup.StimulatorTriggerTime,ExpSetup.StimulatorPulseWidth);
else
    %fprintf('Stimulation is OFF\n');
end

%% flush serial buffer - dont care what has happened before
FlushSerialBuffer(Ard);

%% start init command on ard


%send command to put arduino in receptive state
fprintf(Ard,'I');

%ard checks CS is ok before moving on
disp('Checking CS is OK...');
[resp,numflg,cscommok]=ScouseTom_ard_getresp(Ard);

if (~cscommok)
    warning('Didnt get message from Arduino....');
    return
end
if strcmp(resp,CScommerrmsg)
    warning('CS COMM ERROR - CHECK FRONT PANEL');
end

if strcmp(resp, CScommOKmsg)
    disp('Current Source connected OK! yay!');
end

% ard sends "im waiting" message before cracking on
[resp,numflg,cscommok]=ScouseTom_ard_getresp(Ard);

if (~cscommok)
    warning('Ardunio wasnt ready for settings...shits fucked yo');
    return
end

if strcmp(resp, 'A')
    disp('Ardunio Ready to receive settings');
else
    warning('Didnt get expected ready message from ard');
    return
end

fprintf(Ard,'A'); % send byte telling arduino to await settings
fprintf('##################################\n');
fprintf('Sending settings to arduino...');
finished_sending=0;
%send all of the data, stop if something fucks up - there is a better way
%to do this
while (finished_sending ==0)
    
    okflag=ScouseTom_ard_sendnumconfim(Ard,N_prt,'Protocol Length');
    if (~okflag)
        finished_sending=1;
        break
    end
    
    okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.Elec_num,'Number of Electrodes');
    if (~okflag)
        finished_sending=1;
        break
    end
    
    okflag=ScouseTom_ard_sendnumconfim(Ard,N_freq,'Number of Frequencies');
    if (~okflag)
        finished_sending=1;
        break
    end
    
    okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.Repeats,'Number of Repeats');
    if (~okflag)
        finished_sending=1;
        break
    end
    
    okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.ContactCheckInjectTime,'Contact Z Time');
    if (~okflag)
        finished_sending=1;
        break
    end
    
    okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.StimulatorTriggerTime,'Stimulator Trigger Time');
    if (~okflag)
        finished_sending=1;
        break
    end
    okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.StimulatorTriggerOffset,'Stimulator Trigger Offset');
    if (~okflag)
        finished_sending=1;
        break
    end
    okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.StimulatorPulseWidth,'Stimulator Pulse Width');
    if (~okflag)
        finished_sending=1;
        break
    end
    
    okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.StimulatorWiperSetting,'Stimulator Wiper Setting');
    if (~okflag)
        finished_sending=1;
        break
    end
    
    
    fprintf('Timing OK, ');
    
    %% Send protocol
    
    %send sources
    for n=1:N_prt
        okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.Protocol(n,1),['Source ' num2str(ExpSetup.Protocol(n,1))]);
        if (~okflag)
            finished_sending=1;
            break
        end
    end
    
    %send sinks
    for n=1:N_prt
        okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.Protocol(n,2),['Sink ' num2str(ExpSetup.Protocol(n,2))]);
        if (~okflag)
            finished_sending=1;
            break
        end
    end
    fprintf('Protocol OK, ');
    
    %% send amplitudes and freqs
    
    %send freqs
    for n=1:N_freq
        okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.Freq(n),['Freq ' num2str(ExpSetup.Freq(n,1))]);
        if (~okflag)
            finished_sending=1;
            break
        end
    end
    
    
    %send amps
    for n=1:N_freq
        okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.Amp(n),['Amp ' num2str(ExpSetup.Amp(n,1))]);
        if (~okflag)
            finished_sending=1;
            break
        end
    end
    
    %send measurement times
    for n=1:N_freq
        okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.MeasurementTime(n),['MeasTime ' num2str(ExpSetup.MeasurementTime(n,1))]);
        if (~okflag)
            finished_sending=1;
            break
        end
    end
    
    fprintf('AmpsFreqsTimes sent OK \n');
    
    
    
    %% send bad electrodes
    
    if N_badelec == 0
        okflag=ScouseTom_ard_sendnumconfim(Ard,0,['No Bad Elec Flag']);
        if (~okflag)
            finished_sending=1;
            break
        end
    else
        okflag=ScouseTom_ard_sendnumconfim(Ard,N_badelec,['Bad Elec Num']);
        if (~okflag)
            finished_sending=1;
            break
        end
        
        for n=1:N_badelec
            okflag=ScouseTom_ard_sendnumconfim(Ard,ExpSetup.Bad_Elec(n),['Bad Elec ' num2str(ExpSetup.Bad_Elec(n))]);
            if (~okflag)
                finished_sending=1;
                break
            end
        end
    end
    
    finished_sending=1;
    okflag=1;
end

%% read ok message from arduino that settings all sent ok
[resp,numflg,cscommok]=ScouseTom_ard_getresp(Ard);

if (~cscommok)
    error('Didnt get message from Arduino....');
end
if strcmp(resp,CScommerrmsg)
    warning('Error during settings read');
    return
end

if strcmp(resp, CScommOKmsg)
    disp('All settings sent ok! Tadow! :)');
end

%% check all settings were sent ok to CS

disp('Ardunio is checking settings');
pause(1);

[resp,numflg,cscommok]=ScouseTom_ard_getresp(Ard);

if (~cscommok)
    error('Didnt get message from Arduino....');
end
if strcmp(resp,CSsettingserrmsg)
    warning('INPUT CHECK FAILED!? OMGWTFBBQ CHECK CS CONNECTION');
end

if strcmp(resp, CScommOKmsg)
    disp('Settings all check out, you are ready to inject!!!');
end


OKFLAG=okflag;

FlushSerialBuffer(Ard);

end

function FlushSerialBuffer(Ard)
%remove anything in the serial buffer - otherwise matters are super
%confused


while (Ard.BytesAvailable >0) %whilst there are bytes to read
    
    jnk=fread(Ard,Ard.BytesAvailable,'uchar'); %read as much as possible from buffer
    %     jnkstr=sprintf(char(jnk)); %convert to string
    %     jnkstr=strrep(jnkstr,sprintf('\r\n'),''); %remove newlines
    %     fprintf(logfid,'%.2fs\t\tSerial Buffer flushed: %s\n',toc(tstart),jnkstr); %write to log
    pause(0.2); %wait a bit to fill up Serial buffer is necessary - not needed on my PC but added in case related problems to the pause needed at the start
    
end

end


