% function [r,num_aportaciones_DCA] = calcularCAGR_aportaciones_DCA(data, frecuencia, aportacion, dinero_inicial)
% 
% fprintf("Cálculo utilizando estrategia DCA con inversión inicial y aportaciones periódicas.\n")
% 
% T = length(data);              % Número total de días del período
% fechas_aportaciones = 0:frecuencia:T-1; % Días donde se realiza cada aportación
% num_aportaciones_DCA = length(fechas_aportaciones);
% 
% % Inicializar total de acciones compradas
% acciones_compradas = 0;
% 
% for i = 1:num_aportaciones_DCA
%     precio = data(fechas_aportaciones(i) + 1);  % +1 porque MATLAB indexa desde 1
%     if i == 1
%         aporte = dinero_inicial;  % Primer aporte
%     else
%         aporte = aportacion;      % Aportes mensuales
%     end
%     acciones_compradas = acciones_compradas + (aporte / precio);
% end
% 
% % Valor final del portafolio
% valor_final = acciones_compradas * data(end);
% 
% % Crear vector de aportes
% aportes = [dinero_inicial, repmat(aportacion, 1, num_aportaciones_DCA - 1)];
% 
% % Tiempos en años restantes desde cada aporte hasta el final
% tiempos = (T - fechas_aportaciones) / 252;
% 
% % Definir función para resolver CAGR
% funcion_CAGR = @(r) sum(aportes .* (1 + r).^tiempos) - valor_final;
% 
% % Encontrar CAGR
% r = fzero(funcion_CAGR, [-1, 10]);  % CAGR entre 0% y 100%
% 
% end


function [r_DCA, num_aportaciones_DCA] = calcularCAGR_aportaciones_DCA(data, frecuencia, aportacion, dinero_inicial)
% calcularCAGR_aportaciones_DCA
% - Invierte 'dinero_inicial' en t=0 (día 1 del vector) y luego aporta cada
%   'frecuencia' días bursátiles (p.ej. 21 ≈ mensual).
% - Compra SIEMPRE al precio de cierre del día de aportación.
% - Convierte tiempos a años con 252 días bursátiles / año (coherente con el resto).
%
% Entradas:
%   data            vector de precios (1 x N o N x 1), sin NaN
%   frecuencia      pasos entre aportes en días bursátiles (entero >= 1)
%   aportacion      importe de cada aporte periódico (>0)
%   dinero_inicial  aporte en t=0 (puede ser 0)
%
% Salidas:
%   r                       CAGR anual (solve de IRR continuo con capitalización simple)
%   num_aportaciones_DCA    nº de aportes efectuados (incluye el inicial si > 0)
%
% Notas:
% - Si el último aporte cae el último día (T-1 en 0-based), su tiempo a vencimiento será ~1/252 años.
% - Si todos los aportes son 0, devuelve r = NaN.

   % fprintf("Cálculo utilizando estrategia DCA con inversión inicial y aportaciones periódicas.\n");

    % --------- Validaciones básicas ----------
    if isempty(data) || numel(data) < 2
        error('data debe contener al menos 2 precios.');
    end
    data = data(:)'; % fila
    if any(~isfinite(data))
        error('data contiene NaN/Inf. Limpia o interpola antes.');
    end
    if ~(isscalar(frecuencia) && frecuencia == floor(frecuencia) && frecuencia >= 1)
        error('frecuencia debe ser un entero >= 1.');
    end
    if ~(isscalar(aportacion) && aportacion >= 0)
        error('aportacion debe ser escalar >= 0.');
    end
    if ~(isscalar(dinero_inicial) && dinero_inicial >= 0)
        error('dinero_inicial debe ser escalar >= 0.');
    end

    T = numel(data);  % nº de días
    % Días (0-based) en los que se aporta: 0, f, 2f, ...
    fechas_aportaciones = 0:frecuencia:(T-1);
    num_aportaciones_DCA = numel(fechas_aportaciones);

    % --------- Cómputo de acciones compradas ----------
    acciones_compradas = 0;
    for i = 1:num_aportaciones_DCA
        idx = fechas_aportaciones(i) + 1;   % 1-based para MATLAB
        precio = data(idx);

        % Primer aporte = dinero_inicial; resto = aportacion
        if i == 1
            aporte = dinero_inicial;
        else
            aporte = aportacion;
        end

        if aporte > 0
            acciones_compradas = acciones_compradas + (aporte / precio);
        end
    end

    % --------- Valor final y tiempos ----------
    valor_final = acciones_compradas * data(end);

    % Vector de aportes (en el mismo orden que fechas_aportaciones)
    if num_aportaciones_DCA >= 1
        aportes = [dinero_inicial, repmat(aportacion, 1, num_aportaciones_DCA - 1)];
    else
        aportes = 0;
    end

    % Tiempos en años desde cada aporte hasta el final (252 días/año)
    tiempos = (T - fechas_aportaciones) / 252;

    % Si no hay aportes reales, r = NaN
    if all(aportes == 0)
        r_DCA = NaN;
        return;
    end

    % --------- Resolver CAGR (IRR) ----------
    % Ecuación: sum(aportes .* (1 + r).^tiempos) = valor_final
    funcion_CAGR = @(rr) sum(aportes .* (1 + rr) .^ tiempos) - valor_final;

    % Intento con bracket estándar
    a = -0.999;  % no puede ser -1 porque elevaríamos a 0
    b = 10;

    % Asegurar cambio de signo; si no, usar un fallback
    fa = funcion_CAGR(a);
    fb = funcion_CAGR(b);

    if sign(fa) == sign(fb)
        % Fallback: busca alrededor de 0 como inicial
        try
            r_DCA = fzero(funcion_CAGR, 0.1);
        catch
            % Último recurso: pequeño barrido para encontrar un bracket
            xs = linspace(-0.9, 1.5, 50);
            vals = arrayfun(funcion_CAGR, xs);
            k = find(diff(sign(vals)) ~= 0, 1, 'first');
            if ~isempty(k)
                r_DCA = fzero(funcion_CAGR, [xs(k), xs(k+1)]);
            else
                % Si no se encuentra raíz, devolver NaN para no romper el flujo
                r_DCA = NaN;
            end
        end
    else
        r_DCA = fzero(funcion_CAGR, [a, b]);
    end
end
