"""Event-Driven + Reb. SUAVE v2 (sin filtro MA_reb para receptores)
CAMBIOS MINIMOS:
- r_port (TWR diario) calculado ANTES de flujos del día
- Vol anualizada desde r_port (std * sqrt(252))
- MDD desde equity_series (activos + cash)
- detalle.ret_series añadido
"""

import os
import re

import numpy as np
import pandas as pd

from GBEventHelpers import GBEventHelpers


def Strategy_event_driven_rebal_flexible_v2_sigma(
        periodos=None, basePath=None, tickers_config=None, weights_config=None,
        z_engine=None, n_boll=None, z_threshold=None, MA_sig=None, MA_reb=None,
        upper_abs=None, debug=None):
    # ---------- Defaults ----------
    if _isempty(tickers_config):
        raise ValueError('Debes especificar los tickers del portfolio')
    if _isempty(weights_config):
        weights_config = np.ones(len(tickers_config)) / len(tickers_config)
    if _isempty(periodos):
        periodos = 5
    if _isempty(basePath):
        basePath = 'C:\\Users\\israe\\OneDrive\\Matlab_scripts\\'
    if _isempty(z_engine):
        z_engine = 'shewhart_tippett'
    if _isempty(n_boll):
        n_boll = 22
    if _isempty(z_threshold):
        z_threshold = -2.0
    if _isempty(MA_sig):
        MA_sig = 200
    if _isempty(MA_reb):
        MA_reb = 100
    if _isempty(upper_abs):
        upper_abs = 0.30 * np.ones(len(tickers_config))
    if _isempty(debug):
        debug = False

    # Validaciones
    num_activos = len(tickers_config)
    if len(weights_config) != num_activos:
        raise ValueError('Numero de tickers (%d) debe coincidir con numero de pesos (%d)'
                         % (num_activos, len(weights_config)))
    if abs(np.sum(weights_config) - 1.0) > 1e-6:
        raise ValueError('Los pesos deben sumar 1.0. Suma actual: %.6f' % np.sum(weights_config))
    upper_abs = np.asarray(upper_abs, dtype=np.float64).ravel()
    if upper_abs.size == 1:
        upper_abs = np.full(num_activos, upper_abs[0])
    elif upper_abs.size != num_activos:
        raise ValueError('Numero de techos (%d) debe coincidir con numero de activos (%d)'
                         % (upper_abs.size, num_activos))

    aportacion_mensual = 1500
    dinero_inicial = 1000
    w = np.asarray(weights_config, dtype=np.float64).ravel()

    reader, irrsolve, shew = _get_helpers()

    # ======== Verificacion de archivos ========
    file_paths = [None] * num_activos
    for i in range(1, num_activos + 1):
        ticker = tickers_config[i - 1]
        file_paths[i - 1] = os.path.join(basePath, ticker + '_yahoo.csv')
        if not os.path.isfile(file_paths[i - 1]):
            raise ValueError('Falta archivo: %s. Ejecuta main_vYahoo.m primero.' % file_paths[i - 1])

    # ---------- Datos ----------
    series_data = [None] * num_activos
    dates_data = [None] * num_activos
    for i in range(1, num_activos + 1):
        series_data[i - 1], dates_data[i - 1] = reader(file_paths[i - 1])

    # ---------- Alinear por fechas comunes ----------
    TT_list = [None] * num_activos
    for i in range(1, num_activos + 1):
        TT_list[i - 1] = pd.Series(series_data[i - 1], index=dates_data[i - 1],
                                   name=tickers_config[i - 1])
    if num_activos == 1:
        TT = TT_list[0].to_frame()
    else:
        TT = pd.concat(TT_list, axis=1, join='inner')
    TT = TT.dropna()
    assert TT.shape[0] > 0

    N_total = TT.shape[0]
    N_dias = min(N_total, _round(252 * periodos))
    warmup = max(MA_sig, MA_reb, n_boll, 3)
    i0 = max(1, N_total - (N_dias + warmup) + 1)
    TTw = TT.iloc[i0 - 1:, :]
    dates_w = TTw.index
    P_w = TTw.to_numpy(dtype=np.float64)
    N_w = P_w.shape[0]

    MMsig_w = np.zeros((N_w, num_activos))
    for j in range(1, num_activos + 1):
        MMsig_w[:, j - 1] = pd.Series(P_w[:, j - 1]).rolling(MA_sig, min_periods=1).mean().to_numpy()

    ze = z_engine.lower()
    if ze == 'bollinger':
        mu = pd.DataFrame(P_w).rolling(n_boll, min_periods=1).mean().to_numpy()
        sd = pd.DataFrame(P_w).rolling(n_boll, min_periods=1).std(ddof=1).to_numpy()
        Z_w = (P_w - mu) / sd
        sig_w = (Z_w <= z_threshold) & (sd > 0) & (P_w < MMsig_w)
    elif ze == 'shewhart_tippett':
        Z_w = np.full((N_w, num_activos), np.nan)
        for c in range(1, num_activos + 1):
            _, _, _, _, _, Z_w[:, c - 1] = shew(P_w[:, c - 1])
        sig_w = (Z_w <= z_threshold) & (P_w < MMsig_w)
    else:
        raise ValueError('z_engine no reconocido.')

    P = P_w[N_w - N_dias:, :]
    Z = Z_w[N_w - N_dias:, :]
    sig = sig_w[N_w - N_dias:, :]
    dates = dates_w[N_w - N_dias:]
    N = P.shape[0]
    T_yrs = N / 252
    sig_counts = np.sum(sig, axis=0)

    # ---------- Aportes ----------
    fechas_mens = pd.date_range(start=pd.Timestamp(dates[0]).replace(day=1),
                                periods=(periodos * 12 - 1) + 1, freq='MS')
    fechas_mens = fechas_mens[fechas_mens <= dates[-1]]
    mes_idx = np.zeros(len(fechas_mens))
    for k in range(1, len(fechas_mens) + 1):
        ii = int(np.argmin(np.abs(dates - fechas_mens[k - 1]))) + 1
        mes_idx[k - 1] = ii
    mes_idx = pd.unique(mes_idx)
    num_aportaciones = len(mes_idx)

    # ---------- Estados ----------
    acc = np.zeros(num_activos)
    cash_bal = 0
    min_cash_alcanzado = 0
    equity_series = np.zeros(N)     # equity (activos + cash) tras flujos
    r_port = np.full(N, np.nan)     # retornos diarios TWR (antes de flujos)
    precios_prev = P[0, :]

    # Inversion inicial por pesos
    if dinero_inicial > 0:
        p1 = P[0, :]
        init_weights = w * dinero_inicial
        acc = acc + (init_weights / p1)

    compras_idx = []
    compras_dst = []
    compras_amt = []
    compras_px = []
    compras_z = []
    buy_counts = np.zeros(num_activos)
    cash_hist = np.zeros(N)
    rebalanceos_count = 0
    inversiones_por_senal = []

    # ---------- Bucle ----------
    for i in range(1, N + 1):
        precios = P[i - 1, :]

        # (1) Retorno TWR ANTES de flujos del día (cash rinde 0)
        if i == 1:
            r_port[i - 1] = np.nan
        else:
            valor_inicio = np.sum(acc * precios_prev) + cash_bal
            if valor_inicio > 0:
                delta_activos = np.sum(acc * (precios - precios_prev))
                r_port[i - 1] = delta_activos / valor_inicio
            else:
                r_port[i - 1] = 0

        # (2) Aporte mensual (después de medir r_port)
        if np.any(i == mes_idx):
            cash_bal = cash_bal + aportacion_mensual

        # ===== Rebalanceo suave SIN FILTRO MA_reb =====
        valores = acc * precios
        invertido = np.sum(valores)
        if invertido > 0:
            pesos = valores / max(invertido, np.finfo(np.float64).eps)
            target = invertido * w
            over = pesos > upper_abs
            if np.any(over):
                rebalanceos_count = rebalanceos_count + 1

                # Vender exceso hasta objetivo
                exceso = valores[over] - target[over]
                valores[over] = target[over]
                cash_tmp = np.sum(exceso)

                # Prioridad 1: reducir deuda primero
                if cash_bal < 0 and cash_tmp > 0:
                    deuda_actual = abs(cash_bal)
                    reduccion_deuda = min(deuda_actual, cash_tmp)
                    cash_bal = cash_bal + reduccion_deuda
                    cash_tmp = cash_tmp - reduccion_deuda

                # Prioridad 2: reinvertir exceso restante en receptores (todos los no-over)
                rec = ~over
                if np.any(rec):
                    deficit = np.maximum(target[rec] - valores[rec], 0)
                    sdef = np.sum(deficit)
                    if sdef > 1e-12:
                        alloc_def = cash_tmp * (deficit / max(sdef, np.finfo(np.float64).eps))
                        valores[rec] = valores[rec] + alloc_def
                        cash_tmp = cash_tmp - np.sum(alloc_def)
                    if cash_tmp > 1e-12:
                        wrec = w[rec]
                        wrec = wrec / np.sum(wrec)
                        alloc_rest = cash_tmp * wrec
                        valores[rec] = valores[rec] + alloc_rest
                        residuo = cash_tmp - np.sum(alloc_rest)
                        if residuo > 1e-9:
                            cash_bal = cash_bal + residuo
                        cash_tmp = 0
                else:
                    cash_bal = cash_bal + cash_tmp
                    cash_tmp = 0

                # Actualizar unidades
                acc = valores / precios

        # Compras por señal SIN tope (importe fijo por señal)
        if np.any(sig[i - 1, :]):
            idx = np.flatnonzero(sig[i - 1, :]) + 1
            amount_per_signal = 1500
            total_inversion_dia = 0
            for c in idx:
                acc[c - 1] = acc[c - 1] + amount_per_signal / precios[c - 1]
                cash_bal = cash_bal - amount_per_signal  # puede ser negativo
                compras_idx.append(i)
                compras_dst.append(tickers_config[c - 1])
                compras_amt.append(amount_per_signal)
                compras_px.append(precios[c - 1])
                compras_z.append(Z[i - 1, c - 1])
                buy_counts[c - 1] = buy_counts[c - 1] + 1
                total_inversion_dia = total_inversion_dia + amount_per_signal
            if total_inversion_dia > aportacion_mensual:
                inversiones_por_senal.append([i, total_inversion_dia, len(idx)])

        cash_hist[i - 1] = cash_bal
        min_cash_alcanzado = min(min_cash_alcanzado, cash_bal)

        # (3) Equity tras flujos del día
        valores_dia = acc * precios
        equity_series[i - 1] = np.sum(valores_dia) + cash_bal

        # (4) actualizar precios_prev
        precios_prev = precios

    if len(inversiones_por_senal) > 0:
        inversiones_por_senal = np.asarray(inversiones_por_senal, dtype=np.float64)
    else:
        inversiones_por_senal = np.zeros((0, 3))

    # ---------- Valor final e IRR ----------
    precios_ult = P[-1, :]
    valores = acc * precios_ult
    valor_CASH = cash_bal
    valor_final_total = np.sum(valores) + valor_CASH

    dias_nat = mes_idx * 365 / 252
    tiempos = T_yrs - dias_nat / 365
    aportes = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion_mensual)))
    t_full = np.concatenate(([T_yrs], tiempos))
    with np.errstate(invalid='ignore'):
        r = irrsolve(lambda rr: np.sum(aportes * (1 + rr) ** t_full) - valor_final_total)

    # ---------- MDD (equity) y VOL (TWR) ----------
    mdd_val = _calc_MDD_only(equity_series)
    valid_r = r_port[~np.isnan(r_port)]
    daily_std = np.nanstd(valid_r, ddof=1)
    annual_vol = daily_std * np.sqrt(252)

    # ---------- Detalle estructurado ----------
    detalle = {}
    if len(compras_idx) > 0:
        detalle['compras'] = pd.DataFrame({
            'Fecha': dates[np.asarray(compras_idx) - 1],
            'Activo': compras_dst,
            'Precio': compras_px,
            'Importe': compras_amt,
            'Z': compras_z,
        }, columns=['Fecha', 'Activo', 'Precio', 'Importe', 'Z'])
    else:
        detalle['compras'] = pd.DataFrame(columns=['Fecha', 'Activo', 'Precio', 'Importe', 'Z'])

    buy_counts_struct = {}
    signal_counts_struct = {}
    acciones_struct = {}
    valores_struct = {}
    for i in range(1, num_activos + 1):
        ticker_clean = _make_valid_name(tickers_config[i - 1])
        buy_counts_struct[ticker_clean] = buy_counts[i - 1]
        signal_counts_struct[ticker_clean] = sig_counts[i - 1]
        acciones_struct[ticker_clean] = acc[i - 1]
        valores_struct[ticker_clean] = valores[i - 1]

    detalle['buy_counts'] = buy_counts_struct
    detalle['signal_counts'] = signal_counts_struct
    detalle['cash_series'] = cash_hist
    detalle['rebalanceos'] = rebalanceos_count
    detalle['min_cash'] = min_cash_alcanzado
    detalle['max_deuda'] = abs(min_cash_alcanzado)
    detalle['inversiones_grandes'] = inversiones_por_senal
    detalle['MA_sig'] = MA_sig
    detalle['MA_reb'] = MA_reb
    detalle['acciones'] = acciones_struct
    detalle['valor_por_activo'] = valores_struct

    # Series y métricas clave
    detalle['equity_series'] = equity_series
    detalle['dates_series'] = dates
    detalle['ret_series'] = r_port             # ← NUEVO
    detalle['mdd'] = mdd_val
    detalle['annual_volatility'] = annual_vol

    detalle['params'] = {'periodos': periodos, 'aportacion_mensual': aportacion_mensual,
                         'dinero_inicial': dinero_inicial, 'tickers': tickers_config,
                         'weights': weights_config, 'upper_abs': upper_abs, 'z_engine': z_engine,
                         'z_threshold': z_threshold, 'MA_sig': MA_sig, 'MA_reb': MA_reb,
                         'amount_per_signal': 1500}

    # ---------- Print ----------
    if not debug:
        print('=' * 117)
        print('Portfolio Event-Driven + Reb. SUAVE v2 (NO MA filter) (%s) | %d anos | CAGR: %s%% | Aportes: %d | Valor final: %s'
              % ('/'.join(tickers_config), int(periodos), _fmt(r * 100, '.2f'),
                 num_aportaciones, _fmt(valor_final_total, '.2f')))
        print('Rebalanceos ejecutados: %d' % rebalanceos_count)
        if min_cash_alcanzado < 0:
            print('Deuda maxima alcanzada: %s EUR' % _fmt(abs(min_cash_alcanzado), '.2f'))
        print('Desglose por activo a %s:' % pd.Timestamp(dates[-1]).strftime('%Y-%m-%d'))
        for j in range(1, num_activos + 1):
            print('  %s: %s EUR (%s%%)'
                  % (tickers_config[j - 1], _fmt(valores[j - 1], '.2f'),
                     _fmt(100 * valores[j - 1] / valor_final_total, '.2f')))
        print('  CASH: %s EUR (%s%%)'
              % (_fmt(valor_CASH, '.2f'), _fmt(100 * valor_CASH / valor_final_total, '.2f')))
        print('  TOTAL: %s EUR (100%%)' % _fmt(valor_final_total, '.2f'))
        print('=' * 117)
    else:
        print('=' * 117)
        print('Portfolio Event-Driven + Rebalanceo SUAVE v2 - SIN FILTRO MA_reb')
        print('Tickers: %s' % ', '.join(tickers_config))
        print('Pesos objetivo: %s' % ''.join('%.1f%% ' % (x * 100) for x in np.asarray(weights_config).ravel()))
        print('Motor: %s%s | Inversion por senal: %s EUR'
              % (z_engine,
                 _iff(z_engine.lower() == 'bollinger', '(n=%d)' % int(n_boll), ''),
                 _fmt(1500, '.0f')))
        print('Senal: z<=%s & Px<MMsig(%d) | Receptores: TODOS (sin filtro MA_reb)'
              % (_fmt(z_threshold, '.2f'), int(MA_sig)))
        print('MDD calculado: %s%% | Volatilidad anual (TWR): %s%%'
              % (_fmt(mdd_val * 100, '.2f'), _fmt(annual_vol * 100, '.2f')))
        print('-' * 117)
        print('RESULTADOS:')
        print('  CAGR (IRR): %s%%' % _fmt(r * 100, '.2f'))
        print('  Numero de aportaciones: %d' % num_aportaciones)
        print('  Numero de ordenes de compra (senal): %d' % len(compras_idx))
        print('  Numero de rebalanceos (ventas por techo): %d' % rebalanceos_count)
        print('  Deuda maxima alcanzada: %s EUR' % _fmt(abs(min_cash_alcanzado), '.2f'))
        print('  Maximum Drawdown: %s%%' % _fmt(mdd_val * 100, '.2f'))
        print('  Volatilidad anualizada (TWR): %s%%' % _fmt(annual_vol * 100, '.2f'))
        print('  Valor final total: %s EUR' % _fmt(valor_final_total, '.2f'))
        print('=' * 117)

    return r, num_aportaciones, valor_final_total, detalle


# ---------- Helper resolver ----------
def _get_helpers():
    return (GBEventHelpers.read_yahoo_csv, GBEventHelpers.solve_irr,
            GBEventHelpers.shewhart_tasa_const)


def _isempty(x):
    if x is None:
        return True
    if isinstance(x, (str, bytes, list, tuple, dict)):
        return len(x) == 0
    if isinstance(x, np.ndarray):
        return x.size == 0
    return False


def _round(x):
    return int(np.sign(x) * np.floor(np.abs(x) + 0.5))


def _make_valid_name(s):
    s = re.sub(r'\W', '_', s)
    if s and s[0].isdigit():
        s = 'x' + s
    return s


def _fmt(x, code):
    if isinstance(x, (float, np.floating)):
        if np.isnan(x):
            return 'NaN'
        if np.isinf(x):
            return 'Inf' if x > 0 else '-Inf'
    return format(x, code)


def _iff(c, a, b):
    if c:
        s = a
    else:
        s = b
    return s


# --- Helper MDD solo (VOL se calcula desde r_port) ---
def _calc_MDD_only(equity_series):
    equity_series = np.asarray(equity_series, dtype=np.float64).ravel()
    if equity_series.size < 2:
        mdd = np.nan
        return mdd
    max_run = np.maximum.accumulate(equity_series)
    dd = (equity_series - max_run) / max_run
    mdd = abs(np.min(dd))
    return mdd
