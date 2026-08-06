function [r, num_aportaciones, valor_final_total, detalle] = Strategy_event_driven_rebal_cashpool_flexible_v2_sigma( ...
    periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, upper_abs, debug)

% Portfolio Event-Driven + Reb. por bandas a CASH v2 - SIN tope diario, permite cash negativo
% MDD desde equity_series (post-flujos); VOL desde TWR diario ANTES de flujos
% Unificación de amount_per_signal (usado, guardado e impreso consistentemente)

% ---------- Defaults ----------
if nargin < 3 || isempty(tickers_config)
    error('Debes especificar los tickers del portfolio');
end
if nargin < 4 || isempty(weights_config)
    weights_config = ones(1, length(tickers_config)) / length(tickers_config);
end
if nargin<1||isempty(periodos), periodos=5; end
if nargin<2||isempty(basePath), basePath='C:\Users\israe\OneDrive\Matlab_scripts\'; end
if nargin<5||isempty(z_engine), z_engine='shewhart_tippett'; end
if nargin<6||isempty(n_boll),   n_boll=22; end
if nargin<7||isempty(z_threshold), z_threshold=-2.0; end
if nargin<8||isempty(MA),       MA=200; end
if nargin<9||isempty(upper_abs), upper_abs=0.30*ones(1,length(tickers_config)); end
if nargin<10||isempty(debug),    debug=false; end

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

aportacion_mensual = 1500; 
dinero_inicial     = 1000; 
w = weights_config(:);

amount_per_signal = aportacion_mensual;   % ÚNICO sitio donde se define

[reader, irrsolve, shew] = get_helpers();

%% ======== Verificacion de archivos ========
file_paths = cell(num_activos, 1);
for i = 1:num_activos
    ticker = tickers_config{i};
    file_paths{i} = fullfile(basePath, [ticker '_yahoo.csv']);
    if ~isfile(file_paths{i})
        error('Falta archivo: %s. Ejecuta main_vYahoo.m primero.', file_paths{i});
    end
end

% ---------- Datos ----------
series_data = cell(num_activos, 1);
dates_data = cell(num_activos, 1);
for i = 1:num_activos
    [series_data{i}, dates_data{i}] = reader(file_paths{i});
end

% ---------- Alinear por fechas comunes ----------
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
assert(height(TT)>0);

N_total = height(TT); 
N_dias  = min(N_total, round(252*periodos));
warmup  = max([MA, n_boll, 3]); 
i0      = max(1, N_total - (N_dias + warmup) + 1);

TTw     = TT(i0:end,:); 
dates_w = TTw.Properties.RowTimes; 
P_w     = table2array(TTw); 
N_w     = size(P_w,1);

mm_fun=@(x) movmean(x,[MA-1 0],'omitnan');
MM_w=zeros(N_w, num_activos);
for j = 1:num_activos
    MM_w(:,j) = mm_fun(P_w(:,j));
end

switch lower(z_engine)
    case 'bollinger'
        mu = movmean(P_w,[n_boll-1 0],1,'omitnan'); 
        sd = movstd(P_w,[n_boll-1 0],1,'omitnan');
        Z_w = (P_w - mu) ./ (sd);
        sig_w = (Z_w <= z_threshold) & (sd>0) & (P_w < MM_w);
    case 'shewhart_tippett'
        Z_w = NaN(N_w,num_activos); 
        for c=1:num_activos, [~,~,~,~,~,Z_w(:,c)] = shew(P_w(:,c)); end
        sig_w = (Z_w <= z_threshold) & (P_w < MM_w);
    otherwise
        error('z_engine no reconocido.');
end

P     = P_w(end-N_dias+1:end,:);  
Z     = Z_w(end-N_dias+1:end,:);
sig   = sig_w(end-N_dias+1:end,:); 
dates = dates_w(end-N_dias+1:end); 
N     = size(P,1); 
T_yrs = N/252;
sig_counts = sum(sig,1);

% ---------- Aportes ----------
fechas_mens = dateshift(dates(1),'start','month',0:(periodos*12-1));
fechas_mens = fechas_mens(fechas_mens <= dates(end));
mes_idx = zeros(numel(fechas_mens),1); 
for k=1:numel(fechas_mens), [~,ii]=min(abs(dates-fechas_mens(k))); mes_idx(k)=ii; end
mes_idx = unique(mes_idx,'stable'); 
num_aportaciones = numel(mes_idx);

% ---------- Estados ----------
acc=zeros(num_activos,1); 
cash_bal=0; 
min_cash_alcanzado=0;

% Tracking
equity_series = zeros(N, 1);        % equity post-flujos (activos + cash)
r_port        = nan(N,1);           % retornos TWR diarios ANTES de flujos (cash = 0%)
compras_idx=[]; compras_dst={}; compras_amt=[]; compras_px=[]; compras_z=[];
buy_counts=zeros(1,num_activos); 
ventas_idx=[]; ventas_dst={}; ventas_eur=[]; 
activaciones_count=zeros(num_activos,1);
cash_hist=zeros(N,1); 
inversiones_por_senal = [];

% Inversion inicial por pesos
precios_prev = P(1,:)';
if dinero_inicial>0
    p1=P(1,:).'; 
    init_weights = w * dinero_inicial;
    acc=acc+(init_weights./p1); 
end

% ---------- Bucle ----------
for i=1:N
    precios = P(i,:)';

    % (1) Retorno TWR ANTES de flujos del día (cash rinde 0)
    if i==1
        r_port(i) = NaN;
    else
        valor_inicio = sum(acc .* precios_prev) + cash_bal;
        if valor_inicio > 0
            delta_activos = sum(acc .* (precios - precios_prev));
            r_port(i) = delta_activos / valor_inicio;
        else
            r_port(i) = 0;
        end
    end

    % (2) Aporte mensual (después de medir r_port)
    if any(i==mes_idx), cash_bal = cash_bal + aportacion_mensual; end

    % Reb a CASH (venta del exceso)
    valores=acc.*precios; 
    invertido=sum(valores);
    if invertido>0
        pesos=valores/invertido; 
        target=invertido.*w; 
        over=(pesos>upper_abs(:));
        if any(over)
            exceso=valores(over)-target(over); 
            cash_new=sum(exceso);
            if cash_new>0
                idx_over=find(over);
                for c=idx_over(:).'
                    x=valores(c)-target(c);
                    if x>0
                        activaciones_count(c)=activaciones_count(c)+1;
                        ventas_idx(end+1,1)=i; 
                        ventas_dst{end+1,1}=tickers_config{c}; 
                        ventas_eur(end+1,1)=x;
                    end
                end
                valores(over)=target(over); 
                cash_bal=cash_bal+cash_new;
                acc=valores./precios;
            end
        end
    end

    % Compras SIN tope diario; permite cash negativo (apalancamiento)
    if any(sig(i,:))
        idx=find(sig(i,:));
        total_inversion_dia = 0;
        for c = idx(:).'
            acc(c)   = acc(c) + amount_per_signal / precios(c);
            cash_bal = cash_bal - amount_per_signal;   % puede ser < 0
            compras_idx(end+1,1) = i;
            compras_dst{end+1,1} = tickers_config{c};
            compras_amt(end+1,1) = amount_per_signal;
            compras_px(end+1,1)  = precios(c);
            compras_z(end+1,1)   = Z(i,c);
            buy_counts(c)        = buy_counts(c) + 1;
            total_inversion_dia  = total_inversion_dia + amount_per_signal;
        end
        if total_inversion_dia > aportacion_mensual
            inversiones_por_senal(end+1,:) = [i, total_inversion_dia, numel(idx)];
        end
    end

    cash_hist(i) = cash_bal;
    min_cash_alcanzado = min(min_cash_alcanzado, cash_bal);

    % (3) Equity post-flujos
    valores_dia = acc .* precios;
    equity_series(i) = sum(valores_dia) + cash_bal;

    % (4) actualizar precios_prev
    precios_prev = precios;
end

% ---------- Valor final e IRR ----------
precios_ult=P(end,:).'; 
valores=acc.*precios_ult; 
valor_CASH=cash_bal;
valor_final_total=sum(valores)+valor_CASH;

dias_nat=mes_idx*365/252; 
tiempos=T_yrs - dias_nat/365;
aportes=[dinero_inicial; repmat(aportacion_mensual,num_aportaciones,1)];
t_full=[T_yrs; tiempos];
r = irrsolve(@(rr) sum(aportes.*(1+rr).^t_full) - valor_final_total);

% ---------- MDD (equity) y VOL (TWR) ----------
mdd_val = calc_MDD_only(equity_series);
valid_r = r_port(~isnan(r_port));
daily_std = std(valid_r,'omitnan');
annual_vol = daily_std * sqrt(252);

% ---------- Detalle ----------
if ~isempty(compras_idx)
    detalle.compras = table(dates(compras_idx), compras_dst, compras_px, compras_amt, compras_z, ...
        'VariableNames', {'Fecha','Activo','Precio','Importe','Z'});
else
    detalle.compras = table([], {}, [], [], [], 'VariableNames', {'Fecha','Activo','Precio','Importe','Z'});
end
if ~isempty(ventas_idx)
    detalle.ventas = table(dates(ventas_idx), ventas_dst, ventas_eur, ...
        'VariableNames', {'Fecha','Activo','ImporteVenta'});
else
    detalle.ventas = table([], {}, [], 'VariableNames', {'Fecha','Activo','ImporteVenta'});
end

buy_counts_struct = struct(); signal_counts_struct = struct();
activaciones_struct = struct(); acciones_struct = struct(); valores_struct = struct();
for i = 1:num_activos
    ticker_clean = matlab.lang.makeValidName(tickers_config{i});
    buy_counts_struct.(ticker_clean) = buy_counts(i);
    signal_counts_struct.(ticker_clean) = sig_counts(i);
    activaciones_struct.(ticker_clean) = activaciones_count(i);
    acciones_struct.(ticker_clean) = acc(i);
    valores_struct.(ticker_clean) = valores(i);
end

detalle.buy_counts          = buy_counts_struct;
detalle.signal_counts       = signal_counts_struct;
detalle.activaciones        = activaciones_struct;
detalle.cash_series         = cash_hist;
detalle.min_cash            = min_cash_alcanzado;
detalle.max_deuda           = max(0, -min_cash_alcanzado);
detalle.inversiones_grandes = inversiones_por_senal;
detalle.num_ventas          = numel(ventas_idx);
detalle.acciones            = acciones_struct;
detalle.valor_por_activo    = valores_struct;

% Series y métricas clave
detalle.equity_series      = equity_series;
detalle.ret_series         = r_port;           % ← NUEVO: TWR diario
detalle.dates_series       = dates;
detalle.mdd                = mdd_val;
detalle.annual_volatility  = annual_vol;

detalle.params = struct('periodos', periodos, 'aportacion_mensual', aportacion_mensual, ...
                       'dinero_inicial', dinero_inicial, 'tickers', {tickers_config}, ...
                       'weights', weights_config, 'upper_abs', upper_abs, 'z_engine', z_engine, ...
                       'z_threshold', z_threshold, 'MA', MA, 'amount_per_signal', amount_per_signal);

% ---------- Print ----------
if ~debug
    fprintf('=====================================================================================================================\n');
    fprintf('Portfolio Event-Driven + Reb. a CASH v2 (%s) | %d anos | CAGR: %.2f%% | Aportes: %d | Valor final: %.2f\n', ...
        strjoin(tickers_config, '/'), periodos, r*100, num_aportaciones, valor_final_total);
    if min_cash_alcanzado < 0
        fprintf('Deuda maxima alcanzada: %.2f EUR\n', abs(min_cash_alcanzado));
    end
    fprintf('Desglose por activo a %s:\n', datestr(dates(end),'yyyy-mm-dd'));
    for j=1:num_activos
        fprintf('  %s: %.2f EUR (%.2f%%)\n', tickers_config{j}, valores(j), 100*valores(j)/valor_final_total);
    end
    fprintf('  CASH: %.2f EUR (%.2f%%)\n', valor_CASH, 100*valor_CASH/valor_final_total);
    fprintf('  TOTAL: %.2f EUR (100%%)\n', valor_final_total);
    fprintf('=====================================================================================================================\n');
else
    fprintf('=====================================================================================================================\n');
    fprintf('Portfolio Event-Driven + Rebalanceo por bandas a CASH v2 - SIN LIMITES DE CAPITAL\n');
    fprintf('Tickers: %s\n', strjoin(tickers_config, ', '));
    fprintf('Pesos objetivo: %s\n', sprintf('%.1f%% ', weights_config*100));
    fprintf('Motor: %s%s | Senal: z<=%.2f & Px<MM(%d) | Inversion por senal: %.0f EUR\n', ...
        z_engine, iff(strcmpi(z_engine,'bollinger'), sprintf('(n=%d)',n_boll), ''), z_threshold, MA, amount_per_signal);
    fprintf('Techos absolutos: %s\n', sprintf('%.0f%% ', upper_abs*100));
    fprintf('MDD calculado: %.2f%% | Volatilidad anual (TWR): %.2f%%\n', mdd_val*100, annual_vol*100);
    fprintf('---------------------------------------------------------------------------------------------------------------------\n');
    fprintf('RESULTADOS:\n');
    fprintf('  CAGR (IRR): %.2f%%\n', r*100);
    fprintf('  Numero de aportaciones: %d\n', num_aportaciones);
    fprintf('  Numero de ordenes de compra: %d\n', numel(compras_idx));
    fprintf('  Numero de ventas por rebalanceo: %d\n', numel(ventas_idx));
    fprintf('  Deuda maxima alcanzada: %.2f EUR\n', abs(min_cash_alcanzado));
    fprintf('  Maximum Drawdown: %.2f%%\n', mdd_val*100);
    fprintf('  Volatilidad anualizada (TWR): %.2f%%\n', annual_vol*100);
    fprintf('  Valor final total: %.2f EUR\n', valor_final_total);
    fprintf('=====================================================================================================================\n');
end
end

% ---------- Helpers ----------
function [reader, irrsolve, shew] = get_helpers()
    if exist('read_yahoo_csv','file')==2 && exist('solve_irr','file')==2 && exist('shewhart_tasa_const','file')==2
        reader=@read_yahoo_csv; irrsolve=@solve_irr; shew=@shewhart_tasa_const; return;
    end
    helperNames={'GBEeventHelper','GBEventHelpers','GBEventHelper'};
    for k=1:numel(helperNames)
        nm=helperNames{k};
        if exist(nm,'file')==2 || exist(nm,'class')==8
            try H=feval(nm); catch, H=[]; end
            if ~isempty(H)
                if isstruct(H) && isfield(H,'read_yahoo_csv') && isa(H.read_yahoo_csv,'function_handle')
                    reader=H.read_yahoo_csv; irrsolve=H.solve_irr; shew=@(x) H.shewhart_tasa_const(x); return;
                else
                    reader=@(p) H.read_yahoo_csv(p); irrsolve=@(f) H.solve_irr(f); shew=@(x) H.shewhart_tasa_const(x); return;
                end
            else
                reader=@(p) feval([nm '.read_yahoo_csv'], p);
                irrsolve=@(f) feval([nm '.solve_irr'], f);
                shew=@(x) feval([nm '.shewhart_tasa_const'], x);
                return;
            end
        end
    end
    error('No encuentro helpers (GBEeventHelper/GBEventHelpers o funciones sueltas) en el path.');
end
function s=iff(c,a,b), if c, s=a; else, s=b; end, end

% --- Helper MDD solo (VOL se calcula desde r_port) ---
function mdd = calc_MDD_only(equity_series)
    equity_series = equity_series(:);
    if numel(equity_series) < 2, mdd = NaN; return; end
    max_run = cummax(equity_series);
    dd = (equity_series - max_run) ./ max_run;
    mdd = abs(min(dd));
end
