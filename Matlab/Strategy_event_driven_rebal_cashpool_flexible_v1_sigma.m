function [r, num_aportaciones, valor_final_total, detalle] = Strategy_event_driven_rebal_cashpool_flexible_v1_sigma( ...
    periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, max_cash_por_dia, upper_abs, debug)

% Portfolio Event-Driven + Reb. por bandas a CASH flexible (solo venta) + tope diario
% CAMBIOS MINIMOS:
% - r_port (retorno diario TWR) calculado ANTES de aportar/vender por rebalanceo/comprar
% - Vol anualizada desde r_port (std * sqrt(252))
% - MDD desde equity_series (activos + cash)
% - Se añade detalle.ret_series

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
if nargin<9||isempty(max_cash_por_dia), max_cash_por_dia=3000; end
if nargin<10||isempty(upper_abs), upper_abs=0.30*ones(1,length(tickers_config)); end
if nargin<11||isempty(debug),    debug=false; end

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

aportacion_mensual=1500; dinero_inicial=1000; w=weights_config(:);
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
TT=rmmissing(TT); assert(height(TT)>0);

N_total=height(TT); N_dias=min(N_total,round(252*periodos));
warmup=max([MA, n_boll, 3]); i0=max(1,N_total-(N_dias+warmup)+1);
TTw=TT(i0:end,:); dates_w=TTw.Properties.RowTimes; P_w=table2array(TTw); N_w=size(P_w,1);

mm_fun=@(x) movmean(x,[MA-1 0],'omitnan');
MM_w=zeros(N_w, num_activos);
for j = 1:num_activos
    MM_w(:,j) = mm_fun(P_w(:,j));
end

switch lower(z_engine)
    case 'bollinger'
        mu=movmean(P_w,[n_boll-1 0],1,'omitnan'); sd=movstd(P_w,[n_boll-1 0],1,'omitnan');
        Z_w=(P_w-mu)./(sd); sig_w=(Z_w<=z_threshold)&(sd>0)&(P_w<MM_w);
    case 'shewhart_tippett'
        Z_w=NaN(N_w,num_activos); for c=1:num_activos,[~,~,~,~,~,Z_w(:,c)]=shew(P_w(:,c)); end
        sig_w=(Z_w<=z_threshold)&(P_w<MM_w);
    otherwise, error('z_engine no reconocido.');
end

P=P_w(end-N_dias+1:end,:); Z=Z_w(end-N_dias+1:end,:); sig=sig_w(end-N_dias+1:end,:);
dates=dates_w(end-N_dias+1:end); N=size(P,1); T_yrs=N/252;
sig_counts=sum(sig,1);

% ---------- Aportes ----------
fechas_mens=dateshift(dates(1),'start','month',0:(periodos*12-1));
fechas_mens=fechas_mens(fechas_mens<=dates(end));
mes_idx=zeros(numel(fechas_mens),1); for k=1:numel(fechas_mens), [~,ii]=min(abs(dates-fechas_mens(k))); mes_idx(k)=ii; end
mes_idx=unique(mes_idx,'stable'); num_aportaciones=numel(mes_idx);

% ---------- Estados ----------
acc=zeros(num_activos,1); cash_bal=0; dias_tope=0;

% Arrays para MDD y VOL (TWR)
equity_series = zeros(N, 1);     % equity día a día (activos + cash)
r_port = nan(N,1);               % retorno TWR (sin flujos del propio día)
precios_prev = P(1,:).';         % precios "día anterior" para TWR

% Tracking
compras_idx=[]; compras_dst={}; compras_amt=[]; compras_px=[]; compras_z=[];
buy_counts=zeros(1,num_activos); ventas_idx=[]; ventas_dst={}; ventas_eur=[]; activaciones_count=zeros(num_activos,1);
cash_hist=zeros(N,1);

% Inversion inicial por pesos
if dinero_inicial>0
    p1=P(1,:).'; 
    init_weights = w * dinero_inicial;
    acc=acc+(init_weights./p1); 
end

% ---------- Bucle ----------
for i=1:N
    precios=P(i,:).';

    % (1) Retorno TWR ANTES de cualquier flujo del día (aportación / rebalanceo a cash / compras)
    if i==1
        r_port(i) = NaN; % sin retorno el primer día
    else
        valor_inicio = sum(acc .* precios_prev) + cash_bal; % cash rinde 0
        if valor_inicio > 0
            delta_activos = sum(acc .* (precios - precios_prev));
            r_port(i) = delta_activos / valor_inicio;
        else
            r_port(i) = 0; % o NaN si prefieres
        end
    end

    % (2) Aportación mensual (después de medir r_port)
    if any(i==mes_idx), cash_bal=cash_bal+aportacion_mensual; end

    % (3) Reb a CASH (venta del exceso)
    valores=acc.*precios; invertido=sum(valores);
    if invertido>0
        pesos=valores/invertido; target=invertido.*w; over=(pesos>upper_abs(:));
        if any(over)
            exceso=valores(over)-target(over); cash_new=sum(exceso);
            if cash_new>0
                idx_over=find(over);
                for c=idx_over(:).'
                    x=valores(c)-target(c);
                    if x>0
                        activaciones_count(c)=activaciones_count(c)+1;
                        ventas_idx(end+1,1)=i; ventas_dst{end+1,1}=tickers_config{c}; ventas_eur(end+1,1)=x;
                    end
                end
                valores(over)=target(over); cash_bal=cash_bal+cash_new;
                acc=valores./precios;
            end
        end
    end

    % (4) Compras con cap por activo + tope diario (FIX: N==1 o u≈1 => sin límite, sólo presupuesto)
    if cash_bal>1e-12 && any(sig(i,:))
        presupuesto=min(cash_bal,max_cash_por_dia);
        if presupuesto>0
            if abs(presupuesto-max_cash_por_dia)<1e-9, dias_tope=dias_tope+1; end
            valores_now=acc.*precios; invertido_now=sum(valores_now);

            idx=find(sig(i,:)); caps=zeros(numel(idx),1);
            for jj=1:numel(idx)
                c=idx(jj); u=upper_abs(c); I=invertido_now; vc=valores_now(c);
                if num_activos==1 || (1 - u) <= 1e-12
                    caps(jj) = Inf; % sin límite por cap; limitar por presupuesto
                else
                    denom = max(1 - u, eps);
                    caps(jj) = max(0,(u*I - vc)/denom);
                end
            end

            elig = (caps > 1e-12) | isinf(caps);
            if any(elig)
                amount_per = presupuesto / sum(elig);
                gastado=0;
                for jj=1:numel(idx)
                    if ~elig(jj), continue; end
                    c=idx(jj);
                    eur_c = amount_per;
                    if ~isinf(caps(jj))
                        eur_c = min(amount_per, caps(jj));
                    end
                    if eur_c<=0, continue; end
                    acc(c)=acc(c)+eur_c/precios(c); gastado=gastado+eur_c;
                    compras_idx(end+1,1)=i; compras_dst{end+1,1}=tickers_config{c}; compras_amt(end+1,1)=eur_c;
                    compras_px(end+1,1)=precios(c); compras_z(end+1,1)=Z(i,c); buy_counts(c)=buy_counts(c)+1;
                end
                cash_bal=cash_bal-gastado; % nunca < 0 en V1
            end
        end
    end

    cash_hist(i)=cash_bal;

    % (5) Tracking equity (INCLUYE flujos del propio día)
    valores_dia = acc .* precios;
    equity_series(i) = sum(valores_dia) + cash_bal;

    % (6) Actualizar precios_prev
    precios_prev = precios;
end

% ---------- Valor final e IRR ----------
precios_ult=P(end,:).'; valores=acc.*precios_ult; valor_CASH=cash_bal;
valor_final_total=sum(valores)+valor_CASH;

dias_nat=mes_idx*365/252; tiempos=T_yrs - dias_nat/365;
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

detalle.buy_counts       = buy_counts_struct;
detalle.signal_counts    = signal_counts_struct;
detalle.activaciones     = activaciones_struct;
detalle.cash_series      = cash_hist;
detalle.min_cash         = min(cash_hist);          % siempre >= 0 en V1
detalle.dias_tope        = dias_tope;
detalle.num_ventas       = numel(ventas_idx);
detalle.acciones         = acciones_struct;
detalle.valor_por_activo = valores_struct;

% Series y métricas clave
detalle.equity_series     = equity_series;
detalle.dates_series      = dates;
detalle.ret_series        = r_port;          % *** NUEVO: retornos diarios TWR
detalle.mdd               = mdd_val;
detalle.annual_volatility = annual_vol;

detalle.params = struct('periodos', periodos, 'aportacion_mensual', aportacion_mensual, ...
                       'dinero_inicial', dinero_inicial, 'tickers', {tickers_config}, ...
                       'weights', weights_config, 'upper_abs', upper_abs, 'z_engine', z_engine, ...
                       'z_threshold', z_threshold, 'MA', MA, 'max_cash_por_dia', max_cash_por_dia);

% ---------- Print ----------
if ~debug
    fprintf('=====================================================================================================================\n');
    fprintf('Portfolio Event-Driven + Reb. a CASH (%s) | %d anos | CAGR: %.2f%% | Aportes: %d | Valor final: %.2f\n', ...
        strjoin(tickers_config, '/'), periodos, r*100, num_aportaciones, valor_final_total);
    fprintf('Desglose por activo a %s:\n', datestr(dates(end),'yyyy-mm-dd'));
    for j=1:num_activos
        fprintf('  %s: %.2f EUR (%.2f%%)\n', tickers_config{j}, valores(j), 100*valores(j)/valor_final_total);
    end
    fprintf('  CASH: %.2f EUR (%.2f%%)\n', valor_CASH, 100*valor_CASH/valor_final_total);
    fprintf('  TOTAL: %.2f EUR (100%%)\n', valor_final_total);
    fprintf('=====================================================================================================================\n');
else
    fprintf('=====================================================================================================================\n');
    fprintf('Portfolio Event-Driven + Rebalanceo por bandas a CASH Flexible (solo venta)\n');
    fprintf('Tickers: %s\n', strjoin(tickers_config, ', '));
    fprintf('Pesos objetivo: %s\n', sprintf('%.1f%% ', weights_config*100));
    fprintf('Motor: %s%s | Senal: z<=%.2f & Px<MM(%d) | Tope diario: %.0f EUR\n', ...
        z_engine, iff(strcmpi(z_engine,'bollinger'), sprintf('(n=%d)',n_boll), ''), z_threshold, MA, max_cash_por_dia);
    fprintf('Techos absolutos: %s\n', sprintf('%.0f%% ', upper_abs*100));
    fprintf('MDD calculado: %.2f%% | Volatilidad anual (TWR): %.2f%%\n', mdd_val*100, annual_vol*100);
    fprintf('---------------------------------------------------------------------------------------------------------------------\n');
    fprintf('RESULTADOS:\n');
    fprintf('  CAGR (IRR): %.2f%%\n', r*100);
    fprintf('  Numero de aportaciones: %d\n', num_aportaciones);
    fprintf('  Numero de ordenes de compra: %d\n', numel(compras_idx));
    fprintf('  Numero de ventas por rebalanceo: %d\n', numel(ventas_idx));
    fprintf('  Dias con tope alcanzado: %d\n', dias_tope);
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
    if numel(equity_series) < 2
        mdd = NaN; return;
    end
    max_run = cummax(equity_series);
    dd = (equity_series - max_run) ./ max_run;
    mdd = abs(min(dd));
end
