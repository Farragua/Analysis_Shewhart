"""Portfolio Event-Driven + Reb. por bandas a CASH flexible (solo venta) + tope diario
CAMBIOS MINIMOS:
- r_port (retorno diario TWR) calculado ANTES de aportar/vender por rebalanceo/comprar
- Vol anualizada desde r_port (std * sqrt(252))
- MDD desde equity_series (activos + cash)
- Se añade detalle.ret_series
"""

import os
import re

import numpy as np
import pandas as pd

from GBEventHelpers import GBEventHelpers


def Strategy_event_driven_rebal_cashpool_flexible_v1_sigma(
        periodos=None, basePath=None, tickers_config=None, weights_config=None,
        z_engine=None, n_boll=None, z_threshold=None, MA=None, max_cash_por_dia=None,
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
    if _isempty(MA):
        MA = 200
    if _isempty(max_cash_por_dia):
        max_cash_por_dia = 3000
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
    warmup = max(MA, n_boll, 3)
    i0 = max(1, N_total - (N_dias + warmup) + 1)
    TTw = TT.iloc[i0 - 1:, :]
    dates_w = TTw.index
    P_w = TTw.to_numpy(dtype=np.float64)
    N_w = P_w.shape[0]

    MM_w = np.zeros((N_w, num_activos))
    for j in range(1, num_activos + 1):
        MM_w[:, j - 1] = pd.Series(P_w[:, j - 1]).rolling(MA, min_periods=1).mean().to_numpy()

    ze = z_engine.lower()
    if ze == 'bollinger':
        mu = pd.DataFrame(P_w).rolling(n_boll, min_periods=1).mean().to_numpy()
        sd = pd.DataFrame(P_w).rolling(n_boll, min_periods=1).std(ddof=1).to_numpy()
        Z_w = (P_w - mu) / sd
        sig_w = (Z_w <= z_threshold) & (sd > 0) & (P_w < MM_w)
    elif ze == 'shewhart_tippett':
        Z_w = np.full((N_w, num_activos), np.nan)
        for c in range(1, num_activos + 1):
            _, _, _, _, _, Z_w[:, c - 1] = shew(P_w[:, c - 1])
        sig_w = (Z_w <= z_threshold) & (P_w < MM_w)
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
    dias_tope = 0

    # Arrays para MDD y VOL (TWR)
    equity_series = np.zeros(N)     # equity día a día (activos + cash)
    r_port = np.full(N, np.nan)     # retorno TWR (sin flujos del propio día)
    precios_prev = P[0, :]          # precios "día anterior" para TWR

    # Tracking
    compras_idx = []
    compras_dst = []
    compras_amt = []
    compras_px = []
    compras_z = []
    buy_counts = np.zeros(num_activos)
    ventas_idx = []
    ventas_dst = []
    ventas_eur = []
    activaciones_count = np.zeros(num_activos)
    cash_hist = np.zeros(N)

    # Inversion inicial por pesos
    if dinero_inicial > 0:
        p1 = P[0, :]
        init_weights = w * dinero_inicial
        acc = acc + (init_weights / p1)

    # ---------- Bucle ----------
    for i in range(1, N + 1):
        precios = P[i - 1, :]

        # (1) Retorno TWR ANTES de cualquier flujo del día (aportación / rebalanceo a cash / compras)
        if i == 1:
            r_port[i - 1] = np.nan  # sin retorno el primer día
        else:
            valor_inicio = np.sum(acc * precios_prev) + cash_bal  # cash rinde 0
            if valor_inicio > 0:
                delta_activos = np.sum(acc * (precios - precios_prev))
                r_port[i - 1] = delta_activos / valor_inicio
            else:
                r_port[i - 1] = 0  # o NaN si prefieres

        # (2) Aportación mensual (después de medir r_port)
        if np.any(i == mes_idx):
            cash_bal = cash_bal + aportacion_mensual

        # (3) Reb a CASH (venta del exceso)
        valores = acc * precios
        invertido = np.sum(valores)
        if invertido > 0:
            pesos = valores / invertido
            target = invertido * w
            over = pesos > upper_abs
            if np.any(over):
                exceso = valores[over] - target[over]
                cash_new = np.sum(exceso)
                if cash_new > 0:
                    idx_over = np.flatnonzero(over) + 1
                    for c in idx_over:
                        x = valores[c - 1] - target[c - 1]
                        if x > 0:
                            activaciones_count[c - 1] = activaciones_count[c - 1] + 1
                            ventas_idx.append(i)
                            ventas_dst.append(tickers_config[c - 1])
                            ventas_eur.append(x)
                    valores[over] = target[over]
                    cash_bal = cash_bal + cash_new
                    acc = valores / precios

        # (4) Compras con cap por activo + tope diario (FIX: N==1 o u≈1 => sin límite, sólo presupuesto)
        if cash_bal > 1e-12 and np.any(sig[i - 1, :]):
            presupuesto = min(cash_bal, max_cash_por_dia)
            if presupuesto > 0:
                if abs(presupuesto - max_cash_por_dia) < 1e-9:
                    dias_tope = dias_tope + 1
                valores_now = acc * precios
                invertido_now = np.sum(valores_now)

                idx = np.flatnonzero(sig[i - 1, :]) + 1
                caps = np.zeros(len(idx))
                for jj in range(1, len(idx) + 1):
                    c = idx[jj - 1]
                    u = upper_abs[c - 1]
                    I = invertido_now
                    vc = valores_now[c - 1]
                    if num_activos == 1 or (1 - u) <= 1e-12:
                        caps[jj - 1] = np.inf  # sin límite por cap; limitar por presupuesto
                    else:
                        denom = max(1 - u, np.finfo(np.float64).eps)
                        caps[jj - 1] = max(0, (u * I - vc) / denom)

                elig = (caps > 1e-12) | np.isinf(caps)
                if np.any(elig):
                    amount_per = presupuesto / np.sum(elig)
                    gastado = 0
                    for jj in range(1, len(idx) + 1):
                        if not elig[jj - 1]:
                            continue
                        c = idx[jj - 1]
                        eur_c = amount_per
                        if not np.isinf(caps[jj - 1]):
                            eur_c = min(amount_per, caps[jj - 1])
                        if eur_c <= 0:
                            continue
                        acc[c - 1] = acc[c - 1] + eur_c / precios[c - 1]
                        gastado = gastado + eur_c
                        compras_idx.append(i)
                        compras_dst.append(tickers_config[c - 1])
                        compras_amt.append(eur_c)
                        compras_px.append(precios[c - 1])
                        compras_z.append(Z[i - 1, c - 1])
                        buy_counts[c - 1] = buy_counts[c - 1] + 1
                    cash_bal = cash_bal - gastado  # nunca < 0 en V1

        cash_hist[i - 1] = cash_bal

        # (5) Tracking equity (INCLUYE flujos del propio día)
        valores_dia = acc * precios
        equity_series[i - 1] = np.sum(valores_dia) + cash_bal

        # (6) Actualizar precios_prev
        precios_prev = precios

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

    # ---------- Detalle ----------
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
    if len(ventas_idx) > 0:
        detalle['ventas'] = pd.DataFrame({
            'Fecha': dates[np.asarray(ventas_idx) - 1],
            'Activo': ventas_dst,
            'ImporteVenta': ventas_eur,
        }, columns=['Fecha', 'Activo', 'ImporteVenta'])
    else:
        detalle['ventas'] = pd.DataFrame(columns=['Fecha', 'Activo', 'ImporteVenta'])

    buy_counts_struct = {}
    signal_counts_struct = {}
    activaciones_struct = {}
    acciones_struct = {}
    valores_struct = {}
    for i in range(1, num_activos + 1):
        ticker_clean = _make_valid_name(tickers_config[i - 1])
        buy_counts_struct[ticker_clean] = buy_counts[i - 1]
        signal_counts_struct[ticker_clean] = sig_counts[i - 1]
        activaciones_struct[ticker_clean] = activaciones_count[i - 1]
        acciones_struct[ticker_clean] = acc[i - 1]
        valores_struct[ticker_clean] = valores[i - 1]

    detalle['buy_counts'] = buy_counts_struct
    detalle['signal_counts'] = signal_counts_struct
    detalle['activaciones'] = activaciones_struct
    detalle['cash_series'] = cash_hist
    detalle['min_cash'] = np.min(cash_hist)          # siempre >= 0 en V1
    detalle['dias_tope'] = dias_tope
    detalle['num_ventas'] = len(ventas_idx)
    detalle['acciones'] = acciones_struct
    detalle['valor_por_activo'] = valores_struct

    # Series y métricas clave
    detalle['equity_series'] = equity_series
    detalle['dates_series'] = dates
    detalle['ret_series'] = r_port             # *** NUEVO: retornos diarios TWR
    detalle['mdd'] = mdd_val
    detalle['annual_volatility'] = annual_vol

    detalle['params'] = {'periodos': periodos, 'aportacion_mensual': aportacion_mensual,
                         'dinero_inicial': dinero_inicial, 'tickers': tickers_config,
                         'weights': weights_config, 'upper_abs': upper_abs, 'z_engine': z_engine,
                         'z_threshold': z_threshold, 'MA': MA, 'max_cash_por_dia': max_cash_por_dia}

    # ---------- Print ----------
    if not debug:
        print('=' * 117)
        print('Portfolio Event-Driven + Reb. a CASH (%s) | %d anos | CAGR: %s%% | Aportes: %d | Valor final: %s'
              % ('/'.join(tickers_config), int(periodos), _fmt(r * 100, '.2f'),
                 num_aportaciones, _fmt(valor_final_total, '.2f')))
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
        print('Portfolio Event-Driven + Rebalanceo por bandas a CASH Flexible (solo venta)')
        print('Tickers: %s' % ', '.join(tickers_config))
        print('Pesos objetivo: %s' % ''.join('%.1f%% ' % (x * 100) for x in np.asarray(weights_config).ravel()))
        print('Motor: %s%s | Senal: z<=%s & Px<MM(%d) | Tope diario: %s EUR'
              % (z_engine,
                 _iff(z_engine.lower() == 'bollinger', '(n=%d)' % int(n_boll), ''),
                 _fmt(z_threshold, '.2f'), int(MA), _fmt(max_cash_por_dia, '.0f')))
        print('Techos absolutos: %s' % ''.join('%.0f%% ' % (x * 100) for x in upper_abs))
        print('MDD calculado: %s%% | Volatilidad anual (TWR): %s%%'
              % (_fmt(mdd_val * 100, '.2f'), _fmt(annual_vol * 100, '.2f')))
        print('-' * 117)
        print('RESULTADOS:')
        print('  CAGR (IRR): %s%%' % _fmt(r * 100, '.2f'))
        print('  Numero de aportaciones: %d' % num_aportaciones)
        print('  Numero de ordenes de compra: %d' % len(compras_idx))
        print('  Numero de ventas por rebalanceo: %d' % len(ventas_idx))
        print('  Dias con tope alcanzado: %d' % dias_tope)
        print('  Maximum Drawdown: %s%%' % _fmt(mdd_val * 100, '.2f'))
        print('  Volatilidad anualizada (TWR): %s%%' % _fmt(annual_vol * 100, '.2f'))
        print('  Valor final total: %s EUR' % _fmt(valor_final_total, '.2f'))
        print('=' * 117)

    return r, num_aportaciones, valor_final_total, detalle


# ---------- Helpers ----------
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
