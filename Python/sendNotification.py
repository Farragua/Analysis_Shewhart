import numpy as np


def sendNotification(asset, data, entradas_2smm, entradas_2mmvix, mm200):
    data = np.asarray(data, dtype=float).ravel()
    entradas_2smm = np.atleast_1d(np.asarray(entradas_2smm)).ravel()
    entradas_2mmvix = np.atleast_1d(np.asarray(entradas_2mmvix)).ravel()

    today_idx = len(data)
    precio_actual = data[today_idx - 1]

    # 1. Variación diaria (respecto al día anterior)
    if today_idx > 1:
        precio_ayer = data[today_idx - 2]
        var_diaria = ((precio_actual - precio_ayer) / precio_ayer) * 100
    else:
        var_diaria = 0  # Por seguridad

    # Formatear variación diaria con signo (+/-)
    if var_diaria >= 0:
        str_var = f'+{var_diaria:.2f}%'
    else:
        str_var = f'{var_diaria:.2f}%'

    # 2. Diferencia porcentual respecto a la MA200
    diff_ma200 = ((precio_actual - mm200) / mm200) * 100

    if diff_ma200 >= 0:
        str_ma200 = f'+{diff_ma200:.2f}%'
    else:
        str_ma200 = f'{diff_ma200:.2f}%'

    # 3. Detectar si hoy hay señal activa
    es_2smm = (entradas_2smm.size > 0 and entradas_2smm[-1] == today_idx)
    es_2mmvix = (entradas_2mmvix.size > 0 and entradas_2mmvix[-1] == today_idx)

    # 4. Lógica del código de colores según el estado
    if es_2mmvix:
        # SEÑAL AGRESIVA (+ VIX) -> Verde + Fuego 🔥🟢
        msg = (f'🔥🟢 [{asset.upper()}] 🚨 AGGRESSIVE BUY! (Strategy: 2smm + VIX)\n'
               f'   ↳ Price: ${precio_actual:.2f} ({str_var})  |  MA200: ${mm200:.2f} [{str_ma200}]\n')

    elif es_2smm:
        # SEÑAL DE COMPRA NORMAL -> Verde 🟢
        msg = (f'🟢 [{asset.upper()}] 🚨 BUY SIGNAL! (Strategy: 2smm)\n'
               f'   ↳ Price: ${precio_actual:.2f} ({str_var})  |  MA200: ${mm200:.2f} [{str_ma200}]\n')

    elif precio_actual < mm200:
        # SIN SEÑAL PERO PRECIO < MA200 -> Ámbar 🟡
        msg = (f'🟡 [{asset.upper()}] Below MA200 (Price: ${precio_actual:.2f} ({str_var})  |  '
               f'MA200: ${mm200:.2f} [{str_ma200}])\n')

    else:
        # SIN SEÑAL Y PRECIO >= MA200 -> Rojo 🔴
        msg = (f'🔴 [{asset.upper()}] No signal (Price: ${precio_actual:.2f} ({str_var})  |  '
               f'MA200: ${mm200:.2f} [{str_ma200}])\n')

    return msg
