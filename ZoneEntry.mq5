//+------------------------------------------------------------------+
//|                                                      ZoneEntry.mq5 |
//|                                           Copyright 2024, junmt  |
//|                           https:// |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, junmt"
#property link "https://"
#property version "1.00"
#include <Expert\Money\MoneyFixedMargin.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>
CPositionInfo m_position; // trade position object
CTrade m_trade;           // trading object
CSymbolInfo m_symbol;     // symbol info object
CMoneyFixedMargin m_money;
//---
input double InpStopLoss = 10.0;               // StopLoss
input double InpTakeProfit = 100.0;            // TakeProfit
input double InpTrailingStop = 50.0;           // TrailingStop
input bool AutoLot = false;                    // AutoLot (percent from a free margin)
input double Risk = 10;                        // Risk percent from a free margin
input double ManualLots = 0.01;                // ManualLots
input ulong m_magic = 123;                     // Magic number
input string TradeComment = "ZoneEntry";       // TradeComment
input ulong InpSlippage = 1;                   // Slippage
input int MaxOrders = 10;                      // Max Orders
input int max_position = 1;                    // Max Position
input bool IsManualOrdersAndPositions = false; // Manual Position
//---
int LotDigits;
//---
double ExtStopLoss = 0.0;
double ExtTakeProfit = 0.0;
double ExtTrailingStop = 0.0;
ulong ExtSlippage = 0;
ENUM_ACCOUNT_MARGIN_MODE m_margin_mode;
double m_adjusted_point; // point value adjusted for 3 or 5 points

int atr;

string input_names[] = {"Support1", "Support2", "Support3",
                        "Resistance1", "Resistance2", "Resistance3"};

int barcount = 0;
datetime bartime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    SetMarginMode();
    if (!IsHedging())
    {
        Print("Hedging only!");
        return (INIT_FAILED);
    }
    //---
    m_symbol.Name(Symbol()); // sets symbol name
    if (!RefreshRates())
    {
        Print("Error RefreshRates. Bid=",
              DoubleToString(m_symbol.Bid(), Digits()),
              ", Ask=", DoubleToString(m_symbol.Ask(), Digits()));
        return (INIT_FAILED);
    }
    m_symbol.Refresh();
    //---
    m_trade.SetExpertMagicNumber(m_magic); // sets magic number

    //--- tuning for 3 or 5 digits
    int digits_adjust = 10;
    if (m_symbol.Digits() == 3 || m_symbol.Digits() == 5)
        digits_adjust = 100;
    double point = m_symbol.Point();
    m_adjusted_point = point * digits_adjust;

    ExtStopLoss = InpStopLoss * m_adjusted_point * -1;
    ExtTakeProfit = InpTakeProfit * m_adjusted_point;
    ExtTrailingStop = InpTrailingStop * m_adjusted_point;
    ExtSlippage = InpSlippage * digits_adjust;

    m_trade.SetDeviationInPoints(ExtSlippage);
    //---
    m_money.Init(GetPointer(m_symbol), Period(), m_adjusted_point);
    m_money.Percent(10); // 10% risk

    atr = iATR(m_symbol.Name(), PERIOD_H1, 14);

    // 入力フィールドの作成
    CreatePanel();

    return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // パネル削除
    DeletePanel();
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //---
    if (IsTradeStartButtonPressed())
    {
        entryAll();
        resetButton();
    }
    else if (IsTradeStopButtonPressed())
    {
        removeAll();
        resetButton();
    }

    setBuyPositionTakeProfit();
    setSellPositionTakeProfit();

    // プロフィットをとる
    if (InpTakeProfit > 0)
    {
        for (int i = 0; i < PositionsTotal(); i++)
        {
            m_position.SelectByIndex(i);
            if (m_position.Symbol() != Symbol() ||
                (m_position.Magic() != m_magic && !IsManualOrdersAndPositions))
            {
                continue;
            }
            double profit = 0.0;
            if (m_position.PositionType() == POSITION_TYPE_BUY)
            {
                profit = m_position.PriceCurrent() - m_position.PriceOpen();
            }
            else
            {
                profit = m_position.PriceOpen() - m_position.PriceCurrent();
            }
            if (profit >= ExtTakeProfit)
            {
                m_trade.PositionClose(m_position.Ticket());
            }
        }
    }

    // ロスカット　ストップが自動で設定されるためコメントアウト
    // if (InpStopLoss > 0)
    // {
    //     for (int i = 0; i < PositionsTotal(); i++)
    //     {
    //         m_position.SelectByIndex(i);
    //         if (m_position.Symbol() != Symbol() ||
    //             m_position.Magic() != m_magic)
    //         {
    //             continue;
    //         }
    //         double profit = 0.0;
    //         if (m_position.PositionType() == POSITION_TYPE_BUY)
    //         {
    //             profit = m_position.PriceCurrent() - m_position.PriceOpen();
    //         }
    //         else
    //         {
    //             profit = m_position.PriceOpen() - m_position.PriceCurrent();
    //         }
    //         if (profit <= ExtStopLoss)
    //         {
    //             m_trade.PositionClose(m_position.Ticket());
    //         }
    //     }
    // }

    // 計算量が多いので、PERIOD_CURRENT間隔で計算を行う
    //--- ゼロバーの開いた時間を取得する
    datetime currbar_time = iTime(Symbol(), PERIOD_H1, 0);
    bartime = iTime(Symbol(), PERIOD_M1, 0);
    //--- 新しいバーが到着すると開いた時刻が変わる
    if (bartime == currbar_time)
    {
        return;
    }

    for (int i = 0; i < PositionsTotal(); i++)
    {
        m_position.SelectByIndex(i);

        if (m_position.Symbol() != m_symbol.Name() ||
            (m_position.Magic() != m_magic && !IsManualOrdersAndPositions))
        {
            continue;
        }

        double currentPrice = m_position.PriceCurrent();
        double openPrice = m_position.PriceOpen();

        if (m_position.PositionType() == POSITION_TYPE_BUY)
        {
            if (ExtTrailingStop > 0)
            {
                double profit = currentPrice - openPrice;
                if (profit > ExtTrailingStop &&
                    m_position.PriceCurrent() - ExtTrailingStop >
                        m_position.StopLoss())
                {
                    double sl = NormalizeDouble(currentPrice - ExtTrailingStop,
                                                m_symbol.Digits());
                    m_trade.PositionModify(m_position.Ticket(), sl,
                                           m_position.TakeProfit());
                }
            }
        }
        if (m_position.PositionType() == POSITION_TYPE_SELL)
        {
            if (ExtTrailingStop > 0)
            {
                double profit = openPrice - currentPrice;
                if (profit > ExtTrailingStop &&
                    m_position.PriceCurrent() + ExtTrailingStop <
                        m_position.StopLoss())
                {
                    double sl = NormalizeDouble(currentPrice + ExtTrailingStop,
                                                m_symbol.Digits());
                    m_trade.PositionModify(m_position.Ticket(), sl,
                                           m_position.TakeProfit());
                }
            }
        }
    }

    return;
}
//+------------------------------------------------------------------+
//| Close Positions                                                  |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE pos_type)
{
    for (int i = PositionsTotal() - 1; i >= 0;
         i--) // returns the number of current orders
        if (m_position.SelectByIndex(i))
            if (m_position.Symbol() == Symbol() &&
                (m_position.Magic() == m_magic || IsManualOrdersAndPositions))
                if (m_position.PositionType() == pos_type)
                    m_trade.PositionClose(m_position.Ticket());
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double LOT()
{
    double lots = 0.0;
    //---
    if (AutoLot)
    {
        lots = 0.0;
        //--- getting lot size for open long position (CMoneyFixedMargin)
        double sl = 0.0;
        double check_open_long_lot = m_money.CheckOpenLong(m_symbol.Ask(), sl);

        if (check_open_long_lot == 0.0)
            return (0.0);

        //--- check volume before OrderSend to avoid "not enough money" error
        //(CTrade)
        double chek_volime_lot =
            m_trade.CheckVolume(m_symbol.Name(), check_open_long_lot,
                                m_symbol.Ask(), ORDER_TYPE_BUY);

        if (chek_volime_lot != 0.0)
            if (chek_volime_lot >= check_open_long_lot)
                lots = check_open_long_lot;
    }
    else
        lots = ManualLots;
    //---
    return (LotCheck(lots));
}
//+------------------------------------------------------------------+
//| Lot Check                                                        |
//+------------------------------------------------------------------+
double LotCheck(double lots)
{
    //--- calculate maximum volume
    double volume = NormalizeDouble(lots, 2);
    double stepvol = m_symbol.LotsStep();
    if (stepvol > 0.0)
        volume = stepvol * MathFloor(volume / stepvol);
    //---
    double minvol = m_symbol.LotsMin();
    if (volume < minvol)
        volume = 0.0;
    //---
    double maxvol = m_symbol.LotsMax();
    if (volume > maxvol)
        volume = maxvol;
    return (volume);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetMarginMode(void)
{
    m_margin_mode =
        (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsHedging(void)
{
    return (m_margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
}
//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates()
{
    //--- refresh rates
    if (!m_symbol.RefreshRates())
        return (false);
    //--- protection against the return value of "zero"
    if (m_symbol.Ask() == 0 || m_symbol.Bid() == 0)
        return (false);
    //---
    return (true);
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get value of buffers                                             |
//+------------------------------------------------------------------+
double iGetArray(const int handle, const int buffer, const int start_pos,
                 const int count, double &arr_buffer[])
{
    bool result = true;
    if (!ArrayIsDynamic(arr_buffer))
    {
        Print("This a no dynamic array!");
        return (false);
    }
    ArrayFree(arr_buffer);
    //--- reset error code
    ResetLastError();
    //--- fill a part of the iBands array with values from the indicator buffer
    int copied = CopyBuffer(handle, buffer, start_pos, count, arr_buffer);
    if (copied != count)
    {
        //--- if the copying fails, tell the error code
        PrintFormat("Failed to copy data from the indicator, error code %d",
                    GetLastError());
        //--- quit with zero result - it means that the indicator is considered
        // as not calculated
        return (false);
    }
    return (result);
}

//+------------------------------------------------------------------+
//| パネルの作成                                                     |
//+------------------------------------------------------------------+
void CreatePanel()
{
    // サポートとレジスタンスのパネルを作成
    CreateSupportAndResistanceInputs();

    // ボタンの作成
    CreateTradeStartButton();
    CreateTradeStopButton();
}
//+------------------------------------------------------------------+
//| パネルの削除                                                     |
//+------------------------------------------------------------------+
void DeletePanel()
{
    // パネル削除
    for (int i = 0; i < ArraySize(input_names); i++)
    {
        string name = input_names[i];
        ObjectDelete(0, name);
    }
    ObjectDelete(0, "TradeStartButton");
    ObjectDelete(0, "TradeStopButton");
}
//+------------------------------------------------------------------+
//| サポートとレジスタンスの入力フィールドの作成                     |
//+------------------------------------------------------------------+
void CreateSupportAndResistanceInputs()
{
    int y_offset = 30;

    for (int i = 0; i < ArraySize(input_names); i++)
    {
        string name = input_names[i];
        ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 20);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y_offset);
        ObjectSetInteger(0, name, OBJPROP_XSIZE, 100);
        ObjectSetInteger(0, name, OBJPROP_YSIZE, 20);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrAqua);
        y_offset += 20;
    }
}
//+------------------------------------------------------------------+
//| 指値作成ボタン                                         |
//+------------------------------------------------------------------+
void CreateTradeStartButton()
{
    string button_name = "TradeStartButton";
    ObjectCreate(0, button_name, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, button_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, button_name, OBJPROP_XDISTANCE, 20);
    ObjectSetInteger(0, button_name, OBJPROP_YDISTANCE, 190);
    ObjectSetInteger(0, button_name, OBJPROP_XSIZE, 100);
    ObjectSetInteger(0, button_name, OBJPROP_YSIZE, 30);
    ObjectSetString(0, button_name, OBJPROP_TEXT, "指値追加");
    ObjectSetInteger(0, button_name, OBJPROP_COLOR, clrBlue);
}
//+------------------------------------------------------------------+
//| 指値作成ボタンが押されたかを確認                             |
//+------------------------------------------------------------------+
bool IsTradeStartButtonPressed()
{
    string button_name = "TradeStartButton";
    return (ObjectGetInteger(0, button_name, OBJPROP_STATE) == 1);
}
//+------------------------------------------------------------------+
//| トレード停止ボタンの作成                                         |
//+------------------------------------------------------------------+
void CreateTradeStopButton()
{
    string button_name = "TradeStopButton";
    ObjectCreate(0, button_name, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, button_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, button_name, OBJPROP_XDISTANCE, 20);
    ObjectSetInteger(0, button_name, OBJPROP_YDISTANCE, 220);
    ObjectSetInteger(0, button_name, OBJPROP_XSIZE, 100);
    ObjectSetInteger(0, button_name, OBJPROP_YSIZE, 30);
    ObjectSetString(0, button_name, OBJPROP_TEXT, "指値削除");
    ObjectSetInteger(0, button_name, OBJPROP_COLOR, clrRed);
}
//+------------------------------------------------------------------+
//| トレード停止ボタンが押されたかを確認                             |
//+------------------------------------------------------------------+
bool IsTradeStopButtonPressed()
{
    string button_name = "TradeStopButton";
    return (ObjectGetInteger(0, button_name, OBJPROP_STATE) == 1);
}
//+------------------------------------------------------------------+
//| トレードを停止                                                   |
//+------------------------------------------------------------------+
void DisableTrading()
{
    // トレードを停止するロジックをここに追加
    //   ExpertRemove();
}
//+------------------------------------------------------------------+
//| ボタンが押されていない状態に戻す                                    |
//+------------------------------------------------------------------+
void resetButton()
{
    string button_names[] = {"TradeStartButton", "TradeStopButton"};
    for (int i = 0; i < ArraySize(button_names); i++)
    {
        string name = button_names[i];
        ObjectSetInteger(0, name, OBJPROP_STATE, 0);
    }
}
//+------------------------------------------------------------------+
//| サポートとレジスタンスの値に応じて指値を設定する                      |
//+------------------------------------------------------------------+
void entryAll()
{
    // inputの値を取得して指値を設定する
    for (int i = 0; i < ArraySize(input_names); i++)
    {
        string name = input_names[i];
        string input_text = ObjectGetString(0, name, OBJPROP_TEXT);
        double value = NormalizeDouble(StringToDouble(input_text), m_symbol.Digits());
        Print(name, " ", value, " ", m_symbol.Ask(), " ",
              m_symbol.Bid(), " ", m_symbol.Digits(), " ", m_symbol.Point());
        if (value != 0)
        {
            entry(value);
        }
    }
}
//+------------------------------------------------------------------+
//|
// priceが現在価格よりも上であればSELL、現在価格よりも下であればBUYの指値をMaxOrdersの個数分、均等に指値を入れる
//|
//+------------------------------------------------------------------+
void entry(double price)
{
    double volume = LOT();
    double min_price = 0.0;
    double max_price = 0.0;
    double sl = 0.0;
    double currentPrice = m_symbol.Ask();

    double atr_array[];
    ArraySetAsSeries(atr_array, true);
    int buffer = 0, start_pos = 0;
    int count = 3;

    iGetArray(atr, buffer, start_pos, count, atr_array);

    if (price == 0.0)
    {
        return;
    }

    if (price > currentPrice)
    {
        // 指値の最小priceはATR+priceとする
        max_price = NormalizeDouble(price + atr_array[0], m_symbol.Digits());
        min_price = price;
        sl = NormalizeDouble(max_price + InpStopLoss * m_adjusted_point,
                             m_symbol.Digits());
    }
    else
    {
        // 指値の最大priceはATR+priceとする
        min_price = NormalizeDouble(price - atr_array[0], m_symbol.Digits());
        max_price = price;
        sl = NormalizeDouble(min_price - InpStopLoss * m_adjusted_point,
                             m_symbol.Digits());
    }

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);

    // MaxOrdersの個数分、priceから均等に指値を入れる
    double step = (max_price - min_price) / MaxOrders;
    for (int i = 0; i < MaxOrders; i++)
    {
        double target_price = 0.0;
        if (price > currentPrice)
        {
            target_price =
                NormalizeDouble(min_price + step * i, m_symbol.Digits());
            if (isPendingOrderExist(target_price))
            {
                continue;
            }
            Print(target_price, " ", sl, " ", currentPrice, " ",
                  m_symbol.Digits(), " ", m_symbol.Point());
            request.action = TRADE_ACTION_PENDING;
            request.type = ORDER_TYPE_SELL_LIMIT;
            request.symbol = Symbol();
            request.volume = volume;
            request.price = target_price;
            request.sl = sl;
            request.tp = 0;
            request.deviation = ExtSlippage;
            request.magic = m_magic;
            request.comment = TradeComment;
        }
        else
        {
            target_price =
                NormalizeDouble(max_price - step * i, m_symbol.Digits());
            if (isPendingOrderExist(target_price))
            {
                continue;
            }
            Print(target_price, " ", sl, " ", currentPrice, " ",
                  m_symbol.Digits(), " ", m_symbol.Point());
            request.action = TRADE_ACTION_PENDING;
            request.type = ORDER_TYPE_BUY_LIMIT;
            request.symbol = Symbol();
            request.volume = volume;
            request.price = target_price;
            request.sl = sl;
            request.tp = 0;
            request.deviation = ExtSlippage;
            request.magic = m_magic;
            request.comment = TradeComment;
        }
        if (!OrderSend(request, result))
        {
            Print("Order added successfully. Price: ", target_price);
        }
        else
        {
            Print("Failed to add order. Price: ", target_price,
                  " Error: ", GetLastError());
        }
    }
}
//+------------------------------------------------------------------+
//| 指値をすべて削除する                                               |
//+------------------------------------------------------------------+
void removeAll()
{
    int totalOrders = OrdersTotal(); // 保留中の注文の総数を取得
    for (int i = totalOrders - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        ulong magic = OrderGetInteger(ORDER_MAGIC);

        // Magic Numberが一致する指値注文をチェック
        if (magic == m_magic || IsManualOrdersAndPositions)
        {
            // 削除する注文情報をセット
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action = TRADE_ACTION_REMOVE; // 注文削除アクション
            request.order = ticket;               // 削除する注文のチケット番号

            if (!OrderSend(request, result))
            {
                Print("Order deleted successfully. Ticket: ", ticket);
            }
            else
            {
                Print("Failed to delete order. Ticket: ", ticket,
                      " Error: ", GetLastError());
            }
        }
    }
}
//+------------------------------------------------------------------+
//| 現在のポジションの中で最も含み益が大きいポジションのticketidを返す|
//+------------------------------------------------------------------+
void getPositionWithMaxProfit(ulong &tickets[], int positionType)
{
    double positionPrice[];
    int priceCounter = 0;
    int counter = 0;

    ArrayResize(positionPrice, getPositionCount(positionType));

    for (int i = 0; i < PositionsTotal(); i++)
    {
        m_position.SelectByIndex(i);
        if (m_position.Symbol() != Symbol() || (m_position.Magic() != m_magic && !IsManualOrdersAndPositions))
        {
            continue;
        }
        if (m_position.PositionType() == positionType)
        {
            positionPrice[priceCounter] = m_position.PriceOpen();
            priceCounter++;
        }
    }

    // 価格を昇順にソート
    ArraySort(positionPrice);
    if(positionType == POSITION_TYPE_SELL)
    {
        ArrayReverse(positionPrice);
    }

    for (int i = 0; i < PositionsTotal(); i++)
    {
        m_position.SelectByIndex(i);
        if (m_position.Symbol() != Symbol() || (m_position.Magic() != m_magic && !IsManualOrdersAndPositions))
        {
            continue;
        }
        double price = m_position.PriceOpen();
        for (int j = 0; j < max_position; j++)
        {
            if (positionPrice[j] == price)
            {
                tickets[counter] = m_position.Ticket();
                counter++;
                break;
            }
        }
        if (counter == max_position)
        {
            break;
        }
    }
}
//+------------------------------------------------------------------+
//| 現在のポジション数を返す                                        |
//+------------------------------------------------------------------+
int getPositionCount(int positionType)
{
    int positionCount = 0;
    for (int i = 0; i < PositionsTotal(); i++)
    {
        m_position.SelectByIndex(i);
        if (m_position.Symbol() != Symbol() || (m_position.Magic() != m_magic && !IsManualOrdersAndPositions))
        {
            continue;
        }
        if (m_position.PositionType() == positionType)
        {
            positionCount++;
        }
    }
    return positionCount;
}
//+------------------------------------------------------------------+
//| 買いポジションが２個以上になった場合、不利なポジションに3pipsのTPを設定する|
//+------------------------------------------------------------------+
void setBuyPositionTakeProfit()
{
    ulong tickets[];
    ArrayResize(tickets, max_position);

    int buyPositionCount = getPositionCount(POSITION_TYPE_BUY);
    if (buyPositionCount >= 2)
    {
        getPositionWithMaxProfit(tickets, POSITION_TYPE_BUY);
        for (int i = 0; i < PositionsTotal(); i++)
        {
            m_position.SelectByIndex(i);
            if (m_position.Symbol() != Symbol() ||
                (m_position.Magic() != m_magic && !IsManualOrdersAndPositions))
            {
                continue;
            }
            bool isExist = false;
            for (int j = 0; j < ArraySize(tickets); j++)
            {
                if (tickets[j] == m_position.Ticket())
                {
                    isExist = true;
                    break;
                }
            }
            if (m_position.PositionType() == POSITION_TYPE_BUY &&
                !isExist)
            {
                double profit =
                    m_position.PriceCurrent() - m_position.PriceOpen();
                if (profit < 0)
                {
                    double tp = NormalizeDouble(
                        m_position.PriceOpen() + 3 * m_adjusted_point,
                        m_symbol.Digits());
                    m_trade.PositionModify(m_position.Ticket(),
                                           m_position.StopLoss(), tp);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
//| 売りポジションが２個以上になった場合、不利なポジションに3pipsのTPを設定する|
//+------------------------------------------------------------------+
void setSellPositionTakeProfit()
{
    ulong tickets[];
    ArrayResize(tickets, max_position);

    int sellPositionCount = getPositionCount(POSITION_TYPE_SELL);
    if (sellPositionCount >= 2)
    {
        getPositionWithMaxProfit(tickets, POSITION_TYPE_SELL);
        for (int i = 0; i < PositionsTotal(); i++)
        {
            m_position.SelectByIndex(i);
            if (m_position.Symbol() != Symbol() ||
                (m_position.Magic() != m_magic && !IsManualOrdersAndPositions))
            {
                continue;
            }
            bool isExist = false;
            for (int j = 0; j < ArraySize(tickets); j++)
            {
                if (tickets[j] == m_position.Ticket())
                {
                    isExist = true;
                    break;
                }
            }
            if (m_position.PositionType() == POSITION_TYPE_SELL &&
                !isExist)
            {
                double profit =
                    m_position.PriceOpen() - m_position.PriceCurrent();
                if (profit < 0)
                {
                    double tp = NormalizeDouble(
                        m_position.PriceOpen() - 3 * m_adjusted_point,
                        m_symbol.Digits());
                    m_trade.PositionModify(m_position.Ticket(),
                                           m_position.StopLoss(), tp);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
//| 既に指値が設定されているか確認する                                  |
//+------------------------------------------------------------------+
bool isPendingOrderExist(double price)
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        ulong ticket = OrderGetTicket(i);
        ulong magic = OrderGetInteger(ORDER_MAGIC);
        double order_price = OrderGetDouble(ORDER_PRICE_OPEN);
        if ((magic == m_magic || IsManualOrdersAndPositions) && order_price == price)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
