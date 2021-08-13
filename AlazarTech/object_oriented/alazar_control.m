classdef alazar_control < handle
    properties
        % board configuration 
        system_ID;
        board_ID;
        clock;
        clock_edge;
        channelsPerBoard;
        sample_rate;
        samplesPerSec;
        channelMask; % transmit signal, here channel A 
        channelTrig;
        input_range_signal; % input range of the channel A
        input_range_trigger; % input range of the channel B
        coupling;
        impedance_signal;
        impedance_trigger;
    end
    
    
    properties
        % setting for trigger
        trigger_OP;
        trigger_engine_J;
        trigger_engine_K;
        trigger_source_1; % Channel B is for triggering
        trigger_slope;
        trigger_level_1;
        trigger_level_2;
        trigger_timeout;
        trigger_delay
        trigger_source_2;
        Aux_mode;
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
       bitsPerSample;
       updateInterval_sec;
       buffersCompleted;
    end
    
    methods 
        function obj = alazar_control()
           AlazarDefs
           alazarLoadLibrary()
           
           obj.system_ID = int32(1);
           obj.board_ID = int32(1);
           obj.channelsPerBoard = 2;
           obj.clock = INTERNAL_CLOCK;
           obj.clock_edge = CLOCK_EDGE_RISING;
           obj.sample_rate = SAMPLE_RATE_125MSPS;
           obj.samplesPerSec = 125000000.0; 
           obj.channelMask = CHANNEL_A;
           obj.channelTrig = CHANNEL_B; 
           obj.input_range_signal = INPUT_RANGE_PM_80_MV; % channel A range 
           obj.input_range_trigger = INPUT_RANGE_PM_4_V; % channel B range 
           obj.coupling = DC_COUPLING;
           obj.impedance_signal = IMPEDANCE_50_OHM;
           obj.impedance_trigger = IMPEDANCE_50_OHM;
           
           obj.trigger_OP = TRIG_ENGINE_OP_J;
           obj.trigger_engine_J = TRIG_ENGINE_J;
           obj.trigger_engine_K = TRIG_ENGINE_K;
           obj.trigger_source_1= TRIG_CHAN_B;
           obj.trigger_slope = TRIGGER_SLOPE_POSITIVE;
           obj.trigger_level_1 = 140.8;
           obj.trigger_level_2 = 128;%  376.5 mV as the trigger level, unit here is mV
           obj.trigger_timeout = 0;
           obj.trigger_delay = 0; %7.7 µs
           obj.trigger_source_2 = TRIG_DISABLE;% Engine J for channel B
            
           obj.preTriggerSamples = 3264;
           obj.postTriggerSamples = 32768 - obj.preTriggerSamples;  
           obj.recordsPerBuffer = 1;  % Specifiy the total number of buffers to capture
           obj.buffersPerAcquisition = 1;
           obj.recordsPerAcquisition = 0x7FFFFFFF; % streaming
           obj.channelsPerBoard = 2;
           obj.bufferCount = uint32(8);  % use 8 buffers for data acquisition
           obj.updateInterval_sec = 0.1;
           obj.buffersCompleted = 0;
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
        % Configure the board: 1. clock, 2. analog inputs, and 3. trigger mode and triggering system settings 
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
                                 obj.impedance_signal);
                             
        % Select channel A bandwidth limit as required
            AlazarSetBWLimit(boardHandle, ...
                             obj.channelMask, ...
                             0); 
        % Select channel A bandwidth limit as required
            AlazarSetBWLimit(boardHandle, ...
                             obj.channelMask, ...
                             0); % no bandwidt limit (full)                                                   

        % Select channel B input parameters as required.
            AlazarInputControlEx(boardHandle, ...
                                 obj.channelTrig, ...
                                 obj.coupling, ...
                                 obj.input_range_trigger, ...
                                 obj.impedance_trigger); 

        % Select channel B bandwidth limit as required
            AlazarSetBWLimit(boardHandle, ...
                             obj.channelTrig, ...
                             0); % no bandwidt limit (full)
                        
        % Select trigger inputs and levels as required
            AlazarSetTriggerOperation(boardHandle, ...
                                      obj.trigger_OP, ...
                                      obj.trigger_engine_J, ...
                                      obj.trigger_source_1, ...
                                      obj.trigger_slope, ...
                                      obj.trigger_level_1, ...
                                      obj.trigger_engine_K, ...
                                      obj.trigger_source_2, ...
                                      obj.trigger_slope, ...
                                      obj.trigger_level_2);


        % Set trigger delay as required.
            triggerDelay_sec = obj.trigger_delay; 
            triggerDelay_samples = uint32(floor(triggerDelay_sec * obj.samplesPerSec + 0.5));
            AlazarSetTriggerDelay(boardHandle,...
                                  triggerDelay_samples);

        % Set trigger timeout as required    
            AlazarSetTriggerTimeOut(boardHandle, ...
                                    obj.trigger_timeout); % timeout 0 means always ready for a trigger event
                           
        end
    
        function acquire_data(obj, boardHandle)            
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
            bytesPerSample = floor((double(obj.bitsPerSample) + 7) / double(8));
            samplesPerRecord = obj.preTriggerSamples + obj.postTriggerSamples; %record size, how many samples in a record(block)
            samplesPerBuffer = samplesPerRecord * obj.recordsPerBuffer * channelCount;
            bytesPerBuffer = bytesPerSample * samplesPerBuffer;

            % Create an array of DMA buffers
            buffers = cell(1, obj.bufferCount);
            for j = 1 : obj.bufferCount
                pbuffer = AlazarAllocBuffer(boardHandle, bytesPerBuffer);
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
            AlazarBeforeAsyncRead(boardHandle, obj.channelMask, -int32(obj.preTriggerSamples), samplesPerRecord, obj.recordsPerBuffer, obj.recordsPerAcquisition, obj.admaFlags);

            % Post the buffers to the board
            for bufferIndex = 1 : obj.bufferCount
                pbuffer = buffers{1, bufferIndex};
                AlazarPostAsyncBuffer(boardHandle, pbuffer, bytesPerBuffer);
            end

            % Update status
            if obj.buffersPerAcquisition == hex2dec('7FFFFFFF') % 7FFFFFFF stands for the continuous mode until stop
                fprintf('Capturing buffers until aborted...\n');
            else
                fprintf('Capturing %u buffers ...\n', obj.buffersPerAcquisition);
            end

            % Arm the board system to wait for triggers
            AlazarStartCapture(boardHandle);

            % Create a progress window to give a feedback of the status
            waitbarHandle = waitbar(0, ...
                                    'Captured 0 buffers', ...
                                    'Name','Capturing ...', ...
                                    'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
            setappdata(waitbarHandle, 'canceling', 0);

            % Wait for sufficient data to arrive to fill a buffer, process the buffer,
            % and repeat until the acquisition is complete
            startTickCount = tic;
            updateTickCount = tic;
            captureDone = false;
   

            while ~captureDone
                try
                    bufferIndex = mod(obj.buffersCompleted, obj.bufferCount) + 1;
                    pbuffer = buffers{1, bufferIndex};

                    % Wait for the first available buffer to be filled by the board
                    AlazarWaitAsyncBufferComplete(boardHandle, pbuffer, 5000);     

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
                            fprintf('Error: Write buffer %u failed\n', obj.buffersCompleted);
                        end
                    end

                    % Display the buffer on screen
                    if obj.drawData 
                       plot(pbuffer.Value,'LineWidth',3);
                       xlim([3000 5000]);
                       xlabel('Position From Sample to Transducer','FontSize',12,'FontWeight','bold','Color','r');
                       ylabel('Signal Intensity','FontSize',12,'FontWeight','bold','Color','b');
                    end

                    % Make the buffer available to be filled again by the board
                    AlazarPostAsyncBuffer(boardHandle, pbuffer, bytesPerBuffer);

                    % Update progress
                    obj.buffersCompleted = obj.buffersCompleted + 1;
                    if obj.buffersCompleted >= obj.buffersPerAcquisition
                        captureDone = true;
                    elseif toc(updateTickCount) > obj.updateInterval_sec
                        updateTickCount = tic;

                        % Update waitbar progress
                        waitbar(double(obj.buffersCompleted) / double(obj.buffersPerAcquisition), ...
                                waitbarHandle, ...
                                sprintf('Completed %u buffers', obj.buffersCompleted));

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
            if obj.buffersCompleted > 0
                bytesTransferred = double(obj.buffersCompleted) * double(bytesPerBuffer);
                recordsTransferred = obj.recordsPerBuffer * obj.buffersCompleted;

                if transferTime_sec > 0
                    buffersPerSec = obj.buffersCompleted / transferTime_sec;
                    bytesPerSec = bytesTransferred / transferTime_sec;
                    recordsPerSec = recordsTransferred / transferTime_sec;
                else
                    buffersPerSec = 0;
                    bytesPerSec = 0;
                    recordsPerSec = 0.;
                end

                fprintf('Captured %u buffers in %g sec (%g buffers per sec)\n', obj.buffersCompleted, transferTime_sec, buffersPerSec);
                fprintf('Captured %u records (%.4g records per sec)\n', recordsTransferred, recordsPerSec);
                fprintf('Transferred %u bytes (%.4g bytes per sec)\n', bytesTransferred, bytesPerSec);
            end
        end
    end
end