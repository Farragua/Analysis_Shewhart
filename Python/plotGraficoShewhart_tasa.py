import numpy as np
import matplotlib.pyplot as plt


def plotGraficoShewhart_tasa(data, media, sigma):
    # plotGraficoShewhart_tasa: Gráfico de control tipo Shewhart para tasas
    # Inputs:
    #   - data: vector de tasas o métricas (por ejemplo, porcentaje diario)
    #   - media: valor medio esperado
    #   - sigma: desviación estándar

    data = np.asarray(data, dtype=float).ravel()
    dias = len(data)  # número real de datos

    fig, ax = plt.subplots()
    ax.plot(range(1, dias + 1), data, 'ko', markersize=3, linestyle='none')

    # Línea central
    ax.axhline(media, color='b', linestyle='-', linewidth=2)
    ax.text(1, media, r'$\bar{y}$', va='bottom', ha='left', color='b')

    # Límites ±1σ, ±2σ, ±3σ
    for k in (1, 2):
        ax.axhline(media + k * sigma, color='r', linestyle='--', linewidth=1.5)
        ax.axhline(media - k * sigma, color='r', linestyle='--', linewidth=1.5)
        ax.text(1, media + k * sigma, rf'+{k}$\sigma$', va='bottom', ha='left', color='r')
        ax.text(1, media - k * sigma, rf'-{k}$\sigma$', va='top', ha='left', color='r')
    for k in (3,):
        ax.axhline(media + k * sigma, color='r', linestyle='-', linewidth=2.5)
        ax.axhline(media - k * sigma, color='r', linestyle='-', linewidth=2.5)
        ax.text(1, media + k * sigma, rf'+{k}$\sigma$', va='bottom', ha='left', color='r')
        ax.text(1, media - k * sigma, rf'-{k}$\sigma$', va='top', ha='left', color='r')

    ax.set_title('Gráfico de Control de Shewhart (Tasa)')
    ax.set_xlabel('Día')
    ax.set_ylabel('%')
    ax.grid(True)
    ax.set_xlim(1, dias)  # ← Eje X ajustado al tamaño real de data

    # Obtener límites del eje
    xLimits = ax.get_xlim()
    yLimits = ax.get_ylim()

    # Esquina inferior derecha
    texto1 = rf'$\bar{{y}}$ = {media:.2f}' + '\n' + rf'$\sigma$ = {sigma:.2f}'
    xPos1 = xLimits[1] - 0.02 * (xLimits[1] - xLimits[0])
    yPos1 = yLimits[0] + 0.02 * (yLimits[1] - yLimits[0])
    ax.text(xPos1, yPos1, texto1, ha='right', va='bottom', fontsize=10,
            bbox=dict(facecolor='w', edgecolor='none'))

    # Esquina superior izquierda con intervalos
    texto2 = (rf'$\pm1\sigma$ ({media - sigma:.2f}, {media + sigma:.2f})' + '\n' +
              rf'$\pm2\sigma$ ({media - 2 * sigma:.2f}, {media + 2 * sigma:.2f})' + '\n' +
              rf'$\pm3\sigma$ ({media - 3 * sigma:.2f}, {media + 3 * sigma:.2f})')
    xPos2 = xLimits[0] + 0.01 * (xLimits[1] - xLimits[0])
    yPos2 = yLimits[1] - 0.02 * (yLimits[1] - yLimits[0])
    ax.text(xPos2, yPos2, texto2, ha='left', va='top', fontsize=10,
            bbox=dict(facecolor='w', edgecolor='none'))

    return fig
