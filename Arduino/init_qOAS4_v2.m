% function [mlc,filter_arduino,...
%             s_LPSP,s_VISNIR,DAQ,HWP, ...
%             ophirApp, ophirJuno, ...
%             shutter_arduino,...
%             spectrometerObj, ...
%             LC_Handle, LC_Info, TC_Handle, TC_Info, PBS] ...
%         = init_qOAS4(isUsing_OceanSpectra,Switch_JunoUSB)
%%  version 2.0 starts using Juno, yuanhui 20190206
% % v3.0 added liquid crystal


%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here
delete(instrfindall);

%%
if isUsing_LCVR
    %% INIT ROTOR 
    clear PBS; 
    global PBS; % make h a global variable so it can be used outside the main
              % function. Useful when you do event handling and sequential move
%     % Create Matlab Figure Container
%     fpos    = get(0,'DefaultFigurePosition'); % figure default position
%     fpos(3) = 650; % figure window size;Width
%     fpos(4) = 450; % Height
%     f2 = figure('Position', fpos,'Menu','None','Name','APT GUI - PBS');
%     % Create ActiveX Controller
%     PBS = actxcontrol('MGMOTOR.MGMotorCtrl.1',[20 20 600 400 ], f2);
%     % Initialize and start Control
%     PBS.StartCtrl;
%     % Set the Serial Number
% %      SN=27501884; % Power control halfwave plate
%      SN=83847493; % put in the serial number of the hardware
%      set(PBS,'HWSerialNum', SN);
%     % Indentify the device
%      PBS.Identify;
%      pause(5); % waiting for the GUI to load up;
%      PBS.MoveHome(0,0); % Home the stage. First 0 is the channel ID (channel 1)
%                      % second 0 is to move immediately
%      disp('Home Started!');
%     % % Event Handling
%     % HWP.registerevent({'MoveComplete' 'MoveCompleteHandler'});

    a=motor.listdevices;
    PBS=motor;
    PBS.connect('83847493');
    PBS.home();
    PBS.Data = [0 170];
    PBS.MinAngles =9.599718750000000;
    disp('PBS Homed!');
    PBS.moveto(PBS.MinAngles);  
    
    global LCrotor
    LCrotor=motor;
    LCrotor.connect('83827850');
    LCrotor.home();
    disp('LCrotor Homed!');
    LCrotor.MinAngles=42.994619201660156; % MinAngle is actually the max LCVR dynamic angle.
    LCrotor.Data = [LCrotor.MinAngles LCrotor.MinAngles+89];
    LCrotor.moveto(LCrotor.MinAngles);  
    
    addpath('ThorlabsLCTC');
    global LC_Handle
    global TC_Handle
    global LC_Info
    global TC_Info
    [LC_Handle, LC_Info] = LC_init();
    [TC_Handle, TC_Info] = TC_init();
    Return = TC_Enable(TC_Handle, true);
    LC_setVolt(LC_Handle, 0);
else
    LC_Handle   = 0;
    LC_Info     = 0;
    TC_Handle   = 0;
    TC_Info     = 0;
    PBS         = 0;
end

%% INIT ROTOR 
clear HWP; 
global HWP; % make h a global variable so it can be used outside the main
          % function. Useful when you do event handling and sequential move
% if HWP.isconnected
%     disp(['HWP reconnected for measurements!']);
% else
    disp('Reconnceting to HWP - ');
    a=motor.listdevices;
    HWP=motor;
    HWP.connect('27501884');
    HWP.reset('27501884');
    HWP.updatestatus;
    HWP.lastPos = HWP.position;
%     disp('HWP Homing');
%     HWP.home();
%     HWP.MinAngles =0;
%     HWP.moveto(HWP.MinAngles);  
% end

disp(['Reconnected HWP at ' num2str(round(HWP.position,2)) ' degrees' ]);
    disp('HWP Homing');
    pause(3);
    HWP.home();
    HWP.MinAngles =0;
    HWP.moveto(HWP.MinAngles);  
    HWP.lastPos = HWP.position;
disp('HWP Homed!');
HWP.isconnected;
pause(3);
%
try 
    HWP.disconnect;
catch ME
    display(['HWP Rotor ' ME.message]);
end
disp('HWP disconnected. Reconnect when needed.'); % Thorlabs driver drop offline if kept connected ... yh 20200604
% % use this to reconnect
% reconnectHWP;
% HWP.moveto(45);
% % use this to disconnect
% disconnectHWP;


%% Servo initialization 
global ac
global filter_handle
global s_LPSP
global s_VISNIR

ac = ARDUINO_CONTROL();
ac.filter_arduino_connect();

% initializing 
ac.VIS_NIR_Select('VIS',s_VISNIR);
ac.LPSP_FilterSelect ('VIS',s_LPSP);
ac.LPSP_FilterSelect ('BLK',s_LPSP);
disp('FILTER ARDUINO init');
pause(2);

%% Thorlabs/Oceanid shuttter
global shutter_handle

ac.shutter_arduino_connect();

%initializing
ac.open_shutter('Thorlabs_LaserShutter',shutter_handle);
ac.close_shutter('Thorlabs_LaserShutter',shutter_handle);
ac.open_shutter('Ocean_LampShutter',shutter_handle);
ac.close_shutter('Ocean_LampShutter',shutter_handle);
disp('Shutter init');
%% INIT LASER
global mlc
addpath('D:\Users\yuanhui.huang\Documents\MATLAB\SpitLight1_513_53_yh2_20200608')
mlc = LASER_CONTROL; % automatically run the SpitLight software 
mlc.LoginAdmin;
mlc.initLaser;
mlc.tune(mlc.VISIR); % NEED this to init laserbefore lampON
mlc.lampON();
pause(9);
mlc.qswitchON();
mlc.Data=709; % SWITCH_WL_SIG_IDLER = 709; % Innolas OPO gives signal at 420-709 and idler at 710-2100 (>2100 untuned) nm, as indicated in Spitlight. =709
% 729 switch found to be good to remove dip at 710-720 nm. 20191024 yuanhui
disp('LASER');
mlc.tune(mlc.Data);
%% Powermeter INITIALISATION
global ophirJuno
global ophirApp
[ophirApp,ophirJuno] = init_OphirCOM(ophirJuno);


%% Juno-interfaced powermeter innitialisation
% init_Juno_PE10BFC.m


%% INIT DAQ
global DAQ
addpath('D:\Users\yuanhui.huang\Documents\MATLAB\CompuScope MATLAB SDK')
addpath('D:\Users\yuanhui.huang\Documents\MATLAB\CompuScope MATLAB SDK\Adv')
addpath('D:\Users\yuanhui.huang\Documents\MATLAB\CompuScope MATLAB SDK\CsMl')
addpath('D:\Users\yuanhui.huang\Documents\MATLAB\CompuScope MATLAB SDK\Main')

DAQ=gageInit;
disp('DAQ init');

pause(2);

    

    %% Ocean Optics    
if isUsing_OceanSpectra==1
    global spectrometerObj
    spectrometerObj = icdevice('OceanOptics_OmniDriver.mdd');
    try connect(spectrometerObj);
    catch ME
        display(['OceanOptics USB4000 ' ME.message]);
    end
%     disp(spectrometerObj);
    % set parameters
    Spectra_integrationTime=20e3; % µs
    % Spectrometer index to use (first spectrometer by default).
    spectrometerIndex = 0;
    % Channel index to use (first channel by default).
    channelIndex = 0;
    % Enable flag.#
    enable = 1;
%     % timeoutMilliseconds - if no trigger before timeout, getSpectrum gives
%     % all zeros
%     timeoutMilliseconds = 0; % default 0 - forever; 3in1 spectra uses 5 seconds (5e3) 

    % set parameter
    try
        % integration time for sensor.
        invoke(spectrometerObj, 'setIntegrationTime', spectrometerIndex, channelIndex, Spectra_integrationTime);
        % Enable correct for detector non-linearity.
        invoke(spectrometerObj, 'setCorrectForDetectorNonlinearity', spectrometerIndex, channelIndex, enable);
        % Enable correct for electrical dark.
        invoke(spectrometerObj, 'setCorrectForElectricalDark', spectrometerIndex, channelIndex, enable);
%         % set timeout to be 10 seconds (USB4000FL time in MILLISECONDS)
%         invoke(spectrometerObj, 'setTimeout', timeoutMilliseconds);
    catch ME
        display(['OceanOptics USB4000 ' ME.message]);
    end
else
% Not performing switching protein spectra measurement
    spectrometerObj  = 0;
end


% end

%% 
disp('############ qDOAS initilized. Wish you successful measurements! ############')