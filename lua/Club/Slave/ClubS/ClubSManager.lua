--从服俱乐部管理
local ClubSManager = {}
ClubSManager.arrClub = {}

--创建俱乐部
--@params nGroupId:分组id  nClubId:俱乐部id
--@retuen tClub
function ClubSManager.CreateClub(nGroupId,nClubId)
	if type(nGroupId)~="number" or type(nClubId)~="number" then
		Base.Log("_CreateClub Params Error nGroupId:%s nClubId:%s",tostring(nGroupId),tostring(nClubId))
		return
	end

	nGroupId = math.floor(nGroupId)
	nClubId = math.floor(nClubId)
	local sClubId = string.format("%d",nClubId)
	if ClubSManager.arrClub[sClubId] then
		Base.Log("_CreateClub Club is exist, nGroupId:%d nClubId:%d",nGroupId,nClubId)
		return
	end

	local tNewClub =ClubS:New() 
	tNewClub.nGroupId = math.floor(nGroupId)
	tNewClub.nClubId = math.floor(nClubId)

	ClubSManager.arrClub[sClubId] = tNewClub
	tNewClub:Print("_CreateClub nGroupId_%d nClubId_%d",nGroupId,nClubId)
    return tNewClub
end

--获取某个俱乐部
--@params nClubId:俱乐部id
--@retuen tClub
function ClubSManager.GetClub(nClubId)
	if type(nClubId)~="number" then
		return nil
	end
	local sClubId = string.format("%d",nClubId)
	return ClubSManager.arrClub[sClubId]
end

-- 删除俱乐部
--@params nClubId:俱乐部id
--@retuen true 成功  false 失败
function ClubSManager.RemoveClub(nClubId)
	local tClub = ClubSManager.GetClub(nClubId) 
	if tClub then 
    	tClub:Print("_RemoveClub Remove Club success, nClubId_%d",nClubId)
		local sClubId = string.format("%d",nClubId)
		tClub:Close()
		ClubSManager.arrClub[sClubId] = nil  	
		return true 
    else
    	Base.Log("_RemoveClub GetClub is nil, nClubId_%d",nClubId)    
    	return 	false 
    end 
end

--俱乐部是否已经存在
--@params nClubId:俱乐部id
--@reten true:存在  false:不存在
function ClubSManager.ClubIsExist(nClubId)
    local tClub = ClubSManager.GetClub(nClubId)
    return (tClub~=nil)
end

--获取所有的俱乐部
function ClubSManager.GetAllClub()
	return ClubSManager.arrClub or {}
end

return ClubSManager