package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path
local tBase		  = require("base")           -- 基础功能接口
local mlogger = require("logger")             -- 日志对象 
local tTableMgr = require("TableManage")
local tAndroidIo = require("AndroidIo")
local tJson = require("cjson")
local tPubUserApi   = require("PublicUserInfo")    --玩家数据同步
local tPublicRedis =require("PublicRedis")
local bit = require("bit")
MgrAndroid = {
    Android = {},
    tTimeID = {}, --存放定时器
    tGrpNumber = {},
    tLastGrpNumber = {}    
}

function MgrAndroid.CallBack(...)
    local args = {...}
    local arrAndroidItem = args[#args]
    local nNeed =  args[2]
    if #arrAndroidItem ~= nNeed then
        mlogger:info(string.format( "机器人arrAndroidItem: %d 与需要的nNeed : %d  不符", #arrAndroidItem,nNeed ))
    end
    local sTableId = args[1] or "-1" 
    local tTable = tTableMgr.GetTable(sTableId)
    if tTable == nil then 
        tBase.Log("_CallBack  tTable is nil   sTableId: %s  ",sTableId)
        return 
    end
    -- 1.满人的情况下不需要机器人 2.已经开始的情况下50%的几率不需要机器人
    local nNeedCnt = nNeed 
    if tTable:IsUserFull() then 
        tTable:Print("_CallBack  牌桌已经满人 ")
        tAndroidIo.SetAndroid({arrAndroid=arrAndroidItem})
        return
    elseif (tTable.nMaxUser - tTable:GetReadyUserCnt()) <= 1 then
        tTable:Print("_CallBack  牌桌人数已经够了 ") 
        tAndroidIo.SetAndroid({arrAndroid=arrAndroidItem})
        return
    end
    if #arrAndroidItem <= 0 then
        tTable:Print("_CallBack  机器服 没给到机器人")  
        MgrAndroid:Time_Load_Android(3 * 1000,sTableId)
    end 
    for _, tItem in pairs(arrAndroidItem) do
        if (nNeedCnt > 0) then 
            tTable:Print("_CallBack  机器人信息: %s ",tJson.encode(tItem)) 
            MgrAndroid:Add(tItem)
            tTable:OnAndroid(tItem)
            nNeedCnt  = nNeedCnt - 1
        else
            local temp = {}
            table.insert(temp,tItem )
            tAndroidIo.SetAndroid({arrAndroid=temp})
        end	
    end
end

--添加机器人
function MgrAndroid:Add(tAndroidData)
    self.Android[math.floor(tAndroidData.nUserId)] = tAndroidData
end

-- 删除机器人
function MgrAndroid:Del(nUserID)
    if (self.Android[nUserID] ~= nil) then
        --tBase.Log("_Del 机器人: %d 回收",nUserID)   
        local temp = {}
        self.Android[nUserID].nGold = tPubUserApi.Get_User_Gold(nUserID) or 0
        table.insert(temp, self.Android[nUserID])
        tAndroidIo.SetAndroid({arrAndroid=temp})
       self.Android[nUserID] = nil
    else
        tBase.Log("_Del   机器人: %d 删除失败或者不存在",nUserID)   
    end
    
end

--获取机器人数据
function MgrAndroid.GetAndroidData(nUserID)    
    if (MgrAndroid.Android[nUserID] ~= nil) then
        return MgrAndroid.Android[nUserID]
    else
        tBase.Log("_GetAndroidData   机器人: %d 删除失败或者不存在",nUserID)    
        return nil
    end
end

-- 机器人进入
function MgrAndroid.AndroidEnterTable(nTimerID) 
    MgrAndroid.tTimeID[nTimerID] = nil
    local nTableId = nTimerID % SrvPub.Timer.AndroidEnterTable
    local nCntOfCall = math.random(1,2)
    local nRandomSeconds = 0
    if nCntOfCall%2==1 then
        nRandomSeconds = math.random(2,6)
    else
        nRandomSeconds = math.random(5,18)
    end
    tBase.SetTimer(SrvPub.Timer.AndroidEnterTable + nTableId,nRandomSeconds*1000, 1, MgrAndroid.AndroidEnterTable) 
	local tTable = tTableMgr.GetTable(nTableId)
    if tTable == nil then 
        tBase.Log("_AndroidEnterTable 遇到牌桌解散 nTableId:%d",nTableId)
        return 
    end

    if tTable:IsUserFull() then
        tTable:Print("_AndroidEnterTable 牌桌已经满人")
        return
    elseif (tTable.nMaxUser - tTable:GetReadyUserCnt()) <= 1 then
        tTable:Print("_AndroidEnterTable 牌桌人数已经够了") 
        return
    end
    -- local nNeedCnt = tTable.nPlayerCntAtLeast - tTable:GetReadyUserCnt()
    -- local nMaxCnt =tTable.nMaxUser//2
    local nMaxCnt = bit.rshift(tTable.nMaxUser,1)
    nMaxCnt =math.min(nMaxCnt,tTable.nMaxUser)
    nMaxCnt =(nMaxCnt<0) and 0 or nMaxCnt
    -- local nCnt =math.random(0,nMaxCnt) 		--tPublicRedis._LiveAndroidCount(self.nGroupId,self.nGameId,self.nRoomId)
    local Cnt = 0
    local nNowRobotCnt =#tTable:GetAndroidReadyArr()
    if tTable.ifAdjustedAndroid == 0 then
        Cnt =tPublicRedis._LiveAndroidCount(tTable.nGroup,178,2) --todo参数
        tTable.CurConfigAndroid = Cnt
    else
        Cnt = tTable.adjustAddCnt --一旦后台调整过 忽略原本配置 一直以此作为参考 直到下次后台调整
    end

    tTable:Print("_AndroidEnterTable nNowRobotCnt:%d ShouldNeed:%d nGroupId:%d nRoomId:%d nNeedMaxCnt:%d nTableMaxCnt:%d",
    nNowRobotCnt,Cnt,tTable.nGroup,tTable.nLevel,nMaxCnt,tTable.nMaxUser)

    -- if nNowRobotCnt>=nCnt then
    --     tTable:Print("_AndroidEnterTable 不需要加载机器人 nNowRobotCnt_%d nCnt_%d ",nNowRobotCnt,nCnt)  
    --     return
    -- end
    if tTable:_IsMendOpenTableLimitRobot() then 
        return
    end
    
    local nNumber = 1
    local nGroup =  tTable.nGroup
    local nMixGold = 0
    local nMaxGold = 0 
    nMixGold, nMaxGold =  TableApi.AutoAndroidGold(tTable:GetUserGoldList(),1)
    nMixGold = nMixGold*tTable:_GetTableLowerCoin()
    nMaxGold = nMaxGold*tTable:_GetTableLowerCoin()
    
    -- local tData = {nGrpId= nGroup, sIndex="nGold", nMin = nMixGold, nHigh= nMaxGold, nCnt=nNumber} 
    -- local nIdex = math.floor( nNumber / 30 ) 
    -- for i = 1, nIdex  do
    --     tData.nCnt = 30
    --     tAndroidIo.GetAndroid(tData,  MgrAndroid.CallBack, nTableId, 30 )
    -- end 
    -- tData.nCnt = nNumber - nIdex * 30
    -- tTable:Print("_AndroidEnterTable  nIdex_%d  nCnt_%d  nRobotCnt_%d ",nIdex,tData.nCnt,nNowRobotCnt)   
    -- tAndroidIo.GetAndroid(tData,  MgrAndroid.CallBack, nTableId, nNumber - nIdex * 30 ) 

    local tData = {nGrpId= nGroup, sIndex="nGold", nMin = nMixGold, nHigh= nMaxGold, nCnt=1}
    tTable:Print("_AndroidEnterTable  nCnt_%d  nRobotCnt_%d ",tData.nCnt,nNowRobotCnt)
    
    if nNowRobotCnt < Cnt and tTable.ifAdjustedAndroid == 0 then  --没被后台操作过 才会再自动补充
        tAndroidIo.GetAndroid(tData,MgrAndroid.CallBack,nTableId,1)
    end
    if tTable.adjustAddCnt > 0 and tTable.ifAdjustedAndroid == 1 then
        tAndroidIo.GetAndroid(tData,MgrAndroid.CallBack,nTableId,1)
        tTable:ReduceAdjustAddCnt()
    end
end


--机器人加载定时器
function MgrAndroid:Time_Load_Android(Times,nTableId) 
    local tTable = tTableMgr.GetTable(nTableId)
    if tTable == nil then 
        tBase.Log("_Time_Load_Android  tTable is nil   nTableId: %s  ",nTableId) 
        return 
    end
    if not tTable.isNeedAndroid then
        tTable:Print("_Time_Load_Android  检测到牌桌在后台没有设置机器人的加载")   
        return
    end
    tTable:Print("_Time_Load_Android  启动加载机器人")    
    if (self.tTimeID[SrvPub.Timer.AndroidEnterTable + nTableId] == nil  or  os.time() - self.tTimeID[SrvPub.Timer.AndroidEnterTable + nTableId] > 10 )   then
        local nCount = #tTable:GetReadyUserArr()   --获得桌子已经有多少个玩家
        if (nCount < tTable.nMaxUser -1) then
            local nTimes = math.random(1000,Times)
            self.tTimeID[SrvPub.Timer.AndroidEnterTable + nTableId] = os.time()
            tBase.SetTimer(SrvPub.Timer.AndroidEnterTable + nTableId,nTimes, 1, MgrAndroid.AndroidEnterTable)  
        end
        tTable:Print("_Time_Load_Android  检测牌桌已经有多少个玩家在场:%d ",nCount)    
    else
        tTable:Print("_Time_Load_Android  该定时器已经启动 ")     
    end
end


return MgrAndroid 