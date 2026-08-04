"""MAIN PORTFOLIO FLEXIBLE V10 MDD + VOL + SHARPE EN TABLA

Compara DCA vs Event-driven V1/V2. Muestra MDD, Vol anualizada y Sharpe en la tabla principal.
Soporte para carteras de 1 solo activo (N==1).

Migracion 1:1 desde main_portfolio_flexible.m
"""

import os
import traceback

import numpy as np

from Strategy_simple_DCA_flexible_sigma import Strategy_simple_DCA_flexible_sigma
from Strategy_simple_DCA_rebal_flexible_sigma import Strategy_simple_DCA_rebal_flexible_sigma
from Strategy_simple_DCA_rebal_mm_flexible_sigma import Strategy_simple_DCA_rebal_mm_flexible_sigma
from Strategy_event_driven_flexible_v1_sigma import Strategy_event_driven_flexible_v1_sigma
from Strategy_event_driven_rebal_flexible_v1_sigma import Strategy_event_driven_rebal_flexible_v1_sigma
from Strategy_event_driven_rebal_mm_flexible_v1_sigma import Strategy_event_driven_rebal_mm_flexible_v1_sigma
from Strategy_event_driven_rebal_cashpool_flexible_v1_sigma import Strategy_event_driven_rebal_cashpool_flexible_v1_sigma
from Strategy_event_driven_flexible_v2_sigma import Strategy_event_driven_flexible_v2_sigma
from Strategy_event_driven_rebal_flexible_v2_sigma import Strategy_event_driven_rebal_flexible_v2_sigma
from Strategy_event_driven_rebal_mm_flexible_v2_sigma import Strategy_event_driven_rebal_mm_flexible_v2_sigma
from Strategy_event_driven_rebal_cashpool_flexible_v2_sigma import Strategy_event_driven_rebal_cashpool_flexible_v2_sigma


def _isempty(x):
    """Replica de MATLAB isempty()."""
    if x is None:
        return True
    if isinstance(x, np.ndarray):
        return x.size == 0
    if isinstance(x, (list, tuple, dict, str)):
        return len(x) == 0
    return False


def _isvector(x):
    """Replica de MATLAB isvector() sobre arrays."""
    a = np.asarray(x)
    if a.ndim < 2:
        return True
    return a.ndim == 2 and 1 in a.shape


def _isnan_val(v):
    try:
        return bool(np.isnan(v))
    except TypeError:
        return False


def main_portfolio_flexible(portfolio_name=None, tickers_config=None, weights_config=None,
                            basePath=None, periodos=None, MA=None, weight_limits=None,
                            max_cash_dia=None, MA_reb=None, z_engine=None, n_boll=None):
    # ===== VALIDACION DE PARAMETROS =====
    if portfolio_name is None or _isempty(portfolio_name):
        raise ValueError('Debes especificar el nombre del portfolio')

    if tickers_config is None or _isempty(tickers_config):
        raise ValueError('Debes especificar los tickers del portfolio')

    if weights_config is None or _isempty(weights_config):
        weights_config = np.ones(len(tickers_config)) / len(tickers_config)

    if basePath is None or _isempty(basePath):
        basePath = 'C:\\Users\\israe\\OneDrive\\Matlab_scripts\\'

    if periodos is None or _isempty(periodos):
        periodos = 1

    if MA is None or _isempty(MA):
        MA = 150

    # ===== NORMALIZACION PARA N==1 Y ENTRADAS ESCALARES =====
    # Asegurar que tickers sea cell array 1xN
    if isinstance(tickers_config, str):
        tickers_config = [tickers_config]
    n = len(tickers_config)

    # Forzar pesos a vector fila 1xN
    weights_config = np.atleast_1d(np.asarray(weights_config, dtype=float).ravel())
    if weights_config.size == 1 and n > 1:
        # Si el usuario paso un unico peso y hay varios activos, replicarlo
        weights_config = np.tile(weights_config, n)
    if n == 1:
        # Para un solo activo, el peso debe ser 100%
        weights_config = 1

    # Validar que pesos sumen 1
    if abs(np.sum(weights_config) - 1.0) > 1e-6:
        raise ValueError('Los pesos deben sumar 1.0. Suma actual: %.6f' % np.sum(weights_config))

    # Defecto y forma de weight_limits/upper_abs
    if weight_limits is None or _isempty(weight_limits):
        if n == 1:
            weight_limits = 1      # permitir 100% si hay un solo activo
        else:
            weight_limits = 0.30   # por defecto multi-activo
    if np.asarray(weight_limits).size == 1:
        weight_limits = np.tile(np.atleast_1d(np.asarray(weight_limits, dtype=float).ravel()), n)
    upper_abs = np.asarray(weight_limits, dtype=float).ravel()

    # ===== CONFIGURACION =====
    # z_engine = 'shewhart_tippett';   % 'shewhart_tippett' | 'bollinger'
    # n_boll = 22;                     % Periodos Bollinger
    z_threshold = -2.0              # Umbral Z para senales
    debug = False                   # True = output detallado

    # ===== VERIFICAR ARCHIVOS =====
    print('Verificando archivos para portfolio "%s"...' % portfolio_name)
    archivos_faltantes = []
    for i in range(1, len(tickers_config) + 1):
        ticker = tickers_config[i - 1]
        archivo = os.path.join(basePath, ticker + '_yahoo.csv')
        if not os.path.isfile(archivo):
            archivos_faltantes.append(ticker + '_yahoo.csv')

    if len(archivos_faltantes) > 0:
        print('❌ ARCHIVOS FALTANTES:')
        for i in range(1, len(archivos_faltantes) + 1):
            print('   %s' % archivos_faltantes[i - 1])
        print('\nEjecuta main_vYahoo.m primero para descargar estos tickers.')
        return

    print('✅ Todos los archivos están disponibles.\n')

    # ===== EJECUTAR ESTRATEGIAS =====
    pesos_str = ''.join('%.1f%% ' % v for v in np.atleast_1d(np.asarray(weights_config, dtype=float) * 100))
    techos_str = ''.join('%.1f%% ' % v for v in np.asarray(upper_abs, dtype=float) * 100)
    print('Ejecutando Portfolio "%s" - COMPARACION V1 vs V2' % portfolio_name)
    print('Tickers: %s' % ', '.join(tickers_config))
    print('Pesos: %s' % pesos_str)
    print('Techos: %s' % techos_str)
    print('Periodo: %d años | Motor: %s' % (periodos, z_engine))
    print('======================================================\n')

    try:
        # === ESTRATEGIAS BASELINE (DCA) ===
        print('1/11 Ejecutando: Simple DCA...')
        r1, n1, vf1, det1 = Strategy_simple_DCA_flexible_sigma(periodos, basePath, tickers_config, weights_config, debug)

        print('2/11 Ejecutando: Simple + Rebalanceo...')
        r2, n2, vf2, det2 = Strategy_simple_DCA_rebal_flexible_sigma(periodos, basePath, tickers_config, weights_config, upper_abs, debug)

        print('3/11 Ejecutando: Simple + Rebalanceo + MM...')
        r3, n3, vf3, det3 = Strategy_simple_DCA_rebal_mm_flexible_sigma(periodos, basePath, tickers_config, weights_config, upper_abs, MA_reb, debug)

        # === EVENT-DRIVEN V1 (CON LIMITACIONES) ===
        print('4/11 Ejecutando: Event-driven V1...')
        r4, n4, vf4, det4 = Strategy_event_driven_flexible_v1_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, max_cash_dia, debug)

        print('5/11 Ejecutando: Event-driven + Rebalanceo V1...')
        r5, n5, vf5, det5 = Strategy_event_driven_rebal_flexible_v1_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, max_cash_dia, upper_abs, debug)

        print('6/11 Ejecutando: Event-driven + Rebalanceo MM V1...')
        r6, n6, vf6, det6 = Strategy_event_driven_rebal_mm_flexible_v1_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, MA_reb, max_cash_dia, upper_abs, debug)

        print('7/11 Ejecutando: Event-driven + Cash Pool V1...')
        r7, n7, vf7, det7 = Strategy_event_driven_rebal_cashpool_flexible_v1_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, max_cash_dia, upper_abs, debug)

        # === EVENT-DRIVEN V2 (SIN LIMITACIONES) ===
        print('8/11 Ejecutando: Event-driven V2 (sin límites)...')
        r8, n8, vf8, det8 = Strategy_event_driven_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, debug)

        print('9/11 Ejecutando: Event-driven + Rebalanceo V2 (sin límites)...')
        r9, n9, vf9, det9 = Strategy_event_driven_rebal_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, MA_reb, upper_abs, debug)

        print('10/11 Ejecutando: Event-driven + Rebalanceo MM V2 (sin límites)...')
        r10, n10, vf10, det10 = Strategy_event_driven_rebal_mm_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, MA_reb, upper_abs, debug)

        print('11/11 Ejecutando: Event-driven + Cash Pool V2 (sin límites)...')
        r11, n11, vf11, det11 = Strategy_event_driven_rebal_cashpool_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, upper_abs, debug)

        # ===== EXTRAER MDD Y VOLATILIDAD DE CADA ESTRATEGIA =====
        det_list = [det1, det2, det3, det4, det5, det6, det7, det8, det9, det10, det11]
        mdd_valores = np.zeros(11)
        vol_valores = np.zeros(11)

        for i in range(1, 12):
            current_det = det_list[i - 1]
            if isinstance(current_det, dict):
                # Extraer MDD
                if 'mdd' in current_det and not _isempty(current_det['mdd']):
                    mdd_valores[i - 1] = current_det['mdd']
                elif 'equity_series' in current_det and not _isempty(current_det['equity_series']):
                    equity_series = current_det['equity_series']
                    if _isvector(equity_series) and np.asarray(equity_series).size > 1:
                        mdd_valores[i - 1] = calc_MDD(equity_series)
                    else:
                        mdd_valores[i - 1] = np.nan
                else:
                    mdd_valores[i - 1] = np.nan

                # Extraer Volatilidad Anualizada
                if 'annual_volatility' in current_det and not _isempty(current_det['annual_volatility']):
                    vol_valores[i - 1] = current_det['annual_volatility']
                else:
                    vol_valores[i - 1] = np.nan
            else:
                mdd_valores[i - 1] = np.nan
                vol_valores[i - 1] = np.nan

        # ===== EXTRAER METRICAS DE APALANCAMIENTO Y CASH BAL =====
        # deuda_max_v2: V1=0; V2 toma abs(min_cash) si existe
        deuda_max_v2 = np.zeros(11)
        # V2
        deuda_max_v2[7] = exist_field(det8, 'min_cash') * abs(safe_get(det8, 'min_cash'))
        deuda_max_v2[8] = exist_field(det9, 'min_cash') * abs(safe_get(det9, 'min_cash'))
        deuda_max_v2[9] = exist_field(det10, 'min_cash') * abs(safe_get(det10, 'min_cash'))
        deuda_max_v2[10] = exist_field(det11, 'min_cash') * abs(safe_get(det11, 'min_cash'))

        # Extraer cash_series de cada estrategia
        cash_balance = np.zeros(11)
        for i in range(1, 12):
            current_det = det_list[i - 1]
            if isinstance(current_det, dict):
                if 'cash_series' in current_det:
                    cs = current_det['cash_series']
                    if _isvector(cs) and not _isempty(cs):
                        cash_balance[i - 1] = np.asarray(cs, dtype=float).ravel()[-1]  # Ultimo valor
                    elif np.isscalar(cs):
                        cash_balance[i - 1] = cs
                    else:
                        # dejar en 0 si vacio
                        pass
                else:
                    # Para estrategias DCA simples que no manejan cash, el cash final es 0
                    cash_balance[i - 1] = 0

        # ===== PREP: RENDIMIENTOS (CAGR) + SHARPE =====
        rendimientos = np.array([r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11], dtype=float)

        # Nombres de estrategias (se usan mas abajo tambien)
        estrategias_nombres = ['Simple DCA', 'Simple + Rebalanceo', 'Simple + Rebal + MM',
                               'Event-driven V1', 'Event + Rebalanceo V1', 'Event + Rebal MM V1', 'Event + Cash Pool V1',
                               'Event-driven V2', 'Event + Rebalanceo V2', 'Event + Rebal MM V2', 'Event + Cash Pool V2']

        # Saneado de volatilidades: evita 0 o negativos
        vol_bad = ~np.isfinite(vol_valores) | (vol_valores <= 0)
        vol_valores[vol_bad] = np.nan

        # Sharpe anual con rf fijo
        tipo_libre_riesgo = 0.025  # 2.5% anual como referencia
        sharpe_ratios = np.full(11, np.nan)
        for i in range(1, 12):
            if np.isfinite(rendimientos[i - 1]) and np.isfinite(vol_valores[i - 1]) and vol_valores[i - 1] > 0:
                sharpe_ratios[i - 1] = (rendimientos[i - 1] - tipo_libre_riesgo) / vol_valores[i - 1]

        # ===== RESUMEN COMPARATIVO (CON SHARPE EN TABLA) =====
        print('\n=== RESUMEN COMPARATIVO === Portfolio "%s" MA=%d Periodos=%d' % (portfolio_name, MA, periodos))
        print('%-32s %9s %10s %14s %12s %16s %14s %5s %6s %8s' %
              ('Estrategia', 'CAGR', 'Aportes', 'Valor Final', 'Equity', 'Cash Final', 'Deuda Max', 'MDD', 'Sigma', 'Sharpe'))
        print('%s' % ('-' * 140))

        valores_finales = np.array([vf1, vf2, vf3, vf4, vf5, vf6, vf7, vf8, vf9, vf10, vf11], dtype=float)
        NaN = np.nan
        estrategias_data = [
            ['Simple DCA', r1, n1, vf1, cash_balance[0], deuda_max_v2[0], mdd_valores[0], vol_valores[0], sharpe_ratios[0]],
            ['Simple + Rebalanceo', r2, n2, vf2, cash_balance[1], deuda_max_v2[1], mdd_valores[1], vol_valores[1], sharpe_ratios[1]],
            ['Simple + Rebal + MM', r3, n3, vf3, cash_balance[2], deuda_max_v2[2], mdd_valores[2], vol_valores[2], sharpe_ratios[2]],
            ['--- EVENT-DRIVEN V1 (SIN DEUDA) ---', NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN],
            ['Event-driven V1', r4, n4, vf4, cash_balance[3], deuda_max_v2[3], mdd_valores[3], vol_valores[3], sharpe_ratios[3]],
            ['Event + Rebalanceo V1', r5, n5, vf5, cash_balance[4], deuda_max_v2[4], mdd_valores[4], vol_valores[4], sharpe_ratios[4]],
            ['Event + Rebal MM V1', r6, n6, vf6, cash_balance[5], deuda_max_v2[5], mdd_valores[5], vol_valores[5], sharpe_ratios[5]],
            ['Event + Cash Pool V1', r7, n7, vf7, cash_balance[6], deuda_max_v2[6], mdd_valores[6], vol_valores[6], sharpe_ratios[6]],
            ['--- EVENT-DRIVEN V2 (CON DEUDA) ---', NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN],
            ['Event-driven V2', r8, n8, vf8, cash_balance[7], deuda_max_v2[7], mdd_valores[7], vol_valores[7], sharpe_ratios[7]],
            ['Event + Rebalanceo V2', r9, n9, vf9, cash_balance[8], deuda_max_v2[8], mdd_valores[8], vol_valores[8], sharpe_ratios[8]],
            ['Event + Rebal MM V2', r10, n10, vf10, cash_balance[9], deuda_max_v2[9], mdd_valores[9], vol_valores[9], sharpe_ratios[9]],
            ['Event + Cash Pool V2', r11, n11, vf11, cash_balance[10], deuda_max_v2[10], mdd_valores[10], vol_valores[10], sharpe_ratios[10]],
        ]

        for i in range(1, len(estrategias_data) + 1):
            fila = estrategias_data[i - 1]
            if _isnan_val(fila[1]):
                print('%-35s %s' % (fila[0], '-' * 104))
            else:
                valor_final = fila[3]
                cash_final = fila[4]
                equity = valor_final + cash_final
                mdd_val = fila[6]
                vol_val = fila[7]
                sh_val = fila[8]

                if _isnan_val(mdd_val):
                    mdd_str = 'N/A'
                else:
                    mdd_str = '%.1f%%' % (mdd_val * 100)
                if _isnan_val(vol_val):
                    vol_str = 'N/A'
                else:
                    vol_str = '%.1f%%' % (vol_val * 100)
                if _isnan_val(sh_val):
                    sh_str = 'N/A'
                else:
                    sh_str = '%.2f' % sh_val

                print('%-35s %6.2f%% %8d %11.0f EUR %11.0f EUR %9.0f EUR %9.0f EUR %7s %6s %8s' %
                      (fila[0], fila[1] * 100, int(fila[2]),
                       valor_final, equity, cash_final, fila[5], mdd_str, vol_str, sh_str))

        # ===== ANALISIS DE MEJORAS V1 -> V2 =====
        if debug:
            print('\n=== ANALISIS DE MEJORAS V1 -> V2 ===')
            mejoras_cagr = [(r8 - r4) * 100, (r9 - r5) * 100, (r10 - r6) * 100, (r11 - r7) * 100]
            mejoras_valor = [vf8 - vf4, vf9 - vf5, vf10 - vf6, vf11 - vf7]
            mejoras_mdd = [(mdd_valores[7] - mdd_valores[3]) * 100, (mdd_valores[8] - mdd_valores[4]) * 100,
                           (mdd_valores[9] - mdd_valores[5]) * 100, (mdd_valores[10] - mdd_valores[6]) * 100]
            mejoras_vol = [(vol_valores[7] - vol_valores[3]) * 100, (vol_valores[8] - vol_valores[4]) * 100,
                           (vol_valores[9] - vol_valores[5]) * 100, (vol_valores[10] - vol_valores[6]) * 100]

            print('Event-driven básico:      V1=%.2f%% -> V2=%.2f%% (+%.2fpp, +%.0f EUR, MDD: %.1f%% -> %.1f%%, Vol: %.1f%% -> %.1f%%)' %
                  (r4 * 100, r8 * 100, mejoras_cagr[0], mejoras_valor[0], mdd_valores[3] * 100, mdd_valores[7] * 100, vol_valores[3] * 100, vol_valores[7] * 100))
            print('Event + Rebalanceo:       V1=%.2f%% -> V2=%.2f%% (+%.2fpp, +%.0f EUR, MDD: %.1f%% -> %.1f%%, Vol: %.1f%% -> %.1f%%)' %
                  (r5 * 100, r9 * 100, mejoras_cagr[1], mejoras_valor[1], mdd_valores[4] * 100, mdd_valores[8] * 100, vol_valores[4] * 100, vol_valores[8] * 100))
            print('Event + Rebal MM:         V1=%.2f%% -> V2=%.2f%% (+%.2fpp, +%.0f EUR, MDD: %.1f%% -> %.1f%%, Vol: %.1f%% -> %.1f%%)' %
                  (r6 * 100, r10 * 100, mejoras_cagr[2], mejoras_valor[2], mdd_valores[5] * 100, mdd_valores[9] * 100, vol_valores[5] * 100, vol_valores[9] * 100))
            print('Event + Cash Pool:        V1=%.2f%% -> V2=%.2f%% (+%.2fpp, +%.0f EUR, MDD: %.1f%% -> %.1f%%, Vol: %.1f%% -> %.1f%%)' %
                  (r7 * 100, r11 * 100, mejoras_cagr[3], mejoras_valor[3], mdd_valores[6] * 100, mdd_valores[10] * 100, vol_valores[6] * 100, vol_valores[10] * 100))

        # ===== MEJOR ESTRATEGIA GENERAL =====
        # MATLAB max omite NaN y devuelve el primer indice del maximo
        rend_no_nan = ~np.isnan(rendimientos)
        if np.any(rend_no_nan):
            idx_mejor = int(np.flatnonzero(rend_no_nan)[np.argmax(rendimientos[rend_no_nan])]) + 1
            mejor_r = rendimientos[idx_mejor - 1]
        else:
            idx_mejor = 1
            mejor_r = np.nan

        # Mapear categoria por indice
        if idx_mejor <= 3:
            categoria = 'DCA'
        elif idx_mejor <= 7:
            categoria = 'Event-Driven V1'
        else:
            categoria = 'Event-Driven V2'

        print('\n=== MEJOR ESTRATEGIA ===')
        print('🏆 %s (%s)' % (estrategias_nombre_por_indice(idx_mejor), categoria))
        print('CAGR: %.2f%% | Valor Final: %.0f EUR | Cash Final: %.0f EUR | Deuda Máxima: %.0f EUR | MDD: %.1f%% | Vol: %.1f%% | Sharpe: %.2f' %
              (mejor_r * 100, valores_finales[idx_mejor - 1], cash_balance[idx_mejor - 1], deuda_max_v2[idx_mejor - 1],
               mdd_valores[idx_mejor - 1] * 100, vol_valores[idx_mejor - 1] * 100, sharpe_ratios[idx_mejor - 1]))

        # ===== MEJOR ESTRATEGIA POR SHARPE RATIO =====
        valid_sh = np.flatnonzero(~np.isnan(sharpe_ratios)) + 1
        if valid_sh.size > 0:
            sharpe_validos = sharpe_ratios[valid_sh - 1]
            rel_idx = int(np.argmax(sharpe_validos)) + 1
            mejor_sharpe = sharpe_validos[rel_idx - 1]
            idx_mejor_sharpe = valid_sh[rel_idx - 1]
            if idx_mejor_sharpe != idx_mejor:
                print('\n=== MEJOR ESTRATEGIA AJUSTADA POR RIESGO (SHARPE) ===')
                print('🎯 %s' % estrategias_nombres[idx_mejor_sharpe - 1])
                print('CAGR: %.2f%% | Vol: %.1f%% | Sharpe: %.2f | MDD: %.1f%%' %
                      (rendimientos[idx_mejor_sharpe - 1] * 100, vol_valores[idx_mejor_sharpe - 1] * 100,
                       mejor_sharpe, mdd_valores[idx_mejor_sharpe - 1] * 100))

        # ===== ANALISIS DEUDA vs RENDIMIENTO =====
        if debug:
            print('\n=== ANALISIS DEUDA vs RENDIMIENTO ===')
            print('Estrategias V2 con mayor apalancamiento:')
            idx_deuda = np.argsort(-deuda_max_v2[7:11], kind='stable') + 1
            estrategias_v2 = ['Event-driven V2', 'Event + Rebalanceo V2', 'Event + Rebal MM V2', 'Event + Cash Pool V2']
            rendimientos_v2 = np.array([r8, r9, r10, r11], dtype=float)
            cash_balance_v2 = cash_balance[7:11]
            mdd_v2 = mdd_valores[7:11]
            vol_v2 = vol_valores[7:11]

            for i in range(1, 5):
                idx = idx_deuda[i - 1]
                print('  %s: %.2f%% CAGR, %.0f EUR cash final, %.0f EUR deuda máxima, %.1f%% MDD, %.1f%% Vol' %
                      (estrategias_v2[idx - 1], rendimientos_v2[idx - 1] * 100, cash_balance_v2[idx - 1], deuda_max_v2[7 + idx - 1], mdd_v2[idx - 1] * 100, vol_v2[idx - 1] * 100))

            # ===== ANALISIS RIESGO-RETORNO =====
            print('\n=== ANALISIS RIESGO-RETORNO ===')
            print('Estrategias ordenadas por mejor ratio Rendimiento/MDD:')
            with np.errstate(divide='ignore', invalid='ignore'):
                ratio_riesgo_retorno = rendimientos / mdd_valores
            ratio_validos = ratio_riesgo_retorno[~np.isnan(ratio_riesgo_retorno)]
            idx_ratio = np.argsort(-ratio_validos, kind='stable') + 1

            # Mapear indices originales a la lista filtrada ratio_validos
            idx_no_nan = np.flatnonzero(~np.isnan(ratio_riesgo_retorno)) + 1
            for i in range(1, min(5, len(idx_ratio)) + 1):  # Top 5
                orig_idx = idx_no_nan[idx_ratio[i - 1] - 1]
                print('  %d. %s: %.2f%% CAGR / %.1f%% MDD = %.2f ratio' %
                      (i, estrategias_nombres[orig_idx - 1], rendimientos[orig_idx - 1] * 100, mdd_valores[orig_idx - 1] * 100, ratio_riesgo_retorno[orig_idx - 1]))

        # ===== CONCLUSIONES =====
        if debug:
            print('\n=== CONCLUSIONES ===')
            # Estas variables se definen en el bloque de mejoras (tambien bajo debug==true)
            # mejora_promedio = mean(mejoras_cagr);
            # mejora_mdd_promedio = mean(mejoras_mdd);
            # mejora_vol_promedio = mean(mejoras_vol);
            # (Si quieres usarlas aqui, mueve su calculo fuera o repetilo.)
            print('Resumen mostrado arriba. Ajusta "debug=true" para detalles adicionales.')

            if np.max(deuda_max_v2[7:11]) > 15000:
                print('Atención: Algunas estrategias V2 requieren apalancamiento >15k EUR')

            r123 = np.array([r1, r2, r3], dtype=float)
            mejor_dca = np.max(r123[~np.isnan(r123)]) if np.any(~np.isnan(r123)) else np.nan
            rend_event = rendimientos[3:]
            mejor_event = np.max(rend_event[~np.isnan(rend_event)]) if np.any(~np.isnan(rend_event)) else np.nan

            # Comparar tambien MDDs y volatilidades
            matches_dca = np.flatnonzero(r123 == mejor_dca)
            idx_mejor_dca = int(matches_dca[0]) + 1 if matches_dca.size > 0 else 0
            mdd_mejor_dca = mdd_valores[idx_mejor_dca - 1] if idx_mejor_dca >= 1 else np.nan
            vol_mejor_dca = vol_valores[idx_mejor_dca - 1] if idx_mejor_dca >= 1 else np.nan

            matches_event = np.flatnonzero(rend_event == mejor_event)
            idx_mejor_event_rel = int(matches_event[0]) + 1 if matches_event.size > 0 else 0
            idx_mejor_event = idx_mejor_event_rel + 3
            mdd_mejor_event = mdd_valores[idx_mejor_event - 1] if idx_mejor_event_rel >= 1 else np.nan
            vol_mejor_event = vol_valores[idx_mejor_event - 1] if idx_mejor_event_rel >= 1 else np.nan

            if mejor_event > mejor_dca:
                print('🎯 Event-driven supera a DCA: %.2f%% vs %.2f%% (+%.2fpp)' %
                      (mejor_event * 100, mejor_dca * 100, (mejor_event - mejor_dca) * 100))
                print('   Riesgo: MDD %.1f%% vs %.1f%%, Vol %.1f%% vs %.1f%%' %
                      (mdd_mejor_event * 100, mdd_mejor_dca * 100, vol_mejor_event * 100, vol_mejor_dca * 100))
            else:
                print('📊 DCA sigue siendo competitivo frente a event-driven')

        print('\n=== EJECUCION COMPLETADA ===')

    except Exception as ME:
        print('❌ Error durante la ejecución: %s' % ME)
        tb = traceback.extract_tb(ME.__traceback__)
        if len(tb) > 0:
            print('Línea del error: %d' % tb[-1].lineno)

        # Verificar archivos CSV nuevamente
        print('\nVerificando archivos...')
        for i in range(1, len(tickers_config) + 1):
            ticker = tickers_config[i - 1]
            archivo = os.path.join(basePath, ticker + '_yahoo.csv')
            if os.path.isfile(archivo):
                print('✅ %s' % (ticker + '_yahoo.csv'))
            else:
                print('❌ FALTA: %s' % (ticker + '_yahoo.csv'))


# ===================== HELPERS LOCALES =====================
def calc_MDD(equity_series):
    # equity_series: vector fila/columna con el valor total de la cartera en el tiempo
    equity_series = np.asarray(equity_series, dtype=float).ravel()
    if equity_series.size < 2:
        return np.nan
    max_run = np.maximum.accumulate(equity_series)              # maximo acumulado
    with np.errstate(divide='ignore', invalid='ignore'):
        dd = (equity_series - max_run) / max_run                # drawdown relativo (<=0)
    return abs(np.nanmin(dd))                                   # como porcentaje positivo


def exist_field(s, f):
    return isinstance(s, dict) and (f in s) and not _isempty(s[f])


def safe_get(s, f):
    if isinstance(s, dict) and (f in s) and not _isempty(s[f]):
        return s[f]
    else:
        return 0


def estrategias_nombre_por_indice(idx):
    nombres = ['Simple DCA', 'Simple + Rebalanceo', 'Simple + Rebal + MM',
               'Event-driven V1', 'Event + Rebalanceo V1', 'Event + Rebal MM V1', 'Event + Cash Pool V1',
               'Event-driven V2', 'Event + Rebalanceo V2', 'Event + Rebal MM V2', 'Event + Cash Pool V2']
    return nombres[idx - 1]


if __name__ == '__main__':
    # La funcion requiere argumentos obligatorios (portfolio_name, tickers_config);
    # no hay argumentos demo en el .m original. Se expone sin ejecutar.
    pass
