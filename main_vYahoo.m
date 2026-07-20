function main_vYahoo
clear; close all; clc;

%------------------- Parámetros --------------------------------------%
periodos            = 5;                  % años
dias_bolsa          = 252*periodos;        % ~252 días/año
dias_media_movil    = dias_bolsa + 200;    % para MM200
dinero_inicial      = 1000;
aportacion          = 1500;                % en señal < -2σ
aportacion_DCA      = 1500;                % mensual (~21 días)
MA                  = 200;                 % 25/50/100/150/200
MA_reb              = 100;                  % para compras despues de rebalanceos
bloqueos            = 0;                   % para variantes de cruz dorada/muerte
media_movil_lenta   = 200;                 % 100/150/200 (la rápida es 50)
vix_umbral          = 20;                  % 24 acciones, 28 ETFs 
N_bollinger         = 30;                   % periodos de bollinger
max_cash_por_dia    = 3000;                 % maximo a invertir cada dia para las event driven. Solo aplica en las V1!
z_engine = 'shewhart_tippett';   % 'shewhart_tippett' | 'bollinger'
msg_final = "";
header_msg = "";
%---------------------------------------------------------------------%

%% ========= Descarga UNA VEZ: Yahoo =========
% Forzar la ruta de ejecución correcta en GitHub o en Local
if ~isempty(getenv('GITHUB_WORKSPACE'))
    basePath = getenv('GITHUB_WORKSPACE'); % La ruta absoluta segura en los servidores de GitHub
else
    basePath = pwd; % Tu carpeta local en tu PC de escritorio
end

% Tabla de tickers (clave lógica, símbolo Yahoo, nombre de fichero)
tickers = {
    'SPY',   'SPY',     'SPY_yahoo.csv';
    'IWM',   'IWM',     'IWM_yahoo.csv';      % RU = IWM
    'GLD',   'GLD',     'GLD_yahoo.csv';
    'TLT',   'TLT',     'TLT_yahoo.csv';
    'SHY',   'SHY',     'SHY_yahoo.csv';
    'VIX',   '^VIX',    'VIX_yahoo.csv';
    'IEF',   'IEF',     'IEF_yahoo.csv';
    'DBC',   'DBC',     'DBC_yahoo.csv';
    'BTC-USD',   'BTC-USD',     'BTC-USD_yahoo.csv';
    % Extras
    'MSFT',  'MSFT',    'MSFT_yahoo.csv';
    'GOOGL', 'GOOGL',   'GOOGL_yahoo.csv';
    'META',  'META',    'META_yahoo.csv';
    'AMZN',  'AMZN',    'AMZN_yahoo.csv';
    'QQQ',  'QQQ',    'QQQ_yahoo.csv';
    'AAPL',  'AAPL',    'AAPL_yahoo.csv';
    'TLT5.L',  'TLT5.L',    'TLT5_yahoo.csv';
    'NVDA',  'NVDA',    'NVDA_yahoo.csv';
    'RACE.MI', 'RACE.MI', 'RACE_yahoo.csv';
    'ASTS' , 'ASTS', 'ASTS_yahoo.csv';
    'MA' , 'MA', 'MA_yahoo.csv';
    'RMS.PA' , 'RMS.PA', 'Hermes_yahoo.csv';
    'VST' , 'VST', 'Vistra_yahoo.csv';
    'V', 'V', 'Visa_yahoo.csv';
    'UBER', 'UBER', 'UBER_yahoo.csv';


    % Biotecnologicas especulativas
    'VKTX' , 'VKTX', 'VKTX_yahoo.csv';
    'KRMD' , 'KRMD', 'KRMD_yahoo.csv';
    'SLS' , 'SLS', 'SLS_yahoo.csv';
    'VANI' , 'VANI', 'VANI_yahoo.csv';
    'RANI' , 'RANI', 'RANI_yahoo.csv';
    'DFTX' , 'DFTX', 'DFTX_yahoo.csv';


    


};

% Rango temporal
startDate = '2000-01-01';
endDate   = ''; % hoy

% Descarga (o reutiliza) y guarda rutas
paths = containers.Map('KeyType','char','ValueType','char');
for i = 1:size(tickers,1)
    key   = tickers{i,1};
    sym   = tickers{i,2};
    fname = tickers{i,3};
    fp    = fullfile(basePath, fname);
    try
        ensure_yahoo_csv(sym, fp, startDate, endDate);
    catch ME
        error('Fallo preparando %s (%s): %s', key, sym, ME.message);
    end
    paths(key) = fp;
end


% === Elegir activo para evaluar ===
%asset = "VST";  % <- cambia aquí: 'SPY','IWM','GLD','TLT','SHY','NA9','MSFT','GOOGL','META'
assets = ["MSFT","GOOGL","META","AMZN","MA","V","ASTS","VST","UBER","GLD"];

n_iteraciones=length(assets);

for i=1:n_iteraciones
asset=assets(i)
if ~isKey(paths, upper(asset)), error('Activo no soportado: %s', asset); end
chosen_fp = paths(upper(asset));
fp_VIX    = paths('VIX');

%% ========= Lectura + Alineación por fecha (LEFT JOIN del activo con VIX) =========
[px_asset, vol_asset, dt_asset] = read_yahoo_csv(chosen_fp); % activo
[vix_full,  ~,        dt_vix]   = read_yahoo_csv(fp_VIX);    % VIX

% Normalización defensiva
px_asset = double(px_asset(:));
dt_asset = dt_asset(:);
if ~isempty(vol_asset), vol_asset = double(vol_asset(:)); end

TT_asset = timetable(dt_asset, px_asset, vol_asset, ...
    'VariableNames', {'Close','Vol'});
TT_vix   = timetable(dt_vix,   double(vix_full(:)), ...
    'VariableNames', {'VIX'});

% Left join manual: union + filtro por fechas del activo
TT_all  = synchronize(TT_asset, TT_vix, 'union', 'fillwithmissing');
mask    = ismember(TT_all.Properties.RowTimes, TT_asset.Properties.RowTimes);
TT_left = TT_all(mask, :);   % mismas fechas que el ACTIVO (VIX puede quedar NaN)

% Guardas básicas
L = height(TT_left);
assert(L>0, 'No hay solape temporal entre activo y VIX (o datos vacíos).');

useD    = min(dias_bolsa, L);
useDmm  = min(dias_media_movil, L);

TTp   = TT_left(end-useD+1:end,   :);   % ventana para señales
TTmm  = TT_left(end-useDmm+1:end, :);   % ventana extendida para MM

data    = double(TTp.Close(:));         % precios
datamm  = double(TTmm.Close(:));        % para MM
volumen = TTp.Vol;                      % puede ser []
vix     = TTp.VIX;                      % puede ser NaN
ultima_fecha = TTp.Properties.RowTimes(end);

% Más guardas (evita divisiones por cero/NaN en primeros pasos)
assert(numel(data) >= 50, 'Muy pocos datos del activo tras recorte.');
data = fillmissing(data,'previous');   % si hubiera NaN sueltos
datamm = fillmissing(datamm,'previous');

%% ========= Tu flujo original (mismas llamadas/firmas) =========

% Dinero si solo buy&hold
if data(1) == 0 || isnan(data(1))
    error('Precio inicial inválido (0/NaN). Revisa el CSV del activo.');
end
dinero_final_lump = dinero_inicial / data(1) * data(end);

% Shewhart (tasa %, media global y sigma Tippett)
entradas_3s = []; entradas_2s = [];
try
    [entradas_3s, entradas_2s, tasa, media_sh, sigma_t] = Shewhart(data);
    %plotGraficoShewhart_tasa(tasa, media_sh, sigma_t); %removed for the
    %web version
catch ME
    warning('Plot Shewhart omitido (%s). Sigo con el cálculo.', ME.message);
    [entradas_3s, entradas_2s, ~, ~, ~] = Shewhart(data);
end

% CAGR sin aportaciones
r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos);

% ===== Estrategias base =====
enableMA = 0;
[r_2s, num_aportaciones_2s, entradas_filtradas] = calcularCAGR_aportaciones( ...
    entradas_2s, data, datamm, aportacion, periodos, dinero_inicial, ...
    enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

[r_DCA, num_aportaciones_DCA] = calcularCAGR_aportaciones_DCA(data, 21, aportacion_DCA, dinero_inicial);

% Shewhart -2σ + MM(100/200)
enableMA = 1; 
[r_2smm, num_aportaciones_2smm, entradas_2smm] = calcularCAGR_aportaciones( ...
    entradas_2s, data, datamm, aportacion, periodos, dinero_inicial, ...
    enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

% % También 3σ+MM
% [r_3smm, num_aportaciones_3smm, entradas_3smm] = calcularCAGR_aportaciones( ...
%     entradas_3s, data, datamm, aportacion, periodos, dinero_inicial, ...
%     enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);
% 
% % Shewhart -2σ + MM(100)
% MA = 100;
% [r_2smm100, num_aportaciones_2smm100, entradas_2smm100] = calcularCAGR_aportaciones( ...
%     entradas_2s, data, datamm, aportacion, periodos, dinero_inicial, ...
%     1, MA, bloqueos, media_movil_lenta, volumen, vix);
% 
% % Cruz dorada (usa entradas ya filtradas por MM200)
% MA = 200; enableMA = 3;
% [r_3sgc, num_aportaciones_3sgc, entradas_3sgc] = calcularCAGR_aportaciones( ...
%     entradas_3smm, data, datamm, aportacion, periodos, dinero_inicial, ...
%     enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

[r_2sgc, num_aportaciones_2sgc, entradas2sgc] = calcularCAGR_aportaciones( ...
    entradas_2smm, data, datamm, aportacion, periodos, dinero_inicial, ...
    enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

% Tendencia alcista (MM50 > MM_lenta)
enableMA = 4;
[r_2alcista, num_aportaciones_2alcista, entradas2alcista] = calcularCAGR_aportaciones( ...
    entradas_2smm, data, datamm, aportacion, periodos, dinero_inicial, ...
    enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

% Volumen alto
enableMA = 5;
[r_2vol, num_aportaciones_2vol, entradas_2vol] = calcularCAGR_aportaciones( ...
    entradas_2smm, data, datamm, aportacion, periodos, dinero_inicial, ...
    enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

% RSI (ejemplo con entradas -2σ sobre MM100)
% enableMA = 6;
% [r_2rsi, num_aportaciones_2rsi, entradas_2rsi, rsi] = calcularCAGR_aportaciones( ...
%     entradas_2smm100, data, datamm, aportacion, periodos, dinero_inicial, ...
%     enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

[entradas_filtradas_max, num_maximos, rsi2, maximos] = buscar_maximos(data, datamm, aportacion, periodos, dinero_inicial, MA, volumen, vix);

% MM + VIX
enableMA = 7;
[r_2mmvix, num_aportaciones_2mmvix, entradas_2mmvix, rsi3] = calcularCAGR_aportaciones( ...
    entradas_2smm, data, datamm, aportacion, periodos, dinero_inicial, ...
    enableMA, MA, bloqueos, media_movil_lenta, volumen, vix, vix_umbral);

% Bollinger
enableMA = 0;
[r_bb, num_aportaciones_bb, entradas_bb, entradas_fitradas_bb, rsi4,bb_inf,bb_sup,bb_sigma] = calcularCAGR_aportaciones_bollinger( ...
    data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, volumen, vix, vix_umbral, N_bollinger);

enableMA = 1; %MA = 200;
[r_bbmm, num_aportaciones_bbmm, entradas_bb2, entradas_fitradas_bbmm, rsi5,bb_inf,bb_sup,bb_sigma] = calcularCAGR_aportaciones_bollinger( ...
    data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, volumen, vix, vix_umbral, N_bollinger);

enableMA = 2; %MA = 200;
[r_bbmmvix, num_aportaciones_bbmmvix, entradas_bb3, entradas_fitradas_bbmmvix, rsi6,bb_inf,bb_sup,bb_sigma] = calcularCAGR_aportaciones_bollinger( ...
    data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, volumen, vix, vix_umbral, N_bollinger);

fprintf("========== CAGR PARA DIFERENTES ESTRATEGIAS (%d años) - aportaciones constantes ==========\n\n", periodos);
fprintf('%-72s %8.2f%%\n','Estrategia 1: Sin aportaciones:', r * 100);
fprintf('%-72s %8.2f%% (%3d entradas)\n','Estrategia 2: DCA mensual:', r_DCA * 100, num_aportaciones_DCA);
fprintf('%-72s %8.2f%% (%3d entradas)\n','Estrategia 3a: Shewhart, aportaciones a -2σ:', r_2s * 100, num_aportaciones_2s);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 3b: Shewhart, -2σ y MM (%d):', MA), r_2smm * 100, num_aportaciones_2smm);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 3c: Shewhart, -2σ, MM (%d) y VIX > %d:', MA, vix_umbral), r_2mmvix * 100, num_aportaciones_2mmvix);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 3d: Shewhart, -2σ, MM (%d) y tendencia alcista:', MA), r_2alcista * 100, num_aportaciones_2alcista);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 3e: Shewhart, -2σ, MM (%d) y volumen alto:', MA), r_2vol * 100, num_aportaciones_2vol);
%fprintf('%-72s %8.2f%% (%3d entradas)\n','Estrategia 3f: Shewhart, -2σ, MM (100) y 30 < RSI < 60:', r_2rsi * 100, num_aportaciones_2rsi);
fprintf('%-72s %8.2f%% (%3d entradas)\n', sprintf('Estrategia 4a: Bollinger contrarian (N=%d):', N_bollinger), r_bb * 100, num_aportaciones_bb);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 4b: Bollinger contrarian, MM (%d):', MA), r_bbmm * 100, num_aportaciones_bbmm);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 4c: Bollinger contrarian, MM (%d) y VIX > %d:', MA, vix_umbral), r_bbmmvix * 100, num_aportaciones_bbmmvix);
fprintf("\nÚltima fecha: %s\n", datestr(ultima_fecha,'yyyy-mm-dd'));
fprintf("\n====================================================================\n");

% ===== Gráficas =====
try
    [mm200, mm150, mm100, mm50] = Medias_Moviles(datamm, data);
    % plotMediasMoviles(mm200, mm150, mm100, mm50, periodos, data, entradas_3s, entradas_2s, bloqueos, media_movil_lenta,asset,volumen,vix,entradas_2mmvix,vix_umbral);
    % plotMediasMoviles_bb(mm200, mm150, mm100, mm50, periodos, data, entradas_bb,asset, N_bollinger,bb_sigma,bb_sup,bb_inf,2,volumen,vix,entradas_fitradas_bbmmvix,vix_umbral);
catch ME
    warning('Se omitieron algunas gráficas (%s).', ME.message);
end

% ===== Ponderaciones por nº de entradas =====
enableMA = 1; %MA = 200;
[r_2smm, num_aportaciones_2smm, entradas_2smm] = calcularCAGR_aportaciones( ...
    entradas_2s, data, datamm, num_aportaciones_2s/max(1,num_aportaciones_2smm)*aportacion, ...
    periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

enableMA = 4;
[r_2alcista, num_aportaciones_2alcista, entradas2alcista] = calcularCAGR_aportaciones( ...
    entradas_2smm, data, datamm, num_aportaciones_2s/max(1,num_aportaciones_2alcista)*aportacion, ...
    periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

enableMA = 5;
[r_2vol, num_aportaciones_2vol, entradas_2vol] = calcularCAGR_aportaciones( ...
    entradas_2smm, data, datamm, num_aportaciones_2s/max(1,num_aportaciones_2vol)*aportacion, ...
    periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

% enableMA = 6;
% [r_2rsi, num_aportaciones_2rsi, entradas_2rsi, rsi] = calcularCAGR_aportaciones( ...
%     entradas_2smm100, data, datamm, num_aportaciones_2s/max(1,num_aportaciones_2rsi)*aportacion, ...
%     periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen, vix);

[entradas_filtradas_max, num_maximos, rsi, maximos] = buscar_maximos(data, datamm, aportacion, periodos, dinero_inicial, MA, volumen, vix);

enableMA = 7;
[r_2mmvix, num_aportaciones_2mmvix, entradas_2mmvix, rsi] = calcularCAGR_aportaciones( ...
    entradas_2smm, data, datamm, num_aportaciones_2s/max(1,num_aportaciones_2mmvix)*aportacion, ...
    periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen, vix, vix_umbral);

enableMA = 0;
[r_bb, num_aportaciones_bb, entradas_bb, entradas_fitradas_bb, rsi,bb_inf,bb_sup,bb_sigma] = calcularCAGR_aportaciones_bollinger( ...
    data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, volumen, vix, vix_umbral, N_bollinger);

enableMA = 1; %MA = 200;
[r_bbmm, num_aportaciones_bbmm, entradas_bb, entradas_fitradas_bbmm, rsi,bb_inf,bb_sup,bb_sigma] = calcularCAGR_aportaciones_bollinger( ...
    data, datamm, num_aportaciones_bb/max(1,num_aportaciones_bbmm)*aportacion, periodos, dinero_inicial, ...
    enableMA, MA, volumen, vix, vix_umbral, N_bollinger);

enableMA = 2; %VIX > vix_umbral;
[r_bbmmvix, num_aportaciones_bbmmvix, entradas_bb, entradas_fitradas_bbmmvix, rsi,bb_inf,bb_sup,bb_sigma] = calcularCAGR_aportaciones_bollinger( ...
    data, datamm, num_aportaciones_bb/max(1,num_aportaciones_bbmmvix)*aportacion, periodos, dinero_inicial, ...
    enableMA, MA, volumen, vix, vix_umbral, N_bollinger);

fprintf("========== CAGR PARA DIFERENTES ESTRATEGIAS (%d años) - aportaciones ponderadas ==========\n\n", periodos);
fprintf('%-72s %8.2f%%\n','Estrategia 1: Sin aportaciones:', r * 100);
fprintf('%-72s %8.2f%% (%3d entradas)\n','Estrategia 2: DCA mensual:', r_DCA * 100, num_aportaciones_DCA);
fprintf('%-72s %8.2f%% (%3d entradas)\n','Estrategia 3a: Shewhart, aportaciones a -2σ:', r_2s * 100, num_aportaciones_2s);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 3b: Shewhart, -2σ y MM (%d):', MA), r_2smm * 100, num_aportaciones_2smm);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 3c: Shewhart, -2σ, MM (%d) y VIX > %d:', MA, vix_umbral), r_2mmvix * 100, num_aportaciones_2mmvix);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 3d: Shewhart, -2σ, MM (%d) y tendencia alcista:', MA), r_2alcista * 100, num_aportaciones_2alcista);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 3e: Shewhart, -2σ, MM (%d) y volumen alto:', MA), r_2vol * 100, num_aportaciones_2vol);
%fprintf('%-72s %8.2f%% (%3d entradas)\n','Estrategia 3f: Shewhart, -2σ, MM (100) y 30 < RSI < 60:', r_2rsi * 100, num_aportaciones_2rsi);
fprintf('%-72s %8.2f%% (%3d entradas)\n', sprintf('Estrategia 4a: Bollinger contrarian (N=%d):', N_bollinger), r_bb * 100, num_aportaciones_bb);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 4b: Bollinger contrarian, MM (%d):', MA), r_bbmm * 100, num_aportaciones_bbmm);
fprintf('%-72s %8.2f%% (%3d entradas)\n',sprintf('Estrategia 4c: Bollinger contrarian, MM (%d) y VIX > %d:', MA, vix_umbral), r_bbmmvix * 100, num_aportaciones_bbmmvix);
fprintf("\nÚltima fecha: %s\n", datestr(ultima_fecha,'yyyy-mm-dd'));
fprintf("\n====================================================================\n");



[msg] = sendNotification(asset, data, entradas_2smm, entradas_2mmvix,mm200(end));
fprintf('%s\n', msg)

msg_final = msg_final + msg + newline;

end
fprintf("\n")

% =========================================================================
% CREACIÓN DEL HEADER Y CONCATENACIÓN FINAL
% =========================================================================

% 1. Creamos las variables de la cabecera
fecha_cabecera = datestr(now, 'dd-mmm-yyyy');
vix_actual = vix(end); % Ahora que el bucle terminó, 'vix' ya contiene datos

% 2. Construimos el header usando corchetes [] para evitar el error de tamaños
header_msg = [ ...
    sprintf('==============================\n'), ...
    sprintf('📅 DATE: %s\n', fecha_cabecera), ...
    sprintf('📈 VIX INDEX: %.2f\n', vix_actual), ...
    sprintf('==============================\n\n') ...
];

% 3. Concatenamos el header AL PRINCIPIO del msg_final acumulado
msg_final = header_msg + msg_final;

% 4. Mostramos el resultado en la consola de GitHub
fprintf(msg_final);


% % =========================================================================
% % ENVÍO DE CORREO:
% % =========================================================================
% 
% % 1. Extraer las credenciales ocultas de los Secrets de GitHub
% mail_remitente   = getenv('EMAIL_USER');
% password_envio   = getenv('EMAIL_PASS');
% %mail_destinatario = 'icg1408@gmail.com'; % <- Pon tu correo aquí
% 
%  mail_destinatario = {'icg1408@gmail.com', ...
%                       'pozo.dionisio@gmail.com', ...
%                       'gustems.maestre@gmail.com'};                      
% 
% % mail_destinatario = 'ic1408@gmail.com, pozo.dionisio@gmail.com, gustems.maestre@gmail.com';
% 
% % 2. Convertimos la lista en una sola cadena de texto separada por comas
% mail_destinatario = strjoin(mail_destinatario, ', ');
% 
% 
% % Control defensivo por si GitHub no inyectó bien las variables
% if isempty(mail_remitente) || isempty(password_envio)
%     error('Las credenciales de correo desde los Secrets de GitHub llegaron VACÍAS a MATLAB.');
% end
% 
% % Forzar a que sean cadenas de texto limpias (elimina espacios invisibles)
% mail_remitente = strtrim(char(mail_remitente));
% password_envio = strtrim(char(password_envio));
% 
% 
% % 2. Configurar las propiedades del servidor de correo (Gmail)
% setpref('Internet', 'SMTP_Server', 'smtp.gmail.com');
% setpref('Internet', 'SMTP_Username', mail_remitente);
% setpref('Internet', 'SMTP_Password', password_envio);
% 
% % 3. Configurar la seguridad TLS
% props = java.lang.System.getProperties;
% props.setProperty('mail.smtp.auth', 'true');
% props.setProperty('mail.smtp.starttls.enable', 'true');
% props.setProperty('mail.smtp.port', '587');
% 
% % 4. Enviar el correo siempre (una vez al día) al terminar el análisis
% asunto = ['📊 Reporte Diario de Trading - ', datestr(now, 'yyyy-mm-dd')];
% 
% try
%     sendmail(mail_destinatario, asunto, msg_final);
%     disp('✉️ Correo diario enviado con éxito desde la nube.');
% catch ME
%     warning('❌ Error al enviar el correo: %s', ME.message);
% end


% =========================================================================
% ENVÍO DE CORREO (MULTIDESTINATARIO COMPATIBLE)
% =========================================================================

% 1. Extraer credenciales
mail_remitente = getenv('EMAIL_USER');
password_envio = getenv('EMAIL_PASS');

% 2. Lista de destinatarios en formato de celda limpia
mail_destinatario = { ...
    'icg1408@gmail.com', ...
    'pozo.dionisio@gmail.com', ...
    'gustems.maestre@gmail.com' ...
};

% Control defensivo de credenciales
if isempty(mail_remitente) || isempty(password_envio)
    error('Las credenciales de correo desde los Secrets de GitHub llegaron VACÍAS a MATLAB.');
end

mail_remitente = strtrim(char(mail_remitente));
password_envio = strtrim(char(password_envio));

% Limpiar espacios invisibles de cada correo de destino
mail_destinatario = cellfun(@strtrim, mail_destinatario, 'UniformOutput', false);

% 3. Configurar servidor SMTP de Gmail
setpref('Internet', 'SMTP_Server', 'smtp.gmail.com');
setpref('Internet', 'SMTP_Username', mail_remitente);
setpref('Internet', 'SMTP_Password', password_envio);

% 4. Configurar TLS
props = java.lang.System.getProperties;
props.setProperty('mail.smtp.auth', 'true');
props.setProperty('mail.smtp.starttls.enable', 'true');
props.setProperty('mail.smtp.port', '587');
props.setProperty('mail.smtp.ssl.protocols', 'TLSv1.2');

% 5. Enviar el correo
asunto = ['📊 Reporte Diario de Trading - ', datestr(now, 'yyyy-mm-dd')];

try
    % MATLAB maneja arreglos de celdas directamente en sendmail
    sendmail(mail_destinatario, asunto, msg_final);
    disp('✉️ Correo diario enviado con éxito a todos los destinatarios.');
catch ME
    warning('❌ Error al enviar el correo: %s', ME.message);
end

%------------------------------------------------------------------------------------------------------------------------
%% PORTFOLIO ANALYSIS:
%------------------------------------------------------------------------------------------------------------------------



%[r_allw_simp, num_aportaciones_allw_simp, valor_final_total_allw_simp, detalle_allw_simp] = all_weather_simple_run(periodos, basePath);
%[r_allw_suave, num_aportaciones_allw_suave, valor_final_total_allw_suave, detalle_allw_suave] = all_weather_run_soft(periodos, basePath);
%[r_allw_c, num_aportaciones_allw_c, valor_final_total_allw_c, detalle_allw_c] = all_weather_custom_run(periodos, basePath);
%[r_macro, num_aportaciones_macro, valor_final_total_macro, detalle_macro] = cartera_macro_run(periodos, basePath);
%[r_macro_soft, num_aportaciones_macro_soft, valor_final_total_macro_soft, detalle_macro_soft] = cartera_macro_run_soft(periodos, basePath);
%[r, num_aportaciones, valor_final_total, detalle] = cartera_macro_event_bandas_signals_run(periodos, basePath);

% Cartera All-Weather
% tickers = {'SPY', 'TLT', 'IEF', 'GLD', 'DBC'};
% weights = [0.30, 0.40, 0.15, 0.075, 0.075];
% weight_limits = [0.4, 0.5, 0.2, 0.1, 0.09];
% main_portfolio_flexible_calmar("All-Weather", tickers, weights, basePath, periodos,MA, weight_limits,max_cash_por_dia,MA_reb,z_engine,N_bollinger);


% Cartera Golden Butterfly
% tickers = {'SPY', 'IWM', 'GLD', 'TLT', 'SHY'};
% weights = [0.20, 0.20, 0.20, 0.20, 0.20];
% weight_limits = [0.3, 0.25, 0.3, 0.24, 0.24];
% main_portfolio_flexible_calmar("Golden-Butterfly", tickers, weights, basePath, periodos,MA, weight_limits,max_cash_por_dia,MA_reb,z_engine,N_bollinger);


% Cartera Tecnologica
% tickers = {'MSFT', 'GOOGL', 'META', 'AMZN', 'AAPL', 'NVDA'};
% weights = [1/6, 1/6, 1/6, 1/6, 1/6, 1/6];
% weight_limits = [0.21, 0.21, 0.21, 0.21, 0.21, 0.21];
% main_portfolio_flexible_calmar("Tecnologicas", tickers, weights, basePath, periodos,MA, weight_limits,max_cash_por_dia,MA_reb,z_engine,N_bollinger);

% % %Cartera Macro optimizada (75% RV - 10% RF/LP - 15% GLD) 
% tickers = {'SPY', 'IWM', 'TLT','GLD'};
% weights = [0.6, 0.15, 0.10, 0.15];
% weight_limits = [0.65, 0.25, 0.12, 0.19];
% main_portfolio_flexible_calmar("Cartera Macro", tickers, weights, basePath, periodos, MA, weight_limits,max_cash_por_dia,MA_reb,z_engine,N_bollinger);


% %Cartera Macro defensiva (55% RV - 10% RF/LP - 10% RF/MP - 10% RF/CP - 15% GLD) 
% tickers = {'SPY', 'IWM', 'TLT', 'IEF', 'SHY', 'GLD'};
% weights = [0.45, 0.10, 0.10, 0.10, 0.10, 0.15];
% weight_limits = [0.5, 0.15, 0.12, 0.12, 0.12, 0.19];
% main_portfolio_flexible_calmar("Cartera Macro Defensiva", tickers, weights, basePath, periodos, MA, weight_limits,max_cash_por_dia,MA_reb,z_engine,N_bollinger);

%Cartera Macro agresiva (85% RV - 15% GLD)
 % tickers = {'SPY','QQQ', 'IWM', 'GLD'};
 % weights = [0.50, 0.25 , 0.10, 0.15];
 % weight_limits = [0.66, 0.33, 0.13, 0.18];
 % main_portfolio_flexible_calmar("Cartera Macro Agresiva", tickers, weights, basePath, periodos, MA, weight_limits, max_cash_por_dia,MA_reb,z_engine,N_bollinger);
end % main

%% ===================== HELPERS LOCALES =====================

function ensure_yahoo_csv(ticker, outPath, startDateStr, endDateStr)
    % === 1) Reutilizar por CONTENIDO (chequear última fecha del CSV) ===
    if isfile(outPath)
        try
            T = readtable(outPath);
            if ~isempty(T) && width(T) >= 2 && height(T) > 1
                names = lower(strrep(strrep(T.Properties.VariableNames,'_',''),' ','')); % quitar espacios
                iDate = find(strcmp(names,'date'),1);
                if isempty(iDate), iDate = 1; end
                dt = T{:, iDate};
                if ~isdatetime(dt)
                    if isnumeric(dt)
                        dt = datetime(dt,'ConvertFrom','datenum');
                    elseif iscellstr(dt) || isstring(dt)
                        try
                            dt = datetime(dt,'InputFormat','yyyy-MM-dd','Locale','en_US');
                        catch
                            dt = datetime(dt);
                        end
                    else
                        dt = datetime(dt);
                    end
                end

                dt = dt(~isnat(dt));
                if ~isempty(dt)
                    last_dt = dt(end);

                    % Último día hábil esperado (aprox)
                    today0 = dateshift(datetime('today'),'start','day');
                    wd = weekday(today0); % 1=Domingo ... 7=Sábado
                    if wd == 1
                        last_expected = today0 - days(2);
                    elseif wd == 2
                        last_expected = today0 - days(3);
                    else
                        last_expected = today0 - days(1);
                    end

                    if last_dt >= last_expected
                        fprintf('[Yahoo] %s CSV vigente (hasta %s). Reutilizo.\n', ...
                            ticker, datestr(last_dt,'yyyy-MM-dd'));
                        return
                    else
                        fprintf('[Yahoo] %s CSV desactualizado (última %s < esperada %s). Refresco.\n', ...
                            ticker, datestr(last_dt,'yyyy-MM-dd'), datestr(last_expected,'yyyy-MM-dd'));
                    end
                end
            end
        catch
            % si falla la lectura, seguimos y descargamos
        end
    end

    % === 2) Descargar directamente desde /v8 (chart) y construir CSV ===
    p1 = posixtime(datetime(startDateStr,'InputFormat','yyyy-MM-dd'));
    if isempty(endDateStr)
        p2 = posixtime(dateshift(datetime('today'),'start','day') + days(1)); % mañana 00:00
    else
        p2 = posixtime(datetime(endDateStr,'InputFormat','yyyy-MM-dd'));
    end

    yahoo_chart_to_csv(ticker, outPath, p1, p2);
    if countlines_local(outPath) <= 1
        error('CSV vacío tras /v8 para %s', ticker);
    end
    fprintf('[Yahoo] %s guardado desde /v8 chart (%d filas).\n', ticker, countlines_local(outPath)-1);
end

function yahoo_chart_to_csv(ticker, outPath, p1, p2)
    % /v8 chart → CSV Date,Open,High,Low,Close,AdjClose,Volume (AdjClose SIN espacio)
    ua   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123 Safari/537.36';
    opts = weboptions('Timeout', 30, 'UserAgent', ua, 'ContentType','json');
    tkr  = strrep(ticker,'^','%5E');
    url8 = sprintf(['https://query1.finance.yahoo.com/v8/finance/chart/%s?', ...
                    'period1=%d&period2=%d&interval=1d&includePrePost=false&events=div%%2Csplit'], ...
                    tkr, uint64(p1), uint64(p2));

    S = webread(url8, opts);
    if ~isfield(S,'chart') || ~isfield(S.chart,'result') || isempty(S.chart.result)
        error('Respuesta /v8 inválida para %s.', ticker);
    end
    % OJO: result es struct array, no celda
    R = S.chart.result(1);

    if ~isfield(R,'timestamp') || isempty(R.timestamp)
        error('Sin timestamps en /v8 chart para %s.', ticker);
    end

    ts = R.timestamp(:);
    q  = R.indicators.quote(1);
    op  = q.open(:);
    hi  = q.high(:);
    lo  = q.low(:);
    cl  = q.close(:);
    vol = q.volume(:);
    if isfield(R.indicators,'adjclose') && ~isempty(R.indicators.adjclose)
        adj = R.indicators.adjclose(1).adjclose(:);
    else
        adj = cl;
    end

    n   = numel(ts);
    op  = fixlen(op,n); hi = fixlen(hi,n); lo = fixlen(lo,n);
    cl  = fixlen(cl,n); adj = fixlen(adj,n); vol = fixlen(vol,n);

    dt  = datetime(ts,'ConvertFrom','posixtime','TimeZone','UTC');
    dt.TimeZone = ''; % naive

    % Escribir CSV con cabecera sin espacios en AdjClose
    [fid, msg_err] = fopen(outPath,'w');
    if fid < 0
    error('No se pudo abrir el archivo para escribir: %s. Razón: %s', outPath, msg_err);
    end
    fprintf(fid,'Date,Open,High,Low,Close,AdjClose,Volume\n');
    for i=1:n
        if ~isnan(cl(i)) && ~isnat(dt(i))
            fprintf(fid,'%s,%.10g,%.10g,%.10g,%.10g,%.10g,%.0f\n', ...
                datestr(dt(i),'yyyy-mm-dd'), op(i), hi(i), lo(i), cl(i), adj(i), vol(i));
        end
    end
    fclose(fid);

    function v = fixlen(v, m)
        if isempty(v), v = nan(m,1); return; end
        v = v(:);
        if numel(v) ~= m
            k = min(numel(v), m);
            w = nan(m,1); w(1:k) = v(1:k); v = w;
        end
    end
end

function [close_prices, volume, dates] = read_yahoo_csv(csvPath)
    if ~isfile(csvPath), error('Archivo no encontrado: %s', csvPath); end
    T = readtable(csvPath);
    if isempty(T) || width(T)==0 || height(T)==0
        error('CSV vacío o sin filas: %s', csvPath);
    end
    % Normalizar nombres (sin espacios ni guiones bajos)
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

    % Precio: AdjClose > Close
    iAdj   = find(strcmp(names,'adjclose'),1);
    iClose = find(strcmp(names,'close'),1);
    if ~isempty(iAdj)
        y = T{:,iAdj};
    elseif ~isempty(iClose)
        y = T{:,iClose};
    else
        y = T{:,end};
        warning('No se encontró AdjClose/Close en %s, usando última columna.', csvPath);
    end
    if iscellstr(y) || isstring(y), y = str2double(strrep(string(y),',','.')); end
    if ~isfloat(y), y = double(y); end

    % Volumen (si existe)
    iVol = find(strcmp(names,'volume'),1);
    if isempty(iVol)
        volume = [];
    else
        v = T{:,iVol};
        if iscellstr(v) || isstring(v), v = str2double(strrep(string(v),',','.')); end
        if ~isfloat(v), v = double(v); end
        volume = v;
    end

    % Limpiar y ordenar
    good = ~isnat(dates) & ~isnan(y);
    dates = dates(good); y = y(good);
    if ~isempty(volume), volume = volume(good); end
    [dates, idx] = sort(dates);
    close_prices = y(idx);
    if ~isempty(volume), volume = volume(idx); end

    % Columnas
    close_prices = close_prices(:);
    if ~isempty(volume), volume = volume(:); end
end

function n = countlines_local(fname)
    fid = fopen(fname,'r'); if fid < 0, n = 0; return; end
    n = 0; while ~feof(fid), fgets(fid); n = n + 1; end; fclose(fid);
end
