classdef alazar_control < handle
    properties
        % board configuration setting
        system_ID;
        board_ID;
        clock;
        clock_edge;
        channelsPerBoard;
        sample_rate;
        samplesPerSec;
        channelMask; % transmit signal, connected to channel A 
        input_range_triger; % input range of the channel A/1
        input_range_signal; % input range of the channel B/2
        coupling;
        impedance;
        
    end
    
    properties
        % setting for the data acquisition
        preTriggerSamples;
        postTriggerSamples;
        recordsPerBuffer;
        recordsPerAcquisition; %0x7FFFFFFF is streaming mode
        buffersPerAcquisition; 
        bufferCount;
        admaFlags;
        saveData;
        drawData;
    end
    
    properties
        Trigger_OP;
        Trigger_Engine_1;
        Trigger_Engine_2;
        Triger_channel; % Channel B is for triggering
        Trigger_Slope;
        Trigger_Level;
        Trigger_Timeout;
        Trigger_Delay
        Trigger_Disable
        Aux_mode;
    end
    
    methods 
        function obj = alazar_control()
           AlazarDefs
           alazarLoadLibrary();
           obj.system_ID = int32(1);
           obj.board_ID = int32(1);
           obj.channelsPerBoard = 2;
           obj.clock = INTERNAL_CLOCK;
           obj.sample_rate = SAMPLE_RATE_125MSPS;
           obj.samplesPerSec = 125000000.0;
           obj.clock_edge = CLOCK_EDGE_RISING;
           obj.channelMask = CHANNEL_A;
           obj.input_range_triger = INPUT_RANGE_PM_4_V; % range +- 4V
           obj.input_range_signal = INPUT_RANGE_PM_80_MV; % signal range +-80mV
           obj.coupling = DC_COUPLING;
           obj.impedance = IMPEDANCE_50_OHM; 
           obj.Trigger_OP = TRIG_ENGINE_OP_J;
           obj.Trigger_Engine_1 = TRIG_ENGINE_J;
           obj.Trigger_Engine_2 = TRIG_ENGINE_K;
           obj.Trigger_Disable = TRIG_DISABLE;% Engine J for channel B
           obj.Triger_channel = TRIG_CHAN_B;
           obj.Trigger_Slope = TRIGGER_SLOPE_POSITIVE; % Rising slope 
           obj.Trigger_Level = 10; %  10% or 376.5 mV as the trigger level
           obj.Trigger_Timeout = 0;
           obj.Trigger_Delay = 0; %7.7 µs
           obj.preTriggerSamples = 3264;
           obj.postTriggerSamples = 32768 - obj.preTriggerSamples;
           %obj.Aux_mode = AUX_OUT_TRIGGER;
           obj.recordsPerBuffer = 1;  % Specifiy the total number of buffers to capture
           obj.buffersPerAcquisition = 10;
           obj.recordsPerAcquisition = 0x7FFFFFFF;
           obj.channelsPerBoard = 2;
           obj.bufferCount = uint32(4);  % the number of DMA buffers to allocate. greater than 2 for DMA
           obj.saveData = false;
           obj.drawData = false;
           obj.admaFlags = ADMA_EXTERNAL_STARTCAPTURE + ADMA_TRADITIONAL_MODE;
        end
        
        function boardHandle = alazar_init(obj)
            AlazarDefs % Call mfile with library definitions
            alazarLoadLibrary() % Load driver library
            boardHandle = AlazarGetBoardBySystemID(obj.system_ID,obj.board_ID); %creat a handle for the board
            boardName = AlazarGetBoardKind(boardHandle);
            info = sprintf('AlazarTech Card %s init\n', boardName);
            disp(info);
        end
    end
    
    methods
        % Configure the board: 1. timebase, 2. analog inputs, and 3. trigger system settings 
        function configureBoard(obj, boardHandle)
            AlazarSetCaptureClock(boardHandle, ...
                                  obj.clock, ...
                                  obj.sample_rate, ...
                                  obj.clock_edge, ...
                                  0);
                              
        % Select channel A input parameters as required.
            AlazarInputControlEx(boardHandle, ...
                                 obj.channelMask, ...
                                 obj.coupling, ...
                                 obj.input_range_signal, ...
                                 obj.impedance);
                          
        % Select channel A bandwidth limit as required
            AlazarSetBWLimit(boardHandle, ...
                             obj.channelMask, ...
                             0); % no bandwidt limit (full)
                         
        % Select channel B input parameters as required.
            AlazarInputControlEx(boardHandle, ...
                                 obj.Triger_channel, ...
                                 obj.coupling, ...
                                 obj.input_range_triger, ...
                                 obj.impedance); 
                          
        % Select channel B bandwidth limit as required
            AlazarSetBWLimit(boardHandle, ...
                             obj.Triger_channel, ...
                             0); % no bandwidt limit (full)
                        
        % Select trigger inputs and levels as required
            AlazarSetTriggerOperation(boardHandle, ...
                                      obj.Trigger_OP, ...
                                      obj.Trigger_Engine_1, ...
                                      obj.Triger_channel, ...
                                      obj.Trigger_Slope, ...
                                      obj.Trigger_Level);


        % Set trigger delay as required.
            triggerDelay_sec = obj.Trigger_Delay;  %7.7 µs
            triggerDelay_samples = uint32(floor(triggerDelay_sec * obj.samplesPerSec + 0.5));
            AlazarSetTriggerDelay(obj, ...
                                  boardHandle,...
                                  triggerDelay_samples);

        % Set trigger timeout as required    
            AlazarSetTriggerTimeOut(obj, ...
                                    boardHandle, ...
                                    obj.Trigger_Timeout); % timeout 0 means always ready for a trigger event

        end
    
        function Acquire_Data(obj, boardHandle)
            AlazarDefs        
            % Calculate the number of enabled channels from the channel mask
            channelCount = 0;  
            for channel = 0 : obj.channelsPerBoard - 1
                channelId = 2^channel;
                if bitand(channelId, obj.channelMask)
                    channelCount = channelCount + 1;
                end
            end

            if (channelCount < 1) || (channelCount > obj.channelsPerBoard)
                fprintf('Error: Invalid channel mask %08X\n', obj.channelMask);
                return
            end            
            
            % Get the sample and memory size
            [~, obj.bitsPerSample] = AlazarGetChannelInfo(boardHandle);

            % Calculate the size of each buffer in bytes
            obj.bytesPerSample = floor((double(obj.bitsPerSample) + 7) / double(8));
            obj.samplesPerRecord = obj.preTriggerSamples + obj.postTriggerSamples;
            obj.samplesPerBuffer = obj.samplesPerRecord * obj.recordsPerBuffer * channelCount;
            obj.bytesPerBuffer = obj.bytesPerSample * obj.samplesPerBuffer;

            % Create an array of DMA buffers
            buffers = cell(1, obj.bufferCount);
            for j = 1 : obj.bufferCount
                pbuffer = AlazarAllocBuffer(boardHandle, obj.bytesPerBuffer);
                buffers(1, j) = { pbuffer };
            end

            % Create a data file if required
            fid = -1;
            if obj.saveData
                fid = fopen('data.bin', 'w');
                if fid == -1
                    fprintf('Error: Unable to create data file\n');
                end
            end
            % Set the record size
            AlazarSetRecordSize(boardHandle, obj.preTriggerSamples, obj.postTriggerSamples);

            % Configure the board to make an AutoDMA acquisition
            obj.recordsPerAcquisition = obj.recordsPerBuffer * obj.buffersPerAcquisition;
            AlazarBeforeAsyncRead(boardHandle, obj.channelMask, -int32(obj.preTriggerSamples), obj.samplesPerRecord, obj.recordsPerBuffer, obj.recordsPerAcquisition, obj.admaFlags);

            % Post the buffers to the board
            for bufferIndex = 1 : obj.bufferCount
                pbuffer = buffers{1, bufferIndex};
                AlazarPostAsyncBuffer(boardHandle, pbuffer, obj.bytesPerBuffer);
            end

            % Update status
            if obj.buffersPerAcquisition == hex2dec('7FFFFFFF')
                fprintf('Capturing buffers until aborted...\n');
            else
                fprintf('Capturing %u buffers ...\n', obj.buffersPerAcquisition);
            end

            % Arm the board system to wait for triggers
            AlazarStartCapture(boardHandle);

            % Create a progress window
            waitbarHandle = waitbar(0, ...
                                    'Captured 0 buffers', ...
                                    'Name','Capturing ...', ...
                                    'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
            setappdata(waitbarHandle, 'canceling', 0);

            % Wait for sufficient data to arrive to fill a buffer, process the buffer,
            % and repeat until the acquisition is complete
            startTickCount = tic;
            updateTickCount = tic;
            updateInterval_sec = 0.1;
            buffersCompleted = 0;
            captureDone = false;

            while ~captureDone
                try
                    bufferIndex = mod(buffersCompleted, obj.bufferCount) + 1;
                    pbuffer = buffers{1, bufferIndex};

                    % Wait for the first available buffer to be filled by the board
                    AlazarWaitAsyncBufferComplete(boardHandle, pbuffer, 5000);
                    % TODO: Process sample data in this buffer.
                    %
                    % NOTE:
                    %
                    % While you are processing this buffer, the board is already
                    % filling the next available buffer(s).
                    %
                    % You MUST finish processing this buffer and post it back to the
                    % board before the board fills all of its available DMA buffers
                    % and on-board memory.
                    %
                    % Records are arranged in the buffer as follows: R0A, R0B, ..., R1A, R1B, ...
                    % with RXY the record number X of channel Y.
                    %
                    % A 14-bit sample code is stored in the most significant bits of
                    % in each 16-bit sample value.
                    %
                    % Sample codes are unsigned by default. As a result:
                    % - a sample code of 0x0000 represents a negative full scale input signal.
                    % - a sample code of 0x8000 represents a ~0V signal.
                    % - a sample code of 0xFFFF represents a positive full scale input signal.

                    if obj.bytesPerSample == 1
                        setdatatype(pbuffer, 'uint8Ptr', 1, obj.samplesPerBuffer);
                    else
                        setdatatype(pbuffer, 'uint16Ptr', 1, obj.samplesPerBuffer);
                    end

                    % Save the buffer to file
                    if fid ~= -1
                        if bytesPerSample == 1
                            samplesWritten = fwrite(fid, pbuffer.Value, 'uint8');
                        else
                            samplesWritten = fwrite(fid, pbuffer.Value, 'uint16');
                        end
                        if samplesWritten ~= samplesPerBuffer
                            fprintf('Error: Write buffer %u failed\n', buffersCompleted);
                        end
                    end

                    % Display the buffer on screen
                    if obj.drawData
                        plot(pbuffer.Value);
                    end

                    % Make the buffer available to be filled again by the board
                    AlazarPostAsyncBuffer(boardHandle, pbuffer, obj.bytesPerBuffer);

                    % Update progress
                    buffersCompleted = buffersCompleted + 1;
                    if buffersCompleted >= obj.buffersPerAcquisition
                        captureDone = true;
                    elseif toc(updateTickCount) > updateInterval_sec
                        updateTickCount = tic;

                        % Update waitbar progress
                        waitbar(double(buffersCompleted) / double(obj.buffersPerAcquisition), ...
                                waitbarHandle, ...
                                sprintf('Completed %u buffers', buffersCompleted));

                        % Check if waitbar cancel button was pressed
                        if getappdata(waitbarHandle,'canceling')
                            break
                        end
                    end
                catch ME
                    fprintf("%s:%s\n", ME.identifier, ME.message);
                    captureDone = true;
                end
            end % while ~captureDone

            % Save the transfer time
            transferTime_sec = toc(startTickCount);

            % Close progress window
            delete(waitbarHandle);

            % Abort the acquisition
            AlazarAbortAsyncRead(boardHandle);

            % Close the data file
            if fid ~= -1
                fclose(fid);
            end

            % Release the buffers
            for bufferIndex = 1:obj.bufferCount
                pbuffer = buffers{1, bufferIndex};
                AlazarFreeBuffer(boardHandle, pbuffer);
                clear pbuffer;
            end

            % Display results
            if buffersCompleted > 0
                bytesTransferred = double(buffersCompleted) * double(bytesPerBuffer);
                recordsTransferred = obj.recordsPerBuffer * buffersCompleted;

                if transferTime_sec > 0
                    buffersPerSec = buffersCompleted / transferTime_sec;
                    bytesPerSec = bytesTransferred / transferTime_sec;
                    recordsPerSec = recordsTransferred / transferTime_sec;
                else
                    buffersPerSec = 0;
                    bytesPerSec = 0;
                    recordsPerSec = 0.;
                end

                fprintf('Captured %u buffers in %g sec (%g buffers per sec)\n', buffersCompleted, transferTime_sec, buffersPerSec);
                fprintf('Captured %u records (%.4g records per sec)\n', recordsTransferred, recordsPerSec);
                fprintf('Transferred %u bytes (%.4g bytes per sec)\n', bytesTransferred, bytesPerSec);
            end
        end
    end
end