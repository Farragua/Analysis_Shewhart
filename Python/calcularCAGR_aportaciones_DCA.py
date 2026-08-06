import numpy as np
from scipy.optimize import brentq, newton


def calcularCAGR_aportaciones_DCA(data, frecuencia, aportacion, dinero_inicial):
    # calcularCAGR_aportaciones_DCA
    # - Invierte 'dinero_inicial' en t=0 (día 1 del vector) y luego aporta cada
    #   'frecuencia' días bursátiles (p.ej. 21 ≈ mensual).
    # - Compra SIEMPRE al precio de cierre del día de aportación.
    # - Convierte tiempos a años con 252 días bursátiles / año (coherente con el resto).
    #
    # Notas:
    # - Si el último aporte cae el último día (T-1 en 0-based), su tiempo a vencimiento será ~1/252 años.
    # - Si todos los aportes son 0, devuelve r = NaN.

    # --------- Validaciones básicas ----------
    if data is None or len(data) == 0 or np.asarray(data).size < 2:
        raise ValueError('data debe contener al menos 2 precios.')
    data = np.asarray(data, dtype=float).ravel()  # fila
    if np.any(~np.isfinite(data)):
        raise ValueError('data contiene NaN/Inf. Limpia o interpola antes.')
    if not (np.isscalar(frecuencia) and frecuencia == np.floor(frecuencia) and frecuencia >= 1):
        raise ValueError('frecuencia debe ser un entero >= 1.')
    if not (np.isscalar(aportacion) and aportacion >= 0):
        raise ValueError('aportacion debe ser escalar >= 0.')
    if not (np.isscalar(dinero_inicial) and dinero_inicial >= 0):
        raise ValueError('dinero_inicial debe ser escalar >= 0.')

    frecuencia = int(frecuencia)
    T = data.size  # nº de días
    # Días (0-based) en los que se aporta: 0, f, 2f, ...
    fechas_aportaciones = np.arange(0, T, frecuencia)
    num_aportaciones_DCA = fechas_aportaciones.size

    # --------- Cómputo de acciones compradas ----------
    acciones_compradas = 0
    for i in range(1, num_aportaciones_DCA + 1):
        idx = fechas_aportaciones[i - 1] + 1   # 1-based para replicar MATLAB
        precio = data[idx - 1]

        # Primer aporte = dinero_inicial; resto = aportacion
        if i == 1:
            aporte = dinero_inicial
        else:
            aporte = aportacion

        if aporte > 0:
            acciones_compradas = acciones_compradas + (aporte / precio)

    # --------- Valor final y tiempos ----------
    valor_final = acciones_compradas * data[-1]

    # Vector de aportes (en el mismo orden que fechas_aportaciones)
    if num_aportaciones_DCA >= 1:
        aportes = np.concatenate(([dinero_inicial], np.full(num_aportaciones_DCA - 1, aportacion)))
    else:
        aportes = np.array([0.0])

    # Tiempos en años desde cada aporte hasta el final (252 días/año)
    tiempos = (T - fechas_aportaciones) / 252

    # Si no hay aportes reales, r = NaN
    if np.all(aportes == 0):
        r_DCA = np.nan
        return r_DCA, num_aportaciones_DCA

    # --------- Resolver CAGR (IRR) ----------
    # Ecuación: sum(aportes .* (1 + r).^tiempos) = valor_final
    def funcion_CAGR(rr):
        return np.sum(aportes * (1 + rr) ** tiempos) - valor_final

    # Intento con bracket estándar
    a = -0.999  # no puede ser -1 porque elevaríamos a 0
    b = 10

    # Asegurar cambio de signo; si no, usar un fallback
    fa = funcion_CAGR(a)
    fb = funcion_CAGR(b)

    if np.sign(fa) == np.sign(fb):
        # Fallback: busca alrededor de 0 como inicial
        try:
            r_DCA = newton(funcion_CAGR, 0.1)
        except Exception:
            # Último recurso: pequeño barrido para encontrar un bracket
            xs = np.linspace(-0.9, 1.5, 50)
            vals = np.array([funcion_CAGR(x) for x in xs])
            s = np.sign(vals)
            k = np.flatnonzero(np.diff(s) != 0)  # primer cambio de signo
            if k.size > 0:
                r_DCA = brentq(funcion_CAGR, xs[k[0]], xs[k[0] + 1])
            else:
                # Si no se encuentra raíz, devolver NaN para no romper el flujo
                r_DCA = np.nan
    else:
        r_DCA = brentq(funcion_CAGR, a, b)

    return r_DCA, num_aportaciones_DCA
