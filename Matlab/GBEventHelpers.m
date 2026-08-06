classdef GBEventHelpers
% Helper estático para los backtests Event-Driven (Golden Butterfly)

methods(Static)
    function [TT, ok] = load_yahoo_5(basePath)
        ok = false;
        fp_spy = fullfile(basePath,'SPY_yahoo.csv');
        fp_iwm = fullfile(basePath,'IWM_yahoo.csv');
        fp_gld = fullfile(basePath,'GLD_yahoo.csv');
        fp_tlt = fullfile(basePath,'TLT_yahoo.csv');
        fp_shy = fullfile(basePath,'SHY_yahoo.csv');
        need = {fp_spy, fp_iwm, fp_gld, fp_tlt, fp_shy};
        for k=1:numel(need), if ~isfile(need{k}), return; end, end
        ok = true;

        [spy, d_spy] = GBEventHelpers.read_yahoo_csv(fp_spy);
        [iwm, d_iwm] = GBEventHelpers.read_yahoo_csv(fp_iwm);
        [gld, d_gld] = GBEventHelpers.read_yahoo_csv(fp_gld);
        [tlt, d_tlt] = GBEventHelpers.read_yahoo_csv(fp_tlt);
        [shy, d_shy] = GBEventHelpers.read_yahoo_csv(fp_shy);

        TT = synchronize( ...
            timetable(d_spy, spy, 'VariableNames', {'SPY'}), ...
            timetable(d_iwm, iwm, 'VariableNames', {'IWM'}), ...
            timetable(d_gld, gld, 'VariableNames', {'GLD'}), ...
            timetable(d_tlt, tlt, 'VariableNames', {'TLT'}), ...
            timetable(d_shy, shy, 'VariableNames', {'SHY'}), ...
            'intersection');
        TT = rmmissing(TT);
    end

    function mes_idx = month_indices(dates_all, s, periodos)
        fechas_mens = dateshift(dates_all(s),'start','month',0:(periodos*12-1));
        fechas_mens = fechas_mens(fechas_mens <= dates_all(end));
        mes_idx = zeros(numel(fechas_mens),1);
        for k=1:numel(fechas_mens)
            [~, ii] = min(abs(dates_all - fechas_mens(k)));
            mes_idx(k) = ii;
        end
        mes_idx = unique(mes_idx,'stable');
    end

    function [idx3s, idx2s, media, sigma_t, tasa_pct, z] = shewhart_tasa_const(precios)
        precios = precios(:); N = numel(precios);
        if N < 3, idx3s=[]; idx2s=[]; media=NaN; sigma_t=NaN; tasa_pct=[]; z=NaN(N,1); return; end
        tasa_pct = diff(precios) ./ precios(1:end-1) * 100;
        media    = mean(tasa_pct, 'omitnan');
        RM       = abs(diff(tasa_pct));
        sigma_t  = mean(RM, 'omitnan') / 1.128;
        if ~isfinite(sigma_t) || sigma_t <= 0, sigma_t = NaN; end
        z = NaN(N,1); if isfinite(sigma_t), z(2:end) = (tasa_pct - media) / sigma_t; end
        if isfinite(sigma_t)
            idx3s = find(tasa_pct <= (media - 3*sigma_t)) + 1;
            idx2s = find(tasa_pct <= (media - 2*sigma_t)) + 1;
        else
            idx3s = []; idx2s = [];
        end
    end

    function r = solve_irr(fun)
        a=-0.999; b=10; Fa=fun(a); Fb=fun(b);
        if isfinite(Fa)&&isfinite(Fb)&&sign(Fa)~=sign(Fb), r=fzero(fun,[a b]); return; end
        guesses=[-0.9 -0.5 -0.2 0 0.05 0.1 0.2 0.4 0.8 1 2 5];
        for g=guesses
            try, rr=fzero(fun,g); if isfinite(rr), r=rr; return; end
            catch, end
        end
        obj=@(x) abs(fun(x)); r=fminbnd(obj,-0.99,10);
    end

    function s = iff(cond, a, b)
        if cond, s = a; else, s = b; end
    end

    function [close_prices, dates] = read_yahoo_csv(csvPath)
        T = readtable(csvPath);
        if isempty(T) || width(T)==0 || height(T)==0, error('CSV vacío o sin filas: %s', csvPath); end
        names = lower(strrep(strrep(T.Properties.VariableNames,'_',''),' ','')); 
        iDate = find(strcmp(names,'date'),1); if isempty(iDate), iDate = 1; end
        dates = T{:,iDate};
        if ~isdatetime(dates)
            if isnumeric(dates), dates = datetime(dates,'ConvertFrom','datenum');
            elseif iscellstr(dates) || isstring(dates)
                try, dates = datetime(dates,'InputFormat','yyyy-MM-dd','Locale','en_US'); catch, dates = datetime(dates); end
            else, dates = datetime(dates);
            end
        end
        iAdj   = find(strcmp(names,'adjclose'),1);
        iClose = find(strcmp(names,'close'),1);
        if ~isempty(iAdj), y = T{:,iAdj};
        elseif ~isempty(iClose), y = T{:,iClose};
        else, y = T{:,end}; warning('No AdjClose/Close en %s', csvPath);
        end
        if iscellstr(y) || isstring(y), y = str2double(strrep(string(y),',','.')); end
        if ~isfloat(y), y = double(y); end
        good = ~isnat(dates) & ~isnan(y);
        [dates, idx] = sort(dates(good)); close_prices = y(good); close_prices = close_prices(idx);
        close_prices = close_prices(:); dates = dates(:);
    end
end
end
