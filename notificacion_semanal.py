import numpy as np


def notificacion_semanal(asset, data, entradas_2smm, entradas_2mmvix, mm200):
    data = np.asarray(data, dtype=float).ravel()
    entradas_2smm = np.atleast_1d(np.asarray(entradas_2smm)).ravel()
    entradas_2mmvix = np.atleast_1d(np.asarray(entradas_2mmvix)).ravel()

    today_idx = len(data)
    precio_actual = data[today_idx - 1]

    # 1. Variación semanal (respecto a 5 sesiones atrás, cierre del viernes anterior)
    if today_idx > 5:
        precio_semana_pasada = data[today_idx - 6]
        var_semanal = ((precio_actual - precio_semana_pasada) / precio_semana_pasada) * 100
    elif today_idx > 1:
        precio_inicial = data[0]
        var_semanal = ((precio_actual - precio_inicial) / precio_inicial) * 100
    else:
        var_semanal = 0

    # Formatear variación semanal con signo (+/-)
    if var_semanal >= 0:
        str_var = f'+{var_semanal:.2f}% 1W'
    else:
        str_var = f'{var_semanal:.2f}% 1W'

    # 2. Diferencia porcentual respecto a la MA200
    diff_ma200 = ((precio_actual - mm200) / mm200) * 100
    if diff_ma200 >= 0:
        str_ma200 = f'+{diff_ma200:.2f}%'
    else:
        str_ma200 = f'{diff_ma200:.2f}%'

    # 3. Rango de la semana (últimas 5 sesiones bursátiles: Lunes a Viernes)
    week_start_idx = max(1, today_idx - 4)

    # Buscar si hubo alguna señal en CUALQUIERA de los días de esta semana
    hubo_2mmvix_semana = bool(np.any((entradas_2mmvix >= week_start_idx) & (entradas_2mmvix <= today_idx)))
    hubo_2smm_semana = bool(np.any((entradas_2smm >= week_start_idx) & (entradas_2smm <= today_idx)))

    # 4. Jerarquía de Criticidad (Prioridad: 🔥🟢 VIX > 🟢 2sigma > 🟡 Bajo MA200 > 🔴 Sin Señal)
    if hubo_2mmvix_semana:
        # MÁXIMA CRITICIDAD: Hubo señal de compra agresiva (+ VIX) en la semana
        msg = (f'🔥🟢 [{asset.upper()}] 🚨 AGGRESSIVE BUY! (Strategy: 2smm + VIX)\n'
               f'   ↳ Price: ${precio_actual:.2f} ({str_var})  |  MA200: ${mm200:.2f} [{str_ma200}]\n')

    elif hubo_2smm_semana:
        # SEGUNDA CRITICIDAD: Hubo señal de compra normal (2sigma) en la semana
        msg = (f'🟢 [{asset.upper()}] 🚨 BUY SIGNAL! (Strategy: 2smm)\n'
               f'   ↳ Price: ${precio_actual:.2f} ({str_var})  |  MA200: ${mm200:.2f} [{str_ma200}]\n')

    elif precio_actual < mm200:
        # SIN SEÑAL EN LA SEMANA, PERO PRECIO < MA200
        msg = (f'🟡 [{asset.upper()}] Below MA200 (Price: ${precio_actual:.2f} ({str_var})  |  '
               f'MA200: ${mm200:.2f} [{str_ma200}])\n')

    else:
        # SIN SEÑAL Y PRECIO >= MA200
        msg = (f'🔴 [{asset.upper()}] No signal (Price: ${precio_actual:.2f} ({str_var})  |  '
               f'MA200: ${mm200:.2f} [{str_ma200}])\n')

    return msg
