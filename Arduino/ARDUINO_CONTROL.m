classdef ARDUINO_CONTROL < handle
    
    properties 
        light_range;
        filter_mode;
    end
    
    properties
        posOfNIR = 0.72;
        posOfVIS = 0.13;
        posOfLP = 0;
        posOfSP = 0.66;
        posOfBLK = 0.33;
    end
    
    properties
        s_VISNIR;
        s_LPSP;
        shutter_handle
        filter_handle
        pin;
        pin0;
    end
    
    methods ( Access = public, Static = true ) 
        function obj = ARDUINO_CONTROL()
            obj.light_range = 'VIS';
            obj.filter_mode = 'BLK';
        end
       
        function filter_arduino_connect(obj) 
            try
                obj.filter_handle = arduino('com4', 'uno', 'Libraries', 'Servo');
            catch ME
                display(['obj.filter_arduino' ME.message]);
            end
            obj.s_LPSP = servo(obj.filter_handle, 'D4', 'MinPulseDuration', 371*10^-6, 'MaxPulseDuration',1125*10^-6);
            obj.s_VISNIR = servo(obj.filter_handle, 'D8', 'MinPulseDuration', 375*10^-6, 'MaxPulseDuration',1125*10^-6);
            disp('filter arduino connected')
        end
        
        function shutter_arduino_connect(obj)
            try
               obj.shutter_handle = arduino('COM3','Uno');
            catch ME
                display(['obj.shutter_handle ' ME.message]);
            end
            disp('shutter arduino connected')
        end
        
        function VIS_NIR_Select(obj, Position)
            current_position = readPosition(obj.s_VISNIR);
            switch Position
                case {'NIR','nir'}
                    if current_position ~= obj.posOfNIR
                        writePosition(obj.s_VISNIR, obj.posOfNIR);
                    end
                otherwise
                    if current_position ~=  obj.posOfVIR
                        writePosition(obj.s_VISNIR, obj.posOfVIR);
                    end
            end
        end
        
        function LPSP_FilterSelect(obj, Position)
            current_position = readPosition(obj.s_LPSP);
            switch Position
                case {'LP';'lp';'NIR';'nir'}
                    if current_position ~=  obj.posOfLP
                        writePosition(obj.s_LPSP, obj.posOfLP);
                    end
                case {'Block';'block';'BLK';'blk'}
                    if current_position ~=  obj.posOfBLK
                        writePosition(obj.s_LPSP, obj.posOfBLK);
                    end
                case {'SP';'sp';'VIS';'vis'}
                    if current_position ~=  obj.posOfSP
                        writePosition(obj.s_LPSP, obj.posOfSP);
                    end
                otherwise
                    writePosition(obj.s_LPSP, 1);
            end
        end
        
        function Close_Shutter(obj, Shutter_Name)
             switch Shutter_Name
                 case 'Thorlabs_LaserShutter'
                     obj.pin='D8';
                     obj.pin0='D9';
                 case 'Ocean_LampShutter'
                     obj.pin='D7';
                     obj.pin0='D6';
             end
             state = 0;
             state0 = 0;
             writeDigitalPin(obj.shutter_handle, obj.pin0, state0);
             writeDigitalPin(obj.shutter_handle, obj.pin, state);
        end
        
        function Open_Shutter(obj, Shutter_Name)
            switch Shutter_Name
                 case 'Thorlabs_LaserShutter'
                     obj.pin='D8';
                     obj.pin0='D9';
                 case 'Ocean_LampShutter'
                     obj.pin='D7';
                     obj.pin0='D6';
             end
             state = 1;
             state0 = 0;
             writeDigitalPin(obj.shutter_handle, obj.pin0, state0);
             writeDigitalPin(obj.shutter_handle, obj.pin, state);
        end
    end
end