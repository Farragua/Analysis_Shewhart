% function [msg] = sendNotification(asset,data, entradas_2smm, entradas_2mmvix,vix,mm200);
% 
% today=length(data);
% 
% if entradas_2smm(end) == today 
% msg = asset+ ":---2smm---:P="+data(today)+":MA200="+mm200+":VIX="+vix(end)+":"+date;
% 
% elseif entradas_2mmvix(end) == today 
% msg = asset+ ":-2smm+VIX-:P="+data(today)+":MA200="+mm200+":VIX="+vix(end)+":"+date;
% 
% else
%     msg = asset+ ":-NoSignal-:P="+data(today)+":MA200="+mm200+":VIX="+vix(end)+":"+date;
% 
% end


function [msg] = sendNotification(asset, data, entradas_2smm, entradas_2mmvix, mm200)
    today_idx = length(data);
    precio_actual = data(today_idx);

    % Detectar si hoy hay señal de forma segura
    es_2smm = (~isempty(entradas_2smm) && entradas_2smm(end) == today_idx);
    es_2mmvix = (~isempty(entradas_2mmvix) && entradas_2mmvix(end) == today_idx);

    % Construir el mensaje en inglés sin VIX ni fecha
    if es_2smm
        msg = sprintf('🟢 [%s] 🚨 BUY SIGNAL! (Strategy: 2smm)\n   ↳ Price: $%.2f  |  MA200: $%.2f\n', ...
            upper(asset), precio_actual, mm200);
            
    elseif es_2mmvix
        msg = sprintf('🔥 [%s] 🚨 AGGRESSIVE BUY! (Strategy: 2smm + VIX)\n   ↳ Price: $%.2f  |  MA200: $%.2f\n', ...
            upper(asset), precio_actual, mm200);
            
    else
        msg = sprintf('⚪ [%s] No signal (Price: $%.2f  |  MA200: $%.2f)\n', ...
            upper(asset), precio_actual, mm200);
    end
end