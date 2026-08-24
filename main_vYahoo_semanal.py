import os
from datetime import datetime

import numpy as np
import pandas as pd

from yahoo_utils import ensure_yahoo_csv, read_yahoo_csv
from Shewhart import Shewhart
from calcularCAGR import calcularCAGR
from calcularCAGR_aportaciones import calcularCAGR_aportaciones
from calcularCAGR_aportaciones_DCA import calcularCAGR_aportaciones_DCA
from calcularCAGR_aportaciones_bollinger import calcularCAGR_aportaciones_bollinger
from buscar_maximos import buscar_maximos
from Medias_Moviles import Medias_Moviles
from notificacion_semanal import notificacion_semanal
from email_utils import enviar_reporte

_MESES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']


def _datestr_ddmmmyyyy(dt):
    # datestr(now, 'dd-mmm-yyyy') -> '04-Aug-2026'
    return f"{dt.day:02d}-{_MESES[dt.month - 1]}-{dt.year}"


def main_vYahoo_semanal():
    # ------------------- Parámetros --------------------------------------
    periodos = 5                      # años
    dias_bolsa = 252 * periodos       # ~252 días/año
    dias_media_movil = dias_bolsa + 200  # para MM200
    dinero_inicial = 1000
    aportacion = 1500                 # en señal < -2σ
    aportacion_DCA = 1500             # mensual (~21 días)
    MA = 200                          # 25/50/100/150/200
    MA_reb = 100                      # para compras despues de rebalanceos
    bloqueos = 0                      # para variantes de cruz dorada/muerte
    media_movil_lenta = 200           # 100/150/200 (la rápida es 50)
    vix_umbral = 20                   # 24 acciones, 28 ETFs
    N_bollinger = 30                  # periodos de bollinger
    max_cash_por_dia = 3000           # maximo a invertir cada dia para las event driven. Solo aplica en las V1!
    z_engine = 'shewhart_tippett'     # 'shewhart_tippett' | 'bollinger'
    msg_final = ""
    header_msg = ""
    # ---------------------------------------------------------------------

    # ========= Descarga UNA VEZ: Yahoo =========
    # Forzar la ruta de ejecución correcta en GitHub o en Local
    if os.environ.get('GITHUB_WORKSPACE'):
        basePath = os.environ['GITHUB_WORKSPACE']  # La ruta absoluta segura en los servidores de GitHub
    else:
        basePath = os.getcwd()  # Tu carpeta local en tu PC de escritorio

    # Tabla de tickers (clave lógica, símbolo Yahoo, nombre de fichero)
    tickers = [
        ('SPY',   'SPY',     'SPY_yahoo.csv'),
        # ('IWM',   'IWM',     'IWM_yahoo.csv'),      # RU = IWM
        # ('GLD',   'GLD',     'GLD_yahoo.csv'),
        ('GC=F',   'GC=F',     'Oro_yahoo.csv'),
        # ('TLT',   'TLT',     'TLT_yahoo.csv'),
        # ('SHY',   'SHY',     'SHY_yahoo.csv'),
        ('VIX',   '^VIX',    'VIX_yahoo.csv'),
        # ('IEF',   'IEF',     'IEF_yahoo.csv'),
        # ('DBC',   'DBC',     'DBC_yahoo.csv'),
        ('BTC-USD',   'BTC-USD',     'BTC-USD_yahoo.csv'),
        # Extras
        ('MSFT',  'MSFT',    'MSFT_yahoo.csv'),
        ('GOOG', 'GOOG',   'GOOG_yahoo.csv'),
        ('META',  'META',    'META_yahoo.csv'),
        ('AMZN',  'AMZN',    'AMZN_yahoo.csv'),
        ('QQQ',  'QQQ',    'QQQ_yahoo.csv'),
        ('AAPL',  'AAPL',    'AAPL_yahoo.csv'),
        ('NVDA',  'NVDA',    'NVDA_yahoo.csv'),
        ('ASTS', 'ASTS', 'ASTS_yahoo.csv'),
        ('MA', 'MA', 'MA_yahoo.csv'),
        # ('RMS.PA' , 'RMS.PA', 'Hermes_yahoo.csv'),
        # ('VST' , 'VST', 'Vistra_yahoo.csv'),
        ('V', 'V', 'Visa_yahoo.csv'),
        ('UBER', 'UBER', 'UBER_yahoo.csv'),
        ('MCD', 'MCD', 'Mcdonalds_yahoo.csv'),
        ('AENA.MC', 'AENA.MC', 'Aena_yahoo.csv'),

        # Biotecnologicas especulativas
        # ('VKTX' , 'VKTX', 'VKTX_yahoo.csv'),
        # ('KRMD' , 'KRMD', 'KRMD_yahoo.csv'),
        ('SLS', 'SLS', 'SLS_yahoo.csv'),
        # ('VANI' , 'VANI', 'VANI_yahoo.csv'),
        # ('RANI' , 'RANI', 'RANI_yahoo.csv'),
        # ('DFTX' , 'DFTX', 'DFTX_yahoo.csv'),
    ]

    # Rango temporal
    startDate = '2000-01-01'
    endDate = ''  # hoy

    # Descarga (o reutiliza) y guarda rutas
    paths = {}
    for key, sym, fname in tickers:
        fp = os.path.join(basePath, fname)
        try:
            ensure_yahoo_csv(sym, fp, startDate, endDate)
        except Exception as ME:
            raise RuntimeError(f'Fallo preparando {key} ({sym}): {ME}')
        paths[key] = fp

    # === Elegir activo para evaluar ===
    assets = ["MSFT", "GOOG", "META", "AMZN", "MA", "V", "ASTS", "SLS", "UBER", "MCD", "AENA.MC", "GC=F", "SPY"]

    n_iteraciones = len(assets)

    for i in range(1, n_iteraciones + 1):
        asset = assets[i - 1]
        print(asset)
        if asset.upper() not in paths:
            raise RuntimeError(f'Activo no soportado: {asset}')
        chosen_fp = paths[asset.upper()]
        fp_VIX = paths['VIX']

        # ========= Lectura + Alineación por fecha (LEFT JOIN del activo con VIX) =========
        px_asset, vol_asset, dt_asset = read_yahoo_csv(chosen_fp)  # activo
        vix_full, _, dt_vix = read_yahoo_csv(fp_VIX)               # VIX

        # Normalización defensiva
        px_asset = np.asarray(px_asset, dtype=float).ravel()
        dt_asset = pd.DatetimeIndex(dt_asset)
        if vol_asset.size > 0:
            vol_asset = np.asarray(vol_asset, dtype=float).ravel()

        TT_asset = pd.DataFrame({'Close': px_asset, 'Vol': vol_asset}, index=dt_asset)
        TT_vix = pd.DataFrame({'VIX': np.asarray(vix_full, dtype=float).ravel()}, index=pd.DatetimeIndex(dt_vix))

        # Left join manual: union + filtro por fechas del activo
        TT_all = TT_asset.join(TT_vix, how='outer')   # union + fillwithmissing
        mask = TT_all.index.isin(TT_asset.index)
        TT_left = TT_all[mask]                         # mismas fechas que el ACTIVO (VIX puede quedar NaN)

        # Guardas básicas
        L = len(TT_left)
        assert L > 0, 'No hay solape temporal entre activo y VIX (o datos vacíos).'

        useD = min(dias_bolsa, L)
        useDmm = min(dias_media_movil, L)

        TTp = TT_left.iloc[L - useD:]      # ventana para señales
        TTmm = TT_left.iloc[L - useDmm:]   # ventana extendida para MM

        data = np.asarray(TTp['Close'], dtype=float).ravel()    # precios
        datamm = np.asarray(TTmm['Close'], dtype=float).ravel()  # para MM
        volumen = np.asarray(TTp['Vol'], dtype=float).ravel()    # puede ser []
        vix = np.asarray(TTp['VIX'], dtype=float).ravel()        # puede ser NaN
        ultima_fecha = TTp.index[-1]

        # Más guardas (evita divisiones por cero/NaN en primeros pasos)
        assert data.size >= 50, 'Muy pocos datos del activo tras recorte.'
        data = pd.Series(data).ffill().to_numpy()     # si hubiera NaN sueltos
        datamm = pd.Series(datamm).ffill().to_numpy()

        # ========= Tu flujo original (mismas llamadas/firmas) =========

        # Dinero si solo buy&hold
        if data[0] == 0 or np.isnan(data[0]):
            raise RuntimeError('Precio inicial inválido (0/NaN). Revisa el CSV del activo.')
        dinero_final_lump = dinero_inicial / data[0] * data[-1]

        # Shewhart (tasa %, media global y sigma Tippett)
        entradas_3s = np.array([], dtype=int)
        entradas_2s = np.array([], dtype=int)
        try:
            entradas_3s, entradas_2s, tasa, media_sh, sigma_t = Shewhart(data)
        except Exception as ME:
            print(f'Warning: Plot Shewhart omitido ({ME}). Sigo con el cálculo.')
            entradas_3s, entradas_2s, _, _, _ = Shewhart(data)

        # CAGR sin aportaciones
        r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos)

        # ===== Estrategias base =====
        enableMA = 0
        r_2s, num_aportaciones_2s, entradas_filtradas, _ = calcularCAGR_aportaciones(
            entradas_2s, data, datamm, aportacion, periodos, dinero_inicial,
            enableMA, MA, bloqueos, media_movil_lenta, volumen, vix)

        r_DCA, num_aportaciones_DCA = calcularCAGR_aportaciones_DCA(data, 21, aportacion_DCA, dinero_inicial)

        # Shewhart -2σ + MM(100/200)
        enableMA = 1
        r_2smm, num_aportaciones_2smm, entradas_2smm, _ = calcularCAGR_aportaciones(
            entradas_2s, data, datamm, aportacion, periodos, dinero_inicial,
            enableMA, MA, bloqueos, media_movil_lenta, volumen, vix)

        r_2sgc, num_aportaciones_2sgc, entradas2sgc, _ = calcularCAGR_aportaciones(
            entradas_2smm, data, datamm, aportacion, periodos, dinero_inicial,
            enableMA, MA, bloqueos, media_movil_lenta, volumen, vix)

        # Tendencia alcista (MM50 > MM_lenta)
        enableMA = 4
        r_2alcista, num_aportaciones_2alcista, entradas2alcista, _ = calcularCAGR_aportaciones(
            entradas_2smm, data, datamm, aportacion, periodos, dinero_inicial,
            enableMA, MA, bloqueos, media_movil_lenta, volumen, vix)

        # Volumen alto
        enableMA = 5
        r_2vol, num_aportaciones_2vol, entradas_2vol, _ = calcularCAGR_aportaciones(
            entradas_2smm, data, datamm, aportacion, periodos, dinero_inicial,
            enableMA, MA, bloqueos, media_movil_lenta, volumen, vix)

        entradas_filtradas_max, num_maximos, rsi2, maximos = buscar_maximos(
            data, datamm, aportacion, periodos, dinero_inicial, MA, volumen, vix)

        # MM + VIX
        enableMA = 7
        r_2mmvix, num_aportaciones_2mmvix, entradas_2mmvix, rsi3 = calcularCAGR_aportaciones(
            entradas_2smm, data, datamm, aportacion, periodos, dinero_inicial,
            enableMA, MA, bloqueos, media_movil_lenta, volumen, vix, vix_umbral)

        # Bollinger
        enableMA = 0
        (r_bb, num_aportaciones_bb, entradas_bb, entradas_fitradas_bb, rsi4,
         bb_inf, bb_sup, bb_sigma) = calcularCAGR_aportaciones_bollinger(
            data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, volumen, vix, vix_umbral, N_bollinger)

        enableMA = 1  # MA = 200
        (r_bbmm, num_aportaciones_bbmm, entradas_bb2, entradas_fitradas_bbmm, rsi5,
         bb_inf, bb_sup, bb_sigma) = calcularCAGR_aportaciones_bollinger(
            data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, volumen, vix, vix_umbral, N_bollinger)

        enableMA = 2  # MA = 200
        (r_bbmmvix, num_aportaciones_bbmmvix, entradas_bb3, entradas_fitradas_bbmmvix, rsi6,
         bb_inf, bb_sup, bb_sigma) = calcularCAGR_aportaciones_bollinger(
            data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, volumen, vix, vix_umbral, N_bollinger)

        print(f"========== CAGR PARA DIFERENTES ESTRATEGIAS ({periodos} años) - aportaciones constantes ==========\n")
        print(f"{'Estrategia 1: Sin aportaciones:':<72} {r * 100:8.2f}%")
        print(f"{'Estrategia 2: DCA mensual:':<72} {r_DCA * 100:8.2f}% ({num_aportaciones_DCA:3d} entradas)")
        print(f"{'Estrategia 3a: Shewhart, aportaciones a -2σ:':<72} {r_2s * 100:8.2f}% ({num_aportaciones_2s:3d} entradas)")
        print(f"{f'Estrategia 3b: Shewhart, -2σ y MM ({MA}):':<72} {r_2smm * 100:8.2f}% ({num_aportaciones_2smm:3d} entradas)")
        print(f"{f'Estrategia 3c: Shewhart, -2σ, MM ({MA}) y VIX > {vix_umbral}:':<72} {r_2mmvix * 100:8.2f}% ({num_aportaciones_2mmvix:3d} entradas)")
        print(f"{f'Estrategia 3d: Shewhart, -2σ, MM ({MA}) y tendencia alcista:':<72} {r_2alcista * 100:8.2f}% ({num_aportaciones_2alcista:3d} entradas)")
        print(f"{f'Estrategia 3e: Shewhart, -2σ, MM ({MA}) y volumen alto:':<72} {r_2vol * 100:8.2f}% ({num_aportaciones_2vol:3d} entradas)")
        print(f"{f'Estrategia 4a: Bollinger contrarian (N={N_bollinger}):':<72} {r_bb * 100:8.2f}% ({num_aportaciones_bb:3d} entradas)")
        print(f"{f'Estrategia 4b: Bollinger contrarian, MM ({MA}):':<72} {r_bbmm * 100:8.2f}% ({num_aportaciones_bbmm:3d} entradas)")
        print(f"{f'Estrategia 4c: Bollinger contrarian, MM ({MA}) y VIX > {vix_umbral}:':<72} {r_bbmmvix * 100:8.2f}% ({num_aportaciones_bbmmvix:3d} entradas)")
        print(f"\nÚltima fecha: {ultima_fecha.strftime('%Y-%m-%d')}")
        print("\n====================================================================")

        # ===== Gráficas =====
        try:
            mm200, mm150, mm100, mm50 = Medias_Moviles(datamm, data)
        except Exception as ME:
            print(f'Warning: Se omitieron algunas gráficas ({ME}).')

        # ===== Ponderaciones por nº de entradas =====
        enableMA = 1  # MA = 200
        r_2smm, num_aportaciones_2smm, entradas_2smm, _ = calcularCAGR_aportaciones(
            entradas_2s, data, datamm, num_aportaciones_2s / max(1, num_aportaciones_2smm) * aportacion,
            periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen, vix)

        enableMA = 4
        r_2alcista, num_aportaciones_2alcista, entradas2alcista, _ = calcularCAGR_aportaciones(
            entradas_2smm, data, datamm, num_aportaciones_2s / max(1, num_aportaciones_2alcista) * aportacion,
            periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen, vix)

        enableMA = 5
        r_2vol, num_aportaciones_2vol, entradas_2vol, _ = calcularCAGR_aportaciones(
            entradas_2smm, data, datamm, num_aportaciones_2s / max(1, num_aportaciones_2vol) * aportacion,
            periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen, vix)

        entradas_filtradas_max, num_maximos, rsi, maximos = buscar_maximos(
            data, datamm, aportacion, periodos, dinero_inicial, MA, volumen, vix)

        enableMA = 7
        r_2mmvix, num_aportaciones_2mmvix, entradas_2mmvix, rsi = calcularCAGR_aportaciones(
            entradas_2smm, data, datamm, num_aportaciones_2s / max(1, num_aportaciones_2mmvix) * aportacion,
            periodos, dinero_inicial, enableMA, MA, bloqueos, media_movil_lenta, volumen, vix, vix_umbral)

        enableMA = 0
        (r_bb, num_aportaciones_bb, entradas_bb, entradas_fitradas_bb, rsi,
         bb_inf, bb_sup, bb_sigma) = calcularCAGR_aportaciones_bollinger(
            data, datamm, aportacion, periodos, dinero_inicial, enableMA, MA, volumen, vix, vix_umbral, N_bollinger)

        enableMA = 1  # MA = 200
        (r_bbmm, num_aportaciones_bbmm, entradas_bb, entradas_fitradas_bbmm, rsi,
         bb_inf, bb_sup, bb_sigma) = calcularCAGR_aportaciones_bollinger(
            data, datamm, num_aportaciones_bb / max(1, num_aportaciones_bbmm) * aportacion, periodos, dinero_inicial,
            enableMA, MA, volumen, vix, vix_umbral, N_bollinger)

        enableMA = 2  # VIX > vix_umbral
        (r_bbmmvix, num_aportaciones_bbmmvix, entradas_bb, entradas_fitradas_bbmmvix, rsi,
         bb_inf, bb_sup, bb_sigma) = calcularCAGR_aportaciones_bollinger(
            data, datamm, num_aportaciones_bb / max(1, num_aportaciones_bbmmvix) * aportacion, periodos, dinero_inicial,
            enableMA, MA, volumen, vix, vix_umbral, N_bollinger)

        print(f"========== CAGR PARA DIFERENTES ESTRATEGIAS ({periodos} años) - aportaciones ponderadas ==========\n")
        print(f"{'Estrategia 1: Sin aportaciones:':<72} {r * 100:8.2f}%")
        print(f"{'Estrategia 2: DCA mensual:':<72} {r_DCA * 100:8.2f}% ({num_aportaciones_DCA:3d} entradas)")
        print(f"{'Estrategia 3a: Shewhart, aportaciones a -2σ:':<72} {r_2s * 100:8.2f}% ({num_aportaciones_2s:3d} entradas)")
        print(f"{f'Estrategia 3b: Shewhart, -2σ y MM ({MA}):':<72} {r_2smm * 100:8.2f}% ({num_aportaciones_2smm:3d} entradas)")
        print(f"{f'Estrategia 3c: Shewhart, -2σ, MM ({MA}) y VIX > {vix_umbral}:':<72} {r_2mmvix * 100:8.2f}% ({num_aportaciones_2mmvix:3d} entradas)")
        print(f"{f'Estrategia 3d: Shewhart, -2σ, MM ({MA}) y tendencia alcista:':<72} {r_2alcista * 100:8.2f}% ({num_aportaciones_2alcista:3d} entradas)")
        print(f"{f'Estrategia 3e: Shewhart, -2σ, MM ({MA}) y volumen alto:':<72} {r_2vol * 100:8.2f}% ({num_aportaciones_2vol:3d} entradas)")
        print(f"{f'Estrategia 4a: Bollinger contrarian (N={N_bollinger}):':<72} {r_bb * 100:8.2f}% ({num_aportaciones_bb:3d} entradas)")
        print(f"{f'Estrategia 4b: Bollinger contrarian, MM ({MA}):':<72} {r_bbmm * 100:8.2f}% ({num_aportaciones_bbmm:3d} entradas)")
        print(f"{f'Estrategia 4c: Bollinger contrarian, MM ({MA}) y VIX > {vix_umbral}:':<72} {r_bbmmvix * 100:8.2f}% ({num_aportaciones_bbmmvix:3d} entradas)")
        print(f"\nÚltima fecha: {ultima_fecha.strftime('%Y-%m-%d')}")
        print("\n====================================================================")

        msg = notificacion_semanal(asset, data, entradas_2smm, entradas_2mmvix, mm200[-1])
        print(msg)

        msg_final = msg_final + msg + "\n"

    print("\n")

    # =========================================================================
    # CREACIÓN DEL HEADER Y CONCATENACIÓN FINAL
    # =========================================================================

    # 1. Creamos las variables de la cabecera
    fecha_cabecera = _datestr_ddmmmyyyy(datetime.now())
    vix_actual = vix[-1]  # Ahora que el bucle terminó, 'vix' ya contiene datos

    # 2. Construimos el header
    header_msg = (
        f'==============================\n'
        f'📅 DATE: {fecha_cabecera}\n'
        f'📈 VIX INDEX: {vix_actual:.2f}\n'
        f'==============================\n\n'
    )

    # 3. Concatenamos el header AL PRINCIPIO del msg_final acumulado
    msg_final = header_msg + msg_final

    # 4. Mostramos el resultado en la consola de GitHub
    print(msg_final)

    # =========================================================================
    # ENVÍO DE CORREO (BUCLE INDIVIDUAL - A PRUEBA DE SECRETS Y RFC)
    # =========================================================================
    asunto = f'📊 Reporte Semanal de Trading - {datetime.now().strftime("%Y-%m-%d")}'
    enviar_reporte(asunto, msg_final)

    # ------------------------------------------------------------------------------------------------------------------------
    # PORTFOLIO ANALYSIS: (comentado en el original MATLAB; idéntico al de main_vYahoo.py)
    # ------------------------------------------------------------------------------------------------------------------------


if __name__ == '__main__':
    main_vYahoo_semanal()
