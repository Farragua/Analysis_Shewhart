import numpy as np
import pandas as pd
from scipy.optimize import brentq

from Medias_Moviles import Medias_Moviles
from calcularCAGR import calcularCAGR


def calcularCAGR_aportaciones(entradas, data, datamm, aportacion, periodos, dinero_inicial,
                              enableMA, MA, bloqueos, media_movil_lenta, volumen, vix,
                              vix_umbral=None):
    entradas_filtradas_ret = np.array([], dtype=int)
    rsi = np.array([], dtype=float)

    # Calcular CAGR con aportaciones no periodicas puntuales
    # mm es una variable booleana, 1 activa el calculo con medias moviles. 0 no
    # usa medias moviles, solo los puntos de entradas de Shewhart.

    data = np.asarray(data, dtype=float).ravel()
    datamm = np.asarray(datamm, dtype=float).ravel()

    dinero_final_lump = dinero_inicial / data[0] * data[-1]  # pasado el periodo estudiado sin hacer ninguna aportacion.
    dinero_final_aportaciones = 0

    if enableMA == 0:
        entradas = np.asarray(entradas, dtype=float).ravel()
        num_aportaciones = len(entradas)

        # Calcular los precios de entrada a -X sigma:
        precios_entrada = np.zeros(len(entradas))
        for i in range(1, len(entradas) + 1):
            precios_entrada[i - 1] = data[int(entradas[i - 1]) - 1]

        # comprar cuando el mercado caiga por debajo de -X s:
        dinero_final_aportaciones = 0
        acciones_compradas = 0
        for i in range(1, len(precios_entrada) + 1):
            acciones_compradas = acciones_compradas + (aportacion / precios_entrada[i - 1])

        dinero_final_total = dinero_final_lump + acciones_compradas * data[-1]

        # Ahora hay que calcular la CAGR incluyendo las aportaciones con sus fechas
        # de entrada.

        entradas_365 = entradas * 365 / 252  # para pasar a dias naturales.

        T = periodos  # 365 días naturales

        # Inicializar arrays de aportaciones y fechas
        aportaciones = np.concatenate(([dinero_inicial], np.full(len(entradas), aportacion)))
        dias_aportaciones = np.concatenate(([0.0], entradas_365))  # Día 0 para el dinero inicial
        # Convertir a años (T - t_i)
        tiempos = T - dias_aportaciones / 365

        # Función para encontrar r (CAGR)
        def funcion_CAGR(r):
            return np.sum(aportaciones * (1 + r) ** tiempos) - dinero_final_total

        # Usar fzero para encontrar la tasa de crecimiento r
        r = brentq(funcion_CAGR, -1, 6)  # busca la solucion en un intervalo desde -100% a +200%

    elif enableMA == 1:
        mm200, mm150, mm100, mm50 = Medias_Moviles(datamm, data)

        if MA == 50:
            MA = mm50
        elif MA == 100:
            MA = mm100
        elif MA == 150:
            MA = mm150
        elif MA == 200:
            MA = mm200
        else:
            print("Error: Select a right value for the MA (25, 50, 100, 150) ")

        # Calcular los precios de entrada a -X sigma:
        precios_entrada = []
        entradas_filtradas_ret = []

        for i in range(1, len(entradas) + 1):
            idx = int(entradas[i - 1])
            if data[idx - 1] < MA[idx - 1]:
                precios_entrada.append(data[idx - 1])
                entradas_filtradas_ret.append(idx)

        precios_entrada = np.asarray(precios_entrada, dtype=float)
        entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)
        num_aportaciones = len(entradas_filtradas_ret)

        if len(precios_entrada) == 0:
            r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos)  # 1 periodo Controlar este calculo
        else:
            # comprar cuando el mercado caiga por debajo de -X s:
            dinero_final_aportaciones = 0
            acciones_compradas = 0
            for i in range(1, len(precios_entrada) + 1):
                acciones_compradas = acciones_compradas + (aportacion / precios_entrada[i - 1])

            dinero_final_total = dinero_final_lump + acciones_compradas * data[-1]

            # Ahora hay que calcular la CAGR incluyendo las aportaciones con sus fechas
            # de entrada.

            entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252  # para pasar a dias naturales.

            T = periodos  # 365 días naturales

            # Inicializar arrays de aportaciones y fechas
            aportaciones = np.concatenate(([dinero_inicial], np.full(len(entradas_filtradas_ret), aportacion)))
            dias_aportaciones = np.concatenate(([0.0], entradas_filtradas_365))  # Día 0 para el dinero inicial

            # Convertir a años (T - t_i)
            tiempos = T - dias_aportaciones / 365

            # Función para encontrar r (CAGR)
            def funcion_CAGR(r):
                return np.sum(aportaciones * (1 + r) ** tiempos) - dinero_final_total

            # Usar fzero para encontrar la tasa de crecimiento r
            r = brentq(funcion_CAGR, -1, 10)  # busca la solucion en un intervalo desde -100% a +200%

    elif enableMA == 2:
        # Cálculo utilizando Shewhart + MM y evitando compras si hubo una cruz de la muerte
        # en los últimos 30 días bursátiles

        mm200, mm150, mm100, mm50 = Medias_Moviles(datamm, data)

        if media_movil_lenta == 150:
            media_movil_lenta = mm150
        elif media_movil_lenta == 100:
            media_movil_lenta = mm100
        elif media_movil_lenta == 200:
            media_movil_lenta = mm200
        else:
            print("Error: media movil lenta debe ser (100, 150, 200) ")

        # Detectar cruces de la muerte: MM50 cruza por debajo de MM200
        cruces_muerte = []
        for i in range(2, len(data) + 1):
            if not np.isnan(mm50[i - 1]) and not np.isnan(media_movil_lenta[i - 1]):
                if mm50[i - 1] < media_movil_lenta[i - 1] and mm50[i - 2] >= media_movil_lenta[i - 2]:
                    cruces_muerte.append(i)

        # Crear vector de fechas bloqueadas (30 días tras cada cruce)
        dias_bloqueo = bloqueos
        fechas_bloqueadas = np.zeros(len(data), dtype=bool)
        for i in range(1, len(cruces_muerte) + 1):
            ini = cruces_muerte[i - 1]
            fin = min(ini + dias_bloqueo, len(data))
            fechas_bloqueadas[ini - 1:fin] = True

        # === FILTRADO CORRECTO: NO volver a aplicar MM200 aquí ===
        precios_entrada = []
        entradas_filtradas_ret = []

        for i in range(1, len(entradas) + 1):  # ← estas ya deberían estar filtradas por -2σ y MM200
            idx = int(entradas[i - 1])

            if idx >= 1 and idx <= len(data):
                if not fechas_bloqueadas[idx - 1]:
                    precios_entrada.append(data[idx - 1])
                    entradas_filtradas_ret.append(idx)
                else:
                    print(f" Entrada en {idx} bloqueada por cruce reciente")

        precios_entrada = np.asarray(precios_entrada, dtype=float)
        entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)

        # === Cálculo de CAGR ===
        num_aportaciones = len(entradas_filtradas_ret)

        # NOTA (réplica 1:1): en el original MATLAB el cálculo de r de esta rama está
        # comentado, por lo que 'r' nunca se asigna y MATLAB lanzaría
        # "Output argument 'r' not assigned". Aquí ocurre lo mismo (UnboundLocalError).

    elif enableMA == 3:
        # Cálculo utilizando Shewhart + MM y SOLO comprando tras cruz dorada (MM50 > MM lenta)

        mm200, mm150, mm100, mm50 = Medias_Moviles(datamm, data)

        # Selección de MM lenta
        if media_movil_lenta == 150:
            mm_lenta = mm150
        elif media_movil_lenta == 100:
            mm_lenta = mm100
        elif media_movil_lenta == 200:
            mm_lenta = mm200
        else:
            raise ValueError("Error: media_movil_lenta debe ser 100, 150 o 200")

        # === Detectar cruz dorada: MM50 cruza por encima de MM lenta ===
        cruces_dorada = []
        for i in range(2, len(data) + 1):
            if not np.isnan(mm50[i - 1]) and not np.isnan(mm_lenta[i - 1]):
                if mm50[i - 1] > mm_lenta[i - 1] and mm50[i - 2] <= mm_lenta[i - 2]:
                    cruces_dorada.append(i)

        # === Mantener bandera de "permitido comprar" tras cruz dorada ===
        permitido_comprar = np.zeros(len(data), dtype=bool)
        for i in range(1, len(cruces_dorada) + 1):
            permitido_comprar[cruces_dorada[i - 1] - 1:] = True

        # === Filtrar entradas SOLO si están tras cruz dorada ===
        precios_entrada = []
        entradas_filtradas_ret = []

        for i in range(1, len(entradas) + 1):
            idx = int(entradas[i - 1])
            if idx >= 1 and idx <= len(data):
                if permitido_comprar[idx - 1]:
                    precios_entrada.append(data[idx - 1])
                    entradas_filtradas_ret.append(idx)

        precios_entrada = np.asarray(precios_entrada, dtype=float)
        entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)
        num_aportaciones = len(entradas_filtradas_ret)

        if len(precios_entrada) == 0:
            r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos)
        else:
            acciones_compradas = np.sum(aportacion / precios_entrada)
            dinero_final_total = dinero_final_lump + acciones_compradas * data[-1]

            entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252
            T = periodos

            aportaciones = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion)))
            dias_aportaciones = np.concatenate(([0.0], entradas_filtradas_365))
            tiempos = T - dias_aportaciones / 365

            def funcion_CAGR(r):
                return np.sum(aportaciones * (1 + r) ** tiempos) - dinero_final_total

            r = brentq(funcion_CAGR, -1, 10)

    elif enableMA == 4:
        # Cálculo utilizando Shewhart + MM y SOLO comprando en días con MM50 > MM_lenta (tendencia alcista)

        mm200, mm150, mm100, mm50 = Medias_Moviles(datamm, data)

        # Selección de MM lenta
        if media_movil_lenta == 150:
            mm_lenta = mm150
        elif media_movil_lenta == 100:
            mm_lenta = mm100
        elif media_movil_lenta == 200:
            mm_lenta = mm200
        else:
            raise ValueError("Error: media_movil_lenta debe ser 100, 150 o 200")

        # === Filtrar entradas si y solo si MM50 > MM_lenta ese día ===
        precios_entrada = []
        entradas_filtradas_ret = []

        for i in range(1, len(entradas) + 1):
            idx = int(entradas[i - 1])
            if idx >= 1 and idx <= len(data):
                if mm50[idx - 1] > mm_lenta[idx - 1]:
                    precios_entrada.append(data[idx - 1])
                    entradas_filtradas_ret.append(idx)

        precios_entrada = np.asarray(precios_entrada, dtype=float)
        entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)
        num_aportaciones = len(entradas_filtradas_ret)

        if len(precios_entrada) == 0:
            r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos)
        else:
            acciones_compradas = np.sum(aportacion / precios_entrada)
            dinero_final_total = dinero_final_lump + acciones_compradas * data[-1]

            entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252
            T = periodos

            aportaciones = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion)))
            dias_aportaciones = np.concatenate(([0.0], entradas_filtradas_365))
            tiempos = T - dias_aportaciones / 365

            def funcion_CAGR(r):
                return np.sum(aportaciones * (1 + r) ** tiempos) - dinero_final_total

            r = brentq(funcion_CAGR, -1, 10)

    elif enableMA == 5:
        # Estrategia con volumen: SOLO comprar si volumen del día > media(35 días)

        volumen = np.asarray(volumen, dtype=float).ravel()
        # movmean(volumen, 35) con ventana escalar en MATLAB = ventana centrada [17 17]
        # (con look-ahead, réplica 1:1). np.mean propaga NaN como el movmean por defecto.
        media_volumen = pd.Series(volumen).rolling(35, center=True, min_periods=1).apply(np.mean, raw=True).to_numpy()

        precios_entrada = []
        entradas_filtradas_ret = []

        for i in range(1, len(entradas) + 1):
            idx = int(entradas[i - 1])
            if volumen[idx - 1] > media_volumen[idx - 1]:
                precios_entrada.append(data[idx - 1])
                entradas_filtradas_ret.append(idx)

        precios_entrada = np.asarray(precios_entrada, dtype=float)
        entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)
        num_aportaciones = len(entradas_filtradas_ret)

        if len(precios_entrada) == 0:
            r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos)
        else:
            acciones_compradas = np.sum(aportacion / precios_entrada)
            dinero_final_total = dinero_final_lump + acciones_compradas * data[-1]

            entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252
            T = periodos

            aportaciones = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion)))
            dias_aportaciones = np.concatenate(([0.0], entradas_filtradas_365))
            tiempos = T - dias_aportaciones / 365

            def funcion_CAGR(r):
                return np.sum(aportaciones * (1 + r) ** tiempos) - dinero_final_total

            r = brentq(funcion_CAGR, -1, 10)

    elif enableMA == 6:
        # Estrategia: filtrar entradas si 25<RSI(14)<60

        rsi_len = 14
        rsi = rsi_wilder(data, rsi_len)

        precios_entrada = []
        entradas_filtradas_ret = []

        for i in range(1, len(entradas) + 1):
            idx = int(entradas[i - 1])
            if idx > rsi_len and idx <= len(data):
                if rsi[idx - 1] <= 60 and rsi[idx - 1] >= 25:
                    precios_entrada.append(data[idx - 1])
                    entradas_filtradas_ret.append(idx)

        precios_entrada = np.asarray(precios_entrada, dtype=float)
        entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)
        num_aportaciones = len(entradas_filtradas_ret)

        if len(precios_entrada) == 0:
            r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos)
        else:
            acciones_compradas = np.sum(aportacion / precios_entrada)
            dinero_final_total = dinero_final_lump + acciones_compradas * data[-1]

            entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252
            T = periodos

            aportaciones = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion)))
            dias_aportaciones = np.concatenate(([0.0], entradas_filtradas_365))
            tiempos = T - dias_aportaciones / 365

            def funcion_CAGR(r):
                return np.sum(aportaciones * (1 + r) ** tiempos) - dinero_final_total

            r = brentq(funcion_CAGR, -1, 10)

    elif enableMA == 7:
        # Shewhart -2σ + filtro VIX (descarta si VIX < vix_umbral)
        if vix is None or len(vix) == 0:
            raise ValueError('enableMA==7 requiere pasar el vector VIX como argumento (vix).')
        vix = np.asarray(vix, dtype=float).ravel()
        if vix.size != data.size:
            M = min(vix.size, data.size)
            print(f'Warning: VIX y data con longitudes distintas. Se alinean al último {M} elementos.')
            data = data[data.size - M:]
            vix = vix[vix.size - M:]
            # si usas datamm para algo más adelante, recórtalo también si quieres
            # NOTA (réplica 1:1): el original NO recalcula dinero_final_lump tras realinear.

        precios_entrada = []
        entradas_filtradas_ret = []

        # 'entradas' ya son las señales Shewhart -2σ base que le pasas
        for i in range(1, len(entradas) + 1):
            idx = int(entradas[i - 1])
            if idx >= 1 and idx <= len(data):
                if not np.isnan(vix[idx - 1]) and vix[idx - 1] >= vix_umbral:
                    precios_entrada.append(data[idx - 1])
                    entradas_filtradas_ret.append(idx)

        precios_entrada = np.asarray(precios_entrada, dtype=float)
        entradas_filtradas_ret = np.asarray(entradas_filtradas_ret, dtype=int)
        num_aportaciones = len(entradas_filtradas_ret)

        if len(precios_entrada) == 0:
            r = calcularCAGR(dinero_inicial, dinero_final_lump, periodos)
        else:
            # Compras y CAGR (idéntico a tu caso base)
            acciones_compradas = np.sum(aportacion / precios_entrada)
            dinero_final_total = dinero_final_lump + acciones_compradas * data[-1]

            entradas_filtradas_365 = entradas_filtradas_ret * 365 / 252  # días naturales aprox
            T = periodos

            aportaciones = np.concatenate(([dinero_inicial], np.full(num_aportaciones, aportacion)))
            dias_aportaciones = np.concatenate(([0.0], entradas_filtradas_365))
            tiempos = T - dias_aportaciones / 365

            def funcion_CAGR(rr):
                return np.sum(aportaciones * (1 + rr) ** tiempos) - dinero_final_total

            r = brentq(funcion_CAGR, -1, 10)

    else:
        print("error: introduce 0 o 1 en la variable mm")
        # NOTA (réplica 1:1): en MATLAB 'r' y 'num_aportaciones' quedan sin asignar
        # en esta rama y la función falla ("Output argument not assigned").

    return r, num_aportaciones, entradas_filtradas_ret, rsi


# Funcion RSI

def rsi_wilder(close, n):
    # RSI de Wilder (sin toolboxes). Devuelve un vector columna con NaN iniciales.
    close = np.asarray(close, dtype=float).ravel()  # asegurar columna
    d = np.diff(close)
    up = np.maximum(d, 0)
    dn = np.maximum(-d, 0)

    rsi = np.full(close.shape, np.nan)  # misma longitud que 'close'
    if close.size < n + 1:
        return rsi

    # Medias iniciales (simples) para la primera ventana
    avgU = np.nanmean(up[:n])
    avgD = np.nanmean(dn[:n])

    # Primer RSI válido (posición n+1)
    if avgD == 0:
        rsi[n] = 100  # sin descensos en la ventana
    else:
        rs = avgU / avgD
        rsi[n] = 100 - 100 / (1 + rs)

    # Suavizado de Wilder (EMA con alpha = 1/n)
    for t in range(n + 2, close.size + 1):
        avgU = (avgU * (n - 1) + up[t - 2]) / n
        avgD = (avgD * (n - 1) + dn[t - 2]) / n

        if avgD == 0:
            rsi[t - 1] = 100
        else:
            rs = avgU / avgD
            rsi[t - 1] = 100 - 100 / (1 + rs)

    return rsi
