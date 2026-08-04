"""Portfolio DCA + Rebalanceo con filtro MA flexible
CAMBIOS MINIMOS:
- Añadido r_port (retorno diario TWR) calculado ANTES de aportar/rebalancear
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


def Strategy_simple_DCA_rebal_mm_flexible_sigma(periodos=None, basePath=None, tickers_config=None,
                                                weights_config=None, upper_abs=None, ma_dias=None,
                                                debug=None):
    # ======== Validación de parámetros ========
    if _isempty(tickers_config):
        raise ValueError('Debes especificar los tickers del portfolio')

    if _isempty(weights_config):
        weights_config = np.ones(len(tickers_config)) / len(tickers_config)

    if periodos is None:
        periodos = 5
    if _isempty(basePath):
        basePath = 'C:\\Users\\israe\\OneDrive\\Matlab_scripts\\'
    if _isempty(upper_abs):
        upper_abs = 0.30 * np.ones(len(tickers_config))
    if _isempty(ma_dias):
        ma_dias = 50
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

    # ======== Parámetros de estrategia ========
    dinero_inicial = 1000
    aportacion_total_mes = 1500
    dias_por_aporte = 21

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
        series_data[i - 1], dates_data[i - 1] = _read_yahoo_csv_local(file_paths[i - 1])

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

    # ======== Media movil ========
    ma = pd.DataFrame(series).rolling(ma_dias, min_periods=1).mean().to_numpy()

    # ======== Setup para tracking completo ========
    fechas_aport = np.arange(1, N_dias + 1, dias_por_aporte)
    num_aportaciones = len(fechas_aport)
    aportacion_por_activo = aportacion_total_mes * w

    acc = np.zeros(num_activos)

    # Arrays para MDD y VOL
    equity_series = np.zeros(N_dias)      # equity día a día (con flujos)
    r_port = np.full(N_dias, np.nan)      # retorno diario TWR (sin flujos del día)
    precios_prev = series[0, :]           # precios del "día anterior" para TWR

    # Compra inicial por pesos configurados
    if dinero_inicial > 0:
        precios_d1 = series[0, :]
        init_eur = dinero_inicial * w
        acc = acc + (init_eur / precios_d1)

    # Contadores para verificar diferencias
    ma_redirections = np.zeros(num_activos)
    normal_redirections = np.zeros(num_activos)

    detalle = {}
    detalle['fechas'] = dates[fechas_aport - 1]
    detalle['rebals'] = np.zeros(num_aportaciones, dtype=bool)
    detalle['ma_used'] = np.zeros(num_aportaciones, dtype=bool)
    detalle['compras'] = np.zeros((num_aportaciones, num_activos))
    detalle['cash_from_sell'] = np.zeros(num_aportaciones)
    detalle['cash_to_buy'] = np.zeros(num_aportaciones)
    detalle['over_assets'] = [None] * num_aportaciones

    # ======== BUCLE PRINCIPAL (TWR ANTES DE FLUJOS) ========
    aporte_idx = 1

    for dia in range(1, N_dias + 1):
        precios_dia = series[dia - 1, :]
        ma_i = ma[dia - 1, :]

        # (1) Retorno TWR ANTES de aportar/rebalancear
        if dia == 1:
            r_port[dia - 1] = np.nan  # sin retorno el primer día
        else:
            valor_inicio = np.sum(acc * precios_prev)  # valor al inicio SIN flujos del propio día
            if valor_inicio > 0:
                r_port[dia - 1] = (np.sum(acc * precios_dia) - np.sum(acc * precios_prev)) / valor_inicio
            else:
                r_port[dia - 1] = 0  # o NaN si prefieres

        # (2) Día de aportación + posible rebalanceo
        if aporte_idx <= len(fechas_aport) and dia == fechas_aport[aporte_idx - 1]:
            # 2.1) DCA mensual (después de medir r_port)
            compra_unidades = aportacion_por_activo / precios_dia
            acc = acc + compra_unidades
            detalle['compras'][aporte_idx - 1, :] = compra_unidades

            # 2.2) Estado tras DCA
            valores = acc * precios_dia
            total = np.sum(valores)
            target = total * w
            pesos = valores / total

            # 3) Vender exceso si supera techo
            over = pesos > upper_abs
            if np.any(over):
                detalle['rebals'][aporte_idx - 1] = True

                # Crear lista de activos que superan techo
                activos_over = [tickers_config[k] for k in range(num_activos) if over[k]]
                detalle['over_assets'][aporte_idx - 1] = '|'.join(activos_over)

                # Calcular exceso y vender
                exceso_total = np.sum(valores[over] - target[over])
                valores[over] = target[over]  # Quedan en objetivo
                detalle['cash_from_sell'][aporte_idx - 1] = exceso_total

                # Decidir quienes reciben el exceso
                receptores = ~over  # Los que no se vendieron

                bajo_ma = (precios_dia < ma_i) & np.isfinite(ma_i)
                receptores_bajo_ma = receptores & bajo_ma

                if np.any(receptores_bajo_ma):
                    # USAR FILTRO MA: solo dar dinero a los que están bajo MA
                    detalle['ma_used'][aporte_idx - 1] = True
                    elegidos = receptores_bajo_ma
                    ma_redirections = ma_redirections + elegidos.astype(np.float64)
                else:
                    # Lógica NORMAL: dar a todos los no-vendedores
                    elegidos = receptores
                    normal_redirections = normal_redirections + elegidos.astype(np.float64)

                # Repartir el exceso entre elegidos
                if np.any(elegidos):
                    # Primero cubrir déficits
                    deficit = np.maximum(target[elegidos] - valores[elegidos], 0)
                    total_deficit = np.sum(deficit)

                    if total_deficit > 0 and exceso_total > total_deficit:
                        # Cubrir déficits primero
                        valores[elegidos] = valores[elegidos] + deficit
                        exceso_restante = exceso_total - total_deficit
                    else:
                        exceso_restante = exceso_total

                    # Repartir resto proporcional por peso objetivo
                    if exceso_restante > 1e-12:
                        w_elegidos = w[elegidos]
                        w_elegidos = w_elegidos / np.sum(w_elegidos)
                        valores_elegidos = valores[elegidos] + exceso_restante * w_elegidos
                        valores[elegidos] = valores_elegidos

                    detalle['cash_to_buy'][aporte_idx - 1] = exceso_total

                # Actualizar unidades tras el rebalanceo
                acc = valores / precios_dia

            aporte_idx = aporte_idx + 1

        # (3) Tracking de equity (INCLUYE los flujos del propio día)
        equity_series[dia - 1] = np.sum(acc * precios_dia)

        # (4) Actualizar precios_prev
        precios_prev = precios_dia

    # ======== Resultado final ========
    precios_ult = series[-1, :]
    valores = acc * precios_ult
    valor_final_total = np.sum(valores)

    # Pesos finales
    pesos_finales = valores / valor_final_total

    # ======== CAGR ========
    aportes = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion_total_mes)))
    t_anios = np.concatenate(([0], (fechas_aport - 1) * 365 / 252))
    tiempos = periodos - t_anios / 365

    def funcion_CAGR(rr):
        return np.sum(aportes * (1 + rr) ** tiempos) - valor_final_total

    with np.errstate(invalid='ignore'):
        try:
            r = brentq(funcion_CAGR, -0.99, 10)
        except Exception:
            r = newton(funcion_CAGR, 0.1)

    # ======== MDD (equity) y VOL (TWR) ========
    mdd_val = _calc_MDD_only(equity_series)
    valid_r = r_port[~np.isnan(r_port)]
    daily_std = np.nanstd(valid_r, ddof=1)
    annual_vol = daily_std * np.sqrt(252)

    # ======== Detalle estructurado ========
    acciones_struct = {}
    valores_struct = {}
    pesos_struct = {}

    # (bucle muerto `for i = 1*num_activos` del original: no-op, se conserva la semántica)
    for i in range(1, num_activos + 1):
        ticker_clean = _make_valid_name(tickers_config[i - 1])
        acciones_struct[ticker_clean] = acc[i - 1]
        valores_struct[ticker_clean] = valores[i - 1]
        pesos_struct[ticker_clean] = pesos_finales[i - 1]

    detalle['acciones'] = acciones_struct
    detalle['valor_por_activo'] = valores_struct
    detalle['peso_por_activo'] = pesos_struct

    # Series y métricas clave
    detalle['equity_series'] = equity_series
    detalle['dates_series'] = dates
    detalle['ret_series'] = r_port                 # *** NUEVO: retornos diarios TWR
    detalle['mdd'] = mdd_val
    detalle['annual_volatility'] = annual_vol

    detalle['ma_redirections'] = ma_redirections
    detalle['normal_redirections'] = normal_redirections
    detalle['total_rebals'] = np.sum(detalle['rebals'])
    detalle['ma_activations'] = np.sum(detalle['ma_used'])
    detalle['params'] = {'periodos': periodos, 'aportacion_total_mes': aportacion_total_mes,
                         'dinero_inicial': dinero_inicial, 'tickers': tickers_config,
                         'weights': weights_config, 'upper_abs': upper_abs, 'ma_dias': ma_dias}

    # ======== Salida ========
    if not debug:
        print('=' * 117)
        print('Portfolio DCA + Ventas POST-DCA + Prioridad MA%d (%s) | %d anos | CAGR: %s%% | Aportes: %d | Valor final: %s'
              % (int(ma_dias), '/'.join(tickers_config), int(periodos), _fmt(r * 100, '.2f'),
                 num_aportaciones, _fmt(valor_final_total, '.2f')))
        print('Rebalanceos ejecutados: %d' % detalle['total_rebals'])

        redirecciones_str = ''
        for j in range(1, num_activos + 1):
            redirecciones_str = redirecciones_str + '%s=%d ' % (tickers_config[j - 1],
                                                                int(ma_redirections[j - 1]))
        print('Redirecciones por MA: %s' % redirecciones_str)

        print('Desglose por activo a %s:' % pd.Timestamp(dates[-1]).strftime('%Y-%m-%d'))
        for i in range(1, num_activos + 1):
            print('  %s: %s EUR (%s%%)'
                  % (tickers_config[i - 1], _fmt(valores[i - 1], '.2f'),
                     _fmt(100 * pesos_finales[i - 1], '.2f')))
        print('  TOTAL: %s EUR (100%%)' % _fmt(valor_final_total, '.2f'))
        print('=' * 117)
    else:
        print('=== DEBUG: DIFERENCIAS CON ESTRATEGIA SIMPLE ===')
        print('Total rebalanceos: %d' % detalle['total_rebals'])
        print('Veces que MA modifico la redistribucion: %d' % detalle['ma_activations'])
        print('MDD calculado: %s%% | Volatilidad anual (TWR): %s%%'
              % (_fmt(mdd_val * 100, '.2f'), _fmt(annual_vol * 100, '.2f')))

        redirecciones_ma_str = ''
        redirecciones_norm_str = ''
        for j in range(1, num_activos + 1):
            redirecciones_ma_str = redirecciones_ma_str + '%s=%d ' % (tickers_config[j - 1],
                                                                      int(ma_redirections[j - 1]))
            redirecciones_norm_str = redirecciones_norm_str + '%s=%d ' % (tickers_config[j - 1],
                                                                          int(normal_redirections[j - 1]))
        print('Redirecciones POR MA: %s' % redirecciones_ma_str)
        print('Redirecciones NORMALES: %s' % redirecciones_norm_str)
        print('CAGR: %s%% | Valor final: %s EUR'
              % (_fmt(r * 100, '.4f'), _fmt(valor_final_total, '.2f')))
        print('Maximum Drawdown: %s%% | Volatilidad anualizada (TWR): %s%%'
              % (_fmt(mdd_val * 100, '.2f'), _fmt(annual_vol * 100, '.2f')))

    return r, num_aportaciones, valor_final_total, detalle


# ========================= HELPER FUNCTIONS =========================
def _read_yahoo_csv_local(csvPath):
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
