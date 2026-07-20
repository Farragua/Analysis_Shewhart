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



% function [msg] = sendNotification(asset, data, entradas_2smm, entradas_2mmvix, mm200)
%     today_idx = length(data);
%     precio_actual = data(today_idx);
% 
%     % 1. Variación diaria (respecto al día anterior)
%     if today_idx > 1
%         precio_ayer = data(today_idx - 1);
%         var_diaria = ((precio_actual - precio_ayer) / precio_ayer) * 100;
%     else
%         var_diaria = 0; % Por seguridad si solo hubiera 1 dato
%     end
% 
%     % Formatear variación diaria con signo (+/-)
%     if var_diaria >= 0
%         str_var = sprintf('+%.2f%%%%', var_diaria);
%     else
%         str_var = sprintf('%.2f%%%%', var_diaria);
%     end
% 
%     % 2. Diferencia porcentual respecto a la MA200
%     diff_ma200 = ((precio_actual - mm200) / mm200) * 100;
% 
%     % Formatear distancia a MA200 con signo (+/-)
%     if diff_ma200 >= 0
%         str_ma200 = sprintf('+%.2f%%%%', diff_ma200);
%     else
%         str_ma200 = sprintf('%.2f%%%%', diff_ma200);
%     end
% 
%     % 3. Detectar si hoy hay señal activa
%     es_2smm = (~isempty(entradas_2smm) && entradas_2smm(end) == today_idx);
%     es_2mmvix = (~isempty(entradas_2mmvix) && entradas_2mmvix(end) == today_idx);
% 
%     % 4. Construir el mensaje formateado
%     if es_2smm
%         msg = sprintf('🟢 [%s] 🚨 BUY SIGNAL! (Strategy: 2smm)\n   ↳ Price: $%.2f (%s)  |  MA200: $%.2f [%s]\n\n', ...
%             upper(asset), precio_actual, str_var, mm200, str_ma200);
% 
%     elseif es_2mmvix
%         msg = sprintf('🔥 [%s] 🚨 AGGRESSIVE BUY! (Strategy: 2smm + VIX)\n   ↳ Price: $%.2f (%s)  |  MA200: $%.2f [%s]\n\n', ...
%             upper(asset), precio_actual, str_var, mm200, str_ma200);
% 
%     else
%         msg = sprintf('⚪ [%s] No signal (Price: $%.2f (%s)  |  MA200: $%.2f [%s])\n\n', ...
%             upper(asset), precio_actual, str_var, mm200, str_ma200);
%     end
% end

function [msg] = sendNotification(asset, data, entradas_2smm, entradas_2mmvix, mm200)
    today_idx = length(data);
    precio_actual = data(today_idx);

    % 1. Variación diaria (respecto al día anterior)
    if today_idx > 1
        precio_ayer = data(today_idx - 1);
        var_diaria = ((precio_actual - precio_ayer) / precio_ayer) * 100;
    else
        var_diaria = 0; % Por seguridad
    end

    % Formatear variación diaria con un solo signo %
    if var_diaria >= 0
        str_var = sprintf('+%.2f%%', var_diaria);
    else
        str_var = sprintf('%.2f%%', var_diaria);
    end

    % 2. Diferencia porcentual respecto a la MA200 con un solo signo %
    diff_ma200 = ((precio_actual - mm200) / mm200) * 100;
    
    if diff_ma200 >= 0
        str_ma200 = sprintf('+%.2f%%', diff_ma200);
    else
        str_ma200 = sprintf('%.2f%%', diff_ma200);
    end

    % 3. Detectar si hoy hay señal activa
    es_2smm = (~isempty(entradas_2smm) && entradas_2smm(end) == today_idx);
    es_2mmvix = (~isempty(entradas_2mmvix) && entradas_2mmvix(end) == today_idx);

    % 4. Construir el mensaje (usamos solo un '\n' al final para dejar exactamente 1 línea de espacio)
    if es_2smm
        msg = sprintf('🟢 [%s] 🚨 BUY SIGNAL! (Strategy: 2smm)\n   ↳ Price: $%.2f (%s)  |  MA200: $%.2f [%s]\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
            
    elseif es_2mmvix
        msg = sprintf('🔥 [%s] 🚨 AGGRESSIVE BUY! (Strategy: 2smm + VIX)\n   ↳ Price: $%.2f (%s)  |  MA200: $%.2f [%s]\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
            
    else
        msg = sprintf('⚪ [%s] No signal (Price: $%.2f (%s)  |  MA200: $%.2f [%s])\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
    end
end