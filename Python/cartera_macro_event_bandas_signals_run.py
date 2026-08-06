"""MACRO Event-Driven (CASH mensual + TOPE DIARIO) con REBALANCEO por BANDAS ABSOLUTAS

Activos: SPY, IWM, GLD, TLT, BTC
Logica:
  - Aporte mensual (1.500 EUR) -> CASH.
  - Reb. por bandas (a diario): si peso > techo absoluto, vender EXCESO hasta objetivo (w) -> CASH.
  - Compras (a diario) SOLO si hay senal: (z <= umbral) & (Precio < MA(MA)).
      · z_engine: 'shewhart_tippett' o 'bollinger' (usa n_boll y z_threshold).
      · Presupuesto del dia = min(CASH, max_cash_por_dia), repartido a PARTES IGUALES entre senalizados.
  - Sin compras si no hay senal. El CASH no usado se acumula.

Uso ejemplo:
  r, n, vf, det = cartera_macro_event_bandas_signals_run(12)
  r, n, vf, det = cartera_macro_event_bandas_signals_run(12, 'C:\\Path\\', 3000, 'shewhart_tippett', 22, -2, 200, False, 252, False, 19)

Migracion 1:1 desde cartera_macro_event_bandas_signals_run.m
"""

import os
import warnings

import numpy as np
import pandas as pd
from scipy.optimize import brentq, newton, minimize_scalar


def cartera_macro_event_bandas_signals_run(periodos=None, basePath=None, max_cash_por_dia=None,
                                           z_engine=None, n_boll=None, z_threshold=None, MA=None,
                                           enableMomentum=None, mom_look=None,
                                           enableFiltroVIX=None, vix_umbral=None):
    # === Parametros por defecto ===
    if periodos is None:
        periodos = 10
    if basePath is None or basePath == '':
        basePath = 'C:\\Users\\israe\\OneDrive\\Matlab_scripts\\'
    if max_cash_por_dia is None:
        max_cash_por_dia = 3000
    if z_engine is None or z_engine == '':
        z_engine = 'shewhart_tippett'   # 'shewhart_tippett' | 'bollinger'
    if n_boll is None:
        n_boll = 22
    if z_threshold is None:
        z_threshold = -2.0
    if MA is None:
        MA = 200
    if enableMomentum is None:
        enableMomentum = False
    if mom_look is None:
        mom_look = 252
    if enableFiltroVIX is None:
        enableFiltroVIX = False
    if vix_umbral is None:
        vix_umbral = 19

    aportacion_mensual = 1500
    dinero_inicial = 10000

    # Pesos MACRO (objetivos para ventas por banda y compra inicial)
    w = np.array([0.50, 0.25, 0.10, 0.10, 0.05])              # SPY IWM GLD TLT BTC
    tickers = ['SPY', 'IWM', 'GLD', 'TLT', 'BTC']             # orden estable para logs

    # Bandas absolutas tipicas (techo de peso)
    # SPY>60%, IWM>32%, GLD>13%, TLT>13%, BTC>10%
    upper_abs = np.array([0.60, 0.32, 0.13, 0.13, 0.10])

    # === Ficheros locales (YA descargados) ===
    fp_spy = os.path.join(basePath, 'SPY_yahoo.csv')
    fp_iwm = os.path.join(basePath, 'IWM_yahoo.csv')
    fp_gld = os.path.join(basePath, 'GLD_yahoo.csv')
    fp_tlt = os.path.join(basePath, 'TLT_yahoo.csv')
    fp_btc = os.path.join(basePath, 'BTC-USD_yahoo.csv')
    need = [fp_spy, fp_iwm, fp_gld, fp_tlt, fp_btc]
    for k in range(len(need)):
        assert os.path.isfile(need[k]), 'Falta %s. Ejecuta antes main_vYahoo.' % need[k]
    if enableFiltroVIX:
        fp_vix = os.path.join(basePath, 'VIX_yahoo.csv')
        assert os.path.isfile(fp_vix), 'Falta %s y tienes VIX activo. Ejecuta antes main_vYahoo.' % fp_vix

    # === Lectura y alineacion ===
    spy, d_spy = read_yahoo_csv(fp_spy)
    iwm, d_iwm = read_yahoo_csv(fp_iwm)
    gld, d_gld = read_yahoo_csv(fp_gld)
    tlt, d_tlt = read_yahoo_csv(fp_tlt)
    btc, d_btc = read_yahoo_csv(fp_btc)

    TT = pd.concat([
        pd.Series(spy, index=d_spy, name='SPY'),
        pd.Series(iwm, index=d_iwm, name='IWM'),
        pd.Series(gld, index=d_gld, name='GLD'),
        pd.Series(tlt, index=d_tlt, name='TLT'),
        pd.Series(btc, index=d_btc, name='BTC'),
    ], axis=1, join='inner')
    TT = TT.dropna()
    assert TT.shape[0] > 0, 'No quedan fechas comunes tras la intersección.'

    if enableFiltroVIX:
        vix_raw, d_vix = read_yahoo_csv(fp_vix)
        TT_vix = pd.Series(vix_raw, index=d_vix, name='VIX')
        TT_all = pd.concat([TT, TT_vix], axis=1, join='outer')
        mask = TT_all.index.isin(TT.index)
        TT = TT_all[mask]
    else:
        TT['VIX'] = np.nan

    # Ventana temporal
    N_total = TT.shape[0]
    N_dias = min(N_total, int(np.sign(252 * periodos) * np.floor(abs(252 * periodos) + 0.5)))
    TT = TT.iloc[N_total - N_dias:]

    dates = pd.DatetimeIndex(TT.index)
    P = TT[['SPY', 'IWM', 'GLD', 'TLT', 'BTC']].to_numpy(dtype=np.float64)   # Nx5 (orden de 'tickers')
    vix = TT['VIX'].to_numpy(dtype=np.float64)
    N = P.shape[0]
    T_yrs = N / 252

    # === Aportaciones mensuales (entran a CASH) ===
    fechas_mens = pd.date_range(start=pd.Timestamp(dates[0]).replace(day=1), periods=int(periodos * 12), freq='MS')
    fechas_mens = fechas_mens[fechas_mens <= dates[N - 1]]
    dates_ns = dates.to_numpy().astype('datetime64[ns]').astype(np.int64)
    mes_idx = np.zeros(len(fechas_mens), dtype=np.int64)
    for k in range(len(fechas_mens)):
        ii = int(np.argmin(np.abs(dates_ns - pd.Timestamp(fechas_mens[k]).value))) + 1  # dia habil mas cercano (1-based)
        mes_idx[k] = ii
    mes_idx = pd.unique(mes_idx)

    # === MA causal y z-scores ===
    def mm_fun(x):
        return pd.Series(x).rolling(MA, min_periods=1).mean().to_numpy()
    mm = np.column_stack([mm_fun(P[:, 0]), mm_fun(P[:, 1]), mm_fun(P[:, 2]), mm_fun(P[:, 3]), mm_fun(P[:, 4])])

    if z_engine.lower() == 'bollinger':
        mu = pd.DataFrame(P).rolling(n_boll, min_periods=1).mean().to_numpy()
        sd = pd.DataFrame(P).rolling(n_boll, min_periods=1).std(ddof=1).to_numpy()
        with np.errstate(divide='ignore', invalid='ignore'):
            Z = (P - mu) / sd
        sig_z = (Z <= z_threshold) & (sd > 0)
    elif z_engine.lower() == 'shewhart_tippett':
        Z = np.full((N, 5), np.nan)
        Z[:, 0] = shewhart_tasa_const(P[:, 0])[5]
        Z[:, 1] = shewhart_tasa_const(P[:, 1])[5]
        Z[:, 2] = shewhart_tasa_const(P[:, 2])[5]
        Z[:, 3] = shewhart_tasa_const(P[:, 3])[5]
        Z[:, 4] = shewhart_tasa_const(P[:, 4])[5]
        sig_z = (Z <= z_threshold)
    else:
        raise ValueError("z_engine no reconocido. Usa 'bollinger' o 'shewhart_tippett'.")

    # Senal BRUTA = (z<=umbral) & (Precio < MA)
    sig_raw = sig_z & (P < mm)

    # Momentum opcional
    if enableMomentum:
        def momfun(x, w_):
            x = np.asarray(x, dtype=float)
            with np.errstate(divide='ignore', invalid='ignore'):
                return np.concatenate([np.full(w_, np.nan), (x[w_:] / x[:x.size - w_] - 1)])
        M = np.column_stack([momfun(P[:, 0], mom_look), momfun(P[:, 1], mom_look), momfun(P[:, 2], mom_look),
                             momfun(P[:, 3], mom_look), momfun(P[:, 4], mom_look)])
        sig_raw = sig_raw & (M >= 0)

    # VIX opcional (filtro global del dia)
    if enableFiltroVIX:
        vix_ok = np.isfinite(vix) & (vix > vix_umbral)
    else:
        vix_ok = np.ones(N, dtype=bool)

    sig_counts_raw = np.sum(sig_raw, axis=0)
    sig_counts_filtered = np.sum(sig_raw & vix_ok[:, None], axis=0)

    # === Estados ===
    acc = np.zeros(5)   # unidades
    cash_bal = 0.0
    dias_tope = 0

    # Compra inicial por pesos MACRO
    if dinero_inicial > 0:
        p1 = P[0, :]
        acc = acc + (dinero_inicial * w) / p1

    # Trazas
    compras_idx = []
    compras_dst = []
    compras_z = []
    compras_px = []
    compras_amt = []
    buy_counts = np.zeros(5)

    ventas_idx = []
    ventas_dst = []
    ventas_eur = []
    activaciones_count = np.zeros(5)

    cash_hist = np.zeros(N)

    # Para "% meses > techo" (hubo al menos un dia >techo en el mes, pre-venta)
    ym = dates.year * 100 + dates.month
    _, grp_mes = np.unique(ym.to_numpy(), return_inverse=True)
    grp_mes = grp_mes + 1   # 1-based
    meses_total = int(np.max(grp_mes))
    sobre_techo_mes = np.zeros((meses_total, 5), dtype=bool)

    # === Bucle DIARIO ===
    for i in range(1, N + 1):
        precios_i = P[i - 1, :]

        # Aporte mensual -> CASH
        if np.any(i == mes_idx):
            cash_bal = cash_bal + aportacion_mensual

        # --- Estado antes de ventas ---
        valores = acc * precios_i
        invertido = np.sum(valores)
        if invertido <= 0:
            pesos_assets = np.zeros(5)
            target_assets = np.zeros(5)
        else:
            pesos_assets = valores / invertido
            target_assets = invertido * w

        # --- Reb. por bandas: vender EXCESO hasta objetivo (fluye a CASH) ---
        over_pre = pesos_assets > upper_abs
        if np.any(over_pre):
            sobre_techo_mes[grp_mes[i - 1] - 1, :] = sobre_techo_mes[grp_mes[i - 1] - 1, :] | over_pre
            exceso = valores[over_pre] - target_assets[over_pre]
            cash_new = np.sum(exceso)
            if cash_new > 0:
                idx_over = np.flatnonzero(over_pre) + 1
                for c in idx_over:
                    x = valores[c - 1] - target_assets[c - 1]
                    if x > 0:
                        activaciones_count[c - 1] = activaciones_count[c - 1] + 1
                        ventas_idx.append(i)
                        ventas_dst.append(tickers[c - 1])
                        ventas_eur.append(x)
                valores[over_pre] = target_assets[over_pre]
                cash_bal = cash_bal + cash_new

        # Actualiza acc (por si hubo ventas sin compras)
        acc = valores / precios_i

        # --- Compras SOLO si hay senal hoy (y pasa VIX global) ---
        if cash_bal > 1e-12 and vix_ok[i - 1]:
            base = sig_raw[i - 1, :]
            if np.any(base):
                presupuesto = min(cash_bal, max_cash_por_dia)
                if presupuesto > 0:
                    if abs(presupuesto - max_cash_por_dia) < 1e-9:
                        dias_tope = dias_tope + 1

                    idx_cand = np.flatnonzero(base) + 1
                    amount_per = presupuesto / idx_cand.size

                    for c in idx_cand:
                        acc[c - 1] = acc[c - 1] + amount_per / precios_i[c - 1]

                        compras_idx.append(i)
                        compras_dst.append(tickers[c - 1])
                        compras_z.append(Z[i - 1, c - 1])
                        compras_px.append(precios_i[c - 1])
                        compras_amt.append(amount_per)
                        buy_counts[c - 1] = buy_counts[c - 1] + 1

                    cash_bal = cash_bal - presupuesto  # resta solo lo gastado hoy

        # Caja del dia
        cash_hist[i - 1] = cash_bal

    num_aportaciones = len(compras_idx)   # nº de ordenes de compra

    # === Valor final y CAGR (IRR) ===
    precios_ult = P[N - 1, :]
    valores = acc * precios_ult
    valor_CASH = cash_bal
    valor_final_total = np.sum(valores) + valor_CASH

    # IRR con aportes mensuales
    dias_nat = mes_idx * 365 / 252
    tiempos = T_yrs - dias_nat / 365
    aportes = np.concatenate([[dinero_inicial], np.full(mes_idx.size, aportacion_mensual, dtype=float)])
    t_full = np.concatenate([[T_yrs], tiempos])

    def fCAGR(rr):
        with np.errstate(all='ignore'):
            return np.sum(aportes * np.power(1 + rr, t_full)) - valor_final_total

    r = solve_irr(fCAGR)

    # === Metricas de caja y bandas ===
    idx_max_cash = int(np.argmax(cash_hist)) + 1
    max_cash = cash_hist[idx_max_cash - 1]
    fecha_max_cash = dates[idx_max_cash - 1]
    dias_cash_positivo = int(np.sum(cash_hist > 0))
    total_aportado = dinero_inicial + aportacion_mensual * mes_idx.size
    solo_aportes_mensuales = aportacion_mensual * mes_idx.size
    pct_meses_sobre_techo = np.mean(sobre_techo_mes, axis=0) * 100

    # === Salida y logs (formato como tus ejemplos) ===
    def as_struct(vec):
        v = np.asarray(vec, dtype=float).ravel()
        return {tickers[j]: v[j] for j in range(5)}

    detalle = {}
    compras_idx_arr = np.asarray(compras_idx, dtype=np.int64)
    ventas_idx_arr = np.asarray(ventas_idx, dtype=np.int64)
    detalle['compras'] = pd.DataFrame({
        'Fecha': dates[compras_idx_arr - 1],
        'Activo': compras_dst,
        'Precio': np.asarray(compras_px, dtype=float),
        'Importe': np.asarray(compras_amt, dtype=float),
        'Z': np.asarray(compras_z, dtype=float),
    })
    detalle['ventas'] = pd.DataFrame({
        'Fecha': dates[ventas_idx_arr - 1],
        'Activo': ventas_dst,
        'ImporteVendido': np.asarray(ventas_eur, dtype=float),
    })

    detalle['acciones'] = as_struct(acc)
    detalle['valor_por_activo'] = as_struct(valores)
    detalle['valor_por_activo']['CASH'] = valor_CASH
    with np.errstate(divide='ignore', invalid='ignore'):
        detalle['peso_por_activo'] = {'SPY': valores[0] / valor_final_total, 'IWM': valores[1] / valor_final_total,
                                      'GLD': valores[2] / valor_final_total, 'TLT': valores[3] / valor_final_total,
                                      'BTC': valores[4] / valor_final_total, 'CASH': valor_CASH / valor_final_total}
    detalle['signal_counts_raw'] = as_struct(sig_counts_raw)
    detalle['signal_counts'] = as_struct(sig_counts_filtered)
    detalle['buy_counts'] = as_struct(buy_counts)
    detalle['activaciones_ventas'] = as_struct(activaciones_count)
    detalle['cash_series'] = cash_hist
    detalle['params'] = {'periodos': periodos, 'aportacion_mensual': aportacion_mensual, 'dinero_inicial': dinero_inicial,
                         'pesos': w, 'upper_abs': upper_abs, 'MA': MA, 'z_engine': z_engine, 'n_boll': n_boll,
                         'z_threshold': z_threshold, 'enableMomentum': enableMomentum, 'mom_look': mom_look,
                         'enableFiltroVIX': enableFiltroVIX, 'vix_umbral': vix_umbral,
                         'max_cash_por_dia': max_cash_por_dia, 'dias_con_tope': dias_tope}

    detalle['metricas_cash'] = {
        'max_cash': max_cash,
        'fecha_max_cash': fecha_max_cash,
        'dias_con_cash_positivo': dias_cash_positivo,
        'total_aportado_incl_inicial': total_aportado,
        'solo_aportaciones_mensuales': solo_aportes_mensuales,
    }

    # ===== Logs =====
    print('MACRO Event-Driven (CASH mensual, tope diario=%.2f) | z-engine=%s%s | Señal: z<=%.2f & Px<MM(%d) | CAGR: %.2f%% | Órdenes: %d' %
          (max_cash_por_dia, z_engine, iff(z_engine.lower() == 'bollinger', '(n=%d)' % n_boll, ''),
           z_threshold, MA, r * 100, num_aportaciones))

    print('Desglose VALOR actual (%s): SPY=%.2f  IWM=%.2f  GLD=%.2f  TLT=%.2f  BTC=%.2f  CASH=%.2f  |  TOTAL=%.2f' %
          (pd.Timestamp(dates[N - 1]).strftime('%Y-%m-%d'), valores[0], valores[1], valores[2], valores[3], valores[4], valor_CASH, valor_final_total))

    print('Señales BRUTAS (z+MM):          SPY=%d  IWM=%d  GLD=%d  TLT=%d  BTC=%d' %
          (detalle['signal_counts_raw']['SPY'], detalle['signal_counts_raw']['IWM'], detalle['signal_counts_raw']['GLD'],
           detalle['signal_counts_raw']['TLT'], detalle['signal_counts_raw']['BTC']))
    print('Señales FILTRADAS (VIX):        SPY=%d  IWM=%d  GLD=%d  TLT=%d  BTC=%d' %
          (detalle['signal_counts']['SPY'], detalle['signal_counts']['IWM'], detalle['signal_counts']['GLD'],
           detalle['signal_counts']['TLT'], detalle['signal_counts']['BTC']))

    print('Compras ejecutadas (cap %.0f€/día):  SPY=%d  IWM=%d  GLD=%d  TLT=%d  BTC=%d' %
          (max_cash_por_dia, detalle['buy_counts']['SPY'], detalle['buy_counts']['IWM'], detalle['buy_counts']['GLD'],
           detalle['buy_counts']['TLT'], detalle['buy_counts']['BTC']))

    print('Total aportado (incl. inicial): %.2f € | Solo aportaciones mensuales: %.2f €' %
          (total_aportado, solo_aportes_mensuales))
    print('Máxima aportación acumulada (CASH máx): %.2f € en %s' %
          (max_cash, pd.Timestamp(fecha_max_cash).strftime('%Y-%m-%d')))
    print('Días con CASH > 0: %d | Días con tope alcanzado: %d' %
          (dias_cash_positivo, dias_tope))

    print('--- Métricas de bandas ---')
    for j in range(1, len(tickers) + 1):
        print('  %s: activaciones=%d | %% meses > techo=%.2f%%' %
              (tickers[j - 1], detalle['activaciones_ventas'][tickers[j - 1]], pct_meses_sobre_techo[j - 1]))

    print('Desglose por activo a %s:' % pd.Timestamp(dates[N - 1]).strftime('%Y-%m-%d'))
    with np.errstate(divide='ignore', invalid='ignore'):
        for j in range(1, len(tickers) + 1):
            print('  %s : %.2f € (%.2f%%)' % (tickers[j - 1], valores[j - 1], 100 * valores[j - 1] / valor_final_total))
        print('  CASH: %.2f € (%.2f%%)\n  TOTAL: %.2f € (100%%)' %
              (valor_CASH, 100 * valor_CASH / valor_final_total, valor_final_total))

    return r, num_aportaciones, valor_final_total, detalle


# ----------------- HELPERS -----------------
def shewhart_tasa_const(precios):
    precios = np.asarray(precios, dtype=float).ravel()
    N = precios.size
    if N < 3:
        return np.array([]), np.array([]), np.nan, np.nan, np.array([]), np.full(N, np.nan)
    with np.errstate(divide='ignore', invalid='ignore'):
        tasa_pct = np.diff(precios) / precios[:N - 1] * 100
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', RuntimeWarning)
        media = np.nanmean(tasa_pct)
        RM = np.abs(np.diff(tasa_pct))
        sigma_t = np.nanmean(RM) / 1.128
    if not np.isfinite(sigma_t) or sigma_t <= 0:
        sigma_t = np.nan
    z = np.full(N, np.nan)
    if np.isfinite(sigma_t):
        z[1:] = (tasa_pct - media) / sigma_t
    if np.isfinite(sigma_t):
        idx3s = (np.flatnonzero(tasa_pct <= (media - 3 * sigma_t)) + 1) + 1
        idx2s = (np.flatnonzero(tasa_pct <= (media - 2 * sigma_t)) + 1) + 1
    else:
        idx3s = np.array([])
        idx2s = np.array([])
    return idx3s, idx2s, media, sigma_t, tasa_pct, z


def solve_irr(fun):
    a = -0.999
    b = 10
    Fa = fun(a)
    Fb = fun(b)
    if np.isfinite(Fa) and np.isfinite(Fb) and np.sign(Fa) != np.sign(Fb):
        return brentq(fun, a, b)
    guesses = [-0.9, -0.5, -0.2, 0, 0.05, 0.1, 0.2, 0.4, 0.8, 1, 2, 5]
    for g in guesses:
        try:
            rr = newton(fun, g)
            if np.isfinite(rr):
                return rr
        except Exception:
            pass
    def obj(x):
        return abs(fun(x))
    return minimize_scalar(obj, bounds=(-0.99, 10), method='bounded').x


def iff(cond, a, b):
    return a if cond else b


def read_yahoo_csv(csvPath):
    if not os.path.isfile(csvPath):
        raise FileNotFoundError('Archivo no encontrado: %s' % csvPath)
    T = pd.read_csv(csvPath)
    if T is None or T.shape[1] == 0 or T.shape[0] == 0:
        raise ValueError('CSV vacío o sin filas: %s' % csvPath)
    names = [str(nm).replace('_', '').replace(' ', '').lower() for nm in T.columns]  # normaliza
    iDate = next((i for i, nm in enumerate(names) if nm == 'date'), None)
    if iDate is None:
        iDate = 0
    dates_col = T.iloc[:, iDate]
    if pd.api.types.is_numeric_dtype(dates_col):
        dates = pd.DatetimeIndex(pd.to_datetime(dates_col.to_numpy(dtype=np.float64), unit='D', origin='1899-12-30'))
    else:
        try:
            dates = pd.DatetimeIndex(pd.to_datetime(dates_col, format='%Y-%m-%d'))
        except Exception:
            dates = pd.DatetimeIndex(pd.to_datetime(dates_col))
    iAdj = next((i for i, nm in enumerate(names) if nm == 'adjclose'), None)
    iClose = next((i for i, nm in enumerate(names) if nm == 'close'), None)
    if iAdj is not None:
        y = T.iloc[:, iAdj]
    elif iClose is not None:
        y = T.iloc[:, iClose]
    else:
        y = T.iloc[:, T.shape[1] - 1]
        warnings.warn('No AdjClose/Close en %s' % csvPath)
    if y.dtype == object or pd.api.types.is_string_dtype(y):
        y = pd.to_numeric(pd.Series(y).astype(str).str.replace(',', '.', regex=False), errors='coerce')
    y = np.asarray(y, dtype=np.float64)
    d_arr = dates.to_numpy()
    good = ~np.isnat(d_arr) & ~np.isnan(y)
    d_g = d_arr[good]
    y_g = y[good]
    idx = np.argsort(d_g, kind='stable')
    dates = pd.DatetimeIndex(d_g[idx])
    close_prices = np.asarray(y_g[idx], dtype=np.float64).ravel()
    return close_prices, dates
