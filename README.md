# Drawdown Manager EA by Arjun1337

![Drawdown Manager EA](https://img.shields.io/badge/version-1.20-blue.svg)  
![MQL5](https://img.shields.io/badge/platform-MetaTrader5-green.svg)

---

## 🚀 Overview

**Drawdown Manager EA** is an advanced MetaTrader 5 Expert Advisor designed to **strategically manage drawdowns by layering trades** around a manually initiated position. This EA acts as a precision risk mitigation and scaling tool, automating multiple pending orders (layers) to optimize average entry price and control risk during adverse price movements.

Developed with a strict, scalable architecture, this EA ensures disciplined position management aligned with your strategic trading goals.

---

## 🎯 Key Features

- **Automatic Detection of Manual Trades:** Identifies manually opened trades (magic number = 0) on the active symbol and takes control.
- **Layered Order Placement:** Places multiple pending limit orders ("layers") spaced by configurable pip distances, with increasing lot sizes per layer to capitalize on pullbacks.
- **Take Profit per Layer:** Each layer has its own dynamic take profit, maintaining risk-reward discipline.
- **Dynamic Layer Replacement:** Automatically replaces filled or canceled layers to maintain the intended grid structure.
- **Slippage and Volume Control:** Adjustable slippage and precise volume sizing based on symbol volume steps.
- **Robust Trade Transaction Handling:** Immediate reaction to trade events ensures timely cleanup and re-layering.
- **Minimal Dependency:** Pure MQL5 with standard MetaTrader libraries, no external dependencies.

---

## ⚙️ Input Parameters

| Parameter       | Type    | Description                                                      | Default    |
|-----------------|---------|------------------------------------------------------------------|------------|
| `MagicNumber`   | uint    | Magic number used for EA-managed orders                          | `133700`   |
| `BaseLotSize`   | double  | Base lot size for the first layer; subsequent layers multiply it| `0.01`     |
| `PipDistance`   | int     | Distance in pips between each pending order layer               | `100`      |
| `TPpips`        | int     | Take Profit in pips for each layer                               | `50`       |
| `MaxLayers`     | int     | Maximum number of pending order layers to place                  | `10`       |
| `CommentTag`    | string  | Custom comment tag for EA orders                                 | `"DD_Manager"` |
| `Slippage`      | uint    | Maximum allowed slippage (in points) when sending orders        | `10`       |

---

## 🛠️ How It Works

1. **Manual Trade Detection:** The EA scans for any open manual position on the current symbol with magic number zero.
2. **Layer Deployment:** Upon detection, it places a sequence of pending limit orders at fixed pip intervals away from the entry price, increasing lot size per layer (e.g., layer 2 = base lot × 2).
3. **Take Profit Setup:** Each pending order has a defined take profit offset relative to its price.
4. **Continuous Management:** On every tick and trade event, the EA monitors active trades and pending orders, removing or replacing layers as necessary.
5. **Order Validation:** Ensures no duplicate layers exist at the same price and lot size.
6. **Exit Strategy:** When the main manual trade closes, all EA-generated pending orders are cancelled.

---

## 💡 Use Case & Benefits

- **Drawdown Mitigation:** Smooths out price volatility by layering additional entries, improving average price and risk exposure.
- **Scalable Trading:** Enables systematic position scaling with configurable max layers and lot multiplication.
- **Discipline & Automation:** Enforces strict trade management rules to minimize emotional decision-making.
- **Easy Integration:** Designed to complement manual trading strategies without taking full control.

---

## 📈 Performance & Limitations

- Best suited for traders who **manage manual positions but want automated drawdown control**.
- Requires careful parameter tuning according to instrument volatility and account risk profile.
- **Not a standalone strategy:** must be combined with a sound manual or algorithmic entry methodology.
- MetaTrader 5 platform only.

---

## 📂 File Structure

- `DrawdownManagerEA.mq5` — Core EA source code file.
- Supporting standard MetaTrader 5 libraries (Trade.mqh, etc.) are required.

---

## 🚦 Installation & Usage

1. Copy `DrawdownManagerEA.mq5` to your `MQL5\Experts` directory.
2. Open MetaEditor, compile the EA.
3. Attach the EA to your desired chart.
4. Configure input parameters in the EA properties panel.
5. Open manual trades with magic number = 0 on the chart symbol.
6. Monitor EA behavior and logs for layer placement and management.

---

## 📜 License

© 2025 Arjun1337. All rights reserved.  
This software is provided “as is” without warranty of any kind. Use responsibly and test on demo accounts before live deployment.

---

## 🤝 Contributions & Support

Contributions are welcome via pull requests.  
For issues, questions, or feature requests, please open an issue on this repository.

---

## 📞 Contact

- Twitter: [@Arjun1337](https://twitter.com/Arjun1337)  
- LinkedIn: [Arjun Business](https://linkedin.com/in/arjun-business)  
- Email: arjun1337@yourdomain.com

---

### Power your trades with discipline & precision — because winning is a system, not luck.

---
