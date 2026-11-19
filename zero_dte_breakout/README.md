# 0DTE SPY breakout bot: a rebuild and backtest

This rebuilds and backtests the strategy from Finančník.cz, *"Sdílený opční bot pro malé účty: přes 50 % za posledních 12 měsíců"* (r2048), on SPY 1-minute data from 2007-01 to 2026-03 (4,804 sessions).

**Verdict:** the signal has a real but small edge on SPY. Once you buy 0DTE options to trade it and **hold to the close**, the edge disappears at any realistic option price. In the base case (IV = 0.7 × VIX) the strategy loses **-4.9 % of premium per trade** over 3,459 trades from 2007 to 2026. It loses money in 16 of 20 years and wipes out a 3 %-risk account. It makes money only if 0DTE options are priced **below the volatility SPY actually delivered**, and they aren't.

## 1. What the strategy is

The article's rules sit behind the Trading Room paywall, and the site can't be reached from the backtest machine. I rebuilt the rules from the author's public articles (r1995, r1996, r1999, r2036, r2046, r2048):

| Element | Author's description | What this backtest does |
|---|---|---|
| Signal | Intraday breakout on SPY/QQQ from a pre-calculated level. Based on Zarattini, Aziz & Barbon, *"Beat the Market – An Effective Intraday Momentum Strategy for SPY"* | The paper's "noise area": `UB = max(Open, PrevClose)·(1+σ_m)`, `LB = min(Open, PrevClose)·(1−σ_m)`. Here `σ_m` is the 14-day mean of `|Close_m/Open − 1|` at the same minute of the session |
| Trigger | A 1-minute bar must **close** beyond the level; a touch is not enough | The first 1-min close outside the band between 10:00 and 15:30 |
| Trades per day | One | One |
| Instrument | Buy a slightly ITM 0DTE call (long) or put (short) | Strike at least $0.50 ITM (variant: $2 ITM) |
| Entry | Limit order worked for about 1 minute | Next bar's open, plus $0.02/share slippage, plus $0.65/contract commission |
| Exit | No stop. Hold, and close just before the end of the session (SPY options settle physically) | Exit at the 15:58 bar close, minus $0.02 slippage |
| Risk | Premium = max loss. About $300/trade on $10k. One contract costs about $150–200 | 3 % of equity per trade (compounding), and also a fixed $300 version |

`backtest.py` holds the model and `analysis.py` reproduces every number below.

## 2. About "survivorship bias" for this strategy

This strategy trades **the index ETF itself** (SPY, and QQQ for the author), not a basket of stocks picked from the index. The SPY price series already contains every company that was in the S&P 500 on each historical day, including the ones later dropped, bankrupt or acquired. Survivorship bias would only matter if you rebuilt the index from *today's* members. Here we use the actual tape of the traded ETF, so the bias is not present.

Two related biases do apply, and are addressed as follows:

* **Hindsight choice of market.** SPY and QQQ were picked after a 15-year bull market. Every result here covers all of 2007–2026, including 2008, 2020 and 2022. A **random-direction control** uses the same entry times and the same options. It separates the effect of the signal from the effect of just being long.
* **Selection of the reporting window.** "+50 % over the last 12 months" is one hand-picked window from one account. The full-period, year-by-year table below shows how unrepresentative such a window can be.

QQQ was not tested: no long QQQ 1-minute history was reachable from this environment. `backtest.py` accepts any 1-minute file in the same format.

## 3. Data

* **SPY 1-minute OHLCV**, 2000–2026, unadjusted. Source: the public repo `prsdro/spy` (`data/candles_1m.csv.gz`). Filtered to 09:30–16:00 ET full sessions. Includes real halts (e.g. the 2020-03-16 circuit breaker).
* **CBOE VIX daily** (that day's open is used, so there is no look-ahead).
* `data/fetch_data.sh` downloads both files.

**Main limitation.** There is no historical 0DTE option-chain data here (OptionsDX, CBOE DataShop and Polygon are paid or unreachable). Option prices are **modelled** with Black-Scholes, using IV = `iv_mult × VIX_open`. Daily SPY expirations only exist since **2022-11-14**; before that, M/W/F expiries existed from about 2016. Pre-2022 results are therefore a "what if 0DTE had existed" test of the signal plus option payoff. Section 6 shows the real-0DTE era separately.

### How expensive are 0DTE options? (the assumption that decides the result)

* Measured from SPY 1-minute returns: **realized** volatility from the entry minute to the close averaged **0.54 × VIX (median) / 0.72 × VIX (RMS)**. VIX includes overnight risk and a volatility risk premium, so intraday realized vol is lower.
* The market does not sell options at realized vol. The volatility risk premium, which makes buying options a losing trade on average, is well documented for 0DTE as well.
* The author's own price check is "one slightly ITM contract costs about $150–200". In the model, the median modelled premium in 2024–26 is **$181 at 0.5×, $200 at 0.7× and $246 at 1.0× VIX**.

The base case is therefore **IV = 0.7 × VIX**: about realized vol plus a small premium, which is generous to the strategy. The full range is shown below.

## 4. Results, full period 2007-01 → 2026-03 (3,459 trades)

### How the option price assumption changes the edge

![IV sensitivity](results/iv_sensitivity.png)

| IV / VIX | Avg return on premium per trade | Win rate | Profit factor | CAGR (3 % risk) | Max DD |
|---|---|---|---|---|---|
| 0.5 (options *cheaper* than realized vol) | **+7.7 %** | 45 % | 1.18 | +31.6 % | -84 % |
| 0.6 (≈ realized, no risk premium) | +1.1 % | 43 % | 0.98 | -6.6 % | -98 % |
| **0.7 (base)** | **-4.9 %** | 42 % | 0.94 | -31 % | -100 % |
| 0.8 | -9.7 % | 39 % | 0.89 | -46 % | -100 % |
| 1.0 (priced at VIX) | -14.7 % | 37 % | 0.76 | -59 % | -100 % |

Breakeven needs options priced at about 0.6 × VIX, which is roughly zero volatility premium. Even at 0.5×, a 3 %-risk account would have had an **-84 % drawdown**, because the strategy loses for long stretches (2009–2017).

![Equity curves](results/equity_curves.png)

### Robustness, base IV = 0.7 × VIX

| Variant | Return on premium per trade | Profit factor | Underlying hit rate |
|---|---|---|---|
| Base | -4.9 % | 0.94 | 51.9 % |
| **Random direction, same entry times (control)** | -10.0 % | 0.81 | 48.8 % |
| Long calls only | -5.6 % | 0.85 | 57.4 % |
| Require a fresh cross (prior bar inside band) | -5.7 % | 0.92 | 50.6 % |
| Signals allowed from 09:31 | -5.1 % | 0.95 | 51.4 % |
| Wider band (1.5 σ) | -2.8 % | 0.93 | 52.6 % |
| Deeper ITM ($2) | -0.5 % | 0.95 | 51.9 % |
| Slippage $0.05/share | -9.6 % | 0.88 | 50.4 % |
| **Zero costs** | -2.1 % | 0.98 | 51.9 % |
| Paper's VWAP/band trailing exit instead of holding | -1.5 % | 0.65 | 22.9 % |

The signal beats random direction by about 5 % of premium per trade, so it carries some information. That is not enough to cover the options' time decay, even with zero transaction costs. Every variant is negative.

### Year by year (fixed $300 risk/trade, non-compounding, as in the author's own backtests)

Total over 19 years: **-$59,907** on 3,459 trades.

| Year | Trades | P&L | Win % | Return on premium per trade |
|---|---|---|---|---|
| 2007 | 175 | +2,575 | 48 | +6.1 % |
| 2008 | 190 | **+11,268** | 51 | +20.9 % |
| 2009 | 178 | -6,310 | 39 | -10.8 % |
| 2010 | 179 | -6,276 | 41 | -10.6 % |
| 2011 | 193 | -3,235 | 46 | -4.5 % |
| 2012 | 177 | -5,547 | 41 | -9.4 % |
| 2013 | 185 | -3,467 | 42 | -5.1 % |
| 2014 | 190 | -5,097 | 41 | -7.9 % |
| 2015 | 189 | -1,520 | 49 | -1.6 % |
| 2016 | 178 | -6,632 | 39 | -11.5 % |
| 2017 | 173 | -7,345 | 35 | -13.1 % |
| 2018 | 189 | +5,372 | 45 | +10.4 % |
| 2019 | 165 | -9,070 | 36 | -17.5 % |
| 2020 | 170 | -6,669 | 36 | -12.5 % |
| 2021 | 164 | -8,676 | 38 | -17.1 % |
| 2022 | 182 | +6,341 | 45 | +12.2 % |
| 2023 | 193 | -1,885 | 43 | -2.6 % |
| 2024 | 181 | -7,930 | 37 | -14.0 % |
| 2025 | 164 | -2,400 | 42 | -4.4 % |
| 2026 Q1 | 44 | -3,406 | 32 | -25.5 % |

It wins only in big trending-volatility years (2008, 2018, 2022). That pattern fits buying options: you need realized moves larger than the market priced in.

## 5. Is the signal itself real? (replicating the paper on the ETF)

The paper's original rules, traded on the SPY ETF at 1× notional: checks every 30 minutes, a VWAP/band trailing stop, flat at the close.

| | CAGR | Sharpe | Max DD |
|---|---|---|---|
| Gross | 9.6 % | **1.24** | -11.6 % |
| Net of 1 bp per side | 4.4 % | 0.60 | -17.2 % |

That is close to the paper's reported unlevered Sharpe (≈1.3), so the signal code is right. The edge comes mainly from the **trailing stop cutting losers**. The bot as described holds to the close, and that version's edge on the underlying is only **+2.3 bp/trade (t = 1.55, not significant)**.

## 6. The author's claimed window and the real-0DTE era

| Window | IV/VIX | Sizing | Trades | End equity from $10k | Max DD |
|---|---|---|---|---|---|
| 0DTE era 2022-11 → 2026-03 | 0.5 | whole contracts | 603 | $40,316 | -38 % |
| 0DTE era 2022-11 → 2026-03 | **0.7** | whole contracts | 371 | **$3,227** | -68 % |
| Last 12 m (2025-04 → 2026-03) | 0.5 | whole contracts | 170 | $10,982 | -37 % |
| Last 12 m (2025-04 → 2026-03) | **0.7** | whole contracts | 157 | **$6,384** | -59 % |
| Author's live period (2024-05-17 → 2026-03) | 0.5 | whole contracts | 322 | $14,031 | -34 % |
| Author's live period (2024-05-17 → 2026-03) | **0.7** | whole contracts | 134 | **$3,617** | -64 % |

(In the whole-contract rows, the trade count drops once a shrinking $10k account can't afford a contract within 1.5× the risk budget.)

The rebuild **does not reproduce** "+50 % in 12 months" or "+70 % since 2024-05-17" under any realistic pricing. Possible reasons:

1. **Rules differ from this rebuild.** The private bot may use a different level, filters, time windows or exits, or trade QQQ as well. Without the Trading Room code, this tests the *published* logic, not the exact bot.
2. **One account, one path.** A single live track record of about 1 year, with about 150 trades whose payoffs are heavily skewed, has a very wide confidence interval. A few large trend days can make the year.
3. **Model error.** Real 0DTE IV has an intraday pattern and skew, and IV expands on breakout days. A breakout entry pays the ask on a vol spike. That mostly works *against* the buyer, so the model is more likely generous than harsh.

## 7. What would make this test definitive

* Run `backtest.py` on **real 0DTE SPY/QQQ quotes** (CBOE DataShop, OptionsDX, Polygon/Massive or ThetaData), from 2022-11 for daily expiries. Only the pricing lines in `run()` need replacing.
* Get the exact Trading Room rules and code. Swap them into `signals()`.
* Add QQQ 1-minute data. The code is ticker-agnostic.

## Reproduce

```bash
pip install pandas numpy scipy matplotlib
./data/fetch_data.sh
python3 backtest.py --set iv_mult=0.7          # single run, prints stats, writes results/trades.csv
python3 analysis.py                             # every table and chart in this README
```

Sources: [article r2048](https://www.financnik.cz/clanky/praxe/sdileny-opcni-bot-pro-male-ucty-pres-50-za-poslednich-12-mesicu-r2048), [0DTE breakout r1995](https://www.financnik.cz/clanky/praxe/day-trading-breakoutu-s-0tde-opcemi---extra-paka-s-limitovanym-riskem-r1995), [shorting via 0DTE r1996](https://www.financnik.cz/clanky/praxe/shortovani-breakoutu-skrz-0tde-opce---316-zisk-na-obchod-r1996), [ETF vs options vs e-mini r1999](https://www.financnik.cz/clanky/praxe/obchodovani-intradennich-breakoutu---etf-vs-opce-vs-e-mini-futures-r1999/), [+70 % on 0DTE r2046](https://www.financnik.cz/clanky/praxe/zhodnoceni-pres-70-na-malem-uctu-s-0dte-opcemi-zkusenosti-z-automatickeho-obchodovani-r2046). Zarattini, Aziz & Barbon (2024), *Beat the Market: An Effective Intraday Momentum Strategy for S&P500 ETF (SPY)*, SSRN 4824172.
