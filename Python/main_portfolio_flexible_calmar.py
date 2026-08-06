"""MAIN PORTFOLIO FLEXIBLE V10 MDD + VOL + SHARPE + CALMAR EN TABLA (COMPACTA)

Compara DCA vs Event-driven V1/V2. Muestra MDD, Vol anualizada, Sharpe y Calmar en la tabla principal.

Migracion 1:1 desde main_portfolio_flexible_calmar.m
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


def _round(x):
    """Replica de MATLAB round() (mitades alejandose de cero)."""
    x = np.asarray(x, dtype=float)
    return np.sign(x) * np.floor(np.abs(x) + 0.5)


def main_portfolio_flexible_calmar(portfolio_name=None, tickers_config=None, weights_config=None,
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
    if isinstance(tickers_config, str):
        tickers_config = [tickers_config]
    n = len(tickers_config)
    weights_config = np.atleast_1d(np.asarray(weights_config, dtype=float).ravel())
    if weights_config.size == 1 and n > 1:
        weights_config = np.tile(weights_config, n)
    if n == 1:
        weights_config = 1
    if abs(np.sum(weights_config) - 1.0) > 1e-6:
        raise ValueError('Los pesos deben sumar 1.0. Suma actual: %.6f' % np.sum(weights_config))

    if weight_limits is None or _isempty(weight_limits):
        if n == 1:
            weight_limits = 1
        else:
            weight_limits = 0.30
    if np.asarray(weight_limits).size == 1:
        weight_limits = np.tile(np.atleast_1d(np.asarray(weight_limits, dtype=float).ravel()), n)
    upper_abs = np.asarray(weight_limits, dtype=float).ravel()

    # ===== CONFIGURACION =====
    z_threshold = -2.0
    debug = False

    # ===== VERIFICAR ARCHIVOS =====
    print('Verificando archivos para portfolio "%s"...' % portfolio_name)
    archivos_faltantes = []
    for i in range(1, len(tickers_config) + 1):
        archivo = os.path.join(basePath, tickers_config[i - 1] + '_yahoo.csv')
        if not os.path.isfile(archivo):
            archivos_faltantes.append(tickers_config[i - 1] + '_yahoo.csv')
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
        print('10/11 Ejecutando: Event-driven + Rebal MM V2 (sin límites)...')
        r10, n10, vf10, det10 = Strategy_event_driven_rebal_mm_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, MA_reb, upper_abs, debug)
        print('11/11 Ejecutando: Event-driven + Cash Pool V2 (sin límites)...')
        r11, n11, vf11, det11 = Strategy_event_driven_rebal_cashpool_flexible_v2_sigma(periodos, basePath, tickers_config, weights_config, z_engine, n_boll, z_threshold, MA, upper_abs, debug)

        # ===== EXTRAER METRICAS =====
        det_list = [det1, det2, det3, det4, det5, det6, det7, det8, det9, det10, det11]
        mdd_valores = np.zeros(11)
        vol_valores = np.zeros(11)
        for i in range(1, 12):
            d = det_list[i - 1]
            if isinstance(d, dict):
                if 'mdd' in d and not _isempty(d['mdd']):
                    mdd_valores[i - 1] = d['mdd']
                if 'annual_volatility' in d and not _isempty(d['annual_volatility']):
                    vol_valores[i - 1] = d['annual_volatility']
        deuda_max_v2 = np.zeros(11)
        for i in range(8, 12):
            deuda_max_v2[i - 1] = abs(safe_get(det_list[i - 1], 'min_cash'))
        cash_balance = np.array([safe_get_last(d, 'cash_series') for d in det_list], dtype=float)

        # ===== INDICADORES =====
        rendimientos = np.array([r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11], dtype=float)
        aportes = np.array([n1, n2, n3, n4, n5, n6, n7, n8, n9, n10, n11])
        valores_fin = np.array([vf1, vf2, vf3, vf4, vf5, vf6, vf7, vf8, vf9, vf10, vf11], dtype=float)
        rf = 0.025
        with np.errstate(divide='ignore', invalid='ignore'):
            sharpe_ratios = (rendimientos - rf) / vol_valores
            calmar_ratios = rendimientos / mdd_valores

        # ===== TABLA COMPACTA Y ALINEADA =====
        sep = '-' * 130
        print('\n=== RESUMEN COMPARATIVO === Portfolio "%s" MA=%d Periodos=%d' % (portfolio_name, MA, periodos))
        print('%-30s %7s %7s %14s %14s %12s %12s %6s %6s %7s %7s' %
              ('Estrategia', 'CAGR', 'Aportes', 'ValorFin', 'Equity', 'Cash', 'Deuda', 'MDD', 'Sigma', 'Sharpe', 'Calmar'))
        print('%s' % sep)

        # Bloques y nombres
        nombres = [
            'Simple DCA', 'Simple + Rebalanceo', 'Simple + Rebal + MM',
            '--- EVENT-DRIVEN V1 (SIN DEUDA) ---',
            'Event-driven V1', 'Event + Rebalanceo V1', 'Event + Rebal MM V1', 'Event + Cash Pool V1',
            '--- EVENT-DRIVEN V2 (CON DEUDA) ---',
            'Event-driven V2', 'Event + Rebalanceo V2', 'Event + Rebal MM V2', 'Event + Cash Pool V2']

        # Indices de filas "reales" dentro de los arrays de metricas
        idx_metric = [1, 2, 3, np.nan, 4, 5, 6, 7, np.nan, 8, 9, 10, 11]

        for k in range(1, len(nombres) + 1):
            nombre = nombres[k - 1]
            if '---' in nombre:
                print('%-30s %s' % (nombre, '-' * 97))
                continue
            i = int(idx_metric[k - 1])
            valF = valores_fin[i - 1]
            cashF = cash_balance[i - 1]
            equity = valF + cashF

            # Strings seguros (con unidades y %)
            cagr_str = fmt_pct(rendimientos[i - 1])
            aport_str = '%d' % aportes[i - 1]
            vfin_str = '%d EUR' % int(_round(valF))
            eqty_str = '%d EUR' % int(_round(equity))
            cash_str = '%d EUR' % int(_round(cashF))
            deuda_str = '%d EUR' % int(_round(deuda_max_v2[i - 1]))
            mdd_str = fmt_pct(mdd_valores[i - 1])
            vol_str = fmt_pct(vol_valores[i - 1])
            shrp_str = fmt_num(sharpe_ratios[i - 1])
            calm_str = fmt_num(calmar_ratios[i - 1])

            print('%-30s %7s %7s %14s %14s %12s %12s %6s %6s %7s %7s' %
                  (nombre, cagr_str, aport_str, vfin_str, eqty_str, cash_str, deuda_str, mdd_str, vol_str, shrp_str, calm_str))

        print('%s\n=== EJECUCION COMPLETADA ===' % sep)

    except Exception as ME:
        print('❌ Error durante la ejecución: %s' % ME)
        tb = traceback.extract_tb(ME.__traceback__)
        if len(tb) > 0:
            print('Línea del error: %d' % tb[-1].lineno)
        print('\nVerificando archivos...')
        for i in range(1, len(tickers_config) + 1):
            archivo = os.path.join(basePath, tickers_config[i - 1] + '_yahoo.csv')
            if os.path.isfile(archivo):
                print('✅ %s' % (tickers_config[i - 1] + '_yahoo.csv'))
            else:
                print('❌ FALTA: %s' % (tickers_config[i - 1] + '_yahoo.csv'))


# ===================== HELPERS LOCALES =====================
def calc_MDD(equity_series):
    equity_series = np.asarray(equity_series, dtype=float).ravel()
    if equity_series.size < 2:
        return np.nan
    max_run = np.maximum.accumulate(equity_series)
    with np.errstate(divide='ignore', invalid='ignore'):
        dd = (equity_series - max_run) / max_run
    return abs(np.nanmin(dd))


def safe_get(s, f):
    if isinstance(s, dict) and (f in s) and not _isempty(s[f]):
        return s[f]
    else:
        return 0


def safe_get_last(s, f):
    if isinstance(s, dict) and (f in s) and not _isempty(s[f]):
        x = s[f]
        if not _isempty(x):
            return np.asarray(x, dtype=float).ravel()[-1]
        else:
            return 0
    else:
        return 0


def fmt_pct(x):
    if not np.isfinite(x) or x <= 0:
        return ' N/A '
    else:
        return '%.1f%%' % (x * 100)


def fmt_num(x):
    if not np.isfinite(x):
        return '  N/A '
    else:
        return '%.2f' % x


if __name__ == '__main__':
    # La funcion requiere argumentos obligatorios (portfolio_name, tickers_config);
    # no hay argumentos demo en el .m original. Se expone sin ejecutar.
    pass
