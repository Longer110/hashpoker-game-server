package.path                 = require("./lua/Logon_s/Head").path

local tBase                  = require("base")                  -- 基础功能接口
local api                    = require("publicApi")             -- 共用功能接口
local tname                  = require("typename")              -- 类弄定义接口
local ProtoMgr               = require("ProtoManager")          -- 协议管理对象
local cjson                  = require("cjson")
local tPubUserApi            = require("PublicUserInfo")        --玩家数据同步
local tPlatformChannelShopTb = require("PlatformChannelShopTb") -- 登录和逻辑
local tLocationInfo          = require("LocationInfo")
local tGameCfg               = require("GameConfig")            --  游戏匹配
local http                   = require("socket.http")
local mlogger                = require("logger")
local tApi                   = require("publicApi")
local tBase64                = require("BaseSink") -- base 编码解码
local tPubRds                = require("PublicRedis")
local tSCfg                  = require("SetingConfig")
local tMainVersion           = require("MainVersion")
local tBRRecord              = require("BroadCastRecordApp")
local tMoblieBinder          = require("MoblieBinder")
local Db_Proto1              = ProtoMgr.DbServer1_pb.Db_Proto1()
local LuaCrypto              = require("LuaCrypto") -- 加密库
local TgVerify               = require("TgVerify")

LogonLink                    = {}
local isTest                 = false
local RegistWay              = {}
RegistWay.Accout             = 1 --账号
RegistWay.Phone              = 5 --手机注册
RegistWay.Mail               = 6 --邮箱注册

local function convert_telegram_avatar_url(photo_url)
    if not photo_url or type(photo_url) ~= "string" then
        return nil
    end
    -- 提取 SVG 文件名（不含扩展名）
    local filename = photo_url:match("/([^/]+)%.svg$")
    if not filename then
        return photo_url -- 如果不是 SVG 格式，返回原链接
    end
    -- 转换为 PNG 格式
    local png_url = "https://t.me/i/userpic/320/" .. filename .. ".svg"
    return png_url
end

-- 用户请求区
function LogonLink.RequestData(ClientID, Data, len, clientIp)
    clientIp = clientIp or "未知ip"
    local ReadData = tBase.GetRP().new(Data, len)
    local SysID = ReadData:GetModuleID()
    local SubID = ReadData:GetMsgID()
    local tPubProto = ProtoMgr.LogonPro
    if SysID == tPubProto.LOGON_MAIN then
        if SubID == tPubProto.SUB_REQ_LOGON then
            tBase.Log("_RequestData  登陆" .. clientIp)
            LogonLink.OnLogon_Module(ClientID, Data, len, clientIp)
        elseif SubID == tPubProto.SUB_REQ_REGISTER then
            tBase.Log("_RequestData   注册 " .. clientIp)
            LogonLink.OnRegist_Module(ClientID, Data, len, clientIp)
        elseif SubID == tPubProto.SUB_REQ_LOGON_TENCENT then
            tBase.Log("_RequestData   微信登陆 ")
            LogonLink.WeiXinLogic(ClientID, Data, len, clientIp)
        else
            tBase.Log("_RequestData    SubID_%d  Error  ", SubID)
        end
    end
    return 0
end

--查询玩家当前游戏
function LogonLink.OnCurrentGameQuerryReq(ClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local SystemID = ReadData:GetModuleID()
    local NewsID = ReadData:GetMsgID()
    local CurrentGameQuerryReq = ProtoMgr.Logon_pb.CurrentGameQuerryReq() -- 协议
    CurrentGameQuerryReq:ParseFromString(ReadData:GetString())
    local nUserId = CurrentGameQuerryReq.nUserId
    local nCurrentGameId, nRoomId, sServerKey, sGameName, sTableId = tPubUserApi.GetUserPlayingGame(nUserId)
    local CurrentGameQuerryRsp = ProtoMgr.Logon_pb.CurrentGameQuerryRsp()
    CurrentGameQuerryRsp.nGameId = (nCurrentGameId or -1)
    if sTableId then
        CurrentGameQuerryRsp.sTableId = sTableId
    end
    tBase.Log("_OnCurrentGameQuerryReq nUserId:%d nCurrentGameId:%d sTableId:%s", nUserId, CurrentGameQuerryRsp.nGameId,
        (sTableId or 'nil'))
    local s = base.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.CurrentGameQuerryRsp_CMD)
    s:AddString(CurrentGameQuerryRsp:SerializeToString())
    tBase.PostToGateway(ClientID, s:GetData(), s:GetSize())
end

local function CallProceduerSql(sProceduerName, arrParameter)
    local str = "call " .. sProceduerName .. "("
    for dex, v in ipairs(arrParameter) do
        if type(v) == 'string' then
            str = str .. "'" .. v .. "'"
        else
            str = str .. v
        end
        if dex ~= #arrParameter then
            str = str .. ","
        end
    end
    return str .. ")"
end

-- 定义字符集合
local charset = {}
for c = 48, 57 do table.insert(charset, string.char(c)) end  -- 0-9
for c = 65, 90 do table.insert(charset, string.char(c)) end  -- A-Z
for c = 97, 122 do table.insert(charset, string.char(c)) end -- a-z

-- 随机字符串生成函数
function LogonLink.random_string(length)
    math.randomseed(os.time() + os.clock() * 1000000) -- 初始化随机种子
    local result = {}
    for i = 1, length do
        local index = math.random(1, #charset)
        result[i] = charset[index]
    end
    return table.concat(result)
end

-- 生成带前缀的唯一 ID
function LogonLink.generate_id(prefix, length)
    return prefix .. "_" .. LogonLink.random_string(length)
end

-- 登录账号
function LogonLink.OnLogon_Module(ClientID, Data, len, clientIp)
    local ReadData = tBase.GetRP().new(Data, len)
    local SystemID = ReadData:GetModuleID()
    local NewsID = ReadData:GetMsgID()
    local LogonR = ProtoMgr.Logon_pb.Ruq_Logon() -- 协议
    LogonR:ParseFromString(ReadData:GetString())
    tBase.Log("_OnLogon_Module  Accounts: %s   Password: %s  Models: %s ", LogonR.Accounts, LogonR.Password, LogonR.Models or "")

    local sTGUserName = ""
    local sTgUid = ""
    local nick = nil
    local avatar = "1"
    local Account_Type = LogonR.Type --账号类型
    -- https://t.me/i/userpic/320/WiX37DnYPcL9Jyn6whyNQahY6TMeAaMmf8QJ83xTCuEvWZpr4XbxkSc94qybdDnV.jpg
    --判断前缀是否为telegram:
    if string.sub(LogonR.Accounts, 1, 9) == "telegram:" then
        local telegramInitData = string.sub(LogonR.Accounts, 10) -- 去掉"telegram:"前缀
        tBase.Log("_OnLogon_Module  telegramInitData: %s", telegramInitData)
        -- 解析并验证telegramInitData
        local tUserData, err = LogonLink.ParseAndVerifyTelegramInitData(telegramInitData)
        if not tUserData then
            tBase.Log("OnLogon_Module 验证失败: %s", err or "未知错误")
            LogonLink.Logon_Return_Error_User(ClientID, 10)
            return
        end
        -- 获取telegramId
        local telegramId = tUserData.id
        if not telegramId then
            tBase.Log("_HandleTelegramLogin 缺少用户ID")
            LogonLink.Logon_Return_Error_User(ClientID, 10)
            return
        end
        tBase.Log("_HandleTelegramLogin 验证成功,用户ID: %s, 用户名: %s", telegramId, tUserData.username or "无用户名")
        -- 修改LogonR中的账号和密码，然后重新序列化
        LogonR.Accounts = "telegram_" .. telegramId
        nick = tUserData.first_name .. tUserData.last_name
        LogonR.Password = "telegram_pass_#22vK&l7o" .. telegramId
        LogonR.Password = LuaCrypto.encrypt_password(LogonR.Password, tSCfg.passSecret)
        sTgUid = telegramId
        sTGUserName = tUserData.username
        local url = convert_telegram_avatar_url(tUserData.photo_url)
        avatar = url and url or avatar
        Account_Type = 7
    end

    local sAccounts = LogonR.Accounts
    local sPassword = LogonR.Password

    --For Test
    if isTest then
        local phone = string.match(sAccounts, "phone(%d%d%d%d%d%d%d%d%d%d%d)")
        local mail = string.match(sAccounts, "mail(.*)")
        if phone then
            sAccounts = phone
            Account_Type = RegistWay.Phone
        end
        if mail then
            sAccounts = mail
            Account_Type = RegistWay.Mail
        end
    end

    if sAccounts == nil or sPassword == nil then
        local nError = 0
        if sAccounts == nil then
            tBase.Log("_OnLogon_Module  sAccounts is nil")
            nError = 10
        end
        if sPassword == nil then
            tBase.Log("_OnLogon_Module  sPassword  is nil")
            nError = 11
        end
        LogonLink.Logon_Return_Error_User(ClientID, nError)
        return
    end

    local SysVersion      = LogonR.SysVersion or ""   --手机版本
    local Logon_Models    = LogonR.Models             --手机机器码
    local Logon_sChannel  = LogonR.Channel            --登录渠道
    local sPlatform       = LogonR.sPlatform          --平台号
    local sVersions       = LogonR.sVersions          --版本号
    local sLocation       = LogonR.Location or "no"   --地点
    local sGps            = LogonR.sGps or ""         --GPS位置
    local sDeviceModel    = LogonR.sDeviceModel or "" --设备型号
    local sServerVersion  = tSCfg.sVersionFile or ""  --服务端版本

    -- local tIp = {}
    -- tIp = tBase.m_MyRedisData[1].redis:hgetall("UserAcceptInfo_" .. ClientID)
    local tIp             = {}
    tIp                   = tBase.m_MyRedisData[1].redis:hgetall("UserAcceptInfo_" .. ClientID)
    local LastLogonIP     = tIp.real_ip or "192.168.0.1"
    local LastLogonRealIP = tIp.real_ip or ""
    tBase.Log(
        "_OnLogon_Module  登录IP: %s RaelIp:%s sChannel: %s  sPlatform: %s nShopId:%d sDeviceModel: %s SysVersion: %s sGps: %s ",
        LastLogonIP, LastLogonRealIP, Logon_sChannel, sPlatform, LogonR.nShopId, sDeviceModel, SysVersion, sGps)

    local nTokenUserId = 0
    local sToken = LogonR.sToken
    local sNewToken = nil
    local nShopId = nil --游客登陆时有(如果游客账号不存在，则使用该shopid进行注册)
    if Account_Type == 0 then
        tBase.Log("_OnLogon_Module  游客登录  Account_Type: %d   Logon_Models:%s  ", Account_Type, Logon_Models)
        sAccounts = "Tourist_sAccounts_" .. sAccounts
        sPassword = "Tourist_sPassword_" .. sPassword
        nShopId = tPlatformChannelShopTb.GetShopId(sPlatform, Logon_sChannel, LogonR.nShopId)
    elseif Account_Type == 1 then
        tBase.Log("_OnLogon_Module  账号登录 Account_Type: %d ", Account_Type)
    elseif Account_Type == 3 then --令牌登陆
        tBase.Log("_OnLogon_Module  令牌登陆 sToken:%s", (sToken or 'nil'))
        nTokenUserId, sNewToken = tPubUserApi.GetUserIdByToken(sToken)
        tBase.Log("_OnLogon_Module nTokenUserId:%d sNewToken:%s", (nTokenUserId or -1), (sNewToken or "nil"))
        if nTokenUserId == nil or nTokenUserId <= 0 then
            LogonLink.Logon_Return_Error_User(ClientID, 12)
            return
        end
    end
    --GPS保留五位
    local isSuccee, tGps = pcall(cjson.decode, sGps)
    local sLongonPos = ""
    if isSuccee and tGps.nLongitude and tGps.nLatitude then
        tGps.nLongitude = api.Floor_n(tGps.nLongitude, 5)
        tGps.nLatitude = api.Floor_n(tGps.nLatitude, 5)
        sLongonPos = cjson.encode({ tGps.nLongitude, tGps.nLatitude })
    end
    nick = nick or sAccounts
    nick = nick:gsub("%s+", "")
    sTGUserName = tBase64.encode(sTGUserName) or sAccounts
    local arrParameter = {}
    arrParameter[1] = sAccounts
    arrParameter[2] = sPassword
    arrParameter[3] = Account_Type
    arrParameter[4] = nick                         --tBase64.encode(nick)
    arrParameter[5] = tostring(math.random(1, 10)) -- 1-10号头像直接随机取一个
    arrParameter[6] = 0
    arrParameter[7] = Logon_sChannel
    arrParameter[8] = LastLogonIP
    arrParameter[9] = sPlatform
    arrParameter[10] = sVersions
    arrParameter[11] = Logon_Models                                                         -- 邀请码
    arrParameter[12] = tPlatformChannelShopTb.GetShopId(sPlatform, Logon_sChannel, nShopId) --tonumber(Rdata.Channel) or 1
    arrParameter[13] = sTgUid
    arrParameter[14] = sDeviceModel
    arrParameter[15] = sTGUserName

    local pLogon = ProtoMgr.PubProto_pb.Ruq_Logon()
    pLogon.ClientID = ClientID
    pLogon.sSql = string.format(
        "call Logon_Accounts_new('%s','%s',%d,'%s','%s','%s','%s',%d,'%s','%s','%s','%s','%s','%s', '%s')",
        sAccounts, sPassword, Account_Type, Logon_sChannel, Logon_Models, LastLogonIP, sLocation, nTokenUserId,
        sLongonPos, sVersions, sServerVersion, sDeviceModel, SysVersion, LastLogonIP, sTGUserName)

    pLogon.sSql2 = CallProceduerSql("Regist_Accounts", arrParameter)

    pLogon.nAccountType = Account_Type
    if sNewToken then
        pLogon.sToken = sNewToken
    end
    if nShopId then
        pLogon.nShopId = nShopId
    end
    pLogon.sPlatform = sPlatform or ""
    pLogon.sChannel = Logon_sChannel or ""
    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_ACCOUNT_LOGON)
    s:AddString(pLogon:SerializeToString())
    tBase.PostDatasByType(tname.db, 0, 0, s:GetData(), s:GetSize())
    tBase.Log("_OnLogon_Module 登录 sSql: %s ", pLogon.sSql)
end

-- 注册账号
function LogonLink.OnRegist_Module(ClientID, Data, len, clientIp)
    local ReadData = tBase.GetRP().new(Data, len)
    local SystemID = ReadData:GetModuleID()
    local NewsID = ReadData:GetMsgID()
    local Rdata = ProtoMgr.Logon_pb.Ruq_Regist()
    Rdata:ParseFromString(ReadData:GetString())

    local sTGUserName = ""
    local sTgUid      = ""
    local nick        = nil
    Rdata.IP          = clientIp
    --判断前缀是否为telegram:
    if string.sub(Rdata.Accounts, 1, 9) == "telegram:" then
        -- 从Accounts中提取telegramInitData
        local telegramInitData = string.sub(Rdata.Accounts, 10) -- 去掉"telegram:"前缀
        -- 解析并验证telegramInitData
        local tUserData, err = LogonLink.ParseAndVerifyTelegramInitData(telegramInitData)
        if not tUserData then
            tBase.Log("OnRegist_Module 验证失败: %s", err or "未知错误")
            LogonLink.Regist_Return_Error_User(ClientID, 10)
            return
        end
        -- 获取telegramId
        local telegramId = tUserData.id
        if not telegramId then
            tBase.Log("OnRegist_Module 缺少用户ID")
            LogonLink.Regist_Return_Error_User(ClientID, 10)
            return
        end
        tBase.Log("OnRegist_Module 验证成功,用户ID: %s, 用户名: %s", telegramId, tUserData.username or "无用户名")
        -- 修改LogonR中的账号和密码，然后重新序列化
        Rdata.Accounts = "telegram_" .. telegramId
        nick = tUserData.first_name .. tUserData.last_name --tUserData.username
        Rdata.Password = "telegram_pass_#22vK&l7o" .. telegramId
        Rdata.Password = LuaCrypto.encrypt_password(Rdata.Password, tSCfg.passSecret)
        sTgUid = telegramId
        sTGUserName = tUserData.username
    end

    local nRegistWay = math.max(Rdata.nRegistWay or 1, 1) --5:手机, 6:邮箱, <=1或nil:账号
    local sAccounts = Rdata.Accounts                      --账号或手机或邮箱 ,视nRegistWay字段而定
    tBase.Log("  Accounts:  %s ,nRegistWay:%d", sAccounts or "", nRegistWay)

    --For Test
    local isNotCheckVeriCode = false
    if isTest then
        local phone = string.match(sAccounts, "phone(%d%d%d%d%d%d%d%d%d%d%d)")
        local mail = string.match(sAccounts, "mail(.*)")
        if phone then
            sAccounts = phone
            nRegistWay = RegistWay.Phone
            isNotCheckVeriCode = true
        end
        if mail then
            sAccounts = mail
            nRegistWay = RegistWay.Mail
            isNotCheckVeriCode = true
        end
    end

    local nError = 0
    if nRegistWay == RegistWay.Accout then
        if sAccounts == nil then
            tBase.Log("_OnRegist_Module     Accounts  is nil   ")
            nError = 10
        elseif #sAccounts < 4 or #sAccounts > 50 then
            tBase.Log("_OnRegist_Module   4  > sAccounts   > 20  Error")
            nError = 10
        end
        if (not api.Check_AccountString(sAccounts)) then
            tBase.Log("_OnRegist_Module   账号只接受英文、数字和下划线")
            nError = 12
        end
    end


    if Rdata.Password == nil then
        tBase.Log("_OnRegist_Module   sPassword  is nil    Error ")
        nError = 11
    elseif #Rdata.Password < 6 or #Rdata.Password > 50 then
        tBase.Log("_OnRegist_Module   6  > sPassword   > 24  Error")
        nError = 11
    end

    -- local isSuccee,tModels = pcall(cjson.decode,Rdata.Models)
    -- local sModels = ""
    -- if isSuccee  then
    --     if tModels.nType and tModels.sValue then
    --         if tModels.nType == 1 then
    --             if tModels.sValue and #tModels.sValue > 0 then
    --                 if #tModels.sValue ~= 5 then
    --                     tBase.Log("_OnRegist_Module   推荐码格式错误:%s",Rdata.Models)
    --                     nError = 13
    --                 elseif not api.Check_StringIsNormal(tModels.sValue) then
    --                     tBase.Log("_OnRegist_Module   推荐码只接受英文、数字:%s",Rdata.Models)
    --                     nError = 13
    --                 else
    --                     sModels=tModels.sValue
    --                 end
    --             end
    --         end
    --     else
    --         nError = 13
    --     end
    -- else
    --     tBase.Log("_OnRegist_Module   推荐码格式解析错误:%s",Rdata.Models)
    --     nError = 13
    -- end
    --检验验证码
    if nError == 0 then
        if nRegistWay == RegistWay.Phone or nRegistWay == RegistWay.Mail then
            if not tMoblieBinder.VerifyCode(sAccounts, Rdata.sVeriCode, nRegistWay == RegistWay.Phone, false, 0) then
                tBase.Log("验证码错误[%s]", Rdata.sVeriCode)
                nError = 20
            end
        end
    end

    if nError ~= 0 then
        LogonLink.Regist_Return_Error_User(ClientID, nError)
        return
    end

    local nFaceID        = Rdata.sFaceID or tostring(math.random(1, 10)) --头像ID
    local nSex           = Rdata.Sex                                     --性别 0 男 ，1 女
    local sNickName      = Rdata.NickName or nick or ""                  --昵称
    local sChannel       = Rdata.Channel                                 --渠道号： 1 官网
    local sIP            = Rdata.IP                                      --账号IP
    local sPhoneType     = Rdata.PhoneType                               --手机类型
    local sSystemVersion = Rdata.SysVersion                              --手机版本
    local sModels        = Rdata.Models                                  --手机机器码 现改用作推荐码 2022-05-24
    local sVersions      = Rdata.sVersions                               --前端版本

    sNickName            = sNickName:gsub("%s+", "")

    local sLocation      = "" --地点:  后台根据IP 获取数据
    --[[
    if sNickName==nil or #sNickName==0 then
        local isSuccee, str =pcall(api.CodeChar,sAccounts)
        sNickName = isSuccee and str or "玩家"
        if not isSuccee then
            if type(str) == "string" then
                mlogger:error(str)
            else
                tBase.LogT(str)
            end
        end
        sNickName = tBase64.encode(sNickName)
    end
    ]]
    local nAccountType = nRegistWay -- 账号注册

    --  渠道信息：
    local sChannelKey  = "Regist_Channel_" .. ClientID
    tBase.m_MyRedisData[1].redis:set(sChannelKey, sChannel)
    tBase.m_MyRedisData[1].redis:expire(sChannelKey, 20) --30 秒清除

    local tIp = {}
    tIp       = tBase.m_MyRedisData[1].redis:hgetall("UserAcceptInfo_" .. ClientID)
    sIP       = tIp.real_ip or tIp.ip or "192.168.0.1"
    tBase.Log("_OnRegist_Module  sIP_" .. sIP)

    local arrParameter = {}
    arrParameter[1] = sAccounts
    arrParameter[2] = Rdata.Password
    arrParameter[3] = nAccountType
    arrParameter[4] = sNickName
    arrParameter[5] = nFaceID .. ""
    arrParameter[6] = nSex
    arrParameter[7] = sChannel
    arrParameter[8] = sIP
    arrParameter[9] = sPhoneType
    arrParameter[10] = sSystemVersion
    arrParameter[11] = sModels
    arrParameter[12] = tPlatformChannelShopTb.GetShopId(Rdata.sPlatform, Rdata.Channel, Rdata.nShopId) --tonumber(Rdata.Channel) or 1
    arrParameter[13] = sTgUid
    arrParameter[14] = ""
    arrParameter[15] = tBase64.encode(sTGUserName)

    --log arrParameter
    tBase.Log("_OnRegist_Module  注册参数: %s", cjson.encode(arrParameter))

    local pRegist = ProtoMgr.PubProto_pb.Ruq_Regist()
    pRegist.ClientID = ClientID
    pRegist.sSql = CallProceduerSql("Regist_Accounts", arrParameter)
    --pRegist.sSql ="call Regist_Accounts('"..Rdata.Accounts.."','"..Rdata.Password.."',"..nAccountType..",'"..sNickName.."',"..nFaceID..","..nSex..",'"..sChannel.."','"..sIP.."','"..sPhoneType.."','"..sSystemVersion.."','"..sModels.."')"
    pRegist.nAccountType = nAccountType
    pRegist.sPlatform = Rdata.sPlatform or ""

    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_ACCOUNT_REGISTER)
    s:AddString(pRegist:SerializeToString())
    tBase.PostDatasByType(tname.db, 0, 0, s:GetData(), s:GetSize())
    tBase.Log("_OnRegist_Module  注册 SQL: %s ", pRegist.sSql)
end

-- 账号登陆返回
function LogonLink.DB_Return_Logon(sReturnKey, sData, nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local rLogon = ProtoMgr.PubProto_pb.Rup_Logon()
    rLogon:ParseFromString(ReadData:GetString())
    local ClientID    = rLogon.ClientID
    local nUserID     = rLogon.UserID
    local nError      = rLogon.nErrCode
    local nTimeDiff1  = rLogon.nTimeDiff
    local nLoginCount = rLogon.nLoginCount or 2
    if nError == 1 then
        local nTimeDiff = rLogon.nTimeDiff
        local nServerId = rLogon.nServerId
        local sIp       = rLogon.sIp
        local nPort     = rLogon.nPort
        tBase.Log("_DB_Return_Logon  登录成功nUserID: %d,  nTimeDiff: %d,nServerId: %d, sIp: %s , nPort: %d  "
        , nUserID, nTimeDiff, nServerId, sIp, nPort)

        -- 玩家重连的
        if nError == 1 and nServerId ~= 0 then
            local pReconnect = ProtoMgr.Logon_pb.RUP_Reconnect()
            pReconnect.sIp   = sIp
            pReconnect.nPort = nPort
            local nCLient    = base.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.SUB_REP_RECONNECT)
            nCLient:AddString(pReconnect:SerializeToString())
            tBase.PostToGateway(ClientID, nCLient:GetData(), nCLient:GetSize())
            tBase.Log("_DB_Return_Logon  向UserId:%d 发送重连 ClientId:%s", nUserID, ClientID)
        end
    else
        nUserID = nError
        tBase.Log("_DB_Return_Logon  玩家登录失败  nError %d Error_Info==517 ", nError)
    end
    local nGroupId = LogonLink.GetUserGroupId(nUserID)
    local pLogon   = ProtoMgr.Logon_pb.Rup_Logon()
    pLogon.nUserID = nUserID
    pLogon.nError  = nError
    pLogon.sToken  = rLogon.sToken
    pLogon.sSkin   = tPubRds._getGameSkinVal(tSCfg.RunEnvironment, nGroupId)

    local sUiType  = tPubRds._OnGeHelptUI(nGroupId) or ""
    pLogon.sUiType = sUiType

    if nError == 3 then
        pLogon.sConfineTime = rLogon.sUnsetTime
        tBase.Log("_DB_Return_Logon 玩家：%d  被封号， 解封时间： %s", nUserID, pLogon.sConfineTime)
    end
    pLogon.sVersions = tMainVersion.GetClientMainVersion(nGroupId, rLogon.sPlatform)
    pLogon.nLoginCount = nLoginCount
    local s = base.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.SUB_REP_LOGON_RESULT)
    s:AddString(pLogon:SerializeToString())
    tPubUserApi._SetUser_GroupId(nUserID, nGroupId)
    tBase.PostToGateway(ClientID, s:GetData(), s:GetSize())
    tBase.Log("_DB_Return_Logon  sSkin: " .. pLogon.sSkin ..
        "  玩家 %d:  返回客户端数据成功  nGroupId %d  sVersions:%s sPlatform:%s",
        nUserID, nGroupId, (pLogon.sVersions or "nil"), rLogon.sPlatform)

    if nError == 1 then
        tPubUserApi.IncrbyGamingUser(-1, -2, -1, false, 1, nUserID)
        -- LogonLink.GetUserOtherPlatmformWinlose(nUserID,math.floor(nGroupId))
    end

    return true
end

--账号注册返回
function LogonLink.DB_Return_Regist(sReturnKey, sData, nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local rRegist = ProtoMgr.PubProto_pb.Rup_Regist()
    rRegist:ParseFromString(ReadData:GetString())
    tBase.Log("_DB_Return_Regist    注册成功  ClientID:  " .. rRegist.ClientID)
    if rRegist.nErrCode == 1 then
        tBase.Log("_DB_Return_Regist sIp_" .. rRegist.sIp)
    else
        rRegist.UserID = -1
        tBase.Log("_DB_Return_Regist   玩家注册失败  Result %d   ", rRegist.nErrCode)
    end
    local nGroupId = LogonLink.GetUserGroupId(rRegist.UserID)
    local pRegist = ProtoMgr.Logon_pb.Rup_Regist()
    pRegist.nUserID = rRegist.UserID
    pRegist.nError = rRegist.nErrCode
    pRegist.sSkin = tPubRds._getGameSkinVal(tSCfg.RunEnvironment, nGroupId)
    local sUiType = tPubRds._OnGeHelptUI(nGroupId) or ""
    pRegist.sUiType = sUiType
    pRegist.sVersions = tMainVersion.GetClientMainVersion(nGroupId, rRegist.sPlatform)

    local s = base.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.SUB_REP_REGISTER_RESULT)
    s:AddString(pRegist:SerializeToString())
    tBase.PostToGateway(rRegist.ClientID, s:GetData(), s:GetSize())
    tBase.Log("_DB_Return_Regist    " .. pRegist.sSkin ..
        "  注册玩家 : %d    返回客户端数据成功  Result: %d  sVersions:%s sPlatform:%s",
        rRegist.UserID, rRegist.nErrCode, (pRegist.sVersions or "nil"), rRegist.sPlatform)
    tPubUserApi._SetUser_GroupId(rRegist.UserID, nGroupId)
    tPubUserApi.IncrbyGamingUser(-1, -2, -1, false, 1, rRegist.UserID)
    return true
end

-- 登录返回错误代码
function LogonLink.Logon_Return_Error_User(ClientID, nError)
    tBase.Log("_Logon_Return_Error_User  登录错误代码返回     Result: %d   ", nError)
    local pLogon   = ProtoMgr.Logon_pb.Rup_Logon()
    pLogon.nUserID = 0
    pLogon.nError  = nError
    local s        = base.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.SUB_REP_LOGON_RESULT)
    s:AddString(pLogon:SerializeToString())
    tBase.PostToGateway(ClientID, s:GetData(), s:GetSize())
    return true
end

-- 注册返回错误代码
function LogonLink.Regist_Return_Error_User(ClientID, nError)
    local pRegist   = ProtoMgr.Logon_pb.Rup_Regist()
    pRegist.nUserID = 0
    pRegist.nError  = nError
    local s         = base.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.SUB_REP_REGISTER_RESULT)
    s:AddString(pRegist:SerializeToString())
    tBase.PostToGateway(ClientID, s:GetData(), s:GetSize())
    tBase.Log("_Regist_Return_Error_User  注册错误代码返回    返回客户端数据成功 Result: %d  ", nError)
    return true
end

function LogonLink.LoginCheckInGame(nUserID, sIp)
    local t = tLocationInfo.GetCheckIpCfg()
    if next(t) then
        tBase.Log("_LoginCheckInGame IsSwitch_" .. (t.IsSwitch or ""))
        tBase.Log("_LoginCheckInGame sGroupId_" .. (t.sGroupId or ""))
        if t.IsSwitch == "true" then
            local tV = tApi.string_split(t.sGroupId, ",")
            local nGroupId = LogonLink.GetUserGroupId(nUserID)
            tBase.LogT("_LoginCheckInGame sGroup_", tV, " checkip+玩家_", nUserID, " nGroupId_", nGroupId, " sIp_", sIp, "",
                type(sIp))
            if tApi.FindKeyByVal(tV, tostring(math.modf(nGroupId))) then
                tBase.Log("i")
                local sHttp = t.hCheckIp
                sHttp = sHttp .. sIp
                local tRet = {}
                tRet.nErrCode, tRet.tCode = http.request(sHttp)
                tBase.Log(sHttp)
                tBase.Log(string.format("_LoginCheckInGame Check_%s", cjson.encode(tRet)))
                local tt = cjson.decode(tRet.nErrCode)
                if tt.countryCode and tt.countryCode == "abroad" then
                    return true
                end
            end
        end
    else
        mlogger:error("_LoginCheckInGame  ip校验，缺少后后台配置 nUserID_" .. nUserID)
    end
    return false
end

function LogonLink.GetUserGroupId(nUserID)
    local nShopID = tPubUserApi.Get_User_SHopId(nUserID)
    local nGroupId = tGameCfg.GetGroupId(nShopID, nUserID)
    tBase.Log("_GetUserGroupId  nShopID_" .. nShopID .. " nGroupId_" .. nGroupId)
    return nGroupId
end

--获取其它厂商的输赢
function LogonLink.GetUserOtherPlatmformWinlose(nUserID, nGroupId)
    local shopAccount = tPubUserApi.Get_User_ShopAccount(nUserID) or "testshopAccount"
    if not shopAccount then
        tBase.Log("GetUserOtherPlatmformWinlose 用户的第三方账号不存在_%d", nUserID)
        return
    end
    tBase.Log("GetUserOtherPlatmformWinlose shopAccount_%s nUserID_%d", shopAccount, nUserID)
    local sHttp = PublicRedis.GetOtherPlatformWinloseDomainName()
    if not sHttp or #sHttp <= 0 then
        tBase.LogT("GetUserOtherPlatmformWinlose 后台没有配置获取其它厂商的输赢 的域名")
        return
    end
    sHttp = string.format("%s", sHttp .. shopAccount)
    local sSendType = "GET"
    tBase.Log(sHttp)
    if sHttp then
        tBRRecord.SendToWebPlatformWinloseRequset(sHttp, nUserID, nGroupId, sSendType)
    else
        tBase.Log("后台没有配置 获取用户在其它厂商输赢的域名")
    end
end

--获取注册验证码请求
function LogonLink.OnVeriCodeReq(ClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local SystemID = ReadData:GetModuleID()
    local NewsID = ReadData:GetMsgID()
    local VeriCodeReq = ProtoMgr.Logon_pb.VeriCodeReq() -- 协议
    VeriCodeReq:ParseFromString(ReadData:GetString())
    local nWay = VeriCodeReq.nWay
    local sWayAddr = VeriCodeReq.sWayAddr
    local nPurpose = VeriCodeReq.nPurpose or 0
    local sAcc = VeriCodeReq.sAcc or ""
    --转发给db服处理
    local DbVeriCodeReq = ProtoMgr.DbServer1_pb.DbVeriCodeReq()
    DbVeriCodeReq.nWay = nWay
    DbVeriCodeReq.sWayAddr = sWayAddr
    DbVeriCodeReq.sClientID = ClientID
    DbVeriCodeReq.sAcc = sAcc
    DbVeriCodeReq.nPurpose = nPurpose
    local s = tBase.GetSP().new(Db_Proto1.Main_CMD, Db_Proto1.DbVeriCodeReq_CMD)
    s:AddString(DbVeriCodeReq:SerializeToString())
    tBase.PostDatasByType(tname.db, 0, 0, s:GetData(), s:GetSize())
end

--验证码,db服返回
function LogonLink.OnDbVeriCodeRsp(ClientID, Data, Len)
    local ReadData = tBase.GetRP().new(Data, Len)
    local SystemID = ReadData:GetModuleID()
    local NewsID = ReadData:GetMsgID()
    local DbVeriCodeRsp = ProtoMgr.DbServer1_pb.DbVeriCodeRsp() -- 协议
    DbVeriCodeRsp:ParseFromString(ReadData:GetString())

    --返回给玩家
    local VeriCodeRsp = ProtoMgr.Logon_pb.VeriCodeRsp()
    VeriCodeRsp.nRlt  = DbVeriCodeRsp.nRlt
    VeriCodeRsp.nWay  = DbVeriCodeRsp.nWay

    local s           = base.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.VeriCodeRsp_CMD)
    s:AddString(VeriCodeRsp:SerializeToString())
    tBase.PostToGateway(DbVeriCodeRsp.sClientID, s:GetData(), s:GetSize())
end

--账号绑定查询请求
function LogonLink.OnBindQuerryReq(ClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local SystemID = ReadData:GetModuleID()
    local NewsID = ReadData:GetMsgID()
    local BindQuerryReq = ProtoMgr.Logon_pb.BindQuerryReq() -- 协议
    BindQuerryReq:ParseFromString(ReadData:GetString())
    local sAcc = BindQuerryReq.sAcc
    tBase.Log("OnBindQuerryReq sAcc:%s", sAcc)

    --转发给db服处理
    local DbBindQuerryReq = ProtoMgr.DbServer1_pb.DbBindQuerryReq()
    DbBindQuerryReq.sAcc = BindQuerryReq.sAcc
    DbBindQuerryReq.sClientID = ClientID
    local s = tBase.GetSP().new(Db_Proto1.Main_CMD, Db_Proto1.DbBindQuerryReq_CMD)
    s:AddString(DbBindQuerryReq:SerializeToString())
    tBase.PostDatasByType(tname.db, 0, 0, s:GetData(), s:GetSize())
end

--密码重置请求
function LogonLink.OnPasswordResetReq(ClientID, Data, len)
    local ReadData = tBase.GetRP().new(Data, len)
    local SystemID = ReadData:GetModuleID()
    local NewsID = ReadData:GetMsgID()
    local PasswordResetReq = ProtoMgr.Logon_pb.PasswordResetReq() -- 协议
    PasswordResetReq:ParseFromString(ReadData:GetString())

    --转发给db服处理
    local DbPasswordResetReq = ProtoMgr.DbServer1_pb.DbPasswordResetReq()
    DbPasswordResetReq.nWay = PasswordResetReq.nWay                 --5:通过手机重置 6:通过邮箱重置
    DbPasswordResetReq.sAddrNew = PasswordResetReq.sAddrNew         --手机或邮箱地址
    DbPasswordResetReq.sVeriCode = PasswordResetReq.sVeriCode       --验证码(使用Logon.proto里的VeriCodeReq获取验证码)
    DbPasswordResetReq.sPasswordNew = PasswordResetReq.sPasswordNew --使用的新密码
    DbPasswordResetReq.sClientID = ClientID
    local s = tBase.GetSP().new(Db_Proto1.Main_CMD, Db_Proto1.DbPasswordResetReq_CMD)
    s:AddString(DbPasswordResetReq:SerializeToString())
    tBase.PostDatasByType(tname.db, 0, 0, s:GetData(), s:GetSize())
end

--db服绑定查询返回
function LogonLink.OnDbBindQuerryRsp(ClientID, Data, Len)
    local ReadData = tBase.GetRP().new(Data, Len)
    local SystemID = ReadData:GetModuleID()
    local NewsID = ReadData:GetMsgID()
    local DbBindQuerryRsp = ProtoMgr.DbServer1_pb.DbBindQuerryRsp() -- 协议
    DbBindQuerryRsp:ParseFromString(ReadData:GetString())

    --返回给玩家
    local BindQuerryRsp = ProtoMgr.Logon_pb.BindQuerryRsp()
    BindQuerryRsp.nRlt  = DbBindQuerryRsp.nRlt
    local s             = base.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.BindQuerryRsp_CMD)
    s:AddString(BindQuerryRsp:SerializeToString())
    tBase.PostToGateway(DbBindQuerryRsp.sClientID, s:GetData(), s:GetSize())
end

--db服密码重置返回
function LogonLink.OnDbPasswordResetRsp(ClientID, Data, Len)
    local ReadData = tBase.GetRP().new(Data, Len)
    local SystemID = ReadData:GetModuleID()
    local NewsID = ReadData:GetMsgID()
    local DbPasswordResetRsp = ProtoMgr.DbServer1_pb.DbPasswordResetRsp() -- 协议
    DbPasswordResetRsp:ParseFromString(ReadData:GetString())

    --返回给玩家
    local PasswordResetRsp = ProtoMgr.Logon_pb.PasswordResetRsp()
    PasswordResetRsp.nRlt  = DbPasswordResetRsp.nRlt
    local s                = base.GetSP().new(ProtoMgr.LogonPro.LOGON_MAIN, ProtoMgr.LogonPro.PasswordResetRsp_CMD)
    s:AddString(PasswordResetRsp:SerializeToString())
    tBase.PostToGateway(DbPasswordResetRsp.sClientID, s:GetData(), s:GetSize())
end

-- 解析并验证telegramInitData
function LogonLink.ParseAndVerifyTelegramInitData(telegramInitData)
    local botToken = tSCfg.TelegramBotToken or {}
    tBase.Log("parseAndVerifyTGInitData data: %s, botToken: %s", telegramInitData, botToken)
    -- 1. 解析参数
    local params = {}
    for pair in telegramInitData:gmatch("([^&]+)") do
        local key, value = pair:match("([^=]+)=(.+)")
        if key and value then
            -- URL decode
            value = value:gsub("%%(%x%x)", function(h)
                return string.char(tonumber(h, 16))
            end)
            params[key] = value
        end
    end

    local received_hash = params.hash
    if not received_hash then
        return nil, "missing hash in telegram_init_data"
    end
    params.hash = nil

    local keys = {}
    for k in pairs(params) do table.insert(keys, k) end
    table.sort(keys)

    -- 4. 构建 data_check_string
    local data_check_parts = {}
    for _, k in ipairs(keys) do
        table.insert(data_check_parts, k .. "=" .. params[k])
    end
    local data_check_string = table.concat(data_check_parts, "\n")
    local verify = false

    for _, bot_token in pairs(botToken) do
        local secret_key = TgVerify.hmac_sha256("WebAppData", bot_token)
        -- 6. 计算最终 hash = HMAC_SHA256(secret_key, data_check_string)
        local calculated_hash_bin = TgVerify.hmac_sha256(secret_key, data_check_string)
        local calculated_hash_hex = TgVerify.bin2hex(calculated_hash_bin)
        if calculated_hash_hex == received_hash then
            verify = true
            break
        end
    end
    -- local secret_key = TgVerify.hmac_sha256("WebAppData", botToken)
    -- -- 6. 计算最终 hash = HMAC_SHA256(secret_key, data_check_string)
    -- local calculated_hash_bin = TgVerify.hmac_sha256(secret_key, data_check_string)
    -- local calculated_hash_hex = TgVerify.bin2hex(calculated_hash_bin)
    -- 7. 验证
    if not verify then
        if _G.EnvFlag == "prod" then
            return nil, "hash error"
        else
            tBase.Log("OnBindQuerryReq calculated_hash_hex:%s received_hash:%s", calculated_hash_hex, received_hash)
        end
    end
    -- 返回解析后的数据
    local result = {}
    for _, key in ipairs(keys) do
        result[key] = params[key]
    end
    -- 如果存在user字段，解析JSON
    if result.user then
        tBase.Log("result.user: %s", result.user)
        local success, userTable = pcall(cjson.decode, result.user)
        if success and userTable then
            -- 确保 id 是字符串类型，避免大整数精度问题
            if userTable.id then
                -- 使用 string.format 来确保整数格式
                userTable.id = string.format("%.0f", userTable.id)
            end
            result.user = userTable
        end
    end
    return result.user
end

return LogonLink
