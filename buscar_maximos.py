import numpy as np

from Medias_Moviles import Medias_Moviles


def buscar_maximos(data, datamm, aportacion, periodos, dinero_inicial, MA, volumen, vix):
    # Buscar máximos (LIVE, sin look-ahead)
    # Filtros:
    # 1) Precio / MM200 > umbral
    # 2) RSI(14) > umbral
    # 3) Ruptura mínima sobre el máx previo (lookback)
    # 4) Debounce de señales (separación mínima + requisito de reentrada)
    # 5) VIX en rango [vix_min, vix_max]
    #
    # Salidas:
    # - entradas_filtradas_ret: índices de las señales válidas (1-based, como MATLAB)
    # - num_maximos: número total de señales
    # - rsi: RSI(14) de Wilder
    # - maximos: vector del tamaño de 'data' con NaN salvo en las señales

    # --- Parámetros base ---
    rsi_len = 14
    lookback = 252      # ventana para buscar el máximo previo
    ratio_umbral = 1.17  # requisito de “máximo relativo”: precio / MM200 > 1.17
    umbral_rsi = 70

    # --- Parámetros opcionales ---
    min_breakout = 0.005  # +0.5% sobre el máximo reciente (0 => basta igualarlo)
    min_separacion = 5    # velas mínimas entre señales (0 desactiva)
    reentrada_pct = 0.003  # +0.3% vs última señal para permitir reentrada antes de min_separacion

    # --- Filtros VIX (ambos activos si >0) ---
    vix_max = 0  # descartar si VIX > vix_max   (0 => desactiva)
    vix_min = 0  # descartar si VIX < vix_min   (0 => desactiva)

    data = np.asarray(data, dtype=float).ravel()
    datamm = np.asarray(datamm, dtype=float).ravel()
    vix = np.asarray(vix, dtype=float).ravel()

    # --- Alineación defensiva por si data y vix difieren ---
    Ndata = data.size
    Nvix = vix.size
    if Nvix != Ndata:
        M = min(Ndata, Nvix)
        if M < 10:
            raise ValueError('VIX y data tienen longitudes muy distintas y no se pueden alinear de forma segura.')
        data = data[data.size - M:]
        vix = vix[vix.size - M:]
        # mantener datamm con margen extra para MM200 si es posible
        if datamm.size >= M + 200:
            datamm = datamm[datamm.size - (M + 200):]
        else:
            # si no hay margen suficiente, continuamos igualmente (MM200 puede salir NaN al principio)
            datamm = datamm[datamm.size - M:]
        print(f'Aviso: data y vix alineados al último {M} elementos.')

    # --- Indicadores ---
    rsi = rsi_wilder(data, rsi_len)
    mm200, _, _, _ = Medias_Moviles(datamm, data)

    # --- Salidas ---
    maximos = np.full(data.shape, np.nan)
    entradas_filtradas_ret = []

    # --- Estado para debounce ---
    last_sig_idx = np.nan
    last_sig_price = np.nan

    N = len(data)
    for i in range(2, N + 1):
        # Historial suficiente y datos válidos
        if i <= max([rsi_len + 1, 200 + 1, lookback + 1]) \
                or np.isnan(data[i - 1]) or np.isnan(mm200[i - 1]) or np.isnan(rsi[i - 1]) or np.isnan(vix[i - 1]):
            continue

        # ---------- FILTRO VIX: rango [vix_min, vix_max] ----------
        if vix_max > 0 and vix[i - 1] > vix_max:
            continue  # VIX demasiado alto
        if vix_min > 0 and vix[i - 1] < vix_min:
            continue  # VIX demasiado bajo

        # 1) Precio suficientemente por encima de MM200 (máximo relativo)
        if (data[i - 1] / mm200[i - 1]) <= ratio_umbral:
            continue

        # 2) RSI alto
        if rsi[i - 1] <= umbral_rsi:
            continue

        # 3) Ruptura mínima sobre el máximo previo
        prev_max = np.max(data[i - 1 - lookback:i - 1])
        if data[i - 1] < prev_max * (1 + min_breakout):
            continue

        # 4) Debounce de señales
        if min_separacion > 0 and not np.isnan(last_sig_idx):
            # Si estamos dentro de la ventana de separación, solo aceptar si hay
            # reentrada con mejora suficiente sobre el último precio de señal
            if i - last_sig_idx < min_separacion and data[i - 1] < last_sig_price * (1 + reentrada_pct):
                continue

        # Señal válida
        entradas_filtradas_ret.append(i)
        maximos[i - 1] = data[i - 1]
        last_sig_idx = i
        last_sig_price = data[i - 1]

    entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)
    num_maximos = len(entradas_filtradas_ret)

    return entradas_filtradas_ret, num_maximos, rsi, maximos


# ================= RSI de Wilder =================
def rsi_wilder(close, n):
    # Devuelve vector columna con NaN iniciales; cálculo 100% causal.
    close = np.asarray(close, dtype=float).ravel()
    d = np.diff(close)
    up = np.maximum(d, 0)
    dn = np.maximum(-d, 0)

    rsi = np.full(close.shape, np.nan)
    if close.size < n + 1:
        return rsi

    avgU = np.nanmean(up[:n])
    avgD = np.nanmean(dn[:n])

    if avgD == 0:
        rsi[n] = 100
    else:
        rs = avgU / avgD
        rsi[n] = 100 - 100 / (1 + rs)

    for t in range(n + 2, close.size + 1):
        avgU = (avgU * (n - 1) + up[t - 2]) / n
        avgD = (avgD * (n - 1) + dn[t - 2]) / n
        if avgD == 0:
            rsi[t - 1] = 100
        else:
            rs = avgU / avgD
            rsi[t - 1] = 100 - 100 / (1 + rs)

    return rsi
