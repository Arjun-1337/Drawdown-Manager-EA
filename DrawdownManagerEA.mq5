//+------------------------------------------------------------------+
//|                                             DrawdownManagerEA.mq5|
//|                         Drawdown Manager EA by Arjun1337         |
//+------------------------------------------------------------------+
#property copyright "Drawdown Manager EA by Arjun1337"
#property version   "1.20"
#property strict

#include <Trade\Trade.mqh>

input uint    MagicNumber   = 133700;       // Magic for EA orders
input double  BaseLotSize   = 0.01;         // base lot (layer1 = base * 1, layer2 = base * 2 ...)
input int     PipDistance   = 100;          // distance between layers in pips (per layer)
input int     TPpips        = 50;           // TP for each layer (in pips)
input int     MaxLayers     = 10;           // maximum number of layers
input string  CommentTag    = "DD_Manager"; // comment on orders
input uint    Slippage      = 10;           // slippage in points

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
      }
   }

   // Additionally, if a pending order got executed and closed on TP (deal), we'll let ReplaceMissingLayers()
   // or the next transaction/tick re-place the pending order. We don't rely on transaction type enums here.
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
