//+------------------------------------------------------------------+
//|                                                     OssiTheGreat |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "CashCowFX"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Input parameters
input int GMT = 1; //TimeZone in respect to GMT, i.e. +1
input double RiskPercent = 1.0;  // Account risk percentage per trade
input double RiskRewardRatio = 2.5; // Risk to reward ratio
input double BreakEvenRatio = 1.3; // Risk to reward ratio for Break-Even
input color LineColor = clrRed; // Color for liquidity mark up
input int positionbuffer = 30; //Deviation for entry

// Allowed trading hours
input int amStart = 7; //Morning session start time (24-hour format)
input int amEnd = 9; //Morning session end time (24-hour format)
input int pmStart = 12; //Afternoon session start time (24-hour format)
input int pmEnd = 14; //Afternoon session start time (24-hour format)
input int amOption = 10; //Optional morning session time (am)
input int pmOption = 15; //Optional afternoon session time (pm)

// Update trading time according to user time zone
int MorningSessionStart = amStart - GMT;
int MorningSessionEnd = amEnd - GMT;
int AfternoonSessionStart = pmStart - GMT;
int AfternoonSessionEnd = pmEnd - GMT;
int OptionalMorningSessionHour = amOption - GMT;
int OptionalAfternoonSessionHour = pmOption - GMT;

// Global variables
double positionBuffer, SPREAD;
double note_long, note_short;
double previousHourHigh = DBL_MAX;
double previousHourLow = -1;
double buyStopLoss = DBL_MAX;
double sellStopLoss = 0;
double buyReturnPrice = DBL_MAX;
double sellReturnPrice = 0;
double priceValidate;
bool isExpectLong = false;
bool isExpectShort = false;
bool hasNoted = false;
bool positionTriggered  = false;
//bool hasPendingOrder = false;
bool isValidLong = true;
bool isValidShort = true;
datetime lastHour;
datetime currentHour;
int prevHourHighLine, prevHourLowLine, EntryMarkerLine, bufferLine;
ulong ticketLong = ULONG_MAX;
ulong ticketShort = ULONG_MAX;

// List to store position tickets that have had their stop loss set to break-even
ulong breakEvenPositions[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
// Set the chart timeframe to 5 minutes
   ChartSetSymbolPeriod(0, NULL, PERIOD_M5);
//---
// Set parameters
//SPREAD = 13 * _Point;
   positionBuffer = positionbuffer * _Point;

   Alert("position buffer ", positionBuffer);
   currentHour = iTime(_Symbol, PERIOD_H1, 0);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectDelete(0, "PrevHourHighLine");
   ObjectDelete(0, "PrevHourLowLine");
   ObjectDelete(0, "EntryMarkerLine");
   ObjectDelete(0, "BufferLine");
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
// Set break even on open positions
   if(PositionSelect(_Symbol))
      checkBreakEven();

   SPREAD = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
//---
// Check if the current hour is within the trading window
   if(!IsAllowedTradingHour())
     {resetParameters(); return;}
//---
// At the start of every hour, reset parameters
   datetime Hour = iTime(_Symbol, PERIOD_H1, 0);
   if(Hour != currentHour)
     {resetParameters(); drawLiquidity(); currentHour = Hour;}
//---
// Check if the second M5 bar is closed
   if(closedBarCount() < 2)
      return;
// Check for setup validity
//else checkValidSetup();

//---
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currLow = iLow(_Symbol, PERIOD_H1, 0);
   double currHigh = iHigh(_Symbol, PERIOD_H1, 0);

// Revalidate invalid setup
//revalidateSetup(currLow,currHigh);
//---
// NOTE TRADE ENTRY
   if(!hasNoted && isValidLong && isValidShort)
     {
      // If price trades below the previous hour low
      if(currLow < previousHourLow)
        {
         note_long = iHigh(_Symbol, PERIOD_H1, 0);
         drawEntryMarker(note_long + positionBuffer);

         ticketLong = PlaceBuyStopOrder();
         buyReturnPrice = currLow;
         isExpectLong = true;
         isExpectShort = false;
         hasNoted = true;
        }
      // If price trades above the previous hour high
      else
         if(currHigh > previousHourHigh)
           {
            note_short = iLow(_Symbol, PERIOD_H1, 0);
            drawEntryMarker(note_short - positionBuffer);

            ticketShort = PlaceSellStopOrder();
            sellReturnPrice = currHigh;
            isExpectShort = true;
            isExpectLong = false;
            hasNoted = true;
           }
     }
//---
// UPDATE TRADE ENTRY
   else
      if(!positionTriggered)
        {
         // If we placed BuyStop, price created a new low(new stoploss) and returned to previous stoploss
         if(isExpectLong && currentPrice >= (buyReturnPrice - SPREAD))
            ticketLong = PlaceBuyStopOrder();

         // If we placed SellStop, price created a new high(new stoploss) and returned to previous stoploss
         else
            if(isExpectShort && currentPrice <= sellReturnPrice)
               ticketShort = PlaceSellStopOrder();
        }
//---
// If Stop order has been triggered
   if(PositionSelectByTicket(ticketLong) || PositionSelectByTicket(ticketShort))
      positionTriggered = true;

//---
// Close older position if two open positions are of different types
//ManageOpenPositions();
//---
// Try again if present candle sweeps its own liquidity
   /*if (PositionSelect(_Symbol))
      {
      //set risk management
      positionTriggered  = false;
      //hasNoted = true;
      }
    //else {hasNoted = false;}*/
//---

  }
//===================================================================================================================
//===================================================================================================================
//===================================================================================================================
//+------------------------------------------------------------------+
//| Function to check if the current hour is an allowed trading hour |
//+------------------------------------------------------------------+
bool IsAllowedTradingHour()
  {
// Initiallize MQL time struct
   MqlDateTime tm = {};

// Get current time and populate time struct
   datetime currentTime = TimeCurrent(tm);

// Retrieve hour from time struct
   int Hour = tm.hour;

// If time is within trading hours
   if((Hour >= MorningSessionStart && Hour <= MorningSessionEnd) ||
      (Hour >= AfternoonSessionStart && Hour <= AfternoonSessionEnd))
      return true;

// If time is optional trading hour and no trade has been executed today
//if ((Hour == OptionalMorningSessionHour || Hour == OptionalAfternoonSessionHour)
//  && NoTradesExecutedToday())
// return true;

   return false; // Time is outside trading hour
  }
  
//+------------------------------------------------------------------+
//| Function to check if any trade has been executed today           |
//+------------------------------------------------------------------+
bool NoTradesExecutedToday()
  {
   // Get the current date as a string in "yyyy.mm.dd" format
   string currentDateStr = TimeToString(TimeCurrent(), TIME_DATE);

   // Select entire terminal history
   HistorySelect(0, TimeCurrent());

   // Get the number of deals in the history
   int totalDeals = HistoryDealsTotal();

   // Iterate through all deals
   for(int i = 0; i < totalDeals; i++)
     {
      // Get the deal ticket, skip if no deal at index i
      ulong dealTicket = HistoryDealGetTicket(i);
      if(!(dealTicket > 0)) continue; // Skip non-existent deals

      // Get the deal time and convert to a date string in "yyyy.MM.dd" format
      long dealTime = HistoryDealGetInteger(dealTicket, DEAL_TIME);
      string dealDateStr = TimeToString(dealTime, TIME_DATE);

      // Get the deal symbol
      string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);

      // If the deal was executed today, on our symbol
      if((dealDateStr == currentDateStr) && (dealSymbol == _Symbol))
         return false; // A trade was executed today
     }
   return true; // No trades were executed today
  }
  
//+------------------------------------------------------------------+
//| Function to delete all pending orders                            |
//+------------------------------------------------------------------+
void clearAllOrders()
  {
   int totalpending = OrdersTotal();
   for(int i = totalpending; i >= 0; i--)
     {
      ulong orderTicket = OrderGetTicket(i);
      if(orderTicket > 0)
         trade.OrderDelete(orderTicket);
     }
  }
  
//+------------------------------------------------------------------+
//| Function to reset parameters at the end of an hour               |
//+------------------------------------------------------------------+
void resetParameters()
  {
// Clear markups
   ObjectDelete(0, "PrevHourHighLine");
   ObjectDelete(0, "PrevHourLowLine");
   ObjectDelete(0, "EntryMarkerLine");
   ObjectDelete(0, "BufferLine");

// Clear pending orders
   clearAllOrders();

// Reset all parameters
   note_long = 0;
   note_short = 0;
   isExpectLong = false;
   isExpectShort = false;
   hasNoted = false;
   positionTriggered  = false;
   buyStopLoss = DBL_MAX;
   sellStopLoss = 0;
   buyReturnPrice = DBL_MAX;
   sellReturnPrice = 0;
   ticketLong = ULONG_MAX;
   ticketShort = ULONG_MAX;
   isValidLong = true;
   isValidShort = true;
//ArrayResize(breakEvenPositions,0);
   previousHourHigh = iHigh(_Symbol, PERIOD_H1, 1);
   previousHourLow = iLow(_Symbol, PERIOD_H1, 1);
  }
  
//+------------------------------------------------------------------+
//| Place buy stop order                                             |
//+------------------------------------------------------------------+
ulong PlaceBuyStopOrder()
  {
// if setup valid for long position
   if(isValidLong)
     {
      double currentLow = iLow(Symbol(), PERIOD_H1, 0);
      if((currentLow < buyStopLoss) || !hasNoted)
        {
         clearAllOrders();

         double entryPrice = note_long + positionBuffer;
         double lotSize = CalculateLotSize(currentLow, entryPrice);

         double stopLoss = currentLow;
         double takeProfit = entryPrice + ((MathAbs(entryPrice - stopLoss)) * RiskRewardRatio);

         trade.BuyStop(lotSize, entryPrice, _Symbol, stopLoss, takeProfit);
         ticketLong = trade.ResultOrder();

         uint resultCode = trade.ResultRetcode();
         if(resultCode != TRADE_RETCODE_DONE)
            Print("Error placing stop order");

         buyStopLoss = currentLow;
        }
     }
   return ticketLong;
  }
  
//+------------------------------------------------------------------+
//| Place sell stop order                                            |
//+------------------------------------------------------------------+
ulong PlaceSellStopOrder()
  {
//if short valid
   if(isValidShort)
     {
      double currentHigh = iHigh(Symbol(), PERIOD_H1, 0);
      if((currentHigh > sellStopLoss) || !hasNoted) ///////////*********************************
        {
         clearAllOrders();

         double entryPrice = note_short - positionBuffer;
         double lotSize = CalculateLotSize(currentHigh, entryPrice);

         double stopLoss = currentHigh;
         double takeProfit = entryPrice - ((MathAbs(stopLoss - entryPrice)) * RiskRewardRatio);

         trade.SellStop(lotSize, entryPrice, _Symbol, stopLoss, takeProfit);
         ticketShort = trade.ResultOrder();

         uint resultCode = trade.ResultRetcode();
         if(resultCode != TRADE_RETCODE_DONE)
            Print("Error placing stop order");

         sellStopLoss = currentHigh;
        }
     }
   return ticketShort;
  }
  
//+------------------------------------------------------------------+
//| Calculate lot size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPrice, double entryPrice)
  {
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   int stopLossPoints = int((MathAbs(entryPrice - stopLossPrice)) / _Point);
   double lotSize = riskAmount / (stopLossPoints * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));

   if(lotSize > maxVol) lotSize = maxVol;
   else if(lotSize < minVol) lotSize = minVol;

   return NormalizeDouble(lotSize, 2);
  }
//+------------------------------------------------------------------+
//| Function to draw previous candle liquidity lines                 |
//+------------------------------------------------------------------+
void drawLiquidity()
  {
   prevHourHighLine = ObjectCreate(0, "PrevHourHighLine", OBJ_TREND, 0, iTime(_Symbol, PERIOD_H1, 1), previousHourHigh, iTime(_Symbol, PERIOD_H1, 0), previousHourHigh);
   ObjectSetInteger(0, "PrevHourHighLine", OBJPROP_COLOR, LineColor);

   prevHourLowLine = ObjectCreate(0, "PrevHourLowLine", OBJ_TREND, 0, iTime(_Symbol, PERIOD_H1, 1), previousHourLow, iTime(_Symbol, PERIOD_H1, 0), previousHourLow);
   ObjectSetInteger(0, "PrevHourLowLine", OBJPROP_COLOR, LineColor);
  }
//+------------------------------------------------------------------+
//| Function to mark expected entry price                            |
//+------------------------------------------------------------------+
void drawEntryMarker(double price)
  {
// Draw a line that marks trade entrty price
   EntryMarkerLine = ObjectCreate(0, "EntryMarkerLine", OBJ_TREND, 0, iTime(_Symbol, PERIOD_H1, 0), price, iTime(_Symbol, PERIOD_M1, 0), price);
   ObjectSetInteger(0, "EntryMarkerLine", OBJPROP_COLOR, clrAqua);
  }
//+------------------------------------------------------------------+
//| Function to set break even                                       |
//+------------------------------------------------------------------+
void NOTcheckBreakEven()// Not functional,
  {
//2024.06.20 15:12:03.156 2024.06.03 11:55:35   failed modify #16 buy 0.4 GBPUSD sl: 1.27083, tp: 1.27408 -> sl: 1.27083, tp: 1.27408 [Invalid stops]


   int totalPositions = PositionsTotal();

// ArrayBinarySearch(breakEvenPositions, oldestTicket); ArrayBsearch()
   for(int i = 0; i < totalPositions; i++)
     {
      // Get open positions ticket, skip loop is no position
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double zeroRiskLevel = entryPrice + (type == POSITION_TYPE_BUY ? SPREAD :  - SPREAD);
      double stopLoss = PositionGetDouble(POSITION_SL);
      Alert("Stop loss", stopLoss);
      double takeProfit = PositionGetDouble(POSITION_TP);
      Alert("Take profit", takeProfit);
      double profitLevel = (type == POSITION_TYPE_BUY ? iHigh(_Symbol, PERIOD_H1, 0)  : iLow(_Symbol, PERIOD_H1, 0));

      double riskAmount = (MathAbs(entryPrice - stopLoss)) * BreakEvenRatio;
      double breakEvenPrice = entryPrice + (type == POSITION_TYPE_BUY ? riskAmount  : - riskAmount);

      bool isBreakEvenSet = ((NormalizeDouble(stopLoss, _Digits)) == zeroRiskLevel); //ArrayBsearch(breakEvenPositions, ticket) >= 0;

      // Set stop loss to entry price when position reaches break-even-ration risk to reward
      if(!isBreakEvenSet && ((type == POSITION_TYPE_BUY && profitLevel >= breakEvenPrice) ||
                             (type == POSITION_TYPE_SELL && profitLevel <= breakEvenPrice)))
        {
         Alert("Stop loss: ", stopLoss, " Zero Risk: ", zeroRiskLevel);
         if(trade.PositionModify(ticket, zeroRiskLevel, takeProfit))
           {
            // Add the ticket to the break-even list if the stop loss is successfully modified
            ArrayResize(breakEvenPositions, ArraySize(breakEvenPositions) + 1);
            breakEvenPositions[ArraySize(breakEvenPositions) - 1] = ticket;
           }
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void checkBreakEven()
  {
// Select all open positions
   int totalPositions = PositionsTotal();

// Iterate through all open positions
   for(int i = 0; i < totalPositions; i++)
     {
      // Get open position ticket, skip loop is no position at index i
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
        {
         Alert("ticket not found");
         continue;
        }

      // Get position type
      long type = PositionGetInteger(POSITION_TYPE);

      // Get positions opening price
      double entryPrice = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), _Digits);

      // Get position stop loss and take profit
      double stopLoss = PositionGetDouble(POSITION_SL);
      double takeProfit = PositionGetDouble(POSITION_TP);

      // Get current market price
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Target profit for break even, relative to breakeven ratio
      double riskAmount = MathAbs(entryPrice - stopLoss);
      double targetProfit = riskAmount * BreakEvenRatio;
      double targetProfitPrice = entryPrice + (type == POSITION_TYPE_BUY ? targetProfit : -targetProfit);

      // Price to set break even stop loss
      double breakEvenPrice = NormalizeDouble(entryPrice + (type == POSITION_TYPE_BUY ? SPREAD :  -SPREAD), _Digits); //XXXXXXXXXXXXXXXXXX Instead set at entry price check difference
      //double breakEvenPrice = entryPrice;
      //------------------------------------------------------

      // TRYING TO FIND OUT WHY 0.00000000000000000001 RUBISH
      //Alert("stop loss: ",stopLoss," Break even price: ",breakEvenPrice);

      // Skip loop If break even is set on the position already
      if((type == POSITION_TYPE_BUY && stopLoss >= entryPrice) ||
         (type == POSITION_TYPE_SELL && stopLoss <= entryPrice))
         continue; //Break even already set

      // If price gets to target profit
      else
         if((type == POSITION_TYPE_BUY && currentPrice >= targetProfitPrice) ||
            (type == POSITION_TYPE_SELL && currentPrice <= targetProfitPrice))
           {
            // Modify stop loss to break even
            if(trade.PositionModify(ticket, breakEvenPrice, takeProfit))
              {
               // Add the ticket to the breakEvenPositions list if the stop loss is successfully modified
               ArrayResize(breakEvenPositions, ArraySize(breakEvenPositions) + 1);
               breakEvenPositions[ArraySize(breakEvenPositions) - 1] = ticket;
              }
           }
      // If breakEvenPositions list is holding more than ten tickets, delete the oldest
      if(ArraySize(breakEvenPositions) > 10)
         ArrayRemove(breakEvenPositions, 0, 1);
     }
  }


//+------------------------------------------------------------------+
//| Function to count closed M5 candles                              |
//+------------------------------------------------------------------+
int closedBarCount()
  {
   datetime start = iTime(Symbol(), PERIOD_H1, 0);
   int count = Bars(Symbol(), PERIOD_M5, start, TimeCurrent());

   return count - 1;
  }
//+------------------------------------------------------------------+
//| Function to check if a setup is valid                            |
//+------------------------------------------------------------------+
void checkValidSetup()
  {
   if(closedBarCount() == 2)
     {
      bool isBuyTakeout = (iClose(_Symbol, PERIOD_M5, 1) > MathMax(iOpen(_Symbol, PERIOD_M5, 2), iClose(_Symbol, PERIOD_M5, 2)));
      bool isSellTakeout = (iClose(_Symbol, PERIOD_M5, 1) < MathMin(iOpen(_Symbol, PERIOD_M5, 2), iClose(_Symbol, PERIOD_M5, 2)));

      if((iLow(_Symbol, PERIOD_M5, 2) < previousHourLow) && isBuyTakeout)
        {
         isValidLong = false;
         Alert("XXXXX Invalid long setup");
         priceValidate = MathMin(iLow(_Symbol, PERIOD_M5, 1), iLow(_Symbol, PERIOD_M5, 2)); //reconfirm
        }

      else
         if((iHigh(_Symbol, PERIOD_M5, 2) > previousHourHigh) && isSellTakeout)
           {
            isValidShort = false;
            Alert("XXXXX Invalid short setup");
            priceValidate = MathMax(iHigh(_Symbol, PERIOD_M5, 1), iHigh(_Symbol, PERIOD_M5, 2));
           }
      //if first candle sweeps low, and second closes above - long invalid
      //else if first candle sweeps high, and second closes below - short invalid
      //store max first and second candle low or high
     }
  }
//+------------------------------------------------------------------+
//| Function to check if an invalid setup has been validated         |
//+------------------------------------------------------------------+
void revalidateSetup(double Low, double High)
  {
// If a setup was invalidated
   if(!isValidLong || !isValidShort)
     {
      // Revalidate long if a new low has been created by the hour
      if(Low < priceValidate)
         isValidLong = true;

      // Revalidate short if a new high has been created by the hour
      if(High > priceValidate)
         isValidShort = true;
     }
  }
//+------------------------------------------------------------------+
//time prefferrences, 11am
// numerous opportunities lie outside trading hours but within specific sesisons
// remove the times and first candle and second candle sweep, increase the entry
// the good moves go/run, 1 or 2 good moves as target per week
// no 8pm-12am
