clear;
global boardHandle
% Add path to AlazarTech mfiles
addpath('C:\AlazarTech\ATS-SDK\7.5.0\Samples_MATLAB\Include')
Daq = alazar_control();
boardHandle = Daq.alazar_init();
Daq.configureBoard(boardHandle);
Daq.drawData = true;
Daq.saveData = true;
Daq.acquire_data(boardHandle);
