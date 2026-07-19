function [r, num_aportaciones, entradas_filtradas_ret, rsi] = calcularCAGR_aportaciones(entradas, data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen,vix,vix_umbral)
entradas_filtradas_ret=[];
rsi=[];



% %Calcular CAGR con aportaciones no periodicas puntuales
% mm es una variable booleana, 1 activa el calculo con medias moviles. 0 no
% usa medias moviles, solo los puntos de entradas de Shewhart.

dinero_final_lump=dinero_inicial/data(1)*data(end); %pasado el periodo estudiado sin hacer ninguna aportacion.
dinero_final_aportaciones=0;

if enableMA==0
    entradas = entradas(:).'; 
    num_aportaciones=length(entradas);
    %fprintf("Calculo utilizando solo los puntos de entrada de Shewhart\n")

    %Calcular los precios de entrada a -X sigma:
    precios_entrada=[];
    for i=1:length(entradas)
        precios_entrada(i)=data(entradas(i));
    end


    %comprar cuando el mercado caiga por debajo de -X s:
    dinero_final_aportaciones=0;
    acciones_compradas=0;
    for i=1:length(precios_entrada)
        acciones_compradas=acciones_compradas+(aportacion/precios_entrada(i));
    end

    %dinero_final_aportaciones=acciones_compradas*data(end)+dinero_final_lump;
    %dinero_final_aportaciones = acciones_compradas * data(end);
     dinero_final_total = dinero_final_lump + acciones_compradas * data(end);

    %Ahora hay que calcular la CAGR incluyendo las aportaciones con sus fechas
    %de entrada.

    entradas_365 = entradas*365/252; %para pasar a dias naturales.
    %aportacion=2500;

    %calcular la CAGR teniendo en cuenta las aportaciones (Convertirlo a
    %funcion)


    T = periodos; % 365 días naturales

    % Inicializar arrays de aportaciones y fechas
    aportaciones=[];
    aportaciones = [dinero_inicial, repmat(aportacion, 1, length(entradas))];
   % dias_aportaciones = [0, entradas_365']; % Día 0 para el dinero inicial
     dias_aportaciones = [0, entradas_365]; % Día 0 para el dinero inicial
    % Convertir a años (T - t_i)
    tiempos = T - dias_aportaciones / 365;

    % Valor final total (con aportaciones)
    dinero_final_aportaciones;

    % Función para encontrar r (CAGR)
    funcion_CAGR = @(r) sum(aportaciones .* (1 + r).^tiempos) - dinero_final_total;

    % Usar fzero para encontrar la tasa de crecimiento r
    r = fzero(funcion_CAGR, [-1, 6]); % busca la solucion en un intervalo desde -100% a +200%

elseif enableMA==1
    %fprintf("Calculo utilizando Shewhart y medias moviles\n")
    [mm200, mm150, mm100, mm50] = Medias_Moviles(datamm,data);



    if MA==50
        MA=mm50;
    elseif MA==100
        MA=mm100;
    elseif MA==150
        MA=mm150;

    elseif MA==200
        MA=mm200;
    else
        fprintf("Error: Select a right value for the MA (25, 50, 100, 150) \n")
    end


    %Calcular los precios de entrada a -X sigma:
    precios_entrada=[];


    for i = 1:length(entradas)
        idx = entradas(i);
        % if data(idx) < mm50(idx)
        if data(idx) < MA(idx)
            precios_entrada(end+1) = data(idx);
            entradas_filtradas_ret(end+1) = idx;
        end
    end

    num_aportaciones=length(entradas_filtradas_ret);

    if isempty(precios_entrada)
        r = calcularCAGR(dinero_inicial,dinero_final_lump, periodos); % 1 periodo Controlar este calculo
       % fprintf("Ningun punto de entrada.\n")

    else

        %fprintf("Puntos de entrada encontrados: %d\n", size(precios_entrada,2))

        %comprar cuando el mercado caiga por debajo de -X s:
        dinero_final_aportaciones=0;
        acciones_compradas=0;
        for i=1:length(precios_entrada)
            acciones_compradas=acciones_compradas+(aportacion/precios_entrada(i));
        end

        %dinero_final_aportaciones=acciones_compradas*data(end)+dinero_final_lump;
        %dinero_final_aportaciones=acciones_compradas*data(end);
        dinero_final_total = dinero_final_lump + acciones_compradas * data(end);


        %Ahora hay que calcular la CAGR incluyendo las aportaciones con sus fechas
        %de entrada.

        entradas_filtradas_365 = entradas_filtradas_ret*365/252; %para pasar a dias naturales.
        %aportacion=2500;

        %calcular la CAGR teniendo en cuenta las aportaciones (Convertirlo a
        %funcion)

        T = periodos; % 365 días naturales

        % Inicializar arrays de aportaciones y fechas
        aportaciones=[];
        aportaciones = [dinero_inicial, repmat(aportacion, 1, length(entradas_filtradas_ret))];
        dias_aportaciones = [0, entradas_filtradas_365]; % Día 0 para el dinero inicial

        % Convertir a años (T - t_i)
        tiempos = T - dias_aportaciones / 365;

        % Valor final total (con aportaciones)
        dinero_final_aportaciones;

        % Función para encontrar r (CAGR)
        funcion_CAGR = @(r) sum(aportaciones .* (1 + r).^tiempos) - dinero_final_total;
        %disp('--- Verificación antes de fzero ---')
        %disp(table((0:length(entradas_filtradas))', aportaciones', dias_aportaciones', tiempos', ...
        %    'VariableNames', {'#', 'Aportacion', 'Dia_aport', 'Tiempo_en_anos'}));
        %fprintf('Dinero final calculado: %.2f\n', dinero_final_aportaciones);
        % Usar fzero para encontrar la tasa de crecimiento r
        r = fzero(funcion_CAGR, [-1, 10]); % busca la solucion en un intervalo desde -100% a +200%
    end




elseif enableMA == 2

   % fprintf("Cálculo utilizando Shewhart + MM y evitando compras si hubo una cruz de la muerte en los últimos 30 días bursátiles\n");

    [mm200, mm150, mm100, mm50] = Medias_Moviles(datamm, data);

    if media_movil_lenta==150
        media_movil_lenta=mm150;
    elseif media_movil_lenta==100
        media_movil_lenta=mm100;
    elseif media_movil_lenta==200
        media_movil_lenta=mm200;
    else
        fprintf("Error: media movil lenta debe ser (100, 150, 200) \n")
    end


    % Detectar cruces de la muerte: MM50 cruza por debajo de MM200
    cruces_muerte = [];
    for i = 2:length(data)
        if ~isnan(mm50(i)) && ~isnan(media_movil_lenta(i))
            if mm50(i) < media_movil_lenta(i) && mm50(i - 1) >= media_movil_lenta(i - 1)
                cruces_muerte(end + 1) = i;
            end
        end
    end
   % fprintf("Cruces de la muerte detectadas: %d\n", length(cruces_muerte));

    % Crear vector de fechas bloqueadas (30 días tras cada cruce)
    dias_bloqueo = bloqueos;
    fechas_bloqueadas = false(1, length(data));
    for i = 1:length(cruces_muerte)
        ini = cruces_muerte(i);
        fin = min(ini + dias_bloqueo, length(data));
        fechas_bloqueadas(ini:fin) = true;
    end

    % === FILTRADO CORRECTO: NO volver a aplicar MM200 aquí ===
    precios_entrada = [];
    entradas_filtradas_ret = [];

    for i = 1:length(entradas)  % ← estas ya deberían estar filtradas por -2σ y MM200
        idx = entradas(i);

        if idx >= 1 && idx <= length(data)
            if ~fechas_bloqueadas(idx)
                precios_entrada(end + 1) = data(idx);
                entradas_filtradas_ret(end + 1) = idx;
            else
                fprintf(" Entrada en %d bloqueada por cruce reciente\n", idx);
            end
        end
    end

    % === Mostrar entradas bloqueadas ===
    % fprintf("\n--- Entradas bloqueadas por cruce de la muerte ---\n");
    % entradas_bloqueadas = setdiff(entradas, entradas_filtradas_ret);
    % for i = 1:length(entradas_bloqueadas)
    %     idx = entradas_bloqueadas(i);
    %     cruce_anterior = cruces_muerte(cruces_muerte <= idx);
    %     if ~isempty(cruce_anterior)
    %         delta = idx - cruce_anterior(end);
    %         if delta <= dias_bloqueo
    %             fprintf("Entrada en %d bloqueada por cruce en %d (Δ = %d días)\n", ...
    %                 idx, cruce_anterior(end), delta);
    %         end
    %     end
    % end
    % fprintf("--------------------------------------------------\n\n");

    % === Cálculo de CAGR ===
    num_aportaciones = length(entradas_filtradas_ret);

    % if isempty(precios_entrada)
    %     r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos);
    %     fprintf("  Ninguna entrada válida tras bloquear por cruce de la muerte.\n");
    % else
    %     fprintf(" Entradas válidas (sin cruce de la muerte reciente): %d\n", num_aportaciones);
    % 
    %     acciones_compradas = sum(aportacion ./ precios_entrada);
    %     dinero_final_total = dinero_final_lump + acciones_compradas * data(end);
    % 
    % 
    %     entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252;
    %     T = periodos;
    % 
    %     aportaciones = [dinero_inicial, repmat(aportacion, 1, num_aportaciones)];
    %     dias_aportaciones = [0, entradas_filtradas_365];
    %     tiempos = T - dias_aportaciones / 365;
    % 
    %     funcion_CAGR = @(r) sum(aportaciones .* (1 + r).^tiempos) - dinero_final_total;
    % 
    %     disp('--- Verificación antes de fzero (con bloqueo por cruce de la muerte) ---');
    %     disp(table((0:length(entradas_filtradas_ret))', aportaciones', dias_aportaciones', tiempos', ...
    %         'VariableNames', {'#', 'Aportacion', 'Dia_aport', 'Tiempo_en_anos'}));
    %     fprintf('Dinero final calculado: %.2f\n', dinero_final_total);
    % 
    %     r = fzero(funcion_CAGR, [-1, 10]);
    % end



elseif enableMA == 3
  %  fprintf("Cálculo utilizando Shewhart + MM y SOLO comprando tras cruz dorada (MM50 > MM lenta)\n"); % compra solo despues de la primera cruz dorada

    [mm200, mm150, mm100, mm50] = Medias_Moviles(datamm, data);

    % Selección de MM lenta
    if media_movil_lenta == 150
        mm_lenta = mm150;
    elseif media_movil_lenta == 100
        mm_lenta = mm100;
    elseif media_movil_lenta == 200
        mm_lenta = mm200;
    else
        error("Error: media_movil_lenta debe ser 100, 150 o 200");
    end

    % === Detectar cruz dorada: MM50 cruza por encima de MM lenta ===
    cruces_dorada = [];
    for i = 2:length(data)
        if ~isnan(mm50(i)) && ~isnan(mm_lenta(i))
            if mm50(i) > mm_lenta(i) && mm50(i - 1) <= mm_lenta(i - 1)
                cruces_dorada(end + 1) = i;
            end
        end
    end
    %fprintf("Cruces doradas detectadas: %d\n", length(cruces_dorada));

    % === Mantener bandera de "permitido comprar" tras cruz dorada ===
    % Creamos un array lógico para marcar días después de cruz dorada
    permitido_comprar = false(1, length(data));
    for i = 1:length(cruces_dorada)
        permitido_comprar(cruces_dorada(i):end) = true;
    end

    % === Filtrar entradas SOLO si están tras cruz dorada ===
    precios_entrada = [];
    entradas_filtradas_ret = [];

    for i = 1:length(entradas)
        idx = entradas(i);
        if idx >= 1 && idx <= length(data)
            if permitido_comprar(idx)
                precios_entrada(end + 1) = data(idx);
                entradas_filtradas_ret(end + 1) = idx;
            else
               % fprintf(" Entrada en %d descartada (aún no hay cruz dorada)\n", idx);
            end
        end
    end

    %fprintf("Entradas válidas tras cruz dorada: %d\n", length(entradas_filtradas_ret));
    num_aportaciones = length(entradas_filtradas_ret);

    if isempty(precios_entrada)
        r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos);
     %   fprintf("  Ninguna entrada válida tras cruz dorada.\n");
    else
        acciones_compradas = sum(aportacion ./ precios_entrada);
        %dinero_final_aportaciones = acciones_compradas * data(end) + dinero_final_lump;
        %dinero_final_aportaciones = acciones_compradas * data(end);
        dinero_final_total = dinero_final_lump + acciones_compradas * data(end);

        entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252;
        T = periodos;

        aportaciones = [dinero_inicial, repmat(aportacion, 1, num_aportaciones)];
        dias_aportaciones = [0, entradas_filtradas_365];
        tiempos = T - dias_aportaciones / 365;

        funcion_CAGR = @(r) sum(aportaciones .* (1 + r).^tiempos) - dinero_final_total;

        % disp('--- Verificación antes de fzero (con cruz dorada) ---');
        % disp(table((0:length(entradas_filtradas_ret))', aportaciones', dias_aportaciones', tiempos', ...
        %     'VariableNames', {'#', 'Aportacion', 'Dia_aport', 'Tiempo_en_anos'}));
        % fprintf('Dinero final calculado: %.2f\n', dinero_final_total);

        r = fzero(funcion_CAGR, [-1, 10]);
    end

elseif enableMA == 4
   % fprintf("Cálculo utilizando Shewhart + MM y SOLO comprando en días con MM50 > MM_lenta (tendencia alcista)\n");

    [mm200, mm150, mm100, mm50] = Medias_Moviles(datamm, data);

    % Selección de MM lenta
    if media_movil_lenta == 150
        mm_lenta = mm150;
    elseif media_movil_lenta == 100
        mm_lenta = mm100;
    elseif media_movil_lenta == 200
        mm_lenta = mm200;
    else
        error("Error: media_movil_lenta debe ser 100, 150 o 200");
    end

    % === Filtrar entradas si y solo si MM50 > MM_lenta ese día ===
    precios_entrada = [];
    entradas_filtradas_ret = [];

    for i = 1:length(entradas)
        idx = entradas(i);
        if idx >= 1 && idx <= length(data)
            if mm50(idx) > mm_lenta(idx)
                precios_entrada(end + 1) = data(idx);
                entradas_filtradas_ret(end + 1) = idx;
            else
               % fprintf(" Entrada en %d descartada (no hay tendencia alcista)\n", idx);
            end
        end
    end

   % fprintf("Entradas válidas con tendencia alcista (MM50 > MM_lenta): %d\n", length(entradas_filtradas_ret));
    num_aportaciones = length(entradas_filtradas_ret);

    if isempty(precios_entrada)
        r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos);
    %    fprintf("  Ninguna entrada válida con MM50 > MM_lenta.\n");
    else
        acciones_compradas = sum(aportacion ./ precios_entrada);
        %dinero_final_aportaciones = acciones_compradas * data(end) + dinero_final_lump;
        %dinero_final_aportaciones = acciones_compradas * data(end);
        dinero_final_total = dinero_final_lump + acciones_compradas * data(end);

        entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252;
        T = periodos;

        aportaciones = [dinero_inicial, repmat(aportacion, 1, num_aportaciones)];
        dias_aportaciones = [0, entradas_filtradas_365];
        tiempos = T - dias_aportaciones / 365;

        funcion_CAGR = @(r) sum(aportaciones .* (1 + r).^tiempos) - dinero_final_total;

        % disp('--- Verificación antes de fzero (solo tendencia alcista) ---');
        % disp(table((0:length(entradas_filtradas_ret))', aportaciones', dias_aportaciones', tiempos', ...
        %     'VariableNames', {'#', 'Aportacion', 'Dia_aport', 'Tiempo_en_anos'}));
        % fprintf('Dinero final calculado: %.2f\n', dinero_final_total);

        r = fzero(funcion_CAGR, [-1, 10]);
    end

elseif enableMA == 5
   % fprintf("Estrategia con volumen: SOLO comprar si volumen del día > media(35 días)");

    media_volumen = movmean(volumen, 35);

    precios_entrada = [];
    entradas_filtradas_ret = [];

    for i = 1:length(entradas)
        idx = entradas(i);
        if volumen(idx) >  media_volumen(idx)
            precios_entrada(end + 1) = data(idx);
            entradas_filtradas_ret(end + 1) = idx;
        else
           % fprintf(" Entrada en %d descartada por volumen bajo\n", idx);
        end
    end

  %  fprintf("Entradas válidas por volumen alto: %d\n", length(entradas_filtradas_ret));
    num_aportaciones = length(entradas_filtradas_ret);

    if isempty(precios_entrada)
        r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos);
   %     fprintf("  Ninguna entrada válida con volumen > media(35).\n");
    else
        acciones_compradas = sum(aportacion ./ precios_entrada);
        %dinero_final_aportaciones = acciones_compradas * data(end) + dinero_final_lump;
        %dinero_final_aportaciones = acciones_compradas * data(end);
         dinero_final_total = dinero_final_lump + acciones_compradas * data(end);


        entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252;
        T = periodos;

        aportaciones = [dinero_inicial, repmat(aportacion, 1, num_aportaciones)];
        dias_aportaciones = [0, entradas_filtradas_365];
        tiempos = T - dias_aportaciones / 365;

        funcion_CAGR = @(r) sum(aportaciones .* (1 + r).^tiempos) - dinero_final_total;

        r = fzero(funcion_CAGR, [-1, 10]);
    end


    elseif enableMA == 6
    %fprintf("Estrategia: filtrar entradas si 25<RSI(14)<60 \n");

    rsi_len = 14;
    rsi = rsi_wilder(data, rsi_len);

    precios_entrada = [];
    entradas_filtradas_ret = [];

    for i = 1:length(entradas)
        idx = entradas(i);
        if idx > rsi_len && idx <= length(data)
            if rsi(idx) <= 60 && rsi(idx)>=25
                precios_entrada(end+1) = data(idx);
                entradas_filtradas_ret(end+1) = idx;
            else
     %           fprintf(" Entrada en %d descartada (RSI=%.1f)\n", idx, rsi(idx));
            end
        end
    end

    %fprintf("Entradas válidas con 25<RSI(14) ≤ 60: %d\n", length(entradas_filtradas_ret));
    num_aportaciones = length(entradas_filtradas_ret);

    if isempty(precios_entrada)
        r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos);
     %   fprintf("  Ninguna entrada válida tras filtrar por 25<RSI<60.\n");
    else
        acciones_compradas = sum(aportacion ./ precios_entrada);
        %dinero_final_aportaciones = acciones_compradas * data(end) + dinero_final_lump;
        %dinero_final_aportaciones = acciones_compradas * data(end);
         dinero_final_total = dinero_final_lump + acciones_compradas * data(end);


        entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252;
        T = periodos;

        aportaciones = [dinero_inicial, repmat(aportacion, 1, num_aportaciones)];
        dias_aportaciones = [0, entradas_filtradas_365];
        tiempos = T - dias_aportaciones / 365;

        funcion_CAGR = @(r) sum(aportaciones .* (1 + r).^tiempos) - dinero_final_total;
        r = fzero(funcion_CAGR, [-1, 10]);
    end


elseif enableMA == 7
    % Shewhart -2σ + filtro VIX (descarta si VIX < vix_umbral)
    if isempty(vix)
        error('enableMA==7 requiere pasar el vector VIX como argumento (vix).');
    end
    if numel(vix) ~= numel(data)
        M = min(numel(vix), numel(data));
        warning('VIX y data con longitudes distintas. Se alinean al último %d elementos.', M);
        data = data(end-M+1:end);
        vix  = vix(end-M+1:end);
        % si usas datamm para algo más adelante, recórtalo también si quieres
    end

    %fprintf("Cálculo Shewhart -2σ + filtro VIX (descarta VIX < %.2f)\n", vix_umbral);

    precios_entrada = [];
    entradas_filtradas_ret = [];

    % 'entradas' ya son las señales Shewhart -2σ base que le pasas
    for i = 1:length(entradas)
        idx = entradas(i);
        if idx >= 1 && idx <= length(data)
            if ~isnan(vix(idx)) && vix(idx) >= vix_umbral
                precios_entrada(end+1)      = data(idx);
                entradas_filtradas_ret(end+1) = idx;
            else
                if ~isnan(vix(idx))
     %               fprintf(" Entrada en %d descartada por VIX (%.2f < %.2f)\n", idx, vix(idx), vix_umbral);
                else
      %              fprintf(" Entrada en %d descartada por VIX NaN\n", idx);
                end
            end
        end
    end

    num_aportaciones = length(entradas_filtradas_ret);

    if isempty(precios_entrada)
        r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos);
        %fprintf("  Ninguna entrada válida tras filtro VIX.\n");
    else
        % Compras y CAGR (idéntico a tu caso base)
        acciones_compradas = sum(aportacion ./ precios_entrada);
        %dinero_final_aportaciones = acciones_compradas * data(end) + dinero_final_lump;
        %dinero_final_aportaciones = acciones_compradas * data(end);
        dinero_final_total = dinero_final_lump + acciones_compradas * data(end);

        entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252; % días naturales aprox
        T = periodos;

        aportaciones      = [dinero_inicial, repmat(aportacion, 1, num_aportaciones)];
        dias_aportaciones = [0, entradas_filtradas_365];
        tiempos           = T - dias_aportaciones / 365;

        funcion_CAGR = @(rr) sum(aportaciones .* (1 + rr).^tiempos) - dinero_final_total;
        r = fzero(funcion_CAGR, [-1, 10]);
    end



  








else
    fprintf("error: introduce 0 o 1 en la variable mm\n")

end
end




% Funcion RSI

function rsi = rsi_wilder(close, n)
% RSI de Wilder (sin toolboxes). Devuelve un vector columna con NaN iniciales.
    close = close(:);                 % asegurar columna
    d = diff(close);
    up = max(d, 0);
    dn = max(-d, 0);

    rsi = nan(size(close));           % misma longitud que 'close'
    if numel(close) < n + 1
        return
    end

    % Medias iniciales (simples) para la primera ventana
    avgU = mean(up(1:n), 'omitnan');
    avgD = mean(dn(1:n), 'omitnan');

    % Primer RSI válido (posición n+1)
    if avgD == 0
        rsi(n+1) = 100;               % sin descensos en la ventana
    else
        rs = avgU / avgD;
        rsi(n+1) = 100 - 100 / (1 + rs);
    end

    % Suavizado de Wilder (EMA con alpha = 1/n)
    for t = n+2:numel(close)
        avgU = (avgU * (n - 1) + up(t-1)) / n;
        avgD = (avgD * (n - 1) + dn(t-1)) / n;

        if avgD == 0
            rsi(t) = 100;
        else
            rs = avgU / avgD;
            rsi(t) = 100 - 100 / (1 + rs);
        end
    end
end


