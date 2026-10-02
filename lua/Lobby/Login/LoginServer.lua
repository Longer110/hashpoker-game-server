package.path = require("./lua/Lobby/Head").path

local tBase    	 = require("base")           -- 基础功能接口
local tApi     	 = require("publicApi")      -- 共用功能接口
local tname      = require("typename")       -- 类弄定义接口
local tRdf     	 = require("redisdefine")    -- redis用到的kdy
local tBankLogic = require("BankLogic")      -- 银行逻辑
local tLocation  = require("LocationInfo")
local tPubUserApi= require("PublicUserInfo")    --玩家数据
local ProtoMgr   = require("ProtoManager")        -- 协议管理对象 
local tGameCfg   = require("GameListConfig")   -- 道具配置 
local cjson      = require("cjson") -- json 
local mlogger    = require("logger")
local tBase64 = require("BaseSink")    -- base 编码解码

LoginServer = 
{
	enumErrCode = 
	{	
		nSuccess    = 0,  	   --登录成功
		nNoKeys     = 1,      --验证key失败不存在
		nNoOnLine   = 2,      --玩家在线 踢下线（别的客户端）
		nGetDataError   = 3,  --获取数据失败		
	},
}

-- 玩家登录大厅服 请求
function LoginServer.LoginLobby(sClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 

    local Read = ProtoMgr.Lobby_pb.REQ_LogonLobby()
    Read:ParseFromString(ReadData:GetString())

    local tData ={}
    tData.nUserID = Read.nUserID   -- 用户ID
    if tData.nUserID == nil then 
        tBase.Log( " 登录大厅  获取数据失败    ReadData     ")
        return 0
    end 
    tData.sClientID = sClientID 
    local tUserInfo = tPubUserApi.GetAllUserInfo(tData.nUserID)
    if tUserInfo == nil then   
        tBase.Log( " 玩家  %d  登录大厅  获取数据失败    ",tData.nUserID)
        tData.nResult   = LoginServer.enumErrCode.nNoKeys
        LoginServer.Send_Logon_Lobby_Result(tData)
        return 1
    end 
    tData.nResult   = LoginServer.enumErrCode.nSuccess
    tData.nGold     = tonumber(tUserInfo.nGold )
    tData.sNickName = tUserInfo.sNickName
    tData.nSex      = tonumber(tUserInfo.nSex)
    tData.sFaceID   = tUserInfo.sFaceID

    tBase.Log( " nUserID         "..tData.nUserID)
    tBase.Log( " nGold           "..tData.nGold)
    tBase.Log( " sNickName       "..tData.sNickName)
    tBase.Log( " nSex            "..tData.nSex)
    tBase.Log( " sFaceID         "..tData.sFaceID)



    LoginServer.Send_Logon_Lobby_Result(tData)

    tBase.Log(" 玩家连接大厅成功  ")
    -- 推送一下列表
    LoginServer.Push_GameList(tData)
    -- 推送检测是否可以直接进入保险箱
    LoginServer.GetSafeBoxEnter(sClientID,tData.nUserID)
    -- tPubUserApi.ChangeUserTreasure({nUserID=tData.nUserID, nItemID=1, nDel=10000 ,nSourceType = 1})

    local nShopID  = tPubUserApi.Get_User_SHopId(tData.nUserID)
    local nGroupId  = tGameCfg.GetGroupId(nShopID)
    tBase.Log(" 玩家:  %d 连接大厅成功   nShopID:   %d  nGroupId:  %d ",tData.nUserID,nShopID,nGroupId)

    if 1 == 1 then return end   -- 暂时屏蔽 下面流程

    --解出当前使用网关服端口
    local tVal = tApi.Split(sClientID, ":")
    local nPort = tVal[2]

    local t = tLocation.GetUserLocation(tData.nUserID)
    --排除重连
    if not (next(t) ~= nil and t.sKey ~= "" and t.nServerId ~= nil) then
      tBase.Log("写入位置信息")
      tLocation.SetUserLocation({nUserId=tData.nUserID, nServerId=0, sKey="", 
        nGateWayPort=nPort, sLobbyKey=tBase.m_tKey})
    end
    tBase.Log(" 玩家连接大厅成功  ")
    return 
end

-- 返回成功结果
function LoginServer.Send_Logon_Lobby_Result(tData)
    local tSend = ProtoMgr.Lobby_pb.REP_LogonLobby()
    tSend.nResult  = tData.nResult
    if tData.nResult == 0 then 
        tSend.nUserID   = tData.nUserID
        tSend.nSex      = tData.nSex
        tSend.nGold     = tData.nGold
        tSend.sNickName = tData.sNickName
        tSend.sFaceID   = tData.sFaceID
    end 
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_LOGIN_LOBBY) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(tData.sClientID, nClient:GetData(), nClient:GetSize())   
    tBase.Log(" 玩家: %d  连接大厅 结果   nResult: %d  ",tData.nUserID,tData.nResult) 
    return 1 
end

-- 推送检测是否可以直接进入保险箱
function LoginServer.GetSafeBoxEnter(sClientID,nUserID) 
    local tSafeBoxInfo = tPubUserApi.GetUserIDUnLockTime(nUserID) 
    local del_Time = 0
    del_Time = tSafeBoxInfo.SafeBoxLockTime -  os.time()
    tBase.Log(" 玩家:"..nUserID..":保险箱检测:"..os.time().." 是否可以直接进入保险箱: %s",cjson.encode(tSafeBoxInfo).." del_Time:"..del_Time ) 
    -- 第二天
    if del_Time <= 0 then
        tBase.Log(" del_Time <= 0 需要验证保险箱密码 ") 
        local tSend = ProtoMgr.Lobby_pb.REP_SafeBox_ENTER()
        tSend.nType = tBankLogic.m_LockEnterType._Type0
        local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_PASSWORD_ENTER) 
        nClient:AddString(tSend:SerializeToString())    
        tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())
    -- 持续今天
    elseif del_Time > 0 then
        tBase.Log(" del_Time > 0 不需要验证保险箱密码 ") 
        local tSend = ProtoMgr.Lobby_pb.REP_SafeBox_ENTER()
        tSend.nType = tBankLogic.m_LockEnterType._Type1
        local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_PASSWORD_ENTER) 
        nClient:AddString(tSend:SerializeToString())    
        tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())
    end
end

-- 主动推送一下游戏列表
function LoginServer.Push_GameList(tData)

    local tUserInfo = tPubUserApi.GetAllUserInfo(tData.nUserID)
    if not tUserInfo then  tBase.Log(" 玩家: %d  用户离线 redis 没有数据     ",tData.nUserID) return end  

    -- 根据分店id 获取 群组配置
    local nShopID =  tonumber(tUserInfo.nShopID) or 1
    mlogger:info(string.format( "nShopID = %d",nShopID ))

    local tSend = ProtoMgr.Lobby_pb.REP_GameListCfg()

    local tGameList = tGameCfg.GetGrouplGameListCfg(nShopID)
    local nCount = 0
    if tGameList ~= nil then  
        for i,v in ipairs(tGameList) do   
            local arr =  tSend.GameList:add()        
            arr.Id         = v.Id     
            arr.GroupID  = v.GroupID   
            arr.SType      = v.SType  
            arr.GameName   = v.GameName   
            arr.GameOrder  = v.GameOrder 
            arr.GameStatus = v.GameStatus   
            arr.CGStatus   = v.CGStatus 
            arr.IconUrl    = v.IconUrl   
            arr.GamePath   = v.GamePath   
            arr.Version    = v.Version   
            arr.ZipFilePath     = v.ZipFilePath    
            arr.MD5FilePath     = v.MD5FilePath   

            nCount = nCount + 1 
            tBase.Log(" 玩家: %d ,Id: %d, SType: %d,Version: %s   主动推送一下游戏列表 "
            ,tData.nUserID,v.Id,v.GroupID,v.SType,v.Version  ) 
        end        
    else        
        tBase.Log(" 玩家: %d   的渠道: %s  没有获取到游戏列表配置    Error  ",tData.nUserID,tUserInfo.sChannel )         
    end 
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_PUSH_GAMELIST) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(tData.sClientID, nClient:GetData(), nClient:GetSize())   
    tBase.Log(" 玩家: %d  主动推送一下游戏列表    完成  nCount: %d   size: %d ",tData.nUserID,nCount,nClient:GetSize()) 
    return 1 
end

 -- 检查字符串特殊字符 
function CheckString_Conversion(value)
    local path = ""
    for i=1,#value do        
        local tmp = string.sub(value,i,i)--获取当前下标字符串
        --如果为'\\'则替换
        if tmp=='\\' or tmp=="'" or tmp=="%%"  or tmp== "%b“”"  or tmp== "/" or tmp=="“"  or tmp=="%%" or tmp== "”" or tmp== " " then
            return true 
        else
            path = path..tmp
        end
    end
    return false 
end

-- 修改 玩家信息
function LoginServer.Update_UserInfo(sClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 

    local Read = ProtoMgr.Lobby_pb.Update_UserInfo_Q()
    Read:ParseFromString(ReadData:GetString())

    local nUserID = Read.nUserID   -- 用户ID
    if nUserID == nil then
        tBase.Log( " 修改玩家信息  获取数据失败    nUserID  is nil      "..nUserID)
        return 0
    end
    local tUserInfo = tPubUserApi.GetAllUserInfo(nUserID)
    if tUserInfo == nil then
        tBase.Log( " 玩家  %d  修改玩家信息   获取数据失败    ",nUserID)
        return 1
    end

    local nType = Read.nType   --  1 性别， 2 头像 3 昵称  4 绑定账号 5 修改性别，头像，昵称 
    local sContent = Read.sContent
    local Accounts = Read.Accounts or ""
    local Password = Read.Password or ""
    local tData  = {}
    tData.nUserID = nUserID
    if nType == 1  then 
        if #sContent ~=  1 then 
            LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,-3,nType, sContent)
            tBase.Log( " 玩家  %d  性别    sContent:  %s    超出范围了   size: %d  ",nUserID,sContent,#sContent)
            return
        end
        tData.nSex = tonumber(sContent)
        tBase.Log( " 玩家  %d  修改玩家信息  nType： %d     sContent:  %s     ",nUserID,nType,sContent)
    elseif  nType == 2  then 
        tData.sFaceID = sContent 
        tBase.Log( " 玩家  %d  修改头像  nType： %d     sContent:  %s     ",nUserID,nType,sContent)
    elseif  nType == 3  then
        if #sContent > 16  or #sContent  == 0   then 
            LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,-3,nType, sContent)
            tBase.Log( " 玩家  %d  修改昵称  nType： %d     sContent:  %s    超出范围了  size: %d  ",nUserID,nType,sContent,#sContent)
            return 
        end 

        local sNickName  = tBase64.decode(sContent)
        if CheckString_Conversion(sNickName) then           
            LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,-4,nType, sNickName)
            -- sNickName = tApi.Special_String(sNickName)
            -- tBase.Log( " 玩家  %d  修改昵称  nType： %d     sContent:  %s    特殊字符处理    ",nUserID,nType,sNickName)
            return 
        end 
        -- sContent = tApi.Special_String(sContent)
        tData.sNickName = sContent
        tBase.Log( " 玩家  %d  修改玩家信息  nType： %d     sContent:  %s     ",nUserID,nType,sContent)
    elseif  nType == 4  then
        if #Accounts < 4 or #Accounts > 20  then LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,-5,nType, sContent) return end
        if #Password < 6 or #Password > 40 then LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,-6,nType, sContent) return end
        if not tApi.Check_AccountString(Accounts) then 
            tBase.Log( " 玩家  %d  修改玩家信息   账号只接受英文、数字和下划线  ",nUserID)
            LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,-8,nType, sContent) 
            return 
        end 

    elseif  nType == 5  then
        tBase.Log( " 玩家  %d  修改个人信息  nType： %d     sContent:  %s     ",nUserID,nType,sContent)
        local tUpdateInfo = tApi.string_split(sContent,"#")   --  sContent  "性别#头像#昵称"
        for k,v in pairs(tUpdateInfo) do
            tBase.Log( "  修改个人信息  ---------->  %d   %s ",k,v )         
        end
        tData.nSex = tUpdateInfo[1]
        if #tData.nSex  ~= 1 then 
            LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,-3,nType, sContent)
            tBase.Log( " 玩家  %d  性别    sContent:  %s    超出范围了   size: %d  ",nUserID,sContent,#tData.nSex)
            return             
        end 
        tData.sFaceID = tUpdateInfo[2]
        tData.sNickName = tUpdateInfo[3]    
        -- if #tData.sNickName > 16 then 
        --     LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,-3,nType, sContent)
        --     tBase.Log( " 玩家  %d  修改昵称  nType： %d     sContent:  %s    超出范围了  size: %d  ",nUserID,nType,sContent,#tData.sNickName)
        --     return 
        -- end 

        -- tBase.Log(" 修改个人信息  ---------->  sNickName   %s ",tData.sNickName)   
        -- local sNickName  = tBase64.decode(tData.sNickName)
        -- if CheckString_Conversion(sNickName) then           
        --     LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,-4,nType, sNickName)
        --     return 
        -- end 
        sContent = tData.nSex
        Accounts = tData.sFaceID
        Password = tData.sNickName
    end 
    tPubUserApi.UpdateUserData(tData)
    local tSend = ProtoMgr.PubProto_1_pb.RUQ_UpdateUserInfo()
    tSend.nClientID = sClientID 
    tSend.nUserID = nUserID 
    tSend.sSql = "Call User_Update_UserInfo("..nUserID..","..nType..",'"..sContent.."','"..Accounts.."','"..Password.."')" 
    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_UPDATE_USERINFO)
    s:AddString(tSend:SerializeToString())
    tBase.PostDatasByType(tname.db, 0, 0, s:GetData(), s:GetSize()) 
    tBase.Log( " 玩家  %d  修改玩家信息  nType： %d     sContent:  %s   请求数据库    ",nUserID,nType,sContent)
    return 
end

-- 修改个人信息 返回
function LoginServer.Send_Update_UserInfo_Result(sReturnKey, sData, nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()    

    local Read = ProtoMgr.PubProto_1_pb.RUQ_UpdateUserInfo()
    Read:ParseFromString(ReadData:GetString())
    local sClientID  = Read.nClientID
    local nUserID  = Read.nUserID
    local nResult  = Read.nResult
    local nType    = Read.nType
    local sContent  = Read.sContent

    LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,nResult,nType,sContent)

    return 1 
end


function LoginServer.UpdateUserInfo_Result_Error(sClientID,nUserID,nResult,nType,sContent)

    local tSend = ProtoMgr.Lobby_pb.Update_UserInfo_P()
    tSend.nResult = nResult 
    tSend.nType = nType 
    tSend.sContent = sContent  or "-1"
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.Main_CMD, ProtoMgr.LobbyPro.SUB_REP_UPDATE_USERINFO) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())   
    tBase.Log(" 玩家: %d  修改个人信息 返回 结果   nResult: %d  ",nUserID,nResult) 
end

-- 检查服务器key 是否存在
local function Check_ServerKey(sGameName,sServerKey)
    tBase.m_centerRedis.Mo:select(1)
    local AllKey = tBase.m_centerRedis.Mo:keys("*"..sGameName.."*")
    for k,sKey in pairs(AllKey) do
        tBase.Log("_Check_ServerKey  sKey_%s ",sKey)
        if sKey == sServerKey then
            return true
        end
    end
    return false
end


--web踢人
function LoginServer.KickUser(sClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID()

    local Read = ProtoMgr.Web_pb.REQ_Web_Kick_User()
    Read:ParseFromString(ReadData:GetString())
    local nUserId = Read.nUserId
    local nType = Read.nType

    local tUserInfo = tPubUserApi.GetAllUserInfo(nUserId)
    if tUserInfo == nil or tUserInfo["nGold"] == nil  then
        mlogger:error(string.format(" 后台通知踢人 UserId:  %d      Redis  没有用户数据   ", nUserId))
        return 1
    end

    mlogger:info(string.format("_KickUser  后台通知踢人 UserId:  %d    %d 【1 强制 2 正常踢出】 ", nUserId,nType))
    local  nGameId,nRoomId,sServerKey,sGameName  = PublicUserInfo.GetUserPlayingGame(nUserId)
    if sServerKey ~= nil then
        if Check_ServerKey(sGameName,sServerKey) then
            local tSend = ProtoMgr.PubProto_1_pb.REQ_Kick_User()
            tSend.nUserId = nUserId
            tSend.nType = nType  --暂时写6
            local s = tBase.GetSP().new(ProtoMgr.Sub_LobbyGame.SYSLOBBY_GAME, ProtoMgr.Sub_LobbyGame.SUB_GAME_KICK_USER)
            s:AddString(tSend:SerializeToString())
            tBase.PostToServer(sServerKey, 1, s:GetData(), s:GetSize())

            mlogger:info(string.format("_KickUser  踢用户_%d   游戏名: %s  通知游戏GameKey: %s  ",nUserId,sGameName,sServerKey))
        else
            mlogger:info(string.format("_KickUser  GameKey失效 退出处理  GameId_%d  UserId_%d  GameName_%s GameKey: %s  "
            ,nGameId,nUserId ,sGameName,sServerKey))

            PublicUserInfo.LeaveGame(nUserId,nGameId)
        end
    else
        if nGameId and  nGameId == 133 then
            local arrAllCenterKey = tBase.GetSrcAllKey(tname.pilotmslave) or {}
            for _,sKey in ipairs(arrAllCenterKey) do
                local tSend = ProtoMgr.PubProto_1_pb.REQ_Kick_User()
                tSend.nUserId = nUserId
                tSend.nType = nType
                local s = tBase.GetSP().new(ProtoMgr.Sub_LobbyGame.SYSLOBBY_GAME, ProtoMgr.Sub_LobbyGame.SUB_GAME_KICK_USER) 
                s:AddString(tSend:SerializeToString())
                tBase.PostToServer(sKey, 1, s:GetData(), s:GetSize())

                mlogger:info(string.format("_KickUser 2  踢用户_%d  通知游戏GameKey: %s  ",nUserId,sKey))
                break
            end
        elseif nGameId and  nGameId == 157 then
            local arrAllCenterKey = tBase.GetSrcAllKey(tname.FellTreeSlave) or {}
            for _,sKey in ipairs(arrAllCenterKey) do
                local tSend = ProtoMgr.PubProto_1_pb.REQ_Kick_User()
                tSend.nUserId = nUserId
                tSend.nType = nType
                local s = tBase.GetSP().new(ProtoMgr.Sub_LobbyGame.SYSLOBBY_GAME, ProtoMgr.Sub_LobbyGame.SUB_GAME_KICK_USER)
                s:AddString(tSend:SerializeToString())
                tBase.PostToServer(sKey, 1, s:GetData(), s:GetSize())

                mlogger:info(string.format("_KickUser 2  踢用户_%d  通知游戏GameKey: %s  ",nUserId,sKey))
                break
            end
        elseif nGameId and  nGameId == 159 then
            local arrAllCenterKey = tBase.GetSrcAllKey(tname.BasketballSlave) or {}
            for _,sKey in ipairs(arrAllCenterKey) do
                local tSend = ProtoMgr.PubProto_1_pb.REQ_Kick_User()
                tSend.nUserId = nUserId
                tSend.nType = nType
                local s = tBase.GetSP().new(ProtoMgr.Sub_LobbyGame.SYSLOBBY_GAME, ProtoMgr.Sub_LobbyGame.SUB_GAME_KICK_USER)
                s:AddString(tSend:SerializeToString())
                tBase.PostToServer(sKey, 1, s:GetData(), s:GetSize())

                mlogger:info(string.format("_KickUser 2  踢用户_%d  通知游戏GameKey: %s  ",nUserId,sKey))
                break
            end
        end
        PublicRedis.SetPilotKickUser(nUserId,1)  -- 强制踢人 完成
        PublicRedis.SetPilotKickUser(nUserId,5)  -- 2后过期
        mlogger:info(string.format(" 后台通知踢人 UserId:  %d   sServerKey is  null   不在游戏中    ", nUserId,nType))
    end
    if nType == 1 then
        local arrClubKey = tBase.GetSrcAllKey(tname.ClubSlave) or {}
        for _,sKey in ipairs(arrClubKey) do
            local tSend = ProtoMgr.PubProto_1_pb.REQ_Kick_User()
            tSend.nUserId = nUserId
            tSend.nType = nType
            local s = tBase.GetSP().new(ProtoMgr.Sub_LobbyGame.SYSLOBBY_GAME, ProtoMgr.Sub_LobbyGame.SUB_GAME_KICK_USER)
            s:AddString(tSend:SerializeToString())
            tBase.PostToServer(sKey, 1, s:GetData(), s:GetSize())
            mlogger:info(string.format("_KickUser 3  踢用户_%d  通知俱乐部服GameKey: %s  ",nUserId,sKey))
        end
    end
end





return LoginServer

