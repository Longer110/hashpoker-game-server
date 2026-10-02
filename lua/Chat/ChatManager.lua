 
local tBase = require("base")
local cjson = require("cjson")
local tTimerAux = require("TimerAux")
local tname = require("typename") -- 类弄定义接口
local tgBotMessage = require("TgBotMessage")

ChatManager = {
    arrChat = {},
	cidDict = {},
}

local function _GetUserAccid(nUserId)
    return string.format("game_accid_%d",nUserId)
end

local function FormatCid(sTable_cid)
	return string.format("%d", sTable_cid)
end

-- 语聊房间创建需要的UID
local function _GetUserUid(nUserId)
    return nUserId
end

local tChatInfo = {}

function tChatInfo:New(tInterFace)
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.nChatType = 1   --1:牌桌聊天,2:俱乐部聊天
	t.sTableId = ""
	t.nClubId = 0   	  -- 俱乐部id  
	t.arrUser = {}   	  -- 聊天用户
	t.arrChatRecord = {}  -- 聊天记录
	t.arrChatRecordNew = {}  -- 聊天记录
	t.nLiveUserID = 0     -- 房主 
	t.nGroupId = 0
	t.sTableName = ""  -- 房间名称
	t.sConfig = {}	-- 房间配置 json
	t.nGameId = 0  -- 游戏id

	-- IM 即时通讯 数据  
	t.sTable_accid=""     -- 房主id，分组id  
	t.sTable_token=""     -- IM token  
	t.sTable_cid = 0      -- 音视频房间ID
	t.sTable_uid = 0      -- 音视频房间创建者ID
	t.tid = "0"           -- 群组id   
	t.sCreateTime = ""
	t.nTime = os.time()
	t.Timer =tTimerAux:New()

	t.tInterFace=tInterFace   --Game层接口 (Game =>table =>user)	
	t.arrChatChangeCfg = {}   --价格表配置 json  {{nChatId=1,nCost=10} } 表情价格表:  1-49 , 弹幕价格表:50-100 

	t.nKeepTime = 0  		 -- 房间时长(秒)  -1:永久桌，不要关  >0:非永久桌
	
	t.nLoadCfgTIme  = os.time()  -- 加载配置时间

	return t
end

-- tg机器人消息基础
function tChatInfo:GetTgMsgBase()
	return {
		nGameId =self.nGameId,
		sTableId =self.sTableId,
		sTableName =self.sTableName,
		nZhuaTou =self.sConfig.nZhuaTou or 0,
		nSmallBlind =self.sConfig.nSmallBlind or 0,
		nBigBlind =self.sConfig.nBigBlind or 0,
		isForceBlind =self.sConfig.isForceBlind,
		nForceBlind = self.sConfig.nForceBlind or 0,
		nPreAnte = self.sConfig.nPreAnte or 0
	}
end

-- 添加聊天内容 
function tChatInfo:_AddChat(msg)
	table.insert(self.arrChatRecordNew, msg)
	if #self.arrChatRecordNew == 10 then
		tgBotMessage.PushChat{
			baseCfg = self:GetTgMsgBase(),
			chatLog = tBase.DeepCopy(self.arrChatRecordNew)
		}
		self.arrChatRecordNew = {}
	end
end

-- 语音收费配置
function tChatInfo:GetFeeConfig()
	local isVideoFee = self.sConfig.isVideoFee
	local nVideoFee = self.sConfig.nVideoFee or 0
	return isVideoFee, nVideoFee
end

--//
function tChatInfo:Print(str,...)
	tBase.Log(string.format("Id=>"..self.sTableId.."=>"..str,...))
end

function tChatInfo:PrintError(str,...)
	tBase.Log(string.format("Id=>"..self.sTableId.."=>"..str,...))
end

-- 群组管理
function tChatInfo:Handle_ChatGroup_TableId(tid, cid)
	local sKey = "Chat_GroupId_TableId"
	local tRedis =tBase.m_MyRedisData[2].redis
	if tid then
		local t ={}
		t.tid = self.tid
		t.sTable_cid = self.sTable_cid or 0
		t.nClubId = self.nClubId
		t.nGroupId = self.nGroupId
		t.sTableId = self.sTableId
		t.accid = self.sTable_accid
		tRedis:hmset(sKey,self.sTableId, cjson.encode(t) )
	else
		tRedis:hdel(sKey,self.sTableId)
	end
end
 
-- 写记录
function tChatInfo:WriteRecord()
	self.sCreateTime = publicApi.OsTimetoDataTime(os.time())
	local sSql = string.format(
		"Call Chat_Record('%s','%s','%s',%d,%d,'%s',%d)",
		self.sTableId,
		self.tid,
		self.sTable_accid,
		self.nGroupId,
		self.nClubId,
		self.sCreateTime,
		self.sTable_cid
	)
	-- local sSql= "Call Chat_Record('"..self.sTableId.."','"..self.tid.."','"..self.sTable_accid.."',"..self.nGroupId..","..self.nClubId..",'"..self.sCreateTime..",'"..self.sTable_cid.."')"
	local Send = ProtoManager.PubProto_1_pb.REQ_Control_Record()
	local s = tBase.GetSP().new(ProtoManager.Sys.DB,ProtoManager.Sub_DB.SUB_REQ_Chat_Record)
	Send.sSql =  sSql
	s:AddString(Send:SerializeToString())
	tBase.PostDatasByType(typename.db,0,0, s:GetData(), s:GetSize())
end

function tChatInfo:PushWaringInfo(SendSMS)
	tBase._OnMonitorInfo(SendSMS)
	self:Print("_PushWaringInfo  %s ",SendSMS)
end

function tChatInfo:LoadConfig(isUpdate)
	if isUpdate then
		if (os.time() - self.nLoadCfgTIme) <= 60 * 1 then
			return
		end
	end

	self.arrChatChangeCfg = {}
	local tCfg = RedisCahche.GetClubChangeConfig(self.nGroupId)
	if not tCfg then
		self:Print("_LoadConfig  nGroupId_%d  tCfg is nil ",self.nGroupId)
		return
	end
	if not tCfg.arrChatChangeCfg then  
		self.arrChatChangeCfg= {{nChatId=50,nCost=0},{nChatId=0,nCost=0},{nChatId=0,nCost=0}}
	else
		for key, v in pairs(tCfg.arrChatChangeCfg) do
			if v and tonumber(v.nChatId) and tonumber(v.nChatId) >= 50 and tonumber(v.nChatId) <= 100 then   -- 弹幕配置
				table.insert(self.arrChatChangeCfg ,v)
			end 
		end
	end
	if #self.arrChatChangeCfg == 0 then 
		self.arrChatChangeCfg= {{nChatId=50,nCost=0},{nChatId=0,nCost=0},{nChatId=0,nCost=0}}
	end
	
	self.nLoadCfgTIme = os.time()
	self:Print("_LoadConfig  nGroupId_%d  sCfg: %s ",self.nGroupId,cjson.encode(self.arrChatChangeCfg))   
	return
end

-- 创建群组
function tChatInfo:CreateGroup()
	if tonumber(self.tid) > 0 then
		return
	end
    local sBody = string.format("CreateRoom?tname=%s&owner=%s&msg=%s",self.sTable_accid,self.sTable_accid,self.sTable_accid)
    local sUrl  =IMMessage.sUrl..sBody
	self:Print("_CreateGroup  请求创建群组Url: %s  ",sUrl)
	local funcRes = function(sData,nCode)
		local isSuccee,tRlt = pcall(cjson.decode,sData)
		if not isSuccee then
			local SendSMS = string.format("IM_创建群组失败: %s sUrl: %s ",sData,sUrl)
			self:PushWaringInfo(SendSMS)
			return
		end
		if tonumber(tRlt.code) == 806 then     --  创建群数量达到限制 
			local SendSMS = string.format("IM_创建群数量达到限制: %s sUrl: %s ",sData,sUrl)
			self:PushWaringInfo(SendSMS)
			return
		end
		if tonumber(tRlt.code) ~= 200 then
			local SendSMS = string.format("IM_创建群组失败: %s sUrl: %s ",sData,sUrl)
			self:PushWaringInfo(SendSMS)
			return
		end
		self.tid =tRlt.tid
		self:WriteRecord()
		self:Handle_ChatGroup_TableId(self.tid)
		local arrUserId = {}
		for nUserId, tUser in pairs(self.arrUser) do
			local ChatLogonRsp = {}
			ChatLogonRsp.nRlt = 0
			ChatLogonRsp.accid = tUser.accid
			ChatLogonRsp.token = tUser.token
			ChatLogonRsp.tid =  self.tid
			self.tInterFace.SendToClient(tUser.sClientID,"ChatLogonRsp",ChatLogonRsp)
			table.insert(arrUserId,nUserId)
		end
		self:Print("_CreateGroup  创建群组成功 sTable_accid_%s tid: %s  arrUserId: %s ",self.sTable_accid,self.tid,cjson.encode(arrUserId))
		return 1
	end
	local funcErr = function(nCode)
		self:Print("_CreateGroup   funcErr  nCode: %s ",nCode)
	end
	HttpNB.request(sUrl,funcRes,funcErr,"GET","")
end
 
-- 删除群组
function tChatInfo:DelChatGroup()
	local nCnt = 0
	for nUserId, tUser in pairs(self.arrUser) do
		if nUserId ~= self.nLiveUserID then
			self:DelUser(nUserId)
			nCnt= nCnt + 1
		end
	end
    local sBody = string.format("DissolutionRoom?tid=%s&owner=%s",self.tid,self.sTable_accid)
    local sUrl  =IMMessage.sUrl..sBody
	self:Print("_DelChatGroup  解散群组Url: %s  ",sUrl)
	local funcRes = function(sData,nCode)
		local isSuccee,tRlt = pcall(cjson.decode,sData)
		if not isSuccee then
			local SendSMS = string.format(" IM_解散群组失败 %s  sUrl: %s ",sData,sUrl)
			self:PushWaringInfo(SendSMS)
			return
		end
		self:Print("_DelChatGroup  解散群组成功: %s,tid_%s,nCnt_%d sTableId:%s",self.sTable_accid,self.tid,nCnt,self.sTableId)
		self:Handle_ChatGroup_TableId()
	end
	local funcErr = function(nCode)
		self:Print("_DelChatGroup   funcErr  nCode: %s ",nCode)
	end
	HttpNB.request(sUrl,funcRes,funcErr,"GET","")
end

-- 玩家 退出 原先 非群主的群组
local function DissolutionRoom(nUserId,tid)
	local accid = _GetUserAccid(nUserId)
	local sBody = string.format("GetJoinTeams?accid=%s",accid)
	local sUrl =IMMessage.sUrl..sBody   
	local funcRes = function(sData,nCode)  
		local isSuccee,tRlt = pcall(cjson.decode,sData) 
		if not isSuccee or tonumber(tRlt.code) ~= 200 then  
			return 
		end 		
		local msg = tRlt.msg
		if msg ~= "success" then  
			return  
		end   
		if tonumber(tRlt.count)  <= 1 then return end 
		tBase.Log("_DissolutionRoom   nUserId_%d Now_tid_%s  当前加入群组数量: %d ",nUserId,tid, tonumber(tRlt.count)) 
		local arrLeaveAGroup = {}
		local arrNotLeaveAGroup = {}
		for k, v in pairs(tRlt.infos) do 
 			if v and v.owner and v.tid then 
				local isLeaveAGroup = true 
				local owner = v.owner
				local oldtid = tostring(math.floor(tonumber(v.tid)))
				local tname = v.tname
				if owner == accid then -- 是否群主
					isLeaveAGroup = false
				end 
				if oldtid == tid then 					
					isLeaveAGroup = false
				end 
				local function fcun1(sData)	
					tBase.Log("_DissolutionRoom  退出群组成功 nUserId_%d owner: %s,oldtid: %s GroupInfo_%s  Result: %s  "
					,nUserId,owner,oldtid,cjson.encode(v),sData) 						
				end 
				local funcErr1 = function(nCode)
					tBase.Log("_DissolutionRoom  funcErr  nCode: %s ",nCode)
				end  	
				if isLeaveAGroup then 
					local sBody = string.format("KickUserRoom?tid=%s&owner=%s&kickAccids=%s",oldtid,owner,accid) 
					local sUrl =IMMessage.sUrl..sBody   
					HttpNB.request(sUrl,fcun1,funcErr1,"GET","")   				
					table.insert(arrLeaveAGroup,{tname=tname,tid=oldtid,owner=owner})  
				else
					if oldtid ~= tid then 					
						table.insert(arrNotLeaveAGroup,{tname=tname,tid=oldtid,owner=owner})
					end
				end 
			end  
		end		
		tBase.Log("_DissolutionRoom   nUserId_%d Now_tid_%s 退群： %s 不退群: %s "
		,nUserId,tid,cjson.encode(arrLeaveAGroup),cjson.encode(arrNotLeaveAGroup)) 

	end
	local funcErr = function(nCode)
		tBase.Log("_DissolutionRoom  funcErr  nCode: %s ",nCode)
	end  
	HttpNB.request(sUrl,funcRes,funcErr,"GET","")
end

-- 用户加入
function tChatInfo:AddUser(tUser)  
	self:LoadConfig(true)
	local nUserId = math.floor(tUser.nUserId)
	if self.arrUser[nUserId] then  
		self.arrUser[nUserId] = nil 
	end 
	local function ChatLogonReq(isSuccee,sErr)
		local ChatLogonRsp = {} 
		ChatLogonRsp.nRlt = 0 
		ChatLogonRsp.accid = tUser.accid
		ChatLogonRsp.token = tUser.token 
		ChatLogonRsp.tid =  self.tid
		ChatLogonRsp.sCfg =  cjson.encode(self.arrChatChangeCfg)
		local sLog = "成功"
		if isSuccee then  
			self.arrUser[tUser.nUserId] = tUser 
			self.tInterFace.UserEnterTable(nUserId,self.sTableId) 				
			IMMessage.Update_UserInfo(nUserId,tUser.sName,tUser.sFaceId)  	-- 更新用户信息
			if self.tid == "0" then 
				self:Print("_AddUser 加入: %s  nUserId_%d  tid_%s  token: %s  群还没创建好,稍后再通知",sLog,nUserId,tUser.tid,tUser.token)  
				return
			end
		else
			ChatLogonRsp.nRlt = 1
			ChatLogonRsp.token = sErr
			self.tInterFace.UserLeave(nUserId)
			sLog = "失败: "..sErr
		end
		self.tInterFace.SendToClient(tUser.sClientID,"ChatLogonRsp",ChatLogonRsp)
		self:Print("_AddUser 加入: %s  nUserId_%d  tid_%s  token: %s ",sLog,nUserId,tUser.tid,tUser.token)
	end
	if tUser.nUserId == self.nLiveUserID then 		-- 加入群组
		self:Print("_AddUser  群主来的_%d  tid_%d ",tUser.nUserId,self.tid)	 
		ChatLogonReq(true)
		return 1
	end
	if self.tid == "0" then
		self.arrUser[tUser.nUserId] = tUser 
		self.tInterFace.UserEnterTable(nUserId,self.sTableId) 				
		IMMessage.Update_UserInfo(nUserId,tUser.sName,tUser.sFaceId)  	-- 更新用户信息
		self:Print("_AddUser 群还没创建好,稍后再通知 nUserId_%d  tid_%s  token: %s  ",nUserId,tUser.tid,tUser.token)  
		return
	end 
	local nUserId = math.floor(tUser.nUserId)
	local accid = _GetUserAccid(nUserId)
	local sBody = string.format("JoinRoom?tid=%s&owner=%s&uid=%s&msg=%s",self.tid,self.sTable_accid,accid,self.sTable_accid) 
	local sUrl =IMMessage.sUrl..sBody  
	self:Print("_AddUser  加入群组_%d  tid_%d  sUrl: %s ",nUserId,self.tid,sUrl)	
	local funcRes = function(sData,nCode)  
		local isSuccee,tRlt = pcall(cjson.decode,sData) 
		if not isSuccee or tonumber(tRlt.code) ~= 200 then 
			local SendSMS = string.format(" IM_加入群组失败 code:%d  sData_%s  ",tRlt.code or -1,sData)
			self:PushWaringInfo(SendSMS)  	
			ChatLogonReq(false,sData)
			return 
		end 				
		local msg = tRlt.msg
		if msg ~= "success" then 
			local SendSMS = string.format(" IM_加入群组失败  msg: %s sData_%s  ",msg or "-1",sData)
			self:PushWaringInfo(SendSMS)  		
			ChatLogonReq(false,sData)
			return  
		end  
		tBase.Log("_AddUser   加入群组_%d  sUrl: %s sData_%s ",nUserId,sUrl,sData)	 
		ChatLogonReq(true)

		DissolutionRoom(nUserId,self.tid)  -- 退出原先的群
		return 1
	end	
	local funcErr = function(nCode)
		self:Print("_AddUser  funcErr  nCode: %s ",nCode)
	end 
	HttpNB.request(sUrl,funcRes,funcErr,"GET","")  
	return 1
end

function tChatInfo:DelUser(nUserId)
	local tUser = self.arrUser[nUserId]
	if not tUser then
		self:Print("_DelUser  清除数据 nUserId: %d  tUser is nil",nUserId)
		return
	end
	self.tInterFace.UserEnterTable(nUserId,self.sTableId)
	if (self.nTableType or 1) < 5 then
		self:DelZhiBoUser(nUserId)
		return
	end
	if nUserId == self.nLiveUserID then
		self:Print("_DelUser   nUserId: %d 群主来的，不踢 tid_%d ",nUserId,self.tid)
		self.arrUser[nUserId] = nil
		return
	end

    local sBody = string.format("KickUserRoom?tid=%s&owner=%s&kickAccids=%s",self.tid,self.sTable_accid,tUser.accid)
    local sUrl =IMMessage.sUrl..sBody  
	self:Print("_DelUser   踢出群组_%d tid_%d,sUrl: %s ",nUserId,self.tid,sUrl)	
	local funcRes = function(sData,nCode)  
		local isSuccee,tRlt = pcall(cjson.decode,sData) 
		if not isSuccee then 
			local SendSMS = string.format(" IM_踢出群组失败 %s  sUrl: %s ",sData,sUrl)
			self:PushWaringInfo(SendSMS)	 
		end 	
		tBase.Log("_DelUser   踢出群组_%d  sUrl: %s sData_%s ",nUserId,sUrl,sData)	 
	end	
	local funcErr = function(nCode)
		self:Print("_DelUser  funcErr  nCode: %s ",nCode)
	end 
	HttpNB.request(sUrl,funcRes,funcErr,"GET","") 	
	self.arrUser[nUserId] = nil 
end 

function tChatInfo:GetUser(nUserId)
	if not self.arrUser[nUserId] then
		return
	end
	return self.arrUser[nUserId]
end

function tChatInfo:SetUserInfo(nUserId, data)
	if not self.arrUser[nUserId] then
		return
	end
	for key, value in pairs(data) do
		self.arrUser[nUserId][key] = value
	end
end

-- 获取弹幕 能用
function tChatInfo:_GetChatCost(nChatId)
	self:LoadConfig(true)
	for _,v in ipairs(self.arrChatChangeCfg) do
		if v.nChatId ==nChatId then
			return v.nCost
		end
	end
	return 0
end

-- 添加直播用户 
function tChatInfo:AddZhiBoUser(tUser)  
	local nUserId = math.floor(tUser.nUserId) 
	self.arrUser[nUserId] = tUser 
	self.tInterFace.UserEnterTable(nUserId,self.sTableId) 	
	self:Print("_AddZhiBoUser nUserId: %d  ",nUserId)	
end

function tChatInfo:DelZhiBoUser(nUserId)  
	local tUser = self.arrUser[nUserId]
	if not tUser then 
		self:Print("_DelZhiBoUser  清除数据 nUserId: %d  tUser is nil",nUserId)	
		return
	end 	
	self:Print("_DelZhiBoUser nUserId: %d ",nUserId)	
	self.arrUser[nUserId] = nil 
end 

-- 添加聊天内容 
function tChatInfo:_AddChatMastter(tChatMatter)
	if #self.arrChatRecord >= 20 then  
		local nCnt = #self.arrChatRecord - 20
		for i = 1, nCnt, 1 do
			table.remove(self.arrChatRecord,1)
		end
	end 
	table.insert(self.arrChatRecord,tChatMatter)
	return 
end 

function tChatInfo:_GetChatMastter()
	return self.arrChatRecord
end 

-- 检测是否 创建群组成功
function tChatInfo:_CheckCreateGroup(isVodeo)
	if not self.nCheckCnt then
		self.nCheckCnt = 0
	else
		self.nCheckCnt = self.nCheckCnt + 1
	end
	if isVodeo then
		if self.sTable_cid > 0 then
			return
		end
	else
		if tonumber(self.tid) > 0 then
			return
		end
	end
	if self.nCheckCnt <= 10 then
		if isVodeo then
			self:CreateVideoRoom()
		else
			self:CreateGroup()
		end
		self.Timer:DelayCall(20*1000,self._CheckCreateGroup,self,isVodeo)
	else
		self:Print("_CheckCreateGroup  超时了,需检测 tid_%d   ",tonumber(self.tid))
	end
end

-- 创建音视频房间
function tChatInfo:CreateVideoRoom()
	if self.sTable_cid > 0 then
		return
	end
	if not self.sConfig.isVideoFee then
		return
	end
	local sTable_uid = _GetUserUid(self.nGroupId)
	local sBody2 = string.format("CreateVoiceVideoRoom?uid=%d&tname=%s",sTable_uid, self.sTableId)
	local sUrl2 =IMMessage.sUrl..sBody2
	self:Print("_CreateGroup  请求创建音视频房间Url:%s", sUrl2)
    local funcRes2 = function(sData,nCode)
		local isSuccee,tRlt = pcall(cjson.decode,sData)
		if not isSuccee then
			local SendSMS = string.format(" 创建音视频房间失败 %s  sUrl: %s ",sData,sUrl2)
			self:PushWaringInfo(SendSMS)
			return
		end
		local code = tonumber(tRlt.code)
		if code == 414 or code == 40004 then
			tBase.Log("CreateVideoRoom 创建音视频房间  sTableId:%s 失败 Code:%d tRlt.msg:%s",self.sTableId, code, tRlt.Msg or "")
			tRlt.token = "fail"
			return
		end
		local cid = tonumber(tRlt.cid)
		local sKey = "Chat_IM_Token"
		local tRedis =tBase.m_MyRedisData[2].redis
		tRedis:hset(sKey,self.sTableId, cid)
		self:Print("CreateVideoRoom 创建音视频房间 成功 sTableId_%s tRlt.cid:%d", self.sTableId, cid)

		self.sTable_cid = cid
		self:WriteRecord()
		self:Handle_ChatGroup_TableId(self.tid, cid)
		ChatManager.cidDict[FormatCid(cid)] = self.sTableId
		tBase.LogT(ChatManager.cidDict)
		return 1
	end
	local funcErr = function(nCode)
		self:Print("CreateVideoRoom   funcErr  nCode: %s ",nCode)
	end
	HttpNB.request(sUrl2,funcRes2,funcErr,"GET","")
end

-- 删除音视频房间
function tChatInfo:DelVideoRoom()
	if self.sTable_cid == 0 then
		return
	end
    local sBody = string.format("DeleteRoom?cid=%d", self.sTable_cid)
    local sUrl  =IMMessage.sUrl..sBody
	self:Print("DelVideoRoom  删除音视频房间 Url: %s  ",sUrl)
	local funcRes = function(sData,nCode)
		local isSuccee,tRlt = pcall(cjson.decode,sData)
		if not isSuccee then
			local SendSMS = string.format(" IM_删除音视频房间失败 %s  sUrl: %s ",sData,sUrl)
			self:PushWaringInfo(SendSMS)
			return
		end
		self:Print("DelVideoRoom  删除音视频房间 sTable_cid_%d sTableId:%s", self.sTable_cid, self.sTableId)
	end
	local funcErr = function(nCode)
		self:Print("DelVideoRoom   funcErr  nCode: %s ",nCode)
	end
	HttpNB.request(sUrl,funcRes,funcErr,"GET","")
end

-------------------------  聊天管理 


-- 获取玩家IM token
-- 获取玩家IM token
local function GetUserToken(nUserId,sNickName,sFaceID,isVideo)
    local sKey = "Chat_IM_Token"
	local tRedis =tBase.m_MyRedisData[2].redis
    local accid = _GetUserAccid(nUserId)
    if isVideo then
        accid = string.format("%d", _GetUserUid(nUserId))
    end
    local token = tRedis:hget(sKey,accid)
    if not token or #token <= 1 then
        return
    end
    return token
end

local function CheckLobbyGroup(nGroupId)
	-- 检查分组 的牌桌数量 是否 超过50 

end

-- 注册大厅群主
local function _RegisterLobbyGroup(tData,tInterface)
    local tChat = tChatInfo:New(tInterface)
    tChat.nLiveUserID = math.floor(tData.nLiveUserID)
    tChat.sTableId = tData.sTableId
    local tConfig = cjson.decode(tData.sConfig)
	tChat.nClubId = math.floor(tConfig.nClubId)
	tChat.nKeepTime = math.floor(tConfig.nKeepTime)
	local isVideoFee = tConfig.isVideoFee

    local nGroupId = math.floor(tData.nGroupId)
	local sNewGroupId = CheckLobbyGroup(nGroupId)
	if sNewGroupId then
		nGroupId = sNewGroupId
	end
    tChat.nGroupId = nGroupId
    local sTable_accid = _GetUserAccid(nGroupId)
	local sTable_uid = _GetUserUid(nGroupId)
	tChat.sTable_uid = sTable_uid

    local sBody = string.format("RegisterAccount?accid=%s&name=%s&headUrl=%s",sTable_accid,sTable_accid,sTable_accid)
	local sBody2 = string.format("CreateVoiceVideoRoom?uid=%d&tname=%s",sTable_uid,tChat.sTableId)
	local sUrl =IMMessage.sUrl..sBody
	local sUrl2 =IMMessage.sUrl..sBody2
	tChat:Print("_RegisterLobbyGroup 注册大厅群主 nGroupId_%d nClubId_%d  sUrl: %s ",tChat.nGroupId,tChat.nClubId,sUrl)
	tChat:Print("_RegisterLobbyGroup 注册大厅语聊 nGroupId_%d nClubId_%d  sUrl: %s ",tChat.nGroupId,tChat.nClubId,sUrl2)

	local funcRes = function(sData,nCode)
		local isSuccee,tRlt = pcall(cjson.decode,sData)
		if not isSuccee then
			local SendSMS = string.format(" IM_注册大厅群主失败 %s  sUrl: %s ",sData,sUrl)
			tChat:PushWaringInfo(SendSMS)
			return
		end
		if tonumber(tRlt.code) == 414 then
			if tRlt.msg == "already register" then     -- 已注册, 重新刷新token 
				tBase.Log("_RegisterLobbyGroup 注册大厅群主  sTable_accid: %s 已注册,重新刷新token: %s ",sTable_accid,tRlt.token)
				tRlt.token = "is Club Lobby Group"
			elseif tRlt.msg ==	"Exceed the maximum account 7385" then     -- IM 账号数量超了
				local SendSMS = string.format(" IM_注册账号数量超了 %s  sUrl: %s ",sData,sUrl)
				tChat:PushWaringInfo(SendSMS)
				return
			else
				local SendSMS = string.format(" IM_注册大厅群主失败 %s  sUrl: %s ",sData,sUrl)
				tChat:PushWaringInfo(SendSMS)
				return
			end
		end
		local sKey = "Chat_IM_Token"
		local tRedis =tBase.m_MyRedisData[2].redis
		tRedis:hset(sKey,sTable_accid,tRlt.token)
		tChat:Print("_RegisterLobbyGroup 注册大厅群主 成功  sTable_accid_%s nClubId_%d ",sTable_accid,tChat.nClubId)

		tChat.sTable_accid =sTable_accid  -- 根据俱乐部ID: 分组id来的
		tChat.sTable_token =tRlt.token

		tChat:CreateGroup()
		ChatManager.arrChat[tData.sTableId] = tChat
	end
	local funcErr = function(nCode)
		tChat:Print("_RegisterLobbyGroup funcErr nCode:%s ",nCode)
	end
	local funcRes2 = function(sData,nCode)
		local isSuccee,tRlt = pcall(cjson.decode,sData)
		if not isSuccee then
			local SendSMS = string.format(" IM_注册大厅语聊失败 %s  sUrl: %s ",sData,sUrl)
			tChat:PushWaringInfo(SendSMS)
			return
		end
		local code = tonumber(tRlt.code)
		if code == 414 or code == 40004 then
			tBase.Log("_RegisterLobbyGroup 注册大厅语聊  sTableId:%s 失败 Code:%d tRlt.msg:%s",tData.sTableId, tRlt.Code, tRlt.msg)
			tRlt.token = "fail"
			return
		end
		local cid = tonumber(tRlt.cid)
		local sKey = "Chat_IM_Token"
		local tRedis =tBase.m_MyRedisData[2].redis
		tRedis:hset(sKey,tData.sTableId, cid)
		tChat:Print("_RegisterLobbyGroup 注册大厅语聊 成功  sTable_accid_%s nClubId_%d tRlt.cid:%d",sTable_accid, tChat.nClubId, cid)

		tChat.sTable_cid = cid
		ChatManager.cidDict[FormatCid(cid)] = tData.sTableId
		tBase.LogT(ChatManager.cidDict)
	end
	HttpNB.request(sUrl,funcRes,funcErr,"GET","")
	if isVideoFee then
		HttpNB.request(sUrl2,funcRes2,funcErr,"GET","")
	end
end

 
-- 创建牌桌 
function ChatManager.CreateChat(tData,tInterface)
	local nLiveUserID = math.floor(tData.nLiveUserID)
	local nGroupId = math.floor(tData.nGroupId)
	local nTableType = math.floor(tData.nTableType)
	local tConfig = cjson.decode(tData.sConfig)

	if nTableType == 5 and nLiveUserID == 0 then   -- 大厅房间
		local token = GetUserToken(nGroupId)
		if not token then
			_RegisterLobbyGroup(tData,tInterface)
			return
		end
        tBase.Log("_CreateChat  sTableId: %s  nLiveUserID_%d nGroupId_%d 大厅房间  ",tData.sTableId,tData.nLiveUserID,tData.nGroupId)
	end
    local tChat = tChatInfo:New(tInterface)
    tChat.nLiveUserID = math.floor(tData.nLiveUserID)
	local sTable_uid = _GetUserUid(tChat.nGroupId)
	if nLiveUserID > 0 then
		sTable_uid = _GetUserUid(nLiveUserID)
	end
	tChat.sTable_uid = sTable_uid
    tChat.nTableType = math.floor(tData.nTableType)
    tChat.nGroupId = math.floor(tData.nGroupId)
    tChat.sTableId = tData.sTableId
	tChat.sTableName = tData.sTableName or ""
	tChat.sConfig = tConfig or {}
	tChat.nGameId = tChat.sConfig.nGameId or 0

	if tChat.nTableType == 5 then   -- 俱乐部牌桌
		tChat.nClubId = math.floor(tConfig.nClubId)
		tChat:Print("_CreateChat  俱乐部牌桌聊天 ")
	elseif tChat.nTableType < 5 then  -- 直播牌桌
		ChatManager.arrChat[tData.sTableId] = tChat
		tChat:Print("_CreateChat  直播牌桌聊天")
		return
	end

    local sTable_accid = _GetUserAccid(tChat.nGroupId)    -- 根据俱乐部ID: 分组id来的
	if tChat.nLiveUserID > 0 then
		sTable_accid = _GetUserAccid(tChat.nLiveUserID)
		if not GetUserToken(tChat.nLiveUserID) then  -- 注册 IM
			local Chat_pb =ProtoManager.Chat_pb
			local Chat_CMD =ProtoManager.Chat_pb.Chat_Proto()
			local Send = Chat_pb.ChatLogonReq()
			Send.nUserId = tChat.nLiveUserID
			Send.nChatType = 0
			local s = tBase.GetSP().new(Chat_CMD.Main_CMD,Chat_CMD.ChatLogonReq_CMD)
			s:AddString(Send:SerializeToString())
			tBase.PostDatasByType(tname.chat, 0, 0, s:GetData(), s:GetSize())
			tBase.Log("_CreateChat  nUserId_%d   没有token ",tChat.nLiveUserID)
		end
	end
	tChat.sTable_accid = sTable_accid
	tChat.nKeepTime = math.floor(tConfig.nKeepTime)
	tChat:CreateGroup()
    ChatManager.arrChat[tData.sTableId] = tChat
	tChat:CreateVideoRoom()
	tChat:LoadConfig()
	tChat.Timer:DelayCall(5*1000,tChat._CheckCreateGroup,tChat)
	tChat.Timer:DelayCall(5*1000,tChat._CheckCreateGroup,tChat, true)
    return tChat
end

function ChatManager.DelChat(sTableId)
	local tChat = ChatManager._GetChat(sTableId)
	if not tChat then
		tBase.Log("_DelChat  sTableId_%s  tChat is nil",sTableId)
		return
	end
	local sLog = ""
	if tChat.nTableType and tChat.nTableType < 5 then  -- 区块链牌桌 
		sLog="直播牌桌"
	else
		sLog="俱乐部牌桌"
		tChat:DelChatGroup()
		tChat:DelVideoRoom()
	end
	tChat:Print("_DelChat   nTableType_%d 删除 %s",tChat.nTableType or -1 ,sLog or "")
	tChat.Timer:KillAllTimer()
	ChatManager.arrChat[sTableId] = nil
	return 1
end

function ChatManager._GetChat(sTableId)
    return ChatManager.arrChat[sTableId]
end

-- 语聊房cid
function ChatManager._GetChatByCid(cid)
	-- tBase.LogT("cidDict", ChatManager.cidDict)
	for sTableId, tChat in pairs(ChatManager.arrChat) do
		-- tBase.Log("_GetChatByCid sTableId:%s", sTableId)
	end
	local sTableId = ChatManager.cidDict[cid]
	if not sTableId then
		return
	end
	return ChatManager._GetChat(sTableId)
end

-- 检查牌桌 超时没有关桌问题
function ChatManager.CheckTableTimeOut()
	local arrTableId = {}
	-- 检查 牌桌有效时长
	for sTableId, tChat in pairs(ChatManager.arrChat) do
		local isCloase = false
		if tChat.nKeepTime > 0 then
			if ((os.time() -tChat.nTime) > tChat.nKeepTime) then   -- 超过 7天没有关闭就自行关闭
				tChat:Print("_CheckTableTimeOut  超时关闭  sTableId: "..sTableId)
				table.insert(arrTableId,sTableId)
				isCloase = true
			end
		else  -- 永久牌桌
		end
		-- 检查 服务器key 是否失效
		local nCenterServerId =tonumber(string.match(sTableId,"(%d+)#"))
		local sCenterKey  = tBase.GetServerIdIdKey(nCenterServerId)
		if not isCloase and not sCenterKey then
			table.insert(arrTableId,sTableId)
			tChat:Print("_CheckTableTimeOut  服务器key失效  nCenterServerId_%d  sTableId: %s ",nCenterServerId,sTableId)
		end
	end
	if #arrTableId > 0 then
		Base.Log("_CheckTableTimeOut  即将关桌 arrTableId:  "..cjson.encode(arrTableId))
		for _, sTableId in ipairs(arrTableId) do
			ChatManager.DelChat(sTableId)
		end
	end
end



return ChatManager