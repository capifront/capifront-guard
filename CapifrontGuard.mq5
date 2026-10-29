//+------------------------------------------------------------------+
//|                                              CapifrontGuard.mq5  |
//|                     Capifront LLC - https://capifront.com/guard  |
//|                                                                  |
//|  Free risk helper for Capifront accounts. It shows how much you  |
//|  can still lose today and overall, warns you early, and can      |
//|  close every trade before a Capifront loss limit is reached.     |
//|  Guidance only: Capifront's own review decides every account.    |
//+------------------------------------------------------------------+
#property copyright   "Capifront LLC"
#property link        "https://capifront.com/guard"
#property version     "1.00"
#property description "Capifront Guard shows how much you can still lose today and overall,"
#property description "warns you early and can close every trade before a loss limit is hit."
#property description "Guidance only. It does not guarantee a pass; Capifront's review decides every account."

#include <Trade\Trade.mqh>

enum ENUM_CF_PLAN
  {
   CF_ONE_STEP = 0,   // One-Step (10% target, 5% daily, 10% overall)
   CF_TWO_P1,         // Two-Step Phase 1 (10% target, 5% / 10%)
   CF_TWO_P2,         // Two-Step Phase 2 (5% target, 5% / 10%)
   CF_THREE,          // Three-Step, any phase (6% target, 5% / 10%)
   CF_PRO,            // Capifront Pro (8% target, 6% daily, 12% overall)
   CF_FUNDED,         // Funded or Instant (no target, 5% / 10%)
   CF_PRO_FUNDED      // Funded Pro (no target, 6% / 12%)
  };

input ENUM_CF_PLAN InpPlan        = CF_ONE_STEP; // Your plan and phase
input double       InpAccountSize = 0;           // Account size, e.g. 10000 (0 = read the first deposit)
input bool         InpAutoProtect = true;        // Close all trades before a loss limit is hit
input double       InpStopRoomPct = 15;          // Close when room left is below this % of the daily limit
input double       InpWarnRoomPct = 40;          // Warn when room left is below this % of the daily limit
input bool         InpPush        = true;        // Also send push notifications to MT5 on your phone
input double       InpRiskPct     = 1.0;         // Lot calculator: risk per trade, % of account size
input double       InpSlPips      = 20;          // Lot calculator: stop-loss in pips

#define PFX "CFG_"

string DOT = ShortToString(0x25CF);         // filled circle
string MID = " " + ShortToString(0x00B7) + " "; // middle dot

// Capifront colours
#define C_BG      C'17,14,32'
#define C_VIOLET  C'124,92,255'
#define C_VIOLET2 C'178,160,255'
#define C_TEXT    C'236,233,255'
#define C_MUTED   C'150,143,190'
#define C_LINE    C'48,42,84'
#define C_TRACK   C'45,39,80'
#define C_GREEN   C'34,197,94'
#define C_AMBER   C'245,158,11'
#define C_RED     C'239,68,68'

CTrade   g_trade;
long     g_login = 0;
string   g_gv = "";          // global-variable prefix for this login
string   g_planName = "";
double   g_dailyPct = 5, g_overallPct = 10, g_targetPct = 0;
int      g_minDays = 4;
double   g_size = 0;         // account size every limit is based on
bool     g_sizeGuessed = false;
datetime g_day = 0;          // current broker day (00:00 server time)
double   g_anchor = 0;       // equity at 00:00 server time
bool     g_anchorEst = false;
int      g_tradeDays = 0;
double   g_riskPct = 1, g_slPips = 20;
datetime g_warnDay = 0, g_stopDay = 0, g_breachDay = 0;
uint     g_lastClose = 0;
bool     g_min = false;      // panel collapsed to the two "can still lose" lines
int      g_timerTicks = 0;
double   g_sc = 1.0;
int      g_pw = 290, g_ph = 420, g_px = 10, g_py = 12;

//+------------------------------------------------------------------+
int OnInit()
  {
   PlanSetup();
   g_sc = MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0);
   g_pw = S(290);
   g_riskPct = InpRiskPct > 0 ? InpRiskPct : 1;
   g_slPips = InpSlPips > 0 ? InpSlPips : 20;
   g_trade.SetDeviationInPoints(50);
   g_min = GlobalVariableCheck("CFG_min") && GlobalVariableGet("CFG_min") > 0.5;
   g_login = 0;
   g_day = 0;
   EventSetTimer(1);
   Check();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();
  }

void OnTick()  { Check(); }

void OnTimer()
  {
   // refresh trading days / account size once a minute (history can arrive late after login)
   if(++g_timerTicks >= 60 && g_day != 0)
     {
      g_timerTicks = 0;
      double ch;
      bool flat;
      ScanHistory(ch, flat);
     }
   Check();
  }

void OnTrade()
  {
   if(g_day == 0)
      return;
   double ch;
   bool flat;
   ScanHistory(ch, flat);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
     {
      double v = StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT));
      if(sparam == PFX + "er")
        {
         if(v > 0 && v <= 10)
            g_riskPct = v;
         ObjectSetString(0, sparam, OBJPROP_TEXT, Num(g_riskPct));
        }
      else if(sparam == PFX + "es")
        {
         if(v > 0 && v <= 100000)
            g_slPips = v;
         ObjectSetString(0, sparam, OBJPROP_TEXT, Num(g_slPips));
        }
      Check();
     }
   else if(id == CHARTEVENT_OBJECT_CLICK && sparam == PFX + "btn")
     {
      g_min = !g_min;
      GlobalVariableSet("CFG_min", g_min ? 1 : 0);
      ObjectsDeleteAll(0, PFX);  // rebuild so the background stays underneath
      Check();
     }
   else if(id == CHARTEVENT_CHART_CHANGE)
      Check();
  }

//+------------------------------------------------------------------+
//| Plan limits, copied from capifront.com/trading-rules              |
//+------------------------------------------------------------------+
void PlanSetup()
  {
   g_dailyPct = 5;
   g_overallPct = 10;
   g_minDays = 4;
   g_targetPct = 0;
   switch(InpPlan)
     {
      case CF_ONE_STEP:   g_planName = "One-Step";         g_targetPct = 10; break;
      case CF_TWO_P1:     g_planName = "Two-Step Phase 1"; g_targetPct = 10; break;
      case CF_TWO_P2:     g_planName = "Two-Step Phase 2"; g_targetPct = 5;  break;
      case CF_THREE:      g_planName = "Three-Step";       g_targetPct = 6;  g_minDays = 3; break;
      case CF_PRO:        g_planName = "Capifront Pro";    g_targetPct = 8;  g_minDays = 0; g_dailyPct = 6; g_overallPct = 12; break;
      case CF_FUNDED:     g_planName = "Funded / Instant"; g_minDays = 0; break;
      case CF_PRO_FUNDED: g_planName = "Funded Pro";       g_minDays = 0; g_dailyPct = 6; g_overallPct = 12; break;
     }
  }

datetime DayStart(datetime t) { return t - (t % 86400); }

//+------------------------------------------------------------------+
//| One pass over the deal history: account size (first deposit),    |
//| trading days, today's balance change and whether the account     |
//| was flat at 00:00 server time.                                   |
//+------------------------------------------------------------------+
void ScanHistory(double &todayChange, bool &flatAtMidnight)
  {
   todayChange = 0;
   flatAtMidnight = true;
   double firstDeposit = 0;
   datetime days[];
   int nDays = 0;
   ulong inPos[];
   datetime inTime[];
   int nIn = 0;
   if(HistorySelect(0, TimeCurrent() + 86400))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0)
            continue;
         datetime t = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
         long type  = HistoryDealGetInteger(tk, DEAL_TYPE);
         long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
         double pnl = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP)
                      + HistoryDealGetDouble(tk, DEAL_COMMISSION) + HistoryDealGetDouble(tk, DEAL_FEE);
         if(type == DEAL_TYPE_BALANCE && firstDeposit == 0 && pnl > 0)
            firstDeposit = pnl;
         if(t >= g_day)
            todayChange += pnl;
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
            continue;
         ulong pos = (ulong)HistoryDealGetInteger(tk, DEAL_POSITION_ID);
         if(entry == DEAL_ENTRY_IN)
           {
            datetime d = DayStart(t);
            bool seen = false;
            for(int k = 0; k < nDays && !seen; k++)
               seen = (days[k] == d);
            if(!seen)
              {
               ArrayResize(days, nDays + 1);
               days[nDays++] = d;
              }
            ArrayResize(inPos, nIn + 1);
            ArrayResize(inTime, nIn + 1);
            inPos[nIn] = pos;
            inTime[nIn] = t;
            nIn++;
           }
         else if(t >= g_day)
           {
            for(int k = 0; k < nIn; k++)
               if(inPos[k] == pos && inTime[k] < g_day)
                 {
                  flatAtMidnight = false;
                  break;
                 }
           }
        }
     }
   g_tradeDays = nDays;
   if(InpAccountSize > 0)
     {
      g_size = InpAccountSize;
      g_sizeGuessed = false;
     }
   else if(firstDeposit > 0)
     {
      g_size = firstDeposit;
      g_sizeGuessed = false;
     }
   else
     {
      g_size = AccountInfoDouble(ACCOUNT_BALANCE);
      g_sizeGuessed = true;
     }
  }

//+------------------------------------------------------------------+
//| Equity at 00:00 server time. Exact when Guard was running at     |
//| midnight or the account was flat then; otherwise estimated.      |
//+------------------------------------------------------------------+
void SetupDay(bool rolledOver)
  {
   double todayChange;
   bool flat;
   ScanHistory(todayChange, flat);
   if(rolledOver)
     {
      g_anchor = AccountInfoDouble(ACCOUNT_EQUITY);
      g_anchorEst = false;
     }
   else if(GlobalVariableCheck(g_gv + "ancd") && (datetime)GlobalVariableGet(g_gv + "ancd") == g_day)
     {
      g_anchor = GlobalVariableGet(g_gv + "anc");
      g_anchorEst = GlobalVariableGet(g_gv + "ance") > 0.5;
      return;
     }
   else
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
         if(PositionGetTicket(i) > 0 && (datetime)PositionGetInteger(POSITION_TIME) < g_day)
            flat = false;
      g_anchor = AccountInfoDouble(ACCOUNT_BALANCE) - todayChange;
      g_anchorEst = !flat;
     }
   GlobalVariableSet(g_gv + "anc", g_anchor);
   GlobalVariableSet(g_gv + "ancd", (double)g_day);
   GlobalVariableSet(g_gv + "ance", g_anchorEst ? 1 : 0);
  }

//+------------------------------------------------------------------+
//| Main check: runs every second and on every tick                  |
//+------------------------------------------------------------------+
void Check()
  {
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   if(login == 0)
     {
      DrawWaiting();
      return;
     }
   if(login != g_login)
     {
      g_login = login;
      g_gv = "CFG_" + IntegerToString(login) + "_";
      g_day = 0;
     }
   datetime today = DayStart(TimeTradeServer());
   if(today != g_day)
     {
      bool rolledOver = (g_day != 0);
      g_day = today;
      SetupDay(rolledOver);
     }

   double eq           = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyAllow   = g_size * g_dailyPct / 100.0;
   double overallAllow = g_size * g_overallPct / 100.0;
   double dailyFloor   = g_anchor - dailyAllow;
   double overallFloor = g_size - overallAllow;
   double roomDay      = eq - dailyFloor;
   double roomAll      = eq - overallFloor;
   double room         = MathMin(roomDay, roomAll);
   double stopAt       = dailyAllow * InpStopRoomPct / 100.0;
   double warnAt       = dailyAllow * InpWarnRoomPct / 100.0;
   bool   locked       = GlobalVariableCheck(g_gv + "lock") && (datetime)GlobalVariableGet(g_gv + "lock") == g_day;

   int state = 0; // 0 OK, 1 warning, 2 stopped, 3 limit reached
   if(InpAutoProtect && (locked || room <= stopAt))
     {
      state = 2;
      if(PositionsTotal() > 0 || OrdersTotal() > 0)
         CloseAll();
      if(!locked)
         GlobalVariableSet(g_gv + "lock", (double)g_day);
      if(g_stopDay != g_day)
        {
         g_stopDay = g_day;
         Notify("trades closed to protect your account. Only " + Money(MathMax(room, 0), 2)
                + " was left before a loss limit. New trades are closed until the next server day.");
        }
     }
   else if(room <= warnAt)
     {
      state = 1;
      if(g_warnDay != g_day)
        {
         g_warnDay = g_day;
         Notify("careful, you can lose only " + Money(MathMax(room, 0), 2) + " more before a loss limit.");
        }
     }
   if(room <= 0)
     {
      state = 3;
      if(g_breachDay != g_day)
        {
         g_breachDay = g_day;
         Notify("equity reached a loss floor. This is likely a rule breach; please contact Capifront support.");
        }
     }
   Draw(eq, dailyAllow, overallAllow, dailyFloor, overallFloor, roomDay, roomAll, stopAt, state);
  }

void CloseAll()
  {
   uint now = GetTickCount();
   if(g_lastClose != 0 && now - g_lastClose < 3000)
      return;  // the market may be closed: retry every 3 seconds, not on every tick
   g_lastClose = now;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      g_trade.SetTypeFillingBySymbol(PositionGetString(POSITION_SYMBOL));
      g_trade.PositionClose(tk);
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk > 0)
         g_trade.OrderDelete(tk);
     }
  }

void Notify(string msg)
  {
   Alert("Capifront Guard: ", msg);
   if(InpPush && TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
      SendNotification("Capifront Guard: " + msg);
  }

bool CanTrade()
  {
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED)
          && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
  }

//+------------------------------------------------------------------+
//| Lot size that risks `risk` money with an SL of `slPips` pips     |
//+------------------------------------------------------------------+
double LotsFor(string sym, double risk, double slPips, double &pipSize)
  {
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   pipSize = (digits == 3 || digits == 5) ? point * 10 : point;
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0)
      tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0 || slPips <= 0 || pipSize <= 0)
      return -1;
   double lossPerLot = slPips * pipSize / tickSize * tickValue;
   if(lossPerLot <= 0)
      return -1;
   double lots = risk / lossPerLot;
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step > 0)
      lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN))
      return 0;
   return MathMin(lots, SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX));
  }

int VolDigits(string sym)
  {
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0 || step >= 1)
      return 0;
   return (int)MathCeil(-MathLog10(step) - 1e-9);
  }

//+------------------------------------------------------------------+
//| Formatting                                                       |
//+------------------------------------------------------------------+
string Money(double v, int dec)
  {
   string sign = v < 0 ? "-" : "";
   v = MathAbs(v);
   double scale = MathPow(10, dec);
   double r = MathRound(v * scale) / scale;
   long whole = (long)MathFloor(r + 1e-9);
   string digits = IntegerToString(whole);
   string out = "";
   int n = StringLen(digits);
   for(int i = 0; i < n; i++)
     {
      if(i > 0 && (n - i) % 3 == 0)
         out += ",";
      out += StringSubstr(digits, i, 1);
     }
   if(dec > 0)
      out += "." + IntegerToString((long)MathRound((r - whole) * scale), dec, '0');
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   return cur == "USD" || cur == "" ? sign + "$" + out : sign + out + " " + cur;
  }

string Pct(double p) { return Num(p) + "%"; }

string Num(double v)
  {
   string s = DoubleToString(v, 2);
   while(StringFind(s, ".") >= 0 && (StringSubstr(s, StringLen(s) - 1) == "0" || StringSubstr(s, StringLen(s) - 1) == "."))
     {
      bool dot = StringSubstr(s, StringLen(s) - 1) == ".";
      s = StringSubstr(s, 0, StringLen(s) - 1);
      if(dot)
         break;
     }
   return s;
  }

color RoomColor(double room, double dailyAllow)
  {
   if(room <= dailyAllow * InpStopRoomPct / 100.0)
      return C_RED;
   if(room <= dailyAllow * InpWarnRoomPct / 100.0)
      return C_AMBER;
   return C_GREEN;
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
int S(double v) { return (int)MathRound(v * g_sc); }

// Top-left, over the older bars and below the symbol name / one-click trading panel.
void Place()
  {
   g_px = S(10);
   g_py = ChartGetInteger(0, CHART_SHOW_ONE_CLICK) ? S(84) : S(28);
  }

void Button(string id, int x, int y, int w, int h, string txt)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, n, OBJPROP_FONT, "Segoe UI Semibold");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, n, OBJPROP_COLOR, C_TEXT);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR, C_TRACK);
      ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, C_VIOLET);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, n, OBJPROP_STATE, false);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, g_px + x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, g_py + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
  }

void Rect(string id, int x, int y, int w, int h, color bg, color border)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, g_px + x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, g_py + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, MathMax(w, 1));
   ObjectSetInteger(0, n, OBJPROP_YSIZE, MathMax(h, 1));
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, border);
  }

void Text(string id, int x, int y, string txt, color c, int size, bool bold, bool right)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, g_px + x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, g_py + y);
   ObjectSetString(0, n, OBJPROP_TEXT, txt == "" ? " " : txt);
   ObjectSetString(0, n, OBJPROP_FONT, bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
  }

void Edit(string id, int x, int y, int w, int h, string txt)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, n, OBJPROP_TEXT, txt);
      ObjectSetString(0, n, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, n, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(0, n, OBJPROP_COLOR, C_TEXT);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR, C_TRACK);
      ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, C_VIOLET);
      ObjectSetInteger(0, n, OBJPROP_READONLY, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, g_px + x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, g_py + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
  }

void Row(string id, int y, string key, string val, color vc)
  {
   Text(id + "k", S(12), y, key, C_MUTED, 9, false, false);
   Text(id + "v", g_pw - S(12), y, val, vc, 9, true, true);
  }

void Section(string id, int y, string title)
  {
   Rect(id + "l", S(12), y, g_pw - S(24), 1, C_LINE, C_LINE);
   Text(id, S(12), y + S(6), title, C_VIOLET2, 8, true, false);
  }

void Bar(string id, int y, double ratio, color c)
  {
   ratio = MathMax(0.0, MathMin(1.0, ratio));
   int w = g_pw - S(24);
   Rect(id + "t", S(12), y, w, S(6), C_TRACK, C_TRACK);
   Rect(id + "f", S(12), y, (int)MathRound(w * ratio), S(6), c, c);
  }

void DrawWaiting()
  {
   Place();
   Rect("bg", 0, 0, g_pw, S(60), C_BG, C_VIOLET);
   Text("t0", S(12), S(10), "CAPIFRONT GUARD", C_VIOLET2, 10, true, false);
   Text("t1", S(12), S(34), "Waiting for your MT5 account to connect...", C_MUTED, 8, false, false);
   ChartRedraw();
  }

void Draw(double eq, double dailyAllow, double overallAllow, double dailyFloor, double overallFloor,
          double roomDay, double roomAll, double stopAt, int state)
  {
   Place();
   int lh = S(19);
   int y = S(10);
   double roomToday = MathMin(roomDay, roomAll);  // today's room can never exceed what is left overall
   ObjectDelete(0, PFX + "t1");
   Rect("bg", 0, 0, g_pw, g_ph, C_BG, C_VIOLET);

   string st = "OK";
   color sc = C_GREEN;
   if(state == 1) { st = "WARNING"; sc = C_AMBER; }
   if(state == 2) { st = "STOPPED"; sc = C_RED; }
   if(state == 3) { st = "LIMIT HIT"; sc = C_RED; }
   Text("t0", S(12), y, "CAPIFRONT GUARD", C_VIOLET2, 10, true, false);
   Text("t0v", g_pw - S(46), y + S(2), DOT + " " + st, sc, 9, true, true);
   Button("btn", g_pw - S(38), y, S(26), S(22), g_min ? "+" : "-");
   y += S(30);

   if(g_min)
     {
      color cm = RoomColor(roomToday, dailyAllow);
      Row("dr", y, "You can still lose today", Money(MathMax(roomToday, 0), 2), cm);
      y += lh;
      Bar("bd", y + S(1), dailyAllow > 0 ? roomToday / dailyAllow : 0, cm);
      y += S(14);
      color cn = RoomColor(roomAll, dailyAllow);
      Row("or", y, "You can still lose overall", Money(MathMax(roomAll, 0), 2), cn);
      y += lh;
      Bar("bo", y + S(1), overallAllow > 0 ? roomAll / overallAllow : 0, cn);
      y += S(18);
      FinishPanel(y);
      return;
     }

   Row("pl", y, "Plan", g_planName + MID + Money(g_size, 0) + (g_sizeGuessed ? " (set size!)" : ""), g_sizeGuessed ? C_AMBER : C_TEXT);
   y += lh;
   Row("eq", y, "Equity now", Money(eq, 2), C_TEXT);
   y += lh + S(6);

   Section("s1", y, "TODAY" + MID + "MAX DAILY LOSS " + Pct(g_dailyPct));
   y += S(24);
   Row("an", y, "Equity at 00:00 server", Money(g_anchor, 2) + (g_anchorEst ? " (est.)" : ""), g_anchorEst ? C_AMBER : C_TEXT);
   y += lh;
   Row("df", y, "Daily floor", Money(dailyFloor, 2), C_TEXT);
   y += lh;
   color cd = RoomColor(roomToday, dailyAllow);
   Row("dr", y, "You can still lose today", Money(MathMax(roomToday, 0), 2), cd);
   y += lh;
   Bar("bd", y + S(1), dailyAllow > 0 ? roomToday / dailyAllow : 0, cd);
   y += S(16);

   Section("s2", y, "OVERALL" + MID + "MAX LOSS " + Pct(g_overallPct));
   y += S(24);
   Row("of", y, "Overall floor", Money(overallFloor, 2), C_TEXT);
   y += lh;
   color co = RoomColor(roomAll, dailyAllow);
   Row("or", y, "You can still lose overall", Money(MathMax(roomAll, 0), 2), co);
   y += lh;
   Bar("bo", y + S(1), overallAllow > 0 ? roomAll / overallAllow : 0, co);
   y += S(16);

   Section("s3", y, "PROGRESS");
   y += S(24);
   if(g_targetPct > 0)
     {
      double target = g_size * g_targetPct / 100.0;
      double profit = AccountInfoDouble(ACCOUNT_BALANCE) - g_size;
      Row("tg", y, "Profit target " + Pct(g_targetPct) + " (closed)", Money(profit, 0) + " / " + Money(target, 0),
          profit >= target ? C_GREEN : C_TEXT);
      y += lh;
      Bar("bt", y + S(1), target > 0 ? profit / target : 0, C_VIOLET);
      y += S(14);
     }
   else
     {
      Row("tg", y, "Profit target", "None (funded)", C_TEXT);
      y += lh;
     }
   if(g_minDays > 0)
      Row("td", y, "Trading days", IntegerToString(g_tradeDays) + " / " + IntegerToString(g_minDays),
          g_tradeDays >= g_minDays ? C_GREEN : C_TEXT);
   else
      Row("td", y, "Trading days", IntegerToString(g_tradeDays) + " (no minimum)", C_TEXT);
   y += lh + S(6);

   Section("s4", y, "LOT SIZE" + MID + _Symbol);
   y += S(24);
   Text("lrk", S(12), y + S(3), "Risk %", C_MUTED, 9, false, false);
   Edit("er", S(62), y, S(50), S(22), Num(g_riskPct));
   Text("lsk", S(128), y + S(3), "SL pips", C_MUTED, 9, false, false);
   Edit("es", S(184), y, S(56), S(22), Num(g_slPips));
   y += S(30);
   double risk = g_size * g_riskPct / 100.0;
   double pip = 0;
   double lots = LotsFor(_Symbol, risk, g_slPips, pip);
   string lotTxt = lots < 0 ? "n/a" : (lots == 0 ? "below min lot" : DoubleToString(lots, VolDigits(_Symbol)) + " lots");
   Row("lt", y, "Lots for " + Money(risk, 0) + " risk", lotTxt, lots > 0 ? C_VIOLET2 : C_AMBER);
   y += lh;
   Text("lp", S(12), y, "1 pip = " + DoubleToString(pip, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) + " on " + _Symbol,
        C_MUTED, 8, false, false);
   y += S(16);
   if(risk > MathMax(roomToday, 0))
     {
      Text("lw", S(12), y, "This risk is more than today's room left!", C_AMBER, 8, true, false);
      y += S(16);
     }
   else
      ObjectDelete(0, PFX + "lw");
   y += S(4);

   string foot;
   color fc = C_MUTED;
   if(state == 2)
     {
      foot = "Stopped: new trades close until the next server day";
      fc = C_RED;
     }
   else if(!InpAutoProtect)
     {
      foot = "Auto-close is OFF: warnings only";
      fc = C_AMBER;
     }
   else if(!CanTrade())
     {
      foot = "Turn on Algo Trading so Guard can close trades";
      fc = C_AMBER;
     }
   else
      foot = "Auto-close ON when " + Money(stopAt, 0) + " or less is left";
   Text("f1", S(12), y, foot, fc, 8, false, false);
   y += S(16);
   Text("f2", S(12), y, "Guidance only" + MID + "capifront.com/guard", C_MUTED, 7, false, false);
   y += S(20);
   FinishPanel(y);
  }

void FinishPanel(int y)
  {
   if(g_ph != y)
     {
      g_ph = y;
      ObjectSetInteger(0, PFX + "bg", OBJPROP_YSIZE, g_ph);
     }
   ChartRedraw();
  }
//+------------------------------------------------------------------+
