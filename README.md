# Capifront Guard — Free MT5 Drawdown Guard & Daily Loss Limit EA

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-MetaTrader%205%20(MT5)-green.svg)](https://capifront.com/guard)
[![Official Tool](https://img.shields.io/badge/Official-Capifront.com-blueviolet.svg)](https://capifront.com)

**Capifront Guard** is a free, lightweight, real-time risk-management Expert Advisor (EA) for **MetaTrader 5 (MT5)** desktop. It is built by the **Capifront Team** ([https://capifront.com](https://capifront.com)) to protect prop firm evaluation accounts from failing daily loss and static overall drawdown limits.

Most prop firm challenges fail because of intraday volatility during London/New York market open or high-impact news spikes (CPI, NFP). Capifront Guard monitors your real account room every second, provides visual head-up display (HUD) alerts, and automatically flattens open trades and deletes pending orders before a hard rule breach occurs.

---

## Key Features

1. **Live Daily & Overall Drawdown Tracking:**
   - Calculates your daily reference point at `00:00 broker server time` using `MathMax(opening_balance, opening_equity)` (as specified in standard simulated prop firm rules).
   - Shows exact dollar amounts: **"You can still lose today"** and **"You can still lose overall"** updated every second.
2. **Early Warning HUD & Push Alerts:**
   - When less than 40% of the daily limit remains, the panel turns amber and triggers an audible MT5 desktop alert.
   - Sends real-time mobile push notifications directly to your phone via MetaQuotes ID.
3. **Emergency Auto-Flattening (Breach Protection):**
   - Automatically closes all open positions and cancels pending orders when your safety buffer (default: 15% remaining of daily limit) is reached.
4. **Lot Size & Risk Calculator:**
   - Input your desired risk percentage and stop-loss in pips on the chart panel to instantly calculate proper position sizing for Gold (XAUUSD), Indices (US30, NAS100), and Forex.
5. **Built for MT5 Prop Firm Challenges:**
   - 100% compliant with simulated prop firm evaluations. Guard never opens trades; it only manages risk, monitors drawdown floors, and protects your capital.
   - Optimized for MetaTrader 5 on broker demo servers (e.g., `JustMarkets-Demo6`).

---

## Installation in 2 Minutes

1. Download **`CapifrontGuard.ex5`** (compiled executable) or **`CapifrontGuard.mq5`** (source code) from this repository.
2. In MetaTrader 5, click **File → Open Data Folder**.
3. Navigate to **`MQL5 → Experts`** and paste `CapifrontGuard.ex5` (or `CapifrontGuard.mq5`).
4. In MT5, open the **Navigator** panel (`Ctrl + N`), right-click **Expert Advisors**, and click **Refresh**.
5. Drag **CapifrontGuard** onto any single chart.
6. In the settings dialog:
   - Check **"Allow Algo Trading"**.
   - Under the **Inputs** tab, choose your challenge plan (One-Step, Two-Step, Pro, or Instant) and enter your account size (e.g., `10000` or `100000`).
7. Ensure the **Algo Trading** button in the MT5 top toolbar is **ON (Green)**. Keep MT5 running while you trade.

---

## Settings & Inputs

| Parameter | Default | Description |
| :--- | :--- | :--- |
| **Plan and Phase** | One-Step | Sets standard rules: 5% daily / 10% overall static loss (6% / 12% on Capifront Pro). |
| **Account Size** | `0` (auto) | Initial challenge size (e.g. 10000). Leave `0` for auto-detection or set manually. |
| **Close All Trades Before Limit** | `true` | Emergency auto-close. Can be disabled if you only want alerts. |
| **Auto-Close Buffer Threshold** | `15%` | Closes positions when 15% of daily limit remains ($75 on a $10K account). |
| **Early Warning Threshold** | `40%` | Triggers alert when 40% of daily limit remains ($200 on a $10K account). |
| **Push Notifications** | `true` | Delivers mobile alerts to MetaTrader on iOS/Android. |
| **Default Risk / Stop-Loss** | `1% / 20 pips` | Baseline values for the on-chart lot size calculator. |

---

## About Capifront

**Capifront** ([https://capifront.com](https://capifront.com)) is a simulated proprietary trading firm offering MT5 evaluation challenges starting from **$9** for a **$3,000** Two-Step account up to **$200,000**, with:
- **100% Static Overall Drawdown** (Drawdown floor never trails up into your open floating profits).
- **No Consistency Rule** (No best-day profit limits or volume dilution requirements).
- **Up to 90% Profit Split** with bi-weekly performance rewards.
- Full support for Expert Advisors (EAs), swing trading, and overnight holding.

*(Note: All Capifront accounts are simulated demo environments with virtual funds. Capifront is not a broker and does not provide financial advisory services).*

- **Official Download & Documentation:** [https://capifront.com/guard](https://capifront.com/guard)
- **Prop Firm Trading Rules:** [https://capifront.com/trading-rules](https://capifront.com/trading-rules)
- **Challenge Pricing:** [https://capifront.com/pricing](https://capifront.com/pricing)

---

## License

This project is licensed under the MIT License.
