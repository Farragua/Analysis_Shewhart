import numpy as np
import matplotlib.pyplot as plt


def plotMediasMoviles(mm200, mm150, mm100, mm50, periodos, data, entradas_3s, entradas_2s,
                      bloqueos, media_movil_lenta, asset, volumen, vix, entradas_2mmvix, vix_umbral):
    if media_movil_lenta == 150:
        media_movil_lenta = mm150
    elif media_movil_lenta == 100:
        media_movil_lenta = mm100
    elif media_movil_lenta == 200:
        media_movil_lenta = mm200
    else:
        print("Error: media movil lenta debe ser (100, 150, 200) ")

    data = np.asarray(data, dtype=float).ravel()
    volumen = np.asarray(volumen, dtype=float).ravel()
    vix = np.asarray(vix, dtype=float).ravel()
    entradas_3s = np.asarray(entradas_3s).ravel()
    entradas_2s = np.asarray(entradas_2s).ravel()
    entradas_2mmvix = np.asarray(entradas_2mmvix).ravel()

    fig = plt.figure()
    fig.clf()

    # Subplot superior: Precio y medias móviles (75% de altura)
    ax1 = plt.subplot2grid((4, 1), (0, 0), rowspan=3)  # Ocupa 3/4 de la altura (75%)

    # Trazado principal
    ax1.plot(range(1, len(data) + 1), data, 'k', label='Precio')
    ax1.plot(range(1, len(data) + 1), mm200, linewidth=1.5,
             color=(0.85, 0.33, 0.10), label='Media Móvil 200')
    ax1.plot(range(1, len(data) + 1), mm100, linewidth=1.5,
             color=(0.00, 0.45, 0.74), label='Media Móvil 100')
    ax1.plot(range(1, len(data) + 1), mm50, linewidth=1.5,
             color=(0.47, 0.67, 0.19), label='Media Móvil 50')

    # Puntos -3σ
    ax1.plot(entradas_3s, data[entradas_3s.astype(int) - 1], 'go',
             markersize=4, markeredgewidth=1.2, label='Entrada < -3σ')

    # Puntos entre -2σ y -3σ
    entradas_2s_unicas = np.setdiff1d(entradas_2s, entradas_3s)
    ax1.plot(entradas_2s_unicas, data[entradas_2s_unicas.astype(int) - 1], 'o',
             color=(1, 0.5, 0), markersize=4, markeredgewidth=1.2,
             label='-2σ ≥ Entrada > -3σ')

    # Entradas donde el VIX > vix_umbral
    ax1.plot(entradas_2mmvix, data[entradas_2mmvix.astype(int) - 1], 'rx',
             markersize=5, markeredgewidth=1.2, label=f'VIX > {vix_umbral:.0f}')

    # Configuración del gráfico superior
    ax1.set_xlim(1, 252 * periodos)
    ax1.set_ylabel('Precio')
    ax1.set_title(f'Precio y señales de Shewhart ({periodos} años) — {asset}')
    ax1.legend(loc='upper left')
    ax1.grid(True)

    # Subplot inferior: Volumen y VIX (25% de altura)
    ax2 = plt.subplot2grid((4, 1), (3, 0))  # Ocupa 1/4 de la altura (25%)

    # Determinar colores según cambio de precio
    cambio_precio = np.concatenate(([0], np.diff(data)))  # Primera barra será neutral
    colores_volumen = np.zeros((len(volumen), 3))

    for i in range(1, len(volumen) + 1):
        if cambio_precio[i - 1] > 0:
            colores_volumen[i - 1, :] = [0.2, 0.8, 0.2]  # Verde
        elif cambio_precio[i - 1] < 0:
            colores_volumen[i - 1, :] = [0.8, 0.2, 0.2]  # Rojo
        else:
            colores_volumen[i - 1, :] = [0.5, 0.5, 0.5]  # Gris (sin cambio)

    # Dibujar barras con colores individuales
    for i in range(1, len(volumen) + 1):
        ax2.bar(i, volumen[i - 1], color=colores_volumen[i - 1, :], edgecolor='none')

    # Eje Y izquierdo para volumen
    ax2.set_ylabel('Volumen')
    ax2.set_xlim(1, 252 * periodos)

    # Crear segundo eje Y para VIX
    ax2b = ax2.twinx()
    x = np.arange(1, len(vix) + 1)
    ax2b.plot(x, vix, linewidth=1.5, color=(0.8, 0.2, 0.8), label='VIX')
    ax2b.set_ylabel('VIX')
    ax2b.yaxis.label.set_color((0.8, 0.2, 0.8))
    ax2b.tick_params(axis='y', colors=(0.8, 0.2, 0.8))

    ax2.set_xlabel('Día')
    ax2.grid(True)

    # Ajustar el tamaño de la ventana
    fig.set_size_inches(1000 / 100, 700 / 100)
    fig.set_dpi(100)
