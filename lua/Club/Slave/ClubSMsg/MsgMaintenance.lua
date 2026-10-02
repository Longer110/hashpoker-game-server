--服务器维护
local MsgMaintenance = {}
MsgMaintenance.tMaintenanceInfo = nil --中心服维护信息

--是否在维护期间
function MsgMaintenance.IsDuringMaintenance()
    if MsgMaintenance.tMaintenanceInfo then
        local nNowTime = os.time()
        if nNowTime>=MsgMaintenance.tMaintenanceInfo.ActualStart and nNowTime<=MsgMaintenance.tMaintenanceInfo.ActualEnd then
            return true,MsgMaintenance.tMaintenanceInfo.ActualStart,MsgMaintenance.tMaintenanceInfo.ActualEnd
        end
    end
    return false
end 

--定时维护状态
function MsgMaintenance.CheckMaintenance()
    if MsgMaintenance.tMaintenanceInfo then
        local nNowTime = os.time()
        if MsgMaintenance.tMaintenanceInfo.ActualEnd<=nNowTime then
            Base.Log("维护信息已过期 %s - %s",MsgMaintenance.tMaintenanceInfo.sStartTime,MsgMaintenance.tMaintenanceInfo.sEndTime)
            MsgMaintenance.tMaintenanceInfo = nil
            return
        end
        if MsgMaintenance.tMaintenanceInfo.ActualStart>nNowTime then
            Base.Log("维护信息尚未开始 %s - %s",MsgMaintenance.tMaintenanceInfo.sStartTime,MsgMaintenance.tMaintenanceInfo.sEndTime)
            return
        end

        if MsgMaintenance.tMaintenanceInfo.isEnterMaintain==nil then
            if MsgMaintenance.tMaintenanceInfo.ActualStart<=nNowTime and nNowTime<=MsgMaintenance.tMaintenanceInfo.ActualEnd then
                Base.Log("未维护->维护 %s - %s",MsgMaintenance.tMaintenanceInfo.sStartTime,MsgMaintenance.tMaintenanceInfo.sEndTime)
                MsgMaintenance.tMaintenanceInfo.isEnterMaintain = true
            end
        end

        --未维护->维护,在俱乐部里面的玩家全部踢走
        --维护期间,在俱乐部里面的非白名单玩家全部踢走
        local arrClub = ClubSManager.GetAllClub()
        for _,tClubS in pairs(arrClub) do
            tClubS:NotifyAllUserMaintenance(MsgMaintenance.tMaintenanceInfo.isEnterMaintain)
        end

        --未维护->维护,本服所有不在俱乐部里面的玩家全部踢走
        if MsgMaintenance.tMaintenanceInfo.isEnterMaintain then
            local tAllUser = UserManager.GetAllUserInfo()
            for nUserId,tUser in pairs(tAllUser) do
                if tUser:GetNowClub()==0 then
                    local ClubSMaintenanceNotify = {}
                    ClubSMaintenanceNotify.sTime = string.format("%s - %s",MsgMaintenance.tMaintenanceInfo.sStartTime,MsgMaintenance.tMaintenanceInfo.sEndTime)
                    MsgApi.SendToUser(nUserId,"ClubSMaintenanceNotify",ClubSMaintenanceNotify)
                end
            end
        else
            --维护期间,本服所有不在俱乐部里面的非白名单玩家全部踢走
            local tAllUser = UserManager.GetAllUserInfo()
            for nUserId,tUser in pairs(tAllUser) do
                if tUser:GetNowClub()==0 and not PublicRedis.IsWhiteListUser(nUserId) then
                    local ClubSMaintenanceNotify = {}
                    ClubSMaintenanceNotify.sTime = string.format("%s - %s",MsgMaintenance.tMaintenanceInfo.sStartTime,MsgMaintenance.tMaintenanceInfo.sEndTime)
                    MsgApi.SendToUser(nUserId,"ClubSMaintenanceNotify",ClubSMaintenanceNotify)
                end
            end
        end
    end
end

return MsgMaintenance