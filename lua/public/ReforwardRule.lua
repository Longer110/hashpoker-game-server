
local tBase	= require("base") -- 基础功能接口
local tName	= require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tParserAux = require("ParserAux")
local tLiveCSRelation =require("LiveCSRelation")
local cjson     = require("cjson")        -- json 

local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse


local ReforwardRule={}

local tServIdToIsBan = {}
local tServIdToIsWeiHu = {}

ReforwardRule.tServerIdToGroupList={}
ReforwardRule.tServerIdToState ={}
ReforwardRule.tWhiteList ={}

function ReforwardRule.ServerIdOfKey(sServKey)
	local nServerId =tonumber(string.match(sServKey,"_(%d+)"))
	return nServerId
end

--向db服请求网关转发规则
function ReforwardRule.RefowardRuleReq()	
	local strReq ="RefowardRuleReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    tBase.Log("begin to RefowardRuleReq")
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())    
	return 
end

function ReforwardRule.ServerIdOfMaitainingReq()
	local strReq ="ServerIdOfMaitainingReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    tBase.Log("begin to ServerIdOfMaitainingReq")
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())    
	return 
end

function ReforwardRule.onTimerRefowardRuleReq(nTimerId)
	ReforwardRule.RefowardRuleReq()
	ReforwardRule.ServerIdOfMaitainingReq()
end

--db服返回网关转发规则
function ReforwardRule.OnRefowardRuleRsp(ClientID, Data, Len)
	tBase.Log("OnRefowardRuleRsp")
	local strReq ="RefowardRuleRsp"
    local tData =DbProtoParse(Data, Len,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
	end
	local tServerIdToGroupList ={}
	for _,item in ipairs(tData.arrItems) do
		local nServerId= item.nServerId
		local nGroupId= item.nGroupId		
		tServerIdToGroupList[nServerId] =tServerIdToGroupList[nServerId] or {}
		table.insert(tServerIdToGroupList[nServerId],nGroupId)
	end
	ReforwardRule.tServerIdToGroupList =tServerIdToGroupList
	tBase.LogT("tServerIdToGroupList:",tServerIdToGroupList)
end

--db服返回 不停机维护，被设为维护的serverid
function ReforwardRule.OnServerIdOfMaitainingRsp(ClientID, Data, Len)
	tBase.Log("ServerIdOfMaitainingRsp")
	local strReq ="ServerIdOfMaitainingRsp"
    local tData =DbProtoParse(Data, Len,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
	end
	local tServerIdToState ={}
	for _,item in ipairs(tData.arrItems) do
		tServerIdToState[item.nServerId] =item.nState
	end
	ReforwardRule.tServerIdToState =tServerIdToState
	tBase.LogT("tServerIdToState:",tServerIdToState)
end


function ReforwardRule.WhichGroupBelongTo(sServKey)
	local nServerId =ReforwardRule.ServerIdOfKey(sServKey)
	assert(nServerId~=nil,"nServerId is nil, sServKey:"..(sServKey or "nil"))
	local arrGroupId =ReforwardRule.tServerIdToGroupList[nServerId] or {}
	return arrGroupId
end

--将服务器分成 [专属于某些分组的] 和 [不属于任何分组的]两类
function ReforwardRule.Classify(arrServKey)
	local tGroupIdToKeyList ={}
	local arrNoBelongKey ={}
	for _,sKey in ipairs(arrServKey) do
		local arrGroupId =ReforwardRule.WhichGroupBelongTo(sKey)
		for _,nGroupId in ipairs(arrGroupId) do
			tGroupIdToKeyList[nGroupId] =tGroupIdToKeyList[nGroupId] or {}
			table.insert(tGroupIdToKeyList[nGroupId],sKey)
		end
		if #arrGroupId==0 then
			table.insert(arrNoBelongKey,sKey)
		end
	end
	return tGroupIdToKeyList,arrNoBelongKey
end


--返回跟给定中心服id相关联的游戏服key
function ReforwardRule.SlaveServKeys(arrServKey,nCenterServId)
	local arrSlaveServKey ={}
	for _,sKey in ipairs(arrServKey) do
		local nServerId =ReforwardRule.ServerIdOfKey(sKey)
		if tLiveCSRelation.IsMatch(nServerId,nCenterServId) then	--nServerId是否归属于中心服nCenterServId
			table.insert(arrSlaveServKey,sKey)
		end
	end
	return arrSlaveServKey
end

function ReforwardRule.PickAServKey(arrServKey,nGroupId,nCenterServId,nUserId,stypename)
	local nGroupId =nGroupId or -1
	if nCenterServId then
		-- tBase.Log("_PickAServKey nGroupId_%d nCenterServId: %d  arrServKey: %s ",nGroupId,nCenterServId,cjson.encode(arrServKey))
		arrServKey =ReforwardRule.SlaveServKeys(arrServKey,nCenterServId) 
		-- arrServKey =ReforwardRule.ExcludeMaitainServ(arrServKey)	  -- 过滤是否维护中			
	else
		arrServKey =ReforwardRule.ExcludeMaitainServ(arrServKey)
	end	 
	local tGroupIdToKeyList,arrNoBelongKey =ReforwardRule.Classify(arrServKey)
	-- tBase.Log("_PickAServKey  tGroupIdToKeyList:  %s, arrNoBelongKey: %s arrServKey_%s  "
	-- ,cjson.encode(tGroupIdToKeyList),cjson.encode(arrNoBelongKey),cjson.encode(arrServKey))

	local arrKey =tGroupIdToKeyList[nGroupId] or {}
	if #arrKey >0 then
		local nRandomDex =math.random(1,#arrKey)
		return arrKey[nRandomDex]
	end
	if #arrNoBelongKey>0 then
		table.sort(arrNoBelongKey)
		if nCenterServId then
			local nRandomDex =nUserId%(#arrNoBelongKey) +1
			tBase.Log("_PickAServKey nUserId: %d nGroupId_%d nRandomDex: %d nCnt: %d ",nUserId,nGroupId,nRandomDex,nRandomDex,#arrNoBelongKey)
			return arrNoBelongKey[nRandomDex]
		else
			if stypename == "pilotmslave" then
				local nRandomDex =math.random(1,#arrNoBelongKey)
				tBase.LogT("_PickAServKey nRandomDex_",nRandomDex)
				return arrNoBelongKey[nRandomDex]
			else
				local dex =nGroupId%(#arrNoBelongKey) +1
				tBase.LogT("_PickAServKey dex_",dex)
				return arrNoBelongKey[dex]
			end
		end
	end
	return nil
end

function ReforwardRule.ServerIdFilter(arrServKey)
	if not arrServKey then 
		tBase.LogT("_ServerIdFilter  arrServKey is nil")
		return  
	end 
	local arrRlt ={}
	for _,sServKey in ipairs(arrServKey) do
		if not ReforwardRule.IsServBeBan(sServKey) then
			table.insert(arrRlt,sServKey)
		end
	end
	return arrRlt
end

function ReforwardRule.IsServBeBan(sServKey)
	local nServerId =ReforwardRule.ServerIdOfKey(sServKey) or -1
	if tServIdToIsBan[nServerId] then
		return true
	end
	return false
end

function ReforwardRule.IsServBeWeiHu(sServKey, nServerId)
	nServerId = nServerId or ReforwardRule.ServerIdOfKey(sServKey) or -1
	if tServIdToIsWeiHu[nServerId] then
		return true
	end
	return false
end

-- 是否维护 
function ReforwardRule.IsServMaitain(sServKey)
	local nServerId =ReforwardRule.ServerIdOfKey(sServKey) or -1
	if ReforwardRule.tServerIdToState[nServerId] ==2 then 
		return true
	end
	local nCenterServId =tLiveCSRelation.GetCenterServId(nServerId)
	if nCenterServId and ReforwardRule.tServerIdToState[nCenterServId] ==2 then
		return true
	end
	return false
end

function ReforwardRule.ExcludeMaitainServ(arrServKey)
	local arrRlt ={}
	for _,sServKey in ipairs(arrServKey) do
		if not ReforwardRule.IsServMaitain(sServKey) then
			table.insert(arrRlt,sServKey)
		end
	end
	return arrRlt
end

-- 检测网关是否维护
function ReforwardRule.OnTimerGetServerIdOfBan()
	local redis =tBase.m_MyRedisData[1].redis
	local temMap =redis:hgetall("ServerIdOfBan") or {}
	local copy = tBase.DeepCopy(tServIdToIsWeiHu)
	tServIdToIsBan ={}
	tServIdToIsWeiHu={}
	local isPrint=false
	for sServerId,state in pairs(temMap) do
		local nServerId =tonumber(sServerId)
		local nState =tonumber(state)
		if nServerId then
			if nState ==3 then
				tServIdToIsWeiHu[nServerId]=true
			else
				tServIdToIsBan[nServerId]=true
			end
			isPrint=true
		end
	end
	if isPrint then
		tBase.LogT('tServIdToIsBan:',tServIdToIsBan)
	end
	local targetServerId = 313
	local oldVal = copy[targetServerId]
	local newVal = tServIdToIsWeiHu[targetServerId]

	local isChanged = (oldVal == nil and newVal == true)
	return isChanged
end
 
-- 获取可用的 key(过滤维护)
function ReforwardRule._GetNornalServerKey(stypename)
	local arrServKey =tBase.GetSrcAllKey(stypename)  
	if not arrServKey or #arrServKey <= 0 then 
		tBase.Log("_GetNornalServerKey  stypename: %s 没有key  arrServKey is nil ",stypename)
		return
	end       
	local arrRlt = ReforwardRule.ExcludeMaitainServ(arrServKey)
	local sKey = arrServKey[math.random(1,#arrServKey)]
	if #arrRlt > 0 then 
		sKey = arrRlt[math.random(1,#arrRlt)]
		return sKey
	end  
	tBase.Log("_GetNornalServerKey 没有可用  %d  %d  Random key:  %s ",#arrServKey,#arrRlt,sKey)
	return nil   
end

function ReforwardRule.DbWhitListReq()
	local strReq ="WhiteListReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    tBase.Log("begin to WhiteListReq")
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

function ReforwardRule.ReqDbWhitList(nTimerId)
	tBase.Log("ReqDbWhitList")
	ReforwardRule.DbWhitListReq()
end

--db服返回网关转发规则
function ReforwardRule.OnWhiteListRsp(ClientID, Data, Len)
	tBase.Log("OnWhiteListRsp")
	local strReq ="WhiteListRsp"
    local tData =DbProtoParse(Data, Len,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
	end
	local tWhiteList ={}
	for _, id in pairs(tData.arrUserId or {}) do
		tWhiteList[id] = true
	end
	ReforwardRule.tWhiteList =tWhiteList
	tBase.LogT("tWhiteList:",tWhiteList)
end

function ReforwardRule.IsUserInWhiteList(nUserId)
	if ReforwardRule.tWhiteList[nUserId] then
		return true
	end
	return false
end

return ReforwardRule

