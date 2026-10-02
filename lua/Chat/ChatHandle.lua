local UserManager = require("UserManager")
local ClientIdMgr = require("ClientIdMgr")
local tBase64 = require("BaseSink")    -- base 编码解码
local cjson = require("cjson")
local tname = require("typename") -- 类弄定义接口
local tPublicRedis = require("PublicRedis")
local publicApi =require("publicApi")

ChatHandle = {
    tDeleteList = {}
}

local tInterface={}    --table逻辑所依赖的接口

function SafeExecute(func, funcName, ...)
    local success, result = pcall(func, ...)
    if not success then
        tBase.Log(string.format("函数 %s 执行失败: %s", funcName or "未知", result))
        return false, result
    end
    return true, result
end
 
-- URI 编码
local function encodeURI(s)
    s = string.gsub(s, "([^%w%.%- ])", function(c) return string.format("%%%02X", string.byte(c)) end)
    return string.gsub(s, " ", "%20")
end

--网络协议发送(发给前端)
local function SendToClient(sClientID,strProto,tSendData)
    local tPacket = ChatAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    tBase.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize())
end

local function _GetUserAccid(nUserId)
    return string.format("game_accid_%d",nUserId)
end

-- 语聊房间创建需要的UID
local function _GetUserUid(nUserId)
    return nUserId
end

local function _GenTokenExKey(accid)
    return "imtk:" .. accid
end

local function _GenExKey(nUserId)
    return "vK:" .. string.format("%d", _GetUserUid(nUserId))
end

-- 获取玩家IM token
local function GetUserToken(nUserId,sNickName,sFaceID,isVideo)
    local sKey = "Chat_IM_Token"
	local tRedis =tBase.m_MyRedisData[2].redis
    local accid = _GetUserAccid(nUserId)
    if isVideo then
        accid = string.format("%d", _GetUserUid(nUserId))
        local tRedis1 =tBase.m_MyRedisData[1].redis
        if not tRedis1:exists(_GenExKey(nUserId)) then
            tRedis:hdel(sKey, accid)
            return
        end
    else
        local exKey = _GenTokenExKey(accid)
        local tRedis1 =tBase.m_MyRedisData[1].redis
        if not tRedis1:exists(exKey) then
            tRedis:hdel(sKey, accid)
            return
        end
    end
    local token = tRedis:hget(sKey,accid)
    if not token or #token <= 1 then
        return
    end
    return token
end

local function GetNickName(sNickName)
    if sNickName then
        sNickName=tBase64.decode(sNickName)     -- 先解码
        if #sNickName >= 63 then
            sNickName = string.sub(sNickName,1,63)
        end
        sNickName = publicApi.Check_String_Special(sNickName)
        sNickName=encodeURI(sNickName)
    end
    return sNickName
end

-- 用户离开
local function UserLeave(nUserId)
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        tBase.Log("_UserLeave 用户离开 nUserId_%d  tUser is nil  ",nUserId)
        return
    end
    ClientIdMgr.DestroyClientID(tUser.sClientID)
    local sTableId = tUser:GetNowTable()
    if sTableId and sTableId ~= "" then
        local tChat = ChatManager._GetChat(sTableId)
        if tChat then
            tChat:DelUser(nUserId)
        end
    end
    UserManager.DelUser(nUserId)
    tBase.Log("_UserLeave nUserId_%d 删除数据 sTableId: %s",nUserId,sTableId)
    return
end

local function UserEnterTable(nUserId,sTableId)
    UserManager.UserEnterTable(nUserId,sTableId)
end

local function UserLeaveTable(nUserId,sTableId)
    UserManager.UserLeaveTable(nUserId,sTableId)
end

-- 解散群组 
local function _DeleteIMGroup(tid,accid)
    local sBody = string.format("DissolutionRoom?tid=%s&owner=%s",tid,accid)
    local sUrl =IMMessage.sUrl..sBody
    tBase.Log("_DeleteIMGroup 解散群组Url: %s ",sUrl)     
	local funcRes = function(sData,nCode)
		local isSuccee,tRlt = pcall(cjson.decode,sData)
		if not isSuccee then
            tBase.Log("_DeleteIMGroup    解析失败 sData: %s Url: %s ",sData,sUrl)
			return
		end
        tBase.Log("_DeleteIMGroup   %s   Url: %s ",sData,sUrl)
	end
	local funcErr = function(nCode)
        tBase.Log("_DeleteIMGroup   失败 nCode: %d  Url: %s ",nCode,sUrl)
	end
	HttpNB.request(sUrl,funcRes,funcErr,"GET","")
end

-- 删除音视频房间
local function _DelVideoRoom(sTable_cid)
    sTable_cid = tonumber(sTable_cid)
	if not sTable_cid or sTable_cid == 0 then
        return
    end
    local sBody = string.format("DeleteRoom?cid=%d", sTable_cid)
    local sUrl  =IMMessage.sUrl..sBody
	tBase.Log("_DelVideoRoom  删除音视频房间 Url: %s  ",sUrl)
	local funcRes = function(sData,nCode)
		local isSuccee,tRlt = pcall(cjson.decode,sData)
		if not isSuccee then
			local SendSMS = string.format(" IM_删除音视频房间失败 %s  sUrl: %s ",sData,sUrl)
			return
		end
		tBase.Log("_DelVideoRoom  删除音视频房间 sTable_cid_%d", sTable_cid)
	end
	local funcErr = function(nCode)
		tBase.Log("_DelVideoRoom   funcErr  nCode: %s ",nCode)
	end
	HttpNB.request(sUrl,funcRes,funcErr,"GET","")
end

local function _DeleteChatRoom(info)
    _DeleteIMGroup(info.tid, info.accid)
    _DelVideoRoom(info.sTable_cid)
end

-- 退群 
local function _Leave_IMGroup(tid,owner,accid)
    local sBody = string.format("KickUserRoom?tid=%s&owner=%s&kickAccids=%s",tid,owner,accid)
    local sUrl =IMMessage.sUrl..sBody
	local funcRes = function(sData,nCode)
		local isSuccee,tRlt = pcall(cjson.decode,sData)
		if not isSuccee then
            tBase.Log("_Leave_IMGroup    解析失败 sData: %s Url: %s ",sData,sUrl)  
			return  
		end 	        
        tBase.Log("_Leave_IMGroup   %s   Url: %s ",sData,sUrl) 
	end	
	local funcErr = function(nCode)
        tBase.Log("_Leave_IMGroup   失败 nCode: %d  Url: %s ",nCode,sUrl)
	end 
	HttpNB.request(sUrl,funcRes,funcErr,"GET","")
end

-- 加入清除队列
local function _AddDeleteList(tid,accid,owner)
    if owner then
        table.insert(ChatHandle.tDeleteList,{tid=tid,accid=accid,owner=owner})
    else
        table.insert(ChatHandle.tDeleteList,{tid=tid,accid=accid})
    end
end

-- 加入清除队列
local function _AddDeleteList(info)
    table.insert(ChatHandle.tDeleteList, info)
end

-- 移除队列
local function _RemoveDeleteList(nCnt)
    local arrList = {}
    if nCnt > #ChatHandle.tDeleteList then
        nCnt = #ChatHandle.tDeleteList
    end
    for i = 1,nCnt do
        local t = table.remove(ChatHandle.tDeleteList)
        table.insert(arrList,t)
    end
    return arrList
end

-- 获取用户 家人群组 信息 
local function GetUserJoinGroup(accid)
    local sUrl = IMMessage.sUrl.."GetJoinTeams?accid="..accid
    local funcRes = function(sData,nCode)
        local isSuccee,tRlt = pcall(cjson.decode,sData)
        if not isSuccee then
            return
        end
        if tonumber(tRlt.count) == 0 then
            tBase.Log("_GetUserJoinGroup  nUserId: %s  count: %d  没有群组 ",accid,tonumber(tRlt.count))
            return
        end
        tBase.Log("_GetUserJoinGroup  nUserId: %s  群组数量: %d",accid,tonumber(tRlt.count))
        for k, v in pairs(tRlt.infos) do
            local tid = math.floor(v.tid)
            if accid == v.owner then
                _AddDeleteList(tid,v.owner)
            else
                -- _AddDeleteList(v.tid,accid,v.owner)   
            end
        end
    end
    local funcErr = function(nCode)
        tBase.Log("_GetUserJoinGroup  funcErr  nCode: %s  sUrl: %s",nCode,sUrl)
    end
    HttpNB.request(sUrl,funcRes,funcErr,"GET","")
end

-- 重启时 关闭聊天群组
function ChatHandle.RestartService_CloseTable()
	if tBase.m_tKey ~= tBase.m_arrServerList[tname.chat][1] then
        tBase.Log("_RestartService_CloseTable   此线程不处理 ")
        return
    end

    tBase.Log("_RestartService_CloseTable  处理群组问题")
    local tRedis =tBase.m_MyRedisData[2].redis

    -- 清除牌桌 群    
    local function Clear_TableId_tid()
        local sSubKey = "Chat_GroupId_TableId"
        local arrTableInfo =tRedis:hgetall(sSubKey)
        local arrDel = {}
        local nSum,nCnt = 0,0
        for sTableId, sTableInfo in pairs(arrTableInfo) do
            nSum = nSum + 1
            local sTableKey = string.format("APIOpenTale_%s",sTableId)
            local isExists = tRedis:exists(sTableKey)
            if not isExists then
                if #sTableInfo >= 10 then
                    table.insert(arrDel,sTableInfo)
                else
                    tRedis:hdel(sSubKey,sTableId)
                end
                nCnt = nCnt + 1
            end
        end
        if #arrDel > 0 then
            tBase.Log("_Clear_TableId_tid  加入清除队列 arrDel: %d   %d/%d  ",#arrDel,nSum,nCnt)
            for _, sTableInfo in ipairs(arrDel) do
                local tData = cjson.decode(sTableInfo)
                if tData and tData.tid and tData.accid then
                    tRedis:hdel(sSubKey,tData.sTableId)
                    _AddDeleteList(tData)
                end
            end
        end
    end

    -- 清除旧数据
    local function Clear_GroupId_tid()
        local sSubKey = "Chat_GroupId_List"
        local arrGroupIdList = tRedis:hgetall(sSubKey)
        local arrGroupId = {}
        local nCnt = 0
        for tid, nUserId in pairs(arrGroupIdList) do
            tid = math.floor(tid)
            nUserId = math.floor(nUserId)
            if not arrGroupId[nUserId] then
                arrGroupId[nUserId] = {}
            end
            table.insert(arrGroupId[nUserId],tid)
            nCnt = nCnt + 1
        end
        if nCnt == 0 then return end
        tBase.Log("_Clear_GroupId_tid  nCnt: %d   ",nCnt)
        for nUserId, arrTid in pairs(arrGroupId) do
            tBase.Log("_Clear_GroupId_tid  nUserId_%d  arrTid_%d ",nUserId,#arrTid)
            for k, tid in ipairs(arrTid) do
                -- _AddDeleteList(tid,nUserId)    
                tRedis:hdel(sSubKey,tid)
            end
        end
    end

    -- 清除用户 群
    local function Clear_User_tid()
        local sSubKey = "Chat_IM_Token"
        local arrUserInfo =tRedis:hgetall(sSubKey)
        local arrGroup = {}
        for accid,token in pairs(arrUserInfo) do
            if #accid < 19 then
                table.insert(arrGroup,accid)
            end
        end
        tBase.Log("_Clear_User_tid  arrGroup nCnt: %d   ",#arrGroup)
        for _, accid in pairs(arrGroup) do
            -- GetUserJoinGroup(accid)    --频闭掉没用
        end
    end

    Clear_TableId_tid()
    Clear_GroupId_tid()
    Clear_User_tid()

end

--  定时处理
function ChatHandle._Timer_CLearList()
	if tBase.m_tKey ~= tBase.m_arrServerList[tname.chat][1] then
        -- tBase.Log("_RestartService_CloseTable   此线程不处理 ")  
        return
    end
    local nSum = #ChatHandle.tDeleteList
    local nRemoveCnt = 5
    local arrList = _RemoveDeleteList(nRemoveCnt)
    if #arrList > 0 then
        for k, v in ipairs(arrList) do
            -- if v.owner then
            --     _Leave_IMGroup(v.tid,v.owner,v.accid)    -- 退群
            -- else
            --     _DeleteIMGroup(v.tid,v.accid)            -- 解散群
            -- end
            SafeExecute(_DeleteChatRoom, "_DeleteChatRoom", v)
        end
        base.SetTimer(60005,1000*20,1,ChatHandle._Timer_CLearList)
        tBase.Log("_Timer_CLearList nSum: %d / %d  已清除队列: %s ",nSum,#ChatHandle.tDeleteList,cjson.encode(arrList))
    else
        tBase.Log("_Timer_CLearList   已清空队列数据 %d ",nSum)
    end
end

-- 重启时 关闭聊天群组
function ChatHandle._StopServerClear_IM_Group()
	if tBase.m_tKey ~= tBase.m_arrServerList[tname.chat][1] then
        -- tBase.Log("_StopServerClear_IM_Group   此线程不处理 ")  
        return
    end
    local arrTableId = {}
    for sTableId, tChat in pairs(ChatManager.arrChat) do
        table.insert(arrTableId,sTableId)
    end
    tBase.Log("_StopServerClear_IM_Group  关闭牌桌_%d  ",#arrTableId)
    for _, sTableId in pairs(arrTableId) do
        tBase.Log("_StopServerClear_IM_Group  关闭牌桌  sTableId_%s  ",sTableId)
        ChatManager.DelChat(sTableId)
    end
end

--开桌与关桌
function ChatHandle.OnReqAPI_Table(sReturnKey,Data,nLen)
    local s = tBase.GetRP().new(Data, nLen)
    local nMainID = s:GetModuleID()
    local nSubID = s:GetMsgID()
    local tRead = ProtoManager.Backstage_pb.ReqAPI_Table()
    tRead:ParseFromString(s:GetString())
    local tData = {}
    tData.nType = tRead.nType
    tData.sTableId = tRead.sTableId  or "-1"
    tData.nTableType = tRead.nTableType  or 0
    tData.nLiveUserID = tRead.nLiveUserID  or 0
    tData.nGroupId = tRead.nGroupId
    tData.sConfig = tRead.sConfig or ""
    tData.sTableName = tRead.sTableName  or ""
    local sLog = "开桌"
    if tData.nType == 2 then
        sLog = "关桌"
    end
    if tData.nType == 1 then
        tBase.Log("_OnReqAPI_Table  sTableId: %s %s nLiveUserID_%d nGroupId_%d  ",tData.sTableId,sLog,tData.nLiveUserID,tData.nGroupId)
        ChatManager.CreateChat(tData,tInterface)
    else
        tBase.Log("_OnReqAPI_Table  sTableId: %s   %s  ",tData.sTableId,sLog)
        ChatManager.DelChat(tData.sTableId)
    end
end

local function ChatLogonRsp(sClientID,nUserId,nRlt,sErr,sCfg)
    local accid = _GetUserAccid(nUserId) 
    local ChatLogonRsp = {}
    ChatLogonRsp.nRlt = nRlt
    ChatLogonRsp.accid = accid
    ChatLogonRsp.token = sErr
    ChatLogonRsp.sCfg = sCfg  or "" 
    SendToClient(sClientID,"ChatLogonRsp",ChatLogonRsp)  
    tBase.Log("_ChatLogonRsp  nUserId_%d nRlt_%d  sErr_%s ",nUserId,nRlt,sErr)     
end

local function LogonChat(nUserId,sTableId,nChatType,token,sClientID,sCfg) 
    if nChatType == 0 then   -- 获取token
        ChatLogonRsp(sClientID,nUserId,0,token,sCfg)
        return
    end
	local tChat = ChatManager._GetChat(sTableId)
	if not tChat then
        tBase.Log("ChatLogonReq  登陆失败 nUserId_%d sTableId: %s   tChat is nil ",nUserId,sTableId)   
        return
	end
    local tUser = UserManager.CreateUser(nUserId)
    ClientIdMgr.BuildContact(sClientID,nUserId)      --关联连接与玩家id
    local accid = _GetUserAccid(nUserId)
    tUser.accid = accid
    tUser.tid = tChat.tid
    tUser.token = token
    tUser.sClientID = sClientID
    tUser:_SetIMData(tUser.accid,token,tUser.tid)
    tUser:SetNowTable(nUserId,sTableId)
    tChat:AddUser(tUser)
    return 1
end

local function PushWaringInfo(SendSMS)
	tBase._OnMonitorInfo(SendSMS)
	tBase.Log("_PushWaringInfo  %s ",SendSMS)	 
end
 
--登陆请求
function ChatHandle.ChatLogonReq(sClientID, Data, nLen)
    local tData =ChatAux:Parser(Data, nLen, "ChatLogonReq")
    if tData ==nil then
        tBase.Log("ChatLogonReq _Parse Err")
        return
    end
    local nChatType = tData.nChatType  -- 聊天类型: 0:获取token, 1牌桌聊天,2: 俱乐部聊天
    local sTableId = tData.sTableId or ""
    local nUserId = math.floor(tData.nUserId)
    tBase.Log("_ChatLogonReq nUserId_%d nChatType:%d sTableId:%s ",tData.nUserId,nChatType,sTableId)
    if nUserId < 0 then return 1 end
	local tUserInfo = PublicUserInfo.GetUserInfo(nUserId)
    if not tUserInfo then
        tBase.Log("_ChatLogonReq  登陆失败 nUserId_%d  sTableId:%s   Redis User is nil ", nUserId, sTableId)
        return
    end
    local accid = _GetUserAccid(nUserId)
    local token = GetUserToken(nUserId,tUserInfo.sNickName,tUserInfo.sFaceID)
    if not token then
        local sNickName = GetNickName(tUserInfo.sNickName)
        local sBody = string.format("RegisterAccount?accid=%s&name=%s&headUrl=%s",accid,sNickName,tUserInfo.sFaceID)
        local sUrl =IMMessage.sUrl..sBody
        tBase.Log("_ChatLogonReq   要注册IM账号 accid_%s  sUrl: %s ",accid,sUrl)
        local funcRes = function(sData,nCode)
            local isSuccee,tRlt = pcall(cjson.decode,sData)
            if not isSuccee then
                local SendSMS = string.format("注册IM账号 解析失败_%s  sUrl:%s ",sData,sUrl)
                PushWaringInfo(SendSMS)
                return
            end
            if tonumber(tRlt.code) == 414 then
                local msg =  tRlt.msg
                if msg == "already register" then     -- 已注册, 重新刷新token  
                    local sBody = string.format("UpdateToken?accid=%s",accid)
                    local sUrl =IMMessage.sUrl..sBody    
                    tBase.Log("_ChatLogonReq   nUserId_%d  已注册,重新刷新token sUrl_%s",nUserId,sUrl)
                    local Token_Update = function(sData,nCode)   
                        local isSuccee,tRlt = pcall(cjson.decode,sData) 
                        if not isSuccee or tonumber(tRlt.code) ~= 200 then 
                            local SendSMS = string.format("刷新token 解析失败_%s  sUrl:%s ",sData,sUrl)
                            PushWaringInfo(SendSMS)
                            return
                        end
                        token = tRlt.token
                        local sKey = "Chat_IM_Token"
                        local tRedis =tBase.m_MyRedisData[2].redis
                        tRedis:hset(sKey,accid,token)
                        local tRedis1 =tBase.m_MyRedisData[1].redis
                        local val = os.date("%Y-%m-%d %H:%M:%S")
                        tRedis1:setex(_GenTokenExKey(accid), 43000, val)
                        
                        tBase.Log("_ChatLogonReq   nUserId_%d  成功刷新token:%s ",nUserId,token)
                        LogonChat(nUserId,sTableId,nChatType,token,sClientID)
                        return 1
                    end
                    local funcErr1 = function(nCode)
                        local SendSMS = string.format("注册IM账号 超时失败  sUrl:%s ",sUrl)
                        -- PushWaringInfo(SendSMS)   
                        ChatLogonRsp(sClientID,nUserId,1,SendSMS)
                    end
                    HttpNB.request(sUrl,Token_Update,funcErr1,"GET","")
                    return
                elseif msg == "Exceed the maximum account 7385" then
                    local SendSMS = string.format("注册IM账号 超限_%s ",sData)
                    -- PushWaringInfo(SendSMS)  
                    ChatLogonRsp(sClientID,nUserId,1,SendSMS.." Exceed the maximum account"..sTableId)
                else
                    local SendSMS = string.format("注册IM账号失败_%s  sUrl: %s ",sData,sUrl)
                    -- PushWaringInfo(SendSMS)   
                    ChatLogonRsp(sClientID,nUserId,1,SendSMS)
                end
                return
            end
            tBase.Log("_ChatLogonReq  注册IM账号成功 nUserId_%d  sUrl: %s   ",nUserId,sUrl)
            token = tRlt.token
            local sKey = "Chat_IM_Token"
            local tRedis =tBase.m_MyRedisData[2].redis
            tRedis:hset(sKey,accid,token)
            local tRedis1 =tBase.m_MyRedisData[1].redis
            local val = os.date("%Y-%m-%d %H:%M:%S")
            tRedis1:setex(_GenTokenExKey(accid), 43000, val)
            LogonChat(nUserId,sTableId,nChatType,token,sClientID)
            return 1
        end
        local funcErr = function(nCode)
            local SendSMS = string.format("注册IM账号 超时失败  sUrl: %s ",sUrl)   	                 
            PushWaringInfo(SendSMS)   
        end
        HttpNB.request(sUrl,funcRes,funcErr,"GET","") 	
        return
    end
    if nChatType == 0 then
        local sClientID = tUserInfo.sClientID or sClientID 
        tBase.Log("_ChatLogonReq  获取token nUserId_%d  token: %s  ",tData.nUserId,token)   
        local ChatLogonRsp = {} 
        ChatLogonRsp.nRlt = 0
        ChatLogonRsp.accid = accid
        ChatLogonRsp.token = token        
        SendToClient(sClientID,"ChatLogonRsp",ChatLogonRsp)  
        return 
    end 
    local tUser = UserManager.GetUserInfo(nUserId)
    if nChatType == 1 and tUser then
        if tUser.sTableId ~= sTableId then
            tBase.Log("_ChatLogonReq  还有缓存,先清除了再登录 nUserId_%d  sTableId: %s tid_%s  token: %s  ",tUser.nUserId,tUser.sTableId,tUser.tid,tUser.token)    
            UserLeave(nUserId)
        else 
            local tChat = ChatManager._GetChat(sTableId)
            if not tChat then 		  
                ChatLogonRsp(sClientID,nUserId,1, "tChat is nil sTableId: "..sTableId) 
                return 
            end   
            tBase.Log("_ChatLogonReq   nUserId_%d  tid_%s 重连: %s ",nUserId,tUser.tid,sTableId)    
        end 
    end    
    local tChat = ChatManager._GetChat(sTableId)
	if not tChat then  
        ChatLogonRsp(sClientID,nUserId,1, "tChat is nil sTableId: "..sTableId) 
        return
	end
    LogonChat(nUserId,sTableId,nChatType,token,sClientID,cjson.encode(tChat.arrChatChangeCfg))
    return 0
end

local function VedioChatLogonRsp(sClientID,nUserId,nRlt,sErr,vTid)
    local ChatVedioLogonRsp = {}
    ChatVedioLogonRsp.nRlt = nRlt
    ChatVedioLogonRsp.token = sErr
    ChatVedioLogonRsp.vTid = vTid
    SendToClient(sClientID,"ChatVedioLogonRsp",ChatVedioLogonRsp)
    tBase.Log("ChatVedioLogonRsp  nUserId_%d nRlt_%d  sErr_%s vTid:%s",nUserId,nRlt,sErr,vTid or "")
end

local function LogonVedioChat(nUserId,sTableId,nChatType,token,sClientID)
	local tChat = ChatManager._GetChat(sTableId)
	if not tChat then
        tBase.Log("LogonVedioChat  登陆失败 nUserId_%d sTableId:%s   tChat is nil ",nUserId,sTableId)
        return
	end
    local vTid = string.format("%d", tChat.sTable_cid)
    if nChatType == 0 then   -- 获取token
        VedioChatLogonRsp(sClientID,nUserId,0,token,vTid)
    end
    local tUser = UserManager.GetUserInfo(nUserId)
    if tUser == nil then
        tBase.Log("LogonVedioChat  登陆失败 nUserId_%d sTableId:%s   tUser is nil ",nUserId,sTableId)
        return
    end
    tUser:_SetVTokenData(token)
    tChat:SetUserInfo({["vToken"] = token})
    return 1
end

--获取语聊房间token
function ChatHandle.ChatVedioLogonReq(sClientID, Data, nLen)
    local tData =ChatAux:Parser(Data, nLen, "ChatVedioLogonReq")
    if tData == nil then
        tBase.Log("ChatVedioLogonReq _Parse Err")
        return
    end
    local nChatType = tData.nChatType or 0  -- 聊天类型: 0:获取token
    local sTableId = tData.sTableId or ""
    local nUserId = math.floor(tData.nUserId)
    tBase.Log("ChatVedioLogonReq   nUserId_%d  nChatType:%d  %s",tData.nUserId,nChatType,sTableId)
    if nUserId < 0 then return 1 end
	local tUserInfo = PublicUserInfo.GetUserInfo(nUserId)
    if not tUserInfo then
        tBase.Log("ChatVedioLogonReq  登陆失败 nUserId_%d  %s  Redis User is nil ",nUserId,sTableId)
        return
    end
    local tChat = ChatManager._GetChat(sTableId)
	if not tChat then
        VedioChatLogonRsp(sClientID,nUserId,1, "tChat is nil sTableId: "..sTableId)
        return
	end
    local isVideoFee, nVideoFee = tChat:GetFeeConfig()
    if not isVideoFee then
        VedioChatLogonRsp(sClientID,nUserId,2, "tChat not open sTableId: "..sTableId)
        return
    end
    local vToken = GetUserToken(nUserId,tUserInfo.sNickName,tUserInfo.sFaceID, true)
    if not vToken then
        local sBody = string.format("GetVoiceVideoRoomToken?uid=%d&tname=%s",nUserId, sTableId)
        local sUrl =IMMessage.sUrl..sBody
        tBase.Log("ChatVedioLogonReq   要获取token nUserId:%d  sUrl:%s",nUserId, sUrl)
        local funcRes = function(sData,nCode)
            local isSuccee,tRlt = pcall(cjson.decode,sData)
            if not isSuccee then
                local SendSMS = string.format("要获取token 解析失败_%s  sUrl:%s ",sData,sUrl)
                PushWaringInfo(SendSMS)
                return
            end
            local code = tonumber(tRlt.code)
            if code == 414 or code == 40004 then
                local msg = tRlt.msg
                local SendSMS = string.format("获取token失败:%s  sUrl:%s",sData,sUrl)
                VedioChatLogonRsp(sClientID,nUserId,1,SendSMS)
                return
            end
            tBase.Log("ChatVedioLogonReq  要获取token nUserId_%d  sUrl:%s",nUserId,sUrl)
            vToken = tRlt.token
            local sKey = "Chat_IM_Token"
            local tRedis =tBase.m_MyRedisData[2].redis
            local accid = string.format("%d", _GetUserUid(nUserId))
            tRedis:hset(sKey,accid,vToken)
            local tRedis1 =tBase.m_MyRedisData[1].redis
            local sKey2 = _GenExKey(nUserId)
            local val = os.date("%Y-%m-%d %H:%M:%S")
            tRedis1:setex(sKey2, 43000 ,val)      --有效时间
            LogonVedioChat(nUserId,sTableId,nChatType,vToken,sClientID)
            return 1
        end
        local funcErr = function(nCode)
            local SendSMS = string.format("获取token 超时失败  sUrl: %s ",sUrl)
            PushWaringInfo(SendSMS)
        end
        HttpNB.request(sUrl,funcRes,funcErr,"GET","")
        return
    end
    if nChatType == 0 then
        local sClientID = tUserInfo.sClientID or sClientID
        local ChatVedioLogonRsp = {}
        ChatVedioLogonRsp.nRlt = 0
        ChatVedioLogonRsp.nChatType = nChatType
        ChatVedioLogonRsp.token = vToken
        ChatVedioLogonRsp.vTid = string.format("%d", tChat.sTable_cid)
        tBase.Log("ChatVedioLogonReq  获取token nUserId_%d  token:%s  vTid:%s",tData.nUserId, vToken, ChatVedioLogonRsp.vTid)
        SendToClient(sClientID,"ChatVedioLogonRsp",ChatVedioLogonRsp)
        return
    end
    local tUser = UserManager.GetUserInfo(nUserId)
    if nChatType == 1 and tUser then
        if tUser.sTableId ~= sTableId then
            tBase.Log("_ChatLogonReq  还有缓存,先清除了再登录 nUserId_%d  sTableId: %s tid_%s  token: %s  ",tUser.nUserId,tUser.sTableId,tUser.tid,tUser.token)    
            UserLeave(nUserId)
        else
            local tChat = ChatManager._GetChat(sTableId)
            if not tChat then
                VedioChatLogonRsp(sClientID,nUserId,1, "tChat is nil sTableId: "..sTableId)
                return
            end
            tBase.Log("_ChatLogonReq   nUserId_%d  tid_%s 重连: %s ",nUserId,tUser.tid,sTableId)
        end
    end
    LogonVedioChat(nUserId,sTableId,nChatType,vToken,sClientID)
    return 0
end

--网关 连接关闭通知
function ChatHandle.OnClose(sClientID, Data, nLen)
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
        tBase.Log("_OnClose 连接关闭通知  nUserId is nil  sClientID_%s ",sClientID)
        return
    elseif nUserId < 0  then 
        tBase.Log("_OnClose 连接关闭通知 nUserId_%d  < 0 ",nUserId)
        ClientIdMgr.DestroyClientID(sClientID)
        return
    end    
    tBase.Log("_OnClose 连接关闭通知 nUserId_%d  ",nUserId)    
    UserLeave(nUserId) 
    return 1
end
 
--网关 连接切换通知
function ChatHandle.OnSwicthConn(sClientID, Data, nLen)
    local ReadData = tBase.GetRP().new(Data, nLen)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID()
    local Read = ProtoManager.Gateway_pb.RUQ_SwicthConn()
    Read:ParseFromString(ReadData:GetString())
    local nUserId =Read.nUserID or -1
    local oldClientId =ClientIdMgr.GetClientIdByUserId(nUserId)
    if not oldClientId then return end
    return 1
end

--返回大厅
function ChatHandle.ChatBackToLobbyReq(sClientID, Data, nLen)
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
        tBase.Log("ChatBackToLobbyReq 返回大厅  nUserId is nil  sClientID_%s ",sClientID)
        return
    end
    tBase.Log("ChatBackToLobbyReq  返回大厅  nUserId_%d ",nUserId)
    UserLeave(nUserId)
    return 1
end

local function extractContet(str, prefix)
    str = str:gsub("^" .. prefix, "")
    return str:match("^[^&]+")
end

--聊天请求
function ChatHandle.ChatChangeReq(sClientID, Data, nLen)
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        tBase.Log("_ChatChangeReq 聊天请求 nUserId_%d   tUser is nil  ",nUserId)
        return
    end
    local tData =ChatAux:Parser(Data, nLen,"ChatChangeReq")
    if tData ==nil then
        tBase.Log("_ChatChangeReq  _Parse Err nUserId: "..nUserId)
        return
    end
    local function ChatChangeRsp(sClientID,nUserId,nRlt,tData)
        local ChatChangeRsp = {}
        ChatChangeRsp.nRlt = nRlt 
        ChatChangeRsp.nType =tData.nType
        ChatChangeRsp.sStr = tData.sStr
        SendToClient(sClientID,"ChatChangeRsp",ChatChangeRsp)
        if nRlt ~= 0 then
            tBase.Log("_ChatChangeRsp  nUserId_%d nRlt_%d nType_%s ",nUserId,nRlt,tData.nType)
        end
        return 1
    end
    local tChat = ChatManager._GetChat(tUser.sTableId)
	if not tChat then
        tBase.Log("_ChatChangeReq  nUserId_%d sTableId_%s  tChat is nil ",nUserId,tUser.sTableId)
        ChatChangeRsp(sClientID,nUserId,2,tData)
        return
	end
    if tData.nType == 1 then  -- 弹幕扣费 
        local nCost =tChat:_GetChatCost(tData.nChatId)
        tChat:Print("_ChatChangeReq nUserId_%d nChatId_%d  Cost:%.2f",nUserId,tData.nChatId,nCost)
        --扣金币
        if nCost>0 then
            local nUnLockGold = PublicUserInfo.Get_User_UnLockGold(nUserId,1)
            if nUnLockGold and nUnLockGold < nCost then    
                tChat:Print("_ChatChangeReq Chat Fail,no Gold nUserID_%d nCost_%d > nUnLockGold_%.2f",nUserId,nCost,nUnLockGold)
                ChatChangeRsp(sClientID,nUserId,1,tData)
                return
            end
            if not PublicUserInfo.ChangeUserTreasure({nUserID=nUserId,nItemID=1,nDel=-nCost,nSourceType=99}) then
                tChat:Print("_ChatChangeReq Chat Fail,no Gold nUserID_%d nCost_%.2f ",nUserId,nCost) 
                ChatChangeRsp(sClientID,nUserId,1,tData)
                return
            end
        end
        ChatChangeRsp(sClientID,nUserId,0,tData)
        return
    else
        -- tBase.Log("_ChatChangeReq  nUserId_%d Error nType_%s   ",nUserId,tData.nType)
        local tChatMatter = {}
        tChatMatter.nUserId = nUserId
        tChatMatter.sName = tUser.sName or ""
        tChatMatter.nType = tData.nType or 1
        local str = tData.sStr or ""
        local result = extractContet(str, "BTTPOKER")
        tChatMatter.sStr = result
        -- BTTPOKER5om35Lmq5pmL&avatar=1
        tChat:_AddChat(tChatMatter)
    end
end
 
--俱乐部聊天 APPkey 请求 
function ChatHandle.ClubChatAppKeyReq(sClientID, Data, nLen)
    local tData =ChatAux:Parser(Data, nLen,"ClubChatAppKeyReq")
    if tData ==nil then
        tBase.Log("_ClubChatAppKeyReq  _Parse Err ")
        return
    end
    if not GetUserToken(tData.nUserId) then  -- 注册 IM
        local Chat_pb =ProtoManager.Chat_pb
        local Chat_CMD =ProtoManager.Chat_pb.Chat_Proto()
        local Send = Chat_pb.ChatLogonReq()
        Send.nUserId = tData.nUserId
        Send.nChatType = 0
        local s = tBase.GetSP().new(Chat_CMD.Main_CMD,Chat_CMD.ChatLogonReq_CMD)
        s:AddString(Send:SerializeToString())
        tBase.PostDatasByType(tname.chat, 0, 0, s:GetData(), s:GetSize())
        tBase.Log("_ClubChatAppKeyReq  nUserId_%d   没有token ",tData.nUserId)
    end
    local sAppKey = RedisCahche.GetPayDomainName("appKey")
    local ClubChatAppKeyRsp = {}
    ClubChatAppKeyRsp.sAppKey = sAppKey or ""
    SendToClient(sClientID,"ClubChatAppKeyRsp",ClubChatAppKeyRsp)
    tBase.Log("ClubChatAppKeyReq    sAppKey: %s    ",sAppKey)
    return
end


--登录直播聊天
function ChatHandle.LogonZhiBoReq(sClientID, Data, nLen)
    local tData =ChatAux:Parser(Data, nLen, "LogonZhiBoReq")
    if tData ==nil then
        tBase.Log("_LogonZhiBoReq _Parse Err")
        return
    end
    
    local sTableId = tData.sTableId or ""
    local nUserId = math.floor(tData.nUserId)

    local nGroupId = -1
    local tUserInfo = PublicUserInfo.GetUserInfo(nUserId)
    if tUserInfo then
        nGroupId = tUserInfo.nGroupId or -1
    end
    
    local sSwitchChatConfig = tPublicRedis.Get_SwitchChatConfig(nGroupId)
    tBase.Log("_LogonZhiBoReq sSwitchChatConfig_%s",sSwitchChatConfig)
    if not sSwitchChatConfig then 
        local LogonZhiBoRsp = {} 
        LogonZhiBoRsp.nRlt = -1  
        SendToClient(sClientID,"LogonZhiBoRsp",LogonZhiBoRsp)   
        tBase.Log("_LogonZhiBoReq   nUserId_%d  sTableId: %s  后台没有设置开通聊天 ",nUserId,sTableId)     
        return 
    end

    local tUser = UserManager.GetUserInfo(nUserId)
    if tUser then   
        local tOldChat = ChatManager._GetChat(tUser.sTableId)
        if tOldChat then   
            if tUser.sTableId ~= sTableId then
                tBase.Log("_LogonZhiBoReq   nUserId_%d  sTableId: %s 切换牌桌 %s ",nUserId,sTableId,tUser.sTableId)   
                tOldChat:DelZhiBoUser(nUserId)  
            else
                local LogonZhiBoRsp = {} 
                LogonZhiBoRsp.nRlt = 0  
                LogonZhiBoRsp.arrChatRecord =tOldChat:_GetChatMastter()        --  历史记录
                SendToClient(sClientID,"LogonZhiBoRsp",LogonZhiBoRsp)   
                tBase.Log("_LogonZhiBoReq   nUserId_%d  sTableId: %s  重连 ",nUserId,sTableId)     
                return 
            end                 
        end 
    end 
	
              
    tBase.Log("_LogonZhiBoReq   nUserId_%d  sTableId: %s 登录直播聊天 ",nUserId,sTableId)  
	local tChat = ChatManager._GetChat(sTableId)
	if not tChat then 		   
        tBase.Log("_LogonZhiBoReq  登陆失败 nUserId_%d sTableId: %s  tChat is nil ",nUserId,sTableId)   
        return 
	end 
    local tUser = UserManager.CreateUser(nUserId) 
    ClientIdMgr.BuildContact(sClientID,nUserId)      --关联连接与玩家id
    tUser:SetNowTable(nUserId,sTableId)
    tChat:AddZhiBoUser(tUser)    

    local LogonZhiBoRsp = {} 
    LogonZhiBoRsp.nRlt = 0  
    LogonZhiBoRsp.arrChatRecord =tChat:_GetChatMastter()        --  历史记录
    SendToClient(sClientID,"LogonZhiBoRsp",LogonZhiBoRsp)  
    return
end

--直播聊天请求
function ChatHandle.ZhiBoChatReq(sClientID, Data, nLen)
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then 
        tBase.Log("_ZhiBoChatReq  nUserId_%d   tUser is nil sClientID: %s  ",nUserId or -1,sClientID)
        return    
    end 
    local tData =ChatAux:Parser(Data, nLen, "ZhiBoChatReq")
    if tData ==nil then
        tBase.Log("_ZhiBoChatReq   _Parse Err")
        return
    end
    local tChat = ChatManager._GetChat(tUser.sTableId)
	if not tChat then
        tBase.Log("_ZhiBoChatReq  nUserId_%d sTableId_%s  tChat is nil ",nUserId,tUser.sTableId)      
        local ZhiBoChatRsp = {}
        ZhiBoChatRsp.nRlt = -1
        SendToClient(sClientID,"ZhiBoChatRsp",ZhiBoChatRsp) 
        return 
	end   
    local tChatMatter = {}
    tChatMatter.nUserId = nUserId
    tChatMatter.sName = tUser.sName or ""
    tChatMatter.nType = tData.nType or 1 
    tChatMatter.sStr = tData.sStr or ""

    local ZhiBoChatRsp = {}
    ZhiBoChatRsp.nRlt = 0
    SendToClient(sClientID,"ZhiBoChatRsp",ZhiBoChatRsp)
    local ChatNotify = {}
    ChatNotify.tChatMatter = tChatMatter
    local nCnt = 0
    for nId, tUser in pairs(tChat.arrUser) do
        if tUser.sClientID then
            nCnt = nCnt + 1
            SendToClient(tUser.sClientID,"ChatNotify",ChatNotify)
        end
    end
    tChat:_AddChatMastter(tChatMatter)
    tBase.Log("_ZhiBoChatReq sTableId: %s  内容:%s ",tUser.sTableId,cjson.encode(tChatMatter))
end

--开桌与关桌
function ChatHandle.VideoRoomLeaveNotice(sReturnKey,Data,nLen)
    local s = tBase.GetRP().new(Data, nLen)
    local nMainID = s:GetModuleID()
    local nSubID = s:GetMsgID()
    local tRead = ProtoManager.Backstage_pb.VideoRoomLeaveNotice()
    tRead:ParseFromString(s:GetString())
    local tData = {}
    tData.nUserId = tonumber(tRead.accId) or 0
    tData.nTime = tonumber(tRead.nTime) or 0
    tData.sTableId = tRead.channelName

    if tData.nTime == 0 then
        return
    end

    tBase.LogT("VideoRoomLeaveNotice", tData)

    local tChat = ChatManager._GetChatByCid(tData.sTableId)
	if not tChat then
        tBase.Log("VideoRoomLeaveNotice nUserId_%d sTableId_%s  tChat is nil",tData.nUserId, tData.sTableId)
        return
	end
    local isVideoFee, nVideoFee = tChat:GetFeeConfig()
    tBase.Log("VideoRoomLeaveNotice sTableId_%s isVideoFee:%s nVideoFee:%.4f",tData.sTableId, tostring(isVideoFee or false), nVideoFee)
    if not isVideoFee or nVideoFee <= 0 then
        return
    end
    local nCost = publicApi.Ceil_n((tData.nTime / 60) * nVideoFee, 3)
    tBase.Log("VideoRoomLeaveNotice sTableId_%s nCost:%.3f nVideoFee:%.4f",tData.sTableId, nCost, nVideoFee)
    local tUser = PublicUserInfo.GetUserInfo(tData.nUserId) or {}
    if next(tUser) == nil then -- 离线玩家操作
        PublicUserInfo.ChangeUserDbGold(tData.nUserId, -nCost, 1, 100, 0, "", 0, tChat.sTableId, "", {sTableId = tChat.sTableId})
    else
        local ok = PublicUserInfo.ChangeUserTreasure({
                nUserID = tData.nUserId,
                nItemID = 1,
                nDel = -nCost,
                nSourceType = 100,
                sTableId = tChat.sTableId,
                exData = {sTableId = tChat.sTableId}
            })
        if not ok then
            tBase.Log("VideoRoomLeaveNotice Chat Fail,no Gold nUserID_%d nCost_%.4f tChat.sTableId:%s",tData.nUserId, nCost, tChat.sTableId)
            return
        end
    end
end

tInterface.UserLeave=UserLeave
tInterface.SendToClient=SendToClient
tInterface.UserEnterTable=UserEnterTable
tInterface.UserLeaveTable=UserLeaveTable


return ChatHandle
