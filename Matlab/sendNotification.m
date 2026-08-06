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

    % Formatear variación diaria con signo (+/-)
    if var_diaria >= 0
        str_var = sprintf('+%.2f%%', var_diaria);
    else
        str_var = sprintf('%.2f%%', var_diaria);
    end

    % 2. Diferencia porcentual respecto a la MA200
    diff_ma200 = ((precio_actual - mm200) / mm200) * 100;
    
    if diff_ma200 >= 0
        str_ma200 = sprintf('+%.2f%%', diff_ma200);
    else
        str_ma200 = sprintf('%.2f%%', diff_ma200);
    end

    % 3. Detectar si hoy hay señal activa
    es_2smm = (~isempty(entradas_2smm) && entradas_2smm(end) == today_idx);
    es_2mmvix = (~isempty(entradas_2mmvix) && entradas_2mmvix(end) == today_idx);

    % 4. Lógica del código de colores según el estado
    if es_2mmvix
        % SEÑAL AGRESIVA (+ VIX) -> Verde + Fuego 🔥🟢
        msg = sprintf('🔥🟢 [%s] 🚨 AGGRESSIVE BUY! (Strategy: 2smm + VIX)\n   ↳ Price: $%.2f (%s)  |  MA200: $%.2f [%s]\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
            
    elseif es_2smm
        % SEÑAL DE COMPRA NORMAL -> Verde 🟢
        msg = sprintf('🟢 [%s] 🚨 BUY SIGNAL! (Strategy: 2smm)\n   ↳ Price: $%.2f (%s)  |  MA200: $%.2f [%s]\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
            
    elseif precio_actual < mm200
        % SIN SEÑAL PERO PRECIO < MA200 -> Ámbar 🟡
        msg = sprintf('🟡 [%s] Below MA200 (Price: $%.2f (%s)  |  MA200: $%.2f [%s])\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
            
    else
        % SIN SEÑAL Y PRECIO >= MA200 -> Rojo 🔴
        msg = sprintf('🔴 [%s] No signal (Price: $%.2f (%s)  |  MA200: $%.2f [%s])\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
    end
end