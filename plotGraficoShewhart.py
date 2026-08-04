import matplotlib.pyplot as plt


def plotGraficoShewhart(dias, data, media, sigma):
    # Graficar el grafico de Shewhart
    fig, ax = plt.subplots()
    ax.plot(range(1, dias + 1), data, 'ko', markersize=3, linestyle='none')

    # Media en azul
    ax.axhline(media, color='b', linestyle='-', linewidth=2)

    # Límites de advertencia (±1σ y ±2σ) en rojo discontinuo
    ax.axhline(media + sigma, color='r', linestyle='--', linewidth=1.5)
    ax.axhline(media - sigma, color='r', linestyle='--', linewidth=1.5)
    ax.axhline(media + 2 * sigma, color='r', linestyle='--', linewidth=1.5)
    ax.axhline(media - 2 * sigma, color='r', linestyle='--', linewidth=1.5)

    # Límites de control (±3σ) en rojo sólido y grueso
    ax.axhline(media + 3 * sigma, color='r', linestyle='-', linewidth=2.5)
    ax.axhline(media - 3 * sigma, color='r', linestyle='-', linewidth=2.5)

    # Etiquetas de las líneas (como el 'Label' de yline, alineado a la izquierda)
    x0, x1 = ax.get_xlim()
    ax.text(x0, media, 'Media', va='bottom', ha='left', color='b')
    for k, ls in ((1, '--'), (2, '--'), (3, '-')):
        ax.text(x0, media + k * sigma, f'+{k}σ', va='bottom', ha='left', color='r')
        ax.text(x0, media - k * sigma, f'-{k}σ', va='top', ha='left', color='r')

    ax.set_title('Gráfico de Control de Shewhart')
    ax.set_xlabel('Día')
    ax.set_ylabel('Precio de Cierre')
    ax.grid(True)

    # Obtener límites del eje para ubicar el texto en la esquina inferior derecha
    xLimits = ax.get_xlim()
    yLimits = ax.get_ylim()

    # Crear el texto con los valores de media y sigma
    texto = f'Media = {media:.2f}\nSigma = {sigma:.2f}'

    # Posicionar en esquina inferior derecha
    xPos = xLimits[1] - 0.05 * (xLimits[1] - xLimits[0])
    yPos = yLimits[0] + 0.05 * (yLimits[1] - yLimits[0])

    ax.text(xPos, yPos, texto, ha='right', va='bottom', fontsize=10,
            bbox=dict(facecolor='w', edgecolor='none'))

    return fig
