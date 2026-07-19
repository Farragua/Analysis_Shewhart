function main_portfolio_flexible_calmar(portfolio_name, tickers_config, weights_config, basePath, periodos, MA, weight_limits, max_cash_dia, MA_reb, z_engine, n_boll)
% MAIN PORTFOLIO FLEXIBLE V10 MDD + VOL + SHARPE + CALMAR EN TABLA (COMPACTA)
% Compara DCA vs Event-driven V1/V2. Muestra MDD, Vol anualizada, Sharpe y Calmar en la tabla principal.

%% ===== VALIDACION DE PARAMETROS =====
if nargin < 1 || isempty(portfolio_name), error('Debes especificar el nombre del portfolio'); end
if nargin < 2 || isempty(tickers_config), error('Debes especificar los tickers del portfolio'); end
if nargin < 3 || isempty(weights_config), weights_config = ones(1, length(tickers_config)) / length(tickers_config); end
if nargin < 4 || isempty(basePath), basePath = 'C:\Users\israe\OneDrive\Matlab_scripts\'; end
if nargin < 5 || isempty(periodos), periodos = 1; end
if nargin < 6 || isempty(MA), MA = 150; end

%% ===== NORMALIZACION PARA N==1 Y ENTRADAS ESCALARES =====
if ischar(tickers_config) || isstring(tickers_config), tickers_config = cellstr(tickers_config); end
n = numel(tickers_config);
weights_config = weights_config(:).';
if numel(weights_config)==1 && n>1, weights_config = repmat(weights_config, 1, n); end
if n==1, weights_config = 1; end
if abs(sum(weights_config) - 1.0) > 1e-6, error('Los pesos deben sumar 1.0. Suma actual: %.6f', sum(weights_config)); end

if nargin < 7 || isempty(weight_limits)
    if n==1, weight_limits = 1; else, weight_limits = 0.30; end
end
if isscalar(weight_limits), weight_limits = repmat(weight_limits, 1, n); end
upper_abs = reshape(weight_limits, 1, []);

%% ===== CONFIGURACION =====
z_threshold = -2.0;
debug = false;

%% ===== VERIFICAR ARCHIVOS =====
fprintf('Verificando archivos para portfolio "%s"...\n', portfolio_name);
archivos_faltantes = {};
for i = 1:length(tickers_config)
    archivo = fullfile(basePath, [tickers_config{i} '_yahoo.csv']);
    if ~isfile(archivo), archivos_faltantes{end+1} = [tickers_config{i} '_yahoo.csv']; end %#ok<AGROW>
end
if ~isempty(archivos_faltantes)
    fprintf('❌ ARCHIVOS FALTANTES:\n'); for i = 1:length(archivos_faltantes), fprintf('   %s\n', archivos_faltantes{i}); end
    fprintf('\nEjecuta main_vYahoo.m primero para descargar estos tickers.\n'); return;
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
    fprintf('10/11 Ejecutando: Event-driven + Rebal MM V2 (sin límites)...\n');
    [r10, n10, vf10, det10] = Strategy_event_driven_rebal_mm_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, MA_reb, upper_abs, debug);
    fprintf('11/11 Ejecutando: Event-driven + Cash Pool V2 (sin límites)...\n');
    [r11, n11, vf11, det11] = Strategy_event_driven_rebal_cashpool_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, upper_abs, debug);

    %% ===== EXTRAER METRICAS =====
    det_list = {det1,det2,det3,det4,det5,det6,det7,det8,det9,det10,det11};
    mdd_valores = zeros(1,11); vol_valores = zeros(1,11);
    for i=1:11
        d = det_list{i};
        if isstruct(d)
            if isfield(d,'mdd') && ~isempty(d.mdd), mdd_valores(i)=d.mdd; end
            if isfield(d,'annual_volatility') && ~isempty(d.annual_volatility), vol_valores(i)=d.annual_volatility; end
        end
    end
    deuda_max_v2 = zeros(1,11);
    deuda_max_v2(8:11) = cellfun(@(d) abs(safe_get(d,'min_cash')), det_list(8:11));
    cash_balance = cellfun(@(d) safe_get_last(d,'cash_series'), det_list);

    %% ===== INDICADORES =====
    rendimientos = [r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11];
    aportes      = [n1 n2 n3 n4 n5 n6 n7 n8 n9 n10 n11];
    valores_fin  = [vf1 vf2 vf3 vf4 vf5 vf6 vf7 vf8 vf9 vf10 vf11];
    rf = 0.025;
    sharpe_ratios = (rendimientos - rf) ./ vol_valores;
    calmar_ratios = rendimientos ./ mdd_valores;

    %% ===== TABLA COMPACTA Y ALINEADA =====
    sep = repmat('-', 130, 1);
    fprintf('\n=== RESUMEN COMPARATIVO === Portfolio "%s" MA=%d Periodos=%d\n', portfolio_name, MA, periodos);
    fprintf('%-30s %7s %7s %14s %14s %12s %12s %6s %6s %7s %7s\n', ...
        'Estrategia','CAGR','Aportes','ValorFin','Equity','Cash','Deuda','MDD','Sigma','Sharpe','Calmar');
    fprintf('%s\n', sep);

    % Bloques y nombres
    nombres = { ...
        'Simple DCA', 'Simple + Rebalanceo', 'Simple + Rebal + MM', ...
        '--- EVENT-DRIVEN V1 (SIN DEUDA) ---', ...
        'Event-driven V1','Event + Rebalanceo V1','Event + Rebal MM V1','Event + Cash Pool V1', ...
        '--- EVENT-DRIVEN V2 (CON DEUDA) ---', ...
        'Event-driven V2','Event + Rebalanceo V2','Event + Rebal MM V2','Event + Cash Pool V2'};

    % Índices de filas “reales” dentro de los arrays de métricas
    idx_metric = [1 2 3 NaN 4 5 6 7 NaN 8 9 10 11];

    for k = 1:numel(nombres)
        nombre = nombres{k};
        if contains(nombre,'---')
            fprintf('%-30s %s\n', nombre, repmat('-', 97, 1));
            continue;
        end
        i = idx_metric(k);
        valF   = valores_fin(i);
        cashF  = cash_balance(i);
        equity = valF + cashF;

        % Strings seguros (con unidades y %)
        cagr_str  = fmt_pct(rendimientos(i));
        aport_str = sprintf('%d', aportes(i));
        vfin_str  = sprintf('%d EUR', round(valF));
        eqty_str  = sprintf('%d EUR', round(equity));
        cash_str  = sprintf('%d EUR', round(cashF));
        deuda_str = sprintf('%d EUR', round(deuda_max_v2(i)));
        mdd_str   = fmt_pct(mdd_valores(i));
        vol_str   = fmt_pct(vol_valores(i));
        shrp_str  = fmt_num(sharpe_ratios(i));
        calm_str  = fmt_num(calmar_ratios(i));

        fprintf('%-30s %7s %7s %14s %14s %12s %12s %6s %6s %7s %7s\n', ...
            nombre, cagr_str, aport_str, vfin_str, eqty_str, cash_str, deuda_str, mdd_str, vol_str, shrp_str, calm_str);
    end

    fprintf('%s\n=== EJECUCION COMPLETADA ===\n', sep);

catch ME
    fprintf('❌ Error durante la ejecución: %s\n', ME.message);
    if ~isempty(ME.stack), fprintf('Línea del error: %d\n', ME.stack(1).line); end
    fprintf('\nVerificando archivos...\n');
    for i = 1:length(tickers_config)
        archivo = fullfile(basePath, [tickers_config{i} '_yahoo.csv']);
        if isfile(archivo), fprintf('✅ %s\n', [tickers_config{i} '_yahoo.csv']); else, fprintf('❌ FALTA: %s\n', [tickers_config{i} '_yahoo.csv']); end
    end
end

end % function main

%% ===================== HELPERS LOCALES =====================
function mdd = calc_MDD(equity_series)
    equity_series = equity_series(:);
    if numel(equity_series) < 2, mdd = NaN; return; end
    max_run = cummax(equity_series);
    dd = (equity_series - max_run) ./ max_run;
    mdd = abs(min(dd));
end

function v = safe_get(s, f)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = 0; end
end

function v = safe_get_last(s, f)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
        x = s.(f);
        if ~isempty(x), v = x(end); else, v = 0; end
    else
        v = 0;
    end
end

function s = fmt_pct(x)
    if ~isfinite(x) || x<=0, s = ' N/A '; else, s = sprintf('%.1f%%', x*100); end
end

function s = fmt_num(x)
    if ~isfinite(x), s = '  N/A '; else, s = sprintf('%.2f', x); end
end
