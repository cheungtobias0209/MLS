classdef alazar_control < handle
    properties
        system_ID;
        board_ID;
        clock;
        sample_rate;
        samplesPerSec
        Clock_Edge;
        channelMask; % Channel A transfer the acquried data
        input_range_triger;
        input_range_signal;%
        coupling;
        impedance;
    end
    
    properties
        recordsPerBuffer;
        recordsPerAcquisition;
        flag;
    end
    
    properties
        Trigger_OP;
        Trigger_Engine;
        Triger_channel; % Channel B is for triggering
        Trigger_Slope;
        Trigger_Level;
        Trigger_Timeout;
        Trigger_Delay
        Aux_mode;
    end
    
    properties
        preTriggerSamples;
        postTriggerSamples;
        recordsPerBuffer;
        buffersPerAcquisition;
        saveData;
        drawData;
        channelsPerBoard;
    end
    methods 
        function obj = alazar_control()
           obj.system_ID = int32(1);
           obj.board_ID = int32(1);
           obj.channelsPerBoard = 2;
           obj.clock = INTERNAL_CLOCK;
           obj.sample_rate = SAMPLE_RATE_125MSPS;
           obj.samplesPerSec = 32768;
           obj.Clock_Edge = CLOCK_EDGE_RISING;
           obj.channelMask = CHANNEL_A;
           obj.input_range_triger = INPUT_RANGE_PM_4_V; % range +- 4V
           obj.input_range_signal = INPUT_RANGE_PM_80_MV; % signal range +-80mV
           obj.coupling = DC_COUPLING;
           obj.impedance = IMPEDANCE_50_OHM; 
           obj.Trigger_OP = TRIG_ENGINE_OP_J;
           obj.Trigger_Engine = TRIG_ENGINE_J; % Engine J for channel B
           obj.Triger_channel = TRIG_CHAN_B;
           obj.Trigger_Slope = TRIGGER_SLOPE_POSITIVE; % Rising slope 
           obj.Trigger_Level = 10; %  10% or 376.5 mV as the trigger level
           obj.Trigger_Timeout = 0;
           obj.Trigger_Delay = 0; %7.7 µs
           obj.preTriggerSamples = 3264; 
           obj.postTriggerSamples = obj.samplesPerSec - obj.preTriggerSamples;
           %obj.Aux_mode = AUX_OUT_TRIGGER;
           %recordsPerBuffer = 1;
           %obj.recordsPerAcquisition = 0x7FFFFFFF;
           obj.flags = ADMA_TRADITIONAL_MODE || ADMA_ENABLE_RECORD_HEADERS;
        end
        
        function boardHandle = alazar_init(obj)
            AlazarDefs % Call mfile with library definitions
            alazarLoadLibrary() % Load driver library
            boardHandle = AlazarGetBoardBySystemID(obj.system_ID,obj.board_ID); %creat a handle for the board
            boardName = AlazarGetBoardKind(boardHandle);
            disp('AlazarTech Card %s init\n',boardName);
        end
    end
    
    methods
        % Configure the board: 1. timebase, 2. analog inputs, and 3. trigger system settings 
        function configureBoard(obj, boardHandle)
            AlazarSetCaptureClock(obj, ...
                                  boardHandle, ...
                                  obj.Clock_Source, ...
                                  obj.Sample_Rate, ...
                                  obj.Clock_Edge, ...
                                  0);
                              
        % Select channel A input parameters as required.
            AlazarInputControlEx(obj, ...
                                 boardHandle, ...
                                 obj.channelMask, ...
                                 obj.coupling, ...
                                 obj.input_range_signal, ...
                                 obj.impedance);
                          
        % Select channel A bandwidth limit as required
            AlazarSetBWLimit(obj, ...
                             boardHandle, ...
                             obj.channelMask, ...
                             0); % no bandwidt limit (full)
                         
        % Select channel B input parameters as required.
            AlazarInputControlEx(obj, ...
                                 boardHandle, ...
                                 obj.channelTriger, ...
                                 obj.coupling, ...
                                 obj.input_range_triger, ...
                                 obj.impedance); 
                          
        % Select channel B bandwidth limit as required
            AlazarSetBWLimit(obj, ...
                             boardHandle, ...
                             obj.Trigger_Source, ...
                             0); % no bandwidt limit (full)
                        
        % Select trigger inputs and levels as required
            AlazarSetTriggerOperation(obj, ...
                                      boardHandle, ...
                                      obj.Trigger_OP, ...
                                      obj.Trigger_Engine, ...
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
            for channel = 0:channelsPerBoard - 1
                channelId = 2^channel;
                if bitand(channelId, obj.channelMask)
                    channelCount = channelCount + 1;
                end
            end

            if (channelCount < 1) || (channelCount > channelsPerBoard)
                fprintf('Error: Invalid channel mask %08X\n', channelMask);
                return
            end

            % Get the sample and memory size
            [~, bitsPerSample] = AlazarGetChannelInfo(boardHandle);

            % Calculate the size of each buffer in bytes
            bytesPerSample = floor((double(bitsPerSample) + 7) / double(8));
            samplesPerRecord = obj.preTriggerSamples + obj.postTriggerSamples;
            samplesPerBuffer = samplesPerRecord * obj.recordsPerBuffer * channelCount;
            bytesPerBuffer = bytesPerSample * samplesPerBuffer;

            % Select the number of DMA buffers to allocate.
            % The number of DMA buffers must be greater than 2 to allow a board to DMA into
            % one buffer while, at the same time, your application processes another buffer.
            bufferCount = uint32(4);

            % Create an array of DMA buffers
            buffers = cell(1, bufferCount);
            for j = 1 : bufferCount
                pbuffer = AlazarAllocBuffer(boardHandle, bytesPerBuffer);
                buffers(1, j) = { pbuffer };
            end

            % Create a data file if required
            fid = -1;
            if saveData
                fid = fopen('data.bin', 'w');
                if fid == -1
                    fprintf('Error: Unable to create data file\n');
                end
            end
            % Set the record size
            AlazarSetRecordSize(boardHandle, preTriggerSamples, postTriggerSamples);

            % TODO: Select AutoDMA flags as required
            admaFlags = ADMA_EXTERNAL_STARTCAPTURE + ADMA_TRADITIONAL_MODE;

            % Configure the board to make an AutoDMA acquisition
            recordsPerAcquisition = recordsPerBuffer * buffersPerAcquisition;
            AlazarBeforeAsyncRead(boardHandle, channelMask, -int32(preTriggerSamples), samplesPerRecord, recordsPerBuffer, recordsPerAcquisition, admaFlags);

            % Post the buffers to the board
            for bufferIndex = 1 : bufferCount
                pbuffer = buffers{1, bufferIndex};
                AlazarPostAsyncBuffer(boardHandle, pbuffer, bytesPerBuffer);
            end

            % Update status
            if buffersPerAcquisition == hex2dec('7FFFFFFF')
                fprintf('Capturing buffers until aborted...\n');
            else
                fprintf('Capturing %u buffers ...\n', buffersPerAcquisition);
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
                    bufferIndex = mod(buffersCompleted, bufferCount) + 1;
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

                    if bytesPerSample == 1
                        setdatatype(pbuffer, 'uint8Ptr', 1, samplesPerBuffer);
                    else
                        setdatatype(pbuffer, 'uint16Ptr', 1, samplesPerBuffer);
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
                    if drawData
                        plot(pbuffer.Value);
                    end

                    % Make the buffer available to be filled again by the board
                    AlazarPostAsyncBuffer(boardHandle, pbuffer, bytesPerBuffer);

                    % Update progress
                    buffersCompleted = buffersCompleted + 1;
                    if buffersCompleted >= buffersPerAcquisition
                        captureDone = true;
                    elseif toc(updateTickCount) > updateInterval_sec
                        updateTickCount = tic;

                        % Update waitbar progress
                        waitbar(double(buffersCompleted) / double(buffersPerAcquisition), ...
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
            for bufferIndex = 1:bufferCount
                pbuffer = buffers{1, bufferIndex};
                AlazarFreeBuffer(boardHandle, pbuffer);
                clear pbuffer;
            end

            % Display results
            if buffersCompleted > 0
                bytesTransferred = double(buffersCompleted) * double(bytesPerBuffer);
                recordsTransferred = recordsPerBuffer * buffersCompleted;

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