function [r, num_aportaciones, valor_final_total, detalle] = Strategy_simple_DCA_flexible_sigma(periodos, basePath, tickers_config, weights_config, debug)
% Portfolio DCA simple flexible - VOL por retornos TWR y MDD por equity
% Cambios mínimos:
% - r_port (time-weighted) calculado ANTES de aportar
% - Vol anualizada desde r_port (std * sqrt(252))
% - MDD sigue desde equity_series
% - Se añade detalle.ret_series

%% ======== Validación de parámetros ========
if nargin < 3 || isempty(tickers_config)
    error('Debes especificar los tickers del portfolio');
end

if nargin < 4 || isempty(weights_config)
    weights_config = ones(1, length(tickers_config)) / length(tickers_config);
end

if nargin < 1, periodos = 5; end
if nargin < 2 || isempty(basePath), basePath = 'C:\Users\israe\OneDrive\Matlab_scripts\'; end
if nargin < 5 || isempty(debug), debug = false; end

% Validaciones
if length(tickers_config) ~= length(weights_config)
    error('Numero de tickers (%d) debe coincidir con numero de pesos (%d)', ...
        length(tickers_config), length(weights_config));
end

if abs(sum(weights_config) - 1.0) > 1e-6
    error('Los pesos deben sumar 1.0. Suma actual: %.6f', sum(weights_config));
end

%% ======== Parámetros de estrategia ========
dinero_inicial          = 1000;
aportacion_total_mes    = 1500;
dias_por_aporte         = 21;

num_activos = length(tickers_config);
w = weights_config(:);

%% ======== Verificación de archivos ========
file_paths = cell(num_activos, 1);
for i = 1:num_activos
    ticker = tickers_config{i};
    file_paths{i} = fullfile(basePath, [ticker '_yahoo.csv']);
    if ~isfile(file_paths{i})
        error('Falta archivo: %s. Ejecuta main_vYahoo.m primero.', file_paths{i});
    end
end

%% ======== Lectura de precios ========
series_data = cell(num_activos, 1);
dates_data = cell(num_activos, 1);

for i = 1:num_activos
    [series_data{i}, dates_data{i}] = read_yahoo_csv(file_paths{i});
end

%% ======== Alinear por fechas comunes ========
TT_list = cell(num_activos, 1);
for i = 1:num_activos
    TT_list{i} = timetable(dates_data{i}, series_data{i}, 'VariableNames', {tickers_config{i}});
end

if num_activos == 1
    TT = TT_list{1};
else
    TT = synchronize(TT_list{:}, 'intersection');
end
TT = rmmissing(TT);

if height(TT) == 0
    error('No quedan fechas comunes entre las series tras la interseccion.');
end

dates = TT.Properties.RowTimes;
series = table2array(TT);

%% ======== Ventana temporal ========
N_total = size(series, 1);
N_dias  = min(N_total, round(252*periodos));
series = series(end-N_dias+1:end, :);
dates = dates(end-N_dias+1:end);

%% ======== Setup para tracking completo ========
fechas_aport = 1:dias_por_aporte:N_dias;
num_aportaciones = numel(fechas_aport);
aportacion_por_activo = aportacion_total_mes * w;

% Acumulación de acciones/unidades
acc = zeros(num_activos, 1);

% Arrays de tracking
equity_series = zeros(N_dias, 1);                % equity día a día (con aportaciones)
valor_activos_series = zeros(N_dias, num_activos);
r_port = nan(N_dias,1);                           % retorno diario TWR (sin aportaciones del día)
precios_prev = series(1, :).';                    % precios día anterior para r_port

% Compra inicial (día 1) por pesos configurados
if dinero_inicial > 0
    init_por_activo = dinero_inicial * w;
    precios_d1 = series(1, :).';
    acc = acc + (init_por_activo ./ precios_d1);
end

% Tracking de aportaciones
detalle.fechas = dates(fechas_aport);
detalle.compras = zeros(num_aportaciones, num_activos);

%% ======== BUCLE PRINCIPAL CON TWR ========
aporte_idx = 1;

for dia = 1:N_dias
    precios_dia = series(dia, :).';

    % --- Retorno TWR ANTES de aportar ---
    if dia == 1
        r_port(dia) = NaN; % sin retorno el primer día
    else
        valor_inicio = sum(acc .* precios_prev); % sin flujos del día
        if valor_inicio > 0
            r_port(dia) = (sum(acc .* precios_dia) - sum(acc .* precios_prev)) / valor_inicio;
        else
            r_port(dia) = 0; % o NaN si prefieres
        end
    end

    % --- Aportación DESPUÉS de medir el retorno del día ---
    if aporte_idx <= length(fechas_aport) && dia == fechas_aport(aporte_idx)
        compra_unidades = aportacion_por_activo ./ precios_dia;
        acc = acc + compra_unidades;

        % Guardar detalles de compra
        detalle.compras(aporte_idx, :) = compra_unidades.';
        aporte_idx = aporte_idx + 1;
    end

    % Tracking de valores y equity (incluye la aportación del propio día)
    valores_dia = acc .* precios_dia;
    valor_activos_series(dia, :) = valores_dia.';
    equity_series(dia) = sum(valores_dia);

    % Actualizar precios_prev
    precios_prev = precios_dia;
end

%% ======== Valor final y métricas ========
precios_ult = series(end, :).';
valores = acc .* precios_ult;
valor_final_total = sum(valores);
pesos_finales = valores / valor_final_total;

%% ======== CAGR por IRR ========
aportes  = [dinero_inicial, repmat(aportacion_total_mes, 1, num_aportaciones)];
t_anios  = [0, (fechas_aport-1) * 365/252];
tiempos  = periodos - t_anios/365;

funcion_CAGR = @(rr) sum(aportes .* (1 + rr).^tiempos) - valor_final_total;
try
    fL = funcion_CAGR(-0.99); fR = funcion_CAGR(10);
    if ~isfinite(fL) || ~isfinite(fR)
        r = fzero(funcion_CAGR, 0.1);
    else
        r = fzero(funcion_CAGR, [-0.99, 10]);
    end
catch
    r = fzero(funcion_CAGR, 0.1);
end

%% ======== MDD (equity) y VOL (TWR) ========
mdd_val = calc_MDD_only(equity_series);
valid_r = r_port(~isnan(r_port));
daily_std = std(valid_r, 'omitnan');
annual_vol = daily_std * sqrt(252);

%% ======== Detalle estructurado con series temporales ========
acciones_struct = struct();
valores_struct = struct();
pesos_struct = struct();

for i = 1:num_activos
    ticker_clean = matlab.lang.makeValidName(tickers_config{i});
    acciones_struct.(ticker_clean) = acc(i);
    valores_struct.(ticker_clean) = valores(i);
    pesos_struct.(ticker_clean) = pesos_finales(i);
end

detalle.acciones = acciones_struct;
detalle.valor_por_activo = valores_struct;
detalle.peso_por_activo = pesos_struct;

% Series temporales y métricas
detalle.equity_series = equity_series;           % serie diaria de equity total
detalle.valor_activos_series = valor_activos_series;
detalle.dates_series = dates;
detalle.ret_series = r_port;                     % *** NUEVO: retornos diarios TWR
detalle.mdd = mdd_val;
detalle.annual_volatility = annual_vol;

detalle.params = struct('periodos', periodos, 'aportacion_total_mes', aportacion_total_mes, ...
                       'dinero_inicial', dinero_inicial, 'tickers', {tickers_config}, ...
                       'weights', weights_config, 'num_activos', num_activos);

%% ======== Salida por pantalla ========
if ~debug
    fprintf('=====================================================================================================================\n');
    fprintf('Portfolio DCA simple (%s) | %d anos | CAGR: %.2f%% | Aportes: %d | Valor final: %.2f\n', ...
            strjoin(tickers_config, '/'), periodos, r*100, num_aportaciones, valor_final_total);
    fprintf('Desglose por activo a %s:\n', datestr(dates(end), 'yyyy-mm-dd'));
    for i = 1:num_activos
        fprintf('  %s: %.2f EUR (%.2f%%)\n', tickers_config{i}, valores(i), 100*pesos_finales(i));
    end
    fprintf('  TOTAL: %.2f EUR (100%%)\n', valor_final_total);
    fprintf('=====================================================================================================================\n');
else
    fprintf('=====================================================================================================================\n');
    fprintf('Portfolio DCA Simple Flexible | Sin rebalanceo\n');
    fprintf('Tickers: %s\n', strjoin(tickers_config, ', '));
    fprintf('Pesos objetivo: %s\n', sprintf('%.1f%% ', weights_config*100));
    fprintf('Periodo: %d anos | Aportacion mensual: %.0f EUR | Inversion inicial: %.0f EUR\n', ...
            periodos, aportacion_total_mes, dinero_inicial);
    fprintf('MDD calculado: %.2f%% | Volatilidad anual (TWR): %.2f%%\n', mdd_val*100, annual_vol*100);
    fprintf('---------------------------------------------------------------------------------------------------------------------\n');
    fprintf('RESULTADOS:\n');
    fprintf('  CAGR (IRR): %.2f%%\n', r*100);
    fprintf('  Numero de aportaciones: %d\n', num_aportaciones);
    fprintf('  Valor final total: %.2f EUR\n', valor_final_total);
    fprintf('  Maximum Drawdown: %.2f%%\n', mdd_val*100);
    fprintf('  Volatilidad anualizada (TWR): %.2f%%\n', annual_vol*100);
    fprintf('---------------------------------------------------------------------------------------------------------------------\n');
    fprintf('DESGLOSE POR ACTIVO a %s:\n', datestr(dates(end), 'yyyy-mm-dd'));
    for i = 1:num_activos
        fprintf('  %s: %.2f EUR (%.2f%%) - %.4f unidades | Objetivo: %.1f%%\n', ...
            tickers_config{i}, valores(i), 100*pesos_finales(i), acc(i), weights_config(i)*100);
    end
    fprintf('  TOTAL: %.2f EUR (100%%)\n', valor_final_total);
    fprintf('=====================================================================================================================\n');
end

end

% ========================= HELPERS =========================
function [close_prices, dates] = read_yahoo_csv(csvPath)
    T = readtable(csvPath);
    if isempty(T) || width(T)==0 || height(T)==0
        error('CSV vacio o sin filas: %s', csvPath);
    end
    names = lower(strrep(strrep(T.Properties.VariableNames,'_',''),' ',''));    
    % Fecha
    iDate = find(strcmp(names,'date'),1); if isempty(iDate), iDate = 1; end
    dates = T{:,iDate};
    if ~isdatetime(dates)
        if isnumeric(dates)
            dates = datetime(dates,'ConvertFrom','datenum');
        elseif iscellstr(dates) || isstring(dates)
            try, dates = datetime(dates,'InputFormat','yyyy-MM-dd','Locale','en_US'); catch, dates = datetime(dates); end
        else
            dates = datetime(dates);
        end
    end
    % Precio (AdjClose > Close)
    iAdj   = find(strcmp(names,'adjclose'),1);
    iClose = find(strcmp(names,'close'),1);
    if ~isempty(iAdj)
        y = T{:,iAdj};
    elseif ~isempty(iClose)
        y = T{:,iClose};
    else
        y = T{:,end};
        warning('No AdjClose/Close en %s, usada ultima columna.', csvPath);
    end
    if iscellstr(y) || isstring(y), y = str2double(strrep(string(y),',','.')); end
    if ~isfloat(y), y = double(y); end
    % Limpiar y ordenar
    good = ~isnat(dates) & ~isnan(y);
    dates = dates(good); y = y(good);
    [dates, idx] = sort(dates);
    close_prices = y(idx);
    close_prices = close_prices(:); dates = dates(:);
end

function mdd = calc_MDD_only(equity_series)
    equity_series = equity_series(:);
    if numel(equity_series) < 2
        mdd = NaN;
        return;
    end
    max_run = cummax(equity_series);
    dd = (equity_series - max_run) ./ max_run;
    mdd = abs(min(dd));
end
