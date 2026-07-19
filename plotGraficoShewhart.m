
%Graficar el grafico de Shewhart
function A = plotGraficoShewhart(dias,data,media, sigma )

figure
plot(1:dias, data, 'ko', 'MarkerSize', 3, 'LineStyle', 'none')
hold on

% Media en azul
yline(media, 'b-', 'LineWidth', 2, 'Label', 'Media', 'LabelHorizontalAlignment', 'left');

% Límites de advertencia (±1σ y ±2σ) en rojo discontinuo
yline(media + sigma, 'r--', 'LineWidth', 1.5, 'Label', '+1σ', 'LabelHorizontalAlignment', 'left');
yline(media - sigma, 'r--', 'LineWidth', 1.5, 'Label', '-1σ', 'LabelHorizontalAlignment', 'left');
yline(media + 2*sigma, 'r--', 'LineWidth', 1.5, 'Label', '+2σ', 'LabelHorizontalAlignment', 'left');
yline(media - 2*sigma, 'r--', 'LineWidth', 1.5, 'Label', '-2σ', 'LabelHorizontalAlignment', 'left');

% Límites de control (±3σ) en rojo sólido y grueso
yline(media + 3*sigma, 'r-', 'LineWidth', 2.5, 'Label', '+3σ', 'LabelHorizontalAlignment', 'left');
yline(media - 3*sigma, 'r-', 'LineWidth', 2.5, 'Label', '-3σ', 'LabelHorizontalAlignment', 'left');

title('Gráfico de Control de Shewhart')
xlabel('Día')
ylabel('Precio de Cierre')
grid on

% Obtener límites del eje para ubicar el texto en la esquina inferior derecha
xLimits = xlim;
yLimits = ylim;

% Crear el texto con los valores de media y sigma
texto = sprintf('Media = %.2f\nSigma = %.2f', media, sigma);

% Posicionar en esquina inferior derecha
xPos = xLimits(2) - 0.05*(xLimits(2) - xLimits(1));
yPos = yLimits(1) + 0.05*(yLimits(2) - yLimits(1));

text(xPos, yPos, texto, 'HorizontalAlignment', 'right', ...
     'VerticalAlignment', 'bottom', 'FontSize', 10, 'BackgroundColor', 'w');

hold off
end

