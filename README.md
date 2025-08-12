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

---

## ⚙️ Input Parameters

| Parameter            | Type    | Description |
|----------------------|---------|-------------|
| `MagicNumber`        | uint    | Unique ID for EA trades |
| `BaseLotSize`        | double  | Lot size for first layer |
| `PipDistance`        | int     | Distance between layers (pips) |
| `TPpips`             | int     | TP distance per layer (pips) |
| `MaxLayers`          | int     | Maximum number of layers |
| `CommentTag`         | string  | Order comment text |
| `Slippage`           | uint    | Max allowed slippage (points) |
| `EquityRiskPercent`  | double  | % of equity loss for global SL trigger |

---

## 🛠 Function Breakdown

### **`OnInit()`**
Initializes core variables and prepares EA for manual trade monitoring.

### **`OnTick()`**
- Detects manual trades.
- Manages layer placement.
- Adjusts global SL.
- Moves individual layer SL to breakeven when conditions are met.

### **`PlaceAllLayers()`**
Creates pending orders for all layers according to pip spacing, lot sizing, and TP settings.

### **`LayerExists()`**
Prevents duplicate orders at the same price and lot.

### **`ReplaceMissingLayers()`**
Reinstates layers if they are triggered, closed, or deleted.

### **`AdjustGlobalStopLoss()`**
Computes the global SL price based on account equity risk percentage.

### **`CheckBreakEvenForLayers()`**
Sets SL to entry price when profit reaches half the TP distance.

### **`RemoveAllEAPendingOrders()`**
Removes all pending EA orders when main trade closes.

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

📜 License
© 2025 Arjun1337 — All Rights Reserved.
This EA is provided "as-is" without warranty. Use at your own risk.

🤝 Contributions & Support
Open a GitHub issue for bug reports or feature requests.

PRs welcome.

📞 Contact
Twitter: @Arjun1337

LinkedIn: Arjun Business

Email: arjun1337@yourdomain.com

🔹 Power your trades with discipline & precision — because winning is a system, not luck.

---

This merges **your branded Drawdown Manager EA description** with **the enhanced algo breakdown, per-layer breakeven logic, and global SL risk control** we discussed earlier.  

I can also add **a visual diagram showing the breakeven trigger and global SL interaction** so your GitHub page looks even more premium.  
Do you want me to make that diagram?
