def calcularCAGR(Vi, Vf, n):
    # Calcular CAGR
    r = (Vf / Vi) ** (1 / n) - 1
    return r
