package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path


EventCallBack = {}

function EventCallBack.CallBack(nUserID)
    local tUserInfo = UserManager.GetUserInfo(nUserID) 
    if tUserInfo == nil then
        base.Log("EventCallBack :用户信息错误 nUserID_%d",nUserID)
        return 
    end
    local tTable = TableManager.GetTable(tUserInfo.nTableId)
    if tTable == nil then
        base.Log("EventCallBack :牌桌信息错误 nUserID_%d nTableId_%d",nUserID,tUserInfo.nTableId or -1)
        return
    end
    tTable:Print("_EventCallBack nUserID_%d  UserStatusChange ",nUserID)
    tTable:SendAllUser(nUserID, tTable.EnumProtocol.UserStatusChange)
end 


return  EventCallBack