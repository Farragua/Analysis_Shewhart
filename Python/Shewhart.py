import numpy as np


def Shewhart(data):
    data = np.asarray(data, dtype=float).ravel()

    puntos_entrada_3s = np.array([], dtype=int)
    puntos_entrada_2s = np.array([], dtype=int)

    tasa = np.diff(data) / data[:-1]
    tasa = tasa * 100
    media = np.mean(tasa)
    # sigma = np.std(tasa, ddof=1)
    # calculos de la sigma de tippett:
    RM = np.abs(np.diff(tasa))
    sigma_t = np.mean(RM) / 1.128
    dias = len(data)

    # find(tasa <= (media - 3*sigma_t)) + 1  ->  flatnonzero (0-based) + 1 (find 1-based) + 1 (el +1 del propio código)
    puntos_entrada_3s = np.flatnonzero(tasa <= (media - 3 * sigma_t)) + 1 + 1
    puntos_entrada_2s = np.flatnonzero(tasa <= (media - 2 * sigma_t)) + 1 + 1

    return puntos_entrada_3s, puntos_entrada_2s, tasa, media, sigma_t
