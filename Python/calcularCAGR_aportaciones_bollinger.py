import numpy as np
import pandas as pd
from scipy.optimize import brentq

from Medias_Moviles import Medias_Moviles
from calcularCAGR import calcularCAGR


def calcularCAGR_aportaciones_bollinger(data, datamm, aportacion, periodos, dinero_inicial,
                                        enableMA, MA, volumen, vix, vix_umbral, N_bollinger=None):
    entradas_filtradas_ret = np.array([], dtype=int)
    rsi = np.array([], dtype=float)
    entradas_bb = np.array([], dtype=int)

    # === Valor final buy&hold del dinero inicial (lump-sum coherente) ===
    data = np.asarray(data, dtype=float).ravel()
    datamm = np.asarray(datamm, dtype=float).ravel()
    dinero_final_lump = dinero_inicial / data[0] * data[-1]

    # ==============================================================
    # Bollinger CONTRARIAN (autónoma, causal): BB(n=20, k=2)
    # Señal base = precio <= banda inferior (usar_cruce=false por defecto)
    # ==============================================================

    # Parámetros
    bb_n = 20         # ventana por defecto
    bb_k = 2          # nº de desviaciones
    bb_n = N_bollinger
    usar_cruce = False
    if N_bollinger is not None and len(np.atleast_1d(N_bollinger)) > 0 and N_bollinger > 1:
        bb_n = N_bollinger

    N = data.size

    # Medias/desv. móviles CAUSALES (sin look-ahead)
    # movmean(data, [bb_n-1 0]) / movstd(data, [bb_n-1 0]): ventana causal de bb_n puntos.
    # MATLAB movstd normaliza por (k-1) -> ddof=1. Sin 'omitnan' (NaN propaga como el original).
    ma_bb = pd.Series(data).rolling(bb_n, min_periods=1).mean().to_numpy()
    bb_sigma = pd.Series(data).rolling(bb_n, min_periods=1).std(ddof=1).to_numpy()
    bb_inf = ma_bb - bb_k * bb_sigma
    bb_sup = ma_bb + bb_k * bb_sigma

    # Entradas autónomas
    cond = ((np.arange(1, N + 1)) > bb_n) & ~np.isnan(bb_inf) & (data <= bb_inf)

    if usar_cruce:
        cond_prev = np.concatenate(([False], cond[:-1]))
        cond_cruce = cond & ~cond_prev
        entradas_aut = np.flatnonzero(cond_cruce) + 1
    else:
        entradas_aut = np.flatnonzero(cond) + 1

    # Guardamos entradas base (por si aplicamos filtros)
    precios_entrada_base = data[entradas_aut - 1]
    entradas_filtradas_ret = entradas_aut       # por defecto = base
    entradas_bb = entradas_aut                  # las exponemos como salida
    num_aportaciones = entradas_filtradas_ret.size

    # ========== CAGR para la base (Bollinger sin filtros) ==========
    if precios_entrada_base.size == 0:
        # Sin señales => IRR de buy&hold del dinero inicial
        r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos)
    else:
        acciones_compradas = np.sum(aportacion / precios_entrada_base)
        dinero_final_aportaciones = acciones_compradas * data[-1]

        # Valor final total coherente (lump-sum + señales)
        valor_final_total = dinero_final_lump + dinero_final_aportaciones

        # Flujos y tiempos (días naturales aprox)
        entradas_365 = entradas_filtradas_ret * 365 / 252
        T = periodos

        aportaciones = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion)))
        dias_aportaciones = np.concatenate(([0.0], entradas_365))
        tiempos = T - dias_aportaciones / 365

        def funcion_CAGR(rr):
            return np.sum(aportaciones * (1 + rr) ** tiempos) - valor_final_total

        r = brentq(funcion_CAGR, -1, 10)

    if enableMA == 1:
        # Medias alineadas con 'data'
        mm200, mm150, mm100, mm50 = Medias_Moviles(datamm, data)

        # NO reutilizar 'MA'. Elegimos una serie clara:
        if MA == 50:
            mm_sel = mm50
        elif MA == 100:
            mm_sel = mm100
        elif MA == 150:
            mm_sel = mm150
        elif MA == 200:
            mm_sel = mm200
        else:
            raise ValueError("MA debe ser 50/100/150/200")

        precios_entrada = []
        entradas_filtradas_ret = []

        # Asegura vector fila, ordenado y único
        entradas_bb = pd.unique(entradas_bb)

        # Filtro REAL: precio < MM seleccionada (y MM válida)
        for k in range(1, entradas_bb.size + 1):
            idx = int(entradas_bb[k - 1])
            if idx >= 1 and idx <= data.size and not np.isnan(mm_sel[idx - 1]):
                if data[idx - 1] < mm_sel[idx - 1]:
                    precios_entrada.append(data[idx - 1])
                    entradas_filtradas_ret.append(idx)

        precios_entrada = np.asarray(precios_entrada, dtype=float)
        entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)
        num_aportaciones = entradas_filtradas_ret.size

        if precios_entrada.size == 0:
            r = calcularCAGR(dinero_inicial, dinero_inicial / data[0] * data[-1], periodos)
        else:
            # Compras
            acciones_compradas = np.sum(aportacion / precios_entrada)
            dinero_final_total = (dinero_inicial / data[0] * data[-1]) + acciones_compradas * data[-1]

            # Fechas a días naturales
            entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252
            T = periodos

            aportaciones = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion)))
            dias_aportaciones = np.concatenate(([0.0], entradas_filtradas_365))
            tiempos = T - dias_aportaciones / 365

            def funcion_CAGR(rr):
                return np.sum(aportaciones * (1 + rr) ** tiempos) - dinero_final_total

            r = brentq(funcion_CAGR, -1, 10)

    if enableMA == 2:
        # ==============================================================
        # Bollinger + filtro Media Móvil (MA) + filtro VIX mínimo
        # Mantiene SOLO las entradas donde:
        #   - data(idx) < MM_sel(idx)
        #   - vix(idx)  >= vix_umbral
        # ==============================================================

        # --- 1) Selección de MM ---
        mm200, mm150, mm100, mm50 = Medias_Moviles(datamm, data)
        if MA == 50:
            mm_sel = mm50
        elif MA == 100:
            mm_sel = mm100
        elif MA == 150:
            mm_sel = mm150
        elif MA == 200:
            mm_sel = mm200
        else:
            raise ValueError("MA debe ser 50/100/150/200")

        # --- 2) Preparar VIX y alinear con 'data' si hiciera falta ---
        if vix is None or len(vix) == 0:
            raise ValueError("enableMA==2 requiere vector VIX y vix_umbral.")
        vix = np.asarray(vix, dtype=float).ravel()
        if vix.size != data.size:
            M = min(vix.size, data.size)
            print(f'Warning: VIX y data con longitudes distintas. Se alinean a los últimos {M} elementos.')
            data = data[data.size - M:]
            mm_sel = mm_sel[mm_sel.size - M:]
            vix = vix[vix.size - M:]
            # Reajusta entradas_bb a la nueva longitud
            mask_in = entradas_bb > data.size      # fuera de rango tras recorte
            entradas_bb = entradas_bb[~mask_in]

        # --- 3) Filtrado doble: MM + VIX ---
        entradas_bb = pd.unique(entradas_bb)
        precios_entrada = []
        entradas_filtradas_ret = []

        for k in range(1, entradas_bb.size + 1):
            idx = int(entradas_bb[k - 1])
            if idx >= 1 and idx <= data.size and not np.isnan(mm_sel[idx - 1]) and not np.isnan(vix[idx - 1]):
                cond_mm = (data[idx - 1] < mm_sel[idx - 1])
                cond_vix = (vix[idx - 1] >= vix_umbral)
                if cond_mm and cond_vix:
                    precios_entrada.append(data[idx - 1])
                    entradas_filtradas_ret.append(idx)

        precios_entrada = np.asarray(precios_entrada, dtype=float)
        entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)

        # --- 4) CAGR con las entradas filtradas ---
        num_aportaciones = entradas_filtradas_ret.size
        if precios_entrada.size == 0:
            r = calcularCAGR(dinero_inicial, dinero_inicial / data[0] * data[-1], periodos)
        else:
            acciones_compradas = np.sum(aportacion / precios_entrada)
            dinero_final_total = (dinero_inicial / data[0] * data[-1]) + acciones_compradas * data[-1]

            entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252
            T = periodos

            aportaciones = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion)))
            dias_aportaciones = np.concatenate(([0.0], entradas_filtradas_365))
            tiempos = T - dias_aportaciones / 365

            def funcion_CAGR(rr):
                return np.sum(aportaciones * (1 + rr) ** tiempos) - dinero_final_total

            r = brentq(funcion_CAGR, -1, 10)

    return r, num_aportaciones, entradas_bb, entradas_filtradas_ret, rsi, bb_inf, bb_sup, ma_bb
