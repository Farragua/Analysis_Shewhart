"""Helper estático para los backtests Event-Driven (Golden Butterfly)."""

import os
import sys

import numpy as np
import pandas as pd
from scipy.optimize import brentq, minimize_scalar, newton


class GBEventHelpers:
    """Helper estático para los backtests Event-Driven (Golden Butterfly)."""

    @staticmethod
    def load_yahoo_5(basePath):
        ok = False
        fp_spy = os.path.join(basePath, 'SPY_yahoo.csv')
        fp_iwm = os.path.join(basePath, 'IWM_yahoo.csv')
        fp_gld = os.path.join(basePath, 'GLD_yahoo.csv')
        fp_tlt = os.path.join(basePath, 'TLT_yahoo.csv')
        fp_shy = os.path.join(basePath, 'SHY_yahoo.csv')
        need = [fp_spy, fp_iwm, fp_gld, fp_tlt, fp_shy]
        for k in range(len(need)):
            if not os.path.isfile(need[k]):
                return None, ok
        ok = True

        spy, d_spy = GBEventHelpers.read_yahoo_csv(fp_spy)
        iwm, d_iwm = GBEventHelpers.read_yahoo_csv(fp_iwm)
        gld, d_gld = GBEventHelpers.read_yahoo_csv(fp_gld)
        tlt, d_tlt = GBEventHelpers.read_yahoo_csv(fp_tlt)
        shy, d_shy = GBEventHelpers.read_yahoo_csv(fp_shy)

        TT = pd.concat([
            pd.Series(spy, index=d_spy, name='SPY'),
            pd.Series(iwm, index=d_iwm, name='IWM'),
            pd.Series(gld, index=d_gld, name='GLD'),
            pd.Series(tlt, index=d_tlt, name='TLT'),
            pd.Series(shy, index=d_shy, name='SHY'),
        ], axis=1, join='inner')
        TT = TT.dropna()
        return TT, ok

    @staticmethod
    def month_indices(dates_all, s, periodos):
        fechas_mens = pd.date_range(
            start=pd.Timestamp(dates_all[s - 1]).replace(day=1),
            periods=(periodos * 12 - 1) + 1,
            freq='MS')
        fechas_mens = fechas_mens[fechas_mens <= dates_all[-1]]
        mes_idx = np.zeros(len(fechas_mens))
        for k in range(1, len(fechas_mens) + 1):
            ii = int(np.argmin(np.abs(dates_all - fechas_mens[k - 1]))) + 1
            mes_idx[k - 1] = ii
        mes_idx = pd.unique(mes_idx)
        return mes_idx

    @staticmethod
    def shewhart_tasa_const(precios):
        precios = np.asarray(precios, dtype=np.float64).ravel()
        N = len(precios)
        if N < 3:
            idx3s = np.array([])
            idx2s = np.array([])
            media = np.nan
            sigma_t = np.nan
            tasa_pct = np.array([])
            z = np.full(N, np.nan)
            return idx3s, idx2s, media, sigma_t, tasa_pct, z
        tasa_pct = np.diff(precios) / precios[:-1] * 100
        media = np.nanmean(tasa_pct)
        RM = np.abs(np.diff(tasa_pct))
        sigma_t = np.nanmean(RM) / 1.128
        if not np.isfinite(sigma_t) or sigma_t <= 0:
            sigma_t = np.nan
        z = np.full(N, np.nan)
        if np.isfinite(sigma_t):
            z[1:] = (tasa_pct - media) / sigma_t
        if np.isfinite(sigma_t):
            # find(...) + 1 en MATLAB: flatnonzero (0-based) + 1 (find 1-based) + 1 (el +1 del código)
            idx3s = (np.flatnonzero(tasa_pct <= (media - 3 * sigma_t)) + 1) + 1
            idx2s = (np.flatnonzero(tasa_pct <= (media - 2 * sigma_t)) + 1) + 1
        else:
            idx3s = np.array([])
            idx2s = np.array([])
        return idx3s, idx2s, media, sigma_t, tasa_pct, z

    @staticmethod
    def solve_irr(fun):
        a = -0.999
        b = 10
        Fa = fun(a)
        Fb = fun(b)
        if np.isfinite(Fa) and np.isfinite(Fb) and np.sign(Fa) != np.sign(Fb):
            r = brentq(fun, a, b)
            return r
        guesses = [-0.9, -0.5, -0.2, 0, 0.05, 0.1, 0.2, 0.4, 0.8, 1, 2, 5]
        for g in guesses:
            try:
                rr = newton(fun, g)
                if np.isfinite(rr):
                    r = rr
                    return r
            except Exception:
                pass
        obj = lambda x: abs(fun(x))
        r = minimize_scalar(obj, bounds=(-0.99, 10), method='bounded').x
        return r

    @staticmethod
    def iff(cond, a, b):
        if cond:
            s = a
        else:
            s = b
        return s

    @staticmethod
    def read_yahoo_csv(csvPath):
        T = pd.read_csv(csvPath)
        if T.empty or T.shape[1] == 0 or T.shape[0] == 0:
            raise ValueError(f'CSV vacío o sin filas: {csvPath}')
        names = [c.replace('_', '').replace(' ', '').lower() for c in T.columns]
        iDate = next((i for i, n in enumerate(names) if n == 'date'), None)
        if iDate is None:
            iDate = 0
        dates = T.iloc[:, iDate]
        if not pd.api.types.is_datetime64_any_dtype(dates):
            if pd.api.types.is_numeric_dtype(dates):
                dates = pd.to_datetime(dates, unit='D', origin='1899-12-30')
            elif pd.api.types.is_object_dtype(dates) or pd.api.types.is_string_dtype(dates):
                try:
                    dates = pd.to_datetime(dates, format='%Y-%m-%d')
                except (ValueError, TypeError):
                    dates = pd.to_datetime(dates)
            else:
                dates = pd.to_datetime(dates)
        iAdj = next((i for i, n in enumerate(names) if n == 'adjclose'), None)
        iClose = next((i for i, n in enumerate(names) if n == 'close'), None)
        if iAdj is not None:
            y = T.iloc[:, iAdj]
        elif iClose is not None:
            y = T.iloc[:, iClose]
        else:
            y = T.iloc[:, -1]
            print(f'Warning: No AdjClose/Close en {csvPath}', file=sys.stderr)
        if pd.api.types.is_object_dtype(y) or pd.api.types.is_string_dtype(y):
            y = pd.to_numeric(
                pd.Series(y).astype(str).str.replace(',', '.', regex=False),
                errors='coerce')
        y = np.asarray(y, dtype=np.float64)
        dates = pd.DatetimeIndex(dates)
        good = dates.notna() & ~np.isnan(y)
        dates_g = dates[good]
        y_g = y[good]
        idx = np.argsort(dates_g, kind='stable')
        dates_s = dates_g[idx]
        close_prices = y_g[idx]
        close_prices = np.asarray(close_prices, dtype=np.float64).ravel()
        dates_s = pd.DatetimeIndex(dates_s)
        return close_prices, dates_s
