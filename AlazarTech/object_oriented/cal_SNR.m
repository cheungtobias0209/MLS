% calculate SNR
function SNR = cal_SNR()
    fid = fopen('data.bin');
    ret = fread(fid); 
    ns = linspace(1,1,65536);
    SNR = snr(ret./(ns'));
end
