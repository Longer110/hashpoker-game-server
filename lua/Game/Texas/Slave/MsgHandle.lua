local tBase = require("base") -- 基础功能接口
local Define =require("Define")
local tClientIdMgr =require("ClientIdMgr")
local tGameConfig =require("GameConfig") -- 
local tPubUser = require("PublicUserInfo") -- 用户信息 
local tTableMgr   = require("TableManage")
local tUserMgr   = require("UserManager")
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tname = require("typename") 
local tSetingConfig = require("SetingConfig") -- 
local cjson    = require("cjson")
local tPublicRedis =require("PublicRedis")
local PublicDefine =require("PublicDefine")

local MsgHandle = {}
MsgHandle.m_SendToCenterServer=nil

local tTableLogicInterface={}    --table逻辑所依赖的接口

--网络协议发送(发给前端)
local function SendToClient(sClientID,strProto,tSendData)
   local tPacket =SlaveAux:Encode(strProto,tSendData)
   tBase.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize())
end
--发送协议消息给玩家
local function _SendToUser(nUserId,strProto,tSendData)
   local tUser = tUserMgr.GetUserInfo(nUserId)
   if tUser==nil then
      assert(false)
      return 
   end
   if not tUser.isAndroid then
      local sClientID =tClientIdMgr.GetClientIdByUserId(nUserId)
      if sClientID then
         SendToClient(sClientID,strProto,tSendData)
      end
      return
   end
   local func =function()
      tUser:OnMsgHandle(strProto,tSendData)  
   end
   local isSuccee,ret =pcall(func)              --使用pcall调用，隔断AI对游戏主流程的影响
   if isSuccee==false then
      tBase.LogT("_UserMsgHandle Err happen=>",strProto," ",tSendData)
		tBase.LogT(ret)
		return
   end
end


local function _TryDelUser(nUserId)
   local tUser = tUserMgr.GetUser(nUserId)
   if tUser==nil then return end
   if not tUser:IsNoTable() then return end
   if tUser.isAndroid then
      tUserMgr.DelUser(nUserId)
      return
   end
   local sClientID =tClientIdMgr.GetClientIdByUserId(nUserId)
   if sClientID then
     tClientIdMgr.DestroyClientID(sClientID)
   end
   tUserMgr.DelUser(nUserId)
   tBase.Log("Del Real User_%d",nUserId)
   return true
end

--玩家离开桌子
local function _LeaveTable(nUserId,tTable)
   local tUser = tUserMgr.GetUserInfo(nUserId)
   assert(tUser ~=nil)
   tUser:LeaveTable(tTable:TableId())
  if  _TryDelUser(nUserId) then
      tPubUser.LeaveGame(nUserId,Define.nGameId)
  end
end


--返回玩家当前桌子
local function _GetUserTable(nUserId)
   local tUser = tUserMgr.GetUserInfo(nUserId)
   if tUser==nil then
      return nil
   end
   return tUser.tTable
end


function MsgHandle.InitSet(SendToCenterServerFunc)
   MsgHandle.m_SendToCenterServer =SendToCenterServerFunc
end
function MsgHandle.SendToCenterServer(nRoomId,strProto,tData)
   MsgHandle.m_SendToCenterServer(nRoomId,strProto,tData)
end

---------------------中心服协议 Start-----------------------------------
-----------------------------------------------------------------------

 --登陆回复	
function MsgHandle.OnDZCLogOnResp(sReturnKey,Data,nLen) 
   local tData =CenterAux:Parser(Data, nLen,"DZCLogOnResp")
   assert(tData~=nil)
   tBase.Log("OnDZCLogOnResp")
   Define.isLogonCenterSuccee=true
end

--中心服(回复或通知)
function MsgHandle.OnDZCRsp(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCRsp")
   assert(tData~=nil)
   local isSuccee,tJsonData =pcall(cjson.decode,tData.sJsonData)
   if not isSuccee then
      tBase.LogT(tJsonData)  --error msg
      return
   end
   local tTable =tTableMgr.GetBaiRenTable(tData.sTableId)
   if not tTable then
      tBase.Log("Can not find table:%s,Do DZCScenceReq",tData.sTableId)
      MsgHandle.SendToCenterServer(nil,"DZCScenceReq",{sTableId=tData.sTableId,nEcho=0})
      return
   end
   tTable:OnCenterMsgHandle(tData.sCmd,tJsonData,tData.nEcho)
end  

--桌子场景创建(回复或通知)
function MsgHandle.OnDZCScenceRsp(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCScenceRsp")
   assert(tData~=nil)
   local isSuccee,tJsonScenc =pcall(cjson.decode,tData.sJsonScenc)
   if not isSuccee then
      tBase.LogT(tJsonScenc)  --error msg
      return
   end
   local tConfig={
      nGroupId =tJsonScenc.nGroupId,
      nRoomId=tJsonScenc.nRoomId,
      nTableType=tJsonScenc.nTableType
   }
  local isNew,tTable=  tTableMgr.CreateTable(tTableLogicInterface,tData.sTableId,tConfig)
  tTable:ToDoReport()
  tTable:RecoverCenterScence(tJsonScenc)
   if isNew then
      tBase.Log("OnDZCScenceRsp ,CreateTable Succee,sTableId:%s",tData.sTableId)
   else
      tBase.Log("OnDZCScenceRsp ,CreateTable fail,sTableId:%s.may be repeat create",tData.sTableId)
   end
end




function MsgHandle.GetTableOfMatch(nGroupId,nRoomId)
   local tTable = tTableMgr.GetTableOfMatch(nGroupId,nRoomId)
   if tTable then
        return tTable
   end
   if not Define.isLogonCenterSuccee then
      tBase.Log("not Logon to Center,please wait")
      return 
   end
  --根据参数，返回对应的一个房间配置拷贝( {nGameId= ,nRoomId= ,nEnterFloorLimit= ,nAnte= ,nGroupId= ,nTax=} )
  local tRoomConfig =tGameConfig.GetRoomConfig_v2(Define.nGameId,nRoomId,nGroupId)
  local tRlt,sError =PublicDefine.CheckRoomConfig(tRoomConfig)
  if not tRlt then
     tBase.Log("_CreateMatchTable fail,%s, nRoomId:%d nGroupId:%d",sError,nRoomId,nGroupId)
     return
  end
 
  local tParameter ={
     nGroupId =nGroupId,
     nRoomId =nRoomId,
     nLiveUserID=0,
     isPassWordRoom=false,
     nTableType =Define.TableType.nMatch,
     sLiveID ="",
     sPlatformID="",
     sTableName =string.format("Room_%d",nRoomId),

     nSmallBlind = tRlt.nSmallBlind	,	--小盲
     nBigBlind =tRlt.nBigBlind,	      --大盲
     nCapacity = 6		,	            --人数
     nBuyMin =tRlt.nBuyMin,			   --最小买入
     nBuyMax =tRlt.nBuyMax,             --最大买入
     nFee = 0	,				            --手续费
     nTax = tRlt.nTax	,				   
     nElapseMax=2000000000,			   --多久没真人进入便关桌(秒) 不自动关闭牌桌
  }

  local sTableId =string.format("%d#%s",Define.nCenterServId,tPubUser.CreatePaiJuID())
  local isNew,tTable=  tTableMgr.CreateTable(tTableLogicInterface,sTableId,tParameter)
  
  local DZCTableCreateReq={}
  DZCTableCreateReq.sTableId=sTableId
  DZCTableCreateReq.sParameter=cjson.encode(tParameter)
  MsgHandle.SendToCenterServer(nil,"DZCTableCreateReq",DZCTableCreateReq)

  tBase.Log("_CreateMatchTable succee in Slave,sTableId:%s nRoomId:%d nGroupId:%d",tTable:TableId(),nRoomId,nGroupId)
  return tTable
end

---------------------中心服协议 End-----------------------------------
---------------------------------------------------------------------

local tUserIdToLatelyTableId ={}

--登陆请求(进入游戏，需要先登陆)
function MsgHandle.DeZhouLogOnReq(sClientID, tData, nLen)
   local tReqData =SlaveAux:Parser(tData, nLen,"DeZhouLogOnReq")
   assert(tReqData~=nil,"Parser Fail")
   local nUserId =tReqData.nUserId
   local sTableId =tReqData.sTableId
   local nRoomId =tReqData.nRoomId or -1
   local nIsChangeTable =tReqData.nIsChangeTable
   tBase.LogT("LogonReq:",{nUserId=nUserId,sTableId=sTableId,nRoomId=nRoomId,nIsChangeTable=nIsChangeTable})
   if sTableId and #sTableId>0 and nRoomId >=0 then
      nRoomId =-1
      tBase.Log("set nRoomId to -1")
   end

   --判断玩家id是否正确
   assert(tPubUser.ChecksClientIDByUserID(nUserId,sClientID),"LogOn nUserId Wrong")
   --关联玩家id与连接
   tClientIdMgr.BuildContact(sClientID,nUserId)   
   --获得玩家对象
   local tUser,isCreate =tUserMgr.AssureUserExist(nUserId)
   local tCurTable =tUser:GetTable()

   local nGroupId = tGameConfig.GetGroupId(tUser.nShopId)

   local nCurMatchRoomId =nil   --匹配房间id
   if tCurTable then
       nCurMatchRoomId =tCurTable:MatchRoomId()
   end
   local isChangeTable =(nIsChangeTable==1)
  
   --试玩房每日次数限制检查
   local function _FreeRoomCountCheck()    
      if nRoomId~=0 then return true end
      local nTryPlayCnt =tPublicRedis.GetTryPlayCntOfTexas(nUserId)
      local nMaxTryPlayCnt =tPublicRedis.GetMaxTryPlayCntOfTexas(nGroupId)
      return nTryPlayCnt <nMaxTryPlayCnt
   end

   local tTargetTable =nil
   if nRoomId>=0 and nRoomId<=4 then
      if nCurMatchRoomId and nCurMatchRoomId ~= nRoomId then
         tBase.Log("you are in other table:%s nCurMatchRoomId:%d",tCurTable:TableId(),nCurMatchRoomId)
         SendToClient(sClientID,"DeZhouLogOnRsp",{nRlt=16,strErr="you are in other table"})
         return
      end
      if nCurMatchRoomId == nRoomId and (not isChangeTable) then
         tTargetTable =tCurTable
      elseif not _FreeRoomCountCheck() then
         tBase.Log("TryPlayCnt useout")
         SendToClient(sClientID,"DeZhouLogOnRsp",{nRlt=15,strErr="TryPlayCnt useout"})
         return
      end
      if isChangeTable then
         local sLatelyTableId =tUserIdToLatelyTableId[nUserId]
         if tCurTable then sLatelyTableId =tCurTable:TableId() end
        -- tTargetTable =MsgHandle.GetNextTableOfMatch(nGroupId,nRoomId,sLatelyTableId)
         tTargetTable = tTableMgr.GetNextTableOfMatch(nGroupId,nRoomId,sLatelyTableId)
      end
      tTargetTable =tTargetTable or MsgHandle.GetTableOfMatch(nGroupId,nRoomId)
   else
      tTargetTable =tTableMgr.GetBaiRenTable(sTableId)
   end

   --[[
   --暂时不支持匹配与牌桌切换
  if (nRoomId>=0 and nRoomId<=4) or isChangeTable then
      tBase.Log("Not Support")
      SendToClient(sClientID,"DeZhouLogOnRsp",{nRlt=100,strErr="Not Support"})
      return
  end
   if tCurTable and tCurTable:TableId() ~=sTableId then
      tBase.Log("you are in other table:%s",tCurTable:TableId())
      SendToClient(sClientID,"DeZhouLogOnRsp",{nRlt=16,strErr="you are in other table"})
      return
   end
   local tTargetTable =tTableMgr.GetBaiRenTable(sTableId)
   ]]

  if not tTargetTable then
     tBase.Log("GetTable fail")
     SendToClient(sClientID,"DeZhouLogOnRsp",{nRlt=17,strErr="GetTable fail"})
     return
  end

  --因为多服问题，还需要判断玩家是否还在另一服的桌子当中
  --[[
  local _,_,_,_,sCurTableId= tPubUser.GetUserPlayingGame(nUserId)
  if sCurTableId and #sCurTableId>0 and sCurTableId ~=tTargetTable:TableId() and (not isChangeTable) then
     tBase.Log("you are in other table,sCurTableId:%s",sCurTableId)
     SendToClient(sClientID,"DeZhouLogOnRsp",{nRlt=16,strErr="you are in other table"})
     return
  end
  ]]

  --判断玩家是否在其它游戏中玩
  if not tPubUser.EnterGameV2(nUserId,Define.nGameId,tTargetTable.nRoomId,tTargetTable:TableId()) then
     tBase.Log("tPubUser.EnterGame fail")
     SendToClient(sClientID,"DeZhouLogOnRsp",{nRlt=16,strErr="you are in other game"})
     return
  end

  --加入桌子
  local isKeepStand =true  --tReqData.isKeepStand (是否不自动坐下)
  local isJoinTableSuccee =tTargetTable:OnUserEnter(tUser,isKeepStand)
  if not isJoinTableSuccee then
     tBase.Log("Join Table fail")
     tPubUser.LeaveGame(nUserId,Define.nGameId)
     SendToClient(sClientID,"DeZhouLogOnRsp",{nRlt=13,strErr="Join Table fail"})
     return
  end

  --设置玩家当前选择的桌子
  tUser:EnterTable(tTargetTable,-1)
  tUserIdToLatelyTableId[nUserId] =tTargetTable:TableId()

  --确保玩家离开先前进入的桌子
  if tCurTable and tCurTable:TableId() ~=tTargetTable:TableId() then
     --tCurTable:OnUserLeave(nUserId)	   --
     --tCurTable:_SetLeaveTableByUserId(nUserId)
     tCurTable:OnUserLeave(nUserId)
  end
  
  --获得桌子场景
  local tScence =tTargetTable:GetScenceByUserId(nUserId)
  
  --回复进入桌子成功
  SendToClient(sClientID,"DeZhouLogOnRsp",{nRlt=0,tScence=tScence,sTableId = tTargetTable:TableId()})  
  tBase.Log("Logon succee,nUserId_%d nGold:%f sTableId_%s ",tUser.nUserId,tUser.nGold ,tTargetTable:TableId() )

end


--操作请求
function MsgHandle.DeZhouOpReq(sClientID, Data, len) 					        
   MsgHandle._OnTableMsgHandle("DeZhouOpReq",sClientID,Data,len) 
end
--返回大厅请求
function MsgHandle.DeZhouBackToLobbyReq(sClientID, Data, len) 
   MsgHandle._OnTableMsgHandle("DeZhouBackToLobbyReq",sClientID,Data,len) 
 end
--预操作请求
function MsgHandle.DeZhouPreOpReq(sClientID, Data, len) 			      
   MsgHandle._OnTableMsgHandle("DeZhouPreOpReq",sClientID,Data,len) 
 end
--站起请求
function MsgHandle.DeZhouStanpUpReq(sClientID, Data, len)		      
   MsgHandle._OnTableMsgHandle("DeZhouStanpUpReq",sClientID,Data,len) 
 end
--坐下请求
function MsgHandle.DeZhouSitDownReq(sClientID, Data, len)			    
   MsgHandle._OnTableMsgHandle("DeZhouSitDownReq",sClientID,Data,len) 
 end
--筹码买入范围查看请求
function MsgHandle.DeZhouTakeInRangeReq(sClientID, Data, len)	
   MsgHandle._OnTableMsgHandle("DeZhouTakeInRangeReq",sClientID,Data,len) 
 end
--筹码买入请求
function MsgHandle.DeZhoTakeInReq(sClientID, Data, len)			        
   MsgHandle._OnTableMsgHandle("DeZhoTakeInReq",sClientID,Data,len) 
 end
--取消托管请求
function MsgHandle.DeZhouCancelAutoReq(sClientID, Data, len)   
   MsgHandle._OnTableMsgHandle("DeZhouCancelAutoReq",sClientID,Data,len) 
 end
--房间设置 请求
function MsgHandle.DeZhouCofingReq(sClientID, Data, len)           
   MsgHandle._OnTableMsgHandle("DeZhouCofingReq",sClientID,Data,len) 
 end
--主播踢人请求
function MsgHandle.DeZhouKickUserReq(sClientID, Data, len)       
   MsgHandle._OnTableMsgHandle("DeZhouKickUserReq",sClientID,Data,len) 
 end
--表情聊天请求
function MsgHandle.DeZhouChatReq(sClientID, Data, len)               
   MsgHandle._OnTableMsgHandle("DeZhouChatReq",sClientID,Data,len) 
 end
--暂停请求
function MsgHandle.DeZhouPauseReq(sClientID, Data, len)             
   MsgHandle._OnTableMsgHandle("DeZhouPauseReq",sClientID,Data,len) 
 end
--Gm命令请求
function MsgHandle.DeZhouGmReq(sClientID, Data, len)             
 --[[ if not tSetingConfig.isGm then
      tBase.Log("Gm Not Open")
      return
  end ]]
  
  MsgHandle._OnTableMsgHandle("DeZhouGmReq",sClientID,Data,len) 
 end

--桌子消息处理
function MsgHandle._OnTableMsgHandle(strReq,sClientID,Data,len) 
   local tData =SlaveAux:Parser(Data, len,strReq)
   if tData ==nil then
      tBase.Log(strReq.." _Parse Err")
      return
   end
   local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
   if not nUserId then
      tBase.Log(strReq.." Not Logon,sClientID_"..(sClientID or 'nil'))
      return
   end
   local table =_GetUserTable(nUserId)
   if table then
      table:OnReqHandle(nUserId,strReq,tData)
   else
      tBase.Log(strReq.." can not find table, nUserId_%d",nUserId)
   end
   return nUserId,table
end

local function _CloseUser(sClientID)
   if not sClientID then return end
   local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
   if not nUserId then
      return -1
   end
   tClientIdMgr.DestroyClientID(sClientID)
   local tUser =tUserMgr.GetUser(nUserId)
   if not tUser then
      return nUserId
   end
   local tTable =tUser:GetTable()
   if tTable then
      tTable:OnUserLeave(nUserId)
      return nUserId
   end
  -- tPubUser.LeaveGame(nUserId,Define.nGameId)
  -- tUserMgr.DelUser(nUserId)
   return nUserId
end

--连接关闭通知
function MsgHandle.OnClose(sClientID, Data, len)
   tBase.Log("OnClose sClientID:%s",sClientID)
   local nUserId = _CloseUser(sClientID)
   tBase.Log("nUserId_%d connection close. do clear over.",nUserId)
    return 
end

--连接切换通知
function MsgHandle.OnSwicthConn(sClientID, Data, len)
   local ReadData = tBase.GetRP().new(Data, len)
   local Sys = ReadData:GetModuleID()
   local Sub = ReadData:GetMsgID() 
   local Read = ProtoMgr.Gateway_pb.RUQ_SwicthConn()
   Read:ParseFromString(ReadData:GetString())
   local nUserId =Read.nUserID or -1
   tBase.Log("nUserId_%d swicth to:"..sClientID,nUserId)
   local oldClientId =tClientIdMgr.GetClientIdByUserId(nUserId)
   _CloseUser(oldClientId)
   tBase.Log("nUserId_%d OnSwicthConn. do clear over.",nUserId)
end


--后台踢人通知
function MsgHandle.OnKickUser(sClientID, Data, len)
   local s = tBase.GetRP().new(Data, len)
   local Read = ProtoMgr.PubProto_1_pb.REQ_Kick_User()
   Read:ParseFromString(s:GetString())
   local nUserId    = Read.nUserId or -1
   local nType      = Read.nType or -1    --1:立即踢出，解散 2:下局踢出
   tBase.Log("OnKickUser nUserId:%d nType:%d",nUserId,nType)

   local table =_GetUserTable(nUserId)
   if table then
      table:OnReqHandle(nUserId,"REQ_Kick_User",Read)
   else
      tBase.Log("OnKickUser, can not find table, nUserId_%d",nUserId)
   end
end


--db服充值结果返回
--tData.nRlt			--0:成功
--tData.nUserId
--tData.sSerialNumber --充值序列号
--tData.nAmount		 --充值成功的数量
--tData.sResultKey
--tData.nCurrentAmount  --玩家当前金币数量
function MsgHandle.OnDbRechargeRsp(sClientID, tData, nLen)
   local tData =DbServAux:Parser(tData, nLen,"DbRechargeRsp")
   if tData ==nil then
      tBase.Log("DbRechargeRsp _Parse Err")
      return
   end
   local nUserId =tData.nUserId
   tBase.Log("OnDbRechargeRsp nUserId:%d",nUserId)
   local table =_GetUserTable(nUserId)
   if table then
      table:OnReqHandle(nUserId,"DbRechargeRsp",tData)
   else
      tBase.Log("OnDbRechargeRsp, can not find table, nUserId_%d",nUserId)
   end
end

tTableLogicInterface._LeaveTable=_LeaveTable
tTableLogicInterface._SendToUser =_SendToUser
tTableLogicInterface.SendToCenterServer=MsgHandle.SendToCenterServer
tTableLogicInterface.CloseTable=tTableMgr.CloseTable
tTableLogicInterface.GetAndroids=GetAndroids


return MsgHandle