function main_portfolio_flexible(portfolio_name, tickers_config, weights_config, basePath, periodos, MA, weight_limits, max_cash_dia, MA_reb,z_engine,n_boll)
% MAIN PORTFOLIO FLEXIBLE V10 MDD + VOL + SHARPE EN TABLA
% Compara DCA vs Event-driven V1/V2. Muestra MDD, Vol anualizada y Sharpe en la tabla principal.
% Soporte para carteras de 1 solo activo (N==1).

%% ===== VALIDACION DE PARAMETROS =====
if nargin < 1 || isempty(portfolio_name)
    error('Debes especificar el nombre del portfolio');
end

if nargin < 2 || isempty(tickers_config)
    error('Debes especificar los tickers del portfolio');
end

if nargin < 3 || isempty(weights_config)
    weights_config = ones(1, length(tickers_config)) / length(tickers_config);
end

if nargin < 4 || isempty(basePath)
    basePath = 'C:\Users\israe\OneDrive\Matlab_scripts\';
end

if nargin < 5 || isempty(periodos)
    periodos = 1;
end

if nargin < 6 || isempty(MA)
    MA = 150;
end

%% ===== NORMALIZACION PARA N==1 Y ENTRADAS ESCALARES =====
% Asegurar que tickers sea cell array 1xN
if ischar(tickers_config) || isstring(tickers_config)
    tickers_config = cellstr(tickers_config);
end
n = numel(tickers_config);

% Forzar pesos a vector fila 1xN
weights_config = weights_config(:).';
if numel(weights_config)==1 && n>1
    % Si el usuario pasó un único peso y hay varios activos, replicarlo
    weights_config = repmat(weights_config, 1, n);
end
if n==1
    % Para un solo activo, el peso debe ser 100%
    weights_config = 1;
end

% Validar que pesos sumen 1
if abs(sum(weights_config) - 1.0) > 1e-6
    error('Los pesos deben sumar 1.0. Suma actual: %.6f', sum(weights_config));
end

% Defecto y forma de weight_limits/upper_abs
if nargin < 7 || isempty(weight_limits)
    if n==1
        weight_limits = 1;      % permitir 100% si hay un solo activo
    else
        weight_limits = 0.30;   % por defecto multi-activo
    end
end
if isscalar(weight_limits)
    weight_limits = repmat(weight_limits, 1, n);
end
upper_abs = reshape(weight_limits, 1, []);

%% ===== CONFIGURACION =====
%z_engine = 'shewhart_tippett';   % 'shewhart_tippett' | 'bollinger'
%n_boll = 22;                     % Periodos Bollinger
z_threshold = -2.0;              % Umbral Z para señales
debug = false;                   % true = output detallado

%% ===== VERIFICAR ARCHIVOS =====
fprintf('Verificando archivos para portfolio "%s"...\n', portfolio_name);
archivos_faltantes = {};
for i = 1:length(tickers_config)
    ticker = tickers_config{i};
    archivo = fullfile(basePath, [ticker '_yahoo.csv']);
    if ~isfile(archivo)
        archivos_faltantes{end+1} = [ticker '_yahoo.csv']; %#ok<AGROW>
    end
end

if ~isempty(archivos_faltantes)
    fprintf('❌ ARCHIVOS FALTANTES:\n');
    for i = 1:length(archivos_faltantes)
        fprintf('   %s\n', archivos_faltantes{i});
    end
    fprintf('\nEjecuta main_vYahoo.m primero para descargar estos tickers.\n');
    return;
end

fprintf('✅ Todos los archivos están disponibles.\n\n');

%% ===== EJECUTAR ESTRATEGIAS =====
fprintf('Ejecutando Portfolio "%s" - COMPARACION V1 vs V2\n', portfolio_name);
fprintf('Tickers: %s\n', strjoin(tickers_config, ', '));
fprintf('Pesos: %s\n', sprintf('%.1f%% ', weights_config*100));
fprintf('Techos: %s\n', sprintf('%.1f%% ', upper_abs*100));
fprintf('Periodo: %d años | Motor: %s\n', periodos, z_engine);
fprintf('======================================================\n\n');

try
    % === ESTRATEGIAS BASELINE (DCA) ===
    fprintf('1/11 Ejecutando: Simple DCA...\n');
    [r1, n1, vf1, det1] = Strategy_simple_DCA_flexible_sigma(periodos, basePath, tickers_config, weights_config, debug);
    
    fprintf('2/11 Ejecutando: Simple + Rebalanceo...\n');
    [r2, n2, vf2, det2] = Strategy_simple_DCA_rebal_flexible_sigma(periodos, basePath, tickers_config, weights_config, upper_abs, debug);
    
    fprintf('3/11 Ejecutando: Simple + Rebalanceo + MM...\n');
    [r3, n3, vf3, det3] = Strategy_simple_DCA_rebal_mm_flexible_sigma(periodos, basePath, tickers_config, weights_config, upper_abs, MA_reb, debug);
    
    % === EVENT-DRIVEN V1 (CON LIMITACIONES) ===
    fprintf('4/11 Ejecutando: Event-driven V1...\n');
    [r4, n4, vf4, det4] = Strategy_event_driven_flexible_v1_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, max_cash_dia, debug);
                                                           
    fprintf('5/11 Ejecutando: Event-driven + Rebalanceo V1...\n');
    [r5, n5, vf5, det5] = Strategy_event_driven_rebal_flexible_v1_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, max_cash_dia, upper_abs, debug);
    
    fprintf('6/11 Ejecutando: Event-driven + Rebalanceo MM V1...\n');
    [r6, n6, vf6, det6] = Strategy_event_driven_rebal_mm_flexible_v1_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, MA_reb, max_cash_dia, upper_abs, debug);
    
    fprintf('7/11 Ejecutando: Event-driven + Cash Pool V1...\n');
    [r7, n7, vf7, det7] = Strategy_event_driven_rebal_cashpool_flexible_v1_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, max_cash_dia, upper_abs, debug);
    
    % === EVENT-DRIVEN V2 (SIN LIMITACIONES) ===
    fprintf('8/11 Ejecutando: Event-driven V2 (sin límites)...\n');
    [r8, n8, vf8, det8] = Strategy_event_driven_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, debug);
    
    fprintf('9/11 Ejecutando: Event-driven + Rebalanceo V2 (sin límites)...\n');
    [r9, n9, vf9, det9] = Strategy_event_driven_rebal_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, MA_reb, upper_abs, debug);
                                                                    
    fprintf('10/11 Ejecutando: Event-driven + Rebalanceo MM V2 (sin límites)...\n');
    [r10, n10, vf10, det10] = Strategy_event_driven_rebal_mm_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, MA_reb, upper_abs, debug);
    
    fprintf('11/11 Ejecutando: Event-driven + Cash Pool V2 (sin límites)...\n');
    [r11, n11, vf11, det11] = Strategy_event_driven_rebal_cashpool_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, upper_abs, debug);
    
    %% ===== EXTRAER MDD Y VOLATILIDAD DE CADA ESTRATEGIA =====
    det_list = {det1, det2, det3, det4, det5, det6, det7, det8, det9, det10, det11};
    mdd_valores = zeros(1, 11);
    vol_valores = zeros(1, 11);
    
    for i = 1:11
        current_det = det_list{i};
        if isstruct(current_det)
            % Extraer MDD
            if isfield(current_det, 'mdd') && ~isempty(current_det.mdd)
                mdd_valores(i) = current_det.mdd;
            elseif isfield(current_det, 'equity_series') && ~isempty(current_det.equity_series)
                equity_series = current_det.equity_series;
                if isvector(equity_series) && length(equity_series) > 1
                    mdd_valores(i) = calc_MDD(equity_series);
                else
                    mdd_valores(i) = NaN;
                end
            else
                mdd_valores(i) = NaN;
            end
            
            % Extraer Volatilidad Anualizada
            if isfield(current_det, 'annual_volatility') && ~isempty(current_det.annual_volatility)
                vol_valores(i) = current_det.annual_volatility;
            else
                vol_valores(i) = NaN;
            end
        else
            mdd_valores(i) = NaN;
            vol_valores(i) = NaN;
        end
    end
    
    %% ===== EXTRAER METRICAS DE APALANCAMIENTO Y CASH BAL =====
    % deuda_max_v2: V1=0; V2 toma abs(min_cash) si existe
    deuda_max_v2 = zeros(1, 11);
    % V2
    deuda_max_v2(8)  = (exist_field(det8,  'min_cash'))  * abs(safe_get(det8,  'min_cash'));
    deuda_max_v2(9)  = (exist_field(det9,  'min_cash'))  * abs(safe_get(det9,  'min_cash'));
    deuda_max_v2(10) = (exist_field(det10, 'min_cash'))  * abs(safe_get(det10, 'min_cash'));
    deuda_max_v2(11) = (exist_field(det11, 'min_cash'))  * abs(safe_get(det11, 'min_cash'));
    
    % Extraer cash_series de cada estrategia
    cash_balance = zeros(1, 11);
    for i = 1:11
        current_det = det_list{i};
        if isstruct(current_det)
            if isfield(current_det, 'cash_series')
                if isvector(current_det.cash_series) && ~isempty(current_det.cash_series)
                    cash_balance(i) = current_det.cash_series(end);  % Último valor
                elseif isscalar(current_det.cash_series)
                    cash_balance(i) = current_det.cash_series;
                else
                    % dejar en 0 si vacío
                end
            else
                % Para estrategias DCA simples que no manejan cash, el cash final es 0
                cash_balance(i) = 0;
            end
        end
    end

    %% ===== PREP: RENDIMIENTOS (CAGR) + SHARPE =====
    rendimientos = [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11];

    % Nombres de estrategias (se usan más abajo también)
    estrategias_nombres = {'Simple DCA', 'Simple + Rebalanceo', 'Simple + Rebal + MM', ...
                          'Event-driven V1', 'Event + Rebalanceo V1', 'Event + Rebal MM V1', 'Event + Cash Pool V1', ...
                          'Event-driven V2', 'Event + Rebalanceo V2', 'Event + Rebal MM V2', 'Event + Cash Pool V2'};

    % Saneado de volatilidades: evita 0 o negativos
    vol_bad = ~isfinite(vol_valores) | vol_valores<=0;
    vol_valores(vol_bad) = NaN;

    % Sharpe anual con rf fijo
    tipo_libre_riesgo = 0.025;  % 2.5% anual como referencia
    sharpe_ratios = nan(1, 11);
    for i = 1:11
        if isfinite(rendimientos(i)) && isfinite(vol_valores(i)) && vol_valores(i) > 0
            sharpe_ratios(i) = (rendimientos(i) - tipo_libre_riesgo) ./ vol_valores(i);
        end
    end
    
    %% ===== RESUMEN COMPARATIVO (CON SHARPE EN TABLA) =====
    fprintf('\n=== RESUMEN COMPARATIVO === Portfolio "%s" MA=%d Periodos=%d\n', portfolio_name, MA, periodos);
    fprintf('%-32s %9s %10s %14s %12s %16s %14s %5s %6s %8s\n', ...
        'Estrategia','CAGR','Aportes','Valor Final','Equity','Cash Final','Deuda Max','MDD','Sigma','Sharpe');
    fprintf('%s\n', repmat('-', 140, 1));
    
    valores_finales = [vf1, vf2, vf3, vf4, vf5, vf6, vf7, vf8, vf9, vf10, vf11];
    estrategias_data = {
        'Simple DCA', r1, n1, vf1, cash_balance(1), deuda_max_v2(1), mdd_valores(1), vol_valores(1), sharpe_ratios(1);
        'Simple + Rebalanceo', r2, n2, vf2, cash_balance(2), deuda_max_v2(2), mdd_valores(2), vol_valores(2), sharpe_ratios(2);
        'Simple + Rebal + MM', r3, n3, vf3, cash_balance(3), deuda_max_v2(3), mdd_valores(3), vol_valores(3), sharpe_ratios(3);
        '--- EVENT-DRIVEN V1 (SIN DEUDA) ---', NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN;
        'Event-driven V1', r4, n4, vf4, cash_balance(4), deuda_max_v2(4), mdd_valores(4), vol_valores(4), sharpe_ratios(4);
        'Event + Rebalanceo V1', r5, n5, vf5, cash_balance(5), deuda_max_v2(5), mdd_valores(5), vol_valores(5), sharpe_ratios(5);
        'Event + Rebal MM V1', r6, n6, vf6, cash_balance(6), deuda_max_v2(6), mdd_valores(6), vol_valores(6), sharpe_ratios(6);
        'Event + Cash Pool V1', r7, n7, vf7, cash_balance(7), deuda_max_v2(7), mdd_valores(7), vol_valores(7), sharpe_ratios(7);
        '--- EVENT-DRIVEN V2 (CON DEUDA) ---', NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN;
        'Event-driven V2', r8, n8, vf8, cash_balance(8), deuda_max_v2(8), mdd_valores(8), vol_valores(8), sharpe_ratios(8);
        'Event + Rebalanceo V2', r9, n9, vf9, cash_balance(9), deuda_max_v2(9), mdd_valores(9), vol_valores(9), sharpe_ratios(9);
        'Event + Rebal MM V2', r10, n10, vf10, cash_balance(10), deuda_max_v2(10), mdd_valores(10), vol_valores(10), sharpe_ratios(10);
        'Event + Cash Pool V2', r11, n11, vf11, cash_balance(11), deuda_max_v2(11), mdd_valores(11), vol_valores(11), sharpe_ratios(11);
    };
    
    for i = 1:size(estrategias_data, 1)
        if isnan(estrategias_data{i,2})
            fprintf('%-35s %s\n', estrategias_data{i,1}, repmat('-', 104, 1));
        else
            valor_final = estrategias_data{i,4};
            cash_final  = estrategias_data{i,5};
            equity      = valor_final + cash_final;
            mdd_val     = estrategias_data{i,7};
            vol_val     = estrategias_data{i,8};
            sh_val      = estrategias_data{i,9};
            
            if isnan(mdd_val), mdd_str = 'N/A'; else, mdd_str = sprintf('%.1f%%', mdd_val*100); end
            if isnan(vol_val), vol_str = 'N/A'; else, vol_str = sprintf('%.1f%%', vol_val*100); end
            if isnan(sh_val),  sh_str  = 'N/A'; else, sh_str  = sprintf('%.2f', sh_val); end
            
            fprintf('%-35s %6.2f%% %8d %11.0f EUR %11.0f EUR %9.0f EUR %9.0f EUR %7s %6s %8s\n', ...
                estrategias_data{i,1}, estrategias_data{i,2}*100, estrategias_data{i,3}, ...
                valor_final, equity, cash_final, estrategias_data{i,6}, mdd_str, vol_str, sh_str);
        end
    end

    %% ===== ANALISIS DE MEJORAS V1 -> V2 =====
    if (debug==true)
        fprintf('\n=== ANALISIS DE MEJORAS V1 -> V2 ===\n');
        mejoras_cagr = [(r8-r4)*100, (r9-r5)*100, (r10-r6)*100, (r11-r7)*100];
        mejoras_valor = [vf8-vf4, vf9-vf5, vf10-vf6, vf11-vf7];
        mejoras_mdd = [(mdd_valores(8)-mdd_valores(4))*100, (mdd_valores(9)-mdd_valores(5))*100, ...
                       (mdd_valores(10)-mdd_valores(6))*100, (mdd_valores(11)-mdd_valores(7))*100];
        mejoras_vol = [(vol_valores(8)-vol_valores(4))*100, (vol_valores(9)-vol_valores(5))*100, ...
                       (vol_valores(10)-vol_valores(6))*100, (vol_valores(11)-vol_valores(7))*100];

        fprintf('Event-driven básico:      V1=%.2f%% -> V2=%.2f%% (+%.2fpp, +%.0f EUR, MDD: %.1f%% -> %.1f%%, Vol: %.1f%% -> %.1f%%)\n', ...
            r4*100, r8*100, mejoras_cagr(1), mejoras_valor(1), mdd_valores(4)*100, mdd_valores(8)*100, vol_valores(4)*100, vol_valores(8)*100);
        fprintf('Event + Rebalanceo:       V1=%.2f%% -> V2=%.2f%% (+%.2fpp, +%.0f EUR, MDD: %.1f%% -> %.1f%%, Vol: %.1f%% -> %.1f%%)\n', ...
            r5*100, r9*100, mejoras_cagr(2), mejoras_valor(2), mdd_valores(5)*100, mdd_valores(9)*100, vol_valores(5)*100, vol_valores(9)*100);
        fprintf('Event + Rebal MM:         V1=%.2f%% -> V2=%.2f%% (+%.2fpp, +%.0f EUR, MDD: %.1f%% -> %.1f%%, Vol: %.1f%% -> %.1f%%)\n', ...
            r6*100, r10*100, mejoras_cagr(3), mejoras_valor(3), mdd_valores(6)*100, mdd_valores(10)*100, vol_valores(6)*100, vol_valores(10)*100);
        fprintf('Event + Cash Pool:        V1=%.2f%% -> V2=%.2f%% (+%.2fpp, +%.0f EUR, MDD: %.1f%% -> %.1f%%, Vol: %.1f%% -> %.1f%%)\n', ...
            r7*100, r11*100, mejoras_cagr(4), mejoras_valor(4), mdd_valores(7)*100, mdd_valores(11)*100, vol_valores(7)*100, vol_valores(11)*100);              
    end
    
    %% ===== MEJOR ESTRATEGIA GENERAL =====
    [mejor_r, idx_mejor] = max(rendimientos);

    % Mapear categoría por índice
    if idx_mejor <= 3
        categoria = 'DCA';
    elseif idx_mejor <= 7
        categoria = 'Event-Driven V1';
    else
        categoria = 'Event-Driven V2';
    end

    fprintf('\n=== MEJOR ESTRATEGIA ===\n');
    fprintf('🏆 %s (%s)\n', estrategias_nombre_por_indice(idx_mejor), categoria);
    fprintf('CAGR: %.2f%% | Valor Final: %.0f EUR | Cash Final: %.0f EUR | Deuda Máxima: %.0f EUR | MDD: %.1f%% | Vol: %.1f%% | Sharpe: %.2f\n', ...
        mejor_r*100, valores_finales(idx_mejor), cash_balance(idx_mejor), deuda_max_v2(idx_mejor), ...
        mdd_valores(idx_mejor)*100, vol_valores(idx_mejor)*100, sharpe_ratios(idx_mejor));
    
    %% ===== MEJOR ESTRATEGIA POR SHARPE RATIO =====
    valid_sh = find(~isnan(sharpe_ratios));
    if ~isempty(valid_sh)
        [mejor_sharpe, rel_idx] = max(sharpe_ratios(valid_sh));
        idx_mejor_sharpe = valid_sh(rel_idx);
        if idx_mejor_sharpe ~= idx_mejor
            fprintf('\n=== MEJOR ESTRATEGIA AJUSTADA POR RIESGO (SHARPE) ===\n');
            fprintf('🎯 %s\n', estrategias_nombres{idx_mejor_sharpe});
            fprintf('CAGR: %.2f%% | Vol: %.1f%% | Sharpe: %.2f | MDD: %.1f%%\n', ...
                rendimientos(idx_mejor_sharpe)*100, vol_valores(idx_mejor_sharpe)*100, ...
                mejor_sharpe, mdd_valores(idx_mejor_sharpe)*100);
        end
    end
    
    %% ===== ANALISIS DEUDA vs RENDIMIENTO =====
    if debug==true
        fprintf('\n=== ANALISIS DEUDA vs RENDIMIENTO ===\n');
        fprintf('Estrategias V2 con mayor apalancamiento:\n');
        [~, idx_deuda] = sort(deuda_max_v2(8:11), 'descend');
        estrategias_v2 = {'Event-driven V2', 'Event + Rebalanceo V2', 'Event + Rebal MM V2', 'Event + Cash Pool V2'};
        rendimientos_v2 = [r8, r9, r10, r11];
        cash_balance_v2 = cash_balance(8:11);
        mdd_v2 = mdd_valores(8:11);
        vol_v2 = vol_valores(8:11);
        
        for i = 1:4
            idx = idx_deuda(i);
            fprintf('  %s: %.2f%% CAGR, %.0f EUR cash final, %.0f EUR deuda máxima, %.1f%% MDD, %.1f%% Vol\n', ...
                estrategias_v2{idx}, rendimientos_v2(idx)*100, cash_balance_v2(idx), deuda_max_v2(7+idx), mdd_v2(idx)*100, vol_v2(idx)*100);
        end
        
        %% ===== ANALISIS RIESGO-RETORNO =====
        fprintf('\n=== ANALISIS RIESGO-RETORNO ===\n');
        fprintf('Estrategias ordenadas por mejor ratio Rendimiento/MDD:\n');
        ratio_riesgo_retorno = rendimientos ./ mdd_valores;
        ratio_validos = ratio_riesgo_retorno(~isnan(ratio_riesgo_retorno));
        [~, idx_ratio] = sort(ratio_validos, 'descend');
        
        % Mapear índices originales a la lista filtrada ratio_validos
        idx_no_nan = find(~isnan(ratio_riesgo_retorno));
        for i = 1:min(5, length(idx_ratio))  % Top 5
            orig_idx = idx_no_nan(idx_ratio(i));
            fprintf('  %d. %s: %.2f%% CAGR / %.1f%% MDD = %.2f ratio\n', ...
                i, estrategias_nombres{orig_idx}, rendimientos(orig_idx)*100, mdd_valores(orig_idx)*100, ratio_riesgo_retorno(orig_idx));
        end
    end

    %% ===== CONCLUSIONES =====
    if debug == true 
       fprintf('\n=== CONCLUSIONES ===\n');
       % Estas variables se definen en el bloque de mejoras (también bajo debug==true)
       % mejora_promedio = mean(mejoras_cagr); 
       % mejora_mdd_promedio = mean(mejoras_mdd);
       % mejora_vol_promedio = mean(mejoras_vol);
       % (Si quieres usarlas aquí, mueve su cálculo fuera o repítelo.)
       fprintf('Resumen mostrado arriba. Ajusta "debug=true" para detalles adicionales.\n');
       
        if max(deuda_max_v2(8:11)) > 15000
            fprintf('Atención: Algunas estrategias V2 requieren apalancamiento >15k EUR\n');
        end
        
        mejor_dca = max([r1, r2, r3]);
        mejor_event = max(rendimientos(4:end));
       
        % Comparar también MDDs y volatilidades
        idx_mejor_dca = find([r1, r2, r3] == mejor_dca, 1);
        mdd_mejor_dca = mdd_valores(idx_mejor_dca);
        vol_mejor_dca = vol_valores(idx_mejor_dca);
        
        idx_mejor_event_rel = find(rendimientos(4:end) == mejor_event, 1);
        idx_mejor_event = idx_mejor_event_rel + 3;
        mdd_mejor_event = mdd_valores(idx_mejor_event);
        vol_mejor_event = vol_valores(idx_mejor_event);
        
        if mejor_event > mejor_dca
            fprintf('🎯 Event-driven supera a DCA: %.2f%% vs %.2f%% (+%.2fpp)\n', ...
                mejor_event*100, mejor_dca*100, (mejor_event-mejor_dca)*100);
            fprintf('   Riesgo: MDD %.1f%% vs %.1f%%, Vol %.1f%% vs %.1f%%\n', ...
                mdd_mejor_event*100, mdd_mejor_dca*100, vol_mejor_event*100, vol_mejor_dca*100);
        else
            fprintf('📊 DCA sigue siendo competitivo frente a event-driven\n');
        end
    end
    
    fprintf('\n=== EJECUCION COMPLETADA ===\n');
    
catch ME
    fprintf('❌ Error durante la ejecución: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('Línea del error: %d\n', ME.stack(1).line);
    end
    
    % Verificar archivos CSV nuevamente
    fprintf('\nVerificando archivos...\n');
    for i = 1:length(tickers_config)
        ticker = tickers_config{i};
        archivo = fullfile(basePath, [ticker '_yahoo.csv']);
        if isfile(archivo)
            fprintf('✅ %s\n', [ticker '_yahoo.csv']);
        else
            fprintf('❌ FALTA: %s\n', [ticker '_yahoo.csv']);
        end
    end
end

end % function main

%% ===================== HELPERS LOCALES =====================
function mdd = calc_MDD(equity_series)
    % equity_series: vector fila/columna con el valor total de la cartera en el tiempo
    equity_series = equity_series(:);
    if numel(equity_series) < 2
        mdd = NaN;
        return;
    end
    max_run = cummax(equity_series);                 % máximo acumulado
    dd = (equity_series - max_run) ./ max_run;       % drawdown relativo (<=0)
    mdd = abs(min(dd));                              % como porcentaje positivo
end

function tf = exist_field(s, f)
    tf = isstruct(s) && isfield(s, f) && ~isempty(s.(f));
end

function v = safe_get(s, f)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
        v = s.(f);
    else
        v = 0;
    end
end

function name = estrategias_nombre_por_indice(idx)
    nombres = {'Simple DCA', 'Simple + Rebalanceo', 'Simple + Rebal + MM', ...
               'Event-driven V1', 'Event + Rebalanceo V1', 'Event + Rebal MM V1', 'Event + Cash Pool V1', ...
               'Event-driven V2', 'Event + Rebalanceo V2', 'Event + Rebal MM V2', 'Event + Cash Pool V2'};
    name = nombres{idx};
end
