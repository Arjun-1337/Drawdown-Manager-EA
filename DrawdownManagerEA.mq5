//+------------------------------------------------------------------+
//|                                             DrawdownManagerEA.mq5|
//|                         Drawdown Manager EA by Arjun1337         |
//+------------------------------------------------------------------+
#property copyright "Drawdown Manager EA by Arjun1337"
#property version   "2.1"
#property strict

#include <Trade\Trade.mqh>

// -------------------- Embedded License Verifier (no #include) --------------------
// LicenseVerifier: payload-based Base64 license with HMAC-SHA256 verification
// Keep EA_SECRET_KEY identical to the secret used by your license generator.
#define EA_SECRET_KEY "Insert Key"

struct LicenseInfo
{
   bool   valid;
   string raw_payload; // JSON string
   string account_id;
   string plan;
   string expiry;      // "YYYY-MM-DD" or "lifetime"
   string client_name; // optional
   string error;       // non-empty when valid==false
};

// -------------------- helpers (bytes/strings) ----------------------
void StringToUtf8Bytes(const string s, uchar &out[])
{
   ArrayResize(out,0);
   StringToCharArray(s, out, 0, WHOLE_ARRAY, CP_UTF8);
   int n = ArraySize(out);
   if(n>0 && out[n-1]==0) ArrayResize(out, n-1);
}

string Utf8BytesToString(const uchar &b[])
{
   return CharArrayToString(b, 0, -1, CP_UTF8);
}

int FindLastOf(const string s, const string needle)
{
   int pos = -1;
   int from = 0;
   while(true)
   {
      int p = StringFind(s, needle, from);
      if(p < 0) break;
      pos  = p;
      from = p + StringLen(needle);
   }
   return pos;
}

string ToLowerCopy(const string s)
{
   string tmp = s;
   StringToLower(tmp);
   return tmp;
}

string TrimWhite(const string s)
{
   int n = StringLen(s);
   if(n==0) return s;
   int i=0, j=n-1;
   for(; i<n; i++)
   {
      int c = StringGetCharacter(s,i);
      if(c!=' ' && c!='\t' && c!='\n' && c!='\r') break;
   }
   for(; j>=i; j--)
   {
      int c = StringGetCharacter(s,j);
      if(c!=' ' && c!='\t' && c!='\n' && c!='\r') break;
   }
   if(j<i) return "";
   return StringSubstr(s, i, j-i+1);
}

// Base64 decode using CryptDecode. returns true on success and fills out[]
bool Base64DecodeString(const string b64, uchar &out[])
{
   uchar in[], key_empty[];
   StringToUtf8Bytes(TrimWhite(b64), in);
   ArrayResize(key_empty,0); // empty key param
   ArrayResize(out,0);
   // CryptDecode(method, data, key, result)
   int rc = CryptDecode(CRYPT_BASE64, in, key_empty, out);
   return (rc > 0 && ArraySize(out) > 0);
}

string BytesToHexLower(const uchar &b[], int size)
{
   static string hexchars = "0123456789abcdef";
   string s="";
   for(int i=0;i<size;i++)
   {
      uchar v = b[i];
      int hi = (v >> 4) & 0x0F;
      int lo = v & 0x0F;
      s += CharToString(StringGetCharacter(hexchars,hi));
      s += CharToString(StringGetCharacter(hexchars,lo));
   }
   return s;
}

// -------------------- SHA256 / HMAC-SHA256 -------------------------
bool Sha256(const uchar &data[], uchar &digest[])
{
   uchar key_empty[];
   ArrayResize(key_empty,0);
   ArrayResize(digest,0);
   // CryptEncode(method, data, key, result)
   int rc = CryptEncode(CRYPT_HASH_SHA256, data, key_empty, digest);
   return (rc > 0 && ArraySize(digest) == 32);
}

bool HmacSha256(const uchar &key[], const uchar &message[], uchar &mac[])
{
   const int BLOCK = 64;
   uchar K[];
   if(ArraySize(key) > BLOCK)
   {
      uchar kh[];
      if(!Sha256(key, kh)) return false;
      ArrayResize(K, BLOCK);
      for(int i=0;i<BLOCK;i++) K[i]=0;
      for(int i=0;i<ArraySize(kh) && i<BLOCK;i++) K[i]=kh[i];
   }
   else
   {
      ArrayResize(K, BLOCK);
      for(int i=0;i<BLOCK;i++) K[i]=0;
      for(int i=0;i<ArraySize(key) && i<BLOCK;i++) K[i]=key[i];
   }

   uchar ipad[]; ArrayResize(ipad, BLOCK);
   uchar opad[]; ArrayResize(opad, BLOCK);
   for(int i=0;i<BLOCK;i++)
   {
      ipad[i] = (uchar)(K[i] ^ 0x36);
      opad[i] = (uchar)(K[i] ^ 0x5C);
   }

   // inner = SHA256(ipad || message)
   int mlen = ArraySize(message);
   uchar innerData[]; ArrayResize(innerData, BLOCK + mlen);
   ArrayCopy(innerData, ipad, 0, 0, BLOCK);
   if(mlen>0) ArrayCopy(innerData, message, BLOCK, 0, mlen);

   uchar innerHash[];
   if(!Sha256(innerData, innerHash)) return false;

   // outer = SHA256(opad || innerHash)
   uchar outerData[]; ArrayResize(outerData, BLOCK + ArraySize(innerHash));
   ArrayCopy(outerData, opad, 0, 0, BLOCK);
   ArrayCopy(outerData, innerHash, BLOCK, 0, ArraySize(innerHash));

   ArrayResize(mac,0);
   if(!Sha256(outerData, mac)) return false;

   return (ArraySize(mac) == 32);
}

// -------------------- tiny JSON getters (flat payload only) ----------------------------
bool JsonGetString(const string json, const string key, string &out)
{
   out = "";
   string pat = "\"" + key + "\":";
   int p = StringFind(json, pat, 0);
   if(p < 0) return false;
   p += StringLen(pat);

   // skip spaces
   while(p < StringLen(json))
   {
      int c = StringGetCharacter(json, p);
      if(c==' '||c=='\t'||c=='\n'||c=='\r') { p++; continue; }
      break;
   }

   // expect quoted string value
   if(p >= StringLen(json) || StringGetCharacter(json,p) != '"') return false;
   p++; // after opening quote

   int start = p;
   while(p < StringLen(json))
   {
      int c = StringGetCharacter(json, p);
      if(c == '\\') { p += 2; continue; } // skip escaped char
      if(c == '"') break;
      p++;
   }
   if(p >= StringLen(json)) return false;

   out = StringSubstr(json, start, p - start);
   return true;
}

// -------------------- top-level verify -----------------------------
LicenseInfo VerifyAndParseLicense(const string base64_license)
{
   LicenseInfo info;
   info.valid = false;
   info.raw_payload = "";
   info.account_id  = "";
   info.plan        = "";
   info.expiry      = "";
   info.client_name = "";
   info.error       = "";

   string trimmed = TrimWhite(base64_license);
   if(StringLen(trimmed) <= 8)
   {
      info.error = "License string too short";
      return info;
   }

   // Decode Base64 -> combined bytes
   uchar combinedBytes[];
   if(!Base64DecodeString(trimmed, combinedBytes))
   {
      info.error = "Base64 decode failed";
      return info;
   }

   string combined = Utf8BytesToString(combinedBytes);
   int dot = FindLastOf(combined, ".");
   if(dot < 0)
   {
      info.error = "Malformed license: separator '.' not found";
      return info;
   }

   string payload = StringSubstr(combined, 0, dot);
   string hexsig  = StringSubstr(combined, dot + 1);
   if(StringLen(payload) == 0 || StringLen(hexsig) < 64)
   {
      info.error = "Malformed license contents";
      return info;
   }

   // Compute HMAC-SHA256(payload, EA_SECRET_KEY) and compare
   uchar keyBytes[];     StringToUtf8Bytes(EA_SECRET_KEY, keyBytes);
   uchar payloadBytes[]; StringToUtf8Bytes(payload, payloadBytes);
   uchar mac[];
   if(!HmacSha256(keyBytes, payloadBytes, mac))
   {
      info.error = "HMAC computation failed";
      return info;
   }

   string computedHex = BytesToHexLower(mac, ArraySize(mac));
   if(ToLowerCopy(computedHex) != ToLowerCopy(hexsig))
   {
      info.error = "Signature mismatch (invalid license or wrong secret)";
      return info;
   }

   // Parse JSON fields
   string acc="", plan="", expiry="", client="";
   bool okA = JsonGetString(payload, "account_id", acc);
   bool okP = JsonGetString(payload, "plan",       plan);
   bool okE = JsonGetString(payload, "expiry",     expiry);
   JsonGetString(payload, "client_name", client); // optional

   if(!(okA && okP && okE))
   {
      info.error = "Failed to parse payload JSON";
      return info;
   }

   info.raw_payload = payload;
   info.account_id  = acc;
   info.plan        = plan;
   info.expiry      = expiry;
   info.client_name = client;

   // Account binding (0 => any)
   long login = (long)AccountInfoInteger(ACCOUNT_LOGIN);
   long acc_num = (long)StringToInteger(acc);
   if(acc_num != 0 && acc_num != login)
   {
      info.error = StringFormat("License bound to account %s (current %I64d)", acc, login);
      return info;
   }

   // Expiry check (unless lifetime)
   if(expiry != "lifetime")
   {
      if(StringLen(expiry) != 10 || StringGetCharacter(expiry,4) != '-' || StringGetCharacter(expiry,7) != '-')
      {
         info.error = "Expiry format invalid (expected YYYY-MM-DD)";
         return info;
      }
      int y = (int)StringToInteger(StringSubstr(expiry,0,4));
      int m = (int)StringToInteger(StringSubstr(expiry,5,2));
      int d = (int)StringToInteger(StringSubstr(expiry,8,2));
      MqlDateTime md; md.year=y; md.mon=m; md.day=d; md.hour=0; md.min=0; md.sec=0;
      datetime expiry_dt = StructToTime(md);
      if(TimeCurrent() > expiry_dt)
      {
         info.error = "License expired on " + expiry;
         return info;
      }
   }

   info.valid = true;
   return info;
}
// -------------------- End Embedded License Verifier --------------------


//--------------------------- Inputs --------------------------------
input uint    MagicNumber         = 133700;       // Magic for EA orders (0 => check all)
input double  BaseLotSize         = 0.01;         // base lot (layer1 = base * 1, layer2 = base * 2 ...)
input int     PipDistance         = 100;          // distance between layers in pips (per layer)
input int     TPpips              = 50;           // TP for each layer (in pips)
input int     MaxLayers           = 10;           // maximum number of layers
input string  CommentTag          = "DD_Manager"; // comment on orders
input uint    Slippage            = 10;           // slippage in points
input double  MaxLossPercent      = 0.20;         // maximum allowed total loss as percent of equity (0.20 => 20%)
input double  TargetProfitPerDay  = 100.0;        // profit target (account currency) - evaluated vs balance when first manual trade opens

// License inputs
input string  LicenseKey          = "";           // Paste Base64 license string here
input bool    RequireLicense      = true;         // If true, EA won't run trading logic unless license valid

//----------------------- Dashboard settings ------------------------
#define EA_VERSION_STR "2.1"
string  DASH_PANEL_NAME = "DDM_Panel";
int     DASH_X = 300;     // distance from right edge (dashboard anchored right-upper)
int     DASH_Y = 50;      // distance from top (placed under header near right)
int     DASH_W = 320;
int     DASH_H = 260;
int     DASH_LABELS = 17; // increased to include license fields (L0..L16)

//--------------------------- Globals --------------------------------
CTrade trade;

ulong  mainTicket = 0;
string symbolName;
double pointVal;
double pipPrice;
int    priceDigits;
int    volumeDigits;

double SL_MATCH_TOLERANCE = 0.0; // set in OnInit

double FirstManualTradeBalance = 0.0;
bool   FirstManualTradeRecorded = false;

// When true: stop per-layer breakeven but (NEW) manage a single global TP at breakeven
bool   StopBreakeven = false;

// Strategy tester seed control
bool   TesterSeedOpened = false;

// License state
LicenseInfo GlobalLicense;
bool        LicenseChecked = false;
bool        LicenseValid   = false;

//--------------------------- Utilities ------------------------------
double PipsToPrice(int pips) { return (double)pips * pipPrice; }
double GetTickSize()  { return SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_SIZE); }
double GetTickValue() { return SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_VALUE); }
bool   IsTester()     { return (bool)MQLInfoInteger(MQL_TESTER); }

// Forward declarations
void EnsureTesterSeedTrade();
void EnforceNoTPOnEATrades(); // (kept for compatibility; no longer used after changes)
bool CalculateGlobalBreakevenTP(double &outTP, long &outSide);
void ApplyGlobalBreakevenTP();
void CheckLicense();

//-------------------------------------------------------------------
// License check wrapper
//-------------------------------------------------------------------
void CheckLicense()
{
   LicenseChecked = true;
   GlobalLicense.valid = false;
   GlobalLicense.raw_payload = "";
   GlobalLicense.account_id = "";
   GlobalLicense.plan = "";
   GlobalLicense.expiry = "";
   GlobalLicense.client_name = "";
   GlobalLicense.error = "";

   string lk = TrimWhite(LicenseKey);
   if(StringLen(lk) == 0)
   {
      GlobalLicense.error = "No license key provided";
      LicenseValid = false;
      return;
   }

   GlobalLicense = VerifyAndParseLicense(lk);
   LicenseValid = GlobalLicense.valid;
   if(!LicenseValid)
      PrintFormat("License check failed: %s", GlobalLicense.error);
   else
      PrintFormat("License OK for account %s plan=%s expiry=%s client=%s", GlobalLicense.account_id, GlobalLicense.plan, GlobalLicense.expiry, GlobalLicense.client_name);
}

//-------------------------------------------------------------------
// CalculateGlobalStopPrice
//-------------------------------------------------------------------
bool CalculateGlobalStopPrice(double lossPercent, double &outStopPrice)
{
   double tickSize  = GetTickSize();
   double tickValue = GetTickValue();
   if(tickSize <= 0.0 || tickValue <= 0.0)
   {
      Print("CalculateGlobalStopPrice: invalid tickSize/tickValue");
      return false;
   }

   double sumVolOpen = 0.0;
   double sumVol     = 0.0;

   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;
      string psym = PositionGetString(POSITION_SYMBOL);
      if(psym != symbolName) continue;

      long posMagic = PositionGetInteger(POSITION_MAGIC);
      double vol    = PositionGetDouble(POSITION_VOLUME);
      double openP  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      long   ptype  = PositionGetInteger(POSITION_TYPE);

      bool excludeFromGlobal = false;
      if(MagicNumber != 0 && (ulong)posMagic == (ulong)MagicNumber)
      {
         double tpPrice = curTP;
         if(tpPrice <= 0.0)
         {
            if(ptype == POSITION_TYPE_BUY) tpPrice = openP + PipsToPrice(TPpips);
            else                           tpPrice = openP - PipsToPrice(TPpips);
         }
         // Accept both 40% and 70% profit-locks
         double expectedLockSL40 = (ptype == POSITION_TYPE_BUY)
                                   ? openP + (tpPrice - openP) * 0.40
                                   : openP - (openP - tpPrice) * 0.40;
         double expectedLockSL70 = (ptype == POSITION_TYPE_BUY)
                                   ? openP + (tpPrice - openP) * 0.70
                                   : openP - (openP - tpPrice) * 0.70;

         if( (curSL != 0.0 && MathAbs(curSL - expectedLockSL40) <= SL_MATCH_TOLERANCE) ||
             (curSL != 0.0 && MathAbs(curSL - expectedLockSL70) <= SL_MATCH_TOLERANCE) )
            excludeFromGlobal = true;
      }

      if(excludeFromGlobal)
      {
         PrintFormat("CalculateGlobalStopPrice: excluding pos %I64u from global SL (profit-locked).", posTicket);
         continue;
      }

      sumVolOpen += vol * openP;
      sumVol     += vol;
   }

   int orders = OrdersTotal();
   for(int i=0; i<orders; i++)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbolName) continue;
      if(MagicNumber != 0 && (ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)MagicNumber) continue;

      double ordVol   = OrderGetDouble(ORDER_VOLUME_INITIAL);
      double ordPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      sumVolOpen += ordVol * ordPrice;
      sumVol     += ordVol;
   }

   if(sumVol <= 0.0)
   {
      Print("CalculateGlobalStopPrice: total volume is zero -> nothing to protect.");
      return false;
   }

   long mainType = POSITION_TYPE_BUY;
   if(mainTicket != 0 && PositionSelectByTicket(mainTicket))
      mainType = PositionGetInteger(POSITION_TYPE);

   double coeff = ((AccountInfoDouble(ACCOUNT_EQUITY) * lossPercent) * tickSize) / tickValue;
   double stopPrice = 0.0;
   if(mainType == POSITION_TYPE_BUY)
      stopPrice = (sumVolOpen - coeff) / sumVol;
   else
      stopPrice = (coeff + sumVolOpen) / sumVol;

   outStopPrice = NormalizeDouble(stopPrice, priceDigits);
   PrintFormat("CalculateGlobalStopPrice: equity=%.2f maxLoss=%.2f sumVol=%.2f sumVolOpen=%.10f -> stopPrice=%.10f",
               AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_EQUITY)*lossPercent, sumVol, sumVolOpen, outStopPrice);
   return true;
}

//-------------------------------------------------------------------
// ApplyGlobalStopPrice
//-------------------------------------------------------------------
void ApplyGlobalStopPrice(double stopPrice)
{
   // Positions
   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbolName) continue;

      long ptype    = PositionGetInteger(POSITION_TYPE);
      double openP  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      long posMagic = PositionGetInteger(POSITION_MAGIC);

      if(MagicNumber != 0 && (ulong)posMagic == (ulong)MagicNumber)
      {
         double tpPrice = curTP;
         if(tpPrice <= 0.0)
         {
            if(ptype == POSITION_TYPE_BUY) tpPrice = openP + PipsToPrice(TPpips);
            else                           tpPrice = openP - PipsToPrice(TPpips);
         }
         // exclude 40% or 70% profit-locked trades from SL tightening
         double expectedLockSL40 = (ptype == POSITION_TYPE_BUY)
                                   ? openP + (tpPrice - openP) * 0.40
                                   : openP - (openP - tpPrice) * 0.40;
         double expectedLockSL70 = (ptype == POSITION_TYPE_BUY)
                                   ? openP + (tpPrice - openP) * 0.70
                                   : openP - (openP - tpPrice) * 0.70;
         if(curSL != 0.0 && (MathAbs(curSL - expectedLockSL40) <= SL_MATCH_TOLERANCE ||
                             MathAbs(curSL - expectedLockSL70) <= SL_MATCH_TOLERANCE))
            continue;
      }

      double newSL = stopPrice;
      if(ptype == POSITION_TYPE_BUY)
      {
         if(newSL >= openP) newSL = NormalizeDouble(openP - pipPrice, priceDigits);
      }
      else
      {
         if(newSL <= openP) newSL = NormalizeDouble(openP + pipPrice, priceDigits);
      }

      // Do NOT alter TP here based on StopBreakeven; global TP is managed elsewhere
      double tpToSet = curTP;

      if(MathAbs(newSL - curSL) > (pipPrice * 0.5) || (tpToSet != curTP))
      {
         bool ok = trade.PositionModify(posTicket, newSL, tpToSet);
         if(ok) PrintFormat("ApplyGlobalStopPrice: modified position %I64u SL->%.10f TP->%.10f", posTicket, newSL, tpToSet);
         else   PrintFormat("ApplyGlobalStopPrice: failed to modify position %I64u SL->%.10f TP->%.10f", posTicket, newSL, tpToSet);
      }
   }

   // Pending orders
   int orders = OrdersTotal();
   for(int i=0; i<orders; i++)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbolName) continue;
      if(MagicNumber != 0 && (ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)MagicNumber) continue;

      double ordPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      long   ordType  = (long)OrderGetInteger(ORDER_TYPE);
      double existingTP = OrderGetDouble(ORDER_TP);

      double slToSet = stopPrice;
      if(ordType == ORDER_TYPE_BUY_LIMIT || ordType == ORDER_TYPE_BUY_STOP)
      {
         if(slToSet >= ordPrice) slToSet = NormalizeDouble(ordPrice - pipPrice, priceDigits);
      }
      else
      {
         if(slToSet <= ordPrice) slToSet = NormalizeDouble(ordPrice + pipPrice, priceDigits);
      }

      // Do NOT force TP=0 after target; global TP manager will handle TP
      double tpToSet = existingTP;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action    = TRADE_ACTION_MODIFY;
      req.order     = ordTicket;
      req.symbol    = symbolName;
      req.sl        = NormalizeDouble(slToSet, priceDigits);
      req.tp        = NormalizeDouble(tpToSet, priceDigits);
      req.deviation = (int)Slippage;

      bool sent = OrderSend(req, res);
      if(!sent || (res.retcode < 10000 || res.retcode > 10018))
         PrintFormat("ApplyGlobalStopPrice: modify pending order %I64u failed ret=%d comment=%s", ordTicket, res.retcode, res.comment);
      else
         PrintFormat("ApplyGlobalStopPrice: modified pending order %I64u SL->%.10f TP->%.10f", ordTicket, req.sl, req.tp);
   }
}

//-------------------------------------------------------------------
// Breakeven/profit-lock  (UPDATED: two-stage 40% @60% and 70% @90%)
//-------------------------------------------------------------------
void CheckAndApplyBreakeven()
{
   if(StopBreakeven) return; // after target: no per-layer breakeven

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
      if(MagicNumber == 0 || (ulong)posMagic != (ulong)MagicNumber) continue; // only EA-managed
      if(posTicket == mainTicket) continue;

      long   ptype = PositionGetInteger(POSITION_TYPE);
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      double tpPrice = curTP;
      if(tpPrice <= 0.0)
      {
         if(ptype == POSITION_TYPE_BUY) tpPrice = openP + PipsToPrice(TPpips);
         else                           tpPrice = openP - PipsToPrice(TPpips);
      }

      // progress toward TP (0..1)
      double progress = 0.0;
      if(ptype == POSITION_TYPE_BUY)
      {
         double denom = (tpPrice - openP);
         if(denom <= 0.0) continue;
         progress = (ask - openP) / denom;
      }
      else
      {
         double denom = (openP - tpPrice);
         if(denom <= 0.0) continue;
         progress = (openP - bid) / denom;
      }

      // Determine stage
      double lockFraction = -1.0;
      if(progress >= 0.90)      lockFraction = 0.70; // stage 2
      else if(progress >= 0.60) lockFraction = 0.40; // stage 1
      else                      continue;            // not reached any stage

      // Compute lock SL
      double lockSLPrice = 0.0;
      if(ptype == POSITION_TYPE_BUY)
         lockSLPrice = openP + (tpPrice - openP) * lockFraction;
      else
         lockSLPrice = openP - (openP - tpPrice) * lockFraction;

      // Skip if already (roughly) at desired lock
      if(curSL != 0.0 && MathAbs(curSL - lockSLPrice) <= SL_MATCH_TOLERANCE) continue;

      bool needModify = false;
      if(ptype == POSITION_TYPE_BUY)
      {
         if(curSL < lockSLPrice - (pipPrice * 0.5)) needModify = true;
      }
      else
      {
         if(curSL > lockSLPrice + (pipPrice * 0.5) || curSL == 0.0) needModify = true;
      }

      if(needModify)
      {
         bool ok = trade.PositionModify(posTicket, NormalizeDouble(lockSLPrice, priceDigits), tpPrice);
         if(ok)
            PrintFormat("Profit-lock applied pos %I64u -> SL=%.10f (lock %.0f%% of TP) TP=%.10f",
                        posTicket, NormalizeDouble(lockSLPrice, priceDigits), lockFraction*100.0, tpPrice);
         else
            PrintFormat("Profit-lock FAILED pos %I64u -> attempted SL=%.10f TP=%.10f",
                        posTicket, NormalizeDouble(lockSLPrice, priceDigits), tpPrice);
      }
   }
}

//-------------------------------------------------------------------
// Dashboard helpers (create/update/delete)
//-------------------------------------------------------------------
void CreateDashboard()
{
   ObjectDelete(0, DASH_PANEL_NAME);
   for(int i=0;i<DASH_LABELS;i++) ObjectDelete(0, "DDM_L"+(string)i);

   if(!ObjectCreate(0, DASH_PANEL_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      Print("CreateDashboard: failed to create panel object.");
      return;
   }
   ObjectSetInteger(0, DASH_PANEL_NAME, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, DASH_PANEL_NAME, OBJPROP_XDISTANCE, DASH_X);
   ObjectSetInteger(0, DASH_PANEL_NAME, OBJPROP_YDISTANCE, DASH_Y);
   ObjectSetInteger(0, DASH_PANEL_NAME, OBJPROP_XSIZE, DASH_W);
   ObjectSetInteger(0, DASH_PANEL_NAME, OBJPROP_YSIZE, DASH_H);
   ObjectSetInteger(0, DASH_PANEL_NAME, OBJPROP_COLOR, clrDarkGreen);
   ObjectSetInteger(0, DASH_PANEL_NAME, OBJPROP_BGCOLOR, clrDarkGreen);
   ObjectSetString(0, DASH_PANEL_NAME, OBJPROP_TEXT, "");

   for(int i=0;i<DASH_LABELS;i++)
   {
      string lbl = "DDM_L"+(string)i;
      ObjectCreate(0, lbl, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, lbl, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, lbl, OBJPROP_XDISTANCE, DASH_X - 20);
      ObjectSetInteger(0, lbl, OBJPROP_YDISTANCE, DASH_Y + 8 + i*16);
      ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, (i==0?12:9));
      ObjectSetString(0, lbl, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, lbl, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, lbl, OBJPROP_TEXT, "");
   }
}

void DeleteDashboard()
{
   ObjectDelete(0, DASH_PANEL_NAME);
   for(int i=0;i<DASH_LABELS;i++) ObjectDelete(0, "DDM_L"+(string)i);
}

string FormatMoney(double v) { return (v >= 0.0 ? "+" : "") + DoubleToString(v, 2); }

string FirstActiveSymbol(bool &algoActive)
{
   algoActive = false;
   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;
      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(MagicNumber == 0 || (ulong)posMagic == (ulong)MagicNumber)
      {
         algoActive = true;
         return PositionGetString(POSITION_SYMBOL);
      }
   }
   return "None";
}

//-------------------------------------------------------------------
// History-based helpers
//-------------------------------------------------------------------
double GetClosedProfitSince(datetime since)
{
   datetime now = TimeCurrent();
   if(!HistorySelect(since, now))
   {
      Print("HistorySelect failed; returning 0.0");
      return 0.0;
   }

   double sum = 0.0;
   int totalDeals = HistoryDealsTotal();
   for(int i=0; i<totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;

      long   type  = (long)HistoryDealGetInteger(dealTicket, DEAL_TYPE);

      // Always add commission reported on this deal (if any)
      double comm = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      sum += comm;

      // Only trade deals contribute profit/swap
      if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL)
      {
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         double swap   = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
         sum += profit + swap;
      }
   }
   return sum;
}

double GetClosedProfitToday_Wrapper()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return GetClosedProfitSince(StructToTime(dt));
}

double GetClosedProfitWeek_Wrapper()
{
   MqlDateTime nowdt; TimeToStruct(TimeCurrent(), nowdt);
   int dayOfWeek = nowdt.day_of_week; // 0=Sunday,1=Monday...
   int daysToMonday = (dayOfWeek == 0) ? 6 : (dayOfWeek - 1);
   datetime mondayTime = TimeCurrent() - (daysToMonday * 86400);
   MqlDateTime md; TimeToStruct(mondayTime, md);
   md.hour = 0; md.min = 0; md.sec = 0;
   return GetClosedProfitSince(StructToTime(md));
}

double GetClosedProfitMonth_Wrapper()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;
   return GetClosedProfitSince(StructToTime(dt));
}

double GetFloatingProfit_All()
{
   double sum = 0.0;
   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;
      double profit = PositionGetDouble(POSITION_PROFIT);
      double swap   = PositionGetDouble(POSITION_SWAP);
      sum += profit + swap;
   }
   return sum;
}

//-------------------------------------------------------------------
// Update dashboard
//-------------------------------------------------------------------
void UpdateDashboard()
{
   bool algoActive=false;
   string activeSymbol = FirstActiveSymbol(algoActive);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double closedToday = GetClosedProfitToday_Wrapper();
   double closedWeek  = GetClosedProfitWeek_Wrapper();
   double closedMonth = GetClosedProfitMonth_Wrapper();
   double floating = GetFloatingProfit_All();

   ObjectSetString(0, "DDM_L0", OBJPROP_TEXT, "Drawdown Manager");
   ObjectSetInteger(0, "DDM_L0", OBJPROP_FONTSIZE, 12);

   ObjectSetString(0, "DDM_L1", OBJPROP_TEXT, "by Arjun1337");
   ObjectSetInteger(0, "DDM_L1", OBJPROP_FONTSIZE, 9);

   ObjectSetString(0, "DDM_L2", OBJPROP_TEXT, (algoActive ? "Algo Active" : "Algo Inactive"));
   ObjectSetInteger(0, "DDM_L2", OBJPROP_COLOR, (algoActive ? clrLime : clrRed));

   ObjectSetString(0, "DDM_L3", OBJPROP_TEXT, "Balance: " + DoubleToString(balance,2));
   ObjectSetString(0, "DDM_L4", OBJPROP_TEXT, "Equity : " + DoubleToString(equity,2));
   ObjectSetString(0, "DDM_L5", OBJPROP_TEXT, "Closed Today : " + FormatMoney(closedToday));
   ObjectSetString(0, "DDM_L6", OBJPROP_TEXT, "Closed Week  : " + FormatMoney(closedWeek));
   ObjectSetString(0, "DDM_L7", OBJPROP_TEXT, "Closed Month : " + FormatMoney(closedMonth));
   ObjectSetString(0, "DDM_L8", OBJPROP_TEXT, "Active Symbol: " + activeSymbol);

   if(FirstManualTradeRecorded)
      ObjectSetString(0, "DDM_L9", OBJPROP_TEXT, "Benchmark Bal: " + DoubleToString(FirstManualTradeBalance,2));
   else
      ObjectSetString(0, "DDM_L9", OBJPROP_TEXT, "Benchmark Bal: Not set");

   ObjectSetString(0, "DDM_L10", OBJPROP_TEXT, "Profit Target: " + DoubleToString(TargetProfitPerDay,2));

   double remaining = TargetProfitPerDay;
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(FirstManualTradeRecorded)
      remaining = (FirstManualTradeBalance + TargetProfitPerDay) - currentBalance;
   else
      remaining = TargetProfitPerDay;
   if(remaining <= 0.0) remaining = 0.0;

   ObjectSetString(0, "DDM_L11", OBJPROP_TEXT, "Remaining Target: " + DoubleToString(remaining,2));

   string beStatus = StopBreakeven ? "OFF (global TP mode)" : "ON";
   ObjectSetString(0, "DDM_L12", OBJPROP_TEXT, "Breakeven: " + beStatus + "  |  Ver: " + EA_VERSION_STR);

   // License Info in dashboard
   string licStatus = "Not checked";
   int licColor = clrYellow;
   if(LicenseChecked)
   {
      if(LicenseValid) { licStatus = "VALID"; licColor = clrLime; }
      else             { licStatus = "INVALID"; licColor = clrRed; }
   }
   else
   {
      licStatus = "Not checked";
      licColor = clrYellow;
   }
   if(!RequireLicense) { licStatus = licStatus + " (not required)"; licColor = clrAqua; }

   ObjectSetString(0, "DDM_L13", OBJPROP_TEXT, "License: " + licStatus);
   ObjectSetInteger(0, "DDM_L13", OBJPROP_COLOR, licColor);

   string clientName = (StringLen(GlobalLicense.client_name) > 0 ? GlobalLicense.client_name : "N/A");
   ObjectSetString(0, "DDM_L14", OBJPROP_TEXT, "Client: " + clientName);

   string planText = (StringLen(GlobalLicense.plan) > 0 ? GlobalLicense.plan : "N/A");
   ObjectSetString(0, "DDM_L15", OBJPROP_TEXT, "Plan: " + planText);

   string expiryText = (StringLen(GlobalLicense.expiry) > 0 ? GlobalLicense.expiry : "N/A");
   ObjectSetString(0, "DDM_L16", OBJPROP_TEXT, "Expiry: " + expiryText);
}

//-------------------------------------------------------------------
// History/close/float/closeall
//-------------------------------------------------------------------
double GetClosedProfitToday() { return GetClosedProfitToday_Wrapper(); }
double GetFloatingProfit()    { return GetFloatingProfit_All(); }

void CloseAllPositionsAndRemoveAllPending()
{
   Print("CloseAllPositionsAndRemoveAllPending: Initiating emergency close of all positions and removal of pending orders.");

   int posTotal = PositionsTotal();
   for(int i = posTotal - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;

      string psym = PositionGetString(POSITION_SYMBOL);
      bool closed = trade.PositionClose(posTicket);
      if(!closed)
      {
         bool closedSym = trade.PositionClose(psym);
         if(!closedSym) PrintFormat("CloseAll: failed to close position %I64u (%s)", posTicket, psym);
         else           PrintFormat("CloseAll: closed position %I64u by symbol %s", posTicket, psym);
      }
      else
         PrintFormat("CloseAll: closed position %I64u", posTicket);
   }

   int orders = OrdersTotal();
   for(int i = orders - 1; i >= 0; i--)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ordTicket;

      bool removed = OrderSend(req, res);
      if(!removed)
         PrintFormat("CloseAll: Failed to remove pending order %I64u -> ret=%d comment=%s", ordTicket, res.retcode, res.comment);
      else
         PrintFormat("CloseAll: Removed pending order %I64u", ordTicket);
   }

   mainTicket = 0;
   FirstManualTradeRecorded = false;
   FirstManualTradeBalance  = 0.0;
   StopBreakeven            = false;
   TesterSeedOpened         = false;
}

//-------------------------------------------------------------------
// Enforce daily target; (UPDATED) switch to global TP mode on hit
//-------------------------------------------------------------------
void CheckAndEnforceDailyTarget()
{
   if(TargetProfitPerDay <= 0.0) return;

   double net = 0.0;

   if(FirstManualTradeRecorded)
   {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double balanceDelta   = currentBalance - FirstManualTradeBalance;

      if(balanceDelta >= TargetProfitPerDay)
      {
         if(!StopBreakeven)
         {
            StopBreakeven = true;
            PrintFormat("StopBreakeven set = true (balanceDelta %.2f >= target %.2f). Switching to global TP at breakeven.", balanceDelta, TargetProfitPerDay);
            ApplyGlobalBreakevenTP(); // set common TP right away
         }
      }
      else
      {
         if(StopBreakeven)
         {
            StopBreakeven = false;
            PrintFormat("StopBreakeven cleared = false (balanceDelta %.2f < target %.2f) -> normal per-layer mode.", balanceDelta, TargetProfitPerDay);
         }
      }

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      net = currentEquity - FirstManualTradeBalance;
      PrintFormat("Daily target check (from benchmark) -> benchmark=%.2f equity=%.2f net=%.2f target=%.2f",
                  FirstManualTradeBalance, currentEquity, net, TargetProfitPerDay);
   }
   else
   {
      double closedToday = GetClosedProfitToday();
      double floating    = GetFloatingProfit();
      net = closedToday + floating;
      PrintFormat("Daily target check (fallback) -> closed=%.2f floating=%.2f net=%.2f target=%.2f",
                  closedToday, floating, net, TargetProfitPerDay);
   }

   if(net >= TargetProfitPerDay)
   {
      PrintFormat("Target reached (net=%.2f >= %.2f). Closing all positions and removing pending orders.", net, TargetProfitPerDay);
      CloseAllPositionsAndRemoveAllPending();
   }
}

//-------------------------------------------------------------------
// Core EA functions
//-------------------------------------------------------------------
int OnInit()
{
   symbolName   = _Symbol;
   priceDigits  = (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS);

   double volumeStep = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
   volumeDigits = (int)MathRound(-MathLog10(volumeStep));

   pointVal = SymbolInfoDouble(symbolName, SYMBOL_POINT);
   pipPrice = ((priceDigits == 3) || (priceDigits == 5)) ? pointVal * 10.0 : pointVal;

   SL_MATCH_TOLERANCE = pipPrice * 1.5;

   PrintFormat("Drawdown Manager EA by Arjun1337 initialized for %s (digits=%d, volDigits=%d, pipPrice=%.10f, SL_tol=%.10f)",
               symbolName, priceDigits, volumeDigits, pipPrice, SL_MATCH_TOLERANCE);

   // Check license first
   CheckLicense();

   CreateDashboard();
   UpdateDashboard();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteDashboard();
   Print("Drawdown Manager EA stopped.");
}

void OnTick()
{
   // Ensure license checked once
   if(!LicenseChecked) CheckLicense();

   // If license is required but invalid, do not perform trading operations (dashboard still updates)
   if(RequireLicense && !LicenseValid)
   {
      UpdateDashboard();
      return;
   }

   // Seed a "manual-like" trade in Strategy Tester only (does not run live)
   EnsureTesterSeedTrade();

   // Detect first manual position and record benchmark balance once
   if(!FirstManualTradeRecorded)
   {
      ulong t = DetectFirstManualPosition();
      if(t != 0)
      {
         FirstManualTradeBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
         FirstManualTradeRecorded  = true;
         PrintFormat("First manual trade detected; benchmark balance recorded = %.2f", FirstManualTradeBalance);

         mainTicket = t;
         PrintFormat("Main manual trade detected: %I64u", mainTicket);
         PlaceAllLayers();

         double globalSL = 0.0;
         if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
            ApplyGlobalStopPrice(globalSL);

         CheckAndApplyBreakeven();
      }
   }

   if(mainTicket == 0)
   {
      mainTicket = DetectFirstManualPosition();
      if(mainTicket != 0)
      {
         if(!FirstManualTradeRecorded)
         {
            FirstManualTradeBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
            FirstManualTradeRecorded = true;
            PrintFormat("Main manual trade detected (OnTick): benchmark balance recorded = %.2f", FirstManualTradeBalance);
         }

         PrintFormat("Main manual trade detected: %I64u", mainTicket);
         PlaceAllLayers();

         double globalSL = 0.0;
         if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
            ApplyGlobalStopPrice(globalSL);

         CheckAndApplyBreakeven();
      }
   }
   else
   {
      if(!PositionSelectByTicket(mainTicket))
      {
         Print("Main trade no longer exists on tick -> removing pending layers.");
         RemoveAllEAPendingOrders();
         mainTicket = 0;

         if(DetectFirstManualPosition() == 0)
         {
            FirstManualTradeRecorded = false;
            FirstManualTradeBalance  = 0.0;
            StopBreakeven            = false;
            Print("No manual positions left -> benchmark cleared.");
         }
      }
      else
      {
         ReplaceMissingLayers();
         double globalSL = 0.0;
         if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
            ApplyGlobalStopPrice(globalSL);
         CheckAndApplyBreakeven();
      }
   }

   // (UPDATED) When StopBreakeven is active, continuously manage global TP at breakeven
   if(StopBreakeven) ApplyGlobalBreakevenTP();

   CheckAndEnforceDailyTarget();
   UpdateDashboard();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // License gating
   if(!LicenseChecked) CheckLicense();
   if(RequireLicense && !LicenseValid) { UpdateDashboard(); return; }

   if(mainTicket != 0)
   {
      if(!PositionSelectByTicket(mainTicket))
      {
         Print("OnTradeTransaction: main trade closed -> removing pending layers immediately.");
         RemoveAllEAPendingOrders();
         mainTicket = 0;
         CheckAndEnforceDailyTarget();
         UpdateDashboard();

         if(DetectFirstManualPosition() == 0)
         {
            FirstManualTradeRecorded = false;
            FirstManualTradeBalance  = 0.0;
            StopBreakeven            = false;
            Print("No manual positions left -> benchmark cleared.");
         }
         return;
      }
   }

   if(mainTicket == 0)
   {
      ulong t = DetectFirstManualPosition();
      if(t != 0)
      {
         mainTicket = t;
         if(!FirstManualTradeRecorded)
         {
            FirstManualTradeBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
            FirstManualTradeRecorded = true;
            PrintFormat("OnTradeTransaction: first manual trade detected, benchmark balance recorded = %.2f", FirstManualTradeBalance);
         }

         PrintFormat("OnTradeTransaction: new main manual trade detected: %I64u", mainTicket);
         PlaceAllLayers();

         double globalSL = 0.0;
         if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
            ApplyGlobalStopPrice(globalSL);

         CheckAndApplyBreakeven();
      }
   }
   else
   {
      double globalSL = 0.0;
      if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
         ApplyGlobalStopPrice(globalSL);

      CheckAndApplyBreakeven();
   }

   // (UPDATED) keep global TP synced while in StopBreakeven mode
   if(StopBreakeven) ApplyGlobalBreakevenTP();

   CheckAndEnforceDailyTarget();
   UpdateDashboard();
}

//-------------------------------------------------------------------
// Remaining EA helper functions
//-------------------------------------------------------------------
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
      if(posMagic == 0) return posTicket; // manual position
   }
   return 0;
}

void PlaceAllLayers()
{
   if(RequireLicense && !LicenseValid) return; // license gating

   if(mainTicket == 0 || !PositionSelectByTicket(mainTicket)) return;

   long   posType    = PositionGetInteger(POSITION_TYPE);
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);

   // If we're already in "global TP mode", grab current global TP once
   double currentGlobalTP = 0.0; long side = -1;
   bool haveGlobalTP = false;
   if(StopBreakeven)
      haveGlobalTP = CalculateGlobalBreakevenTP(currentGlobalTP, side);

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
      else continue;

      if(!LayerExists(lot, price))
      {
         ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;

         // In global TP mode, preset pending order TP to current global breakeven (will be re-synced on fill)
         double tpToUse = StopBreakeven && haveGlobalTP ? currentGlobalTP : tp;

         if(PlacePending(orderType, lot, price, tpToUse))
            PrintFormat("Placed layer %d -> type=%d price=%.10f lot=%.2f tp=%.10f",
                        layer, (int)orderType, NormalizeDouble(price, priceDigits), lot, NormalizeDouble(tpToUse, priceDigits));
      }
   }

   double globalSL = 0.0;
   if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
      ApplyGlobalStopPrice(globalSL);

   CheckAndApplyBreakeven();

   // If in global TP mode, ensure TPs are aligned after new layer placement
   if(StopBreakeven) ApplyGlobalBreakevenTP();
}

void ReplaceMissingLayers()
{
   if(RequireLicense && !LicenseValid) return; // license gating

   if(mainTicket == 0 || !PositionSelectByTicket(mainTicket)) return;

   long   posType    = PositionGetInteger(POSITION_TYPE);
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);

   // Cache current global TP if applicable
   double currentGlobalTP = 0.0; long side = -1;
   bool haveGlobalTP = false;
   if(StopBreakeven)
      haveGlobalTP = CalculateGlobalBreakevenTP(currentGlobalTP, side);

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
      else continue;

      if(!LayerExists(lot, price))
      {
         ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
         double tpToUse = StopBreakeven && haveGlobalTP ? currentGlobalTP : tp;

         if(PlacePending(orderType, lot, price, tpToUse))
            PrintFormat("Replaced missing layer at price=%.10f lot=%.2f", NormalizeDouble(price, priceDigits), lot);
      }
   }

   double globalSL = 0.0;
   if(CalculateGlobalStopPrice(MaxLossPercent, globalSL))
      ApplyGlobalStopPrice(globalSL);

   CheckAndApplyBreakeven();

   if(StopBreakeven) ApplyGlobalBreakevenTP();
}

bool LayerExists(double lot, double price)
{
   double normPrice = NormalizeDouble(price, priceDigits);
   double normLot   = NormalizeDouble(lot, volumeDigits);

   int orders = OrdersTotal();
   for(int i=0; i<orders; i++)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;

      if(OrderGetString(ORDER_SYMBOL) != symbolName) continue;
      if(MagicNumber != 0 && (ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)MagicNumber) continue;

      double ordPrice = NormalizeDouble(OrderGetDouble(ORDER_PRICE_OPEN), priceDigits);
      double ordVol   = NormalizeDouble(OrderGetDouble(ORDER_VOLUME_INITIAL), volumeDigits);

      if(ordPrice == normPrice && ordVol == normLot)
         return true;
   }

   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;

      string posSymbol = PositionGetString(POSITION_SYMBOL);
      if(posSymbol != symbolName) continue;

      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(MagicNumber != 0 && (ulong)posMagic != (ulong)MagicNumber) continue;

      double posPrice = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), priceDigits);
      double posVol   = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), volumeDigits);

      if(posPrice == normPrice && posVol == normLot)
         return true;
   }

   return false;
}

bool PlacePending(ENUM_ORDER_TYPE orderType, double volume, double price, double tp)
{
   MqlTradeRequest req; MqlTradeResult  res;
   ZeroMemory(req); ZeroMemory(res);

   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = symbolName;
   req.volume       = NormalizeDouble(volume, volumeDigits);
   req.type         = orderType;
   req.price        = NormalizeDouble(price, priceDigits);
   req.sl           = 0.0;
   req.tp           = NormalizeDouble(tp, priceDigits); // in global TP mode, this is common breakeven TP
   req.deviation    = (int)Slippage;
   req.magic        = (long)MagicNumber;
   req.comment      = CommentTag;
   req.type_filling = ORDER_FILLING_RETURN;
   req.type_time    = ORDER_TIME_GTC;

   bool sent = OrderSend(req, res);
   if(!sent)
   {
      PrintFormat("OrderSend failed (place pending) ret=%d comment=%s", res.retcode, res.comment);
      return false;
   }
   if(res.retcode >= 10000 && res.retcode <= 10018) return true;

   PrintFormat("OrderSend returned ret=%d comment=%s", res.retcode, res.comment);
   return false;
}

void RemoveAllEAPendingOrders()
{
   int orders = OrdersTotal();
   for(int i=orders-1; i>=0; i--)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;

      if(OrderGetString(ORDER_SYMBOL) != symbolName) continue;
      if(MagicNumber != 0 && (ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)MagicNumber) continue;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ordTicket;
      bool removed = OrderSend(req, res);
      if(!removed)
         PrintFormat("Failed to remove pending order %I64u -> ret=%d comment=%s", ordTicket, res.retcode, res.comment);
      else
         PrintFormat("Removed pending order %I64u", ordTicket);
   }
}

//-------------------------------------------------------------------
// Strip TP from all EA-managed positions & pending orders
// (Legacy function kept for backward compatibility; not used now.)
//-------------------------------------------------------------------
void EnforceNoTPOnEATrades()
{
   // no-op in the new logic; left intentionally blank
}

//-------------------------------------------------------------------
// Global TP manager (NEW)
// - Calculates a single TP so that combined EA layers' floating P/L is ~0
//-------------------------------------------------------------------
bool CalculateGlobalBreakevenTP(double &outTP, long &outSide)
{
   outTP = 0.0; outSide = -1;

   double sumLotsBuy = 0.0, sumPxLotsBuy = 0.0;
   double sumLotsSell = 0.0, sumPxLotsSell = 0.0;

   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != symbolName) continue;

      long pmagic = PositionGetInteger(POSITION_MAGIC);
      if(MagicNumber != 0 && (ulong)pmagic != (ulong)MagicNumber) continue; // only EA layers

      long   ptype = PositionGetInteger(POSITION_TYPE);
      double lots  = PositionGetDouble(POSITION_VOLUME);
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);

      if(ptype == POSITION_TYPE_BUY)
      {
         sumLotsBuy    += lots;
         sumPxLotsBuy  += lots * openP;
      }
      else if(ptype == POSITION_TYPE_SELL)
      {
         sumLotsSell   += lots;
         sumPxLotsSell += lots * openP;
      }
   }

   // Decide side to manage (should be single-sided; fallback to main ticket side if both present)
   if(sumLotsBuy > 0.0 && sumLotsSell == 0.0)
   {
      outTP = sumPxLotsBuy / sumLotsBuy;
      outSide = POSITION_TYPE_BUY;
   }
   else if(sumLotsSell > 0.0 && sumLotsBuy == 0.0)
   {
      outTP = sumPxLotsSell / sumLotsSell;
      outSide = POSITION_TYPE_SELL;
   }
   else if(sumLotsBuy > 0.0 && sumLotsSell > 0.0)
   {
      // Fallback: use main position side if mixed (shouldn't happen with this strategy)
      if(mainTicket != 0 && PositionSelectByTicket(mainTicket))
      {
         long mtype = PositionGetInteger(POSITION_TYPE);
         if(mtype == POSITION_TYPE_BUY && sumLotsBuy > 0.0)   { outTP = sumPxLotsBuy  / sumLotsBuy;  outSide = POSITION_TYPE_BUY; }
         else if(mtype == POSITION_TYPE_SELL && sumLotsSell > 0.0){ outTP = sumPxLotsSell / sumLotsSell; outSide = POSITION_TYPE_SELL; }
      }
      else
      {
         // Choose the heavier side
         if(sumLotsBuy >= sumLotsSell) { outTP = sumPxLotsBuy  / sumLotsBuy;  outSide = POSITION_TYPE_BUY;  }
         else                          { outTP = sumPxLotsSell / sumLotsSell; outSide = POSITION_TYPE_SELL; }
      }
   }
   else
   {
      return false; // no EA positions to manage
   }

   outTP = NormalizeDouble(outTP, priceDigits);
   return true;
}

void ApplyGlobalBreakevenTP()
{
   double beTP = 0.0; long side = -1;
   if(!CalculateGlobalBreakevenTP(beTP, side)) return;

   // Update positions
   int posTotal = PositionsTotal();
   for(int p=0; p<posTotal; p++)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(!PositionSelectByTicket(posTicket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != symbolName) continue;

      long pmagic = PositionGetInteger(POSITION_MAGIC);
      if(MagicNumber != 0 && (ulong)pmagic != (ulong)MagicNumber) continue; // only EA layers

      long   ptype = PositionGetInteger(POSITION_TYPE);
      if(ptype != side) continue; // only same-side layers

      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      if(MathAbs(curTP - beTP) > (pipPrice * 0.5))
      {
         bool ok = trade.PositionModify(posTicket, curSL, beTP);
         if(ok) PrintFormat("Global BE TP: set position %I64u TP -> %.10f", posTicket, beTP);
      }
   }

   // Update pending orders (preset TP so fills inherit current global BE; will be re-synced later)
   int orders = OrdersTotal();
   for(int i=0; i<orders; i++)
   {
      ulong ordTicket = OrderGetTicket(i);
      if(ordTicket == 0) continue;
      if(!OrderSelect(ordTicket)) continue;

      if(OrderGetString(ORDER_SYMBOL) != symbolName) continue;
      if(MagicNumber != 0 && (ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)MagicNumber) continue;

      long otype = (long)OrderGetInteger(ORDER_TYPE);
      bool sideMatch =
         (side == POSITION_TYPE_BUY  && (otype == ORDER_TYPE_BUY_LIMIT  || otype == ORDER_TYPE_BUY_STOP)) ||
         (side == POSITION_TYPE_SELL && (otype == ORDER_TYPE_SELL_LIMIT || otype == ORDER_TYPE_SELL_STOP));

      if(!sideMatch) continue;

      double existingTP = OrderGetDouble(ORDER_TP);
      if(MathAbs(existingTP - beTP) <= (pipPrice * 0.5)) continue;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action    = TRADE_ACTION_MODIFY;
      req.order     = ordTicket;
      req.symbol    = symbolName;
      req.sl        = OrderGetDouble(ORDER_SL);
      req.tp        = beTP;
      req.deviation = (int)Slippage;

      bool sent = OrderSend(req, res);
      if(sent && (res.retcode >= 10000 && res.retcode <= 10018))
         PrintFormat("Global BE TP: set pending %I64u TP -> %.10f", ordTicket, beTP);
   }
}

//-------------------------------------------------------------------
// Strategy tester seeding - open one 0.01 manual-like trade
//-------------------------------------------------------------------
void EnsureTesterSeedTrade()
{
   if(!IsTester()) return;
   if(TesterSeedOpened) return;

   // If no manual position exists on this symbol, open a seed Buy 0.01
   ulong manual = DetectFirstManualPosition();
   if(manual == 0)
   {
      double volMin  = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
      double volStep = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
      double vol     = MathMax(0.01, volMin);
      double steps   = MathRound(vol/volStep);
      vol = steps * volStep;

      bool ok = trade.Buy(vol, symbolName, 0.0, 0.0, 0.0, "TesterSeed");
      if(ok)
      {
         TesterSeedOpened = true;
         PrintFormat("Tester seed trade opened: BUY %.2f on %s", vol, symbolName);
      }
   }
}
