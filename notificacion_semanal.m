function [msg] = notificacion_semanal(asset, data, entradas_2smm, entradas_2mmvix, mm200)
    today_idx = length(data);
    precio_actual = data(today_idx);
    
    % 1. Variación semanal (respecto a 5 sesiones atrás, cierre del viernes anterior)
    if today_idx > 5
        precio_semana_pasada = data(today_idx - 5);
        var_semanal = ((precio_actual - precio_semana_pasada) / precio_semana_pasada) * 100;
    elseif today_idx > 1
        precio_inicial = data(1);
        var_semanal = ((precio_actual - precio_inicial) / precio_inicial) * 100;
    else
        var_semanal = 0;
    end
    
    % Formatear variación semanal con signo (+/-)
    if var_semanal >= 0
        str_var = sprintf('+%.2f%% 1W', var_semanal);
    else
        str_var = sprintf('%.2f%% 1W', var_semanal);
    end
    
    % 2. Diferencia porcentual respecto a la MA200
    diff_ma200 = ((precio_actual - mm200) / mm200) * 100;
    if diff_ma200 >= 0
        str_ma200 = sprintf('+%.2f%%', diff_ma200);
    else
        str_ma200 = sprintf('%.2f%%', diff_ma200);
    end
    
    % 3. Rango de la semana (últimas 5 sesiones bursátiles: Lunes a Viernes)
    week_start_idx = max(1, today_idx - 4);
    
    % Buscar si hubo alguna señal en CUALQUIERA de los días de esta semana
    hubo_2mmvix_semana = any(entradas_2mmvix >= week_start_idx & entradas_2mmvix <= today_idx);
    hubo_2smm_semana   = any(entradas_2smm >= week_start_idx & entradas_2smm <= today_idx);
    
    % 4. Jerarquía de Criticidad (Prioridad: 🔥🟢 VIX > 🟢 2sigma > 🟡 Bajo MA200 > 🔴 Sin Señal)
    if hubo_2mmvix_semana
        % MÁXIMA CRITICIDAD: Hubo señal de compra agresiva (+ VIX) en la semana
        msg = sprintf('🔥🟢 [%s] 🚨 AGGRESSIVE BUY! (Strategy: 2smm + VIX)\n   ↳ Price: $%.2f (%s)  |  MA200: $%.2f [%s]\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
            
    elseif hubo_2smm_semana
        % SEGUNDA CRITICIDAD: Hubo señal de compra normal (2sigma) en la semana
        msg = sprintf('🟢 [%s] 🚨 BUY SIGNAL! (Strategy: 2smm)\n   ↳ Price: $%.2f (%s)  |  MA200: $%.2f [%s]\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
            
    elseif precio_actual < mm200
        % SIN SEÑAL EN LA SEMANA, PERO PRECIO < MA200
        msg = sprintf('🟡 [%s] Below MA200 (Price: $%.2f (%s)  |  MA200: $%.2f [%s])\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
            
    else
        % SIN SEÑAL Y PRECIO >= MA200
        msg = sprintf('🔴 [%s] No signal (Price: $%.2f (%s)  |  MA200: $%.2f [%s])\n', ...
            upper(asset), precio_actual, str_var, mm200, str_ma200);
    end
end