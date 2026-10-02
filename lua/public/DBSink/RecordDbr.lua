package.path = "../lua/base/?.lua;./lua/base/?.lua;" .. package.path
package.path = "../?.lua;./?.lua;" .. package.path
package.path = "../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" .. package.path


local tBase          = require("base")
local tName          = require("typename")
local tApi           = require("publicApi")
local cjson          = require("cjson")
local ProtoMgr       = require("ProtoManager") -- 协议管理对象
local tSrvInfo       = require("ServerInfo")
local tParserAux     = require("ParserAux")
local tPubUser       = require("PublicUserInfo") -- 用户信息
local tBRRecord      = require("BroadCastRecordApp")
local ctlDefine      = require("ControlDefine")
local tPublicClub    = require("PublicClub") --俱乐部公共接口
local tPublicRedis   = require("PublicRedis")
local DbProtoEncode  = tParserAux.DbProtoEncode
local DbProtoEncode1 = tParserAux.DbProtoEncode1

RecordDbr            = {}

local function sql_escape(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("\\", "\\\\") -- 转义反斜杠
    s = s:gsub("'", "\\'")   -- 转义单引号
    return s
end

function RecordDbr.WritePaiJu(tData)
    local Send = ProtoMgr.PubProto_pb.Req_WritePaiJuRecord()
    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_WRITEPAIJU)


    Send.sSql = string.format(
        "CALL PaiJuRecord_Write(%d,'%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s')",
        tData.nUserId,
        sql_escape(tData.sPaiJuID),
        sql_escape(tData.sUsrInfo),
        sql_escape(tData.sTableInfo),
        sql_escape(tData.nRoomType),
        sql_escape(tData.sFullHand),
        sql_escape(tData.sShowHand),
        sql_escape(tData.sTablePaiRecord),
        sql_escape(tData.sRoomInfo),
        sql_escape(tData.sHuWhat),
        sql_escape(tData.sMaPai),
        sql_escape(tData.sDetailedScore),
        sql_escape(tData.sExData)
    )

    s:AddString(Send:SerializeToString())
    tBase.PostDatasByTypeAndUID(tName.db, 0, tData.nUserId, s:GetData(), s:GetSize())
    --tBase.Log(" 我在写入牌局记录"..Send.sSql)
end

--特殊关照一下这个保存百人输盈记录
function RecordDbr.Write_BrZhuangWinLoseRecord(tData)
    if tData.nUserId < 0 or tData.nShopId == -1 then --机器人不写输赢记录
        assert("Write_WinLoseRecord   nShopId is  <= 0  nUserId_" .. tData.nUserId .. " nShopId_" .. tData.nShopId)
        return
    end
    tData.nIsZhuang = 1
    RecordDbr.Write_WinLoseRecord(tData)
end

--输赢(战绩)批量写
function RecordDbr.Write_WinLoseRecordBatch(arrData)
    local sInsertHead =
    "INSERT INTO DJH_RecordDB.PaiJuWinLoseRecord(UserID,GameType,Session,WinLose,DrawWater,XiaZhu,Valid,PaiJuId,CreatetTime,nType,ElseInfo)  VALUES "
    local arrStrValue = {}
    local nArrStrLen = 0
    for nDex, tData in ipairs(arrData) do
        --[[
        local sDataValue =string.format("(%d,%d,%d,%.3f,%.3f,%.3f,%.3f,'%s',NOW(),%d,'%s')",
            tData.nUserId or 0,tData.nGameType or 0,tData.nSession or 0,
            tData.nWinlose or 0,tData.nDrawWater or 0,tData.nXiaZhu or 0,tData.nValid or 0,
            tData.sPaiJuId or "", tData.nIsZhuang or 0, string.gsub(cjson.encode(tData.tElseInfo or {}),'"', '\\"'))
        table.insert(arrStrValue,sDataValue)
        nArrStrLen =nArrStrLen + #sDataValue
        if nArrStrLen>=4000 or nDex==#arrData then
            local Send = ProtoMgr.PubProto_pb.Rep_Write_PaiJuWinLose()
            Send.sSql = 'call ZhiBo_PaiJuWinLoseRecord_Write("'..sInsertHead..table.concat(arrStrValue,",")..'")'
            local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_WRITEPAIJU_WINLOSE)
            s:AddString(Send:SerializeToString())
            tBase.PostDatasByType(tName.db, 0, tData.nUserId, s:GetData(), s:GetSize())
            tBase.Log("  Write_WinLoseRecordBatch  SendSize_ %d    arrStrValue_%d  ",s:GetSize(),#arrStrValue)
            arrStrValue={}
            nArrStrLen=0
        end
        --]]

        RecordDbr.Write_WinLoseRecord(tData)
    end
end

-- 输赢记录  情况： nUserId ,GameType, Session , Winlose ,nDrawWater,sPaiJuId
function RecordDbr.Write_WinLoseRecord(tData, choushuiType)
    choushuiType = choushuiType or 0
    if tData.nShopId == -1 then --机器人不写输赢记录
        assert("Write_WinLoseRecord   nShopId is  <= 0  nUserId_" .. tData.nUserId .. " nShopId_" .. tData.nShopId)
        return
    end
    if tData.nSession == 0 or tData.nSession == 50 then --体验房不写战绩
        return
    end
    if tData.nXiaZhu == nil or tData.nValid == nil then
        if tData.nXiaZhu == nil then
            tData.nXiaZhu = 0
        end
        if tData.nValid == nil then
            tData.nValid = 0
        end
    end
    if tData.nType then -- 飞行棋玩法类型： 1 经典玩法，2 赏金玩法
        tData.nIsZhuang = tData.nType
    end
    if tData.nIsZhuang == nil then
        tData.nIsZhuang = 0       -- 0 不是庄家， 1 庄家
    end
    if not tData.nRecordType then -- 战绩类型:  0:普通,1:PK,2:试玩
        tData.nRecordType = 0
    end
    local sElseInfo = ""
    if tData.tElseInfo then
        tData.tElseInfo.nRecordType = tData.nRecordType
        sElseInfo = cjson.encode(tData.tElseInfo)
        if tData.tElseInfo.nLiveUserID and tData.tElseInfo.nLiveUserID == tData.nUserId then
            local tLiveBetControl = PublicRedis._DisposeLiveControl_Win(tData) -- 处理 主播下注与推荐 风控数据
            if tLiveBetControl then
                tData.tElseInfo.tLiveBetControl = tLiveBetControl
                sElseInfo = cjson.encode(tData.tElseInfo)
            end
        end
    end
    -- tBRRecord.WriteGameRecord(tData)         -- 推给后台(由后台推给APP)
    local Send = ProtoMgr.PubProto_pb.Rep_Write_PaiJuWinLose()
    -- Send.sSql = "Call PaiJuWinLoseRecord_Write("..tData.nUserId..","..tData.nGameType..","..tData.nSession..","
    --         ..tData.nWinlose..","..tData.nDrawWater..","..tData.nXiaZhu..","
    --         ..tData.nValid..",'"..tData.sPaiJuId.."'," ..tData.nIsZhuang..",".."'"..sElseInfo.."'"..",'"..tData.sTableId.."'"..")"

    if tData.nSmallBlind == nil then
        tData.nSmallBlind = 0
    end
    if tData.nPreAnte == nil then
        tData.nPreAnte = 0
    end

    if tData.nZhuaTou == nil then
        tData.nZhuaTou = 0
    end
    if tData.nPreAnteOdd == nil then
        tData.nPreAnteOdd = 0
    end
    
    Send.sSql = string.format(
        "Call PaiJuWinLoseRecord_Write(%d,%d,%d,%.2f,%.2f,%.2f,%.2f,'%s',%d,'%s','%s',%d,%d,%d,%d,%d,%d,%d,'%s',%d,%.2f,%d,%d,%d,%.2f,%.2f,%d,%.2f,%.2f,%.2f,%.2f);",
        tData.nUserId, tData.nGameType, tData.nSession, tData.nWinlose, tData.nDrawWater, tData.nXiaZhu, tData.nValid,
        tData.sPaiJuId, tData.nIsZhuang, sElseInfo, tData.sTableId,
        tData.nInPoolCount, tData.nRaiseCountBFlop, tData.nAllInAndWinCount, tData.nWinCount or 0, tData.nQiPaiCount or 0,
        tData.nGoldType, tData.nClubId, tData.sTableName, tData.isAllIn or 0, tData.nHandProfit or 0, tData.nSeeFlop,
        tData.nReachShowdown, tData.isHaveSelfOp,
        tData.nInsurWin or 0, tData.nInsurCost or 0, choushuiType, tData.nSmallBlind, tData.nPreAnte, tData.nZhuaTou, tData.nPreAnteOdd
)

    if tData.nRecordType ~= 0 then -- 战绩类型:  0:普通,1:PK,2:试玩
        tBase.Log("_Write_WinLoseRecord 不写战绩nUserId: %d nRecordType: %d nGold: %f  %s "
        , tData.nUserId, tData.nRecordType, tData.nGold or 0, tData.sExData or "")
        return
    end

    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_WRITEPAIJU_WINLOSE)
    s:AddString(Send:SerializeToString())
    tBase.PostDatasByTypeAndUID(tName.db, 0, tData.nUserId, s:GetData(), s:GetSize())
    --tBase.Log(" 我在写入   牌局输赢记录")
    if tData.nClubId then
        --俱乐部牌桌,通知俱乐部中心服
        tBase.Log("通知俱乐部中心服")
        tPublicClub.ClubUserSettleNotify(tData)
    end

    if not tData.nShopId then
        assert("Write_WinLoseRecord,nShopId is nil   ")
        return
    end

    local arrData = { tData }
    RecordDbr.SendControRoomlData(tData)

    return
end

--废弃
function RecordDbr.Update_WinLoseRecordTax(nUserId, sPaiJuId, nTax)
    local sql = string.format(
        "UPDATE PaiJuWinLoseRecord SET DrawWater=DrawWater+%.2f,WinLose=WinLose-%.2f WHERE UserID=%d AND PaiJuId='%s';",
        nTax, nTax, nUserId, sPaiJuId)

    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

function RecordDbr.UpdatePenaltyDataWithPlayBackData(tData)
    local sSql = string.format("call Club_UpdatePlayBackDataWithPenalty('%s','%s')",
        tData.sPaiJuId, tData.tPenaltyData)
    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sSql })
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

function RecordDbr.WriteUserRecord(nUserId, sPaiJuId, nGameId, nRtype, nRvalue)
    local sql = string.format(
        "INSERT INTO PaiJuUserRecord(UserId,GameId,PaiJuId,Rtype,Rvalue) VALUES(%d,%d,'%s',%d,%.3f)",
        nUserId, nGameId, sPaiJuId, nRtype, nRvalue)
    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByTypeAndUID(tName.db, 0, nUserId, tPacket:GetData(), tPacket:GetSize())
end

--[[
 tData.nClubId --俱乐部id
 tData.sTableId --牌桌id
 tData.nItemId --道具id
 tData.nGameType --游戏id
 tData.nUserId --玩家id
 tData.nDrawWater --抽水
 tData.sPaiJuId --牌局id
 tData.nClubIdOfCorrect --校正后的俱乐部id (用0表示大厅)
]]
--德州按桌抽水记录更新
function RecordDbr.Update_WinLoseRecordTaxV2(tData, paijuid)
    local nUserId = tData.nUserId
    local sPaiJuId = tData.sPaiJuId
    local nTax = tData.nDrawWater
    local nBigBlind = tData.nBigBlind
    local nSmallBlind = tData.nSmallBlind
    local nPreAnte = tData.nPreAnte
    local nPreAnteOdd = tData.nPreAnteOdd or 0
    local nZhuaTou = tData.nZhuaTou
    local sTableId = tData.sTableId
    local gametype = tData.nGameType or 0
    if paijuid and paijuid ~= "" then
        sPaiJuId = paijuid
    end
    --更新一
    local sql = string.format(
        "UPDATE PaiJuWinLoseRecord SET DrawWater=DrawWater+%.2f,WinLose=WinLose-%.2f,HandProfit=HandProfit-%.2f,ChouShuiType=1 WHERE UserID=%d AND PaiJuId='%s';",
        nTax, nTax, nTax, nUserId, sPaiJuId)
    --  sTableId
    -- local sql = string.format([[
    --     INSERT INTO PaiJuWinLoseRecord AS new
    --     (UserID, PaiJuId, DrawWater, WinLose, HandProfit, ChouShuiType, TableId, GameType)
    --     VALUES
    --     (%d, '%s', %.2f, -%.2f, -%.2f, 1, '%s',%d)
    --     ON DUPLICATE KEY UPDATE
    --     DrawWater = DrawWater + new.DrawWater,
    --     WinLose   = WinLose   + new.WinLose,
    --     HandProfit= HandProfit+ new.HandProfit,
    --     ChouShuiType = 1;
    --     ]],
    --     nUserId, sPaiJuId, nTax, nTax, nTax, sTableId, gametype)
    tBase.Log("Update_WinLoseRecordTaxV2,sql=" .. sql)
    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByTypeAndUID(tName.db, 0, nUserId, tPacket:GetData(), tPacket:GetSize())
    --更新二
    local sqlA = string.format(
        "UPDATE TexaTableUserStatistic SET ProfitSum=ProfitSum-%.2f WHERE UserId=%d AND TableId='%s';",
        nTax, nUserId, tData.sTableId)
    local tPacketA = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sqlA })
    tBase.PostDatasByTypeAndUID(tName.db, 0, nUserId, tPacketA:GetData(), tPacketA:GetSize())

    -- 更新三
    local sqlB = string.format(
        "UPDATE TexaClubUserStatistic SET ProfitSum=ProfitSum-%.2f, HandProfit=HandProfit-%.2f WHERE UserId=%d AND ClubId=%d AND GameId=%d AND GoldType=%d AND SmallBlind=%.2f AND BigBlind=%.2f AND ZhuaTou=%.2f AND PreAnte=%.2f AND PreAnteOdd=%.2f;",
        nTax, nTax, nUserId, tData.nClubId, tData.nGameType, tData.nItemId, nSmallBlind, nBigBlind, nZhuaTou, nPreAnte, nPreAnteOdd)
    local tPacketB = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sqlB })
    tBase.PostDatasByTypeAndUID(tName.db, 0, nUserId, tPacketB:GetData(), tPacketB:GetSize())

    --更新四
    local sqlC = string.format("UPDATE TexaTableStatistic SET SumChouShui=SumChouShui+%.2f WHERE TableId='%s';",
        nTax, tData.sTableId)
    local tPacketC = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sqlC })
    tBase.PostDatasByTypeAndUID(tName.db, 0, nUserId, tPacketC:GetData(), tPacketC:GetSize())

    if not tData.nClubId then
        return
    end

    local t = {}
    t.nClubId = tData.nClubId     --俱乐部id
    t.sTableId = tData.sTableId   --牌桌id
    t.nItemId = tData.nItemId     --道具id
    t.nGameType = tData.nGameType --游戏id
    t.nUserId = nUserId           --玩家id
    t.nWinlose = -nTax            --玩家输赢
    t.nDrawWater = nTax           --抽水

    t.sPaiJuId = ""               --牌局id (注意:非牌局结算填"")
    t.nInsurance = 0              --
    t.nJuShu = 0                  --第几局
    --俱乐部牌桌,通知俱乐部中心服
    tPublicClub.ClubUserSettleNotify(t)

    --控相关
    local tD = {}
    tD.nGroupId = tData.nGroupId
    tD.nGameType = tData.nGameType
    tD.nSession = tData.nSession
    tD.nUserId = nUserId
    tD.nWinlose = 0
    tD.nDrawWater = -nTax
    tD.IsControl = false
    RecordDbr.SendControRoomlData(tD)
end

--限制玩家非充值方式获得的金币提现(需要跑流水)
--nPayType 1:充值 2:提现 3:活动或广告获得金币 11:首冲 12:推荐 13:签到 14:分享 15:绑定 20:广告
function RecordDbr.WithdrawLimit(nUserId, nGold, nPayType)
    if nGold <= 0.0001 then return end
    local nGroupId = tPubUser.Get_User_GroupId(nUserId) or -1
    local nPayType = nPayType or 3
    local sql = string.format("call WithdrawLimit_v2(%d,%.3f,%d,%d);", nUserId, nGold, nGroupId, nPayType)
    local tPacketB = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByTypeAndUID(tName.db, 0, nUserId, tPacketB:GetData(), tPacketB:GetSize())
end

--德州试玩房记录
--tData参数 :nUserId,nGameId,nProfit,nTakeIn,nDuration,nTFlag(玩家在同一桌子里仅第一条记录为1，其余为0 (方便用sum统计局数))
function RecordDbr.WriteTexaExperience(tData)
    local nUserId = tData.nUserId
    local nGameId = tData.nGameId or 0
    local nProfit = tData.nProfit or 0
    local nTakeIn = tData.nTakeIn or 0
    local nDuration = tData.nDuration or 0
    local nTFlag = tData.nTFlag or 0
    local sql = string.format("call TexaExperience_Write(%d,%d,%.3f,%.3f,%d,%d);", nUserId, nGameId, nProfit, nTakeIn,
        nDuration, nTFlag)
    local tPacketB = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByTypeAndUID(tName.db, 0, nUserId, tPacketB:GetData(), tPacketB:GetSize())
end

-- 写入控制数据
function RecordDbr.SendControRoomlData(tData)
    if true then
        return
    end
    if tData.nSession > 0 and tData.nSession < 100 then -- 非体验房和区块链
        if tData.nWinloseToRobot == nil or tData.nWinloseToRobot ~= 0 then
            local Send = ProtoMgr.PubProto_1_pb.REQ_Control_Room_Data()
            if tData.nGroupId == nil then
                tBase.Log("_SendControRoomlData [ERROR] nGroupId == nil")
                return
            end
            Send.nShopId = tData.nGroupId
            Send.nGameId = tData.nGameType
            Send.nLevelId = tData.nSession
            Send.nUserId = tData.nUserId

            if tData.nWinloseToRobot == nil then
                Send.dWinLose = tData.nWinlose
                Send.dDrawWater = tData.nDrawWater
            else -- 如果有按与机器人间输赢单独统计的
                Send.dWinLose = tData.nWinloseToRobot
                if tData.nDrawWaterToRobot ~= 0 then
                    Send.dDrawWater = tData.nDrawWaterToRobot
                else
                    local nWater = 0
                    local isSuccee, tParam = pcall(ctlDefine.GetRoomParam, Send.nShopId, Send.nGameId, Send.nLevelId)
                    if not isSuccee then
                        tBase.Log("GetRoomParam error")
                        if type(tParam) == "string" then
                            logger:error(tParam)
                        else
                            tBase.LogT(tParam)
                        end
                    else
                        nWater = (tParam.PoolWinWaterPer / 100.00) or nWater
                    end

                    Send.dDrawWater = tData.nXiaZhu * nWater

                    tBase.Log(
                        "_SendControRoomlData nUserId: %d  dDrawWater: %f  nXiaZhu: %f  nWater: %f  PoolWinWaterPer_%d ",
                        tData.nUserId, Send.dDrawWater, tData.nXiaZhu, nWater, tParam.PoolWinWaterPer)
                end
            end

            Send.isControl = tData.IsControl
            -- 清除控牌
            tPubUser.DelRedisControlUser(tData.nUserId)
            tPubUser.DelRedisControlRoom(tData.nGroupId, tData.nGameType, tData.nSession, tData.nUserId)
            local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_CONTROL_ROOM_DATA)
            s:AddString(Send:SerializeToString())
            tBase.PostDatasByType(tName.db, tData.nUserId, tData.nUserId, s:GetData(), s:GetSize())
        end
    end
    RecordDbr.SendAllRoomlData(tData)
end

-- 记录所有房间的输赢数据
function RecordDbr.SendAllRoomlData(tData)
    if tData.nSession > 0 then -- 非体验房
        if tData.nWinloseToRobot == nil or tData.nWinloseToRobot ~= 0 then
            if tData.nGroupId == nil then
                logger:error("nGroupId == nil")
            end
            local nShopId = tData.nGroupId
            local nGameId = tData.nGameType
            local nLevelId = tData.nSession
            local nUserId = tData.nUserId
            local dWinLose = 0
            local dDrawWater = 0

            if tData.nWinloseToRobot == nil then
                dWinLose = tData.nWinlose
                dDrawWater = tData.nDrawWater
            else -- 如果有按与机器人间输赢单独统计的
                dWinLose = tData.nWinloseToRobot
                if tData.nDrawWaterToRobot ~= 0 then
                    dDrawWater = tData.nDrawWaterToRobot
                else
                    local nWater = 0
                    local isSuccee, tParam = pcall(ctlDefine.GetRoomParam, nShopId, nGameId, nLevelId)
                    if isSuccee then
                        nWater = (tParam.PoolWinWaterPer / 100.00) or nWater
                    end
                    dDrawWater = tData.nXiaZhu * nWater
                end
            end
            local Send = ProtoManager.PubProto_1_pb.REQ_Control_Record()
            Send.sSql = string.format("Call DJH_TreasureDB.SetUserWinLoseStat(%d, %d, %d, %d, %f, %f)",
                nShopId, nGameId, nLevelId, nUserId, dWinLose, dDrawWater);

            local s = tBase.GetSP().new(ProtoManager.Sys.DB, ProtoManager.Sub_DB.SUB_REQ_CONTROL_INFO)
            s:AddString(Send:SerializeToString())
            tBase.PostDatasByType(typename.db, nUserId, nUserId, s:GetData(), s:GetSize())
        end
    end
end

-- 奖池控
-- 输赢记录  情况： nUserId ,GameType, Session , Winlose ,nDrawWater,sPaiJuId
function RecordDbr.Write_TableWinLoseRecord(tData)
    if tData.nSession > 0 and tData.nSession < 100 then -- 非体验房和区块链
        -- 通知控制服
        local SendObj = {}
        SendObj.nShopId = math.floor(tData.nShopId)
        SendObj.nGameId = math.floor(tData.nGameType)
        SendObj.nLevelId = math.floor(tData.nSession)
        SendObj.sTableId = tData.sTableId
        SendObj.dWinLose = tData.nWinlose
        SendObj.dDrawWater = tData.nDrawWater
        SendObj.sPaiJuId = tData.sPaiJuId

        if SendObj.dWinLose < 0 then -- 玩家输钱
            local nTmpWaterPer = 0
            local isSuccee, tParam = pcall(ctlDefine.GetRoomParam, SendObj.nShopId, SendObj.nGameId, SendObj.nLevelId)
            if not isSuccee then
                tBase.Log("GetRoomParam error")
                if type(tParam) == "string" then
                    logger:error(tParam)
                else
                    tBase.LogT(tParam)
                end
            else
                nTmpWaterPer = tParam.PoolWinWaterPer or nTmpWaterPer
            end
            tBase.Log("PoolWinWaterPer," .. nTmpWaterPer)
            if nTmpWaterPer > 0 then -- 奖池加值也要抽水
                local dSumWin = SendObj.dWinLose + SendObj.dDrawWater
                SendObj.dDrawWater = SendObj.dDrawWater + dSumWin * nTmpWaterPer / 100.00 * -1.00
            else
                tBase.Log("PoolWinWaterPer no set," .. SendObj.nShopId .. "," .. SendObj.nGameId)
            end
        else
            tBase.Log("PoolWinWaterPer no set 2," .. SendObj.nShopId .. "," .. SendObj.nGameId)
        end
        local nIndex = SendObj.nShopId * 1000 + SendObj.nGameId * 100 + SendObj.nLevelId * 10
        local SendControl = ProtoMgr.PubProto_1_pb.REQ_Control_TableInfo()
        tBase.ProtoInit(SendControl, SendObj)
        local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_CONTROL_WINLOSE)
        s:AddString(SendControl:SerializeToString())
        tBase.PostDatasByType(tName.db, 0, nIndex, s:GetData(), s:GetSize())
    end
end

function RecordDbr.WriteGameDataCount(tData)
    tBase.Log("调用存储过程：Get_Game_Data_Count1")
    tBase.Log("tData: %s", tData)
    -- local s = tBase.GetSP().new(tPubProto.Sys.SYS_DB, tPubProto.SUB_DB.SUB_GAME_DATA_COUNT)
    -- local sSql = "Call Get_Game_Data_Count1("..tData.nServerId..
    --     ","..tData.nTiYanSum..
    --     ","..tData.nLiuJuSum..
    --     ","..tData.nEastCountHuPai..
    --     ","..tData.nEastCountZiMo..
    --     ","..tData.nEastCountPoint..
    --     ","..tData.nSouthCountHuPai..
    --     ","..tData.nSouthCountZiMo..
    --     ","..tData.nSouthCountPoint..
    --     ","..tData.nWestCountHuPai..
    --     ","..tData.nWestCountZiMo..
    --     ","..tData.nWestCountPoint..
    --     ","..tData.nNorthCountHuPai..
    --     ","..tData.nNorthCountZiMo..
    --     ","..tData.nNorthCountPoint..
    --     ","..tData.cResult..
    --     ")"
    -- s:AddString(sSql)
    -- tBase.Log("sSql: %s",sSql )
    -- tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())
    tBase.Log("已写入游戏记录数据")
end

function RecordDbr.AddPrivateRoomWinLog(tData)
    tBase.Log("调用存储过程：AddPrivateRoomWinLog")
    tBase.Log("tData: %s", tData)
    -- local s = tBase.GetSP().new(tPubProto.Sys.SYS_DB, tPubProto.SUB_DB.SUB_REQ_PRIROOM_WIN)
    -- local sSql = "Call AddPrivateRoomWinLog("..tData.nRoomID..
    --     ","..tData.nType..
    --     ","..tData.UserData[1].UserID..
    --     ","..tData.UserData[1].WinVal..
    --     ","..tData.UserData[2].UserID..
    --     ","..tData.UserData[2].WinVal..
    --     ","..tData.UserData[3].UserID..
    --     ","..tData.UserData[3].WinVal..
    --     ","..tData.UserData[4].UserID..
    --     ","..tData.UserData[4].WinVal..
    --     ")"
    -- s:AddString(sSql)
    -- tBase.Log("sSql: %s",sSql )
    -- tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())
    tBase.Log("已发送私人房总结算写入请求")
end

function RecordDbr.WritePaiJuStatistic(tRoundStatistic)
    local tb = tRoundStatistic:InfoTable()

    --  local s = tBase.GetSP().new(tPubProto.Sys.SYS_DB, tPubProto.SUB_DB.SUB_REQ_PAIJU_STATISTIC)

    --  local jsonStr =cjson.encode(tb)
    -- -- tBase.Log(" WritePaiJuStatistic    json: %s",jsonStr )

    --  if s:AddString(jsonStr)==false then
    --      tBase.Log("add string fail %d",#jsonStr)
    --  end

    --  tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())
end

--tData各字段 (table类型的字段会以json编码存数据库)
--[[
sPaiJuId    :牌局id
sTableId    :tableid(用来区分哪些牌局是同一张桌子产生的)
nGameId     :游戏id
nRoomId     :房间(场次)id
nAnte       :底分
tUsersInfo  :各玩家信息与金币变化;{{nUserId=,nSitId=,sName=昵称,nProfit=利润,nDrawWater=抽水} ,{},...}
            百人类在mysql表PaiJuWinLoseRecord->ElseInfo定义，规则看mysql注明
nZhuang     :庄家座位id (0:系统做庄 ,-1:游戏不分庄闲)
tDealCardInfo   :最终得牌情况信息(各玩家 或各押注区域 或系统做庄得牌) json
                nSitId意义：(要改动意义同步注明到mysql为主，这里为次)
                百人牛牛类： 1庄 2-5分别对应黑桃，红桃，梅花，方块区
                百人炸花类： 0红 1黑
                百人百家乐类： 0闲 1庄
                其他游戏类: 保持原有座位号不变
                {{nSitId=,arrCard={},nCardType=},{nSitId=,arrCard={},nCardType=?},...}
            直播类: {arrCard= arrDice , sCardName = "鱼 虾 蟹" }
tBetInfo    :各玩家最终下注数目与抢庄倍数信息(json)：
            非百人扎金花和百人百家乐类存储规则 {{nSitId=,nAreaId=押注区域,nBet=押注数,nQiang=抢庄倍数},{},...};
            百人类在mysql表PaiJuWinLoseRecord->ElseInfo定义，规则看mysql注明
            直播类型：({nUserId= ,allBet=总下注, arrBetDetail(下注详细)={{nAreaId=押注区域,nBet=押注数},{},..} })

tElseInfo   :游戏过程或其它 (各自定义或不填)
            直播类：  {nWinLose = 本局输赢,  arrCard=开牌结果, allBet=总下注,arrBetDetail(下注详细)={{nAreaId=押注区域,nBet=押注数} }
]]
--注：｛ 百人类只记录真人(闲)和庄的牌局记录，其他游戏记录有真人玩的牌桌记录 ｝

function RecordDbr.Write_PaiJuDetail(tData)
    if tData.nRoomId == 0 then --过滤掉体验房
        return
    end
    --tBase.Log(cjson.encode(tData))
    tData.tUsersInfo = tData.tUsersInfo or {}
    tData.tDealCardInfo = tData.tDealCardInfo or {}
    tData.tBetInfo = tData.tBetInfo or {}
    tData.tElseInfo = tData.tElseInfo or {}

    local SPaiJuID = tData.sPaiJuId
    local nGameId = tData.nGameId
    local nRoomId = tData.nRoomId
    local nAnte = math.floor(tData.nAnte)
    local sUsersInfo = cjson.encode(tData.tUsersInfo)
    local nZhuang = tData.nZhuang
    local sDealCardInfo = cjson.encode(tData.tDealCardInfo)
    local sBetInfo = cjson.encode(tData.tBetInfo)
    local sElseInfo = cjson.encode(tData.tElseInfo)
    local sTableId = tData.sTableId or ""
    local sExData = tData.sExData or ""
    local sql = string.format("call PaiJuDetail_Write_v2('%s',%d,%d,%d,'%s',%d,'%s','%s','%s','%s','%s')",
        SPaiJuID, nGameId, nRoomId, nAnte, sUsersInfo, nZhuang, sDealCardInfo, sBetInfo, sElseInfo, sTableId, sExData)
    local arr = tApi.CutString(sql, 1000)
    local tKey = tBase.GetSrcAllKey(tName.db)
    local Db = tKey[math.random(1, #tKey)]
    local End = false
    for i = 1, #arr do
        if i == #arr then End = true end
        local tPacket, nMainCmd, nSubCmd = DbProtoEncode("SqlExcuteReq",
            { sDbName = "DJH_RecordDB", sSql = arr[i], bEnd = End, sPaiJuID = SPaiJuID })
        tBase.PostToServer(Db, nGameId, tPacket:GetData(), tPacket:GetSize())
    end
end

--写下注记录
--tData.sSeriesNumber   --期号
--tData.nGame           --游戏id
--tData.nBetArea        --下注区
--tData.nBetGold        --下注金额
--tData.dOdds           --倍数
--tData.nUserId         --玩家id
--tData.nGameType       --游戏类型 1:飞行棋小游戏
--tData.nBall           --飞行棋时时彩填
--tData.nBetId          --下注订单号
--tData.nGoldWin         --如果写该记录时还没结算则填nil
function RecordDbr.RecordBet(tData)
    local sSeriesNumber = tData.sSeriesNumber --期号
    local nGame = tData.nGame                 --游戏id
    local nBetArea = tData.nBetArea           --下注区
    local nBetGold = tData.nBetGold           --下注金额
    local dOdds = tData.dOdds or 0            --倍数
    local nUserId = tData.nUserId             --玩家id
    local nGameType = tData.nGameType or -1   --游戏类型 1:飞行棋小游戏
    local nBall = tData.nBall or -1           --飞行棋时时彩填
    local nBetId = tData.nBetId or -1         --下注订单号
    local sGoldWin = "NULL"
    if tData.nGoldWin then
        sGoldWin = tostring(tData.nGoldWin)
    end
    local sql = string.format("call BettingRecord_Write2('%s',%d,%d,%d,%.2f,%d,%d,%d,%d,%d,%s);",
        sSeriesNumber, nGame, nBetArea, nBetGold, dOdds, nUserId, nGameType, nBall, tSrvInfo.nServerId, nBetId, sGoldWin)
    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

--自动下注结算记录
--tD.nUserId        --玩家id
--tD.sPaiJuId       --牌局id
--tD.nBetArea       --下注区域
--tD.nBetGold       --下注金币
--tD.nXianD         --闲家点数
--tD.nZhuangD       --庄家点数
--tD.nProfit        --盈利
--tD.nBalanceAfter  --本结算后的余额
--tD.sTableName     --桌子名称
--tD.nTrendType     --好路类型
--tD.nIsOffLine	    --是否离线下注 1:是 0:否
function RecordDbr.BJLAutoBetRecord(tD)
    local nUserId = tD.nUserId                    --玩家id
    local sPaiJuId = tD.sPaiJuId                  --牌局id
    local nBetArea = tD.nBetArea or -1            --下注区域
    local nBetGold = tD.nBetGold or 0             --下注金币
    local nXianD = tD.nXianD or -1                --闲家点数
    local nZhuangD = tD.nZhuangD or -1            --庄家点数
    local nProfit = tD.nProfit or 0               --盈利
    local nBalanceAfter = tD.nBalanceAfter or 0   --本结算后的余额
    local sTableName = tD.sTableName or "UnKnown" --桌子名称
    local nTrendType = tD.nTrendType or -1        --好路类型
    local nIsOffLine = tD.nIsOffLine or 0         --是否离线下注
    local sGrpNo = tPublicRedis.GetGrpNoByPaiJu(nUserId, sPaiJuId) or "ErrorGrpNo"

    local sql = string.format("call BJLAutoBetRecord_WriteV2(%d,'%s',%d,%.2f,%d,%d,%.2f,%.2f,'%s',%d,%d,'%s');",
        nUserId, sPaiJuId, nBetArea, nBetGold, nXianD, nZhuangD, nProfit, nBalanceAfter, sTableName, nTrendType,
        nIsOffLine, sGrpNo)

    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())

    tPublicRedis.SaveUserAutoBetPaiJu(nUserId, sPaiJuId, nIsOffLine)
end

--自动下注总览记录开始(插入一条记录)
function RecordDbr.BJLAutoBetRecordOverview_Start(nUserId, sGrpNo, nTimeStart)
    local sql = string.format("call BJLAutoBetRecordOverview_Start(%d,'%s',%d);", nUserId, sGrpNo, nTimeStart)
    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

--自动下注总览记录(更新结束时间)
function RecordDbr.BJLAutoBetRecordOverview_End(nUserId, sGrpNo, nTimeEnd)
    local sql = string.format("call BJLAutoBetRecordOverview_End(%d,'%s',%d);", nUserId, sGrpNo, nTimeEnd)
    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

--自动下注总览记录开服调用 (结束没结束的记录)
function RecordDbr.BJLAutoBetRecordOverview_ServStart()
    local sql = "call BJLAutoBetRecordOverview_ServStart();"
    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

--百家乐,好路开牌记录
--tD.sPaiJuId       --牌局id
--tD.sTableName     --桌子名称
--tD.nTrendType     --好路类型
--tD.nXianD         --闲家点数
--tD.nZhuangD       --庄家点数
--tD.nTrend         --1:顺路 0:逆路
--tD.STableId       --桌子Id
--tD.nGroupId      --分组id
function RecordDbr.BJLGTSettleRecord(tD)
    local sPaiJuId = tD.sPaiJuId
    local nXianD = tD.nXianD or -1
    local nZhuangD = tD.nZhuangD or -1
    local sTableName = tD.sTableName or "UnKnown"
    local nTrendType = tD.nTrendType or -1
    local nTrend = tD.nTrend or -1
    local sTableId = tD.sTableId or tD.STableId or ""
    local nGroupId = tD.nGroupId or -1
    local sql = string.format("call BJLGTSettleRecord_Write('%s',%d,%d,'%s',%d,%d,'%s',%d);",
        sPaiJuId, nXianD, nZhuangD, sTableName, nTrendType, nTrend, sTableId, nGroupId)

    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())

    tPublicRedis.GoodtrendSettle(nGroupId, sPaiJuId)
end

function RecordDbr.TexaStatistic_WriteN(tTableInfo, arrTableUsers)
    local sTableId = tTableInfo.sTableId
    local nGameId = tTableInfo.nGameId
    local nClubId = tTableInfo.nClubId
    local nGoldType = tTableInfo.nGoldType or 1
    local nPlayCount = 1
    local nTakeInTotal = 0
    local nFlowTotal = 0
    local nPool = tTableInfo.nPool or 0           --底池
    local nInsurPool = tTableInfo.nInsurPool or 0 --保险池
    local sTableName = tTableInfo.sTableName or "NoName"
    local nKeepTime = tTableInfo.nKeepTime or 0
    local nGroupId = tTableInfo.nGroupId or 1
    local nSumBet = tTableInfo.nSumBet or 0
    local nRoomId = tTableInfo.nRoomId
    local nBigBlind = tTableInfo.nBigBlind
    local nSmallBlind = tTableInfo.nSmallBlind
    local nPreAnte = tTableInfo.nPreAnte
    local nPreAnteOdd = tTableInfo.nPreAnteOdd
    local nZhuaTou = tTableInfo.nZhuaTou
    local nSumChouShui = tTableInfo.nSumChouShui
    tBase.LogT("TexaStatistic_WriteN ", tTableInfo, arrTableUsers)

    for _, v in ipairs(arrTableUsers) do
        nTakeInTotal = nTakeInTotal + v.nTakeInAdd
        nFlowTotal = nFlowTotal + math.abs(v.nProfitSum)
        local playCount = 1
        if v.isHaveSelfOp > 0 then
            playCount = 1
        end
        if not v.isAndroid then --保存每个俱乐部 每个用户的总下注 总入池 总带入 总收益 总保险(永久牌桌这个不需要)
            local sql = string.format(
                "call TexaClubUserStatistic_Write_new(%d,%d,%d,%d,%d,%d,%d,%.2f,%d,%.2f,%d,%d,%d,%.2f,%d,%d,%.2f,%.2f,%.2f,%.2f,%d,%.2f);",
                v.nUserId, nClubId, nGameId, playCount, v.nInPoolCount, v.nRaiseCountBFlop, v.nAllInAndWinCount,
                v.nProfitSum, nGoldType, v.nSumBet or 0,
                v.nWinCount or 0, v.nQiPaiCount or 0, v.isAllIn or 0, v.nHandProfit or 0, v.nSeeFlop, v.nReachShowdown,
                nBigBlind, nSmallBlind, nZhuaTou, nPreAnte, v.isHaveSelfOp, nPreAnteOdd)
            local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
            tBase.Log("TexaClubUserStatistic_Write for user_%d", v.nUserId)
            tBase.PostDatasByTypeAndUID(tName.db, 0, v.nUserId, tPacket:GetData(), tPacket:GetSize())
        end
        if nClubId ~= -999 then --保存每个牌桌 每个用户的总下注 总入池 总带入 总收益 总保险
            local sql = string.format("call TexaTableUserStatistic_Write(%d,'%s',%d,%.2f,%d,%.2f,%.2f,'%s','%s',%.2f);",
                v.nUserId, sTableId, nPlayCount, v.nTakeInAdd, v.nInPoolCount, v.nProfitSum, v.nInsurance, v.sFaceId,
                v.sName, v.nSumBet or 0)
            local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
            tBase.Log("TexaTableUserStatistic_Write for user_%d", v.nUserId)
            tBase.PostDatasByTypeAndUID(tName.db, 0, v.nUserId, tPacket:GetData(), tPacket:GetSize())
        elseif tTableInfo.nKeepTime == -1 then
            --大厅永久牌桌  保存每个牌桌 每个用户的总下注 总入池 总带入 总收益 总保险
            local sql = string.format(
                "call TexaTableUserStatisticHall_Write(%d,'%s',%d,%.2f,%d,%.2f,%.2f,%d,%d,'%s','%s',%.2f);",
                v.nUserId, sTableName, nPlayCount, v.nTakeInAdd, v.nInPoolCount, v.nProfitSum, v.nInsurance, nGameId,
                nGroupId, v.sFaceId, v.sName, v.nSumBet or 0)
            local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
            tBase.Log("TexaTableUserStatisticHall_Write %s", sql)
            tBase.PostDatasByTypeAndUID(tName.db, 0, v.nUserId, tPacket:GetData(), tPacket:GetSize())
        end
    end
    if nClubId ~= -999 then --保存每个牌桌 的局数 总带入 保险 俱乐部ID
        local sql = string.format("call TexaTableStatistic_Write('%s',%d,%.2f,%.2f,%.2f,%.2f,%d,%.2f,%.2f,%.2f,%.2f);",
            sTableId, nPlayCount, nTakeInTotal, nFlowTotal, nPool, nInsurPool, nClubId, nSumBet, nSumChouShui,
            tTableInfo.nInsurWin or 0, tTableInfo.nInsurCost or 0)
        local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
        tBase.Log("TexaTableStatistic_Write sql:%s", sql)
        tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
    elseif tTableInfo.nKeepTime == -1 then
        --大厅永久牌桌  保存每个牌桌 的总下注 总入池 总带入 总收益 总保险
        local sql = string.format("call TexaTableStatisticHall_Write('%s',%d,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%.2f);",
            sTableName, nPlayCount, nTakeInTotal, nFlowTotal, nPool, nInsurPool, nClubId, nGameId, nGroupId, nSumBet)
        local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
        tBase.Log("TexaTableStatisticHall_Write sql:%s", sql)
        tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
    end
end

--
function RecordDbr.RecordSettle(sSeriesNumber, nGame, tResult)
    local sql = string.format("call LotteryRecord_Settle('%s',%d,'%s',%d);", sSeriesNumber, nGame, cjson.encode(tResult),
        tSrvInfo.nServerId)
    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

--下注结算记录
--arrResult: {{nBetId=9999,nGoldWin=10.1},{nBetId=9999,nGoldWin=10.1},{nBetId=9999,nGoldWin=10.1}}
function RecordDbr.RecordBetSettle(arrResult)
    local arrItems = {}
    for dex, item in ipairs(arrResult) do
        table.insert(arrItems, { sBetId = tostring(item.nBetId), nGoldWin = item.nGoldWin })
        if #arrItems >= 200 or dex == #arrResult then
            local tPacket = DbProtoEncode("RecordBetSettleReq", { arrItems = arrItems })
            tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
            tBase.Log("RecordBetSettle arrItems Len:%d", #arrItems)
            arrItems = {}
        end
    end
end

--直播桌子创建记录
--tData.sTableId
--tData.sTableName
--tData.nGameId
--tData.nGroupId
--tData.nRoomId
function RecordDbr.LiveTableCreate(tData)
    local sTableId = tData.sTableId
    local sTableName = tData.sTableName
    local nGameId = tData.nGameId
    local nRoomId = tData.nRoomId
    local nGroupId = tData.nGroupId
    local nTableType = tData.nTableType or 1
    local sLiveID = "0"
    if tData.sLiveID and #tData.sLiveID >= 1 then sLiveID = tData.sLiveID end
    local DbLiveTableCreateReq = {}
    DbLiveTableCreateReq.sSql = string.format("call LiveTableCreate('%s','%s',%d,%d,%d,'%s',%d)", sTableId, sTableName,
        nGameId, nRoomId, nGroupId, sLiveID, nTableType)
    tBase.Log("_LiveTableCreate   直播桌子创建记录_Sql: " .. DbLiveTableCreateReq.sSql)
    local tPacket = DbProtoEncode("DbLiveTableCreateReq", DbLiveTableCreateReq)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

--直播桌子关闭记录
function RecordDbr.LiveTableClose(sTableId, sExData)
    local DbLiveTableCloseReq = {}
    DbLiveTableCloseReq.sTableId = sTableId
    DbLiveTableCloseReq.sExData = sExData or ""
    local tPacket = DbProtoEncode("DbLiveTableCloseReq", DbLiveTableCloseReq)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

--直播桌子创建记录
--tData.nType
--tData.sTableId
--tData.nLiveUserID
--tData.nGameId
--tData.nGroupId
--tData.nRoomId
function RecordDbr.LiveTableBingDingRecord(tData)
    -- tBase.Log("_LiveTableBingDingRecord   tData_: %s",cjson.encode(tData))
    local DbLiveBingdingReq = {}
    DbLiveBingdingReq.sSql = string.format("call LiveBingdingRecord(%d,'%s', %d, %d, %d, %d,'%s')", tData.nType,
        tData.sTableId, tData.nLiveUserID, tData.nGameId, tData.nRoomId, tData.nGroupId, tData.sLiveID)
    local tPacket = DbProtoEncode("DbLiveBingdingReq", DbLiveBingdingReq)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

-- 写记录:  nType: 1退款记录，
function RecordDbr.WriteRecordPublic(nType, tData)
    -- tBase.Log("_WriteRecordPublic  nType_%d 【1退款记录】 tData_: %s",nType,cjson.encode(tData))
    local DbWriteRecordPublicReq = {}
    local sSql = ""
    if nType == 1 then -- 退款记录
        -- tRefundRecord.sTableId = self.sTableId
        -- tRefundRecord.sPaiJuId = self.sPaiJuId
        -- tRefundRecord.nGameId = self.nGameId
        -- tRefundRecord.nGroupId = self.nGroupId
        -- tRefundRecord.nRoomId = self.nRoomId
        -- tRefundRecord.nRefundType = nType        -- 1人工,2服务器自行退款
        -- tRefundRecord.nRefundGold = nRefundGold     -- 退款总额
        -- tRefundRecord.nRefundPeopleCnt = nRefundPeopleCnt  -- 退款人数
        -- tRefundRecord.sUserBetInfo = sUserBetInfo    -- 玩家下注详细
        if #tData.sUserBetInfo <= 2 then
            tBase.Log("_WriteRecordPublic  nType_%d 【1退款记录】 没有玩家下注信息 tData_: %s", nType, cjson.encode(tData))
            return
        end
        sSql = string.format("call WriteRefundRecord('%s','%s', %d, %d, %d, %d, %d, %d,'%s')"
            , tData.sTableId, tData.sPaiJuId, tData.nGroupId, tData.nGameId, tData.nRoomId, tData.nRefundType,
            tData.nRefundPeopleCnt, tData.nRefundGold, tData.sUserBetInfo)
    else
    end
    DbWriteRecordPublicReq.sSql = sSql
    local tPacket = DbProtoEncode("DbWriteRecordPublicReq", DbWriteRecordPublicReq)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
    tBase.Log("_WriteRecordPublic  nType_%d 【1退款记录】 sSql_: %s", nType, sSql)
end

--[[
    nGameId,sPaiJuId,sTableId
    arrAbnormal ={{nUserId=, nBetArea=, nBetGold=, sLogonIp=,nGoldBeforeSettle=},...}
]]
--异常流水监控异常记录
function RecordDbr.AbnormalBet(nGameId, sPaiJuId, sTableId, arrAbnormal)
    local tTemp = {}
    local tIsBetAll = {}
    for _, v in ipairs(arrAbnormal) do
        local nUserId = v.nUserId
        local nBetArea = v.nBetArea
        local nBetGold = v.nBetGold
        local sLogonIp = v.sLogonIp
        local nCnt = 1
        if tTemp[nUserId] then nCnt = 0 end
        local sql = string.format("call AbnormalBet_Write(%d,'%s',%d,%d,%.2f,%d,'%s','%s');", nUserId, sPaiJuId, nGameId,
            nBetArea, nBetGold, nCnt, sLogonIp, sTableId)
        local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sql })
        tBase.PostDatasByType(tName.db, 0, nUserId, tPacket:GetData(), tPacket:GetSize())
        tTemp[nUserId] = tTemp[nUserId] or 0
        if nCnt == 1 then
            tTemp[nUserId] = tPublicRedis.AddAbnormalCnt(nUserId)
            tIsBetAll[nUserId] = (math.abs(v.nGoldBeforeSettle or 1) < 0.01)
        end
    end

    for nUserId, nCnt in pairs(tTemp) do
        if nCnt % 3 == 0 or tIsBetAll[nUserId] then     --每发现3次异常或AllIn上报一次灰名单
            tPublicRedis.AbnormalUserReport(nUserId, 2) --第二个参数type 2:灰名单 3：黑名单
            tPublicRedis.DelAbnormalCnt(nUserId)
        end
    end
end

--local tUserIdToBetA ={[11]=100,[12]=300,[13]=400,[99]=8}
--local tUserIdToBetB ={[111]=100,[122]=300,[133]=400,[13]=399}
--local tA,tB =abnormalCheck(tAreaA,tAreaB,100)
function RecordDbr.abnormalCheck(tUserIdToBetA, tUserIdToBetB, nDiff)
    local tA = {}
    local tB = {}
    for nUserId, nBet in pairs(tUserIdToBetA) do
        for nUserIdInner, nBetInner in pairs(tUserIdToBetB) do
            if math.abs(nBet - nBetInner) <= nDiff then
                tA[nUserId] = nBet
                tB[nUserIdInner] = nBetInner
            end
        end
    end
    return tA, tB
end

-- 牌局Hash记录
function RecordDbr.WriteRecordHash(sTableId, nGameId, nRoomId, tData)
    local sData = cjson.encode(tData)
    -- tBase.Log("WriteRecordHash tData_: %s", sData)
    local DbWritePaiJuHashReq = {}
    local sSql = string.format("CALL PaiJuHashRecord_InsertBatch('%s',%d,%d,'%s')", sTableId, nGameId, nRoomId,
        sData:gsub("'", "\\'"))
    DbWritePaiJuHashReq.sSql = sSql
    local tPacket = DbProtoEncode1("DbWritePaiJuHashReq", DbWritePaiJuHashReq)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
    tBase.Log("WriteRecordHash sSql_: %s", sSql)
end

-- 牌局花费记录
function RecordDbr.WriteRecordCost(sTableId, nGameId, sTableName, sPaiJuId, tData)
    local sData = cjson.encode(tData)
    -- tBase.Log("WriteRecordCost tData_: %s", sData)
    local WriteRecordCost = {}
    local sSql = string.format("CALL PaiJuCostRecord_InsertBatch('%s',%d,'%s','%s','%s')", sTableId, nGameId, sTableName,
        sPaiJuId, sData:gsub("'", "\\'"))
    WriteRecordCost.sSql = sSql
    local tPacket = DbProtoEncode1("DbWriteRecordCostReq", WriteRecordCost)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
    tBase.Log("WriteRecordCost sSql_: %s", sSql)
end

-- 更新牌局hash
function RecordDbr.UpdateHashRecord(nUserId, nPaiJuId)
    local DbPaiJuHashRecordUpdateReq = {}
    local sql = string.format("call PaiJuHashRecord_Update(%d,'%s')", nUserId, nPaiJuId)
    DbPaiJuHashRecordUpdateReq.sSql = sql
    local tPacket = DbProtoEncode1("DbPaiJuHashRecordUpdateReq", DbPaiJuHashRecordUpdateReq)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

-- 更新牌桌买入金额
function RecordDbr.UpdateUserLockGlodRecord(nUserId, sTableId, nLockGold, nStatus)
    nStatus = nStatus or 0
    local UserLockGlodReq = {}
    local sql = string.format([[
        INSERT INTO
            UserLockGoldRecord(TableId, UserId, LockGold, UpdateTime)
        VALUES
            ("%s",%d, %.2f, NOW())
    ]], sTableId, nUserId, nLockGold)
    UserLockGlodReq.sSql = sql
    local tPacket = DbProtoEncode1("UserLockGlodReq", UserLockGlodReq)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

function RecordDbr.UpdateTableStatusOnPaiJuWinLossRecord(sTableId, nStatus)
    nStatus = nStatus or 1
    local UserLockGlodReq = {}
    local sql = string.format([[
        update PaiJuWinLoseRecord set TableStatus = %d where TableId = "%s"
    ]], nStatus, sTableId)
    UserLockGlodReq.sSql = sql
    local tPacket = DbProtoEncode1("UserLockGlodReq", UserLockGlodReq)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

-- 更新用户罚款或者罚款盈利
function RecordDbr.UpdatePenaltyRevenueOnPaiJuWinLossRecord(sTableId, sPaiJuId, nUserId, nPenalty, nRevenue,
                                                            nChouShuiType, nGameType, nGoldType, sTableName, nSmallBlind, nPreAnte, nZhuaTou, nPreAnteOdd)
    local UserLockGlodReq = {}

    local sql = string.format(
        'INSERT INTO PaiJuWinLoseRecord ' ..
        '(UserID, PaiJuId, TableId, Penalty, Revenue, ChouShuiType, CreatetTime, GameType, GoldType, TableName, SmallBlind, PreAnte, ZhuaTou, PreAnteOdd) ' ..
        'VALUES (%d, "%s", "%s", %.2f, %.2f, %d, NOW(), %d, %d, "%s", %.2f, %.2f, %.2f, %.2f) ' ..
        'ON DUPLICATE KEY UPDATE ' ..
        'Penalty = Penalty + VALUES(Penalty), ' ..
        'Revenue = Revenue + VALUES(Revenue), ' ..
        'ChouShuiType = %d;',
        nUserId, sPaiJuId, sTableId,
        nPenalty, nRevenue, nChouShuiType, nGameType, nGoldType, sTableName, nSmallBlind, nPreAnte, nZhuaTou, nPreAnteOdd,
        nChouShuiType
    )
    
    UserLockGlodReq.sSql = sql
    tBase.Log("UpdatePenaltyRevenueOnPaiJuWinLossRecord,sql=" .. sql)
    local tPacket = DbProtoEncode1("UserLockGlodReq", UserLockGlodReq)
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

function RecordDbr.WriteSystemNoticeNotic(nUserId, nType, nMsgType, sMsg)
    local nMsgType = nMsgType or 0
    local exData = { sMsg = sMsg }
    if nMsgType > 0 then
        exData.nType = nMsgType
    end
    exData = cjson.encode(exData)
    local sSql = string.format("call Club_WriteUserNotice(%d,%d,'%s')", nUserId, nType, exData)
    local tPacket = DbProtoEncode("DbSqlExcuteReq", { sDbName = "DJH_RecordDB", sSql = sSql })
    tBase.PostDatasByTypeAndUID(tName.db, 0, nUserId, tPacket:GetData(), tPacket:GetSize())
end

return RecordDbr
