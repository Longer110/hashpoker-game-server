local ssl    = require("ssl")
Cjson     = require("cjson")        -- json  
local Base  = require("base")         -- 基础功能接口
local url = require("socket.url")
local tPublicRedis =require("PublicRedis") -- Redis 公共接口 
local tPublicBlockChain =require("PublicBlockChain")
local tMoblieBinder =require("MoblieBinder")
local tRedisdefine = require("redisdefine")
local tPubUsrApi  = require("PublicUserInfo")   -- 用户信息 
local GlobalConfigKey = tRedisdefine.GlobalConfigKey
local CostName = tRedisdefine.CostName

--前端消息处理
local MsgClient = {}

--前端消息统一校验
function MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not SlaveData.isInitFinish then
        Base.Log("_CheckClientMsg 开服加载数据还没结束")
        return false
    end

    local tData =SlaveAux:Parser(Data, nLen, strProto)
    if not tData then
        Base.Log("%s _Parse Err",strProto)
        return false
    end

    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId or nUserId < 0 then
        Base.Log("__CheckClientMsg not find nUserId by sClientID_%s,strProto_%s",tostring(sClientID),strProto)
        return false
    end

    return true,tData,nUserId
end

function MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not SlaveData.isInitFinish then
        Base.Log("_CheckClientMsg 开服加载数据还没结束")
        return false
    end

    local tData =SlaveAux2:Parser(Data, nLen, strProto)
    if not tData then
        Base.Log("%s _Parse Err",strProto)
        return false
    end

    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId or nUserId < 0 then
        Base.Log("__CheckClientMsg not find nUserId by sClientID_%s,strProto_%s",tostring(sClientID),strProto)
        return false
    end

    return true,tData,nUserId
end


--数据库返回统一校验
function MsgClient._CheckDbMsg(strProto, Data, nLen)
    local tData =DbClubServAux:Parser(Data, nLen, strProto)
    if not tData then
       Base.Log("%s _Parse Err",strProto)
       return
    end
    return tData
end

--数据库返回统一校验
function MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    local tData =DbClubServAux1:Parser(Data, nLen, strProto)
    if not tData then
       Base.Log("%s _Parse Err",strProto)
       return
    end
    return tData
end

--数据库1返回统一校验
function MsgClient._CheckDb1Msg(strProto, Data, nLen)
    local tData =DbServer1Aux:Parser(Data, nLen, strProto)
    if not tData then
       Base.Log("%s _Parse Err",strProto)
       return
    end
    return tData
end

--前端消息处理
function MsgClient._OnTableMsgHandle(strReq,sClientID,Data,nLen) 
    local tData =SlaveAux:Parser(Data, nLen,strReq)
    if tData ==nil then
       Base.Log(strReq.." _Parse Err")
       return
    end
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
       Base.Log(strReq.." Not Logon,sClientID_"..(sClientID or 'nil'))
       return
    elseif nUserId < 0  then 
       Base.Log(strReq.." is look account,sClientID_"..(sClientID or 'nil'))
       return 
    end
    local tClub =UserManager.GetUserNowClub(nUserId)
    if tClub then
       tClub:OnReqHandle(nUserId,strReq,tData)
       return nUserId,tClub
    else
       Base.Log(strReq.." can not find tClub, nUserId_%d",nUserId)
    end
    return nUserId,tClub
end

function MsgClient._OnTableMsgHandle2(strReq,sClientID,Data,nLen)
    local tData =SlaveAux2:Parser(Data, nLen,strReq)
    if tData ==nil then
       Base.Log(strReq.." _Parse Err")
       return
    end
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
       Base.Log(strReq.." Not Logon,sClientID_"..(sClientID or 'nil'))
       return
    elseif nUserId < 0  then
       Base.Log(strReq.." is look account,sClientID_"..(sClientID or 'nil'))
       return
    end
    local tClub =UserManager.GetUserNowClub(nUserId)
    if tClub then
       tClub:OnReqHandle(nUserId,strReq,tData)
       return nUserId,tClub
    else
       Base.Log(strReq.." can not find tClub, nUserId_%d",nUserId)
    end
    return nUserId,tClub
end
 
--登陆请求
function MsgClient.OnClubSLogOnReq(sClientID, Data, nLen)
    if not SlaveData.isInitFinish then
        Base.Log("_OnClubSLogOnReq 开服加载数据还没结束")
        return
    end

    local tData =SlaveAux:Parser(Data, nLen, "ClubSLogOnReq")
    if tData ==nil then
        Base.Log("ClubSLogOnReq _Parse Err")
        return
    end

    local nUserId =math.floor(tData.nUserId)
    local nClubId =math.floor(tData.nClubId)
    local inviteCode = tData.nInviteCode
    --判断玩家id是否正确
    if not PublicUserInfo.ChecksClientIDByUserID(nUserId,sClientID) then
        Base.Log("_OnClubSLogOnReq 登陆请求 nUserId_%d Error  id不正确 sClientID_%s",nUserId,sClientID)
        MsgApi.SendToClient(sClientID,"ClubSLogOnResp",{nRlt=PubErrCode.Login.UserIdErr,sErrStr="nUserId  get  fail"})
        return
    end

    --关联连接与玩家id
    ClientIdMgr.BuildContact(sClientID,nUserId)
    local tUser=UserManager.CreateUser(nUserId)
    local nGroupId = tUser.nGroupId
    Base.Log("_OnClubSLogOnReq  登陆请求 nUserId_%d nGroupId_%d nClubId_%d nGold_%.2f ",nUserId,nGroupId,nClubId,tUser.nGold)

    --是否在维护中
    local isMaintenance,nStartTime,nEndTime = MsgMaintenance.IsDuringMaintenance()
    if isMaintenance then
        local sStartTime,sEndTime = tostring(math.floor(nStartTime)),tostring(math.floor(nEndTime))
        if MsgMaintenance.tMaintenanceInfo.isEnterMaintain or not PublicRedis.IsWhiteListUser(nUserId) then
            --进入从未维护->维护或者非白名单用户
            local sMaintenance = string.format("%s - %s",os.date("%Y-%m-%d %H:%M:%S",nStartTime),os.date("%Y-%m-%d %H:%M:%S",nEndTime))
            Base.Log("_OnClubSLogOnReq 游戏服维护中 %s",sMaintenance)
            -- MsgApi.SendToClient(sClientID,"ClubSLogOnResp",{nRlt=PubErrCode.Login.IsMaintenance,sErrStr="server is Maintenance,time: "..sMaintenance})
            MsgPush.SendMaintenanceNotify(sClientID,sStartTime,sEndTime)
            return
        end
    end

    if nClubId==0 then
        nClubId = nGroupId
        Base.Log("_OnClubSLogOnReq 请求登录大厅 nUserId_%d nClubId_%d ",nUserId,nClubId)
    elseif nClubId==-1 then
        MsgApi.SendToClient(sClientID,"ClubSLogOnResp",{nRlt=PubErrCode.Login.Success,sErrStr=""})
        return
    end

    --重连判断
    local nNowClubId = tUser:GetNowClub()
    if nNowClubId ~= 0  then
        Base.Log("_OnClubSLogOnReq 玩家在俱乐部中 nUserId_%d nNowClubId_%d nClubId_%d ",nUserId,nNowClubId,nClubId)
        --有所在的俱乐部
        if nNowClubId == nClubId then
            --是同一个，回这个俱乐部
            local tClub = ClubSManager.GetClub(nNowClubId)
            if not tClub then
                --没找到俱乐部
                local sErrStr = string.format("get Club_%d fail",nClubId)
                Base.Log("_OnClubSLogOnReq 玩家重连,没找到俱乐部  nUserId_%d %s",nUserId,sErrStr)
                MsgApi.SendToClient(sClientID,"ClubSLogOnResp",{nRlt=PubErrCode.Login.NoClub,sErrStr=sErrStr})
                return
            end
            local tScence = tClub:GetScenceByUserId(nUserId)
            local tIfBinging = tClub:GetBingingByUserId(nUserId)
            local tFlag = PublicUserInfo.GetCodeSwitch(nGroupId)
            
            Base.Log("tIfBinging_%d,tFlag_%d",tIfBinging,tFlag)
            MsgApi.SendToClient(sClientID,"ClubSLogOnResp",{nRlt=PubErrCode.Login.Success,sErrStr="sucess",tScence=tScence,ifBinging=tIfBinging,nflag=tFlag})
            Base.Log("_OnClubSLogOnReq 玩家重连,回到以前的俱乐部中")
            return
        else
            Base.Log("_OnClubSLogOnReq 玩家重连,但不是回到以前的俱乐部,执行切换俱乐部流程 nNowClubId_%d nClubId_%d",nNowClubId,nClubId)
            local tNowClub = ClubSManager.GetClub(nNowClubId)
            if tNowClub then
                local isLeaveSuccee = tNowClub:Leave(nUserId)
                if not isLeaveSuccee then
                    --离开失败
                    Base.Log("_OnClubSLogOnReq 离开旧的俱乐部失败 nUserId_%d nNowClubId_%d",nUserId,nNowClubId)
                    MsgApi.SendToClient(sClientID,"ClubSLogOnResp",{nRlt=PubErrCode.Login.InOtherClub,sErrStr="in other Club, swicth fail"})
                    return
                end
            else
                Base.Log("_OnClubSLogOnReq 没找到旧的俱乐部,删除玩家的所在的俱乐部")
                tUser:DelNowClub()
            end
        end
    end

    MsgClient.HandleLogonClub(tUser,nClubId,inviteCode) 
end

--处理进入俱乐部
function MsgClient.HandleLogonClub(tUser,nClubId,inviteCode)
    local nGroupId = tUser.nGroupId
    local nUserId =  tUser.nUserId

    if nClubId == 0 then
        --如果nClubId为0，进入大厅，对应分组的大厅的id就是分组id
        nClubId = nGroupId
        Base.Log("_HandleLogonClub 请求登录对应分组的大厅，对应的nClubId_%d",nUserId,nClubId)
    end
  
    local nLastReqTime = SlaveData.tDBOprateWaitting.arrLogin[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_HandleLogonClub 请求过于频繁，等待上一个请求结束")
            MsgApi.SendToUser(nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.WaitDBReturn,sErrStr="too frequently,waitting last req return"})
            return
        end
    end
    SlaveData.tDBOprateWaitting.arrLogin[nUserId] = os.time()
    --进入俱乐部
    local tClub = ClubSManager.GetClub(nClubId)
    if not tClub then
        --没找到俱乐部
        local sErrStr = string.format("get Club_%d fail",nClubId)
        Base.Log("_HandleLogonClub 没找到俱乐部  nUserId_%d %s",nUserId,sErrStr)
        MsgApi.SendToUser(nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.NoClub,sErrStr=sErrStr})
        return
    end

    if tClub.nGroupId ~= nGroupId then
        --玩家分组与俱乐部分组不一致
        Base.Log("_HandleLogonClub 玩家分组与俱乐部分组不一致  (nUserId_%d nGroupId_%d) (Club_%d,nGroupId_%d)",nUserId,nGroupId,nClubId,tClub.nGroupId)
        MsgApi.SendToUser(nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.GroupErr,sErrStr="GroupErr"})
        return
    end

    Base.Log("_HandleLogonClub 向DB服请求登录 nUserId_%d nClubId_%d",nUserId,nClubId)
    MsgApi.SendToDBServer("ClubUserLogonReq",{nClubId=nClubId,nUserId=nUserId,nInviteCode=inviteCode},nUserId)
end

--DB服 玩家登录返回
function MsgClient.OnDBClubUserLogonRsp(sReturnKey, Data, nLen)
    local strProto = "ClubUserLogonRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubUserLogonRsp DB服 玩家登录返回 nRlt_%d,nClubId_%d nUserId_%d",tData.nRlt,tData.nClubId,tData.nUserId)

    local tUser = UserManager.GetUserInfo(tData.nUserId)
    if tUser then
        local nNowClubId = tUser:GetNowClub()
        if nNowClubId~=0 then
            Base.Log("_OnDBClubUserLogonRsp 玩家已经在俱乐部中 nNowClubId_%d nUserId_%d",nNowClubId,tData.nUserId)
            return
        end
    else
        Base.Log("_OnDBClubUserLogonRsp 玩家已不在本服了,不处理 nUserId_%d",tData.nUserId)
        SlaveData.tDBOprateWaitting.arrLogin[tData.nUserId] = nil
        return
    end

    Base.Log("是否为绑定用户_%d",tData.ifBinging)
    if tData.nRlt==1 then
        --登录成功
        local tClub = ClubSManager.GetClub(tData.nClubId)
        if not tClub then
            --没找到俱乐部
            local sErrStr = string.format("get Club_%d fail",tData.nClubId)
            Base.Log("_OnDBClubUserLogonRsp   nUserId_%d %s",tData.nUserId,sErrStr)
            MsgApi.SendToUser(tData.nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.NoClub,sErrStr=sErrStr})
            return
        end

        local tUserInfo = {}
        tUserInfo.nUserId = tData.tUserInfo.nUserId
        tUserInfo.sFaceId = tData.tUserInfo.sFaceId
        tUserInfo.sName = tData.tUserInfo.sName
        tUserInfo.nSex = tData.tUserInfo.nSex
        tUserInfo.nGold = tData.tUserInfo.nGold
        tUserInfo.nClubGold = tData.tUserInfo.nClubGold
        tUserInfo.nIdentify = tData.tUserInfo.nIdentify
        tUserInfo.nContribution = tData.tUserInfo.nContribution
        tUserInfo.nGoldContribution = tData.tUserInfo.nGoldContribution
        tUserInfo.nGroupId = tData.tUserInfo.nGroupId
        tUserInfo.sShopAcc = tData.tUserInfo.sShopAcc
        tUserInfo.ifBinging = tData.ifBinging
        tUserInfo.arrPower = {}

        -- if tUserInfo.nIdentify ~= Define.nMember and tData.nClubId >= Define.nMinClubId then
            local isSuccee,arrPower = pcall(Cjson.decode,tData.tUserInfo.sPower)
            if isSuccee then
                for k,v in pairs(arrPower) do
                    table.insert(tUserInfo.arrPower,{nPowerType=v.nPowerType,isOpen=v.isOpen})
                end
            else
                if type(arrPower) == "string" then
                    Logger:error(arrPower)
                else
                    Base.LogT(arrPower)
                end
            end
        -- end
        Base.Log("_OnDBClubUserLogonRsp 进入私人俱乐部 nUserId_%d nClubId_%d  nGroupId_%d  ",tUserInfo.nUserId,tData.nClubId,tUser.nGroupId)
        tClub:Enter(tUserInfo) --进入俱乐部

        local tScence = tClub:GetScenceByUserId(tData.nUserId)
        MsgApi.SendToUser(tData.nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.Success,sErrStr="success",tScence=tScence,ifBinging=tData.ifBinging,nflag=tFlag})
    elseif tData.nRlt==4 then
        --封禁玩家禁止登录
        Base.Log("_OnDBClubUserLogonRsp 封禁玩家禁止登录 nUserId_%d nClubId_%d ForbidEndTime:%s",tData.nUserId,tData.nClubId,tData.sExData or "")
        MsgApi.SendToUser(tData.nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.UserInBlackList,sErrStr=tData.sExData})
    elseif tData.nRlt==5 then
        --封禁IP禁止登录
        Base.Log("_OnDBClubUserLogonRsp 封禁IP禁止登录 nUserId_%d nClubId_%d ForbidEndTime:%s",tData.nUserId,tData.nClubId,tData.sExData or "")
        MsgApi.SendToUser(tData.nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.IPInBlackList,sErrStr=tData.sExData})
    elseif tData.nRlt==6 then
        --封禁GPS禁止登录
        Base.Log("_OnDBClubUserLogonRsp 封禁GPS禁止登录 nUserId_%d nClubId_%d ForbidEndTime:%s",tData.nUserId,tData.nClubId,tData.sExData or "")
        MsgApi.SendToUser(tData.nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.GPSInBlackList,sErrStr=tData.sExData})
    elseif tData.nRlt==12 then
        --邀请码出错
        Base.Log("_OnDBClubUserLogonRsp 邀请码错误 nUserId_%d nClubId_%d ForbidEndTime:%s",tData.nUserId,tData.nClubId,tData.sExData or "")
        MsgApi.SendToUser(tData.nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.InviteCodeError,sErrStr=tData.sExData})
    else
        --登录失败,不是该俱乐部成员
        Base.Log("_OnDBClubUserLogonRsp 登录失败,不是该俱乐部成员 nUserId_%d nClubId_%d",tData.nUserId,tData.nClubId)
        MsgApi.SendToUser(tData.nUserId,"ClubSLogOnResp",{nRlt=PubErrCode.Login.NoClubUser,sErrStr="not Club Member"})
    end

    SlaveData.tDBOprateWaitting.arrLogin[tData.nUserId] = nil
end

--切换俱乐部请求
function MsgClient.OnClubSSwitchReq(sClientID, Data, nLen)
    if not SlaveData.isInitFinish then
        Base.Log("_OnClubSSwitchReq 开服加载数据还没结束")
        return
    end

    local tData =SlaveAux:Parser(Data, nLen, "ClubSSwitchReq")
    if tData ==nil then
        Base.Log("ClubSSwitchReq _Parse Err")
        return
    end

    Base.Log("_OnClubSSwitchReq 切换俱乐部请求 nUserId_%d nNewClubId_%d",tData.nUserId,tData.nNewClubId)

    local ClubSSwitchResp = {
        nRlt = PubErrCode.Swicth.Success,
        sErrStr = "",
        nNowClubId=0,
        nNewClubId=tData.nNewClubId,
    }

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrLogin[tData.nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSSwitchReq 请求过于频繁，等待上一个请求结束")
            ClubSSwitchResp.nRlt = PubErrCode.Swicth.WaitDBReturn
            ClubSSwitchResp.sErrStr = "too frequently,waitting last req return"
            MsgApi.SendToUser(tData.nUserId,"ClubSSwitchResp",ClubSSwitchResp)
            return
        end
    end

    local tUser = UserManager.GetUserInfo(tData.nUserId)
    if not tUser then
        Base.Log("_OnClubSSwitchReq 玩家不在本服,通知其他从服清除玩家,本服走登录流程")
        local ClubCSwitchNotify = {}
        ClubCSwitchNotify.nUserId = tData.nUserId
        ClubCSwitchNotify.nNewClubId = tData.nNewClubId
        MsgApi.SendToSlaveServer("ClubCSwitchNotify",ClubCSwitchNotify,true)

        local ClubSLogOnReq = {}
        ClubSLogOnReq.nUserId = tData.nUserId
        ClubSLogOnReq.nClubId = tData.nNewClubId
        local tPacket =SlaveAux:Encode("ClubSLogOnReq",ClubSLogOnReq)
        MsgClient.OnClubSLogOnReq(sClientID,tPacket:GetData(),tPacket:GetSize())
        return
    end

    --离开旧的俱乐部
    local nNowClubId = tUser:GetNowClub()
    if nNowClubId~=0 then
        Base.Log("_OnClubSSwitchReq 离开旧的俱乐部 nUserId_%d nNowClubId_%d",tData.nUserId,nNowClubId)
        local tNowClub = ClubSManager.GetClub(nNowClubId)
        if tNowClub then
            local isLeaveSuccee = tNowClub:Leave(tData.nUserId)
            if not isLeaveSuccee then
                --离开失败
                Base.Log("_OnClubSSwitchReq 离开旧的俱乐部失败 nUserId_%d nNowClubId_%d",tData.nUserId,nNowClubId)
                ClubSSwitchResp.nRlt = PubErrCode.Swicth.LeaveFail
                ClubSSwitchResp.sErrStr = string.format("leave Club_%d fail",nNowClubId)
                MsgApi.SendToUser(tData.nUserId,"ClubSSwitchResp",ClubSSwitchResp)
                return
            end
        end
    else
        tUser:DelNowClub()
    end

    --走登录俱乐部的逻辑
    MsgClient.HandleLogonClub(tUser,tData.nNewClubId)
end

--获取玩家的俱乐部列表请求
function MsgClient.OnClubSGetUserClubListReq(sClientID, Data, nLen)
    if not SlaveData.isInitFinish then
        Base.Log("_OnClubSGetUserClubListReq 开服加载数据还没结束")
        return
    end
    
    local tData =SlaveAux:Parser(Data, nLen,"ClubSGetUserClubListReq")
    if tData ==nil then
        Base.Log("ClubSGetUserClubListReq _Parse Err")
        return
    end

    Base.Log("_OnClubSGetUserClubListReq 获取玩家的俱乐部列表请求 nUserId_%d",tData.nUserId)
    MsgApi.SendToDBServer("GetUserClubListReq",{nUserId=tData.nUserId,sClientID=sClientID},tData.nUserId)
end

--DB服返回 玩家俱乐部列表返回
function MsgClient.OnDBGetUserClubListRsp(sReturnKey, Data, nLen)
    local strProto = "GetUserClubListRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local nGroupId = -1 
    local tUserInfo =PublicUserInfo.GetAllUserInfo(tData.nUserId)
    if tUserInfo then
        local nShopId =tonumber(tUserInfo.nShopID) or -1
        nGroupId = GameConfig.GetGroupId(nShopId) or -1
    end

    local arrClub = {}
    for k,v in pairs(tData.arrClub) do
        if type(v.nClubId)=="number" then
            local t = {}
            t.nClubId = v.nClubId
            t.sClubName = v.sClubName
            t.nMaster = v.nMaster
            t.nIdentify = v.nIdentify or 0    -- 角色： 1:主席  10:管理员  20:普通成员 
            t.nClubGold = 0   -- 俱乐部币
            t.nTableCnt = 0   -- 桌数 
            local tClub = ClubSManager.GetClub(v.nClubId)
            if tClub then
                t.nClubGold = tClub.nClubGold    -- 俱乐部币
                t.nTableCnt = #tClub.arrTable or 0   -- 桌数 
            end
            table.insert(arrClub,t)
        end
    end
    local tConfig = PubClubApi.GetClubWebConfig(nGroupId)
    if not tConfig.IsOpenClub then
        arrClub = {}
    end
    if tConfig.IsOpenHall then
        local tClub = ClubSManager.GetClub(nGroupId)
        if tClub then
            local t = {}
            t.nClubId = 0
            t.sClubName = tClub.sClubName
            t.nMaster = tClub.nMaster 
            table.insert(arrClub,t)
        else
            Base.Log("_OnDBGetUserClubListRsp 没有对应的大厅 nGroupId_%d",nGroupId)
        end
    end
    Base.Log("_OnDBGetUserClubListRsp DB服返回 玩家俱乐部列表 nUserId_%d nGroupId_%d #arrClub_%d nPage_%d nAllPage_%d",
        tData.nUserId,nGroupId,#arrClub,tData.nPage,tData.nAllPage)

    local ClubSGetUserClubListResp = {}
    ClubSGetUserClubListResp.arrClub = arrClub
    ClubSGetUserClubListResp.nPage = tData.nPage
    ClubSGetUserClubListResp.nAllPage = tData.nAllPage
    MsgApi.SendToClient(tData.sClientID,"ClubSGetUserClubListResp",ClubSGetUserClubListResp)
end

--创建俱乐部请求
function MsgClient.OnClubSCreateReq(sClientID, Data, nLen)
    local strProto = "ClubSCreateReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSCreateReq 玩家信息不存在 nUserId:%d",nUserId)
        return
    end
    local nGroupId = tUser.nGroupId or -1

    Base.Log("_OnClubSCreateReq 创建俱乐部请求 nUserId_%d nGroupId_%d sClubName_%s nCanSearch_%d nCanApply_%d sPassWord_%s",
        nUserId,nGroupId,tData.sClubName,tData.nCanSearch,tData.nCanApply,tData.sPassWord)
    
    local nLastReqTime = SlaveData.tDBOprateWaitting.arrCreateClub[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSCreateReq 请求过于频繁，等待上一个请求结束")
            MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.WaitDBReturn,sErrStr="too frequently,waitting last req return"})
            return
        end
    end

    --参数校验
    if tData.nCanSearch~=0 and tData.nCanSearch~=1 then
        Base.Log("_OnClubSCreateReq 是否允许搜索错误")
        MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.ParamsErr,sErrStr="nCanSearch Err"})
        return
    end
    if tData.nCanApply~=0 and tData.nCanApply~=1 then
        Base.Log("_OnClubSCreateReq 是否允许申请错误")
        MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.ParamsErr,sErrStr="nCanApply Err"})
        return
    end
    if #tData.sClubName>Define.nNameLen then
        Base.Log("_OnClubSCreateReq 俱乐部名字过长")
        MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.NameTooLong,sErrStr="sClubName is toolong"})
        return
    end

    --校验俱乐部名称
    local isSucceeClub,sClubName = pcall(BaseSink.decode,tData.sClubName)
    if not isSucceeClub then
        Base.Log("_OnClubSCreateReq 俱乐部名称不是base64编码")
        MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.ParamsErr,sErrStr="sClubName Err"})
        if type(sClubName) == "string" then 
            Logger:error(sClubName)
        else 
            Base.LogT(sClubName) 
        end
        return
    end 

    --俱乐部名称是否是空字符串或者纯空格
    if not string.match(sClubName,"[^%s]") then
        Base.Log("_OnClubSCreateReq 俱乐部名称是空字符串或者纯空格")
        MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.ParamsErr,sErrStr="sClubName Err"})
        return
    end

    if PublicApi.CheckSpecailWords(sClubName) then
        Base.Log("_OnClubSCreateReq 俱乐部名称有特殊字符")
        MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.HasSpecailwords,sErrStr="sClubName has Specailwords"})
        return
    end
    if PublicApi.CheckSensitiveWords(sClubName) then
        Base.Log("_OnClubSCreateReq 俱乐部名称有敏感词")
        MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.HasSensitivewords,sErrStr="sClubName has Specailwords"})
        return
    end

    --校验库存密码
    local isSuccee,sPassWord = pcall(BaseSink.decode,tData.sPassWord)
    if not isSuccee then
        Base.Log("_OnClubSCreateReq 库存密码不是base64编码")
        MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.ParamsErr,sErrStr="sPassWord Err"})
        if type(sPassWord) == "string" then 
            Logger:error(sPassWord)
        else 
            Base.LogT(sPassWord) 
        end
        return
    end

    --库存密码不是数字或者过长
    if type(tonumber(sPassWord))~="number" or #sPassWord>Define.Len_PassWord then
        Base.Log("_OnClubSCreateReq 库存密码不是数字或者过长")
        MsgApi.SendToClient(sClientID,"ClubSCreateResp",{nRlt=PubErrCode.CreateClub.ParamsErr,sErrStr="sPassWord Err"})
        return
    end
    
    SlaveData.tDBOprateWaitting.arrCreateClub[nUserId] = os.time()

    local nLimitCnt = PubClubApi.GetUserCreateMaxCnt(nGroupId) --个人创建俱乐部的上限

    local sSql = string.format("call Club_Create(%d,'%s',%d,%d,%d,'%s',%d)",nGroupId,tData.sClubName,nUserId,tData.nCanSearch,tData.nCanApply,tData.sPassWord,nLimitCnt)
    Base.Log("_OnClubSCreateReq sSql:%s",sSql)

    local CreateClubReq = {}
    CreateClubReq.sSql = sSql
    CreateClubReq.nUserId = nUserId
    MsgApi.SendToDBServer("CreateClubReq",CreateClubReq,nUserId)
end

--DB服返回 创建俱乐部 返回
function MsgClient.OnDBCreateClubRsp(sReturnKey, Data, nLen)
    local strProto = "CreateClubRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBCreateClubRsp DB服返回 创建俱乐部 nUserId:%d nRlt:%d",tData.nUserId,tData.nRlt)

    local ClubSCreateResp = {}
    ClubSCreateResp.nRlt = PubErrCode.CreateClub.Success
    ClubSCreateResp.sErrStr = "success"
    if tData.nRlt==0 then
        local tClubItem = {}
        tClubItem.nClubId = tData.tClubItem.nClubId
        tClubItem.sClubName = tData.tClubItem.sClubName	  
        tClubItem.nMaster = tData.tClubItem.nMaster
        tClubItem.sFaceId = tData.tClubItem.sFaceId
        tClubItem.sName = tData.tClubItem.sName
        tClubItem.nSex = tData.tClubItem.nSex
        tClubItem.sShopAcc = tData.tClubItem.sShopAcc
        tClubItem.nClubGold = tData.tClubItem.nClubGold
        tClubItem.nCanApply = tData.tClubItem.nCanApply
        tClubItem.nCanSearch = tData.tClubItem.nCanSearch
        tClubItem.nUserCnt = tData.tClubItem.nUserCnt
        tClubItem.nGroupId = tData.tClubItem.nGroupId
        tClubItem.sCreateTime= tData.tClubItem.sCreateTime
        tClubItem.sPassWord = tData.tClubItem.sPassWord
        tClubItem.nApplyJionCnt = tData.tClubItem.nApplyJionCnt
        tClubItem.nApplyAddGoldCnt = tData.tClubItem.nApplyAddGoldCnt
        tClubItem.nApplyCutGoldCnt = tData.tClubItem.nApplyCutGoldCnt
        tClubItem.nGold = tData.tClubItem.nGold
        tClubItem.nIncome = tData.tClubItem.nIncome
        tClubItem.nGoldIncome = tData.tClubItem.nGoldIncome
        
        local sClubInfo = Cjson.encode(tClubItem)
        Base.Log("_OnDBCreateClubRsp 创建俱乐部成功 tClubItem_%s",sClubInfo)
        ClubSCreateResp.nClubId = tClubItem.nClubId
        if tClubItem.nClubId and tClubItem.nClubId>0 then
            local ClubCCreateSucessReq = {}
            ClubCCreateSucessReq.sClubInfo = sClubInfo
            MsgApi.SendToCenterServer("ClubCCreateSucessReq",ClubCCreateSucessReq)
        end
    elseif tData.nRlt==3 then
        Base.Log("_OnDBCreateClubRsp 俱乐部已存在")
        ClubSCreateResp.nRlt = PubErrCode.CreateClub.ClubExits
        ClubSCreateResp.sErrStr = "ClubName is exists"
    elseif tData.nRlt==7 then
        Base.Log("_OnDBCreateClubRsp 俱乐部已存在")
        ClubSCreateResp.nRlt = PubErrCode.CreateClub.LimtMax
        ClubSCreateResp.sErrStr = "club is max,not create"
    else
        Base.Log("_OnDBCreateClubRsp DB Err")
        ClubSCreateResp.nRlt = PubErrCode.CreateClub.DBERR
        ClubSCreateResp.sErrStr = "DB Error"
    end

    MsgApi.SendToUser(tData.nUserId,"ClubSCreateResp",ClubSCreateResp)
    SlaveData.tDBOprateWaitting.arrCreateClub[tData.nUserId] = nil
end

--搜索俱乐部请求
function MsgClient.OnClubSSearchReq(sClientID, Data, nLen)
    local strProto = "ClubSSearchReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("_OnClubSSearchReq 搜索俱乐部请求 nUserId_%d,str_%s",nUserId,tData.str)

    local isSuccee,sErr = pcall(BaseSink.decode,tData.str)
    if not isSuccee then
        Base.Log("_OnClubSSearchReq 搜索字符串不是base64编码")
        if type(sErr) == "string" then 
            Logger:error(sErr)
        else 
            Base.LogT(sErr) 
        end
        MsgApi.SendToClient(sClientID,"ClubSSearchResp",{arrItem={},nPage=0,nAllPage=0})
        return
    end

    local SearchClubReq = {}
    SearchClubReq.str = tData.str
    SearchClubReq.nUserId = nUserId
    MsgApi.SendToDBServer("SearchClubReq",SearchClubReq,nUserId)
end

--DB服返回 搜索俱乐部返回
function MsgClient.OnDBSearchClubRsp(sReturnKey, Data, nLen)
    local strProto = "SearchClubRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrItem = {}
    for k,v in pairs(tData.arrItem) do
        local tItem = {}
        for a, b in pairs(ProtoManager.DbServerClub_pb.ClubSearchItem()._setter) do
            tItem[a] = v[a]
        end
        if tItem.nClubId and tItem.nClubId>0 then
            local nMaxUserCnt = 0
            local tConfig = PubClubApi.GetClubWebConfig(tItem.nGroupId)
            if tConfig then
                nMaxUserCnt = tConfig.nMaxUserCnt
            end

            local tClubItem = {}
            tClubItem.nClubId = tItem.nClubId
            tClubItem.sClubName = tItem.sClubName
            tClubItem.sMasterName = tItem.sMasterName
            tClubItem.nUserCnt = tItem.nUserCnt
            tClubItem.nMaxUserCnt = nMaxUserCnt
            tClubItem.nStatus = tItem.nStatus
            tClubItem.nMaster = tItem.nMaster

            table.insert(arrItem,tClubItem)
        end
    end

    Base.Log("_OnDBSearchClubRsp DB服返回 搜索俱乐部 nUserId_%d #arrItem_%d nPage_%d nAllPage_%d",tData.nUserId,#arrItem,tData.nPage,tData.nAllPage)

    local ClubSSearchResp = {}
    ClubSSearchResp.arrItem = arrItem
    ClubSSearchResp.nPage = tData.nPage
    ClubSSearchResp.nAllPage = tData.nAllPage
    MsgApi.SendToUser(tData.nUserId,"ClubSSearchResp",ClubSSearchResp)
end

--申请加入俱乐部请求
function MsgClient.OnClubSApplyReq(sClientID, Data, nLen)
    local strProto = "ClubSApplyReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSApplyReq 申请加入俱乐部请求 nUserId_%d nClubId_%d",nUserId,tData.nClubId)

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSApplyReq 玩家信息不存在")
        return
    end
    local nGroupId = tonumber(tUser.nGroupId) or -1

    --参数校验
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSApplyReq 大厅无需申请加入")
        MsgApi.SendToClient(sClientID,"ClubSApplyResp",{nRlt=PubErrCode.ApplyJoin.ParamsErr,sErrStr="club is hall"})
        return
    end

    local tClubUserInfo = PublicRedis.GetClubUserInfo(tData.nClubId,nUserId)
    if tClubUserInfo then
        Base.Log("_OnClubSApplyReq 已经是俱乐部成员")
        MsgApi.SendToClient(sClientID,"ClubSApplyResp",{nRlt=PubErrCode.ApplyJoin.IsInClub,sErrStr="is Club member"})
        return
    end

    local nLimitCnt = PubClubApi.GetUserApplyMaxCnt(nGroupId) --加入俱乐部申请的数量上限

    --发送到DB服
    MsgApi.SendToDBServer("ApplyJoinClubReq",{nClubId=tData.nClubId,nUserId=nUserId,nLimitCnt=nLimitCnt,nGroupId=nGroupId},nUserId)
end

--DB服返回 申请加入俱乐部 返回
function MsgClient.OnDBApplyJoinClubRsp(sReturnKey, Data, nLen)
    local strProto = "ApplyJoinClubRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBApplyJoinClubRsp DB服返回 申请加入俱乐部 nUserId_%d,nClubId_%d,nRlt_%d",tData.nUserId,tData.nClubId,tData.nRlt)

    local ClubSApplyResp = {}
    ClubSApplyResp.nRlt = PubErrCode.ApplyJoin.Success
    ClubSApplyResp.sErrStr = "Success"
    if tData.nRlt==0 then
        Base.Log("_OnDBApplyJoinClubRsp 申请成功，目前俱乐部未处理申请 nApplyJionCnt_%d",tData.nApplyCnt)
        --发送俱乐部场景信息改变
        MsgApi.SendClubInfoChange(tData.nClubId,{nApplyJionCnt = tData.nApplyCnt})
    elseif tData.nRlt==2 then
        Base.Log("_OnDBApplyJoinClubRsp 俱乐部不存在")
        ClubSApplyResp.nRlt = PubErrCode.ApplyJoin.NoClub
        ClubSApplyResp.sErrStr = "not find Club"
    elseif tData.nRlt==3 then
        Base.Log("_OnDBApplyJoinClubRsp 已申请过了")
        ClubSApplyResp.nRlt = PubErrCode.ApplyJoin.HadApply
        ClubSApplyResp.sErrStr = "already apply"
    elseif tData.nRlt==4 then
        Base.Log("_OnDBApplyJoinClubRsp 俱乐部设置不能申请")
        ClubSApplyResp.nRlt = PubErrCode.ApplyJoin.CanNotApply
        ClubSApplyResp.sErrStr = "could not apply"
    elseif tData.nRlt==6 then
        Base.Log("_OnDBApplyJoinClubRsp 玩家与俱乐部不是同一个分组")
        ClubSApplyResp.nRlt = PubErrCode.ApplyJoin.GroupErr
        ClubSApplyResp.sErrStr = "not Same Group"
    elseif tData.nRlt==7 then
        Base.Log("_OnDBApplyJoinClubRsp 在黑名单中")
        ClubSApplyResp.nRlt = PubErrCode.ApplyJoin.InBlackList
        ClubSApplyResp.sErrStr = "in Club BlackList"
    elseif tData.nRlt==8 then
        Base.Log("_OnDBApplyJoinClubRsp 申请达到上限")
        ClubSApplyResp.nRlt = PubErrCode.ApplyJoin.LimtMax
        ClubSApplyResp.sErrStr = "ApplyCnt is Max"
    else
        Base.Log("_OnDBApplyJoinClubRsp DB Err")
        ClubSApplyResp.nRlt = PubErrCode.ApplyJoin.DBERR
        ClubSApplyResp.sErrStr = "DB Err"
    end
    MsgApi.SendToUser(tData.nUserId,"ClubSApplyResp",ClubSApplyResp)
end

--修改俱乐部信息请求
function MsgClient.OnClubSChangeInfoReq(sClientID, Data, nLen)
    local strProto = "ClubSChangeInfoReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSChangeInfoReq 修改俱乐部信息请求 nClubId_%d nUserId_%d",tData.nClubId,nUserId)

    local nClubId = tData.nClubId
    local arrItem = tData.arrItem

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrChangeClubInfo[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSChangeInfoReq 请求过于频繁，等待上一个请求结束")
            MsgApi.SendToClient(sClientID,"ClubSChangeInfoResp",{nClubId=nClubId,arrRlt={},nRlt=1})
            return
        end
    end

    local arrNotChange = {}
    local arrChange = {}
    local tPassWord = {}
    
    for k,v in pairs(arrItem) do
        if v.sKey == "sClubName" then
            local isSuccee,sClubName = pcall(BaseSink.decode,v.sVal)
            if isSuccee and string.match(sClubName,"[^%s]") then
                if PublicApi.CheckSpecailWords(sClubName) then
                    table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.HasSpecailwords,sKey="sClubName"})
                    Base.Log("_OnClubSChangeInfoReq 俱乐部名称有特殊字符. sClubName_%s",v.sVal)
                elseif PublicApi.CheckSensitiveWords(sClubName) then
                    table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.HasSensitivewords,sKey="sClubName"})
                    Base.Log("_OnClubSChangeInfoReq 俱乐部名称有敏感词. sClubName_%s",v.sVal)
                else
                    table.insert(arrChange,{sKey="sClubName",Value=v.sVal})
                end
            else
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.ParamsErr,sKey="sClubName"})
                Base.Log("_OnClubSChangeInfoReq 俱乐部名称不符合要求. sClubName_%s",v.sVal)
                if not isSuccee then
                    if type(sClubName) == "string" then 
                        Logger:error(sClubName)
                    else 
                        Base.LogT(sClubName) 
                    end
                end
            end
            if #v.sVal>Define.nNameLen then
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.NameTooLong,sKey="sClubName"})
                Base.Log("_OnClubSChangeInfoReq 俱乐部名称过长. sClubName_%s",v.sVal)
            end
        end
        if v.sKey == "nCanSearch" then
            if tonumber(v.sVal)==0 or tonumber(v.sVal)==1 then
                table.insert(arrChange,{sKey="nCanSearch",Value=v.sVal})
            else
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.ParamsErr,sKey="nCanSearch"})
                Base.Log("_OnClubSChangeInfoReq 是否能搜索不符合要求. nCanSearch_%d",nUserId,nClubId,tonumber(v.sVal) or -1)
            end
        end
        if v.sKey == "nCanApply" then 
            if tonumber(v.sVal)==0 or tonumber(v.sVal)==1 then
                table.insert(arrChange,{sKey="nCanApply",Value=v.sVal})
            else
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.ParamsErr,sKey="nCanApply"})
                Base.Log("_OnClubSChangeInfoReq 是否能申请不符合要求. nCanApply_%d",nUserId,nClubId,tonumber(v.sVal) or -1)
            end
        end
        if v.sKey == "sNewPassWord" and #v.sVal>0 then
            local isSuccee1,sNewPassWord1 = pcall(BaseSink.decode,v.sVal)
            local sNewPassWord = tonumber(sNewPassWord1)
            if isSuccee1 and type(sNewPassWord)=="number" and #sNewPassWord1<=Define.Len_PassWord then
                tPassWord.sNewPassWord = v.sVal
            else
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.ParamsErr,sKey="sPassWord"})
                Base.Log("_OnClubSChangeInfoReq 新的库存密码不符合要求. sNewPassWord_%s",nUserId,nClubId,v.sVal)
                if not isSuccee1 then
                    if type(sNewPassWord1) == "string" then 
                        Logger:error(sNewPassWord1)
                    else 
                        Base.LogT(sNewPassWord1) 
                    end
                end 
            end
        end
        if v.sKey == "sOldPassWord" and #v.sVal>0 then
            local isSuccee2,sOldPassWord1 = pcall(BaseSink.decode,v.sVal)
            local sOldPassWord = tonumber(sOldPassWord1)
            if isSuccee2 and type(sOldPassWord)=="number" and #sOldPassWord1<=Define.Len_PassWord then
                tPassWord.sOldPassWord = v.sVal
            else
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.ParamsErr,sKey="sPassWord"})
                Base.Log("_OnClubSChangeInfoReq 旧的库存密码不符合要求. sOldPassWord_%s",nUserId,nClubId,v.sVal)
                if not isSuccee2 then
                    if type(sOldPassWord1) == "string" then 
                        Logger:error(sOldPassWord1)
                    else 
                        Base.LogT(sOldPassWord1) 
                    end
                end
            end
        end
    end

    if tPassWord.sNewPassWord and tPassWord.sOldPassWord then
        table.insert(arrChange,{sKey="sNewPassWord",Value=tPassWord.sNewPassWord})
        table.insert(arrChange,{sKey="sOldPassWord",Value=tPassWord.sOldPassWord})
    elseif tPassWord.sNewPassWord and not tPassWord.sOldPassWord then
        Base.Log("_OnClubSChangeInfoReq 缺少旧的库存密码")
        --判断有没有库存密码错误的返回，如果没有就加上
        local isNeedPassWordErr = true
        for k,v in pairs(arrNotChange) do
            if v.sKey=="sPassWord" then
                isNeedPassWordErr = true
                break
            end
        end
        if isNeedPassWordErr then
            table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.ParamsErr,sKey="sPassWord"})
        end
    elseif not tPassWord.sNewPassWord and tPassWord.sOldPassWord then
        Base.Log("_OnClubSChangeInfoReq 缺少新的库存密码")
        --判断有没有库存密码错误的返回，如果没有就加上 
        local isNeedPassWordErr = true
        for k,v in pairs(arrNotChange) do
            if v.sKey=="sPassWord" then
                isNeedPassWordErr = true
                break
            end
        end
        if isNeedPassWordErr then
            table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.ParamsErr,sKey="sPassWord"})
        end
    end
    
    
    Base.Log("_OnClubSChangeInfoReq 参数校验成功的项arrChange_%s 参数校验失败的项arrNotChange_%s",Cjson.encode(arrChange),Cjson.encode(arrNotChange))

    --有不符合修改的项，不进行修改
    if #arrNotChange>0 then
        Base.Log("_OnClubSChangeInfoReq 有不符合修改的项，不进行修改 arrNotChange_%s",Cjson.encode(arrNotChange))
        MsgApi.SendToClient(sClientID,"ClubSChangeInfoResp",{nClubId=nClubId,arrRlt=arrNotChange,nRlt=1})
        return
    end

    local tClub = ClubSManager.GetClub(nClubId)
    if not tClub then
        Base.Log("_OnClubSChangeInfoReq 俱乐部不存在，不进行修改")
        for k,v in pairs(arrChange) do
            table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.NoClub,sKey=v.sKey})
        end
        MsgApi.SendToClient(sClientID,"ClubSChangeInfoResp",{nClubId=nClubId,arrRlt=arrNotChange,nRlt=1})
        return
    end

    if tClub.nMaster~=nUserId then
        Base.Log("_OnClubSChangeInfoReq 不是主席，不进行修改 nMaster_%d",tClub.nMaster)
        for k,v in pairs(arrChange) do
            table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.NoPower,sKey=v.sKey})
        end
        MsgApi.SendToClient(sClientID,"ClubSChangeInfoResp",{nClubId=nClubId,arrRlt=arrNotChange,nRlt=1})
        return
    end

    local arrNeedChange = {}
    for k,v in pairs(arrChange) do
        if v.sKey=="sClubName" then
            if v.Value==tClub.sClubName then
                Base.Log("_OnClubSChangeInfoReq 新的俱乐部名字与旧的相同，不进行修改 Value_%s sClubName_%s",v.Value,tClub.sClubName)
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.SameVal,sKey=v.sKey})
            else
                table.insert(arrNeedChange,{sKey=v.sKey,sVal=v.Value})
            end
        elseif v.sKey=="nCanSearch" then
            if tonumber(v.Value)==tClub.nCanSearch then
                Base.Log("_OnClubSChangeInfoReq 可搜索设置与旧的相同，不进行修改 Value_%s nCanSearch_%d",v.Value,tClub.nCanSearch)
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.SameVal,sKey=v.sKey})
            else
                table.insert(arrNeedChange,{sKey=v.sKey,sVal=v.Value})
            end
        elseif v.sKey=="nCanApply" then
            if tonumber(v.Value)==tClub.nCanApply then
                Base.Log("_OnClubSChangeInfoReq 可申请设置与旧的相同，不进行修改 Value_%s nCanApply_%d",v.Value,tClub.nCanApply)
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.SameVal,sKey=v.sKey})
            else
                table.insert(arrNeedChange,{sKey=v.sKey,sVal=v.Value})
            end
        elseif v.sKey=="sNewPassWord" then
            if v.Value==tClub.sPassWord then
                Base.Log("_OnClubSChangeInfoReq 新的库存密码与旧密码相同，不进行修改 Value_%s sPassWord_%s",v.Value,tClub.sPassWord)
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.SameVal,sKey="sPassWord"})
            else
                table.insert(arrNeedChange,{sKey=v.sKey,sVal=v.Value})
            end
        elseif v.sKey=="sOldPassWord" then
            if v.Value~=tClub.sPassWord then --旧的库存密码不正确
                Base.Log("_OnClubSChangeInfoReq 旧的库存密码不正确，不进行修改 Value_%s sPassWord_%s",v.Value,tClub.sPassWord)
                table.insert(arrNotChange,{nRlt=PubErrCode.ChangeClubInfo.PassWordErr,sKey="sPassWord"})
            else
                table.insert(arrNeedChange,{sKey=v.sKey,sVal=v.Value})
            end
        end
    end

    --有相同的项，不进行修改
    if #arrNotChange>0 then
        Base.Log("_OnClubSChangeInfoReq 有相同的项，不进行修改 arrNotChange_%s",Cjson.encode(arrNotChange))
        MsgApi.SendToClient(sClientID,"ClubSChangeInfoResp",{nClubId=nClubId,arrRlt=arrNotChange,nRlt=1})
        return
    end

    SlaveData.tDBOprateWaitting.arrChangeClubInfo[nUserId] = os.time()

    Base.Log("_OnClubSChangeInfoReq arrNeedChange_%s",Cjson.encode(arrNeedChange))

    local ChangeClubInfoReq = {}
    ChangeClubInfoReq.nClubId = nClubId
    ChangeClubInfoReq.nUserId = nUserId
    ChangeClubInfoReq.arrItem = arrNeedChange
    MsgApi.SendToDBServer("ChangeClubInfoReq",ChangeClubInfoReq,nUserId)
end

--DB服返回 修改俱乐部信息 返回
function MsgClient.OnDBChangeClubInfoRsp(sReturnKey, Data, nLen)
    local strProto = "ChangeClubInfoRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local nClubId = tData.nClubId
    local nUserId = tData.nUserId
    local arrRlt = {}
    for k,v in pairs(tData.arrRlt) do
        if v.sKey=="sClubName" then
            table.insert(arrRlt,{nRlt=v.nRlt,sKey="sClubName",sValue=v.sValue})
        elseif v.sKey=="nCanSearch" then
            table.insert(arrRlt,{nRlt=v.nRlt,sKey="nCanSearch",sValue=v.sValue})
        elseif v.sKey=="nCanApply" then
            table.insert(arrRlt,{nRlt=v.nRlt,sKey="nCanApply",sValue=v.sValue})
        elseif v.sKey=="sPassWord" then
            table.insert(arrRlt,{nRlt=v.nRlt,sKey="sPassWord",sValue=v.sValue})
        end
    end

    Base.Log("_OnDBChangeClubInfoRsp DB服返回 修改俱乐部信息 nUserId_%d,nClubId_%d,arrRlt_%s",nUserId,nClubId,Cjson.encode(arrRlt))

    local tChangeInfo = {}

    local isChangeSuccess = false
    --通知玩家修改结果
    local arrRlt_Client = {}
    local nRlt = 0
    for k,v in pairs(arrRlt) do
        table.insert(arrRlt_Client,{nRlt=v.nRlt,sKey=v.sKey})
        if v.nRlt==PubErrCode.ChangeClubInfo.Success then
            --成功的
            isChangeSuccess= true
            if v.sKey=="sClubName" then
                tChangeInfo.sClubName = v.sValue
            elseif v.sKey=="nCanSearch" then
                tChangeInfo.nCanSearch = tonumber(v.sValue)
            elseif v.sKey=="nCanApply" then
                tChangeInfo.nCanApply = tonumber(v.sValue)
            elseif v.sKey=="sPassWord" then   
                tChangeInfo.sPassWord = v.sValue 
            end
        else
            nRlt = 1
        end
    end
    MsgApi.SendToUser(nUserId,"ClubSChangeInfoResp",{nClubId=nClubId,arrRlt=arrRlt_Client,nRlt=nRlt})

    --把修改成功后的值发到中心服
    if isChangeSuccess then
        Base.Log("_OnDBChangeClubInfoRsp 场景信息改变 ClubSceneChange_%s",Cjson.encode(tChangeInfo))
        --发送俱乐部场景信息改变
        MsgApi.SendClubInfoChange(nClubId,tChangeInfo)
    end

    SlaveData.tDBOprateWaitting.arrChangeClubInfo[nUserId] = nil
end

--俱乐部成员请求
function MsgClient.OnClubSMembersReq(sClientID, Data, nLen)
    local strProto = "ClubSMembersReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSMembersReq 俱乐部成员请求 nUserId_%d nClubId_%d nCnt_%d nPage_%d",nUserId,tData.nClubId,tData.nCnt,tData.nPage)
    -- if tData.nClubId < Define.nMinClubId then
    --     Base.Log("_OnClubSMembersReq  大厅不能获取成员")
    --     MsgApi.SendToClient(sClientID,"ClubSMembersResp",{arrUser={},nPage=0,nUserCnt=0,nMaxUserCnt=0})
    --     return
    -- end
    local tUser = UserManager.GetUserInfo(nUserId)
    if tData.nClubId < Define.nMinClubId then
        tData.nClubId = tUser.nGroupId
    end

    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSMembersReq 俱乐部不存在")
        MsgApi.SendToClient(sClientID,"ClubSMembersResp",{arrUser={},nPage=0,nUserCnt=0,nMaxUserCnt=0})
        return
    end
    local nCnt = tData.nCnt
    local nPage = tData.nPage
    if tData.nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end
    if nPage<=0 then
        nPage = 1
    end
    -- local result = tClub:GetPageUsers(tData.nPage,tData.nCnt)
    -- local arrUser = {}
    -- for k,v in pairs(result.arrUser) do
    --     if v.nUserId and v.nUserId > 0 then
    --         local tItem = {}
    --         tItem.nUserId = v.nUserId
    --         tItem.sFaceId = v.sFaceId
    --         tItem.sName = v.sName
    --         tItem.nSex = v.nSex
    --         tItem.nClubId = v.nClubId or tData.nClubId
    --         tItem.nIdentify = v.nIdentify
    --         tItem.nContribution = v.nContribution
    --         tItem.nGoldContribution = v.nGoldContribution
    --         tItem.nClubGold = v.nClubGold
    --         tItem.sShopAcc = v.sShopAcc
    --         tItem.nWeekCount = v.nWeekCount
    --         tItem.nCreateTime = v.nCreateTime
    --         table.insert(arrUser,tItem)
    --     end
    -- end
    -- local ClubSMembersResp = {}
    -- ClubSMembersResp.arrUser = arrUser
    -- ClubSMembersResp.nPage = result.page
    -- ClubSMembersResp.nUserCnt = result.total
    -- ClubSMembersResp.nMaxUserCnt = result.nMaxUserCnt
    -- MsgApi.SendToUser(nUserId, "ClubSMembersResp", ClubSMembersResp)

    local ClubMembersReq = {}
    ClubMembersReq.nClubId = tData.nClubId
    ClubMembersReq.nCnt = nCnt
    ClubMembersReq.nUserId = nUserId
    ClubMembersReq.nPage = nPage
    ClubMembersReq.nShopId = tUser.nShopId
    MsgApi.SendToDBServer("ClubMembersReq",ClubMembersReq,nUserId)
end

--DB服返回 大厅成员返回
function MsgClient.OnDBClubMembersRsp(sReturnKey, Data, nLen)
    local strProto = "ClubMembersRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end
    local nMaxUserCnt = 0
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if tClub then
        nMaxUserCnt = tClub.nMaxUserCnt
    end

    local arrUser = {}
    for k,v in ipairs(tData.arrUser) do
        if v.nUserId and v.nUserId>0 then
            local tItem = {}
            tItem.nUserId = v.nUserId
            tItem.sFaceId = v.sFaceId
            tItem.sName = v.sName
            tItem.nSex = v.nSex
            tItem.nClubId = v.nClubId
            tItem.nIdentify = v.nIdentify
            tItem.nContribution = v.nContribution
            tItem.nGoldContribution = v.nGoldContribution
            tItem.nClubGold = v.nClubGold
            tItem.sShopAcc = v.sShopAcc
            tItem.nWeekCount = 0
            tItem.nCreateTime = v.nCreateTime
            table.insert(arrUser,tItem)
        end
    end

    Base.Log("_OnDBClubMembersRsp nClubId_%d nUserId_%d #arrUser_%d nPage_%d nUserCnt_%d nMaxUserCnt_%d",
        tData.nClubId,tData.nUserId,#arrUser,tData.nPage,tData.nUserCnt,nMaxUserCnt)

    local ClubSMembersResp = {}
    ClubSMembersResp.arrUser = arrUser
    ClubSMembersResp.nPage = tData.nPage
    ClubSMembersResp.nUserCnt = tData.nUserCnt
    ClubSMembersResp.nMaxUserCnt = nMaxUserCnt
    MsgApi.SendToUser(tData.nUserId,"ClubSMembersResp",ClubSMembersResp)
end

--DB服返回 俱乐部成员 返回
function MsgClient.OnDBClubMembersRsp_old(sReturnKey, Data, nLen)
    local strProto = "ClubMembersRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local nMaxUserCnt = 0
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if tClub then
        nMaxUserCnt = tClub.nMaxUserCnt
    end

    local arrUser = {}
    for k,v in pairs(tData.arrUser) do
        if v.nUserId and v.nUserId>0 then
            local tItem = {}
            tItem.nUserId = v.nUserId
            tItem.sFaceId = v.sFaceId
            tItem.sName = v.sName
            tItem.nSex = v.nSex
            tItem.nClubId = v.nClubId
            tItem.nIdentify = v.nIdentify
            tItem.nContribution = v.nContribution
            tItem.nGoldContribution = v.nGoldContribution
            tItem.nClubGold = v.nClubGold
            tItem.sShopAcc = v.sShopAcc
            tItem.nWeekCount = PublicRedis.GetClubUserWeekCount(v.nClubId,v.nUserId)
            table.insert(arrUser,tItem)
        end
    end

    Base.Log("_OnDBClubMembersRsp nClubId_%d nUserId_%d #arrUser_%d nPage_%d nUserCnt_%d nMaxUserCnt_%d",
        tData.nClubId,tData.nUserId,#arrUser,tData.nPage,tData.nUserCnt,nMaxUserCnt)

    local ClubSMembersResp = {}
    ClubSMembersResp.arrUser = arrUser
    ClubSMembersResp.nPage = tData.nPage
    ClubSMembersResp.nUserCnt = tData.nUserCnt
    ClubSMembersResp.nMaxUserCnt = nMaxUserCnt
    MsgApi.SendToUser(tData.nUserId,"ClubSMembersResp",ClubSMembersResp)
end

--搜索俱乐部成员请求
function MsgClient.OnClubSSearchMemberReq(sClientID, Data, nLen)
    local strProto = "ClubSSearchMemberReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSSearchMemberReq 搜索俱乐部成员请求 nUserId_%d,str_%s,nClubId_%d",nUserId,tData.str,tData.nClubId)
    -- 现在是大厅先屏蔽
    -- if tData.nClubId < Define.nMinClubId then
    --     Base.Log("_OnClubSSearchMemberReq club is hall")
    --     MsgApi.SendToClient(sClientID,"ClubSSearchMemberResp",{arrUser={},nPage=0,nAllPage=0})
    --     return
    -- end

    if tData.str == "" then
        Base.Log("_OnClubSSearchMemberReq str is empty")
        MsgApi.SendToClient(sClientID,"ClubSSearchMemberResp",{arrUser={},nPage=0,nAllPage=0})
        return
    end

    local isSuccee, sErr = pcall(BaseSink.decode, tData.str)
    if not isSuccee then
        Base.Log("_OnClubSSearchMemberReq str is not Base64Encode")
        if type(sErr) == "string" then
            Logger:error(sErr)
        else 
            Base.LogT(sErr)
        end
        MsgApi.SendToClient(sClientID,"ClubSSearchMemberResp",{arrUser={},nPage=0,nAllPage=0})
        return
    end

    local SearchClubMemberReq = {}
    SearchClubMemberReq.str = tData.str
    SearchClubMemberReq.nUserId = nUserId
    SearchClubMemberReq.nClubId = tData.nClubId
    MsgApi.SendToDBServer("SearchClubMemberReq",SearchClubMemberReq,nUserId)
end

--DB服返回 搜索俱乐部成员返回
function MsgClient.OnDBSearchClubMemberRsp(sReturnKey, Data, nLen)
    local strProto = "SearchClubMemberRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrUser = {}
    for k,v in pairs(tData.arrUser) do
        if v.nUserId and v.nUserId>0 then
            local tItem = {}
            tItem.nUserId = v.nUserId
            tItem.sFaceId = v.sFaceId
            tItem.sName = v.sName
            tItem.nSex = v.nSex
            tItem.nClubId = v.nClubId
            tItem.nIdentify = v.nIdentify
            tItem.nContribution = v.nContribution
            tItem.nGoldContribution = v.nGoldContribution
            tItem.nClubGold = v.nClubGold
            tItem.sShopAcc = v.sShopAcc
            -- tItem.nWeekCount = PublicRedis.GetClubUserWeekCount(v.nClubId,v.nUserId)
            tItem.nWeekCount = v.nWeekCount or 0
            tItem.nCreateTime = v.nCreateTime
            table.insert(arrUser,tItem)
        end
    end

    Base.Log("_OnDBSearchClubMemberRsp nUserId_%d #arrUser_%d nPage_%d nAllPage_%d",
        tData.nUserId,#arrUser,tData.nPage,tData.nAllPage)

    local ClubSSearchMemberResp = {}
    ClubSSearchMemberResp.arrUser = arrUser
    ClubSSearchMemberResp.nPage = tData.nPage
    ClubSSearchMemberResp.nAllPage = tData.nAllPage
    MsgApi.SendToUser(tData.nUserId,"ClubSSearchMemberResp",ClubSSearchMemberResp)
end

--管理员操作请求
function MsgClient.OnClubSOperateReq(sClientID, Data, nLen)
    local strProto = "ClubSOperateReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSOperateReq nClubId:%d nUserId:%d nTUserId:%d nType:%d nChange:%f sPassWord:%s",
    tData.nClubId,nUserId,tData.nTUserId,tData.nType,tData.nChange or 0,tData.sPassWord or "")

    MsgClient.HandleAdminOperate(nUserId,tData)
end

--处理管理员操作
function MsgClient.HandleAdminOperate(nUserId,tData)
    local ClubSOperateResp = {nRlt=PubErrCode.AdminOprate.Success,sErrStr="",nTUserId=tData.nTUserId,nType=tData.nType,nClubId=tData.nClubId}

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrAdminOprate[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_HandleAdminOperate 请求过于频繁，等待上一个请求结束")
            ClubSOperateResp.nRlt = PubErrCode.AdminOprate.WaitDBReturn
            ClubSOperateResp.sErrStr = "too frequently,waitting last req return"
            MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
            return
        end
    end

    --不是私人俱乐部
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_HandleAdminOperate club is hall")
        ClubSOperateResp.nRlt = PubErrCode.AdminOprate.NoClub
        ClubSOperateResp.sErrStr="club is hall"
        MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
        return
    end

    --俱乐部是否存在
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_HandleAdminOperate not find club")
        ClubSOperateResp.nRlt = PubErrCode.AdminOprate.NoClub
        ClubSOperateResp.sErrStr="not find club"
        MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
        return
    end

    --被操作玩家是否是俱乐部成员
    local tTargetUser = PublicRedis.GetClubUserInfo(tData.nClubId,tData.nTUserId)
    if not tTargetUser then
        Base.Log("_HandleAdminOperate TargetUser is not in Club")
        ClubSOperateResp.nRlt = PubErrCode.AdminOprate.NoClubUser
        ClubSOperateResp.sErrStr="TargetUser is not in Club"
        MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
        return
    end

    --是否还有未处理的操作
    local isUnDeal = MsgOnTime.HasUnDealMsg({nClubId=tData.nClubId,nTUserId=tData.nTUserId,nType=tData.nType,nOpUserId=nUserId})
    if isUnDeal then
        Base.Log("_HandleAdminOperate has undeal opration")
        ClubSOperateResp.nRlt=5
        ClubSOperateResp.sErrStr="has undeal opration"
        MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
        return
    end

    --操作玩家是否是俱乐部成员
    local tAdmin = PublicRedis.GetClubUserInfo(tData.nClubId,nUserId)
    if not tAdmin then
        tClub:Print("_HandleAdminOperate not find tAdmin in Club")
        ClubSOperateResp.nRlt = PubErrCode.AdminOprate.NotAdmin
        ClubSOperateResp.sErrStr = "not find tAdmin in Club"
        MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
        return
    end
    --操作玩家是否是管理员或者主席
    if tAdmin.nIdentify~=Define.nMaster and tAdmin.nIdentify~=Define.nAdmin then
        tClub:Print("_HandleAdminOperate you not admin, nUserId:%d nIdentify:%d",nUserId,tAdmin.nIdentify)
        ClubSOperateResp.nRlt = PubErrCode.AdminOprate.NotAdmin
        ClubSOperateResp.sErrStr = "you not admin"
        MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
        return
    end

    --管理员权限
    local isSuccee,arrPower = pcall(Cjson.decode,tAdmin.sPower)
    if not isSuccee then
        tClub:Print("_HandleAdminOperate decode tAdmin:%d sPower fail, sPower:%s",nUserId,tostring(tAdmin.sPower))
        arrPower = {}
    end

    local nPowerType = 0

    if tData.nType==1 or tData.nType==2 then
        nPowerType = Define.tPower.ClubGold
    
        --参数校验
        if tData.nChange<=0 then
            tClub:Print("_HandleAdminOperate nChange Err")
            ClubSOperateResp.nRlt = PubErrCode.AdminOprate.ParamsErr
            ClubSOperateResp.sErrStr = "nChange Err"
            MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
            return
        end

        --检查操作者和被操者身份
        if tAdmin.nIdentify==Define.nAdmin then
            --操作者是管理员
            if tTargetUser.nIdentify==Define.nAdmin and tData.nTUserId~=nUserId then
                --被操者身份是另外一个管理员
                tClub:Print("_HandleAdminOperate 被操者身份是另外一个管理员")
                ClubSOperateResp.nRlt = PubErrCode.AdminOprate.TargetIsOtherAdmin
                ClubSOperateResp.sErrStr = "you can not oprated other admin"
                MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
                return
            elseif tTargetUser.nIdentify==Define.nMaster then
                --被操者身份是主席
                tClub:Print("_HandleAdminOperate 被操者身份是主席")
                ClubSOperateResp.nRlt = PubErrCode.AdminOprate.TargetIsMaser
                ClubSOperateResp.sErrStr = "you can not oprated master"
                MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
                return
            end
        end

        --检查库存密码是否正确
        if tClub.sPassWord~=tData.sPassWord then
            tClub:Print("_HandleAdminOperate sPassWord not right tClub sPassWord_%s",tClub.sPassWord)
            ClubSOperateResp.nRlt = PubErrCode.AdminOprate.PassWordErr
            ClubSOperateResp.sErrStr = "sPassWord not right"
            MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
            return
        end
    elseif tData.nType==3 then
        nPowerType = Define.tPower.Member

        if tData.nTUserId==nUserId then
            tClub:Print("_HandleAdminOperate 不能踢出自己")
            ClubSOperateResp.nRlt = PubErrCode.AdminOprate.KickOutYourself
            ClubSOperateResp.sErrStr = "you can not kickout youself"
            MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
            return
        end

        --检查操作者和被操者身份
        if tAdmin.nIdentify==Define.nAdmin then
            --操作者是管理员
            if tTargetUser.nIdentify==Define.nAdmin  then
                --被操者身份是另外一个管理员
                tClub:Print("_HandleAdminOperate 被操者身份是另外一个管理员")
                ClubSOperateResp.nRlt = PubErrCode.AdminOprate.TargetIsOtherAdmin
                ClubSOperateResp.sErrStr = "you can not oprated other admin"
                MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
                return
            elseif tTargetUser.nIdentify==Define.nMaster then
                --被操者身份是主席
                tClub:Print("_HandleAdminOperate 被操者身份是主席")
                ClubSOperateResp.nRlt = PubErrCode.AdminOprate.TargetIsMaser
                ClubSOperateResp.sErrStr = "you can not oprated master"
                MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
                return
            end
        end
    end

    --检查是否有管理权限
    local hasPower = MsgClient._CheckPower(arrPower,nPowerType)
    if not hasPower then
        tClub:Print("_HandleAdminOperate no power")
        ClubSOperateResp.nRlt = PubErrCode.AdminOprate.NoPower
        ClubSOperateResp.sErrStr = "no power"
        MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
        return
    end

    SlaveData.tDBOprateWaitting.arrAdminOprate[nUserId] = os.time()

    if tData.nType==1 then
        ClubSOperateResp.nRlt,ClubSOperateResp.sErrStr = MsgClient._AddClubGoldByAdmin(tData,tClub,nUserId)
    elseif tData.nType==2 then
        ClubSOperateResp.nRlt,ClubSOperateResp.sErrStr = MsgClient._DeductClubGoldByAdmin(tData,tClub,nUserId)
    elseif tData.nType==3 then
        ClubSOperateResp.nRlt,ClubSOperateResp.sErrStr = MsgClient._KickOutByAdmin(tData,tClub,nUserId)
    end
    MsgApi.SendToUser(nUserId,"ClubSOperateResp",ClubSOperateResp)
    SlaveData.tDBOprateWaitting.arrAdminOprate[nUserId] = nil
end

--检查是否有权限
--@param arrPower 管理员权限
--@param nPowerType 权限类型
function MsgClient._CheckPower(arrPower,nPowerType)
    for _,v in pairs(arrPower) do
        if v.nPowerType==nPowerType and v.isOpen==true then
            return true
        end
    end
    return false
end

--管理员增加成员俱乐部币
--@param arrPower 管理员权限
--@return nErrCode 错误码  sErrStr 错误信息
function MsgClient._AddClubGoldByAdmin(tData,tClub,nOpUserId)
    --尝试锁住俱乐部总资产
    local isSuccee,sErr,nCurGold = PublicUserInfo.LockClubSumAsset(tClub.nClubId,PublicApi.Floor_2(tData.nChange),tClub.nClubId)
    if not isSuccee then
        tClub:Print("__AddClubGoldByAdmin LockClubSumAsset fail, sErr:%s, nCurGold:%f",sErr or "",nCurGold or 0)
        return PubErrCode.AdminOprate.ClubGoldLess,"ClubGoldLess"
    end

    --尝试解锁并且扣除俱乐部总资产
    local isSuccee1,sErr1,nGoldAfterChange = PublicUserInfo.UnLockAndMinusClubSumAsset(tClub.nClubId,PublicApi.Floor_2(tData.nChange),Define.SourceType.AdminAddGold,tData.nTUserId,nOpUserId,tClub.nClubId)
    if not isSuccee1 then
        tClub:Print("__AddClubGoldByAdmin UnLockAndMinusClubSumAsset fail, sErr1:%s, nGoldAfterChange:%f",sErr1 or "",nGoldAfterChange or 0)
        return PubErrCode.AdminOprate.ClubGoldLess,"ClubGoldLess"
    end

    --给玩家增加俱乐部币
    local t = {nUserID=tData.nTUserId,nItemID=tClub.nClubId,nDel= PublicApi.Floor_2(tData.nChange),nSourceType=Define.SourceType.AdminAddGold}
    local isSuccee2 = PublicUserInfo.ChangeUserTreasure(t)
    if not isSuccee2 then
        tClub:Print("__AddClubGoldByAdmin add TargetUser Club Gold Fail")
        return PubErrCode.AdminOprate.ChangeClubGoldFail,"add TargetUser Club Gold Fail"
    end

    --获取个人俱乐部币
    local nUserClubGold =  PublicUserInfo.Get_User_Gold(tData.nTUserId,tClub.nClubId)

    --发送俱乐部玩家信息改变
    MsgApi.SendUserInfoChange(tData.nClubId,tData.nTUserId,{nClubGold = nUserClubGold})

    local tUserInfo = PublicUserInfo.GetUserBasic(nOpUserId) or {}
    local tExData = {}
    tExData.sClubName = tClub.sClubName
    tExData.nClubId = tClub.nClubId
    tExData.nUserId = nOpUserId
    tExData.nOpType = 1
    tExData.nChange = tData.nChange
    tExData.sUserName = tUserInfo.sNickName or ""
    tExData.sFaceId = tUserInfo.sFaceID or "1"

    --发送到db服
    local ClubAdminOperateReq = {}
    ClubAdminOperateReq.nClubId = tData.nClubId
    ClubAdminOperateReq.nTUserId = tData.nTUserId
    ClubAdminOperateReq.nType = tData.nType
    ClubAdminOperateReq.nOpUserId = nOpUserId
    ClubAdminOperateReq.nChange = tData.nChange
    ClubAdminOperateReq.sExData = Cjson.encode(tExData)
    MsgApi.SendToDBServer("ClubAdminOperateReq",ClubAdminOperateReq,nOpUserId)

    tClub:Print("__AddClubGoldByAdmin add TargetUser Club Gold success")

    return PubErrCode.AdminOprate.Success,"Success"
end

--管理员回收成员俱乐部币
function MsgClient._DeductClubGoldByAdmin(tData,tClub,nOpUserId)
    --检查被操作玩家是否在游戏中
    local nCurGameId,nCurRoomId,sCurServerKey = PublicUserInfo.GetUserPlayingGame(tData.nTUserId)
    if nCurGameId then
        tClub:Print("__DeductClubGoldByAdmin targetUser is in Game,nTUserId_%d nCurGameId_%s nCurRoomId_%s sCurServerKey_%s",
            tData.nTUserId,tostring(nCurGameId),tostring(nCurRoomId),tostring(sCurServerKey))
        -- --发送踢人到游戏服
        -- MsgApi.SendKickUserToGame(tData.nTUserId,sCurServerKey)
        --插入消息队列
        local tMsgData = {}
        tMsgData.nClubId = tData.nClubId
        tMsgData.nTUserId = tData.nTUserId
        tMsgData.nType = tData.nType
        tMsgData.nOpUserId = nOpUserId
        tMsgData.nChange = tData.nChange
        tMsgData.sPassWord = tData.sPassWord
        tMsgData.MsgType = Define.MsgType.Recycling
        MsgOnTime.Push(tMsgData)
        return PubErrCode.AdminOprate.InGame,"use in game"
    end

    --尝试个人俱乐部币
    local isSuccee,sErr,nCurGold = PublicUserInfo.Gold_Lock(tData.nTUserId,PublicApi.Floor_2(tData.nChange),tClub.nClubId)
    if not isSuccee then
        tClub:Print("__DeductClubGoldByAdmin LockClubSumAsset fail, sErr:%s, nCurGold:%f",sErr or "",nCurGold or 0)
        return PubErrCode.AdminOprate.UserClubGoldLess,"UserClubGoldLess"
    end

    --尝试解锁并且扣除个人俱乐部币
    local isSuccee1,sErr1,nGoldAfterChange = PublicUserInfo.UnLockAndMinus(tData.nTUserId, PublicApi.Floor_2(tData.nChange),Define.SourceType.AdminDelGold,1,tClub.nClubId)
    if not isSuccee1 then
        tClub:Print("__DeductClubGoldByAdmin UnLockAndMinus fail, sErr1:%s, nGoldAfterChange:%f",sErr1 or "",nGoldAfterChange or 0)
        return PubErrCode.AdminOprate.UserClubGoldLess,"UserClubGoldLess"
    end

    --增加俱乐部总资产
    local t = {nClubId=tData.nClubId,nChange=PublicApi.Floor_2(tData.nChange),nSourceType=Define.SourceType.AdminDelGold,nMemberId=tData.nTUserId,nHandleId=nOpUserId,nItemId=tData.nClubId}
    local isSuccee2 = PublicUserInfo.ChangeClubSumAsset(t)
    if not isSuccee2 then
        tClub:Print("__DeductClubGoldByAdmin add ClubGold Fail")
        return PubErrCode.AdminOprate.ChangeClubGoldFail,"add ClubGold Fail"
    end

    --发送俱乐部玩家信息改变
    MsgApi.SendUserInfoChange(tData.nClubId,tData.nTUserId,{nClubGold = nGoldAfterChange})

    local tUserInfo = PublicUserInfo.GetUserBasic(nOpUserId) or {}
    local tExData = {}
    tExData.sClubName = tClub.sClubName
    tExData.nClubId = tClub.nClubId
    tExData.nUserId = nOpUserId
    tExData.nOpType = 2
    tExData.nChange = tData.nChange
    tExData.sUserName = tUserInfo.sNickName or ""
    tExData.sFaceId = tUserInfo.sFaceID or "1"

    --发送到db服
    local ClubAdminOperateReq = {}
    ClubAdminOperateReq.nClubId = tData.nClubId
    ClubAdminOperateReq.nTUserId = tData.nTUserId
    ClubAdminOperateReq.nType = tData.nType
    ClubAdminOperateReq.nOpUserId = nOpUserId
    ClubAdminOperateReq.nChange = tData.nChange
    ClubAdminOperateReq.sExData = Cjson.encode(tExData)
    MsgApi.SendToDBServer("ClubAdminOperateReq",ClubAdminOperateReq,nOpUserId)

    tClub:Print("__DeductClubGoldByAdmin del TargetUser Club Gold success")

    return PubErrCode.AdminOprate.Success,"Success"
end

--管理员把成员踢出俱乐部
function MsgClient._KickOutByAdmin(tData,tClub,nOpUserId)
    --检查被操作玩家是否在游戏中
    local nCurGameId,nCurRoomId,sCurServerKey = PublicUserInfo.GetUserPlayingGame(tData.nTUserId)
    if nCurGameId then
        tClub:Print("__KickOutByAdmin targetUser is in Game,nTUserId_%d nCurGameId_%s nCurRoomId_%s sCurServerKey_%s",
            tData.nTUserId,tostring(nCurGameId),tostring(nCurRoomId),tostring(sCurServerKey))
        -- --发送踢人到游戏服
        -- MsgApi.SendKickUserToGame(tData.nTUserId,sCurServerKey)
        --插入消息队列
        local tMsgData = {}
        tMsgData.nClubId = tData.nClubId
        tMsgData.nTUserId = tData.nTUserId
        tMsgData.nType = tData.nType
        tMsgData.nOpUserId = nOpUserId
        tMsgData.nChange = tData.nChange
        tMsgData.sPassWord = tData.sPassWord
        tMsgData.MsgType = Define.MsgType.KickOut
        MsgOnTime.Push(tMsgData)
        return PubErrCode.AdminOprate.InGame,"use in game"
    end

    --获取个人俱乐部币
    local nUserClubGold =  PublicUserInfo.Get_User_Gold(tData.nTUserId,tClub.nClubId)
    nUserClubGold = PublicApi.Floor_2(nUserClubGold)

    if nUserClubGold and math.abs(nUserClubGold)>1e-6 then
        --尝试个人俱乐部币
        local isSuccee,sErr,nCurGold = PublicUserInfo.Gold_Lock(tData.nTUserId,nUserClubGold,tClub.nClubId)
        if not isSuccee then
            tClub:Print("__KickOutByAdmin LockClubSumAsset fail, sErr:%s, nCurGold:%f",sErr or "",nCurGold or 0)
            return PubErrCode.AdminOprate.UserClubGoldLess,"UserClubGoldLess"
        end

        --尝试解锁并且扣除个人俱乐部币
        local isSuccee1,sErr1,nGoldAfterChange = PublicUserInfo.UnLockAndMinus(tData.nTUserId,nUserClubGold,Define.SourceType.KickOut,1,tClub.nClubId)
        if not isSuccee1 then
            tClub:Print("__KickOutByAdmin UnLockAndMinus fail, sErr1:%s, nGoldAfterChange:%f",sErr1 or "",nGoldAfterChange or 0)
            return PubErrCode.AdminOprate.UserClubGoldLess,"UserClubGoldLess"
        end

        --增加俱乐部总资产
        local t = {nClubId=tData.nClubId,nChange=nUserClubGold,nSourceType=Define.SourceType.KickOut,nMemberId=tData.nTUserId,nHandleId=nOpUserId,nItemId=tData.nClubId}
        local isSuccee2 = PublicUserInfo.ChangeClubSumAsset(t)
        if not isSuccee2 then
            tClub:Print("__KickOutByAdmin add ClubGold Fail")
            return PubErrCode.AdminOprate.ChangeClubGoldFail,"add ClubGold Fail"
        end
    end

    --删除玩家本周局数
    PublicRedis.DelClubUserWeekCount(tData.nClubId,tData.nTUserId)
    --删除俱乐部玩家信息
    PublicRedis.DelClubUserInfo(tData.nClubId,tData.nTUserId)
    --删除玩家上一次登录的俱乐部id
    local nLastClubId = PublicUserInfo.GetUserLastEnterClub(tData.nTUserId)
    if nLastClubId==tData.nClubId then
        PublicUserInfo.DelUserLastEnterClub(tData.nTUserId)
    end

    --通知所有从服玩家被踢出
    local ClubCKickOutNotify = {}
    ClubCKickOutNotify.nClubId = tData.nClubId
    ClubCKickOutNotify.nUserId = tData.nTUserId
    ClubCKickOutNotify.sClubName = tClub.sClubName
    MsgApi.SendToSlaveServer("ClubCKickOutNotify",ClubCKickOutNotify)

    local tUserInfo = PublicUserInfo.GetUserBasic(nOpUserId) or {}
    local tExData = {}
    tExData.sClubName = tClub.sClubName
    tExData.nClubId = tClub.nClubId
    tExData.nUserId = nOpUserId
    tExData.nOpType = 5
    tExData.sUserName = tUserInfo.sNickName or ""
    tExData.sFaceId = tUserInfo.sFaceID or "1"

    --发送到db服
    local ClubAdminOperateReq = {}
    ClubAdminOperateReq.nClubId = tData.nClubId
    ClubAdminOperateReq.nTUserId = tData.nTUserId
    ClubAdminOperateReq.nType = tData.nType
    ClubAdminOperateReq.nOpUserId = nOpUserId
    ClubAdminOperateReq.sExData = Cjson.encode(tExData)
    MsgApi.SendToDBServer("ClubAdminOperateReq",ClubAdminOperateReq,nOpUserId)

    tClub:Print("__KickOutByAdmin KickOut targetUser success")

    return PubErrCode.AdminOprate.Success,"Success"
end

--DB服返回 管理员操作返回
function MsgClient.OnDBClubAdminOperateRsp(sReturnKey, Data, nLen)
    local strProto = "ClubAdminOperateRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubAdminOperateRsp nRlt_%d,nClubId_%d,nType_%d,nOpUserId_%d,nTUserId_%d,sExtra_%s",
    tData.nRlt,tData.nClubId,tData.nType,tData.nOpUserId,tData.nTUserId,tData.sExtra or "nil")

    --管理员的信息
    local tOpTUserinfo = PublicUserInfo.GetAllUserInfo(tData.nOpUserId) or {}
    local tUserInfo = {sUserName="",sFaceId="",nUserId=tData.nOpUserId}
    if tOpTUserinfo then
        tUserInfo.sUserName=tOpTUserinfo.sNickName
        tUserInfo.sFaceId=tOpTUserinfo.sFaceID
    else
        Base.Log("_OnDBClubAdminOperateRsp 没有管理员的信息")
    end

    --俱乐部的信息
    local tClub = ClubSManager.GetClub(tData.nClubId)
    local tClubInfo = {nClubId=tData.nClubId,sClubName="",nMaster=0}
    if tClub then
        tClubInfo.sClubName = tClub.sClubName
        tClubInfo.nMaster = tClub.nMaster
    else
        Base.Log("_OnDBClubAdminOperateRsp 俱乐部的信息")
    end

    local isSuccee,tExtra = pcall(Cjson.decode,tData.sExtra)
    if isSuccee then
        if tData.nRlt==0 then
            local tNoticesInfo = {}
            tNoticesInfo.tClubInfo = tClubInfo
            tNoticesInfo.tUserInfo = tUserInfo
            tNoticesInfo.tNoticesItem = tExtra.tNoticesItem
            tNoticesInfo.arrRedot = {{nType=3,nCount=tExtra.nUnReadCnt}}
            MsgApi.SendUserMessage(tData.nTUserId,6,tNoticesInfo)

            if tData.nType==3 then --踢出俱乐部
                --发送俱乐部场景信息改变
                local tChangeInfo = {
                    nUserCnt=tExtra.nUserCnt,
                    nApplyAddGoldCnt=tExtra.nApplyAddGoldCnt,
                    nApplyCutGoldCnt=tExtra.nApplyCutGoldCnt,
                }
                MsgApi.SendClubInfoChange(tData.nClubId,tChangeInfo)
            end
        end
    end
end

--个人俱乐部币增加退还请求
function MsgClient.OnClubSTransferClubGoldReq(sClientID, Data, nLen)
    local strProto = "ClubSTransferClubGoldReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSTransferClubGoldReq 个人俱乐部币增加退还请求 nUserId_%d,nClubId_%d,nChange_%.2f,nType_%d",
        nUserId,tData.nClubId,tData.nChange,tData.nType)

    --参数校验
    if tData.nChange<=0 then
        Base.Log("_OnClubSTransferClubGoldReq nChange Err")
        MsgApi.SendToClient(sClientID,"ClubSTransferClubGoldResp",{nRlt=PubErrCode.ApplyGold.ParamsErr,sErrStr="nChange Err",nType=tData.nType})
        return
    end
    if tData.nType~=1 and tData.nType~=2 then
        Base.Log("_OnClubSTransferClubGoldReq nType Err")
        MsgApi.SendToClient(sClientID,"ClubSTransferClubGoldResp",{nRlt=PubErrCode.ApplyGold.ParamsErr,sErrStr="nType Err",nType=tData.nType})
        return
    end

    --不是私人俱乐部，是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSTransferClubGoldReq club is hall")
        MsgApi.SendToClient(sClientID,"ClubSTransferClubGoldResp",{nRlt=PubErrCode.ApplyGold.IsHall,sErrStr="club is hall",nType=tData.nType})
        return
    end

    --俱乐部是否存在
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSTransferClubGoldReq not find club")
        MsgApi.SendToClient(sClientID,"ClubSTransferClubGoldResp",{nRlt=PubErrCode.ApplyGold.NoClub,sErrStr="not find club",nType=tData.nType})
        return
    end

    --退还俱乐部币，检测是否足够
    if tData.nType==2 then
        --获取个人俱乐部币
        local nUserClubGold =  PublicUserInfo.Get_User_Gold(nUserId,tData.nClubId)
        if nUserClubGold-tData.nChange<0 and math.abs(nUserClubGold-tData.nChange)>=1e-6 then
            Base.Log("_OnClubSTransferClubGoldReq ClubGold is not enough")
            MsgApi.SendToClient(sClientID,"ClubSTransferClubGoldResp",{nRlt=PubErrCode.ApplyGold.UserClubGoldLess,sErrStr="ClubGold is not enough",nType=tData.nType})
            return
        end
    end

    --需要进行安全密码校验
    if PublicUserInfo.IsNeedCheckSafePassWard(nUserId) then
        -- local nResult = PublicUserInfo.GetCheckSafePassWardResult(nUserId) ----获取安全密码校验结果
        -- if nResult==nil then
        --     Base.Log("_OnClubSTransferClubGoldReq 没有进行安全密码校验")
        --     MsgApi.SendToClient(sClientID,"ClubSTransferClubGoldResp",{nRlt=PubErrCode.ApplyGold.NoCheckSPW,sErrStr="not check SafePassWard",nType=tData.nType})
        --     return
        -- elseif nResult==0 then
        --     Base.Log("_OnClubSTransferClubGoldReq 进行安全密码校验失败")
        --     MsgApi.SendToClient(sClientID,"ClubSTransferClubGoldResp",{nRlt=PubErrCode.ApplyGold.CheckSPWErr,sErrStr="check SafePassWard fail",nType=tData.nType})
        --     return 
        -- end
        PublicUserInfo.DelCheckSafePassWardResult(nUserId)
    end

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSTransferClubGoldReq 玩家信息不存在")
        return
    end
    local nGroupId = tonumber(tUser.nGroupId) or -1
    local nLimitCnt = PubClubApi.GetUserApplyGoldMaxCnt(nGroupId) --加入俱乐部申请的数量上限

    local TransferClubGoldReq = {}
    TransferClubGoldReq.nClubId = tData.nClubId
    TransferClubGoldReq.nChange = tData.nChange
    TransferClubGoldReq.nType = tData.nType
    TransferClubGoldReq.nUserId = nUserId
    TransferClubGoldReq.nLimitCnt = nLimitCnt
    MsgApi.SendToDBServer("TransferClubGoldReq",TransferClubGoldReq,nUserId)
end

--DB服返回 个人俱乐部币增加退还返回
function MsgClient.OnDBTransferClubGoldRsp(sReturnKey, Data, nLen)
    local strProto = "TransferClubGoldRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBTransferClubGoldRsp nRlt_%d,nClubId_%d,nType_%d,nUserId_%d,nApplyCnt_%d",
        tData.nRlt,tData.nClubId,tData.nType,tData.nUserId,tData.nApplyCnt)

    local sErrStr = ""
    if tData.nRlt==0 then
        sErrStr = "success"
        local tChangeInfo = {}
        if tData.nType==1 then
            tChangeInfo.nApplyAddGoldCnt = tData.nApplyCnt
        elseif tData.nType==2 then
            tChangeInfo.nApplyCutGoldCnt = tData.nApplyCnt
        end
        --发送俱乐部场景信息改变
        MsgApi.SendClubInfoChange(tData.nClubId,tChangeInfo)
    elseif tData.nRlt==2 then
        sErrStr = "not find club"
    elseif tData.nRlt==4 then
        sErrStr = "ClubGold is not enough"
    elseif tData.nRlt==5 then
        sErrStr = "is not Member of club"
    elseif tData.nRlt==6 then
        sErrStr = "Applycnt is Max"
    end

    local ClubSTransferClubGoldResp = {}
    ClubSTransferClubGoldResp.nRlt = tData.nRlt
    ClubSTransferClubGoldResp.sErrStr = sErrStr
    ClubSTransferClubGoldResp.nType = tData.nType
    MsgApi.SendToUser(tData.nUserId,"ClubSTransferClubGoldResp",ClubSTransferClubGoldResp)
end

--个人俱乐部币流水记录请求
function MsgClient.OnClubSTransferRecordReq(sClientID, Data, nLen)
    local strProto = "ClubSTransferRecordReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSTransferRecordReq 个人俱乐部币流水记录请求 nUserId_%d,nClubId_%d,nIdOfStart_%d,nCnt_%d",
    nUserId,tData.nClubId,tData.nIdOfStart,tData.nCnt)

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSTransferRecordReq nClubId Err,is hall")
        MsgApi.SendToClient(sClientID,"ClubSTransferRecordResp",{arrRecords={},nClubId=tData.nClubId,nAllCnt=0})
        return
    end

    --参数校验
    local nCnt = tData.nCnt
    local nIdOfStart = tData.nIdOfStart
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end
    if nIdOfStart<0 then
        nIdOfStart=0
    end

    local TransferRecordReq = {}
    TransferRecordReq.nClubId = tData.nClubId
    TransferRecordReq.nIdOfStart = nIdOfStart
    TransferRecordReq.nCnt = nCnt
    TransferRecordReq.nUserId = nUserId
    MsgApi.SendToDBServer("TransferRecordReq",TransferRecordReq,nUserId)
end

--DB服返回 个人俱乐部币流水记录 返回
function MsgClient.OnDBTransferRecordRsp(sReturnKey, Data, nLen)
    local strProto = "TransferRecordRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrRecords = {}
    for k,v in pairs(tData.arrRecords) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.nChange = v.nChange
            tItem.nClubGold = v.nClubGold
            tItem.sTime = v.sTime
            tItem.nSourceType = v.nSourceType
            table.insert(arrRecords,tItem)
        end
    end

    Base.Log("_OnDBTransferRecordRsp nClubId_%d,nUserId_%d,nAllCnt_%d,#arrRecords_%d",
    tData.nClubId,tData.nUserId,tData.nAllCnt,#arrRecords)

    local ClubSTransferRecordResp = {}
    ClubSTransferRecordResp.arrRecords = arrRecords
    ClubSTransferRecordResp.nClubId = tData.nClubId
    ClubSTransferRecordResp.nAllCnt = tData.nAllCnt
    MsgApi.SendToUser(tData.nUserId,"ClubSTransferRecordResp",ClubSTransferRecordResp)
end

--俱乐部个人历史牌局请求
function MsgClient.OnClubSPaiJuRecordReq(sClientID, Data, nLen)
    local strProto = "ClubSPaiJuRecordReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSPaiJuRecordReq 俱乐部个人历史牌局请求 myself_%d,nClubId_%d,nIdOfStart_%d,nCnt_%d,nUserId_%d",
    nUserId,tData.nClubId,tData.nIdOfStart,tData.nCnt,tData.nUserId)

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSPaiJuRecordReq club is hall")
        MsgApi.SendToClient(sClientID,"ClubSPaiJuRecordResp",{arrRecords={},nClubId=tData.nClubId,nAllCnt=0})
        return
    end

    --参数校验
    local nCnt = tData.nCnt
    local nIdOfStart = tData.nIdOfStart
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end
    if nIdOfStart<0 then
        nIdOfStart=0
    end

    local ClubPaiJuRecordReq = {}
    ClubPaiJuRecordReq.nClubId = tData.nClubId
    ClubPaiJuRecordReq.nIdOfStart = nIdOfStart
    ClubPaiJuRecordReq.nCnt = nCnt
    ClubPaiJuRecordReq.nUserId = tData.nUserId
    ClubPaiJuRecordReq.nSendUserId = nUserId
    MsgApi.SendToDBServer("ClubPaiJuRecordReq",ClubPaiJuRecordReq,nUserId)
end

--DB服返回 俱乐部个人历史牌局 返回
function MsgClient.OnDBClubPaiJuRecordRsp(sReturnKey, Data, nLen)
    local strProto = "ClubPaiJuRecordRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local nClubId = tData.nClubId
    local nAllCnt = tData.nAllCnt
    local nUserId = tData.nUserId
    local nSendUserId = tData.nSendUserId
    local arrRecords = {}

    for k,v in pairs(tData.arrRecords) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.sPaiJuID = v.sPaiJuID
            tItem.nWinLose = v.nWinLose
            tItem.sTime = v.sTime
            tItem.nGameId = v.nGameId
            tItem.sTableInfo = v.sTableInfo
            tItem.sHandCards = v.sHandCards
            if v.sHandCards=="" or v.sHandCards=="{}" then
                Base.Log("sPaiJuID_%s,sHandCards_%s",v.sPaiJuID,v.sHandCards)
            end
            tItem.nCollect = v.nCollect
            table.insert(arrRecords,tItem)
        end
    end

    Base.Log("_OnDBClubPaiJuRecordRsp nClubId_%d,nUserId_%d,nAllCnt_%d,#arrRecords_%d",
    nClubId,nUserId,nAllCnt,#arrRecords,nSendUserId)

    local ClubSPaiJuRecordResp = {}
    ClubSPaiJuRecordResp.nClubId = nClubId
    ClubSPaiJuRecordResp.nAllCnt = nAllCnt
    ClubSPaiJuRecordResp.arrRecords = arrRecords
    ClubSPaiJuRecordResp.nUserId = nUserId
    MsgApi.SendToUser(nSendUserId,"ClubSPaiJuRecordResp",ClubSPaiJuRecordResp)
end

--俱乐部个人贡献请求
function MsgClient.OnClubSContribRecordReq(sClientID, Data, nLen)
    local strProto = "ClubSContribRecordReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    local str = "俱乐部个人贡献请求"
    if tData.nUserId==0 then
        str = "俱乐部收益"
    end
    Base.Log("_OnClubSContribRecordReq strReq_%s nClubId_%d,nUserId_%d,myself_%d,nIdOfStart_%d,nCnt_%d,nType_%d",
    str,tData.nClubId,tData.nUserId,nUserId,tData.nIdOfStart,tData.nCnt,tData.nType)

    local ClubSContribRecordResp = {}
    ClubSContribRecordResp.arrRecords = {}
    ClubSContribRecordResp.nClubId = tData.nClubId
    ClubSContribRecordResp.nTotalContrib = 0
    ClubSContribRecordResp.nAllCnt = 0

    --不是私人俱乐部
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSContribRecordReq club is hall")
        MsgApi.SendToClient(sClientID,"ClubSContribRecordResp",ClubSContribRecordResp)
        return
    end

    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSContribRecordReq club not find")
        MsgApi.SendToClient(sClientID,"ClubSContribRecordResp",ClubSContribRecordResp)
        return
    end

    --查询俱乐部流水，需要判断是不是主席
    if tData.nUserId==0 then
        if tClub.nMaster~=nUserId then
            Base.Log("_OnClubSContribRecordReq you is not Master")
            MsgApi.SendToClient(sClientID,"ClubSContribRecordResp",ClubSContribRecordResp)
            return
        end
    end

    local nIdOfStart = tData.nIdOfStart
    local nCnt = tData.nCnt
    if nIdOfStart<0 then
        nIdOfStart = 0
    end
    if nCnt<0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubContribRecordReq = {}
    ClubContribRecordReq.nClubId = tData.nClubId
    ClubContribRecordReq.nUserId = tData.nUserId
    ClubContribRecordReq.nIdOfStart = nIdOfStart
    ClubContribRecordReq.nCnt = nCnt
    ClubContribRecordReq.nSendUserId = nUserId
    ClubContribRecordReq.nType = tData.nType
    MsgApi.SendToDBServer("ClubContribRecordReq",ClubContribRecordReq,nUserId)
end

--DB服返回 俱乐部个人贡献(俱乐部收益) 返回
function MsgClient.OnDBClubContribRecordRsp(sReturnKey, Data, nLen)
    local strProto = "ClubContribRecordRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrRecords = {}
    local nClubId = tData.nClubId
    local nTotalContrib = tData.nTotalContrib
    local nAllCnt = tData.nAllCnt
    local nSendUserId = tData.nSendUserId

    for k,v in pairs(tData.arrRecords) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.nContrib = v.nContrib
            tItem.sTime = v.sTime
            tItem.nType = v.nSourceType%100
            tItem.nGameId = math.floor((v.nSourceType-10000)/100)
            table.insert(arrRecords,tItem)
        end
    end

    Base.Log("_OnDBClubContribRecordRsp nClubId_%d,nSendUserId_%d,nTotalContrib_%.2f,nAllCnt_%d,#arrRecords_%d,nType_%d nServiceCharge_%f nPropsIncome_%f nInsurance_%f",
    nClubId,nSendUserId,nTotalContrib,nAllCnt,#arrRecords,tData.nType,tData.nServiceCharge,tData.nPropsIncome,tData.nInsurance)

    local ClubSContribRecordResp = {}
    ClubSContribRecordResp.arrRecords = arrRecords
    ClubSContribRecordResp.nClubId = nClubId
    ClubSContribRecordResp.nTotalContrib = nTotalContrib
    ClubSContribRecordResp.nAllCnt = nAllCnt
    ClubSContribRecordResp.nType = tData.nType
    ClubSContribRecordResp.nServiceCharge = tData.nServiceCharge
    ClubSContribRecordResp.nPropsIncome = tData.nPropsIncome
    ClubSContribRecordResp.nInsurance = tData.nInsurance
    MsgApi.SendToUser(nSendUserId,"ClubSContribRecordResp",ClubSContribRecordResp)
end

--俱乐部黑名单请求
function MsgClient.OnClubSBlacklistReq(sClientID, Data, nLen)
    local strProto = "ClubSBlacklistReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSBlacklistReq 俱乐部黑名单请求 nClubId_%d,nUserId_%d,nIdOfStart_%d,nCnt_%d",
    tData.nClubId,nUserId,tData.nIdOfStart,tData.nCnt)

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSBlacklistReq nClubId is hall")
        MsgApi.SendToClient(sClientID,"ClubSBlacklistResp",{arrBlacklist={},nClubId=tData.nClubId,nAllCnt=0})
        return
    end

    --参数校验
    local nCnt = tData.nCnt
    local nIdOfStart = tData.nIdOfStart
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end
    if nIdOfStart<0 then
        nIdOfStart=0
    end

    local ClubBlacklistReq = {}
    ClubBlacklistReq.nClubId = tData.nClubId
    ClubBlacklistReq.nCnt = nCnt
    ClubBlacklistReq.nIdOfStart = nIdOfStart
    ClubBlacklistReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubBlacklistReq",ClubBlacklistReq,nUserId)
end

--DB服返回 俱乐部黑名单 返回
function MsgClient.OnDBClubBlacklistRsp(sReturnKey, Data, nLen)
    local strProto = "ClubBlacklistRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrBlacklist = {}
    for k,v in pairs(tData.arrBlacklist) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.nUserId = v.nUserId
            tItem.sFaceId = v.sFaceId
            tItem.sName = v.sName
            tItem.sTime = v.sTime
            tItem.nSex = v.nSex
            tItem.sShopAcc = v.sShopAcc
            table.insert(arrBlacklist,tItem)
        end
    end

    Base.Log("_OnDBClubBlacklistRsp nClubId_%d,nUserId_%d,nAllCnt_%d,#arrBlacklist_%d",
    tData.nClubId,tData.nUserId,tData.nAllCnt,#arrBlacklist)

    local ClubSBlacklistResp = {}
    ClubSBlacklistResp.arrBlacklist = arrBlacklist
    ClubSBlacklistResp.nAllCnt = tData.nAllCnt
    ClubSBlacklistResp.nClubId = tData.nClubId
    MsgApi.SendToUser(tData.nUserId,"ClubSBlacklistResp",ClubSBlacklistResp)
end

--黑名单管理操作请求
function MsgClient.OnClubSBlacklistMgrReq(sClientID, Data, nLen)
    local strProto = "ClubSBlacklistMgrReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSBlacklistMgrReq 黑名单管理操作请求 nClubId_%d,nOpType_%d,nUserId_%d,nOpUserId_%d",
        tData.nClubId,tData.nOpType,tData.nUserId,nUserId)

    local ClubSBlacklistMgrResp = {}
    ClubSBlacklistMgrResp.nRlt = PubErrCode.BlackListOp.Success
    ClubSBlacklistMgrResp.sErrStr = ""
    ClubSBlacklistMgrResp.nUserId = tData.nUserId
    ClubSBlacklistMgrResp.nOpType = tData.nOpType
    ClubSBlacklistMgrResp.nClubId = tData.nClubId

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrBlackListOp[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSBlacklistMgrReq 请求过于频繁，等待上一个请求结束")
            ClubSBlacklistMgrResp.nRlt = PubErrCode.BlackListOp.WaitDBReturn
            ClubSBlacklistMgrResp.sErrStr = "too frequently,waitting last req return"
            MsgApi.SendToClient(sClientID,"ClubSBlacklistMgrResp",ClubSBlacklistMgrResp)
            return
        end
    end

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSBlacklistMgrReq nClubId is hall")
        ClubSBlacklistMgrResp.nRlt = PubErrCode.BlackListOp.IsHall
        ClubSBlacklistMgrResp.sErrStr = "club is hall"
        MsgApi.SendToClient(sClientID,"ClubSBlacklistMgrResp",ClubSBlacklistMgrResp)
        return
    end

    --参数校验
    if tData.nOpType~=1 and tData.nOpType~=2 then
        Base.Log("_OnClubSBlacklistMgrReq nOpType Err")
        ClubSBlacklistMgrResp.nRlt = PubErrCode.BlackListOp.ParamsErr
        ClubSBlacklistMgrResp.sErrStr = "nOpType Err"
        MsgApi.SendToClient(sClientID,"ClubSBlacklistMgrResp",ClubSBlacklistMgrResp)
        return
    end
    
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSBlacklistMgrReq club not find")
        ClubSBlacklistMgrResp.nRlt = PubErrCode.BlackListOp.NoClub
        ClubSBlacklistMgrResp.sErrStr = "club not find"
        MsgApi.SendToClient(sClientID,"ClubSBlacklistMgrResp",ClubSBlacklistMgrResp)
        return
    end

    --操作玩家是否是俱乐部成员
    local tAdmin = PublicRedis.GetClubUserInfo(tData.nClubId,nUserId)
    if not tAdmin then
        Base.Log("_OnClubSBlacklistMgrReq not find user in Club")
        ClubSBlacklistMgrResp.nRlt=PubErrCode.BlackListOp.NoClubUser
        ClubSBlacklistMgrResp.sErrStr="not find user in Club"
        MsgApi.SendToClient(sClientID,"ClubSBlacklistMgrResp",ClubSBlacklistMgrResp)
        return
    end
    --操作玩家是否是管理员或者主席
    if tAdmin.nIdentify~=Define.nMaster and tAdmin.nIdentify~=Define.nAdmin then
        tClub:Print("_OnClubSBlacklistMgrReq you not admin, nUserId:%d nIdentify:%d",nUserId,tAdmin.nIdentify)
        ClubSBlacklistMgrResp.nRlt=PubErrCode.BlackListOp.NoPower
        ClubSBlacklistMgrResp.sErrStr="you not admin"
        MsgApi.SendToClient(sClientID,"ClubSBlacklistMgrResp",ClubSBlacklistMgrResp)
        return
    end

    --管理员权限
    local isSuccee,arrPower = pcall(Cjson.decode,tAdmin.sPower)
    if not isSuccee then
        tClub:Print("_OnClubSBlacklistMgrReq decode tAdmin:%d sPower fail, sPower:%s",nUserId,tostring(tAdmin.sPower))
        arrPower = {}
    end

    --权限校验
    local hasPower = false
    for _,v in pairs(arrPower) do
        if v.nPowerType==Define.tPower.Member and v.isOpen==true then
            hasPower = true
            break
        end
    end
    if not hasPower then --没有操作权限
        Base.Log("_OnClubSBlacklistMgrReq no power")
        ClubSBlacklistMgrResp.nRlt=PubErrCode.BlackListOp.NoPower
        ClubSBlacklistMgrResp.sErrStr="no power"
        MsgApi.SendToClient(sClientID,"ClubSBlacklistMgrResp",ClubSBlacklistMgrResp)
        return
    end

    SlaveData.tDBOprateWaitting.arrBlackListOp[nUserId] = os.time()

    local ClubBlacklistMgrReq = {}
    ClubBlacklistMgrReq.nClubId = tData.nClubId
    ClubBlacklistMgrReq.nUserId = tData.nUserId
    ClubBlacklistMgrReq.nOpType = tData.nOpType
    ClubBlacklistMgrReq.nOpUserId = nUserId
    MsgApi.SendToDBServer("ClubBlacklistMgrReq",ClubBlacklistMgrReq,nUserId)
end

--DB服返回 黑名单管理操作 返回
function MsgClient.OnDBClubBlacklistMgrRsp(sReturnKey, Data, nLen)
    local strProto = "ClubBlacklistMgrRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubBlacklistMgrRsp nClubId_%d,nOpType_%d,nUserId_%d,nOpUserId_%d,nRlt_%d",
        tData.nClubId,tData.nOpType,tData.nUserId,tData.nOpUserId,tData.nRlt)
    
    local arrErrStr = {}
    arrErrStr[0] = "success"
    arrErrStr[1] = "club is hall"
    arrErrStr[2] = "nOpType Err"
    arrErrStr[3] = "club not find"
    arrErrStr[4] = "no power"
    arrErrStr[5] = "is in BlackList"
    if tData.nRlt~=0 then
        Base.Log("_OnDBClubBlacklistMgrRsp %s",arrErrStr[tData.nRlt] or "other Err")
    end

    local ClubSBlacklistMgrResp = {}
    ClubSBlacklistMgrResp.nRlt = tData.nRlt
    ClubSBlacklistMgrResp.sErrStr = arrErrStr[tData.nRlt] or ""
    ClubSBlacklistMgrResp.nUserId = tData.nUserId
    ClubSBlacklistMgrResp.nOpType = tData.nOpType
    ClubSBlacklistMgrResp.nClubId = tData.nClubId
    MsgApi.SendToUser(tData.nOpUserId,"ClubSBlacklistMgrResp",ClubSBlacklistMgrResp)
    SlaveData.tDBOprateWaitting.arrBlackListOp[tData.nOpUserId] = nil
end

--黑名单玩家搜索请求
function MsgClient.OnClubSBlacklistSearchReq(sClientID, Data, nLen)
    local strProto = "ClubSBlacklistSearchReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSBlacklistSearchReq 黑名单玩家搜索请求 nClubId_%d,nUserId_%d,str_%s",tData.nClubId,nUserId,tData.str)

    local ClubSBlacklistSearchResp = {}
    ClubSBlacklistSearchResp.arrBlacklist = {}
    ClubSBlacklistSearchResp.nPage = 0
    ClubSBlacklistSearchResp.nAllPage = 0
    ClubSBlacklistSearchResp.nClubId = tData.nClubId

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSBlacklistSearchReq nClubId is hall")
        MsgApi.SendToClient(sClientID,"ClubSBlacklistSearchResp",ClubSBlacklistSearchResp)
        return
    end

    --检验下是否能base64解码
    local isSuccee,sErr = pcall(BaseSink.decode,tData.str)
    if not isSuccee then
        Base.Log("_OnClubSBlacklistSearchReq nUserId_%d str is not Base64Encode",nUserId)
        MsgApi.SendToClient(sClientID,"ClubSBlacklistSearchResp",ClubSBlacklistSearchResp)
        if type(sErr) == "string" then 
            Logger:error(sErr)
        else 
            Base.LogT(sErr) 
        end
        return
    end

    local ClubBlacklistSearchReq = {}
    ClubBlacklistSearchReq.nClubId = tData.nClubId
    ClubBlacklistSearchReq.str = tData.str
    ClubBlacklistSearchReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubBlacklistSearchReq",ClubBlacklistSearchReq,nUserId)
end

--DB服返回 黑名单玩家搜索 返回
function MsgClient.OnDBClubBlacklistSearchRsp(sReturnKey, Data, nLen)
    local strProto = "ClubBlacklistSearchRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end
    
    local arrBlacklist = {}
    for k,v in pairs(tData.arrBlacklist) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.nUserId = v.nUserId
            tItem.sFaceId = v.sFaceId
            tItem.sName = v.sName
            tItem.sTime = v.sTime
            tItem.nSex = v.nSex
            tItem.sShopAcc = v.sShopAcc
            table.insert(arrBlacklist,tItem)
        end
    end

    Base.Log("_OnDBClubBlacklistSearchRsp nClubId_%d,nUserId_%d,nPage_%d,nAllPage_%d,#arrBlacklist_%d",
    tData.nClubId,tData.nUserId,tData.nPage,tData.nAllPage,#arrBlacklist)

    local ClubSBlacklistSearchResp = {}
    ClubSBlacklistSearchResp.arrBlacklist = arrBlacklist
    ClubSBlacklistSearchResp.nPage = tData.nPage
    ClubSBlacklistSearchResp.nAllPage = tData.nAllPage
    ClubSBlacklistSearchResp.nClubId = tData.nClubId
    MsgApi.SendToUser(tData.nUserId,"ClubSBlacklistSearchResp",ClubSBlacklistSearchResp)
end

--俱乐部牌桌记录请求
function MsgClient.OnClubSTableRecordReq(sClientID, Data, nLen)
    local strProto = "ClubSTableRecordReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSTableRecordReq 俱乐部牌桌记录请求 nClubId_%d,nUserId_%d,nIdOfStart_%d,nCnt_%d",
    tData.nClubId,nUserId,tData.nIdOfStart,tData.nCnt)

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSTableRecordReq nClubId is hall")
        MsgApi.SendToClient(sClientID,"ClubSTableRecordResp",{arrRecords={},nAllCnt=0,nClubId=tData.nClubId})
        return
    end

    --参数校验
    local nIdOfStart = tData.nIdOfStart
    local nCnt = tData.nCnt
    if nIdOfStart<0 then
        nIdOfStart = 0
    end
    if nCnt<0 then
        nCnt = 10
    elseif nCnt>15 then
        nCnt = 15
    end

    local ClubTableRecordReq = {}
    ClubTableRecordReq.nClubId = tData.nClubId
    ClubTableRecordReq.nIdOfStart = nIdOfStart
    ClubTableRecordReq.nCnt = nCnt
    ClubTableRecordReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubTableRecordReq",ClubTableRecordReq,nUserId)
end

--DB服返回 俱乐部牌桌记录 返回
function MsgClient.OnDBClubTableRecordRsp(sReturnKey, Data, nLen)
    local strProto = "ClubTableRecordRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrRecords = {}
    for k,v in pairs(tData.arrRecords) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.sTableId = v.sTableId
            tItem.sTableInfo = v.sTableInfo
            tItem.sTime = v.sTime
            table.insert(arrRecords,tItem)
        end
    end

    Base.Log("_OnDBClubTableRecordRsp nClubId_%d,nUserId_%d,nAllCnt_%d,#arrRecords_%d",
    tData.nClubId,tData.nUserId,tData.nAllCnt,#arrRecords)

    local ClubSTableRecordResp = {}
    ClubSTableRecordResp.arrRecords = arrRecords
    ClubSTableRecordResp.nAllCnt = tData.nAllCnt
    ClubSTableRecordResp.nClubId = tData.nClubId
    MsgApi.SendToUser(tData.nUserId,"ClubSTableRecordResp",ClubSTableRecordResp)
end

--俱乐部牌桌参与玩家请求
function MsgClient.OnClubSTableUserReq(sClientID, Data, nLen)
    local strProto = "ClubSTableUserReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSTableUserReq 俱乐部牌桌参与玩家请求 sTableId_%s,nUserId_%d,nIdOfStart_%d,nCnt_%d",
    tData.sTableId,nUserId,tData.nIdOfStart,tData.nCnt)

    if tData.sTableId=="" then
        Base.Log("_OnClubSTableUserReq sTableId Error")
        MsgApi.SendToClient(sClientID,"ClubSTableUserResp",{arrUser={},nAllCnt=0})
        return
    end

    local nIdOfStart = tData.nIdOfStart
    local nCnt = tData.nCnt
    if nIdOfStart<=0 then
        nIdOfStart = 0
    end
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubTableUserReq = {}
    ClubTableUserReq.sTableId = tData.sTableId
    ClubTableUserReq.nIdOfStart = nIdOfStart
    ClubTableUserReq.nCnt = nCnt
    ClubTableUserReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubTableUserReq",ClubTableUserReq,nUserId)
end

--DB服返回 俱乐部牌桌参与玩家 返回
function MsgClient.OnDBClubTableUserRsp(sReturnKey, Data, nLen)
    local strProto = "ClubTableUserRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrUser = {}
    for k,v in pairs(tData.arrUser) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.nUserId = v.nUserId
            tItem.sFaceId = v.sFaceId
            tItem.sName = v.sName
            tItem.nSex = v.nSex
            tItem.nClubId = v.nClubId
            tItem.nIdentify = v.nIdentify
            tItem.sShopAcc = v.sShopAcc
            tItem.nPlayCnt = v.nPlayCnt
            tItem.nWinLose = v.nWinLose
            tItem.nContribution = v.nContribution
            tItem.nItemId = v.nItemId
            table.insert(arrUser,tItem)
        end
    end

    Base.Log("_OnDBClubTableUserRsp sTableId_%s,#arrUser_%d,nAllCnt_%d,nUserId_%d",
    tData.sTableId,#arrUser,tData.nAllCnt,tData.nUserId)

    local ClubSTableUserResp = {}
    ClubSTableUserResp.arrUser = arrUser
    ClubSTableUserResp.nAllCnt = tData.nAllCnt
    MsgApi.SendToUser(tData.nUserId,"ClubSTableUserResp",ClubSTableUserResp)
end

--俱乐部成员信息请求
function MsgClient.OnClubSMemberInfoReq(sClientID, Data, nLen)
    local strProto = "ClubSMemberInfoReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSMemberInfoReq 俱乐部成员信息请求 nClubId_%d,nUserId_%d,myself_%d",tData.nClubId,tData.nUserId,nUserId)

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSMemberInfoReq club is hall")
        local ClubSMemberInfoResp = {}
        ClubSMemberInfoResp.nRlt = PubErrCode.MemberInfo.IsHall
        ClubSMemberInfoResp.sErrStr = "club is hall"
        ClubSMemberInfoResp.nUserId = tData.nUserId
        ClubSMemberInfoResp.nClubId = tData.nClubId
        MsgApi.SendToClient(sClientID,"ClubSMemberInfoResp",ClubSMemberInfoResp)
        return
    end

    local ClubMemberInfoReq = {}
    ClubMemberInfoReq.nClubId = tData.nClubId
    ClubMemberInfoReq.nUserId = tData.nUserId
    ClubMemberInfoReq.nSendUserId = nUserId
    MsgApi.SendToDBServer("ClubMemberInfoReq",ClubMemberInfoReq,nUserId)
end

--DB服返回 俱乐部成员信息 返回
function MsgClient.OnDBClubMemberInfoRsp(sReturnKey, Data, nLen)
    local strProto = "ClubMemberInfoRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubMemberInfoRsp nClubId_%d,nUserId_%d,nSendUserId_%d,nRlt_%d",
    tData.nClubId,tData.nUserId,tData.nSendUserId,tData.nRlt)

    local ClubSMemberInfoResp = {}
    ClubSMemberInfoResp.nUserId = tData.nUserId
    ClubSMemberInfoResp.nClubId = tData.nClubId
    if tData.nRlt==0 then
        ClubSMemberInfoResp.nRlt = PubErrCode.MemberInfo.Success
        ClubSMemberInfoResp.sErrStr = "success"
        local tUserInfo = {}
        tUserInfo.nUserId = tData.tUserInfo.nUserId
        tUserInfo.sFaceId = tData.tUserInfo.sFaceId
        tUserInfo.sName = tData.tUserInfo.sName
        tUserInfo.nSex = tData.tUserInfo.nSex
        tUserInfo.nClubId = tData.nClubId
        tUserInfo.nClubGold = tData.tUserInfo.nClubGold
        tUserInfo.nIdentify = tData.tUserInfo.nIdentify
        tUserInfo.nContribution = tData.tUserInfo.nContribution
        tUserInfo.nGoldContribution = tData.tUserInfo.nGoldContribution
        tUserInfo.sShopAcc = tData.tUserInfo.sShopAcc
        ClubSMemberInfoResp.tUserInfo = tUserInfo
        Base.Log("_OnDBClubMemberInfoRsp tUserInfo_%s",Cjson.encode(tUserInfo))
    else
        ClubSMemberInfoResp.nRlt = PubErrCode.MemberInfo.NoClubUser
        ClubSMemberInfoResp.sErrStr = "user not find"
        Base.Log("俱乐部没有这个玩家")
    end
    MsgApi.SendToUser(tData.nSendUserId,"ClubSMemberInfoResp",ClubSMemberInfoResp)
end

--俱乐部管理员列表请求
function MsgClient.OnClubSAdminListReq(sClientID, Data, nLen)
    local strProto = "ClubSAdminListReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSAdminListReq 俱乐部管理员列表请求 nClubId_%d,nUserId_%d,nPage_%d,nCnt_%d",tData.nClubId,nUserId,tData.nPage,tData.nCnt)

    local ClubSAdminListResp = {}
    ClubSAdminListResp.arrAdminList = {}
    ClubSAdminListResp.nClubId=tData.nClubId
    ClubSAdminListResp.nPage=0
    ClubSAdminListResp.nAllCnt=0

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSAdminListReq club is hall")
        MsgApi.SendToClient(sClientID,"ClubSAdminListResp",ClubSAdminListResp)
        return
    end

    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSAdminListReq club is not find")
        MsgApi.SendToClient(sClientID,"ClubSAdminListResp",ClubSAdminListResp)
        return
    end

    --不是主席
    if tClub.nMaster~= nUserId then
        Base.Log("_OnClubSAdminListReq you is not master")
        MsgApi.SendToClient(sClientID,"ClubSAdminListResp",ClubSAdminListResp)
        return
    end

    local nPage = tData.nPage
    local nCnt = tData.nCnt
    if nPage<=0 then
        nPage = 1
    end
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubAdminListReq = {}
    ClubAdminListReq.nClubId = tData.nClubId
    ClubAdminListReq.nUserId = nUserId
    ClubAdminListReq.nPage = nPage
    ClubAdminListReq.nCnt = nCnt
    MsgApi.SendToDBServer("ClubAdminListReq",ClubAdminListReq,nUserId)
end

--DB服返回 俱乐部管理员列表 返回
function MsgClient.OnDBClubAdminListRsp(sReturnKey, Data, nLen)
    local strProto = "ClubAdminListRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrShow = {}
    local arrAdminList = {}
    for k,v in pairs(tData.arrAdminList) do
        if v.nUserId and v.nUserId>0 then
            local tItem = {}
            tItem.nUserId = v.nUserId
            tItem.sFaceId = v.sFaceId
            tItem.sName = v.sName
            tItem.nSex = v.nSex
            tItem.nClubId = v.nClubId
            tItem.sShopAcc = v.sShopAcc
            tItem.sPower = v.sPower
            table.insert(arrAdminList,tItem)
            table.insert(arrShow,{nUserId=v.nUserId,sPower=v.sPower})
        end
    end
    
    Base.Log("_OnDBClubAdminListRsp nClubId_%d,nUserId_%d,nPage_%d,nAllCnt_%d,arrAdminList_%s",
        tData.nClubId,tData.nUserId,tData.nPage,tData.nAllCnt,Cjson.encode(arrShow))

    local ClubSAdminListResp = {}
    ClubSAdminListResp.arrAdminList = arrAdminList
    ClubSAdminListResp.nClubId = tData.nClubId
    ClubSAdminListResp.nPage = tData.nPage
    ClubSAdminListResp.nAllCnt = tData.nAllCnt
    MsgApi.SendToUser(tData.nUserId,"ClubSAdminListResp",ClubSAdminListResp)
end

--俱乐部增加删除管理员请求
function MsgClient.OnClubSAdminMgrReq(sClientID, Data, nLen)
    local strProto = "ClubSAdminMgrReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSAdminMgrReq 俱乐部增加删除管理员请求 nClubId_%d,myself_%d,nOpType_%d,nUserId_%d",tData.nClubId,nUserId,tData.nOpType,tData.nUserId)

    local ClubSAdminMgrResp = {}
    ClubSAdminMgrResp.nUserId = tData.nUserId
    ClubSAdminMgrResp.nClubId = tData.nClubId
    ClubSAdminMgrResp.nOpType = tData.nOpType

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrAdminMgr[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSAdminMgrReq 请求过于频繁，等待上一个请求结束")
            ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.WaitDBReturn
            ClubSAdminMgrResp.sErrStr = "too frequently,waitting last req return"
            MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
            return
        end
    end

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSAdminMgrReq 是大厅")
        ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.IsHall
        ClubSAdminMgrResp.sErrStr = "club is hall"
        MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
        return
    end

    if tData.nOpType~=1 and tData.nOpType~=2 then
        Base.Log("_OnClubSAdminMgrReq 参数错误")
        ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.ParamsErr
        ClubSAdminMgrResp.sErrStr = "nOpType Err"
        MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
        return
    end

    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSAdminMgrReq 俱乐部不存在")
        ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.NoClub
        ClubSAdminMgrResp.sErrStr = "club is not find"
        MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
        return
    end

    --不是主席
    if tClub.nMaster~= nUserId then
        Base.Log("_OnClubSAdminMgrReq 你不是主席")
        ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.NotMaster
        ClubSAdminMgrResp.sErrStr = "you is not master"
        MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
        return
    end

    --修改的玩家是主席
    if tData.nUserId==tClub.nMaster then
        Base.Log("_OnClubSAdminMgrReq 修改的玩家是主席")
        ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.isMaster
        ClubSAdminMgrResp.sErrStr = "user is master"
        MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
        return
    end

    --增加俱乐部管理员
    if tData.nOpType == 1 then
        local arrClubUserInfo = PublicRedis.GetClubAllUserInfo(tData.nClubId)
        local nAdminCnt = 0
        local tTargetUser = nil --目标玩家的信息
        for _,tUserInfo in pairs(arrClubUserInfo) do
            if tUserInfo.nIdentify==Define.nAdmin then
                nAdminCnt = nAdminCnt + 1
            end
            if tUserInfo.nUserId==tData.nUserId then
                tTargetUser = tUserInfo
            end
        end
        if nAdminCnt>=Define.MaxAdminCnt then
            ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.LimtMax
            ClubSAdminMgrResp.sErrStr = "Admin cnt is Max"
            MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
            Base.Log("_OnDBClubAdminMgrRsp 管理员人数达到上限")
            return
        end

        if not tTargetUser then
            ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.NoClubUser
            ClubSAdminMgrResp.sErrStr = "not find user in club"
            MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
            Base.Log("_OnDBClubAdminMgrRsp 目标玩家不是不存在")
            return
        end
        --如果目标玩家是管理员了
        if tTargetUser.nIdentify~=Define.nMember then
            ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.isAdmin
            ClubSAdminMgrResp.sErrStr = "Target User is Admin"
            MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
            Base.Log("_OnDBClubAdminMgrRsp 目标玩家是管理员了")
            return
        end
    else
        --删除管理员
        local tTargetUser = PublicRedis.GetClubUserInfo(tData.nClubId,tData.nUserId)
        if not tTargetUser then
            ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.NoClubUser
            ClubSAdminMgrResp.sErrStr = "not find user in club"
            MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
            Base.Log("_OnDBClubAdminMgrRsp 目标玩家不是不存在")
            return
        end
        if tTargetUser.nIdentify~=Define.nAdmin then
            ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.isNotAdmin
            ClubSAdminMgrResp.sErrStr = "Target User is not Admin"
            MsgApi.SendToClient(sClientID,"ClubSAdminMgrResp",ClubSAdminMgrResp)
            Base.Log("_OnDBClubAdminMgrRsp 目标玩家不是管理员")
            return
        end
    end
	
    SlaveData.tDBOprateWaitting.arrAdminMgr[nUserId] = os.time()

    local tUserInfo = PublicUserInfo.GetUserBasic(nUserId) or {}
    local tExData = {}
    tExData.sClubName = tClub.sClubName
    tExData.nClubId = tClub.nClubId
    tExData.nUserId = nUserId
    tExData.nOpType = (tData.nOpType==1 and 3) or 4
    tExData.sUserName = tUserInfo.sNickName or ""
    tExData.sFaceId = tUserInfo.sFaceID or "1"

    local ClubAdminMgrReq = {}
    ClubAdminMgrReq.nClubId = tData.nClubId
    ClubAdminMgrReq.nUserId = tData.nUserId
    ClubAdminMgrReq.nOpType = tData.nOpType
    ClubAdminMgrReq.nSendUserId = nUserId
    ClubAdminMgrReq.sExData = Cjson.encode(tExData)
    MsgApi.SendToDBServer("ClubAdminMgrReq",ClubAdminMgrReq,nUserId)
end

--DB服返回 俱乐部增加删除管理员 返回
function MsgClient.OnDBClubAdminMgrRsp(sReturnKey, Data, nLen)
    local strProto = "ClubAdminMgrRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubAdminMgrRsp nClubId_%d,myself_%d,nOpType_%d,nUserId_%d,nRlt_%d",
    tData.nClubId,tData.nSendUserId,tData.nOpType,tData.nUserId,tData.nRlt)

    local ClubSAdminMgrResp = {}
    ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.Success
    ClubSAdminMgrResp.sErrStr = ""
    ClubSAdminMgrResp.nUserId = tData.nUserId
    ClubSAdminMgrResp.nClubId = tData.nClubId
    ClubSAdminMgrResp.nOpType = tData.nOpType

    if ClubSAdminMgrResp.nRlt==0 then
        local arrPower = {}
        for _,v in pairs(Define.tPower) do
            table.insert(arrPower,{nPowerType=v,isOpen=false})
        end

        ClubSAdminMgrResp.sErrStr = "success"
        if tData.nOpType==1 then --增加管理员
            local tAdmin = {}
            tAdmin.nUserId = tData.tAdmin.nUserId
            tAdmin.sFaceId = tData.tAdmin.sFaceId
            tAdmin.sName = tData.tAdmin.sName
            tAdmin.nSex = tData.tAdmin.nSex
            tAdmin.nClubId = tData.tAdmin.nClubId
            tAdmin.sShopAcc = tData.tAdmin.sShopAcc
            tAdmin.sPower = Cjson.encode(arrPower)
            ClubSAdminMgrResp.tAdmin = tAdmin
            Base.Log("_OnDBClubAdminMgrRsp tAdmin_%s",Cjson.encode(tAdmin))

            --修改redis上玩家的身份
            PublicRedis.SetClubUserInfo(tData.nClubId,{{nUserId=tData.nUserId,nIdentify=Define.nAdmin}})

            --发送俱乐部玩家信息改变
            MsgApi.SendUserInfoChange(tData.nClubId,tData.nUserId,{nIdentify = Define.nAdmin})
        else 
            --删除管理员

            --发送俱乐部玩家信息改变
            MsgApi.SendUserInfoChange(tData.nClubId,tData.nUserId,{nIdentify = Define.nMember,arrPower={}})

            --发送俱乐部申请数量给被操作玩家
            local ClubSSceneChangeNotify = {}
	        ClubSSceneChangeNotify.nClubId = tData.nClubId
            ClubSSceneChangeNotify.sChangeInfo = Cjson.encode({nApplyJionCnt=0,nApplyAddGoldCnt=0,nApplyCutGoldCnt=0})
            MsgApi.SendToUser(tData.nUserId,"ClubSSceneChangeNotify",ClubSSceneChangeNotify)

            --修改redis上玩家的身份
            PublicRedis.SetClubUserInfo(tData.nClubId,{{nUserId=tData.nUserId,nIdentify=Define.nMember}})
        end
    elseif ClubSAdminMgrResp.nRlt==5 then
        ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.NoClubUser
        ClubSAdminMgrResp.sErrStr = "not find admin"
        Base.Log("_OnDBClubAdminMgrRsp 被操作的玩家不存在")
    elseif ClubSAdminMgrResp.nRlt==6 then
        ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.isAdmin
        ClubSAdminMgrResp.sErrStr = "user is admin"
        Base.Log("_OnDBClubAdminMgrRsp 玩家已经是管理员了")
    elseif ClubSAdminMgrResp.nRlt==7 then
        ClubSAdminMgrResp.nRlt = PubErrCode.AdminMgr.isMaster
        ClubSAdminMgrResp.sErrStr = "user is admin"
        Base.Log("_OnDBClubAdminMgrRsp 被操作玩家是主席")
    end
    MsgApi.SendToUser(tData.nSendUserId,"ClubSAdminMgrResp",ClubSAdminMgrResp)
    SlaveData.tDBOprateWaitting.arrAdminMgr[tData.nSendUserId] = nil
end

--修改管理员权限请求
function MsgClient.OnClubSChangeAdminPowerReq(sClientID, Data, nLen)
    local strProto = "ClubSChangeAdminPowerReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    local arrPower = {}
    for k,v in pairs(tData.arrPower) do
        if v.nPowerType and type(v.nPowerType)=="number" then
            local tPower = {}
            tPower.nPowerType = v.nPowerType
            tPower.isOpen = v.isOpen
            table.insert(arrPower,tPower)
        end
    end
    Base.Log("_OnClubSChangeAdminPowerReq 修改管理员权限请求 nClubId_%d,nUserId_%d,myself_%d,arrPower_%s",
    tData.nClubId,tData.nUserId,nUserId,Cjson.encode(arrPower))

    local ClubSChangeAdminPowerResp = {}
    ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.Success
    ClubSChangeAdminPowerResp.sErrStr = ""
    ClubSChangeAdminPowerResp.nUserId = tData.nUserId
    ClubSChangeAdminPowerResp.nClubId = tData.nClubId

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrChangeAdminPower[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSChangeAdminPowerReq 请求过于频繁，等待上一个请求结束")
            ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.WaitDBReturn
            ClubSChangeAdminPowerResp.sErrStr = "too frequently,waitting last req return"
            MsgApi.SendToClient(sClientID,"ClubSChangeAdminPowerResp",ClubSChangeAdminPowerResp)
            return
        end
    end

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSChangeAdminPowerReq club is hall")
        ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.IsHall
        ClubSChangeAdminPowerResp.sErrStr = "club is hall"
        MsgApi.SendToClient(sClientID,"ClubSChangeAdminPowerResp",ClubSChangeAdminPowerResp)
        return
    end

    --参数校验
    if #arrPower>0 then
        for k,v in pairs(arrPower) do
            local isSame = false
            for _,nPowerType in pairs(Define.tPower) do
                if v.nPowerType==nPowerType then
                    isSame = true
                    break
                end
            end
            if not isSame then
                ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.ParamsErr
                ClubSChangeAdminPowerResp.sErrStr = "nPowerType Err"
                MsgApi.SendToClient(sClientID,"ClubSChangeAdminPowerResp",ClubSChangeAdminPowerResp)
                Base.Log("_OnClubSChangeAdminPowerReq nPowerType Err")
                return
            end
        end
    else
        ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.ParamsErr
        ClubSChangeAdminPowerResp.sErrStr = "nPowerType Err"
        MsgApi.SendToClient(sClientID,"ClubSChangeAdminPowerResp",ClubSChangeAdminPowerResp)
        Base.Log("_OnClubSChangeAdminPowerReq nPowerType Err,#arrPower=0")
        return
    end
    

    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSChangeAdminPowerReq club is not find")
        ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.NoClub
        ClubSChangeAdminPowerResp.sErrStr = "club is not find"
        MsgApi.SendToClient(sClientID,"ClubSChangeAdminPowerResp",ClubSChangeAdminPowerResp)
        return
    end

    --不是主席
    if tClub.nMaster~= nUserId then
        Base.Log("_OnClubSChangeAdminPowerReq you is not master")
        ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.NotMaster
        ClubSChangeAdminPowerResp.sErrStr = "you is not master"
        MsgApi.SendToClient(sClientID,"ClubSChangeAdminPowerResp",ClubSChangeAdminPowerResp)
        return
    end

    --是主席
    if tData.nUserId==tClub.nMaster then
        Base.Log("_OnClubSChangeAdminPowerReq user is master")
        ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.isMaster
        ClubSChangeAdminPowerResp.sErrStr = "user is master"
        MsgApi.SendToClient(sClientID,"ClubSChangeAdminPowerResp",ClubSChangeAdminPowerResp)
        return
    end

    --被操作玩家信息
    local arrChangePower = {} --被修改的权限
    local tClubUserInfo = PublicRedis.GetClubUserInfo(tData.nClubId,tData.nUserId)
    if tClubUserInfo then
        --管理员权限
        local isSuccee,arrUserPower = pcall(Cjson.decode,tClubUserInfo.sPower)
        if isSuccee then
            for _,v in pairs(arrPower) do
                local isChange = true
                for _,v1 in pairs(arrUserPower) do
                    if v.nPowerType==v1.nPowerType and v.isOpen==v1.isOpen then
                        isChange = false
                    end
                end
                if isChange then
                    table.insert(arrChangePower,v)
                end
            end
        end
    end

    SlaveData.tDBOprateWaitting.arrChangeAdminPower[nUserId] = os.time()

    local tUserInfo = PublicUserInfo.GetUserBasic(nUserId) or {}
    local tExData = {}
    tExData.sClubName = tClub.sClubName
    tExData.nClubId = tClub.nClubId
    tExData.nUserId = nUserId
    tExData.nOpType = 6
    tExData.sUserName = tUserInfo.sNickName or ""
    tExData.sFaceId = tUserInfo.sFaceID or "1"
    tExData.arrChangePower = arrChangePower

    local ClubChangeAdminPowerReq = {}
    ClubChangeAdminPowerReq.nClubId = tData.nClubId
    ClubChangeAdminPowerReq.nUserId = tData.nUserId
    ClubChangeAdminPowerReq.nSendUserId = nUserId
    ClubChangeAdminPowerReq.sPower = Cjson.encode(arrPower)
    ClubChangeAdminPowerReq.sExData = Cjson.encode(tExData)
    MsgApi.SendToDBServer("ClubChangeAdminPowerReq",ClubChangeAdminPowerReq,nUserId)
end

--DB服返回 修改管理员权限 返回
function MsgClient.OnDBClubChangeAdminPowerRsp(sReturnKey, Data, nLen)
    local strProto = "ClubChangeAdminPowerRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubChangeAdminPowerRsp nClubId_%d,nUserId_%d,nSendUserId_%d,nRlt_%d",
    tData.nClubId,tData.nUserId,tData.nSendUserId,tData.nRlt)

    local ClubSChangeAdminPowerResp = {}
    ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.Success
    ClubSChangeAdminPowerResp.sErrStr = ""
    ClubSChangeAdminPowerResp.nUserId = tData.nUserId
    ClubSChangeAdminPowerResp.nClubId = tData.nClubId

    if tData.nRlt == 0 then
        ClubSChangeAdminPowerResp.sErrStr = "success"
        ClubSChangeAdminPowerResp.sPower = tData.sPower
        Base.Log("_OnDBClubChangeAdminPowerRsp sPower_%s",tData.sPower)

        --修改redis上玩家的权限
        PublicRedis.SetClubUserInfo(tData.nClubId,{{nUserId=tData.nUserId,sPower=tData.sPower}})

        --发送俱乐部玩家信息改变
        MsgApi.SendUserInfoChange(tData.nClubId,tData.nUserId,{sPower = tData.sPower})

        local isSuccee,arrPower = pcall(Cjson.decode,tData.sPower)
        if isSuccee then
            local tClubS = ClubSManager.GetClub(tData.nClubId)
            if tClubS then
                local nApplyJionCnt,nApplyAddGoldCnt,nApplyCutGoldCnt = tClubS:GetApplyCnt()
                local tChangeInfo = {}
                if MsgClient._CheckPower(arrPower,Define.tPower.Member) then
                    tChangeInfo.nApplyJionCnt = nApplyJionCnt
                else
                    tChangeInfo.nApplyJionCnt = 0
                end
                if MsgClient._CheckPower(arrPower,Define.tPower.ClubGold) then
                    tChangeInfo.nApplyAddGoldCnt = nApplyAddGoldCnt
                    tChangeInfo.nApplyCutGoldCnt = nApplyCutGoldCnt
                else
                    tChangeInfo.nApplyAddGoldCnt = 0
                    tChangeInfo.nApplyCutGoldCnt = 0
                end
                Base.Log("tChangeInfo:%s",Cjson.encode(tChangeInfo))
                --发送俱乐部申请数量给被操作玩家
                local ClubSSceneChangeNotify = {}
                ClubSSceneChangeNotify.nClubId = tData.nClubId
                ClubSSceneChangeNotify.sChangeInfo = Cjson.encode(tChangeInfo)
                MsgApi.SendToUser(tData.nUserId,"ClubSSceneChangeNotify",ClubSSceneChangeNotify)
            else
                Base.Log("_OnDBClubChangeAdminPowerRsp 没有找到俱乐部 nClubId_%d",tData.nClubId)
            end
        else
            Base.Log("_OnDBClubChangeAdminPowerRsp decode sPower fail")
        end

        
    elseif tData.nRlt==5 then
        ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.NoClubUser
        ClubSChangeAdminPowerResp.sErrStr = "user is not find"
        Base.Log("_OnDBClubChangeAdminPowerRsp 被操作的玩家不存在")
    elseif tData.nRlt==2 then
        ClubSChangeAdminPowerResp.nRlt = PubErrCode.ChangeAdminPower.ParamsErr
        ClubSChangeAdminPowerResp.sErrStr = "nPowerType Err"
        Base.Log("_OnDBClubChangeAdminPowerRsp nPowerType Err,#arrPower=0")
    end
    MsgApi.SendToUser(tData.nSendUserId,"ClubSChangeAdminPowerResp",ClubSChangeAdminPowerResp)
    SlaveData.tDBOprateWaitting.arrChangeAdminPower[tData.nSendUserId] = nil
end

--俱乐部账户的俱乐部币流水请求
function MsgClient.OnClubSGoldChangeRecordReq(sClientID, Data, nLen)
    local strProto = "ClubSGoldChangeRecordReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGoldChangeRecordReq 俱乐部账户的俱乐部币流水请求 nClubId_%d,nUserId_%d,nIdOfStart_%d,nCnt_%d",
    tData.nClubId,nUserId,tData.nIdOfStart,tData.nCnt)

    local ClubSGoldChangeRecordResp = {}
    ClubSGoldChangeRecordResp.arrRecords = {}
    ClubSGoldChangeRecordResp.nAllCnt = 0
    ClubSGoldChangeRecordResp.nClubId = tData.nClubId

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSGoldChangeRecordReq club is hall")
        MsgApi.SendToClient(sClientID,"ClubSGoldChangeRecordResp",ClubSGoldChangeRecordResp)
        return
    end

    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSGoldChangeRecordReq club is not find")
        MsgApi.SendToClient(sClientID,"ClubSGoldChangeRecordResp",ClubSGoldChangeRecordResp)
        return
    end

    --不是主席
    if tClub.nMaster~= nUserId then
        Base.Log("_OnClubSGoldChangeRecordReq you is not master")
        MsgApi.SendToClient(sClientID,"ClubSGoldChangeRecordResp",ClubSGoldChangeRecordResp)
        return
    end

    local nIdOfStart = tData.nIdOfStart
    local nCnt = tData.nCnt
    if nIdOfStart<=0 then
        nIdOfStart = 0
    end
    if nCnt<=0 then
        nCnt=0
    elseif nCnt>30 then
        nCnt = 30
    end
    local ClubGoldChangeRecordReq = {}
    ClubGoldChangeRecordReq.nClubId = tData.nClubId
    ClubGoldChangeRecordReq.nIdOfStart = tData.nIdOfStart
    ClubGoldChangeRecordReq.nCnt = tData.nCnt
    ClubGoldChangeRecordReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubGoldChangeRecordReq",ClubGoldChangeRecordReq,nUserId)
end

--DB服返回 俱乐部账户的俱乐部币流水 返回
function MsgClient.OnDBClubGoldChangeRecordRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGoldChangeRecordRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrRecords = {}
    for k,v in pairs(tData.arrRecords) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.nUserId = v.nUserId
            tItem.nChange = v.nChange
            tItem.sTime = v.sTime
            if v.nUserId>0 then
                tItem.sName = v.sName
            end
            table.insert(arrRecords,tItem)
        end
    end

    Base.Log("_OnDBClubGoldChangeRecordRsp nClubId_%d,nUserId_%d,nAllCnt_%d,#arrRecords_%d",
    tData.nClubId,tData.nUserId,tData.nAllCnt,#arrRecords)

    local ClubSGoldChangeRecordResp = {}
    ClubSGoldChangeRecordResp.arrRecords = arrRecords
    ClubSGoldChangeRecordResp.nAllCnt = tData.nAllCnt
    ClubSGoldChangeRecordResp.nClubId = tData.nClubId
    MsgApi.SendToUser(tData.nUserId,"ClubSGoldChangeRecordResp",ClubSGoldChangeRecordResp)
end

--俱乐部申请列表请求
function MsgClient.OnClubSApplyListReq(sClientID, Data, nLen)
    local strProto = "ClubSApplyListReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSApplyListReq 俱乐部申请列表请求 nClubId_%d,nUserId_%d,nIdOfStart_%d,nCnt_%d,nType_%d",
    tData.nClubId,nUserId,tData.nIdOfStart,tData.nCnt,tData.nType)

    local ClubSApplyListResp = {}
    ClubSApplyListResp.arrApplyList = {}
    ClubSApplyListResp.nAllCnt = 0
    ClubSApplyListResp.nClubId = tData.nClubId
    ClubSApplyListResp.nType = tData.nType

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSApplyListReq club is hall")
        MsgApi.SendToClient(sClientID,"ClubSApplyListResp",ClubSApplyListResp)
        return
    end

    --参数校验
    if tData.nType~=1 and tData.nType~=2 and tData.nType~=3 then
        Base.Log("_OnClubSApplyListReq nType Err")
        MsgApi.SendToClient(sClientID,"ClubSApplyListResp",ClubSApplyListResp)
        return
    end

    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSApplyListReq club is not find")
        MsgApi.SendToClient(sClientID,"ClubSApplyListResp",ClubSApplyListResp)
        return
    end

    --操作玩家是否是俱乐部成员
    local tAdmin = PublicRedis.GetClubUserInfo(tData.nClubId,nUserId)
    if not tAdmin then
        tClub:Print("_OnClubSApplyListReq not find user in Club")
        MsgApi.SendToClient(sClientID,"ClubSApplyListResp",ClubSApplyListResp)
        return
    end
    --操作玩家是否是管理员或者主席
    if tAdmin.nIdentify~=Define.nMaster and tAdmin.nIdentify~=Define.nAdmin then
        tClub:Print("_OnClubSApplyListReq you not admin, nUserId:%d nIdentify:%d",nUserId,tAdmin.nIdentify)
        MsgApi.SendToClient(sClientID,"ClubSApplyListResp",ClubSApplyListResp)
        return
    end

    -- --管理员权限
    -- local isSuccee,arrPower = pcall(Cjson.decode,tAdmin.sPower)
    -- if not isSuccee then
    --     tClub:Print("_OnClubSApplyListReq decode tAdmin:%d sPower fail, sPower:%s",nUserId,tostring(tAdmin.sPower))
    --     arrPower = {}
    -- end

    -- --权限校验
    -- local hasPower = false
    -- for _,v in pairs(arrPower) do
    --     if v.nPowerType==Define.tPower.Member and v.isOpen==true then
    --         hasPower = true
    --         break
    --     end
    -- end
    -- if not hasPower then --没有操作权限
    --     Base.Log("_OnClubSApplyListReq no power")
    --     MsgApi.SendToClient(sClientID,"ClubSApplyListResp",ClubSApplyListResp)
    --     return
    -- end

    local ClubApplyListReq = {}
    ClubApplyListReq.nClubId = tData.nClubId
    ClubApplyListReq.nType = tData.nType
    ClubApplyListReq.nIdOfStart = tData.nIdOfStart
    ClubApplyListReq.nCnt = tData.nCnt
    ClubApplyListReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubApplyListReq",ClubApplyListReq,nUserId)
end

--DB服返回 俱乐部申请列表 返回
function MsgClient.OnDBClubApplyListRsp(sReturnKey, Data, nLen)
    local strProto = "ClubApplyListRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrApplyList = {}
    for k,v in pairs(tData.arrApplyList) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.nUserId = v.nUserId
            tItem.sFaceId = v.sFaceId
            tItem.sName = v.sName
            tItem.nSex = v.nSex
            tItem.sTime = v.sTime
            tItem.nType = v.nType
            if v.nType==1 or v.nType==2 then
                tItem.nChange = v.nChange
            end
            table.insert(arrApplyList,tItem)
        end
    end

    Base.Log("_OnDBClubApplyListRsp nClubId_%d,nUserId_%d,nAllCnt_%d,nType_%d,#arrApplyList_%d",
    tData.nClubId,tData.nUserId,tData.nAllCnt,tData.nType,#arrApplyList)

    local ClubSApplyListResp = {}
    ClubSApplyListResp.arrApplyList = arrApplyList
    ClubSApplyListResp.nAllCnt = tData.nAllCnt
    ClubSApplyListResp.nClubId = tData.nClubId
    ClubSApplyListResp.nType = tData.nType
    MsgApi.SendToUser(tData.nUserId,"ClubSApplyListResp",ClubSApplyListResp)
end

--俱乐部申请处理请求
function MsgClient.OnClubSApplyHandleReq(sClientID, Data, nLen)
    local strProto = "ClubSApplyHandleReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSApplyHandleReq 俱乐部申请处理请求 nClubId_%d,nUserId_%d,nId_%d,nType_%d,nOpType_%d,sPassWord_%s",
    tData.nClubId,nUserId,tData.nId,tData.nType,tData.nOpType,tData.sPassWord or "")

    MsgClient.HandleApply(nUserId,tData)
end

--处理俱乐部的申请
function MsgClient.HandleApply(nUserId,tData)
    local ClubSApplyHandleResp = {
        nRlt = PubErrCode.ApplyDeal.Success,
        sErrStr = "",
        nId = tData.nId,
        nType = tData.nType,
        nClubId = tData.nClubId,
        nOpType = tData.nOpType,
    }

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrApplyDeal[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_HandleApply 请求过于频繁，等待上一个请求结束")
            ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.WaitDBReturn
            ClubSApplyHandleResp.sErrStr = "too frequently,waitting last req return"
            MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
            return
        end
    end

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_HandleApply club is hall")
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.IsHall
        ClubSApplyHandleResp.sErrStr = "club is hall"
        MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        return
    end

    --参数校验
    if tData.nType~=1 and tData.nType~=2 and tData.nType~=3 then
        Base.Log("_HandleApply nType Err")
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.ParamsErr
        ClubSApplyHandleResp.sErrStr = "nType Err"
        MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        return
    end

    if tData.nOpType~=1 and tData.nOpType~=2 then
        Base.Log("_HandleApply nOpType Err")
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.ParamsErr
        ClubSApplyHandleResp.sErrStr = "nOpType Err"
        MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        return
    end
    if tData.nId<=0 then
        Base.Log("_HandleApply nId Err")
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.ParamsErr
        ClubSApplyHandleResp.sErrStr = "nId Err"
        MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        return
    end

    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_HandleApply club is not find")
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.NoClub
        ClubSApplyHandleResp.sErrStr = "club is not find"
        MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        return
    end

    --校验库存密码是否正确
    if tData.nType==1 or tData.nType==2 then
        if tData.sPassWord~=tClub.sPassWord then
            tClub:Print("_HandleApply sPassWord is not Right,tClub.sPassWord:%s",tClub.sPassWord)
            ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.PassWordErr
            ClubSApplyHandleResp.sErrStr = "sPassWord is not Right"
            MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
            return
        end
    end

    --操作玩家是否是俱乐部成员
    local tAdmin = PublicRedis.GetClubUserInfo(tData.nClubId,nUserId)
    if not tAdmin then
        tClub:Print("_HandleApply not find tAdmin in Club")
        ClubSApplyHandleResp.nRlt = PubErrCode.AdminOprate.NotAdmin
        ClubSApplyHandleResp.sErrStr = "not find tAdmin in Club"
        MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        return
    end
    --操作玩家是否是管理员或者主席
    if tAdmin.nIdentify~=Define.nMaster and tAdmin.nIdentify~=Define.nAdmin then
        tClub:Print("_HandleApply you not admin, nUserId:%d nIdentify:%d",nUserId,tAdmin.nIdentify)
        ClubSApplyHandleResp.nRlt = PubErrCode.AdminOprate.NotAdmin
        ClubSApplyHandleResp.sErrStr = "you not admin"
        MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        return
    end

    --管理员权限
    local isSuccee,arrPower = pcall(Cjson.decode,tAdmin.sPower)
    if not isSuccee then
        tClub:Print("_HandleApply decode tAdmin:%d sPower fail, sPower:%s",nUserId,tostring(tAdmin.sPower))
        arrPower = {}
    end

    local nPowerType = 0
    if tData.nType==1 or tData.nType==2 then
        --检查俱乐部币管理权限
        nPowerType = Define.tPower.ClubGold
    elseif tData.nType==3 then
        --检查俱乐部成员管理权限
        nPowerType = Define.tPower.Member
    end

    --检查是否有管理权限
    local hasPower = MsgClient._CheckPower(arrPower,nPowerType)
    if not hasPower then
        tClub:Print("_HandleApply no power,sPower_%s",tAdmin.sPower)
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.NoPower
        ClubSApplyHandleResp.sErrStr = "no power"
        MsgApi.SendToUser(nUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        return
    end


    SlaveData.tDBOprateWaitting.arrApplyDeal[nUserId] = os.time()
    
    local tSend = {}
    tSend.nId = tData.nId
    tSend.nType = tData.nType
    local tExData = {}
    tExData.nClubId = tData.nClubId
    tExData.nOpUserId = nUserId
    tExData.nOpType = tData.nOpType
    tExData.sPassWord = tData.sPassWord
    tSend.sExData = Cjson.encode(tExData)
    MsgApi.SendToDBServer("ClubApplyInfoReq",tSend,nUserId)
end

--DB服返回 俱乐部某条申请的信息 返回
function MsgClient.OnDBClubApplyInfoRsp(sReturnKey, Data, nLen)
    local strProto = "ClubApplyInfoRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubApplyInfoRsp 俱乐部某条申请的信息 sExData:%s sApplyInfo:%s",tData.sExData,tData.sApplyInfo)

    local tExData = Cjson.decode(tData.sExData)
    local tApplyInfo = Cjson.decode(tData.sApplyInfo)

    local ClubSApplyHandleResp = {
        nRlt = PubErrCode.ApplyDeal.Success,
        sErrStr = "",
        nId = tApplyInfo.nId,
        nType = tApplyInfo.nType,
        nClubId = tExData.nClubId,
        nOpType = tExData.nOpType,
    }

    if not tApplyInfo.nStatus then
        --没有找到该条申请的信息
        Base.Log("_OnDBClubApplyInfoRsp not find ApplyInfo %s",tData.sApplyInfo)
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.NoApply
        ClubSApplyHandleResp.sErrStr = "not find ApplyInfo"
        MsgApi.SendToUser(tExData.nOpUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        SlaveData.tDBOprateWaitting.arrApplyDeal[tExData.nOpUserId] = nil
        return
    end

    if tApplyInfo.nStatus~=0 then
        --已处理
        Base.Log("_OnDBClubApplyInfoRsp Apply is Deal")
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.IsDeal
        ClubSApplyHandleResp.sErrStr = "Apply is Deal"
        MsgApi.SendToUser(tExData.nOpUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        SlaveData.tDBOprateWaitting.arrApplyDeal[tExData.nOpUserId] = nil
        return
    end

    local sDealUserId = PublicRedis.GetApplyDealLock(tExData.nClubId,tApplyInfo.nId,tApplyInfo.nType)
    if sDealUserId then
        --正被其它人处理
        Base.Log("_OnDBClubApplyInfoRsp Apply is Dealing by other_%s",sDealUserId)
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.IsInDealing
        ClubSApplyHandleResp.sErrStr = "Apply is Dealing by other"
        MsgApi.SendToUser(tExData.nOpUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
        SlaveData.tDBOprateWaitting.arrApplyDeal[tExData.nOpUserId] = nil
        return
    end

    --对这条申请加锁
    PublicRedis.SetApplyDealLock(tExData.nClubId,tApplyInfo.nId,tApplyInfo.nType,tExData.nOpUserId)

    local nMaxUserCnt = 0
    if tExData.nOpType==1 then
        --同意
        if tApplyInfo.nType==1 or tApplyInfo.nType==2 then
            --被操作玩家是否是俱乐部成员
            local tTargetUser = PublicRedis.GetClubUserInfo(tExData.nClubId,tApplyInfo.nUserId)
            if not tTargetUser then
                Base.Log("_OnDBClubApplyInfoRsp TargetUser is not in Club")
                ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.NoClubUser
                ClubSApplyHandleResp.sErrStr = "TargetUser is not in Club"
                MsgApi.SendToUser(tExData.nOpUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
                --删除申请处理锁
                PublicRedis.DelApplyDealLock(tExData.nClubId,tExData.nId,tExData.nType)
                SlaveData.tDBOprateWaitting.arrApplyDeal[tExData.nOpUserId] = nil
                return
            end

            if tApplyInfo.nType==1 then
                ClubSApplyHandleResp.nRlt,ClubSApplyHandleResp.sErrStr = MsgClient.HanleAddClubGoldApply(tExData,tApplyInfo)
            elseif tApplyInfo.nType==2 then
                ClubSApplyHandleResp.nRlt,ClubSApplyHandleResp.sErrStr = MsgClient.HanleCutClubGoldApply(tExData,tApplyInfo)
            end
    
            if ClubSApplyHandleResp.nRlt~=PubErrCode.ApplyDeal.Success then
                --俱乐部币处理没有成功
                Base.Log("_OnDBClubApplyInfoRsp 俱乐部币处理没有成功 nRlt:%d sErrStr:%s",ClubSApplyHandleResp.nRlt,ClubSApplyHandleResp.sErrStr)
                MsgApi.SendToUser(tExData.nOpUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
                --删除申请处理锁
                PublicRedis.DelApplyDealLock(tExData.nClubId,tExData.nId,tExData.nType)
                SlaveData.tDBOprateWaitting.arrApplyDeal[tExData.nOpUserId] = nil
                return
            end
        elseif tApplyInfo.nType==3 then
            --同意邀请加入俱乐部
            local tClub = ClubSManager.GetClub(tExData.nClubId)
            if not tClub then
                Base.Log("_OnDBClubApplyInfoRsp 俱乐部不存在")
                ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.NoClub
                ClubSApplyHandleResp.sErrStr = "no club"
                MsgApi.SendToUser(tExData.nOpUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
                SlaveData.tDBOprateWaitting.arrApplyDeal[tExData.nOpUserId] = nil
                return
            end

            if tClub.nUserCnt>=tClub.nMaxUserCnt then
                Base.Log("_OnDBClubGetUserNoticeInfoRsp 俱乐部已满人")
                ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.ClubIsFull
                ClubSApplyHandleResp.sErrStr = "Club member is full"
                MsgApi.SendToUser(tExData.nOpUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
                SlaveData.tDBOprateWaitting.arrApplyDeal[tExData.nOpUserId] = nil
                return
            end

            nMaxUserCnt = tClub.nMaxUserCnt
        end

        Base.Log("_OnDBClubApplyInfoRsp agree success")
    else
        --拒绝
        Base.Log("_OnDBClubApplyInfoRsp refuse success")
    end

    --发送到db服
    local tSend = {}
    tSend.nClubId = tExData.nClubId
    tSend.nId = tApplyInfo.nId
    tSend.nOpType = tExData.nOpType
    tSend.nOpUserId = tExData.nOpUserId
    tSend.nType = tApplyInfo.nType
    tSend.nTUserId = tApplyInfo.nUserId
    tSend.nMaxUserCnt = nMaxUserCnt
    MsgApi.SendToDBServer("ClubApplyHandleReq",tSend,tApplyInfo.nUserId)
end

--处理增加俱乐部币申请
--@param tExData {nClubId=俱乐部id,nOpUserId=管理员id}
--@return tApplyInfo {nChange=申请的俱乐部币,nUserId=申请玩家的id}
function MsgClient.HanleAddClubGoldApply(tExData,tApplyInfo)
    --尝试锁住俱乐部总资产
    local isSuccee,sErr,nCurGold = PublicUserInfo.LockClubSumAsset(tExData.nClubId,PublicApi.Floor_2(tApplyInfo.nChange),tExData.nClubId)
    if not isSuccee then
        Base.Log("_HanleAddClubGoldApply LockClubSumAsset fail, sErr:%s, nCurGold:%f",sErr,nCurGold)
        return PubErrCode.ApplyDeal.ClubGoldLess,"ClubGoldLess"
    end

    --尝试解锁并且扣除俱乐部总资产
    local isSuccee1,sErr1,nGoldAfterChange = PublicUserInfo.UnLockAndMinusClubSumAsset(tExData.nClubId,PublicApi.Floor_2(tApplyInfo.nChange),Define.SourceType.ApplyAddGold,tApplyInfo.nUserId,tExData.nOpUserId,tExData.nClubId)
    if not isSuccee1 then
        Base.Log("_HanleAddClubGoldApply UnLockAndMinusClubSumAsset fail, sErr1:%s, nGoldAfterChange:%f",sErr1 or "",nGoldAfterChange or 0)
        return PubErrCode.ApplyDeal.ClubGoldLess,"ClubGoldLess"
    end

    --给玩家增加俱乐部币
    local t = {nUserID=tApplyInfo.nUserId,nItemID=tExData.nClubId,nDel= PublicApi.Floor_2(tApplyInfo.nChange),nSourceType=Define.SourceType.ApplyAddGold}
    local isSuccee2 = PublicUserInfo.ChangeUserTreasure(t)
    if not isSuccee2 then
        Base.Log("_HanleAddClubGoldApply add TargetUser Club Gold Fail")
        return PubErrCode.ApplyDeal.ChangeClubGoldFail,"add TargetUser Club Gold Fail"
    end

    --获取个人俱乐部币
    local nUserClubGold =  PublicUserInfo.Get_User_Gold(tApplyInfo.nUserId,tExData.nClubId)

    --发送俱乐部玩家信息改变
    MsgApi.SendUserInfoChange(tExData.nClubId,tApplyInfo.nUserId,{nClubGold = nUserClubGold})

    Base.Log("_HanleAddClubGoldApply add TargetUser Club Gold success")

    return PubErrCode.ApplyDeal.Success,"Success"
end

--处理退还俱乐部币申请
--@param tExData {nClubId=俱乐部id,nOpUserId=管理员id,sPassWord=库存密码}
--@return tApplyInfo {nChange=申请的俱乐部币,nUserId=申请玩家的id,nId=申请id}
function MsgClient.HanleCutClubGoldApply(tExData,tApplyInfo)
    --检查被操作玩家是否在游戏中
    local nCurGameId,nCurRoomId,sCurServerKey = PublicUserInfo.GetUserPlayingGame(tApplyInfo.nUserId)
    if nCurGameId then
        Base.Log("_HanleCutClubGoldApply targetUser is in Game,nTUserId_%d nCurGameId_%s nCurRoomId_%s sCurServerKey_%s",
        tApplyInfo.nUserId,tostring(nCurGameId),tostring(nCurRoomId),tostring(sCurServerKey))
        -- --发送踢人到游戏服
        -- MsgApi.SendKickUserToGame(tApplyInfo.nUserId,sCurServerKey)
        --插入消息队列
        local tMsgData = {}
        tMsgData.nClubId = tExData.nClubId
        tMsgData.nTUserId = tApplyInfo.nUserId
        tMsgData.nType = tApplyInfo.nType
        tMsgData.nOpUserId = tExData.nOpUserId
        tMsgData.nChange = tApplyInfo.nChange
        tMsgData.sPassWord = tExData.sPassWord
        tMsgData.nId = tApplyInfo.nId
        tMsgData.MsgType = Define.MsgType.DelApply
        MsgOnTime.Push(tMsgData)
        return PubErrCode.ApplyDeal.InGame,"use in game"
    end

    --尝试个人俱乐部币
    local isSuccee,sErr,nCurGold = PublicUserInfo.Gold_Lock(tApplyInfo.nUserId, PublicApi.Floor_2(tApplyInfo.nChange),tExData.nClubId)
    if not isSuccee then
        Base.Log("_HanleCutClubGoldApply LockClubSumAsset fail, sErr:%s, nCurGold:%f",sErr or "",nCurGold or 0)
        return PubErrCode.ApplyDeal.UserClubGoldLess,"UserClubGoldLess"
    end

    --尝试解锁并且扣除个人俱乐部币
    local isSuccee1,sErr1,nGoldAfterChange = PublicUserInfo.UnLockAndMinus(tApplyInfo.nUserId, PublicApi.Floor_2(tApplyInfo.nChange),Define.SourceType.ApplyDelGold,1,tExData.nClubId)
    if not isSuccee1 then
        Base.Log("_HanleCutClubGoldApply UnLockAndMinus fail, sErr1:%s, nGoldAfterChange:%f",sErr1 or "",nGoldAfterChange or 0)
        return PubErrCode.ApplyDeal.UserClubGoldLess,"UserClubGoldLess"
    end

    --增加俱乐部总资产
    local t = {nClubId=tExData.nClubId,nChange=PublicApi.Floor_2(tApplyInfo.nChange),nSourceType=Define.SourceType.ApplyDelGold,nMemberId=tApplyInfo.nUserId,nHandleId=tExData.nOpUserId,nItemId=tExData.nClubId}
    local isSuccee2 = PublicUserInfo.ChangeClubSumAsset(t)
    if not isSuccee2 then
        Base.Log("_HanleCutClubGoldApply add ClubGold Fail")
        return PubErrCode.ApplyDeal.ChangeClubGoldFail,"add ClubGold Fail"
    end

    --发送俱乐部玩家信息改变
    MsgApi.SendUserInfoChange(tExData.nClubId,tApplyInfo.nUserId,{nClubGold = nGoldAfterChange})

    Base.Log("_HanleCutClubGoldApply del TargetUser Club Gold success")

    return PubErrCode.ApplyDeal.Success,"Success"
end

--DB服返回 俱乐部申请处理 返回
function MsgClient.OnDBClubApplyHandleRsp(sReturnKey, Data, nLen)
    local strProto = "ClubApplyHandleRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubApplyHandleRsp nRlt_%d,sExData_%s",tData.nRlt,tData.sExData)
    

    local tExData = Cjson.decode(tData.sExData)

    local ClubSApplyHandleResp = {}
    ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.Success
    ClubSApplyHandleResp.sErrStr = ""
    ClubSApplyHandleResp.nId = tExData.nId
    ClubSApplyHandleResp.nType = tExData.nType
    ClubSApplyHandleResp.nClubId = tExData.nClubId
    ClubSApplyHandleResp.nOpType = tExData.nOpType

    if tData.nRlt==0 then
        local tClubInfo = {nClubId=tExData.nClubId,sClubName=tExData.sClubName,nMaster=tExData.nMaster}
        local tUserInfo = {nUserId=tExData.nOpUserId,sUserName=tExData.sUserName,sFaceId=tExData.sFaceId}
        local tApply = tExData.tApply
        local tNoticesItem = tExData.tNoticesItem

        local tNoticesInfo = {}
        tNoticesInfo.tClubInfo = tClubInfo
        tNoticesInfo.tUserInfo = tUserInfo
        tNoticesInfo.tApply = tApply
        tNoticesInfo.tNoticesItem = tNoticesItem

        local tChangeInfo = {}
        if tExData.nType==1 then
            --增加俱乐部币申请  
            Base.Log("_OnDBClubApplyHandleRsp nApplyAddGoldCnt_%d",tExData.nApplyCnt)
            tChangeInfo.nApplyAddGoldCnt = tExData.nApplyCnt

            --通知玩家增加俱乐部币申请结果
            Base.Log("_OnDBClubApplyHandleRsp 通知玩家增加俱乐部币申请结果 nTUserId_%d nClubId_%d",tExData.nTUserId,tExData.nClubId)
            local arrRedot = {{nType=3,nCount=tExData.nUnReadCnt}}
            tNoticesInfo.arrRedot = arrRedot
            MsgApi.SendUserMessage(tExData.nTUserId,4,tNoticesInfo)
        elseif tExData.nType==2 then
            --退还俱乐部币申请
            Base.Log("_OnDBClubApplyHandleRsp nApplyCutGoldCnt_%d",tExData.nApplyCnt)
            tChangeInfo.nApplyCutGoldCnt = tExData.nApplyCnt

            --通知玩家退还俱乐部币申请结果
            Base.Log("_OnDBClubApplyHandleRsp 通知玩家退还俱乐部币申请结果 nTUserId_%d nClubId_%d",tExData.nTUserId,tExData.nClubId)
            local arrRedot = {{nType=3,nCount=tExData.nUnReadCnt}}
            tNoticesInfo.arrRedot = arrRedot
            MsgApi.SendUserMessage(tExData.nTUserId,5,tNoticesInfo)
        elseif tExData.nType==3 then
            --加入俱乐部申请
            Base.Log("_OnDBClubApplyHandleRsp nApplyJionCnt_%d",tExData.nApplyCnt)
            tChangeInfo.nApplyJionCnt = tExData.nApplyCnt
            if tExData.nOpType==1 then
                Base.Log("_OnDBClubApplyHandleRsp 同意加入申请")
                --(俱乐部的人数)
                tChangeInfo.nUserCnt = tExData.nUserCnt
                Base.Log("_OnDBClubApplyHandleRsp nUserCnt_%d",tExData.nUserCnt)
            elseif tData.nOpType==2 then
                Base.Log("_OnDBClubApplyHandleRsp 拒绝加入申请")
            end

            --通知玩家俱乐部加入申请结果
            Base.Log("_OnDBClubApplyHandleRsp 通知玩家俱乐部加入申请结果 nTUserId_%d nClubId_%d",tExData.nTUserId,tExData.nClubId)
            local arrRedot = {{nType=1,nCount=tExData.nUserApplyCnt}}
            tNoticesInfo.arrRedot = arrRedot
            MsgApi.SendUserMessage(tExData.nTUserId,1,tNoticesInfo)
        end
        --发送俱乐部场景信息改变
        MsgApi.SendClubInfoChange(tExData.nClubId,tChangeInfo)
    elseif tData.nRlt==1 then
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.NoApply
        ClubSApplyHandleResp.sErrStr = "No Apply"
        Base.Log("_OnDBClubApplyHandleRsp No Apply")
    elseif tData.nRlt==2 then
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.IsDeal
        ClubSApplyHandleResp.sErrStr = "Apply is Deal"
        Base.Log("_OnDBClubApplyHandleRsp Apply is Deal")
    elseif tData.nRlt==3 then
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.NoClub
        ClubSApplyHandleResp.sErrStr = "club is not find"
        Base.Log("_OnDBClubApplyHandleRsp club is not find")
    elseif tData.nRlt==4 then
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.ClubIsFull
        ClubSApplyHandleResp.sErrStr = "Club member is full"
        Base.Log("_OnDBClubApplyHandleRsp 俱乐部已满人")
    else
        ClubSApplyHandleResp.nRlt = PubErrCode.ApplyDeal.DBERR
        ClubSApplyHandleResp.sErrStr = "DB Err"
        Base.Log("_OnDBClubApplyHandleRsp DB Err")
    end

    --删除申请处理锁
    PublicRedis.DelApplyDealLock(tExData.nClubId,tExData.nId,tExData.nType)

    MsgApi.SendToUser(tExData.nOpUserId,"ClubSApplyHandleResp",ClubSApplyHandleResp)
    SlaveData.tDBOprateWaitting.arrApplyDeal[tExData.nOpUserId] = nil
end

--邀请用户请求
function MsgClient.OnClubSInviteUserReq(sClientID, Data, nLen)
    local strProto = "ClubSInviteUserReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSInviteUserReq 邀请用户请求 nClubId:%d nUserId:%d myself:%d",tData.nClubId,tData.nUserId,nUserId)

    local ClubSInviteUserResp = {}
    ClubSInviteUserResp.nRlt = 0
    ClubSInviteUserResp.sErrStr = ""
    ClubSInviteUserResp.nClubId = tData.nClubId
    ClubSInviteUserResp.nUserId = tData.nUserId

    --不是私人俱乐部,是大厅
    if tData.nClubId<Define.nMinClubId then
        Base.Log("_OnClubSInviteUserReq 不是私人俱乐部,是大厅")
        ClubSInviteUserResp.nRlt = PubErrCode.InviteUser.IsHall
        ClubSInviteUserResp.sErrStr = "club is hall"
        MsgApi.SendToClient(sClientID,"ClubSInviteUserResp",ClubSInviteUserResp)
        return
    end

    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSInviteUserReq club is not find")
        ClubSInviteUserResp.nRlt = PubErrCode.InviteUser.NoClub
        ClubSInviteUserResp.sErrStr = "club is not find"
        MsgApi.SendToClient(sClientID,"ClubSInviteUserResp",ClubSInviteUserResp)
        return
    end

    --操作玩家是否是俱乐部成员
    local tAdmin = PublicRedis.GetClubUserInfo(tData.nClubId,nUserId)
    if not tAdmin then
        Base.Log("_OnClubSInviteUserReq you is not member of club")
        ClubSInviteUserResp.nRlt = PubErrCode.InviteUser.NoClubUser
        ClubSInviteUserResp.sErrStr = "you is not member of club"
        MsgApi.SendToClient(sClientID,"ClubSInviteUserResp",ClubSInviteUserResp)
        return
    end
    --操作玩家是否是管理员或者主席
    if tAdmin.nIdentify~=Define.nMaster and tAdmin.nIdentify~=Define.nAdmin then
        Base.Log("_OnClubSInviteUserReq no power")
        ClubSInviteUserResp.nRlt = PubErrCode.InviteUser.NoPower
        ClubSInviteUserResp.sErrStr = "no power"
        MsgApi.SendToClient(sClientID,"ClubSInviteUserResp",ClubSInviteUserResp)
        return
    end

    --管理员权限
    local isSuccee,arrPower = pcall(Cjson.decode,tAdmin.sPower)
    if not isSuccee then
        tClub:Print("_OnClubSInviteUserReq decode tAdmin:%d sPower fail, sPower:%s",nUserId,tostring(tAdmin.sPower))
        arrPower = {}
    end

    --权限校验
    local hasPower = false
    for _,v in pairs(arrPower) do
        if v.nPowerType==Define.tPower.Member and v.isOpen==true then--俱乐部成员管理权限
            hasPower = true
            break
        end
    end
    if not hasPower then --没有操作权限
        Base.Log("_OnClubSInviteUserReq no power")
        ClubSInviteUserResp.nRlt = PubErrCode.InviteUser.NoPower
        ClubSInviteUserResp.sErrStr = "no power"
        MsgApi.SendToClient(sClientID,"ClubSInviteUserResp",ClubSInviteUserResp)
        return
    end
    
    local ClubInviteUserReq = {}
    ClubInviteUserReq.nClubId = tData.nClubId
    ClubInviteUserReq.nUserId = tData.nUserId
    ClubInviteUserReq.nSendUserId = nUserId
    MsgApi.SendToDBServer("ClubInviteUserReq",ClubInviteUserReq,tData.nUserId)
end

--DB服返回 邀请用户 返回
function MsgClient.OnDBClubInviteUserRsp(sReturnKey, Data, nLen)
    local strProto = "ClubInviteUserRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end
 
    Base.Log("_OnDBClubInviteUserRsp nClubId_%d,nRlt_%d,nUserId_%d,nSendUserId_%d,sExtData_%s",
        tData.nClubId,tData.nRlt,tData.nUserId,tData.nSendUserId,tData.sExtData)

    local sErrStr = ""
    local nRlt = tData.nRlt
    if tData.nRlt == 0 then
        nRlt = PubErrCode.InviteUser.Success
        sErrStr = "success"

        --给被邀请玩家发送通知邮件
        local tExtData = Cjson.decode(tData.sExtData)
        local tNoticesItem = {}
        tNoticesItem.nId = tExtData.nId
        tNoticesItem.nType = tExtData.nType
        tNoticesItem.nStatus = tExtData.nStatus
        tNoticesItem.sTime = tExtData.sTime
        tNoticesItem.sData = tExtData.sData
        local arrRedot = {}
        table.insert(arrRedot,{nType=2,nCount=tExtData.nInvationCnt})
        MsgApi.SendUserMessage(tData.nUserId,2,{tNoticesItem=tNoticesItem,arrRedot=arrRedot})
    elseif tData.nRlt == 3 then
        nRlt = PubErrCode.InviteUser.NoUser
        sErrStr = "not find user"
        Base.Log("_OnDBClubInviteUserRsp 没找到被邀请玩家")
    elseif tData.nRlt == 4 then
        nRlt = PubErrCode.InviteUser.HadInvite
        sErrStr = "had Invite"
        Base.Log("_OnDBClubInviteUserRsp 已邀请")
    elseif tData.nRlt == 5 then
        nRlt = PubErrCode.InviteUser.IsInClub
        sErrStr = "user is club member"
        Base.Log("_OnDBClubInviteUserRsp 被邀请玩家已在俱乐部中")
    elseif tData.nRlt == 6 then
        nRlt = PubErrCode.InviteUser.NoClub
        sErrStr = "no club"
        Base.Log("_OnDBClubInviteUserRsp 没找到俱乐部")
    end

    --给邀请者返回
    local ClubSInvieteResp = {}
    ClubSInvieteResp.nRlt = tData.nRlt
    ClubSInvieteResp.sErrStr = sErrStr
    ClubSInvieteResp.nClubId = tData.nClubId
    ClubSInvieteResp.nUserId = tData.nUserId
    MsgApi.SendToUser(tData.nSendUserId,"ClubSInviteUserResp",ClubSInvieteResp)
end

--搜索用户请求
function MsgClient.OnClubSSearchUserReq(sClientID, Data, nLen)
    local strProto = "ClubSSearchUserReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSSearchUserReq 搜索用户请求 nUserId_%d,str_%s,nClubId_%d",nUserId,tData.str,tData.nClubId)

    if tData.str=="" then
        Base.Log("_OnClubSSearchUserReq str is empty")
        MsgApi.SendToClient(sClientID,"ClubSSearchUserResp",{arrUser={},nPage=0,nAllPage=0})
        return
    end

    local isSuccee,sErr = pcall(BaseSink.decode,tData.str)
    if not isSuccee then
        Base.Log("_OnClubSSearchUserReq str is not Base64Encode")
        if type(sErr) == "string" then 
            Logger:error(sErr)
        else 
            Base.LogT(sErr) 
        end
        MsgApi.SendToClient(sClientID,"ClubSSearchUserResp",{arrUser={},nPage=0,nAllPage=0})
        return
    end

    local ClubSearchUserReq = {}
    ClubSearchUserReq.str = tData.str
    ClubSearchUserReq.nUserId = nUserId
    ClubSearchUserReq.nClubId = tData.nClubId
    MsgApi.SendToDBServer("ClubSearchUserReq",ClubSearchUserReq,nUserId)
end

--DB服返回 搜索用户 返回
function MsgClient.OnDBClubSearchUserRsp(sReturnKey, Data, nLen)
    local strProto = "ClubSearchUserRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrUser = {}
    for k,v in pairs(tData.arrUser) do
        if v.nUserId and v.nUserId>0 then
            local tItem = {}
            tItem.nUserId = v.nUserId
            tItem.sFaceId = v.sFaceId
            tItem.sName = v.sName
            tItem.nSex = v.nSex
            tItem.nStatus = v.nStatus
            tItem.sTime = v.sTime
            table.insert(arrUser,tItem)
        end
    end

    Base.Log("_OnDBClubSearchUserRsp nUserId_%d #arrUser_%d nPage_%d nAllPage_%d",
        tData.nUserId,#arrUser,tData.nPage,tData.nAllPage)

    local ClubSSearchUserResp = {}
    ClubSSearchUserResp.arrUser = arrUser
    ClubSSearchUserResp.nPage = tData.nPage
    ClubSSearchUserResp.nAllPage = tData.nAllPage
    MsgApi.SendToUser(tData.nUserId,"ClubSSearchUserResp",ClubSSearchUserResp)
end

--获取后台配置请求
function MsgClient.OnClubSGetGameParamsReq(sClientID, Data, nLen)
    local strProto = "ClubSGetGameParamsReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSGetGameParamsReq 玩家信息不存在")
        return
    end
    local nGroupId = tonumber(tUser.nGroupId) or -1

    Base.Log("_OnClubSGetGameParamsReq 获取后台配置请求 nGameId_%d,nUserId_%d,nGroupId_%d",tData.nGameId,nUserId,nGroupId)

    local tGameConfig = {nGameId=tData.nGameId}

    if PublicApi.IsTexasClassGame(tData.nGameId)  then --德州,短牌,奥马哈
        local tBackstageConfig = RedisCahche.GetClubTexasConfig(nGroupId,2,tData.nGameId)   --后台配置
        if tBackstageConfig then
            tGameConfig.arrCapacityOption =tBackstageConfig.arrCapacityOption    --可选人数设置
            tGameConfig.arrConfigOption =tBackstageConfig.arrClubAnteOption      --可选大小盲、默认带入，前注选项 {{小盲，大盲，默认带入，{前注1,前注2,...}},....}
            tGameConfig.arrKeepTimeOption=tBackstageConfig.arrKeepTimeOption     --可选房间时长
            tGameConfig.arrTakeinOption = tBackstageConfig.arrTakeinOption       --可选带入筹码倍数选项
            tGameConfig.arrPoolEntryRateOption = tBackstageConfig.arrPoolEntryRateOption     --可选入池率选项
            tGameConfig.arrDWLimitOption = tBackstageConfig.arrDWLimitOption     --可选抽水封顶选项
            tGameConfig.nVideoFee = tBackstageConfig.nVideoFee
            tGameConfig.tLeaveTableConfig = tBackstageConfig.tLeaveTableConfig
        end
    end

    local ClubSGetGameParamsResp = {}
    ClubSGetGameParamsResp.sGameConfig = Cjson.encode(tGameConfig)
    ClubSGetGameParamsResp.nGameId = tData.nGameId
    MsgApi.SendToClient(sClientID,"ClubSGetGameParamsResp",ClubSGetGameParamsResp)
end



--俱乐部开桌请求
function MsgClient.OnClubSOpenTableReq(sClientID, Data, nLen)
    local strProto = "ClubSOpenTableReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("_OnClubSOpenTableReq 俱乐部开桌请求 nClubId_%d,nGameId_%d,sConfig_%s",tData.nClubId,tData.nGameId,tData.sConfig)
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSOpenTableReq 玩家信息不存在")
        return
    end
    local nGroupId = tonumber(tUser.nGroupId) or -1
    local ClubSOpenTableResp = {nRlt=PubErrCode.OpenTable.Success}

    local isSuccee,tConfig = pcall(Cjson.decode,tData.sConfig)
    if not isSuccee then
        Base.Log("_OnClubSOpenTableReq decode sConfig fail")
        ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.ParamsErr
        MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
        return
    end

    --大厅
    if tData.nClubId == 0 then
        tData.nClubId = nGroupId
        Base.Log("_OnClubSOpenTableReq 大厅 nClubId:%d",tData.nClubId)
    end
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSOpenTableReq 俱乐部不存在")
        ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.NoClub
        MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
        return
    end

    --检查公共开桌参数
    local nRlt = PubClubApi.CheckOpenTable(tClub,tConfig)
    if nRlt ~= PubErrCode.OpenTable.Success then
        ClubSOpenTableResp.nRlt = nRlt
        MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
        return
    end

    local nItemId = 1
    if tConfig.nGoldType == 2 then
        --使用俱乐部币
        nItemId = tData.nClubId
    elseif tConfig.nGoldType == 3 then
        --使用积分
        nItemId = 0
    end

    local tRoomConfig = {
        nClubId = tData.nClubId, --俱乐部id
        nItemId = nItemId, --使用的货币id 0:积分 1:金币 1000000~:俱乐部币
        nKeepTime = tonumber(tConfig.nKeepTime) or 1800, --房间时长
        nGoldType = tConfig.nGoldType, --使用的金币类型 1:金币 2:俱乐部币 3:积分
        -- isNeedAndroid = PubClubApi.IsUseAndroid(tClub, tConfig.nGoldType), --是否加载机器人
        isNeedAndroid = tConfig.isNeedAndroid or false, --是否加载机器人
        sClubName = tClub.sClubName, --俱乐部名称
        nGameId = tData.nGameId, --游戏id
    }

    if PublicApi.IsTexasClassGame(tData.nGameId)  then --德州,短牌,奥马哈
        --参数校验
        local nRlt1 = PubClubApi.CheckTexasPubOpenTable(tConfig)
        Base.Log("_OnClubSOpenTableReq CheckTexasPubOpenTable %d", nRlt1)
        if nRlt1 ~= PubErrCode.OpenTable.Success then
            ClubSOpenTableResp.nRlt = nRlt1
            MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
            return
        end

        --短牌
        if tData.nGameId == Define.GameList.nTexasShortCard.nGameId then
            local nRlt = PubClubApi.CheckTexasShortCardOpenTable(tConfig)
            if nRlt ~= PubErrCode.OpenTable.Success then
                ClubSOpenTableResp.nRlt = nRlt
                MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
                return
            end
            tRoomConfig.isDPreAnte = tConfig.isDPreAnte --庄家是否要下两倍前注 true:开启 false:关闭
        elseif tData.nGameId == Define.GameList.nTexas.nGameId or tData.nGameId == Define.GameList.nTexasOmaha.nGameId then
            --德州，奥马哈
            local nRlt = PubClubApi.CheckTexasOpenTable(tConfig)
            if nRlt ~= PubErrCode.OpenTable.Success then
                ClubSOpenTableResp.nRlt = nRlt
                MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
                return
            end
        end

        tRoomConfig.nSmallBlind = tConfig.nSmallBlind --小盲
        tRoomConfig.nBigBlind = tConfig.nBigBlind--大盲
        tRoomConfig.nTakeIn = tConfig.nTakeIn--默认带入
        tRoomConfig.nTakeInMin = tConfig.nTakeIn--最低带入
        tRoomConfig.nTakeInMax = tConfig.nTakeIn--最高带入
        tRoomConfig.nCapacity = tConfig.nCapacity--人数
        tRoomConfig.nPreAnte = tConfig.nPreAnte--前注
        tRoomConfig.tAutostart = tConfig.tAutostart--自动开始设置
        tRoomConfig.nMinTabkeInBB = tConfig.nMinTabkeInBB--带入筹码倍数最小值
        tRoomConfig.nMaxTabkeInBB = tConfig.nMaxTabkeInBB--带入筹码倍数最大值
        tRoomConfig.nPoolEntryRate = tConfig.nPoolEntryRate--入池率
        tRoomConfig.isOnlyPlayByIOS = tConfig.isOnlyPlayByIOS--true:只能IOS设备玩 fasle:所有设备都能玩
        tRoomConfig.isForceBlind = tConfig.isForceBlind--强制盲注 true:开启 false:关闭
        tRoomConfig.isGPSLimit = tConfig.isGPSLimit--GPS限制
        tRoomConfig.isIPLimit = tConfig.isIPLimit--IP限制
        tRoomConfig.isAOF = tConfig.isAOF--全下或弃牌
        tRoomConfig.isDelayLook = tConfig.isDelayLook--延迟看牌
        tRoomConfig.nInsureMode = tConfig.nInsureMode--保险模式 0:无保险 1:传统保险 2:低水保险
        tRoomConfig.tDrawWaterMode = tConfig.tDrawWaterMode--抽水模式
        tRoomConfig.isTabkeOut = tConfig.isTabkeOut--是否开启带出筹码功能
        tRoomConfig.nZhuaTou = tConfig.nZhuaTou
        if tRoomConfig.isForceBlind then
            tRoomConfig.nZhuaTou = tRoomConfig.nZhuaTou or tRoomConfig.nBigBlind*2
        end
        tRoomConfig.preAnteOdd = tConfig.preAnteOdd --庄家n倍数前注
        tRoomConfig.nLoseMaxAmount = tConfig.nLoseMaxAmount --输钱限制
        tRoomConfig.nTabkeOutOdd = tConfig.nTabkeOutOdd--撤码阈值的倍数N
        tRoomConfig.nTableCost = tConfig.nTableCost   --牌桌消耗
        tRoomConfig.nPoolEntryRateHands = tConfig.nPoolEntryRateHands        --入池率多少手不限制
        tRoomConfig.nPoolHands = tConfig.nPoolHands                          --手数限制
        tRoomConfig.nIsPerson = tConfig.nIsPerson                            --是否私人房间
        tRoomConfig.nIsShow = tConfig.nIsShow                                --是否显示房间
        tRoomConfig.sPassWord = tConfig.sPassWord                            --私人房间密码
        tRoomConfig.isVideoFee = tConfig.isVideoFee
        tRoomConfig.nVideoFee = tConfig.nVideoFee                            --语聊收费价格
        tRoomConfig.nTakeInLimit = tConfig.nTakeInLimit                      --补码上限值
        -- if tConfig.preAnteOdd ~= nil then
        --     --有设置PreAntOdd，计算补码: 补码 = 补码* 最大买入BB * 庄家N倍前注
        --     tRoomConfig.nTakeInLimit = tConfig.nTakeInLimit * tConfig.nMaxTabkeInBB * tConfig.preAnteOdd
        -- else
        --     -- 没有设置PreAntOdd，计算补码: 补码 = 补码* 最大买入BB * 大盲
        --     tRoomConfig.nTakeInLimit = tConfig.nTakeInLimit * tConfig.nMaxTabkeInBB * tConfig.nBigBlind
        -- end
        if tConfig.tLeaveTableConfig ~= nil and tConfig.tLeaveTableConfig.isOpen then
            tRoomConfig.tLeaveTableConfig = {
                isOpen = tConfig.tLeaveTableConfig.isOpen,
                nWinThreshold = tConfig.tLeaveTableConfig.nWinThreshold, -- 赢钱阈值, 超过阈值时会触发离桌限制
                nLots = tConfig.tLeaveTableConfig.nLots, -- 离桌限制局数, 当赢钱达到阈值时, 需要超过限制手数才不会触发离桌限制
                nPenaltyRatio = tConfig.tLeaveTableConfig.nPenaltyRatio, -- 罚款比例, 只罚赢钱部分
                nUserRatio = tConfig.tLeaveTableConfig.nUserRatio, -- 同桌玩家分配比例, 罚款金额中的占比,平均分配给牌桌上的人
                nType = tConfig.tLeaveTableConfig.nType  -- 罚款触发模式 0: 返回大厅罚款 1: 站起罚款
            }
        end
    elseif tData.nGameId == Define.GameList.nClubQiangZhuangNiu then
        --参数校验
        local nRlt = PubClubApi.CheckQZNiuOpenTable(tConfig)
        if nRlt ~= PubErrCode.OpenTable.Success then
            ClubSOpenTableResp.nRlt = nRlt
            MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
            return
        end

        tRoomConfig.nCapacity = tConfig.nCapacity--人数
        tRoomConfig.tAutostart = tConfig.tAutostart--自动开始设置
        tRoomConfig.nBaseScore = tConfig.nBaseScore--底分
        tRoomConfig.HuType = tConfig.HuType--牌型倍率
        tRoomConfig.nTax = tConfig.nTax--抽水
    end

    --校验权限
    if tData.nClubId >= Define.nMinClubId then
        --操作玩家是否是俱乐部成员
        local tAdmin = PublicRedis.GetClubUserInfo(tData.nClubId,nUserId)
        if not tAdmin then
            tClub:Print("_OnClubSOpenTableReq 玩家不是俱乐部成员")
            ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.NotAdmin
            MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
            return
        end
        --操作玩家是否是管理员或者主席
        if tAdmin.nIdentify ~= Define.nMaster and tAdmin.nIdentify ~= Define.nAdmin then
            tClub:Print("_OnClubSOpenTableReq 玩家是不是管理员或者主席, nUserId:%d nIdentify:%d",nUserId,tAdmin.nIdentify)
            ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.NotAdmin
            MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
            return
        end

        --管理员权限
        -- local isSuccee,arrPower = pcall(Cjson.decode,tAdmin.sPower)
        -- if not isSuccee then
        --     tClub:Print("_OnClubSOpenTableReq decode tAdmin:%d sPower fail, sPower:%s",nUserId,tostring(tAdmin.sPower))
        --     arrPower = {}
        -- end

        --检查是否有管理权限
        local hasPower = MsgClient._CheckPower(tAdmin.sPower,Define.tPower.OpenTable)
        if not hasPower then
            tClub:Print("_OnClubSOpenTableReq 没有权限,sPower_%s",tAdmin.sPower)
            ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.NoPower
            MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
            return
        end
    else
        --操作玩家是否是俱乐部成员
        local tAdmin = PublicRedis.GetClubUserInfo(tData.nClubId,nUserId)
        if not tAdmin then
            tClub:Print("_OnClubSOpenTableReq 11 玩家不是俱乐部成员")
            ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.NotAdmin
            MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
            return
        end
        --管理员权限
        -- local isSuccee,arrPower = pcall(Cjson.decode,tAdmin.sPower)
        -- if not isSuccee then
        --     tClub:Print("_OnClubSOpenTableReq 11 decode tAdmin:%d sPower fail, sPower:%s",nUserId,tostring(tAdmin.sPower))
        --     arrPower = {}
        -- end

        --检查是否有管理权限
        local hasPower = MsgClient._CheckPower(tAdmin.sPower,Define.tPower.OpenTable)
        if not hasPower then
            tClub:Print("_OnClubSOpenTableReq 11 没有权限,sPower_%s",tAdmin.sPower)
            ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.NoPower
            MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
            return
        end
        --检查玩家在大厅有没有开桌权限
        -- local hasPower = tClub:HasPower(nUserId, Define.tPower.OpenTable)
        -- if not hasPower then
        --     tClub:Print("_OnClubSOpenTableReq 玩家在大厅有没有开桌权限")
        --     ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.NoPower
        --     MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
        --     return
        -- end
    end

    --检查个人开桌数目
    local nPersonTableCnt = tClub:GerPerSonTableCnt(nUserId)
    local nMaxPersonTableCnt = PubClubApi.GetUserOpenMaxCnt(nGroupId, tData.nClubId)
    if nPersonTableCnt >= nMaxPersonTableCnt then
        tClub:Print("_OnClubSOpenTableReq 开桌数目达到上限")
        ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.LimtMax
        MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
        return
    end

    --检查上一次开桌是否处理完了
    if MsgOnTime.HasWaitingMsg({nClubId=tData.nClubId,nUserId=nUserId,MsgType=Define.MsgType.OpenTable}) then
        tClub:Print("_OnClubSOpenTableReq 上一次的开桌还没处理完")
        ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.isOpening
        MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
        return
    end

    local tOpenTableConsume = SlaveData.arrOpenTableConsume[nGroupId] or Define.tOpenTableConsume
    local nConsumeItemId = nil
    local nConsume = nil
    tClub:Print("_OnClubSOpenTableReq 玩家开桌金币消耗 nGoldType:%d nCount:%d",tOpenTableConsume.nGoldType,tOpenTableConsume.nCount)
    if tOpenTableConsume.nGoldType and tOpenTableConsume.nCount>0 then
        nConsumeItemId = 1
        nConsume = tOpenTableConsume.nCount
        if tOpenTableConsume.nGoldType==2 then
            nConsumeItemId = tData.nClubId
        end
        if not PublicUserInfo.Gold_Lock(nUserId, PublicApi.Floor_2(nConsume),nConsumeItemId) then
            tClub:Print("_OnClubSOpenTableReq 玩家开桌金币加锁失败")
            ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.GoldLess
            MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
            return
        end
    end

    Define.nOpenCloseTableCnt = Define.nOpenCloseTableCnt + 1
    local sRequestkey = string.format("ClubSlave%dOpenTable%d",ServerInfo.nServerId,Define.nOpenCloseTableCnt)

    -- 处理自动开房相关逻辑
    if tConfig.tAutomaticOpenTable ~= nil and tConfig.tAutomaticOpenTable.automatic then
        tRoomConfig.sServerKey = Base.m_tKey          -- 俱乐部中心服 key 关桌需要用
        tRoomConfig.isAutomatic = tConfig.isAutomatic or false -- 牌桌结束自动开桌
        if not tRoomConfig.isAutomatic then   -- 类型互斥, 如果开启了牌桌结束自动开桌, 则游戏开始的自动开桌不生效
            tRoomConfig.automatic = tConfig.automatic or false     -- 自动开桌
            tRoomConfig.automaticType = tConfig.nAutomaticType     -- 自动开桌类型 -- 0:按比例开桌; 1:总是自动开桌, 不限制人数
            tRoomConfig.automaticRatio = tConfig.sAutomaticRatio    -- 自动开桌类型为0时生效, 当前只支持1/3 1/2 2/3 1/1 4种类型
            tRoomConfig.automaticCount = CalculateNumOfOpenTable({nAutomaticType = tConfig.nAutomaticType, automaticRatio = tConfig.sAutomaticRatio, nCapacity = tConfig.nCapacity})
        end
    end

    local tSendData = {}
    tSendData.nType = 1
    tSendData.nRoomId = 2
    tSendData.nLiveUserID = nUserId
    tSendData.nOpentime = os.time()
    tSendData.sRequestkey = sRequestkey
    tSendData.nGroupId = nGroupId
    --tSendData.sTableName = tConfig.sTableName
    tSendData.nTableType = 5
    tSendData.sConfig = Cjson.encode(tRoomConfig)

    -- 房间编号唯一
    local timestampSuffix = tostring(os.time() % 1000000)  -- 获取当前时间秒数的后4位
    local randomSuffix = string.format("%04d", math.random(0, 999999))
    local uniqueSuffix = string.sub(timestampSuffix .. randomSuffix, 1, 6)  -- 取前4位
    local decodedTableName = BaseSink.decode(tConfig.sTableName)
    tSendData.sTableName = BaseSink.encode(decodedTableName .. '-'.. uniqueSuffix)


    tClub:Print("_OnClubSOpenTableReq 开桌参数 %s",Cjson.encode(tSendData))

    if tConfig.tAutomaticOpenTable ~= nil and tConfig.tAutomaticOpenTable.automatic then
        -- 保存持久化配置, 后续删除模板以及开房时都需要使用
        local tCfg = {}
        tCfg.nServerId = ServerInfo.nServerId
        tCfg.nSourceType = 1                              -- 取值为0或者空时, 则为后端创建的房间, 取值为1时, 则为前端创建的房间,方便后续根据配置类型查询时分辨
        tCfg.nOpenTableCfgId =tostring(os.time())	                         -- 开桌配置id
        tCfg.isConfigSwitch = true           -- 配置开关: true、false 
        tCfg.isAutomatic = tRoomConfig.isAutomatic or false -- 牌桌结束自动开桌
        tCfg.automatic = tRoomConfig.automatic or false          -- 是否开始游戏是自动开桌,取tRoomConfig中的取值,避免重复判断
        tCfg.automaticType = tConfig.nAutomaticType         --#自动开桌类型: 0:按比例开桌; 1:总是自动开桌, 不限制人数
        tCfg.automaticCount = tRoomConfig.automaticCount
        tCfg.automaticRatio = tConfig.automaticRatio or ""    -- 不参与业务,只是后台配置界面展示时使用
        tCfg.nClubId = tData.nClubId
        tCfg.tSendData = tSendData
        tCfg.tRoomConfig = tRoomConfig
        tCfg.templateConfig = tConfig                       -- 方便后续前端展示字段开桌列表配置返回, 直接返回templateConfig即可

        PublicRedis._HandleClubTableCongfig(1, tData.nGroupId, tData.nClubId, tData.nGameId, tCfg.nOpenTableCfgId, tCfg)
    end

    --插入消息队列
    local tMsgData = {}
    tMsgData.nClubId = tData.nClubId
    tMsgData.nUserId = nUserId
    tMsgData.nOpentime = os.time()
    tMsgData.MsgType = Define.MsgType.OpenTable
    tMsgData.nConsumeItemId = nConsumeItemId
    tMsgData.nConsume = nConsume
    MsgOnTime.Push(tMsgData)

    local isSendSucess = MsgApi.SendOpenTableToGame(tData.nGameId, tSendData)

    if not isSendSucess then
        tClub:Print("_OnClubSOpenTableReq not find Game Center server")
        ClubSOpenTableResp.nRlt = PubErrCode.OpenTable.NoServer
        MsgApi.SendToClient(sClientID,"ClubSOpenTableResp",ClubSOpenTableResp)
        MsgOnTime.DelWaitingMsg(tMsgData)
        return
    end

    -- 测试 批量牌桌
    -- for i = 1, 2, 1 do
    --     local sTableName = BaseSink.decode(tConfig.sTableName)
    --     sTableName =  sTableName..i 
    --     tClub:Print("_OnClubSOpenTableReq    sTableName:    "..sTableName)
    --     tSendData.sTableName =  BaseSink.encode(sTableName)
    --     local isSendSucess = MsgApi.SendOpenTableToGame(tData.nGameId,tSendData)        
    -- end
    
end

function CalculateNumOfOpenTable(input)
    -- 参数错误则返回牌桌容量+1, 使其不能触发开桌
    if input.nAutomaticType == 0 then  -- 按比例开桌
        if input.automaticRatio == "1/3" then
            return math.floor(input.nCapacity / 3.0)
        elseif input.automaticRatio == "1/2" then
            return math.floor(input.nCapacity / 2.0)
        elseif input.automaticRatio == "2/3" then
            return math.floor(input.nCapacity * 2.0 / 3.0)
        elseif input.automaticRatio == "1/1" then
            return input.nCapacity
        else
            return input.nCapacity + 1
        end
    elseif input.nAutomaticType == 1 then -- 总是自动开桌, 不限制人数
        return 0
    else
        return input.nCapacity + 1
    end 
end

 --俱乐部关桌请求
function MsgClient.OnClubSCloseTableReq(sClientID, Data, nLen)
    local strProto = "ClubSCloseTableReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSCloseTableReq 俱乐部关桌请求 nClubId:%d,nUserId:%d,sTableId:%s",tData.nClubId,nUserId,tData.sTableId)
    local ClubSCloseTableResp = {nRlt=PubErrCode.CloseTable.Success}
    if tData.nClubId == 0 then
        --大厅
        local tUser = UserManager.GetUserInfo(nUserId)
        if not tUser then
            Base.Log("_OnClubSCloseTableReq 玩家信息不存在")
            return
        end
        local nGroupId = tonumber(tUser.nGroupId) or -1
        tData.nClubId = nGroupId
        Base.Log("_OnClubSCloseTableReq 大厅 nClubId:%d",tData.nClubId)
    end

    --俱乐部不存在
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSCloseTableReq club is not find")
        ClubSCloseTableResp.nRlt = PubErrCode.CloseTable.NoClub
        MsgApi.SendToClient(sClientID,"ClubSCloseTableResp",ClubSCloseTableResp)
        return
    end
    --私人俱乐部校验权限
    if tData.nClubId >= Define.nMinClubId then
        --操作玩家是否是俱乐部成员
        local tAdmin = PublicRedis.GetClubUserInfo(tData.nClubId,nUserId)
        if not tAdmin then
            tClub:Print("_OnClubSCloseTableReq not find tAdmin in Club")
            ClubSCloseTableResp.nRlt = PubErrCode.CloseTable.NotAdmin
            MsgApi.SendToClient(sClientID,"ClubSCloseTableResp",ClubSCloseTableResp)
            return
        end
        --操作玩家是否是管理员或者主席
        if tAdmin.nIdentify ~= Define.nMaster and tAdmin.nIdentify ~= Define.nAdmin then
            tClub:Print("_OnClubSOpenTableReq you not admin, nUserId:%d nIdentify:%d",nUserId,tAdmin.nIdentify)
            ClubSCloseTableResp.nRlt = PubErrCode.CloseTable.NotAdmin
            MsgApi.SendToClient(sClientID,"ClubSCloseTableResp",ClubSCloseTableResp)
            return
        end
        --管理员权限
        local isSuccee,arrPower = pcall(Cjson.decode,tAdmin.sPower)
        if not isSuccee then
            tClub:Print("_OnClubSOpenTableReq decode tAdmin:%d sPower fail, sPower:%s",nUserId,tostring(tAdmin.sPower))
            arrPower = {}
        end
        --检查是否有管理权限
        local hasPower = MsgClient._CheckPower(arrPower, Define.tPower.OpenTable)
        if not hasPower then
            tClub:Print("_OnClubSOpenTableReq no power,sPower_%s",tAdmin.sPower)
            ClubSCloseTableResp.nRlt = PubErrCode.CloseTable.NoPower
            MsgApi.SendToClient(sClientID,"ClubSCloseTableResp",ClubSCloseTableResp)
            return
        end
    end
    --牌桌不存在
    local tTable = tClub:GetTableInfo(tData.sTableId)
    if not tTable then
        tClub:Print("_OnClubSCloseTableReq not find table")
        ClubSCloseTableResp.nRlt = PubErrCode.CloseTable.NoTable
        MsgApi.SendToClient(sClientID,"ClubSCloseTableResp",ClubSCloseTableResp)
        return
    end
    --大厅的牌桌只有本人才能关
    if tData.nClubId < Define.nMinClubId then
        if tTable.nLiveUserID ~= nUserId then
            tClub:Print("_OnClubSCloseTableReq you can not close other's table")
            ClubSCloseTableResp.nRlt = PubErrCode.CloseTable.NotYouTable
            MsgApi.SendToClient(sClientID,"ClubSCloseTableResp",ClubSCloseTableResp)
            return
        end
    end

    -- if MsgOnTime.HasWaitingMsg({nClubId=tData.nClubId,nUserId=nUserId,sTableId=tData.sTableId,MsgType=Define.MsgType.CloseTable}) then
    --     tClub:Print("_OnClubSCloseTableReq 上一次的关桌还没处理完")
    --     ClubSCloseTableResp.nRlt = PubErrCode.CloseTable.isCloseing
    --     MsgApi.SendToClient(sClientID,"ClubSCloseTableResp",ClubSCloseTableResp)
    --     return
    -- end

    Define.nOpenCloseTableCnt = Define.nOpenCloseTableCnt + 1
    local sRequestkey = string.format("ClubSlave%dCloseTable%d",ServerInfo.nServerId, Define.nOpenCloseTableCnt)

    local tSendData = {}
    tSendData.nType = 2
    tSendData.nRoomId = 2
    tSendData.nLiveUserID = 0
    tSendData.nOpentime = 0
    tSendData.sRequestkey = sRequestkey
    tSendData.sTableId = tData.sTableId

    --插入消息队列
    -- local tMsgData = {}
    -- tMsgData.nClubId = tData.nClubId
    -- tMsgData.nUserId = nUserId
    -- tMsgData.sTableId = tData.sTableId
    -- tMsgData.nOpentime = os.time()
    -- tMsgData.MsgType = Define.MsgType.CloseTable
    -- MsgOnTime.Push(tMsgData)

    local isSendSucess = MsgApi.SendCloseTableToGame(tSendData)

    if not isSendSucess then
        tClub:Print("_OnClubSCloseTableReq not find Game Center server")
        ClubSCloseTableResp.nRlt = PubErrCode.CloseTable.NoServer
        MsgApi.SendToClient(sClientID,"ClubSCloseTableResp",ClubSCloseTableResp)
        -- MsgOnTime.DelWaitingMsg(tMsgData)
        return
    end
end

--俱乐部牌桌列表请求
function MsgClient.OnClubSGetTableListReq(sClientID, Data, nLen)
    local strProto = "ClubSGetTableListReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        Base.Log("_OnClubSGetTableListReq  isCheckPass is false ")
        return
    end
    Base.Log("_OnClubSGetTableListReq 俱乐部牌桌列表请求 nClubId:%d,nUserId:%d,nCnt:%d,nTableIndex:%d nGameId: %d sScreen:%s  "
    ,tData.nClubId,nUserId,tData.nCnt,tData.nTableIndex,tData.nGameId or 0,tData.sScreen or "")

    if tData.nClubId == 0 then --大厅
        local tUser = UserManager.GetUserInfo(nUserId)
        if not tUser then
            Base.Log("_OnClubSGetTableListReq 玩家信息不存在")
            return
        end
        local nGroupId = tonumber(tUser.nGroupId) or -1
        tData.nClubId = nGroupId
        Base.Log("_OnClubSGetTableListReq 请求大厅牌桌列表 nClubId:%d",tData.nClubId)
    end
    --俱乐部不存在
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnClubSGetTableListReq 俱乐部不存在")
        return
    end

    local arrTableInfo, arrTableId = tClub:GetGameTableList(tData.nTableIndex, tData.nCnt, tData.nGameId, tData.sScreen, nUserId)
    tClub:SetUserGetTables(nUserId, arrTableId)

    tClub:Print("_OnClubSGetTableListReq #arrTableInfo:%d", #arrTableInfo)
    local arr = {}
    for k,v in pairs(arrTableInfo) do
        if v then
            --返回时清空入座列表避免超长
            local v1 = Cjson.decode(v)
            v1.nSittedList = {}
            local v2 = Cjson.encode(v1)
            table.insert(arr,v2)
            if #arr >= 5 or k == #arrTableInfo then
                local ClubSGetTableListResp = {}
                ClubSGetTableListResp.nClubId = tData.nClubId
                ClubSGetTableListResp.arrTableInfo = arr
                MsgApi.SendToClient(sClientID,"ClubSGetTableListResp",ClubSGetTableListResp)
                -- tClub:Print("_OnClubSGetTableListReq #arr:%d",#arr)
                arr = {}
            end
        end
    end
    if #arrTableInfo == 0 then 
        local ClubSGetTableListResp = {}
        ClubSGetTableListResp.nClubId = tData.nClubId
        ClubSGetTableListResp.arrTableInfo = arrTableInfo
        MsgApi.SendToClient(sClientID,"ClubSGetTableListResp",ClubSGetTableListResp)
    end
end

--牌谱请求
function MsgClient.OnClubSPaiPuReq(sClientID, Data, nLen)
    local strProto = "ClubSPaiPuReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSPaiPuReq 牌谱请求 nUserId_%d,nType_%d,nIdOfStart_%d,nCnt_%d,nGameId_%d",nUserId,tData.nType,tData.nIdOfStart,tData.nCnt,tData.nGameId)

    --参数校验
    if tData.nType~=1 and tData.nType~=2 then
        Base.Log("_OnClubSPaiPuReq 参数错误")
        MsgApi.SendToClient(sClientID,"ClubSPaiPuResp",{arrRecords={},nType=tData.nType,nAllCnt=0})
        return
    end
    local nIdOfStart = tData.nIdOfStart
    if nIdOfStart<0 then
        nIdOfStart = 0
    end
    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>10 then
        nCnt = 10
    end

    local ClubPaiPuReq = {}
    ClubPaiPuReq.nType = tData.nType
    ClubPaiPuReq.nIdOfStart = nIdOfStart
    ClubPaiPuReq.nCnt = nCnt
    ClubPaiPuReq.nUserId = nUserId
    ClubPaiPuReq.nSendUserId = nUserId
    ClubPaiPuReq.nGameId = tData.nGameId
    MsgApi.SendToDBServer("ClubPaiPuReq",ClubPaiPuReq,nUserId)
end

--DB服返回 牌谱返回 返回
function MsgClient.OnDBClubPaiPuResp(sReturnKey, Data, nLen)
    local strProto = "ClubPaiPuResp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrRecords = {}
    for k,v in pairs(tData.arrRecords) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.sPaiJuID = v.sPaiJuID
            tItem.nWinLose = v.nWinLose
            tItem.sTime = v.sTime
            tItem.nGameId = v.nGameId
            tItem.sTableInfo = v.sTableInfo
            tItem.sHandCards = v.sHandCards
            if v.sHandCards=="" or v.sHandCards=="{}" then
                Base.Log("sPaiJuID_%s,sHandCards_%s",v.sPaiJuID,v.sHandCards)
            end
            tItem.nCollect = v.nCollect
            table.insert(arrRecords,tItem)
        end
    end

    Base.Log("_OnDBClubPaiPuResp nUserId_%d nSendUserId_%d #arrRecords_%d nType_%d nAllCnt_%d",
        tData.nUserId,tData.nSendUserId,#arrRecords,tData.nType,tData.nAllCnt)

    local ClubSPaiPuResp = {}
    ClubSPaiPuResp.arrRecords = arrRecords
    ClubSPaiPuResp.nType = tData.nType
    ClubSPaiPuResp.nAllCnt = tData.nAllCnt
    ClubSPaiPuResp.nGameId = tData.nGameId
    MsgApi.SendToUser(tData.nSendUserId,"ClubSPaiPuResp",ClubSPaiPuResp)
end

--操作牌谱请求
function MsgClient.OnClubSOpratePaiPuReq(sClientID, Data, nLen)
    local strProto = "ClubSOpratePaiPuReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSOpratePaiPuReq 操作牌谱请求 nUserId_%d,nType_%d,sPaiJuID_%s",nUserId,tData.nType,tData.sPaiJuID)

    local ClubSOpratePaiPuResp = {
        nRlt = PubErrCode.PaiPuOprate.Success,
        sErrStr = "",
        nType=tData.nType,
        sPaiJuID = tData.sPaiJuID,
    }

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrPaiPuOprate[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSOpratePaiPuReq 请求过于频繁，等待上一个请求结束")
            ClubSOpratePaiPuResp.nRlt = PubErrCode.PaiPuOprate.WaitDBReturn
            ClubSOpratePaiPuResp.sErrStr = "too frequently,waitting last req return"
            MsgApi.SendToClient(sClientID,"ClubSOpratePaiPuResp",ClubSOpratePaiPuResp)
            return
        end
    end

    --参数校验
    if tData.nType~=1 and tData.nType~=2 then
        Base.Log("_OnClubSOpratePaiPuReq 参数错误 nType Err")
        ClubSOpratePaiPuResp.nRlt = PubErrCode.PaiPuOprate.ParamsErr
        ClubSOpratePaiPuResp.sErrStr = "nType Err"
        MsgApi.SendToClient(sClientID,"ClubSOpratePaiPuResp",ClubSOpratePaiPuResp)
        return
    end
    if tData.sPaiJuID=="" then
        Base.Log("_OnClubSOpratePaiPuReq 参数错误 sPaiJuID Err")
        ClubSOpratePaiPuResp.nRlt = PubErrCode.PaiPuOprate.ParamsErr
        ClubSOpratePaiPuResp.sErrStr = "sPaiJuID Err"
        MsgApi.SendToClient(sClientID,"ClubSOpratePaiPuResp",ClubSOpratePaiPuResp)
        return
    end
    
    SlaveData.tDBOprateWaitting.arrPaiPuOprate[nUserId] = os.time()

    local ClubOpratePaiPuReq = {}
    ClubOpratePaiPuReq.nType = tData.nType
    ClubOpratePaiPuReq.sPaiJuID = tData.sPaiJuID
    ClubOpratePaiPuReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubOpratePaiPuReq",ClubOpratePaiPuReq,nUserId)
end

--DB服返回 操作牌谱返回 返回
function MsgClient.OnDBClubOpratePaiPuResp(sReturnKey, Data, nLen)
    local strProto = "ClubOpratePaiPuResp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubOpratePaiPuResp nUserId_%d nRlt_%d nType_%d sPaiJuID_%s",
        tData.nUserId,tData.nRlt,tData.nType,tData.sPaiJuID)
    
    local nRlt = tData.nRlt
    local sErrStr = ""
    if tData.nRlt==0 then
        nRlt = PubErrCode.PaiPuOprate.Success
        sErrStr = "Success"
    elseif tData.nRlt==1 then 
        nRlt = PubErrCode.PaiPuOprate.NoPaiJu
        sErrStr = "PaiJu not find"
        Base.Log("牌局不存在")
    elseif tData.nRlt==3 then 
        nRlt = PubErrCode.PaiPuOprate.NotUserPaiju
        sErrStr = "not your PaiJu"
        Base.Log("不是该玩家的牌局")
    elseif tData.nRlt==4 then
        nRlt = PubErrCode.PaiPuOprate.HadCollect
        sErrStr = "already collect"
        Base.Log("已收藏")
    end

    local ClubSOpratePaiPuResp = {}
    ClubSOpratePaiPuResp.nRlt = nRlt
    ClubSOpratePaiPuResp.sErrStr = sErrStr
    ClubSOpratePaiPuResp.nType = tData.nType
    ClubSOpratePaiPuResp.sPaiJuID = tData.sPaiJuID
    MsgApi.SendToUser(tData.nUserId,"ClubSOpratePaiPuResp",ClubSOpratePaiPuResp)
    SlaveData.tDBOprateWaitting.arrPaiPuOprate[tData.nUserId] = nil
end

--个人通知请求
function MsgClient.OnClubSUserNoticeReq(sClientID, Data, nLen)
    local strProto = "ClubSUserNoticeReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSUserNoticeReq 个人通知请求 nUserId_%d,nIdOfStart_%d,nCnt_%d,nType_%d",nUserId,tData.nIdOfStart,tData.nCnt,tData.nType)

    local nIdOfStart = tData.nIdOfStart
    if nIdOfStart<0 then
        nIdOfStart = 0
    end
    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubUserNoticeReq = {}
    ClubUserNoticeReq.nIdOfStart = nIdOfStart
    ClubUserNoticeReq.nCnt = nCnt
    ClubUserNoticeReq.nUserId = nUserId
    ClubUserNoticeReq.nType = tData.nType
    MsgApi.SendToDBServer("ClubUserNoticeReq",ClubUserNoticeReq,nUserId)
end

--DB服返回 玩家个人通知 返回
function MsgClient.OnDBClubUserNoticeRsp(sReturnKey, Data, nLen)
    local strProto = "ClubUserNoticeRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrNotices = {}
    for k,v in pairs(tData.arrNotices) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.nType = v.nType
            tItem.nStatus = v.nStatus
            tItem.sTime = v.sTime
            tItem.sData = v.sData
            tItem.nHadRead = v.nHadRead
            table.insert(arrNotices,tItem)
        end
    end

    local arrApplyList = {}
    for k,v in pairs(tData.arrApplyList) do
        if v.nId and v.nId>0 then
            local tApplyInfo = {}
            tApplyInfo.nId = v.nId
            tApplyInfo.nClubId = v.nClubId
            tApplyInfo.nType = v.nType
            tApplyInfo.sTime = v.sTime
            tApplyInfo.sClubName = v.sClubName
            tApplyInfo.nStatus = v.nStatus
            table.insert(arrApplyList,tApplyInfo)
        end
    end

    Base.Log("_OnDBClubUserNoticeRsp nUserId_%d #arrNotices_%d nType_%d nAllCnt_%d #arrApplyList_%d nUnReadCnt_%d",
        tData.nUserId,#arrNotices,tData.nType,tData.nAllCnt,#arrApplyList,tData.nUnReadCnt or -1)

    local ClubSUserNoticeResp = {}
    ClubSUserNoticeResp.arrNotices = arrNotices
    ClubSUserNoticeResp.nAllCnt = tData.nAllCnt
    ClubSUserNoticeResp.nType = tData.nType
    ClubSUserNoticeResp.arrApplyList = arrApplyList
    ClubSUserNoticeResp.nUnReadCnt = tData.nUnReadCnt
    MsgApi.SendToUser(tData.nUserId,"ClubSUserNoticeResp",ClubSUserNoticeResp)
end

--处理个人通知请求
function MsgClient.OnClubSUserNoticeHandleReq(sClientID, Data, nLen)
    local strProto = "ClubSUserNoticeHandleReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSUserNoticeHandleReq 处理个人通知请求 nUserId_%d,nId_%d,nOpType_%d",nUserId,tData.nId,tData.nOpType)

    local ClubSUserNoticeHandleResp = {
        nRlt = PubErrCode.UserNoticeOprate.Success,
        sErrStr = "",
        nType=tData.nType,
        nId = tData.nId,
        nOpType = tData.nOpType,
    }

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrUserNoticeOprate[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSUserNoticeHandleReq 请求过于频繁，等待上一个请求结束")
            ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.WaitDBReturn
            ClubSUserNoticeHandleResp.sErrStr = "too frequently,waitting last req return"
            MsgApi.SendToClient(sClientID,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
            return
        end
    end

    --参数校验
    if tData.nOpType~=1 and tData.nOpType~=2 then
        Base.Log("_OnClubSOpratePaiPuReq 参数错误 nOpType Err")
        ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.ParamsErr
        ClubSUserNoticeHandleResp.sErrStr = "nOpType Err"
        MsgApi.SendToClient(sClientID,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
        return
    end

    
    SlaveData.tDBOprateWaitting.arrUserNoticeOprate[nUserId] = os.time()

    local tExtData = {}
    tExtData.nUserId = nUserId
    tExtData.nId = tData.nId
    tExtData.nOpType = tData.nOpType
    tExtData.nType = 2 --受邀请

    local ClubGetUserNoticeInfoReq = {}
    ClubGetUserNoticeInfoReq.nId = tData.nId
    ClubGetUserNoticeInfoReq.sExtData = Cjson.encode(tExtData)
    MsgApi.SendToDBServer("ClubGetUserNoticeInfoReq",ClubGetUserNoticeInfoReq,nUserId)
end

--DB服返回 获取某条个人通知信息 返回
function MsgClient.OnDBClubGetUserNoticeInfoRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetUserNoticeInfoRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubGetUserNoticeInfoRsp nId_%d sExtData_%s",tData.nId,tData.sExtData)

    local tExtData = Cjson.decode(tData.sExtData)

    local ClubSUserNoticeHandleResp = {
        nRlt = PubErrCode.UserNoticeOprate.Success,
        sErrStr = "",
        nType=tExtData.nType,
        nId = tExtData.nId,
        nOpType = tExtData.nOpType,
    }
    
    if not tData.tNoticesInfo or not tData.tNoticesInfo.nId or tData.tNoticesInfo.nId<=0 then
        Base.Log("_OnDBClubGetUserNoticeInfoRsp 玩家通知信息不存在")
        ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.NoNotice
        ClubSUserNoticeHandleResp.sErrStr = "not find notice"
        MsgApi.SendToUser(tExtData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
        SlaveData.tDBOprateWaitting.arrUserNoticeOprate[tExtData.nUserId] = nil
        return
    end

    local tNoticesInfo = {}
    tNoticesInfo.nId = tData.tNoticesInfo.nId
    tNoticesInfo.nType = tData.tNoticesInfo.nType
    tNoticesInfo.nStatus = tData.tNoticesInfo.nStatus
    tNoticesInfo.sTime = tData.tNoticesInfo.sTime
    tNoticesInfo.sData = tData.tNoticesInfo.sData
    tNoticesInfo.nUserId = tData.tNoticesInfo.nUserId

    tExtData.nType = tData.tNoticesInfo.nType

    Base.Log("_OnDBClubGetUserNoticeInfoRsp tNoticesInfo:%s",Cjson.encode(tNoticesInfo))

    if tNoticesInfo.nType ~=2 then
        Base.Log("_OnDBClubGetUserNoticeInfoRsp 系统或者俱乐部消息，无需处理")
        ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.NoNotice
        ClubSUserNoticeHandleResp.sErrStr = "not need handled"
        MsgApi.SendToUser(tExtData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
        SlaveData.tDBOprateWaitting.arrUserNoticeOprate[tExtData.nUserId] = nil
        return
    end

    if tNoticesInfo.nUserId~=tExtData.nUserId then
        Base.Log("_OnDBClubGetUserNoticeInfoRsp 不是你的通知消息")
        ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.NotUserNotice
        ClubSUserNoticeHandleResp.sErrStr = "not your notice"
        MsgApi.SendToUser(tExtData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
        SlaveData.tDBOprateWaitting.arrUserNoticeOprate[tExtData.nUserId] = nil
        return
    end

    if tNoticesInfo.nStatus~=0 then
        if tNoticesInfo.nStatus==1 or tNoticesInfo.nStatus==2 then
            Base.Log("_OnDBClubGetUserNoticeInfoRsp 该消息已处理")
            ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.HadHandle
            ClubSUserNoticeHandleResp.sErrStr = "had handled"
            MsgApi.SendToUser(tExtData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
        elseif tNoticesInfo.nStatus==3 then
            Base.Log("_OnDBClubGetUserNoticeInfoRsp 该消息无需处理")
            ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.NoNotice
            ClubSUserNoticeHandleResp.sErrStr = "not need handled"
            MsgApi.SendToUser(tExtData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
        elseif tNoticesInfo.nStatus==4 then
            Base.Log("_OnDBClubGetUserNoticeInfoRsp 该消息已失效")
            ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.Invalid
            ClubSUserNoticeHandleResp.sErrStr = "is Invalid"
            MsgApi.SendToUser(tExtData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
        end
        SlaveData.tDBOprateWaitting.arrUserNoticeOprate[tExtData.nUserId] = nil
        return
    end

    local isSuccee,tNData = pcall(Cjson.decode,tNoticesInfo.sData)
    if not isSuccee then
        Base.Log("_OnDBClubGetUserNoticeInfoRsp decode sData fail")
        ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.InfoErr
        ClubSUserNoticeHandleResp.sErrStr = "decode sData fail"
        MsgApi.SendToUser(tExtData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
        SlaveData.tDBOprateWaitting.arrUserNoticeOprate[tExtData.nUserId] = nil
        return
    end

    if tNoticesInfo.nType==2 then
        local nClubId = tNData.nClubId
        tExtData.nClubId = nClubId

        if tExtData.nOpType==1 then
            --同意邀请加入俱乐部
            local tClub = ClubSManager.GetClub(nClubId)
            if not tClub then
                Base.Log("_OnDBClubGetUserNoticeInfoRsp 俱乐部不存在")
                ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.NoClub
                ClubSUserNoticeHandleResp.sErrStr = "no club"
                MsgApi.SendToUser(tExtData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
                SlaveData.tDBOprateWaitting.arrUserNoticeOprate[tExtData.nUserId] = nil
                return
            end

            if tClub.nUserCnt>=tClub.nMaxUserCnt then
                Base.Log("_OnDBClubGetUserNoticeInfoRsp 俱乐部已满人")
                ClubSUserNoticeHandleResp.nRlt = PubErrCode.UserNoticeOprate.ClubIsFull
                ClubSUserNoticeHandleResp.sErrStr = "Club member is full"
                MsgApi.SendToUser(tExtData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
                SlaveData.tDBOprateWaitting.arrUserNoticeOprate[tExtData.nUserId] = nil
                return
            end

            tExtData.nMaxUserCnt = tClub.nMaxUserCnt
        end
        
        local ClubUserNoticeHandleReq = {}
        ClubUserNoticeHandleReq.nId = tNoticesInfo.nId
        ClubUserNoticeHandleReq.nOpType = tExtData.nOpType
        ClubUserNoticeHandleReq.nUserId = tExtData.nUserId
        ClubUserNoticeHandleReq.sExData = Cjson.encode(tExtData)
        MsgApi.SendToDBServer("ClubUserNoticeHandleReq",ClubUserNoticeHandleReq,tExtData.nUserId)
    else
        Base.Log("_OnDBClubGetUserNoticeInfoRsp 非法类型，无法处理")
    end
end

--DB服返回 处理个人通知 返回
function MsgClient.OnDBClubUserNoticeHandleRsp(sReturnKey, Data, nLen)
    local strProto = "ClubUserNoticeHandleRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end
    Base.Log("_OnDBClubUserNoticeHandleRsp nUserId_%d nRlt_%d sExData_%s",tData.nUserId,tData.nRlt,tData.sExData)
    local nRlt = tData.nRlt
    local sErrStr = ""
    local tExData = Cjson.decode(tData.sExData)
    if tData.nRlt==0 then
        nRlt = PubErrCode.UserNoticeOprate.Success
        sErrStr = "Success"
        
        if tExData.nOpType==1 then --同意
            --(俱乐部的人数)
            local tChangeInfo = {}
            tChangeInfo.nUserCnt = tExData.nUserCnt
            Base.Log("_OnDBClubUserNoticeHandleRsp nUserCnt_%d",tExData.nUserCnt)
            --发送俱乐部场景信息改变
            MsgApi.SendClubInfoChange(tExData.nClubId,tChangeInfo)

            --通知玩家同意进入的新俱乐部
            Base.Log("_OnDBClubUserNoticeHandleRsp 通知玩家同意进入的新俱乐部 nUserId_%d nClubId_%d",tData.nUserId,tExData.nClubId)
            local tClubInfo = {nClubId=tExData.nClubId,sClubName=tExData.sClubName,nMaster=tExData.nMaster}
            MsgApi.SendUserMessage(tData.nUserId,3,{tClubInfo=tClubInfo})
        end
    elseif tData.nRlt==4 then
        nRlt = PubErrCode.UserNoticeOprate.NoClub
        sErrStr = "no club"
        Base.Log("俱乐部不存在")
    elseif tData.nRlt==5 then
        nRlt = PubErrCode.UserNoticeOprate.ClubIsFull
        sErrStr = "Club member is full"
        Base.Log("俱乐部已满人")
    elseif tData.nRlt==10 then
        nRlt = PubErrCode.UserNoticeOprate.InClub
        sErrStr = "you is club member"
        Base.Log("已经是俱乐部成员")
    end

    local ClubSUserNoticeHandleResp = {}
    ClubSUserNoticeHandleResp.nRlt = nRlt
    ClubSUserNoticeHandleResp.sErrStr = sErrStr
    ClubSUserNoticeHandleResp.nId = tExData.nId
    ClubSUserNoticeHandleResp.nOpType = tExData.nOpType
    MsgApi.SendToUser(tData.nUserId,"ClubSUserNoticeHandleResp",ClubSUserNoticeHandleResp)
    SlaveData.tDBOprateWaitting.arrUserNoticeOprate[tData.nUserId] = nil
end

--玩家俱乐部币申请记录请求（玩家个人）
function MsgClient.OnClubSGetApplyListReq(sClientID, Data, nLen)
    local strProto = "ClubSGetApplyListReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetApplyListReq 玩家俱乐部币申请记录请求 nUserId_%d,nIdOfStart_%d,nCnt_%d,nType_%d,nClubId_%d",nUserId,tData.nIdOfStart,tData.nCnt,tData.nType,tData.nClubId)

    local nIdOfStart = tData.nIdOfStart
    if nIdOfStart<0 then
        nIdOfStart = 0
    end
    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubGetApplyListReq = {}
    ClubGetApplyListReq.nIdOfStart = nIdOfStart
    ClubGetApplyListReq.nCnt = nCnt
    ClubGetApplyListReq.nUserId = nUserId
    ClubGetApplyListReq.nType = tData.nType
    ClubGetApplyListReq.nClubId = tData.nClubId
    MsgApi.SendToDBServer("ClubGetApplyListReq",ClubGetApplyListReq,nUserId)
end

--DB服返回 玩家俱乐部币申请记录（玩家个人） 返回
function MsgClient.OnDBClubGetApplyListRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetApplyListRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrApplyList = {}
    for k,v in pairs(tData.arrApplyList) do
        if v.nId and v.nId>0 then
            local tApplyInfo = {}
            tApplyInfo.nId = v.nId
            tApplyInfo.nClubId = v.nClubId
            tApplyInfo.nType = v.nType
            tApplyInfo.sTime = v.sTime
            tApplyInfo.sClubName = v.sClubName
            tApplyInfo.nStatus = v.nStatus
            tApplyInfo.nChange = v.nChange
            table.insert(arrApplyList,tApplyInfo)
        end
    end

    Base.Log("_OnDBClubGetApplyListRsp nUserId_%d nType_%d nAllCnt_%d #arrApplyList_%d nClubId_%d",
        tData.nUserId,tData.nType,tData.nAllCnt,#arrApplyList,tData.nClubId)

    local ClubSGetApplyListResp = {}
    ClubSGetApplyListResp.nClubId = tData.nClubId
    ClubSGetApplyListResp.nAllCnt = tData.nAllCnt
    ClubSGetApplyListResp.nType = tData.nType
    ClubSGetApplyListResp.arrApplyList = arrApplyList
    MsgApi.SendToUser(tData.nUserId,"ClubSGetApplyListResp",ClubSGetApplyListResp)
end

--玩家申请处理请求（玩家个人）
function MsgClient.OnClubSUserApplyOpReq(sClientID, Data, nLen)
    local strProto = "ClubSUserApplyOpReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSUserApplyOpReq 玩家申请处理请求 nUserId_%d,nId_%d,nOpType_%d,nType_%d",nUserId,tData.nId,tData.nOpType,tData.nType)

    local ClubSUserApplyOpResp = {
        nRlt = PubErrCode.UserNoticeOprate.Success,
        nType=tData.nType,
        nId = tData.nId,
        nOpType = tData.nOpType,
    }

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrUserApplyOprate[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSUserApplyOpReq 请求过于频繁，等待上一个请求结束")
            ClubSUserApplyOpResp.nRlt = PubErrCode.UserApplyOprate.WaitDBReturn
        MsgApi.SendToClient(sClientID,"ClubSUserApplyOpResp",ClubSUserApplyOpResp)
            return
        end
    end

    --参数校验
    if tData.nOpType~=1 and tData.nOpType~=2 then
        Base.Log("_OnClubSUserApplyOpReq 参数错误 nOpType Err")
        ClubSUserApplyOpResp.nRlt = PubErrCode.UserApplyOprate.ParamsErr
        MsgApi.SendToClient(sClientID,"ClubSUserApplyOpResp",ClubSUserApplyOpResp)
        return
    end
    if tData.nType~=1 and tData.nType~=2 and tData.nType~=3 then
        Base.Log("_OnClubSUserApplyOpReq 参数错误 nType Err")
        ClubSUserApplyOpResp.nRlt = PubErrCode.UserApplyOprate.ParamsErr
        MsgApi.SendToClient(sClientID,"ClubSUserApplyOpResp",ClubSUserApplyOpResp)
        return
    end

    
    SlaveData.tDBOprateWaitting.arrUserApplyOprate[nUserId] = os.time()

    local ClubUserApplyOpReq = {}
    ClubUserApplyOpReq.nId = tData.nId
    ClubUserApplyOpReq.nOpType = tData.nOpType
    ClubUserApplyOpReq.nType = tData.nType
    ClubUserApplyOpReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubUserApplyOpReq",ClubUserApplyOpReq,nUserId)
end

--DB服返回 玩家申请处理 返回
function MsgClient.OnDBClubUserApplyOpRsp(sReturnKey, Data, nLen)
    local strProto = "ClubUserApplyOpRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubUserApplyOpRsp nUserId_%d nRlt_%d nId_%d nOpType_%d nType_%d sExData_%s",
    tData.nUserId,tData.nRlt,tData.nId,tData.nOpType,tData.nType,tData.sExData)
    
    local nRlt = tData.nRlt
    local tExData = Cjson.decode(tData.sExData)
    if tData.nRlt==0 then
        local tChangeInfo = {}
        if tData.nType==3 then
            tChangeInfo.nApplyJionCnt = tExData.nApplyCnt
            Base.Log("_OnDBClubUserApplyOpRsp nApplyJionCnt_%d",tExData.nApplyCnt)
        elseif tData.nType==1 then
            tChangeInfo.nApplyAddGoldCnt = tExData.nApplyCnt
            Base.Log("_OnDBClubUserApplyOpRsp nApplyAddGoldCnt_%d",tExData.nApplyCnt)
        elseif tData.nType==2 then  
            tChangeInfo.nApplyCutGoldCnt = tExData.nApplyCnt
            Base.Log("_OnDBClubUserApplyOpRsp nApplyCutGoldCnt_%d",tExData.nApplyCnt)
        end
        --发送俱乐部场景信息改变
        MsgApi.SendClubInfoChange(tExData.nClubId,tChangeInfo)
    elseif tData.nRlt==1 then
        Base.Log("_OnDBClubUserApplyOpRsp 申请不存在")
    elseif tData.nRlt==2 then
        Base.Log("_OnDBClubUserApplyOpRsp 不是你的申请")
    elseif tData.nRlt==3 then
        Base.Log("_OnDBClubUserApplyOpRsp 已被处理或者已失效")
    else
        Base.Log("_OnDBClubUserApplyOpRsp db Err")
    end


    local ClubSUserApplyOpResp = {}
    ClubSUserApplyOpResp.nRlt = nRlt
    ClubSUserApplyOpResp.nType = tData.nType
    ClubSUserApplyOpResp.nId = tData.nId
    ClubSUserApplyOpResp.nOpType = tData.nOpType
    MsgApi.SendToUser(tData.nUserId,"ClubSUserApplyOpResp",ClubSUserApplyOpResp)
    SlaveData.tDBOprateWaitting.arrUserApplyOprate[tData.nUserId] = nil
end


local function _SetWithDrawGold_User_ServerKey(nUserId)   
	local sKey =string.format("WithDrawGold_User_ServerKey_%d",nUserId)
	local sServKey =  Base.m_tKey
	Base.m_MyRedisData[1].redis:set(sKey,Base.m_tKey.."Gateway")
	Base.m_MyRedisData[1].redis:expire(sKey,10)   
end

-- 获取 可提现金币 与 不可提现金币： nHandleType: 1、更新，2、获取
local function _GetUserWithDrawGold(nUserId,nHandleType,nGold)
    if nHandleType == 1 then
        local function OnWebUrlReq(sUrl)           
            local funcRes = function(sData,nCode)  
                local isSuccee,tRlt = pcall(Cjson.decode,sData) 
                if not isSuccee then  
                    return 
                end 	 
            end	
            local funcErr = function(nCode)
                Base.Log("_GetUserWithDrawGold  funcErr  nCode: %s  sUrl: %s",nCode,sUrl)
            end 
            HttpNB.request(sUrl,funcRes,funcErr,"GET","") 
        end
        local sConfigUrl = RedisCahche._Get_WebDomainName("sClubWithDrawGoldUrl") or ""
        local sUrl = string.format("%s%d",sConfigUrl,nUserId) 
        -- OnWebUrlReq(sUrl)   
        Base.Log("_GetUserWithDrawGold  nUserId: %d  请求提现金币 %s ",nUserId,Base.m_tKey)
        _SetWithDrawGold_User_ServerKey(nUserId) 
        return {}
    else         
        local t =  PublicRedis._GetRedisData("GSP_WithdrawalGold",math.floor(nUserId)) --[[总额度: SumAmount ,可用：SureAmount,不可用：NoAmount--]]
        --  {\"SumAmount\": 990.0,\"SureAmount\": 990.0,\"NoAmount\": 999.0}
        local tData = t
        if type(t) == "string" then 
            tData = Cjson.decode(t)  
        end 
        local tWithDrawGold = {}
        tWithDrawGold.nWithDrawGold = tonumber(tData.SureAmount) or 0         
        tWithDrawGold.nNotWithDrawGold = tonumber(tData.NoAmount) or 0 
        -- 保留2位
        nGold=  PublicApi.Floor_2(nGold)
        tWithDrawGold.nWithDrawGold =  PublicApi.Floor_2(tWithDrawGold.nWithDrawGold)
        tWithDrawGold.nNotWithDrawGold =  PublicApi.Floor_2(tWithDrawGold.nNotWithDrawGold)
        local sLog = ""
        if nGold ~= (tWithDrawGold.nWithDrawGold + tWithDrawGold.nNotWithDrawGold) then 
            sLog = string.format("有延迟:  nGold: %.1f ~=  %.1f + %.1f ",nGold,tWithDrawGold.nWithDrawGold,tWithDrawGold.nNotWithDrawGold)
            tWithDrawGold.nNotWithDrawGold = PublicApi.Floor_2(math.abs(nGold-tWithDrawGold.nWithDrawGold) )
        end 
        Base.Log("_GetUserWithDrawGold 获取提现金币_: %d=%s,  %s  Redis: %s ",nUserId,Cjson.encode(tWithDrawGold),sLog,t)
        return tWithDrawGold
    end 
end

--玩家个人信息请求
function MsgClient.OnClubSUserInfoReq(sClientID, Data, nLen)
    local strProto = "ClubSUserInfoReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("_OnClubSUserInfoReq 玩家个人信息请求 myself_%d,nUserId_%d",nUserId,tData.nUserId)
    local ClubUserInfoReq = {}
    ClubUserInfoReq.nUserId = tData.nUserId
    ClubUserInfoReq.nSendUserId = nUserId
    MsgApi.SendToDBServer("ClubUserInfoReq",ClubUserInfoReq,nUserId)
    _GetUserWithDrawGold(tData.nUserId,1)   
end

--DB服返回 玩家个人信息 返回
function MsgClient.OnDBClubUserInfoRsp(sReturnKey, Data, nLen)
    local strProto = "ClubUserInfoRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local nGroupId = -1
    local tUser = UserManager.GetUserInfo(tData.tUserInfo.nUserId)
    if tUser then
        nGroupId = tUser.nGroupId
    end

    local PayExchangeRate = RedisCahche._GetPayExchangeRate(nGroupId)
    local tUserInfo = {}
    if tData.tUserInfo then
        tUserInfo.nUserId = tData.tUserInfo.nUserId
        tUserInfo.sFaceId = tData.tUserInfo.sFaceId
        tUserInfo.sName = tData.tUserInfo.sName
        tUserInfo.nSex = tData.tUserInfo.nSex
        tUserInfo.nGold = tData.tUserInfo.nGold
        tUserInfo.sTime = tData.tUserInfo.sTime
        tUserInfo.sPhone = tData.tUserInfo.sPhone
        tUserInfo.nAllCount = tData.tUserInfo.nAllCount
        tUserInfo.nMaxProfit = tData.tUserInfo.nMaxProfit
        tUserInfo.sPersonality = tData.tUserInfo.sPersonality
        tUserInfo.nHandCount = tData.tUserInfo.nHandCount
        tUserInfo.nMaxHandProfit = tData.tUserInfo.nMaxHandProfit
        tUserInfo.nVip = tData.tUserInfo.nVip
        tUserInfo.nExp = tData.tUserInfo.nExp
        tUserInfo.nGloryLevel = tData.tUserInfo.nGloryLevel
        tUserInfo.nLevelStart = tData.tUserInfo.nLevelStart
        tUserInfo.nOpenProtection = tData.tUserInfo.nOpenProtection
        local tWithDraw = _GetUserWithDrawGold(tData.tUserInfo.nUserId,2,tUserInfo.nGold)
        tUserInfo.nWithDrawGold =  tWithDraw.nWithDrawGold or 0        -- 可提现金币
        tUserInfo.nNotWithDrawGold = tWithDraw.nNotWithDrawGold or 0    -- 不可提现金币
        -- tUserInfo.nCash = tWithDraw.nWithDrawGold/PayExchangeRate
        tUserInfo.nReviewedGold = tData.tUserInfo.nReviewedGold
        tUserInfo.nExchangeRate = PayExchangeRate
        tUserInfo.nTransSwitch = PublicUserInfo.GetUserTransferSwitch(math.floor(tData.tUserInfo.nUserId))
        tUserInfo.sMail =tData.tUserInfo.sMail
        local count, price = UserOnTime.GetUserNameData(tUserInfo.nUserId)
        Base.Log("_OnDBClubUserInfoRsp count_%d price_%d", count, price)
        tUserInfo.nFreeCount = count
        tUserInfo.nPrice = price
    end
    Base.Log("_OnDBClubUserInfoRsp nSendUserId_%d nRlt_%d tUserInfo_%s",
        tData.nSendUserId,tData.nRlt,Cjson.encode(tUserInfo))

    local nRlt = tData.nRlt
    local sErrStr = ""
    if nRlt == 0 then
        nRlt = PubErrCode.GetUserInfo.Success
        sErrStr = "sucess"
    elseif nRlt == 2 then
        nRlt = PubErrCode.GetUserInfo.NoUser
        sErrStr = "not find user"
        Base.Log("_OnDBClubUserInfoRsp 没找到玩家")
    end
    local ClubSUserInfoResp = {}
    ClubSUserInfoResp.nRlt = nRlt
    ClubSUserInfoResp.sErrStr = sErrStr
    if nRlt==PubErrCode.GetUserInfo.Success then
        ClubSUserInfoResp.tUserInfo = tUserInfo
    end
    MsgApi.SendToUser(tData.nSendUserId,"ClubSUserInfoResp",ClubSUserInfoResp)
end

--后台用户提现通知
function MsgClient.OnWithDrawGoldNotify(sReturnKey,Data,nLen)
    local tData =BackstageAux:Parser(Data, nLen,"WithDrawGoldNotify")
    if not tData then
        Base.Log("_OnWithDrawGoldNotify _Parse Err")
        return
    end
    local tUser = UserManager.GetUserInfo(tData.nUserId)
    if not tUser then
        Base.Log("_OnWithDrawGoldNotify 玩家信息不存在 nUserId:%d",tData.nUserId)
        return
    end
    local nNowGold = PublicUserInfo.Get_User_Gold(tData.nUserId,1)
    Base.Log("_OnOnWithDrawGoldNotify 后台用户提现通知 nUserId:%s  nNowGold: %.1f",tData.nUserId,nNowGold)    
    local tWithDraw = _GetUserWithDrawGold(tData.nUserId,2,nNowGold)
    local ClubSWithDrawGoldRep = {}
    ClubSWithDrawGoldRep.nWithDrawGold =  tWithDraw.nWithDrawGold or 0        -- 可提现金币
    ClubSWithDrawGoldRep.nNotWithDrawGold = tWithDraw.nNotWithDrawGold or 0    -- 不可提现金币
    MsgApi.SendToUser(tData.nUserId,"ClubSWithDrawGoldRep",ClubSWithDrawGoldRep)    
end

--后台审核通知
function MsgClient.OnVerifyNotify_old(sReturnKey,Data,nLen)
    Base.Log("收到后台审核通知")
    local tData =BackstageAux:Parser(Data, nLen,"VerifyNotify")
    if not tData then
        Base.Log("_OnVerifyNotify _Parse Err")
        return
    end
    Base.Log("_OnVerifyNotify nUserId:%d nType:%d",tData.nUserId,tData.nType)
    
    if tData.nType == 6 then
        RedisCahche._UpdateUserTransferSwitch(tData.nUserId,1)
    end
    if tData.nType == 9 then
        RedisCahche._UpdateUserTransferSwitch(tData.nUserId,0)
    end
    --分享审核未通过
    if tData.nType == 12 then
        RedisCahche._UpdateUserShareActiSwitch(tData.nUserId,1)
    end
    
    --首充奖励
    if tData.nType == 10 then
        local tNoticesInfo = {}
        tNoticesInfo.arrRedot = {{nType=4,nCount=1}}
        MsgApi.SendUserMessage(tData.nUserId,7,tNoticesInfo)
        return
    end
    --分享奖励    
    if tData.nType == 11 then
        local tNoticesInfo = {}
        tNoticesInfo.arrRedot = {{nType=4,nCount=1}}
        MsgApi.SendUserMessage(tData.nUserId,7,tNoticesInfo)
    end
    --绑定奖励
    if tData.nType == 13 then
        local tNoticesInfo = {}
        tNoticesInfo.arrRedot = {{nType=4,nCount=1}}
        MsgApi.SendUserMessage(tData.nUserId,7,tNoticesInfo)
    end
    
    local ClubNotifyRecordReq = {}
    ClubNotifyRecordReq.nUserId = tData.nUserId
    ClubNotifyRecordReq.nType = tData.nType
    MsgApi.SendToDBServer("ClubNotifyRecordReq",ClubNotifyRecordReq,tData.nUserId)
end

--DB服返回 后台审核返回
function MsgClient.OnDBClubNotifyRecordRsp(sReturnKey, Data, nLen)
    local strProto = "ClubNotifyRecordRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("OnDBClubNotifyRecordRsp")

    local tNoticesInfo = {}
    tNoticesInfo.arrRedot = {{nType=3,nCount=1}}
    MsgApi.SendUserMessage(tData.nUserId,7,tNoticesInfo)
end


--修改玩家个人信息请求 sFaceId,sName,nSex,sPhone
function MsgClient.OnClubSChangeUserInfoReq(sClientID, Data, nLen)
    local strProto = "ClubSChangeUserInfoReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    local tChange = {}
    for _,v in pairs(tData.arrChange) do
        if v.sKey then
            tChange[v.sKey] = v.sVal
        end
    end
    local nPurpose = tonumber(tData.nPurpose) or 2

    local nGroupId = -1
    local tUser = UserManager.GetUserInfo(nUserId)
    if tUser then
        nGroupId = tUser.nGroupId
    end
    local tUserInfo = PublicUserInfo.GetUserInfo(nUserId) or {}
    local nEmail = tUserInfo.nEmail

    Base.Log("_OnClubSChangeUserInfoReq 修改玩家个人信息请求 nUserId_%d nGroupId_%d tChange_%s",nUserId,nGroupId,Cjson.encode(tChange))

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrChangeUserInfo[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSChangeUserInfoReq 请求过于频繁，等待上一个请求结束")
            local ClubSChangeUserInfoResp = {}
            ClubSChangeUserInfoResp.arrRlt = {}
            ClubSChangeUserInfoResp.nRlt = 1
            MsgApi.SendToClient(sClientID,"ClubSChangeUserInfoResp",ClubSChangeUserInfoResp)
            return
        end
    end

    local arrSuccess = {} --校验成功的
    local arrFail = {} --校验失败的
    local nPrice = 0
    --参数校验
    if tChange["sFaceId"] then
        local sVal = tChange["sFaceId"] 
        if #sVal<=0 then
            Base.Log("_OnClubSChangeUserInfoReq 参数错误 sFaceId不符合要求")
            table.insert(arrFail,{sKey="sFaceId",nRlt=PubErrCode.ChangeUserInfo.ParamsErr})
        else
            table.insert(arrSuccess,{sKey="sFaceId",sVal=sVal})
        end
    end
    if tChange["sName"] then
        local sVal = tChange["sName"]
        local count, price = UserOnTime.GetUserNameData(nUserId)
        if sVal == "" then
            Base.Log("_OnClubSChangeUserInfoReq 玩家昵称为空")
            table.insert(arrFail,{sKey="sName",nRlt=PubErrCode.ChangeUserInfo.ParamsErr})
        elseif count > 0 and price > 0 then
            --不能免费修改名字了，对金币进行加锁
            nPrice = price
            if not PublicUserInfo.Gold_Lock(nUserId, PublicApi.Floor_2(price),1) then
                Base.Log("_OnClubSChangeUserInfoReq 金币加锁失败")
                table.insert(arrFail,{sKey="sName",nRlt=PubErrCode.ChangeUserInfo.GoldLess})
            else
                table.insert(arrSuccess,{sKey="sName",sVal=sVal})
            end        
        elseif #sVal>Define.nNameLen then
            Base.Log("_OnClubSChangeUserInfoReq 参数错误 sName过长")
            table.insert(arrFail,{sKey="sName",nRlt=PubErrCode.ChangeUserInfo.NameTooLong})
        elseif count == 0 then
            Base.Log("_OnClubSChangeUserInfoReq 玩家免费修改名字次数已用完")
            table.insert(arrFail,{sKey="sName",nRlt=PubErrCode.ChangeUserInfo.NoFreeChangeNameCnt})
        else
            table.insert(arrSuccess,{sKey="sName",sVal=sVal})
        end
    end
    if tChange["nSex"] then
        local sVal = tChange["nSex"]
        if tonumber(sVal)~=0 and tonumber(sVal)~=1 and tonumber(sVal)~=2 then
            Base.Log("_OnClubSChangeUserInfoReq 参数错误 nSex不符合要求")
            table.insert(arrFail,{sKey="nSex",nRlt=PubErrCode.ChangeUserInfo.ParamsErr})
        else
            table.insert(arrSuccess,{sKey="nSex",sVal=sVal})
        end
    end
    if tChange["sPhone"] and false then  --不能修改手机号
        local sVal = tChange["sPhone"]
        if type(tonumber(sVal))~="number" then
            Base.Log("_OnClubSChangeUserInfoReq 参数错误 sPhone不是数字")
            table.insert(arrFail,{sKey="sPhone",nRlt=PubErrCode.ChangeUserInfo.ParamsErr})
        elseif #sVal~=11 then
            Base.Log("_OnClubSChangeUserInfoReq 参数错误 sPhone不是11位数字")
            table.insert(arrFail,{sKey="sPhone",nRlt=PubErrCode.ChangeUserInfo.NotSuit})
        else
            table.insert(arrSuccess,{sKey="sPhone",sVal=sVal})
        end
    end
    if tChange["sPersonality"] then
        local sVal = tChange["sPersonality"]
        if #sVal>Define.nPersonalityLen then
            Base.Log("_OnClubSChangeUserInfoReq 参数错误 sPersonality过长")
            table.insert(arrFail,{sKey="sPersonality",nRlt=PubErrCode.ChangeUserInfo.PersonalityTooLong})
        else
            table.insert(arrSuccess,{sKey="sPersonality",sVal=sVal})
        end        
    end
    if tChange["sSafePassWard"] then
        repeat
            Base.Log("_OnClubSChangeUserInfoReq NeedCheckSafePassWard tUserInfo.nOpenProtection:%s", tUserInfo.nOpenProtection)
            if PublicUserInfo.IsNeedCheckSafePassWard(nUserId) then
                Base.Log("_OnClubSChangeUserInfoReq NeedCheckSafePassWard tData.oldPass:%s tUserInfo.sSafePassWard:%s", tData.oldPass, tUserInfo.sSafePassWard)
                if tUserInfo.sSafePassWard ~= tData.oldPass then
                    table.insert(arrFail,{sKey="sSafePassWard",nRlt=PubErrCode.ChangeUserInfo.OldPassErr})
                    break
                end
            end
            Base.Log("_OnClubSChangeUserInfoReq nEmail:%s tData.code:%s tData.oldPass:%s", nEmail, tData.code, tData.oldPass)
            if nEmail == "" then
                table.insert(arrFail,{sKey="sSafePassWard",nRlt=PubErrCode.ChangeUserInfo.EmailErr})
                break
            end
            if tData.code == "" then
                table.insert(arrFail,{sKey="sSafePassWard",nRlt=PubErrCode.ChangeUserInfo.ParamsErr})
                break
            end
            if not tMoblieBinder.VerifyCode(nEmail,tData.code,false,false,nPurpose) then
                Base.Log("_OnClubSChangeUserInfoReq VerifyCode not pass")
                table.insert(arrFail,{sKey="sSafePassWard",nRlt=PubErrCode.ChangeUserInfo.CodeErr})
                break
            end
        until true
        local sVal = tChange["sSafePassWard"]
        if #sVal>Define.Len_PassWord then
            Base.Log("_OnClubSChangeUserInfoReq 参数错误 sSafePassWard不符合要求")
            table.insert(arrFail,{sKey="sSafePassWard",nRlt=PubErrCode.ChangeUserInfo.SafePassWardErr})
        else
            table.insert(arrSuccess,{sKey="sSafePassWard",sVal=sVal})
        end
        -- local ClubSecuPwdReq = {}
        -- ClubSecuPwdReq.nUserId = nUserId
        -- ClubSecuPwdReq.SecuPwd = sVal
        -- MsgApi.SendToDBServer("ClubSecuPwdReq",ClubSecuPwdReq,nUserId)
    end
    
    Base.Log("_OnClubSChangeUserInfoReq arrSuccess_%s arrFail_%s",Cjson.encode(arrSuccess),Cjson.encode(arrFail))

    --如果有参数校验没通过的，直接返回失败
    if #arrFail>0 then
        local ClubSChangeUserInfoResp = {}
        ClubSChangeUserInfoResp.arrRlt = arrFail
        ClubSChangeUserInfoResp.nRlt = 1
        MsgApi.SendToClient(sClientID,"ClubSChangeUserInfoResp",ClubSChangeUserInfoResp)
        return
    end

    if #arrSuccess==0 then
        Base.Log("_OnClubSChangeUserInfoReq 没有要修改的个人信息项")
        return
    end

    --不是修改安全密码，判断是否需要进行安全密码校验
    -- if not tChange["sSafePassWard"] and PublicUserInfo.IsNeedCheckSafePassWard(nUserId) then
    --     local nResult = PublicUserInfo.GetCheckSafePassWardResult(nUserId) ----获取安全密码校验结果
    --     if nResult==nil then
    --         Base.Log("_OnClubSChangeUserInfoReq 没有进行安全密码校验")
    --         for k,v in pairs(arrSuccess) do
    --             table.insert(arrFail,{sKey=v.sKey,nRlt=PubErrCode.ChangeUserInfo.NoCheckSPW})
    --         end
    --         local ClubSChangeUserInfoResp = {}
    --         ClubSChangeUserInfoResp.arrRlt = arrFail
    --         ClubSChangeUserInfoResp.nRlt = 1
    --         MsgApi.SendToClient(sClientID,"ClubSChangeUserInfoResp",ClubSChangeUserInfoResp)
    --         return
    --     elseif nResult==0 then
    --         Base.Log("_OnClubSChangeUserInfoReq 进行安全密码校验失败")
    --         for k,v in pairs(arrSuccess) do
    --             table.insert(arrFail,{sKey=v.sKey,nRlt=PubErrCode.ChangeUserInfo.CheckSPWErr})
    --         end
    --         local ClubSChangeUserInfoResp = {}
    --         ClubSChangeUserInfoResp.arrRlt = arrFail
    --         ClubSChangeUserInfoResp.nRlt = 1
    --         MsgApi.SendToClient(sClientID,"ClubSChangeUserInfoResp",ClubSChangeUserInfoResp)
    --         return
    --     end
    --     PublicUserInfo.DelCheckSafePassWardResult(nUserId)
    -- end

    SlaveData.tDBOprateWaitting.arrChangeUserInfo[nUserId] = os.time()

    local ClubChangeUserInfoReq = {}
    ClubChangeUserInfoReq.arrChange = arrSuccess
    ClubChangeUserInfoReq.nUserId = nUserId
    ClubChangeUserInfoReq.nPrice = nPrice
    MsgApi.SendToDBServer("ClubChangeUserInfoReq",ClubChangeUserInfoReq,nUserId)
end

--DB服返回 修改玩家个人信息 返回
function MsgClient.OnDBClubChangeUserInfoRsp(sReturnKey, Data, nLen)
    local strProto = "ClubChangeUserInfoRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local nGroupId = -1
    local tUser = UserManager.GetUserInfo(tData.nUserId)
    if tUser then
        nGroupId = tUser.nGroupId
    end

    local nNowClubId = tUser:GetNowClub()

    local arrRlt = {}
    for k,v in pairs(tData.arrRlt) do
        if v.sKey then
            table.insert(arrRlt,{nRlt=v.nRlt,sKey=v.sKey,sVal=v.sVal})
        end
    end

    Base.Log("_OnDBClubChangeUserInfoRsp nUserId_%d arrRlt_%s",
        tData.nUserId,Cjson.encode(arrRlt))

    local nRlt = 0
    local arrFail = {}
    local arrSuccess = {}
    local tChangeInfo = {nUserID=tData.nUserId}
    local isUpdate = false
    local isNotify = false
    local isDelCheck = false
    for k,v in pairs(arrRlt) do
        if v.nRlt~=PubErrCode.ChangeUserInfo.Success then
            table.insert(arrFail,{nRlt=v.nRlt,sKey=v.sKey})
            nRlt = 1
        else
            table.insert(arrSuccess,{nRlt=v.nRlt,sKey=v.sKey})
            if v.sKey=="sName" then
                tChangeInfo["sNickName"] = v.sVal
                isUpdate = true
                isNotify = true
                local count, price = UserOnTime.GetUserNameData(tData.nUserId)
                Base.Log("GetUserNameData count:%d price:%.2f", count, price)
                --修改名字成功，增加次数，并且扣除金币
                if price > 0 then
                    local isSuccee,sErr,nGoldAfterChange = PublicUserInfo.UnLockAndMinus(tData.nUserId, PublicApi.Floor_2(price),Define.SourceType.ChangeName,0,1)
                    if isSuccee then
                        MsgApi.SendUserInfoChange(nNowClubId,tData.nUserId,{nGold=nGoldAfterChange})
                        UserManager.RefleshUserGold(tData.nUserId,nGoldAfterChange)
                    else
                        Base.Log("修改名字扣除金币失败 %s",sErr or "")
                    end
                end
                UserOnTime.ChangeNameSuccess(tData.nUserId)
            elseif v.sKey=="sFaceId" then
                tChangeInfo["sFaceID"] = v.sVal
                isUpdate = true
                isNotify = true
            elseif v.sKey=="nSex" then
                tChangeInfo["nSex"] = tonumber(v.sVal) or 0
                isUpdate = true
                isNotify = true
            elseif v.sKey=="sPersonality" then
                tChangeInfo["sPersonality"] = v.sVal
                isUpdate = true
            elseif v.sKey=="sSafePassWard" then
                tChangeInfo["sSafePassWard"] = v.sVal
                isUpdate = true
                isDelCheck = true
            elseif v.sKey=="nOpenProtection" then
                tChangeInfo["nOpenProtection"] = tonumber(v.sVal) or 0
                isUpdate = true
                isDelCheck = true
            end
        end
    end

    if #arrRlt==0 then
        nRlt = 1
    end

    --需要更新redis上的玩家数据
    if isUpdate then
        PublicUserInfo.UpdateUserData(tChangeInfo)
        MsgApi.SendUserInfoChangeToGameServer(tData.nUserId,tChangeInfo)
    end

    --需要删除安全码校验状态
    if isDelCheck then
        PublicUserInfo.DelCheckSafePassWardResult(tData.nUserId)
    end

    local ClubSChangeUserInfoResp = {}
    ClubSChangeUserInfoResp.nRlt = nRlt
    if nRlt==1 then
        ClubSChangeUserInfoResp.arrRlt = arrFail
    else
        ClubSChangeUserInfoResp.arrRlt = arrSuccess
    end
    MsgApi.SendToUser(tData.nUserId,"ClubSChangeUserInfoResp",ClubSChangeUserInfoResp)

    --是否需要通知俱乐部主席信息改变
    if isNotify then
        local arrClub = ClubSManager.GetAllClub()
        for _,tClub in pairs(arrClub) do
            local tMasterInfo = tClub:GetMasterInfo()
            if tMasterInfo.nMaster==tData.nUserId then
                --通知这个玩家所创建的俱乐部，主席信息改变
                if tChangeInfo["sFaceID"] then
                    tMasterInfo.sFaceId = tChangeInfo["sFaceID"]
                end
                if tChangeInfo["nSex"] then
                    tMasterInfo.nSex = tChangeInfo["nSex"]
                end
                if tChangeInfo["sNickName"] then
                    tMasterInfo.sName = tChangeInfo["sNickName"]
                end
                MsgApi.SendClubInfoChange(tClub.nClubId,{tMasterInfo=tMasterInfo})
            end
        end
        --通知玩家所在俱乐部，玩家信息改变
        MsgApi.SendUserInfoChange(nNowClubId,tData.nUserId,{sFaceId=tChangeInfo["sFaceID"],sName=tChangeInfo["sNickName"],nSex=tChangeInfo["nSex"]})
    end
    SlaveData.tDBOprateWaitting.arrChangeUserInfo[tData.nUserId] = nil
end

--修改登录密码请求
function MsgClient.OnClubSChangeLoginPassWardReq(sClientID, Data, nLen)
    local strProto = "ClubSChangeLoginPassWardReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSChangeLoginPassWardReq 修改登录密码请求 nUserId_%d sOldPassWord_%s sNewPassWord_%s",
    nUserId,tData.sOldPassWord,tData.sNewPassWord)

    local ClubSChangeLoginPassWardResp = {
        nRlt = PubErrCode.ChangePassWard.Success,
        sErrStr = "",
    }

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrChangePassWard[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_OnClubSChangeLoginPassWardReq 请求过于频繁，等待上一个请求结束")
            ClubSChangeLoginPassWardResp.nRlt = PubErrCode.ChangePassWard.WaitDBReturn
            ClubSChangeLoginPassWardResp.sErrStr = "too frequently,waitting last req return"
            MsgApi.SendToClient(sClientID,"ClubSChangeLoginPassWardResp",ClubSChangeLoginPassWardResp)
            return
        end
    end

    --参数校验
    if #tData.sOldPassWord < 6 or #tData.sOldPassWord > 50 then 
        Base.Log("_OnClubSChangeLoginPassWardReq 旧密码长度不对")   
        ClubSChangeLoginPassWardResp.nRlt = PubErrCode.ChangePassWard.NotSuit
        ClubSChangeLoginPassWardResp.sErrStr = "sOldPassWord len Err ,not in 6~50"
        MsgApi.SendToClient(sClientID,"ClubSChangeLoginPassWardResp",ClubSChangeLoginPassWardResp)
        return
    end 
    if #tData.sNewPassWord < 6 or #tData.sNewPassWord > 50 then 
        Base.Log("_OnClubSChangeLoginPassWardReq 新密码长度不对")   
        ClubSChangeLoginPassWardResp.nRlt = PubErrCode.ChangePassWard.NotSuit
        ClubSChangeLoginPassWardResp.sErrStr = "sNewPassWord len Err ,not in 6~50"
        MsgApi.SendToClient(sClientID,"ClubSChangeLoginPassWardResp",ClubSChangeLoginPassWardResp)
        return
    end 

    --需要进行安全密码校验
    if PublicUserInfo.IsNeedCheckSafePassWard(nUserId) then
        -- local nResult = PublicUserInfo.GetCheckSafePassWardResult(nUserId) ----获取安全密码校验结果
        -- if nResult==nil then
        --     Base.Log("_OnClubSChangeLoginPassWardReq 没有进行安全密码校验")
        --     ClubSChangeLoginPassWardResp.nRlt = PubErrCode.ChangePassWard.NoCheckSPW
        --     ClubSChangeLoginPassWardResp.sErrStr = "not check SafePassWard"
        --     MsgApi.SendToClient(sClientID,"ClubSChangeLoginPassWardResp",ClubSChangeLoginPassWardResp)
        --     return
        -- elseif nResult==0 then
        --     Base.Log("_OnClubSChangeLoginPassWardReq 进行安全密码校验失败")
        --     ClubSChangeLoginPassWardResp.nRlt = PubErrCode.ChangePassWard.CheckSPWErr
        --     ClubSChangeLoginPassWardResp.sErrStr = "check SafePassWard fail"
        --     MsgApi.SendToClient(sClientID,"ClubSChangeLoginPassWardResp",ClubSChangeLoginPassWardResp)
        --     return 
        -- end
        PublicUserInfo.DelCheckSafePassWardResult(nUserId)
    end

    SlaveData.tDBOprateWaitting.arrChangePassWard[nUserId] = os.time()

    local ClubChangeLoginPassWardReq = {}
    ClubChangeLoginPassWardReq.sOldPassWord = tData.sOldPassWord
    ClubChangeLoginPassWardReq.sNewPassWord = tData.sNewPassWord
    ClubChangeLoginPassWardReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubChangeLoginPassWardReq",ClubChangeLoginPassWardReq,nUserId)
end

--DB服返回 修改登录密码 返回
function MsgClient.OnDBClubChangeLoginPassWardRsp(sReturnKey, Data, nLen)
    local strProto = "ClubChangeLoginPassWardRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubChangeLoginPassWardRsp nUserId_%d nRlt_%d",tData.nUserId,tData.nRlt)

    local nRlt = tData.nRlt
    local sErrStr = ""
    if nRlt==0 then
        nRlt = PubErrCode.ChangePassWard.Success
        sErrStr = "success"
    elseif nRlt==2 then
        nRlt = PubErrCode.ChangePassWard.OldPassWardErr
        sErrStr = "OldPassWard is Err"
        Base.Log("_OnDBClubChangeLoginPassWardRsp 旧密码错误")
    elseif nRlt==3 then
        nRlt = PubErrCode.ChangePassWard.IsSame
        sErrStr = "OldPassWard is same to sNewPassWord"
        Base.Log("_OnDBClubChangeLoginPassWardRsp 新旧密码相同")
    else
        nRlt = PubErrCode.ChangePassWard.DBErr
        sErrStr = "Db Err"
        Base.Log("_OnDBClubChangeLoginPassWardRsp db Err")
    end

    local ClubSChangeLoginPassWardResp = {}
    ClubSChangeLoginPassWardResp.nRlt = nRlt
    ClubSChangeLoginPassWardResp.sErrStr = sErrStr
    MsgApi.SendToUser(tData.nUserId,"ClubSChangeLoginPassWardResp",ClubSChangeLoginPassWardResp)
    SlaveData.tDBOprateWaitting.arrChangePassWard[tData.nUserId] = nil
end

--回放数据请求
function MsgClient.OnClubSPlaybackDataReq(sClientID, Data, nLen)
    local strProto = "ClubSPlaybackDataReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSPlaybackDataReq 回放数据请求 nUserId_%d,sPaiJuID_%s",nUserId,tData.sPaiJuID)

    local ClubPlaybackDataReq = {}
    ClubPlaybackDataReq.sPaiJuID = tData.sPaiJuID
    ClubPlaybackDataReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubPlaybackDataReq",ClubPlaybackDataReq,nUserId)
end

--DB服返回 回放数据 返回
function MsgClient.OnDBClubPlaybackDataRsp(sReturnKey, Data, nLen)
    local strProto = "ClubPlaybackDataRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubPlaybackDataRsp nUserId_%d nRlt_%d sPaiJuID_%s nGameId_%d sJson_%s sTime_%s",
    tData.nUserId,tData.nRlt,tData.sPaiJuID,tData.nGameId or -1,tData.sJson or "",tData.sTime or "")

    local nRlt = tData.nRlt
    local sErrStr = ""
    if nRlt==0 then
        nRlt = PubErrCode.ChangePassWard.Success
        sErrStr = "success"
    elseif nRlt==1 then
        nRlt = PubErrCode.Playback.NoPaiJu
        sErrStr = "not find PaiJu"
        Base.Log("_OnDBClubPlaybackDataRsp 牌局不存在")
    end

    local ClubSPlaybackDataResp = {}
    ClubSPlaybackDataResp.nRlt = nRlt
    ClubSPlaybackDataResp.sErrStr = sErrStr
    ClubSPlaybackDataResp.sPaiJuID = tData.sPaiJuID
    ClubSPlaybackDataResp.nGameId = tData.nGameId
    ClubSPlaybackDataResp.sJson = tData.sJson
    ClubSPlaybackDataResp.sTime = tData.sTime
    ClubSPlaybackDataResp.sTableName=tData.sTableName
    MsgApi.SendToUser(tData.nUserId,"ClubSPlaybackDataResp",ClubSPlaybackDataResp)
end

--绑定手机或邮箱请求
function MsgClient.OnClubBindReq(sClientID, Data, nLen)
    local strProto = "ClubBindReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto,Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("_OnClubBindReq nUserId_%d",nUserId)

    local DbBindReq={}
    DbBindReq.nWay=tData.nWay			    --5:绑定手机 6:绑定邮箱
    DbBindReq.sAddrNew=tData.sAddrNew		--新手机或邮箱地址
    DbBindReq.sVeriCode=tData.sVeriCode	    --验证码(使用Logon.proto里的VeriCodeReq获取验证码)
    DbBindReq.sAddrOld=tData.sAddrOld		--旧手机或邮箱地址  (更换绑定时需要填，新绑定不用)
    DbBindReq.sPassWord=tData.sPassWord	    --登陆密码			(更换绑定时需要填，新绑定不用)
    DbBindReq.nUserId=nUserId		        --
    DbBindReq.nPurpose = tData.nPurpose
    MsgApi.SendToDB1Server("DbBindReq",DbBindReq,nUserId)
end

--DB服返回 绑定手机或邮箱 返回
function MsgClient.OnDbBindRsp(sReturnKey, Data, nLen)
    local strProto = "DbBindRsp"
    local tData =  MsgClient._CheckDb1Msg(strProto, Data, nLen)
    if not tData then
        return
    end

    MsgApi.SendToUser2(tData.nUserId,"ClubBindRsp",{nRlt=tData.nRlt})
end

--签到界面信息 请求
function MsgClient.OnClubSignInfoReq(sClientID, Data, nLen)
    local strProto = "ClubSignInfoReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto,Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("_OnClubSignInfoReq nUserId_%d",nUserId)

    MsgApi.SendToDB1Server("DbSignInfoReq",{nUserId=nUserId},nUserId)
end
--DB服返回 签到界面信息 返回
function MsgClient.OnDbSignInfoRsp(sReturnKey, Data, nLen)
    local strProto = "DbSignInfoRsp"
    local tData =  MsgClient._CheckDb1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    local arrAwards={}
    for _,item in ipairs(tData.arrAwards) do
        table.insert(arrAwards,{nDays=item.nDays,nAward=item.nAward})
    end
    local ClubSignInfoRsp={}
    ClubSignInfoRsp.arrAwards=arrAwards		             --1~7天的奖励,大于7的奖励使用第7天的
    ClubSignInfoRsp.nDaysCur=tData.nDaysCur		        --/当前天数,取值为1至无穷大
    ClubSignInfoRsp.isSign=tData.isSign			        --/当天是否已经签到 true:是,false:否
    ClubSignInfoRsp.nPlayCntCur=tData.nPlayCntCur	    --/当天手数
    ClubSignInfoRsp.nPlayCntMax=tData.nPlayCntMax	    --可领奖的手数
    
    MsgApi.SendToUser2(tData.nUserId,"ClubSignInfoRsp",ClubSignInfoRsp)
end


--签到 请求
function MsgClient.OnClubSignReq(sClientID, Data, nLen)
    local strProto = "ClubSignReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto,Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("_OnClubSignReq nUserId_%d",nUserId)

    MsgApi.SendToDB1Server("DbSignReq",{nUserId=nUserId},nUserId)
end
--DB服返回 签到 返回
function MsgClient.OnDbSignRsp(sReturnKey, Data, nLen)
    local strProto = "DbSignRsp"
    local tData =  MsgClient._CheckDb1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    if tData.nRlt==0 and tData.nAward>0 then
        local nSourceType = 10090 + 3
        PublicUserInfo.ChangeUserTreasure({nUserID=tData.nUserId, nItemID=1, nDel=tData.nAward, nSourceType=nSourceType,nRoomId=-1})
        RecordDbr.WithdrawLimit(tData.nUserId,tData.nAward,10+3)
    end
    MsgApi.SendToUser2(tData.nUserId,"ClubSignRsp",{nRlt=tData.nRlt,nAward=tData.nAward})
end

--领取绑定奖励 请求
function MsgClient.OnClubGetBindAwardReq(sClientID, Data, nLen)
    local strProto = "ClubGetBindAwardReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto,Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("_OnClubGetBindAwardReq nUserId_%d",nUserId)

    MsgApi.SendToDB1Server("DbGetBindAwardReq",{nUserId=nUserId},nUserId)
end

--DB服返回 领取绑定奖励 返回
function MsgClient.OnDbGetBindAwardRsp(sReturnKey, Data, nLen)
    local strProto = "DbGetBindAwardRsp"
    local tData =  MsgClient._CheckDb1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    if tData.nRlt==0 and tData.nAward>0 then
        local nSourceType = 10090 + 5
        PublicUserInfo.ChangeUserTreasure({nUserID=tData.nUserId, nItemID=1, nDel=tData.nAward, nSourceType=nSourceType,nRoomId=-1})
        RecordDbr.WithdrawLimit(tData.nUserId,tData.nAward,10+5)
    end
    MsgApi.SendToUser2(tData.nUserId,"ClubGetBindAwardRsp",{nRlt=tData.nRlt,nAward=tData.nAward})
end


--玩家红点数据请求
function MsgClient.OnClubSUserRedDotReq(sClientID, Data, nLen)
    local strProto = "ClubSUserRedDotReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSUserRedDotReq 玩家红点数据请求 nUserId_%d",nUserId)

    local ClubUserRedDotReq = {}
    ClubUserRedDotReq.nUserId = nUserId
    MsgApi.SendToDBServer("ClubUserRedDotReq",ClubUserRedDotReq,nUserId)
end

--DB服返回 玩家红点数据 返回
function MsgClient.OnDBClubUserRedDotRsp(sReturnKey, Data, nLen)
    local strProto = "ClubUserRedDotRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrRedot = {}
    for _,v in pairs(tData.arrRedot) do
        if v.nType and v.nType>0 then
            local t = {}
            t.nType = v.nType
            t.nCount = v.nCount
            table.insert(arrRedot,t)
        end
    end

    Base.Log("_OnDBClubUserRedDotRsp nUserId_%d arrRedot_%s",tData.nUserId,Cjson.encode(arrRedot))

    local ClubSUserRedDotResp = {}
    ClubSUserRedDotResp.arrRedot = arrRedot
    MsgApi.SendToUser(tData.nUserId,"ClubSUserRedDotResp",ClubSUserRedDotResp)
end

--获取牌桌的牌局id请求
function MsgClient.OnClubSGetTablePaiJuIdReq(sClientID, Data, nLen)
    local strProto = "ClubSGetTablePaiJuIdReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetTablePaiJuIdReq 获取牌桌的牌局id请求 nUserId_%d sTableId_%s",nUserId,tData.sTableId)

    local ClubGetTablePaiJuIdReq = {}
    ClubGetTablePaiJuIdReq.nUserId = nUserId
    ClubGetTablePaiJuIdReq.sTableId = tData.sTableId
    ClubGetTablePaiJuIdReq.nCnt = tData.nCnt or 30
    ClubGetTablePaiJuIdReq.nPage = tData.nPage or 0
    MsgApi.SendToDBServer("ClubGetTablePaiJuIdReq",ClubGetTablePaiJuIdReq,nUserId)
end

--DB服返回 获取牌桌的牌局id 返回
function MsgClient.OnDBClubGetTablePaiJuIdResp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTablePaiJuIdResp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end
    local arrPaiJuID = {}
    for _,v in pairs(tData.arrPaiJuID) do
        if v.nId and v.nId>0 then
            local t = {}
            t.nId = v.nId
            t.sPaiJuID = v.sPaiJuID
            table.insert(arrPaiJuID,t)
        end
    end

    Base.Log("_OnDBClubGetTablePaiJuIdResp nUserId_%d #arrPaiJuID_%d sTableId_%s nGameId_%d nAllCnt_%d nNowPage_%d nAllPage_%d",
    tData.nUserId,#arrPaiJuID,tData.sTableId,tData.nGameId,tData.nAllCnt,tData.nNowPage,tData.nAllPage)

    local ClubSGetTablePaiJuIdResp = {}
    ClubSGetTablePaiJuIdResp.sTableId = tData.sTableId
    ClubSGetTablePaiJuIdResp.nGameId = tData.nGameId
    ClubSGetTablePaiJuIdResp.arrPaiJuID = arrPaiJuID
    ClubSGetTablePaiJuIdResp.nAllCnt = tData.nAllCnt
    ClubSGetTablePaiJuIdResp.nNowPage = tData.nNowPage
    ClubSGetTablePaiJuIdResp.nAllPage = tData.nAllPage
    MsgApi.SendToUser(tData.nUserId,"ClubSGetTablePaiJuIdResp",ClubSGetTablePaiJuIdResp)
end

--设置安全密码开启关闭请求
function MsgClient.OnClubSSetSafePassWardOpenReq(sClientID, Data, nLen)
    local strProto = "ClubSSetSafePassWardOpenReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSSetSafePassWardOpenReq 设置安全密码开启关闭请求 nUserId_%d isOpen_%s",nUserId,tostring(tData.isOpen))

    local nOpen = 0
    if tData.isOpen==true then
        nOpen = 1
    end

    local ClubSetSafePassWardOpenReq = {}
    ClubSetSafePassWardOpenReq.nUserId = nUserId
    ClubSetSafePassWardOpenReq.nOpen = nOpen
    MsgApi.SendToDBServer("ClubSetSafePassWardOpenReq",ClubSetSafePassWardOpenReq,nUserId)
end

--DB服返回 设置安全密码开启关闭 返回
function MsgClient.OnDBClubSetSafePassWardOpenRsp(sReturnKey, Data, nLen)
    local strProto = "ClubSetSafePassWardOpenRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubSetSafePassWardOpenRsp nUserId_%d nRlt_%d isNeedSet_%s nOpen_%d",
    tData.nUserId,tData.nRlt,tostring(tData.isNeedSet),tData.nOpen)

    local isOpen = false
    if tData.nOpen==1 then
        isOpen = true
    end

    if tData.nRlt==0 and tData.isNeedSet==false then
        local tChangeInfo = {nUserID=tData.nUserId,nOpenProtection=tData.nOpen}
        PublicUserInfo.UpdateUserData(tChangeInfo)
        MsgApi.SendUserInfoChangeToGameServer(tData.nUserId,tChangeInfo)
    end

    local ClubSSetSafePassWardOpenResp = {}
    ClubSSetSafePassWardOpenResp.nRlt = tData.nRlt
    ClubSSetSafePassWardOpenResp.isNeedSet = tData.isNeedSet
    ClubSSetSafePassWardOpenResp.isOpen = isOpen
    MsgApi.SendToUser(tData.nUserId,"ClubSSetSafePassWardOpenResp",ClubSSetSafePassWardOpenResp)
end

--获取俱乐部相关配置请求
function MsgClient.OnClubSGetClubConfigReq(sClientID, Data, nLen)
    local strProto = "ClubSGetClubConfigReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetClubConfigReq 获取俱乐部相关配置请求 nUserId:%d",nUserId)

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSGetClubConfigReq 玩家信息不存在 nUserId:%d",nUserId)
        return
    end
    local nGroupId = tUser.nGroupId or -1

    local tClubConfig = {}
    -- tClubConfig.tChangeName = SlaveData.arrChangeNameConsume[nGroupId] or Define.tChangeName
    -- tClubConfig.tOpenTable = SlaveData.arrOpenTableConsume[nGroupId] or Define.tOpenTableConsume
    -- tClubConfig.arrLevel = SlaveData.arrLevelConfig[nGroupId] or Define.arrLevel
    tClubConfig.transferOpen = {open = 0}
    local config = SlaveData.GetConfig(GlobalConfigKey.TransferOpen)
    if config then
        tClubConfig.transferOpen.open = tonumber(config.open)
    end
    tClubConfig.costConfigs = {}
    local config1 = SlaveData.GetConfig(GlobalConfigKey.CostConfigs)
    if config1 then
        tClubConfig.costConfigs = config1
    end
    tClubConfig.linkConfigs = {}
    local config2 = SlaveData.GetConfig(GlobalConfigKey.LinkConfigs)
    if config2 then
        tClubConfig.linkConfigs = config2
    end

    local ClubSGetClubConfigResp = {}
    ClubSGetClubConfigResp.sClubConfig = Cjson.encode(tClubConfig)
    MsgApi.SendToUser(nUserId,"ClubSGetClubConfigResp",ClubSGetClubConfigResp)
end

--发送短信验证码请求
function MsgClient.OnClubSSendCodeReq(sClientID, Data, nLen)
    local strProto = "ClubSSendCodeReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSSendCodeReq 发送短信验证码请求 nUserId:%d sPhone_%s",nUserId,tData.sPhone)

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSGetClubConfigReq 玩家信息不存在 nUserId:%d",nUserId)
        return
    end
    local nGroupId = tUser.nGroupId or -1

    local ClubSSendCodeResp = {}
    ClubSSendCodeResp.nRlt = PubErrCode.SendCode.Success

    if tonumber(tData.sPhone)==nil then
        Base.Log("_OnClubSSendCodeReq 手机号码错误")
        ClubSSendCodeResp.nRlt = PubErrCode.SendCode.PhoneErr
        MsgApi.SendToClient(sClientID,"ClubSSendCodeResp",ClubSSendCodeResp)
        return
    end

    if PublicRedis.GetSendCodeStatus(nUserId)=="1" then
        Base.Log("_OnClubSSendCodeReq 60s内有发送过")
        ClubSSendCodeResp.nRlt = PubErrCode.SendCode.TooFrequently
        MsgApi.SendToClient(sClientID,"ClubSSendCodeResp",ClubSSendCodeResp)
        return
    end

    local isSuccee = MsgApi.SendGetMsgCode(nUserId,tData.sPhone,nGroupId) --向web请求发送短信验证码
    if not isSuccee then
        Base.Log("_OnClubSSendCodeReq 发送到web服失败")
        ClubSSendCodeResp.nRlt = PubErrCode.SendCode.OverTime
        MsgApi.SendToClient(sClientID,"ClubSSendCodeResp",ClubSSendCodeResp)
        return
    end

    PublicRedis.SetSendCodeStatus(nUserId,Define.nSendCodeOverTime) ----设置玩家发送短信验证码的状态

    MsgApi.SendToClient(sClientID,"ClubSSendCodeResp",ClubSSendCodeResp)
end

--短信验证码校验请求
function MsgClient.OnClubSCodeCheckReq(sClientID, Data, nLen)
    local strProto = "ClubSCodeCheckReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSCodeCheckReq 短信验证码校验请求 nUserId:%d sCode_%s",nUserId,tData.sCode)

    local ClubSCodeCheckResp = {}
    ClubSCodeCheckResp.nRlt = PubErrCode.CodeCheck.Success

    local sMsgCode = PublicRedis.GetMsgCode(nUserId)
    if not sMsgCode then
        Base.Log("_OnClubSCodeCheckReq 验证码已过期或者不存在")
        ClubSCodeCheckResp.nRlt = PubErrCode.CodeCheck.CodeErr
        MsgApi.SendToClient(sClientID,"ClubSCodeCheckResp",ClubSCodeCheckResp)
        return
    end

    if sMsgCode~=tData.sCode then
        Base.Log("_OnClubSCodeCheckReq 验证码不正确 sMsgCode_%s sCode_%s",sMsgCode,tData.sCode)
        ClubSCodeCheckResp.nRlt = PubErrCode.CodeCheck.CodeErr
        MsgApi.SendToClient(sClientID,"ClubSCodeCheckResp",ClubSCodeCheckResp)
        return
    end

    PublicRedis.DelMsgCode(nUserId) --删除玩家短信验证码

    MsgApi.SendToClient(sClientID,"ClubSCodeCheckResp",ClubSCodeCheckResp)
end

-- --安全密码校验请求
-- function MsgClient.OnClubSSafePassWardCheckReq(sClientID, Data, nLen)
--     local strProto = "ClubSSafePassWardCheckReq"
--     local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
--     if not isCheckPass then
--         return
--     end

--     Base.Log("_OnClubSSafePassWardCheckReq 安全密码校验请求 nUserId:%d sSafePassWard_%s sKey_%s",nUserId,tData.sSafePassWard,tData.sKey or "")

    -- local nResult = PublicUserInfo.CheckSafePassWard(nUserId,tData.sSafePassWard)

--     Base.Log("_OnClubSSafePassWardCheckReq 安全密码校验结果 nResult:%d(0:校验失败 1:校验成功)",nResult)

--     PublicUserInfo.SetCheckSafePassWardResult(nUserId,nResult)

--     local nRlt = (nResult==1 and 0) or 1

--     local ClubSSafePassWardCheckResp = {}
--     ClubSSafePassWardCheckResp.nRlt = nRlt
--     ClubSSafePassWardCheckResp.sKey = tData.sKey
--     MsgApi.SendToClient(sClientID,"ClubSSafePassWardCheckResp",ClubSSafePassWardCheckResp)
-- end

--安全密码校验请求
function MsgClient.OnClubSSafePassWardCheckReq(sClientID, Data, nLen)
    local strProto = "ClubSSafePassWardCheckReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSSafePassWardCheckReq 安全密码校验请求 nUserId:%d sSafePassWard_%s sKey_%s",nUserId,tData.sSafePassWard,tData.sKey or "")

    local ClubSearchSecuPwdReq = {}
    ClubSearchSecuPwdReq.nUserId = nUserId
    ClubSearchSecuPwdReq.SecuPwd = tData.sSafePassWard
    ClubSearchSecuPwdReq.sKey = tData.sKey
    MsgApi.SendToDBServer("ClubSearchSecuPwdReq",ClubSearchSecuPwdReq,nUserId)
end

--DB服安全密码验证返回
function MsgClient.OnDBClubCSearchSecuPwdRsp(sReturnKey, Data, nLen)
    local strProto = "ClubSearchSecuPwdRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("ClubSearchSecuPwdRsp nRlt_%d sKey_%s",tData.nRlt,tData.sKey)

    local nRlt = (tData.nRlt==1 and 0) or 1

    PublicUserInfo.SetCheckSafePassWardResult(tData.nUserId,nRlt)

    local ClubSSafePassWardCheckResp = {}
    ClubSSafePassWardCheckResp.nRlt = tData.nRlt
    ClubSSafePassWardCheckResp.sKey = tData.sKey
    MsgApi.SendToUser(tData.nUserId,"ClubSSafePassWardCheckResp",ClubSSafePassWardCheckResp)
end

--是否需要安全码校验请求
function MsgClient.OnClubSNeedCheckSafePassWardReq(sClientID, Data, nLen)
    local strProto = "ClubSNeedCheckSafePassWardReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSNeedCheckSafePassWardReq 是否需要安全码校验请求 nUserId:%d sKey_%s",nUserId,tData.sKey or "")

    local isNeedCheck = PublicUserInfo.IsNeedCheckSafePassWard(nUserId)

    Base.Log("_OnClubSSafePassWardCheckReq 是否需要安全码校验请求 isNeedCheck:%s",tostring(isNeedCheck))

    local ClubSNeedCheckSafePassWardResp = {}
    ClubSNeedCheckSafePassWardResp.isNeedCheck = isNeedCheck
    ClubSNeedCheckSafePassWardResp.sKey = tData.sKey
    MsgApi.SendToClient(sClientID,"ClubSNeedCheckSafePassWardResp",ClubSNeedCheckSafePassWardResp)
end

--输入兑换码请求
function MsgClient.ClubSInputRedeemCodeReq(sClientID, Data, nLen)
    local strProto = "ClubSInputRedeemCodeReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_ClubSInputRedeemCodeReq 输入兑换码请求 nUserId:%d sRedeemCode_%s",nUserId,tData.sRedeemCode)
    
    local ClubSInputRedeemCodeRsp = {
        nRlt = PubErrCode.InputRedeemCode.Success,
    }

    local nLastReqTime = SlaveData.tDBOprateWaitting.arrInputRedeemCode[nUserId]
    if nLastReqTime then
        local nNowTime = os.time()
        if nNowTime-nLastReqTime<Define.nOverTime then
            Base.Log("_ClubSInputRedeemCodeReq 请求过于频繁，等待上一个请求结束")
            ClubSInputRedeemCodeRsp.nRlt = PubErrCode.InputRedeemCode.WaitDBReturn
            MsgApi.SendToClient(sClientID,"ClubSInputRedeemCodeRsp",ClubSInputRedeemCodeRsp)
            return
        end
    end

     --兑换码长度校验和格式校验
     if #tData.sRedeemCode ~= 10 or not PublicApi.Check_StringIsNormal(tData.sRedeemCode) then
        Base.Log("_ClubSInputRedeemCodeReq 格式错误  Err")
        ClubSInputRedeemCodeRsp.nRlt = PubErrCode.InputRedeemCode.NotSuit
        MsgApi.SendToClient(sClientID,"ClubSInputRedeemCodeRsp",ClubSInputRedeemCodeRsp)
        return
    end
    
    SlaveData.tDBOprateWaitting.arrInputRedeemCode[nUserId] = os.time()

    local ClubInputRedeemCodeReq = {}
    ClubInputRedeemCodeReq.nUserId = nUserId
    ClubInputRedeemCodeReq.sRedeemCode = tData.sRedeemCode
    MsgApi.SendToDBServer("ClubInputRedeemCodeReq",ClubInputRedeemCodeReq,nUserId)
end

--DB服返回 输入兑换码 返回
function MsgClient.OnDBClubInputRedeemCodeRsp(sReturnKey, Data, nLen)
    local strProto = "ClubInputRedeemCodeRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("ClubInputRedeemCodeRsp nUserId_%d nRlt_%d sExData_%s",tData.nUserId,tData.nRlt,tData.sExData)

    if tData.nRlt == 0 then
        local tExData = {}
        if #tData.sExData > 0 then
            tExData = Cjson.decode(tData.sExData)
        end
        if tExData.nGiftBagId then
            local arrGiftBag = Store.GetGiftBagCfg(tExData.nGiftBagId)
            if not arrGiftBag then 
                local SendSMS = string.format("ClubInputRedeemCodeRsp nUserId_%d nGiftBagId_%d  arrGiftBag is nil",tData.nUserId,tExData.nGiftBagId) 	
                Base._OnMonitorInfo(SendSMS)   
                Base.Log(SendSMS)  	     		
                return 
            end 
            -- 下发礼包 
            Base.Log("ClubInputRedeemCodeRsp  下发礼包 nUserId_%d nGiftBagId_%d  ",tData.nUserId,tExData.nGiftBagId)  
            for _, v in pairs(arrGiftBag) do
                if v and v.nItemId and v.nItemId > 0 and v.nCount > 0 then 
                    local nSourceType = 200001  -- 兑换码充值
                    Base.Log("ClubInputRedeemCodeRsp  兑换码充值 nUserId_%d nGiftBagId_%d nItemId_%d nCount_%d ",tData.nUserId,tExData.nGiftBagId,v.nItemId,v.nCount)
                    PublicUserInfo.ChangeUserTreasure({nUserID =tData.nUserId,nItemID=v.nItemId,nDel= PublicApi.Floor_2(v.nCount),nSourceType=nSourceType})
                end 
            end
        end
    end
    
    local ClubSInputRedeemCodeRsp = {}
    ClubSInputRedeemCodeRsp.nRlt = tData.nRlt
    ClubSInputRedeemCodeRsp.sExData = tData.sExData or ""
    MsgApi.SendToUser(tData.nUserId,"ClubSInputRedeemCodeRsp",ClubSInputRedeemCodeRsp)

    SlaveData.tDBOprateWaitting.arrInputRedeemCode[tData.nUserId] = nil
end

--获取玩家个人牌桌记录请求
function MsgClient.OnClubSGetPersonTableRecordReq(sClientID, Data, nLen)
    Base.Log("ClubSGetPersonTableRecordReq 开始")
    local strProto = "ClubSGetPersonTableRecordReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetPersonTableRecordReq 获取玩家个人牌桌记录请求 nUserId_%d nIdOfStart_%d nCnt_%d nGameId_%d nGoldType_%d nClubId_%d",
    nUserId,tData.nIdOfStart,tData.nCnt,tData.nGameId,tData.nGoldType,tData.nClubId)

    local nIdOfStart = tData.nIdOfStart
    if nIdOfStart < 0 then
        nIdOfStart = 0
    end
    local nCnt = tData.nCnt
    if nCnt <= 0 then
        nCnt = 0
    end
    if nCnt > 15 then
        nCnt = 15
    end
    local nGoldType = tData.nGoldType
    if nGoldType ~= 1 and nGoldType ~= 2 then
        nGoldType = 1
    end

    local ClubGetPersonTableRecordReq = {}
    ClubGetPersonTableRecordReq.nUserId = nUserId
    ClubGetPersonTableRecordReq.nIdOfStart = nIdOfStart
    ClubGetPersonTableRecordReq.nCnt = nCnt
    ClubGetPersonTableRecordReq.nGameId = tData.nGameId
    ClubGetPersonTableRecordReq.nGoldType = nGoldType
    ClubGetPersonTableRecordReq.nClubId = tData.nClubId
    MsgApi.SendToDBServer("ClubGetPersonTableRecordReq",ClubGetPersonTableRecordReq,nUserId)
end

--DB服返回 获取玩家个人牌桌记录 返回
function MsgClient.OnDBClubGetPersonTableRecordRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetPersonTableRecordRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrRecords = {}
    local tStatics = nil

    for k,v in pairs(tData.arrRecords) do
        if v.nId and v.nId>0 then
            local t = {}
            t.nId = v.nId
            t.nLiveUserID = v.nLiveUserID
            t.sFaceId = v.sFaceId
            t.nWinLose = v.nWinLose
            t.sTime = v.sTime
            t.sTableName = ""
            t.nKeepTime = -1
            t.sExData = ""
            t.sTableId = v.sTableId

            local isSuccee,tTableInfo = pcall(Cjson.decode,v.sTableInfo)
            if isSuccee then
                t.sTableName = tTableInfo.sTableName or ""
                t.nKeepTime = tTableInfo.nKeepTime or 0

                local tExData = {}
                tExData.isAOF = tTableInfo.isAOF or false
                tExData.isInsure = tTableInfo.nInsureMode or 0
                tExData.nSB = tTableInfo.nSmallBlind
                tExData.nBB = tTableInfo.nBigBlind
                t.sExData = Cjson.encode(tExData)
            end

            table.insert(arrRecords,t)
        end
    end

    if tData.tStatics then
        tStatics = {}
        tStatics.nPaiJuCnt = tData.tStatics.nPaiJuCnt
        tStatics.nHandCnt = tData.tStatics.nPlayCount
        tStatics.nWinLose = tData.tStatics.nProfitSum

        Base.Log("_OnDBClubGetPersonTableRecordRsp %d,%d,%d",tData.tStatics.nInPoolCount,tData.tStatics.nRaiseCountBFlop,tData.tStatics.nAllInAndWinCount)

        if tData.tStatics.nPlayCount>0 then
            tStatics.nInpoolRate = PublicApi.Floor_n(100*tData.tStatics.nInPoolCount/tData.tStatics.nPlayCount,1)
            tStatics.nBFlopRaiseRate = PublicApi.Floor_n(100*tData.tStatics.nRaiseCountBFlop/tData.tStatics.nPlayCount,1)
            tStatics.nAllInAndWinRate = PublicApi.Floor_n(100*tData.tStatics.nAllInAndWinCount/tData.tStatics.nPlayCount,1)
        else
            tStatics.nInpoolRate = 0
            tStatics.nBFlopRaiseRate = 0
            tStatics.nAllInAndWinRate = 0
        end
        Base.Log("_OnDBClubGetPersonTableRecordRsp tStatics_%s",Cjson.encode(tStatics))
    end

    Base.Log("_OnDBClubGetPersonTableRecordRsp nUserId_%d nGameId_%d nGoldType_%d nClubId_%d #arrRecords_%d",
    tData.nUserId,tData.nGameId,tData.nGoldType,tData.nClubId,#arrRecords)


    local ClubSGetPersonTableRecordRsp = {}
    ClubSGetPersonTableRecordRsp.arrRecords = arrRecords
    ClubSGetPersonTableRecordRsp.tStatics = tStatics
    ClubSGetPersonTableRecordRsp.nGameId = tData.nGameId
    ClubSGetPersonTableRecordRsp.nGoldType = tData.nGoldType
    ClubSGetPersonTableRecordRsp.nClubId = tData.nClubId
    ClubSGetPersonTableRecordRsp.nIdOfStart = tData.nIdOfStart
    MsgApi.SendToUser(tData.nUserId,"ClubSGetPersonTableRecordRsp",ClubSGetPersonTableRecordRsp)
end

--获取玩家个人牌桌记录2请求(大厅永久牌桌)
function MsgClient.OnClubSGetPersonTableRecord2Req(sClientID, Data, nLen)
    Base.Log("ClubSGetPersonTableRecord2Req 开始")
    local strProto = "ClubSGetPersonTableRecord2Req"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    tData.nClubId = 0
    Base.Log("ClubSGetPersonTableRecord2Req 开始 nClubId:%d",tData.nClubId)
    if tData.nClubId == 0 then
        --大厅
        local tUser = UserManager.GetUserInfo(nUserId)
        if not tUser then
            Base.Log("ClubSGetPersonTableRecord2Req 玩家信息不存在")
            return
        end
        local nGroupId = tonumber(tUser.nGroupId) or -1
        tData.nClubId = nGroupId
        Base.Log("ClubSGetPersonTableRecord2Req 获取玩家个人牌桌记录请求 nClubId:%d",tData.nClubId)
    end

    --俱乐部不存在
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("ClubSGetPersonTableRecord2Req 俱乐部不存在")
        return
    end

    Base.Log("_OnClubSGetPersonTableRecord2Req 获取玩家个人牌桌记录请求 nUserId_%d nIdOfStart_%d nCnt_%d nGameId_%d nGoldType_%d nClubId_%d nDay_%d nStartTime_%s nEndTime_%s",
    nUserId,tData.nIdOfStart,tData.nCnt,tData.nGameId,tData.nGoldType,tData.nClubId,tData.nDay,tData.nStartTime,tData.nEndTime)

    local nIdOfStart = tData.nIdOfStart
    if nIdOfStart < 0 then
        nIdOfStart = 0
    end
    local nCnt = tData.nCnt
    if nCnt <= 0 then
        nCnt = 0
    end
    if nCnt > 15 then
        nCnt = 15
    end
    local nGoldType = tData.nGoldType
    if nGoldType ~= 1 and nGoldType ~= 2 then
        nGoldType = 1
    end
    -- local nDay = tData.nDay
    -- if nDay < 0 then
    --     nDay = 0
    -- end

    local ClubGetPersonTableRecord2Req = {}
    ClubGetPersonTableRecord2Req.nUserId = nUserId
    ClubGetPersonTableRecord2Req.nIdOfStart = nIdOfStart
    ClubGetPersonTableRecord2Req.nCnt = nCnt
    ClubGetPersonTableRecord2Req.nGameId = tData.nGameId
    ClubGetPersonTableRecord2Req.nGoldType = nGoldType
    ClubGetPersonTableRecord2Req.nClubId = tData.nClubId
    ClubGetPersonTableRecord2Req.nDay = 0
    ClubGetPersonTableRecord2Req.nStartTime = tData.nStartTime
    ClubGetPersonTableRecord2Req.nEndTime = tData.nEndTime
    MsgApi.SendToDBServer("ClubGetPersonTableRecord2Req",ClubGetPersonTableRecord2Req,nUserId)
end

--DB服返回 获取玩家个人牌桌记录2 返回 (大厅永久牌桌)
function MsgClient.OnDBClubGetPersonTableRecord2Rsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetPersonTableRecord2Rsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrRecords = {}
    local tStatics = nil

    for k,v in pairs(tData.arrRecords) do
        if v.nId and v.nId>0 then
            local t = {}
            t.nId = v.nId
            t.nLiveUserID = v.nLiveUserID
            t.sFaceId = v.sFaceId
            t.nWinLose = v.nWinLose
            t.sTime = v.sTime
            t.sTableName = ""
            t.nKeepTime = -1
            t.sExData = ""
            t.sTableId = v.sTableId
            t.nTableIndex = v.nTableIndex
            t.nFaceIdList = v.nFaceIdList or ""
            -- local t = {}
            -- for s in string.gmatch(v.nFaceIdList or "", "[^,]+") do
            --     table.insert(t, s)
            -- end
            -- if #t>0 then
            --     local jsonStr = Cjson.encode(t)
            --     t.nFaceIdList = jsonStr
            -- end
            
            local isSuccee,tTableInfo = pcall(Cjson.decode,v.sTableInfo)
            if isSuccee then
                t.sTableName = tTableInfo.sTableName or ""
                t.nKeepTime = tTableInfo.nKeepTime or 0

                local tExData = {}
                tExData.isAOF = tTableInfo.isAOF or false
                tExData.isInsure = tTableInfo.nInsureMode or 0
                tExData.nSB = tTableInfo.nSmallBlind or 0
                tExData.nBB = tTableInfo.nBigBlind or 0
                tExData.nBaseScore = tTableInfo.nBaseScore or 0
                tExData.nZhuaTou = tTableInfo.nZhuaTou or 0
                tExData.nPreAnte = tTableInfo.nPreAnte or 0
                tExData.preAnteOdd = tTableInfo.preAnteOdd or 0
                t.sExData = Cjson.encode(tExData)
            end
            table.insert(arrRecords,t)
        end
    end

    if tData.tStatics then
        tStatics = {}
        tStatics.nPaiJuCnt = tData.tStatics.nPaiJuCnt
        tStatics.nHandCnt = tData.tStatics.nPlayCount
        tStatics.nWinLose = tData.tStatics.nProfitSum
        Base.Log("_OnDBClubGetPersonTableRecord2Rsp %d,%d,%f,%d",tData.tStatics.nPaiJuCnt,tData.tStatics.nPlayCount,tData.tStatics.nProfitSum,tData.tStatics.nInPoolCount)
        if tData.tStatics.nPlayCount>0 then
            tStatics.nInpoolRate = PublicApi.Floor_n(100*tData.tStatics.nInPoolCount/tData.tStatics.nPlayCount,1)
            tStatics.nBFlopRaiseRate = PublicApi.Floor_n(100*tData.tStatics.nRaiseCountBFlop/tData.tStatics.nPlayCount,1)
            -- tStatics.nAllInAndWinRate = PublicApi.Floor_n(100*tData.tStatics.nAllInAndWinCount/tData.tStatics.nPlayCount,1)
            tStatics.nWinRate = PublicApi.Floor_n(100*tData.tStatics.nWinCount/tData.tStatics.nPlayCount,1)
            tStatics.nQiPaiRate = PublicApi.Floor_n(100*tData.tStatics.nQiPaiCount/tData.tStatics.nPlayCount,1)
            tStatics.nHandProfit = PublicApi.Floor_n(tData.tStatics.nHandProfit/tData.tStatics.nPlayCount,2)
        else
            tStatics.nInpoolRate = 0
            tStatics.nBFlopRaiseRate = 0
            tStatics.nAllInAndWinRate = 0
            tStatics.nWinRate = 0
            tStatics.nQiPaiRate = 0
            tStatics.nHandProfit = 0
        end
        tStatics.nAllInAndWinRate = 0
        if tData.tStatics.nAllInCount > 0 then
            tStatics.nAllInAndWinRate = PublicApi.Floor_n(100*tData.tStatics.nAllInAndWinCount/tData.tStatics.nAllInCount,1)
        end
        Base.Log("_OnDBClubGetPersonTableRecord2Rsp tStatics_%s",Cjson.encode(tStatics))
    end

    Base.Log("_OnDBClubGetPersonTableRecord2Rsp nUserId_%d nGameId_%d nGoldType_%d nClubId_%d #arrRecords_%d",
    tData.nUserId,tData.nGameId,tData.nGoldType,tData.nClubId,#arrRecords)


    local ClubSGetPersonTableRecord2Rsp = {}
    ClubSGetPersonTableRecord2Rsp.arrRecords = arrRecords
    ClubSGetPersonTableRecord2Rsp.tStatics = tStatics
    ClubSGetPersonTableRecord2Rsp.nGameId = tData.nGameId
    ClubSGetPersonTableRecord2Rsp.nGoldType = tData.nGoldType
    ClubSGetPersonTableRecord2Rsp.nClubId = tData.nClubId
    ClubSGetPersonTableRecord2Rsp.nIdOfStart = tData.nIdOfStart
    ClubSGetPersonTableRecord2Rsp.nDay = tData.nDay
    ClubSGetPersonTableRecord2Rsp.nStartTime = tData.nStartTime
    ClubSGetPersonTableRecord2Rsp.nEndTime = tData.nEndTime
    MsgApi.SendToUser(tData.nUserId,"ClubSGetPersonTableRecord2Rsp",ClubSGetPersonTableRecord2Rsp)
end

--获取牌桌详细记录请求
function MsgClient.OnClubSGetTableDetailReq(sClientID, Data, nLen)
    local strProto = "ClubSGetTableDetailReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetTableDetailReq 获取牌桌详细记录请求 nUserId_%d nGameId_%d sTableId_%s",nUserId,tData.nGameId,tData.sTableId)

    local ClubGetTableDetailReq = {}
    ClubGetTableDetailReq.nUserId = nUserId
    ClubGetTableDetailReq.nGameId = tData.nGameId
    ClubGetTableDetailReq.sTableId = tData.sTableId
    MsgApi.SendToDBServer("ClubGetTableDetailReq",ClubGetTableDetailReq,nUserId)
end

--DB服返回 获取牌桌详细记录 返回
function MsgClient.OnDBClubGetTableDetailRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTableDetailRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubGetTableDetailRsp nUserId_%d nGameId_%d sTableId_%s",tData.nUserId,tData.nGameId,tData.sTableId)

    local tTexas = nil
    if tData.tTexas then
        --房主
        local tLiver = {}
        tLiver.nUserId = tData.tTexas.tLiver.nUserId
        tLiver.sFaceId =  tData.tTexas.tLiver.sFaceId
        tLiver.sName =  tData.tTexas.tLiver.sName
        --MVP
        local tMVPUser = {}
        tMVPUser.nUserId = tData.tTexas.tMVPUser.nUserId
        tMVPUser.sFaceId =  tData.tTexas.tMVPUser.sFaceId
        tMVPUser.sName =  tData.tTexas.tMVPUser.sName
        --土豪
        local tTHUser = {}
        tTHUser.nUserId = tData.tTexas.tTHUser.nUserId
        tTHUser.sFaceId =  tData.tTexas.tTHUser.sFaceId
        tTHUser.sName =  tData.tTexas.tTHUser.sName
        --大鱼
        local tDYUser = {}
        tDYUser.nUserId = tData.tTexas.tDYUser.nUserId
        tDYUser.sFaceId =  tData.tTexas.tDYUser.sFaceId
        tDYUser.sName =  tData.tTexas.tDYUser.sName

        tTexas = {}
        tTexas.tLiver = tLiver
        tTexas.tMVPUser = tMVPUser
        tTexas.tTHUser = tTHUser
        tTexas.tDYUser = tDYUser
        tTexas.nHandCnt = tData.tTexas.nHandCnt
        tTexas.nTakeIn = tData.tTexas.nTakeIn
        tTexas.nJournalAccount = tData.tTexas.nJournalAccount
        tTexas.nMaxPool = tData.tTexas.nMaxPool
        tTexas.nGameId = tData.tTexas.nGameId
        tTexas.sTime = tData.tTexas.sTime
        tTexas.nKeepTime = tData.tTexas.nKeepTime
        tTexas.nInsurancePool = tData.tTexas.nInsurancePool
        tTexas.nSmallBlind = 0
        tTexas.nBigBlind = 0
        tTexas.sTableName = ""
        tTexas.nSumBet = tData.tTexas.nSumBet or 0
        tTexas.nZhuaTou = 0
        tTexas.nPreAnte = 0
        tTexas.nBaseScore = 0

        local isSuccee,tTableInfo = pcall(Cjson.decode,tData.tTexas.sTableInfo)
        if isSuccee then
            tTexas.sTableName = tTableInfo.sTableName or ""
            tTexas.nSmallBlind = tTableInfo.nSmallBlind or 0
            tTexas.nBigBlind = tTableInfo.nBigBlind or 0
            tTexas.nBaseScore = tTableInfo.nBaseScore or 0
            tTexas.nZhuaTou = tTableInfo.nZhuaTou or 0
            tTexas.nPreAnte = tTableInfo.nPreAnte or 0
            tTexas.preAnteOdd = tTableInfo.preAnteOdd or 0
        end
    end

    local ClubSGetTableDetailRsp = {}
    ClubSGetTableDetailRsp.tTexas = tTexas
    ClubSGetTableDetailRsp.nGameId = tData.nGameId
    ClubSGetTableDetailRsp.sTableId = tData.sTableId
    MsgApi.SendToUser(tData.nUserId,"ClubSGetTableDetailRsp",ClubSGetTableDetailRsp)
end

--获取牌桌详细记录2请求(大厅永久牌桌)
function MsgClient.OnClubSGetTableDetail2Req(sClientID, Data, nLen)
    local strProto = "ClubSGetTableDetail2Req"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetTableDetail2Req 获取牌桌详细记录请求 nUserId_%d nGameId_%d sTableName_%s nTableIndex_%d",nUserId,tData.nGameId,tData.sTableName,tData.nTableIndex)

    local ClubGetTableDetail2Req = {}
    ClubGetTableDetail2Req.nUserId = nUserId
    ClubGetTableDetail2Req.nGameId = tData.nGameId
    ClubGetTableDetail2Req.sTableName = tData.sTableName
    ClubGetTableDetail2Req.nTableIndex = tData.nTableIndex
    MsgApi.SendToDBServer("ClubGetTableDetail2Req",ClubGetTableDetail2Req,nUserId)
end

--DB服返回 获取牌桌详细记录2 返回(大厅永久牌桌)
function MsgClient.OnDBClubGetTableDetail2Rsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTableDetail2Rsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubGetTableDetail2Rsp nUserId_%d nGameId_%d sTableName_%s",tData.nUserId,tData.nGameId,tData.sTableName)

    local tTexas = nil
    if tData.tTexas then
        --房主
        local tLiver = {}
        tLiver.nUserId = tData.tTexas.tLiver.nUserId
        tLiver.sFaceId =  tData.tTexas.tLiver.sFaceId
        tLiver.sName =  tData.tTexas.tLiver.sName
        --MVP
        local tMVPUser = {}
        tMVPUser.nUserId = tData.tTexas.tMVPUser.nUserId
        tMVPUser.sFaceId =  tData.tTexas.tMVPUser.sFaceId
        tMVPUser.sName =  tData.tTexas.tMVPUser.sName
        --土豪
        local tTHUser = {}
        tTHUser.nUserId = tData.tTexas.tTHUser.nUserId
        tTHUser.sFaceId =  tData.tTexas.tTHUser.sFaceId
        tTHUser.sName =  tData.tTexas.tTHUser.sName
        --大鱼
        local tDYUser = {}
        tDYUser.nUserId = tData.tTexas.tDYUser.nUserId
        tDYUser.sFaceId =  tData.tTexas.tDYUser.sFaceId
        tDYUser.sName =  tData.tTexas.tDYUser.sName

        tTexas = {}
        tTexas.tLiver = tLiver
        tTexas.tMVPUser = tMVPUser
        tTexas.tTHUser = tTHUser
        tTexas.tDYUser = tDYUser
        tTexas.nHandCnt = tData.tTexas.nHandCnt
        tTexas.nTakeIn = tData.tTexas.nTakeIn
        tTexas.nJournalAccount = tData.tTexas.nJournalAccount
        tTexas.nMaxPool = tData.tTexas.nMaxPool
        tTexas.nGameId = tData.tTexas.nGameId
        tTexas.sTime = tData.tTexas.sTime
        tTexas.nKeepTime = tData.tTexas.nKeepTime
        tTexas.nInsurancePool = tData.tTexas.nInsurancePool
        tTexas.nSmallBlind = 0
        tTexas.nBigBlind = 0
        tTexas.sTableName = ""
        tTexas.nBaseScore = 0
        local isSuccee,tTableInfo = pcall(Cjson.decode,tData.tTexas.sTableInfo)
        if isSuccee then
            tTexas.sTableName = tTableInfo.sTableName or ""
            tTexas.nSmallBlind = tTableInfo.nSmallBlind or 0
            tTexas.nBigBlind = tTableInfo.nBigBlind or 0
            tTexas.nBaseScore = tTableInfo.nBaseScore or 0
        end
    end

    local ClubSGetTableDetailRsp = {}
    ClubSGetTableDetailRsp.tTexas = tTexas
    ClubSGetTableDetailRsp.nGameId = tData.nGameId
    ClubSGetTableDetailRsp.sTableName = tData.sTableName
    ClubSGetTableDetailRsp.nTableIndex = tData.nTableIndex
    MsgApi.SendToUser(math.floor(tData.nUserId),"ClubSGetTableDetail2Rsp",ClubSGetTableDetailRsp)
end

--获取牌桌牌谱请求
function MsgClient.OnClubSGetTablePaiPuReq(sClientID, Data, nLen)
    local strProto = "ClubSGetTablePaiPuReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    tData = tData or {}

    Base.Log("_OnClubSGetTablePaiPuReq 获取牌桌牌谱请求 nUserId_%d nGameId_%d sTableId_%s nPage_%d nCnt_%d",
    nUserId,tData.nGameId,tData.sTableId,tData.nPage,tData.nCnt)

    local nPage = tData.nPage
    if nPage<=0 then
        nPage = 1
    end
    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubGetTablePaiPuReq = {}
    ClubGetTablePaiPuReq.nUserId = nUserId
    ClubGetTablePaiPuReq.nGameId = tData.nGameId
    ClubGetTablePaiPuReq.sTableId = tData.sTableId
    ClubGetTablePaiPuReq.nPage = nPage
    ClubGetTablePaiPuReq.nCnt = nCnt
    MsgApi.SendToDBServer("ClubGetTablePaiPuReq",ClubGetTablePaiPuReq,nUserId)
end
--DB服返回 获取牌桌牌谱 返回
function MsgClient.OnDBClubGetTablePaiPuRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTablePaiPuRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end
    local trunc1 = function (x)
        return math.floor(x * 10) / 10
    end
    local arrPaiJu = {}
    for k,v in pairs(tData.arrPaiJu) do
        if v.nId and v.nId>0 then
            local t = {}
            t.nId = v.nId
            t.sPaiJuID = v.sPaiJuID
            t.sTableInfo = v.sTableInfo
            t.sHandCards = v.sHandCards
            t.nWinLose = trunc1(v.nWinLose or 0)
            t.nPenalty = trunc1(v.nPenalty or 0)
            t.nRevenue = trunc1(v.nRevenue or 0)
            t.nJuShu = v.nJuShu
            t.sWinInfo = v.sWinInfo
            t.nCollect = v.nCollect
            t.nUserBet = v.nUserBet
            table.insert(arrPaiJu,t)
        end
    end

    Base.Log("_OnDBClubGetTablePaiPuRsp nUserId_%d nGameId_%d sTableId_%s #arrPaiJu_%d nAllCnt_%d nPage_%d",
    tData.nUserId,tData.nGameId,tData.sTableId,#arrPaiJu,tData.nAllCnt,tData.nPage)

    local ClubSGetTablePaiPuRsp = {}
    ClubSGetTablePaiPuRsp.arrPaiJu = arrPaiJu
    ClubSGetTablePaiPuRsp.nGameId = tData.nGameId
    ClubSGetTablePaiPuRsp.nAllCnt = tData.nAllCnt
    ClubSGetTablePaiPuRsp.nPage = tData.nPage
    MsgApi.SendToUser(tData.nUserId,"ClubSGetTablePaiPuRsp",ClubSGetTablePaiPuRsp)
end

--获取牌桌牌谱2请求(大厅永久牌桌)
function MsgClient.OnClubSGetTablePaiPu2Req(sClientID, Data, nLen)
    local strProto = "ClubSGetTablePaiPu2Req"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetTablePaiPu2Req 获取牌桌牌谱请求 nUserId_%d nGameId_%d sTableName_%s nPage_%d nCnt_%d",
    nUserId,tData.nGameId,tData.sTableName,tData.nPage,tData.nCnt)

    local nPage = tData.nPage
    if nPage<=0 then
        nPage = 1
    end
    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubGetTablePaiPu2Req = {}
    ClubGetTablePaiPu2Req.nUserId = nUserId
    ClubGetTablePaiPu2Req.nGameId = tData.nGameId
    ClubGetTablePaiPu2Req.sTableName = tData.sTableName
    ClubGetTablePaiPu2Req.nPage = nPage
    ClubGetTablePaiPu2Req.nCnt = nCnt
    ClubGetTablePaiPu2Req.nTableIndex = tData.nTableIndex
    MsgApi.SendToDBServer("ClubGetTablePaiPu2Req",ClubGetTablePaiPu2Req,nUserId)
end

--DB服返回 获取牌桌牌谱2 返回(大厅永久牌桌)
function MsgClient.OnDBClubGetTablePaiPu2Rsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTablePaiPu2Rsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrPaiJu = {}
    for k,v in pairs(tData.arrPaiJu) do
        if v.nId and v.nId>0 then
            local t = {}
            t.nId = v.nId
            t.sPaiJuID = v.sPaiJuID
            t.sTableInfo = v.sTableInfo
            t.sHandCards = v.sHandCards
            t.nWinLose = v.nWinLose
            t.nJuShu = v.nJuShu
            t.sWinInfo = v.sWinInfo
            t.nCollect = v.nCollect
            table.insert(arrPaiJu,t)
        end
    end

    Base.Log("_OnDBClubGetTablePaiPu2Rsp nUserId_%d nGameId_%d sTableId_%s #arrPaiJu_%d nAllCnt_%d nPage_%d",
    tData.nUserId,tData.nGameId,tData.sTableId,#arrPaiJu,tData.nAllCnt,tData.nPage)

    local ClubSGetTablePaiPu2Rsp = {}
    ClubSGetTablePaiPu2Rsp.arrPaiJu = arrPaiJu
    ClubSGetTablePaiPu2Rsp.nGameId = tData.nGameId
    ClubSGetTablePaiPu2Rsp.nAllCnt = tData.nAllCnt
    ClubSGetTablePaiPu2Rsp.nPage = tData.nPage
    ClubSGetTablePaiPu2Rsp.nTableIndex = tData.nTableIndex
    MsgApi.SendToUser(tData.nUserId,"ClubSGetTablePaiPu2Rsp",ClubSGetTablePaiPu2Rsp)
end

--获取牌桌保险明细请求
function MsgClient.OnClubSGetTableInsuranceReq(sClientID, Data, nLen)
    local strProto = "ClubSGetTableInsuranceReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetTableInsuranceReq 获取牌桌保险明细请求 nUserId_%d sTableId_%s nPage_%d nCnt_%d",
    nUserId,tData.sTableId,tData.nPage,tData.nCnt)

    local nPage = tData.nPage
    if nPage<=0 then
        nPage = 1
    end
    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubGetTableInsuranceReq = {}
    ClubGetTableInsuranceReq.nUserId = nUserId
    ClubGetTableInsuranceReq.sTableId = tData.sTableId
    ClubGetTableInsuranceReq.nPage = nPage
    ClubGetTableInsuranceReq.nCnt = nCnt
    MsgApi.SendToDBServer("ClubGetTableInsuranceReq",ClubGetTableInsuranceReq,nUserId)
end

--DB服返回 获取牌桌保险明细 返回
function MsgClient.OnDBClubGetTableInsuranceRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTableInsuranceRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrUserDetail = {}
    for k,v in pairs(tData.arrUserDetail) do
        if v.nUserId and v.nUserId>0 then
            local t = {}
            t.nUserId = v.nUserId
            t.sFaceId = v.sFaceId
            t.sName = v.sName
            t.nInsurance = v.nInsurance
            table.insert(arrUserDetail,t)
        end
    end

    Base.Log("_OnDBClubGetTableInsuranceRsp nUserId_%d sTableId_%s nPage_%d nAllCnt_%d #arrUserDetail_%d",
    tData.nUserId,tData.sTableId,tData.nPage,tData.nAllCnt,#arrUserDetail)

    local ClubSGetTableInsuranceRsp = {}
    ClubSGetTableInsuranceRsp.arrUserDetail = arrUserDetail
    ClubSGetTableInsuranceRsp.nPage = tData.nPage
    ClubSGetTableInsuranceRsp.nAllCnt = tData.nAllCnt
    MsgApi.SendToUser(tData.nUserId,"ClubSGetTableInsuranceRsp",ClubSGetTableInsuranceRsp)
end

--获取牌桌保险明细2请求(大厅永久牌桌)
function MsgClient.OnClubSGetTableInsurance2Req(sClientID, Data, nLen)
    local strProto = "ClubSGetTableInsurance2Req"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetTableInsurance2Req 获取牌桌保险明细请求 nUserId_%d sTableName_%s nPage_%d nCnt_%d nGameId_%d",
    nUserId,tData.sTableName,tData.nPage,tData.nCnt,tData.nGameId)

    local nPage = tData.nPage
    if nPage<=0 then
        nPage = 1
    end
    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubGetTableInsurance2Req = {}
    ClubGetTableInsurance2Req.nUserId = nUserId
    ClubGetTableInsurance2Req.sTableName = tData.sTableName
    ClubGetTableInsurance2Req.nPage = nPage
    ClubGetTableInsurance2Req.nCnt = nCnt
    ClubGetTableInsurance2Req.nTableIndex = tData.nTableIndex
    ClubGetTableInsurance2Req.nGameId = tData.nGameId
    MsgApi.SendToDBServer("ClubGetTableInsurance2Req",ClubGetTableInsurance2Req,nUserId)
end

--DB服返回 获取牌桌保险明细2 返回(大厅永久牌桌)
function MsgClient.OnDBClubGetTableInsurance2Rsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTableInsurance2Rsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrUserDetail = {}
    for k,v in pairs(tData.arrUserDetail) do
        if v.nUserId and v.nUserId>0 then
            local t = {}
            t.nUserId = v.nUserId
            t.sFaceId = v.sFaceId
            t.sName = v.sName
            t.nInsurance = v.nInsurance
            table.insert(arrUserDetail,t)
        end
    end

    Base.Log("_OnDBClubGetTableInsuranceRsp nUserId_%d sTableId_%s nPage_%d nAllCnt_%d #arrUserDetail_%d",
    tData.nUserId,tData.sTableId,tData.nPage,tData.nAllCnt,#arrUserDetail)

    local ClubSGetTableInsurance2Rsp = {}
    ClubSGetTableInsurance2Rsp.arrUserDetail = arrUserDetail
    ClubSGetTableInsurance2Rsp.nPage = tData.nPage
    ClubSGetTableInsurance2Rsp.nAllCnt = tData.nAllCnt
    ClubSGetTableInsurance2Rsp.nTableIndex = tData.nTableIndex
    ClubSGetTableInsurance2Rsp.nGameId = tData.nGameId
    MsgApi.SendToUser(tData.nUserId,"ClubSGetTableInsurance2Rsp",ClubSGetTableInsurance2Rsp)
end

--获取牌局明细查询请求(大厅:抢庄牛)
function MsgClient.OnClubSGetPaijuDetailReq(sClientID, Data, nLen)
    local strProto = "ClubSGetPaijuDetailReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_ClubSGetPaijuDetailReq 获取牌局明细查询请求 nUserId_%d sPaiJuID_%s",nUserId,tData.sPaiJuID)

    local ClubGetPaijuDetailReq = {}
    ClubGetPaijuDetailReq.nUserId = nUserId
    ClubGetPaijuDetailReq.sPaiJuID = tData.sPaiJuID
    MsgApi.SendToDBServer("ClubGetPaijuDetailReq",ClubGetPaijuDetailReq,nUserId)
end

--DB服返回 获取牌局明细查询返回 ClubGetPaijuDetailRsp
function MsgClient.OnDBClubGetPaijuDetailRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetPaijuDetailRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    Base.Log("_OnDBClubGetPaijuDetailRsp nUserId_%d sPaiJuID_%s GameId_%d nAnte_%f",tData.nUserId,tData.sPaiJuID,tData.GameId,tData.nAnte)

    local ClubSGetPaijuDetailRsp={}
    ClubSGetPaijuDetailRsp.GameId =tData.GameId
    ClubSGetPaijuDetailRsp.nAnte =tData.nAnte
    ClubSGetPaijuDetailRsp.tUsersInfo =tData.tUsersInfo
    ClubSGetPaijuDetailRsp.nZhuang =tData.nZhuang 
    ClubSGetPaijuDetailRsp.tDealCardInfo =tData.tDealCardInfo
    ClubSGetPaijuDetailRsp.tBetInfo=tData.tBetInfo
    ClubSGetPaijuDetailRsp.sTime =tData.sTime
    ClubSGetPaijuDetailRsp.sPaiJuID =tData.sPaiJuID

    Base.Log("_OnDBClubGetPaijuDetailRsp_%s",Cjson.encode(ClubSGetPaijuDetailRsp))

    MsgApi.SendToUser(tData.nUserId,"ClubSGetPaijuDetailRsp",ClubSGetPaijuDetailRsp)
end

--获取牌桌玩家列表请求
function MsgClient.OnClubSGetTableUserListReq(sClientID, Data, nLen)
    local strProto = "ClubSGetTableUserListReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    tData = tData or {}
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSGetTableUserListReq 获取牌桌玩家列表请求 nUserId_%d nGameId_%d sTableId_%s nPage_%d nCnt_%d",
    nUserId,tData.nGameId,tData.sTableId,tData.nPage,tData.nCnt)

    local nPage = tData.nPage
    if nPage<=0 then
        nPage = 1
    end
    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubGetTableUserListReq = {}
    ClubGetTableUserListReq.nUserId = nUserId
    ClubGetTableUserListReq.nGameId = tData.nGameId
    ClubGetTableUserListReq.sTableId = tData.sTableId
    ClubGetTableUserListReq.nPage = nPage
    ClubGetTableUserListReq.nCnt = nCnt
    MsgApi.SendToDBServer("ClubGetTableUserListReq",ClubGetTableUserListReq,nUserId)
end

--DB服返回 获取牌桌玩家列表 返回
function MsgClient.OnDBClubGetTableUserListRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTableUserListRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrUserDetail = {}
    for k,v in pairs(tData.arrUserDetail) do
        if v.nUserId and v.nUserId>0 then
            local t = {}
            t.nUserId = v.nUserId
            t.sFaceId = v.sFaceId
            t.sName = v.sName
            t.nWinLose = v.nWinLose
            t.nPlayCnt = v.nPlayCnt
            t.nRank = v.nRank
            t.nPenalty = v.nPenalty or 0
            t.nRevenue = v.nRevenue or 0
            if PublicApi.IsTexasClassGame(tData.nGameId) then
                --德州类的游戏
                t.nTakeIn = v.nTakeIn
                if v.nPlayCnt>0 then
                    t.nInpoolRate = PublicApi.Floor_n(v.nInPoolCount/v.nPlayCnt,3)
                else
                    t.nInpoolRate = 0
                end
            end
            table.insert(arrUserDetail,t)
        end
    end

    Base.Log("_OnDBClubGetTableUserListRsp nUserId_%d nGameId_%d sTableId_%s nPage_%d nAllCnt_%d #arrUserDetail_%d",
    tData.nUserId,tData.nGameId,tData.sTableId,tData.nPage,tData.nAllCnt,#arrUserDetail)

    local ClubSGetTableUserListRsp = {}
    ClubSGetTableUserListRsp.arrUserDetail = arrUserDetail
    ClubSGetTableUserListRsp.nPage = tData.nPage
    ClubSGetTableUserListRsp.nAllCnt = tData.nAllCnt
    ClubSGetTableUserListRsp.nGameId = tData.nGameId
    MsgApi.SendToUser(tData.nUserId,"ClubSGetTableUserListRsp",ClubSGetTableUserListRsp)
end

--获取牌桌玩家列表2请求(大厅永久牌桌)
function MsgClient.OnClubSGetTableUserList2Req(sClientID, Data, nLen)
    local strProto = "ClubSGetTableUserList2Req"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    tData = tData or {}

    Base.Log("_OnClubSGetTableUserList2Req 获取牌桌玩家列表请求 nUserId_%d nGameId_%d sTableName_%s nPage_%d nCnt_%d",
    nUserId,tData.nGameId,tData.sTableName,tData.nPage,tData.nCnt)

    local nPage = tData.nPage
    if nPage<=0 then
        nPage = 1
    end
    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt>30 then
        nCnt = 30
    end

    local ClubGetTableUserList2Req = {}
    ClubGetTableUserList2Req.nUserId = nUserId
    ClubGetTableUserList2Req.nGameId = tData.nGameId
    ClubGetTableUserList2Req.sTableName = tData.sTableName
    ClubGetTableUserList2Req.nPage = nPage
    ClubGetTableUserList2Req.nCnt = nCnt
    ClubGetTableUserList2Req.nTableIndex = tData.nTableIndex
    MsgApi.SendToDBServer("ClubGetTableUserList2Req",ClubGetTableUserList2Req,nUserId)
end

--DB服返回 获取牌桌玩家列表2 返回(大厅永久牌桌)
function MsgClient.OnDBClubGetTableUserList2Rsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTableUserList2Rsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrUserDetail = {}
    for k,v in pairs(tData.arrUserDetail) do
        if v.nUserId and v.nUserId>0 then
            local t = {}
            t.nUserId = v.nUserId
            t.sFaceId = v.sFaceId
            t.sName = v.sName
            t.nWinLose = v.nWinLose
            t.nPlayCnt = v.nPlayCnt
            t.nRank = v.nRank
            if PublicApi.IsTexasClassGame(tData.nGameId) then
                --德州类的游戏
                t.nTakeIn = v.nTakeIn
                if v.nPlayCnt>0 then
                    t.nInpoolRate = PublicApi.Floor_n(v.nInPoolCount/v.nPlayCnt,3)
                else
                    t.nInpoolRate = 0
                end
            end
            table.insert(arrUserDetail,t)
        end
    end

    Base.Log("_OnDBClubGetTableUserList2Rsp nUserId_%d nGameId_%d sTableId_%s nPage_%d nAllCnt_%d #arrUserDetail_%d",
    tData.nUserId,tData.nGameId,tData.sTableId,tData.nPage,tData.nAllCnt,#arrUserDetail)

    local ClubSGetTableUserList2Rsp = {}
    ClubSGetTableUserList2Rsp.arrUserDetail = arrUserDetail
    ClubSGetTableUserList2Rsp.nPage = tData.nPage
    ClubSGetTableUserList2Rsp.nAllCnt = tData.nAllCnt
    ClubSGetTableUserList2Rsp.nGameId = tData.nGameId
    ClubSGetTableUserList2Rsp.nTableIndex = tData.nTableIndex
    MsgApi.SendToUser(tData.nUserId,"ClubSGetTableUserList2Rsp",ClubSGetTableUserList2Rsp)
end

--俱乐部广告奖励金请求、返回
function MsgClient.OnClubSAdvertiseMentGoldRep(sClientID, Data, nLen)
    local strProto = "ClubSAdvertiseMentGoldRep"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSAdvertiseMentGoldRep 俱乐部广告奖励金请求 nUserId_%d nType_%d",nUserId,tData.nType or -1)

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSAdvertiseMentGoldRep 玩家信息不存在 nUserId:%d",nUserId)
        return
    end
    local nGroupId = tUser.nGroupId or -1

    local nTodayMaxGetCnt,nGiveGold = PublicRedis.GetGiveInfoOfLookAdvertisement(nGroupId)
    local nTodayCnt = PublicRedis.GetLookAdvertisementCnt(nUserId)

    local nRlt = 1
    local nItemId = 1 --大厅金币
    if nTodayCnt < nTodayMaxGetCnt and nTodayMaxGetCnt > 0 and nGiveGold > 0 then
        local nSourceType = 200010  -- 广告奖励金
        nRlt = 0
        Base.Log("OnClubSAdvertiseMentGoldRsp  俱乐部广告奖励金 nUserId_%d nItemId_%d nGiveGold_%d nTodayMaxGetCnt_%d nTodayCnt_%d",
            nUserId,nItemId,nGiveGold,nTodayMaxGetCnt,nTodayCnt)
        PublicUserInfo.ChangeUserTreasure({nUserID =nUserId,nItemID=nItemId,nDel= PublicApi.Floor_2(nGiveGold),nSourceType=nSourceType})
        PublicRedis.IncrUserLookAdvertisement(nUserId)
        RecordDbr.WithdrawLimit(nUserId,nGiveGold,20)        --提现限制
    else
        if nTodayCnt >= nTodayMaxGetCnt then
            nRlt = 1
        elseif nTodayMaxGetCnt <= 0 or nGiveGold <= 0 then
            nRlt = 2
        end
    end
    local ClubSAdvertiseMentGoldRsp = {}
    ClubSAdvertiseMentGoldRsp.nRlt = nRlt
    ClubSAdvertiseMentGoldRsp.nTodayMaxGetCnt = nTodayMaxGetCnt
    ClubSAdvertiseMentGoldRsp.nTodayCnt = PublicRedis.GetLookAdvertisementCnt(nUserId)
    ClubSAdvertiseMentGoldRsp.nGiveGold = nGiveGold
    MsgApi.SendToUser(nUserId,"ClubSAdvertiseMentGoldRsp",ClubSAdvertiseMentGoldRsp)
end

--前端用文件编码请求
function MsgClient.OnClubsFileConfigReq(sClientID,Data,nLen)
    local strProto = "ClubsFileConfigReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if not tData then
        return
    end
    local ClubsFileConfigRsp = {}
    ClubsFileConfigRsp.nUserId = tData.nUserId
    ClubsFileConfigRsp.nConfigCode = PublicUserInfo.GetFileConfig()
    MsgApi.SendToUser(tData.nUserId,"ClubsFileConfigRsp",ClubsFileConfigRsp)
end

--转账方式请求
function MsgClient.OnClubTransferWayReq(sClientID,Data,nLen)
    local strProto = "ClubTransferWayReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if not tData then
        return
    end

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSCreateReq 玩家信息不存在 nUserId:%d",nUserId)
        return
    end
    local nGroupId = tUser.nGroupId or -1

    local nTransferWay = PublicUserInfo.GetTransferWay(nGroupId)
    local TransferWay = Cjson.encode(nTransferWay)

    local sTransferInfos = RedisCahche._GetTransferInfos()
    
    local ClubTransferWayRsp = {}
    ClubTransferWayRsp.nUserId = tData.nUserId
    ClubTransferWayRsp.nWayInfo = TransferWay
    ClubTransferWayRsp.sInfos = Cjson.encode(sTransferInfos)
    MsgApi.SendToUser2(tData.nUserId,"ClubTransferWayRsp",ClubTransferWayRsp)
end

--活动信息请求
function MsgClient.OnClubActivityInfoReq(sClientID,Data,nLen)
    local strProto = "ClubActivityInfoReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if not tData then
        return
    end
    local ClubGetActiInfoReq = {}
    ClubGetActiInfoReq.nUserId = tData.nUserId
    ClubGetActiInfoReq.nActivityType = tData.nActivityType
    MsgApi.SendToDBServer("ClubGetActiInfoReq",ClubGetActiInfoReq,tData.nUserId)
end

--充值或提现审核请求
function MsgClient.OnClubRechargeWithdrawalReq(sClientID,Data,nLen)
    local sUrl = ""
    local strProto = "ClubRechargeWithdrawalReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if not tData then
        return
    end
 
    local sDomainName = tPublicRedis._GetRechargeWithdrawalDomainName() or "http://192.168.0.215:82"

    local name = url.escape(tData.name)
    local account = url.escape(tData.account)
    local phoneNo = url.escape(tData.phoneNo)
    local remarks = url.escape(tData.remarks)

    local ActiSwitch = PublicUserInfo.GetUserShareActiSwitch(nUserId)

    --活动开关关闭
    if tData.payType==3 and ActiSwitch == 1 then
        local sJsonData = {}
        sJsonData.code = 12
        sJsonData.text = "Activity Permission closed"
        local ClubRechargeWithdrawalRsp = {}
        ClubRechargeWithdrawalRsp.nUserId = tData.nUserId
        ClubRechargeWithdrawalRsp.res = Cjson.encode(sJsonData)
        MsgApi.SendToUser2(nUserId,"ClubRechargeWithdrawalRsp",ClubRechargeWithdrawalRsp)
        return
    end
    
    -- local tUser = UserManager.GetUserInfo(nUserId)
    -- if not tUser then
    --     Base.Log("_OnClubRechargeWithdrawalReq 玩家信息不存在")
    --     return
    -- end
    -- local nGroupId = tonumber(tUser.nGroupId) or -1

    -- local ChannelInfo = RedisCahche._GetTransferWay(nGroupId,tData.channelNo)

    -- --判断金额数是否合法
    -- local isSuccee,sChannelInfo = pcall(Cjson.decode,ChannelInfo)
    -- if isSuccee then
    --     if tonumber(sChannelInfo.minRecharge) > math.abs(tonumber(tData.amount)) then
    --         local sJsonData = {}
    --         sJsonData.code = 13
    --         sJsonData.text = "Recharge amount is less than the minimum amount"
    --         local ClubRechargeWithdrawalRsp = {}
    --         ClubRechargeWithdrawalRsp.nUserId = tData.nUserId
    --         ClubRechargeWithdrawalRsp.res = Cjson.encode(sJsonData)
    --         MsgApi.SendToUser2(nUserId,"ClubRechargeWithdrawalRsp",ClubRechargeWithdrawalRsp)
    --         return
    --     end
    -- end

    if tData.payType==1 then --充值
        sUrl = string.format("%s?userNo=%d&imgHandTransfer=%s&amount=%d&payType=1&channelNo=%d&remarks=%s",
        sDomainName,tData.nUserId,tData.imgHandTransfer,tData.amount,tData.channelNo,remarks)
    elseif tData.payType==2 then --提现
        sUrl = string.format("%s?userNo=%d&amount=%d&payType=2&channelNo=%d&remarks=%s&name=%s&account=%s&phoneNo=%s",
        sDomainName,tData.nUserId,tData.amount,tData.channelNo,remarks,name,account,phoneNo)
    elseif tData.payType==3 then --分享活动
        local sSql = string.format("call Club_WriteShareActiRecord(%d,'%s')",tData.nUserId,tData.imgHandTransfer) 
        local ClubActivityReviewDataReq = {}
        ClubActivityReviewDataReq.nUserId = tData.nUserId
        ClubActivityReviewDataReq.sSql = sSql
        MsgApi.SendToDBServer("ClubActivityReviewDataReq",ClubActivityReviewDataReq,tData.nUserId)
        return
    else
        Base.Log("error:非充值，提现或分享")
        return
    end

    local switch = PublicUserInfo.GetUserTransferSwitch(nUserId)

    Base.Log("switch:%d",switch)

    if switch == 1 then
        local sJsonData = {}
        sJsonData.code = 7
        sJsonData.text = "Permission closed"
        local ClubRechargeWithdrawalRsp = {}
        ClubRechargeWithdrawalRsp.nUserId = tData.nUserId
        ClubRechargeWithdrawalRsp.res = Cjson.encode(sJsonData)
        MsgApi.SendToUser2(nUserId,"ClubRechargeWithdrawalRsp",ClubRechargeWithdrawalRsp)
        return
    end
    tPublicBlockChain.GetContent(sUrl,nUserId)
end

--充值或提现审核请求2
function MsgClient.OnClubRechargeWithdrawalV2Req(sClientID,Data,nLen)
    local sUrl = ""
    local strProto = "ClubRechargeWithdrawalV2Req"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if not tData then
        return
    end
 
    local sDomainName = tPublicRedis._GetRechargeWithdrawalDomainName() or "http://192.168.0.215:82"

    local name = url.escape(tData.name)
    local account = url.escape(tData.account)
    local phoneNo = url.escape(tData.phoneNo)
    local remarks = url.escape(tData.remarks)
    local bankName = url.escape(tData.bankName)
    local country = url.escape(tData.country)

    local ActiSwitch = PublicUserInfo.GetUserShareActiSwitch(nUserId)

    --活动开关关闭
    if tData.payType==3 and ActiSwitch == 1 then
        local sJsonData = {}
        sJsonData.code = 12
        sJsonData.text = "Activity Permission closed"
        local ClubRechargeWithdrawalRsp = {}
        ClubRechargeWithdrawalRsp.nUserId = tData.nUserId
        ClubRechargeWithdrawalRsp.res = Cjson.encode(sJsonData)
        MsgApi.SendToUser2(nUserId,"ClubRechargeWithdrawalRsp",ClubRechargeWithdrawalRsp)
        return
    end
    
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubRechargeWithdrawalReq 玩家信息不存在")
        return
    end
    local nGroupId = tonumber(tUser.nGroupId) or -1

    local ChannelInfo = RedisCahche._GetTransferWay(nGroupId,tData.channelNo)

    local TransInfo = RedisCahche._GetOneTransferInfo(tData.country)

    --判断金额数是否合法
    if tData.payType==1 then --充值
        local isSuccee,sChannelInfo = pcall(Cjson.decode,ChannelInfo)
        if isSuccee then
            if tonumber(sChannelInfo.minRecharge) > math.abs(tonumber(tData.amount)) then
                local sJsonData = {}
                sJsonData.code = 13
                sJsonData.text = "Recharge amount is less than the minimum amount (1)"
                local ClubRechargeWithdrawalRsp = {}
                ClubRechargeWithdrawalRsp.nUserId = tData.nUserId
                ClubRechargeWithdrawalRsp.res = Cjson.encode(sJsonData)
                MsgApi.SendToUser2(nUserId,"ClubRechargeWithdrawalRsp",ClubRechargeWithdrawalRsp)
                return
            end
        end
    elseif tData.payType==2 then --提现
        local isSuccee,sTransInfo = pcall(Cjson.decode,TransInfo)
        if isSuccee then
            if tonumber(sTransInfo.MinWithdrawal) > math.abs(tonumber(tData.amount)) then
                local sJsonData = {}
                sJsonData.code = 13
                sJsonData.text = "Recharge amount is less than the minimum amount (2)"
                local ClubRechargeWithdrawalRsp = {}
                ClubRechargeWithdrawalRsp.nUserId = tData.nUserId
                ClubRechargeWithdrawalRsp.res = Cjson.encode(sJsonData)
                MsgApi.SendToUser2(nUserId,"ClubRechargeWithdrawalRsp",ClubRechargeWithdrawalRsp)
                return
            end
        end
    end
    

    if tData.payType==1 then --充值
        sUrl = string.format("%s?userNo=%d&imgHandTransfer=%s&amount=%d&payType=1&channelNo=%d&remarks=%s",
        sDomainName,tData.nUserId,tData.imgHandTransfer,tData.amount,tData.channelNo,remarks)
    elseif tData.payType==2 then --提现
        sUrl = string.format("%s?userNo=%d&amount=%d&payType=2&channelNo=%d&remarks=%s&name=%s&account=%s&phoneNo=%s&bankName=%s&country=%s",
        sDomainName,tData.nUserId,tData.amount,tData.channelNo,remarks,name,account,phoneNo,bankName,country)
    elseif tData.payType==3 then --分享活动
        local sSql = string.format("call Club_WriteShareActiRecord(%d,'%s')",tData.nUserId,tData.imgHandTransfer) 
        local ClubActivityReviewDataReq = {}
        ClubActivityReviewDataReq.nUserId = tData.nUserId
        ClubActivityReviewDataReq.sSql = sSql
        MsgApi.SendToDBServer("ClubActivityReviewDataReq",ClubActivityReviewDataReq,tData.nUserId)
        return
    else
        Base.Log("error:非充值，提现或分享")
        return
    end

    local switch = PublicUserInfo.GetUserTransferSwitch(nUserId)

    Base.Log("switch:%d",switch)

    if switch == 1 then
        local sJsonData = {}
        sJsonData.code = 7
        sJsonData.text = "Permission closed"
        local ClubRechargeWithdrawalRsp = {}
        ClubRechargeWithdrawalRsp.nUserId = tData.nUserId
        ClubRechargeWithdrawalRsp.res = Cjson.encode(sJsonData)
        MsgApi.SendToUser2(nUserId,"ClubRechargeWithdrawalRsp",ClubRechargeWithdrawalRsp)
        return
    end
    tPublicBlockChain.GetContent(sUrl,nUserId)
end

--根据key获取value请求 通用接口
function MsgClient.OnGetValueByKeyReq(sClientID,Data,nLen)
    local strProto = "ClubGetValueByKeyReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if not tData then
        return
    end

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSCreateReq 玩家信息不存在 nUserId:%d",nUserId)
        return
    end
    local nGroupId = tUser.nGroupId or -1

    local value = nil
    local sRedisKey = nil
    local sJsonKey = tData.sKey
    local Config = RedisCahche._GetKeyValueConfig(nGroupId)
    local isSuccee,sConfig = pcall(Cjson.decode,Config)
    if isSuccee then
        sRedisKey = sConfig[sJsonKey]
        value = RedisCahche._GetNumValueByKey(sRedisKey)
    end

    local ClubGetValueByKeyRsp = {}
    ClubGetValueByKeyRsp.nUserId = math.floor(nUserId)
    ClubGetValueByKeyRsp.sValue = tostring(value)
    
    MsgApi.SendToUser2(tData.nUserId,"ClubGetValueByKeyRsp",ClubGetValueByKeyRsp)
end

--获取活动列表请求
function MsgClient.OnClubActivityListReq(sClientID, Data, nLen)
    local strProto = "ClubActivityListReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("_OnClubActivityListReq 获取活动列表请求 nUserId_%d", nUserId)

    local ClubGetActivityListReq = {}
    ClubGetActivityListReq.nUserId = nUserId
    MsgApi.SendToDBServer1("ClubGetActivityListReq", ClubGetActivityListReq, nUserId)
end

--DB服返回 获取活动列表 返回
function MsgClient.OnClubGetActivityListRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetActivityListRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end

    local arrDetail = {}
    for _ ,v in pairs(tData.arrRecords) do
        local t = {}
        t.nActId = v.nActId
        t.nName = v.nName
        t.nSort = v.nSort
        t.nStartTime = v.nStartTime
        t.nEndTime = v.nEndTime
        t.nConfig = v.nConfig
        t.nBaseConfig = v.nBaseConfig
        t.nImage = v.nImage
        t.nRecharge = v.nRecharge
        t.nTitle = v.nTitle
        table.insert(arrDetail, t)
    end

    Base.Log("OnClubGetActivityListRsp nUserId_%d #arrDetail_%d", tData.nUserId, #arrDetail)

    local ClubActivityListRsp = {}
    ClubActivityListRsp.arrActivityCfg = arrDetail
    MsgApi.SendToUser2(tData.nUserId, "ClubActivityListRsp", ClubActivityListRsp)
end

--获取用户总数请求
function MsgClient.OnClubSumUserCountReq(sClientID, Data, nLen)
    local strProto = "ClubSumUserCountReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    local ClubSumUserCountRsp = {}
    ClubSumUserCountRsp.nCount = PublicUserInfo.GetRegisterCount()
    MsgApi.SendToUser2(nUserId, "ClubSumUserCountRsp", ClubSumUserCountRsp)
end

--获取大厅统计信息(大厅永久牌桌)
function MsgClient.OnClubSGetPersonTableStaticReq(sClientID, Data, nLen)
    local strProto = "ClubSGetPersonTableStaticReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    nUserId = math.floor(nUserId)
    tData.nClubId = 0
    Base.Log("ClubSGetPersonTableStaticReq 开始 nClubId:%d",tData.nClubId)
    if tData.nClubId == 0 then
        --大厅
        local tUser = UserManager.GetUserInfo(nUserId)
        if not tUser then
            Base.Log("ClubSGetPersonTableStaticReq 玩家信息不存在")
            return
        end
        local nGroupId = tonumber(tUser.nGroupId) or -1
        tData.nClubId = nGroupId
        Base.Log("ClubSGetPersonTableStaticReq 获取大厅统计信息 nClubId:%d",tData.nClubId)
    end
    --俱乐部不存在
    local tClub = ClubSManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("ClubSGetPersonTableStaticReq 俱乐部不存在")
        return
    end
    Base.Log("ClubSGetPersonTableStaticReq 获取大厅统计信息 nUserId_%d nGameId_%d nGoldType_%d nClubId_%d",
    nUserId,tData.nGameId,tData.nGoldType,tData.nClubId)
    local nGoldType = tData.nGoldType
    if nGoldType ~= 1 and nGoldType ~= 2 then
        nGoldType = 1
    end
    local skey = string.format("tStatics:%s:%s", nUserId, tData.nGameId)
    local val = tPublicRedis.GetRedis1(skey)
    if val ~= "" then
        local tStatics = Cjson.decode(val)
        local ClubSGetPersonTableStaticRsp = {}
        ClubSGetPersonTableStaticRsp.tStatics = tStatics
        ClubSGetPersonTableStaticRsp.nGameId = tData.nGameId
        ClubSGetPersonTableStaticRsp.nGoldType = nGoldType
        ClubSGetPersonTableStaticRsp.nClubId = tData.nClubId
        MsgApi.SendToUser2(nUserId,"ClubSGetPersonTableStaticRsp",ClubSGetPersonTableStaticRsp)
        return
    end
    local ClubGetPersonTableStaticReq = {}
    ClubGetPersonTableStaticReq.nUserId = nUserId
    ClubGetPersonTableStaticReq.nGameId = tData.nGameId
    ClubGetPersonTableStaticReq.nGoldType = nGoldType
    ClubGetPersonTableStaticReq.nClubId = tData.nClubId
    MsgApi.SendToDBServer1("ClubGetPersonTableStaticReq",ClubGetPersonTableStaticReq,nUserId)
end

--DB服返回 获取大厅统计信息 返回 (大厅永久牌桌)
function MsgClient.OnClubGetPersonTableStaticRsp(sReturnKey, Data, nLen)
    Base.Log("--enter ClubGetPersonTableStaticRsp" )
    local strProto = "ClubGetPersonTableStaticRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        Base.Log("--enter ClubGetPersonTableStaticRsp:not tDat" )
        return
    end

    local nUserID = math.floor( tData.nUserId )
    local tStatics = nil
    if tData.tStatics then
        tStatics = {}
        tStatics.nPaiJuCnt = tData.tStatics.nPaiJuCnt
        tStatics.nHandCnt = tData.tStatics.nPlayCount
        tStatics.nWinLose = tData.tStatics.nProfitSum
        -- Base.Log("OnClubGetPersonTableStaticRsp %d,%d,%f,%d",tData.tStatics.nPaiJuCnt,tData.tStatics.nPlayCount,tData.tStatics.nProfitSum,tData.tStatics.nAllInCount)
        if tData.tStatics.nPlayCount>0 then
            tStatics.nInpoolRate = PublicApi.Floor_n(100*tData.tStatics.nInPoolCount/tData.tStatics.nPlayCount,1)
            tStatics.nBFlopRaiseRate = PublicApi.Floor_n(100*tData.tStatics.nRaiseCountBFlop/tData.tStatics.nPlayCount,1)
            -- tStatics.nAllInAndWinRate = PublicApi.Floor_n(100*tData.tStatics.nAllInAndWinCount/tData.tStatics.nPlayCount,1)
            tStatics.nWinRate = PublicApi.Floor_n(100*tData.tStatics.nWinCount/tData.tStatics.nPlayCount,1)
            tStatics.nQiPaiRate = PublicApi.Floor_n(100*tData.tStatics.nQiPaiCount/tData.tStatics.nPlayCount,1)
            tStatics.nHandProfit = PublicApi.Floor_n(tData.tStatics.nHandProfit/tData.tStatics.nPlayCount,2)
        else
            tStatics.nInpoolRate = 0
            tStatics.nBFlopRaiseRate = 0
            tStatics.nAllInAndWinRate = 0
            tStatics.nWinRate = 0
            tStatics.nQiPaiRate = 0
            tStatics.nHandProfit = 0
        end
        tStatics.nAllInAndWinRate = 0
        if tData.tStatics.nAllInCount > 0 then
            tStatics.nAllInAndWinRate = PublicApi.Floor_n(100*tData.tStatics.nAllInAndWinCount/tData.tStatics.nAllInCount,1)
        end
        Base.Log("OnClubGetPersonTableStaticRsp tStatics_%s",Cjson.encode(tStatics))
        local skey = string.format("tStatics:%d:%s", nUserID, tData.nGameId)
        tPublicRedis.SetRedis1(skey, Cjson.encode(tStatics), 60*3)
    end
    -- Base.Log("OnClubGetPersonTableStaticRsp nUserId_%d nGameId_%d nGoldType_%d nClubId_%d",tData.nUserId,tData.nGameId,tData.nGoldType,tData.nClubId)

    local ClubSGetPersonTableStaticRsp = {}
    ClubSGetPersonTableStaticRsp.tStatics = tStatics
    ClubSGetPersonTableStaticRsp.nGameId = tData.nGameId
    ClubSGetPersonTableStaticRsp.nGoldType = tData.nGoldType
    ClubSGetPersonTableStaticRsp.nClubId = tData.nClubId
    MsgApi.SendToUser2(nUserID,"ClubSGetPersonTableStaticRsp",ClubSGetPersonTableStaticRsp)
    Base.Log("--leave ClubGetPersonTableStaticRsp" )
end

--获取配置信息
function MsgClient.OnClubSGetConfigReq(sClientID, Data, nLen)
    local strProto = "ClubSGetConfigReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    local tUser = UserManager.GetUserInfo(nUserId)
    local nShopId =tonumber(tUser.nShopId) or -1
    local conf = GameConfig.GetGroupConf(nShopId)
    local ClubSGetConfigRsp = {}
    ClubSGetConfigRsp.nTgLink = conf.sTgLink or ""
    MsgApi.SendToUser2(nUserId,"ClubSGetConfigRsp",ClubSGetConfigRsp)
end

-- 获取玩家账变信息
function MsgClient.OnClubSGetGoldHistoryReq(sClientID, Data, nLen)
    Base.Log("OnClubSGetGoldHistoryReq 开始")
    local strProto = "ClubSGetGoldHistoryReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    local nIdOfStart = tData.nIdOfStart or 0
    if nIdOfStart < 0 then
        nIdOfStart = 0
    end
    local nCnt = tData.nCnt or 15
    if nCnt > 15 then
        nCnt = 15
    end

    local ClubGetGoldHistoryReq = {}
    ClubGetGoldHistoryReq.nUserId = nUserId
    ClubGetGoldHistoryReq.nIdOfStart = nIdOfStart
    ClubGetGoldHistoryReq.nCnt = nCnt
    ClubGetGoldHistoryReq.nStartTime = tData.nStartTime or ""
    ClubGetGoldHistoryReq.nEndTime = tData.nEndTime or ""
    ClubGetGoldHistoryReq.nType = tData.nType
    MsgApi.SendToDBServer1("ClubGetGoldHistoryReq",ClubGetGoldHistoryReq,nUserId)
end

--DB服返回 获取玩家账变信息
function MsgClient.OnClubSGetGoldHistoryRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetGoldHistoryRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    local arrRecords = {}
    for k,v in pairs(tData.arrRecord) do
        if v.nId and v.nId>0 then
            local t = {}
            t.nId = v.nId
            t.nChange = v.nChange
            t.nClubGold = v.nClubGold
            t.sTime = v.sTime
            t.nSourceType = v.nSourceType
            t.nExData = v.nExData
            table.insert(arrRecords,t)
        end
    end

    Base.Log("OnClubSGetGoldHistoryRsp nUserId_%d #arrRecords_%d",tData.nUserId,#arrRecords)
    local ClubSGetGoldHistoryRsp = {}
    ClubSGetGoldHistoryRsp.arrRecord = arrRecords
    ClubSGetGoldHistoryRsp.nIdOfStart = tData.nIdOfStart
    ClubSGetGoldHistoryRsp.nAllCnt = tData.nAllCnt
    ClubSGetGoldHistoryRsp.nStartTime = tData.nStartTime
    ClubSGetGoldHistoryRsp.nEndTime = tData.nEndTime
    ClubSGetGoldHistoryRsp.nType = tData.nType
    MsgApi.SendToUser2(tData.nUserId,"ClubSGetGoldHistoryRsp",ClubSGetGoldHistoryRsp)
end

-- 局内消耗
function MsgClient.OnClubSGetGameGoldHistoryReq(sClientID, Data, nLen)
    -- Base.Log("OnClubSGetGameGoldHistoryReq 开始")
    local strProto = "ClubSGetGameGoldHistoryReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if tData.nIdOfStart and tData.nCnt then
        Base.Log("OnClubSGetGameGoldHistoryReq nIdOfStart_%d nCnt_%d",tData.nIdOfStart,tData.nCnt)
    end
    local nIdOfStart = tData.nIdOfStart or 0
    if nIdOfStart < 0 then
        nIdOfStart = 0
    end
    local nCnt = tData.nCnt or 15
    if nCnt > 15 then
        nCnt = 15
    end

    local ClubGetGameGoldReq = {}
    ClubGetGameGoldReq.nUserId = nUserId
    ClubGetGameGoldReq.nIdOfStart = nIdOfStart
    ClubGetGameGoldReq.nCnt = nCnt
    ClubGetGameGoldReq.nStartTime = tData.nStartTime or ""
    ClubGetGameGoldReq.nEndTime = tData.nEndTime or ""
    MsgApi.SendToDBServer1("ClubGetGameGoldReq",ClubGetGameGoldReq,nUserId)
end

--DB服返回 局内消耗
function MsgClient.OnClubGetGameGoldRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetGameGoldRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    local arrRecords = {}
    for k,v in pairs(tData.arrRecord) do
        if v.nId and v.nId>0 then
            local t = {}
            t.nId = v.nId
            t.nChange = v.nChange
            t.sTableId = v.sTableId
            t.sTableName = v.sTableName
            t.nGameId = v.nGameId
            t.sTime = v.sTime
            t.nGoldType = v.nGoldType
            t.sPaiJuId = v.sPaiJuId
            t.nZhuang = v.nZhuang
            t.nZhuaTou = v.nZhuaTou
            t.nPreAnte = v.nPreAnte
            t.preAnteOdd = v.preAnteOdd
            t.nSmallBlind = v.nSmallBlind
            t.nBigBlind = v.nBigBlind
            
            local arrDetails = {}
            for k,v in pairs(v.arrDetails) do
                if v.nSourceType and v.nSourceType > 0 then
                    local t = {}
                    t.nSourceType = v.nSourceType
                    t.nChange = v.nChange
                    t.sTime = v.sTime
                    table.insert(arrDetails,t)
                end
            end
            local arrFeeDetails = {}
            for k,v in pairs(v.arrFeeDetails) do
                if v.nSourceType and v.nSourceType > 0 then
                    local t = {}
                    t.nSourceType = v.nSourceType
                    t.nChange = v.nChange
                    t.sTime = v.sTime
                    table.insert(arrFeeDetails,t)
                end
            end
            t.arrDetails = arrDetails
            t.arrFeeDetails = arrFeeDetails
            table.insert(arrRecords,t)
        end
    end

    Base.Log("OnClubGetGameGoldRsp nUserId_%d #arrRecords_%d",tData.nUserId,#arrRecords)
    local ClubSGetGameGoldHistoryRsp = {}
    ClubSGetGameGoldHistoryRsp.arrRecord = arrRecords
    ClubSGetGameGoldHistoryRsp.nIdOfStart = tData.nIdOfStart
    ClubSGetGameGoldHistoryRsp.nAllCnt = tData.nAllCnt
    ClubSGetGameGoldHistoryRsp.nStartTime = tData.nStartTime
    ClubSGetGameGoldHistoryRsp.nEndTime = tData.nEndTime
    MsgApi.SendToUser2(tData.nUserId,"ClubSGetGameGoldHistoryRsp",ClubSGetGameGoldHistoryRsp)
end

-- 局内消耗详情
function MsgClient.OnClubSGetGameGoldDetailReq(sClientID, Data, nLen)
    Base.Log("OnClubSGetGameGoldDetailReq 开始")
    local strProto = "ClubSGetGameGoldDetailReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if tData.sTableId and tData.sPaiJuId and tData.nStartTime then
        Base.Log("OnClubSGetGameGoldHistoryReq sTableId_%s sPaiJuId_%s nStartTime_%s",tData.sTableId,tData.sPaiJuId, tData.nStartTime)
    end

    local ClubGetGameGoldDetailReq = {}
    ClubGetGameGoldDetailReq.nUserId = nUserId
    ClubGetGameGoldDetailReq.sTableId = tData.sTableId
    ClubGetGameGoldDetailReq.sPaiJuId = tData.sPaiJuId
    ClubGetGameGoldDetailReq.nStartTime = tData.nStartTime
    MsgApi.SendToDBServer1("ClubGetGameGoldDetailReq",ClubGetGameGoldDetailReq,nUserId)
end

--DB服返回 局内消耗详情
function MsgClient.OnClubGetGameGoldDetailRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetGameGoldDetailRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    local arrRecords = {}
    for k,v in pairs(tData.arrRecord) do
        if v.nId and v.nId>0 then
            local t = {}
            t.nId = v.nId
            t.nChange = v.nChange
            t.sTime = v.sTime
            t.nSourceType = v.nSourceType
            table.insert(arrRecords,t)
        end
    end

    Base.Log("OnClubGetGameGoldDetailRsp nUserId_%d #arrRecords_%d",tData.nUserId,#arrRecords)
    local ClubSGetGameGoldDetailRsp = {}
    ClubSGetGameGoldDetailRsp.arrRecord = arrRecords
    MsgApi.SendToUser2(tData.nUserId,"ClubSGetGameGoldDetailRsp",ClubSGetGameGoldDetailRsp)
end

-- 内部转币
function MsgClient.OnClubSGoldTransToUserReq(sClientID, Data, nLen)
    Base.Log("OnClubSGoldTransToUserReq 开始")
    local strProto = "ClubSGoldTransToUserReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    local config = SlaveData.GetConfig(GlobalConfigKey.TransferOpen)
    if not config then
        MsgApi.SendToUser2(nUserId,"ClubSGoldTransToUserRsp",{nRlt = 4})
        return
    end
    if tonumber(config.open) == 0 then
        MsgApi.SendToUser2(nUserId,"ClubSGoldTransToUserRsp",{nRlt = 4})
        return
    end
    if tData.nUserId and tData.nAmount then
        Base.Log("OnClubSGoldTransToUserReq nUserId_%d tData.nUserId_%d nAmount_%.2f",nUserId,tData.nUserId, tData.nAmount)
    end
    if tData.nAmount <= 0 then
        MsgApi.SendToUser2(nUserId,"ClubSGoldTransToUserRsp",{nRlt = 2})
        return
    end
    local tUserInfo = PublicUserInfo.GetUserInfo(nUserId) or {}
    -- if tUserInfo.sSafePassWard ~= tData.nPassWord then
    --     MsgApi.SendToUser2(nUserId,"ClubSGoldTransToUserRsp",{nRlt = 5})
    --     return
    -- end
    if tUserInfo.isBan then
        MsgApi.SendToUser2(nUserId,"ClubSGoldTransToUserRsp",{nRlt = 4})
        return
    end
    local ClubGoldTransUserReq = {}
    ClubGoldTransUserReq.nUserId = nUserId
    ClubGoldTransUserReq.nAmount = tData.nAmount
    ClubGoldTransUserReq.nTUserId = tData.nUserId
    ClubGoldTransUserReq.nName = tUserInfo.sNickName
    ClubGoldTransUserReq.nTname = tData.nName
    MsgApi.SendToDBServer1("ClubGoldTransUserReq",ClubGoldTransUserReq,nUserId)
end

--DB服返回 内部转币
function MsgClient.OnClubGoldTransUserRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGoldTransUserRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    Base.Log("OnClubGoldTransUserRsp nUserId_%d nRlt_%d",tData.nUserId, tData.nRlt)
    local ClubSGoldTransToUserRsp = {}
    ClubSGoldTransToUserRsp.nRlt = tData.nRlt
    MsgApi.SendToUser2(tData.nUserId,"ClubSGoldTransToUserRsp",ClubSGoldTransToUserRsp)
end

-- 可存证hash请求
function MsgClient.OnClubSHashListReq(sClientID, Data, nLen)
    -- Base.Log("OnClubSHashListReq 开始")
    local strProto = "ClubSHashListReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if tData.sTableId and tData.sPaiJuId then
        Base.Log("OnClubSHashListReq sTableId_%s sPaiJuId_%s",tData.sTableId,tData.sPaiJuId)
    end

    local ClubGetHashListReq = {}
    ClubGetHashListReq.nUserId = nUserId
    ClubGetHashListReq.sTableId = tData.sTableId
    ClubGetHashListReq.sPaiJuId = tData.sPaiJuId
    MsgApi.SendToDBServer1("ClubGetHashListReq",ClubGetHashListReq,nUserId)
end

--DB服返回 可存证hash请求
function MsgClient.OnClubGetHashListRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetHashListRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    Base.Log("OnClubGetHashListRsp nUserId_%d",tData.nUserId)
    local item = nil
    if tData.item then
        item = {}
        item.sPaiJuId = tData.item.sPaiJuId
        item.sTime = tData.item.sTime
        item.hash = tData.item.hash
        item.cards = tData.item.cards
        item.hand = tData.item.hand
        item.nPlayCnt = tData.item.nPlayCnt
        item.seed = tData.item.seed
        item.show = tData.item.show
        item.nCards = tData.item.nCards
        item.nDetail = tData.item.nDetail
        item.fTime = tData.item.fTime
        Base.Log("OnClubGetHashListRsp item_%s",Cjson.encode(item))
    end
    local ClubSHashListRsp = {}
    ClubSHashListRsp.item = item
    MsgApi.SendToUser2(tData.nUserId,"ClubSHashListRsp",ClubSHashListRsp)
end

-- Hash指定局牌序列请求
function MsgClient.OnClubSHashCardReq(sClientID, Data, nLen)
    Base.Log("OnClubSHashCardReq 开始")
    local strProto = "ClubSHashCardReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if tData.sTableId and tData.sPaiJuId then
        Base.Log("OnClubSHashCardReq sTableId_%s sPaiJuId_%s",tData.sTableId,tData.sPaiJuId)
    end
    local name = CostName.Hash
    local cost = SlaveData.GetConfigCost(GlobalConfigKey.CostConfigs, name)
    local ClubGetHashCardReq = {}
    ClubGetHashCardReq.nUserId = nUserId
    ClubGetHashCardReq.sTableId = tData.sTableId
    ClubGetHashCardReq.sPaiJuId = tData.sPaiJuId
    ClubGetHashCardReq.nCost = cost
    MsgApi.SendToDBServer1("ClubGetHashCardReq",ClubGetHashCardReq,nUserId)
end

--DB服返回 Hash指定局牌序列请求
function MsgClient.OnClubGetHashCardRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetHashCardRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    Base.Log("OnClubGetHashCardRsp nUserId_%d",tData.nUserId)
    local ClubSHashCardRsp = {}
    ClubSHashCardRsp.nRlt = tData.nRlt
    ClubSHashCardRsp.nCards = tData.nCards
    ClubSHashCardRsp.nDetail = tData.nDetail
    MsgApi.SendToUser2(tData.nUserId,"ClubSHashCardRsp",ClubSHashCardRsp)
end

--在线用户请求
function MsgClient.OnClubSOnlineUserReq(sClientID, Data, nLen)
    local strProto = "ClubSOnlineUserReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    local nCnt = tData.nCnt or 0
    local nIdOfStart = tData.nIdOfStart or 0
    if nCnt <= 0 then
        nCnt = 10
    elseif nCnt > 30 then
        nCnt = 30
    end
    if nIdOfStart < 0 then
        nIdOfStart = 0
    end
    -- 尝试解码 sStr，防止异常
    local sStr = ""
    if tData.str and #tData.str > 0 then
        local ok, decodeResult = pcall(BaseSink.decode, tData.str)
        if ok and type(decodeResult) == "string" then
            sStr = decodeResult
        else
            sStr = tData.str
        end
    end
    local ClubSOnlineUserRsp = {}
    local UserItem = {}
    ClubSOnlineUserRsp.arrUser = UserItem
    ClubSOnlineUserRsp.nIdOfStart = 0
    ClubSOnlineUserRsp.nAllCnt = 0
    local tUser = UserManager.GetUserInfo(nUserId)
    local nShopId =tonumber(tUser.nShopId) or -1
    Base.Log("ClubSOnlineUserReq str:%s nIdOfStart:%d nCnt:%d nShopId:%d",tData.str, nIdOfStart, nCnt, nShopId)
    local ids = PublicUserInfo.GetGameMingUsers(nShopId)
    Base.Log("ClubSOnlineUserReq str:%s ids:%d", sStr, #ids)
    if #ids == 0 then
        MsgApi.SendToUser2(nUserId,"ClubSOnlineUserRsp",ClubSOnlineUserRsp)
        return
    end
    table.sort(ids, function(a, b) return a < b end)
    -- 筛选条件（昵称包含或UserID匹配）
    if sStr ~= "" then
        local searchLower = (sStr)
        for _, userId in ipairs(ids) do
            if nUserId ~= userId then
                local tUserInfo = PublicUserInfo.GetUserInfo(userId)
                if tUserInfo then
                    local nIsSeat = tonumber(tUserInfo.nIsSeat) or 0
                    local sNickName = (tUserInfo.sNickName or "")
                    local nick = BaseSink.decode(sNickName)
                    Base.Log("ClubSOnlineUserReq sNickName%s nick:%s", sNickName, nick)
                    local sUserId = tostring(userId)
                    if string.find(nick, searchLower, 1, true) or string.find(sUserId, sStr, 1, true) then
                        table.insert(UserItem, {nUserId = userId, sFaceId = tUserInfo.sFaceID or "1", sName = tUserInfo.sNickName or "", nStatus = nIsSeat})
                    end
                end
            end
        end
        ClubSOnlineUserRsp.nAllCnt = #UserItem
        MsgApi.SendToUser2(nUserId,"ClubSOnlineUserRsp",ClubSOnlineUserRsp)
        return
    end
    local nEndIdx = math.min(nIdOfStart + nCnt, #ids)
    ClubSOnlineUserRsp.nAllCnt = #ids
    for i = nIdOfStart + 1, nEndIdx do
        local userId = ids[i]
        if nUserId ~= userId then
            local tUserInfo = PublicUserInfo.GetUserInfo(userId)
            if tUserInfo then
                local nIsSeat = tonumber(tUserInfo.nIsSeat) or 0
                local item = {}
                item.nUserId = userId
                item.sFaceId = tUserInfo.sFaceID or "1"
                item.sName = tUserInfo.sNickName or ""
                item.nStatus = nIsSeat
                table.insert(UserItem, item)
            end
        end
    end
    MsgApi.SendToUser2(nUserId,"ClubSOnlineUserRsp",ClubSOnlineUserRsp)
end

--邀请玩家进入牌局请求
function MsgClient.OnClubSInvitePlayGameReq(sClientID, Data, nLen)
    local strProto = "ClubSInvitePlayGameReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("ClubSInvitePlayGameReq nUserId:%d sTableId:%s nGameId:%d",tData.nUserId, tData.sTableId, tData.nGameId)
    if tData.nUserId <= 0 then
        return
    end
    local tUser = UserManager.GetUserInfo(nUserId)
    local nShopId =tonumber(tUser.nShopId) or -1
    local ClubSInvitePlayGameRsp = {}
    ClubSInvitePlayGameRsp.nRlt = 0
    local tUserInfo = PublicUserInfo.GetUserInfo(tData.nUserId)
    if not tUserInfo then
        ClubSInvitePlayGameRsp.nRlt = 3
        MsgApi.SendToUser2(nUserId,"ClubSInvitePlayGameRsp",ClubSInvitePlayGameRsp)
        return
    end
    local shopId = tonumber(tUserInfo.nShopID) or -1
    if nShopId ~= shopId then
        Base.Log("ClubSInvitePlayGameReq diff shop nUserId:%d shopId:%d nShopId:%d", nUserId, shopId, nShopId)
        ClubSInvitePlayGameRsp.nRlt = 3
        MsgApi.SendToUser2(nUserId,"ClubSInvitePlayGameRsp",ClubSInvitePlayGameRsp)
        return
    end
    local nIsSeat = tonumber(tUserInfo.nIsSeat) or 0
    if nIsSeat > 0 then
        ClubSInvitePlayGameRsp.nRlt = 2
        MsgApi.SendToUser2(nUserId,"ClubSInvitePlayGameRsp",ClubSInvitePlayGameRsp)
        return
    end
    Base.Log("ClubSInvitePlayGameReq sName:%s nPos:%d nSmallBlind:%.2f nBigBlind:%.2f nZhuaTou:%.2f nPreAnte:%.2f nTakeInMin:%.2f sTableName:%s",
        tUser.sName, tData.nPos or 0, tData.nSmallBlind or 0, tData.nBigBlind or 0, tData.nZhuaTou or 0, tData.nPreAnte or 0, tData.nTakeInMin or 0, tData.sTableName or "")
    local ClubSInvitedPlayGameRsp = {}
    ClubSInvitedPlayGameRsp.nUserId = nUserId
    ClubSInvitedPlayGameRsp.sName = tUser.sName
    ClubSInvitedPlayGameRsp.sTableId = tData.sTableId
    ClubSInvitedPlayGameRsp.nGameId = tData.nGameId
    ClubSInvitedPlayGameRsp.nPos = tData.nPos
    ClubSInvitedPlayGameRsp.nSmallBlind = tData.nSmallBlind
    ClubSInvitedPlayGameRsp.nBigBlind = tData.nBigBlind
    ClubSInvitedPlayGameRsp.nZhuaTou = tData.nZhuaTou
    ClubSInvitedPlayGameRsp.nPreAnte = tData.nPreAnte
    ClubSInvitedPlayGameRsp.nTakeInMin = tData.nTakeInMin
    ClubSInvitedPlayGameRsp.sTableName = tData.sTableName or ""
    ClubSInvitedPlayGameRsp.nIsPerson = tData.nIsPerson or 0
    ClubSInvitedPlayGameRsp.preAnteOdd = tData.preAnteOdd
    Base.LogT("ClubSInvitedPlayGameRsp", ClubSInvitedPlayGameRsp)
    MsgApi.SendToUser2(tData.nUserId, "ClubSInvitedPlayGameRsp",ClubSInvitedPlayGameRsp)
end

--收到邀请回复
function MsgClient.OnClubSInvitedPlayGameReq(sClientID, Data, nLen)
    local strProto = "ClubSInvitedPlayGameReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("ClubSInvitedPlayGameReq nUserId:%d nRlt:%d",tData.nUserId, tData.nRlt)
    if tData.nUserId <= 0 then
        return
    end
    local ClubSInvitePlayGameRsp = {}
    ClubSInvitePlayGameRsp.nRlt = tData.nRlt or 0
    MsgApi.SendToUser2(tData.nUserId, "ClubSInvitePlayGameRsp",ClubSInvitePlayGameRsp)
end

-- 牌桌模板获取
function MsgClient.OnClubSTableModuleListReq(sClientID, Data, nLen)
    Base.Log("ClubSTableModuleListReq 开始")
    local strProto = "ClubSTableModuleListReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    local ClubGetTableModuleListReq = {}
    ClubGetTableModuleListReq.nUserId = nUserId
    MsgApi.SendToDBServer1("ClubGetTableModuleListReq",ClubGetTableModuleListReq,nUserId)
end

--DB服返回 牌桌模板获取
function MsgClient.OnClubGetTableModuleListRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetTableModuleListRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    local nList = {}
    if tData.nList then
        for _, v in pairs(tData.nList) do
            table.insert(nList, v)
        end
    end
    Base.Log("ClubGetTableModuleListRsp nUserId_%d",tData.nUserId)
    local ClubSTableModuleListRsp = {}
    ClubSTableModuleListRsp.nList = nList
    MsgApi.SendToUser2(tData.nUserId,"ClubSTableModuleListRsp",ClubSTableModuleListRsp)
end

-- 牌桌模板保存
function MsgClient.OnClubSTableModuleSaveReq(sClientID, Data, nLen)
    Base.Log("ClubSTableModuleSaveReq 开始")
    local strProto = "ClubSTableModuleSaveReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("ClubSTableModuleSaveReq nGameId_%d name_%s content:%s",tData.nGameId,tData.name,tData.content)

    local ClubTableModuleSaveReq = {}
    ClubTableModuleSaveReq.nUserId = nUserId
    ClubTableModuleSaveReq.nGameId = tData.nGameId
    ClubTableModuleSaveReq.name = tData.name
    ClubTableModuleSaveReq.content = tData.content
    ClubTableModuleSaveReq.nId = tData.nId or 0
    MsgApi.SendToDBServer1("ClubTableModuleSaveReq",ClubTableModuleSaveReq,nUserId)
end

--DB服返回 牌桌模板保存
function MsgClient.OnClubTableModuleSaveRsp(sReturnKey, Data, nLen)
    local strProto = "ClubTableModuleSaveRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    Base.Log("ClubTableModuleSaveRsp nUserId_%d",tData.nUserId)
    local nModule = nil
    if tData.nRlt == 0 then
        nModule = nModule
    end
    local ClubSTableModuleSaveRsp = {}
    ClubSTableModuleSaveRsp.nRlt = tData.nRlt
    ClubSTableModuleSaveRsp.nModule = tData.nModule
    MsgApi.SendToUser2(tData.nUserId,"ClubSTableModuleSaveRsp",ClubSTableModuleSaveRsp)
end

-- 标记玩家请求
function MsgClient.OnClubSMarkUserReq(sClientID, Data, nLen)
    Base.Log("OnClubSMarkUserReq 开始")
    local strProto = "ClubSMarkUserReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    Base.Log("OnClubSMarkUserReq nUserId_%d name_%s nColorId:%d",tData.nUserId, tData.nText or "",tData.nColorId or 0)
    if tData.nUserId <= 0 then
        return
    end

    local ClubMarkUserReq = {}
    ClubMarkUserReq.nUserId = nUserId
    ClubMarkUserReq.nTarUid = tData.nUserId
    ClubMarkUserReq.nText = tData.nText
    ClubMarkUserReq.nColorId = tData.nColorId
    ClubMarkUserReq.nIsMark = true
    MsgApi.SendToDBServer1("ClubMarkUserReq",ClubMarkUserReq,nUserId)
end

--DB服返回 标记玩家请求
function MsgClient.OnClubMarkUserRsp(sReturnKey, Data, nLen)
    local strProto = "ClubMarkUserRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    Base.Log("ClubMarkUserRsp nUserId_%d",tData.nUserId)
    local ClubMarkUserRsp = {}
    ClubMarkUserRsp.nRlt = tData.nRlt
    ClubMarkUserRsp.nText = tData.nText
    ClubMarkUserRsp.nColorId = tData.nColorId
    MsgApi.SendToUser2(tData.nUserId,"ClubSMarkUserRsp",ClubMarkUserRsp)
end

--全局配置变更通知
function MsgClient.OnVerifyNotify(sReturnKey,Data,nLen)
    local tData = BackstageAux:Parser(Data, nLen, "GloBalConfigNotice")
    if not tData then
        Base.Log("OnGloBalConfigNotice _Parse Err")
        return
    end
    Base.Log("_GloBalConfigNotice name:%s isDel:%s", tData.name, tostring(tData.isDel or false))
    if tData.isDel then
        SlaveData.globalConfig[tData.name] = nil
        return
    else
        local value = tPublicRedis.HgetRedis1(GlobalConfigKey.ConfigKey, tData.name)
        if value and value ~= "" then
            SlaveData.globalConfig[tData.name] = Cjson.decode(value)
            if tData.name == GlobalConfigKey.ChangeNameTime then
                UserOnTime.TryRestartReNameTimer()
            end
        else
        end
        if tData.name ~= GlobalConfigKey.TransferOpen and tData.name ~= GlobalConfigKey.CostConfigs then
            return
        end
        local tClubConfig = {}
        tClubConfig.transferOpen = {open = 0}
        local config = SlaveData.GetConfig(GlobalConfigKey.TransferOpen)
        if config then
            tClubConfig.transferOpen.open = tonumber(config.open)
        end
        tClubConfig.costConfigs = {}
        local config1 = SlaveData.GetConfig(GlobalConfigKey.CostConfigs)
        if config1 then
            tClubConfig.costConfigs = config1
        end

        local ClubSGetClubConfigResp = {}
        ClubSGetClubConfigResp.sClubConfig = Cjson.encode(tClubConfig)
        local arrClientID = UserManager.GetAllUserClientID()
        MsgApi.SendToGateWay("ClubSGetClubConfigResp",ClubSGetClubConfigResp,arrClientID)
    end
end

-- 全局配置变更通知
function MsgClient.OnGloBalConfigNotice(sReturnKey, Data, nLen)
    local tData = BackstageAux:Parser(Data, nLen, "GloBalConfigNotice")
    if not tData then
        Base.Log("OnGloBalConfigNotice _Parse Err")
        return
    end
    Base.Log("_GloBalConfigNotice name:%s isDel:%s", tData.name, tostring(tData.isDel or false))
    if tData.isDel then
        SlaveData.globalConfig[tData.name] = nil
        return
    else
        local value = tPublicRedis.HgetRedis1(GlobalConfigKey.ConfigKey, tData.name)
        if value and value ~= "" then
            SlaveData.globalConfig[tData.name] = Cjson.decode(value)
        else
        end
    end
    -- GameConfig.ReloadGlobalConfig(tData.name)
end

-- 看牌操作
function MsgClient.OnClubSLookCardReq(sClientID, Data, nLen)
    Base.Log("OnClubSLookCardReq 开始")
    local strProto = "ClubSLookCardReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if tData.nType <= 0 or tData.nType > 2 then
        MsgApi.SendToUser2(nUserId,"ClubSLookCardRsp",{nRlt = 3, nType = tData.nType})
        return
    end
    Base.Log("OnClubSLookCardReq tData.sPaiJuID:%s", tData.sPaiJuID or "")
    local ClubSLookCardRsp = {}
    ClubSLookCardRsp.nRlt = 0
    ClubSLookCardRsp.nType = tData.nType
    -- local name = (tData.nType == 1) and CostName.FaFaKan or CostName.TouTouKan
    -- local cost = SlaveData.GetConfigCost(GlobalConfigKey.CostConfigs, name)
    local cost = tData.nCost
    local nSourceType = (tData.nType == 1) and Define.SourceType.LookCards or Define.SourceType.LookHands
    local ok = true
    if cost > 0 then
        ok = tPubUsrApi.ChangeUserTreasure({
            nUserID = tonumber(nUserId),
            nItemID = 1,
            nDel = -cost,
            nSourceType = nSourceType,
            sTableId = tData.sTableID,
            sPaiJuId = tData.sPaiJuId,
        })
    end
    if not ok then
        ClubSLookCardRsp.nRlt = 2
    end
    MsgApi.SendToUser2(nUserId,"ClubSLookCardRsp",ClubSLookCardRsp)
    if ClubSLookCardRsp.nRlt == 0 then
        local CluUpdatePlaybackDataReq = {}
        CluUpdatePlaybackDataReq.nUserId = tonumber(nUserId)
        CluUpdatePlaybackDataReq.nType = tData.nType
        CluUpdatePlaybackDataReq.sPaiJuID = tData.sPaiJuID
        MsgApi.SendToDBServer1("CluUpdatePlaybackDataReq",CluUpdatePlaybackDataReq,nUserId)
    end
end

--私人房密码验证
function MsgClient.OnClubSTablePassReq(sClientID, Data, nLen)
    local strProto = "ClubSTablePassReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        Base.Log("OnClubSTablePassReq  isCheckPass is false ")
        return
    end
    Base.Log("OnClubSTablePassReq sTableId:%s,nUserId:%d,nPass:%s",tData.sTableId,nUserId,tData.nPass)

    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("OnClubSTablePassReq 玩家信息不存在")
        return
    end
    local nGroupId = tonumber(tUser.nGroupId) or -1
    local nClubId = nGroupId
    --俱乐部不存在
    local tClub = ClubSManager.GetClub(nClubId)
    if not tClub then
        Base.Log("OnClubSTablePassReq 俱乐部不存在")
        return
    end
    local ok, pass = tClub:CheckPass(tData.sTableId, tData.nPass)
    Base.Log("OnClubSTablePassReq ok:%s pass:%s", tostring(ok), pass)
    local ClubSTablePassRsp = {}
    ClubSTablePassRsp.nRlt = ok and 0 or 1
    MsgApi.SendToUser2(nUserId,"ClubSTablePassRsp",ClubSTablePassRsp)
end

-- 获取充提账单
function MsgClient.OnClubSGetBillRecordReq(sClientID, Data, nLen)
    Base.Log("ClubSGetBillRecordReq 开始")
    local strProto = "ClubSGetBillRecordReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    local nIdOfStart = tData.nIdOfStart or 0
    if nIdOfStart < 0 then
        nIdOfStart = 0
    end
    local nCnt = tData.nCnt or 15
    if nCnt > 15 then
        nCnt = 15
    end

    local ClubGetBillRecordReq = {}
    ClubGetBillRecordReq.nUserId = nUserId
    ClubGetBillRecordReq.nIdOfStart = nIdOfStart
    ClubGetBillRecordReq.nCnt = nCnt
    ClubGetBillRecordReq.nType = tData.nType
    MsgApi.SendToDBServer1("ClubGetBillRecordReq",ClubGetBillRecordReq,nUserId)
end

--DB服返回 获取充提账单
function MsgClient.OnClubGetBillRecordRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetBillRecordRsp"
    local tData = MsgClient._CheckDbClub1Msg(strProto, Data, nLen)
    if not tData then
        return
    end
    local arrRecords = {}
    for k,v in pairs(tData.arrRecord) do
        if v.nId and v.nId>0 then
            local t = {}
            t.nId = v.nId
            t.nOrderId = v.nOrderId
            t.nAmount = v.nAmount
            t.nRealAmount = v.nRealAmount
            t.nFromAddr = v.nFromAddr
            t.nToAddr = v.nToAddr
            t.nStatus = v.nStatus
            t.nTxHash = v.nTxHash
            t.fee = v.fee
            t.contract = v.contract
            t.nCreatetime = v.nCreatetime
            t.nUpdatetime = v.nUpdatetime
            t.nRemark = v.nRemark
            table.insert(arrRecords,t)
        end
    end

    Base.Log("ClubGetBillRecordRsp nUserId_%d #arrRecords_%d",tData.nUserId,#arrRecords)
    local ClubSGetBillRecordRsp = {}
    ClubSGetBillRecordRsp.arrRecord = arrRecords
    ClubSGetBillRecordRsp.nIdOfStart = tData.nIdOfStart
    ClubSGetBillRecordRsp.nAllCnt = tData.nAllCnt
    ClubSGetBillRecordRsp.nType = tData.nType
    MsgApi.SendToUser2(tData.nUserId,"ClubSGetBillRecordRsp",ClubSGetBillRecordRsp)
end

--Web服通知
function MsgClient.OnWebNotify(sReturnKey, Data, nLen)
    local tData =WebAux:Parser(Data, nLen,"WebUrlRsp")
    if not tData then
        Base.Log("WebUrlRsp _Parse Err")
        return
    end

    Base.Log("_WebUrlRsp Web服返回 sJsonData:%s sCode:%d",tData.sJsonData,tData.nCode)

    local ClubRechargeWithdrawalRsp = {}
    ClubRechargeWithdrawalRsp.nUserId = tData.nUserId
    ClubRechargeWithdrawalRsp.res = tData.sJsonData
    MsgApi.SendToUser2(tData.nUserId,"ClubRechargeWithdrawalRsp",ClubRechargeWithdrawalRsp)
end

--明文密码请求
function MsgClient.OnClubSUserMWStringReq(sClientID,Data,nLen)
    local strProto = "ClubSUserMWStringReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end

    Base.Log("_OnClubSUserMWStringReq 明文请求 前端传来的加密值_%s",tData.mwString)

    -- local before = ssl.base64decode(tData.mwString)
    -- Base.Log("_OnClubSUserMWStringReq 明文请求 nUserId_%d,解密出前端的值_%s",nUserId,before)
    -- local after = ssl.encodeBase64(before)
    -- Base.Log("加密后存入数据库的值_%s",after)

    local ClubAddiInfoChangeReq = {}
    ClubAddiInfoChangeReq.nUserId = nUserId
    ClubAddiInfoChangeReq.nAddiInfo = tData.mwString
    MsgApi.SendToDBServer("ClubAddiInfoChangeReq",ClubAddiInfoChangeReq,nUserId)
end

--DB服返回 明文密码 返回
function MsgClient.OnDBClubAddiInfoChangeRsp(sReturnKey, Data, nLen)
    local strProto = "ClubAddiInfoChangeRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end

    local ClubSUserMWStringRsp = {}
    ClubSUserMWStringRsp.nRlt = tData.nRlt
    MsgApi.SendToUser(tData.nUserId,"ClubSUserMWStringRsp",ClubSUserMWStringRsp)
end

--网关 连接关闭通知
function MsgClient.OnClose(sClientID, Data, nLen)
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId  then
        Base.Log("_OnClose 连接关闭通知  nUserId is nil  sClientID_%s ",sClientID)
        return
    elseif nUserId < 0  then 
        Base.Log("_OnClose 连接关闭通知 nUserId_%d  < 0 ",nUserId)
        ClientIdMgr.DestroyClientID(sClientID)
        return
    end
    ClientIdMgr.DestroyClientID(sClientID)
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then 
        Base.Log("_OnClose 连接关闭通知 nUserId_%d   tUser is nil  ",nUserId)
        return    
    end
    Base.Log("_OnClose 连接关闭通知 nUserId_%d",nUserId)
    local nNowClubId = tUser:GetNowClub()
    if nNowClubId~=0 then
        --有所在的俱乐部
        local tClub = ClubSManager.GetClub(nNowClubId)
        if tClub then
            tClub:Leave(nUserId)
        else
            UserManager.DelUser(nUserId)
        end
    else
        UserManager.DelUser(nUserId)
    end
    UserOnTime.deleteUserData(nUserId)
end
 
--网关 连接切换通知
function MsgClient.OnSwicthConn(sClientID, Data, nLen)
    local ReadData = Base.GetRP().new(Data, nLen)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 
    local Read = ProtoManager.Gateway_pb.RUQ_SwicthConn()
    Read:ParseFromString(ReadData:GetString())
    local nUserId =Read.nUserID or -1
    local oldClientId =ClientIdMgr.GetClientIdByUserId(nUserId)
    if not oldClientId then
        return
    end
    Base.Log("nUserId_%d connection Swicth",nUserId)
    ClientIdMgr.DestroyClientID(oldClientId)  
end

return MsgClient