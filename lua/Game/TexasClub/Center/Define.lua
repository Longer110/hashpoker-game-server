
require "DeZhou_pb"

local tProtoAux =require("ProtoCoder").Aux
local tname = require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local PublicDefine =require("PublicDefine")
local Define ={}

Define.nGameId_Normal=125                          --德州 正常玩法
Define.nGameId_Ahm=126                             --德州 奥哈马玩法
Define.nGameId_Sc =175                             --德州 短牌

Define.sGameName=typename.clubdezhoucenter          --游戏名称
Define.LLogDir   = "center"                  --游戏日志目录名称

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

Define.nInsureStageTime=20  --保险阶段时间 秒
Define.PauseTime =1*60     --房主暂停最大时间 秒
Define.TimeOutMax =2        --最大超时次数 (超时次数超过该值后，操作时间将缩短)
Define.nRetainTime =180    --离桌留座时间 秒
Define.nOfflineTime =90    --离线倒计时时间 秒

Define.nAddTime = 15         --操作时间延长时间 秒(每点一次延长一次,收费功能)
Define.nCutTime = 10          --切牌动画时间

Define.InsureMode ={
    nNormal =1,
    nLow =2
}

Define.TableCloseReason={
    nGmClose =2,
    nNoRealUserTooLong=3,
    nClubTableTimeOut=1,
    nBackstageClose=4,
    nTableError=5,
    nTestTableUserLeave=6,  --试玩桌真人离开
    nMatchServ=7,           --比赛服请求关闭
}

function Define.UserOpToStr(nOp)
    if nOp ==PublicDefine.UserOp.nFold then
        return "Fold"
    end
    if nOp ==PublicDefine.UserOp.nAllIn then
        return "AllIn"
    end
    if nOp ==PublicDefine.UserOp.nPass then
        return "Pass"
    end
    if nOp ==PublicDefine.UserOp.nRaise then
        return "Raise"
    end
    if nOp ==PublicDefine.UserOp.nRaiseBan then
        return "RaiseBan"
    end
    if nOp ==PublicDefine.UserOp.nCall then
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
    local nHuaSe = math.floor(nCard / 16)
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
tCardTypeToStr[6]="同花"
tCardTypeToStr[7]="葫芦"
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

Define.nAxx =300                            --当手数达到该值时，入池率限制才会起效
Define.nOverViewRtLen=20                    --总览战绩列表每次返回给前端的最大长度
Define.nCacheRobot =16                      --缓存的机器人数量

return Define