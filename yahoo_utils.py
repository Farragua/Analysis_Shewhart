"""Utilidades compartidas de descarga/lectura de CSVs de Yahoo Finance.

Réplica 1:1 de los helpers locales que main_vYahoo.m y main_vYahoo_semanal.m
llevaban duplicados al final del fichero (ensure_yahoo_csv, yahoo_chart_to_csv,
read_yahoo_csv, countlines_local).
"""

import calendar
import math
import os
from datetime import date, datetime, time, timedelta, timezone

import numpy as np
import pandas as pd
import requests


def _fmt_g(x):
    """fprintf '%.10g' de MATLAB (NaN -> 'NaN', Inf -> 'Inf')."""
    if math.isnan(x):
        return 'NaN'
    if math.isinf(x):
        return 'Inf' if x > 0 else '-Inf'
    return '%.10g' % x


def _fmt_f0(x):
    """fprintf '%.0f' de MATLAB (NaN -> 'NaN', Inf -> 'Inf')."""
    if math.isnan(x):
        return 'NaN'
    if math.isinf(x):
        return 'Inf' if x > 0 else '-Inf'
    return '%.0f' % x


def _parse_dates(dt):
    """Réplica del bloque de conversión a datetime de los .m originales."""
    if isinstance(dt, pd.Series):
        dt = dt.to_numpy()
    if np.issubdtype(np.asarray(dt).dtype, np.datetime64):
        return pd.to_datetime(dt)
    if np.issubdtype(np.asarray(dt).dtype, np.number):
        # datenum de MATLAB (días desde 01-ene-0000) -> epoch 1899-12-30
        return pd.to_datetime(pd.Timestamp('1899-12-30') + pd.to_timedelta(np.asarray(dt, dtype=float), unit='D'))
    try:
        return pd.to_datetime(dt, format='%Y-%m-%d')
    except (ValueError, TypeError):
        return pd.to_datetime(dt)


def _norm_names(cols):
    """lower + quitar '_' y espacios (como strrep(strrep(...,'_',''),' ',''))."""
    return [str(c).lower().replace('_', '').replace(' ', '') for c in cols]


def ensure_yahoo_csv(ticker, outPath, startDateStr, endDateStr):
    # === 1) Reutilizar por CONTENIDO (chequear última fecha del CSV) ===
    if os.path.isfile(outPath):
        try:
            T = pd.read_csv(outPath)
            if T is not None and T.shape[1] >= 2 and T.shape[0] > 1:
                names = _norm_names(T.columns)
                iDate = names.index('date') if 'date' in names else 0
                dt = _parse_dates(T.iloc[:, iDate])

                dt = dt[~dt.isna()]
                if len(dt) > 0:
                    last_dt = dt.iloc[-1]

                    # Último día hábil esperado (aprox)
                    today0 = pd.Timestamp(date.today())
                    # MATLAB weekday: 1=Dom, 2=Lun, ..., 7=Sáb (isoweekday: Lun=1..Dom=7)
                    wd = (today0.isoweekday() % 7) + 1
                    if wd == 1:
                        last_expected = today0 - pd.Timedelta(days=2)
                    elif wd == 2:
                        last_expected = today0 - pd.Timedelta(days=3)
                    else:
                        last_expected = today0 - pd.Timedelta(days=1)

                    if last_dt >= last_expected:
                        print(f"[Yahoo] {ticker} CSV vigente (hasta {last_dt.strftime('%Y-%m-%d')}). Reutilizo.")
                        return
                    else:
                        print(f"[Yahoo] {ticker} CSV desactualizado (última {last_dt.strftime('%Y-%m-%d')} "
                              f"< esperada {last_expected.strftime('%Y-%m-%d')}). Refresco.")
        except Exception:
            # si falla la lectura, seguimos y descargamos
            pass

    # === 2) Descargar directamente desde /v8 (chart) y construir CSV ===
    p1 = calendar.timegm(datetime.strptime(startDateStr, '%Y-%m-%d').timetuple())
    if endDateStr is None or endDateStr == '':
        p2 = calendar.timegm((datetime.combine(date.today(), time.min) + timedelta(days=1)).timetuple())  # mañana 00:00
    else:
        p2 = calendar.timegm(datetime.strptime(endDateStr, '%Y-%m-%d').timetuple())

    yahoo_chart_to_csv(ticker, outPath, p1, p2)
    if countlines_local(outPath) <= 1:
        raise RuntimeError(f'CSV vacío tras /v8 para {ticker}')
    print(f'[Yahoo] {ticker} guardado desde /v8 chart ({countlines_local(outPath) - 1} filas).')


def yahoo_chart_to_csv(ticker, outPath, p1, p2):
    # /v8 chart → CSV Date,Open,High,Low,Close,AdjClose,Volume (AdjClose SIN espacio)
    ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123 Safari/537.36'
    tkr = ticker.replace('^', '%5E')
    url8 = (f'https://query1.finance.yahoo.com/v8/finance/chart/{tkr}?'
            f'period1={p1}&period2={p2}&interval=1d&includePrePost=false&events=div%2Csplit')

    resp = requests.get(url8, headers={'User-Agent': ua}, timeout=30)
    resp.raise_for_status()
    S = resp.json()
    if 'chart' not in S or 'result' not in S['chart'] or not S['chart']['result']:
        raise RuntimeError(f'Respuesta /v8 inválida para {ticker}.')
    R = S['chart']['result'][0]

    if 'timestamp' not in R or not R['timestamp']:
        raise RuntimeError(f'Sin timestamps en /v8 chart para {ticker}.')

    ts = np.asarray(R['timestamp'], dtype=float).ravel()
    q = R['indicators']['quote'][0]
    op = _fixlen(q.get('open'), len(ts))
    hi = _fixlen(q.get('high'), len(ts))
    lo = _fixlen(q.get('low'), len(ts))
    cl = _fixlen(q.get('close'), len(ts))
    vol = _fixlen(q.get('volume'), len(ts))
    if 'adjclose' in R['indicators'] and R['indicators']['adjclose']:
        adj = _fixlen(R['indicators']['adjclose'][0].get('adjclose'), len(ts))
    else:
        adj = cl

    # datetime(ts,'ConvertFrom','posixtime','TimeZone','UTC') con TimeZone='' (naive)
    dt = [datetime.fromtimestamp(t, tz=timezone.utc).replace(tzinfo=None) for t in ts]

    n = len(ts)
    with open(outPath, 'w') as fid:
        fid.write('Date,Open,High,Low,Close,AdjClose,Volume\n')
        for i in range(n):
            if not math.isnan(cl[i]) and dt[i] is not None:
                fid.write(f"{dt[i].strftime('%Y-%m-%d')},{_fmt_g(op[i])},{_fmt_g(hi[i])},{_fmt_g(lo[i])},"
                          f"{_fmt_g(cl[i])},{_fmt_g(adj[i])},{_fmt_f0(vol[i])}\n")


def _fixlen(v, m):
    if v is None or len(v) == 0:
        return np.full(m, np.nan)
    v = np.asarray([np.nan if x is None else x for x in v], dtype=float).ravel()
    if v.size != m:
        k = min(v.size, m)
        w = np.full(m, np.nan)
        w[:k] = v[:k]
        v = w
    return v


def read_yahoo_csv(csvPath):
    if not os.path.isfile(csvPath):
        raise FileNotFoundError(f'Archivo no encontrado: {csvPath}')
    T = pd.read_csv(csvPath)
    if T is None or T.shape[1] == 0 or T.shape[0] == 0:
        raise ValueError(f'CSV vacío o sin filas: {csvPath}')
    # Normalizar nombres (sin espacios ni guiones bajos)
    names = _norm_names(T.columns)

    # Fecha
    iDate = names.index('date') if 'date' in names else 0
    dates = _parse_dates(T.iloc[:, iDate])

    # Precio: AdjClose > Close
    iAdj = names.index('adjclose') if 'adjclose' in names else None
    iClose = names.index('close') if 'close' in names else None
    if iAdj is not None:
        y = T.iloc[:, iAdj]
    elif iClose is not None:
        y = T.iloc[:, iClose]
    else:
        y = T.iloc[:, -1]
        print(f'Warning: No se encontró AdjClose/Close en {csvPath}, usando última columna.')
    y = _to_float(y)

    # Volumen (si existe)
    iVol = names.index('volume') if 'volume' in names else None
    if iVol is None:
        volume = np.array([], dtype=float)
    else:
        volume = _to_float(T.iloc[:, iVol])

    # Limpiar y ordenar
    dates_arr = pd.DatetimeIndex(dates)
    good = (~dates_arr.isna()) & (~np.isnan(y))
    dates_arr = dates_arr[good]
    y = y[good]
    if volume.size > 0:
        volume = volume[good]
    idx = np.argsort(dates_arr.values, kind='stable')
    dates_arr = dates_arr[idx]
    close_prices = y[idx]
    if volume.size > 0:
        volume = volume[idx]

    # Columnas
    close_prices = np.asarray(close_prices, dtype=float).ravel()
    if volume.size > 0:
        volume = np.asarray(volume, dtype=float).ravel()
    return close_prices, volume, dates_arr


def _to_float(col):
    """str2double(strrep(string(y),',','.')) + double() de MATLAB."""
    v = col.to_numpy() if isinstance(col, pd.Series) else np.asarray(col)
    if v.dtype == object or np.issubdtype(v.dtype, np.str_):
        v = pd.to_numeric(pd.Series([str(x).replace(',', '.') for x in v]), errors='coerce').to_numpy()
    return np.asarray(v, dtype=float)


def countlines_local(fname):
    try:
        fid = open(fname, 'r')
    except OSError:
        return 0
    n = 0
    with fid:
        for _ in fid:
            n += 1
    return n
