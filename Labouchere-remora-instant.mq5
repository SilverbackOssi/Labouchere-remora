//+------------------------------------------------------------------+
//|                                    Labouchere-remora-instant.mq5 |
//|                                                        CashCowFX |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//Description: 
//
//+------------------------------------------------------------------+
#property copyright "CashCowFX"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#include <Trade\Trade.mqh>
CTrade trade;
//+------------------------------------------------------------------+
// Input parameters
input double gridSize = 10.0;                                     // Debugging; Grid size
input double Lot = 0.05;                                          // Base lot size for 1 unit
input int MaxLosses = 12;                                         // Maximum number of consecutive losses until sequence reset
input int NightStartHour = 19;
input int NightEndHour = 3;

// Global variables
double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);     // Symbol minimum allowed trading volume
double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);     // Symbol maximum allowed trading volume
double LotSize;                                                   // Starting lot size
int lastWager;
int sequence[];
int consecutiveLosses = 0;
long placeHolder = 1001;                                          // Expert default place holder
bool positionWasBuy = true;                                       // Last position type, Buy/Sell
bool wasProfit = true;                                            // P/L of last closed position
string eaComment = "RemoraLabouchere";                            // EA unique identifier
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize all parameters and open buy position
   StartBot();
   
return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
 {
   // Clear comments
   // Close all positions opened by EA
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void OnTick()
{
   //if (isNightTime()) return;
   // If closed position, get last position type and profit status
   if (!PositionSelect(_Symbol)) 
      {
      //store to open once, ensure position is opened
      // Get closed position profit
      CheckLastProfit();
      
      // Update labouchere sequence
      UpdateSequence(wasProfit);
      
      // If closed profit, open position to continue trend
      if (wasProfit) OpenPosition(positionWasBuy);
      
      // If closed loss, open position oposite to last position type
      else 
         {
         //long newPositionType = (positionWasBuy==POSITION_TYPE_BUY ? POSITION_TYPE_SELL:POSITION_TYPE_BUY);
         positionWasBuy = !positionWasBuy;
         OpenPosition(positionWasBuy);
         }
      }
   else setPositionExit();
   // Debug
   //ExpertRemove();
}
//===================================================================================================================|
//===================================================================================================================|
//===================================================================================================================|
 
// FUNTION STARTS EA WITH BUY POSITION
void StartBot()
   {
   // Initialize the Labouchere sequence
   InitializeSequence();
   
   // Initialise the starting lot
   LotSize = (Lot < minVol ? minVol: Lot);
   
   // Start the bot with a buy position
   trade.Buy(LotSize,_Symbol,0);
   CheckError("starting bot with instant buy");
   positionWasBuy = POSITION_TYPE_BUY;
   //ulong ticket = trade.ResultOrder();
   
   }

// FUNTION INITIALIZES LABOUCHERE SEQUENCE
void InitializeSequence()
{
    // Set to original sequence
    ArrayResize(sequence, 2);
    sequence[0] = 1;
    sequence[1] = 2;
    
    //Debug
    Alert("sequence reset to:");
    ArrayPrint(sequence);
}

// FUNTION GETS LAST POSITION PROFIT/LOSS AND POSITION TYPE
void CheckLastProfit()
{
   // Position type set to default
   long positionType = placeHolder;
   
   // Select entire terminal history
   HistorySelect(0,TimeCurrent());
   
   // Get the number of deals in the history
   int totalDeals = HistoryDealsTotal();
   
   for (int i = totalDeals - 1; i >= 0; i--)
     {
     // Get the deal ticket
     ulong dealTicket = HistoryDealGetTicket(i);
     
     if(!(dealTicket > 0)) continue; // Skip non-existent deals
     if (HistoryDealGetString(dealTicket,DEAL_SYMBOL) != _Symbol) continue; // Skip unrelated deals
     
     // Get deal type
     positionType = HistoryDealGetInteger(dealTicket,DEAL_TYPE);
     
     // Get deal profit
     double positionProfit = HistoryDealGetDouble(dealTicket,DEAL_PROFIT);
     
     // Update last position P/L status
     wasProfit = (positionProfit > 0);
     
     // Debug
     
     break; // Only process the most recent closed order
     }
   //return positionType; 
}

// FUNCTION OPENS NEW POSITION
void OpenPosition(bool LONG)
{
   // Calculate lot size
   lastWager = CalculateWager();
   double volume = lastWager * LotSize;
   
   // Open long
   if (LONG) 
      {
      trade.Buy(volume,_Symbol,0);
      CheckError("opening buy position");
      positionWasBuy = true;
      }
    
   // Open short
   else 
      {
      trade.Sell(volume,_Symbol,0);
      CheckError("opening sell position");
      positionWasBuy = false;
      }
}

// FUNTION CALCULATES WAGER FROM CURRENT SEQUENCE
int CalculateWager()
{
   // If sequence is cleared return default wager
   if (ArraySize(sequence) == 0)
        return 1;
    
   // If sequence contains one element return it
   if (ArraySize(sequence) == 1)
        return sequence[0];
   
   // Return first + last element 
   return sequence[0] + sequence[ArraySize(sequence) - 1];
}

// FUNTION UPDATES THE LABOUCHERE SEQUENCE
void UpdateSequence(bool closeProfit)
{
   // If closed profit
   if (closeProfit)
    {
        // Remove first and last numbers from the sequence
        if (ArraySize(sequence) > 1)
         {
           ArrayRemove(sequence, 0, 1);
           ArrayRemove(sequence, (ArraySize(sequence) - 1), 1);
         }
        
        // Empty the lambouchere sequence
        else if (ArraySize(sequence) == 1)
           ArrayResize(sequence, 0);
        
        // Reset consecutive losses count
        consecutiveLosses = 0;
    }
    
    // If closed loss
    else 
      {
        // Add the bet size to the end of the sequence
        int wagerSize = lastWager;
        ArrayResize(sequence, ArraySize(sequence) + 1);
        sequence[ArraySize(sequence) - 1] = wagerSize;
        
        // Count consecutive losses
        consecutiveLosses++;
        
      }
    // Debug
    Alert("Updated sequence:");
    ArrayPrint(sequence);
}

// FUNTION SETS STOPLOSS/TAKEPROFIT ON OPEN POSITIONS
void setPositionExit()
{
   // Select all open positions
   int totalPositions = PositionsTotal();

   // Iterate through all open positions
   for(int i = 0; i < totalPositions; i++)
     {
      // Get open position ticket
      ulong Ticket = PositionGetTicket(i);
      
      //if open position does not have stop loss or take profit
      if (PositionGetString(POSITION_SYMBOL) == _Symbol && (PositionGetDouble(POSITION_SL) == 0 || PositionGetDouble(POSITION_TP) == 0))
         {
         double positionOpen = PositionGetDouble(POSITION_PRICE_OPEN);
         double stopLoss = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? positionOpen-gridSize : positionOpen+gridSize);
         double takeProfit = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? positionOpen+gridSize : positionOpen-gridSize);
         
         // Modify position according to grid size
         trade.PositionModify(Ticket,stopLoss,takeProfit);
         CheckError("modifing stoploss/takeprofit");
         
         // Debug
         
         }
      }
}

// FUNTION REPORTS TRADE EXECUTION ERRORS
void CheckError(string errorLocation)
{
  // Get the retcode of last order
  uint resultCode = trade.ResultRetcode();
  
  // Check if order was successfully executed by server
  if (resultCode != TRADE_RETCODE_DONE)
   {
      Print("Error ",errorLocation);
      Print("error message as: ",GetLastError());
      Print("with RETcode: ", resultCode);
      
      // Reset 'GetLastError()' variable
      ResetLastError();
   }
}

// FUNCTION CONFIRMS TRADING HOUR
bool isNightTime()
  {
   MqlDateTime tm={};
   datetime currentTime = TimeCurrent(tm);
   int currentHour = tm.hour;

   if(currentHour >= NightStartHour || currentHour < NightEndHour)
      return true;

   return false;
  }
//===================================================================================================================|
//===================================================================================================================|
//===================================================================================================================|
// TO - DO
/*
- use buy/sell code {1000/1001} instead of DEAL_TYPE_BUY/SELL
- make grid size automatic, set minimum
- make grid static with stop orders
- ensure sequence is properly updated
- ensure all operations are symbol specific
- test gold = 8am - 11am
- ensure within trading volume max and min
*/
