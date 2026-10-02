 package.path = require("./lua/Lobby/Head").path

local tBase = require("base") -- 基础功能接口
local tName = require("typename") -- 类弄定义接口
local tApi = require("publicApi") -- 共用功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local cjson = require("cjson") -- 数据交换格式
local tBankLogic = require("BankLogic") -- 银行逻辑

Bank = 
{
    -- 错误号归类
    m_Error = {
         m_VerifyResult = 1, -- 银行密码验证
    },
   
}

-- 协议入口
function Bank.BankProcol(sClientID, Data, len)
	local tPubProto =  ProtoMgr.LobbyPro
    local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID()  
     
    tBase.Log( " 大厅银行模块 Sys:"..Sys.." Sub:"..Sub ) 
    if Sub == tPubProto.SUB_REQ_INPUT_PASSWORD then
		local Read = ProtoMgr.Lobby_pb.REQ_SafeBox_PassWord()
		Read:ParseFromString(ReadData:GetString())
		local tmp = { nPassword = "" }
		tmp.nUserID = Read.nUserID
        tmp.nType = Read.nType
        if tmp.nType == 0 then 
            tmp.nPassword = Read.nPassword
        else
            tmp.nPassword = tmp.nUserID.."玩家今天不用验证密码!"
        end 
        tmp.sClientID = sClientID 
        if tmp.nUserID == nil or type(tmp.nUserID) ~= "number" or tmp.nUserID == 0 or 
            tmp.nPassword == nil or type(tmp.nPassword) ~= "string" or tmp.nPassword == ""
            then 
            local tSend = ProtoMgr.Lobby_pb.REP_SafeBox_PassWord()
            tSend.nResult = 1 
            tSend.strErr = tmp.nUserID.." 用户请求验证银行存在非法参数!"  
            Bank.BankErrorReturn( sClientID, tSend, Sys, tPubProto.SUB_REP_INPUT_PASSWORD )
            return
        end 
        tBase.Log( " 玩家:"..tmp.nUserID.."请求进入包厢箱note:(nType=1直接进入)： %s ",cjson.encode(tmp) )          
        tBankLogic.SafePassword( tmp.nUserID, tmp.nType, tmp.nPassword, sClientID )
    elseif Sub == tPubProto.SUB_REQ_SAFEBOX_OPTIONS then
        local Read = ProtoMgr.Lobby_pb.REQ_SafeBox_Options()
        Read:ParseFromString(ReadData:GetString())
        local tmp = {}
        tmp.nUserID = Read.nUserID
        tmp.nType = Read.nType
        tmp.sClientID = sClientID
        tBase.Log( " 请求保险箱操作（类型：1存取 2明细 3密码）： %s ",cjson.encode(tmp) )          
        tBankLogic.SafeBoxOption( tmp.nUserID, tmp.nType, sClientID, Read )
    else
        tBase.Log( " 银行错误的 协议   nSub == 1000" )
    end
  
    return
end

-- 错误码返回公共接口 
function Bank.BankErrorReturn( sClientID, tSend, MainID, SubID )

    tBase.Log( " 银行非法请求错误协议: 主%d 子%d", MainID, SubID )
    local s = tBase.GetSP().new(MainID, SubID)    
    s:AddString(tSend:SerializeToString())
    tBase.PostToGateway(sClientID,s:GetData(),s:GetSize())

end

return Bank