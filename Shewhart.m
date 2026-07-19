

function [puntos_entrada_3s, puntos_entrada_2s, tasa, media, sigma_t] = Shewhart(data)

puntos_entrada_3s = [];
puntos_entrada_2s = [];


tasa = diff(data) ./ data(1:end-1);
tasa=tasa*100;
media=mean(tasa);
%sigma=std(tasa);
%calculos de la sigma de tippet:
RM=abs(diff(tasa));
sigma_t=mean(RM)/1.128;
dias=length(data);
%plotGraficoShewhart_tasa(tasa,media,sigma_t)

puntos_entrada_3s = find(tasa <= (media - 3 * sigma_t)) + 1;
puntos_entrada_2s = find(tasa <= (media - 2 * sigma_t)) + 1; 
end

