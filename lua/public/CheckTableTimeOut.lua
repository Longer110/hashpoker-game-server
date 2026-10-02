package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path
local tBase = require("base")
local tGameConfig = require("GameConfig")
local mlogger = require("logger")
local SetingConfig = require("SetingConfig")
CheckTableTimeOut = {
    nMixTimerID = nil, -- 设置定时器基础
    nMaxTimerID = nil, --最大
    OnCloseGroup = nil, --组关闭回调通知
    tTimerID = {},
    tRoomLoginTime = {}, -- 用户登录该房间的时间
    tRoomNumber = {},
    tUserTimer = {}, -- 定时器
}
-- CheckTableTimeOut
--初始化回调函数
function CheckTableTimeOut.Init(CallBack,nMixTimerID,nMaxTimerID)
    CheckTableTimeOut.OnCloseGroup = CallBack
    CheckTableTimeOut.nMixTimerID = nMixTimerID
    CheckTableTimeOut.nMaxTimerID = nMaxTimerID or (nMixTimerID + 1999)
    if nMixTimerID == nil or nMaxTimerID == nil or nMixTimerID < tBase.m_wTimer_ID_Max then
        
        assert(false,"定时器使用错误")
    end
    for i = nMixTimerID,  CheckTableTimeOut.nMaxTimerID do
        table.insert(CheckTableTimeOut.tTimerID, i)
    end
end
-- 登录增加
function CheckTableTimeOut.AddLoginNumber(nGroup, nGameType, nLevel)
    -- mlogger:info(string.format( "AddLoginNumber nGroup:%d nGameType:%d nLevel:%d",nGroup, nGameType, nLevel ))
    local key = CheckTableTimeOut.MakeKey(nGroup, nGameType, nLevel)
    local nNumber =  CheckTableTimeOut.tRoomNumber[key] or 0
    nNumber = nNumber + 1
    CheckTableTimeOut.tRoomNumber[key] = nNumber
    CheckTableTimeOut.tRoomLoginTime[key] = os.time()
    local nFlag =  CheckTableTimeOut.tUserTimer[key] 
    if nFlag ~= nil then
        tBase.KillTimer(nFlag)
        CheckTableTimeOut.tUserTimer[key] = nil
    end
end

-- 退出登录
function CheckTableTimeOut.DelLoginNumber(nGroup, nGameType, nLevel)
    local key = CheckTableTimeOut.MakeKey(nGroup, nGameType, nLevel)
    local nNumber =  CheckTableTimeOut.tRoomNumber[key] or 0
    nNumber = nNumber - 1 
    local sLog = ""
    if nNumber <=0 then
        nNumber = 0 
        CheckTableTimeOut.tRoomNumber[key] = nNumber
        local nTimerID = CheckTableTimeOut.GetTimeID()
        if nTimerID < 0 then
            -- tBase.Log( "DelLoginNumber nGroup:%d nGameType:%d nLevel:%d nTimerID_%d  ", nGroup, nGameType, nLevel,nTimerID)
            return
        end
        local nFlag =  CheckTableTimeOut.tUserTimer[key] 
        if nFlag == nil then 
            sLog = "SetCheckTimeOutTimer"
            CheckTableTimeOut.tUserTimer[key] = nTimerID
            CheckTableTimeOut.SetCheckTimeOutTimer(nTimerID,nGroup,nGameType,nLevel)
        else
            sLog = "SetCheckTimeOutTimered" 
        end       
    end
    -- tBase.Log( "DelLoginNumber nGroup:%d nGameType:%d nLevel:%d  %s  ", nGroup, nGameType, nLevel,sLog)
    CheckTableTimeOut.tRoomNumber[key] = nNumber
end

--获取定时器的ID

function CheckTableTimeOut.GetTimeID()
    if #CheckTableTimeOut.tTimerID <=0 then
        mlogger:warn("检查牌桌超时定时器ID已经不足")
        return -1
    end
    local nTimerID = CheckTableTimeOut.tTimerID[1]
    table.remove(CheckTableTimeOut.tTimerID, 1)
    return nTimerID
end

function CheckTableTimeOut.MakeKey(nGroup, nGameType, nLevel)
    local skey = math.floor( nGroup ) .. math.floor( nGameType ) .. math.floor( nLevel )
    return  skey
end
---设置启动检查超时
function CheckTableTimeOut.SetCheckTimeOutTimer(nTimerID,nGroupID,nGameType, nRoomID)
  
    mlogger:info(string.format( "SetCheckTimeOutTime :%d:",nTimerID ))
    tBase.TokenCallTimeID(nTimerID,SetingConfig.nDissolveTable,1,CheckTableTimeOut.CheckTimeOut, nGroupID,nGameType, nRoomID,nTimerID)

end


-- 检查是否超时
function CheckTableTimeOut.CheckTimeOut(...)
  
    local args = {...}
    local nTimerID = args[4]
    local nRoomID = args[3]
    local nGameType =  args[2]
    local nGroup = args[1]
    mlogger:info(nTimerID or -1)
    mlogger:info( args[2] or -2)
    -- mlogger:info(string.format( "CheckTableTimeOut nTimerID: %d",nTimerID ))
    -- 归还定时器ID
    local key = CheckTableTimeOut.MakeKey(nGroup, nGameType, nRoomID)
    table.insert(CheckTableTimeOut.tTimerID, nTimerID)
    if  CheckTableTimeOut.tUserTimer[key] == nil then
        mlogger:warn("key 获取的值为空警告")
    end
    CheckTableTimeOut.tUserTimer[key] = nil

    local tGroup =  tGameConfig.GetGameList()
    local nNumber =  CheckTableTimeOut.tRoomNumber[key] or 0
    mlogger:info(string.format( "CheckTableTimeOut nTimerID: %d   nNumber: %d  key: %s    ",nTimerID,nNumber,key ))
   
    if nNumber > 0 then
        return
    end 
 
    -- local bCloseGroup = true -- 组关闭标志
    -- for i = 1, #tGroup do
    --     if tGroup[i] == nGroup then
    --         bCloseGroup = false
    --         break;
    --     end
    -- end

        --组关闭了回调出去
       if CheckTableTimeOut.OnCloseGroup ~= nil then
            mlogger:info(string.format("OnCloseGroup nGroup:%d,nGameType:%d, nRoomID:%d",nGroup,nGameType, nRoomID))
            CheckTableTimeOut.OnCloseGroup(nGroup,nGameType,nRoomID)
       end
       CheckTableTimeOut.tRoomNumber[key] = nil
end


return  CheckTableTimeOut