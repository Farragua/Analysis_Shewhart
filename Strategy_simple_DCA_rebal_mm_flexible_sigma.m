function [r, num_aportaciones, valor_final_total, detalle] = Strategy_simple_DCA_rebal_mm_flexible_sigma(periodos, basePath, tickers_config, weights_config, upper_abs, ma_dias, debug)
% Portfolio DCA + Rebalanceo con filtro MA flexible
% CAMBIOS MINIMOS:
% - Añadido r_port (retorno diario TWR) calculado ANTES de aportar/rebalancear
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
if nargin < 5 || isempty(upper_abs), upper_abs = 0.30 * ones(1, length(tickers_config)); end
if nargin < 6 || isempty(ma_dias), ma_dias = 50; end
if nargin < 7 || isempty(debug), debug = false; end

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
    [series_data{i}, dates_data{i}] = read_yahoo_csv_local(file_paths{i});
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
N_dias = min(N_total, round(252*periodos));
series = series(end-N_dias+1:end, :);
dates = dates(end-N_dias+1:end);

%% ======== Media movil ========
ma = movmean(series, [ma_dias-1 0], 1, 'omitnan');

%% ======== Setup para tracking completo ========
fechas_aport = 1:dias_por_aporte:N_dias;
num_aportaciones = numel(fechas_aport);
aportacion_por_activo = (aportacion_total_mes * w);

acc = zeros(num_activos, 1);

% Arrays para MDD y VOL
equity_series = zeros(N_dias, 1);      % equity día a día (con flujos)
r_port = nan(N_dias,1);                 % retorno diario TWR (sin flujos del día)
precios_prev = series(1, :).';          % precios del "día anterior" para TWR

% Compra inicial por pesos configurados
if dinero_inicial > 0
    precios_d1 = series(1, :).';
    init_eur = dinero_inicial .* w;
    acc = acc + (init_eur ./ precios_d1);
end

% Contadores para verificar diferencias
ma_redirections = zeros(num_activos, 1);
normal_redirections = zeros(num_activos, 1);

detalle = struct();
detalle.fechas = dates(fechas_aport);
detalle.rebals = false(num_aportaciones, 1);
detalle.ma_used = false(num_aportaciones, 1);
detalle.compras = zeros(num_aportaciones, num_activos);
detalle.cash_from_sell = zeros(num_aportaciones, 1);
detalle.cash_to_buy = zeros(num_aportaciones, 1);
detalle.over_assets = cell(num_aportaciones, 1);

%% ======== BUCLE PRINCIPAL (TWR ANTES DE FLUJOS) ========
aporte_idx = 1;

for dia = 1:N_dias
    precios_dia = series(dia, :).';
    ma_i = ma(dia, :).';

    % (1) Retorno TWR ANTES de aportar/rebalancear
    if dia == 1
        r_port(dia) = NaN; % sin retorno el primer día
    else
        valor_inicio = sum(acc .* precios_prev); % valor al inicio SIN flujos del propio día
        if valor_inicio > 0
            r_port(dia) = (sum(acc .* precios_dia) - sum(acc .* precios_prev)) / valor_inicio;
        else
            r_port(dia) = 0; % o NaN si prefieres
        end
    end

    % (2) Día de aportación + posible rebalanceo
    if aporte_idx <= length(fechas_aport) && dia == fechas_aport(aporte_idx)
        % 2.1) DCA mensual (después de medir r_port)
        compra_unidades = aportacion_por_activo ./ precios_dia;
        acc = acc + compra_unidades;
        detalle.compras(aporte_idx, :) = compra_unidades.';

        % 2.2) Estado tras DCA
        valores = acc .* precios_dia;
        total = sum(valores);
        target = total .* w;
        pesos = valores / total;

        % 3) Vender exceso si supera techo
        over = pesos > upper_abs(:);
        if any(over)
            detalle.rebals(aporte_idx) = true;

            % Crear lista de activos que superan techo
            activos_over = tickers_config(over);
            detalle.over_assets{aporte_idx} = strjoin(activos_over, '|');

            % Calcular exceso y vender
            exceso_total = sum(valores(over) - target(over));
            valores(over) = target(over);  % Quedan en objetivo
            detalle.cash_from_sell(aporte_idx) = exceso_total;

            % Decidir quienes reciben el exceso
            receptores = ~over;  % Los que no se vendieron

            bajo_ma = (precios_dia < ma_i) & isfinite(ma_i);
            receptores_bajo_ma = receptores & bajo_ma;

            if any(receptores_bajo_ma)
                % USAR FILTRO MA: solo dar dinero a los que están bajo MA
                detalle.ma_used(aporte_idx) = true;
                elegidos = receptores_bajo_ma;
                ma_redirections = ma_redirections + double(elegidos);
            else
                % Lógica NORMAL: dar a todos los no-vendedores
                elegidos = receptores;
                normal_redirections = normal_redirections + double(elegidos);
            end

            % Repartir el exceso entre elegidos
            if any(elegidos)
                % Primero cubrir déficits
                deficit = max(target(elegidos) - valores(elegidos), 0);
                total_deficit = sum(deficit);

                if total_deficit > 0 && exceso_total > total_deficit
                    % Cubrir déficits primero
                    valores(elegidos) = valores(elegidos) + deficit;
                    exceso_restante = exceso_total - total_deficit;
                else
                    exceso_restante = exceso_total;
                end

                % Repartir resto proporcional por peso objetivo
                if exceso_restante > 1e-12
                    w_elegidos = w(elegidos);
                    w_elegidos = w_elegidos / sum(w_elegidos);
                    valores_elegidos = valores(elegidos) + exceso_restante * w_elegidos;
                    valores(elegidos) = valores_elegidos;
                end

                detalle.cash_to_buy(aporte_idx) = exceso_total;
            end

            % Actualizar unidades tras el rebalanceo
            acc = valores ./ precios_dia;
        end

        aporte_idx = aporte_idx + 1;
    end

    % (3) Tracking de equity (INCLUYE los flujos del propio día)
    equity_series(dia) = sum(acc .* precios_dia);

    % (4) Actualizar precios_prev
    precios_prev = precios_dia;
end

%% ======== Resultado final ========
precios_ult = series(end, :).';
valores = acc .* precios_ult;
valor_final_total = sum(valores);

% Pesos finales
pesos_finales = valores / valor_final_total;

%% ======== CAGR ========
aportes = [dinero_inicial, repmat(aportacion_total_mes, 1, num_aportaciones)];
t_anios = [0, (fechas_aport-1) * 365/252];
tiempos = periodos - t_anios/365;

funcion_CAGR = @(rr) sum(aportes .* (1 + rr).^tiempos) - valor_final_total;
try
    r = fzero(funcion_CAGR, [-0.99, 10]);
catch
    r = fzero(funcion_CAGR, 0.1);
end

%% ======== MDD (equity) y VOL (TWR) ========
mdd_val = calc_MDD_only(equity_series);
valid_r = r_port(~isnan(r_port));
daily_std = std(valid_r, 'omitnan');
annual_vol = daily_std * sqrt(252);

%% ======== Detalle estructurado ========
acciones_struct = struct();
valores_struct = struct();
pesos_struct = struct();

for i = 1*num_activos
    % (mantener bucle) — corrección menor: * debe ser :
end
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

detalle.ma_redirections = ma_redirections;
detalle.normal_redirections = normal_redirections;
detalle.total_rebals = sum(detalle.rebals);
detalle.ma_activations = sum(detalle.ma_used);
detalle.params = struct('periodos', periodos, 'aportacion_total_mes', aportacion_total_mes, ...
                       'dinero_inicial', dinero_inicial, 'tickers', {tickers_config}, ...
                       'weights', weights_config, 'upper_abs', upper_abs, 'ma_dias', ma_dias);

%% ======== Salida ========
if ~debug
    fprintf('=====================================================================================================================\n');
    fprintf('Portfolio DCA + Ventas POST-DCA + Prioridad MA%d (%s) | %d anos | CAGR: %.2f%% | Aportes: %d | Valor final: %.2f\n', ...
        ma_dias, strjoin(tickers_config, '/'), periodos, r*100, num_aportaciones, valor_final_total);
    fprintf('Rebalanceos ejecutados: %d\n', detalle.total_rebals);

    redirecciones_str = '';
    for j = 1:num_activos
        redirecciones_str = [redirecciones_str, sprintf('%s=%d ', tickers_config{j}, ma_redirections(j))];
    end
    fprintf('Redirecciones por MA: %s\n', redirecciones_str);

    fprintf('Desglose por activo a %s:\n', datestr(dates(end), 'yyyy-mm-dd'));
    for i = 1:num_activos
        fprintf('  %s: %.2f EUR (%.2f%%)\n', tickers_config{i}, valores(i), 100*pesos_finales(i));
    end
    fprintf('  TOTAL: %.2f EUR (100%%)\n', valor_final_total);
    fprintf('=====================================================================================================================\n');
else
    fprintf('=== DEBUG: DIFERENCIAS CON ESTRATEGIA SIMPLE ===\n');
    fprintf('Total rebalanceos: %d\n', detalle.total_rebals);
    fprintf('Veces que MA modifico la redistribucion: %d\n', detalle.ma_activations);
    fprintf('MDD calculado: %.2f%% | Volatilidad anual (TWR): %.2f%%\n', mdd_val*100, annual_vol*100);

    redirecciones_ma_str = '';
    redirecciones_norm_str = '';
    for j = 1:num_activos
        redirecciones_ma_str = [redirecciones_ma_str, sprintf('%s=%d ', tickers_config{j}, ma_redirections(j))];
        redirecciones_norm_str = [redirecciones_norm_str, sprintf('%s=%d ', tickers_config{j}, normal_redirections(j))];
    end
    fprintf('Redirecciones POR MA: %s\n', redirecciones_ma_str);
    fprintf('Redirecciones NORMALES: %s\n', redirecciones_norm_str);
    fprintf('CAGR: %.4f%% | Valor final: %.2f EUR\n', r*100, valor_final_total);
    fprintf('Maximum Drawdown: %.2f%% | Volatilidad anualizada (TWR): %.2f%%\n', mdd_val*100, annual_vol*100);
end

end

% ========================= HELPER FUNCTIONS =========================
function [close_prices, dates] = read_yahoo_csv_local(csvPath)
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
