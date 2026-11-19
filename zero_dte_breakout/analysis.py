"""Runs the full set of experiments for README.md and writes tables + charts to results/."""
from __future__ import annotations

import json
from dataclasses import replace, asdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from backtest import Params, load_spy_minutes, load_vix, run, stats

OUT = Path("results")
OUT.mkdir(exist_ok=True)
BLUE, ORANGE, AQUA, GRAY = "#2a78d6", "#eb6834", "#1baf7a", "#8a8984"

data = load_spy_minutes(Path("data/spy_1m.csv.gz"), "2007-01-01", "2026-03-31")
vix = load_vix(Path("data/vix_history.csv"))
BASE = Params(iv_mult=0.7)


def subset(data, start, end):
    m = (data["days"] >= np.datetime64(start)) & (data["days"] <= np.datetime64(end))
    # keep 14-day warm-up before start
    i0 = max(np.argmax(m) - 20, 0)
    i1 = len(m) - np.argmax(m[::-1])
    return {k: v[i0:i1] for k, v in data.items()}, start


def go(p, d=data, start=None):
    tr = run(d, vix, p)
    if start is not None and not tr.empty:
        tr = tr[tr.date >= start]
        if not tr.empty:  # rebase equity to the window
            tr = tr.copy()
            if p.risk_mode == "pct":
                eq = p.start_equity * np.cumprod(1 + tr.pnl.values / (tr.equity - tr.pnl).values)
                tr["pnl"] = np.diff(np.r_[p.start_equity, eq])
                tr["equity"] = eq
            else:
                tr["equity"] = p.start_equity + tr.pnl.cumsum()
    return tr, stats(tr, p, d["days"])


BASE_NAME = "base (IV=0.7xVIX, 3% risk, 10:00-15:30, both sides)"
results = {}

# 0) replication check: the paper's original rules on the ETF itself
from backtest import paper_underlying
rep = {}
for c in [0.0, 1.0]:
    r = paper_underlying(data, cost_bp=c)
    eq = (1 + r).cumprod()
    rep[f"cost_{c}bp_per_side"] = dict(CAGR=round((eq.iloc[-1] ** (252 / len(r)) - 1) * 100, 2),
                                       sharpe=round(r.mean() / r.std() * np.sqrt(252), 2),
                                       max_drawdown=round((eq / eq.cummax() - 1).min() * 100, 1),
                                       by_year={str(k): round(v * 100, 1) for k, v in r.groupby(r.index.year).apply(lambda x: (1 + x).prod() - 1).items()})
results["paper_replication_etf"] = rep

# 1) IV sensitivity -- the dominant assumption
iv_rows = []
for k in [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1]:
    tr, s = go(replace(BASE, iv_mult=k))
    iv_rows.append(dict(iv_mult=k, **{x: s[x] for x in ["trades", "CAGR", "max_drawdown", "sharpe", "win_rate", "expectancy_on_premium", "profit_factor"]}))
results["iv_sensitivity"] = iv_rows

# 2) base case + controls + variants (full period 2007-2026)
variants = {
    BASE_NAME: BASE,
    "random direction (same entry times)": replace(BASE, random_direction=True),
    "long calls only": replace(BASE, long_only=True),
    "require a fresh cross": replace(BASE, require_cross=True),
    "signals from 09:31": replace(BASE, first_minute=1),
    "band x1.5": replace(BASE, band_mult=1.5),
    "deeper ITM ($2)": replace(BASE, itm=2.0),
    "slippage $0.05/share": replace(BASE, slippage=0.05),
    "no costs at all": replace(BASE, slippage=0.0, commission=0.0),
    "VWAP/band trailing exit (paper's stop)": replace(BASE, vwap_stop=True),
}
var_rows, curves = [], {}
for name, p in variants.items():
    tr, s = go(p)
    var_rows.append(dict(variant=name, **s))
    curves[name] = tr
results["variants"] = var_rows

# 3) by-year table for the base case
tr, s_fixed = go(replace(BASE, risk_mode="fixed", risk=300.0))
results["fixed_300_full_period"] = dict(total_pnl=round(tr.pnl.sum(), 0), **{k: s_fixed[k] for k in ["trades", "win_rate", "expectancy_on_premium", "profit_factor"]})
tr["year"] = tr.date.str[:4]
yr = tr.groupby("year").agg(trades=("pnl", "size"), pnl_usd=("pnl", "sum"),
                            win_rate=("pnl", lambda x: (x > 0).mean() * 100),
                            exp_on_prem=("ret_on_premium", lambda x: x.mean() * 100),
                            und_hit=("und_ret", lambda x: (x > 0).mean() * 100)).round(1)
results["by_year"] = yr.reset_index().to_dict("records")

# 4) windows: real daily-0DTE era and the article's "last 12 months"
win_rows = []
for label, a, b in [("0DTE era 2022-11-14..2026-03-31", "2022-11-14", "2026-03-31"),
                    ("last 12 months 2025-04-01..2026-03-31", "2025-04-01", "2026-03-31"),
                    ("2024-05-17..2026-03-31 (author's live account period)", "2024-05-17", "2026-03-31")]:
    for k in [0.5, 0.7, 0.9]:
        d, st = subset(data, a, b)
        for frac in [True, False]:
            p = replace(BASE, iv_mult=k, fractional=frac)
            t, s = go(p, d, st)
            win_rows.append(dict(window=label, iv_mult=k, sizing="fractional" if frac else "whole contracts, $10k",
                                 **{x: s.get(x) for x in ["trades", "final_equity", "CAGR", "max_drawdown", "sharpe", "win_rate", "expectancy_on_premium"]}))
results["windows"] = win_rows

# 5) the signal on the underlying itself (ETF, 1x, hold to close) -- is there any edge to monetise?
und = tr
results["underlying_signal"] = dict(trades=len(und), hit_rate=round((und.und_ret > 0).mean() * 100, 1),
                                    avg_bp=round(und.und_ret.mean() * 1e4, 2),
                                    t_stat=round(und.und_ret.mean() / und.und_ret.std() * np.sqrt(len(und)), 2),
                                    total_compounded_pct=round((np.prod(1 + und.und_ret) - 1) * 100, 1))

(OUT / "results.json").write_text(json.dumps(results, indent=2, default=str))

# ---------------------------------------------------------------- charts
plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False,
                     "axes.edgecolor": GRAY, "axes.grid": True, "grid.color": "#e6e5e0", "grid.linewidth": 0.6})

fig, ax = plt.subplots(figsize=(9, 4.6), dpi=150)
for name, col in [(BASE_NAME, BLUE),
                  ("random direction (same entry times)", GRAY),
                  ("no costs at all", ORANGE)]:
    t = curves[name]
    ax.plot(pd.to_datetime(t.date), t.equity, lw=1.6, color=col, label=name)
iv5 = go(replace(BASE, iv_mult=0.5))[0]
ax.plot(pd.to_datetime(iv5.date), iv5.equity, lw=1.6, color=AQUA, label="IV=0.5xVIX (options cheaper than realized vol; unrealistic)")
ax.set_yscale("log")
ax.set_ylabel("Account equity, $ (log scale)")
ax.set_title("SPY noise-band breakout via slightly ITM 0DTE options, $10k start, 3% premium risk/trade", loc="left", fontsize=10.5)
ax.legend(frameon=False, fontsize=8.5, loc="lower left")
fig.tight_layout()
fig.savefig(OUT / "equity_curves.png")

fig, ax = plt.subplots(figsize=(7, 3.6), dpi=150)
iv = pd.DataFrame(iv_rows)
ax.bar(iv.iv_mult.astype(str), iv.expectancy_on_premium, color=[AQUA if v > 0 else ORANGE for v in iv.expectancy_on_premium], width=0.6)
ax.axhline(0, color="#52514e", lw=0.8)
for x, v in zip(iv.iv_mult.astype(str), iv.expectancy_on_premium):
    ax.annotate(f"{v:+.1f}%", (x, v), ha="center", va="bottom" if v > 0 else "top", fontsize=8.5, xytext=(0, 2 if v > 0 else -2), textcoords="offset points")
ax.set_xlabel("Assumed 0DTE implied vol as a multiple of VIX")
ax.set_ylabel("Avg return on premium per trade")
ax.set_title("Edge per trade vs. how expensive the options are (2007-2026)", loc="left", fontsize=10.5)
fig.tight_layout()
fig.savefig(OUT / "iv_sensitivity.png")
print(json.dumps(results, indent=1, default=str))
