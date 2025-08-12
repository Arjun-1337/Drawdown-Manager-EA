//+------------------------------------------------------------------+
//|                                             DrawdownManagerEA.mq5|
//|                         Drawdown Manager EA by Arjun1337         |
//+------------------------------------------------------------------+
#property copyright "Drawdown Manager EA by Arjun1337"
#property version   "1.22"
#property strict

#include <Trade\Trade.mqh>

input uint    MagicNumber     = 133700;       // Magic for EA orders
input double  BaseLotSize     = 0.01;         // base lot (layer1 = base * 1, layer2 = base * 2 ...)
input int     PipDistance     = 100;          // distance between layers in pips (per layer)
input int     TPpips          = 50;           // TP for each layer (in pips)
input int     MaxLayers       = 10;           // maximum number of layers
input string  CommentTag      = "DD_Manager"; // comment on orders
input uint    Slippage        = 10;           // slippage in points
input double  MaxLossPercent  = 0.20;         // maximum allowed total loss as percent of equity (0.20 => 20%)

CTrade trade;

// runtime globals
ulong  mainTicket = 0;
string symbolName;
double pointVal;
double pipPrice;
int    priceDigits;
int    volumeDigits;

//+------------------------------------------------------------------+
//| utility: convert pips -> price units                             |
//+------------------------------------------------------------------+
double PipsToPrice(int pips)
{
   return (double)pips * pipPrice;
}

//+------------------------------------------------------------------+
//| symbol tick helpers                                               |
//+------------------------------------------------------------------+
double GetTickSize()
{
   return SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_SIZE);
}
double GetTickValue()
{
   return SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_VALUE);
}

//+------------------------------------------------------------------+
//| Compute global stop price that limits total loss to MaxLossPercent |
//| Returns true + outStopPrice if computed successfully             |
//+------------------------------------------------------------------+
bool CalculateGlobalStopPrice(double lossPercent, double &outStopPrice)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double maxLoss = equity * lossPercent;
   double tickSize  = GetTickSize();
   double tickValue = GetTickValue();

   if(tickSize <= 0.0 || tickValue <= 0.0)
   {
      Print("CalculateGlobalStopPrice: invalid tickSize/tickValue");
      return false;
   }

   // Sum volumes and sum(volume * openPrice) for all relevant items (open positions + EA pending layers)
   double sumVolOpen = 0.0;
   double sumVol     = 0.0;

   // include open positions on this symbol
   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;
      string psym = PositionGetString(POSITION_SYMBOL);
      if(psym != symbolName) continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      sumVolOpen += vol * openP;
      sumVol     += vol;
   }

   // include pending EA layers (assume they will fill at their registered price)
   int orders = OrdersTotal();
   for(int i=0; i<orders; i++)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbolName) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)MagicNumber) continue;

      double ordVol = OrderGetDouble(ORDER_VOLUME_INITIAL);
      double ordPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      sumVolOpen += ordVol * ordPrice;
      sumVol     += ordVol;
   }

   if(sumVol <= 0.0)
   {
      Print("CalculateGlobalStopPrice: total volume is zero -> nothing to protect.");
      return false;
   }

   // Determine main direction. Default BUY if unknown
   long mainType = POSITION_TYPE_BUY;
   if(mainTicket != 0 && PositionSelectByTicket(mainTicket))
      mainType = PositionGetInteger(POSITION_TYPE);

   // coeff = maxLoss * tickSize / tickValue (units of price * volume)
   double coeff = (maxLoss * tickSize) / tickValue;
   double stopPrice = 0.0;

   if(mainType == POSITION_TYPE_BUY)
   {
      // total_loss = (sumVolOpen - stopPrice * sumVol) / tickSize * tickValue = maxLoss
      // => stopPrice = (sumVolOpen - coeff) / sumVol
      stopPrice = (sumVolOpen - coeff) / sumVol;
   }
   else // SELL
   {
      // total_loss = (stopPrice * sumVol - sumVolOpen) / tickSize * tickValue = maxLoss
      // => stopPrice = (coeff + sumVolOpen) / sumVol
      stopPrice = (coeff + sumVolOpen) / sumVol;
   }

   outStopPrice = NormalizeDouble(stopPrice, priceDigits);

   PrintFormat("CalculateGlobalStopPrice: equity=%.2f maxLoss=%.2f sumVol=%.2f sumVolOpen=%.10f -> stopPrice=%.10f",
               equity, maxLoss, sumVol, sumVolOpen, outStopPrice);

   return true;
}

//+------------------------------------------------------------------+
//| Apply global stop price: set SL on open positions and pending orders |
//+------------------------------------------------------------------+
void ApplyGlobalStopPrice(double stopPrice)
{
   // Modify open positions (all positions on this symbol)
   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbolName) continue;

      long ptype = PositionGetInteger(POSITION_TYPE);
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      double newSL = stopPrice;

      // ensure SL is a valid price relative to open price per direction
      if(ptype == POSITION_TYPE_BUY)
      {
         if(newSL >= openP) newSL = NormalizeDouble(openP - pipPrice, priceDigits);
      }
      else // SELL
      {
         if(newSL <= openP) newSL = NormalizeDouble(openP + pipPrice, priceDigits);
      }

      // only modify if sufficiently different to avoid spamming
      if(MathAbs(newSL - curSL) > (pipPrice * 0.5))
      {
         bool ok = trade.PositionModify(posTicket, newSL, curTP);
         if(ok)
            PrintFormat("ApplyGlobalStopPrice: modified position %I64u SL->%.10f", posTicket, newSL);
         else
            PrintFormat("ApplyGlobalStopPrice: failed to modify position %I64u SL->%.10f", posTicket, newSL);
      }
   }

   // Modify EA pending orders so filled positions will inherit SL
   int orders = OrdersTotal();
   for(int i=0; i<orders; i++)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbolName) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)MagicNumber) continue;

      double ordPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      long ordType = (long)OrderGetInteger(ORDER_TYPE);
      double existingTP = OrderGetDouble(ORDER_TP);

      double slToSet = stopPrice;
      if(ordType == ORDER_TYPE_BUY_LIMIT || ordType == ORDER_TYPE_BUY_STOP)
      {
         if(slToSet >= ordPrice) slToSet = NormalizeDouble(ordPrice - pipPrice, priceDigits);
      }
      else // SELL pending
      {
         if(slToSet <= ordPrice) slToSet = NormalizeDouble(ordPrice + pipPrice, priceDigits);
      }

      // Build modify request
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action = TRADE_ACTION_MODIFY;
      req.order  = ordTicket;
      req.symbol = symbolName;
      req.sl     = NormalizeDouble(slToSet, priceDigits);
      req.tp     = NormalizeDouble(existingTP, priceDigits);
      req.deviation = (int)Slippage;

      bool sent = OrderSend(req, res);
      if(!sent || (res.retcode < 10000 || res.retcode > 10018))
         PrintFormat("ApplyGlobalStopPrice: modify pending order %I64u failed ret=%d comment=%s", ordTicket, res.retcode, res.comment);
      else
         PrintFormat("ApplyGlobalStopPrice: modified pending order %I64u SL->%.10f", ordTicket, req.sl);
   }
}

//+------------------------------------------------------------------+
//| Breakeven rule: for EA layer positions (magic == MagicNumber, not mainTicket) |
//| If running price profit >= half TP (in price units) -> move SL to entry price |
//| NOTE: This runs AFTER global SL is applied so that per-layer BE overrides the global SL for that position. |
//+------------------------------------------------------------------+
void CheckAndApplyBreakeven()
{
   double halfTPprice = ((double)TPpips / 2.0) * pipPrice;

   double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);

   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbolName) continue;

      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if((ulong)posMagic != (ulong)MagicNumber) continue; // only EA-managed layer positions
      if(posTicket == mainTicket) continue; // ensure not main (shouldn't have EA magic, but safe)

      long ptype = PositionGetInteger(POSITION_TYPE);
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      // If TP is 0 (unlikely for EA layers), compute expected TP from PipsToPrice on entry
      if(curTP == 0.0)
      {
         if(ptype == POSITION_TYPE_BUY) curTP = openP + PipsToPrice(TPpips);
         else curTP = openP - PipsToPrice(TPpips);
      }

      double curPrice = (ptype == POSITION_TYPE_BUY) ? ask : bid;
      double priceDiff = (ptype == POSITION_TYPE_BUY) ? (curPrice - openP) : (openP - curPrice);

      // only consider if TP distance is positive and priceDiff reached halfTP
      if(priceDiff >= halfTPprice)
      {
         // Set new SL to exact entry price (with small safety offset if required by broker)
         double newSL = NormalizeDouble(openP, priceDigits);

         // Validate newSL relative to current SL to avoid moving SL in wrong direction
         bool needModify = false;
         if(ptype == POSITION_TYPE_BUY)
         {
            // For buy, SL must be below current price. Only move up if current SL is lower than entry
            if(curSL < newSL - (pipPrice * 0.5))
               needModify = true;
         }
         else // SELL
         {
            // For sell, SL must be above current price. Only move down if current SL is higher than entry or not set
            if(curSL > newSL + (pipPrice * 0.5) || curSL == 0.0)
               needModify = true;
         }

         if(needModify)
         {
            // Try to set SL to break-even entry price
            bool ok = trade.PositionModify(posTicket, newSL, curTP);
            if(ok) PrintFormat("Breakeven applied pos %I64u -> SL=%.10f", posTicket, newSL);
            else PrintFormat("Breakeven FAILED pos %I64u -> attempted SL=%.10f", posTicket, newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   symbolName   = _Symbol;
   priceDigits  = (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS);

   double volumeStep = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
   volumeDigits = (int)MathRound(-MathLog10(volumeStep));

   pointVal = SymbolInfoDouble(symbolName, SYMBOL_POINT);
   // pipPrice: if 3/5 digits (fractional digit), 1 pip = 10 * point; else 1 pip = point
   pipPrice = ((priceDigits == 3) || (priceDigits == 5)) ? pointVal * 10.0 : pointVal;

   PrintFormat("Drawdown Manager EA by Arjun1337 initialized for %s (digits=%d, volDigits=%d)",
               symbolName, priceDigits, volumeDigits);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Drawdown Manager EA stopped.");
}

//+------------------------------------------------------------------+
//| OnTick: detect main trade, place layers, maintain them           |
//+------------------------------------------------------------------+
void OnTick()
{
   // If we don't have a main trade recorded, try to detect a manual one
   if(mainTicket == 0)
   {
      mainTicket = DetectFirstManualPosition();
      if(mainTicket != 0)
      {
         PrintFormat("Main manual trade detected: %I64u", mainTicket);
         PlaceAllLayers();

         // compute & apply global SL immediately after placing layers
         double globalSL = 0.0;
         if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
            ApplyGlobalStopPrice(globalSL);

         // Now apply per-layer breakeven overrides if any layer already meets condition
         CheckAndApplyBreakeven();
      }
   }
   else
   {
      // If main trade was closed between calls, cleanup (defensive)
      if(!PositionSelectByTicket(mainTicket))
      {
         Print("Main trade no longer exists on tick -> removing pending layers.");
         RemoveAllEAPendingOrders();
         mainTicket = 0;
         return;
      }

      // Ensure layers exist (re-place missing ones)
      ReplaceMissingLayers();

      // recompute global SL and apply it first (so it remains the common SL baseline)
      double globalSL = 0.0;
      if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
         ApplyGlobalStopPrice(globalSL);

      // Then apply per-layer breakeven so qualifying layers override the common SL
      CheckAndApplyBreakeven();
   }
}

//+------------------------------------------------------------------+
//| Instant reaction to trade events                                 |
//| Called on every trade transaction; used to detect main trade close quickly |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // If we currently track a main trade and it's gone -> cleanup immediately
   if(mainTicket != 0)
   {
      // If the position has been deleted/closed, PositionSelectByTicket will return false
      if(!PositionSelectByTicket(mainTicket))
      {
         Print("OnTradeTransaction: main trade closed -> removing pending layers immediately.");
         RemoveAllEAPendingOrders();
         mainTicket = 0;
         return;
      }
   }

   // If we are not tracking a main trade, check if a new manual position appeared
   if(mainTicket == 0)
   {
      ulong t = DetectFirstManualPosition();
      if(t != 0)
      {
         mainTicket = t;
         PrintFormat("OnTradeTransaction: new main manual trade detected: %I64u", mainTicket);
         PlaceAllLayers();

         // compute & apply global SL immediately after placing layers
         double globalSL = 0.0;
         if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
            ApplyGlobalStopPrice(globalSL);

         // then apply breakeven (if some layers were instantly in-range)
         CheckAndApplyBreakeven();
      }
   }
   else
   {
      // If a pending order was filled/closed, ReplaceMissingLayers() on next tick will re-place
      // Also recompute global SL on trade transaction to respond quickly to equity changes
      double globalSL = 0.0;
      if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
         ApplyGlobalStopPrice(globalSL);

      // after global SL update, try applying breakeven for any qualifying layers
      CheckAndApplyBreakeven();
   }
}

//+------------------------------------------------------------------+
//| Detect first manual position (POSITION_MAGIC == 0) on this symbol|
//+------------------------------------------------------------------+
ulong DetectFirstManualPosition()
{
   int totalPos = PositionsTotal();
   for(int i=0; i<totalPos; i++)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      if(posSymbol != symbolName) continue;

      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(posMagic == 0) // manual position (no EA magic)
      {
         return posTicket;
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Place all configured layers for current mainTicket              |
//+------------------------------------------------------------------+
void PlaceAllLayers()
{
   if(mainTicket == 0 || !PositionSelectByTicket(mainTicket)) return;

   long posType = PositionGetInteger(POSITION_TYPE);
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);

   for(int layer=1; layer<=MaxLayers; layer++)
   {
      double lot = NormalizeDouble(BaseLotSize * layer, volumeDigits);
      double price = 0.0;
      double tp    = 0.0;

      if(posType == POSITION_TYPE_BUY)
      {
         price = entryPrice - PipsToPrice(PipDistance * layer);
         tp    = price + PipsToPrice(TPpips);
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         price = entryPrice + PipsToPrice(PipDistance * layer);
         tp    = price - PipsToPrice(TPpips);
      }
      else
      {
         continue;
      }

      // Only place if there's no pending or active position at same price & lot
      if(!LayerExists(lot, price))
      {
         ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
         if(PlacePending(orderType, lot, price, tp))
            PrintFormat("Placed layer %d -> type=%d price=%.10f lot=%.2f tp=%.10f", layer, (int)orderType, NormalizeDouble(price, priceDigits), lot, NormalizeDouble(tp, priceDigits));
      }
   }

   // Recompute & apply global SL after placing layers
   double globalSL = 0.0;
   if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
      ApplyGlobalStopPrice(globalSL);

   // Apply breakeven overrides if any (rare immediately after placement but safe)
   CheckAndApplyBreakeven();
}

//+------------------------------------------------------------------+
//| Replace missing layers (if a layer was filled & closed at TP)   |
//+------------------------------------------------------------------+
void ReplaceMissingLayers()
{
   if(mainTicket == 0 || !PositionSelectByTicket(mainTicket)) return;

   long posType = PositionGetInteger(POSITION_TYPE);
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);

   for(int layer=1; layer<=MaxLayers; layer++)
   {
      double lot = NormalizeDouble(BaseLotSize * layer, volumeDigits);
      double price = 0.0;
      double tp    = 0.0;

      if(posType == POSITION_TYPE_BUY)
      {
         price = entryPrice - PipsToPrice(PipDistance * layer);
         tp    = price + PipsToPrice(TPpips);
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         price = entryPrice + PipsToPrice(PipDistance * layer);
         tp    = price - PipsToPrice(TPpips);
      }
      else
         continue;

      // If no pending order or active position exists at this price+lot, re-place it
      if(!LayerExists(lot, price))
      {
         ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
         if(PlacePending(orderType, lot, price, tp))
            PrintFormat("Replaced missing layer at price=%.10f lot=%.2f", NormalizeDouble(price, priceDigits), lot);
      }
   }

   // Recompute & apply global SL after replacing layers
   double globalSL = 0.0;
   if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
      ApplyGlobalStopPrice(globalSL);

   // Apply breakeven overrides if any
   CheckAndApplyBreakeven();
}

//+------------------------------------------------------------------+
//| Check whether a pending order or active position exists at price+lot |
//+------------------------------------------------------------------+
bool LayerExists(double lot, double price)
{
   double normPrice = NormalizeDouble(price, priceDigits);
   double normLot   = NormalizeDouble(lot, volumeDigits);

   // check pending orders pool
   int orders = OrdersTotal();
   for(int i=0; i<orders; i++)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;

      // Only consider pending orders on our symbol with our magic and comment
      if(OrderGetString(ORDER_SYMBOL) != symbolName) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)MagicNumber) continue;

      double ordPrice = NormalizeDouble(OrderGetDouble(ORDER_PRICE_OPEN), priceDigits);
      double ordVol   = NormalizeDouble(OrderGetDouble(ORDER_VOLUME_INITIAL), volumeDigits);

      if(ordPrice == normPrice && ordVol == normLot)
         return true;
   }

   // check active positions (an active position might have same open price & vol)
   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;

      string posSymbol = PositionGetString(POSITION_SYMBOL);
      if(posSymbol != symbolName) continue;

      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if((ulong)posMagic != (ulong)MagicNumber) continue;

      double posPrice = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), priceDigits);
      double posVol   = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), volumeDigits);

      if(posPrice == normPrice && posVol == normLot)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Place a pending order (MQL5)                                     |
//+------------------------------------------------------------------+
bool PlacePending(ENUM_ORDER_TYPE orderType, double volume, double price, double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action      = TRADE_ACTION_PENDING;
   req.symbol      = symbolName;
   req.volume      = NormalizeDouble(volume, volumeDigits);
   req.type        = orderType;
   req.price       = NormalizeDouble(price, priceDigits);
   req.sl          = 0.0;
   req.tp          = NormalizeDouble(tp, priceDigits);
   req.deviation   = (int)Slippage;
   req.magic       = (long)MagicNumber;
   req.comment     = CommentTag;
   req.type_filling = ORDER_FILLING_RETURN;
   req.type_time    = ORDER_TIME_GTC;

   bool sent = OrderSend(req, res);
   if(!sent)
   {
      PrintFormat("OrderSend failed (place pending) ret=%d comment=%s", res.retcode, res.comment);
      return false;
   }
   if(res.retcode >= 10000 && res.retcode <= 10018)
   {
      // success codes for order execution
      return true;
   }
   // otherwise log and return false
   PrintFormat("OrderSend returned ret=%d comment=%s", res.retcode, res.comment);
   return false;
}

//+------------------------------------------------------------------+
//| Remove all pending orders created by this EA (by MagicNumber)    |
//+------------------------------------------------------------------+
void RemoveAllEAPendingOrders()
{
   int orders = OrdersTotal();
   for(int i=orders-1; i>=0; i--)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;

      if(OrderGetString(ORDER_SYMBOL) != symbolName) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)MagicNumber) continue;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);

      req.action = TRADE_ACTION_REMOVE;
      req.order  = ordTicket;
      bool removed = OrderSend(req, res);
      if(!removed)
         PrintFormat("Failed to remove pending order %I64u -> ret=%d comment=%s", ordTicket, res.retcode, res.comment);
      else
         PrintFormat("Removed pending order %I64u", ordTicket);
   }
}
