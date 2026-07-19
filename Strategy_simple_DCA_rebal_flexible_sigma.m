function [r, num_aportaciones, valor_final_total, detalle] = Strategy_simple_DCA_rebal_flexible_sigma(periodos, basePath, tickers_config, weights_config, upper_abs, debug)
% Portfolio DCA + Rebalanceo SUAVE flexible
% CAMBIOS MÍNIMOS:
% - Añadido r_port (retorno diario TWR) calculado ANTES de aportar/rebalancear
% - Volatilidad anualizada desde r_port (std * sqrt(252))
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
if nargin < 5 || isempty(upper_abs), upper_abs = 0.30 * ones(1, length(tickers_config)); end
if nargin < 6 || isempty(debug), debug = false; end

% Validaciones
num_activos = length(tickers_config);
if length(weights_config) ~= num_activos
    error('Numero de tickers (%d) debe coincidir con numero de pesos (%d)', num_activos, length(weights_config));
end

if abs(sum(weights_config) - 1.0) > 1e-6
    error('Los pesos deben sumar 1.0. Suma actual: %.6f', sum(weights_config));
end

if length(upper_abs) == 1
    upper_abs = repmat(upper_abs, 1, num_activos);
elseif length(upper_abs) ~= num_activos
    error('Numero de techos (%d) debe coincidir con numero de activos (%d)', length(upper_abs), num_activos);
end

%% ======== Parámetros de estrategia ========
dinero_inicial          = 1000;
aportacion_total_mes    = 1500;
dias_por_aporte         = 21;

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
aport_por_activo = (aportacion_total_mes * w);

% Acumulación de unidades
acc = zeros(num_activos, 1);

% Arrays de tracking (equity para MDD; r_port para VOL)
equity_series = zeros(N_dias, 1);
r_port = nan(N_dias,1);                 % retorno diario TWR (sin flujos del día)
precios_prev = series(1, :).';          % precios del día anterior para r_port

% Compra inicial por pesos configurados
if dinero_inicial > 0
    init = dinero_inicial .* w;
    precios_d1 = series(1, :).';
    acc = acc + (init ./ precios_d1);
end

% Trazas
detalle.fechas         = dates(fechas_aport);
detalle.compras        = zeros(num_aportaciones, num_activos);
detalle.rebals         = false(num_aportaciones,1);
detalle.cash_from_sell = zeros(num_aportaciones,1);
detalle.cash_to_buy    = zeros(num_aportaciones,1);
detalle.over_assets    = cell(num_aportaciones,1);

% Metricas de bandas
sobre_techo_hist   = false(num_aportaciones, num_activos);
pesos_pre_hist     = zeros(num_aportaciones, num_activos);
activaciones_count = zeros(num_activos, 1);

%% ======== BUCLE PRINCIPAL CON TWR ========
aporte_idx = 1;

for dia = 1:N_dias
    precios_dia = series(dia, :).';

    % --- (1) Retorno TWR ANTES de aportar/rebalancear ---
    if dia == 1
        r_port(dia) = NaN; % sin retorno el primer día
    else
        valor_inicio = sum(acc .* precios_prev); % valor al inicio SIN flujos del día
        if valor_inicio > 0
            r_port(dia) = (sum(acc .* precios_dia) - sum(acc .* precios_prev)) / valor_inicio;
        else
            r_port(dia) = 0; % o NaN si prefieres
        end
    end

    % --- (2) Día de aportación (DCA) + posible rebalanceo por techos ---
    if aporte_idx <= length(fechas_aport) && dia == fechas_aport(aporte_idx)
        % 2.1) DCA por pesos configurados (después de medir r_port)
        compra_unidades = aport_por_activo ./ precios_dia;
        acc = acc + compra_unidades;
        detalle.compras(aporte_idx, :) = compra_unidades.';

        % 2.2) Estado PRE-rebalanceo
        valores = acc .* precios_dia;
        total   = sum(valores);
        pesos   = valores / total;
        target  = total .* w;

        over_pre = pesos > upper_abs(:);
        pesos_pre_hist(aporte_idx,:)   = pesos(:).';
        sobre_techo_hist(aporte_idx,:) = over_pre(:).';

        % 2.3) Rebalancear solo el EXCESO de los que superan techo
        if any(over_pre)
            detalle.rebals(aporte_idx) = true;

            activos_over = tickers_config(over_pre);
            detalle.over_assets{aporte_idx} = strjoin(activos_over,'|');

            exceso_val = valores(over_pre) - target(over_pre);
            cash = sum(exceso_val);
            valores(over_pre) = target(over_pre);
            detalle.cash_from_sell(aporte_idx) = cash;

            activaciones_count = activaciones_count + double(over_pre);

            % Receptores = NO pasados de techo
            rec = ~over_pre;

            % 2.3.a) Rellenar déficits vs objetivo entre receptores
            if any(rec)
                deficit = max(target(rec) - valores(rec), 0);
                sum_def = sum(deficit);
                if cash > 1e-12 && sum_def > 0
                    alloc_def = cash * (deficit / sum_def);
                    valores(rec) = valores(rec) + alloc_def;
                    cash = cash - sum(alloc_def);
                    detalle.cash_to_buy(aporte_idx) = detalle.cash_to_buy(aporte_idx) + sum(alloc_def);
                end

                % 2.3.b) Si sigue sobrante, repartir por pesos w entre receptores
                if cash > 1e-12
                    w_rec = w(rec);
                    w_rec = w_rec / sum(w_rec);
                    alloc_rest = cash * w_rec;
                    valores(rec) = valores(rec) + alloc_rest;
                    detalle.cash_to_buy(aporte_idx) = detalle.cash_to_buy(aporte_idx) + sum(alloc_rest);
                    cash = 0;
                end
            end

            % 2.4) Actualizar unidades tras el rebalanceo
            acc = valores ./ precios_dia;
        end

        aporte_idx = aporte_idx + 1;
    end

    % --- (3) Tracking de equity (incluye flujos del propio día) ---
    equity_series(dia) = sum(acc .* precios_dia);

    % --- (4) Actualizar precios_prev ---
    precios_prev = precios_dia;
end

%% ======== Valor final y desglose ========
precios_ult = series(end, :).';
valores     = acc .* precios_ult;
valor_final_total = sum(valores);

% Pesos finales
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

%% ======== Metricas de bandas ========
pct_time_above = mean(sobre_techo_hist,1) * 100;

%% ======== Detalle estructurado ========
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

% Series y métricas clave
detalle.equity_series = equity_series;
detalle.dates_series = dates;
detalle.ret_series = r_port;                 % *** NUEVO: retornos diarios TWR
detalle.mdd = mdd_val;
detalle.annual_volatility = annual_vol;

detalle.params = struct('periodos', periodos, 'aportacion_total_mes', aportacion_total_mes, ...
                       'dinero_inicial', dinero_inicial, 'tickers', {tickers_config}, ...
                       'weights', weights_config, 'upper_abs', upper_abs);
detalle.metricas = struct( ...
    'tickers', {tickers_config}, ...
    'activaciones_por_activo', activaciones_count(:).', ...
    'pct_aportes_sobre_techo', pct_time_above, ...
    'fechas_aporte', {detalle.fechas}, ...
    'pesos_pre_en_aportes', pesos_pre_hist, ...
    'sobre_techo_pre', sobre_techo_hist, ...
    'cash_total_vendido', sum(detalle.cash_from_sell), ...
    'cash_total_reinvertido', sum(detalle.cash_to_buy) ...
);

%% ======== Salida por pantalla ========
if ~debug
    fprintf('=====================================================================================================================\n');
    fprintf('Portfolio DCA + Rebalanceo SUAVE (%s) | %d anos | CAGR: %.2f%% | Aportes: %d | Valor final: %.2f\n', ...
            strjoin(tickers_config, '/'), periodos, r*100, num_aportaciones, valor_final_total);
    fprintf('Rebalanceos ejecutados: %d\n', sum(detalle.rebals));
    fprintf('Desglose por activo a %s:\n', datestr(dates(end), 'yyyy-mm-dd'));
    for i = 1:num_activos
        fprintf('  %s: %.2f EUR (%.2f%%)\n', tickers_config{i}, valores(i), 100*pesos_finales(i));
    end
    fprintf('  TOTAL: %.2f EUR (100%%)\n', valor_final_total);
    fprintf('=====================================================================================================================\n');
else
    fprintf('=====================================================================================================================\n');
    fprintf('Portfolio DCA + Rebalanceo SUAVE Flexible | Bandas absolutas\n');
    fprintf('Tickers: %s\n', strjoin(tickers_config, ', '));
    fprintf('Pesos objetivo: %s\n', sprintf('%.1f%% ', weights_config*100));
    fprintf('Periodo: %d anos | Aportacion mensual: %.0f EUR | Inversion inicial: %.0f EUR\n', ...
            periodos, aportacion_total_mes, dinero_inicial);
    fprintf('Techos absolutos: %s\n', sprintf('%.0f%% ', upper_abs*100));
    fprintf('MDD calculado: %.2f%% | Volatilidad anual (TWR): %.2f%%\n', mdd_val*100, annual_vol*100);
    fprintf('---------------------------------------------------------------------------------------------------------------------\n');
    fprintf('RESULTADOS:\n');
    fprintf('  CAGR (IRR): %.2f%%\n', r*100);
    fprintf('  Numero de aportaciones: %d\n', num_aportaciones);
    fprintf('  Numero de rebalanceos: %d\n', sum(detalle.rebals));
    fprintf('  Maximum Drawdown: %.2f%%\n', mdd_val*100);
    fprintf('  Volatilidad anualizada (TWR): %.2f%%\n', annual_vol*100);
    fprintf('  Valor final total: %.2f EUR\n', valor_final_total);
    fprintf('---------------------------------------------------------------------------------------------------------------------\n');
    fprintf('METRICAS DE BANDAS:\n');
    for j = 1:num_activos
        fprintf('  %s: activaciones=%d | %% aportes > techo=%.2f%%\n', ...
            tickers_config{j}, activaciones_count(j), pct_time_above(j));
    end
    fprintf('  Cash total vendido: %.2f EUR\n', sum(detalle.cash_from_sell));
    fprintf('  Cash total reinvertido: %.2f EUR\n', sum(detalle.cash_to_buy));
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
