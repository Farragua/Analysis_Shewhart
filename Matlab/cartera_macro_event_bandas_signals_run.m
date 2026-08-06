function [r, num_aportaciones, valor_final_total, detalle] = cartera_macro_event_bandas_signals_run( ...
    periodos, basePath, max_cash_por_dia, z_engine, n_boll, z_threshold, MA, ...
    enableMomentum, mom_look, enableFiltroVIX, vix_umbral)

% MACRO Event-Driven (CASH mensual + TOPE DIARIO) con REBALANCEO por BANDAS ABSOLUTAS
% Activos: SPY, IWM, GLD, TLT, BTC
% Lógica:
%   - Aporte mensual (1.500 €) -> CASH.
%   - Reb. por bandas (a diario): si peso > techo absoluto, vender EXCESO hasta objetivo (w) -> CASH.
%   - Compras (a diario) SOLO si hay señal: (z <= umbral) & (Precio < MA(MA)).
%       · z_engine: 'shewhart_tippett' o 'bollinger' (usa n_boll y z_threshold).
%       · Presupuesto del día = min(CASH, max_cash_por_dia), repartido a PARTES IGUALES entre señalizados.
%   - Sin compras si no hay señal. El CASH no usado se acumula.
%
% Uso ejemplo:
%   [r,n,vf,det] = cartera_macro_event_bandas_signals_run(12);
%   [r,n,vf,det] = cartera_macro_event_bandas_signals_run(12,'C:\Path\',3000,'shewhart_tippett',22,-2,200,false,252,false,19);

%% === Parámetros por defecto ===
if nargin < 1, periodos = 10; end
if nargin < 2 || isempty(basePath), basePath = 'C:\Users\israe\OneDrive\Matlab_scripts\'; end
if nargin < 3 || isempty(max_cash_por_dia), max_cash_por_dia = 3000; end
if nargin < 4 || isempty(z_engine), z_engine = 'shewhart_tippett'; end   % 'shewhart_tippett' | 'bollinger'
if nargin < 5 || isempty(n_boll), n_boll = 22; end
if nargin < 6 || isempty(z_threshold), z_threshold = -2.0; end
if nargin < 7 || isempty(MA), MA = 200; end
if nargin < 8 || isempty(enableMomentum), enableMomentum = false; end
if nargin < 9 || isempty(mom_look), mom_look = 252; end
if nargin < 10 || isempty(enableFiltroVIX), enableFiltroVIX = false; end
if nargin < 11 || isempty(vix_umbral), vix_umbral = 19; end

aportacion_mensual = 1500;
dinero_inicial     = 10000;

% Pesos MACRO (objetivos para ventas por banda y compra inicial)
w = [0.50, 0.25, 0.10, 0.10, 0.05];                 % SPY IWM GLD TLT BTC
tickers = {'SPY','IWM','GLD','TLT','BTC'};          % orden estable para logs

% Bandas absolutas típicas (techo de peso)
% SPY>60%, IWM>32%, GLD>13%, TLT>13%, BTC>10%
upper_abs = [0.60, 0.32, 0.13, 0.13, 0.10];

%% === Ficheros locales (YA descargados) ===
fp_spy = fullfile(basePath,'SPY_yahoo.csv');
fp_iwm = fullfile(basePath,'IWM_yahoo.csv');
fp_gld = fullfile(basePath,'GLD_yahoo.csv');
fp_tlt = fullfile(basePath,'TLT_yahoo.csv');
fp_btc = fullfile(basePath,'BTC-USD_yahoo.csv');
need = {fp_spy, fp_iwm, fp_gld, fp_tlt, fp_btc};
for k=1:numel(need), assert(isfile(need{k}), 'Falta %s. Ejecuta antes main_vYahoo.', need{k}); end
if enableFiltroVIX
    fp_vix = fullfile(basePath,'VIX_yahoo.csv');
    assert(isfile(fp_vix), 'Falta %s y tienes VIX activo. Ejecuta antes main_vYahoo.', fp_vix);
end

%% === Lectura y alineación ===
[spy, d_spy] = read_yahoo_csv(fp_spy);
[iwm, d_iwm] = read_yahoo_csv(fp_iwm);
[gld, d_gld] = read_yahoo_csv(fp_gld);
[tlt, d_tlt] = read_yahoo_csv(fp_tlt);
[btc, d_btc] = read_yahoo_csv(fp_btc);

TT = synchronize( ...
    timetable(d_spy, spy, 'VariableNames', {'SPY'}), ...
    timetable(d_iwm, iwm, 'VariableNames', {'IWM'}), ...
    timetable(d_gld, gld, 'VariableNames', {'GLD'}), ...
    timetable(d_tlt, tlt, 'VariableNames', {'TLT'}), ...
    timetable(d_btc, btc, 'VariableNames', {'BTC'}), ...
    'intersection');
TT = rmmissing(TT);
assert(height(TT)>0, 'No quedan fechas comunes tras la intersección.');

if enableFiltroVIX
    [vix_raw, d_vix] = read_yahoo_csv(fp_vix);
    TT_vix  = timetable(d_vix, vix_raw, 'VariableNames', {'VIX'});
    TT_all  = synchronize(TT, TT_vix, 'union','fillwithmissing');
    mask    = ismember(TT_all.Properties.RowTimes, TT.Properties.RowTimes);
    TT      = TT_all(mask,:);
else
    TT.VIX = NaN(height(TT),1);
end

% Ventana temporal
N_total = height(TT);
N_dias  = min(N_total, round(252*periodos));
TT      = TT(end-N_dias+1:end,:);

dates   = TT.Properties.RowTimes;
P       = [TT.SPY, TT.IWM, TT.GLD, TT.TLT, TT.BTC];   % Nx5 (orden de 'tickers')
vix     = TT.VIX;
N       = size(P,1);
T_yrs   = N/252;

%% === Aportaciones mensuales (entran a CASH) ===
fechas_mens = dateshift(dates(1),'start','month',0:(periodos*12-1));
fechas_mens = fechas_mens(fechas_mens <= dates(end));
mes_idx = zeros(numel(fechas_mens),1);
for k=1:numel(fechas_mens)
    [~, ii] = min(abs(dates - fechas_mens(k)));  % día hábil más cercano
    mes_idx(k) = ii;
end
mes_idx = unique(mes_idx,'stable');

%% === MA causal y z-scores ===
mm_fun = @(x) movmean(x,[MA-1 0],'omitnan');
mm = [mm_fun(P(:,1)), mm_fun(P(:,2)), mm_fun(P(:,3)), mm_fun(P(:,4)), mm_fun(P(:,5))];

switch lower(z_engine)
    case 'bollinger'
        mu = movmean(P,[n_boll-1 0],1,'omitnan');
        sd = movstd (P,[n_boll-1 0],1,'omitnan');
        Z  = (P - mu) ./ sd;
        sig_z = (Z <= z_threshold) & (sd > 0);
    case 'shewhart_tippett'
        Z = NaN(N,5);
        [~,~,~,~,~, Z(:,1)] = shewhart_tasa_const(P(:,1));
        [~,~,~,~,~, Z(:,2)] = shewhart_tasa_const(P(:,2));
        [~,~,~,~,~, Z(:,3)] = shewhart_tasa_const(P(:,3));
        [~,~,~,~,~, Z(:,4)] = shewhart_tasa_const(P(:,4));
        [~,~,~,~,~, Z(:,5)] = shewhart_tasa_const(P(:,5));
        sig_z = (Z <= z_threshold);
    otherwise
        error('z_engine no reconocido. Usa ''bollinger'' o ''shewhart_tippett''.');
end

% Señal BRUTA = (z<=umbral) & (Precio < MA)
sig_raw = sig_z & (P < mm);

% Momentum opcional
if enableMomentum
    momfun = @(x,w)[nan(w,1); (x(w+1:end)./x(1:end-w) - 1)];
    M = [momfun(P(:,1),mom_look), momfun(P(:,2),mom_look), momfun(P(:,3),mom_look), momfun(P(:,4),mom_look), momfun(P(:,5),mom_look)];
    sig_raw = sig_raw & (M >= 0);
end

% VIX opcional (filtro global del día)
if enableFiltroVIX
    vix_ok = isfinite(vix) & (vix > vix_umbral);
else
    vix_ok = true(N,1);
end

sig_counts_raw      = sum(sig_raw, 1);
sig_counts_filtered = sum(sig_raw & vix_ok, 1);

%% === Estados ===
acc = zeros(5,1);  % unidades
cash_bal = 0;
dias_tope = 0;

% Compra inicial por pesos MACRO
if dinero_inicial > 0
    p1 = P(1,:).';
    acc = acc + (dinero_inicial .* w(:)) ./ p1;
end

% Trazas
compras_idx=[]; compras_dst={}; compras_z=[]; compras_px=[]; compras_amt=[];
buy_counts = zeros(1,5);

ventas_idx=[]; ventas_dst={}; ventas_eur=[];
activaciones_count = zeros(5,1);

cash_hist = zeros(N,1);

% Para "% meses > techo" (hubo al menos un día >techo en el mes, pre-venta)
ym = year(dates)*100 + month(dates);
[~,~,grp_mes] = unique(ym);
meses_total = max(grp_mes);
sobre_techo_mes = false(meses_total,5);

%% === Bucle DIARIO ===
for i = 1:N
    precios_i = P(i,:).';

    % Aporte mensual -> CASH
    if any(i == mes_idx)
        cash_bal = cash_bal + aportacion_mensual;
    end

    % --- Estado antes de ventas ---
    valores   = acc .* precios_i;
    invertido = sum(valores);
    if invertido <= 0
        pesos_assets  = zeros(5,1);
        target_assets = zeros(5,1);
    else
        pesos_assets  = valores / invertido;
        target_assets = invertido .* w(:);
    end

    % --- Reb. por bandas: vender EXCESO hasta objetivo (fluye a CASH) ---
    over_pre = pesos_assets > upper_abs(:);
    if any(over_pre)
        sobre_techo_mes(grp_mes(i), :) = sobre_techo_mes(grp_mes(i), :) | over_pre(:).';
        exceso = valores(over_pre) - target_assets(over_pre);
        cash_new = sum(exceso);
        if cash_new > 0
            idx_over = find(over_pre);
            for c = idx_over(:)'
                x = valores(c) - target_assets(c);
                if x > 0
                    activaciones_count(c) = activaciones_count(c) + 1;
                    ventas_idx(end+1,1) = i;
                    ventas_dst{end+1,1} = tickers{c};
                    ventas_eur(end+1,1) = x;
                end
            end
            valores(over_pre) = target_assets(over_pre);
            cash_bal = cash_bal + cash_new;
        end
    end

    % Actualiza acc (por si hubo ventas sin compras)
    acc = valores ./ precios_i;

    % --- Compras SOLO si hay señal hoy (y pasa VIX global) ---
    if cash_bal > 1e-12 && vix_ok(i)
        base = sig_raw(i,:);
        if any(base)
            presupuesto = min(cash_bal, max_cash_por_dia);
            if presupuesto > 0
                if abs(presupuesto - max_cash_por_dia) < 1e-9, dias_tope = dias_tope + 1; end

                idx_cand = find(base);
                amount_per = presupuesto / numel(idx_cand);

                for c = idx_cand(:)'
                    acc(c) = acc(c) + amount_per / precios_i(c);

                    compras_idx(end+1,1) = i;
                    compras_dst{end+1,1} = tickers{c};
                    compras_z(end+1,1)   = Z(i,c);
                    compras_px(end+1,1)  = precios_i(c);
                    compras_amt(end+1,1) = amount_per;
                    buy_counts(c) = buy_counts(c) + 1;
                end

                cash_bal = cash_bal - presupuesto;  % resta solo lo gastado hoy
            end
        end
    end

    % Caja del día
    cash_hist(i) = cash_bal;
end

num_aportaciones = numel(compras_idx);   % nº de órdenes de compra

%% === Valor final y CAGR (IRR) ===
precios_ult = P(end,:).';
valores     = acc .* precios_ult;
valor_CASH  = cash_bal;
valor_final_total = sum(valores) + valor_CASH;

% IRR con aportes mensuales
dias_nat   = mes_idx * 365/252;
tiempos    = T_yrs - dias_nat/365;
aportes    = [dinero_inicial; repmat(aportacion_mensual, numel(mes_idx), 1)];
t_full     = [T_yrs; tiempos];
fCAGR      = @(rr) sum(aportes .* (1+rr).^t_full) - valor_final_total;
r          = solve_irr(fCAGR);

%% === Métricas de caja y bandas ===
[max_cash, idx_max_cash] = max(cash_hist);
fecha_max_cash           = dates(idx_max_cash);
dias_cash_positivo       = sum(cash_hist > 0);
total_aportado           = dinero_inicial + aportacion_mensual * numel(mes_idx);
solo_aportes_mensuales   = aportacion_mensual * numel(mes_idx);
pct_meses_sobre_techo    = mean(sobre_techo_mes,1) * 100;

%% === Salida y logs (formato como tus ejemplos) ===
as_struct = @(vec) cell2struct(num2cell(vec(:).'), tickers, 2);

detalle.compras = table(dates(compras_idx), compras_dst, compras_px, compras_amt, compras_z, ...
    'VariableNames', {'Fecha','Activo','Precio','Importe','Z'});
detalle.ventas  = table(dates(ventas_idx), ventas_dst, ventas_eur, ...
    'VariableNames', {'Fecha','Activo','ImporteVendido'});

detalle.acciones            = as_struct(acc);
detalle.valor_por_activo    = as_struct(valores);  detalle.valor_por_activo.CASH = valor_CASH;
detalle.peso_por_activo     = struct('SPY',valores(1)/valor_final_total,'IWM',valores(2)/valor_final_total, ...
                                     'GLD',valores(3)/valor_final_total,'TLT',valores(4)/valor_final_total, ...
                                     'BTC',valores(5)/valor_final_total,'CASH',valor_CASH/valor_final_total);
detalle.signal_counts_raw   = as_struct(sig_counts_raw);
detalle.signal_counts       = as_struct(sig_counts_filtered);
detalle.buy_counts          = as_struct(buy_counts);
detalle.activaciones_ventas = as_struct(activaciones_count);
detalle.cash_series         = cash_hist;
detalle.params = struct('periodos',periodos,'aportacion_mensual',aportacion_mensual,'dinero_inicial',dinero_inicial, ...
    'pesos',w,'upper_abs',upper_abs,'MA',MA,'z_engine',z_engine,'n_boll',n_boll,'z_threshold',z_threshold, ...
    'enableMomentum',enableMomentum,'mom_look',mom_look,'enableFiltroVIX',enableFiltroVIX,'vix_umbral',vix_umbral, ...
    'max_cash_por_dia',max_cash_por_dia,'dias_con_tope',dias_tope);

detalle.metricas_cash = struct( ...
    'max_cash', max_cash, ...
    'fecha_max_cash', fecha_max_cash, ...
    'dias_con_cash_positivo', dias_cash_positivo, ...
    'total_aportado_incl_inicial', total_aportado, ...
    'solo_aportaciones_mensuales', solo_aportes_mensuales ...
);

% ===== Logs =====
fprintf('MACRO Event-Driven (CASH mensual, tope diario=%.2f) | z-engine=%s%s | Señal: z<=%.2f & Px<MM(%d) | CAGR: %.2f%% | Órdenes: %d\n', ...
    max_cash_por_dia, z_engine, iff(strcmpi(z_engine,'bollinger'), sprintf('(n=%d)',n_boll), ''), ...
    z_threshold, MA, r*100, num_aportaciones);

fprintf('Desglose VALOR actual (%s): SPY=%.2f  IWM=%.2f  GLD=%.2f  TLT=%.2f  BTC=%.2f  CASH=%.2f  |  TOTAL=%.2f\n', ...
    datestr(dates(end),'yyyy-mm-dd'), valores(1), valores(2), valores(3), valores(4), valores(5), valor_CASH, valor_final_total);

fprintf('Señales BRUTAS (z+MM):          SPY=%d  IWM=%d  GLD=%d  TLT=%d  BTC=%d\n', ...
    detalle.signal_counts_raw.SPY, detalle.signal_counts_raw.IWM, detalle.signal_counts_raw.GLD, detalle.signal_counts_raw.TLT, detalle.signal_counts_raw.BTC);
fprintf('Señales FILTRADAS (VIX):        SPY=%d  IWM=%d  GLD=%d  TLT=%d  BTC=%d\n', ...
    detalle.signal_counts.SPY, detalle.signal_counts.IWM, detalle.signal_counts.GLD, detalle.signal_counts.TLT, detalle.signal_counts.BTC);

fprintf('Compras ejecutadas (cap %.0f€/día):  SPY=%d  IWM=%d  GLD=%d  TLT=%d  BTC=%d\n', ...
    max_cash_por_dia, detalle.buy_counts.SPY, detalle.buy_counts.IWM, detalle.buy_counts.GLD, detalle.buy_counts.TLT, detalle.buy_counts.BTC);

fprintf('Total aportado (incl. inicial): %.2f € | Solo aportaciones mensuales: %.2f €\n', ...
    total_aportado, solo_aportes_mensuales);
fprintf('Máxima aportación acumulada (CASH máx): %.2f € en %s\n', ...
    max_cash, datestr(fecha_max_cash,'yyyy-mm-dd'));
fprintf('Días con CASH > 0: %d | Días con tope alcanzado: %d\n', ...
    dias_cash_positivo, dias_tope);

fprintf('--- Métricas de bandas ---\n');
for j=1:numel(tickers)
    fprintf('  %s: activaciones=%d | %% meses > techo=%.2f%%\n', ...
        tickers{j}, detalle.activaciones_ventas.(tickers{j}), pct_meses_sobre_techo(j));
end

fprintf('Desglose por activo a %s:\n', datestr(dates(end),'yyyy-mm-dd'));
for j=1:numel(tickers)
    fprintf('  %s : %.2f € (%.2f%%)\n', tickers{j}, valores(j), 100*valores(j)/valor_final_total);
end
fprintf('  CASH: %.2f € (%.2f%%)\n  TOTAL: %.2f € (100%%)\n', valor_CASH, 100*valor_CASH/valor_final_total, valor_final_total);

end % ===== FIN FUNCIÓN =====

%% ----------------- HELPERS -----------------
function [idx3s, idx2s, media, sigma_t, tasa_pct, z] = shewhart_tasa_const(precios)
    precios = precios(:); N = numel(precios);
    if N < 3, idx3s=[]; idx2s=[]; media=NaN; sigma_t=NaN; tasa_pct=[]; z=NaN(N,1); return; end
    tasa_pct = diff(precios) ./ precios(1:end-1) * 100;
    media    = mean(tasa_pct, 'omitnan');
    RM       = abs(diff(tasa_pct));
    sigma_t  = mean(RM, 'omitnan') / 1.128;
    if ~isfinite(sigma_t) || sigma_t <= 0, sigma_t = NaN; end
    z = NaN(N,1); if isfinite(sigma_t), z(2:end) = (tasa_pct - media) / sigma_t; end
    if isfinite(sigma_t)
        idx3s = find(tasa_pct <= (media - 3*sigma_t)) + 1;
        idx2s = find(tasa_pct <= (media - 2*sigma_t)) + 1;
    else
        idx3s = []; idx2s = [];
    end
end

function r = solve_irr(fun)
    a=-0.999; b=10; Fa=fun(a); Fb=fun(b);
    if isfinite(Fa)&&isfinite(Fb)&&sign(Fa)~=sign(Fb), r=fzero(fun,[a b]); return; end
    guesses=[-0.9 -0.5 -0.2 0 0.05 0.1 0.2 0.4 0.8 1 2 5];
    for g=guesses
        try, rr=fzero(fun,g); if isfinite(rr), r=rr; return; end
        catch, end
    end
    obj=@(x) abs(fun(x)); r=fminbnd(obj,-0.99,10);
end

function s = iff(cond, a, b), if cond, s = a; else, s = b; end, end

function [close_prices, dates] = read_yahoo_csv(csvPath)
    if ~isfile(csvPath), error('Archivo no encontrado: %s', csvPath); end
    T = readtable(csvPath);
    if isempty(T) || width(T)==0 || height(T)==0, error('CSV vacío o sin filas: %s', csvPath); end
    names = lower(strrep(strrep(T.Properties.VariableNames,'_',''),' ','')); % normaliza
    iDate = find(strcmp(names,'date'),1); if isempty(iDate), iDate = 1; end
    dates = T{:,iDate};
    if ~isdatetime(dates)
        if isnumeric(dates), dates = datetime(dates,'ConvertFrom','datenum');
        elseif iscellstr(dates) || isstring(dates)
            try, dates = datetime(dates,'InputFormat','yyyy-MM-dd','Locale','en_US'); catch, dates = datetime(dates); end
        else, dates = datetime(dates);
        end
    end
    iAdj   = find(strcmp(names,'adjclose'),1);
    iClose = find(strcmp(names,'close'),1);
    if ~isempty(iAdj), y = T{:,iAdj};
    elseif ~isempty(iClose), y = T{:,iClose};
    else, y = T{:,end}; warning('No AdjClose/Close en %s', csvPath);
    end
    if iscellstr(y) || isstring(y), y = str2double(strrep(string(y),',','.')); end
    if ~isfloat(y), y = double(y); end
    good = ~isnat(dates) & ~isnan(y);
    [dates, idx] = sort(dates(good)); close_prices = y(good); close_prices = close_prices(idx);
    close_prices = close_prices(:); dates = dates(:);
end
