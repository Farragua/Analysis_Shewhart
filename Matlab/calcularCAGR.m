
%Calcular CAGR
function r = calcularCAGR(Vi, Vf, n)
    r = (Vf / Vi)^(1 / n) - 1;
end