"""
Backtest of the "shared options bot for small accounts" (Financnik.cz, r2048):
an intraday SPY breakout system executed with slightly in-the-money 0DTE options.

Signal (Zarattini, Aziz & Barbon, "Beat the Market - An Effective Intraday
Momentum Strategy for S&P500 ETF (SPY)", 2024), which the Financnik intraday
breakout system says it is built on:

    move_d(m)  = |Close_d(m) / Open_d - 1|            (m = minute of session)
    sigma_d(m) = mean(move_{d-14..d-1}(m))            (14-day lookback, no look-ahead)
    Upper_d(m) = max(Open_d, Close_{d-1}) * (1 + band_mult * sigma_d(m))
    Lower_d(m) = min(Open_d, Close_{d-1}) * (1 - band_mult * sigma_d(m))

Execution as described for the Financnik option bot:
    * first 1-minute bar that CLOSES beyond a band (not just a touch) -> signal
    * at most one trade per day
    * long breakout -> buy slightly ITM 0DTE call; short -> slightly ITM 0DTE put
    * entry at next bar's open (bot works a limit order for ~1 minute)
    * no stop-loss; hold until just before the close (SPY options settle physically)
    * max loss = premium paid, sized by a fixed dollar / % risk budget

Option prices are MODELLED (Black-Scholes, IV taken from that day's VIX open
times a 0DTE scaling factor) because no historical 0DTE SPY option chain is
available in this environment. See README.md for the limits this implies.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict, field
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.special import ndtr

MIN_PER_YEAR = 390 * 252
SESSION = 390  # 09:30 .. 15:59 one-minute bars (bar labelled by its start time)


# --------------------------------------------------------------------------- data
def load_spy_minutes(path: Path, start: str, end: str) -> dict[str, np.ndarray]:
    """Return day x minute matrices (open, close) for regular trading hours."""
    df = pd.read_csv(path, parse_dates=["timestamp"])
    df = df[(df.timestamp >= start) & (df.timestamp < pd.Timestamp(end) + pd.Timedelta(days=1))]
    mins = df.timestamp.dt.hour * 60 + df.timestamp.dt.minute - (9 * 60 + 30)
    df = df[(mins >= 0) & (mins < SESSION)].copy()
    df["m"] = mins[(mins >= 0) & (mins < SESSION)]
    df["d"] = df.timestamp.dt.normalize()
    # keep full sessions only (drops half-days, which is what most bots do anyway)
    counts = df.groupby("d").m.agg(["min", "max", "size"])
    full = counts[(counts["min"] == 0) & (counts["max"] == SESSION - 1) & (counts["size"] >= 300)].index
    df = df[df.d.isin(full)]
    days = np.array(sorted(df.d.unique()), dtype="datetime64[ns]")
    di = pd.Index(days).get_indexer(df.d)
    O = np.full((len(days), SESSION), np.nan)
    C = np.full((len(days), SESSION), np.nan)
    V = np.zeros((len(days), SESSION))
    O[di, df.m.values] = df.open.values
    C[di, df.m.values] = df.close.values
    V[di, df.m.values] = df.volume.values
    # forward-fill missing minutes (trading halts / no prints) with last close
    C = pd.DataFrame(C).ffill(axis=1).values
    O = np.where(np.isnan(O), np.roll(C, 1, axis=1), O)
    return {"days": days, "O": O, "C": C, "V": V}


def load_vix(path: Path) -> pd.Series:
    v = pd.read_csv(path)
    v.columns = [c.lower() for c in v.columns]
    v["date"] = pd.to_datetime(v["date"])
    return v.set_index("date")["open"]


# ------------------------------------------------------------------------ pricing
def bs(S, K, T, sigma, kind, r=0.0):
    T = np.maximum(T, 1e-9)
    sd = sigma * np.sqrt(T)
    d1 = (np.log(S / K) + (r + 0.5 * sigma**2) * T) / sd
    d2 = d1 - sd
    if kind == "C":
        return S * ndtr(d1) - K * np.exp(-r * T) * ndtr(d2)
    return K * np.exp(-r * T) * ndtr(-d2) - S * ndtr(-d1)


# ------------------------------------------------------------------------ params
@dataclass
class Params:
    lookback: int = 14
    band_mult: float = 1.0
    first_minute: int = 30          # first bar allowed to signal: 30 -> 10:00 bar
    last_minute: int = 360          # no new entries after 15:30
    exit_minute: int = 388          # exit at close of 15:58 bar (1 min to expiry)
    itm: float = 0.5                # strike at least $0.50 in the money
    iv_mult: float = 1.0            # 0DTE ATM IV = iv_mult * VIX_open
    slippage: float = 0.02          # $/share paid on entry AND given up on exit
    commission: float = 0.65        # $/contract per side
    risk_mode: str = "pct"          # "pct" (compounding), "fixed" ($ risk) or "contracts" (fixed count)
    risk: float = 0.03              # 3% of equity (=$300 on $10k) or $ amount
    start_equity: float = 10_000.0
    long_only: bool = False
    random_direction: bool = False  # control experiment: same timing, coin-flip side
    require_cross: bool = False     # True: previous bar must be inside the band (a real "cross")
    fractional: bool = True         # True: fractional contracts (pure edge measurement);
                                    # False: whole contracts, like a real small account
    vwap_stop: bool = False         # variant: exit early when price crosses back through
                                    # max(band, VWAP) (long) / min(band, VWAP) (short), checked every minute
    seed: int = 0


# ---------------------------------------------------------------------- backtest
def signals(data, p: Params):
    O, C, days = data["O"], data["C"], data["days"]
    open_ = O[:, 0]
    move = np.abs(C / open_[:, None] - 1)
    out = []
    for d in range(p.lookback, len(days)):
        sigma = move[d - p.lookback:d].mean(axis=0)
        prev_close = C[d - 1, -1]
        ub = max(open_[d], prev_close) * (1 + p.band_mult * sigma)
        lb = min(open_[d], prev_close) * (1 - p.band_mult * sigma)
        rng = slice(p.first_minute, p.last_minute + 1)
        above = C[d] > ub
        below = C[d] < lb
        if p.require_cross:
            above = above & ~np.roll(above, 1)
            below = below & ~np.roll(below, 1)
        up = np.nonzero(above[rng])[0]
        dn = np.nonzero(below[rng])[0]
        iu = up[0] if len(up) else 10**9
        idn = dn[0] if len(dn) else 10**9
        if iu == idn == 10**9:
            continue
        side = 1 if iu < idn else -1
        m = p.first_minute + min(iu, idn)
        out.append((d, m, side, ub, lb))
    return out


def paper_underlying(data, lookback=14, band_mult=1.0, cost_bp=1.0):
    """Original Zarattini-Aziz-Barbon rules on the ETF itself, 1x notional:
    check at 10:00, 10:30, ... 15:30; enter on close outside the noise band;
    trailing stop = max(band, VWAP) (long) / min(band, VWAP) (short); flat at close.
    Returns a daily return series (net of cost_bp per side)."""
    O, C, V, days = data["O"], data["C"], data["V"], data["days"]
    open_ = O[:, 0]
    move = np.abs(C / open_[:, None] - 1)
    vwap = np.cumsum(C * V, axis=1) / np.maximum(np.cumsum(V, axis=1), 1)
    checks = list(range(29, SESSION - 1, 30))  # bar closing at 10:00 is index 29
    rets = {}
    for d in range(lookback, len(days)):
        sigma = move[d - lookback:d].mean(axis=0)
        prev_close = C[d - 1, -1]
        ub = max(open_[d], prev_close) * (1 + band_mult * sigma)
        lb = min(open_[d], prev_close) * (1 - band_mult * sigma)
        pos, entry, r = 0, 0.0, 0.0
        for m in checks:
            px = C[d, m]
            if pos == 1 and px < max(ub[m], vwap[d, m]):
                r += px / entry - 1 - cost_bp / 1e4; pos = 0
            elif pos == -1 and px > min(lb[m], vwap[d, m]):
                r += 1 - px / entry - cost_bp / 1e4; pos = 0
            if pos == 0:
                if px > ub[m]:
                    pos, entry = 1, px; r -= cost_bp / 1e4
                elif px < lb[m]:
                    pos, entry = -1, px; r -= cost_bp / 1e4
        if pos:
            px = C[d, -1]
            r += pos * (px / entry - 1) - cost_bp / 1e4
        rets[pd.Timestamp(days[d])] = r
    return pd.Series(rets)


def run(data, vix: pd.Series, p: Params):
    O, C, V, days = data["O"], data["C"], data["V"], data["days"]
    vwap = np.cumsum(C * V, axis=1) / np.maximum(np.cumsum(V, axis=1), 1)
    rng = np.random.default_rng(p.seed)
    equity = p.start_equity
    trades = []
    for d, m, side, ub, lb in signals(data, p):
        if p.long_only and side < 0:
            continue
        if p.random_direction:
            side = 1 if rng.random() < 0.5 else -1
        day = pd.Timestamp(days[d])
        if day not in vix.index:
            continue
        em = m + 1                       # enter at next bar's open
        if em >= p.exit_minute:
            continue
        S0 = O[d, em]
        kind = "C" if side > 0 else "P"
        K = np.floor(S0 - p.itm) if kind == "C" else np.ceil(S0 + p.itm)
        iv = p.iv_mult * vix[day] / 100
        T0 = (SESSION - em) / MIN_PER_YEAR
        prem_mid = float(bs(S0, K, T0, iv, kind))
        prem = prem_mid + p.slippage
        xm = p.exit_minute
        if p.vwap_stop:
            seg = slice(em, p.exit_minute)
            if side > 0:
                hit = np.nonzero(C[d, seg] < np.maximum(ub, vwap[d])[seg])[0]
            else:
                hit = np.nonzero(C[d, seg] > np.minimum(lb, vwap[d])[seg])[0]
            if len(hit):
                xm = em + hit[0]
        S1 = C[d, xm]
        T1 = (SESSION - 1 - xm) / MIN_PER_YEAR
        exit_mid = float(bs(S1, K, T1, iv, kind))
        exit_px = max(exit_mid - p.slippage, 0.0)
        budget = equity * p.risk if p.risk_mode == "pct" else p.risk
        cost1 = prem * 100 + p.commission
        if p.risk_mode == "contracts":
            n = p.risk
        else:
            n = budget / cost1 if p.fractional else int(budget // cost1)
        if p.risk_mode != "contracts" and n < 1 and not p.fractional:
            # buy one contract if it is within 1.5x budget, otherwise skip the day
            if cost1 <= 1.5 * budget and cost1 <= equity:
                n = 1
            else:
                continue
        pnl = n * (exit_px - prem) * 100 - n * p.commission * (2 if exit_px > 0 else 1)
        equity += pnl
        trades.append(dict(date=day.date().isoformat(), side=kind, entry_min=int(em),
                           S0=round(S0, 4), K=K, S1=round(S1, 4), vix=vix[day], premium=round(prem, 4),
                           exit=round(exit_px, 4), contracts=round(n, 3), pnl=round(pnl, 2),
                           exit_min=int(xm), ret_on_premium=round(exit_px / prem - 1, 4), equity=round(equity, 2),
                           und_ret=round(side * (S1 / S0 - 1), 6)))
        if p.risk_mode == "pct" and equity <= 1.0:  # account is gone
            break
    return pd.DataFrame(trades)


def stats(tr: pd.DataFrame, p: Params, all_days: np.ndarray) -> dict:
    if tr.empty:
        return {}
    eq = pd.concat([pd.Series([p.start_equity]), tr.equity]).reset_index(drop=True)
    dd = (eq / eq.cummax() - 1).min()
    dates = pd.to_datetime(tr.date)
    yrs = (dates.iloc[-1] - dates.iloc[0]).days / 365.25
    # daily returns on equity for Sharpe (zero on no-trade days)
    idx = pd.DatetimeIndex(all_days)
    idx = idx[(idx >= dates.iloc[0]) & (idx <= dates.iloc[-1])]
    prev_eq = tr.equity - tr.pnl
    r = pd.Series(tr.pnl.values / prev_eq.values, index=dates).reindex(idx).fillna(0.0)
    sharpe = r.mean() / r.std() * np.sqrt(252) if r.std() > 0 else np.nan
    wins = tr.pnl > 0
    return dict(
        trades=len(tr), years=round(yrs, 2), final_equity=round(tr.equity.iloc[-1], 0),
        CAGR=round(((tr.equity.iloc[-1] / p.start_equity) ** (1 / yrs) - 1) * 100, 2) if tr.equity.iloc[-1] > 0 else -100,
        max_drawdown=round(dd * 100, 2), sharpe=round(sharpe, 2),
        win_rate=round(wins.mean() * 100, 1),
        avg_win_on_premium=round(tr.ret_on_premium[wins].mean() * 100, 1),
        avg_loss_on_premium=round(tr.ret_on_premium[~wins].mean() * 100, 1),
        expectancy_on_premium=round(tr.ret_on_premium.mean() * 100, 2),
        profit_factor=round(tr.pnl[wins].sum() / -tr.pnl[~wins].sum(), 2),
        underlying_hit_rate=round((tr.und_ret > 0).mean() * 100, 1),
        avg_underlying_move_bp=round(tr.und_ret.mean() * 1e4, 2),
    )


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--spy", default="data/spy_1m.csv.gz")
    ap.add_argument("--vix", default="data/vix_history.csv")
    ap.add_argument("--start", default="2007-01-01")
    ap.add_argument("--end", default="2026-03-31")
    ap.add_argument("--out", default="results")
    ap.add_argument("--set", nargs="*", default=[], help="override Params, e.g. iv_mult=1.2")
    a = ap.parse_args()
    p = Params()
    for kv in a.set:
        k, v = kv.split("=")
        setattr(p, k, type(getattr(p, k))(v) if not isinstance(getattr(p, k), bool) else v == "True")
    data = load_spy_minutes(Path(a.spy), a.start, a.end)
    vix = load_vix(Path(a.vix))
    tr = run(data, vix, p)
    s = stats(tr, p, data["days"])
    print(json.dumps({"params": asdict(p), "stats": s}, indent=2))
    Path(a.out).mkdir(exist_ok=True)
    tr.to_csv(Path(a.out) / "trades.csv", index=False)
