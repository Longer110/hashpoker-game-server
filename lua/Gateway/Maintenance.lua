
local tBase = require("base")               --基础功能接口
local tName = require("typename")           --类弄定义接口



local Maintenance={}
local nStatus =nil
local tTarget={}
local tWhitelist={}
local tTimePeriod={}


--Maintenance_status		--维护状态 set("Maintenance_status",1) set("Maintenance_status",2) set("Maintenance_status",3)
--Maintenance_target		--维护目标 hmset("Maintenance_target" "All" 1); hmset("Maintenance_target" "Grounp1" 1)
--Maintenance_whitelist		--白名单
--Maintenance_TimePeriod	--维护时间段 hmset("Maintenance_TimePeriod" "StartTime" "00-00-00"); hmset("Maintenance_TimePeriod" "EndTime" "00-00-00")
--[[
	状态1:	 维护目标下局被踢出,同时网关禁止非游戏中的维护目标通信进入和登陆.
	状态2:	 网关禁止除白名单外的维护目标通讯进入和登陆.
	其它状态:非维护状态
]]

local function GetGameIdByMainID(MainID,SubID)
    if MainID==300 then
        return 122
    elseif MainID==222 then
        return 121
    elseif MainID==252 then
        return 155
    elseif MainID==255 then
        return 153
    elseif MainID==311 then
        return 129
    elseif MainID==312 then
        return 157
    elseif MainID==263 then
        return 230
    elseif MainID==313 then
        return 159
    elseif MainID==309 then
        return 143
    elseif MainID==307 then
        return 139 
    end

end

local function IsMaintenanceTarget(nGroupId,MainID,SubID)
    local nGroupId =math.floor((nGroupId or -1))
    local nGameId =math.floor((GetGameIdByMainID(MainID,SubID) or -1))

    local function IsTarget()
        if tTarget["All"]=="1" then                  -- *_*
            return true
        end
        if tTarget["All_"..nGameId]=="1" then        -- *_GameId
            return true
        end
        if tTarget["Group"..nGroupId]=="1" then      --GroupId_*
            return true
        end
        if tTarget[string.format("Group%d_%d",nGroupId,nGameId)]=="1" then   --GroupId_nGameId
            return true
        end
        return false
    end

    if not IsTarget() then
        return false
    end

	local sStartTime =tTimePeriod["StartTime"] or "00-00-00"		--维护开始时间
    local sEndTime =tTimePeriod["EndTime"] or "00-00-00"			--预计维护结束时间
    
    local nActualStart =tonumber(tTimePeriod["ActualStart"]) or 0
	local nActualEnd =tonumber(tTimePeriod["ActualEnd"]) or 0
    local nCurrentTime =os.time()
    
    local sActualStart = string.format("%d",nActualStart)
    local sActualEnd = string.format("%d",nActualEnd)

   --tBase.Log("nActualStart_%d nActualEnd_%d nCurrentTime_%d",nActualStart,nActualEnd,nCurrentTime)
    if (nActualStart==0 and nActualEnd==0) or (nCurrentTime>=nActualStart and nCurrentTime<=nActualEnd) then
		return true,sActualStart,sActualEnd,nActualStart,nActualEnd
    end
	return false,sActualStart,sActualEnd,nActualStart,nActualEnd
end

function Maintenance.IsNotMaintenance()
    if nStatus==1 or nStatus==2 then
        return false
    end
    return true
end

function Maintenance.IsLetPlayingUserPass()
    if nStatus==2 then
        return false
    end
    return true
end

function Maintenance.IsMaintenance(nGroupId,nUserId,MainID,SubID)
    if nStatus ==1 then
        return IsMaintenanceTarget(nGroupId,MainID,SubID)
    end
    if nStatus==2 then
        if tWhitelist[string.format("%d",nUserId)] then
            return false
        end
        return IsMaintenanceTarget(nGroupId,MainID,SubID)
    end
    return false
end


function Maintenance.OnTimerReadMaintenanceData(nTimerId)
    local redis =tBase.m_MyRedisData[2].redis
    nStatus =tonumber(redis:get("Maintenance_status"))
	if nStatus~=1 and nStatus~=2 then
		return
    end
    if nStatus ==1 then
        tTarget =redis:hgetall("Maintenance_target") or {}
        tTimePeriod =redis:hgetall("Maintenance_TimePeriod") or {}
        return
    end
    if nStatus ==2 then
        tTarget =redis:hgetall("Maintenance_target") or {}
        tTimePeriod =redis:hgetall("Maintenance_TimePeriod") or {}
        tWhitelist =redis:hgetall("Maintenance_whitelist") or {}
        return
    end
end

return Maintenance

