local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tBase = require("base") -- 基础功能接口
local tTableMgr   = require("TableManage")
local tUserMgr   = require("UserManager")
local tTable = require("Table") 
local tClientIdMgr =require("ClientIdMgr")
local tGameConfig =require("GameConfig") -- 
local tPubUser = require("PublicUserInfo")   -- 用户信息 
local Define =require("Define")
local MsgPush =require("MsgPush")
local tSrvInfo = require("ServerInfo")
local RecordDbr =require("RecordDbr")
local tSetingConfig = require("SetingConfig")
local tPublicRedis =require("PublicRedis")
local tname = require("typename")
local cjson    = require("cjson")
local tPLiveGame =require("PublicLiveGame")
local tSlaveManager =require("SlaveManage")
local tPublicClub =require("PublicClub")
local tAiGet =require("AiGet")
local PublicDefine =require("PublicDefine")
local tTimerAux =require("TimerAux")
local BaseSink =require("BaseSink")

local ProtoAuxFront =Define.ProtoAuxFront

local MsgHandle={}
local tGameInterFace ={}


local function SetTableOpResult(sRequestkey,tData)
   if not sRequestkey then
      return
   end
   local tRedis =tBase.m_MyRedisData[1].redis
   tRedis:hmset(sRequestkey,tData)
   tRedis:expire(sRequestkey,60)
end
local function CreateTableInRedis(tTableConfig)
   local tTableInfo={}
   tTableInfo.sTableId=tTableConfig.sTableId
   tTableInfo.nGameId =tTableConfig.nGameId
   tTableInfo.nRoomId =tTableConfig.nRoomId
   tTableInfo.nLiveUserID=math.floor(tTableConfig.nLiveUserID)
   tTableInfo.nGroupId =math.floor(tTableConfig.nGroupId)
   tTableInfo.sTableName=tTableConfig.sTableName
   tTableInfo.nTableType=tTableConfig.nTableType
   tTableInfo.sLiveID =tTableConfig.sLiveID
   tTableInfo.sPlatformID =tTableConfig.sPlatformID
   tTableInfo.sConfig =tTableConfig.sConfig
   tTableInfo.nClubId =tTableConfig.tJsonConfig.nClubId
   tPubUser.API_Open_Table_InRedis(tTableInfo)
   return true
end

--关闭桌子
function MsgHandle._CloseTable(sTableId,sRequestkey,nReason)
   local tTable =tTableMgr.GetBaiRenTable(sTableId)
   if tTable==nil then
      tBase.Log("close table fail,can not find table")
      SetTableOpResult(sRequestkey,{nErrorCode=1})
      return false
   end
   SetTableOpResult(sRequestkey,{nErrorCode=0})
   tTable:SetClose(nReason or Define.TableCloseReason.nBackstageClose)   --设置本局结束后关闭桌子
   return true
end

--nCreateType:1比赛桌 其它:默认桌
local function _CreateTable(tParameter,nCreateType)
   tBase.LogT("CreateTable 111 tParameter:",tParameter)
   local isSuccee,tTable= nil,nil
   if nCreateType==1 then
      isSuccee,tTable=tTableMgr.CreateTableMatch(tGameInterFace,tParameter.sTableId,tParameter)
   else
      isSuccee,tTable= tTableMgr.CreateTable(tGameInterFace,tParameter.sTableId,tParameter)
   end

   if not isSuccee then
      return nil,11
   end
   tTable:Init()
   CreateTableInRedis(tParameter)
   if nCreateType~=1 then
      RecordDbr.LiveTableCreate({sTableId=tParameter.sTableId,
                                 sTableName=tParameter.sTableName,
                                 nGameId=tParameter.nGameId,
                                 nGroupId=tParameter.nGroupId,
                                 nRoomId=tParameter.nRoomId})
   end
   --广播到从服
   local tScence= tTable:GetScence()
   local sJsonScenc= cjson.encode(tScence)
   local DZCScenceRsp ={}
   DZCScenceRsp.sTableId=tParameter.sTableId
   DZCScenceRsp.sJsonScenc =sJsonScenc
   DZCScenceRsp.nEcho =-1
   tSlaveManager.Broadcast("DZCScenceRsp",DZCScenceRsp)
   return tTable
end

--试玩桌子使用的json配置(仅给玩家体验用)
local function _TestConfig(nGameId)
   local tJsonConfig={}
   tJsonConfig.nGameId =nGameId
   tJsonConfig.isTabkeOut= false	         --是否开启带出功能 true:是 false:否
   tJsonConfig.sClubName="MA=="           --0
	tJsonConfig.nClubId=0                  --俱乐部id (俱乐部房配置,否时为nil)
	tJsonConfig.nItemId=1                  --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	tJsonConfig.nKeepTime=7200             --房间时长(秒) (俱乐部房配置,否时为nil)
	tJsonConfig.nGoldType=3			         -- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)

   tJsonConfig.isNeedAndroid =true
   tJsonConfig.nSmallBlind=1
   tJsonConfig.nBigBlind =2
   tJsonConfig.nCapacity=6
   tJsonConfig.nTakeIn =tJsonConfig.nBigBlind*3
   tJsonConfig.nIntervalLev = 2           --牌局间隔 1:短暂 2:适中 3:漫长
   tJsonConfig.nMinTabkeInBB = 1          --百倍大盲(1代表1百倍大盲)
   tJsonConfig.nMaxTabkeInBB = 10
   tJsonConfig.tAutostart ={isOpen=false,nPlayerCnt=2}
   tJsonConfig.nPreAnte= 0
   tJsonConfig.isForceBlind= false
   tJsonConfig.nPoolEntryRate= 0
   tJsonConfig.isOnlyPlayByIOS=false
   tJsonConfig.isGPSLimit =false
   tJsonConfig.isIPLimit =false
   tJsonConfig.isAOF =false
   tJsonConfig.isDelayLook =false
   tJsonConfig.nInsureMode =0             --保险模式 0:无保险 1:传统保险 2:低水保险
   tJsonConfig.tDrawWaterMode =	
		{
         nModeType=0,		         --抽水类型 0 不收取 1:按奖池比例收取 2:固定收取
			nComputeMode=1,	         --抽取方式 1:按净盈利  2:按底池
			nTaxRate=0,			         --比例 百分制  如2%就是2
			nTopLimitBB=0,		         --封顶 多少个大盲
			isFreeBeforeFlop=false, 	--翻牌前结束免服务费 true:是 false：否
			isHalf=false,				   --低于3人服务费5折 true:是 false：否
			tFreeConfig = {			   --盈利过低免服务费
				isOpen=false,			   --是否开启功能 true：开启 false:关闭
				nLimitBB=0		         --多少倍大盲
			},
			--固定收取
			nCutoffValue=0,		      --分界值
			nLessValue=0,		         --当净盈利小于分界值固定收多少
			nGreaterValue=0,	         --当净盈利大于等于分界值固定收多少
		}
   return tJsonConfig
end

--试玩桌子(仅给玩家体验用)
local function _CreateTable_ForTest(nGameId,nGroupId)
   local tRlt =_TestConfig(nGameId)
   local tParameter ={
      nGroupId =nGroupId,
      nRoomId =0,
      nLiveUserID=0,
      nTableType =Define.TableType.nMatch,
      sLiveID ="",
      sPlatformID="",
      sTableName ="MA==", --0
      nGameId =nGameId,
      sTableId=string.format("%d#%s",tSrvInfo.nServerId,tPubUser.CreatePaiJuID()),
      tJsonConfig =tRlt,                                 --解码后的json设置
   }
   tBase.LogT("CreateTable Test tParameter:",tParameter)
   local isSuccee,tTable= tTableMgr.CreateTable(tGameInterFace,tParameter.sTableId,tParameter)
   if not isSuccee then
      tBase.LogT("CreateTable Test Fail")
      return nil,11
   end
   tTable:Init()
   return tTable
end


--从服试玩房创建请求
function MsgHandle.OnDZCTestTableCreateReq(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCTestTableCreateReq")
   assert(tData~=nil)
   local nUserId =tData.nUserId 
	local sClientID =tData.sClientID 
	local nGroupId =tData.nGroupId
	local nServerId =tData.nServerId
   local tTable =_CreateTable_ForTest(Define.nGameId_Normal,nGroupId)

    --广播到从服
    local DZCTestTableCreateRsp ={}
    DZCTestTableCreateRsp.nUserId =nUserId
    DZCTestTableCreateRsp.sClientID =sClientID
    DZCTestTableCreateRsp.nGroupId=nGroupId
    DZCTestTableCreateRsp.nServerId=nServerId
    if tTable then
      local tScence= tTable:GetScence()
      local sJsonScenc= cjson.encode(tScence)
      DZCTestTableCreateRsp.sTableId=tTable.sTableId
      DZCTestTableCreateRsp.sJsonScenc=sJsonScenc
    else
      DZCTestTableCreateRsp.sTableId=""
      DZCTestTableCreateRsp.sJsonScenc=""
    end
    tBase.LogT("OnDZCTestTableCreateReq ",{nUserId=nUserId,nGroupId=nGroupId,nServerId=nServerId})
    tSlaveManager.Broadcast("DZCTestTableCreateRsp",DZCTestTableCreateRsp)
end

--从服登陆请求+
function MsgHandle.OnDZCLogOnReq(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCLogOnReq")
   assert(tData~=nil)
   tSlaveManager.AddSlaveServ(tData.nServerId,sReturnKey)
   --回复成功
   tSlaveManager.Send(sReturnKey,"DZCLogOnResp",{nRlt=0})
   tBase.Log("DZCLogOnResp nServerId_%d",tData.nServerId)
end
--从服牌桌命令请求
function MsgHandle.OnDZCReq(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCReq")
   assert(tData~=nil)
   local isSuccee,tJsonData =pcall(cjson.decode,tData.sJsonData)
   if not isSuccee then
      tBase.LogT(tJsonData)  --error msg
      return
   end
   local tTable =tTableMgr.GetBaiRenTable(tData.sTableId)
   if not tTable then
      tBase.Log("Can not find talbe:%s,sCmd:%s",tData.sTableId,tData.sCmd)
      return
   end
   tTable:OnSlaveMsgHandle(sReturnKey,tData.sCmd,tJsonData,tData.nEcho)
end

--从服场景请求
function MsgHandle.OnDZCScenceReq(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCScenceReq")
   assert(tData~=nil)
   local tTable =tTableMgr.GetBaiRenTable(tData.sTableId)
   if not tTable then
      tBase.LogT("Can not find talbe:%s of OnDZCScenceReq",tData.sTableId)
      return
   end
   tBase.LogT("OnDZCScenceReq sTableId:%d",tData.sTableId)
   local tScence= tTable:GetScence()
   local sJsonScenc= cjson.encode(tScence)
   local DZCScenceRsp ={}
   DZCScenceRsp.sTableId=tData.sTableId
   DZCScenceRsp.sJsonScenc =sJsonScenc
   DZCScenceRsp.nEcho =tData.nEcho
   tSlaveManager.Send(sReturnKey,"DZCScenceRsp",DZCScenceRsp)
   tBase.LogT("DZCScenceRsp Succee")
end

--桌子创建请求(匹配桌,俱乐部无用) _CreateTable参数有变化，所以这个已不能用,其实也不会用到
function MsgHandle.OnDZCTableCreateReq(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCTableCreateReq")
   assert(tData~=nil)
 
   if PublicDefine.isTest then
      return
   end

   local sTableId=tData.sTableId
   local tParameter=cjson.decode(tData.sParameter)
   tParameter.sTableId =sTableId
   local tTable,nCode =  _CreateTable(tParameter)

   local nTableCnt =tTableMgr.GetCntOfMatchTable(tParameter.nGroupId ,tParameter.nRoomId)

   local tCntOfMathcTableShould=5
   if nTableCnt >=tCntOfMathcTableShould then
         return 
   end
   for i=1,(tCntOfMathcTableShould-nTableCnt) do
         _CreateTable(tParameter)
   end
end

--检查配置，并尽可能纠正
local function ConfigCorrected(tJsonConfig)
   if tJsonConfig.nGameId==nil then
      tJsonConfig.nGameId =Define.nGameId_Normal
   end
   if tJsonConfig.nGameId~=Define.nGameId_Normal and tJsonConfig.nGameId~=Define.nGameId_Ahm then
      return false,"NotSupport GameId"
   end
   tJsonConfig.isNeedAndroid =tJsonConfig.isNeedAndroid or false
   if tJsonConfig.nSmallBlind==nil or tJsonConfig.nSmallBlind<=0 then
      tJsonConfig.nSmallBlind=1
   end
   if tJsonConfig.nBigBlind==nil or tJsonConfig.nBigBlind<tJsonConfig.nSmallBlind then
      tJsonConfig.nBigBlind =(tJsonConfig.nSmallBlind*2)
   end
   if tJsonConfig.nCapacity==nil or tJsonConfig.nCapacity<0 then
      tJsonConfig.nCapacity=0
   end
   if tJsonConfig.nTakeIn==nil or tJsonConfig.nTakeIn< 0 then
      tJsonConfig.nTakeIn =tJsonConfig.nBigBlind*3
   end

   tJsonConfig.nIntervalLev =tJsonConfig.nIntervalLev or 1           --牌局间隔 1:短暂 2:适中 3:漫长
   tJsonConfig.nMinTabkeInBB =tJsonConfig.nMinTabkeInBB or 1         --百倍大盲(1代表1百倍大盲)
   tJsonConfig.nMaxTabkeInBB =tJsonConfig.nMaxTabkeInBB or 10
   if (tJsonConfig.nMinTabkeInBB*100)<3 then
      tJsonConfig.nMinTabkeInBB =1
   end
   if tJsonConfig.nMinTabkeInBB >tJsonConfig.nMaxTabkeInBB then
      tJsonConfig.nMaxTabkeInBB=tJsonConfig.nMinTabkeInBB
   end
   tJsonConfig.tAutostart =tJsonConfig.tAutostart or {isOpen=false,nPlayerCnt=2}
   local nPlayerCnt =tJsonConfig.tAutostart.nPlayerCnt
   if tJsonConfig.tAutostart.isOpen and (nPlayerCnt==nil or nPlayerCnt<2) then
      tJsonConfig.tAutostart.nPlayerCnt =2
   end
   if not tJsonConfig.tAutostart.isOpen then
      tJsonConfig.tAutostart.nPlayerCnt=2
   end
   tJsonConfig.nPreAnte=tJsonConfig.nPreAnte or 0
   tJsonConfig.isForceBlind=tJsonConfig.isForceBlind or false
   tJsonConfig.nPoolEntryRate=tJsonConfig.nPoolEntryRate or 0
   tJsonConfig.isOnlyPlayByIOS=tJsonConfig.isOnlyPlayByIOS or false
   tJsonConfig.isGPSLimit =tJsonConfig.isGPSLimit or false
   tJsonConfig.isIPLimit =tJsonConfig.isIPLimit or false
   tJsonConfig.isAOF =tJsonConfig.isAOF or false
   tJsonConfig.isDelayLook =tJsonConfig.isDelayLook or false
   tJsonConfig.nInsureMode =tJsonConfig.nInsureMode or 0
   tJsonConfig.tDrawWaterMode =tJsonConfig.tDrawWaterMode or 	
		{
         nModeType=0,		         --抽水类型 0 不收取 1:按奖池比例收取 2:固定收取
			nComputeMode=1,	         --抽取方式 1:按净盈利  2:按底池
			nTaxRate=0,			         --比例 百分制  如2%就是2
			nTopLimitBB=0,		         --封顶 多少个大盲
			isFreeBeforeFlop=false, 	--翻牌前结束免服务费 true:是 false：否
			isHalf=false,				   --低于3人服务费5折 true:是 false：否
			tFreeConfig = {			   --盈利过低免服务费
				isOpen=false,			   --是否开启功能 true：开启 false:关闭
				nLimitBB=0		         --多少倍大盲
			},
			--固定收取
			nCutoffValue=0,		      --分界值
			nLessValue=0,		         --当净盈利小于分界值固定收多少
			nGreaterValue=0,	         --当净盈利大于等于分界值固定收多少
		}	
   local tInfo =tJsonConfig.tDrawWaterMode
   tInfo.nModeType=tInfo.nModeType or 0
   tInfo.nComputeMode=tInfo.nComputeMode or 1
   tInfo.nTaxRate =tInfo.nTaxRate or 0
   if tInfo.nTaxRate<0 then
      tInfo.nTaxRate =0
   end
   tInfo.nTopLimitBB=tInfo.nTopLimitBB or 0
   if tInfo.nTopLimitBB<0 then
      tInfo.nTopLimitBB=0
   end
   tInfo.isFreeBeforeFlop =tInfo.isFreeBeforeFlop or false
   tInfo.isHalf =tInfo.isHalf or false
   tInfo.tFreeConfig =tInfo.tFreeConfig or {isOpen=false,nLimitBB=0}
   if tInfo.tFreeConfig.isOpen  then
      tInfo.tFreeConfig.nLimitBB=tInfo.tFreeConfig.nLimitBB or 0
   else
      -- tInfo.tFreeConfig.nLimitBB=0
   end
   tInfo.nCutoffValue=tInfo.nCutoffValue or 0
   tInfo.nLessValue=tInfo.nLessValue or 0
   tInfo.nGreaterValue =tInfo.nGreaterValue or 0
  if tInfo.nLessValue<0 then
      tInfo.nLessValue =0
  end
  if tInfo.nGreaterValue<0 then
      tInfo.nGreaterValu=0
  end
  tInfo.nPoolEntryRateHands = tInfo.nPoolEntryRateHands or 300
  tInfo.nPoolHands = tInfo.nPoolHands or 0
  tInfo.nIsPerson = tInfo.nIsPerson or 0
  tInfo.nIsShow = tInfo.nIsShow or 1
  tInfo.sPassWord = tInfo.sPassWord or ""
  return true
end

--后台递增减机器人
function MsgHandle.OnAndroidIncr(sReturnKey,Data,nLen)
   local tData =BackstageAux:Parser(Data, nLen,"ReqAddAndroid")
   assert(tData~=nil,"ReqAddAndroid Parser Error")
   local sTableId =tData.sTableId or ""
   local nReserve =tData.nReserve   --1:增加一个机器人 -1:减少一个机器人 其它:无意义
   tBase.LogT("OnAndroidIncr ",{sTableId=sTableId,nReserve=nReserve})
   local tTable =tTableMgr.GetBaiRenTable(sTableId)
   if tTable==nil then
      tBase.Log("tTable is nil,%s",sTableId)
      return
   end
   if nReserve ==1 then
      tTable:OnIncrAndroid()
   elseif nReserve ==-1 then
      tTable:OnDecrAndroid()
   end
end


--后台桌子管理请求
function MsgHandle.OnReqAPI_Table(sReturnKey,Data,nLen)
   local tData =BackstageAux:Parser(Data, nLen,"ReqAPI_Table")
   assert(tData~=nil,"OnReqAPI_Table Parser Error")
   tBase.LogT("OnReqAPI_Table:",{nLiveUserID=tData.nLiveUserID,nType=tData.nType,sTableId=tData.sTableId,nDuration=tData.nDuration,
   nGroupId=tData.nGroupId,sTableName=tData.sTableName,nTableType=tData.nTableType,nThirdPartyTableId=tData.nThirdPartyTableId,sLiveID=tData.sLiveID,
   sPlatformID =tData.sPlatformID,sConfig =tData.sConfig})
   --开桌
   if tData.nType==1 then
      if PublicDefine.isTest then
         return
      end
      local isSuccee,tRlt =pcall(cjson.decode,tData.sConfig)
      if not isSuccee then
         SetTableOpResult(tData.sRequestkey,{nErrorCode=20})
         tBase.LogT("_CreateTable fail,nCode:",20)
         tBase.LogT(tRlt)
         return
      end
      local isCorrect,sErr =ConfigCorrected(tRlt)
      if not isCorrect then
         SetTableOpResult(tData.sRequestkey,{nErrorCode=21})
         tBase.LogT("_CreateTable fail,nCode:",21)
         tBase.LogT(sErr)
         return
      end
      local tParameter ={
         nGroupId =tData.nGroupId,
         nRoomId =tData.nRoomId,
         nLiveUserID=tData.nLiveUserID,
         nTableType =tData.nTableType,
         sLiveID =tData.sLiveID,
         sPlatformID=tData.sPlatformID,
         sTableName =tData.sTableName,
         nGameId =math.floor(tRlt.nGameId),
         sTableId=string.format("%d#%s",tSrvInfo.nServerId,tPubUser.CreatePaiJuID()),
         tJsonConfig =tRlt,                                 --解码后的json设置
         sConfig =tData.sConfig,                            --用来回写到redis
      }
      local tTable,nCode =  _CreateTable(tParameter)
      if not tTable then
         SetTableOpResult(tData.sRequestkey,{nErrorCode=nCode})
         tBase.LogT("_CreateTable fail,nCode:",nCode)
         return
      end
      local t={
         nErrorCode=0,
         sTableId =tTable:TableId(),
         nGameId =tRlt.nGameId,
         nRoomId =tTable:RoomId(),
         sTableIdentify =tTable:TableId()
      }
      SetTableOpResult(tData.sRequestkey,t)
      tBase.LogT("_CreateTable succee,sTableId:",tTable:TableId())
      --俱乐部桌开桌通知
      local tTableInfo = tTable:GetTableInfoForClub()
      tTableInfo.sRequestkey = tData.sRequestkey
      tPublicClub.ClubTableOpenNotify(tRlt.nClubId,tTable:TableId(),tTableInfo)
   end
   --关桌
   if tData.nType==2 or tData.nType==3 then
      if MsgHandle._CloseTable(tData.sTableId,tData.sRequestkey) then
         RecordDbr.LiveTableClose(tData.sTableId)  
      end
   end
end

--后台改牌
function MsgHandle.ChangeCardReq(sReturnKey,Data,nLen)
   local tData =BackstageAux:Parser(Data, nLen,"ChangeCardReq")
   assert(tData~=nil,"ChangeCardReq Parser Error")

   local sTableId =tData.sTableId 			   --牌桌id
   local sPaiJuId =tData.sPaiJuId 			   --牌局id
   local nCardOriginal =tData.nCardOriginal	--需要改掉的牌
   local nCardChangeTo =tData.nCardChangeTo	--改成什么牌 (将牌'nCardOriginal'改为牌'nCardChangeTo')
   local sRequestkey =tData.sRequestkey       --请求唯一标识(用于每次请求返回获取 结果)
   tBase.LogT("ChangeCardReq:",{sTableId=sTableId,sPaiJuId=sPaiJuId,nCardOriginal=nCardOriginal,nCardChangeTo=nCardChangeTo})

   local tTable =tTableMgr.GetBaiRenTable(sTableId)
   if tTable==nil then
      tBase.Log("tTable is nil,%s",sTableId)
      return
   end
   local isSuccee,sErr =tTable:ChangeCard(sPaiJuId,nCardOriginal,nCardChangeTo)
   tBase.Log("ChangeCard %s,sErr:%s",tostring(isSuccee),tostring(sErr))
   if isSuccee then
      SetTableOpResult(sRequestkey,{nResult=1})
   else
      SetTableOpResult(sRequestkey,{nResult=10})
   end
end

--Ai结果返回
function MsgHandle.OnDZARsp(sClientID, tData, nLen)
   local tData =AiAux:Parser(tData, nLen,"DZARsp")
   assert(tData~=nil)
   tBase.Log("OnDZARsp:%s",tData.sEcho)

   tAiGet.CallBack(tData.sEcho,{nActionId=tData.nActionId,nBet=tData.nBet,sEcho=tData.sEcho})
   --nActionId
   --nBet
end

--后台踢人
function MsgHandle.OnKickUser(sClientID, Data, len)
   local s = tBase.GetRP().new(Data, len)
   local Read = ProtoMgr.PubProto_1_pb.REQ_Kick_User()
   Read:ParseFromString(s:GetString())
   local nUserId    = Read.nUserId or -1
   local nType      = Read.nType or -1    --1:立即踢出，解散 2:下局踢出
   tBase.Log("OnKickUser nUserId:%d nType:%d",nUserId,nType)
  -- MsgHandle._OnUserTableMsgHandle(nUserId,"REQ_Kick_User",Read)
end

local function _TableClose(sTableId,nTableType)
   local tTable =tTableMgr.GetBaiRenTable(sTableId)
   tTableMgr.CloseTable(sTableId)
   tPubUser.API_Close_Table(sTableId)
   if nTableType ==5 then     --俱乐部桌子
      tPublicClub.ClubTableCloseNotify(tTable:ClubId(),sTableId)
   end
end

-- 重启服务器 将桌子删除
function MsgHandle.DeleteTable()  
   local sKey = "APIOpenTale_"..tSrvInfo.nServerId.."#*"
   local tRedis =tBase.m_MyRedisData[2].redis
   local arrTableInfo = tRedis:keys(sKey)
   for _,val in pairs(arrTableInfo) do
       local tInfo = tRedis:hgetall(val)
       local nGameId =tonumber(tInfo.nGameId)
       if tInfo and tInfo.sTableId and (nGameId == Define.nGameId_Normal or nGameId == Define.nGameId_Ahm) then 
         tRedis:del(val)
       end 
   end
end 

 --比赛服登陆回复	
function MsgHandle.OnDZCLogOnResp(sReturnKey,Data,nLen) 
   local tData =CenterAux:Parser(Data, nLen,"DZCLogOnResp")
   assert(tData~=nil)
   tBase.Log("OnDZCLogOnResp From matchServ")
end

--

function MsgHandle.SendToMatchServ(nEventId,sCmd,tData)
   local DZCMtRsp ={}
	DZCMtRsp.sCmd =sCmd
	DZCMtRsp.sJsonData=cjson.encode(tData)
	DZCMtRsp.nEventId=nEventId
	DZCMtRsp.nEcho =-1
   if MsgHandle.SendToMatchServer then
      MsgHandle.SendToMatchServer("DZCMtRsp",DZCMtRsp)
   else
      assert(false)
   end
end


--来自比赛服 创桌请求 处理
local function _CreateMtTable(sReturnKey,tData,nEventId,sCmd)
   local tJsonConfig ={}
	tJsonConfig.nCapacity=tData.nCapacity				       --能供玩游戏的座位数
   tJsonConfig.nTakeIn=tData.nTakeIn					       --初始记分牌
   tJsonConfig.nGameId=tData.nGameId	                   --游戏Id
   tJsonConfig.nEventId=nEventId                          --赛事id
	tJsonConfig.tFeeR =tData.tFeeR				            --重购费s
	tJsonConfig.tFeeA =tData.tFeeA					         --增购费s
	tJsonConfig.tEvtTakInR =tData.tEvtTakInR		         --重购规则s
	tJsonConfig.tEvtTakInA =tData.tEvtTakInA		         --增购规则s
	tJsonConfig.arrLvItem =tData.arrLvItem			         --升盲列表s
	tJsonConfig.nBlindUpGap =tData.nBlindUpGap     	      --涨盲时间 秒
	tJsonConfig.nTimeStampBegin =tData.nTimeStampBegin    --开赛时间(涨盲初始时间)
   local tFirstBlind=tJsonConfig.arrLvItem[1] or {}
	tJsonConfig.nSmallBlind=tFirstBlind.nSmallB			   --小盲注数额
	tJsonConfig.nBigBlind=tFirstBlind.nBigB				   --大盲注数额(通常等于:小盲注x2)
   tJsonConfig.nTimeBefore=tData.nTimeBefore 	         --开赛前时间 秒(期间内，已报名者可"进入比赛")
	tJsonConfig.nTimeAfter=tData.nTimeAfter		         --开赛后时间 秒(期间内，未报名者可"延迟报名",超过后所有人仅能"观战")
   tJsonConfig.nCntBegin =tData.nCntBegin                --最小开赛人数
   --奖励列表s
	tJsonConfig.nAwardType =tData.nAwardType			      --奖励方式 1:固定 2:奖池百分比
	tJsonConfig.arrAward=tData.arrAward
	tJsonConfig.arrAwardPercent=tData.arrAwardPercent
   --是否为等待桌(用来给报名玩家等待分配桌子)
   tJsonConfig.isWaitRoom =tData.isWaitRoom
   tJsonConfig.isFree =tData.isFree                      --是否报名免费
   tJsonConfig.nUserCntMax =tData.nUserCntMax            --最大报名人数
   tJsonConfig.nLoopType =tData.nLoopType                --1按月 2按周 3按天 4按次 5测试循环
   tJsonConfig.sUkey =tData.sUkey                        --比赛唯一标识

   local tParameter ={
      nGroupId =tData.nGroupId,
      nRoomId =0,
      nLiveUserID=0,
      nTableType =3,
      sLiveID ="",
      sPlatformID="",
      sTableName =tData.sName,
      nGameId =tJsonConfig.nGameId,
      sTableId=string.format("%d#%s",tSrvInfo.nServerId,tPubUser.CreatePaiJuID()),
      tJsonConfig =tJsonConfig,                                 --解码后的json设置
      sConfig =cjson.encode(tJsonConfig),                       --用来回写到redis
   }
   
   local arrTb ={}
   for i=1,tData.nCntCreate do
      tParameter.sTableId =string.format("%d#%s",tSrvInfo.nServerId,tPubUser.CreatePaiJuID())
      local tTable,nCode =  _CreateTable(tParameter,1)
      if tTable then
         table.insert(arrTb,tTable:TableId())
      end
   end
   tBase.Log("_CreateMtTable nCntCreate:%d actul:%d nEventId:%d nGameId:%d",tData.nCntCreate,#arrTb,nEventId,tData.nGameId)
   MsgHandle.SendToMatchServ(nEventId,sCmd,{arrTb=arrTb,isWaitRoom=tData.isWaitRoom})
end

--关闭比赛桌
local function CloseMtTable(nEventId)
   local arrTb =tTableMgr.GetMttTables(nEventId)
   for _,tB in ipairs(arrTb) do
      MsgHandle._CloseTable(tB:TableId(),nil,Define.TableCloseReason.nMatchServ)
   end
   return #arrTb
end

--游戏服或比赛服主动结束比赛
local function CloseMtt(nEventId,sReason,isGameServDo)
   local nCnt =CloseMtTable(nEventId)
   tBase.Log("CloseMtt,nCloseTableCnt:%d,sReason:%s,isGameServDo:%s,nEventId:%d",nCnt,tostring(sReason),tostring(isGameServDo),nEventId)
   if isGameServDo then
      MsgHandle.SendToMatchServ(nEventId,"MttEnd",{sReason=sReason})  --
   end
end


---来自比赛服请求 处理
function MsgHandle.OnDZCMtReq(sReturnKey,Data,nLen) 
   local tData =CenterAux:Parser(Data, nLen,"DZCMtReq")
   assert(tData~=nil)
   local sCmd=tData.sCmd
	local sJsonData=tData.sJsonData
	local nEventId=tData.nEventId
	local nEcho=tData.nEcho
   tBase.Log("OnDZCMtReq sCmd:%s nEventId:%d",sCmd,nEventId)

   local isSuccee,tRlt =pcall(cjson.decode,sJsonData)
	if not isSuccee then
		tBase.Log("Json decode Fail,%s",sJsonData)
		return
	end

   --创建比赛桌
   if sCmd =="CreateMtTable" then
      _CreateMtTable(sReturnKey,tRlt,nEventId,sCmd)
      return
   end
   --关闭比赛
   if sCmd =="CloseMtt" then
      CloseMtt(nEventId,tRlt.sReason,false)
      return
   end
end

local function GetMttUserCnt(nEventId)
   local nCnt =0
   local arrTb =tTableMgr.GetMttTables(nEventId)
   for _,tB in ipairs(arrTb) do
      local nUserCnt= tB:GetUserCnt()
      nCnt =nCnt +nUserCnt
   end
   return nCnt
end

--更新比赛玩家排名和平均筹码等信息
local function _UpdateMttUsersRank(nEventId)
   local arrTb =tTableMgr.GetMttTables(nEventId)
   local arrUsers ={}
   local nChipSum =0
   for _,tB in ipairs(arrTb) do
      local arrUserC= tB:GetUsersChip()
      for _,v in ipairs(arrUserC) do
         table.insert(arrUsers,v)
         nChipSum =nChipSum +v.nChip
      end
   end
   table.sort(arrUsers,function(A,B) return A.nChip>B.nChip end)  --按筹码数由大到小排序
   local tUserIdToRank={}
   for dex,v in ipairs(arrUsers) do
      tUserIdToRank[v.nUserId] =dex
   end
   local nUserCnt =#arrUsers
   local nChipAv =0
   if nChipSum>=1 then
      nChipAv =math.floor(nChipSum/nUserCnt) 
   end
   for _,tB in ipairs(arrTb) do
      tB:UpdateRank(nUserCnt,nChipAv,tUserIdToRank)
   end
end

local UpdateRankTimer =tTimerAux:New()
local tEventIdToFucId ={}
local function UpdateMttUsersRank(nEventId)
   if tEventIdToFucId[nEventId] then
      UpdateRankTimer:KillTimer(tEventIdToFucId[nEventId])
   end
   tEventIdToFucId[nEventId]= UpdateRankTimer:DelayCall(0.5*1000,_UpdateMttUsersRank,nEventId)
end

--为正在等待比赛的玩家统一分配桌子
local function BindForBatch(nEventId,arrUserItem,nCapacity,tFromTb)
   local nCnt =#arrUserItem
	if nCnt==0 then
		return
	end
   assert(nCapacity>0,"MTT Error:nCapacity Error")
	local nTbNeed =math.ceil(nCnt/nCapacity)
   local arrTb =tTableMgr.GetMttTables(nEventId)
   local arrEmptyTb={}
   for _,tB in ipairs(arrTb) do
      local nUserCnt= tB:GetUserCnt()
      if (not tB:IsWaitRoom()) and  nUserCnt==0 then
         table.insert(arrEmptyTb,tB)
         if #arrEmptyTb ==nTbNeed then
            break
         end
      end
   end
   if #arrEmptyTb ~=nTbNeed then
      assert(false,"MTT Error:Table Too Few")
      return
   end
	for n,tUserItem in ipairs(arrUserItem) do
		local nDex =(n%nTbNeed) +1
		local tB =arrEmptyTb[nDex]
      tB:BindUser(tUserItem)
		tFromTb:AssignUserTo(tUserItem.nUserId,tB:TableId())
	end
end

--为单个比赛玩家分配桌子
local function BindForSingle(nEventId,tUserItem,tFromTb)
   local arrTb =tTableMgr.GetMttTables(nEventId)
   local arr={}
   for _,tB in ipairs(arrTb) do
      local nUserCnt,nCapacity,nBindCnt= tB:GetUserCnt()
      if (not tB:IsWaitRoom()) and  nBindCnt<nCapacity and  nUserCnt<nCapacity then
         local nCnt =math.max(nUserCnt,nBindCnt)
         table.insert(arr,{nCnt=nCnt,tB=tB})
      end
   end
   table.sort(arr,function(A,B) return A.nCnt<B.nCnt end) --按人数由小到大排序
   assert(#arr>0,"MTT Error:BindForSingle,Table Too Few")
   local tTarget =arr[1].tB
   for _,v in ipairs(arr) do
      if v.nCnt>0 then
         tTarget =v.tB
         break
      end
   end
   tTarget:BindUser(tUserItem)
   tFromTb:AssignUserTo(tUserItem.nUserId,tTarget:TableId())
end


--返回一张旁观桌子id
local function GetNextTableIdOfMtt(nEventId,sNowTableId)
   local arrTb =tTableMgr.GetMttTables(nEventId)
	local arr ={}
	for _,tB in ipairs(arrTb) do
      local nUserCnt= tB:GetUserCnt()
      if not tB:IsWaitRoom() and nUserCnt>0 then
		   table.insert(arr,tB:TableId())
      end
	end
	table.sort(arr)
	local nNowDex =nil
	for dex,v in ipairs(arr) do
		if v==sNowTableId then
			nNowDex =dex
			break
		end
	end
	nNowDex =nNowDex or 0
	if nNowDex<#arr then
		nNowDex =nNowDex +1
	else
		nNowDex =1
	end
	local sNextTableId =arr[nNowDex]
	return sNextTableId
end

function MsgHandle.MttSplitUsers(nEventId,tFromTb,arrUserId)
   local arrTb =tTableMgr.GetMttTables(nEventId)
   local arr={}
   local nEmptySum=0
   local sFromTableId =tFromTb:TableId()
   local nUserCntAll=0
   for _,tB in ipairs(arrTb) do
      local nUserCnt,nCapacity,nBindCnt= tB:GetUserCnt()
      nUserCntAll =nUserCntAll +nUserCnt
      local sTableId =tB:TableId()
      if sTableId~=sFromTableId and nUserCnt>0 and nBindCnt<nCapacity and  nUserCnt<nCapacity then
         local nCnt =math.max(nUserCnt,nBindCnt)
         table.insert(arr,{sTableId=sTableId,nUserCnt=nCnt,tB=tB})
         nEmptySum =nEmptySum +(nCapacity -nCnt)
      end
   end
	--全部拆散分到其它桌
	if nEmptySum>=#arrUserId then
		for _,nUserId in ipairs(arrUserId) do
			table.sort(arr,function(A,B) return A.nUserCnt<B.nUserCnt end) --按人数由小到大排序
			local tFirst =arr[1]
			tFirst.nUserCnt=tFirst.nUserCnt +1
         local tD,tUserItem =tFromTb:UnBindForR(nUserId,tFirst.sTableId)
         tFirst.tB:BindUser(tUserItem,tD)
		end
		return nUserCntAll
	end
	--拆散部分到其它人少的桌
	local nCntNow =#arrUserId
	for _,nUserId in ipairs(arrUserId) do
		table.sort(arr,function(A,B) return A.nUserCnt<B.nUserCnt end) --按人数由小到大排序
		local tFirst =arr[1]
		if tFirst and (nCntNow-tFirst.nUserCnt) >=2 then
			tFirst.nUserCnt=tFirst.nUserCnt +1
			nCntNow =nCntNow -1
			local tD,tUserItem =tFromTb:UnBindForR(nUserId,tFirst.sTableId)
         tFirst.tB:BindUser(tUserItem,tD)
		end
      return nUserCntAll
	end
	return nUserCntAll
end

--机器人获取
local function _GetRobots(tRoomConfig,nRobotCntNeed)
   tUserMgr.DoPrepareRobot(tRoomConfig)
   return tUserMgr.GetRobots(tRoomConfig,nRobotCntNeed) 
end

--玩家离开桌子
local function _LeaveTable(nUserId,tTable,isChangTable)
    local tUser = tUserMgr.GetUser(nUserId)
    if tUser==nil then --这是真人
      return
    end
    tUser:LeaveTable(tTable:TableId())
    assert(tUser.isAndroid)
    if not isChangTable then     --比赛桌子中，换桌时离开原桌子不用删
      tUserMgr.DelUser(nUserId)
    end
end
local function SendToUser(nUserId,strProto,tSendData)
   local tUser = tUserMgr.GetUser(nUserId)
   if tUser==nil then   --这是真人
      return
   end
   assert(tUser.isAndroid)
   --使用pcall调用，隔断AI对游戏主流程的影响
   local isSuccee,ret =pcall(tUser.OnMsgHandle,tUser,strProto,tSendData)   
   if isSuccee then return end
   tBase.LogT("_UserMsgHandle Err happen=>",strProto," ",tSendData)
	tBase.LogT(ret)
   if type(ret) == "string" then 
      logger:error(ret)
  end
end

local function UserEnterTable(nUserId,tTable,nSitId)
   local tUser = tUserMgr.GetUser(nUserId)
   if tUser==nil then   --这是真人
      return 
   end
   tUser:EnterTable(tTable,nSitId)
end


tGameInterFace.SendToUser =SendToUser
tGameInterFace._LeaveTable =_LeaveTable
tGameInterFace._TableClose =_TableClose
tGameInterFace._GetRobots =_GetRobots
tGameInterFace.GetUser =tUserMgr.GetUser

tGameInterFace.SendToMatchServ= MsgHandle.SendToMatchServ
tGameInterFace.GetNextTableIdOfMtt =GetNextTableIdOfMtt
tGameInterFace.MttSplitUsers =MsgHandle.MttSplitUsers
tGameInterFace.GetMttUserCnt =GetMttUserCnt
tGameInterFace.UpdateMttUsersRank =UpdateMttUsersRank
tGameInterFace.BindForBatch =BindForBatch
tGameInterFace.BindForSingle =BindForSingle
tGameInterFace.CloseMtt =CloseMtt
tGameInterFace.UserEnterTable =UserEnterTable

return MsgHandle