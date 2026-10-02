
--[[用户聊天 针对更多的情况，允许聊天，不允许聊天情况，牌桌聊，大厅聊，跨服聊,支持用户定制
	聊天 更多情况]]

package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path

local tBase 	= require("base")
local tName 	= require("typename")
local tApi      = require("publicApi")
local tSrvInfo  = require("ServerInfo")

ChatChanel = {
	nMax = 3, --最多承载3台服务器的聊天,日后serverId按照从1开始排列

	enumErrCode = 
	{			
		nNoFind = -1,	--没找到聊天服
		nSuccess = 0,	--成功
	},

	enumMode =
	{
		nPub	= 1,	--本服公聊
		nTable  = 2, 	--本桌公聊
	},
}


function ChatChanel.GetDispatchKey(nSrvId)

	tBase.Log("  GetDispatchKey     nSrvId:   "..nSrvId)
	local sKey = tBase.GetSrcKey(tName.chat, nSrvId+1)
	if sKey ~= nil then
		return ChatChanel.enumErrCode.nSuccess, sKey
	end

	return ChatChanel.enumErrCode.nNoFind, ""
end

function ChatChanel.OpenChat(sClientId, tData)
	local nErrCode, sKey = ChatChanel.GetDispatchKey(tSrvInfo.nServerId)

	-- if nErrCode ~= ChatChanel.enumErrCode.nSuccess then
	-- 	tBase.Log("  Error_Info==167")
	-- 	return
	-- end

	-- local s = tBase.GetSP().new(tPubProto.MAIN.CHAT, tPubProto.SUB_CHAT.SUB_REQ_OPENCHAT)
	-- s:AddInt32(tData.nUserId)
	-- s:AddString(tData.sName)
	-- s:AddInt32(tData.nGender)
	-- s:AddInt32(tData.nSitId)
	-- tBase.PostToGateway(sClientId, s:GetData(), s:GetSize())

	tBase.Log("玩家开启聊天:"..sKey)
end



--tData = {Mode=2, SData=""}
function ChatChanel.ChooseMode(sClientId, tData)
	local nErrCode, sKey = ChatChanel.GetDispatchKey(tSrvInfo.nServerId, tBase.m_tType)

	tBase.Log("玩家开启聊天:"..sKey)

	-- if nErrCode ~= ChatChanel.enumErrCode.nSuccess then
	-- 	tBase.Log("  Error_Info==169")
	-- 	return
	-- end

	-- if tData["Mode"] < ChatChanel.enumMode.nPub or tData["Mode"] > ChatChanel.enumMode.nTable then
	-- 	tBase.Log("  Error_Info==170")
	-- 	return
	-- end

	-- local s = tBase.GetSP().new(tPubProto.MAIN.CHAT, tPubProto.SUB_CHAT.SUB_REQ_CHOOSEMODE)
	-- s:AddInt32(tData["Mode"])
	-- s:AddString(tData["SData"])
	-- tBase.PostToGateway(sClientId, s:GetData(), s:GetSize())
end

function ChatChanel.Chat(sClientID, sData, nLen)
	local ReadData = base.GetRP().new(sData, nLen)
    local nSystemID = ReadData:GetModuleID()
    local nNewsID = ReadData:GetMsgID()

    local nChatType  = ReadData:GetInt32()
    local nTopicType = ReadData:GetInt32()
    local sTopic     = ReadData:GetString()

    local s = tBase.GetSP().new(tPubProto.MAIN.CHAT, tPubProto.SUB_CHAT.SUB_REQ_CHAT)
	s:AddInt32(nChatType)
	s:AddInt32(nTopicType)
	s:AddString(sTopic)
	tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())

    tBase.Log(" ChatChanel  玩家聊天 sClientID: %s  %d ,  %d ,  %s ",sClientID,nChatType ,nTopicType,sTopic)
end

return ChatChanel

