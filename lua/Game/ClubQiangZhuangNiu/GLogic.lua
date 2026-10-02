
package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase = require("base") -- 基础
local tUserMgr = require("UserManager")
local tTableMgr = require("TableManage")
local tJson = require("cjson")
local tMgrAndroid = require("MgrAndroid")
local tConfig =require("GameConfig")
local tPublicMath = require("PublicMath")
local tCfg = require("GConfig")
local mlogger = require("logger") -- 日志对象 
local tGameCfgRedis = require("GameCfgRedis")
local tPublicRedis =require("PublicRedis")
local MsgPush =require("MsgPush")
local tPublicClub =require("PublicClub")
local tSrvInfo = require("ServerInfo")
local tPubUser = require("PublicUserInfo")   -- 用户信息
local tSrvPub = require("SrvPublic")

GLogic = {
    tPrestrainGroup = {}, -- 预开桌处理动态加载组
}

local function SetTableOpResult(sRequestkey,tData)
    if not sRequestkey then
       return
    end
    local tRedis =tBase.m_MyRedisData[1].redis
    tRedis:hmset(sRequestkey,tData)
    tRedis:expire(sRequestkey,60)
 end

 local function CreateTableInRedis(tTableConfig)
    local tTableInfo={}
    tTableInfo.sTableId=tTableConfig.sTableId
    tTableInfo.nGameId =tTableConfig.nGameType
    tTableInfo.nRoomId =tTableConfig.nRoomId
    tTableInfo.nLiveUserID=math.floor(tTableConfig.nLiveUserID or 0)
    tTableInfo.nGroupId =math.floor(tTableConfig.nGroupId)
    tTableInfo.sTableName=tTableConfig.sTableName
    tTableInfo.nTableType=tTableConfig.nTableType
    tTableInfo.sLiveID =tTableConfig.sLiveID
    tTableInfo.sPlatformID =tTableConfig.sPlatformID
    tTableInfo.sConfig =tTableConfig.sConfig
    tTableInfo.nClubId =tTableConfig.nClubId      
      
    tPubUser.API_Open_Table_InRedis(tTableInfo)
    return true
 end

 --检查配置，并尽可能纠正
local function ConfigCorrected(tJsonConfig)
    if tJsonConfig.nGameId==nil then
       tJsonConfig.nGameId =GConfig.GameType.KanPaiNiuNiu
    end
    if tJsonConfig.nGameId~=GConfig.GameType.KanPaiNiuNiu then
       return false,"NotSupport GameId"
    end
    tJsonConfig.isNeedAndroid =tJsonConfig.isNeedAndroid or false
    if tJsonConfig.nCapacity==nil or tJsonConfig.nCapacity<0 then
       tJsonConfig.nCapacity=0
    end
 
    tJsonConfig.tAutostart =tJsonConfig.tAutostart or {isOpen=false,nPlayerCnt=2}
    local nPlayerCnt =tJsonConfig.tAutostart.nPlayerCnt
    --永久牌桌(已废弃) 默认满2人开始
    -- if tJsonConfig.nKeepTime >= 0 then
    if tJsonConfig.tAutostart.isOpen and (nPlayerCnt==nil or nPlayerCnt<2) then
        tJsonConfig.tAutostart.nPlayerCnt =2
    end
    if not tJsonConfig.tAutostart.isOpen then
        if tJsonConfig.nClubId < 1000000 then
            --大厅自动满2人开始
            tJsonConfig.tAutostart.nPlayerCnt =2
        else
            --俱乐部按照设置
            tJsonConfig.tAutostart.nPlayerCnt=5
        end
    end
    -- else
    --     --大厅永久牌桌自动满2人开始
    --     tJsonConfig.tAutostart.nPlayerCnt =2
    -- end
   
    if tJsonConfig.nTax==nil or tJsonConfig.nTax<0 then
        tJsonConfig.nTax=0
    end
    if tJsonConfig.nAnte==nil or tJsonConfig.nAnte<0 then
        tJsonConfig.nAnte=0
        return false,"nAnte is less 0"
    end
     --牌型倍数
    if tJsonConfig.HuType==nil or #tJsonConfig.HuType<0 then
        tJsonConfig.HuType=0
        return false,"HuType is wrong1"
    else
        for k, v in pairs(tJsonConfig.HuType) do
            if v < 1 or type(v) ~="number" then
                mlogger:info(string.format("后台牌型:HuType k :%d is wrong",k))
                return false,"HuType is wrong2"
            end
        end  
     end
   return true
 end

--检查玩家是否有未完成对局
function GLogic.CheckInRoom(nUserID)
    local  tUser = tUserMgr.GetUserInfo(nUserID)
    if (tUser == nil) then
    return false, nil 
    end
    tBase.Log("CheckInRoom"..tJson.encode(tUser))
    local  tTable = tTableMgr.GetTable(tUser.nTableId)
    if (tTable == nil) then
        return false, nil 
    end
    return true, tTable
end

-- 获取一个牌桌的随机步骤
function GLogic.GetStepByGameID(nGameID) 
    local nRandStep = -1
    if nGameID == tCfg.GameType.KanPaiNiuNiu then   
        local k = math.random(1, #SrvPub.KanPaiStep)
        nRandStep = SrvPub.KanPaiStep[k]
    end
    return nRandStep
end

--后台桌子管理请求
function GLogic.OnReqAPI_Table(sReturnKey,Data,nLen)
    local tData =BackstageAux:Parser(Data, nLen,"ReqAPI_Table")
    assert(tData~=nil,"OnReqAPI_Table Parser Error")
    tBase.LogT("OnReqAPI_Table:",{nType=tData.nType,nRoomId=tData.nRoomId,nTableType=tData.nTableType})
    --开桌
    if tData.nType==1 then
        local isSuccee,tRlt =pcall(tJson.decode,tData.sConfig)
        if not isSuccee then
            SetTableOpResult(tData.sRequestkey,{nErrorCode=20})
            tBase.LogT("_CreateTable fail,nCode:",20)
            tBase.LogT(tRlt)
            return
        end
        local isCorrect,sErr =ConfigCorrected(tRlt)
        if not isCorrect then
            SetTableOpResult(tData.sRequestkey,{nErrorCode=21})
            tBase.LogT("_CreateTable fail,nCode:",21)
            tBase.LogT(sErr)
            return
        end
    
        local nIdx  = tTableMgr.AddTable()
        local tTable = tTableMgr.GetTable(nIdx)
        if not tTable then
            SetTableOpResult(tData.sRequestkey,{nErrorCode=22})
            tBase.LogT("_CreateTable fail")
            return false
        end
        local tInfo = {}
        tInfo.nRoomId = tData.nRoomId --场次ID
        tInfo.sTableName = tData.sTableName
        tInfo.nTableType = tData.nTableType
        tInfo.nOpentime = tData.nOpentime
        tInfo.sRequestkey = tData.sRequestkey
        tInfo.nLiveUserID = tData.nLiveUserID
        tInfo.nGroupId = tData.nGroupId
        tInfo.nGameType = tRlt.nGameId
        tInfo.BaseScore = tRlt.nAnte
        tInfo.nTax = tRlt.nTax / 1000
        tInfo.nNModeType = tRlt.nNModeType
        tInfo.nClubId = tRlt.nClubId
        tInfo.bPreOpenTable = true
        tInfo.nCapacity = tRlt.nCapacity
        tInfo.nGoldType = tRlt.nGoldType
        tInfo.nItemId = tRlt.nItemId
        tInfo.HuType = tRlt.HuType
        tInfo.tAutostart = tRlt.tAutostart
        tInfo.isNeedAndroid = tRlt.isNeedAndroid
        tInfo.sClubName = tRlt.sClubName
        tInfo.nKeepTime = tRlt.nKeepTime
        
        tInfo.sLiveID = ""
        tInfo.sPlatformID = ""
        tInfo.PlayFan = {}
        tPublicMath.CopyTable(tInfo.PlayFan, tCfg.HuPlayFunc[1])
        tInfo.nLimitGold = 0
        tInfo.nRandStopStep = -1 -- GLogic.GetStepByGameID(tRlt.nGameId) 
        tInfo.sTableId = string.format("%d#%s",tSrvInfo.nServerId,tPubUser.CreatePaiJuID())
        tInfo.sConfig= tData.sConfig
        tInfo.nContinuedNum = tRlt.nContinuedNum                
        tTable:Loader(tInfo)
       
        --机器人加载
        if tInfo.isNeedAndroid then
            local nCntOfCall = math.random(1,2)
            local nRandomSeconds = 0
            if nCntOfCall%2==1 then
                nRandomSeconds = math.random(2,6)
            else
                nRandomSeconds = math.random(5,18)
            end
            tMgrAndroid:Time_Load_Android(nRandomSeconds * 1000,nIdx)
        end

        CreateTableInRedis(tInfo)

        local t={
            nErrorCode=0,
            sTableId =tTable.sTableId,
            nGameId =tRlt.nGameId,
            nRoomId =tTable.nLevel,
            sTableIdentify =tTable.sTableId
        }
        SetTableOpResult(tData.sRequestkey,t)
        tBase.LogT("_CreateTable succee,sTableId:",tTable.sTableId)
        --俱乐部桌开桌通知
        local tTableInfo = tTable:GetTableInfoForClub()
        tTableInfo.sRequestkey = tData.sRequestkey
        tPublicClub.ClubTableOpenNotify(tRlt.nClubId,tTable.sTableId,tTableInfo)
    end
    --关桌
    if tData.nType==2 or tData.nType==3 then
        tBase.LogT("_CloseTable ,is Need deal,sTableId:",tData.sTableId)
       if GLogic._CloseTable(tData.sTableId,tData.sRequestkey) then
          RecordDbr.LiveTableClose(tData.sTableId)  
       end
    end
 end

-- 统计本服各桌情况
function GLogic.TotalTable() 
    local tTotal = {}
    local tTableDataArr = {}
    for i = 1, #tTableMgr.arrTable do
        local  tTable = tTableMgr.arrTable[i]
        if type(tTable) == "number" and tTable ==0 then
            --tBase.Log("无效的牌桌")
        else
            local sKey = tBase.m_tKey..tTable.nGameType..tTable.nLevel..tTable.nGroup
            tTableDataArr[sKey] =  tTableDataArr[sKey] or {sSeverKey = tBase.m_tKey, nGameID =tTable.nGameType,nRoomID = tTable.nLevel, nGroupID = tTable.nGroup, nTableCount = 0, nAndroidCount = 0, nUserCount = 0 }
            local tData = tTableDataArr[sKey]
            local nAnd, nUser =   tTable:GetAndroidCountAndUserCount() 
           -- mlogger:info(string.format( "nAnd : %d nUser:%d ", nAnd, nUser))
            tData.nTableCount =  tData.nTableCount + 1
            tData.nAndroidCount =  tData.nAndroidCount + nAnd
            tData.nUserCount =  tData.nUserCount + nUser
        end
    end
    
    for _, v in pairs(tTableDataArr) do
        TableApi.SetGameTableData(v)
    end
end

-- 统计本服各桌情况
function GLogic.TotalTable2()  
    local tTotal = {}
    local tTableDataArr = {}
    for i = 1, #tTableMgr.arrTable do
        local  tTable = tTableMgr.arrTable[i]
        if type(tTable) == "number" and tTable ==0 then
            --tBase.Log("无效的牌桌")
        else
            local sKey = tTable.nGameType..tTable.nLevel..tTable.nGroup
            tTableDataArr[sKey] =  tTableDataArr[sKey] or {nUserCount =0,nGameType = tTable.nGameType, nLevel = tTable.nLevel, nGroup = tTable.nGroup}
            local tData = tTableDataArr[sKey] 
            local nAnd, nUser =   tTable:GetAndroidCountAndUserCount() 
           -- mlogger:info(string.format( "nAnd : %d nUser:%d ", nAnd, nUser))
            tData.nUserCount =  tData.nUserCount + nUser
        end
    end
end

--关闭对应分组牌桌
function GLogic.OnCloseGroupCallBack(nGroup,nGameType, nRoomID)
    local tTableObjArr = {}
    for i = 1, #tTableMgr.arrTable do
        local  tTable = tTableMgr.arrTable[i]
        if type(tTable) == "number" and tTable ==0 then
            --tBase.Log("无效的牌桌")
        else
          if tTable.nGroup == nGroup and tTable.nLevel == nRoomID and tTable.nGameType  == nGameType  and  tTable:GetRealUser() <= 0 then
            --解散牌桌
            table.insert(tTableObjArr,tTable )
            --GLogic.DisMissTable(tTable)
          end
        end
    end

    for i = 1, #tTableObjArr do
        GLogic.DisMissTable(tTableObjArr[i])
    end
    local sKey = nGroup..nGameType..nRoomID
    GLogic.tPrestrainGroup[sKey] = nil
end

--解散所有牌桌
function GLogic.DisMissAllTable(nNumber)
    for i = 1, #tTableMgr.arrTable do
        local  tTable = tTableMgr.arrTable[i]
        if type(tTable) == "number" and tTable ==0 then
            tBase.Log("无效的牌桌")
        else
            GLogic.DisMissTable(tTable)
        end
    end
end

-- 解散牌桌
function GLogic.DisMissTable(TableObj,IsSend)
    if TableObj == nil then
        return 
    end
    local tData = {["TableId"]=TableObj.nTableId}
    mlogger:info(string.format("%s_DisMissTable tableID :%d",TableObj.sTableId,TableObj.nTableId ))
    tBase.KillTimer(SrvPub.Timer.TableStep + TableObj.nTableId) --牌桌流程定时器
    tBase.KillTimer(SrvPub.Timer.AndroidAi + TableObj.nTableId) --牌桌ai
    tBase.KillTimer(SrvPub.Timer.AndroidEnterTable + TableObj.nTableId) -- 牌桌机器人进入
    MgrAndroid.tTimeID[SrvPub.Timer.AndroidEnterTable + TableObj.nTableId] = nil
    TableObj.TimerForRetain:KillAllTimer()
    TableObj.TimerForAndroid:KillAllTimer()
    TableObj.TimerForElapWarn:KillAllTimer()
    local RmUserArr = {}
	PublicMath.CopyTable(RmUserArr,TableObj.tUserIDArr)
    for i = 1, #RmUserArr do
        local tData = {["userid"]=RmUserArr[i]}
        local  tUser = tUserMgr.GetUserInfo(RmUserArr[i])
        TableObj:ExitTable(RmUserArr[i])

        if tUser ~=nil and tUser.isAndroid == false then -- 真人
            Protocol.Rep_LogOut(tUser.sClientID,{UserID = tUser.nUserID,Result = 2})
            if IsSend == nil then
                MsgPush.SendKickOutNotify(tUser.sClientID,"2",0)
            end
          
            TableObj:UserLout(tUser)
        end
        tUserMgr.DelUser(tUser)
    end
  
    --tSrvPub.PostInnerEvent(tSrvPub.Event.REMOVETABLE, tData)
    tTableMgr.RemoveTable(TableObj.nTableId)

    tPubUser.API_Close_Table(TableObj.sTableId)
    tPublicClub.ClubTableCloseNotify(TableObj.nClubId,TableObj.sTableId)
    TableObj:TaxByTableRateSettle_All()
end

--关闭桌子
function GLogic._CloseTable(sTableId,sRequestkey)
    local tTable = tTableMgr.GetTableBySTableId(sTableId)
    if tTable==nil then
       tBase.Log("%s_close table fail,can not find table",sTableId)
       SetTableOpResult(sRequestkey,{nErrorCode=1})
       return false
    end
    SetTableOpResult(sRequestkey,{nErrorCode=0})
    
    if tTable.nStep <= tSrvPub.enumStep.nNull then
        GLogic.DisMissTable(tTable,1)
    else
        tTable:SetClose(tSrvPub.TableCloseReason.nBackstageClose)   --设置本局结束后关闭桌子
    end
    return true
 end

return GLogic