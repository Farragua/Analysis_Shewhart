import numpy as np


def Medias_Moviles(datamm, data):
    # data son los datos que queremos tratar
    # datamm son los datos + 150 periodos atras para poder calcular la mm150
    datamm = np.asarray(datamm, dtype=float).ravel()
    data = np.asarray(data, dtype=float).ravel()

    N = data.size
    L = datamm.size

    # En MATLAB los arrays nacen con tamaño de 'data' y crecen hasta length(datamm)
    # dentro del bucle; aquí se reservan directamente con tamaño length(datamm).
    mm200 = np.full(L, np.nan)
    mm150 = np.full(L, np.nan)
    mm100 = np.full(L, np.nan)
    mm50 = np.full(L, np.nan)

    # OJO: replica 1:1 del original -> las ventanas son de K+1 puntos
    # (MATLAB: mean(datamm(i-200:i)) son 201 puntos, etc.)
    for i in range(201, L + 1):
        mm200[i - 1] = np.mean(datamm[i - 201:i])

    for i in range(151, L + 1):
        mm150[i - 1] = np.mean(datamm[i - 151:i])

    mm150 = mm150[L - N:]  # Coger los ultimos size(data,1) elementos

    for i in range(101, L + 1):
        mm100[i - 1] = np.mean(datamm[i - 101:i])

    mm100 = mm100[L - N:]  # Coger los ultimos size(data,1) elementos

    for i in range(51, L + 1):
        mm50[i - 1] = np.mean(datamm[i - 51:i])

    mm50 = mm50[L - N:]  # Coger los ultimos 251 elementos

    # elimina los NaN
    mm200 = mm200[~np.isnan(mm200)]
    mm150 = mm150[~np.isnan(mm150)]
    mm100 = mm100[~np.isnan(mm100)]
    mm50 = mm50[~np.isnan(mm50)]

    return mm200, mm150, mm100, mm50
