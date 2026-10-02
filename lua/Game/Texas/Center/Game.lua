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
   tTableInfo.nGameId =Define.nGameId
   tTableInfo.nRoomId =tTableConfig.nRoomId
   tTableInfo.nLiveUserID=math.floor(tTableConfig.nLiveUserID)
   tTableInfo.nGroupId =math.floor(tTableConfig.nGroupId)
   tTableInfo.sTableName=tTableConfig.sTableName
   tTableInfo.nTableType=tTableConfig.nTableType
   tTableInfo.sLiveID =tTableConfig.sLiveID
   tTableInfo.sPlatformID =tTableConfig.sPlatformID
   tTableInfo.sConfig =tTableConfig.sConfig
   tTableInfo.nClubId =tTableConfig.nClubId    
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


local function _CreateTable(tParameter,sTableId)
   local nGroupId =tParameter.nGroupId
   local nRoomId =tParameter.nRoomId
   local tBackstageConfig =tPublicRedis.GetTexasConfig(nGroupId,nRoomId)   --后台配置
  
   local tConfig ={}
   tConfig.arrCapacityOption =tBackstageConfig.arrCapacityOption        --主播可选人数设置
   tConfig.arrConfigOption =tBackstageConfig.arrConfigOption            --主播可选大小盲、最低最高带入选项
   tConfig.nLiveUserID =tParameter.nLiveUserID                          --主播用户id
   tConfig.nSmallBlind =tParameter.nSmallBlind or 1                      --小盲
   tConfig.nBigBlind =tParameter.nBigBlind or (2*tConfig.nSmallBlind)    --大盲
   tConfig.nCapacity =tParameter.nCapacity or 6                          --人数
   tConfig.nBuyMin =tParameter.nBuyMin or (10*tConfig.nBigBlind)         --最小买入
   tConfig.nBuyMax =tParameter.nBuyMax or (20*tConfig.nBuyMin)           --最大买入
   tConfig.nFee =tParameter.nFee or tBackstageConfig.nFee or 0           --手续费
   tConfig.nTax =tParameter.nTax or tBackstageConfig.nTax or 0           --抽水(百分比) 
   tConfig.isUseApiConfig =tParameter.isUseApiConfig                     --true时,主播不用选配(使用当前配置)
   tConfig.nIntervalLev =tParameter.nIntervalLev or 2                    --牌局间隔 1:短暂 2:适中 3:漫长
   tConfig.nTableType =tParameter.nTableType                             --桌子类型
   tConfig.sTableName =tParameter.sTableName                             --桌子名称
   tConfig.sLiveID =tParameter.sLiveID                                   --
   tConfig.sPlatformID =tParameter.sPlatformID                           --
   tConfig.isPassWordRoom =tParameter.isPassWordRoom                     --是否密码房
   tConfig.nGroupId =nGroupId
   tConfig.nRoomId =nRoomId
   tConfig.nElapseMax =tParameter.nElapseMax
   tConfig.sConfig =tParameter.sConfig                                  --后台传过来得json配置,用来回写到redis
   tConfig.nClubId =tParameter.nClubId                                 --俱乐部id (俱乐部房配置)
   tConfig.nItemId=tParameter.nItemId                                 --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置)
   tConfig.nKeepTime =tParameter.nKeepTime                            --房间时长(秒) (俱乐部房配置)
   tConfig.nGoldType =tParameter.nGoldType                             --1:金币 2:俱乐部币 3:积分 (俱乐部房配置)
   tConfig.isNeedAndroid =tParameter.isNeedAndroid                     --是否需要加载机器人 true:要 false:不要 (俱乐部房配置)
   tConfig.tJsonConfig =tParameter.tJsonConfig
   tConfig.sTableId =sTableId or string.format("%d#%s",tSrvInfo.nServerId,tPubUser.CreatePaiJuID())
   tBase.LogT("CreateTable tConfig:",tConfig)

   local isSuccee,tTable= false,nil
   if tConfig.nTableType ==3 then   --比赛桌
      isSuccee,tTable=tTableMgr.CreateTableMatch(tGameInterFace,tConfig.sTableId,tConfig)
   else
      isSuccee,tTable=tTableMgr.CreateTable(tGameInterFace,tConfig.sTableId,tConfig)
   end

   if not isSuccee then
      return nil,11
   end
   if tConfig.isNeedAndroid ==false or tConfig.isPassWordRoom then
      tTable:BanRobot() --禁止机器人
   end

   CreateTableInRedis(tConfig)
   RecordDbr.LiveTableCreate({sTableId=tConfig.sTableId,sTableName=tConfig.sTableName,nGameId=Define.nGameId,nGroupId=nGroupId,nRoomId=nRoomId})
   tTable:TryLetAndroidEnter()   --定时检查桌子是否需要加入机器人,是则加入
   tTable:TableCheck()           --定时检查真人进入情况,桌子过久没真人则自动关闭

   --广播到从服
   local tScence= tTable:GetScence()
   local sJsonScenc= cjson.encode(tScence)
   local DZCScenceRsp ={}
   DZCScenceRsp.sTableId=tConfig.sTableId
   DZCScenceRsp.sJsonScenc =sJsonScenc
   DZCScenceRsp.nEcho =-1
   tSlaveManager.Broadcast("DZCScenceRsp",DZCScenceRsp)
   return tTable
end


local function IsTexasConfigLegal(tTexasConfig)
  if  tTexasConfig.nSmallBlind==nil or
      tTexasConfig.nBigBlind==nil or
      tTexasConfig.nTakeInMin==nil or
      tTexasConfig.nTakeInMax==nil or
      tTexasConfig.nCapacity==nil or
      tTexasConfig.nIntervalLev==nil then
      return false
   end
   if  tTexasConfig.nSmallBlind <=0 then
      return false
   end
   if  tTexasConfig.nBigBlind <=tTexasConfig.nSmallBlind then
      return false
   end
   if tTexasConfig.nTakeInMin <tTexasConfig.nBigBlind then
      return false
   end
   if tTexasConfig.nTakeInMax < tTexasConfig.nTakeInMin then
      return false
   end
   if tTexasConfig.nCapacity<2 or tTexasConfig.nCapacity>9 then
      return false
   end
   if tTexasConfig.nIntervalLev<1 or tTexasConfig.nIntervalLev>3 then
      return false
   end
   return true
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
      tBase.LogT("Can not find talbe:%s",tData.sTableId)
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

--桌子创建请求(匹配桌)
function MsgHandle.OnDZCTableCreateReq(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCTableCreateReq")
   assert(tData~=nil)

  local sTableId=tData.sTableId
  local tParameter=cjson.decode(tData.sParameter)

  local tTable,nCode =  _CreateTable(tParameter,sTableId)

  local nTableCnt =tTableMgr.GetCntOfMatchTable(tParameter.nGroupId ,tParameter.nRoomId)
  
  
  local tCntOfMathcTableShould=5
  if nTableCnt >=tCntOfMathcTableShould then
      return 
  end
  for i=1,(tCntOfMathcTableShould-nTableCnt) do
      _CreateTable(tParameter)
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
      local isPassWordRoom =false
      local isSuccee,tRlt =pcall(cjson.decode,tData.sConfig)
      local tTexasConfig ={}
      local isUseApiConfig =false
      if isSuccee then
         isPassWordRoom =tRlt.isPassWordRoom          --是否为密码房
         tTexasConfig.nSmallBlind=tRlt.nSmallBlind	   --小盲
         tTexasConfig.nBigBlind=tRlt.nBigBlind		   --大盲
         tTexasConfig.nTakeInMin=tRlt.nTakeInMin	   --最低带入
         tTexasConfig.nTakeInMax=tRlt.nTakeInMax	   --最高带入
         tTexasConfig.nCapacity=math.floor(tRlt.nCapacity or 0)	      --人数配置
         tTexasConfig.nIntervalLev=math.floor(tRlt.nIntervalLev or 0)  --牌局间隔 1:短暂 2:适中 3:漫长
         if tData.nTableType ==5 then
            tTexasConfig.nClubId =tRlt.nClubId              --俱乐部id (俱乐部房配置)
            tTexasConfig.nItemId=tRlt.nItemId               --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置)
            tTexasConfig.nKeepTime =tRlt.nKeepTime          --房间时长(秒) (俱乐部房配置)
            tTexasConfig.nGoldType =tRlt.nGoldType          --1:金币 2:俱乐部币 3:积分
            tTexasConfig.isNeedAndroid =tRlt.isNeedAndroid  --是否需要加载机器人 true:要 false:不要
         end
         isUseApiConfig =IsTexasConfigLegal(tTexasConfig)
         tBase.Log("isUseApiConfig:%s",tostring(isUseApiConfig))
      end

      local tParameter ={
         nGroupId =tData.nGroupId,
         nRoomId =tData.nRoomId,
         nLiveUserID=tData.nLiveUserID,
         isPassWordRoom=isPassWordRoom,
         nTableType =tData.nTableType,
         sLiveID =tData.sLiveID,
         sPlatformID=tData.sPlatformID,
         sTableName =tData.sTableName,

         nSmallBlind = tTexasConfig.nSmallBlind	,	   --小盲
         nBigBlind =tTexasConfig.nBigBlind,	         --大盲
         nCapacity = tTexasConfig.nCapacity,	         --人数
         nBuyMin =tTexasConfig.nTakeInMin,			   --最小买入
         nBuyMax =tTexasConfig.nTakeInMax,            --最大买入
         nIntervalLev =tTexasConfig.nIntervalLev,     --牌局间隔 1:短暂 2:适中 3:漫长
         nClubId =tTexasConfig.nClubId,               --俱乐部id (俱乐部房配置)
         nItemId=tTexasConfig.nItemId ,               --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置)
         nKeepTime =tTexasConfig.nKeepTime,           --房间时长(秒) (俱乐部房配置)
         nGoldType =tTexasConfig.nGoldType,            --1:金币 2:俱乐部币 3:积分
         isNeedAndroid =tTexasConfig.isNeedAndroid,    --是否需要加载机器人 true:要 false:不要

         isUseApiConfig=isUseApiConfig,               --是否使用Api指定的配置(如果是,主播则不再能选配置)
         sConfig =tData.sConfig,                      --用来回写到redis
         tJsonConfig =tRlt,
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
      --[[牌桌信息 必须有的信息 tTableInfo = {nGameId=游戏id,sTableName=牌桌名字,nItemId=使用的金币id,nOpentime=开桌时间,nLiveUserID=房主id,nKeepTime=房间时长}
         德州要有的: nSmallBlind=小盲,nBigBlind=大盲,nTakeInMin=最低带入,nTakeInMax=最高带入,nIntervalLev=牌局间隔
      ]]--
      if tData.nTableType ==5 then
         
      --俱乐部桌开桌通知
      local tTableInfo = tTable:GetTableInfoForClub()
      tTableInfo.sRequestkey = tData.sRequestkey
      tPublicClub.ClubTableOpenNotify(tRlt.nClubId,tTable:TableId(),tTableInfo)

      end
     
      --[[
      local tTableInfo = {}
      tTableInfo.nGameId = 123 
      tTableInfo.nRoomId = tData.nRoomId 
      tTableInfo.nGroupId = tData.nGroupId 
      tTableInfo.nLiveUserID = tData.nLiveUserID 
      tTableInfo.sPlatformID = tData.sPlatformID 
      tTableInfo.sTableName = tData.sTableName  
      tTableInfo.sLiveID = tData.sLiveID  
      tTableInfo.nTableType = tData.nTableType  
      tTableInfo.sTableId = tTable.sTableId   
      tTableInfo.nType = tData.nType    
      tTableInfo.nGameServerId = tSrvInfo.nServerId  -- 服务器ID  
       tPLiveGame.MultistepBrocast(tPLiveGame.Msg.sTableHandle,tTableInfo)
       -- 场景
       tPLiveGame.MultistepBrocast(tPLiveGame.Msg.sScence,tTable:GetScence()) 
       ]]
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
       if tInfo and tInfo.sTableId and tonumber(tInfo.nGameId) == Define.nGameId then 
         tRedis:del(val)
       end 
   end
end 

function MsgHandle.CreateTestTable()
   local tParameter ={
      nGroupId =1,
      nRoomId =1,
      nLiveUserID=0,
      isPassWordRoom=false,
      nTableType =Define.TableType.nMatch,
      sLiveID ="",
      sPlatformID="",
      sTableName =string.format("Room_%d",1),

      nSmallBlind = 3	,	         --小盲
      nBigBlind =6,	               --大盲
      nCapacity = 6		,	         --人数
      nBuyMin =10,			         --最小买入
      nBuyMax =10 *20,              --最大买入
      nFee = 0	,				         --手续费
      nTax = 0	,				         --抽水(数据库配置为千分比，游戏里用百分比，所以除以10)
      nElapseMax=18000000,			    --多久没真人进入便关桌(秒)
   }
   local tNewTable,nCode = _CreateTable(tParameter)
end

--[[
function MsgHandle.GetNextTableOfMatch(nGroupId,nRoomId,sNowTableId)
   return tTableMgr.GetNextTableOfMatch(nGroupId,nRoomId,sNowTableId)
end

local tKeyToTableCreateCount ={}
function MsgHandle.GetTableOfMatch(nGroupId,nRoomId)
    local tTable = tTableMgr.GetTableOfMatch(nGroupId,nRoomId)
    if tTable then
         return tTable
    end

   --根据参数，返回对应的一个房间配置拷贝( {nGameId= ,nRoomId= ,nEnterFloorLimit= ,nAnte= ,nGroupId= ,nTax=} )
   local tRoomConfig =tGameConfig.GetRoomConfig_v2(Define.nGameId,nRoomId,nGroupId)
   if not tRoomConfig then
      tBase.Log("_CreateMatchTable fail,can not find room config, nRoomId:%d nGroupId:%d",nRoomId,nGroupId)
      return
   end

   if tRoomConfig.nAnte <=0 or tRoomConfig.nEnterFloorLimit< (tRoomConfig.nAnte*2) then
      tBase.Log("_CreateMatchTable fail,room config error, nRoomId:%d nGroupId:%d",nRoomId,nGroupId)
      return
   end
   local sKey =string.format("%d_%d",nGroupId,nRoomId)
   tKeyToTableCreateCount[sKey] =tKeyToTableCreateCount[sKey] or 0
   local nCreateCount =tKeyToTableCreateCount[sKey]

   local tParameter ={
      nGroupId =nGroupId,
      nRoomId =nRoomId,
      nLiveUserID=0,
      isPassWordRoom=false,
      nTableType =Define.TableType.nMatch,
      sLiveID ="",
      sPlatformID="",
      sTableName =string.format("Room_%d",nRoomId),

      nSmallBlind = tRoomConfig.nAnte	,	         --小盲
      nBigBlind =tRoomConfig.nAnte *2,	            --大盲
      nCapacity = 6		,	                        --人数
      nBuyMin =tRoomConfig.nEnterFloorLimit,			--最小买入
      nBuyMax =tRoomConfig.nEnterFloorLimit *20,   --最大买入
      nFee = 0	,				                        --手续费
      nTax = (tRoomConfig.nTax/10)	,				   --抽水(数据库配置为千分比，游戏里用百分比，所以除以10)
      nElapseMax=1800,			                     --多久没真人进入便关桌(秒)
   }
   local tNewTable,nCode =nil,nil
   if nCreateCount==0 then
      local nCnt =math.random(3,6)
      tParameter.nElapseMax =2000000000   --不自动关闭牌桌
      for i=1,nCnt do
         tNewTable,nCode = _CreateTable(tParameter)
      end
      tKeyToTableCreateCount[sKey] =nCnt
   else
      tNewTable,nCode =  _CreateTable(tParameter)
      tKeyToTableCreateCount[sKey] =tKeyToTableCreateCount[sKey] +1
   end
   if tNewTable then
      tBase.Log("_CreateMatchTable succee,sTableId:%s nRoomId:%d nGroupId:%d",tNewTable:TableId(),nRoomId,nGroupId)
      return tNewTable
   end
   tBase.Log("_CreateMatchTable fail, nRoomId:%d nGroupId:%d",nRoomId,nGroupId)
end
]]

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

return MsgHandle