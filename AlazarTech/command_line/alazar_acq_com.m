saveData = true;
drawData = true;
preTriggerSamples = 3264;
postTriggerSamples = 32768 - preTriggerSamples;
recordsPerBuffer = 1;  % might be used for averaging
buffersPerAcquisition = 1; 
channelMask = CHANNEL_A;
bufferCount = uint32(8);

admaFlags = ADMA_EXTERNAL_STARTCAPTURE + ADMA_TRADITIONAL_MODE; % Select AutoDMA flags as required


% Calculate the number of enabled channels from the channel mask
channelCount = 0;
channelsPerBoard = 2;
for channel = 0:channelsPerBoard - 1
    channelId = 2^channel;
    if bitand(channelId, channelMask)
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
samplesPerRecord = preTriggerSamples + postTriggerSamples;
samplesPerBuffer = samplesPerRecord * recordsPerBuffer * channelCount;
bytesPerBuffer = bytesPerSample * samplesPerBuffer;

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
           plot(pbuffer.Value,'LineWidth',3);
           xlim([3000 5000]);
           xlabel('Position From Sample to Transducer','FontSize',12,'FontWeight','bold','Color','r');
           ylabel('Signal Intensity','FontSize',12,'FontWeight','bold','Color','b');
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