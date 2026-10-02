package.path = require("./lua/Chat/Head").path

local tBase 	= require("base")         -- 基础功能接口
local tApi  	= require("publicApi")    -- 共用功能接口
local dbInfo     = require("DBInfo") -- 数据库连接信息

ClientLog = {}

ClientLog.sLogPath = dbInfo.Client_LogDir    -- log路径

ClientLog.arrUserIDLog = {}   --  用户log对象
ClientLog.arrClientIDLog = {}   --  用户log对象

-- 调试信息登陆
function ClientLog.LogIn(sClientID, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nSystemID = ReadData:GetModuleID()
    local nNewsID = ReadData:GetMsgID()

    local nUsrId = ReadData:GetInt32()
    
    --tBase.Log("*******************************************DebugLog LogIn:"..nUsrId)

    local nRes = 0

    if ClientLog.arrUserIDLog[sClientID] == nil then
        ClientLog.arrUserIDLog[sClientID] = tBase.GetLogObject().new()
        ClientLog.arrUserIDLog[sClientID]:SetLogPath(ClientLog.sLogPath.."UserID_"..nUsrId, "debug_"..tBase.GetPort().."_"..tBase.GetThreadIndex())
    else
        nRes = 1
    end

    if ClientLog.arrClientIDLog[sClientID] ~= nil then
        local sSrcPath = ClientLog.sLogPath.."ClientID_"..sClientID
        local sTagPath = ClientLog.sLogPath.."UserID_"..nUsrId

        --tBase.Log(ClientLog.sLogPath.."ClientID_"..sClientID)
        local tFileLst = ClientLog.FileLstByDir(ClientLog.sLogPath.."ClientID_"..sClientID, "log")
        for i=1, #tFileLst do

            --tBase.Log("sSrcPath:"..sSrcPath.."/"..tFileLst[i])
            --tBase.Log("sTagPath:"..sTagPath.."/"..tFileLst[i])

            tApi.copyfile(sSrcPath.."/"..tFileLst[i], sTagPath.."/"..tFileLst[i])
            os.remove(sSrcPath.."/"..tFileLst[i])
        end 

        os.remove(sSrcPath)
        ClientLog.arrClientIDLog[sClientID] = nil

        if c == nil then
            nRes = 2
        end
    end

    -- local s = tBase.GetSP().new(tPubProto.MAIN.MAIN_GATEWAY, tPubProto.Sub_GATEWAY.SUB_REP_DEBUG_LOG_LOGIN)
    -- s:AddInt32(nRes)
    -- s:SendData(tBase.GetNetworkEngine(), sClientID)
end

-- 调试信息写入
function ClientLog.LogClient(sClientID, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nSystemID = ReadData:GetModuleID()
    local nNewsID = ReadData:GetMsgID()
    
    local Buff, nSize = ReadData:GetBuff()

    local sText = tApi.udataToStr(Buff, nSize)

    sText = string.gsub(sText, "%%", "*")

    --tBase.Log("LogClient("..nLen.."):"..sText)

    if ClientLog.arrUserIDLog[sClientID] ~= nil then
        ClientLog.arrUserIDLog[sClientID]:Log(sText)
    else
        if ClientLog.arrClientIDLog[sClientID] == nil then
            ClientLog.arrClientIDLog[sClientID] = tBase.GetLogObject().new()
            ClientLog.arrClientIDLog[sClientID]:SetLogPath(ClientLog.sLogPath.."/ClientID_"..sClientID, "debug_Client"..tBase.GetPort().."_"..tBase.GetThreadIndex())
        end
        ClientLog.arrClientIDLog[sClientID]:Log(sText)
    end
end

-- 关闭用户log对象
function ClientLog.CloseClient(sClientID)

    if ClientLog.arrUserIDLog[sClientID] ~= nil then
        ClientLog.arrUserIDLog[sClientID] = nil
    end

    if ClientLog.arrClientIDLog[sClientID] ~= nil then
        ClientLog.arrClientIDLog[sClientID] = nil
    end

end

-- 获取目录下的文件名列表
function ClientLog.FileLstByDir(DirPath, type)

    local tRes = {}
    local nIndex = 1
    local start_pos = 1

    local s = io.popen("ls "..DirPath)
    local fileLists = s:read("*all")
    --print(fileLists)
    --tBase.Log("File:"..fileLists)

    
    while true do
        --从文件列表里一行一行的获取文件名
        local _,end_pos, line = string.find(fileLists, "([^\n\r]+."..type..")", start_pos)
            if not end_pos then 
                break
            end
        --tBase.Log("File1:"..line)

        tRes[nIndex] = line
        nIndex = nIndex + 1

        start_pos = end_pos + 1
    end

    return tRes
end


return ClientLog