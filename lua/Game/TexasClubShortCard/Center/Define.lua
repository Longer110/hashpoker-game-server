
require "DeZhou_pb"

local tProtoAux =require("ProtoCoder").Aux
local tname = require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 

local Define ={}


Define.nGameId =175                                 --游戏id
Define.sGameName=tname.TexasShortCardCenter          --游戏名称
Define.LLogDir   = "center"             --日志目录名称

local ProtoPbFront =DeZhou_pb                       --游戏pb协议
local CmdObjFront =ProtoPbFront.DeZhou_Proto()      --游戏命令对象
Define.CmdObjFront =CmdObjFront
Define.ProtoAuxFront =tProtoAux:New(ProtoPbFront,function(sProto) --协议编解码辅助对象
    return CmdObjFront.Main_CMD,CmdObjFront[sProto..'_CMD'] 
end)

--db服<->游戏服协议
local pb_DbServer =ProtoMgr.DbServer1_pb
local CMD_DbServer =pb_DbServer.Db_Proto1()
local ToCMD_DbServer =function(strProto)
  return CMD_DbServer.Main_CMD,CMD_DbServer[strProto..'_CMD']
end
Define.DbServAux =tProtoAux:New(pb_DbServer,ToCMD_DbServer)
Define.CMD_DbServer =CMD_DbServer


Define.PauseTime =1*60      --房主暂停最大时间 秒
Define.TimeOutMax =2        --最大超时次数 (超时次数超过该值后，操作时间将缩短)
Define.nRetainTime = 180    --离桌留座时间 秒
Define.nAddTime = 15         --操作时间延长时间 秒(每点一次延长一次,收费功能)
Define.nCutTime = 10          --切牌动画时间
Define.nOfflineTime =90    --离线倒计时时间 秒

--桌子状态 0:未开始 
Define.TableState ={
    nInit =0,           --未开始
    nPlaying =1,        --倒计时开始阶段
    nSettle=2,          --结算阶段
}

Define.UserStatus={
    nWaitForOp=0,   --0:等待操作权中
    nThinking=1,    --思考中
    nCall=2,        --跟注
    nPass=3,        --看牌
    nRaise=4,       --加注
    nAllIn=5,       --AllIn
    nFold=6,        --弃牌
    nLooker=7,      --旁观
}
Define.UserOp={
    nFold =-5,      --弃牌
    nAllIn =-1,     --AllIn
    nPass =-2,      --看牌(过牌)
    nRaise=-3,      --加注
    nRaiseBan=-4,   --加注(置灰)
    nCall =-6,      --跟注
    -- -10:(1/2底池)  -11:(2/3底池) -12:(1个底池)  -13:(2个大盲) -14:(3个大盲)  -15:(4个大盲)
    
    nHalfPool =-10,         --(1/2底池)
    nTwoThirdsPool =-11,    --(2/3底池)
    nOnePool =-12,          --1个底池
    nTwoBlind=-13,          --2个大盲
    nThreeBlind=-14,        --3个大盲
    nFourBlind =-15,        --4个大盲
}

Define.nInsureStageTime=20  --保险阶段时间 秒

Define.TableCloseReason={
    nGmClose =2,
    nNoRealUserTooLong=3,
    nClubTableTimeOut=1,
    nBackstageClose=4,
    nTableError=5,
}

Define.InsureMode ={
    nNormal =1,
    nLow =2
}
function Define.UserOpToStr(nOp)
    if nOp ==Define.UserOp.nFold then
        return "Fold"
    end
    if nOp ==Define.UserOp.nAllIn then
        return "AllIn"
    end
    if nOp ==Define.UserOp.nPass then
        return "Pass"
    end
    if nOp ==Define.UserOp.nRaise then
        return "Raise"
    end
    if nOp ==Define.UserOp.nRaiseBan then
        return "RaiseBan"
    end
    if nOp ==Define.UserOp.nCall then
        return "Call"
    end
    if nOp>0 then
        return string.format("Call%.2f",nOp)
    end

    return "unknown"
end

local tHuaSeToStr ={[1]="方",[2]="梅",[3]="红",[4]="黑"}
local tPointToStr ={[1]="A",[2]="2",[3]="3",[4]="4",[5]="5",[6]="6",[7]="7",[8]="8",[9]="9",[10]="10",[11]="J",[12]="Q",[13]="K",}

local function CardToStr(nCard)
	local nPoint =(nCard %16)
	local nHuaSe =math.floor(nCard/16)
	local sPoint =tPointToStr[nPoint] or "-1"
	local sHuaSe =tHuaSeToStr[nHuaSe] or "Error"
	return string.format("%s%s",sHuaSe,sPoint)
end
function Define.CardsToStr(arrCard)
	local arr ={}
	for _,nCard in ipairs(arrCard) do
		table.insert(arr,CardToStr(nCard))
	end
	return table.concat(arr,",")
end

local tCardTypeToStr={}
tCardTypeToStr[0]="未计算"
tCardTypeToStr[1]="高牌"
tCardTypeToStr[2]="对子"
tCardTypeToStr[3]="两对"
tCardTypeToStr[4]="三条"
tCardTypeToStr[5]="顺子"
tCardTypeToStr[6]="葫芦"
tCardTypeToStr[7]="同花"
tCardTypeToStr[8]="四条"
tCardTypeToStr[9]="同花顺"
tCardTypeToStr[10]="皇家同花顺"
function Define.CardTypeToStr(nCardType)
    return (tCardTypeToStr[nCardType] or "Error")
end


--[[
//DeZhouFailNotify 错误码定义
//11:金币不足(登陆游戏成功, 但坐下失败时) 00
//12:金币不足('坐下'请求失败时) 
//13:金币不足(被请离座位后) 

//14:座位不足('坐下'请求失败时)
//15:重复坐下(已在座位上,'坐下'请求失败时)
//16:重复站起(当前不在座位上,'站起'请求失败)
]]

Define.TableType ={
    nMatch =4,          --匹配房
}
Define.GoldOfFreeRoom =10000  --免费场玩家身上金币


local tBigBlindToSysWater ={}
local function AssertWaterInfoExist(nBigBlind)
    if tBigBlindToSysWater[nBigBlind] ==nil then
        tBigBlindToSysWater[nBigBlind] ={nSysSumIn =110*nBigBlind,nSysSumOut =100*nBigBlind}
    end
    return tBigBlindToSysWater[nBigBlind]
end
Define.AssertWaterInfoExist =AssertWaterInfoExist
Define.nSysWinRate =1.02                    --(nSysSumIn/nSysSumOut)系统盈利率
Define.arrDelayCost={0,500,1000,1000,1000}  --延时操作花费,第一次0，第二次500,... (nil表示禁止延时)

Define.nOverViewRtLen=20                    --总览战绩列表每次返回给前端的最大长度

return Define