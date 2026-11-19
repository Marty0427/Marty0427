#!/usr/bin/env bash
# Downloads the two public inputs used by backtest.py into this folder.
set -euo pipefail
cd "$(dirname "$0")"
# SPY 1-minute OHLCV, 2000-01 .. 2026-04, US/Eastern, extended hours included (filtered to 09:30-16:00)
git clone --depth 1 --filter=blob:none --sparse https://github.com/prsdro/spy _spy
git -C _spy sparse-checkout set data
cp _spy/data/candles_1m.csv.gz spy_1m.csv.gz && rm -rf _spy
# CBOE VIX daily OHLC 1990..2026-03 (mirror of cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv)
curl -sSL https://raw.githubusercontent.com/3pacs/GRID/HEAD/data/cboe_vix_history.csv -o vix_history.csv \
  || curl -sSL https://cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv -o vix_history.csv
