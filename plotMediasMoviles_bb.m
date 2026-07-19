

% function plotMediasMoviles_bb(mm200, mm150, mm100, mm50, periodos, data, entradas_bb, asset, N_bollinger, bb_mid, bb_up, bb_dn, k,volumen,vix);
% 
% % Pinta Precio, MM (200/150/100/50), Entradas y Bandas de Bollinger PRECALCULADAS.
% % Args obligatorios de bandas: bb_mid, bb_up, bb_dn (mismo tamaño que data).
% % Args opcional: k (multiplicador de sigma para el rotulado; por defecto 2).
% 
%     if nargin < 12
%         error('Debes pasar bb_mid, bb_up y bb_dn (bandas de Bollinger ya calculadas).');
%     end
%     if nargin < 13 || isempty(k)
%         k = 2;
%     end
% 
%     % Asegurar vectores columna y longitudes compatibles
%     data   = data(:);
%     mm200  = mm200(:); mm150 = mm150(:); mm100 = mm100(:); mm50 = mm50(:);
%     bb_mid = bb_mid(:); bb_up = bb_up(:); bb_dn = bb_dn(:);
% 
%     n = numel(data);
%     if any([numel(mm200) numel(mm150) numel(mm100) numel(mm50) numel(bb_mid) numel(bb_up) numel(bb_dn)] ~= n)
%         error('Las longitudes de data/MM/bandas deben coincidir. data=%d, mm200=%d, mm150=%d, mm100=%d, mm50=%d, mid=%d, up=%d, dn=%d', ...
%               n, numel(mm200), numel(mm150), numel(mm100), numel(mm50), numel(bb_mid), numel(bb_up), numel(bb_dn));
%     end
% 
%     x = (1:n)';
% 
%     figure; clf; hold on;
% 
%     % Precio
%     plot(x, data, 'k', 'DisplayName', 'Precio');
% 
%     % Medias móviles
%     %plot(x, mm200, 'LineWidth', 1.5, 'Color', [0.85 0.33 0.10], 'DisplayName', 'Media Móvil 200');
%     %plot(x, mm150, 'LineWidth', 1.5, 'Color', [0.93 0.69 0.13], 'DisplayName', 'Media Móvil 150');
%     plot(x, mm100, 'LineWidth', 1.5, 'Color', [0.00 0.45 0.74], 'DisplayName', 'Media Móvil 100');
%     %plot(x, mm50,  'LineWidth', 1.5, 'Color', [0.47 0.67 0.19], 'DisplayName', 'Media Móvil 50');
% 
%     % Banda de Bollinger (relleno entre superior e inferior)
%     inBand = isfinite(bb_up) & isfinite(bb_dn);
%     if any(inBand)
%         px = [x(inBand); flipud(x(inBand))];
%         py = [bb_up(inBand); flipud(bb_dn(inBand))];
%         patch(px, py, [0.1 0.4 0.4], 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'DisplayName', 'Banda Bollinger');
%     end
% 
%     % Líneas de Bollinger
%     plot(x, bb_up,  '-',  'LineWidth', 1.2, 'Color', [1 0.4 0.4], ...
%          'DisplayName', sprintf('Bollinger +%gσ', k));
%     % plot(x, bb_mid, '--', 'LineWidth', 1.2, 'Color', [0.50 0.50 0.50], ...
%     %      'DisplayName', 'Media Bollinger');
%     plot(x, bb_dn,  '-',  'LineWidth', 1.2, 'Color', [1 0.4 0.4], ...
%          'DisplayName', sprintf('Bollinger -%gσ', k));
% 
%     % Puntos de entrada Bollinger
%     if ~isempty(entradas_bb)
%         entradas_bb = entradas_bb(:);
%         entradas_bb = entradas_bb(entradas_bb >= 1 & entradas_bb <= n & isfinite(data(entradas_bb)));
%         if ~isempty(entradas_bb)
%             plot(entradas_bb, data(entradas_bb), 'go', ...
%                  'MarkerSize', 4, 'LineWidth', 1.2, ...
%                 'DisplayName', 'Entradas Bollinger');
%         end
%     end
% 
%     % Configuración
%     xlim([1 n]);
%     xlabel('Día'); ylabel('Precio');
%     title(sprintf('Precio y señales de Bollinger (N=%d, %d años) — %s', N_bollinger, periodos, char(asset)));
%     legend('Location', 'northwest');
%     grid on;
% end
function plotMediasMoviles_bb(mm200, mm150, mm100, mm50, periodos, data, entradas_bb, asset, N_bollinger, bb_mid, bb_up, bb_dn, k, volumen, vix, entradas_fitradas_bbmmvix,vix_umbral)
% Pinta Precio, MM (200/150/100/50), Entradas y Bandas de Bollinger PRECALCULADAS.
% Args obligatorios de bandas: bb_mid, bb_up, bb_dn (mismo tamaño que data).
% Args opcional: k (multiplicador de sigma para el rotulado; por defecto 2).

    if nargin < 12
        error('Debes pasar bb_mid, bb_up y bb_dn (bandas de Bollinger ya calculadas).');
    end
    if nargin < 13 || isempty(k)
        k = 2;
    end
    
    % Asegurar vectores columna y longitudes compatibles
    data = data(:);
    mm200 = mm200(:); mm150 = mm150(:); mm100 = mm100(:); mm50 = mm50(:);
    bb_mid = bb_mid(:); bb_up = bb_up(:); bb_dn = bb_dn(:);
    n = numel(data);
    
    if any([numel(mm200) numel(mm150) numel(mm100) numel(mm50) numel(bb_mid) numel(bb_up) numel(bb_dn)] ~= n)
        error('Las longitudes de data/MM/bandas deben coincidir. data=%d, mm200=%d, mm150=%d, mm100=%d, mm50=%d, mid=%d, up=%d, dn=%d', ...
            n, numel(mm200), numel(mm150), numel(mm100), numel(mm50), numel(bb_mid), numel(bb_up), numel(bb_dn));
    end
    
    x = (1:n)';
    
    figure; clf;
    
    % Subplot superior: Precio y Bollinger (75% de altura)
    subplot(4, 1, 1:3);
    hold on;
    
    % Precio
    plot(x, data, 'k', 'DisplayName', 'Precio');
    
    % Medias móviles
    plot(x, mm100, 'LineWidth', 1.5, 'Color', [0.00 0.45 0.74], 'DisplayName', 'Media Móvil 100');
    
    % Banda de Bollinger (relleno entre superior e inferior)
    inBand = isfinite(bb_up) & isfinite(bb_dn);
    if any(inBand)
        px = [x(inBand); flipud(x(inBand))];
        py = [bb_up(inBand); flipud(bb_dn(inBand))];
        patch(px, py, [0.1 0.4 0.4], 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'DisplayName', 'Banda Bollinger');
    end
    
    % Líneas de Bollinger
    plot(x, bb_up, '-', 'LineWidth', 1.2, 'Color', [1 0.4 0.4], ...
        'DisplayName', sprintf('Bollinger +%gσ', k));
    plot(x, bb_dn, '-', 'LineWidth', 1.2, 'Color', [1 0.4 0.4], ...
        'DisplayName', sprintf('Bollinger -%gσ', k));
    
    % Puntos de entrada Bollinger
    if ~isempty(entradas_bb)
        entradas_bb = entradas_bb(:);
        entradas_bb = entradas_bb(entradas_bb >= 1 & entradas_bb <= n & isfinite(data(entradas_bb)));
        if ~isempty(entradas_bb)
            plot(entradas_bb, data(entradas_bb), 'go', ...
                'MarkerSize', 4, 'LineWidth', 1.2, ...
                'DisplayName', 'Entradas Bollinger');
        end
    end


        % Entradas donde el VIX > vix_umbral
    hold on;
    plot(entradas_fitradas_bbmmvix, data(entradas_fitradas_bbmmvix), 'rx', ...
        'MarkerSize', 5, 'LineWidth', 1.2, 'DisplayName', sprintf('VIX > %.2d', vix_umbral));
    
    % Configuración gráfico superior
    xlim([1 n]);
    ylabel('Precio');
    title(sprintf('Precio y señales de Bollinger (N=%d, %d años) — %s', N_bollinger, periodos, char(asset)));
    legend('Location', 'northwest');
    grid on;
    
    % Subplot inferior: Volumen y VIX (25% de altura)
    subplot(4, 1, 4);
    
    % Determinar colores según cambio de precio
    cambio_precio = [0; diff(data)];
    colores_volumen = zeros(length(volumen), 3);
    
    for i = 1:length(volumen)
        if cambio_precio(i) > 0
            colores_volumen(i, :) = [0.2 0.8 0.2]; % Verde
        elseif cambio_precio(i) < 0
            colores_volumen(i, :) = [0.8 0.2 0.2]; % Rojo
        else
            colores_volumen(i, :) = [0.5 0.5 0.5]; % Gris (sin cambio)
        end
    end
    
    % Dibujar barras con colores individuales
    hold on;
    for i = 1:length(volumen)
        bar(i, volumen(i), 'FaceColor', colores_volumen(i, :), 'EdgeColor', 'none');
    end
    
    % Eje Y izquierdo para volumen
    ylabel('Volumen');
    xlim([1 n]);
    
    % Crear segundo eje Y para VIX
    yyaxis right;
    vix = vix(:);
    plot(x, vix, 'LineWidth', 1.5, 'Color', [0.8 0.2 0.8], 'DisplayName', 'VIX');
    ylabel('VIX');
    ax = gca;
    ax.YAxis(2).Color = [0.8 0.2 0.8]; % Color del eje Y derecho igual al VIX
    
    xlabel('Día');
    grid on;
    
    % Ajustar el tamaño de la ventana
    set(gcf, 'Position', [100, 100, 1000, 700]);
end