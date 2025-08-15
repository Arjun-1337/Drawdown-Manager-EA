# 📉 Drawdown Manager EA by Arjun1337

![Version](https://img.shields.io/badge/version-1.30-blue.svg)  
![Platform](https://img.shields.io/badge/platform-MetaTrader5-green.svg)

---

## 🚀 Overview

**Drawdown Manager EA** is an advanced MetaTrader 5 Expert Advisor designed to **strategically manage drawdowns by layering trades** around a manually initiated position.  
This EA automates pending orders (layers) to optimize average entry price, protect equity with a global stop loss, and lock in risk-free trades using **tiered breakeven logic**.

This version also introduces a **Global Take-Profit Aggregation System** that consolidates all open layers into a single TP when targets are hit, ensuring maximum efficiency and **0$ drawdown exits**.  
In addition, it comes with a **secure payload-based license verification system** to protect your IP and control distribution.

---

## 🎯 Key Features

- **Automatic Detection of Manual Trades** — Monitors for manually opened trades (magic number = 0) and takes over position management.  
- **Layered Order Placement** — Multiple pending limit orders at fixed pip distances with increasing lot sizes.  
- **Individual Take Profit for Each Layer** — Ensures structured exit points until global TP mode is activated.  
- **Tiered Breakeven System**:
  - **First stage:** Locks breakeven at **+40%** when price reaches **+60%** of TP target.  
  - **Second stage:** Moves breakeven to **+70%** when price reaches **+90%** of TP target.  
- **Global TP Mode**:
  - When the profit target is reached, EA switches from per-layer TP to a **single aggregated TP** for all open positions.  
  - Recalculates TP dynamically if new layers open, keeping total floating PnL at **0$ drawdown**.  
- **Global Equity Stop Loss** — Calculates the price where total open position loss equals a fixed % of account equity (default 20%) and sets SL for all trades.  
- **Dynamic Layer Replacement** — Replaces filled or canceled layers until the main trade is closed.  
- **Clean-Up Logic** — Removes all EA orders when the main trade closes.  
- **Secure License Verification** — HMAC-SHA256 signed license keys with account binding and expiry checks.  
- **Pure MQL5 Implementation** — No external dependencies.  

---

## 🛡 License System

### 🔹 How It Works

Each license contains a **Base64-encoded payload**:

```json
{
  "account_id": 12345678,
  "plan": "pro",
  "expiry": "2025-12-31"
}
```

Payload is signed with a secret key using **HMAC-SHA256**.

**EA verifies:**
- Account binding  
- Expiry date  
- Payload integrity  

If the license is invalid, the EA halts operations.

---

## 🧠 Algorithm Overview

1. **Manual Trade Detection**  
   Detects any manual position on the chart’s symbol with magic number `0` and sets it as `mainTicket`.  

2. **Layer Placement**  
   - Places limit orders at `PipDistance` from the main trade.  
   - Lot size = `BaseLotSize × LayerNumber`.  
   - Each layer has a fixed TP distance (unless in global TP mode).  

3. **Global Stop Loss**  
   - Calculates the price where closing all trades would result in `EquityRiskPercent` loss of total equity.  
   - Sets this as SL for all positions (manual + EA).  

4. **Tiered Breakeven**  
   - If price reaches **60%** of TP → SL moves to lock **40%** profit.  
   - If price reaches **90%** of TP → SL moves to lock **70%** profit.  

5. **Global TP Activation**  
   - If profit target hits → switch to aggregated TP mode.  
   - Calculate a single TP for all open positions at **0$ drawdown**.  
   - Adjust TP if more layers open.  

6. **Ongoing Monitoring**  
   - On every tick, EA re-checks:  
     - Layer placement  
     - Global SL level  
     - Breakeven & TP conditions  
   - Replaces missing layers when needed.  

7. **Cleanup**  
   - When the main trade is closed, all EA orders are canceled.  

---

## 📟 Dashboard Layout

```
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
```

---

## ⚙️ Input Parameters

| Parameter            | Type     | Description                                         |
|----------------------|----------|-----------------------------------------------------|
| `MagicNumber`        | `uint`   | Magic number for EA-managed trades (0 = all trades) |
| `BaseLotSize`        | `double` | Base lot for first layer                            |
| `PipDistance`        | `int`    | Distance between layered entries (pips)             |
| `TPpips`             | `int`    | Take profit per layer (pips)                        |
| `MaxLayers`          | `int`    | Maximum layers allowed                              |
| `CommentTag`         | `string` | Comment tag for orders                              |
| `Slippage`           | `uint`   | Max slippage (points)                               |
| `MaxLossPercent`     | `double` | Max allowed equity drawdown %                       |
| `TargetProfitPerDay` | `double` | Daily net profit target (account currency)          |
| `LicenseKey`         | `string` | Base64-encoded license key for verification         |

---

## 📂 File Structure

```
📁 MQL5
 ├── Experts
 │   ├── DrawdownManagerEA.mq5   # Main EA file
 │
 ├── Include
 │   ├── LicenseVerifier.mqh     # License validation module
 │
 ├── Scripts
 │   └── LicenseGenerator.py     # Python script for generating keys
```

---

## 🚦 Installation & Usage

1. Copy `.mq5` file into `MQL5/Experts/`  
2. Copy `LicenseVerifier.mqh` into `MQL5/Include/`  
3. Compile via **MetaEditor**  
4. Attach to chart and enter `LicenseKey` in inputs  
5. Open a manual trade (magic number = `0`) and let EA handle layers, SL, and TP automatically  

---

## 📜 License

© 2025 **Arjun1337** — All Rights Reserved.  
Unauthorized copying, modification, or redistribution is prohibited.  

---

## 🏆 Trader's Edge

> “The market rewards discipline — not hope. The Drawdown Manager EA is your silent enforcer.”
