--机器人借出统计
local tPublicApi = require("publicApi")
local tAndroidData = require("AndroidData")
local NameLibMgr = require("NameLibMgr")
local tPublicRedis = require("PublicRedis")
local tALog = require("AndroidLog")
local AndroidMgr = require("AndroidMgr")
local Typename = require("typename")
local tBase = require("base")
local Define = require("Define")
local ProtoManager = require("ProtoManager")
local tSrvInfo = require("ServerInfo")
local cjson = require("cjson")

local RentalInfo = {}

--根据ServerKey获得游戏名称和服务器id
--@params ServerKey 服务器key 如1F7B948C50EC47BB9D87C397C1BB6565_BaiRenZhaJinHua162884731479687933493_322
--@return sGameName：服务器名字，如BaiRenZhaJinHua， sServerId：服务器id，如322
function RentalInfo.GetGameNameByServerKey(ServerKey)
    if not ServerKey then
        return ""
    end
    ServerKey = tPublicApi.GetServerKey(ServerKey)
    local arr = tPublicApi.Split(ServerKey, '_')
    local sServerId = (arr and arr[3]) or "0"
    local sTwo = (arr and arr[2]) or ""
    local sGameName = string.match(sTwo,"%a+") or ""
    return sGameName,sServerId
end

--输出机器人借出情况
function RentalInfo.ShowInfo()
    --各个游戏服机器人借出情况
    for sServerKey,tData in pairs(tAndroidData.tLendAndroid) do
        local sGameName,sServerId = RentalInfo.GetGameNameByServerKey(sServerKey)
        local str = string.format("_ShowInfo  服务器租用_%s serverId_%s :",sGameName,sServerId)
        local nTotal = 0
        for nGrpId,arrLendAn in pairs(tData) do
            local nGrpCnt,nAppAnCnt,nHJAnCnt,nNotNameCnt = RentalInfo.GetLendAndroidCnt(arrLendAn)
            str = str..string.format("分组_%d 借出_%d =[app_%d,合集_%d,非昵称_%d] ",nGrpId,nGrpCnt,nAppAnCnt,nHJAnCnt,nNotNameCnt)
            nTotal = nTotal + nGrpCnt
        end

        --记录失效的游戏服
        if nTotal>0 then
            local bExist = tBase.m_centerRedis.Mo:exists(sServerKey) or false
            if not bExist then  
                tALog.Print(string.format("_ShowInfo 游戏服key已失效,sServerKey:%s",sServerKey))
                if not tAndroidData.tServerKeyInexistence[sServerKey] then 
                    tAndroidData.tServerKeyInexistence[sServerKey] = os.time()
                end 
            else
                if tAndroidData.tServerKeyInexistence[sServerKey] then 
                    tAndroidData.tServerKeyInexistence[sServerKey] = nil 
                end             
            end
            tALog.Print(str)
        end
    end

    --各分组昵称使用情况
    local tUseUp = {} --各分组语言是否用完
    local tGrpCursors = tPublicRedis.GetAllUseAnNickCursor()
    for _, tGrp in pairs(NameLibMgr.tGrpCfg) do
        tUseUp[tGrp.nGrpId] = {}
        local str = string.format("_ShowInfo  分组_%d 昵称使用情况:",tGrp.nGrpId)
        for nLanguageId, tLNameLib in pairs(tGrp.tAnNameList) do
            local nCursors = tGrpCursors[tGrp.nGrpId] and tGrpCursors[tGrp.nGrpId][nLanguageId] or 0
            tALog.Print("_ShowInfo  分组_%d,nLanguageId_%d,昵称游标_%d ",tGrp.nGrpId,nLanguageId,nCursors)
            local nUnUseCnt = NameLibMgr.GetGrpUnUseNickCnt(tGrp.nGrpId,nLanguageId,nCursors)
            local nAllCnt  = #tLNameLib.arrAnNameList
            local nUseCnt = nAllCnt - nUnUseCnt
            local nRate = 0
            if nAllCnt > 0 then
                nRate =  tPublicApi.Floor_2(nUseCnt/nAllCnt * 100)
            end
            str = str..string.format("Language_%d 剩余[%d/%d] 已使用%d(%.2f%%%%),",nLanguageId,nUnUseCnt,nAllCnt,nUseCnt,nRate)
            if nRate>=100 and tAndroidData.nServerState==1 then
                tALog.SendMsgToTG(string.format("分组_%d,Language_%d 昵称已用完",tGrp.nGrpId,nLanguageId))
            end

            tUseUp[tGrp.nGrpId][nLanguageId] = {isUseUp=false,isApp=false}
            if nRate>=100 or nAllCnt==0 then
                tUseUp[tGrp.nGrpId][nLanguageId].isUseUp = true
            end

            local tName = tLNameLib.arrAnNameList[1] or {}
            if tName.sShopAcc~="0" and tName.sShopAcc ~= "" then
                tUseUp[tGrp.nGrpId][nLanguageId].isApp = true
            end
            if nLanguageId==4 or nLanguageId==5 then
                tUseUp[tGrp.nGrpId][nLanguageId].isApp = true
            end
        end
        if tAndroidData.nServerState==1 then
            tALog.Print(str)
        end
    end

    --检查是否有重复加载机器人
    local tServerAndroidId = tPublicRedis.GetAllServerLoadAndroid()
    local tLoadAndroidId = {}
    for nServerId,arrUserId in pairs(tServerAndroidId) do
        for _,nUserId in pairs(arrUserId) do
            if tLoadAndroidId[nUserId] and tLoadAndroidId[nUserId]~=nServerId then
                local str = string.format("_ShowInfo 重复加载机器人: nUserId_%d nServerId1_%d nServerId2_%d",
                nUserId,tLoadAndroidId[nUserId],nServerId)
                tALog.Print(str)
                tALog.SendMsgToTG(str)
            else
                tLoadAndroidId[nUserId] = nServerId
            end
        end
    end

    --各个分组机器人使用情况
    for nGrpId,arrAndroid in pairs(tAndroidData.arrAllAndroid) do
        local nTotal,nAppNameCnt,nHJNameCnt,nNotNameCnt = AndroidMgr.GetAndroidCnt(nGrpId) --机器人总数
        local nTotal_lend,nAppLendCnt,nHJLendCnt,nNoNameLendCnt = RentalInfo.GetGrpLendAndroidCnt(nGrpId) --借出的机器人数
        local nTotal_lendBR,nAppLendBRCnt,nHJLendBRCnt,nHJLendBRCnt = RentalInfo.GetGrpLendBRAndroidCnt(nGrpId) --借出给百人游戏的机器人数
        local nTotal_Free,nAppFreeCnt,nHJFreeCnt,nNotNameFreeCnt = AndroidMgr.GetFreeAndroidCnt(nGrpId) --空闲的机器人
        local nTotal_Rest,nAppRestCnt,nHJRestCnt,nNotNameRestCnt = AndroidMgr.GetRestAndroidCnt(nGrpId) --休息的机器人

        local arrAndroid_HJ = tPublicRedis.GetAndroidKey(nGrpId,1) or {}
        local arrAndroid_App = tPublicRedis.GetAndroidKey(nGrpId,2) or {}
        local nTotal_Redis = #arrAndroid_HJ + #arrAndroid_App

        local nAppRate,nBrAppRate,nHJRate,nBRHJRate = 0,0,0,0
        if nAppNameCnt>0 then
            nAppRate = tPublicApi.Floor_2(nAppLendCnt/nAppNameCnt*100)
            nBrAppRate = tPublicApi.Floor_2(nAppLendBRCnt/nAppNameCnt*100)
        end
        if nHJNameCnt>0 then
            nHJRate = tPublicApi.Floor_2(nHJLendCnt/nHJNameCnt*100)
            nBRHJRate = tPublicApi.Floor_2(nHJLendBRCnt/nHJNameCnt*100)
        end

        if tAndroidData.nServerState==1 then
            tALog.Print(string.format("_ShowInfo 分组_%d,app机器人_%d个,总共借出_%d个(%.2f%%%%),百人游戏借出_%d个(%.2f%%%%)",nGrpId,nAppNameCnt,nAppLendCnt,nAppRate,nAppLendBRCnt,nBrAppRate))
            tALog.Print(string.format("_ShowInfo 分组_%d,合集昵称机器人_%d个,总共借出_%d个(%.2f%%%%),百人游戏借出_%d个(%.2f%%%%)",nGrpId,nHJNameCnt,nHJLendCnt,nHJRate,nHJLendBRCnt,nBRHJRate))
            -- if nNotNameCnt and nNotNameCnt>0 then
            --     tALog.Print(string.format("[RentalInfo.ShowInfo]分组%d,非昵称机器人%d个,总共借出%d个,百人游戏借出%d个",nGrpId,nNotNameCnt,nNoNameLendCnt,nHJLendBRCnt))
            -- end
            tALog.Print("_ShowInfo  分组_%d,空闲的机器人_%d个(app机器人_%d个,合集机器人_%d个,非昵称机器人_%d个)",nGrpId,nTotal_Free,nAppFreeCnt,nHJFreeCnt,nNotNameFreeCnt)
            tALog.Print("_ShowInfo  分组_%d,休息的机器人_%d个(app机器人_%d个,合集机器人_%d个,非昵称机器人_%d个)",nGrpId,nTotal_Rest,nAppRestCnt,nHJRestCnt,nNotNameRestCnt)

            if nAppRate>=90 and nAppRate<=100  then
                --app机器人使用过多
                local isUseUp = true --昵称是否用完
                for _,v in pairs(tUseUp[nGrpId] or {}) do
                    if v.isApp and not v.isUseUp then
                        isUseUp = false
                    end
                end
                if isUseUp then
                    local sKey = string.format("分组_%d,app机器人借出%d%%",nGrpId,math.floor(nAppRate))
                    local str = string.format("分组%d,app机器人%d个,总共借出%d个(%.2f%%),百人游戏借出%d个(%.2f%%)",nGrpId,nAppNameCnt,nAppLendCnt,nAppRate,nAppLendBRCnt,nBrAppRate)
                    tALog.SendMsgToTG(sKey,str)
                end
            end
    
            if nHJRate>=90 and nHJRate<=100  then
                --合集昵称机器人使用过多
                local isUseUp = true --昵称是否用完
                for _,v in pairs(tUseUp[nGrpId] or {}) do
                    if not v.isApp and not v.isUseUp then
                        isUseUp = false
                    end
                end
                if isUseUp then
                    local sKey = string.format("分组_%d,合集昵称机器人借出%d%%",nGrpId,math.floor(nHJRate))
                    local str = string.format("分组%d,合集昵称机器人%d个,总共借出%d个(%.2f%%),百人游戏借出%d个(%.2f%%)",nGrpId,nHJNameCnt,nHJLendCnt,nHJRate,nHJLendBRCnt,nBRHJRate)
                    tALog.SendMsgToTG(sKey,str)
                end
            end
        end

        RentalInfo.SendAndroidDetailToDB(nGrpId,nTotal_Redis,"HJAndroid",nHJNameCnt,nHJRestCnt,nHJLendCnt,nHJFreeCnt)
        RentalInfo.SendAndroidDetailToDB(nGrpId,nTotal_Redis,"AppAndroid",nAppNameCnt,nAppRestCnt,nAppLendCnt,nAppFreeCnt)
        -- if nNotNameCnt and nNotNameCnt>0 then
        --     RentalInfo.SendAndroidDetailToDB(nGrpId,nTotal_Redis,"NoNameAndroid",nNotNameCnt,nNotNameRestCnt,nNoNameLendCnt,nNotNameFreeCnt) 
        -- end
    end

    RentalInfo.DetectionGameServerKey()
end

--统计借出机器人数量
--@params tData {[nUserId]=tAnItem,...}
--@return 分组数量,app机器人数量，合集机器人数量，非昵称机器人数量
function RentalInfo.GetLendAndroidCnt(tData)
    local nGrpCnt = 0
    local nAppAnCnt = 0
    local nHJAnCnt = 0
    local nNotNameCnt = 0
    for nUserId,tAnItem in pairs(tData) do
        nGrpCnt = nGrpCnt + 1
        if tAnItem.sShopAcc=="" then
            nNotNameCnt = nNotNameCnt + 1
        elseif tAnItem.sShopAcc=="0" then
            nHJAnCnt = nHJAnCnt + 1
        else
            nAppAnCnt = nAppAnCnt + 1
        end
    end
    return nGrpCnt,nAppAnCnt,nHJAnCnt,nNotNameCnt
end

--统计某个分组借出的机器人数量
--@Params nGrpId 分组id
--@return 分组数量,app机器人数量，合集机器人数量，非昵称机器人数量
function RentalInfo.GetGrpLendAndroidCnt(nGrpId)
    local nGrpLendCnt,nAppLendCnt,nHJLendCnt,nNotNameLendCnt = 0,0,0,0
    for sServerKey,tData in pairs(tAndroidData.tLendAndroid) do
        for nGroupId,arrLendAn in pairs(tData) do
            if nGroupId == nGrpId then
                local nGrpCnt,nAppAnCnt,nHJAnCnt,nNotNameCnt = RentalInfo.GetLendAndroidCnt(arrLendAn)
                nGrpLendCnt = nGrpLendCnt + nGrpCnt
                nAppLendCnt = nAppLendCnt + nAppAnCnt
                nHJLendCnt = nHJLendCnt + nHJAnCnt
                nNotNameLendCnt = nNotNameLendCnt + nNotNameCnt
            end
        end
    end
    return nGrpLendCnt,nAppLendCnt,nHJLendCnt,nNotNameLendCnt
end

--统计某个分组借出给百人游戏的机器人数量
--@Params nGrpId 分组id
--@return 分组数量,app机器人数量，合集机器人数量，非昵称机器人数量
function RentalInfo.GetGrpLendBRAndroidCnt(nGrpId)
    local nGrpLendBRCnt,nAppLendBRCnt,nHJLendBRCnt,nNotNameLendBRCnt = 0,0,0,0
    for sServerKey,tData in pairs(tAndroidData.tLendAndroid) do
        if RentalInfo.IsBRGame(sServerKey) then
            for nGroupId,arrLendAn in pairs(tData) do
                if nGroupId == nGrpId then
                    local nGrpCnt,nAppAnCnt,nHJAnCnt,nNotNameCnt = RentalInfo.GetLendAndroidCnt(arrLendAn)
                    nGrpLendBRCnt = nGrpLendBRCnt + nGrpCnt
                    nAppLendBRCnt = nAppLendBRCnt + nAppAnCnt
                    nHJLendBRCnt = nHJLendBRCnt + nHJAnCnt
                    nNotNameLendBRCnt = nNotNameLendBRCnt + nNotNameCnt
                end
            end
        end
    end
    return nGrpLendBRCnt,nAppLendBRCnt,nHJLendBRCnt,nNotNameLendBRCnt
end

--是否是百人游戏
--@params sServerKey 服务器key 如1F7B948C50EC47BB9D87C397C1BB6565_BaiRenZhaJinHua162884731479687933493_322
--@return true 是  false 不是
function RentalInfo.IsBRGame(sServerKey)
    local sGameName,sServerId = RentalInfo.GetGameNameByServerKey(sServerKey)
    local tBRGame = {}
    --直播
    tBRGame[121] = Typename.yuxiaxiecenter --直播鱼虾蟹
    tBRGame[122] = Typename.BaiJiaLeCenter --直播百家乐
    tBRGame[125] = Typename.yuxiaxieslave  --直播鱼虾蟹
    tBRGame[126] = Typename.BaiJiaLeSlave  --直播百家乐
    
    tBRGame[129] = Typename.FootBallCenter   --直播足球
    tBRGame[130] = Typename.FootBallSlave    --直播足球

    tBRGame[153] = Typename.SeDieMCenter   --直播色碟
    tBRGame[154] = Typename.SeDieMSlave    --直播色碟
    tBRGame[155] = Typename.toubaocenter   --直播骰宝
    tBRGame[156] = Typename.toubaoslave    --直播骰宝
    --合集
    tBRGame[104] = Typename.brniuniu --百人牛牛
    tBRGame[107] = Typename.baijiale --百家乐
    tBRGame[118] = Typename.BaiRenZhaJinHua --百人炸金花
    tBRGame[212] = Typename.yuxiaxieJH --合集鱼虾蟹
    tBRGame[151] = Typename.SeDie --合集色碟

    for nGameId,sGameName in pairs(tBRGame) do
        if sGameName == sGameName then
            return true
        end
    end
    return false
end

-- 检测 游戏服key 是否失效
function RentalInfo.DetectionGameServerKey() 
    -- 检查服务器超时 问题
    for ServerKey,nTime in pairs(tAndroidData.tServerKeyInexistence) do  
        if (os.time() - nTime) >= Define.nServerKeyTimeOut then
            --回收游戏服的机器人      
            tAndroidData.tServerKeyInexistence[ServerKey] = nil             
            local arrAndroid = {}
            local nCnt = 0
            local sUserId = ""
            for nGrpId,arrLendAn in pairs(tAndroidData.tLendAndroid[ServerKey]) do
                for nUserId,tItem in pairs(arrLendAn) do
                    local tAnItem = {}
                    for a, b in pairs(ProtoManager.PubProto_pb.AndroidItem()._setter) do 
                        tAnItem[a] = tItem[a]
                    end
                    if AndroidMgr.IsLend(nGrpId,nUserId) then
                        tALog.Print("_DetectionGameServerKey   自动回收机器人nUserId_%d",tAnItem.nUserId)

                        nCnt = nCnt + 1 
                        if nCnt <= 20 then 
                            sUserId= sUserId..tAnItem.nUserId..","
                        end
                        table.insert(arrAndroid,tAnItem)
                    end
                end  
            end
            tAndroidData.tLendAndroid[ServerKey] = {} 
            
            AndroidMgr.SetAndroidReturn(ServerKey,arrAndroid)
    
            local sSendSMS = string.format("_DetectionGameServerKey  ServerKey_%s 失效时间%d秒,已回收 %d 个机器人。",ServerKey,Define.nServerKeyTimeOut,nCnt)
            sSendSMS = sSendSMS..sUserId
            tALog.Print(sSendSMS)
            tALog.SendMsgToTG(sSendSMS,nil,Define.nServerKeyTimeOut)
        end  
    end 
    return
end

--输出游戏服的借出
--@params sClientID 服务器key 如1F7B948C50EC47BB9D87C397C1BB6565_BaiRenZhaJinHua162884731479687933493_322:0
function RentalInfo.ShowGameServerLend(sClientID)
    local sServerKey = tPublicApi.GetServerKey(sClientID)
    local tData = tAndroidData.tLendAndroid[sServerKey]
    if tData then
        local sGameName,sServerId = RentalInfo.GetGameNameByServerKey(sServerKey)
        local str = string.format("服务器借用情况:_%s(serverId_%s):",sGameName,sServerId)
        for nGrpId,arrLendAn in pairs(tData) do
            local nGrpCnt,nAppAnCnt,nHJAnCnt,nNotNameCnt = RentalInfo.GetLendAndroidCnt(arrLendAn)
            str = str..string.format(" 分组_%d 借出_%d=[app_%d,合集_%d,非昵称_%d] ",
            nGrpId,nGrpCnt,nAppAnCnt,nHJAnCnt,nNotNameCnt)
        end
        tALog.Print("_ShowGameServerLend "..str)
    end
end

--获取机器人类型
--@params nGrpId 分组id nGameId 游戏id
--@return nAnCfgId(1:合集机器人 2:app机器人),默认1
function RentalInfo.GetAnCfgId(sClientID,nGrpId)
    local sGameName = RentalInfo.GetGameNameByServerKey(sClientID)
    local nGameId = 0
    if sGameName == Typename.sangong then --三公
        nGameId = 113
    elseif sGameName == Typename.niuniu then --牛牛
        nGameId = 102
    elseif sGameName == Typename.brniuniu then --百人牛牛
        nGameId = 104
    elseif sGameName == Typename.zhajinhua then --扎金花
        nGameId = 105
    elseif sGameName == Typename.dian21 or sGameName == "dian"  then --21点
        nGameId = 106
    elseif sGameName == Typename.baijiale then --百家乐
        nGameId = 107
    elseif sGameName == Typename.mahjong then --麻将
        nGameId = 108
    elseif sGameName == Typename.qzbaijiale then --抢庄百家乐
        nGameId = 109
    elseif sGameName == Typename.tbbaijiale then --同比百家乐
        nGameId = 110
    elseif sGameName == Typename.paijiu then --牌九
        nGameId = 116
    elseif sGameName == Typename.BaiRenZhaJinHua then --百人扎金花
        nGameId = 118
    elseif sGameName == Typename.erbagang then --二八杠
        nGameId = 120
    elseif sGameName == Typename.yuxiaxieJH then --合集鱼虾蟹
        nGameId = 212
    elseif sGameName == Typename.gaobo then --高博
        nGameId = 128
    elseif sGameName == Typename.BoDeng then --博灯
        nGameId = 124
    elseif sGameName == Typename.SeDie then --合集色碟
        nGameId = 150
    elseif sGameName == Typename.yuxiaxieslave or sGameName == Typename.yuxiaxiecenter then --直播鱼虾蟹
        nGameId = 121
    elseif sGameName == Typename.BaiJiaLeSlave or sGameName == Typename.BaiJiaLeCenter then --直播百家乐
        nGameId = 122
    elseif sGameName == Typename.LongHuSlave or sGameName == Typename.LongHuCenter then --直播龙虎
        nGameId = 139
    elseif sGameName == Typename.pilotmslave or sGameName == Typename.pilotmcenter then --飞行棋
        nGameId = 133
    elseif sGameName == Typename.dezhouslave or sGameName == Typename.texas or sGameName == Typename.dezhoucenter then --德州
        nGameId = 123
    elseif sGameName == Typename.SeDieMSlave or sGameName == Typename.SeDieMCenter then --直播色碟
        nGameId = 153
    elseif sGameName == Typename.toubaoslave or sGameName == Typename.toubaocenter then --直播骰宝
        nGameId = 155
    elseif sGameName == Typename.FootBallSlave or sGameName == Typename.FootBallCenter then
        nGameId = 129
    elseif sGameName == Typename.FellTreeSlave or sGameName == Typename.FellTreeCenter then --砍树
        nGameId = 157
    elseif sGameName == Typename.BasketballSlave or sGameName == Typename.BasketballCenter then --篮球
        nGameId = 159
    elseif sGameName == Typename.TexasShortCardCenter or  sGameName == Typename.TexasShortCardSlave then --俱乐部德州短牌
        nGameId = 175
    elseif sGameName == Typename.clubdezhoucenter or sGameName == Typename.clubdezhouslave  then --俱乐部德州、奥马哈现共用一套 有问题就要分开
        nGameId = 125
    elseif sGameName == Typename.ClubQiangZhuangNiu  then --俱乐部抢庄牛
        nGameId = 178
    elseif sGameName == Typename.JackLot then       --彩票夺宝类游戏
        nGameId =306
    end

    local nAnCfgId = NameLibMgr.GetAnCfgId(nGrpId,nGameId)  --1:合集机器人(没有sShopAcc) 2:app
    if not nAnCfgId then
        if nGameId ==306 then
            nAnCfgId = 2
        else
            nAnCfgId = 1
        end
    end
    tALog.Print("_GetAnCfgId,nGrpId:%d nGameId:%d nAnCfgId:%d sGameName:%s",nGrpId,nGameId,nAnCfgId,sGameName)
    return nAnCfgId
end

--把机器人的使用信息写入数据库
--@params nGrpId:分组  nTotal：机器人总数 nWorking：使用中的机器人数 nRelax：休息的机器人数 nLending：借出的机器人数 nCanUse:空闲的机器人数
function RentalInfo.SendAndroidDetailToDB(nGrpId,nTotal,sIndex,nWorking,nRelax,nLending,nCanUse)
    local tSend = ProtoManager.PubProto_pb.Req_UpdateAndroidMysql()
    tSend.nSrvId = tSrvInfo.nServerId
    tSend.nGrpId = nGrpId
    tSend.sIndex = sIndex
    tSend.nTotal = nTotal
    tSend.nWorking = nWorking
    tSend.nRelax = nRelax
    tSend.nLending = nLending
    tSend.nCanUse = nCanUse

    local s = tBase.GetSP().new(ProtoManager.Sys.DB, ProtoManager.Sub_DB.SUB_REQ_UPDATEMYSQL)
    s:AddString(tSend:SerializeToString())
    tBase.PostDatasByType(Typename.db, 0, 0, s:GetData(), s:GetSize())
end

--统计机器人使用情况存 Redis 
function RentalInfo.StatisticsData()
    local arrData={}

    --各个游戏服机器人借出情况
    for sServerKey,tData in pairs(tAndroidData.tLendAndroid) do
        local sGameName,sServerId = RentalInfo.GetGameNameByServerKey(sServerKey) 
        local nTotal = 0
        for nGrpId,arrLendAn in pairs(tData) do
            local nGrpCnt,nAppAnCnt,nHJAnCnt,nNotNameCnt = RentalInfo.GetLendAndroidCnt(arrLendAn) 
            local t = {}
            t.nGroupGameCnt = nGrpCnt   
            t.nHJAnCnt = nHJAnCnt
            t.nAppAnCnt = nAppAnCnt
            t.nNotNameCnt = nNotNameCnt
            
        end
 
    end


    --各分组昵称使用情况
    local tUseUp = {} --各分组语言是否用完
    local tGrpCursors = tPublicRedis.GetAllUseAnNickCursor()
    for _, tGrp in pairs(NameLibMgr.tGrpCfg) do
        tUseUp[tGrp.nGrpId] = {}
        local str = string.format("_ShowInfo  分组_%d 昵称使用情况:",tGrp.nGrpId)
        for nLanguageId, tLNameLib in pairs(tGrp.tAnNameList) do
            local nCursors = tGrpCursors[tGrp.nGrpId] and tGrpCursors[tGrp.nGrpId][nLanguageId] or 0
            tALog.Print("_ShowInfo  分组_%d,nLanguageId_%d,昵称游标_%d ",tGrp.nGrpId,nLanguageId,nCursors)
            local nUnUseCnt = NameLibMgr.GetGrpUnUseNickCnt(tGrp.nGrpId,nLanguageId,nCursors)
            local nAllCnt  = #tLNameLib.arrAnNameList
            local nUseCnt = nAllCnt - nUnUseCnt
            local nRate = 0
            if nAllCnt > 0 then
                nRate =  tPublicApi.Floor_2(nUseCnt/nAllCnt * 100)
            end
            str = str..string.format("Language_%d 剩余[%d/%d] 已使用%d(%.2f%%%%),",nLanguageId,nUnUseCnt,nAllCnt,nUseCnt,nRate)
            if nRate>=100 and tAndroidData.nServerState==1 then
                tALog.SendMsgToTG(string.format("分组_%d,Language_%d 昵称已用完",tGrp.nGrpId,nLanguageId))
            end

            tUseUp[tGrp.nGrpId][nLanguageId] = {isUseUp=false,isApp=false}
            if nRate>=100 or nAllCnt==0 then
                tUseUp[tGrp.nGrpId][nLanguageId].isUseUp = true
            end

            local tName = tLNameLib.arrAnNameList[1] or {}
            if tName.sShopAcc~="0" and tName.sShopAcc ~= "" then
                tUseUp[tGrp.nGrpId][nLanguageId].isApp = true
            end
            if nLanguageId==4 or nLanguageId==5 then
                tUseUp[tGrp.nGrpId][nLanguageId].isApp = true
            end
        end
        if tAndroidData.nServerState==1 then
            tALog.Print(str)
        end
    end

    --检查是否有重复加载机器人
    local tServerAndroidId = tPublicRedis.GetAllServerLoadAndroid()
    local tLoadAndroidId = {}
    for nServerId,arrUserId in pairs(tServerAndroidId) do
        for _,nUserId in pairs(arrUserId) do
            if tLoadAndroidId[nUserId] and tLoadAndroidId[nUserId]~=nServerId then
                local str = string.format("_ShowInfo 重复加载机器人: nUserId_%d nServerId1_%d nServerId2_%d",
                nUserId,tLoadAndroidId[nUserId],nServerId)
                tALog.Print(str)
                tALog.SendMsgToTG(str)
            else
                tLoadAndroidId[nUserId] = nServerId
            end
        end
    end

    --各个分组机器人使用情况
    for nGrpId,arrAndroid in pairs(tAndroidData.arrAllAndroid) do
        local nTotal,nAppNameCnt,nHJNameCnt,nNotNameCnt = AndroidMgr.GetAndroidCnt(nGrpId) --机器人总数
        local nTotal_lend,nAppLendCnt,nHJLendCnt,nNoNameLendCnt = RentalInfo.GetGrpLendAndroidCnt(nGrpId) --借出的机器人数
        local nTotal_lendBR,nAppLendBRCnt,nHJLendBRCnt,nHJLendBRCnt = RentalInfo.GetGrpLendBRAndroidCnt(nGrpId) --借出给百人游戏的机器人数
        local nTotal_Free,nAppFreeCnt,nHJFreeCnt,nNotNameFreeCnt = AndroidMgr.GetFreeAndroidCnt(nGrpId) --空闲的机器人
        local nTotal_Rest,nAppRestCnt,nHJRestCnt,nNotNameRestCnt = AndroidMgr.GetRestAndroidCnt(nGrpId) --休息的机器人

        local arrAndroid_HJ = tPublicRedis.GetAndroidKey(nGrpId,1) or {}
        local arrAndroid_App = tPublicRedis.GetAndroidKey(nGrpId,2) or {}
        local nTotal_Redis = #arrAndroid_HJ + #arrAndroid_App

        local nAppRate,nBrAppRate,nHJRate,nBRHJRate = 0,0,0,0
        if nAppNameCnt>0 then
            nAppRate = tPublicApi.Floor_2(nAppLendCnt/nAppNameCnt*100)
            nBrAppRate = tPublicApi.Floor_2(nAppLendBRCnt/nAppNameCnt*100)
        end
        if nHJNameCnt>0 then
            nHJRate = tPublicApi.Floor_2(nHJLendCnt/nHJNameCnt*100)
            nBRHJRate = tPublicApi.Floor_2(nHJLendBRCnt/nHJNameCnt*100)
        end

        if tAndroidData.nServerState==1 then
            tALog.Print(string.format("_ShowInfo 分组_%d,app机器人_%d个,总共借出_%d个(%.2f%%%%),百人游戏借出_%d个(%.2f%%%%)",nGrpId,nAppNameCnt,nAppLendCnt,nAppRate,nAppLendBRCnt,nBrAppRate))
            tALog.Print(string.format("_ShowInfo 分组_%d,合集昵称机器人_%d个,总共借出_%d个(%.2f%%%%),百人游戏借出_%d个(%.2f%%%%)",nGrpId,nHJNameCnt,nHJLendCnt,nHJRate,nHJLendBRCnt,nBRHJRate))
            -- if nNotNameCnt and nNotNameCnt>0 then
            --     tALog.Print(string.format("[RentalInfo.ShowInfo]分组%d,非昵称机器人%d个,总共借出%d个,百人游戏借出%d个",nGrpId,nNotNameCnt,nNoNameLendCnt,nHJLendBRCnt))
            -- end
            tALog.Print("_ShowInfo  分组_%d,空闲的机器人_%d个(app机器人_%d个,合集机器人_%d个,非昵称机器人_%d个)",nGrpId,nTotal_Free,nAppFreeCnt,nHJFreeCnt,nNotNameFreeCnt)
            tALog.Print("_ShowInfo  分组_%d,休息的机器人_%d个(app机器人_%d个,合集机器人_%d个,非昵称机器人_%d个)",nGrpId,nTotal_Rest,nAppRestCnt,nHJRestCnt,nNotNameRestCnt)

            if nAppRate>=90 and nAppRate<=100  then
                --app机器人使用过多
                local isUseUp = true --昵称是否用完
                for _,v in pairs(tUseUp[nGrpId] or {}) do
                    if v.isApp and not v.isUseUp then
                        isUseUp = false
                    end
                end
                if isUseUp then
                    local sKey = string.format("分组_%d,app机器人借出%d%%",nGrpId,math.floor(nAppRate))
                    local str = string.format("分组%d,app机器人%d个,总共借出%d个(%.2f%%),百人游戏借出%d个(%.2f%%)",nGrpId,nAppNameCnt,nAppLendCnt,nAppRate,nAppLendBRCnt,nBrAppRate)
                    tALog.SendMsgToTG(sKey,str)
                end
            end
    
            if nHJRate>=90 and nHJRate<=100  then
                --合集昵称机器人使用过多
                local isUseUp = true --昵称是否用完
                for _,v in pairs(tUseUp[nGrpId] or {}) do
                    if not v.isApp and not v.isUseUp then
                        isUseUp = false
                    end
                end
                if isUseUp then
                    local sKey = string.format("分组_%d,合集昵称机器人借出%d%%",nGrpId,math.floor(nHJRate))
                    local str = string.format("分组%d,合集昵称机器人%d个,总共借出%d个(%.2f%%),百人游戏借出%d个(%.2f%%)",nGrpId,nHJNameCnt,nHJLendCnt,nHJRate,nHJLendBRCnt,nBRHJRate)
                    tALog.SendMsgToTG(sKey,str)
                end
            end
        end

        RentalInfo.SendAndroidDetailToDB(nGrpId,nTotal_Redis,"HJAndroid",nHJNameCnt,nHJRestCnt,nHJLendCnt,nHJFreeCnt)
        RentalInfo.SendAndroidDetailToDB(nGrpId,nTotal_Redis,"AppAndroid",nAppNameCnt,nAppRestCnt,nAppLendCnt,nAppFreeCnt)
        -- if nNotNameCnt and nNotNameCnt>0 then
        --     RentalInfo.SendAndroidDetailToDB(nGrpId,nTotal_Redis,"NoNameAndroid",nNotNameCnt,nNotNameRestCnt,nNoNameLendCnt,nNotNameFreeCnt) 
        -- end
    end
    



end





return RentalInfo