classdef alazarTech_control < handle
    properties
        system_ID;
        board_ID;
        Clock_Source;
        Sample_Rate;
        Clock_Edge;
        Channel_Read;
        Input_Range;
        Coupling;
        Impedance;
    end
    
    properties
        transferOffset;
        transferLength;
        recordsPerBuffer;
        recordsPerAcquisition;
        flag;
    end
    
    properties
        Trigger_OP;
        Trigger_Engine;
        Trigger_Source;
        Trigger_Slope;
        Trigger_Level;
        Trigger_Timeout;
        Trigger_Delay
        Aux_mode;
    end
    
    methods( Access = public, Static = true ) 
        function obj = Initialize_Para()
           obj.system_ID = 1;
           obj.board_ID = 1;
           obj.Clock = INTERNAL_CLOCK;
           obj.sample_rate = SAMPLE_RATE_200MSPS;
           obj.Clock_Edge = CLOCK_EDGE_RISING;
           obj.Channel_Read = CHANNEL_ALL;
           obj.Input_Range = INPUT_RANGE_PM_2_V;
           obj.Coupling = DC_COUPLING;
           obj.Impedance = IMPEDANCE_50_OHM;
           obj.Trigger_OP = TRIG_ENGINE_OP_J;
           obj.Trigger_Eingine = TRIG_ENGINE_J;
           obj.Trigger_Source = TRIG_CHAN_A;
           obj.Trigger_Slope = TRIGGER_SLOPE_POSITIVE;
           obj.Trigger_Level = 64;
           obj.Trigger_Timeout = 10e6;
           obj.Trigger_Delay = 0;
           obj.Aux_mode = AUX_OUT_TRIGGER;
         % obj.transferOffset = ;
         % obj.transferLength = ;
           obj.recordsPerAcquisition = 0x7FFFFFFF;
           obj.flags = ADMA_TRADITIONAL_MODE || ADMA_ENABLE_RECORD_HEADERS;
        end
        
        function boardHandle = Alazar_Init(obj)
            boardHandle = AlazarGetBoardBySystemID(obj.system_ID,obj.board_ID);
            boardName = AlazarGetBoardKind(boardHandle);
            disp('AlazarTech Card %s Connected\n',boardName);
        end
    end
    
    methods( Access = public, Static = true )
        %configure_board 1. timebase, 2. analog inputs, and 3. trigger system settings 
        function Set_Clock(obj,boardHandle)
            AlazarSetCaptureClock(boardHandle,obj.Clock_Source,obj.Sample_Rate,obj.Clock_Edge,0);
        end
        
        function Input_Control(obj,boardHandle)
            AlazarInputControl(boardHandle,obj.channel,obj.Coupling,obj.input_range,obj.impedance)
        end
        
        function Configure_Trigger(obj,boardHandle)
            AlazarSetTriggerOperation(obj,boardHandle,obj.Trigger_OP,obj.Trigger_Engine,obj.Trigger_source,...
                                      obj.Trigger_Slope,obj.Trigger_Level);
                                  
            AlazarSetTriggerTimeOut(boardHandle,obj.Trigger_Timeout);
            
            AlazarSetTriggerDelay(boardHandle,obj.Trigger_Delay);
            
            AlazarConfigureAuxIO(boardHandle,obj.Aux_Mode);
        end
        
        function Acquire_Data(obj,boardHandle)
            AlazarAbortAsyncRead(boardHanle);%stop the possible runing Acquisition, avoiding blue screen error
            AlazarBeforeAsyncRead(boardHandle,obj.Channel_Read,obj.transferOffset,...
                                  obj.transferLength,obj.recordsPerAcquisition,obj.flags);
            AlazarAsyncRead(obj,boardHandle);
            AlazarAbortAsyncRead(boardHanle);
        end 
        
        function Trasmit(obj,boardHandle)
            
        end
    end
end