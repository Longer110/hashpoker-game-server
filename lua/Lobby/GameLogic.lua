 -- 大厅服   游戏部分）
package.path = require("./lua/Lobby/Head").path
local tBase        = require("base")            -- 基础功能接口
local tname        = require("typename")        -- 类弄定义接口
local dbInfo       = require("DBInfo") -- 数据库连接信息
local ProtoMgr     = require("ProtoManager")    -- 协议管理对象 
local tGameCfg     = require("GameListConfig")   -- 道具配置
local tPubUserApi  = require("PublicUserInfo")    --玩家数据
local tLocation = require("LocationInfo")
local tParserAux = require("ParserAux")
local tClientIdMgr =require("ClientIdMgr")
local tConfig =require("GameConfig") -- 
local tMsgPush =require("MsgPush") 
local tWhiteList =require("WhiteList")
local http      = require("socket.http")  -- Http 服务器
local cjson     = require("cjson")        -- json 
local tApi = require("publicApi")
local tPublicRedis =require("PublicRedis")
local tGameVersion =require("GameVersion")
local logger = require("logger")      -- 日志对象
local RedisCahche =require("RedisCahche")
local tPay          = require("Pay")
local tMsgHandle    = require("MsgHandle")
local tFrozen  = require("Frozen")    
local LobbyParse =tParserAux.LobbyParse
local LobbySendToClient =tParserAux.LobbySendToClient
local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse
local DbProtoEncode1 =tParserAux.DbProtoEncode1
local DbProtoParse1 =tParserAux.DbProtoParse1

local tUserIdToGameListUpdateTime={} 
local tGameTypeList = {}

local function LobbySendToUser(nUserId,strProto,tSendData)
    local sClientID =tClientIdMgr.GetClientIdByUserId(nUserId)
    if not sClientID then
        tBase.Log("Err happen ,can not find nUserId_%d clientID",(nUserId or -1))
       return false
    end
    return LobbySendToClient(sClientID,strProto,tSendData)
 end
local function UsersGroupId(nUserId)
    local tUserInfo = tPubUserApi.GetAllUserInfo(nUserId)
    if not tUserInfo then
        tBase.Log("Err happen ,UsersGroupId =>GetAllUserInfo fail,nUserId_%d",nUserId)
        return -1
    end  
    local nShopID =  tonumber(tUserInfo.nShopID) or -1   
    local nGroupId =tConfig.GetGroupId(nShopID)
    if nShopID<0 or nGroupId<0 then
        tBase.Log("Err happen ,nShopID_%d nGroupId_%d nUserId_%d",nShopID,nGroupId,nUserId)
    end
    return nGroupId
end


local function PlayerCnt(nGameId,nGroupId,nRoomId)
    return tPubUserApi.GetOnlineUserCount(nGroupId,nGameId,nRoomId)
end

GameLogic = {}

function GameLogic.OnConnectionClose(nUserId,sClientId)
    tBase.Log("OnConnectionClose nUserId_%d sClientId_%s",nUserId,sClientId)
   tClientIdMgr.DestroyClientID(sClientId)

   tUserIdToGameListUpdateTime[nUserId]=nil
end

function GameLogic.OnSwicthConn(sClientID, Data, len) 
    local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 
    local Read = ProtoMgr.Gateway_pb.RUQ_SwicthConn()
    Read:ParseFromString(ReadData:GetString())
    tBase.Log("_OnSwicthConn  nUserId_%d swicth to:"..sClientID,(Read.nUserID or -1)) 
    if not tClientIdMgr.GetClientIdByUserId(Read.nUserID or -1) then
        tBase.Log("nUserId_%d areadly leave",(Read.nUserID or -1))
        return
    end

    if Read.nUserID then
       tClientIdMgr.BuildContact(sClientID,Read.nUserID)
    end
 end

--大厅登陆请求
function GameLogic.OnLogonReq(sClientID, Data, len)
    local strReq ="LogonReq"

    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnLogonReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnLogonReq strReq:"..strReq)
        return
    end
    local nUserID =math.floor(tData.nUserID)
    if not tPubUserApi.ChecksClientIDByUserID(nUserID,sClientID) then
        tBase.Log("nUserId_%d Error",nUserID)
        return
     end
    local tUserInfo = tPubUserApi.GetAllUserInfo(tData.nUserID)
    if tUserInfo == nil then   
        tBase.Log("_OnLogonReq GetAllUserInfo fail,nUserID_%d",tData.nUserID)
        LobbySendToClient(sClientID,"LogonRsp",{nResult =1})
        return
    end 
    tBase.Log("_OnLogonReq  Logon succee nUserID_%d",tData.nUserID)
    tClientIdMgr.BuildContact(sClientID,tData.nUserID)

    local nGroupId =UsersGroupId(tData.nUserID)
    tPubUserApi._SetUser_GroupId(tData.nUserID,nGroupId)  

    local ttUserInfo={}
    ttUserInfo.nGold     = tonumber(tUserInfo.nGold) or -1
    ttUserInfo.sNickName = tUserInfo.sNickName or 'unknown_'
    ttUserInfo.nSex      = tonumber(tUserInfo.nSex) or 0
    ttUserInfo.sFaceID   = tUserInfo.sFaceID or '0'
    ttUserInfo.nUserID =tData.nUserID
    ttUserInfo.nVisitor = tUserInfo.nAccountType and (math.floor(tUserInfo.nAccountType)==0) and 1 or 2
    ttUserInfo.sTime = tUserInfo.nRegisTime or ""
    tBase.LogT(ttUserInfo)

    local tExtraConfigureInfo = tPublicRedis.GetExtraConfigureInfo(nGroupId)
    local nGameId,nRoomId,sServerKey,sGameName,sTableId =tPubUserApi.GetUserPlayingGame(tData.nUserID)
    local tRlt ={}
    tRlt.nResult =0
    tRlt.tUserInfo =ttUserInfo
    tRlt.tGameList =GameLogic._GetUserGameListNotify(tData.nUserID)
    tRlt.nLastClubId = tPubUserApi.GetUserLastEnterClub(tData.nUserID)
    if tExtraConfigureInfo then
        tRlt.tExtraConfigureInfo = tExtraConfigureInfo
    end
    -- local token = jwt.sign(env.jwtSecret,{uid = tData.nUserID, nick = ttUserInfo.sNickName})
    -- local extra = {}
    -- if tExtraConfigureInfo then
    --     local ok, data = pcall(cjson.decode, tExtraConfigureInfo)
    --     if ok and type(data) == "table" then
    --         extra = data
    --     end
    -- end
    -- extra.jwtToken = token
    -- tExtraConfigureInfo = cjson.encode(extra)
    -- tRlt.tExtraConfigureInfo = tExtraConfigureInfo
    if nGameId then
        tRlt.tCurrentPlay={nGameId=nGameId,nRoomId=(nRoomId or -1),sTableId =sTableId}
        tBase.Log("_OnLogonReq  nUserId_%d is in playing,nGameId_%d nRoomId_%d sTableId_%s ",tData.nUserID,nGameId,(nRoomId or -1),sTableId or "-1")
    end
    if sTableId and #sTableId>0 then
        tRlt.nLastClubId = tPubUserApi.GetClubIdByTableId(sTableId)
    end
    LobbySendToClient(sClientID,"LogonRsp",tRlt)
    tBase.Log("_OnLogonReq 玩家_%d 连接大厅成功 nGroupId_%d ",tData.nUserID,nGroupId)

    tPubUserApi.IncrbyGamingUser(-1,-2,-1,false,1,tData.nUserID)

end

-- 获取玩家  分组id
function GameLogic.Get_User_GroupId(sClientID, Data, len)
    if not dbInfo.isGm then 
        return 
    end 

    local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 
    local Read = ProtoMgr.Lobby_pb.Get_UserInfo_Q()
    Read:ParseFromString(ReadData:GetString())

    local arrUserId = {}
    local nSize = #Read.arrUserId

    for i=1,nSize do
        local nUserID = Read.arrUserId[i]
        local t = {}
        t.nUserID = nUserID
        t.nGroupId = UsersGroupId(nUserID)
        local tUserInfo  = tPubUserApi.GetAllUserInfo(nUserID)
        if tUserInfo.nUserID == nil then           
            tBase.Log(" 请求获取玩家:  %d    GetAllUserInfo   is nil    ",nUserID)
            -- return 
        end 
        if tonumber(tUserInfo.isAndroid) == 1 then  
            t.nGroupId = tonumber(tUserInfo.nGrpId) or 1
        end         
        arrUserId[nUserID] = t
        tBase.Log(" 请求玩家:  %d   --------------->  分组数据 nGroupId: %d    ",nUserID, t.nGroupId )
    end
   
    local tSend = ProtoMgr.Lobby_pb.Get_UserInfo_P()
    for k,v in pairs(arrUserId) do
        local arrUserGroupInfo =  tSend.arrUserGroupInfo:add()
        arrUserGroupInfo.nUserID = k
        arrUserGroupInfo.nGroupId = v.nGroupId
        arrUserGroupInfo.nShoupId = 1
        arrUserGroupInfo.sNickName = '-1'
    end
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.Main_CMD, ProtoMgr.LobbyPro.SUB_REP_GET_USER_INFO) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())   
    tBase.Log(" 请求获取玩家群组         返回成功 ")
end 

--房间列表请求
function GameLogic.OnRoomListReq(sClientID, Data, len)
    local strReq ="RoomListReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnLogonReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnLogonReq strReq:"..strReq)
        return
    end
    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID then
        tBase.Log("Err happen Not Logon OnRoomListReq")
        return
    end
    local nGroupId =UsersGroupId(nUserID)
    tBase.Log("获得组ID %d nGameId:%d ",nGroupId,tData.nGameId)

    local isInWhiteList =tWhiteList.IsUserInWhiteList(nUserID)  --是否是白名单用户


    local arrRoomList={} 
    local nFailReson=-2 --游戏维护中或未开放

    local isMaintaining,isTimeOut =tConfig.IsGameMaintaining(nGroupId,tData.nGameId)
    if (not isMaintaining) or (isInWhiteList and isTimeOut) then
        arrRoomList ,nFailReson=tConfig.GetRoomList_v2(nGroupId,tData.nGameId)
    end

    local arrRoomItems={}
    for _,item in ipairs(arrRoomList) do
        local tempItem ={}
        tempItem.nRoomId=item.nRoomId
        tempItem.nEnterFloorLimit =item.nEnterFloorLimit
        tempItem.nAnte =item.nAnte
        tempItem.nPlayerCnt =PlayerCnt(tData.nGameId,nGroupId,item.nRoomId)
        --tBase.Log("房间 nRoomId "..tempItem.nRoomId.."  EnterFloorLimit "..item.nEnterFloorLimit.."在线人数 "..tempItem.nPlayerCnt)
        table.insert(arrRoomItems,tempItem)
    end
    local tRlt ={}
    tRlt.nGameId =tData.nGameId
    tRlt.arrRoomItems =arrRoomItems
    if nFailReson ==-1 then
        tRlt.sErrStr="Game Close"
        tRlt.nErrCode=1
    elseif nFailReson==-2 then
        tRlt.sErrStr="Game Maintaining"
        tRlt.nErrCode=2
    end
    LobbySendToClient(sClientID,"RoomListRsp",tRlt)
    tBase.Log("房间列表请求 成功 nUserID_%d RoomListLen:%d sErrStr:%s nUpdateCount:%d",nUserID,#arrRoomItems,(tRlt.sErrStr or ''),tConfig.nUpdateCount)
  
    GameLogic.PushGameList_IfNeed(nUserID)
end

--财富请求
function GameLogic.OnTreasureReq(sClientID, Data, len)
    local strReq ="TreasureReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnLogonReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnLogonReq strReq:"..strReq)
        return
    end
    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID then
        tBase.Log("Err happen Not Logon OnTreasureReq")
        return
    end

    local nGold = tPubUserApi.Get_User_Gold(nUserID)
    if not nGold then
        tBase.Log("OnTreasureReq redis上没有玩家的金币信息 nUserID_%d",nUserID)
        return
    end

    tBase.Log("OnTreasureReq nUserID_%d nGold_%f",nUserID,nGold)

    local TreasureRsp ={}
    TreasureRsp.nResult = 0              --0成功  其它:失败	
	TreasureRsp.nGold   = nGold         --金币 (成功时有) 
    LobbySendToUser(nUserID,"TreasureRsp",TreasureRsp)
    -- local DbUserTreasureReq ={}
    -- DbUserTreasureReq.nUserId =nUserID
    -- local tPacket,nMainCmd,nSubCmd =DbProtoEncode('DbUserTreasureReq',DbUserTreasureReq)
    -- if not tPacket then
    --     tBase.Log("Err happen,DbProtoEncode_%s fail",'DbUserTreasureReq')
    --     return
    -- end
    -- tBase.Log("begin to DbUserTreasureReq nMainCmd_%d nSubCmd_%d nUserID_%d",(nMainCmd or -1),(nSubCmd or -1),nUserID)
    -- tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize())  
    -- return
end

--玩家财富数据 从db服返回
function GameLogic.OnDbUserTreasureRsp(sReturnKey, Data, nLen)
    tBase.Log("OnDbUserTreasureRsp")
    local strReq ="DbUserTreasureRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end

    local nUserId =tData.nUserId
	local nGold =tData.nGold  

    local TreasureRsp ={}
    TreasureRsp.nResult = 0              --0成功  其它:失败	
	TreasureRsp.nGold   = nGold         --金币 (成功时有) 
    LobbySendToUser(nUserId,"TreasureRsp",TreasureRsp)
end

-- 游戏列表更新通知
function GameLogic._GetUserGameListNotify(nUserID)
    local nGroupId =UsersGroupId(nUserID)
    local arr = {}
    local arrGameItems ={}
    local arrGameList =tConfig.GetGameList(nGroupId)
    local tUserInfo = tPubUserApi.GetAllUserInfo(nUserID)
    local nErrCode = 0
    local sErrStr = ""
    local sLog = string.format("sPlatform=%s: ",tUserInfo.sPlatform)
    tBase.Log("#arrGameList[%d]=%d",nGroupId,#arrGameList)

    if #arrGameList == 0 then
        nErrCode = 1
        sErrStr = string.format("PlatformDB-Config_GameList is not configured Game or Open Game;nGroupId=%d",nGroupId)
    end

    for _,item in ipairs(arrGameList) do
        local tVersionInfo =tGameVersion.GetGameVersionInfo(nGroupId,item.sGamePath,tUserInfo.sPlatform)
        if (tVersionInfo and tVersionInfo.sPlatform) or tUserInfo.sPlatform == "test" then
            local gameItem ={}
            gameItem.nGameId     	=item.nGameId ;         --游戏id, 105:扎金花 113:三公 106:21点 104:百人牛牛 103:通比牛牛 ...
            gameItem.nGameOrder  	=item.nGameOrder ;  	--游戏排序的位置:1 -- 100 
            gameItem.nGameStatus 	=item.nGameStatus ; 	--游戏状态:0默认 1热门 2最新 3即将开启 4正在维护
            gameItem.sIconUrl    	=item.sIconUrl; 	    --图标地址
            gameItem.sGamePath   	=item.sGamePath;        --游戏路径
            gameItem.sVersion    	=tVersionInfo.sVersion or ""; 	    --版本号
            gameItem.sZipFilePath 	=tVersionInfo.sZipFilePath or "";		--地址
            gameItem.sMD5FilePath   =tVersionInfo.sMD5FilePath or "";	    --地址
            gameItem.nPeople = GameLogic._GetGamePeople(nGroupId,item.nGameId)

            table.insert(arrGameItems,gameItem)
        else
            nErrCode = 2
            sLog = sLog..string.format("GameId=%d sGamePath=%s,",item.nGameId,item.sGamePath)
        end
        tGameTypeList[item.nGameId] ={nGameId=item.nGameId,nGrId=nGroupId }
    end

    if nErrCode==2 then
        -- sErrStr = "WebDB-Config_Update_Package is not configured "..sLog
    end

    if nErrCode~=0 then
        tBase.Log(sErrStr)
    end

    local GameListNotify ={}
    GameListNotify.arrGameItems =arrGameItems
    GameListNotify.nErrCode = nErrCode
    GameListNotify.sErrStr = sErrStr
    return GameListNotify,nGroupId
end

function GameLogic.PushGameList(nUserID)
    local GameListNotify,nGroupId =GameLogic._GetUserGameListNotify(nUserID)
    local arrGameItems =GameListNotify.arrGameItems or {}
    tBase.Log("PushGameList to nUserID_%d nGroupId_%d GameCount_%d nUpdateCount:%d",nUserID,nGroupId,#arrGameItems,tConfig.nUpdateCount)
    LobbySendToUser(nUserID,"GameListNotify",GameListNotify)    
    tUserIdToGameListUpdateTime[nUserID]=tConfig.nUpdateCount
end

function GameLogic.PushGameList_IfNeed(nUserID)
    local nLastPushTime =tUserIdToGameListUpdateTime[nUserID]
    if tConfig.nUpdateCount ~=nLastPushTime then
        GameLogic.PushGameList(nUserID)        
    end
end

-- 在线人数列表 
function GameLogic.OnlinePeopleReq(sClientID, Data, len)
    local strReq ="OnlinePeopleReq"
    local tData =LobbyParse(Data, len,strReq)
    local nUserId = tData.nUserID
    local NoticeOnlinePeople = {}
    local arrPeople = {}
    local sPeople = ""
    for _,v in pairs(tGameTypeList) do
        local t = {}
        t.nGameID = v.nGameId
        t.nPeople = GameLogic._GetGamePeople(v.nGrId,v.nGameId)
        table.insert(arrPeople,t) 
        sPeople = sPeople ..string.format("Id_%d=%d,",v.nGameId,t.nPeople)
    end
    NoticeOnlinePeople.arrPeople = arrPeople
    LobbySendToUser(nUserId,"NoticeOnlinePeople",NoticeOnlinePeople)
    tBase.Log("_OnlinePeopleReq nUserId_%d  游戏总人数  %s ",nUserId,sPeople)
    return 
end

function IsOuNumber(num)
    local num1,num2=math.modf(num/2)--返回整数和小数部分
    if(num2==0)then
        return true
    else
        return false
    end
end

-- 检查是否为麻将 游戏
local function isMajong(nGameId)
    local tMajong = {202,203,204,207,208,210}
    for k,v in pairs(tMajong) do
        if v == nGameId then 
            return true 
        end 
    end
   return false
end

-- 获取游戏中总人数
function GameLogic._GetGamePeople(nGroupId,nGameId)
    local nOnlineUserCnt = 0   -- 在线人数
    local nAndroidCnt = 0      -- 机器人数
    for nRoomId=1,5 do 
        local nOnlineUserCount= 0
        local nAndroidCount=0
        if nRoomId == 5 then 
            nOnlineUserCount = tPublicRedis._GetGameCenterUserCount(nGroupId,nGameId,0) 
            nAndroidCount = tPublicRedis._GetGameAndroidCount(nGroupId,nGameId,0) 
        else
            nOnlineUserCount = tPublicRedis._GetGameCenterUserCount(nGroupId,nGameId,nRoomId) 
            nAndroidCount = tPublicRedis._GetGameAndroidCount(nGroupId,nGameId,nRoomId) 
        end 
        nOnlineUserCnt = nOnlineUserCnt + nOnlineUserCount
        nAndroidCnt = nAndroidCnt + nAndroidCount
    end    
    if nAndroidCnt < 0 then 
        -- tBase.Log("_GetGamePeople  ErrorMsg nGroupId_%d  nGameId_%d   nAndroidCnt_%d < 0 ",nGroupId,nGameId,nAndroidCnt)   
        nAndroidCnt = 0      
    end 
    if nOnlineUserCnt < 0 then 
        -- tBase.Log("_GetGamePeople  ErrorMsg nGroupId_%d  nGameId_%d   nOnlineUserCnt_%d < 0 ",nGroupId,nGameId,nOnlineUserCnt)   
        nOnlineUserCnt = 0
    end     
    local nCnt = nOnlineUserCnt + nAndroidCnt
    if isMajong(nGameId) then    -- 处理麻将 偶数问题
        local num1,num2=math.modf(nCnt/2)
        if num2 ~= 0 then 
            nCnt = nCnt + 1  
        end 
    end             
    return nCnt
end

-- 获取游戏中总人数
function GameLogic._GetLiveGamePeople(nGroupId,nGameId,nRoomId)
    local nOnlineUserCnt = 0   -- 在线人数
    local nAndroidCnt = 0      -- 机器人数
    nOnlineUserCnt = tPublicRedis._GetGameCenterUserCount(nGroupId,nGameId,nRoomId) 
    nAndroidCnt = tPublicRedis._GetGameAndroidCount(nGroupId,nGameId,nRoomId)      
    if nAndroidCnt < 0 then  
        nAndroidCnt = 0      
    end 
    if nOnlineUserCnt < 0 then  
        nOnlineUserCnt = 0
    end     
    local nCnt = nOnlineUserCnt + nAndroidCnt 
    return nCnt
end

local tUserBankUnlockDate={} --nUserId be Key

--进入银行请求
function GameLogic.OnEnterBankReq(sClientID, Data, len)
    local strReq ="EnterBankReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnEnterBankReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnEnterBankReq strReq:"..strReq)
        return
    end
    tBase.Log("OnEnterBankReq")
    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID then
        tBase.Log("Err happen Not Logon OnEnterBankReq")
        return
    end
    local nGameId =tPubUserApi.GetUserPlayingGame(nUserID)
    if nGameId then
        LobbySendToUser(nUserID,"EnterBankRsp",{nResult=10,nGameId=nGameId,sErrStr='in playing,nGameId:'..nGameId})
        tBase.Log('in playing,nGameId:'..nGameId)
        return
    end

    local tTreasure = tPubUserApi.GetUserTreasure(nUserID)
    if not tTreasure then
        tBase.Log("Err happen,why GetUserTreasure is nil")
        tTreasure={}
    end

    local sDate =os.date("%Y/%m/%d", os.time()) --当前日期(年 月 日)
    local sLastUnlockDate =tUserBankUnlockDate[nUserID] or "" --上一次解锁银行日期
    local isShouldUnlock =(sDate ~=sLastUnlockDate) --是否需要先进行解锁操作

    local EnterBankRsp ={}
    EnterBankRsp.nResult =1
    if not isShouldUnlock then
        EnterBankRsp.nResult =0 
        EnterBankRsp.tTreasure={nGold=tTreasure.nGold or 0}
    end
    tBase.LogT("EnterBankRsp ",EnterBankRsp)
    --EnterBankRsp.sErrStr ='for test'
    LobbySendToUser(nUserID,"EnterBankRsp",EnterBankRsp)
end

--解锁银行请求
function GameLogic.OnBankUnlockReq(sClientID, Data, len)
    local strReq ="BankUnlockReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnBankUnlockReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnBankUnlockReq strReq:"..strReq)
        return
    end
    tBase.Log("OnBankUnlockReq")

    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID then
        tBase.Log("Err happen Not Logon OnBankUnlockReq")
        return
    end

    local DbCheckSafePasswordReq ={}
    DbCheckSafePasswordReq.nUserId =nUserID
    DbCheckSafePasswordReq.sPassword =tData.sPassword

    local tPacket,nMainCmd,nSubCmd =DbProtoEncode('DbCheckSafePasswordReq',DbCheckSafePasswordReq)
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",'DbCheckSafePasswordReq')
        return
    end
    tBase.Log("begin to DbCheckSafePasswordReq nMainCmd_%d nSubCmd_%d nUserID_%d",(nMainCmd or -1),(nSubCmd or -1),nUserID)
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
end

--Db服银行密码验证返回处理
function GameLogic.OnDbCheckSafePasswordRsp(sReturnKey, Data, nLen)
    tBase.Log("OnDbCheckSafePasswordRsp")
    local strReq ="DbCheckSafePasswordRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
	local tTreasure = tPubUserApi.GetUserTreasure(tData.nUserId)
    if not tTreasure then
        tBase.Log("Err happen,why GetUserTreasure is nil")
        tTreasure={}
    end
    local BankUnlockRsp ={}
    if tData.nResult ==0 then
        BankUnlockRsp.nResult=0
        BankUnlockRsp.tTreasure={nGold=tTreasure.nGold or 0}
    else
        BankUnlockRsp.nResult=2     --密码错误
        BankUnlockRsp.sErrStr ='password error'
    end
    tBase.LogT("BankUnlockRsp ",BankUnlockRsp)
    LobbySendToUser(tData.nUserId,"BankUnlockRsp",BankUnlockRsp)
    
    local sDate =os.date("%Y/%m/%d", os.time()) --当前日期(年 月 日)
    tUserBankUnlockDate[tData.nUserId]=sDate    --记录该用户解锁日期
end

--银行金币存取请求
function GameLogic.OnBankAccessReq(sClientID, Data, len)
    local strReq ="BankAccessReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnBankAccessReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnBankAccessReq strReq:"..strReq)
        return
    end
    tBase.Log("OnBankAccessReq")
    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID then
        tBase.Log("Err happen Not Logon OnBankAccessReq")
        return
    end

    local tTreasure = tPubUserApi.GetUserTreasure(nUserID)
    if not tTreasure then
        tBase.Log("Err happen,why GetUserTreasure is nil")
        tTreasure={nGold=0}
    end
    --tData.nOperation		//操作 0:存钱 1:取钱
    --tData.nGold		    //所操作的金币数目
    local sDate =os.date("%Y/%m/%d", os.time()) --当前日期(年 月 日)
    local sLastUnlockDate =tUserBankUnlockDate[nUserID] or "" --上一次解锁银行日期
    local isShouldUnlock =(sDate ~=sLastUnlockDate) --是否需要先进行解锁操作

    local BankAccessRsp ={}
    BankAccessRsp.nOperation =tData.nOperation
    --今天是否验证过银行密码检查
    if isShouldUnlock then
        BankAccessRsp.nResult = 1
        BankAccessRsp.sErrStr ='bank not unlock'
        LobbySendToUser(nUserID,"BankAccessRsp",BankAccessRsp)
        tBase.Log("bank not unlock")
        return
    end
    --存钱参数合法性判断
    if tData.nOperation ==0 and (tData.nGold>tTreasure.nGold or tData.nGold<=0) then
        BankAccessRsp.nResult =3
        BankAccessRsp.sErrStr ='Gold Error'
        LobbySendToUser(nUserID,"BankAccessRsp",BankAccessRsp)
        tBase.Log("gold error,to save %d,only have %d",tData.nGold,tTreasure.nGold)
        return
    end
    --取钱参数合法性判断
    if tData.nOperation ==1 and ( tData.nGold<=0) then
        BankAccessRsp.nResult =3
        BankAccessRsp.sErrStr ='Gold Error'
        LobbySendToUser(nUserID,"BankAccessRsp",BankAccessRsp)
        tBase.Log("gold error,to get %d",tData.nGold)
        return
    end

    local nGameId =tPubUserApi.GetUserPlayingGame(nUserID)
    if nGameId then
        BankAccessRsp.nResult =10
        BankAccessRsp.sErrStr ='you are in playing,nGameId:'..nGameId
        LobbySendToUser(nUserID,"BankAccessRsp",BankAccessRsp)
        tBase.Log('in playing,nGameId:'..nGameId)
        return
    end

    --存钱
    if tData.nOperation ==0 then
        tPubUserApi.ChangeUserTreasure({nUserID=nUserID, nItemID=1, nDel= -tData.nGold ,nSourceType =1})
        tPubUserApi.ChangeUserTreasure({nUserID=nUserID, nItemID=2, nDel= tData.nGold ,nSourceType =1001})
        BankAccessRsp.nResult =0
        BankAccessRsp.tTreasure={nGold=tTreasure.nGold-tData.nGold}
        LobbySendToUser(nUserID,"BankAccessRsp",BankAccessRsp)
        tBase.Log("save gold_%s succee",tData.nGold)
        return
    end
    --取钱
    if tData.nOperation ==1 then
        tPubUserApi.ChangeUserTreasure({nUserID=nUserID, nItemID=1, nDel= tData.nGold ,nSourceType =1002})
        tPubUserApi.ChangeUserTreasure({nUserID=nUserID, nItemID=2, nDel= -tData.nGold ,nSourceType =1})
        BankAccessRsp.nResult =0
        BankAccessRsp.tTreasure={nGold=tTreasure.nGold+tData.nGold}
        LobbySendToUser(nUserID,"BankAccessRsp",BankAccessRsp)
        tBase.Log("get gold_%s succee",tData.nGold)
        return
    end
    tBase.Log("nOperation_%d error",tData.nOperation)
end

--银行密码更改请求
function GameLogic.OnBankPasswordChangeReq(sClientID, Data, len)
    local strReq ="BankPasswordChangeReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnBankPasswordChangeReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnBankPasswordChangeReq strReq:"..strReq)
        return
    end
    tBase.Log("OnBankPasswordChangeReq")

    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID then
        tBase.Log("Err happen Not Logon OnBankPasswordChangeReq")
        return
    end


    local sDate =os.date("%Y/%m/%d", os.time()) --当前日期(年 月 日)
    local sLastUnlockDate =tUserBankUnlockDate[nUserID] or "" --上一次解锁银行日期
    local isShouldUnlock =(sDate ~=sLastUnlockDate) --是否需要先进行解锁操作

    if isShouldUnlock then
        local BankPasswordChangeRsp ={}
        BankPasswordChangeRsp.nResult=1
        BankPasswordChangeRsp.sErrStr="bank not unlock"
        LobbySendToUser(nUserID,"BankPasswordChangeRsp",BankPasswordChangeRsp)
        tBase.Log("bank not unlock")
        return
    end

    local DbBankPasswordChangeReq ={}
    DbBankPasswordChangeReq.nUserId =nUserID
    DbBankPasswordChangeReq.sOldPassword=tData.sOldPassword
    DbBankPasswordChangeReq.sNewPassword=tData.sNewPassword
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode('DbBankPasswordChangeReq',DbBankPasswordChangeReq)
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",'DbBankPasswordChangeReq')
        return
    end
    tBase.Log("begin to DbBankPasswordChangeReq nMainCmd_%d nSubCmd_%d nUserID_%d",(nMainCmd or -1),(nSubCmd or -1),nUserID)
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
   
end

--Db服银行密码修改结果返回处理
function GameLogic.OnDbBankPasswordChangeRsp(sReturnKey, Data, nLen)
    tBase.Log("OnDbBankPasswordChangeRsp")
    local strReq ="DbBankPasswordChangeRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    local BankPasswordChangeRsp ={}
    BankPasswordChangeRsp.nResult=tData.nResult
    if BankPasswordChangeRsp.nResult ~=0 then
        BankPasswordChangeRsp.sErrStr="change password fail"
        tBase.Log("change password fail")
    else
        tUserBankUnlockDate[tData.nUserId] =nil
    end
    tBase.LogT("BankPasswordChangeRsp ",BankPasswordChangeRsp)
    LobbySendToUser(tData.nUserId,"BankPasswordChangeRsp",BankPasswordChangeRsp)
end


--银行存取明细请求
function GameLogic.OnBankAccessDetailReq(sClientID, Data, len)
    local strReq ="BankAccessDetailReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq)
        return
    end
    tBase.Log("OnBankAccessDetailReq")

    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID then
        tBase.Log("Err happen Not Logon OnBankAccessDetailReq")
        return
    end

    local sDate =os.date("%Y/%m/%d", os.time()) --当前日期(年 月 日)
    local sLastUnlockDate =tUserBankUnlockDate[nUserID] or "" --上一次解锁银行日期
    local isShouldUnlock =(sDate ~=sLastUnlockDate) --是否需要先进行解锁操作

     --今天是否验证过银行密码检查
    if isShouldUnlock then
        local BankAccessDetailRsp ={}
        BankAccessDetailRsp.nResult =1
        BankAccessDetailRsp.arrDetails={}
        LobbySendToUser(nUserID,"BankAccessDetailRsp",BankAccessDetailRsp)
        return
    end

    local DbBankAccessDetailReq ={}
    DbBankAccessDetailReq.nUserId =nUserID
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode('DbBankAccessDetailReq',DbBankAccessDetailReq)
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",'DbBankAccessDetailReq')
        return
    end
    tBase.Log("begin to DbBankAccessDetailReq nMainCmd_%d nSubCmd_%d nUserID_%d",(nMainCmd or -1),(nSubCmd or -1),nUserID)
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
end

--Db服银行存取明细返回处理
function GameLogic.OnDbBankAccessDetailRsp(sReturnKey, Data, nLen)
    tBase.Log("OnDbBankAccessDetailRsp")
    local strReq ="DbBankAccessDetailRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    
    local BankAccessDetailRsp ={}
    BankAccessDetailRsp.nResult=0
    BankAccessDetailRsp.arrDetails={}
    for _,item in ipairs(tData.arrDetails) do
        local itemCopy ={}
        itemCopy.sTime=item.sTime
        itemCopy.nOperation =item.nOperation
        itemCopy.nGold =item.nGold
        table.insert(BankAccessDetailRsp.arrDetails,itemCopy)
    end
    LobbySendToUser(tData.nUserId,"BankAccessDetailRsp",BankAccessDetailRsp)
end


--战绩查询请求
function GameLogic.OnPaijuRecordReq(sClientID, Data, len)
    local strReq ="PaijuRecordReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnPaijuRecordReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnPaijuRecordReq strReq:"..strReq)
        return
    end
    tBase.Log("OnPaijuRecordReq111_"..tostring(tData.nPage))
    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID or tData.nPage<0 then
        tBase.Log("Err happen Not Logon OnBankAccessDetailReq "..tData.nPage)
        return
    end
    local RecentRecordReq ={}
    RecentRecordReq.nUserId =nUserID
    RecentRecordReq.nGameId=tData.nGameId or 0
    RecentRecordReq.nPage = tData.nPage
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode('RecentRecordReq',RecentRecordReq)
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",'RecentRecordReq')
        return
    end
    tBase.Log("begin to RecentRecordReq nMainCmd_%d nSubCmd_%d nUserID_%d nGameId_%d",(nMainCmd or -1),(nSubCmd or -1),nUserID,RecentRecordReq.nGameId)
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
end

--Db服战绩查询返回
function GameLogic.OnDbRecentRecordRsp(sReturnKey, Data, nLen)
    tBase.Log("OnDbRecentRecordRsp===========>")
    local strReq ="RecentRecordRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    local nIndex =0
    local nIDx = 20
    local PaijuRecordRsp={}
    PaijuRecordRsp.arrRecords={}
    local nMaxCount = math.floor(tData.nMaxCount/nIDx) + ((tData.nMaxCount%nIDx>0) and 1 or 0 )
    PaijuRecordRsp.nSumPage = nMaxCount
    for _,item in ipairs(tData.arrRecords) do
        local itemCp ={}
        itemCp.sPaiJuID=item.sPaiJuID 		--牌局编号
		itemCp.nRoomId =item.nRoomId 		--房间(场次)id  1新手 2初级 3中级 4高级 0免费
		itemCp.nProfit =item.nProfit		--盈利
        itemCp.sTime   = item.sTime         --结算时间
        itemCp.nType   = item.nType 
        itemCp.nAnte   = item.nAnte 
        table.insert(PaijuRecordRsp.arrRecords,itemCp)
    end
    tBase.Log("#PaijuRecordRsp.arrRecords :%d",#PaijuRecordRsp.arrRecords)
    LobbySendToUser(tData.nUserId,"PaijuRecordRsp",PaijuRecordRsp)
end

--牌局明细查询请求
function GameLogic.OnPaijuDetailReq(sClientID, Data, len)
    local strReq ="PaijuDetailReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnPaijuDetail strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnPaijuDetail strReq:"..strReq)
        return
    end    
    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID then
        tBase.Log("Err happen Not Logon OnPaijuDetail")
        return
    end
    tBase.Log("PaiJuDetail_Req_nUserId="..nUserID.." sPaiJuID="..tData.sPaiJuID)
    local RecentDetailReq ={} 
    RecentDetailReq.sPaiJuID= tData.sPaiJuID or ""
    RecentDetailReq.nUserId = nUserID
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode1('RecentDetailReq',RecentDetailReq)
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode1_%s fail",'RecentDetailReq')
        return
    end
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
end

--Db服牌局记录查询返回
function GameLogic.OnDbRecentDetailRsp(sReturnKey, Data, nLen)
    tBase.Log("OnDbRecentDetail Rsp to Clietn")
    local strReq ="RecentDetailRsp"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    if tData.GameId ==123 then
        GameLogic.OnLobbyRecentDetailRsp(sReturnKey, Data, nLen)
        return
    end

    local function BuildBaiRenData(GameType)
        if tApi.FindKeyByVal(tPublicRedis.tGameType,GameType)  then --百人类            
            local _cjson = cjson.decode(tData.tElseInfo)
            if GameType==tPublicRedis.tGameType.nBaiRenZhaJinHua then
                tData.tBetInfo = tData.tElseInfo
            elseif GameType==tPublicRedis.tGameType.nSeDie then
                --色碟做兼容
                if _cjson.tBet then
                    tData.tBetInfo = cjson.encode(_cjson.tBet)
                else
                    tData.tBetInfo = tData.tElseInfo
                end
            else
                tData.tBetInfo = cjson.encode(_cjson.tBet)
            end
            if GameType~=tPublicRedis.tGameType.nBaiRenNiuNiu then
                local t = {}
                t.nProfit = tData.nWinLose
                tData.tUsersInfo = cjson.encode(t)
            else
                tData.tUsersInfo = cjson.encode(_cjson.tUserInfo)
            end
        end
    end
    local PaijuDetailRsp={} 
    PaijuDetailRsp.GameId = tData.GameId    -- 游戏gameId
    BuildBaiRenData(tData.GameId)
    PaijuDetailRsp.nAnte = tData.nAnte
    PaijuDetailRsp.tUsersInfo = tData.tUsersInfo or "{}"
    PaijuDetailRsp.nZhuang = tData.nZhuang
    PaijuDetailRsp.tDealCardInfo = tData.tDealCardInfo or "{}"
    PaijuDetailRsp.tBetInfo = tData.tBetInfo or "{}" 
    tBase.LogT("#Paiju.GameId:",PaijuDetailRsp.GameId," PaiJuDetail_Rsp_nUserId=",tData.nUserId, " tBetInfo=",PaijuDetailRsp.tBetInfo,
            " tData.tUsersInfo=",tData.tUsersInfo,"CardInfo",PaijuDetailRsp.tDealCardInfo)

    LobbySendToUser(tData.nUserId,"PaijuDetailRsp",PaijuDetailRsp)
end


--德州战绩 请求
function GameLogic.LobbyDeZhouRecordReq(sClientID, tData, nLen) 
    local tReqData =LobbyParse(tData, nLen,"LobbyDeZhouRecordReq")
    assert(tReqData~=nil,"LobbyDeZhouRecordReq Parser Fail")

    local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
       tBase.Log(" Not Logon,sClientID_"..(sClientID or 'nil'))
       return false
    end
    local nIdOfStart =tReqData.nMinId
    local nCnt =tReqData.nQueryCnt
    tBase.Log("LobbyDeZhouRecordReq nUserId:%d nMinId:%d nQueryCnt:%d",nUserId,nIdOfStart,nCnt)
 
    if nCnt<=0 then
       tBase.Log("nCnt is Zero")
       return
    end
    if nCnt>50 then nCnt=50 end
    local tPacket =DbProtoEncode1('DbLiveRecordReq',{nUserId=nUserId,nGameId=123,nIdOfStart=nIdOfStart,nCnt=nCnt,sEcho="LobbyDeZhouRecordReq"})
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
 end

  --德州记录详情 请求
  function GameLogic.LobbyDeZhouRecordDetailReq(sClientID, tData, nLen) 
    local tReqData =LobbyParse(tData, nLen,"LobbyDeZhouRecordDetailReq")

    assert(tReqData~=nil,"LobbyDeZhouRecordDetailReq Parser Fail")
    local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
       tBase.Log(" Not Logon,sClientID_"..(sClientID or 'nil'))
       return false
    end
    tBase.Log("LobbyDeZhouRecordDetailReq nUserId:%d sSeriesNumber:%s",nUserId,tReqData.sSeriesNumber)

    local tPacket =DbProtoEncode1("RecentDetailReq",{nUserId=nUserId,sPaiJuID=tReqData.sSeriesNumber,nVer=2})
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
 end
 
 --德州 db服输赢记录查询 返回
function GameLogic.OnDbLiveRecordRsp(sReturnKey, Data, nLen)
    local tData =DbProtoParse1(Data, nLen,"DbLiveRecordRsp")
    if tData ==nil then
       tBase.Log("LobbyDeZhouRecordRsp _Parse Err")
       return
    end
    local nUserId =tData.nUserId
    local arrItem ={}
    local nMinId =tData.nIdOfStart or 0x7FFFFFFF
    if nMinId ==0 then nMinId =0x7FFFFFFF end


    if tData.sEcho=="BrLiveGameRecordReq" then
        local sData = tData.sData or "" 

        for _,v in ipairs(tData.arrRecords) do
            local item ={}
            item.sPaiJuID=v.sPaiJuID  --牌局编号
            item.sTime=v.sTime 	     --结算时间
            item.nBet=v.nBet          --总下注
            item.nProfit=v.nProfit    --盈利
            item.nId=v.nId
            table.insert(arrItem,item)
            if item.nId<nMinId then
               nMinId =item.nId
            end
         end
        local nAccountType = tPubUserApi.GetUserAccountType(nUserId)
        if nAccountType == 2 then
            tBase.Log("BrLiveGameRecordRsp nUserId:%d RecordLen:%d  测试玩家 ",nUserId,#arrItem) 
            -- arrItem = {}               
        else
            tBase.Log("BrLiveGameRecordRsp nUserId:%d RecordLen:%d nSumItem_%d sData: %s ",nUserId,#arrItem,tData.nSumItem,sData)               
        end 
        local BrLiveGameRecordRsp = {}
        BrLiveGameRecordRsp.arrItem = arrItem 
        BrLiveGameRecordRsp.nMinId = nMinId 
        BrLiveGameRecordRsp.nGameID = tData.nGameId 
        BrLiveGameRecordRsp.nSumItem = tData.nSumItem 
        BrLiveGameRecordRsp.sData = sData
        LobbySendToUser(nUserId,"BrLiveGameRecordRsp",BrLiveGameRecordRsp)
        return
    end

    if tData.sEcho=="LobbyDeZhouRecordReq" then
        for _,v in ipairs(tData.arrRecords) do
            local item ={}
            item.sSeriesNumber=v.sPaiJuID  --牌局编号
            item.sTime=v.sTime 	     --结算时间
            item.nBet=v.nBet          --总下注
            item.nWin=v.nProfit    --盈利
            item.Id=v.nId
            table.insert(arrItem,item)
            if item.Id<nMinId then
                nMinId =item.Id
            end
        end
        local nAccountType = tPubUserApi.GetUserAccountType(nUserId)
        if nAccountType == 2 then 
            tBase.Log("LobbyDeZhouRecordRsp nUserId:%d RecordLen:%d  测试玩家 ",nUserId,#arrItem)
            -- arrItem = {}               
        else
            tBase.Log("LobbyDeZhouRecordRsp nUserId:%d RecordLen:%d",nUserId,#arrItem)             
        end 
        tBase.Log("LobbyDeZhouRecordRsp nUserId:%d RecordLen:%d",nUserId,#arrItem)
        LobbySendToUser(nUserId,"LobbyDeZhouRecordRsp",{arrItem=arrItem,nMinId=nMinId})
        return
    end
end
 

 --德州 db服输赢记录详情查询 返回
function GameLogic.OnLobbyRecentDetailRsp(sReturnKey, Data, nLen)
    local tData =DbProtoParse1(Data, nLen,"RecentDetailRsp")
    if tData ==nil then
       tBase.Log("RecentDetailRsp _Parse Err")
       return
    end
    if tData.GameId ~=123 then
      -- assert(false)
       return
    end
    tBase.Log("OnLobbyRecentDetailRsp nUserId:%d",tData.nUserId)
 
    local isSucceeA,tUsersInfo =pcall(cjson.decode,tData.tUsersInfo)
    if not isSucceeA then 
        tBase.LogT("tUsersInfo ",tUsersInfo,' ',tData.tUsersInfo)
        if type(tUsersInfo) == "string" then 
            logger:error(tUsersInfo)
        end
    end
    local isSucceeB,tDealCardInfo =pcall(cjson.decode,tData.tDealCardInfo)
    if not isSucceeB then 
        tBase.LogT("tDealCardInfo ",tDealCardInfo,' ',tData.tDealCardInfo)
        if type(tDealCardInfo) == "string" then 
            logger:error(tDealCardInfo)
        end
    end
    local isSucceeC,tBetInfo =pcall(cjson.decode,tData.tBetInfo)
    if not isSucceeC then 
        tBase.LogT("tBetInfo " ,tBetInfo,' ',tData.tBetInfo)
        if type(tBetInfo) == "string" then 
            logger:error(tBetInfo)
        end
    end
    local isSucceeD,tElseInfo =pcall(cjson.decode,tData.tElseInfo)
    if not isSucceeD then 
        tBase.LogT("tElseInfo ",tElseInfo,' ',tData.tElseInfo)
        if type(tElseInfo) == "string" then 
            logger:error(tElseInfo)
        end
    end
    
    local tSitIdToInfo ={}
    for _, v in ipairs(tUsersInfo) do
       tSitIdToInfo[v.nSitId] ={nUserId=v.nUserId,sName=v.sName,nProfit=v.nProfit}
    end
    for _, v in ipairs(tDealCardInfo) do
       local tInfo =tSitIdToInfo[v.nSitId]
       if tInfo then
          tInfo.arrCard =v.arrCard
          tInfo.isFold =v.isFold
          if v.isFold and tInfo.nUserId~=tData.nUserId and (not v.isShowCardWhenEnd)  then
             tInfo.arrCard ={0,0}
          end
       end
    end
    for _, v in ipairs(tBetInfo) do
       local tInfo =tSitIdToInfo[v.nSitId]
       if tInfo then
          tInfo.nBet =v.nBet
       end
    end
 
    local arrItem ={}
    for _,v in pairs(tSitIdToInfo) do
       local ItemA ={}
       ItemA.sName=v.sName or ""	            --玩家昵称
       ItemA.arrHoleCards=v.arrCard or {0,0}	--底牌
       ItemA.nBet=v.nBet or 0		            --下注
       ItemA.nWin=v.nProfit	or 0		         --派彩
       ItemA.nUserId=v.nUserId		            --玩家ID
       ItemA.isFold =v.isFold                   --是否弃牌
       table.insert(arrItem,ItemA)
    end
    local DeZhouRecordDetailRsp ={}
    DeZhouRecordDetailRsp.sSeriesNumber =tData.sPaiJuID
    DeZhouRecordDetailRsp.arrCommunityCards =tElseInfo.arrCommunityCards or {}
    DeZhouRecordDetailRsp.arrItem =arrItem
 
    tBase.LogT("LobbyDeZhouRecordDetailRsp ",DeZhouRecordDetailRsp)
    LobbySendToUser(tData.nUserId,"LobbyDeZhouRecordDetailRsp",DeZhouRecordDetailRsp)
end
 
 --百人直播游戏战绩 请求
function GameLogic.BrLiveGameRecordReq(sClientID, Data, len)
    local tReqData =LobbyParse(Data, len,"BrLiveGameRecordReq")
    assert(tReqData~=nil,"BrLiveGameRecordReq Parser Fail")

    local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
       tBase.Log(" Not Logon,sClientID_"..(sClientID or 'nil'))
       return false
    end
    local nIdOfStart =tReqData.nMinId
    local nCnt =tReqData.nQueryCnt
    local nGameID =tReqData.nGameID
    local sStartTime =tReqData.sStartTime or ""
    local sEndTime =tReqData.sEndTime or ""

    tBase.Log("BrLiveGameRecordReq nUserId:%d nMinId:%d nQueryCnt:%d nGameID:%d",nUserId,nIdOfStart,nCnt,nGameID)
    if nCnt<=0 then
       tBase.Log("nCnt is Zero")
       return
    end
    if nCnt>50 then nCnt=50 end
    local tData = {nUserId=nUserId,nGameId=nGameID,nIdOfStart=nIdOfStart,nCnt=nCnt,sEcho="BrLiveGameRecordReq"}
    tData.sStartTime = sStartTime 
    tData.sEndTime = sEndTime 

    local tPacket =DbProtoEncode1('DbLiveRecordReq',tData)
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
end

--账号注销 请求
function GameLogic.AccountCloseReq(sClientID, Data, len)
    local tReqData =LobbyParse(Data, len,"AccountCloseReq")
    assert(tReqData~=nil,"AccountCloseReq Parser Fail")

    local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
       tBase.Log(" Not Logon,sClientID_"..(sClientID or 'nil'))
       return false
    end
    tBase.Log("AccountCloseReq nUserId:%d",nUserId)

    local DbAccountCloseReq={}
    DbAccountCloseReq.sAccounts=tReqData.sAccounts
    DbAccountCloseReq.sPassword=tReqData.sPassword
    DbAccountCloseReq.nUserId=nUserId
    
    local tPacket =DbProtoEncode1('DbAccountCloseReq',DbAccountCloseReq)
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
 
end

--账号注销 db服返回
function GameLogic.OnDbAccountCloseRsp(sReturnKey, Data, nLen)
    local tData =DbProtoParse1(Data, nLen,"DbAccountCloseRsp")
    if tData ==nil then
        tBase.Log("DbAccountCloseRsp _Parse Err")
        return
    end
    local nUserId =tData.nUserId
    LobbySendToUser(nUserId,"AccountCloseRsp",{nCode=tData.nCode,sErrStr=""})
end


--百人直播游戏记录详情 请求
function GameLogic.BrLiveGameDetailReq(sClientID, Data, len)
    local tReqData =LobbyParse(Data, len,"BrLiveGameDetailReq")
    assert(tReqData~=nil,"BrLiveGameDetailReq Parser Fail")

    local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
       tBase.Log(" Not Logon,sClientID_"..(sClientID or 'nil'))
       return false
    end
    tBase.Log("BrLiveGameDetailReq nUserId:%d sPaiJuID:%s",nUserId,tReqData.sPaiJuID)
    local sSql =string.format("call PaiJuDetail_Read_v5('%s',%d)",tReqData.sPaiJuID,nUserId)

    local tPacket =DbProtoEncode1("GetResultsBySqlReq",{sEcho="BrLiveGameDetailReq",sSql=sSql,sDbName="DJH_RecordDB",nUserId=nUserId})
    tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
end

--sql执行结果(百人直播游戏记录详情) 返回
function GameLogic.OnGetResultsBySqlRsp(sReturnKey, Data, nLen)
    local tData =DbProtoParse1(Data, nLen,"GetResultsBySqlRsp")
    if tData ==nil then
       tBase.Log("GetResultsBySqlRsp _Parse Err")
       return
    end
    local nUserId =tData.nUserId
    if #tData.sJsonRows <2 then 
       tBase.Log("sJsonRows is not valid")
       return
    end
    local arrRows =cjson.decode(tData.sJsonRows)
    local tRow =arrRows[1] or {}
    if not tRow.PaiJuDetail_DealCardInfo then 
        tBase.Log("PaiJuDetail_DealCardInfo is nil")
        return
    end 
   local DealCardInfo= cjson.decode(tRow.PaiJuDetail_DealCardInfo)
   local PaiJuDetail_ElseInfo= cjson.decode(tRow.PaiJuDetail_ElseInfo)
   local PaiJuWinLoseRecord_ElseInfo= cjson.decode(tRow.PaiJuWinLoseRecord_ElseInfo)
   local nGameId =tonumber(tRow.GameId)
   local sPaiJuID =tRow.sPaiJuID
   local nWinLose = 0 --tonumber(tRow.PaiJuWinLoseRecord_WinLose) or 0

   local BrLiveGameDetailRsp ={}
   BrLiveGameDetailRsp.sPaiJuID =sPaiJuID
   if PaiJuDetail_ElseInfo.sTableName then
    BrLiveGameDetailRsp.sTableNo =PaiJuDetail_ElseInfo.sTableName
   end
   if PaiJuDetail_ElseInfo.nBootsno then
    BrLiveGameDetailRsp.sXueNo =string.match (PaiJuDetail_ElseInfo.nBootsno, '[%a%d]*') --字母与数字
   end
   if PaiJuDetail_ElseInfo.nRound then
    BrLiveGameDetailRsp.sRoundNo =string.match (PaiJuDetail_ElseInfo.nRound, '[%a%d]*') 
   end
   BrLiveGameDetailRsp.nGameID =nGameId
   
   local arrProfitDetail ={}
   if PaiJuWinLoseRecord_ElseInfo.arrBet then
        for _,arr in ipairs(PaiJuWinLoseRecord_ElseInfo.arrBet) do  --arr格式 :{nBetArea,nBetSum,nProfit,nNumber}
            local nAreaId =arr[1] or -1
            local nBetSum =arr[2] or 0
            local nProfit=arr[3] or 0
            local nNumber =arr[4] or -1
           -- if nProfit>0 then
             --   nProfit =nProfit +nBetSum
          --  end
            table.insert(arrProfitDetail,{nAreaId=nAreaId,nProfit=nProfit,nNumber=nNumber})
            nWinLose = nWinLose + nProfit
        end
   elseif PaiJuWinLoseRecord_ElseInfo.tBet then
        for _,item in ipairs(PaiJuWinLoseRecord_ElseInfo.tBet) do
            table.insert(arrProfitDetail,{nAreaId=(item.nBetArea or item.nArea),nProfit=item.nProfit,nNumber=item.nNumber})
            nWinLose = nWinLose + item.nProfit
        end
    end
   BrLiveGameDetailRsp.arrProfitDetail=arrProfitDetail

   local Game_BaiJiaLe =122
   local Game_YuXiaXie=121
   local Game_TouBao =155
   local Game_SeDie =153
   local Game_FootBall =129
   local Game_LongHu=139
   local Game_NiuNiu=143
   local Game_Br=146        --红黑彩

   if nGameId ==Game_BaiJiaLe then
        local Result ={}
        Result.arrCardsOfXian=DealCardInfo[1].arrCard		--闲家牌,牌数量[2,3]
        Result.arrCardsOfZhuang=DealCardInfo[2].arrCard	--庄家牌,牌数量[2,3]
        Result.nPointXian=DealCardInfo[1].nCardType		--闲点数
        Result.nPointZhuang=DealCardInfo[2].nCardType		--庄点数 
        Result.nResult=PaiJuDetail_ElseInfo.nResult		--1:闲赢 2:庄赢 0:和
        BrLiveGameDetailRsp.tBaiJiaLeResult =Result
   elseif nGameId ==Game_YuXiaXie then
        local Result ={}
        Result.arrCards =DealCardInfo[1].arrCard
        BrLiveGameDetailRsp.tYuXiaXieResult =Result
   elseif nGameId ==Game_TouBao then
        local Result ={}
        Result.arrCards =DealCardInfo[1].arrCard
        BrLiveGameDetailRsp.tTouBaoResult =Result
   elseif nGameId==Game_SeDie then
        local Result ={}
        Result.arrCards =DealCardInfo[1].arrCard
        BrLiveGameDetailRsp.tSeDieResult =Result
    elseif nGameId==Game_FootBall then
        local Result ={}
        Result.arrCards=DealCardInfo[1].arrCard		--1:进  0:不进
        BrLiveGameDetailRsp.tFootBallResult =Result
    elseif nGameId==Game_LongHu then
        local Result ={}
        Result.nCardL=DealCardInfo[1].arrCard[1]	    --龙 牌
		Result.nCardH=DealCardInfo[2].arrCard[1]		--虎 牌
		Result.nResult=PaiJuDetail_ElseInfo.nResult		--1:龙赢 2:虎赢 0:和
        BrLiveGameDetailRsp.tLongHuResult=Result
    elseif nGameId==Game_NiuNiu then
        local Result ={}
        Result.arrCardsOfZhuang = DealCardInfo[1].ShouPai --庄家牌
        Result.arrCardsOfXian1 =DealCardInfo[2].ShouPai --闲一家牌
        Result.arrCardsOfXian2 =DealCardInfo[3].ShouPai --闲一家牌
        Result.arrCardsOfXian3 =DealCardInfo[4].ShouPai --闲一家牌

        Result.nZhuangNiuWhat =DealCardInfo[1].NiuWhat --庄家牛几
        Result.nXian1NiuWhat =DealCardInfo[2].NiuWhat --闲一家牛几
        Result.nXian2NiuWhat =DealCardInfo[3].NiuWhat --闲二家牛几
        Result.nXian3NiuWhat =DealCardInfo[4].NiuWhat --闲三牛几

        local arrResult = {}
        arrResult[1] = DealCardInfo[1].nResult --庄家输赢结果 (1:庄赢 2:闲赢)
        arrResult[2] =  DealCardInfo[2].nResult --闲一家输赢结果(1:庄赢 2:闲赢)
        arrResult[3] =  DealCardInfo[3].nResult --闲一家输赢结果(1:庄赢 2:闲赢)
        arrResult[4] =  DealCardInfo[4].nResult --闲一家输赢结果(1:庄赢 2:闲赢)
        Result.arrResult = arrResult

        BrLiveGameDetailRsp.tNiuNiuResult =Result
    elseif nGameId==Game_Br then
        BrLiveGameDetailRsp.nNumberOpen =PaiJuDetail_ElseInfo.nResult   --开奖号码
    end

   BrLiveGameDetailRsp.nWinLose = nWinLose

   tBase.Log("BrLiveGameDetailRsp,nUserId:%d ",nUserId)
   tBase.LogT("BrLiveGameDetailRsp:",BrLiveGameDetailRsp)
   LobbySendToUser(nUserId,"BrLiveGameDetailRsp",BrLiveGameDetailRsp)
end

function GameLogic.OnBeforeLoadScenceReq(sClientID, Data, len)
    local strReq ="BeforeLoadScenceReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local nUserID =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserID then
        tBase.Log("_OnBeforeLoadScenceReq  Err happen Not Logon  sClientID: "..sClientID)
        return
    end
    local nGameId =tData.nGameId
    local nRoomId =tData.nRoomId or -1
    local nCurrentGameId,nCurrentRoomId,sGameServerKey,sGameName,sTableId=tPubUserApi.GetUserPlayingGame(nUserID,nGameId)
    tBase.Log("_OnBeforeLoadScenceReq  nUserID_%d  nGameId_%d  nRoomId_%d  nCurrentGameId:%d nCurrentRoomId:%d",nUserID,nGameId,nRoomId,nCurrentGameId or -1, nCurrentRoomId or -1)
    local BeforeLoadScenceRsp={}
    BeforeLoadScenceRsp.nResult = 0;  	--0:成功(可以加载场景) 101:金币不足 200:在其他游戏玩(或同游戏不同房间) 201:游戏已经结束 其它：未定义错误
    BeforeLoadScenceRsp.nGameId=nil;	--当前正在玩的游戏id(nResult=200时有)
    BeforeLoadScenceRsp.nRoomId=nil;	--当前正在玩的房间id(nResult=200时有)
    BeforeLoadScenceRsp.sErrStr =nil;	--异常描述 (nResult非0时有),可不管
    if nRoomId == -1 then
        if nGameId~=nCurrentGameId then
            BeforeLoadScenceRsp.nResult = 201
            BeforeLoadScenceRsp.sErrStr ="nRoomId Error or Game already end"
            tBase.Log(BeforeLoadScenceRsp.sErrStr)
        end
        LobbySendToUser(nUserID,"BeforeLoadScenceRsp",BeforeLoadScenceRsp)
        return
    end

    if nCurrentGameId then
        if nCurrentGameId~=nGameId or (sTableId ~= nil and #sTableId > 2) or (nCurrentRoomId~=nil and nRoomId~=nCurrentRoomId) then
            BeforeLoadScenceRsp.nResult = 200;
            BeforeLoadScenceRsp.nGameId=nCurrentGameId
            BeforeLoadScenceRsp.nRoomId=nCurrentRoomId
            BeforeLoadScenceRsp.sTableId = sTableId
            BeforeLoadScenceRsp.sErrStr ="In other game playing or other room"
            tBase.Log("_OnBeforeLoadScenceReq  sErrStr_"..BeforeLoadScenceRsp.sErrStr)
        end
        LobbySendToUser(nUserID,"BeforeLoadScenceRsp",BeforeLoadScenceRsp)
        return
    end

    local tUserInfo = tPubUserApi.GetAllUserInfo(nUserID) or {}
    local nShopID =  tonumber(tUserInfo.nShopID) or -1 
    local tRoomConfig =tConfig.GetRoomConfig(nGameId,nRoomId,nShopID)
    local nGroupId =tConfig.GetGroupId(nShopID)

    local isInWhiteList =tWhiteList.IsUserInWhiteList(nUserID)  --是否是白名单用户
    local isMaintaining,isTimeOut =tConfig.IsGameMaintaining(nGroupId,nGameId)

    if isMaintaining and (not isInWhiteList) then
        BeforeLoadScenceRsp.nResult = 301
        BeforeLoadScenceRsp.sErrStr ="游戏维护中"
        LobbySendToUser(nUserID,"BeforeLoadScenceRsp",BeforeLoadScenceRsp)
        tBase.Log("_OnBeforeLoadScenceReq  sErrStr_"..BeforeLoadScenceRsp.sErrStr)
        GameLogic.PushGameList_IfNeed(nUserID) --给玩家重新推送游戏列表
       return
    end

    if tRoomConfig==nil then
        BeforeLoadScenceRsp.nResult = 300
        BeforeLoadScenceRsp.sErrStr ="房间已关闭"
        LobbySendToUser(nUserID,"BeforeLoadScenceRsp",BeforeLoadScenceRsp)
        tBase.Log("_OnBeforeLoadScenceReq  sErrStr_"..BeforeLoadScenceRsp.sErrStr)
        GameLogic.PushGameList_IfNeed(nUserID) --给玩家重新推送游戏列表
       return
    end
    
    if nRoomId >0 and tonumber(tUserInfo.nGold or 0)<tRoomConfig.nEnterFloorLimit then      --金币不足判断
        BeforeLoadScenceRsp.nResult = 101
        BeforeLoadScenceRsp.sErrStr ="gold not enough"
        LobbySendToUser(nUserID,"BeforeLoadScenceRsp",BeforeLoadScenceRsp)
        tBase.Log("_OnBeforeLoadScenceReq  sErrStr_"..BeforeLoadScenceRsp.sErrStr)
       return
    end
    LobbySendToUser(nUserID,"BeforeLoadScenceRsp",BeforeLoadScenceRsp)
end
 


--[[
--玩家财富数据 从db服返回
function GameLogic.On_DBUserTreasure(sReturnKey, sData, nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()
  
    local Read = ProtoMgr.PubProto_pb.RUP_GetTreasure()
    Read:ParseFromString(ReadData:GetString())
    local sClientID = Read.nClientID
   --Read.nUserID
    --Read.nGold 
    tBase.Log("db server return UserTreasure nUserID_%d",Read.nUserID)
 
    local tRlt ={}
    tRlt.nResult =0
    tRlt.nGold =Read.nGold
    LobbySendToClient(sClientID,"TreasureRsp",tRlt) 
    return 
end 
]]
 

-- 获取 游戏的场次数据
function GameLogic.Get_GameTypeCfg(sClientID, Data, len)

    local Read =LobbyParse(Data, len,"REQ_Get_GameType")
    if not Read then
        tBase.Log("Err happen ,Parse error") 
        return
    end
    local nId = Read.Id
    local nUserID   = Read.nUserID
    -- local tUserInfo = tPubUserApi.GetAllUserInfo(nUserID)
    tBase.Log(" 玩家: %d   nId: %d   获取游戏的场次数据     ",nUserID,nId ) 
    local arrGameCfg = tGameCfg.Get_GroupGameRelation(nId)
    local tSend = ProtoMgr.Lobby_pb.REP_Get_GameType()
    if arrGameCfg ~= nil then 
        for i,v in ipairs(arrGameCfg) do   
            local arr =  tSend.GameType:add()      
            arr.Id       = v.Id   
            arr.Number   = 100 
            arr.Session  = v.Session   
            arr.Floor    = v.Floor   
            arr.LowGrade = v.LowGrade   
            arr.SessionName  = v.SessionName 
            arr.Status   = v.Status 
        end
    else
        tBase.Log(" 玩家: %d   没有 该nId: %d   相关的配置数据       ",nUserID,nId ) 
    end 
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_GET_GAMETYPE) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())   
    tBase.Log(" 玩家: %d  游戏的场次数据返回    size: %d ",nUserID,nClient:GetSize()) 
    return
end

function GameLogic.Get_ZBTableID(sClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 

    local Read = ProtoMgr.Lobby_pb.Get_ZBTableID_Q()
    Read:ParseFromString(ReadData:GetString())

    local surl   = Read.sUrl
    tBase.Log("Get_ZBTableID:" .. surl)

    local nStatus  = -1
    local stableID = "100"
    local strRet = http.request(surl)
    if (strRet ~= nil and strRet ~= "") then
        tBase.Log("Get_ZBTableID Info: "..strRet)
        local unjson = cjson.decode(strRet)
        nStatus = tonumber(unjson["status"]) or 0
        stableID = unjson["tableID"]
        tBase.Log("status = "..nStatus.." tableID= "..stableID)
    else
        tBase.Log("get zbtable error")
    end
    local res = ProtoMgr.Lobby_pb.Get_ZBTableID_P()
    res.nStatus   = nStatus
    res.sTableID  = tostring(stableID)
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.Main_CMD, ProtoMgr.LobbyPro.SUB_REP_GET_ZBTABLEID)
    nClient:AddString(res:SerializeToString())
    tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())
end

-- 进入游戏前 处理
function GameLogic.Enter_Game(sClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID()

    tBase.Log("    进入游戏前 处理     " )
    local Read = ProtoMgr.Lobby_pb.REQ_EnterGame()
    Read:ParseFromString(ReadData:GetString())
    local nUserID   = Read.nUserID
    local GameCfgID = Read.GameCfgID

    local tUserInfo = tPubUserApi.GetAllUserInfo(nUserID)
    if tUserInfo == nil then 
        tBase.Log(" 玩家: %d   GameCfgID: %d   进入游戏准备   用户离线     ",nUserID,GameCfgID )      
        return
    end 
    tUserInfo.nGold  = tonumber(tUserInfo.nGold )
    tBase.Log(" 玩家: %d   GameCfgID: %d   进入游戏准备  nGold: %d    ",nUserID,GameCfgID,tUserInfo.nGold) 
    local nResult = 0   -- 进入游戏结果0 成功， 1 金币不足，2 没有找到服务器 
    local tGameCfg = tGameCfg.Get_GameCfg(GameCfgID)
    if tGameCfg == nil then 
        tBase.Log(" 玩家: %d   GameCfgID: %d   没有该场次配置     ",nUserID,GameCfgID ) 
        nResult = 3 
    else           
        tBase.Log(" 该 %s   进入下限: %d   Status: %d   ",tGameCfg.SessionName,tGameCfg.Floor,tGameCfg.Status) 
        if tGameCfg.Status == 1 then      
            local nGold = tPubUserApi.Get_User_Gold(nUserID)
            if nGold  < tGameCfg.Floor then 
                tBase.Log(" 玩家: %d   进入游戏准备  nGold: %d  下限： %d  不能进入该场次  ",nUserID,GameCfgID,nGold,tGameCfg.Floor) 
                nResult = 1 
            end 
        else
            tBase.Log(" 该 %s  Status: %d   没有开启 ",tGameCfg.SessionName,tGameCfg.Status) 
            nResult = 4    -- 该场次没有开启
        end
    end 

    local SType =  tonumber(tGameCfg.SType)    
    local sTypename = GameLogic.GetServer_Typename(SType)
    if sTypename == nil then
        tBase.Log("  没有该类型服务器 sTypename 获取为空,不能再继续 UserID %d",nUserID)
        nResult = 5 
    end 
    local arrGame = tBase.m_centerRedis.Mo:keys("*_"..sTypename.."*")
    if #arrGame == 0 then 
       tBase.Log(" 没有该类型服务器,不能再继续 UserID %d",nUserID)
       nResult = 5  
    end  

    local tSend = ProtoMgr.Lobby_pb.REP_EnterGame()
    tSend.nResult  = nResult  
    tSend.SType    = tGameCfg.SType
    tSend.Session  = tGameCfg.Session
    tSend.Floor    = tGameCfg.Floor
    tSend.LowGrade = tGameCfg.LowGrade
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_ENTER_GAME) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())  

    if nResult ~= 0 then  return end 

    --  可以进行负载均衡 

    --开始进入牌桌
    tBase.Log("  进入牌桌 %d  %d   %s key :%s",nUserID,SType,sTypename,arrGame[1])
    tLocation.ApplyEnter({nUserId=nUserID, sTypeName=sTypename, SType=SType, sKey=arrGame[1]})
    return
end

--帮助列表请求
function GameLogic.OnHelpInfoReq(sClientID, Data, len)
    local strReq ="HelpInfoReq"
    local tData =LobbyParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnHelpInfoReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnHelpInfoReq strReq:"..strReq)
        return
    end
    local nGroupId =UsersGroupId(tData.nUserID)
    local nGameID = tData.nGameID or -1
    local sUiType=tPublicRedis._OnGeHelptUI(nGroupId) or ""
    local tSend = ProtoMgr.Lobby_pb.HelpInfoRsp()
    tSend.sUiType = sUiType
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.Main_CMD, ProtoMgr.LobbyPro.HelpInfoRsp_CMD) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())  
    tBase.Log("OnHelpInfoReq nGroupId_"..nGroupId.." nGameId_ "..nGameID.." sUiType_"..sUiType)
end

function  GameLogic.GetServer_Typename(SType)
    if SType == 101 then 
        return tname.kpqzniuniu
    elseif SType == 102 then
        return tname.sjzjniuniu 
    elseif SType == 103 then 
        return tname.tbniuniu
    elseif SType == 104 then 
        return tname.brniuniu
    elseif SType == 105 then 
        return tname.zhajinhua
    elseif SType == 106 then 
        return tname.dian21
    elseif SType == 107 then 
        return tname.baijiale
    elseif SType == 108 then 
        return tname.xueliuch
    elseif SType == 109 then 
        return tname.qzbaijiale     --抢庄百家乐
    elseif SType == 110 then 
        return tname.tbbaijiale     --通比百家乐
    elseif SType == 111 then 
        return tname.caosanmahjong
    elseif SType == 112 then 
        return tname.tuidaohu
    elseif SType == 113 then 
        return tname.sangong
    elseif SType == 215 then 
        return tname.qzbaijiale
    else
        return nil 
    end     
end


--后台通知 玩家VIP身份
--tData.nUserId 玩家身份
--tData.nVip vip身份 0:无vip 1~9 vip等级
function GameLogic.OnWebUserVipNotify(sReturnKey, Data, nLen)
    local s = tBase.GetRP().new(Data, nLen)
    local tData = ProtoManager.Backstage_pb.WebUserVipNotify()
    tData:ParseFromString(s:GetString())

    assert(tData~=nil,"WebUserVipNotify _Parse Err,tData is nil")

    tBase.Log("_OnWebUserVipNotify 后台通知 玩家VIP身份 nUserId:%d nVip:%d",tData.nUserId,tData.nVip)

    if tData.nUserId<=0 then
        return
    end

    if tData.nVip<0 then
        return
    end

    tPubUserApi.UpdateUserData({nUserID=tData.nUserId,nVip=tData.nVip})

    --通知游戏服玩家VIP身份
    local nGameId,nRoomId,sServerKey =tPubUserApi.GetUserPlayingGame(tData.nUserId)
    if sServerKey and #sServerKey>0 then
        tBase.PostToServer(sServerKey, 0, Data, nLen)
        tBase.Log("_OnWebUserVipNotify send notify to serv %s",sServerKey)
    else
        tBase.Log("_OnWebUserVipNotify not in Game serv %s",tostring(sServerKey))
    end
end

-- 区块链 人数 
function GameLogic._GetBlockPeopleSum(nGroupId,nGameId,nRoomId,nTableCount)
    local sLog = ""
    local sKey =string.format("GameAndroidCount_GroupId_%d:GameId_%d:RoomId_%d",nGroupId,nGameId,nRoomId)
    local sKey1 =string.format("GameCenterUserCount_GroupId_%d:GameId_%d:RoomId_%d",nGroupId,nGameId,nRoomId)
    local tRedis = tBase.m_MyRedisData[1].redis 
    local function _GetSum(sKey)
        local nCnt = tRedis:get(sKey) or 0   
        if tonumber(nCnt) < 0 then return 0 end 
        return tonumber(nCnt)
    end
    local nAndroidCnt =_GetSum(sKey) or 0   
    local nUserCount = _GetSum(sKey1) or 0  
    sLog = string.format("%s nTableCount_%d nAndroidCnt_%d nUserCount_%d]",sLog,nTableCount,nAndroidCnt,nUserCount) 

    if nTableCount > 0 then 
        local nMinCnt = math.random(15,30)  * nTableCount   --最少數量
        if nAndroidCnt <= 0 then         
            sLog = string.format(" %s nAndroidCnt_%d  nMinCnt_%d ",sLog,nAndroidCnt,nMinCnt)
            nAndroidCnt = PublicRedis._SetGameAndroidCount(nGroupId,nGameId,nRoomId,nMinCnt-nAndroidCnt)    
            sLog = string.format(" %s New nAndroidCnt_%d",sLog,nAndroidCnt)
        end 
        if nAndroidCnt >= 3000 then 
            sLog = string.format(" %s (nAndroidCnt_%d >= 3000) nMinCnt_%d, ",sLog,nAndroidCnt,nMinCnt)
            nAndroidCnt = PublicRedis._SetGameAndroidCount(nGroupId,nGameId,nRoomId, -(nAndroidCnt-nMinCnt))   
            sLog = string.format(" %s  nMinCnt_%d, New_%d ",sLog,nMinCnt,nAndroidCnt) 
        end 
        -- 真人數量
        if nUserCount < 0 or nUserCount >= 2000 then  
            sLog = string.format(" %s (nUserCount_%d 不在(0 ~2000),nMinCnt_%d ",sLog,nUserCount,nMinCnt)
            nUserCount = nMinCnt
        end 
    else 
        nUserCount = 0 
        nAndroidCnt = 0 
        sLog = string.format("沒有牌桌")
    end  
    local nPlayerCnt =  nUserCount + nAndroidCnt
    local sStr=string.format(" %d_%d_%d ",nGroupId,nGameId,nRoomId)
    tBase.Log("_GetBlockPeopleSum %s %s nPlayerCnt:%d= %d + %d ",sStr,sLog,nPlayerCnt,nAndroidCnt,nUserCount) 	
    return nPlayerCnt 
end

local function _GetNotTable_CenterId(nBlockChian) 
    local arrServerInfo =  PublicRedis._HandleServerInfo(1) 
    local nMachineID = 0
    local nCenterType = 126
    if nBlockChian ~= 2 then   --非区块链服 
        nMachineID = 1
    end 
    -- tBase.Log("_GetNotTable_CenterId  arrServerInfo:  %s ",cjson.encode(arrServerInfo))
    local nCenterId = nil  
    local arrServerId = {}
    for nServerId, tInfo in pairs(arrServerInfo) do
        if tInfo.nStype == nCenterType and tInfo.nMachineID == nMachineID and tInfo.nState ~= 2 then 
            table.insert(arrServerId,nServerId)              
        end 
    end
    -- 过滤维护
    tBase.Log("_GetNotTable_CenterId  arrServerId: %s ",cjson.encode(arrServerId))
    nCenterId = arrServerId[1] or -1

    -- 找不到就指定
    if not nCenterId then 
        for nServerId, tInfo in pairs(arrServerInfo) do
            if tInfo.nStype == nCenterType and tInfo.nMachineID ~= nMachineID then 
                nCenterId = nServerId
                break 
            end 
        end
    end 
    return nCenterId
end

--区块链列表信息请求 请求
function GameLogic.BlockChianListInfoReq(sClientID, Data, len)
    local tData =LobbyParse(Data, len,"BlockChianListInfoReq")
    assert(tData~=nil,"BlockChianListInfoReq Parser Fail")
    local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
       tBase.Log("_BlockChianListInfoReq   Not Logon,sClientID_"..(sClientID or 'nil'))
       return false
    end 
    local nBlockChian = tData.nBlockChian or 1 -- 桌型: 1区块链、2固定桌、自己源桌 
    local sLog = "区块链"
    if nBlockChian== 2 then 
        sLog = "非区块链"
    end 
    local nGroupId =UsersGroupId(nUserId)
    local arrTableId = RedisCahche.GetLiveTableList(nGroupId,2,tData.nGameId,nBlockChian)  -- 获取区块链牌桌 
    local nRoomId = 100 
    if nBlockChian == 2 then nRoomId = 2 end 
    local nPlayerCnt =  GameLogic._GetBlockPeopleSum(nGroupId,tData.nGameId,nRoomId,#arrTableId)     
    if #arrTableId == 0 then   -- 需要指定服 
        local nCenterId = _GetNotTable_CenterId(nBlockChian) 
        arrTableId[1] = string.format("%d#..",nCenterId)
        sLog= sLog.." 无牌桌,指定中心服_"..nCenterId  
    end 
    tBase.Log("_BlockChianListInfoReq %s %d =【 %d= %d = %d    %d=%s "
    ,sLog,nUserId,nGroupId,tData.nGameId,nPlayerCnt,#arrTableId,cjson.encode(arrTableId)) 

    local BlockChianListInfoRep ={}
    BlockChianListInfoRep.nPeople = nPlayerCnt  
    BlockChianListInfoRep.nTableSum = #arrTableId or 0 
    BlockChianListInfoRep.sTableId = arrTableId[1] or ""
    LobbySendToUser(nUserId,"BlockChianListInfoRep",BlockChianListInfoRep) 
end

---------------------------------------------------------------------------
--[[
-- 请求获取充值地址URL
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function GameLogic.AccountPayURLReq(sClientID, Data, len)
    tBase.Log("AccountPayURLReq,sClientID_"..(sClientID or 'nil'))

    -- 解析
    local reqName = "AccountPayURLReq"
    local tData =LobbyParse(Data, len, reqName)
    assert(tData~=nil,"reqName Parser Fail")

    local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
       tBase.Log("AccountPayURLRsp  Not Logon,sClientID_"..(sClientID or 'nil'))
       return false
    end 

    local tUserInfo = tPubUserApi.GetAllUserInfo(nUserId)
    if not tUserInfo then
        tBase.Log("Err happen ,UsersGroupId =>GetAllUserInfo fail,nUserId_%d",nUserId)
        return -1
    end  

    tBase.Log("AccountPayURLReq,tUserInfo.sAddress_"..(tUserInfo.sAddress or 'nil'))
    if tUserInfo.sAddress ~= nil and tUserInfo.sAddress ~= "" then
        -- 充值成功，通知玩家修改界面数据
        local AccountPayURLRsp ={}
        AccountPayURLRsp.nCode = 0
        AccountPayURLRsp.strPayURL = tUserInfo.sAddress

        --
        -- 返回给用户请求地址信息
        if not AccountPayURLRsp.arrAddressList then
            AccountPayURLRsp.arrAddressList = {}
        end

        local addressInfo = {}
        addressInfo.strMainNet = "TRON-TRC20"
        addressInfo.strContractAddres = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        addressInfo.nMinTopup = 1
        addressInfo.nInputCompileTime = 1
        addressInfo.nOutputCompileTime = 1
        table.insert(AccountPayURLRsp.arrAddressList, addressInfo)

        tBase.Log("获取地址信息成功！")
        LobbySendToUser(nUserId, "AccountPayURLRsp", AccountPayURLRsp) 

        

        ------------ 
        -- TODO:临时测试用
        -- local reqData = {}
        -- reqData.sFrom = "1"
        -- reqData.sTo = tUserInfo.sAddress
        -- reqData.sAmount = "1.1"
        -- reqData.sTxHash = "test_hash"
        -- reqData.sContract = "test_count_pass"

        -- local packet = DbProtoEncode("PayUpdatePayInfoReq", reqData)
        -- tBase.PostDatasByType(tname.db, 0, 0, packet:GetData(), packet:GetSize())
        -- tBase.Log("开始更新订单")

        -- local nUserId = nUserId
        -- local AccountPayInfoRsp ={}
        -- AccountPayInfoRsp.nCode = 0
        -- AccountPayInfoRsp.fAmount = 1
        -- AccountPayInfoRsp.strRemark = ""
        -- LobbySendToUser(nUserId, "AccountPayInfoRsp", AccountPayInfoRsp) 
        -- tBase.Log("更新充值信息成功！")

        -- local msg = string.format("已成功提取 <color=#00FF86>%.2f USDT</color>,请核对;", tData.fAmount)
        -- tMsgHandle.WriteSystemNoticeNotic(nUserId, 1, msg, 21)
        -- tPubUserApi.Send_User_Notice(nUserId, 1, msg)
        -----------------------------------
        
        -- 此处返回
        return
    end

    -- 根据userid读取用户的充值地址
    local reqData = {
        nUserID = nUserId,
    }

    local packet = DbProtoEncode("PayGetPayAddressReq", reqData)
    tBase.PostDatasByType(tname.db, 0, nUserId, packet:GetData(), packet:GetSize())
end


--[[
-- 注册请求付款的消息函数，从kafka收到返回结果消息
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function GameLogic.CallAccountPayInfoReq(transfer)
    -- 返回的订单数据
    -- transfer.tx_hash, transfer.from, transfer.to, transfer.amount, transfer.contract

    -- 充值成功，游戏服务器更新玩家数据
    if transfer ~= nil then
        local reqData = {}
        -- 根据userid读取用户的充值地址
        reqData.sFrom = transfer.from
        reqData.sTo = transfer.to
        reqData.sAmount = transfer.amount
        reqData.sTxHash = transfer.tx_hash
        reqData.sContract = transfer.contract

        local packet = DbProtoEncode("PayUpdatePayInfoReq", reqData)
        tBase.PostDatasByType(tname.db, 0, 0, packet:GetData(), packet:GetSize())
        tBase.Log("开始更新订单")

    else
        tBase.Log("transfer == nil。更新充值信息失败，请检查")
    end
end 

--[[
-- 接收客户端请求付款的消息函数
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function GameLogic.AccountPayInfoReq(sClientID, Data, len)
    tBase.Log("AccountPayURLRsp,sClientID_"..(sClientID or 'nil'))

    -- 解析
    local reqName = "AccountPayInfoReq"
    local tData = LobbyParse(Data, len, reqName)
    assert(tData~=nil,"reqName Parser Fail")

    local nUserId = tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
        tBase.Log("AccountPayURLRsp  Not Logon,sClientID_"..(sClientID or 'nil'))
        return false
    end 

    tBase.Log("tPay.registerOrderCb")


    -- 创建支付订单
    local currency = "usdt"
    local subject = "request pay"
    local channel = "poker_client"
    local ackData, err = tPay.create_payorder(nUserId, tData.fAmount, currency, subject, channel)
    if ackData == nil or ackData.code == nil or ackData.code ~= 0 then
        tBase.Log("tPay.create_payorder error, client_"..nUserId) 
        tBase.Log(err)
    else 
        -- 充值订单创建成功，写入到DB 
        local reqData = {}
        reqData.nUserID = ackData.uid
        reqData.sOrderID = ackData.order_id
        reqData.sAmount = ackData.amount
        reqData.sChannel = ackData.channel
        reqData.sCurrency = ackData.currency
        reqData.sTopup_url = ackData.topup_url
        reqData.sFee = ackData.fee
        reqData.nResult = ackData.status

        local packet = DbProtoEncode("PayInsertPayInfoReq", reqData)
        tBase.PostDatasByType(tname.db, 0, 0, packet:GetData(), packet:GetSize())

        -- 充值成功，通知玩家修改界面数据
        local nUserId = nUserId
        local AccountPayInfoRsp ={}
        AccountPayInfoRsp.nCode = ackData.status
        AccountPayInfoRsp.fAmount = ackData.amount
        AccountPayInfoRsp.strRemark = ackData.message
        LobbySendToUser(nUserId, "AccountPayInfoRsp", AccountPayInfoRsp) 
        tBase.Log("更新充值信息成功！")
    end
end


--[[
-- 接收客户端请求提现的消息函数
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
-- 在文件顶部添加以下变量和配置
local WITHDRAWAL_CONFIG = {
    MAX_CONCURRENT = 10,        -- 最大并发处理数
    RETRY_COUNT = 3,            -- 最大重试次数
    RETRY_DELAY = 5,            -- 重试间隔(秒)
    QUEUE_TIMEOUT = 300,        -- 队列中超时时间(秒)
    PROCESS_INTERVAL = 0.1      -- 处理间隔(秒)
}

-- 提现处理状态管理
local WithdrawalProcessor = {
    processingCount = 0,
    queue = {},
    processing = {},            -- 正在处理的请求
    completed = {},             -- 已完成的请求(用于幂等性检查)
    failed = {},                -- 失败的请求
    lastProcessTime = 0
}

-- 初始化处理器
function WithdrawalProcessor:init()
    -- 定期清理过期数据
    self:cleanupExpired()
    
    -- 如果有需要处理的队列项，定期处理
    if #self.queue > 0 or next(self.failed) then
        local currentTime = os.time()
        if currentTime - self.lastProcessTime >= WITHDRAWAL_CONFIG.PROCESS_INTERVAL then
            tBase.Log("1. star to manage withdraw info")
            self:processQueue()
            self.lastProcessTime = currentTime
        end
    end
end

-- 清理过期数据
function WithdrawalProcessor:cleanupExpired()
    local currentTime = os.time()
    
    -- 清理已完成的请求记录(保留1小时)
    for orderId, timestamp in pairs(self.completed) do
        if currentTime - timestamp > 3600 then
            self.completed[orderId] = nil
        end
    end
    
    -- 清理失败的请求记录(保留24小时)
    for orderId, record in pairs(self.failed) do
        if currentTime - record.timestamp > 86400 then
            self.failed[orderId] = nil
        end
    end
end

-- 检查请求是否已处理(幂等性检查)
function WithdrawalProcessor:isProcessed(orderId)
    return self.completed[orderId] ~= nil
end

-- 标记请求为已处理
function WithdrawalProcessor:markAsCompleted(orderId)
    self.completed[orderId] = os.time()
    self.processing[orderId] = nil
    self.processingCount = self.processingCount - 1
end

-- 标记请求为失败
function WithdrawalProcessor:markAsFailed(orderId, requestData, errorMsg)
    if not self.failed[orderId] then
        self.failed[orderId] = {
            count = 0,
            requestData = requestData,
            errors = {},
            timestamp = os.time()
        }
    end
    
    self.failed[orderId].count = self.failed[orderId].count + 1
    table.insert(self.failed[orderId].errors, {
        time = os.time(),
        message = errorMsg
    })
    
    self.processing[orderId] = nil
    self.processingCount = self.processingCount - 1
end

-- 重试失败的请求
function WithdrawalProcessor:retryFailedRequests()
    local currentTime = os.time()
    
    for orderId, record in pairs(self.failed) do
        -- 检查是否达到最大重试次数
        if record.count < WITHDRAWAL_CONFIG.RETRY_COUNT then
            -- 检查是否到了重试时间
            local lastError = record.errors[#record.errors]
            if currentTime - lastError.time >= WITHDRAWAL_CONFIG.RETRY_DELAY then
                tBase.Log("WithdrawalProcessor: retrying failed request orderId=%s, attempt=%d", 
                         orderId, record.count + 1)
                self:enqueue(record.requestData, true)  -- 重新入队
                self.failed[orderId] = nil  -- 移除旧记录
            end
        else
            -- 达到最大重试次数，发送错误通知
            tBase.Log("WithdrawalProcessor: max retries reached for orderId=%s", orderId)
            local requestData = record.requestData
            local AccountWithdrawalRsp = {}
            AccountWithdrawalRsp.nCode = 1
            AccountWithdrawalRsp.fAmount = 1
            AccountWithdrawalRsp.strRemark = "系统繁忙，请稍后重试"
            LobbySendToUser(requestData.requestData.nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp)
        end
    end
end

-- 将请求加入队列
function WithdrawalProcessor:enqueue(requestData, isRetry)
    -- 生成唯一订单ID(用于幂等性检查)
    local orderId = string.format("%d_%s_%d", 
                                requestData.nUserId, 
                                requestData.strURL or "", 
                                os.time())
    local new_requestData = {}
    new_requestData.requestData = requestData
    if not isRetry then
        new_requestData.orderId = orderId
    end
    
    -- 检查是否已在队列中
    for i, item in ipairs(self.queue) do
        if item.orderId == orderId then
            tBase.Log("WithdrawalProcessor: duplicate request ignored orderId=%s", orderId)
            return false
        end
    end
    
    table.insert(self.queue, {
        orderId = orderId,
        requestData = new_requestData,
        timestamp = os.time(),
        isRetry = isRetry or false
    })
    
    tBase.Log("WithdrawalProcessor: request enqueued orderId=%s, queue size=%d", 
             orderId, #self.queue)
    
    return true
end

-- 处理队列中的请求
function WithdrawalProcessor:processQueue()
    -- 重试失败的请求
    self:retryFailedRequests()
    
    -- 检查并发限制
    if self.processingCount >= WITHDRAWAL_CONFIG.MAX_CONCURRENT then
        tBase.Log("error: max processed count >= WITHDRAWAL_CONFIG.MAX_CONCURRENT")
        return
    end
    
    local currentTime = os.time()
    local processedCount = 0
    local maxProcess = math.min(WITHDRAWAL_CONFIG.MAX_CONCURRENT - self.processingCount, #self.queue)
    
    -- 处理队列中的请求
    for i = #self.queue, 1, -1 do
        if processedCount >= maxProcess then
            break
        end
        
        local item = self.queue[i]
        
        -- 检查是否超时
        if currentTime - item.timestamp > WITHDRAWAL_CONFIG.QUEUE_TIMEOUT then
            tBase.Log("WithdrawalProcessor: request timeout orderId=%s", item.orderId)
            table.remove(self.queue, i)
            
            -- 通知用户
            local AccountWithdrawalRsp = {}
            AccountWithdrawalRsp.nCode = 1
            AccountWithdrawalRsp.fAmount = item.requestData.requestData.fAmount
            AccountWithdrawalRsp.strRemark = "请求超时，请重新提交"
            LobbySendToUser(item.requestData.requestData.nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp)
            goto continue
        end
        
        -- 检查是否已处理(幂等性)
        if self:isProcessed(item.orderId) then
            tBase.Log("WithdrawalProcessor: duplicate processed request ignored orderId=%s", item.orderId)
            table.remove(self.queue, i)
            goto continue
        end
        
        -- 开始处理
        self.processing[item.orderId] = item
        self.processingCount = self.processingCount + 1
        table.remove(self.queue, i)
        processedCount = processedCount + 1
        
        -- 异步处理提现请求
        self:processWithdrawal(item.requestData.requestData, item.orderId)
        
        ::continue::
    end
end

-- 实际处理提现请求
function WithdrawalProcessor:processWithdrawal(requestData, orderId)
    tBase.Log("enter processWithdrawal")
    -- 使用协程异步处理
    local co = coroutine.create(function()
        local nUserId = requestData.nUserId
        local AccountWithdrawalRsp = {}
        AccountWithdrawalRsp.nCode = 1
        AccountWithdrawalRsp.fAmount = requestData.fAmount
        AccountWithdrawalRsp.strRemark = "提现订单创建失败"
        
        local success = false
        local errorMsg = ""
        
        -- 错误处理包装器
        local function handleWithError(func, ...)
            local status, result = pcall(func, ...)
            if not status then
                errorMsg = tostring(result)
                tBase.Log("WithdrawalProcessor: error in %s - %s", debug.traceback(), errorMsg)
                return nil, errorMsg
            end
            return result, nil
        end
        
        -- 执行提现逻辑
        local function doWithdrawal()
            -- 是否校验用户密码
            local tUserInfo = PublicUserInfo.GetUserInfo(nUserId) or {}
            if PublicUserInfo.IsNeedCheckSafePassWard(nUserId) then
                if tUserInfo ~= nil and tUserInfo.sSafePassWard ~= requestData.strPwd then
                    tBase.Log("AccountWithdrawalReq NeedCheckSafePassWard requestData.strPwd:%s is wrong", requestData.strPwd)
                    AccountWithdrawalRsp.strRemark = "用户密码校验失败"
                    return false
                end
            end

            -- 扣减手续费后实际充值金额
            local realAmount = 0
            if tPay.cfg.withdrawCostType == 0 then
                realAmount = requestData.fAmount - tPay.cfg.WithdrawCostFixed
            else
                realAmount = requestData.fAmount - requestData.fAmount * tPay.cfg.WithdrawCostRate
            end

            -- 校验金额是否满足充值条件
            if 0 >= realAmount then
                tBase.Log("AccountWithdrawalReq requestData.fAmount:%s is less than WithdrawCostFixed", requestData.fAmount)
                AccountWithdrawalRsp.strRemark = "提现金额不足"
                return false
            end

            -- 创建提现订单
            local currency = "usdt"
            local remark = "poker_client"
            local ackData, err = tPay:create_withdraw(nUserId, realAmount, currency, requestData.strURL, remark)
            if ackData == nil then 
                tBase.Log("tPay.create_withdraw error for user %d", nUserId)
                tBase.Log(tostring(err))
                AccountWithdrawalRsp.strRemark = "创建提现订单失败"
                return false
            end

            -- 提现订单创建成功，写入到DB 
            local reqData = {}
            reqData.nUserID = nUserId
            reqData.sOrderID = orderId --ackData.order_id
            reqData.sToAddr = ackData.to_address
            reqData.sInputAmount = tostring(requestData.fAmount)
            reqData.sRealAmount = tostring(realAmount)
            reqData.sTxHash = ""
            reqData.sResult = 0 --0：插入提现订单  1：审核通过后，更新订单
            reqData.sRemark = "创建提现订单"

            -- 审核成功，请求提现
            local responReal, errReal = tPay:requestRealWichdraw(ackData)
            --local tmpJson = string.format(
            --        "{\"order_id\":\"WD202512052140138127\", \"amount\":\"%s\",\"timestamp\":1764942013,\"sign\":\"\",\"to_addr\":\"TUvhB3bVzbgsCNRTEoG6KfPgyiGwu9xVjC\",\"user_id\":\"14000304\",\"tx_hash\":\"0x123456789abcdef\",\"desc\":\"Withdrawal successful\"}",
            --        tostring(realAmount))
            --local responReal, errReal = cjson.decode(tmpJson), nil
            if errReal ~= nil or responReal == nil then
                tBase.Log(tostring(errReal))
                AccountWithdrawalRsp.strRemark = "提现处理失败"
                return false
            end

            -- 订单处理成功
            self:markAsCompleted(orderId)

            tBase.Log("提现完成，准备入库")
            tBase.LogT(responReal)
            
            -- 提现完成
            reqData.nUserID = nUserId
            reqData.sOrderID = responReal.order_id
            reqData.sToAddr = responReal.to_addr
            reqData.sInputAmount = tostring(requestData.fAmount)
            reqData.sRealAmount = responReal.amount
            reqData.sTxHash = responReal.tx_hash
            reqData.sResult = 1 --0：插入提现订单  1：审核通过后，更新订单
            reqData.sRemark = responReal.desc

            local packet = DbProtoEncode("PayInsertWithdrawInfoReq", reqData)
            tBase.PostDatasByType(tname.db, 0, 0, packet:GetData(), packet:GetSize())
            
            -- 成功处理
            AccountWithdrawalRsp.nCode = 0
            AccountWithdrawalRsp.fAmount = requestData.fAmount
            AccountWithdrawalRsp.strRemark = ""
            return true
        end
        
        -- 执行提现处理
        success, errorMsg = handleWithError(doWithdrawal)
        
        if success then
            -- 通知用户
            LobbySendToUser(nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp)
            
            -- 发送系统消息
            local msg = string.format("已成功提取 <color=#00FF86>%.2f USDT</color>,请核对;", requestData.fAmount)
            tMsgHandle.WriteSystemNoticeNotic(nUserId, 1, msg, 22)
            tPubUserApi.Send_User_Notice(nUserId, 2, msg)
            
            tBase.Log("WithdrawalProcessor: withdrawal successful orderId=%s, userId=%d", orderId, nUserId)
        else
            -- 处理失败
            self:markAsFailed(orderId, requestData, errorMsg or "未知错误")
            
            -- 通知用户
            AccountWithdrawalRsp.strRemark = "系统错误"
            LobbySendToUser(nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp)
            
            tBase.Log("WithdrawalProcessor: withdrawal failed orderId=%s, userId=%d, error=%s", 
                     orderId, nUserId, errorMsg or "Unknown error")
        end
    end)
    
    -- 启动协程
    local status, err = coroutine.resume(co)
    if not status then
        tBase.Log("WithdrawalProcessor: coroutine error - %s", tostring(err))
        self:markAsFailed(orderId, requestData, "协程执行错误: " .. tostring(err))
    end

    tBase.Log("leave processWithdrawal")
end

function GameLogic.initWithdraw()
    GameLogic.UpdateWithdrawalProcessor()
end

-- 在适当的地方(如主循环)定期调用处理器
function GameLogic.UpdateWithdrawalProcessor()
    tBase.Log("--enter UpdateWithdrawalProcessor")
    if WithdrawalProcessor then
        tBase.Log("--enter WithdrawalProcessor:init()")
        WithdrawalProcessor:init()
    end
    tBase.Log("--leave UpdateWithdrawalProcessor")
end

function GameLogic.AccountWithdrawalReqEx(sClientID, Data, len)
    tBase.Log("AccountWithdrawalReq sClientID_"..(sClientID or 'nil'))

    -- 解析
    local reqName = "AccountWithdrawalReq"
    local tData = LobbyParse(Data, len, reqName)
    assert(tData~=nil,"reqName Parser Fail")

    local nUserId = tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
        tBase.Log("AccountWithdrawalReq Not Logon, sClientID_"..(sClientID or 'nil'))
        return false
    end 

    -- 检查系统是否准备好处理提现请求
    if not WithdrawalProcessor then
        tBase.Log("WithdrawalProcessor not initialized")
        local AccountWithdrawalRsp = {}
        AccountWithdrawalRsp.nCode = 0
        AccountWithdrawalRsp.fAmount = tData.fAmount
        AccountWithdrawalRsp.strRemark = "系统初始化中，请稍后重试"
        LobbySendToUser(nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp)
        return
    end

    -- 将请求加入处理队列
    local success = WithdrawalProcessor:enqueue(tData)
    if not success then
        local AccountWithdrawalRsp = {}
        AccountWithdrawalRsp.nCode = 0
        AccountWithdrawalRsp.fAmount = tData.fAmount
        AccountWithdrawalRsp.strRemark = "请求处理中，请勿重复提交"
        LobbySendToUser(nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp)
        return
    end

    -- 通知用户请求已提交
    local AccountWithdrawalRsp = {}
    AccountWithdrawalRsp.nCode = 0  -- 2表示处理中
    AccountWithdrawalRsp.fAmount = tData.fAmount
    AccountWithdrawalRsp.strRemark = "提现请求已提交，正在处理中"
    LobbySendToUser(nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp)
    
    tBase.Log("AccountWithdrawalReq queued for user %d, amount=%.2f", nUserId, tData.fAmount or 0)
end


--[[
-- 接收客户端请求提现的消息函数
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
-- 返回客户端告知提现结果
function GameLogic.NoticeUserWichdrawResult(nUserId, nCode, fAmount, strRemark)
    local AccountWithdrawalRsp ={}
    AccountWithdrawalRsp.nCode = nCode 
    AccountWithdrawalRsp.fAmount = fAmount
    AccountWithdrawalRsp.strRemark = strRemark
    LobbySendToUser(nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp) 
end

-- 返回系统通知提现结果
function GameLogic.NoticeSystemInfo(nUserId, msg)
    tMsgHandle.WriteSystemNoticeNotic(nUserId, 1, msg, 22)
    tPubUserApi.Send_User_Notice(nUserId, 2, msg)
end

-- 通知DB提现信息
function GameLogic.NoticeDBWithdrawinfo(nUserId, order_id, to_address, fAmount, realAmount, txHash, sResult, sRemark)
    local reqData = {}
    reqData.nUserID = nUserId
    reqData.sOrderID = order_id
    reqData.sToAddr = to_address
    reqData.sInputAmount = tostring(fAmount)
    reqData.sRealAmount = tostring(realAmount)
    reqData.sTxHash = txHash
    reqData.sResult = sResult
    reqData.sRemark = sRemark

    local packet = DbProtoEncode("PayInsertWithdrawInfoReq", reqData)
    tBase.PostDatasByType(tname.db, 0, 0, packet:GetData(), packet:GetSize())
end

-- AccountWithdrawalReq 函数
function GameLogic.AccountWithdrawalReq(sClientID, Data, len)
    tBase.Log("AccountWithdrawalReq  sClientID_"..(sClientID or 'nil'))

    -- 解析
    local reqName = "AccountWithdrawalReq"
    local tData = LobbyParse(Data, len, reqName)
    assert(tData~=nil,"reqName Parser Fail")

    local nUserId = tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
        tBase.Log("AccountPayURLRsp  Not Logon,sClientID_"..(sClientID or 'nil'))
        return false
    end 

    -- 使用协程实现异步处理
    local co = coroutine.create(function()
        -- 是否校验用户密码
        local tUserInfo = PublicUserInfo.GetUserInfo(nUserId) or {}
        if PublicUserInfo.IsNeedCheckSafePassWard(nUserId) then
            if tUserInfo ~= nil and tUserInfo.sSafePassWard ~= tData.strPwd then
                tBase.Log("AccountWithdrawalReq NeedCheckSafePassWard tData.strPwd:%s is wrong", tData.strPwd)

                GameLogic.NoticeUserWichdrawResult(nUserId, 1, 0, "用户密码校验失败")
                GameLogic.NoticeSystemInfo(nUserId, "用户密码校验失败")
                return
            end
        end
        if tUserInfo.isBan then
            tBase.Log("AccountWithdrawalReq isBan nUserId:%s", nUserId)
            GameLogic.NoticeUserWichdrawResult(nUserId, 1, 0, "被禁止提现")
            return
        end

        -- 判断用户提现金额是否充足
        local nLockGold
        local err
        nLockGold, err = tFrozen:getFrozen(nUserId)
        if err then
            tBase.Log("AccountWithdrawalReq getFrozen err:%s nUserId:%s", err, nUserId)
            GameLogic.NoticeUserWichdrawResult(nUserId, 1, 0, "获取锁定金币失败")
            GameLogic.NoticeSystemInfo(nUserId, "获取锁定金币失败")
            return
        end
        
        local tUserBaseInfo = PublicUserInfo.GetUserBasic(nUserId) or {}
        local nUnLockGold = tUserBaseInfo.nGold - tApi.Ceil_n(nLockGold, 1)  -- 锁定金币返回的为乘100后的值

        if nUnLockGold < tData.fAmount then 
            tBase.Log("AccountWithdrawalReq  tData.fAmount:%s is less than WithdrawCostFixed", tData.fAmount)
            GameLogic.NoticeUserWichdrawResult(nUserId, 1, 0, "提现金额不足")
            GameLogic.NoticeSystemInfo(nUserId, "提现金额不足")
        end

        -- 扣减手续费后实际充值金额
        local realAmount = 0
        if tPay.cfg.withdrawCostType == 0 then
            realAmount = tData.fAmount - tPay.cfg.WithdrawCostFixed
        else
            realAmount = tData.fAmount - tData.fAmount * tPay.cfg.WithdrawCostRate
        end

        -- 校验金额是否满足充值条件
        if 1 > realAmount then
            tBase.Log("AccountWithdrawalReq  tData.fAmount:%s is less than WithdrawCostFixed", tData.fAmount)
            GameLogic.NoticeUserWichdrawResult(nUserId, 1, 0, "提现金额不足")
            GameLogic.NoticeSystemInfo(nUserId, "提现金额不足")
            return
        end

        -- 与自身携带量比较
        local unlockGold = PublicUserInfo.Get_User_UnLockGold(nUserId)
        if unlockGold < realAmount then
            tBase.Log("AccountWithdrawalReq  tData.fAmount:%s is less than WithdrawCostFixed", tData.fAmount)
            GameLogic.NoticeUserWichdrawResult(nUserId, 1, 0, "提现金额大于自身携带额，提现失败")
            GameLogic.NoticeSystemInfo(nUserId, "提现金额大于自身携带额，提现失败")
            return
        end


        -- 创建提现订单
        local currency = "usdt"
        local remark = "poker_client"
        local ackData, err = tPay:create_withdraw(nUserId, realAmount, currency, tData.strURL, remark)
        if ackData == nil then 
            tBase.Log("tPay.create_withdraw error:  sClientID_"..(sClientID or 'nil'))
            tBase.Log(err)

            GameLogic.NoticeUserWichdrawResult(nUserId, 1, 0, "创建提现订单失败")
            GameLogic.NoticeSystemInfo(nUserId, "创建提现订单失败")
        else
            -- 请求审核提现订单
            -- local resCheck, errCheck = tPay:requestCheckWitchdraw(ackData)
            -- if errCheck ~= nil or resCheck == nil or resCheck.data == nil then
            --     tBase.Log(errCheck)
            --     tBase.Log("errCheck ~= nil or resCheck == nil or resCheck.data == nil")

            --     AccountWithdrawalRsp.strRemark = "审核提现订单失败"
            --     LobbySendToUser(nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp) 
            --     return false
            -- end

            -- resCheck.code = 0:自动审核 1：人工审核
            --if resCheck.code == 0 then
            if true then
                -- 审核成功，请求提现
                local responReal, errReal = tPay:requestRealWichdraw(ackData)
                --local tmpJson = string.format(
                --    "{\"order_id\":\"WD202512052140138127\", \"amount\":\"%s\",\"timestamp\":1764942013,\"sign\":\"\",\"to_addr\":\"TUvhB3bVzbgsCNRTEoG6KfPgyiGwu9xVjC\",\"user_id\":\"14000304\",\"tx_hash\":\"0x123456789abcdef\",\"desc\":\"Withdrawal successful\"}",
                --    tostring(realAmount))
                --local responReal, errReal = cjson.decode(tmpJson), nil
                if errReal ~= nil or responReal == nil then
                    tBase.Log(errReal)
                    tBase.Log("errReal ~= nil or responReal == nil or responReal.data == nil")

                    local AccountWithdrawalRsp ={}
                    AccountWithdrawalRsp.strRemark = errReal
                    LobbySendToUser(nUserId, "AccountWithdrawalRsp", AccountWithdrawalRsp) 
                    return false
                end

                tBase.Log("提现完成，准备入库")
                tBase.LogT(responReal)
         
                -- 提现完成
                GameLogic.NoticeDBWithdrawinfo(nUserId, responReal.order_id, responReal.to_addr, tData.fAmount, realAmount, responReal.tx_hash, 0, responReal.desc)
            else
                GameLogic.NoticeDBWithdrawinfo(nUserId, ackData.order_id, ackData.to_address, tData.fAmount, realAmount, "", 1, "提现提现订单审核失败")
            end

            -- 通知用户2076
            GameLogic.NoticeUserWichdrawResult(nUserId, 0, tData.fAmount, "")
           
            -- 发送系统消息
            local msg = string.format("已成功提取 <color=#00FF86>%.2f USDT</color>,请核对;", tData.fAmount)
            GameLogic.NoticeSystemInfo(nUserId, msg)
        end
    end)

    -- 启动协程
    tBase.Log("******************* 111")
    local status, err = coroutine.resume(co)
    if not status then
        tBase.Log("AccountWithdrawalReq coroutine error: %s", err)
        GameLogic.NoticeUserWichdrawResult(nUserId, 1, tData.fAmount, "提现失败，请确认提现信息")
    end
end

--[[
-- 接收客户端请求提现的消息函数
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function GameLogic.AccountWithdrawalViewReq(sClientID, Data, len)
    -- 解析
    tBase.Log("AccountWithdrawalViewReq")
    local reqName = "AccountWithdrawalViewReq"
    local tData =LobbyParse(Data, len, reqName)
    assert(tData~=nil,"reqName Parser Fail")

    local nUserId = tData.nUserId
    if not nUserId then
        tBase.Log("AccountWithdrawalViewReq  Not Logon,sClientID_"..(sClientID or 'nil'))
        return false
    end 

    -- 返回给用户请求地址信息
    local AccountWithdrawalViewRsp ={}
    if not AccountWithdrawalViewRsp.arrWithdrawList then
        AccountWithdrawalViewRsp.arrWithdrawList = {}
    end

    local arrWithdrawView = {}
    arrWithdrawView.strMainNet = "TRON-TRC20"
    arrWithdrawView.nMinTopupMoney = 100 ----客户端除以100是最小值
    arrWithdrawView.strTime = "1-10分钟"
    if tPay.cfg.withdrawCostType == 0 then
        arrWithdrawView.strRate = tostring(tPay.cfg.WithdrawCostFixed)
    else
        arrWithdrawView.strRate = tostring(tPay.cfg.WithdrawCostRate)
    end
    table.insert(AccountWithdrawalViewRsp.arrWithdrawList, arrWithdrawView)

    tBase.Log("AccountWithdrawalViewRsp")
    LobbySendToUser(nUserId, "AccountWithdrawalViewRsp", AccountWithdrawalViewRsp) 
end




------------------------------------------------------------------------
--[[
-- 插入充值地址信息
-- sClientID：用户ID
-- Data：响应数据
-- len：数据长度
]] 
function GameLogic.OnDBInserClientAddRsp(sReturnKey, Data, len)
    local strReq = "InsertClientAddressRsp"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error InsertClientAddressRsp strReq:"..strReq) 
        assert(false,"Err happen ,Parse error InsertClientAddressRsp strReq:"..strReq)
        return
    end
    tBase.Log("InsertClientAddressRsp")

 
end

--[[
-- 更新充值地址
-- sClientID：用户ID
-- Data：响应数据
-- len：数据长度
]] 
function GameLogic.OnDBUpdateAddrRsp(sReturnKey, Data, len)
    local strReq = "UpdateUserPayInfoAddrArrRsp"
    local tData =DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq)
        return
    end
    tBase.Log("OnBankAccessDetailReq")


end

--[[
-- 插入付款信息
-- sClientID：用户ID
-- Data：响应数据
-- len：数据长度
]] 
function GameLogic.OnDBInsertPayInfoRsp(sReturnKey, Data, len)
    local strReq = "InsertPayInfoRsp"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq)
        return
    end
    tBase.Log("OnBankAccessDetailReq")


end

--[[
-- 更新付款信息
-- sClientID：用户ID
-- Data：响应数据
-- len：数据长度
]] 
function GameLogic.OnDBUpdatePayInfoRsp(sReturnKey, Data, len)
    tBase.Log("enter OnBankAccessDetailReq")

    local strReq = "PayUpdatePayInfoRsp"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq)
        assert(false,"Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq)
        return
    end

    local nUserId = math.floor(tonumber(tData.nUserId))
    local aMount = tonumber(tData.sAmount)
    local AccountPayInfoRsp ={}
    AccountPayInfoRsp.nCode = 0
    AccountPayInfoRsp.fAmount = aMount
    AccountPayInfoRsp.strRemark = ""
    LobbySendToUser(nUserId, "AccountPayInfoRsp", AccountPayInfoRsp)
    tBase.Log("AccountPayInfoRsp")
    -- 充值改名次数检测
    if aMount > 0 then
        local arrClubKey = tBase.GetSrcAllKey(tname.ClubSlave) or {}
        for _,sKey in ipairs(arrClubKey) do
            local tSend = ProtoMgr.PubProto_1_pb.REQ_Club_Recharge()
            tSend.nUserId = nUserId
            tSend.nAmount = aMount
            local s = tBase.GetSP().new(ProtoMgr.Sub_LobbyGame.SYSLOBBY_GAME, ProtoMgr.Sub_LobbyGame.SUB_CLUB_RECHARGE)
            s:AddString(tSend:SerializeToString())
            tBase.PostToServer(sKey, 1, s:GetData(), s:GetSize())
            tBase.Log("AccountPayInfoRsp send club:%s", sKey)
        end
    end
    LobbySendToUser(nUserId, "AccountPayInfoRsp", AccountPayInfoRsp)

    -- 发送系统消息
    local msg = string.format("已成功充值 <color=#00FF86>%s USDT</color>,请核对;", tData.sAmount)
    tMsgHandle.WriteSystemNoticeNotic(nUserId, 1, msg, 21)
    tBase.Log("leave AccountPayInfoRsp")
    tPubUserApi.Send_User_Notice(nUserId, 1, msg)
end

--[[
-- 插入提现信息
-- sClientID：用户ID
-- Data：响应数据
-- len：数据长度
]] 
function GameLogic.OnDBInsertWithdrawRsp(sReturnKey, Data, len)
    local strReq = "PayInsertWithdrawInfoRsp"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnBankAccessDetailReq strReq:"..strReq)
        return
    end
    tBase.Log("OnBankAccessDetailReq")

end


--[[
-- 获取支付地址
-- sClientID：用户ID
-- Data：响应数据
-- len：数据长度
]] 
function GameLogic.OnDBGetAddressRsp(sReturnKey, Data, len)
    local strReq = "PayGetPayAddressRsp"
    local tData = DbProtoParse(Data, len, strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error PayGetPayAddressRsp strReq:"..strReq) 
        assert(false,"Err happen ,Parse error PayGetPayAddressRsp strReq:"..strReq)
        return
    end
    tBase.Log("PayGetPayAddressRsp")

    local payAddress = tData.sPayAddres
     
    -- 返回给用户请求地址信息
    local AccountPayURLRsp = {}
    AccountPayURLRsp.nCode = 0  
    AccountPayURLRsp.strPayURL = payAddress 

    local addressInfo = {}
    addressInfo.strMainNet = "TRON-TRC20"
    addressInfo.strContractAddres = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    addressInfo.nMinTopup = 1
    addressInfo.nInputCompileTime = 1
    addressInfo.nOutputCompileTime = 1

    -- 创建一个新的地址信息项
    if not AccountPayURLRsp.arrAddressList then
        AccountPayURLRsp.arrAddressList = {}
    end
    table.insert(AccountPayURLRsp.arrAddressList, addressInfo)

    -- 更新redis的用户数据
    tPubUserApi.UpdateUserData({nUserID = tData.nUserID, sAddress = payAddress})
 
    -- 发送到客户端
    local nTmpUserID = tonumber(tData.nUserID)       
    local nUserID = math.floor(nTmpUserID) 
    LobbySendToUser(nUserID, "AccountPayURLRsp", AccountPayURLRsp) 


end


return GameLogic
