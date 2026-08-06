function [r, num_aportaciones, entradas_bb, entradas_filtradas_ret, rsi,bb_inf,bb_sup,ma_bb] = calcularCAGR_aportaciones_bollinger(data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, volumen, vix, vix_umbral, N_bollinger)

entradas_filtradas_ret = [];
rsi = [];
entradas_bb = [];

% === Valor final buy&hold del dinero inicial (lump-sum coherente) ===
dinero_final_lump = dinero_inicial / data(1) * data(end);

%==============================================================
% Bollinger CONTRARIAN (autónoma, causal): BB(n=20, k=2)
% Señal base = precio <= banda inferior (usar_cruce=false por defecto)
%==============================================================
%fprintf("Estrategia Bollinger contrarian autónoma: BB(n,k) causal, señal = precio <= banda inferior.\n");

% Parámetros

bb_n = 20;         % ventana por defecto
bb_k = 2;          % nº de desviaciones
bb_n=N_bollinger;
usar_cruce = false;
if exist('N_bollinger','var') && ~isempty(N_bollinger) && N_bollinger > 1
    bb_n = N_bollinger;
end

data = data(:);
N = length(data);

% Medias/desv. móviles CAUSALES (sin look-ahead)
ma_bb    = movmean(data, [bb_n-1 0]);
bb_sigma = movstd (data, [bb_n-1 0]);
bb_inf   = ma_bb - bb_k * bb_sigma;
bb_sup = ma_bb + bb_k * bb_sigma;

% Entradas autónomas
cond = ((1:N)' > bb_n) & ~isnan(bb_inf) & (data <= bb_inf);

if usar_cruce
    cond_prev    = [false; cond(1:end-1)];
    cond_cruce   = cond & ~cond_prev;
    entradas_aut = find(cond_cruce).';
else
    entradas_aut = find(cond).';
end

% Guardamos entradas base (por si aplicamos filtros)
precios_entrada_base   = data(entradas_aut);
entradas_filtradas_ret = entradas_aut;       % por defecto = base
entradas_bb            = entradas_aut;       % las exponemos como salida
num_aportaciones       = numel(entradas_filtradas_ret);

% ========== CAGR para la base (Bollinger sin filtros) ==========
if isempty(precios_entrada_base)
    % Sin señales => IRR de buy&hold del dinero inicial
    r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos);
 %   fprintf("  Ninguna entrada válida con Bollinger contrarian autónoma.\n");
else
    acciones_compradas = sum(aportacion ./ precios_entrada_base);
    dinero_final_aportaciones = acciones_compradas * data(end);

    % Valor final total coherente (lump-sum + señales)
    valor_final_total = dinero_final_lump + dinero_final_aportaciones;

    % Flujos y tiempos (días naturales aprox)
    entradas_365 = entradas_filtradas_ret * 365 / 252;
    T = periodos;

    aportaciones      = [dinero_inicial, repmat(aportacion, 1, num_aportaciones)];
    dias_aportaciones = [0, entradas_365];
    tiempos           = T - dias_aportaciones / 365;

    funcion_CAGR = @(rr) sum(aportaciones .* (1 + rr).^tiempos) - valor_final_total;
    r = fzero(funcion_CAGR, [-1, 10]);
end

if enableMA == 1
  %  fprintf("Calculo utilizando Bollinger y medias moviles\n")

    % Medias alineadas con 'data'
    [mm200, mm150, mm100, mm50] = Medias_Moviles(datamm, data);

    % NO reutilizar 'MA'. Elegimos una serie clara:
    if MA == 50
        mm_sel = mm50;
    elseif MA == 100
        mm_sel = mm100;
    elseif MA == 150
        mm_sel = mm150;
    elseif MA == 200
        mm_sel = mm200;
    else
        error("MA debe ser 50/100/150/200");
    end

    % Depuración útil
   % fprintf("Entradas Bollinger base: %d\n", numel(entradas_bb));

    precios_entrada = [];
    entradas_filtradas_ret = [];

    % Asegura vector fila, ordenado y único
    entradas_bb = unique(entradas_bb(:).', 'stable');

    % Filtro REAL: precio < MM seleccionada (y MM válida)
    for k = 1:numel(entradas_bb)
        idx = entradas_bb(k);
        if idx >= 1 && idx <= numel(data) && ~isnan(mm_sel(idx))
            if data(idx) < mm_sel(idx)
                precios_entrada(end+1)     = data(idx); %#ok<AGROW>
                entradas_filtradas_ret(end+1) = idx;    %#ok<AGROW>
            end
        end
    end

    %fprintf("Entradas tras filtro MM(%d): %d\n", MA, numel(entradas_filtradas_ret));
    num_aportaciones = numel(entradas_filtradas_ret);

    if isempty(precios_entrada)
        r = calcularCAGR(dinero_inicial, dinero_inicial/data(1)*data(end), periodos);
     %   fprintf("Ningun punto de entrada tras filtro de MM.\n")
    else
        % Compras
        acciones_compradas = sum(aportacion ./ precios_entrada);
        dinero_final_total = (dinero_inicial/data(1)*data(end)) + acciones_compradas * data(end);

        % Fechas a días naturales
        entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252;
        T = periodos;

        aportaciones      = [dinero_inicial, repmat(aportacion, 1, num_aportaciones)];
        dias_aportaciones = [0, entradas_filtradas_365];
        tiempos           = T - dias_aportaciones / 365;

        funcion_CAGR = @(rr) sum(aportaciones .* (1 + rr).^tiempos) - dinero_final_total;
        r = fzero(funcion_CAGR, [-1, 10]);
    end
end


if enableMA == 2
    %==============================================================
    % Bollinger + filtro Media Móvil (MA) + filtro VIX mínimo
    % Mantiene SOLO las entradas donde:
    %   - data(idx) < MM_sel(idx)
    %   - vix(idx)  >= vix_umbral
    %==============================================================
    
    %fprintf("Bollinger + MM(%d) + VIX >= %.2f\n", MA, vix_umbral);

    % --- 1) Selección de MM ---
    [mm200, mm150, mm100, mm50] = Medias_Moviles(datamm, data);
    if     MA == 50,  mm_sel = mm50;
    elseif MA == 100, mm_sel = mm100;
    elseif MA == 150, mm_sel = mm150;
    elseif MA == 200, mm_sel = mm200;
    else,  error("MA debe ser 50/100/150/200");
    end

    % --- 2) Preparar VIX y alinear con 'data' si hiciera falta ---
    if isempty(vix)
        error("enableMA==2 requiere vector VIX y vix_umbral.");
    end
    vix = vix(:);
    if numel(vix) ~= numel(data)
        M = min(numel(vix), numel(data));
        warning('VIX y data con longitudes distintas. Se alinean a los últimos %d elementos.', M);
        data   = data(end-M+1:end);
        mm_sel = mm_sel(end-M+1:end);
        vix    = vix(end-M+1:end);
        % Reajusta entradas_bb a la nueva longitud
        mask_in = entradas_bb > numel(data);      % fuera de rango tras recorte
        entradas_bb(mask_in) = [];
    end

    % --- 3) Filtrado doble: MM + VIX ---
    entradas_bb = unique(entradas_bb(:).', 'stable');
    precios_entrada = [];
    entradas_filtradas_ret = [];

    for k = 1:numel(entradas_bb)
        idx = entradas_bb(k);
        if idx >= 1 && idx <= numel(data) && ~isnan(mm_sel(idx)) && ~isnan(vix(idx))
            cond_mm  = (data(idx) < mm_sel(idx));
            cond_vix = (vix(idx) >= vix_umbral);
            if cond_mm && cond_vix
                precios_entrada(end+1)        = data(idx); %#ok<AGROW>
                entradas_filtradas_ret(end+1) = idx;       %#ok<AGROW>
            else
                % Mensajes de depuración (opcional):
                % fprintf("Descartada idx=%d | MM:%d VIX:%d (vix=%.2f)\n", ...
                %    idx, cond_mm, cond_vix, vix(idx));
            end
        end
    end

    %fprintf("Entradas base Bollinger: %d | tras MM+VIX: %d\n",numel(entradas_bb), numel(entradas_filtradas_ret));

    % --- 4) CAGR con las entradas filtradas ---
    num_aportaciones = numel(entradas_filtradas_ret);
    if isempty(precios_entrada)
        r = calcularCAGR(dinero_inicial, dinero_inicial/data(1)*data(end), periodos);
     %   fprintf("Ninguna entrada tras filtro MM+VIX.\n");
    else
        acciones_compradas  = sum(aportacion ./ precios_entrada);
        dinero_final_total  = (dinero_inicial/data(1)*data(end)) + acciones_compradas * data(end);

        entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252;
        T = periodos;

        aportaciones      = [dinero_inicial, repmat(aportacion, 1, num_aportaciones)];
        dias_aportaciones = [0, entradas_filtradas_365];
        tiempos           = T - dias_aportaciones / 365;

        funcion_CAGR = @(rr) sum(aportaciones .* (1 + rr).^tiempos) - dinero_final_total;
        r = fzero(funcion_CAGR, [-1, 10]);
    end


end
