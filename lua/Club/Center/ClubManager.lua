--[[
	负责牌桌管理，创建牌桌，删除牌桌
]]
local ClubManager = {}

ClubManager.arrClub = {}	

--创建俱乐部
--@params nGroupId:分组id  nClubId:俱乐部id
--@retuen tClub
function ClubManager.CreateClub(nGroupId,nClubId)
	if type(nGroupId)~="number" or type(nClubId)~="number" then
		Base.Log("_CreateClub Params Error nGroupId:%s nClubId:%s",tostring(nGroupId),tostring(nClubId))
		return
	end

	nGroupId = math.floor(nGroupId)
	nClubId = math.floor(nClubId)
	local sClubId = string.format("%d",nClubId)
	if ClubManager.arrClub[sClubId] then
		Base.Log("_CreateClub Club is exist,  nGroupId:%d nClubId:%d",nGroupId,nClubId)
		return
	end

	local tNewClub =ClubC:New() 
	tNewClub.nGroupId = math.floor(nGroupId)
	tNewClub.nClubId = math.floor(nClubId)

	ClubManager.arrClub[sClubId] = tNewClub
	CenterData.nClubCnt = CenterData.nClubCnt + 1

	local nIndex = #CenterData.arrSplitClub
	if nIndex==0 then
		nIndex=1
		CenterData.arrSplitClub[nIndex] = {}
	end
	if #CenterData.arrSplitClub[nIndex] == Define.nSplitClubCnt then
		nIndex = nIndex + 1
		CenterData.arrSplitClub[nIndex] = {}
	end
	table.insert(CenterData.arrSplitClub[nIndex],tNewClub)

	tNewClub:Print("_CreateClub nGroupId_%d nClubId_%d",nGroupId,nClubId)
	ClubManager.PrintClubCnt()
    return tNewClub
end

--获取某个俱乐部
--@params nClubId:俱乐部id
--@retuen tClub
function ClubManager.GetClub(nClubId)
	if type(nClubId)~="number" then
		return nil
	end
	local sClubId = string.format("%d",nClubId)
	return ClubManager.arrClub[sClubId]
end

-- 删除俱乐部
--@params nClubId:俱乐部id
--@retuen true 成功  false 失败
function ClubManager.RemoveClub(nClubId)
	local tClub = ClubManager.GetClub(nClubId) 
	if tClub then 
    	tClub:Print("_RemoveClub Remove Club success, nClubId_%d",nClubId)
		local sClubId = string.format("%d",nClubId)
		tClub:Close()
		ClubManager.arrClub[sClubId] = nil 
		CenterData.nClubCnt = CenterData.nClubCnt - 1
		ClubManager.PrintClubCnt() 
		CenterData.arrSplitClub = ClubManager.GetAllClubBySplit()	
		return true 
    else
    	Base.Log("_RemoveClub GetClub is nil, nClubId_%d",nClubId)    
    	return 	false 
    end 
end

--删除某些分组的俱乐部
--@params arrGroup = {nGroupId,nGroupId,...} 分组id数组
function ClubManager.RemoveClubByGroup(arrGroup)
	local tGroup = {}
	for k,nGroupId in pairs(arrGroup) do
		tGroup[nGroupId] = nGroupId
	end
	for nClubId,tClub in pairs(ClubManager.arrClub) do
		if tGroup[tClub.nGroupId] then
			tClub:Print("_RemoveClubByGroup nGroupId_%d nClubId_%d Remove  Club",tClub.nGroupId,tClub.nClubId)
			ClubManager.RemoveClub(nClubId)
		end
	end
end

--获取所有的俱乐部
function ClubManager.GetAllClub()
	return ClubManager.arrClub or {}
end

--获取所有俱乐部
function ClubManager.GetAllClubBySplit()
	local arrSplitClub = {}
	local nIndex = 1
	arrSplitClub[nIndex] = {}
	for _,tClub in pairs(ClubManager.arrClub) do
		table.insert(arrSplitClub[nIndex],tClub)
		if #arrSplitClub[nIndex] == Define.nSplitClubCnt then
			nIndex = nIndex + 1
			arrSplitClub[nIndex] = {}
		end
	end
	return arrSplitClub
end

function ClubManager.PrintClubCnt()
	Base.Log("本服俱乐部数量:%d",CenterData.nClubCnt)
end

-- 获取牌桌的俱乐部
function ClubManager._GetTableClub(sTableId) 
	for nClubId,tClub in pairs(ClubManager.arrClub) do
		for _,tTable in pairs(tClub.arrTable) do
			if tTable.sTableId==sTableId then
				return tClub
			end 
		end 		
	end
	return 
end

return ClubManager

