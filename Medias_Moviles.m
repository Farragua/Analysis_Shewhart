function [mm200, mm150, mm100, mm50] = Medias_Moviles(datamm, data)

% data son los datos que queremos tratar
% datamm son los datos + 150 periodos atras para poder calcular la mm150
mm200 = NaN(size(data));
mm150 = NaN(size(data));
mm100 = NaN(size(data));
mm50 = NaN(size(data));


for i = 201:length(datamm)
    mm200(i) = mean(datamm(i-200:i));
end

for i = 151:length(datamm)
    mm150(i) = mean(datamm(i-150:i));
end

mm150 = mm150(end-(size(data,1)-1):end); %Coger los ultimos size(data,1) elementos

for i = 101:length(datamm)
    mm100(i) = mean(datamm(i-100:i));
end

mm100 = mm100(end-(size(data,1)-1):end); %Coger los ultimos size(data,1) elementos

for i = 51:length(datamm)
    mm50(i) = mean(datamm(i-50:i));
end

mm50 = mm50(end-(size(data,1)-1):end); %Coger los ultimos 251 elementos


% elimina los NaN
mm200 = mm200(~isnan(mm200));
mm150 = mm150(~isnan(mm150));
mm100 = mm100(~isnan(mm100));
mm50 = mm50(~isnan(mm50));

