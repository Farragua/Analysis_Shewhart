
function [entradas_filtradas_ret, num_maximos, rsi, maximos] = buscar_maximos(data, datamm, aportacion, periodos, dinero_inicial, MA, volumen, vix)
% Buscar máximos (LIVE, sin look-ahead)
% Filtros:
% 1) Precio / MM200 > umbral
% 2) RSI(14) > umbral
% 3) Ruptura mínima sobre el máx previo (lookback)
% 4) Debounce de señales (separación mínima + requisito de reentrada)
% 5) VIX en rango [vix_min, vix_max]
%
% Salidas:
% - entradas_filtradas_ret: índices de las señales válidas
% - num_maximos: número total de señales
% - rsi: RSI(14) de Wilder
% - maximos: vector del tamaño de 'data' con NaN salvo en las señales

%fprintf("Buscar máximos LIVE (ruptura mínima + debounce + VIX en rango)\n");

% --- Parámetros base ---
rsi_len      = 14;
lookback     = 252;     % ventana para buscar el máximo previo
ratio_umbral = 1.17;    % requisito de “máximo relativo”: precio / MM200 > 1.17
umbral_rsi   = 70;

% --- Parámetros opcionales ---
min_breakout   = 0.005; % +0.5% sobre el máximo reciente (0 => basta igualarlo)
min_separacion = 5;     % velas mínimas entre señales (0 desactiva)
reentrada_pct  = 0.003; % +0.3% vs última señal para permitir reentrada antes de min_separacion

% --- Filtros VIX (ambos activos si >0) ---
vix_max = 0; % descartar si VIX > vix_max   (0 => desactiva)
vix_min = 0; % descartar si VIX < vix_min   (0 => desactiva)

% --- Alineación defensiva por si data y vix difieren ---
Ndata = numel(data);
Nvix  = numel(vix);
if Nvix ~= Ndata
    M = min(Ndata, Nvix);
    if M < 10
        error('VIX y data tienen longitudes muy distintas y no se pueden alinear de forma segura.');
    end
    data  = data(end-M+1:end);
    vix   = vix(end-M+1:end);
    % mantener datamm con margen extra para MM200 si es posible
    if numel(datamm) >= M + 200
        datamm = datamm(end-(M+200)+1:end);
    else
        % si no hay margen suficiente, continuamos igualmente (MM200 puede salir NaN al principio)
        datamm = datamm(end-M+1:end);
    end
    fprintf('Aviso: data y vix alineados al último %d elementos.\n', M);
end

% --- Indicadores ---
rsi = rsi_wilder(data, rsi_len);
[mm200, ~, ~, ~] = Medias_Moviles(datamm, data);

% --- Salidas ---
maximos = nan(size(data));
entradas_filtradas_ret = [];

% --- Estado para debounce ---
last_sig_idx   = NaN;
last_sig_price = NaN;

N = length(data);
for i = 2:N
    % Historial suficiente y datos válidos
    if i <= max([rsi_len+1, 200+1, lookback+1]) ...
            || isnan(data(i)) || isnan(mm200(i)) || isnan(rsi(i)) || isnan(vix(i))
        continue;
    end

    % ---------- FILTRO VIX: rango [vix_min, vix_max] ----------
    if (vix_max > 0 && vix(i) > vix_max)
        continue; % VIX demasiado alto
    end
    if (vix_min > 0 && vix(i) < vix_min)
        continue; % VIX demasiado bajo
    end
    % (Opcional: suavizar VIX para evitar falsos positivos)
    % vix_smooth = movmean(vix, 5);
    % if (vix_max > 0 && vix_smooth(i) > vix_max) || (vix_min > 0 && vix_smooth(i) < vix_min)
    %     continue;
    % end

    % 1) Precio suficientemente por encima de MM200 (máximo relativo)
    if (data(i) / mm200(i)) <= ratio_umbral
        continue;
    end

    % 2) RSI alto
    if rsi(i) <= umbral_rsi
        continue;
    end

    % 3) Ruptura mínima sobre el máximo previo
    prev_max = max(data(i - lookback : i - 1));
    if data(i) < prev_max * (1 + min_breakout)
        continue;
    end

    % 4) Debounce de señales
    if min_separacion > 0 && ~isnan(last_sig_idx)
        % Si estamos dentro de la ventana de separación, solo aceptar si hay
        % reentrada con mejora suficiente sobre el último precio de señal
        if i - last_sig_idx < min_separacion && data(i) < last_sig_price * (1 + reentrada_pct)
            continue;
        end
    end

    % Señal válida
    entradas_filtradas_ret(end+1) = i; %#ok<AGROW>
    maximos(i) = data(i);
    last_sig_idx   = i;
    last_sig_price = data(i);
end

num_maximos = length(entradas_filtradas_ret);
%fprintf("Entradas válidas: %d\n", num_maximos);

end


% ================= RSI de Wilder =================
function rsi = rsi_wilder(close, n)
% Devuelve vector columna con NaN iniciales; cálculo 100% causal.
close = close(:);
d  = diff(close);
up = max(d, 0);
dn = max(-d, 0);

rsi = nan(size(close));
if numel(close) < n + 1, return; end

avgU = mean(up(1:n), 'omitnan');
avgD = mean(dn(1:n), 'omitnan');

if avgD == 0
    rsi(n+1) = 100;
else
    rs = avgU / avgD;
    rsi(n+1) = 100 - 100 / (1 + rs);
end

for t = n+2:numel(close)
    avgU = (avgU * (n - 1) + up(t-1)) / n;
    avgD = (avgD * (n - 1) + dn(t-1)) / n;
    if avgD == 0
        rsi(t) = 100;
    else
        rs = avgU / avgD;
        rsi(t) = 100 - 100 / (1 + rs);
    end
end
end
