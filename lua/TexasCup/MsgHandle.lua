local tBase = require("base") -- 基础功能接口
local tClientIdMgr =require("ClientIdMgr")
local tGameConfig =require("GameConfig") -- 
local tPubUser = require("PublicUserInfo") -- 用户信息 
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tname = require("typename") 
local tSetingConfig = require("SetingConfig") -- 
local cjson    = require("cjson")
local tPublicRedis =require("PublicRedis")
local tSrvInfo = require("ServerInfo")
local tMatchManager=require("MatchManage")
local tSlaveManager =require("SlaveManage")
local Define =require("Define")
local BaseSink =require("BaseSink")

local MsgHandle = {}

local function UsersGroupId(nUserId)
   return tPubUser.Get_User_GroupId(nUserId)
end
local function SendToClient(sClientID,strProto,tSendData)
   local tPacket =ClientAux:Encode(strProto,tSendData)
   tBase.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize())
end

--发送协议消息给玩家
local function _SendToUser(nUserId,strProto,tSendData)
   local sClientID =tClientIdMgr.GetClientIdByUserId(nUserId)
   if sClientID then
      SendToClient(sClientID,strProto,tSendData)
      return true
   end
   return false
end

--保存打开了赛事列表的玩家
local tUsersOfEvtOpen={}

local tInterface ={}
tInterface._SendToUser =_SendToUser
tInterface.SendToUsersOfOpen=function(strProto,tSendData)   --广播消息给打开了列表的玩家
   for nUserId,_ in pairs(tUsersOfEvtOpen) do
      _SendToUser(nUserId,strProto,tSendData)
   end
end
tInterface.SendToUsersOfOpenByF=function(strProto,f)     --广播消息给打开了列表的玩家
   for nUserId,_ in pairs(tUsersOfEvtOpen) do
      _SendToUser(nUserId,strProto,f(nUserId))
   end
end
tInterface.CloseMatch =function(nEventId,sKeyRedisCfg,sFieldRedisCfg)
   tMatchManager.CloseMatch(nEventId)
   local redis =tBase.m_MyRedisData[2].redis
   local rt =redis:hdel(sKeyRedisCfg,sFieldRedisCfg)
   tBase.Log("hdel sKey:%s sField:%s rt:%s",sKeyRedisCfg,sFieldRedisCfg,tBase.tostring(rt)) 
end


--比赛服登陆 请求
function MsgHandle.OnTEvtLogonReq(sClientID, tData, nLen)	               
   local strReq ="TEvtLogonReq"
   local tReqData =ClientAux:Parser(tData, nLen,strReq)
   if not tReqData then
       tBase.Log("%s ,Parse error",strReq) 
       return
   end
   --检查UserId合法性
   local nUserID =math.floor(tReqData.nUserID)
   if not tPubUser.ChecksClientIDByUserID(nUserID,sClientID) then
       tBase.Log("Logon nUserID_%d Error",nUserID)
       SendToClient(sClientID,"TEvtLogonRsp",{nRlt=10})
       return
   end
   --登录成功
   tBase.Log("Logon succee, nUserID_%d",nUserID)
   tClientIdMgr.BuildContact(sClientID,nUserID)
   SendToClient(sClientID,"TEvtLogonRsp",{nRlt=0})
end

local function _Parser(sClientID,tData, nLen,strReq)
   local tReqData =ClientAux:Parser(tData, nLen,strReq)
   if not tReqData then
       tBase.Log("%s ,Parse error",strReq) 
       assert(false,"Parse error "..strReq)
       return
   end
   local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
   if not nUserID then
       tBase.Log("Err happen, Not Logon %s",strReq)
       assert(false,"Not Logon "..strReq)
       return
   end
   return tReqData,nUserID
end

--赛事列表 请求
function MsgHandle.OnTEvtEventsOpenReq(sClientID, tData, nLen)  
   local _,nUserID =_Parser(sClientID,tData, nLen,"TEvtEventsOpenReq")
   local nGroupId =UsersGroupId(nUserID)

   local arrMatch =tMatchManager.GetMatchsByGrpId(nGroupId)
   local arrEvents ={}
   for _,tMatch in ipairs(arrMatch) do
      local item =tMatch:GetProtoItemInfo(nUserID)
      if item then
         table.insert(arrEvents,item)
      end
   end
   tBase.Log("OnTEvtEventsOpenReq,nUserId:%d nGroupId:%d #arrEvents:%d",nUserID,nGroupId,#arrEvents)
   tUsersOfEvtOpen[nUserID] =nGroupId

   local tTEvtEventsOpenRsp ={}
   tTEvtEventsOpenRsp.nTimeStampNow =os.time()
   tTEvtEventsOpenRsp.arrEvents =arrEvents
   SendToClient(sClientID,"TEvtEventsOpenRsp",tTEvtEventsOpenRsp)

   local arrTem ={}
   for dex,item in ipairs(arrEvents) do
      table.insert(arrTem,item)
      if dex%10==0 or dex ==#arrEvents then
         local TEvtUsersRsp ={}
         TEvtUsersRsp.arrItems=arrTem
	      TEvtUsersRsp.nCntOfAll=#arr		--所有条目数量
         TEvtUsersRsp.nCntOfRsp=dex			--当前已发出的条目数量
         SendToClient(sClientID,"TEvtUsersRsp",TEvtUsersRsp)
         arrTem ={}
      end
   end


end

--赛事列表关闭 请求 (关闭后不再接收通知:TEvtUserCntNotify,TEvtRuleDNotify)
function MsgHandle.OnTEvtEventsCloseReq(sClientID, tData, nLen)     
   local _,nUserID =_Parser(sClientID,tData, nLen,"TEvtEventsCloseReq")
   tBase.Log("OnTEvtEventsCloseReq,nUserId:%d",nUserID)
   tUsersOfEvtOpen[nUserID]=nil
end

--比赛信息=>玩家列表 请求
function MsgHandle.OnTEvtUsersReq(sClientID, tData, nLen)
   local tReqData,nUserID =_Parser(sClientID,tData, nLen,"TEvtUsersReq")
   local nEventId =tReqData.nEventId

   local tMatch =tMatchManager.GetMatch(nEventId)
   if tMatch==nil then
      tBase.Log("OnTEvtUsersReq, can not find EventId:%d, nUserID:%d",nEventId,nUserID)
      return
   end
   local arr =tMatch:GetProtoEvtUsers()
   tBase.Log("OnTEvtUsersReq,nUserId:%d Len:%d",nUserID,#arr)
   --返回结果(太长时分段发送)
   if #arr==0 then
      local TEvtUsersRsp ={}
      TEvtUsersRsp.arrItems={}
      TEvtUsersRsp.nCntOfAll=0		--所有条目数量
      TEvtUsersRsp.nCntOfRsp=0		--当前已发出的条目数量
      SendToClient(sClientID,"TEvtUsersRsp",TEvtUsersRsp)
      return
   end
   local arrTem ={}
   for dex,item in ipairs(arr) do
      table.insert(arrTem,item)
      if dex%50==0 or dex ==#arr then
         local TEvtUsersRsp ={}
         TEvtUsersRsp.arrItems=arrTem
	      TEvtUsersRsp.nCntOfAll=#arr		--所有条目数量
         TEvtUsersRsp.nCntOfRsp=dex			--当前已发出的条目数量
         SendToClient(sClientID,"TEvtUsersRsp",TEvtUsersRsp)
         arrTem ={}
      end
   end
end

--比赛信息=>奖励列表 请求
function MsgHandle.OnTEvtAwardsReq(sClientID, tData, nLen)       
   local tReqData,nUserID =_Parser(sClientID,tData, nLen,"TEvtAwardsReq")
   local nEventId =tReqData.nEventId   

   local tMatch =tMatchManager.GetMatch(nEventId)
   if tMatch==nil then
      tBase.Log("OnTEvtAwardsReq, can not find EventId:%d, nUserID:%d",nEventId,nUserID)
      return
   end
   local arr =tMatch:GetProtoAwards()
   tBase.Log("OnTEvtAwardsReq,nUserId:%d Len:%d",nUserID,#arr)
   --返回结果
   SendToClient(sClientID,"TEvtAwardsRsp",{arrItems=arr})
end

--报名 请求
function MsgHandle.OnTEvtSignUpReq(sClientID, tData, nLen)       
   local tReqData,nUserID =_Parser(sClientID,tData, nLen,"TEvtSignUpReq")
   local nEventId =tReqData.nEventId   

   local tMatch =tMatchManager.GetMatch(nEventId)
   if tMatch==nil then
      tBase.Log("OnTEvtSignUpReq, can not find EventId:%d, nUserID:%d",nEventId,nUserID)
      return
   end   

   local nRlt =tMatch:SignUp(nUserID)
   tBase.Log("OnTEvtSignUpReq,nUserId:%d nRlt:%d",nUserID,nRlt)

   local TEvtSignUpRsp ={}
   TEvtSignUpRsp.nEventId=nEventId
   TEvtSignUpRsp.nRlt=nRlt			    --0:报名成功 1: 费用不足 2:报名人数达上限 3:超出报名时间 其它:未定义错误
   TEvtSignUpRsp.nOp=tMatch:_GetOpCan(nUserID)
   SendToClient(sClientID,"TEvtSignUpRsp",TEvtSignUpRsp)
end

--取消报名 请求
function MsgHandle.OnTEvtSignUpCancelReq(sClientID, tData, nLen)    
   local tReqData,nUserID =_Parser(sClientID,tData, nLen,"TEvtSignUpCancelReq")
   local nEventId =tReqData.nEventId   

   local tMatch =tMatchManager.GetMatch(nEventId)
   if tMatch==nil then
      tBase.Log("OnTEvtSignUpCancelReq, can not find EventId:%d, nUserID:%d",nEventId,nUserID)
      return
   end   

   local nRlt =tMatch:SignUpCancel(nUserID)
   tBase.Log("OnTEvtSignUpCancelReq,nUserId:%d nRlt:%d",nUserID,nRlt)

   local TEvtSignUpCancelRsp={}
   TEvtSignUpCancelRsp.nEventId=nEventId		--赛事ID
   TEvtSignUpCancelRsp.nRlt=nRlt			      --0:取消成功 其它:未定义错误
   TEvtSignUpCancelRsp.nOp=tMatch:_GetOpCan(nUserID)
   SendToClient(sClientID,"TEvtSignUpCancelRsp",TEvtSignUpCancelRsp)
end

--延迟报名 请求
function MsgHandle.OnTEvtSignUpDReq(sClientID, tData, nLen)   
   local tReqData,nUserID =_Parser(sClientID,tData, nLen,"TEvtSignUpDReq")
   local nEventId =tReqData.nEventId   

   local tMatch =tMatchManager.GetMatch(nEventId)
   if tMatch==nil then
      tBase.Log("OnTEvtSignUpDReq, can not find EventId:%d, nUserID:%d",nEventId,nUserID)
      return
   end   
   
   local nRlt,sTableId =tMatch:SignUpDelay(nUserID)
   tBase.Log("OnTEvtSignUpDReq,nUserId:%d nRlt:%d sTableId:%s",nUserID,nRlt,tostring(sTableId))

   local TEvtSignUpDRsp={}
   TEvtSignUpDRsp.nEventId=nEventId		--赛事ID
   TEvtSignUpDRsp.nRlt=nRlt			   --0:报名成功 1: 费用不足 2:报名人数达上限 3:超出报名时间 其它:未定义错误
   TEvtSignUpDRsp.sTableId=sTableId		--比赛桌子id,根据该id前端自行进入牌桌 (成功时有效)
   TEvtSignUpDRsp.nOp=tMatch:_GetOpCan(nUserID)
   TEvtSignUpDRsp.nGameId =tMatch:GameId()
   
   SendToClient(sClientID,"TEvtSignUpDRsp",TEvtSignUpDRsp)
end

 --观战 请求
function MsgHandle.OnTEvtWatchReq(sClientID, tData, nLen)
   local tReqData,nUserID =_Parser(sClientID,tData, nLen,"TEvtWatchReq")
   local nEventId =tReqData.nEventId   

   local tMatch =tMatchManager.GetMatch(nEventId)
   if tMatch==nil then
      tBase.Log("OnTEvtWatchReq, can not find EventId:%d, nUserID:%d",nEventId,nUserID)
      return
   end   
   local nRlt,sTableId =tMatch:Watch(nUserID)
   tBase.Log("OnTEvtWatchReq,nUserId:%d nRlt:%d sTableId:%s",nUserID,nRlt,tostring(sTableId))

   local TEvtWatchRsp ={}
   TEvtWatchRsp.nEventId=nEventId		            --赛事ID
   TEvtWatchRsp.nRlt=nRlt			                   --0:成功  其它:未定义错误
   TEvtWatchRsp.sTableId=sTableId		            --比赛桌子id,根据该id前端自行进入牌桌(成功时有效)
   TEvtWatchRsp.nOp=tMatch:_GetOpCan(nUserID)
   TEvtWatchRsp.nGameId =tMatch:GameId()
   SendToClient(sClientID,"TEvtWatchRsp",TEvtWatchRsp)
end

--进入比赛 请求 (调用后分两情况:1进入倒计时等待,倒计时完后,前端重新调用该请求 2直接进入比赛桌子)
function MsgHandle.OnTEvtEnterReq(sClientID, tData, nLen)
   local tReqData,nUserID =_Parser(sClientID,tData, nLen,"TEvtEnterReq")
   local nEventId =tReqData.nEventId   

   local tMatch =tMatchManager.GetMatch(nEventId)
   if tMatch==nil then
      tBase.Log("OnTEvtEnterReq, can not find EventId:%d, nUserID:%d",nEventId,nUserID)
      return
   end

   --这函数可能会被延时调
   local function f(nRlt,sTableId,nRemainT)
      local TEvtEnterRsp={}
      TEvtEnterRsp.nEventId=nEventId		--赛事ID
      TEvtEnterRsp.nRlt=nRlt			      --1:比赛未开始  2:比赛已开始 其它:错误
      TEvtEnterRsp.nRemainT=nRemainT	   --距离比赛开始剩余时间 秒 				(nRlt为1时有效)
      TEvtEnterRsp.sTableId=sTableId		--比赛桌子id,根据该id前端自行进入牌桌	(nRlt为2时有效)
      TEvtEnterRsp.nOp=tMatch:_GetOpCan(nUserID)
      TEvtEnterRsp.nGameId =tMatch:GameId()
      SendToClient(sClientID,"TEvtEnterRsp",TEvtEnterRsp)
      tBase.Log("OnTEvtEnterReq,nUserId:%d nRlt:%d sTableId:%s nRemainT:%s",nUserID,nRlt,tostring(sTableId),tostring(nRemainT))
   end

   tBase.Log("OnTEvtEnterReq,nUserId:%d nEventId:%d",nUserID,nEventId)
   tMatch:TEvtEnter(nUserID,f)
end


--入口提示查询 请求
--nRlt 0:正在比赛当中 1:可以进入比赛 -1:没提示
function MsgHandle.OnTEvtCheckReq(sClientID, tData, nLen)
   local tReqData,nUserID =_Parser(sClientID,tData, nLen,"TEvtCheckReq")
   local nGroupId =UsersGroupId(nUserID)
   local arrMatch =tMatchManager.GetMatchsByGrpId(nGroupId)
   for _,tMatch in ipairs(arrMatch) do
      local nRlt,nEventId,sName=tMatch:EntryCheck(nUserID)
      if nRlt and nRlt~= -1 then
         tBase.Log("OnTEvtCheckReq,nUserId:%d,EventId:%d sName:%s nRlt:%d",nUserID,nEventId,sName,nRlt)
         SendToClient(sClientID,"TEvtCheckRsp",{nRlt=nRlt,nEventId=nEventId,sName=sName})
         return
      end
   end

   tBase.Log("OnTEvtCheckReq,nUserId:%d Not in match,nGroupId:%d",nUserID,nGroupId)
   SendToClient(sClientID,"TEvtCheckRsp",{nRlt=-1})
end


--退出比赛(弹窗里的;不再进行离线托管) 请求
function MsgHandle.OnTEvtQuitReq(sClientID, tData, nLen)     
   local tReqData,nUserID =_Parser(sClientID,tData, nLen,"TEvtQuitReq")
   local nEventId =tReqData.nEventId    
   tBase.Log("OnTEvtQuitReq,nUserId:%d nEventId:%d",nUserID,nEventId)
end


function MsgHandle.OnClose(sClientID, Data, len)
   local ReadData = tBase.GetRP().new(Data, len)
   local Sys = ReadData:GetModuleID()
   local Sub = ReadData:GetMsgID() 

   local Read = ProtoMgr.Gateway_pb.RUQ_User_Line()
   Read:ParseFromString(ReadData:GetString())
   local nUserId =  Read.nUserID
   tBase.Log("OnClose nUserId_%d sClientId_%s",nUserId,sClientID)
   tClientIdMgr.DestroyClientID(sClientID)
end

function MsgHandle.OnSwicthConn(sClientID, Data, len) 
   local ReadData = tBase.GetRP().new(Data, len)
   local Sys = ReadData:GetModuleID()
   local Sub = ReadData:GetMsgID() 
   local Read = ProtoMgr.Gateway_pb.RUQ_SwicthConn()
   Read:ParseFromString(ReadData:GetString())
   tBase.Log("OnSwicthConn nUserId_%d swicth to:"..sClientID,(Read.nUserID or -1)) 
   if not tClientIdMgr.GetClientIdByUserId(Read.nUserID or -1) then
       tBase.Log("nUserId_%d areadly leave",(Read.nUserID or -1))
       return
   end
   if Read.nUserID then
      tClientIdMgr.BuildContact(sClientID,Read.nUserID)
   end
end


--游戏中心服登陆请求+
function MsgHandle.OnDZCLogOnReq(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCLogOnReq")
   assert(tData~=nil)
   tSlaveManager.AddSlaveServ(tData.nServerId,sReturnKey)
   --回复成功
   tSlaveManager.Send(sReturnKey,"DZCLogOnResp",{nRlt=0})
   tBase.Log("OnDZCLogOnReq nServerId_%d",tData.nServerId)
end

--游戏中心服通知或回复
function MsgHandle.OnDZCMtRsp(sReturnKey,Data,nLen)
   local tData =CenterAux:Parser(Data, nLen,"DZCMtRsp")
   assert(tData~=nil)

   local sCmd=tData.sCmd
   local sJsonData =tData.sJsonData
   local nEventId=tData.nEventId
   local nEcho =tData.nEcho

   local isSuccee,tRlt =pcall(cjson.decode,sJsonData)
	if not isSuccee then
		tBase.Log("OnDZCMtRsp Err Json decode Fail,%s",sJsonData)
		return
	end

   local tMatch =tMatchManager.GetMatch(nEventId)
   if tMatch==nil then
      tBase.Log("OnDZCMtRsp Err, can not find EventId:%d",nEventId)
      return
   end

   tBase.Log("OnDZCMtRsp,EventId:%d,sCmd:%s",nEventId,sCmd)
   tMatch:MsgHandle(sReturnKey,sCmd,tRlt)
end


function MsgHandle.CreateTestCfg()
   local t={}
   t.sName="测试一"	                  --比赛名称(base64编码)
   t.sBackground=""							--背景图url
   t.nTimeBefore=60							--入场时间 秒
   t.nTimeAfter=60							--延迟报名时间 秒
   t.nUserCntMax=100							--最高参赛人数
   t.nTakeIn=20								--初始筹码
   t.nCntBegin=2								--最低参赛人数
   t.nBlindUpGap=60							--涨盲时间 秒
   t.nUserCntOfTable=4						--牌桌人数
   t.nSignUpFee=100							--报名费 金币数量
   t.nServiceFee=100							--服务费 金币数量
   t.nTicket =1								--门票
   t.nRCnt=5									--可重购次数
   t.nRLv =10									--可重购盲注级别
   t.nRChip=100								--重购筹码数量
   t.nACnt=5									--可增购次数
   t.nALv =11									--可增购盲注级别
   t.nAChip=100								--增购筹码数量
   t.nGameId=125								--游戏id (125:普通德州 126:奥哈马 175:短牌)
   --盲注列表
   t.arrLvItem={								
      {nSmallB=1,nBigB=2,nPreAnte=0},			--小盲, 大盲, 前注
      {nSmallB=2,nBigB=4,nPreAnte=2},
      {nSmallB=4,nBigB=8,nPreAnte=4},
      {nSmallB=8,nBigB=16,nPreAnte=8},
      {nSmallB=16,nBigB=32,nPreAnte=16},
      {nSmallB=32,nBigB=64,nPreAnte=32},
      {nSmallB=64,nBigB=128,nPreAnte=64},
   }

   --比赛奖励二选一;优先用固定方式，nil时则用百分比
   --比赛奖励(固定金额)
   t.arrAward={
      {nRank=1,nCoin=1000},				--名次,奖励金币
      {nRank=2,nCoin=500},
   }
   --比赛奖励(百分比方式)
   t.arrAwardPercent={
      {nRank=1,nPercent=30},				--名次,百分比(30即30%)
      {nRank=2,nPercent=20},
   }
   local nZone =8
   local curDay = os.date("!*t", os.time()+3600*nZone+ 240) --day hour min sec
   --赛事循环方式
   t.tTRule ={}
   t.tTRule.nLoopType =5	         --比赛类型 1每月 2每周 3每日 4单次 5测试用按次循环
   t.tTRule.nYear=2024		         --年(2000~2099)
   t.tTRule.nMonth=12		         --月(1~12)
   t.tTRule.nMonthday=1	            --日(1~28)
   t.tTRule.nHour=curDay.hour		   --时(0~23)
   t.tTRule.nMin=curDay.min			--分(0~59)
   t.tTRule.nWeekday=1		         -- 一周里的第几天(1~7, 1=星期日,7=星期六)
   t.tTRule.nZone =nZone	         --参数所用时区(8为北京时区)
   t.tTRule.nLoopSec=120            --按次循环周期 秒

   local redis =tBase.m_MyRedisData[2].redis
   local nGroupId =4
   local sKey =string.format("TexasCup_%d",nGroupId)
   redis:del("TexasCup")
   redis:del(sKey)

   --测试一 创建
   local sCfg =cjson.encode(t)
   redis:hmset(sKey,1,sCfg)

   --测试二奥哈马 创建
   t.sName="测试二奥哈马"
   t.tTRule.nLoopType =5
   t.nGameId=126
   sCfg =cjson.encode(t)
   redis:hmset(sKey,2,sCfg)

   --测试三短牌 创建
   t.sName="测试三短牌"
   t.tTRule.nLoopType =5
   t.nGameId=175
   t.arrLvItem={								
      {nSmallB=0,nBigB=0,nPreAnte=2},			--小盲, 大盲, 前注
      {nSmallB=0,nBigB=0,nPreAnte=4},
      {nSmallB=0,nBigB=0,nPreAnte=8},
      {nSmallB=0,nBigB=0,nPreAnte=16},
      {nSmallB=0,nBigB=0,nPreAnte=32},
      {nSmallB=0,nBigB=0,nPreAnte=64},
   }
   sCfg =cjson.encode(t)
   redis:hmset(sKey,3,sCfg)

end

--TexasCup_*
function _GetKeys(sPattern)
   local tRt ={}  --辅助去重复
   local redis =tBase.m_MyRedisData[2].redis
   local cursor,arrKeys =0,nil
   for i=1,10000 do
      cursor,arrKeys = redis:scan(cursor, 'MATCH', sPattern,"COUNT",1000)
      --tBase.LogT({arrKeys=arrKeys,cursor=cursor})
      for _,v in ipairs(arrKeys) do
         tRt[v]=true
      end
      if tonumber(cursor)==0 then
         break
      end
   end
   local arr={}
   for k,_ in pairs(tRt) do
      table.insert(arr,k)
   end
   return arr,redis
end

function MsgHandle.Check()
   local arrKeys,redis =_GetKeys("TexasCup_*")
   tBase.LogT("Check ",arrKeys)
   local arrCreateNeed ={}

   --获得正在运行的所有比赛
   local tAll={}
   local arrMtt =tMatchManager.GetMatchsByGrpId()
   for _,tMtt in ipairs(arrMtt) do
      tAll[tMtt:UKey()] =tMtt
   end

   --确定需要创建的比赛
   for _,sKey in ipairs(arrKeys) do
      local sGroupId =string.match(sKey,"TexasCup_(.*)")
      local nGroupId =tonumber(sGroupId)
      if nGroupId then
         local arr =redis:hkeys(sKey) or {}
         for _,sField in ipairs(arr) do
            local sUkey =string.format("%d_%s",nGroupId,sField)
            if not tAll[sUkey] then
               table.insert(arrCreateNeed,{sField=sField,nGroupId=nGroupId,sKey=sKey,sUkey=sUkey})
            end
            tAll[sUkey]=nil
         end
      else
         tBase.Log("MTT Error,sKey:%s",sKey)
      end
   end

   --删除比赛
   for _,tMtt in pairs(tAll) do
      tMtt:OnClose()
   end

   --创建
   for _,v in ipairs(arrCreateNeed) do
      local sJsonCfg =redis:hget(v.sKey,v.sField)
      local isSuccee,tJsonData =pcall(cjson.decode,sJsonCfg)
      if not isSuccee then
         tBase.LogT("MTT Error ",tJsonData," ",v.sKey," ",v.sField)    --error msg
      else
         MsgHandle._CreateMtt(v.sUkey,v.nGroupId,tJsonData,v.sKey,v.sField)
      end
   end
end


local function _CheckCfg(t)
   assert(type(t.sName)=="string","sName")                                    --比赛名称
   if not type(t.sBackground or "")=="string" then					               --背景图url
      t.sBackground=""
   end
   assert(type(t.nTimeBefore)=="number" and t.nTimeBefore>=0,"nTimeBefore")					--入场时间 秒
   assert(type(t.nTimeAfter)=="number" and t.nTimeAfter>=0,"nTimeAfter")						--延迟报名时间 秒
   assert(type(t.nUserCntMax)=="number" and t.nUserCntMax>0,"nUserCntMax")					--最高参赛人数
   assert(type(t.nTakeIn)=="number" and t.nTakeIn>0,"nTakeIn")								--初始筹码
   assert(type(t.nCntBegin)=="number" and t.nCntBegin>0 ,"nCntBegin")						   --最低参赛人数
   assert(type(t.nBlindUpGap)=="number" and t.nBlindUpGap>=0,"nBlindUpGap")				   --涨盲时间 秒
   assert(type(t.nUserCntOfTable)=="number" and t.nUserCntOfTable>=2,"nUserCntOfTable")			--牌桌人数

   assert(type(t.nSignUpFee)=="number" and t.nSignUpFee>=0,"nSignUpFee")						--报名费 金币数量
   assert(type(t.nServiceFee)=="number" and t.nServiceFee>=0,"nServiceFee")					--服务费 金币数量
   assert(type(t.nTicket)=="number" and t.nTicket>=0,"nTicket")							   --门票

   assert(type(t.nRCnt)=="number" and t.nRCnt>=0,"nRCnt")								--可重购次数
   assert(type(t.nRLv)=="number" and t.nRLv>=0,"nRLv")								   --可重购盲注级别
   assert(type(t.nRChip)=="number" and t.nRChip>=0,"nRChip")							   --重购筹码数量

   assert(type(t.nACnt)=="number" and t.nACnt>=0,"nACnt")								--可增购次数
   assert(type(t.nALv)=="number" and t.nALv>=0,"nALv")								   --可增购盲注级别
   assert(type(t.nAChip)=="number" and t.nAChip>=0 ,"nAChip")								--增购筹码数量
   assert(type(t.nGameId)=="number" ,"nGameId")							--游戏id (125:普通德州 126:奥哈马 175:短牌)
   assert(t.nGameId==125 or t.nGameId==126 or t.nGameId==175,"nGameId")	

   --盲注列表
   assert(type(t.arrLvItem)=="table","arrLvItem")
   assert(#t.arrLvItem>0,"arrLvItem")
   for _,v in ipairs(t.arrLvItem) do
      assert(type(v.nSmallB)=="number" and v.nSmallB>=0,"nSmallB" )
      assert(type(v.nBigB)=="number" and v.nBigB>=0,"nBigB")
      assert(type(v.nPreAnte)=="number" and v.nPreAnte>=0,"nPreAnte")
   end

   --比赛奖励(固定金额)
   assert(type(t.arrAward or {})=="table","arrAward")
   for _,v in ipairs(t.arrAward) do
      assert(type(v.nRank)=="number" and v.nRank>=0,"nRank")
      assert(type(v.nCoin)=="number" and v.nCoin>=0,"nCoin")
   end

   --比赛奖励(百分比方式)
   assert(type(t.arrAwardPercent or {})=="table","arrAwardPercent")
   for _,v in ipairs(t.arrAwardPercent) do
      assert(type(v.nRank)=="number" and v.nRank>=0,"nRank")
      assert(type(v.nPercent)=="number" and v.nPercent>=0,"nPercent")
   end

    --赛事循环方式
    assert(type(t.tTRule)=="table","tTRule")
    assert(type(t.tTRule.nLoopType)=="number","tTRule.nLoopType")	   --比赛类型 1每月 2每周 3每日 4单次 5:测试用按次循环
    if t.tTRule.nLoopType ==1 then
      assert(type(t.tTRule.nMonthday)=="number" and t.tTRule.nMonthday>=1 and t.tTRule.nMonthday<=28,"tTRule.nMonthday")	   --日(1~28)
      assert(type(t.tTRule.nHour)=="number" and t.tTRule.nHour>=0 and t.tTRule.nHour<=23,"tTRule.nHour")		      --时(0~23)
      assert(type(t.tTRule.nMin)=="number" and t.tTRule.nMin>=0 and t.tTRule.nMin<=59,"tTRule.nMin")		         --分(0~59)
    end
    if t.tTRule.nLoopType ==2 then
      assert(type(t.tTRule.nHour)=="number" and t.tTRule.nHour>=0 and t.tTRule.nHour<=23,"tTRule.nHour")		      --时(0~23)
      assert(type(t.tTRule.nMin)=="number" and t.tTRule.nMin>=0 and t.tTRule.nMin<=59,"tTRule.nMin")		         --分(0~59)
      assert(type(t.tTRule.nWeekday)=="number" and t.tTRule.nWeekday>=1 and t.tTRule.nWeekday<=7,"tTRule.nWeekday")		-- 一周里的第几天(1~7, 1=星期日,7=星期六)
    end
    if t.tTRule.nLoopType ==3 then
      assert(type(t.tTRule.nHour)=="number" and t.tTRule.nHour>=0 and t.tTRule.nHour<=23,"tTRule.nHour")		      --时(0~23)
      assert(type(t.tTRule.nMin)=="number" and t.tTRule.nMin>=0 and t.tTRule.nMin<=59,"tTRule.nMin")		         --分(0~59)
    end
    if t.tTRule.nLoopType ==4 then
      assert(type(t.tTRule.nYear)=="number" and t.tTRule.nYear>=2000 and t.tTRule.nYear<=2099,"tTRule.nYear")		      --年(2000~2099)
      assert(type(t.tTRule.nMonth)=="number" and t.tTRule.nMonth>=1 and t.tTRule.nMonth<=12,"tTRule.nMonth")	         --月(1~12)
      assert(type(t.tTRule.nMonthday)=="number" and t.tTRule.nMonthday>=1 and t.tTRule.nMonthday<=28,"tTRule.nMonthday")	   --日(1~28)
      assert(type(t.tTRule.nHour)=="number" and t.tTRule.nHour>=0 and t.tTRule.nHour<=23,"tTRule.nHour")		      --时(0~23)
      assert(type(t.tTRule.nMin)=="number" and t.tTRule.nMin>=0 and t.tTRule.nMin<=59,"tTRule.nMin")		         --分(0~59)
    end
    if t.tTRule.nLoopType ==5 then
      assert(type(t.tTRule.nYear)=="number" and t.tTRule.nYear>=2000 and t.tTRule.nYear<=2099,"tTRule.nYear")		         --年(2000~2099)
      assert(type(t.tTRule.nMonth)=="number" and t.tTRule.nMonth>=1 and t.tTRule.nMonth<=12,"tTRule.nMonth")	            --月(1~12)
      assert(type(t.tTRule.nMonthday)=="number" and t.tTRule.nMonthday>=1 and t.tTRule.nMonthday<=28,"tTRule.nMonthday")	--日(1~28)
      assert(type(t.tTRule.nHour)=="number" and t.tTRule.nHour>=0 and t.tTRule.nHour<=23,"tTRule.nHour")		               --时(0~23)
      assert(type(t.tTRule.nMin)=="number" and t.tTRule.nMin>=0 and t.tTRule.nMin<=59,"tTRule.nMin")		                  --分(0~59)
      assert(type(t.tTRule.nLoopSec)=="number" and t.tTRule.nLoopSec>=0,"nLoopSec")                                        --按次循环周期 秒
    end
    assert(type(t.tTRule.nZone)=="number","tTRule.nZone")		      --参数所用时区(8为北京时区)
   return true
end

local nLatelyEventId =0
function _CreateEventId()
   nLatelyEventId =nLatelyEventId +1
   return nLatelyEventId
end


function MsgHandle._CreateMtt(sUkey,nGroupId,tJsonData ,sKeyRedisCfg,sFieldRedisCfg)
   local isSucce,s =pcall(_CheckCfg,tJsonData)
   if not isSucce then
      tBase.LogT("_CreateMtt Fail ",s," ",tJsonData)
      return false
   end

   local t={}
	t.sName=tJsonData.sName or ""			                  --赛事名称
	t.sBackground=tJsonData.sBackground or ""					--背景图url (空字符串时,前端默认一个图)
	t.nTimeBefore=tJsonData.nTimeBefore							--开赛前时间 秒(期间内，已报名者可"进入比赛")
	t.nTimeAfter=tJsonData.nTimeAfter							--开赛后时间 秒(期间内，未报名者可"延迟报名",超过后所有人仅能"观战")
	t.nUserCntMax=tJsonData.nUserCntMax							--最大报名人数
	t.nTakeIn=tJsonData.nTakeIn								   --初始记分牌
	t.nCntBegin=tJsonData.nCntBegin								--最小开赛人数
	t.nBlindUpGap=tJsonData.nBlindUpGap							--涨盲时间 秒
	t.nUserCntOfTable=tJsonData.nUserCntOfTable				--单桌人数
   t.nGameId =tJsonData.nGameId                          --游戏id

   local nTicket =tJsonData.nTicket                      --门票
   local nSignUpFee =tJsonData.nSignUpFee                --报名费
   local nServiceFee =tJsonData.nServiceFee              --服务费
   local nFeeType =3                                     --费用类型,1免费 2仅门票 3金币或门票
   if (nTicket +nSignUpFee +nServiceFee)==0 then
      nFeeType =1
   end

	--报名费s
	t.tFeeSignUp={}  				
	t.tFeeSignUp.nFeeType=nFeeType		            --费用类型,1免费 2仅门票 3金币或门票
	t.tFeeSignUp.nTicketNeed=nTicket	               --所需门票数量					(nFeeType 2或3时有效)
	t.tFeeSignUp.nFeeA=nSignUpFee	                  --参赛费					   (nFeeType 3时有效)
	t.tFeeSignUp.nFeeB=nServiceFee		            --报名服务费 或重购费 或增购费 	(nFeeType 3时有效)

	--重购费s
	t.tFeeR={}	  	
	t.tFeeR.nFeeType=nFeeType		         --费用类型,1免费 2仅门票 3金币或门票
	t.tFeeR.nTicketNeed=nTicket	         --所需门票数量	(nFeeType 2或3时有效)
	t.tFeeR.nFeeA=0		                  --参赛费	(nFeeType 3时有效)
	t.tFeeR.nFeeB=nSignUpFee		         --报名服务费 或重购费 或增购费 	(nFeeType 3时有效)

	--增购费s
	t.tFeeA={}	  			
	t.tFeeA.nFeeType=nFeeType		          --费用类型,1免费 2仅门票 3金币或门票
	t.tFeeA.nTicketNeed=nTicket	          --所需门票数量					(nFeeType 2或3时有效)
	t.tFeeA.nFeeA=0		                   --参赛费					   (nFeeType 3时有效)
	t.tFeeA.nFeeB=nSignUpFee		         --报名服务费 或重购费 或增购费 	(nFeeType 3时有效)

	--重购规则s
	t.tEvtTakInR={}
	t.tEvtTakInR.nLevel=tJsonData.nRLv 	         --盲注级别
	t.tEvtTakInR.nCnt=tJsonData.nRCnt	         --可购次数
	t.tEvtTakInR.nChip=tJsonData.nRChip	         --增加的筹码数量

	--增购规则s
	t.tEvtTakInA={}		
	t.tEvtTakInA.nLevel=tJsonData.nALv 	         --盲注级别
	t.tEvtTakInA.nCnt=tJsonData.nACnt	         --可购次数
	t.tEvtTakInA.nChip=tJsonData.nAChip	         --增加的筹码数量
	
	--升盲列表(必须是排序好)s
	t.arrLvItem={}
   for _,v in ipairs(tJsonData.arrLvItem) do
      local item ={nSmallB=v.nSmallB,nBigB=v.nBigB,nPreAnte=v.nPreAnte}
      table.insert(t.arrLvItem,item)
   end
   local function _Sort(A,B)
      if A.nSmallB and A.nSmallB>0 then return A.nSmallB<B.nSmallB end
      return A.nPreAnte<B.nPreAnte
   end
   table.sort(t.arrLvItem,_Sort)             --由小到大排序
   if t.nGameId ==Define.nGameId_Sc then     --短牌大小盲强制为0
      for _,v in ipairs(t.arrLvItem) do
         v.nBigB =0
         v.nSmallB=0
      end
   end

   --赛事循环方式
   local tTRule =tJsonData.tTRule
	t.tTRule ={}
	t.tTRule.nLoopType =tTRule.nLoopType	--1按月 2按周 3按天 4按次 5测试用按次循环
	t.tTRule.nZone =tTRule.nZone	         --参数所用时区(8为北京时区)
	t.tTRule.nYear=tTRule.nYear		      --年 (按次时有效)
	t.tTRule.nMonth=tTRule.nMonth		      --月 (按次时有效;1~12)
	t.tTRule.nMonthday=tTRule.nMonthday		--日 (1~28)
	t.tTRule.nHour=tTRule.nHour			   --时(0~23)
	t.tTRule.nMin=tTRule.nMin			      --分(0~59)
	t.tTRule.nSec=tTRule.nSec			      --秒(0~59)
	t.tTRule.nWeekday=tTRule.nWeekday		--(1~7) 一周里的第几天 （按周时有效;1=星期日,7=星期六,）
	t.tTRule.nLoopSec=tTRule.nLoopSec      --按次循环周期 秒

   --奖励列表s
	t.arrAward={}
   t.arrAwardPercent={}
   for _,v in ipairs(tJsonData.arrAward or {}) do
      local item ={nRank=v.nRank,nCoin=v.nCoin,nTicket=0}
      table.insert(t.arrAward,item)
   end
   for _,v in ipairs(tJsonData.arrAwardPercent or {}) do
      local item ={nRank=v.nRank,nPercent=v.nPercent,nTicket=0}
      table.insert(t.arrAwardPercent,item)
   end
   if #t.arrAward>0 then
      t.nAwardType =1									--奖励方式 1:固定 2:奖池百分比
   elseif #t.arrAwardPercent>0 then
      t.nAwardType =2
   else
      t.nAwardType =1
   end
   table.sort(t.arrAward,function(A,B) return A.nRank<B.nRank end)  --由小到大排序
   table.sort(t.arrAwardPercent,function(A,B) return A.nRank<B.nRank end)  --由小到大排序

   --分组id
   t.nGroupId=nGroupId
   t.sUkey =sUkey 
   t.sKeyRedisCfg =sKeyRedisCfg
   t.sFieldRedisCfg=sFieldRedisCfg

   local nEventId =_CreateEventId()
   --测试 创建
   tBase.Log("_CreateMtt,nEventId:%d nGroupId:%d sUkey:%s tCfg:%s",nEventId,nGroupId,sUkey,cjson.encode(t))
   local isNew,tMatch =tMatchManager.CreateMatch(tInterface,nEventId,t)
   tMatch:Start()
   return true
end

local function _BackFee(t)
   local nEntryTicket =tonumber(t.nEntryTicket) or 0        --入场门票数量
   local nEntryCoin =tonumber(t.nEntryCoin) or 0			   --入场金币
   local nServiceCoin =tonumber(t.nServiceCoin) or 0		   --手续费金币
   local SettleEnd =tonumber(t.SettleEnd)                   --1：表示比赛已结算
   local nGameId =tonumber(t.nGameId)

   if SettleEnd or nGameId==nil then
      return
   end
   local nFee =nEntryCoin +nServiceCoin
   for s,v in pairs(t) do
      local s1 =string.match(s,"U:(.*)")
      local nUserId =tonumber(s1)
      if nUserId then
         local nSourceType =10000 +100*nGameId +Define.GoldCReason.nMttCancel
         local isSuccee =tPubUser.ChangeUserTreasure({nUserID=nUserId,nItemID=1,nDel=nFee,nSourceType=nSourceType,isNotCheck=true})
         tBase.Log("_BackFee,nUserId:%d nFee:%d nGameId:%d v:%s",nUserId,nFee,nGameId,v)
      end
   end
end


function MsgHandle.CheckBackFee()
   local arrKeys,redis =_GetKeys("MTTUsers_*")
   for _,sKey in ipairs(arrKeys) do
      local t =redis:hgetall(sKey)
      tBase.Log("CheckBackFee:%s",sKey)
      _BackFee(t)
      redis:del(sKey)
   end
end


return MsgHandle