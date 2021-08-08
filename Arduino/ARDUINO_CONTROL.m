%---------------------------------------------------------------------------
%
% This code is modified based on the old version from yuanhui's init_qOAS4
% by ge zhang. It is used to generate an object that control the Arduino Uno board.
% The whole procedure inluces initializing the board to create a board
% handle(if connected to a servo motor, also initializing a servo handle),
% selecting the range of light, choosing the proper filter. Also the
% Arduino Uno board can be uesed to control the opening and closing of the
% Oceanid or Thorlabs shutter.
%
%
%%
classdef ARDUINO_CONTROL < handle
    
    properties
        % this properity is about the adopted light range and filter type,
        % it can be a visible light(VIS) or near infrared(NIR). The filter
        % can be a longpass(LP) or shortpass(SP) filter.
       
        light_range;
        filter_mode;
    end

    properties
        % this properties define the position of the filter while according
        % to the corresponding filter type.
        posOfNIR = 0.72; % position of the NIR 
        posOfVIS = 0.13;
        posOfLP = 0;     % position of the Longpass for the filter wheel.
        posOfSP = 0.66;
        posOfBLK = 0.33; % position of blocking for the filter wheel
    end
    
    properties
        pin; % the pin on Uno board that used for data communication when 
        pin0;% performing the closing or opening of shutter
        
    end
    
    methods
        function obj = ARDUINO_CONTROL()
            obj.light_range = 'VIS'; %default : visible light
            obj.filter_mode = 'BLK'; %default : block light from getting through
        end
       
        function [s_LPSP,s_VISNIR,filter_handle] = filter_arduino_connect(obj)
            global filter_handle
            global s_LPSP
            global s_VISNIR
            
            try
                filter_handle = arduino('com4', 'uno', 'Libraries', 'Servo'); %creat a filter handle for next use. Port name subjects to change.
            catch ME
                display(['filter_arduino' ME.message]);
            end
            pause(1);
            s_LPSP = servo(filter_handle, 'D4', 'MinPulseDuration', 371*10^-6, 'MaxPulseDuration',1125*10^-6); %servo handle for filter
            s_VISNIR = servo(filter_handle, 'D8', 'MinPulseDuration', 375*10^-6, 'MaxPulseDuration',1125*10^-6); %servo handle for light range
            disp('filter arduino connected.')
            pause(2);
        end
        
        function shutter_handle = shutter_arduino_connect(obj)
            global shutter_handle
            
            try
               shutter_handle = arduino('COM3','Uno'); %creat a shutter handle for next use. Port name subjects to change.
            catch ME
                display(['shutter_handle ' ME.message]);
            end
            disp('shutter arduino connected.')
        end
        
        function VIS_NIR_Select(obj, Position, s_VISNIR) 
            global s_VISNIR
            current_position = readPosition(s_VISNIR);
            switch Position
                case {'NIR','nir'}
                    if current_position ~= obj.posOfNIR
                        writePosition(s_VISNIR, obj.posOfNIR);
                    end
                otherwise
                    if current_position ~=  obj.posOfVIS
                        writePosition(s_VISNIR, obj.posOfVIS);
                    end
            end
        end
        
        function LPSP_FilterSelect(obj, Position, s_LPSP)
            global s_LPSP
            current_position = readPosition(s_LPSP);
            switch Position
                case {'LP';'lp';'NIR';'nir'}
                    if current_position ~=  obj.posOfLP
                        writePosition(s_LPSP, obj.posOfLP);
                    end
                case {'Block';'block';'BLK';'blk'}
                    if current_position ~=  obj.posOfBLK
                        writePosition(s_LPSP, obj.posOfBLK);
                    end
                case {'SP';'sp';'VIS';'vis'}
                    if current_position ~=  obj.posOfSP
                        writePosition(s_LPSP, obj.posOfSP);
                    end
                otherwise
                    writePosition(s_LPSP, 1);
            end
        end
        
        function servo_init(s_VISNIR, s_LPSP)
            VIS_NIR_Select(s_VISNIR , 'VIS');
            LPSP_FilterSelect (s_LPSP, 'VIS');
            LPSP_FilterSelect (s_LPSP, 'BLK');
            disp('FILTER ARDUINO init ');
            pause(2);
        end
        
        function close_shutter(obj, Shutter_Name, shutter_handle)
             switch Shutter_Name
                 case 'Thorlabs_LaserShutter'
                     obj.pin='D8';
                     obj.pin0='D9';
                 case 'Ocean_LampShutter'
                     obj.pin='D7';
                     obj.pin0='D6';
             end
             state = 0;  % state for closed shutter
             state0 = 0;
             writeDigitalPin(shutter_handle, obj.pin0, state0);
             writeDigitalPin(shutter_handle, obj.pin, state);
        end
        
        function open_shutter(obj, Shutter_Name, shutter_handle)
            switch Shutter_Name
                 case 'Thorlabs_LaserShutter'
                     obj.pin='D8';
                     obj.pin0='D9';
                 case 'Ocean_LampShutter'
                     obj.pin='D7';
                     obj.pin0='D6';
             end
             state = 1;  % state for open shutter
             state0 = 0;
             writeDigitalPin(shutter_handle, obj.pin0, state0);
             writeDigitalPin(shutter_handle, obj.pin, state);
        end
        
        
    end
end