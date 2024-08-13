//+------------------------------------------------------------------+
//|                                             MovingAverageBot.mq5 |
//|                                                        CashCowFX |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "CashCowFX"
#property link      "https://www.mql5.com"
#property version   "1.00"


input int FastMAPeriod = 12;
input int SlowMAPeriod = 26;

double fastMA, slowMA;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Calculate the moving averages
   fastMA = iMA(NULL, 0, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
   slowMA = iMA(NULL, 0, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
   
   // Check for a crossover
   if (fastMA > slowMA && PositionSelect(Symbol()) == false)
     {
      // Buy signal
      int ticket = OrderSend(Symbol(), OP_BUY, 0.1, Ask, 2, 0, 0, "Buy Order", 0, 0, clrGreen);
      if (ticket < 0)
        Print("Error opening order: ", GetLastError());
     }
   else if (fastMA < slowMA && PositionSelect(Symbol()) == true)
     {
      // Sell signal
      int ticket = OrderClose(OrderTicket(), OrderLots(), Bid, 2, clrRed);
      if (ticket < 0)
        Print("Error closing order: ", GetLastError());
     }
  }
//+------------------------------------------------------------------+
