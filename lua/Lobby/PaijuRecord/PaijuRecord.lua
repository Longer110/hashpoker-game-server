 package.path = require("./lua/Lobby/Head").path

local tBase = require("base") -- 基础功能接口
local tname = require("typename") -- 类弄定义接口
local tApi = require("publicApi") -- 共用功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local cjson = require("cjson") -- 数据交换格式
local tPubUserApi  = require("PublicUserInfo") --玩家数据

PaijuRecord = {

} 

function PaijuRecord.GetList(sClientID, Data, Len)

    local ReadData = base.GetRP().new(Data, Len)
	local nMainId = ReadData:GetModuleID()
	local nSubId = ReadData:GetMsgID()
    local Read = ProtoMgr.Lobby_pb.REQ_Paiju_Record()
    Read:ParseFromString(ReadData:GetString())
	local nUserID = Read.nUserID
    assert(nUserID~=nil,"nUserID nil,PaijuRecord Err must happen")
    local nPages = Read.nPage
    assert(nPages~=nil,"nPages nil,PaijuRecord Err must happen")
    -- local nCollect = Read.nCollect
    
	tBase.Log(" 接受到玩家%d的历史列表请求，第%d页 ",nUserID, nPages )
    
    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_GET_RECORD_LIST) 
    local pSend = ProtoMgr.PubProto_pb.RUQ_PaiJuRecord()
    pSend.nClientID = sClientID
    pSend.nUserID = nUserID
    pSend.nPages = nPages 
    s:AddString(pSend:SerializeToString())
	tBase.PostDatasByType(tname.db, 0,nUserID, s:GetData(), s:GetSize())

end

-- 获取牌局列表 返回
function PaijuRecord.SendPaiJuList(ClientID, Data, Len)

    local ReadData = base.GetRP().new(Data, Len)
	local nMainId = ReadData:GetModuleID()
	local nSubId = ReadData:GetMsgID()
 
    local Read = ProtoMgr.PubProto_pb.RUP_PaiJuRecord()
    Read:ParseFromString(ReadData:GetString()) 
    local nClientID = Read.nClientID  
    local nUserID = Read.nUserID
    local nTotal = Read.nTotal
    local nPages = Read.nPages
    local nCount = Read.nCount 

    tBase.Log(" nClientID:"..nClientID.." 玩家nUserID:"..nUserID.." nTotal:"..nTotal.." nPages:"..nPages.."页牌局记录当前条数nCount: "..nCount )
 
    local tSend = ProtoMgr.Lobby_pb.REP_Paiju_Record()
    tSend.nTotal = nTotal
    tSend.nPage = nPages
    tSend.nCount = nCount
  
    for i,v in ipairs(Read.tPaijuStruct) do
		local tPerData = {}
		tPerData.nPaiJuID = Read.tPaijuStruct[i].nPaiJuID
		tPerData.sSession = Read.tPaijuStruct[i].sSession -- 场次
		tPerData.nProfit = Read.tPaijuStruct[i].nProfit -- 输赢rmb
		tPerData.sRecordTime = Read.tPaijuStruct[i].sRecordTime 
   	  	tBase.Log(" 发送牌局记录给客户端：包体第["..i.."]条数据 %s",cjson.encode(tPerData) )
        local arr =  tSend.tPaijuStruct:add()  
        arr.nPaiJuID = tPerData.nPaiJuID
        arr.nRoomType = tPerData.sSession
        arr.nWinCount = tPerData.nProfit
        arr.sJiesuanTime = tPerData.sRecordTime 
    end
  
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_PAIJU_RECORD) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(nClientID, nClient:GetData(), nClient:GetSize())   
	tBase.Log(" 返回牌局历史的列表给客户端：打印size:"..nClient:GetSize() )

end


function PaijuRecord.ReadRecord(ClientID, Data, Len)
    local ReadData = base.GetRP().new(Data, Len)
	local nMainId = ReadData:GetModuleID()
	local nSubId = ReadData:GetMsgID()
    local nPaiJuId = ReadData:GetInt32()
    
	
	tBase.Log("接受到%s的历史牌局请求，牌局ID为%d",ClientID,nPaiJuId)
    
 --    local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_READ_RECORD)
 --    local sPaiJuId =tostring(nPaiJuId)
	-- s:AddString(sPaiJuId)
	-- s:AddString(ClientID)
	-- tBase.PostDatasByType(tName.db, 0,0, s:GetData(), s:GetSize())
end

-- 获取一条牌局记录
function PaijuRecord.ReReadRecord(ClientID, Data, Len)
    local ReadData = base.GetRP().new(Data, Len)
	local nMainId = ReadData:GetModuleID()
	local nSubId = ReadData:GetMsgID()
    local sClientID = ReadData:GetString()
	local nArr = ReadData:GetInt32()
	local sData = ""
	for i=1,nArr do 
		sData = sData..ReadData:GetString()
	end

	local arrInfo =cjson.decode(sData)

	--tBase.Log("nMainId = %d ,nSubId = %d ,sClientID = %s ",nMainId,nSubId,sClientID)
    -- local s = tBase.GetSP().new(tPubProto.MAIN.SYSLOBBY, tPubProto.SubLobby.SUB_REP_READ_RECORD)
	--tBase.Log("sData = %s",sData)

	
	-- s:AddString(arrInfo[1])
	-- s:AddString(arrInfo[2])
	-- s:AddString(arrInfo[3])
	-- s:AddString(arrInfo[4])
	-- s:AddString(arrInfo[5])
	-- s:AddString(arrInfo[6])
	-- s:AddString(arrInfo[7])
	-- s:AddString(arrInfo[8])
	-- s:AddString(arrInfo[9])
	-- s:AddInt32(arrInfo[10])
	-- s:AddString(arrInfo[11])

	--[[
	s:AddString(PaijuRecord.StrValue(sData, 1))
	s:AddString(PaijuRecord.StrValue(sData, 2))
	s:AddString(PaijuRecord.StrValue(sData, 3))
	s:AddString(PaijuRecord.StrValue(sData, 4))
	s:AddString(PaijuRecord.StrValue(sData, 5))
	s:AddString(PaijuRecord.StrValue(sData, 6))
	s:AddString(PaijuRecord.StrValue(sData, 7))
	s:AddString(PaijuRecord.StrValue(sData, 8))
	s:AddString(PaijuRecord.StrValue(sData, 9))
	s:AddInt32(tonumber(PaijuRecord.StrValue(sData, 10)))
	s:AddString(PaijuRecord.StrValue(sData, 11))
	]]

	tBase.Log("返回仔细的历史牌局")

	-- tBase.PostToGateway(sClientID,s:GetData(), s:GetSize())

end


function PaijuRecord.HandleCollect(ClientID, Data, Len)

    local ReadData = base.GetRP().new(Data, Len)
	local nMainId = ReadData:GetModuleID()
	local nSubId = ReadData:GetMsgID()
    local nUsrId = ReadData:GetInt32()
    local nPaiJuId = ReadData:GetInt32()
    local nCollectFlag = ReadData:GetInt32()
    
	tBase.Log("玩家%d的牌局%d收藏处理：%d",nUsrId,nPaiJuId,nCollectFlag)
    
 --    local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_COLLECT)
 --    --local sUsrId =tostring(nUsrId)
	-- s:AddInt32(nUsrId)
	-- s:AddInt32(nPaiJuId)
	-- s:AddInt32(nCollectFlag)
	-- s:AddString(ClientID)
	-- tBase.PostDatasByType(tName.db, 0,nUsrId, s:GetData(), s:GetSize())
end


function PaijuRecord.ReHandleCollect(ClientID, Data, Len)

    local ReadData = base.GetRP().new(Data, Len)
	local nMainId = ReadData:GetModuleID()
	local nSubId = ReadData:GetMsgID()
    local nPaiJuId = ReadData:GetInt32()
    local nReturn = ReadData:GetInt32()   
    local sClientID = ReadData:GetString()
    
	tBase.Log("返回 牌局%d收藏处理：%d",nPaiJuId,nReturn)
    
 --    local s = tBase.GetSP().new(tPubProto.MAIN.SYSLOBBY, tPubProto.SubLobby.SUB_REP_COLLECT)
	-- s:AddInt32(nPaiJuId)
	-- s:AddInt32(nReturn)
	-- tBase.PostToGateway(sClientID,s:GetData(), s:GetSize())
end


--从一行里面提取值
function PaijuRecord.StrValue(sStr, nPages)
	local nPageStart
	local nPageEnd = - 1
	
	for i = 1, nPages do
		nPageStart = nPageEnd	
		nPageStart = nPageStart + 1
		nPageEnd = string.find(sStr, "}", nPageStart)		
	end
	return string.sub(sStr, nPageStart, nPageEnd - 1)
	
end

--从全部数据里面提取一行
function PaijuRecord.StrArray(sStr, nPages)
	local nPageStart
	local nPageEnd = - 1
	
	for i = 1, nPages do
		nPageStart = nPageEnd	
		nPageStart = nPageStart + 1
		nPageEnd = string.find(sStr, "{", nPageStart)
	end
	--tBase.Log("sStr = %s",sStr)
	tBase.Log("%d,%d",nPageStart,nPageEnd)
	return string.sub(sStr, nPageStart, nPageEnd - 1)
	
end

return PaijuRecord