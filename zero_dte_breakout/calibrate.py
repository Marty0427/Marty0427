"""Calibration against the article (r2048): the author pays ~$150-200 per slightly ITM
contract, sizes 1 contract per signal on a $10k account, and reports ~+70 % from
2024-05-17 to 2026-07-28 (+90 % to ~autumn 2026). Writes results/calibration.json."""
import json
from pathlib import Path

import numpy as np
import pandas as pd

from backtest import Params, load_spy_minutes, load_vix, run, signals, SESSION, MIN_PER_YEAR

vix = load_vix(Path("data/vix_history.csv"))
out = {}

# 1) realized vol from entry to close on signal days, as a multiple of VIX_open
full = load_spy_minutes(Path("data/spy_1m.csv.gz"), "2007-01-01", "2026-03-31")
C, O, days = full["C"], full["O"], full["days"]
ratios = []
for d, m, side, ub, lb in signals(full, Params()):
    day = pd.Timestamp(days[d]); em = m + 1
    if day not in vix.index:
        continue
    path = np.log(np.r_[O[d, em], C[d, em:389]])
    T = (SESSION - em) / MIN_PER_YEAR
    ratios.append(np.sqrt((np.diff(path) ** 2).sum() / T) / (vix[day] / 100))
r = np.array(ratios)
out["realized_over_vix_signal_days"] = dict(mean=round(r.mean(), 3), median=round(np.median(r), 3),
                                            rms=round(np.sqrt((r ** 2).mean()), 3))

# 2) strike depth x IV grid: premium paid and P&L in the author's live window, 1 contract/signal
recent = load_spy_minutes(Path("data/spy_1m.csv.gz"), "2024-03-01", "2026-03-31")
grid = []
for itm in [0.0, 0.5, 1.0]:
    for k in [0.4, 0.5, 0.6, 0.7, 0.8]:
        tr = run(recent, vix, Params(iv_mult=k, itm=itm, risk_mode="contracts", risk=1.0))
        row = dict(itm_rule=itm, iv_mult=k)
        for start in ["2024-05-17", "2025-04-01"]:
            t = tr[tr.date >= start]
            eq = 10_000 + t.pnl.cumsum()
            row[f"ret_pct_from_{start}"] = round(t.pnl.sum() / 100, 1)
            row[f"maxdd_pct_from_{start}"] = round(((eq - eq.cummax()) / eq.cummax()).min() * 100, 1)
        t = tr[tr.date >= "2024-05-17"]
        row.update(trades=len(t), median_premium_usd=round(t.premium.median() * 100),
                   avg_itm_depth=round(np.where(t.side == "C", t.S0 - t.K, t.K - t.S0).mean(), 2),
                   expectancy_on_premium=round(t.ret_on_premium.mean() * 100, 1))
        grid.append(row)
out["author_window_grid"] = grid

# 3) full history at the calibrated prices, fixed $300 risk
for k in [0.5, 0.6]:
    tr = run(full, vix, Params(iv_mult=k, risk_mode="fixed", risk=300.0))
    tr["year"] = tr.date.str[:4]
    eq = 10_000 + tr.pnl.cumsum()
    under = eq < eq.cummax()
    dates = pd.to_datetime(tr.date)
    longest, start = 0, None
    for dt, u in zip(dates, under):
        if u and start is None:
            start = dt
        if not u and start is not None:
            longest, start = max(longest, (dt - start).days), None
    if start is not None:
        longest = max(longest, (dates.iloc[-1] - start).days)
    y = tr.groupby("year").agg(pnl=("pnl", "sum"), exp=("ret_on_premium", "mean"))
    out[f"full_history_iv_{k}"] = dict(
        trades=len(tr), total_pnl=round(tr.pnl.sum()), losing_years=int((y.pnl < 0).sum()),
        max_dd_usd=round((eq - eq.cummax()).min()), longest_underwater_days=longest,
        t_stat=round(tr.ret_on_premium.mean() / tr.ret_on_premium.std() * np.sqrt(len(tr)), 2),
        expectancy_on_premium=round(tr.ret_on_premium.mean() * 100, 1),
        by_year={yr: dict(pnl=round(v.pnl), exp=round(v.exp * 100, 1)) for yr, v in y.iterrows()})

Path("results/calibration.json").write_text(json.dumps(out, indent=1))
print(json.dumps({k: v for k, v in out.items() if k != "author_window_grid"}, indent=1)[:1500])
print(pd.DataFrame(grid).to_string())
