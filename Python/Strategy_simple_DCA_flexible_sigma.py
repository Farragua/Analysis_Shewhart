"""Portfolio DCA simple flexible - VOL por retornos TWR y MDD por equity
Cambios mínimos:
- r_port (time-weighted) calculado ANTES de aportar
- Vol anualizada desde r_port (std * sqrt(252))
- MDD sigue desde equity_series
- Se añade detalle.ret_series
"""

import os
import re
import sys

import numpy as np
import pandas as pd
from scipy.optimize import brentq, newton


def Strategy_simple_DCA_flexible_sigma(periodos=None, basePath=None, tickers_config=None,
                                       weights_config=None, debug=None):
    # ======== Validación de parámetros ========
    if _isempty(tickers_config):
        raise ValueError('Debes especificar los tickers del portfolio')

    if _isempty(weights_config):
        weights_config = np.ones(len(tickers_config)) / len(tickers_config)

    if periodos is None:
        periodos = 5
    if _isempty(basePath):
        basePath = 'C:\\Users\\israe\\OneDrive\\Matlab_scripts\\'
    if _isempty(debug):
        debug = False

    # Validaciones
    if len(tickers_config) != len(weights_config):
        raise ValueError('Numero de tickers (%d) debe coincidir con numero de pesos (%d)'
                         % (len(tickers_config), len(weights_config)))

    if abs(np.sum(weights_config) - 1.0) > 1e-6:
        raise ValueError('Los pesos deben sumar 1.0. Suma actual: %.6f' % np.sum(weights_config))

    # ======== Parámetros de estrategia ========
    dinero_inicial = 1000
    aportacion_total_mes = 1500
    dias_por_aporte = 21

    num_activos = len(tickers_config)
    w = np.asarray(weights_config, dtype=np.float64).ravel()

    # ======== Verificación de archivos ========
    file_paths = [None] * num_activos
    for i in range(1, num_activos + 1):
        ticker = tickers_config[i - 1]
        file_paths[i - 1] = os.path.join(basePath, ticker + '_yahoo.csv')
        if not os.path.isfile(file_paths[i - 1]):
            raise ValueError('Falta archivo: %s. Ejecuta main_vYahoo.m primero.' % file_paths[i - 1])

    # ======== Lectura de precios ========
    series_data = [None] * num_activos
    dates_data = [None] * num_activos

    for i in range(1, num_activos + 1):
        series_data[i - 1], dates_data[i - 1] = _read_yahoo_csv(file_paths[i - 1])

    # ======== Alinear por fechas comunes ========
    TT_list = [None] * num_activos
    for i in range(1, num_activos + 1):
        TT_list[i - 1] = pd.Series(series_data[i - 1], index=dates_data[i - 1],
                                   name=tickers_config[i - 1])

    if num_activos == 1:
        TT = TT_list[0].to_frame()
    else:
        TT = pd.concat(TT_list, axis=1, join='inner')
    TT = TT.dropna()

    if TT.shape[0] == 0:
        raise ValueError('No quedan fechas comunes entre las series tras la interseccion.')

    dates = TT.index
    series = TT.to_numpy(dtype=np.float64)

    # ======== Ventana temporal ========
    N_total = series.shape[0]
    N_dias = min(N_total, _round(252 * periodos))
    series = series[N_total - N_dias:, :]
    dates = dates[N_total - N_dias:]

    # ======== Setup para tracking completo ========
    fechas_aport = np.arange(1, N_dias + 1, dias_por_aporte)
    num_aportaciones = len(fechas_aport)
    aportacion_por_activo = aportacion_total_mes * w

    # Acumulación de acciones/unidades
    acc = np.zeros(num_activos)

    # Arrays de tracking
    equity_series = np.zeros(N_dias)                # equity día a día (con aportaciones)
    valor_activos_series = np.zeros((N_dias, num_activos))
    r_port = np.full(N_dias, np.nan)                # retorno diario TWR (sin aportaciones del día)
    precios_prev = series[0, :]                     # precios día anterior para r_port

    # Compra inicial (día 1) por pesos configurados
    if dinero_inicial > 0:
        init_por_activo = dinero_inicial * w
        precios_d1 = series[0, :]
        acc = acc + (init_por_activo / precios_d1)

    # Tracking de aportaciones
    detalle = {}
    detalle['fechas'] = dates[fechas_aport - 1]
    detalle['compras'] = np.zeros((num_aportaciones, num_activos))

    # ======== BUCLE PRINCIPAL CON TWR ========
    aporte_idx = 1

    for dia in range(1, N_dias + 1):
        precios_dia = series[dia - 1, :]

        # --- Retorno TWR ANTES de aportar ---
        if dia == 1:
            r_port[dia - 1] = np.nan  # sin retorno el primer día
        else:
            valor_inicio = np.sum(acc * precios_prev)  # sin flujos del día
            if valor_inicio > 0:
                r_port[dia - 1] = (np.sum(acc * precios_dia) - np.sum(acc * precios_prev)) / valor_inicio
            else:
                r_port[dia - 1] = 0  # o NaN si prefieres

        # --- Aportación DESPUÉS de medir el retorno del día ---
        if aporte_idx <= len(fechas_aport) and dia == fechas_aport[aporte_idx - 1]:
            compra_unidades = aportacion_por_activo / precios_dia
            acc = acc + compra_unidades

            # Guardar detalles de compra
            detalle['compras'][aporte_idx - 1, :] = compra_unidades
            aporte_idx = aporte_idx + 1

        # Tracking de valores y equity (incluye la aportación del propio día)
        valores_dia = acc * precios_dia
        valor_activos_series[dia - 1, :] = valores_dia
        equity_series[dia - 1] = np.sum(valores_dia)

        # Actualizar precios_prev
        precios_prev = precios_dia

    # ======== Valor final y métricas ========
    precios_ult = series[-1, :]
    valores = acc * precios_ult
    valor_final_total = np.sum(valores)
    pesos_finales = valores / valor_final_total

    # ======== CAGR por IRR ========
    aportes = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion_total_mes)))
    t_anios = np.concatenate(([0], (fechas_aport - 1) * 365 / 252))
    tiempos = periodos - t_anios / 365

    def funcion_CAGR(rr):
        return np.sum(aportes * (1 + rr) ** tiempos) - valor_final_total

    with np.errstate(invalid='ignore'):
        try:
            fL = funcion_CAGR(-0.99)
            fR = funcion_CAGR(10)
            if not np.isfinite(fL) or not np.isfinite(fR):
                r = newton(funcion_CAGR, 0.1)
            else:
                r = brentq(funcion_CAGR, -0.99, 10)
        except Exception:
            r = newton(funcion_CAGR, 0.1)

    # ======== MDD (equity) y VOL (TWR) ========
    mdd_val = _calc_MDD_only(equity_series)
    valid_r = r_port[~np.isnan(r_port)]
    daily_std = np.nanstd(valid_r, ddof=1)
    annual_vol = daily_std * np.sqrt(252)

    # ======== Detalle estructurado con series temporales ========
    acciones_struct = {}
    valores_struct = {}
    pesos_struct = {}

    for i in range(1, num_activos + 1):
        ticker_clean = _make_valid_name(tickers_config[i - 1])
        acciones_struct[ticker_clean] = acc[i - 1]
        valores_struct[ticker_clean] = valores[i - 1]
        pesos_struct[ticker_clean] = pesos_finales[i - 1]

    detalle['acciones'] = acciones_struct
    detalle['valor_por_activo'] = valores_struct
    detalle['peso_por_activo'] = pesos_struct

    # Series temporales y métricas
    detalle['equity_series'] = equity_series           # serie diaria de equity total
    detalle['valor_activos_series'] = valor_activos_series
    detalle['dates_series'] = dates
    detalle['ret_series'] = r_port                     # *** NUEVO: retornos diarios TWR
    detalle['mdd'] = mdd_val
    detalle['annual_volatility'] = annual_vol

    detalle['params'] = {'periodos': periodos, 'aportacion_total_mes': aportacion_total_mes,
                         'dinero_inicial': dinero_inicial, 'tickers': tickers_config,
                         'weights': weights_config, 'num_activos': num_activos}

    # ======== Salida por pantalla ========
    if not debug:
        print('=' * 117)
        print('Portfolio DCA simple (%s) | %d anos | CAGR: %s%% | Aportes: %d | Valor final: %s'
              % ('/'.join(tickers_config), int(periodos), _fmt(r * 100, '.2f'),
                 num_aportaciones, _fmt(valor_final_total, '.2f')))
        print('Desglose por activo a %s:' % pd.Timestamp(dates[-1]).strftime('%Y-%m-%d'))
        for i in range(1, num_activos + 1):
            print('  %s: %s EUR (%s%%)'
                  % (tickers_config[i - 1], _fmt(valores[i - 1], '.2f'),
                     _fmt(100 * pesos_finales[i - 1], '.2f')))
        print('  TOTAL: %s EUR (100%%)' % _fmt(valor_final_total, '.2f'))
        print('=' * 117)
    else:
        print('=' * 117)
        print('Portfolio DCA Simple Flexible | Sin rebalanceo')
        print('Tickers: %s' % ', '.join(tickers_config))
        print('Pesos objetivo: %s' % ''.join('%.1f%% ' % (x * 100) for x in np.asarray(weights_config).ravel()))
        print('Periodo: %d anos | Aportacion mensual: %s EUR | Inversion inicial: %s EUR'
              % (int(periodos), _fmt(aportacion_total_mes, '.0f'), _fmt(dinero_inicial, '.0f')))
        print('MDD calculado: %s%% | Volatilidad anual (TWR): %s%%'
              % (_fmt(mdd_val * 100, '.2f'), _fmt(annual_vol * 100, '.2f')))
        print('-' * 117)
        print('RESULTADOS:')
        print('  CAGR (IRR): %s%%' % _fmt(r * 100, '.2f'))
        print('  Numero de aportaciones: %d' % num_aportaciones)
        print('  Valor final total: %s EUR' % _fmt(valor_final_total, '.2f'))
        print('  Maximum Drawdown: %s%%' % _fmt(mdd_val * 100, '.2f'))
        print('  Volatilidad anualizada (TWR): %s%%' % _fmt(annual_vol * 100, '.2f'))
        print('-' * 117)
        print('DESGLOSE POR ACTIVO a %s:' % pd.Timestamp(dates[-1]).strftime('%Y-%m-%d'))
        for i in range(1, num_activos + 1):
            print('  %s: %s EUR (%s%%) - %s unidades | Objetivo: %s%%'
                  % (tickers_config[i - 1], _fmt(valores[i - 1], '.2f'),
                     _fmt(100 * pesos_finales[i - 1], '.2f'), _fmt(acc[i - 1], '.4f'),
                     _fmt(np.asarray(weights_config).ravel()[i - 1] * 100, '.1f')))
        print('  TOTAL: %s EUR (100%%)' % _fmt(valor_final_total, '.2f'))
        print('=' * 117)

    return r, num_aportaciones, valor_final_total, detalle


# ========================= HELPERS =========================
def _read_yahoo_csv(csvPath):
    T = pd.read_csv(csvPath)
    if T.empty or T.shape[1] == 0 or T.shape[0] == 0:
        raise ValueError('CSV vacio o sin filas: %s' % csvPath)
    names = [c.replace('_', '').replace(' ', '').lower() for c in T.columns]
    # Fecha
    iDate = next((i for i, n in enumerate(names) if n == 'date'), None)
    if iDate is None:
        iDate = 0
    dates = T.iloc[:, iDate]
    if not pd.api.types.is_datetime64_any_dtype(dates):
        if pd.api.types.is_numeric_dtype(dates):
            dates = pd.to_datetime(dates, unit='D', origin='1899-12-30')
        elif pd.api.types.is_object_dtype(dates) or pd.api.types.is_string_dtype(dates):
            try:
                dates = pd.to_datetime(dates, format='%Y-%m-%d')
            except (ValueError, TypeError):
                dates = pd.to_datetime(dates)
        else:
            dates = pd.to_datetime(dates)
    # Precio (AdjClose > Close)
    iAdj = next((i for i, n in enumerate(names) if n == 'adjclose'), None)
    iClose = next((i for i, n in enumerate(names) if n == 'close'), None)
    if iAdj is not None:
        y = T.iloc[:, iAdj]
    elif iClose is not None:
        y = T.iloc[:, iClose]
    else:
        y = T.iloc[:, -1]
        print('Warning: No AdjClose/Close en %s, usada ultima columna.' % csvPath, file=sys.stderr)
    if pd.api.types.is_object_dtype(y) or pd.api.types.is_string_dtype(y):
        y = pd.to_numeric(
            pd.Series(y).astype(str).str.replace(',', '.', regex=False),
            errors='coerce')
    y = np.asarray(y, dtype=np.float64)
    # Limpiar y ordenar
    dates = pd.DatetimeIndex(dates)
    good = dates.notna() & ~np.isnan(y)
    dates = dates[good]
    y = y[good]
    idx = np.argsort(dates, kind='stable')
    dates = dates[idx]
    close_prices = y[idx]
    close_prices = np.asarray(close_prices, dtype=np.float64).ravel()
    dates = pd.DatetimeIndex(dates)
    return close_prices, dates


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


def _calc_MDD_only(equity_series):
    equity_series = np.asarray(equity_series, dtype=np.float64).ravel()
    if equity_series.size < 2:
        mdd = np.nan
        return mdd
    max_run = np.maximum.accumulate(equity_series)
    dd = (equity_series - max_run) / max_run
    mdd = abs(np.min(dd))
    return mdd
