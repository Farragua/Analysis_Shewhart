
% 
% function plotMediasMoviles(mm200, mm150, mm100, mm50, periodos, data, entradas_3s, entradas_2s, bloqueos, media_movil_lenta,asset,volumen)
% 
% 
%  if media_movil_lenta==150
%         media_movil_lenta=mm150;
%     elseif media_movil_lenta==100
%         media_movil_lenta=mm100;
%     elseif media_movil_lenta==200
%         media_movil_lenta=mm200;
%     else
%         fprintf("Error: media movil lenta debe ser (100, 150, 200) \n")
%  end
% 
% if nargin < 5
%     periodos = 3; % valor por defecto
% end
% 
% figure;
% clf;
% 
% % Trazado principal
% plot(1:length(data), data, 'k', 'DisplayName', 'Precio'); hold on;
% 
% plot(1:length(data), mm200, 'LineWidth', 1.5, ...
%     'Color', [0.85 0.33 0.10], 'DisplayName', 'Media Móvil 200');  % Terracota
% % plot(1:length(data), mm150, 'LineWidth', 1.5, ...
% %     'Color', [0.93 0.69 0.13], 'DisplayName', 'Media Móvil 150');  % Dorado
% plot(1:length(data), mm100, 'LineWidth', 1.5, ...
%     'Color', [0.00 0.45 0.74], 'DisplayName', 'Media Móvil 100');  % Azul
% plot(1:length(data), mm50, 'LineWidth', 1.5, ...
%     'Color', [0.47 0.67 0.19], 'DisplayName', 'Media Móvil 50');   % Verde
% 
% % Puntos -3σ
% plot(entradas_3s, data(entradas_3s), 'go', ...
%     'MarkerSize', 4, 'LineWidth', 1.2, 'DisplayName', 'Entrada < -3σ');
% 
% % Puntos entre -2σ y -3σ
% entradas_2s_unicas = setdiff(entradas_2s, entradas_3s);
% plot(entradas_2s_unicas, data(entradas_2s_unicas), 'o', ...
%     'Color', [1, 0.5, 0], 'MarkerSize', 4, 'LineWidth', 1.2, ...
%     'DisplayName', '-2σ ≥ Entrada > -3σ');
% 
% % Configuración del gráfico
% xlim([1 252*periodos]);
% xlabel('Día');
% ylabel('Precio');
% title(sprintf('Precio y señales de Shewhart (%d años) — %s', periodos, char(asset)));
% 
% legend('Location', 'northwest');
% grid on;
% 
% end
% 
function plotMediasMoviles(mm200, mm150, mm100, mm50, periodos, data, entradas_3s, entradas_2s, bloqueos, media_movil_lenta, asset, volumen, vix, entradas_2mmvix, vix_umbral)
    if media_movil_lenta == 150
        media_movil_lenta = mm150;
    elseif media_movil_lenta == 100
        media_movil_lenta = mm100;
    elseif media_movil_lenta == 200
        media_movil_lenta = mm200;
    else
        fprintf("Error: media movil lenta debe ser (100, 150, 200) \n")
    end
    
    if nargin < 5
        periodos = 3; % valor por defecto
    end
    
    figure;
    clf;
    
    % Subplot superior: Precio y medias móviles (75% de altura)
    subplot(4, 1, 1:3); % Ocupa 3/4 de la altura (75%)
    
    % Trazado principal
    plot(1:length(data), data, 'k', 'DisplayName', 'Precio'); hold on;
    plot(1:length(data), mm200, 'LineWidth', 1.5, ...
        'Color', [0.85 0.33 0.10], 'DisplayName', 'Media Móvil 200');
    plot(1:length(data), mm100, 'LineWidth', 1.5, ...
        'Color', [0.00 0.45 0.74], 'DisplayName', 'Media Móvil 100');
    plot(1:length(data), mm50, 'LineWidth', 1.5, ...
        'Color', [0.47 0.67 0.19], 'DisplayName', 'Media Móvil 50');
    
    % Puntos -3σ
    plot(entradas_3s, data(entradas_3s), 'go', ...
        'MarkerSize', 4, 'LineWidth', 1.2, 'DisplayName', 'Entrada < -3σ');
    
    % Puntos entre -2σ y -3σ
    entradas_2s_unicas = setdiff(entradas_2s, entradas_3s);
    plot(entradas_2s_unicas, data(entradas_2s_unicas), 'o', ...
        'Color', [1, 0.5, 0], 'MarkerSize', 4, 'LineWidth', 1.2, ...
        'DisplayName', '-2σ ≥ Entrada > -3σ');

    % Entradas donde el VIX > vix_umbral
    hold on;
    plot(entradas_2mmvix, data(entradas_2mmvix), 'rx', ...
        'MarkerSize', 5, 'LineWidth', 1.2, 'DisplayName', sprintf('VIX > %.2d', vix_umbral));



    % Configuración del gráfico superior
    xlim([1 252*periodos]);
    ylabel('Precio');
    title(sprintf('Precio y señales de Shewhart (%d años) — %s', periodos, char(asset)));
    legend('Location', 'northwest');
    grid on;
    
    % Subplot inferior: Volumen y VIX (25% de altura)
    subplot(4, 1, 4); % Ocupa 1/4 de la altura (25%)
    
    % Determinar colores según cambio de precio
    cambio_precio = [0; diff(data)]; % Primera barra será neutral
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
    xlim([1 252*periodos]);
    
    % Crear segundo eje Y para VIX
    yyaxis right;
    vix = vix(:);
    x = (1:length(vix))';
    plot(x, vix, 'LineWidth', 1.5, 'Color', [0.8 0.2 0.8], 'DisplayName', 'VIX');
    ylabel('VIX');
    ax = gca;
    ax.YAxis(2).Color = [0.8 0.2 0.8]; % Color del eje Y derecho igual al VIX
    
    xlabel('Día');
    grid on;
    
    % Ajustar el espaciado entre subplots
    set(gcf, 'Position', [100, 100, 1000, 700]); % Ajusta el tamaño de la ventana
end