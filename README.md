# 📉 Drawdown Manager EA by Arjun1337

![Version](https://img.shields.io/badge/version-1.20-blue.svg)  
![Platform](https://img.shields.io/badge/platform-MetaTrader5-green.svg)

---

## 🚀 Overview

**Drawdown Manager EA** is an advanced MetaTrader 5 Expert Advisor designed to **strategically manage drawdowns by layering trades** around a manually initiated position. This EA automates pending orders (layers) to optimize average entry price, protect equity with a global stop loss, and lock in risk-free trades using dynamic breakeven logic.

Developed with a robust, scalable architecture, this EA ensures disciplined trade management aligned with professional trading objectives.

---

## 🎯 Key Features

- **Automatic Detection of Manual Trades** — Monitors for manually opened trades (magic number = 0) and takes over position management.
- **Layered Order Placement** — Multiple pending limit orders at fixed pip distances with increasing lot sizes.
- **Individual Take Profit for Each Layer** — Ensures structured exit points.
- **Per-Layer Breakeven** — When a layer reaches halfway to TP, SL moves to entry for risk-free profit locking.
- **Global Equity Stop Loss** — Calculates the price where total open position loss equals a fixed % of account equity (default 20%) and sets SL for all trades.
- **Dynamic Layer Replacement** — Replaces filled or canceled layers until the main trade is closed.
- **Clean-Up Logic** — Removes all EA orders when the main trade closes.
- **Pure MQL5 Implementation** — No external dependencies.

---

## 🧠 Algorithm Overview

1. **Manual Trade Detection**  
   Detects any manual position on the chart’s symbol with magic number 0 and sets it as `mainTicket`.

2. **Layer Placement**  
   - Places limit orders at `PipDistance` from the main trade.  
   - Lot size = `BaseLotSize × LayerNumber`.  
   - Each layer has a fixed TP distance.

3. **Global Stop Loss**  
   - Calculates the price where **closing all trades** would result in `EquityRiskPercent` loss of total equity.  
   - Sets this as SL for **all positions** (manual + EA).

4. **Per-Layer Breakeven**  
   - If price reaches **halfway to TP**, the layer’s SL is moved to entry price.  
   - This happens without changing the global SL for other positions.

5. **Ongoing Monitoring**  
   - On every tick, EA re-checks:  
     - Layer placement.  
     - Global SL level.  
     - Breakeven conditions.  
   - Replaces missing layers when needed.

6. **Cleanup**  
   - When the main trade is closed, all EA orders are canceled.
  
   - 
---

### 🛡 Drawdown Protection
- Calculates **global stop price** based on your equity and maximum allowed loss percentage.
- Automatically **applies SL adjustments** to all open trades & pending orders to cap losses.
- Excludes **profit-locked trades** from global stop loss adjustments.

### 💰 Profit Lock & Breakeven
- Monitors all EA-managed trades.
- **Locks 40% of Take Profit distance** once price reaches 60% of TP target.
- Automatically moves Stop Loss to secure profits without interfering in early trade stages.

### 📊 Real-Time Dashboard
- Displays:
  - EA Status (Active/Inactive)
  - Balance / Equity
  - Daily, Weekly, and Monthly P&L
  - Active symbol
  - Total lots traded
  - Total commission paid
  - Current version & author branding
- Fully auto-refreshing on-chart interface.

### 🎯 Daily Profit Target Enforcement
- Stops trading for the day when **net profit (closed + floating)** reaches target.
- Immediately closes all trades and removes pending orders upon hitting target.

### 🔄 Emergency Close All
- One-click (or automated trigger) close of **all positions & orders**.
- Instant risk-off mode for volatile markets or news events.

### 🧮 Historical & Floating PnL Tracking
- Tracks closed profit:
  - **Today**
  - **This Week**
  - **This Month**
- Tracks total lots traded & commission paid.
- Calculates floating profit for all open trades.

---

## ⚙️ Input Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `MagicNumber` | `uint` | Magic number for EA-managed trades (0 = all trades) |
| `BaseLotSize` | `double` | Base lot for first layer |
| `PipDistance` | `int` | Distance between layered entries (pips) |
| `TPpips` | `int` | Take profit per layer (pips) |
| `MaxLayers` | `int` | Maximum layers allowed |
| `CommentTag` | `string` | Comment tag for orders |
| `Slippage` | `uint` | Max slippage (points) |
| `MaxLossPercent` | `double` | Max allowed equity drawdown % |
| `TargetProfitPerDay` | `double` | Daily net profit target (account currency) |

---

## 📟 Dashboard Layout
The EA creates a **rectangle panel** with dynamic labels:

Drawdown Manager
by Arjun1337
Algo Status: Active/Inactive
Balance: XXXX
Equity: XXXX
Closed Today: +XXX
Closed Week: +XXX
Closed Month: +XXX
Active Symbol: XXX
Version: X.X
Total Lots: XX.XX
Total Commission: XX.XX

---

## 📊 Example Flow

```mermaid
flowchart TD
    A[Manual Trade Opened] --> B[EA Detects Main Trade]
    B --> C[Places All Layers]
    C --> D[Price Moves Against Main]
    D --> E[Layers Triggered]
    E --> F[Price Retraces Halfway to TP] --> G[Set Breakeven SL]
    F --> H[Hit TP or Breakeven] --> C
    E --> I[Continued Drawdown] --> J[Global SL Hit → Close All Trades]

💡 Use Case & Benefits
Drawdown Control — Smooths volatility impact via averaging.

Risk-Free Trades — Breakeven locking removes downside risk mid-trade.

Hands-Off Layer Management — Fully automated after initial manual trade.

Capital Protection — Global SL ensures losses remain within defined limits.

📈 Performance Notes
Works best on liquid pairs with consistent volatility.

Must be paired with a sound entry strategy.

Test thoroughly in demo before live use.

📂 File Structure
DrawdownManagerEA.mq5 — Core EA source file.

🚦 Installation & Usage
Copy .mq5 file into MQL5/Experts/

Compile via MetaEditor.

Attach to the desired chart.

Configure input parameters.

Open a manual trade (magic number 0).

Let the EA manage layers, SL, and breakeven automatically.

PRs welcome.

📞 Contact
Twitter: @Arjun1337

LinkedIn: Arjun Ashtankar

Email: arjun@arjun.media

🔹 Power your trades with discipline & precision — because winning is a system, not luck.

## 📌 Best Practices
- Use on **one chart per account** to avoid duplicate SL updates.
- Set realistic `MaxLossPercent` and `TargetProfitPerDay`.
- Combine with a trusted entry strategy — this EA focuses on **management**, not signals.

---

## 🧠 How It Works (Algorithm Flow)

1. **Initialization**
   - Detects symbol specs, tick size/value, pip size, digits.
   - Prepares dashboard UI.

2. **Drawdown Monitoring**
   - Continuously calculates **stop price** for all positions.
   - Updates SL levels if equity drawdown exceeds threshold.

3. **Profit Locking**
   - For each trade:
     - If price hits 60% of TP → Move SL to lock 40% profit.

4. **Daily Target Enforcement**
   - Checks net daily profit.
   - If reached → Close all & remove pending orders.

5. **Dashboard Updates**
   - Every tick refreshes PnL, status, and account stats.

---

📜 License
© 2025 Arjun1337 — All Rights Reserved.
This EA is provided "as-is" without warranty. Use at your own risk.

🤝 Contributions & Support
Open a GitHub issue for bug reports or feature requests.

---

### 🏆 Trader's Edge
> “The market rewards discipline — not hope. The Drawdown Manager EA is your silent enforcer.”

---
![Footer Logo](https://via.placeholder.com/250x80.png?text=Arjun1337+Trading+Tools)
