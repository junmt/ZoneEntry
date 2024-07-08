//+------------------------------------------------------------------+
//|                                                    ZoneEntry.mq5 |
//|                                            Copyright 2024, junmt |
//|                                   https://twitter.com/SakenomiFX |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, junmt"
#property link "https://twitter.com/SakenomiFX"
#property version "1.05"
#include <Expert\Money\MoneyFixedMargin.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>
#include <..\MT5libs\CLotsLibrary.mqh>
#include <..\MT5libs\CPositionLibrary.mqh>
#include <..\MT5libs\COrderLibrary.mqh>

CPositionInfo m_position; // trade position object
CTrade m_trade;           // trading object
CSymbolInfo m_symbol;     // symbol info object
CMoneyFixedMargin m_money;
CLotsLibrary m_lots_lib;
CPositionLibrary m_position_lib;
COrderLibrary m_order_lib;
//---
input double InpStopLoss = 10.0;               // 最も不利なポジションからのストップの幅(pips)
input double InpTakeProfit = 100.0;            // 自動利益確定(pips)
input double InpTrailingStop = 50.0;           // トレーリングストップ(pips)
input bool AutoLot = false;                    // ロットサイズ自動計算 (percent from a free margin)
input double Risk = 10;                        // ロットサイズを計算するためのリスク(%)
input double ManualLots = 0.01;                // ロットサイズ(手動の場合のみ)
input double LotRatio = 1.1;                   // ロットサイズの比率
input ulong m_magic = 65127841;                // Magic number
input string TradeComment = "ZoneEntry";       // 注文のコメント欄の内容
input ulong InpSlippage = 1;                   // 許容するスリッページ(pips)
input int MaxOrders = 10;                      // ポジションの数
input int max_position = 1;                    // 有利なポジションを残す数
input double breakEven = 3.0;                  // 不利なポジションを決済する際の利益(pips)
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1;   // 注文の値幅を計算する時間足
input bool IsManualOrdersAndPositions = false; // 手動トレードの注文に対しても処理を行う
input bool isShowSymbolName = true;            // シンボル名を表示する
input bool isDebugMessage = true;              // デバッグ用のメッセージを表示する
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

    m_lots_lib.Init(AutoLot, ManualLots, m_money, m_trade, m_symbol);

    m_position_lib.Init(m_symbol, m_trade, m_position);
    m_position_lib.magic = m_magic;
    m_position_lib.lots = m_lots_lib.LOT();
    m_position_lib.profit = InpTakeProfit;
    m_position_lib.stoploss = InpStopLoss;
    m_position_lib.trailing_stop = InpTrailingStop;
    m_position_lib.breakeven = breakEven;
    // m_position_lib.distance = distance;
    m_position_lib.slippage = InpSlippage;
    // m_position_lib.adjusted_point = m_adjusted_point;
    // m_position_lib.digits_adjust = digits_adjust;
    m_position_lib.trade_comment = TradeComment;
    m_position_lib.is_manual_orders_and_positions = IsManualOrdersAndPositions;
    m_position_lib.max_manual_position = max_position;

    m_order_lib.Init(m_symbol, m_trade, m_position);
    m_order_lib.magic = m_magic;
    m_order_lib.slippage = InpSlippage;
    // m_order_lib.adjusted_point = m_adjusted_point;
    // m_order_lib.digits_adjust = digits_adjust;
    m_order_lib.trade_comment = TradeComment;
    m_order_lib.is_manual_orders_and_positions = IsManualOrdersAndPositions;

    atr = iATR(m_symbol.Name(), TimeFrame, 14);

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
    m_symbol.RefreshRates();
    if (IsTradeStartButtonPressed())
    {
        entryAll();
        resetButton();
    }
    else if (IsTradeStopButtonPressed())
    {
        m_order_lib.RemoveAll();
        resetButton();
    }

    m_position_lib.SetPositionTakeProfit(POSITION_TYPE_BUY);
    m_position_lib.SetPositionTakeProfit(POSITION_TYPE_SELL);
    m_position_lib.TrailingStop();

    if (isDebugMessage)
    {
        setDebugMessage(getDebugMessage1());
    }

    // プロフィットをとる
    m_position_lib.TakeProfitAll();

    // ロスカット　ストップが自動で設定されるためコメントアウト
    // m_position_lib.StopLossAll();

    // 計算量が多いので、PERIOD_CURRENT間隔で計算を行う
    //--- ゼロバーの開いた時間を取得する
    datetime currbar_time = iTime(Symbol(), TimeFrame, 0);
    bartime = iTime(Symbol(), TimeFrame, 0);
    //--- 新しいバーが到着すると開いた時刻が変わる
    if (bartime == currbar_time)
    {
        return;
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

    CreateSymbolName();

    // デバッグメッセージの作成
    CreateDebugMessage();
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
    ObjectDelete(0, "SymbolName");
    ObjectDelete(0, "DebugMessage1");
    ObjectDelete(0, "DebugMessage2");
}
//+------------------------------------------------------------------+
//| サポートとレジスタンスの入力フィールドの作成                     |
//+------------------------------------------------------------------+
void CreateSupportAndResistanceInputs()
{
    int y_offset = 100;

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
    ObjectSetInteger(0, button_name, OBJPROP_YDISTANCE, 230);
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
    ObjectSetInteger(0, button_name, OBJPROP_YDISTANCE, 260);
    ObjectSetInteger(0, button_name, OBJPROP_XSIZE, 100);
    ObjectSetInteger(0, button_name, OBJPROP_YSIZE, 30);
    ObjectSetString(0, button_name, OBJPROP_TEXT, "指値削除");
    ObjectSetInteger(0, button_name, OBJPROP_COLOR, clrRed);
}
//+------------------------------------------------------------------+
//| 画面の中心にシンボル名を大きく表示する                                        |
//+------------------------------------------------------------------+
void CreateSymbolName()
{
    if (isShowSymbolName == false)
    {
        return;
    }
    string name = "SymbolName";
    string symbol_name = m_symbol.Name();
    int font_size = 100;

    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetString(0, name, OBJPROP_TEXT, symbol_name);
    ObjectSetInteger(0, name, OBJPROP_COLOR, C'82,82,82');
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, (int)((ChartGetInteger(0, CHART_WIDTH_IN_PIXELS) - TextGetWidth(symbol_name, font_size)) / 2));
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, (int)((ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS) - TextGetHeight(font_size)) / 2));
    ObjectSetInteger(0, name, OBJPROP_XSIZE, TextGetWidth(symbol_name, font_size));
    ObjectSetInteger(0, name, OBJPROP_YSIZE, TextGetHeight(font_size));
    ObjectSetInteger(0, name, OBJPROP_BACK, true); // 背景に表示する設定
}
//+------------------------------------------------------------------+
//| Calculate text width in pixels                                   |
//+------------------------------------------------------------------+
int TextGetWidth(const string text, const int fontsize)
{
    // テキストの幅を計算（簡略化した計算方法）
    return StringLen(text) * fontsize;
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calculate text height in pixels                                  |
//+------------------------------------------------------------------+
int TextGetHeight(const int fontsize)
{
    // テキストの高さを計算
    return fontsize;
}
//+------------------------------------------------------------------+
//| デバッグメッセージの表示                                        |
//+------------------------------------------------------------------+
void CreateDebugMessage()
{
    if (isDebugMessage == false)
    {
        return;
    }
    string name = "DebugMessage1";
    string message = getDebugMessage1();
    int font_size = 8;

    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 250);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 0);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, TextGetWidth(message, font_size));
    ObjectSetInteger(0, name, OBJPROP_YSIZE, 30);
    ObjectSetString(0, name, OBJPROP_TEXT, message);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, name, OBJPROP_BACK, true); // 背景に表示する設定

    name = "DebugMessage2";
    message = getDebugMessage2();

    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 250 + TextGetWidth(message, font_size) + 10);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 0);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, TextGetWidth(message, font_size));
    ObjectSetInteger(0, name, OBJPROP_YSIZE, 30);
    ObjectSetString(0, name, OBJPROP_TEXT, message);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, name, OBJPROP_BACK, true); // 背景に表示する設定
}
string getDebugMessage1()
{
    string message = "";
    string name = m_symbol.Name();
    string ask = DoubleToString(m_symbol.Ask(), m_symbol.Digits());
    string bid = DoubleToString(m_symbol.Bid(), m_symbol.Digits());
    string point = DoubleToString(m_symbol.Point(), m_symbol.Digits());
    string digits = DoubleToString(m_symbol.Digits(), m_symbol.Digits());
    string spread = DoubleToString(m_symbol.Spread(), m_symbol.Digits());
    message = name + " " + ask + "/" + bid + " POINT:" + point + " DIGITS:" + digits + " SPREAD:" + spread;
    return message;
}
string getDebugMessage2()
{
    string message = "";
    string profit = DoubleToString(ExtTakeProfit, m_symbol.Digits());
    string stoploss = DoubleToString(ExtStopLoss, m_symbol.Digits());
    string trailingstop = DoubleToString(ExtTrailingStop, m_symbol.Digits());
    string slippage = DoubleToString(ExtSlippage, m_symbol.Digits());
    string ajust = DoubleToString(m_adjusted_point, m_symbol.Digits());
    message = "TP:" + profit + " SL:" + stoploss + " TRAIL:" + trailingstop + " SLIP:" + slippage + " AJUST:" + ajust;
    return message;
}
void setDebugMessage(string message)
{
    if (!isDebugMessage)
    {
        return;
    }
    string name = "DebugMessage1";
    ObjectSetString(0, name, OBJPROP_TEXT, message);
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
    double min_price = 0.0;
    double max_price = 0.0;
    double sl = 0.0;
    double currentPrice = m_symbol.Ask();

    double atr_array[];
    ArraySetAsSeries(atr_array, true);
    int buffer = 0, start_pos = 0;
    int count = 3;

    iGetArray(atr, buffer, start_pos, count, atr_array);

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
            if (value > currentPrice)
            {
                // 指値の最小priceはATR+priceとする
                max_price = NormalizeDouble(value + atr_array[0], m_symbol.Digits());
                min_price = value;
                m_order_lib.ZoneEntry(min_price, max_price, m_lots_lib.LOT(), LotRatio, MaxOrders, InpStopLoss);
            }
            else
            {
                // 指値の最大priceはATR+priceとする
                min_price = NormalizeDouble(value - atr_array[0], m_symbol.Digits());
                max_price = value;
                m_order_lib.ZoneEntry(max_price, min_price, m_lots_lib.LOT(), LotRatio, MaxOrders, InpStopLoss);
            }
        }
    }
}

//+------------------------------------------------------------------+
