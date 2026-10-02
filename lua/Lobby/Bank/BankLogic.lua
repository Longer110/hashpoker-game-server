package.path = require("./lua/Lobby/Head").path

local tBase = require("base") -- 基础功能接口
local tname = require("typename") -- 类弄定义接口
local tPublicApi = require("publicApi") -- 共用功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local cjson = require("cjson") -- 数据交换格式
local tPubUserApi  = require("PublicUserInfo") --玩家数据

BankLogic = 
{
    m_LockEnterType = {
        _Type0 = 0, -- 要输入密码
        _Type1 = 1, -- 今天不用输入密码
    }
}

-- 验证银行密码
function BankLogic.SafePassword( nUserID, nType, nPassword, sClientID ) 
    
    --进入保险箱(是否要密码)
    if nType == 0 or nType == 1 then
        local pSend = ProtoMgr.PubProto_pb.RUQ_SafePassword()
        pSend.nClientID = sClientID
        pSend.nUserID = nUserID
        pSend.nPassword = nPassword
        pSend.sSql = "Call SafeBox_Verify("..nUserID..","..nType..",'"..nPassword.."')" 
        local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_SAFEBOX_VERIFY)
        s:AddString(pSend:SerializeToString())
        tBase.PostDatasByType(tname.db, 0, nUserID, s:GetData(), s:GetSize()) 
        return
    end

end

-- 发送银行验证结果 
function BankLogic.SafeBoxPassWordVerifySend(sReturnKey, sData, nLen)

    tBase.Log(" 发送银行验证结果：Len:"..nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()     

    local Read =  ProtoMgr.PubProto_pb.RUP_SafePassword()  
    Read:ParseFromString(ReadData:GetString()) 
    local tSendData = {}
    local nClientID = Read.nClientID
    tSendData.nUserID = Read.nUserID
    tSendData.nResult = Read.Result
    if tSendData.nResult == 0 then
        tSendData.nGold = Read.nGold 
    else
        tSendData.strErr = tSendData.nUserID.." 验证银行密码错误密码和原密码不匹配!"
    end
    tBase.Log(" 银行验证发送数据：%s",cjson.encode(tSendData) )

    local tSend = ProtoMgr.Lobby_pb.REP_SafeBox_PassWord()
    tSend.nResult = tSendData.nResult
    if tSendData.nResult == 0 then
        tSend.nGold = tSendData.nGold 
    else
        tSend.strErr = tSendData.nUserID.." 验证银行密码错误密码和原密码不匹配!"
    end

    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_INPUT_PASSWORD) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(nClientID, nClient:GetData(), nClient:GetSize())
    tBase.Log(" 玩家: %d  密码校验数据返回 size: %d ",tSendData.nUserID, nClient:GetSize()) 

end

-- 存取操作
function BankLogic.SafeBoxOption( nUserID, nType, sClientID, ReadData ) 

    local tTreasure = tPubUserApi.GetUserTreasure(nUserID)
    if tTreasure == nil then 
        tTreasure.nGold = 0
    else
        tBase.Log(" redis 获取财富 nGold: "..tTreasure.nGold)
    end

    local tUserInfo = {}
    tUserInfo.nUserID = nUserID       
    tUserInfo.sClientID = sClientID
    tBase.Log(" 银行模块操作类型："..nType) 

    if nType ==  1 then
        local Req_TypeOne = ReadData.arrTypeOne
        tBase.Log(" Req_TypeOne操作: 1存入金币资源101 2取出金币资源102 :"..Req_TypeOne)
        if Req_TypeOne == 1 then
            local nInputGold = ReadData.nInputGold -- 要存入的钱
            tBase.Log("存金币数："..nInputGold)
            if tTreasure.nGold >= nInputGold then 
                tPubUserApi.ChangeUserTreasure({nUserID=nUserID, nItemID=1, nDel= -nInputGold ,nSourceType =1})
                tPubUserApi.ChangeUserTreasure({nUserID=nUserID, nItemID=2, nDel= nInputGold ,nSourceType =101}) 
                local Send = ProtoMgr.Lobby_pb.REP_SafeBox_Access() 
                Send.nType = Req_TypeOne
                Send.nResult = 0 
                local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_SAFEBOX_ACCESS) 
                nClient:AddString(Send:SerializeToString())    
                tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())
                tBase.Log(" 玩家: %d 土豪请求【存钱成功】数据返回 size: %d ",nUserID,nClient:GetSize()) 
            else
                local Send = ProtoMgr.Lobby_pb.REP_SafeBox_Access()   
                Send.nType = Req_TypeOne
                Send.nResult = 1
                Send.strErr = "存入金币操作失败：拥有金币<存入金币!"
                local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_SAFEBOX_ACCESS) 
                nClient:AddString(Send:SerializeToString())    
                tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())
                tBase.Log(" 玩家: %d 土豪请求【存钱失败现有余额不足】数据返回 size: %d ",nUserID,nClient:GetSize()) 
            end
        elseif Req_TypeOne == 2 then
            local nOutputGold = ReadData.nOutPutGold -- 取出的钱
            tBase.Log("取金币数："..nOutputGold)
            if tTreasure.nGold < nOutputGold then 
                local Send = ProtoMgr.Lobby_pb.REP_SafeBox_Access() 
                Send.nType = Req_TypeOne
                Send.nResult = 1
                Send.strErr = "取出金币操作失败：银行金币<取出金币!"
                local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_SAFEBOX_ACCESS) 
                nClient:AddString(Send:SerializeToString())    
                tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())
                tBase.Log(" 玩家: %d 土豪请求【取钱失败银行余额不足】数据返回 size: %d ",nUserID,nClient:GetSize()) 
            else
                tPubUserApi.ChangeUserTreasure({nUserID=nUserID, nItemID=1, nDel= nOutputGold ,nSourceType =102})
                tPubUserApi.ChangeUserTreasure({nUserID=nUserID, nItemID=2, nDel= -nOutputGold ,nSourceType =1}) 
                local Send = ProtoMgr.Lobby_pb.REP_SafeBox_Access() 
                Send.nType = Req_TypeOne
                Send.nResult = 0
                local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_SAFEBOX_ACCESS) 
                nClient:AddString(Send:SerializeToString())    
                tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())
                tBase.Log(" 玩家: %d 土豪请求【取钱成功】数据返回 size: %d ",nUserID,nClient:GetSize()) 
            end
        end
    elseif nType == 2 then
        local pSend = ProtoMgr.PubProto_pb.RUQ_Safe_Detiail()
        pSend.nClientID = sClientID
        pSend.nUserID = nUserID
        tBase.Log(" Req_TypeTwo操作: 查看 存入取出明细:"..nType)
        local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_SAFEBOX_DETAIL)
        s:AddString(pSend:SerializeToString())
        tBase.PostDatasByType(tname.db, 0, nUserID, s:GetData(), s:GetSize()) 
        return
    elseif nType == 3 then 
        local OldPassword = ReadData.OldPassword
        local NewPassword = ReadData.NewPassword
        local OkPassword = ReadData.OkPassword
        if NewPassword ~= OkPassword then 
            local Send = ProtoMgr.Lobby_pb.REP_SafeBox_ResetPas() 
            Send.nResult = 1
            Send.strErr = "由于2次输入密码不匹配，请重新输入!"
            local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_SAFEBOX_RESETPAS) 
            nClient:AddString(tSend:SerializeToString())    
            tBase.PostToGateway(nClientID, nClient:GetData(), nClient:GetSize())
            tBase.Log(" 玩家: %d 请求【重设密码失败】数据返回 size: %d ",nUserID,nClient:GetSize()) 
        end
        local pSend = ProtoMgr.PubProto_pb.RUQ_Safe_ResetCode()
        pSend.nClientID = sClientID
        pSend.nUserID = nUserID
        pSend.nType = nType
        pSend.OldPassword = OldPassword
        pSend.NewPassword = NewPassword
        tBase.Log(" Req_TypeThree操作:玩家:"..nUserID.." 旧密码:"..OldPassword.." 新密码:"..NewPassword )
        local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_SAFEBOX_RESETCODE)
        s:AddString(pSend:SerializeToString())
        tBase.PostDatasByType(tname.db, 0, nUserID, s:GetData(), s:GetSize()) 
    end
 
end
  
-- 推送账单明细
function BankLogic.SafeBoxDetailSend(sReturnKey, sData, nLen)

    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()

    local Read = ProtoMgr.PubProto_pb.RUP_Safe_Detiail() 
    Read:ParseFromString(ReadData:GetString())
    local sClientID = Read.nClientID
    local nUserID = Read.nUserID

    tBase.Log("发送明细：sClientID："..sClientID.." nUserID:"..nUserID)
    local tSend = ProtoMgr.Lobby_pb.REP_SafeBox_Detail()

    for i,v in ipairs(Read.arrSafeBoxDetailItem) do 
        local arr =  tSend.nTypeTwo:add()  
        arr.nTime = Read.arrSafeBoxDetailItem[i].UpdateTime
        arr.nSourceType = Read.arrSafeBoxDetailItem[i].SourceType 

        local tt = {}
        tt.nTime = arr.nTime
        tt.nSourceType = arr.nSourceType 
        tBase.Log(" ["..i.."] 明细:%s",cjson.encode(tt) )
    end 

    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_SAFEBOX_DETAIL) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())   
    tBase.Log(" 玩家: %d 返回银行明细账单成功 size: %d ",nUserID,nClient:GetSize())

end

 
-- 通知修改密码结果
function BankLogic.SafeBoxResetCodeSend(sReturnKey, sData, nLen)

    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()
    local Read = ProtoMgr.PubProto_pb.RUP_Safe_ResetCode() 
    Read:ParseFromString(ReadData:GetString())

    local sClientID = Read.nClientID
    local nUserID = Read.nUserID
    local nResult = Read.nResult
    local nType = Read.nType

    local tSend = ProtoMgr.Lobby_pb.REP_SafeBox_ResetPas() 
    if nResult == 0 then 
        tSend.nResult = 0
    else
        tSend.nResult = 1
        tSend.strErr = " 密码重置错误，旧密码不匹配!"
    end
    
    local nClient = tBase.GetSP().new(ProtoMgr.LobbyPro.SYSLOBBY, ProtoMgr.LobbyPro.SUB_REP_SAFEBOX_RESETPAS) 
    nClient:AddString(tSend:SerializeToString())    
    tBase.PostToGateway(sClientID, nClient:GetData(), nClient:GetSize())   
    tBase.Log(" 玩家: %d 通知客戶端修改密码成功 size: %d ",nUserID,nClient:GetSize())

end


return BankLogic