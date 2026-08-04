import numpy as np
import matplotlib.pyplot as plt


def plotMediasMoviles_bb(mm200, mm150, mm100, mm50, periodos, data, entradas_bb, asset,
                         N_bollinger, bb_mid, bb_up, bb_dn, k=None, volumen=None, vix=None,
                         entradas_fitradas_bbmmvix=None, vix_umbral=None):
    # Pinta Precio, MM (200/150/100/50), Entradas y Bandas de Bollinger PRECALCULADAS.
    # Args obligatorios de bandas: bb_mid, bb_up, bb_dn (mismo tamaño que data).
    # Args opcional: k (multiplicador de sigma para el rotulado; por defecto 2).

    if k is None or (np.size(k) == 0):
        k = 2

    # Asegurar vectores columna y longitudes compatibles
    data = np.asarray(data, dtype=float).ravel()
    mm200 = np.asarray(mm200, dtype=float).ravel()
    mm150 = np.asarray(mm150, dtype=float).ravel()
    mm100 = np.asarray(mm100, dtype=float).ravel()
    mm50 = np.asarray(mm50, dtype=float).ravel()
    bb_mid = np.asarray(bb_mid, dtype=float).ravel()
    bb_up = np.asarray(bb_up, dtype=float).ravel()
    bb_dn = np.asarray(bb_dn, dtype=float).ravel()
    n = data.size

    if any(v.size != n for v in (mm200, mm150, mm100, mm50, bb_mid, bb_up, bb_dn)):
        raise ValueError(f'Las longitudes de data/MM/bandas deben coincidir. data={n}, mm200={mm200.size}, '
                         f'mm150={mm150.size}, mm100={mm100.size}, mm50={mm50.size}, mid={bb_mid.size}, '
                         f'up={bb_up.size}, dn={bb_dn.size}')

    x = np.arange(1, n + 1)

    fig = plt.figure()
    fig.clf()

    # Subplot superior: Precio y Bollinger (75% de altura)
    ax1 = plt.subplot2grid((4, 1), (0, 0), rowspan=3)

    # Precio
    ax1.plot(x, data, 'k', label='Precio')

    # Medias móviles
    ax1.plot(x, mm100, linewidth=1.5, color=(0.00, 0.45, 0.74), label='Media Móvil 100')

    # Banda de Bollinger (relleno entre superior e inferior)
    inBand = np.isfinite(bb_up) & np.isfinite(bb_dn)
    if np.any(inBand):
        px = np.concatenate((x[inBand], x[inBand][::-1]))
        py = np.concatenate((bb_up[inBand], bb_dn[inBand][::-1]))
        ax1.fill(px, py, color=(0.1, 0.4, 0.4), alpha=0.15, edgecolor='none', label='Banda Bollinger')

    # Líneas de Bollinger
    ax1.plot(x, bb_up, '-', linewidth=1.2, color=(1, 0.4, 0.4),
             label=f'Bollinger +{k:g}σ')
    ax1.plot(x, bb_dn, '-', linewidth=1.2, color=(1, 0.4, 0.4),
             label=f'Bollinger -{k:g}σ')

    # Puntos de entrada Bollinger
    if entradas_bb is not None and np.size(entradas_bb) > 0:
        entradas_bb = np.asarray(entradas_bb).ravel().astype(int)
        entradas_bb = entradas_bb[(entradas_bb >= 1) & (entradas_bb <= n) & np.isfinite(data[entradas_bb - 1])]
        if entradas_bb.size > 0:
            ax1.plot(entradas_bb, data[entradas_bb - 1], 'go',
                     markersize=4, markeredgewidth=1.2,
                     label='Entradas Bollinger')

    # Entradas donde el VIX > vix_umbral
    if entradas_fitradas_bbmmvix is not None and np.size(entradas_fitradas_bbmmvix) > 0:
        entradas_fitradas_bbmmvix = np.asarray(entradas_fitradas_bbmmvix).ravel().astype(int)
        ax1.plot(entradas_fitradas_bbmmvix, data[entradas_fitradas_bbmmvix - 1], 'rx',
                 markersize=5, markeredgewidth=1.2, label=f'VIX > {vix_umbral:.0f}')

    # Configuración gráfico superior
    ax1.set_xlim(1, n)
    ax1.set_ylabel('Precio')
    ax1.set_title(f'Precio y señales de Bollinger (N={N_bollinger}, {periodos} años) — {asset}')
    ax1.legend(loc='upper left')
    ax1.grid(True)

    # Subplot inferior: Volumen y VIX (25% de altura)
    ax2 = plt.subplot2grid((4, 1), (3, 0))

    volumen = np.asarray(volumen, dtype=float).ravel()
    vix = np.asarray(vix, dtype=float).ravel()

    # Determinar colores según cambio de precio
    cambio_precio = np.concatenate(([0], np.diff(data)))
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
    ax2.set_xlim(1, n)

    # Crear segundo eje Y para VIX
    ax2b = ax2.twinx()
    ax2b.plot(x, vix, linewidth=1.5, color=(0.8, 0.2, 0.8), label='VIX')
    ax2b.set_ylabel('VIX')
    ax2b.yaxis.label.set_color((0.8, 0.2, 0.8))
    ax2b.tick_params(axis='y', colors=(0.8, 0.2, 0.8))

    ax2.set_xlabel('Día')
    ax2.grid(True)

    # Ajustar el tamaño de la ventana
    fig.set_size_inches(1000 / 100, 700 / 100)
    fig.set_dpi(100)
