local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tBase = require("base") -- 基础功能接口
local tTableMgr   = require("TableManage")
local tUserMgr   = require("UserManager") 
local tPubUser = require("PublicUserInfo")   -- 用户信息 
local Define =require("Define") 
local tSrvInfo = require("ServerInfo")
local RecordDbr =require("RecordDbr")  
local cjson    = require("cjson") 
local tSlaveManager =require("SlaveManage")
local tPublicClub =require("PublicClub") 

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
   tTableInfo.nGameId =Define.nGameId
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
function MsgHandle._CloseTable(sTableId,sRequestkey)
   local tTable =tTableMgr.GetBaiRenTable(sTableId)
   if tTable==nil then
      tBase.Log("close table fail,can not find table")
      SetTableOpResult(sRequestkey,{nErrorCode=1})
      return false
   end
   SetTableOpResult(sRequestkey,{nErrorCode=0})
   tTable:SetClose(Define.TableCloseReason.nBackstageClose)   --设置本局结束后关闭桌子
   return true
end

local function _CreateTable(tParameter)
   tBase.LogT("CreateTable   tParameter:",tParameter)
   local isSuccee,tTable= tTableMgr.CreateTable(tGameInterFace,tParameter.sTableId,tParameter)
   if not isSuccee then
      return nil,11
   end
   tTable:Init()
   CreateTableInRedis(tParameter)
   RecordDbr.LiveTableCreate({sTableId=tParameter.sTableId,
                              sTableName=tParameter.sTableName,
                              nGameId=Define.nGameId,
                              nGroupId=tParameter.nGroupId,
                              nRoomId=tParameter.nRoomId})
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
   tJsonConfig.isNeedAndroid =tJsonConfig.isNeedAndroid or false
   -- if tJsonConfig.nSmallBlind==nil or tJsonConfig.nSmallBlind<=0 then
   --    tJsonConfig.nSmallBlind=1
   -- end
   -- if tJsonConfig.nBigBlind==nil or tJsonConfig.nBigBlind<tJsonConfig.nSmallBlind then
   --    tJsonConfig.nBigBlind =(tJsonConfig.nSmallBlind*2)
   -- end
   if tJsonConfig.nCapacity==nil or tJsonConfig.nCapacity<0 then
      tJsonConfig.nCapacity=0
   end
   tJsonConfig.nIntervalLev =tJsonConfig.nIntervalLev or 1           --牌局间隔 1:短暂 2:适中 3:漫长
   tJsonConfig.nMinTabkeInBB =tJsonConfig.nMinTabkeInBB or 10
   tJsonConfig.nMaxTabkeInBB =tJsonConfig.nMaxTabkeInBB or 100
   if tJsonConfig.nMinTabkeInBB*100<3 then
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
   tJsonConfig.isForceBlind = tJsonConfig.isForceBlind or false

   tJsonConfig.isDPreAnte =tJsonConfig.isDPreAnte or false                    -- 短牌 庄家是否2倍前注
   tJsonConfig.isTabkeOut =tJsonConfig.isTabkeOut or false                    -- 是否 带出筹码

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
         nGameId =Define.nGameId,
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
   local nTableCnt = tTableMgr.CloseTable(sTableId)
   tPubUser.API_Close_Table(sTableId)
   if nTableType ==5 then     --俱乐部桌子
      tPublicClub.ClubTableCloseNotify(tTable:ClubId(),sTableId)
   end
   tBase.Log("_TableClose   nTableCnt: %d ",nTableCnt)
   if nTableCnt == 0 then 
      tUserMgr.DoReleaseRobot({nGroupId=tTable.nGroupId,nRoomId=tTable.nRoomId}) 
   end 
   
end

local function GetInt(str)
   return math.floor(tonumber(str))
end

-- 重启牌桌
local function _RestaertTable(tParameter)
   tBase.LogT("_RestaertTable   tParameter:",tParameter)   
   tParameter.nLiveUserID = GetInt(tParameter.nLiveUserID)
   tParameter.nRoomId = GetInt(tParameter.nRoomId)
   tParameter.nRoomId = GetInt(tParameter.nRoomId)
   tParameter.nGroupId = GetInt(tParameter.nGroupId)

   local isSuccee,tRlt =pcall(cjson.decode,tParameter.sConfig)

   tParameter.tJsonConfig = tRlt
   local isSuccee,tTable= tTableMgr.CreateTable(tGameInterFace,tParameter.sTableId,tParameter)
   if not isSuccee then
      return nil,11
   end

   tTable:Init()  

   --广播到从服
   local tScence= tTable:GetScence()
   local sJsonScenc= cjson.encode(tScence)
   local DZCScenceRsp ={}
   DZCScenceRsp.sTableId=tParameter.sTableId
   DZCScenceRsp.sJsonScenc =sJsonScenc
   DZCScenceRsp.nEcho =-1
   tSlaveManager.Broadcast("DZCScenceRsp",DZCScenceRsp)


   --俱乐部桌开桌通知
   tPublicClub.ClubTableOpenNotify(tRlt.nClubId,tTable:TableId(),tTable:GetTableInfoForClub())
    
   return tTable
end

-- 重启服务器  恢复永久牌桌
function MsgHandle.RestartServiceTable()   
   local sKey = "APIOpenTale_"..tSrvInfo.nServerId.."#*"
   local tRedis =tBase.m_MyRedisData[2].redis
   local arrTableInfo = tRedis:keys(sKey)
   for _,val in pairs(arrTableInfo) do
       local tInfo = tRedis:hgetall(val)
       if tInfo and tInfo.sTableId and tonumber(tInfo.nGameId) == Define.nGameId then 
         local tCfg = cjson.decode(tInfo.sConfig)
         if tonumber(tCfg.nKeepTime) == -1 then   -- 永久牌桌，需要开起来
            tBase.Log("_RestartServiceTable  永久牌桌，需要开起来 sTableId:  "..tInfo.sTableId) 
            _RestaertTable(tInfo) 
         end
       end 
   end
end 

-- 重启服务器 将桌子删除
function MsgHandle.DeleteTable()   
   local sKey = "APIOpenTale_"..tSrvInfo.nServerId.."#*"
   local tRedis =tBase.m_MyRedisData[2].redis
   local arrTableInfo = tRedis:keys(sKey)
   for _,val in pairs(arrTableInfo) do
       local tInfo = tRedis:hgetall(val)
       if tInfo and tInfo.sTableId and tonumber(tInfo.nGameId) == Define.nGameId then 
         local tCfg = cjson.decode(tInfo.sConfig)
         if tonumber(tCfg.nKeepTime) ~= -1 then    
            tRedis:del(val) 
            tBase.Log("_DeleteTable  重启服务器 将桌子删除 sTableId:  "..tInfo.sTableId.." sConfig: "..tInfo.sConfig)
         else 
            tRedis:del(val)   -- 2.3版本才 进行恢复 永久牌桌
         end
       end 
   end
end 



--机器人获取
local function _GetRobots(tRoomConfig,nRobotCntNeed)
   tUserMgr.DoPrepareRobot(tRoomConfig)
   return tUserMgr.GetRobots(tRoomConfig,nRobotCntNeed) 
end

--玩家离开桌子
local function _LeaveTable(nUserId,tTable)
    local tUser = tUserMgr.GetUser(nUserId)
    if tUser==nil then --这是真人
      return
    end
    tUser:LeaveTable(tTable:TableId())
    assert(tUser.isAndroid)
    tUserMgr.DelUser(nUserId)
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

tGameInterFace.SendToUser =SendToUser
tGameInterFace._LeaveTable =_LeaveTable
tGameInterFace._TableClose =_TableClose
tGameInterFace._GetRobots =_GetRobots
tGameInterFace.GetUser =tUserMgr.GetUser
return MsgHandle