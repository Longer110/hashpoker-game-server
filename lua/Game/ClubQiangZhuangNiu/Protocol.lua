package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tProtoMgr = require("ProtoManager") -- 协议管理对象 
local tBase = require("base") -- 基础功能接口
local tTableApi = require("TableApi")
local tPubUserApi   = require("PublicUserInfo")    --玩家数据同步
local tUserMgr = require("UserManager")
local tTableMgr = require("TableManage")
local mlogger = require("logger") -- 日志对象 
local tJosn = require("cjson")
local tName     = require("typename")
local tCfg = require("GConfig")
local tPublicMath = require("PublicMath")
local tUserLogin = require("UserLogin")
local tSrvPub     = require("SrvPublic")
local tGLogic = require("GLogic")
local tGameCfgRedis = require("GameCfgRedis")
local tApi      = require("publicApi")    -- 共用功能接口
local tRdf      = require("redisdefine")  -- redis用到的kdy
local tDbInfo    = require("DBInfo")         -- 数据库连接信息
local tConfig =require("GameConfig") -- 
local  tMagicFace = require("MagicFace")
local tCheckTableTimeOut = require("CheckTableTimeOut")
Protocol = {}

------------------------返回----------------------------------
-- 登录游戏服返回
function Protocol.LoginRespon(sClientID,tData)
    mlogger:debug(string.format("LoginRespon %s",tJosn.encode(tData)))
    local LoginGame_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZLoginGame_P()
    LoginGame_P.nResult = tData.nResult 
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_LOGIN)
    s:AddString(LoginGame_P:SerializeToString()) 
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
    tMagicFace.GetNeedGoldByFace(1)
    local REQ_USER_MSG = tProtoMgr.MagicFace_pb.REP_User_Msg() 
end

-- 返回牌桌信息 牌桌场景
function Protocol.TableInfoRespon(sClientID,tData)
    mlogger:debug(string.format("TableInfoRespon"))
    local GameTable_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZGameTable_P()
    GameTable_P.TableNumber = tostring(tData.TableNumber)
    GameTable_P.TabelStep = tData.TabelStep
    GameTable_P.TabelZhuangJiaSit = tData.TabelZhuangJiaSit
    GameTable_P.GameType = tData.GameType
    GameTable_P.GameLevel = tData.GameLevel
    GameTable_P.TabelDiFen = tData.TabelDiFen
    GameTable_P.nElapsedStatus = tData.nElapsedStatus
  
    for k, v in pairs(tData.UserDataList) do        
        local TableUserData =  GameTable_P.UserArr:add()
        TableUserData.UserID = v.nUserID
        TableUserData.Name = v.sNickName
        TableUserData.Sex = v.nSex
        TableUserData.FaceID = v.sFaceID
        TableUserData.SitID = v.nSitId
        TableUserData.Status = v.nStatus
        TableUserData.Gold = v.nGold or 0
        TableUserData.Online = v.isOnLine
        local tRInfo =v.tRetainInfo
        if tRInfo then
            TableUserData.nRetain=	tRInfo.nLen -(os.time() -tRInfo.nStartTime) 
            TableUserData.nRetain =math.max(0,TableUserData.nRetain)
        end
        mlogger:debug(string.format("TableInfoRespon.UserDataList UserID_%d Gold_%.2f Name_%s SitID_%d nRetain_%d",v.nUserID,v.nGold,v.sNickName,v.nSitId,TableUserData.nRetain))
        --mlogger:debug(string.format("TableInfoRespon.UserDataList UserID_%d Gold_%.2f Name_%s SitID_%d"),v.nUserID,v.nGold,v.sNickName,v.nSitId)
    end

    --个人信息
    GameTable_P.tMyself.UserID = tData.tMyself.nUserID
    GameTable_P.tMyself.Name = tData.tMyself.sNickName
    GameTable_P.tMyself.Sex = tData.tMyself.nSex
    GameTable_P.tMyself.FaceID = tData.tMyself.sFaceID
    GameTable_P.tMyself.SitID = tData.tMyself.nSitId
    GameTable_P.tMyself.Status = tData.tMyself.nStatus
    GameTable_P.tMyself.Gold = tData.tMyself.nGold or 0
    GameTable_P.tMyself.Online = tData.tMyself.isOnLine

    --表情价格列表
    for k, v in pairs(tData.arrChat) do
        local arrChat = GameTable_P.arrChat:add()
        arrChat.nChatId = v.nChatId
        arrChat.nCost = v.nCost
        --mlogger:info(string.format("TableInfoRespon.arrChat nChatId_%d nCost_%.2f",v.nChatId,v.nCost))
    end

    --牌桌配置
    local tTableConfig = GameTable_P.tTableConfig
    tTableConfig.sTableName = tData.tTableConfig.sTableName
    tTableConfig.sPaiJuId = tData.tTableConfig.sPaiJuId
    tTableConfig.sClubName = tData.tTableConfig.sClubName
    tTableConfig.nBaseScore = tData.tTableConfig.nBaseScore
    tTableConfig.isOnlyPlayByIOS = tData.tTableConfig.isOnlyPlayByIOS
    tTableConfig.isGPSLimit = tData.tTableConfig.isGPSLimit
    tTableConfig.isIPLimit = tData.tTableConfig.isIPLimit
    tTableConfig.nPlayerAtLeast = tData.tTableConfig.nPlayerAtLeast
    --mlogger:info(string.format("TableInfoRespon.tTableConfig sTableName_%s nBaseScore_%d",tData.tTableConfig.sTableName,tData.tTableConfig.nBaseScore))
    

    -- 牌桌位置
    for k ,v in pairs(tData.TableSit) do
        GameTable_P.TableSit:append(v)
    end

    --抢庄配置
    for k, v in pairs (tData.QiangZhuangCfg) do
       GameTable_P.QiangZhuang:append(v)
    end

    --抢庄信息
    for k, v in pairs(tData.QiangZhuangArr) do
        --mlogger:info(tJosn.encode(v))
        local QiangZhuangArr = GameTable_P.QiangZhuangArr:add()
        QiangZhuangArr.UserID = k
        QiangZhuangArr.Times = v.nTimes
    end

    -- 下注配置
    for k, v in pairs (tData.XiaZhuCfg) do
        GameTable_P.XiaZhu:append(v)
    end
    --下注信息
    for k, v in pairs(tData.tXiaZhuArr) do
        --mlogger:info(tJosn.encode(v)) 
        local tXiaZhu = GameTable_P.XiaZhuArr:add()
        tXiaZhu.UserID = v.nUserID
        tXiaZhu.Times = v.nGold
        tXiaZhu.Index = v.nIndex or 0
    end

    --手牌信息（如果有自己的手牌）
    for k, v in pairs(tData.UserShouPai) do
        local UserShouPai  = GameTable_P.UserShouPai:add()
        UserShouPai.UserID = k
        for k1, v1 in pairs(v) do
            UserShouPai.ShouPai:append(v1)
        end
    end
          
   -- 摊牌准备
    for k, v in pairs (tData.TanPaiReady) do
        GameTable_P.TanPaiReady:append(v)
    end
    --摊牌信息
    for k, v in pairs(tData.tTanPaiArr) do
        --mlogger:info("摊牌信息发送")
        local TanPai =  GameTable_P.TanPai:add()
        TanPai.UserID = k
        TanPai.NiuWhat = v.NiuWhat
        for k1, v1 in pairs(v.HandCard) do
            --mlogger:info(tJosn.encode(v.HandCard))
            TanPai.ShouPai:append(v1)
         end
         TanPai.Times = v.NiuTimes
    end

    --结算信息
    for k, v in pairs(tData.tUserData) do
        local JieSuan = GameTable_P.JieSuan.UserWinArr:add()
        JieSuan.UserID = v.UserID
        JieSuan.TotalWin = v.TotalWin
        for k2, v2 in pairs(v.WinObjectArr) do 
           local WinArr = JieSuan.WinArr:add()
           WinArr.UserID = v2.UserID
           WinArr.Gold = v2.Gold
           WinArr.Index = v2.Index or 0
        end
    end

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_TABLE_INFO)
  
    s:AddString(GameTable_P:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

-- 玩家进入 
function Protocol.Enter(sClientID, tData) 
    mlogger:debug(string.format("Enter"))
    local tUser = tUserMgr.GetUserInfo(tData.nUserID)
    if (tUser == nil ) then
        mlogger:error("tUserID 错误")
        mlogger:info(tJosn.encode(tData))
        return 
    end
    --mlogger:info(tJosn.encode(tUser))
	local tTable = tTableMgr.GetTable(tUser.nTableId)
	if (tTable == nil) then tBase.Log(" Error_Info==3042") return   end
  
	local arrUserId = tTable:GetAllUser()
	for i = 1, #arrUserId do
        local tCurUser = tUserMgr.GetUserInfo(arrUserId[i])
        mlogger:info(tJosn.encode(tCurUser))
        if tCurUser.isAndroid == false and tUser:IsOnLine() == true then
        
			--如果不是本玩家，就只需要告诉另外的玩家本玩家信息
			if arrUserId[i] ~= tData.nUserID then
                tBase.Log("不是本人 %d 发信息 UserId %d SitId %d ",tCurUser.nUserID, tCurUser.nUserID, tCurUser.nSitId)			
            else
                tBase.Log("  是本人 %d 发信息 UserId %d SitId %d ",tCurUser.nUserID, tCurUser.nUserID, tCurUser.nSitId)		
            end
            
            local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_ENTER) 
            local Enter_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZEnter_P()
           
            Enter_P.tUserData.UserID = tUser.nUserID
            Enter_P.tUserData.Name = tUser.sNickName or "2111"
            Enter_P.tUserData.Sex = tUser.nSex
            Enter_P.tUserData.FaceID = tostring(tUser.sFaceID)
            Enter_P.tUserData.SitID =  tUser.nSitId or 0
            Enter_P.tUserData.Status = tUser.nStatus or 0
            Enter_P.tUserData.Gold = tUser.nGold or 0
            Enter_P.tUserData.Online = true
            s:AddString(Enter_P:SerializeToString())
            tBase.PostToGateway(tCurUser.sClientID, s:GetData(), s:GetSize())
		end
	end
end

-- 只发给自己
function Protocol.Enter2(sClientID, tData) 
    mlogger:debug(string.format("Enter"))
    local tUser = tUserMgr.GetUserInfo(tData.nUserID)
    if (tUser == nil ) then
        mlogger:error("tUserID 错误")
        mlogger:info(tJosn.encode(tData))
        return 
    end
	
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_ENTER) 
    local Enter_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZEnter_P()
    
    Enter_P.tUserData.UserID = tUser.nUserID
    Enter_P.tUserData.Name = tUser.sNickName or "2111"
    Enter_P.tUserData.Sex = tUser.nSex
    Enter_P.tUserData.FaceID = tostring(tUser.sFaceID)
    Enter_P.tUserData.SitID =  tUser.nSitId or 0
    Enter_P.tUserData.Status = tUser.nStatus or 0
    Enter_P.tUserData.Gold = tUser.nGold or 0
    Enter_P.tUserData.Online = true
    s:AddString(Enter_P:SerializeToString())
    tBase.PostToGateway(tUser.sClientID, s:GetData(), s:GetSize())
    
end

-- 等待游戏开始
function Protocol.WatiStartGame(sClientID, tData)
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_WaitGame) 
    local WaitGame_p = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZWaitGame_p()
   
    WaitGame_p.nResult = tData.nResult
    if tData.nResult == 1 then
        WaitGame_p.WaitTime  = tData.WaitTime or 5
        WaitGame_p.sPaiJuID  = tData.sPaiJuID or "0"
    end
    
    s:AddString(WaitGame_p:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
    
end

-- 抢庄放回
function Protocol.QiangZhuang(sClientID, tData)
    local QiangZhuang_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZQiangZhuang_P()
    QiangZhuang_P.UserID = tData.UserID
    QiangZhuang_P.Times = tData.Times
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_QIANGZHUAGN)
    s:AddString(QiangZhuang_P:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
end
-- 返回定庄
function Protocol.DingZhuang(sClientID, tData)
   -- mlogger:info("DingZhuang")
   -- mlogger:info(tJosn.encode(tData))
    local DingZhuang_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZDingZhuang_P()
    DingZhuang_P.UserID = tData.UserID
    DingZhuang_P.IsChange = tData.IsChangeZhuang
    DingZhuang_P.SitID = tData.SitID
    DingZhuang_P.ByWay      = tData.ByWay
    DingZhuang_P.Round = tData.Round
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_DIZHUANG)
    s:AddString(DingZhuang_P:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
end

-- 下注返回
function Protocol.XiaZhu(sClientID, tData)
    local XiaZhu_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZXiaZhu_P()
    XiaZhu_P.UserID = tData.UserID
    XiaZhu_P.Times = tData.Times
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_XIAZHU)
    s:AddString(XiaZhu_P:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
end

-- 手牌
function Protocol.ShouPai(sClientID, tData)
    local ShouPai_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZShouPai_P()
      
    ShouPai_P.UserID = tData.UserID
    for k, v in pairs(tData.ShouPai) do
       -- mlogger:info(v)
       ShouPai_P.ShouPai:append(v)
    end

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_SHOUPAI)
    s:AddString(ShouPai_P:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
end
-- 发牌
function  Protocol.FaiPai(sClientID, tData)
    local FaiPai_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZFaiPai_P()
    FaiPai_P.UserID = tData.UserID
    FaiPai_P.Pai = tData.Pai

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_FAPAI)
    s:AddString(FaiPai_P:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
  
end

-- 摊牌准备返回
function Protocol.Rep_TanPaiReady(sClientID, tData)
    local TanPaiReady_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZTanPaiReady_P()
    TanPaiReady_P.UserID = tData.UserID
    TanPaiReady_P.Ready = tData.Ready

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_TANPAI_READY)
    s:AddString(TanPaiReady_P:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
  
end

-- 摊牌返回
function Protocol.TanPai(sClientID, tData)
    local TanPai_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZTanPai_P()
    TanPai_P.UserID = tData.UserID
    TanPai_P.NiuWhat = tData.NiuWhat
    TanPai_P.Times = tData.NiuTimes
    for k, v in pairs(tData.ShouPai) do
        TanPai_P.ShouPai:append(v)
    end

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_TANPAI)
    s:AddString(TanPai_P:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
end

--结算返回
function Protocol.JieSuan(sClientID, tData)

    local JieSuan_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZJieSuan_P()
    for k, v in pairs(tData.tUserData) do
        local JieSuan = JieSuan_P.UserWinArr:add()
        JieSuan.UserID = v.UserID
        JieSuan.TotalWin = v.TotalWin
        for k2, v2 in pairs(v.WinObjectArr) do 
           local WinArr = JieSuan.WinArr:add()
           --mlogger:info(tJosn.encode(v2))
           WinArr.UserID = v2.UserID
           WinArr.Gold = v2.Gold
           if v2.Index then
                WinArr.Index = v2.Index
           end
        end
    end

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_JIESUAN)
    s:AddString(JieSuan_P:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
end

-- 重置游戏
function Protocol.ResetGame(sClientID, tData)
    --mlogger:debug(string.format( "ResetGame"))
    local ResetGame_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZResetGame_P()
    ResetGame_P.TableNumber = tData.TableNumber
    ResetGame_P.time = tData.time
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_RESETGAME)
    s:AddString(ResetGame_P:SerializeToString())
    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
end

-- 玩家动作
function Protocol.UserAction(sClientID, tData)
    local UserAction_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZUserAction_P()
    -- mlogger:debug(string.format( "UserAction %s:",tJosn.encode(tData)))
    UserAction_P.UserID = tData.UserID
    UserAction_P.Action = tData.Action
    UserAction_P.SitID = tData.SitID or 0
    UserAction_P.nRlt = tData.nRlt
    if tData.Action == 1 and tData.tUserData then
        UserAction_P.tUserData.UserID = tData.tUserData.UserID
        UserAction_P.tUserData.Name = tData.tUserData.Name
        UserAction_P.tUserData.Sex = tData.tUserData.Sex
        UserAction_P.tUserData.FaceID = tostring(tData.tUserData.FaceID)
        UserAction_P.tUserData.SitID =  tData.tUserData.SitID
        UserAction_P.tUserData.Status = tData.tUserData.Status
        UserAction_P.tUserData.Gold = tData.tUserData.Gold
        UserAction_P.tUserData.Online = tData.tUserData.Online
    end
    if not tData.isAndroid then
        local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_ACTION)
        s:AddString(UserAction_P:SerializeToString())
        tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
    end
end

-- 玩家钱不够
function Protocol.UserNotMoney(sClientID, tData)
    local UserNotNoney_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZUserNotNoney_P()
    --mlogger:debug(string.format( "UserNotMoney"))
    --mlogger:debug(string.format( "%s:",tJosn.encode(tData)))
    UserNotNoney_P.UserID = tData.UserID
  
    UserNotNoney_P.Result = tData.Result
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_NOT_MONEY)
    s:AddString(UserNotNoney_P:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--玩家离开牌桌
function Protocol.UserLeaveTable(sClientID, tData)
    local UserLeaveTable_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZUserLeaveTable_P()
    --mlogger:debug(string.format( "UserLeaveTable_P"))
    --mlogger:debug(string.format( "%s:",tJosn.encode(tData)))
    UserLeaveTable_P.UserID = tData.UserID
    --UserAction_P.IsZhuang = 0
    UserLeaveTable_P.Status = tData.Status
   
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_LEAVE_TABLE)
    s:AddString(UserLeaveTable_P:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end
-- 用户状态改变通知
function Protocol.UserStatusChange(sClientID,tData)
    --mlogger:info(string.format( "UserStatusChange:%s",tJosn.encode(tData) ))
    local UserStatusChange = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZUserStatusChange()
    UserStatusChange.UserID = tData.nUserID
    UserStatusChange.Status = tData.nStatus

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUP_STATUS_CHANGE)
    s:AddString(UserStatusChange:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end
--金币改变通知
function Protocol.UserGoldChange(sClientID,tData)
    --mlogger:info(string.format( "UserGoldChange:%s",tJosn.encode(tData) ))
    local UserGold_p_Arr = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZUserGold_p_Arr()
    for k, v in pairs(tData) do
        --mlogger:info(tJosn.encode(v))
        local tGoldArr = UserGold_p_Arr.tGoldArr:add()
        tGoldArr.UserID = v.nUserID
        tGoldArr.Gold = v.nGold
    end
 
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUP_GOLD_ChANGE)
    s:AddString(UserGold_p_Arr:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

-- 玩家没有动作站起
function Protocol.UserNotAction(sClientID,tData)
    local REP_Not_Action = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZREP_Not_Action()
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUP_NOT_ACTION)
    s:AddString(REP_Not_Action:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--玩家请求主动退出牌桌返回
function Protocol.Rep_LogOut(sClientID, tData)
    mlogger:info("Rep_LogOut")
    local UserLogOut_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZUserLogOut_P()
    UserLogOut_P.UserID = tData.UserID
    UserLogOut_P.Result = tData.Result
   
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_LOGOUT_GAME)
    s:AddString(UserLogOut_P:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end


--网关通知链接切换
function Protocol.OnSwicthConn(sClientID, sData, nLen)
    local s = tBase.GetRP().new(sData, nLen)
    local SwicthConn = tProtoMgr.Gateway_pb.RUQ_SwicthConn()
    SwicthConn:ParseFromString(s:GetString())
    local nUserID = SwicthConn.nUserID
    local  tUser = tUserMgr.GetUserInfo(nUserID)
    if tUser ~= nil then
        mlogger:info(string.format( "玩家 %d切换链接 newsClientID:%s, ordsClientID:%s", nUserID, sClientID, tUser.sClientID))

        local In_Room, In_tTable =  tGLogic.CheckInRoom(nUserID)
        --检查有未完成对局 当离线处理(等待网关通知踢出)
        if In_Room == true then 
           -- tUser.sClientID = sClientID
            tUser:SetOffLine() 
        else -- 没有未完成对局 当成退出登录
            tUserLogin.OnUserLogout(tUser.sClientID)
        end
    end
end

--留座离桌返回
function Protocol.RetainRsp(sClientID,tData)
    local UserRetain_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZRetainGame_P()
    mlogger:debug(string.format( "RetainRsp %s:",tJosn.encode(tData)))
    UserRetain_P.UserID = tData.UserID
    --UserAction_P.IsZhuang = 0
    UserRetain_P.nRlt = tData.nRlt
    UserRetain_P.nOp = tData.nOp
   
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_Retain)
    s:AddString(UserRetain_P:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--留座离桌通知
function Protocol.RetainNotify(sClientID,tData)
    local UserRetainNotify = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZRetainNotify()
    --mlogger:debug(string.format( "RetainNotify %s:",tJosn.encode(tData)))
    UserRetainNotify.nPos = tData.nPos
    UserRetainNotify.nOp = tData.nOp
    if tData.nOp == 0 then
        UserRetainNotify.nSeconds = tData.nSeconds
    end
   
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_RetainNotify)
    s:AddString(UserRetainNotify:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--表情返回
function Protocol.ChatRsp(sClientID,tData)
    local UserRetain_P = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZChatGame_P()
    mlogger:debug(string.format( "ChatRsp %s:",tJosn.encode(tData)))
    UserRetain_P.UserID = tData.UserID
    UserRetain_P.nRlt = tData.nRlt
   
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_Chat)
    s:AddString(UserRetain_P:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--表情通知
function Protocol.ChatNotify(sClientID,tData)
    local UserChatNotify = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZChatNotify()
    --mlogger:debug(string.format( "ChatNotify %s:",tJosn.encode(tData)))
    UserChatNotify.nSpeaker = tData.nSpeaker
    UserChatNotify.nChatId = tData.nChatId
    UserChatNotify.nTarget = tData.nTarget
    
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_ChatNotify)
    s:AddString(UserChatNotify:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--牌桌总览回复
function Protocol.OverViewRsp(sClientID,tData)
    local ClubQZOverView = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZOverView_P()
    ClubQZOverView.sPaiJuId = tData.sPaiJuId --牌局编号
    ClubQZOverView.sTableName = tData.sTableName  --牌桌名称
    ClubQZOverView.nBaseScore = tData.nBaseScore --牌桌底分
    ClubQZOverView.nRound = tData.nRound --第几手
    ClubQZOverView.nRemainTime = tData.nRemainTime --剩余时间
    ClubQZOverView.nEndFlag = tData.nEndFlag
    tBase.Log("nEndFlag:%d,nRemainTime:%d",ClubQZOverView.nEndFlag,ClubQZOverView.nRemainTime)
    for k2, v2 in pairs(tData.arrPartInUser) do   --参与过牌局的用户
        local arrPartInUser = ClubQZOverView.arrPartInUser:add()
        --mlogger:info(tJosn.encode(v2))
        arrPartInUser.nUserId = v2.nUserId
        arrPartInUser.sName = v2.sName
        arrPartInUser.nStatus = v2.nStatus
        arrPartInUser.nPlayCnt = v2.nPlayCnt
        arrPartInUser.nProfitSum = v2.nProfitSum
        arrPartInUser.sFaceId = v2.sFaceId
    end
    for k2, v2 in pairs(tData.arrLooker) do --观看用户
        local arrLooker = ClubQZOverView.arrLooker:add()
        --mlogger:info(tJosn.encode(v2))
        arrLooker.nUserId = v2.nUserId
        arrLooker.sName = v2.sName
        arrLooker.nStatus = v2.nStatus
        arrLooker.sFaceId = v2.sFaceId
    end
    tBase.Log("nEndFlag2:%d,nRemainTime2:%d",ClubQZOverView.nEndFlag,ClubQZOverView.nRemainTime)
    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_OverView)
    s:AddString(ClubQZOverView:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--头像信息回复
function Protocol.HeadInfoRsp(sClientID,tData)
    local HeadInfo = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZHeadInfo_P()
    HeadInfo.nUserId = tData.nUserId 
    HeadInfo.sFaceId = tData.sFaceId  
    HeadInfo.sName = tData.sName  
    HeadInfo.nSex = tData.nSex  
    HeadInfo.nBalance = tData.nBalance 
    HeadInfo.sSigna = tData.sSigna  
    HeadInfo.nVipLev = tData.nVipLev  
    HeadInfo.nPlayCount = tData.nPlayCount  
    HeadInfo.nProfit = tData.nProfit  
    HeadInfo.nJuShu = tData.nJuShu  

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_HeadInfo)
    s:AddString(HeadInfo:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--db服牌局详情 返回
function Protocol.OnDbRecordDetailRsp(sReturnKey, Data, nLen)   
	tBase.Log("OnDbRecordDetailRsp ")
	local tData =DbServAux:Parser(Data, nLen,"GetResultsBySqlRsp")
	if tData ==nil then
	   tBase.Log("OnDbRecordDetailRsp _Parse Err")
	   return
	end
	local nUserId =tData.nUserId
	local tUser = tUserMgr.GetUserInfo(nUserId)
    if (tUser == nil ) then
        mlogger:error("_OnDbRecordDetailRsp tUserID 错误")
        return 
    end
	if #tData.sJsonRows <2 then 
	   tBase.Log("sJsonRows is not valid")
	   return
	end
	local arrRows =tJosn.decode(tData.sJsonRows)
	local tRow =arrRows[1] or {}
 
	if not tRow.UsersInfo or not tRow.DealCardInfo or not tRow.GameId or not tRow.Ante or not tRow.Zhuang  then
		tBase.Log("info is less")
		return
	 end
	 local PaijuDetailRsp={}
	 PaijuDetailRsp.GameId =tonumber(arrRows[1].GameId) or -1
	 PaijuDetailRsp.nAnte =tonumber(arrRows[1].Ante) or -1
	 PaijuDetailRsp.tUsersInfo =arrRows[1].UsersInfo or "{}"
	 PaijuDetailRsp.nZhuang =tonumber(arrRows[1].Zhuang) or -1 
	 PaijuDetailRsp.tDealCardInfo =arrRows[1].DealCardInfo or "{}"
	 PaijuDetailRsp.tBetInfo=arrRows[1].BetInfo or "{}"
	 PaijuDetailRsp.sTime =arrRows[1].PaiJuTime or ""
     PaijuDetailRsp.sPaiJuID =tData.sEcho or ""

	 Protocol.PaijuDetailRsp(tUser.sClientID,PaijuDetailRsp)
  
	 --[[ tBase.LogT("#Paiju.GameId:",PaijuDetailRsp.GameId, " tBetInfo=",PaijuDetailRsp.tBetInfo," nAnte=",PaijuDetailRsp.nAnte,
	 " nZhuang=",PaijuDetailRsp.nZhuang," tData.tUsersInfo=",PaijuDetailRsp.tUsersInfo,"CardInfo=",PaijuDetailRsp.tDealCardInfo,
        "sTime=",PaijuDetailRsp.sTime,"sPaiJuID=",PaijuDetailRsp.sPaiJuID) ]]
 end

--牌局详情 返回
function Protocol.PaijuDetailRsp(sClientID,tData)
    local PaijuDetail = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZPaijuDetail_P()
    PaijuDetail.GameId = tData.GameId 
    PaijuDetail.nAnte = tData.nAnte  
    PaijuDetail.tUsersInfo = tData.tUsersInfo  
    PaijuDetail.nZhuang = tData.nZhuang  
    PaijuDetail.tDealCardInfo = tData.tDealCardInfo 
    PaijuDetail.tBetInfo = tData.tBetInfo  
    PaijuDetail.sTime = tData.sTime
    PaijuDetail.sPaiJuID = tData.sPaiJuID  

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUB_REP_PaijuDetail)
    s:AddString(PaijuDetail:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--开始抢庄通知
function Protocol.QiangZhuangStartNotify(sClientID,tData)
    local QiangZhuangStart = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZQiangZhuangNotify()
    QiangZhuangStart.nTimes = tData.nTimes  

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.SUP_QiangZhuangNotify)
    s:AddString(QiangZhuangStart:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--桌子剩余时间 警告
function Protocol.RemainTimeWarning(sClientID,tData)
    local RemainTimeWarning = tProtoMgr.ClubQZNiuNiuGame_pb.NNElapWarnNotify()
    RemainTimeWarning.nRemainTime = tData.nRemainTime

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.NNElapWarnNotify_CMD)
    s:AddString(RemainTimeWarning:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--桌子计时状态变化通知
function Protocol.StateChangeNotify(sClientID,tData)
    local StatusNotify = tProtoMgr.ClubQZNiuNiuGame_pb.NNElapsedStatusNotify()
    StatusNotify.nElapsedStatus = tData.nElapsedStatus

    local s = tBase.GetSP().new(tProtoMgr.ClubQZNiuNiuGamePro.Main, tProtoMgr.ClubQZNiuNiuGamePro.NNElapsedStatusNotify_CMD)
    s:AddString(StatusNotify:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

local function SetWebRedisResulte(sRequestkey,tData)
    if not sRequestkey then
       return
    end
    local tRedis =tBase.m_MyRedisData[1].redis
    tRedis:hmset(sRequestkey,tData)
    tRedis:expire(sRequestkey,60)
 end

function Protocol.OnDbRechargeRsp(sReturnKey, Data, nLen)
    local tData =DbServAux:Parser(Data, nLen,"DbRechargeRsp")
    if tData ==nil then
       tBase.Log("DbRechargeRsp _Parse Err")
       return
    end
    tBase.Log("OnDbRechargeRsp nUserId:%d sSerialNumber:%s nAmount:%f nRlt:%d",tData.nUserId,tData.sSerialNumber,tData.nAmount,tData.nRlt)
    if tData.nRlt==0 then
       SetWebRedisResulte(tData.sResultKey,{nRlt=0})
    else
       SetWebRedisResulte(tData.sResultKey,{nRlt=12,sErr="db error"})
    end
    --判断玩家是否在牌桌中

    --第二参数true，为重新同步redis金币       
    local tUser = tUserMgr.GetUserInfo(tData.nUserId)
    if not tUser then
       tBase.Log("OnDbRechargeRsp 没有找到玩家")
       return
    end

    local  tTable = tTableMgr.GetTable(tUser.nTableId)
    if not tTable then
       tBase.Log("_OnDbRechargeRsp not in tTable,nUserId:%d",tData.nUserId)
       return
    end
    --通知牌桌，该玩家充值成功
    Protocol.RechargeSuccee(tData.nUserId,tData.nAmount,tData.nCurrentAmount)	
 end

 -- 充值成功
function Protocol.RechargeSuccee(nUserId,nAmount,nNewGold)
	local tUser = tUserMgr.GetUserInfo(nUserId) 
	if (tUser == nil) then
		return false,-1,"can not find user "
	end
	if not tUser.nSitId then
		tBase.Log("_RechargeSuccee can not find user nUserId_%d ",nUserId) 
		return
	end
	-- assert(tUser.isLockForRecharge==true)
	-- tUser.isLockForRecharge=false
	tUser.nGold = tPubUserApi.Get_User_Gold(nUserId)
	tBase.Log("_RechargeSuccee  nUserId_%d nSitId_%d nAmount:%f  nGold_%f   nNewGold_%f ",nUserId,tUser.nSitId,nAmount,tUser.nGold,nNewGold)

	if nAmount>0.0001 or nAmount<-0.0001 then
        tBase.Log("_RechargeSuccee  nUserId_%d nSitId_%d nAmount:%f  nGold_%f   nNewGold_%f ",nUserId,tUser.nSitId,nAmount,tUser.nGold,nNewGold)

        local  tTable = tTableMgr.GetTable(tUser.nTableId)
        if not tTable then
            tBase.Log("_RechargeSuccee not in tTable,nUserId:%d",nUserId)
            return
        end

        local tSendData1 = {}
        tSendData1.nUserID = nUserId
        tSendData1.nReason = 2 --后台充值
        tTable:SendAllUser(nUserId,tTable.EnumProtocol.GoldChange, tSendData1)
        tBase.Log("_RechargeSuccee 充值成功 ") 
	end
end

------------------------请求---------------------------------
-- 登录游戏服
function Protocol.LogRequest(sClientID, sData, nLen)
    mlogger:debug(string.format( "ReqLogRequest sClientID ClubQiangZhuangNiu: %s ", sClientID))
    local s = tBase.GetRP().new(sData, nLen)
    local LoginGame_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZLoginGame_Q()
    LoginGame_Q:ParseFromString(s:GetString())
    
    local UserID = LoginGame_Q.UserID
    local sTableId = LoginGame_Q.sTableId
    local tUserData = tPubUserApi.GetUserBasic(UserID)
    mlogger:debug(string.format("LogRequest tUserData : %s",tJosn.encode(tUserData)))

    if (tUserData == nil) then
        mlogger:error(string.format( "LogRequest UserID:%d get UserID data err", UserID ))
        return
    end
    local  tdata = {}
    tdata.nResult = 1

    tBase.Log("LogRequest UserID_%d sTableId_%s",UserID,sTableId)
    local tTable = tTableMgr.GetTableBySTableId(sTableId)
    if not tTable then
        tBase.Log("GetTable fail")
        tdata.nResult = -4
        Protocol.LoginRespon(sClientID,tdata)
        return
    end

     --因为多服问题，还需要判断玩家是否还在另一服的桌子当中
    local _,_,_,_,sCurTableId= tPubUserApi.GetUserPlayingGame(UserID)
    if sCurTableId and #sCurTableId>0 and sCurTableId ~=sTableId  then
        tBase.Log("you are in other table,sCurTableId:%s",sCurTableId)
        tdata.nResult = -6
        Protocol.LoginRespon(sClientID,tdata)
        return
    end

    --判断玩家是否在其它游戏中玩
    if not tPubUserApi.EnterGameV2(UserID,GConfig.GameType.KanPaiNiuNiu,tTable.nLevel,sTableId) then
        tBase.Log("tPubUser.EnterGame fail")
        tdata.nResult = -6
        Protocol.LoginRespon(sClientID,tdata)
        return
    end

    --判断是否在房间黑名单内
    if tTable:IfBlacklist(UserID) then
        tBase.Log("userId_%d you are in the table blacklist",UserID)
        tdata.nResult = -7
        Protocol.LoginRespon(sClientID,tdata)
    end
    
   --[[  --是否在本服
    local nFlag, nCurrentGame, nCurrentlevel =  tPubUserApi.CheckInGame(UserID,tTable.nGameType,tTable.nLevel)
    if  nFlag == false then
        mlogger:error("在其他服")
        tdata.nResult = -6
        tdata.GameType = nCurrentGame or -1
        tdata.GameLevel = nCurrentlevel or -1
        Protocol.LoginRespon(sClientID,tdata)
        return
    end ]]

    local In_Room, In_tTable =  tGLogic.CheckInRoom(UserID)
    if In_Room == true then
        mlogger:info("有未完成对局")
        Protocol.LoginRespon(sClientID,tdata)
        
        local tUser = tUserMgr.GetUserInfo(UserID)
        if (tUser ~= nil) then
            --tUser.nTableId = tTable.nTableId
            tUser.sClientID = sClientID
            tUser:SetOnLine()
        end
        -- 自动进入牌桌
        local tData = In_tTable:MakeTableData(In_Room,tUser.nUserID)
        tPubUserApi.EnterGame(tUser.nUserID,In_tTable.nGameType,In_tTable.nLevel,sTableId)
        Protocol.TableInfoRespon(sClientID,tData)
        --Protocol.Enter(sClientID,{nUserID =UserID })
        --自动坐下    
        return 
    end

    -- 登录返回 进入
    local GameType = tTable.nGameType
    local GameLevel = tTable.nLevel
    if tPubUserApi.EnterGame(tUserData.nUserID,GameType,GameLevel,sTableId) == false then
        mlogger:info("在其他服")
        tdata.nResult = -6
        Protocol.LoginRespon(sClientID,tdata)
        return
    end
    mlogger:info(string.format( "LogRequest UserID:%d GameType:%d  GameLevel:%d", UserID,GameType, GameLevel ))
    tdata.nResult = 2
    Protocol.LoginRespon(sClientID,tdata)
    tUserData.GameType = GameType
    tUserData.GameLevel = GameLevel
    tUserData.sClientID = sClientID
    tUserData.nTableId = tTable.nTableId
    tUserMgr.AddUser(tUserData)
    local nGroupId = tConfig.GetGroupId(tonumber(tUserData.nShopID))
    local nResult = tTable:AddUser(tUserData.nUserID)
    if  nResult >= 0 then 
        tCheckTableTimeOut.AddLoginNumber(nGroupId,GameType,GameLevel)
        --返回牌桌场景
        local  tTableData = tTable:MakeTableData(false, tUserData.nUserID)
        Protocol.TableInfoRespon(tUserData.sClientID,tTableData)
    else
        mlogger:error("失败")
    end
    tTable.tTableOverview:LookerIn(tUserData.nUserID,tUserData.sNickName,tUserData.sFaceID)

end

--玩家动作请求(站起/坐下)
function Protocol.Req_Action(sClientID, sData, nLen)
    local s = tBase.GetRP().new(sData, nLen)
    local UserAction_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZUserAction_Q()
    UserAction_Q:ParseFromString(s:GetString())
    local nUserID = UserAction_Q.UserID
    local Action = UserAction_Q.Action
    local SidID = UserAction_Q.SitID
    mlogger:info(string.format("Req_Action nUserID_%d Action_%d[0:站起 1:坐下]",nUserID,Action))
    local  tUserInfo = tUserMgr.GetUserInfo(nUserID)
    if tUserInfo == nil then
        mlogger:info("Req_Action 用户获取不到数据")
        return 
    end

    local  tTable = tTableMgr.GetTable(tUserInfo.nTableId) 
    if tTable == nil then
        mlogger:info("Req_Action 获取牌桌失败")
        return 
    end

    if (Action == 0) then
        tTable:UserSetSitUp(nUserID)
    elseif Action == 1 then
        if SidID == nil then
            mlogger:info("Req_Action SidID 错误")
            return 
        end
        tTable:UserSetSitDown(nUserID, SidID)
    end
end

-- 抢庄请求
function Protocol.Req_QiangZhuang(sClientID, sData, nLen)
    mlogger:debug(string.format( "Req_QiangZhuang"))
    local s = tBase.GetRP().new(sData, nLen)
    local QiangZhuang_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZQiangZhuang_Q()
    QiangZhuang_Q:ParseFromString(s:GetString())
    local nUserID =  QiangZhuang_Q.UserID
    local nTimes  = QiangZhuang_Q.Times
    local tUser = tUserMgr.GetUserInfo(nUserID)
    if tUser == nil then
        return 
    end
    local tTable = tTableMgr.GetTable( tUser.nTableId)
   
    if tTable ~= nil then
        tTable:QiangZhuang(nUserID, nTimes,true)
    end
end

--下注请求
function Protocol.Req_XiaZhu(sClientID, sData, nLen)
    mlogger:debug(string.format( "Req_XiaZhu"))
    local s = tBase.GetRP().new(sData, nLen)
    local XiaZhu_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZXiaZhu_Q()
    XiaZhu_Q:ParseFromString(s:GetString())
    local nUserID =  XiaZhu_Q.UserID
    local nTimes  = XiaZhu_Q.Times
    local tUser = tUserMgr.GetUserInfo(nUserID)
    if tUser == nil then
        return
    end
    local tTable = tTableMgr.GetTable( tUser.nTableId)

    if tTable == nil then
        return
    end

    local key = tTable:GetIndexByVal(nTimes)

    if key == nil then
        mlogger:warn("Req_XiaZhuerr key ")
        return
    end

    local nIndex = 0
    tTable:UserXiaZhu(nUserID, nTimes,true)
end

--摊牌准备
function Protocol.TanPaiReady(sClientID, sData, nLen)
    mlogger:debug(string.format( "Req_TanPaiReady"))
    local s = tBase.GetRP().new(sData, nLen)
    local TanPaiReady_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZTanPaiReady_Q()
    TanPaiReady_Q:ParseFromString(s:GetString())
    local nUserID =  TanPaiReady_Q.UserID
    local Ready  = TanPaiReady_Q.Ready
    local tUser = tUserMgr.GetUserInfo(nUserID)
    if (tUser ==nil) then
        mlogger:info("TanPaiReady 用户不存在")
        return
    end
    local tTable = tTableMgr.GetTable( tUser.nTableId)
    if tTable ~= nil then
        tTable:UserTanPaiReady(nUserID, true)
    end
    
end

-- 玩家请求退出游戏服
function Protocol.Req_LogOut(sClientID, sData, nLen)
    mlogger:info("Req_LogOut")
    local s = tBase.GetRP().new(sData, nLen)
    local UserLogOut_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZUserLogOut_Q()
    UserLogOut_Q:ParseFromString(s:GetString())
    local nUserID = UserLogOut_Q.UserID

    local tUser = tUserMgr.GetUserInfo(nUserID)
    if (tUser ==nil) then
        mlogger:info("Req_LogOut 用户不存在")
        return
    end
    local tTable = tTableMgr.GetTable(tUser.nTableId)
    if tTable ~= nil and tUser.isRetain then
        --如果用户主动离开房间 则立即清掉留坐离桌
        tTable:_RetainCancel(nUserID,false)
    end

    if not tUser.isAndroid then
        tBase.LogT("主动离开抽水",nUserID)
        tTable:TaxByTableRateSettle(tUser)
    end

    Protocol.OnClose(sClientID, sData, nLen)

    Protocol.Rep_LogOut(sClientID,{UserID = nUserID,Result = 1})
end

-- '留座离桌'或'回到座位' 请求
function Protocol.Req_Retain(sClientID, sData, nLen)
    mlogger:info("Req_Retain")
    local s = tBase.GetRP().new(sData, nLen)
    local Retain_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZRetainGame_Q()
    Retain_Q:ParseFromString(s:GetString())
    local nUserID = Retain_Q.UserID
    local nOp = Retain_Q.nOp
    local tUser = tUserMgr.GetUserInfo(nUserID)
    if (tUser ==nil) then
        mlogger:error("Req_Retain 用户不存在")
        return
    end
    local tTable = tTableMgr.GetTable( tUser.nTableId)
    if tTable ~= nil then
        tTable:RetainReq({nUserId= nUserID,nOp=nOp})
    end
end

-- 表情聊天 请求
function Protocol.Req_Chat(sClientID, sData, nLen)
    mlogger:info("Req_Chat")
    local s = tBase.GetRP().new(sData, nLen)
    local Chat_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZChatGame_Q()
    Chat_Q:ParseFromString(s:GetString())
    local nUserID = Chat_Q.UserID
    local nChatId = Chat_Q.nChatId
    local nTarget = Chat_Q.nTarget
    local tUser = tUserMgr.GetUserInfo(nUserID)
    if (tUser ==nil) then
        mlogger:info("Req_Chat 用户不存在")
        return
    end
    local tTable = tTableMgr.GetTable( tUser.nTableId)
    if tTable ~= nil then
        tTable:Chat(sClientID,{UserID= nUserID,nChatId=nChatId,nTarget=nTarget})
    end
end

-- 牌桌总览 请求
function Protocol.Req_OverView(sClientID, sData, nLen)
    mlogger:info("Req_OverView")
    local s = tBase.GetRP().new(sData, nLen)
    local OverView_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZOverView_Q()  
    OverView_Q:ParseFromString(s:GetString())
    local nUserID = OverView_Q.UserID 
    local nNoUse = OverView_Q.nNoUse or 0
    local tUser = tUserMgr.GetUserInfo(nUserID)
    tBase.Log("Req_OverView nUserID_%d",nUserID)
    if (tUser ==nil) then
        mlogger:info("Req_OverView 用户不存在")
        return
    end
    local tTable = tTableMgr.GetTable( tUser.nTableId)
    if tTable ~= nil then
        tTable:OverView(sClientID,{nUserID= nUserID,nNoUse = nNoUse})
    end
end

-- 头像信息 请求
function Protocol.Req_HeadInfo(sClientID, sData, nLen)
    mlogger:info("Req_HeadInfo")
    local s = tBase.GetRP().new(sData, nLen)
    local HeadInfo_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZHeadInfo_Q()
    HeadInfo_Q:ParseFromString(s:GetString())
    local nUserID = HeadInfo_Q.nUserId
    local nPos = HeadInfo_Q.nPos
    local tUser = tUserMgr.GetUserInfo(nUserID)
    if (tUser ==nil) then
        mlogger:info("Req_HeadInfo 用户不存在")
        return
    end
    local tTable = tTableMgr.GetTable( tUser.nTableId)
    if tTable ~= nil then
        tTable:HeadInfo(sClientID,{nUserID= nUserID,nPos = nPos})
    end
end

-- 牌局详情 请求
function Protocol.Req_PaijuDetail(sClientID, sData, nLen)
    mlogger:info("Req_PaijuDetail")
    local s = tBase.GetRP().new(sData, nLen)
    local PaijuDetail_Q = tProtoMgr.ClubQZNiuNiuGame_pb.ClubQZPaijuDetail_Q()
    PaijuDetail_Q:ParseFromString(s:GetString())
    local nUserID = PaijuDetail_Q.nUserId
    local sPaiJuID = PaijuDetail_Q.sPaiJuID
    local tUser = tUserMgr.GetUserInfo(nUserID)
    if (tUser ==nil) then
        mlogger:info("Req_PaijuDetail 用户不存在")
        return
    end
    local tTable = tTableMgr.GetTable( tUser.nTableId)
    if tTable ~= nil then
        tTable:PaijuDetail(sClientID,{nUserID= nUserID,sPaiJuID = sPaiJuID})
    end
end

-- 链接断开（被动）
function Protocol.OnClose(sClientID, sData, nLen)
    local tUser = tUserMgr.GetUserInfoByLink(sClientID)
    mlogger:info(string.format( "OnClose sClientID: %s ,tUser:%s", sClientID,tJosn.encode(tUser) or "" ))
    if tUser ~= nil then
        tUser:SetOffLine()
        local  tTable = tTableMgr.GetTable(tUser.nTableId)
        if tTable ~= nil then 
            if (tUser:GetStatus() == tSrvPub.enumState.nPlay or tUser.isRetain) then
                tTable:UserLeave(tUser.nUserID)
            else
                if tUser:GetStatus() == tSrvPub.enumState.nSetDown then 
                    tTable:UserSetSitUp(tUser.nUserID)
                end
                tTable:ExitTable(tUser.nUserID)
                tUserLogin.OnUserLogout(sClientID)
            end
        else
            tUserLogin.OnUserLogout(sClientID)
        end
    end   
end

-- 踢人请求
function Protocol.ReqKickUser(sClientID, sData, nLen)
    mlogger:info("ReqKickUser")
    local s = tBase.GetRP().new(sData, nLen)
    local Read = tProtoMgr.PubProto_1_pb.REQ_Kick_User()
    Read:ParseFromString(s:GetString())
    local nUserId    = Read.nUserId or -1
    local nType      = Read.nType or -1    --1:立即踢出，解散 2:下局踢出 3:强制站起
 
    tBase.Log("OnKickUser nUserId_%d nType_%d",nUserId,nType)

    local tUser = tUserMgr.GetUserInfo(nUserId)
    if tUser ~= nil then
        mlogger:info("tUser")
        local  tTable = tTableMgr.GetTable(tUser.nTableId)
        if tTable ~= nil then 
            if (nType == 2) then
                --tTable:UserLeave(tUser.nUserID)
                tTable:AddKickUser(nUserId)
                -- tBase.LogT("被踢抽水",nUserId)
                tTable:TaxByTableRateSettle(tUser)
            elseif nType == 1 then
                GLogic.DisMissTable(tTable)
            elseif nType == 3 then
                tTable:AddForcedStandUser(nUserId)
                tTable:UserSetSitUp(nUserId)
                -- MsgPush.SendKickOutNotify(tUser.sClientID,"8",0)
            end
        end
    end
end

function Protocol.OnAdjustRobCountReq(sClientID, sData, nLen)
    local tData =BackstageAux:Parser(sData, nLen,"ReqAddAndroid")
    assert(tData~=nil,"ReqAddAndroid Parser Error")
    local sTableId =tData.sTableId or ""
    local nReserve =tData.nReserve   --1:增加一个机器人 -1:减少一个机器人 其它:无意义
    tBase.LogT("OnAdjustRobCountReq ",{sTableId=sTableId,nReserve=nReserve})
    local tTable =tTableMgr.GetTableBySTableId(sTableId)
    if tTable==nil then
       tBase.Log("tTable is nil,%s",sTableId)
       return
    end
    tTable:AdjustedAndroid()
    tTable:ReserveAndroid(nReserve)
end

return Protocol