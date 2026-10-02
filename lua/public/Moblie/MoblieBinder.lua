
--[[手机绑定]]

package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path
local env = require("env")    -- 环境配置
local tBase 	 = require("base")
local tName 	 = require("typename")
local tApi       = require("publicApi")
local tLocation  = require("LocationInfo")
-- local tPubProto  = require("PubProto")
local cjson      = require("cjson")        -- json 
local http       = require("socket.http")  -- Http 服务器
local dbInfo     = require("DBInfo")    -- 数据库连接信息
local tPubUserApi= require("PublicUserInfo")
local tPublicRedis =require("PublicRedis")


MoblieBinder = {
	enumErrCode = 
	{
		nBSuccess  =  2,  --绑定成功
        nCodeCheck =  1,  --验证码已发送
		nHasSend   =  0,  --已发送绑定
		nMobileErr = -1,  --手机号码错误
        nBeforeBind= -2,  --已绑定,不能重复绑定
		nCooling   = -3,  --冷却中
        nCodeErr   = -4,  --验证码错误
        beUsered   = -5,  -- 已被其他用户绑定
	}
}

function MoblieBinder.SendErrCode(sClientID, nCode)
 -- 	local s = tBase.GetSP().new(tPubProto.MAIN.LOGON_MAIN, tPubProto.SUB_LOGON_MAIN.SUB_GP_BIND_RESULT)
 --    s:AddInt32(nCode)
 --    tBase.Log("phone err nCode"..nCode)
	-- tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
end

--新增绑定
function MoblieBinder.AddBind(sClientID, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nSystemID = ReadData:GetModuleID()
    local nNewsID = ReadData:GetMsgID()

    local nUserId = ReadData:GetInt32()
    local sMobilePhone = ReadData:GetString()
    local sMachineId = ReadData:GetString()

    tBase.Log("AddBind 字节数:%d userId:%d 手机:%s 机器码:%s", nLen, nUserId, sMobilePhone, sMachineId)
       if string.len(sMobilePhone) ~= 11 then
        tBase.Log("string.len(sMobilePhone) ~= 11       Error_Info==180")
   		MoblieBinder.SendErrCode(sClientID, MoblieBinder.enumErrCode.nMobileErr)
        return
   	end

    local tBasic = tPubUserApi.GetUserBasic(nUserId)
    if string.len(tBasic.sPhone) > 8 then
        tBase.Log("string.len(tBasic.sPhone) > 8")
        MoblieBinder.SendErrCode(sClientID, MoblieBinder.enumErrCode.nBeforeBind)
        return
    end

   	local nCode = math.random(111111, 999999)	

   	-- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_ADDMOBLILEBIND)
    -- s:AddString(sClientID)
   	-- s:AddString("Call Sms_Add("..nUserId..",'"..sMobilePhone.."','"..sMachineId.."',"..nCode..")")
   	-- tBase.PostDatasByType(tName.db, tApi.SClientIdtoNumber(sClientID) , nUserId, s:GetData(), s:GetSize())
    
   	MoblieBinder.SendErrCode(sClientID, MoblieBinder.enumErrCode.nHasSend)
	tBase.Log("添加手机绑定"..sClientID)
end

--验证绑定
function MoblieBinder.CheckBind(sClientID, sData, nLen)
	local ReadData = base.GetRP().new(sData, nLen)
    local nSystemID = ReadData:GetModuleID()
    local nNewsID = ReadData:GetMsgID()

    local nUserId = ReadData:GetInt32()
    local sMobilePhone = ReadData:GetString()
    local sMachineId = ReadData:GetString()
	local nCode = ReadData:GetInt32()

	if string.len(sMobilePhone) ~= 11 then
   		MoblieBinder.SendErrCode(sClientID, MoblieBinder.enumErrCode.nMobileErr)
        return
   	end

    local tBasic = tPubUserApi.GetUserBasic(nUserId)
    if string.len(tBasic.sPhone) > 8 then
        MoblieBinder.SendErrCode(sClientID, MoblieBinder.enumErrCode.nBeforeBind)
        return
    end

    tBase.Log("Call Check_Moblie_Bind("..nUserId..",'"..sMobilePhone.."','"..sMachineId.."',"..nCode..")")
	-- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_CHECKBIND)
 --   	s:AddString(sClientID)
 --    s:AddInt32(nUserId)
 --    s:AddString(sMobilePhone)
 --    s:AddString("Call Check_Moblie_Bind("..nUserId..",'"..sMobilePhone.."','"..sMachineId.."',"..nCode..")")
   	tBase.PostDatasByType(tName.db, tApi.SClientIdtoNumber(sClientID) , nUserId, s:GetData(), s:GetSize())

    MoblieBinder.SendErrCode(sClientID, MoblieBinder.enumErrCode.nCodeCheck)
   	tBase.Log("验证手机绑定")   	
end

--返回db添加绑定
function MoblieBinder.DbBindResult(sClientID, sData, nLen)
	local ReadData = base.GetRP().new(sData, nLen)
    local nSystemID = ReadData:GetModuleID()
    local nNewsID = ReadData:GetMsgID()
    local sGateCliId = ReadData:GetString()
    local nResult = ReadData:GetInt32()

    local sPhone = ReadData:GetString()
    local nCode = ReadData:GetInt32()

    if nResult ~= 0 then
        if nResult ~= -1 then
            tBase.Log("nResult ~= 0:nResult:"..nResult)
    	    MoblieBinder.SendErrCode(sGateCliId, nResult)
            
        else
            MoblieBinder.SendErrCode(sGateCliId, MoblieBinder.enumErrCode.nCooling)
        end
        return
    end

    tBase.Log("添加的手机")
    local nResult = MoblieBinder.HttpSendMsg(sPhone, nCode) -- Add web

    if nResult ~= 0 then
    	tBase.Log("向后台申请发送短信失败 Error_Info==182 ")
    else
    	tBase.Log("向后台请求发送短信成功")
    end
end

--返回db验证绑定的结果
function MoblieBinder.DbCheckBind(sClientID, sData, nLen)
	local ReadData = base.GetRP().new(sData, nLen)
    local nSystemID = ReadData:GetModuleID()
    local nNewsID = ReadData:GetMsgID()
    local sGateCliId = ReadData:GetString()
    local nUserId = ReadData:GetInt32()
    local sMobilePhone = ReadData:GetString()
    local nFlag = ReadData:GetInt32()

    local nErrCode = 0
    if nFlag == 0 then
        local tBasic = tPubUserApi.GetUserBasic(nUserId)
        tBasic.sPhone = sMobilePhone
        tPubUserApi.UpdateUserData(tBasic) 
        nErrCode = MoblieBinder.enumErrCode.nBSuccess
    else
        nErrCode = nFlag
    end
    MoblieBinder.SendErrCode(sGateCliId, nErrCode)

    tBase.Log("绑定结果: sClientID:%s nFlag:%d", sGateCliId, nFlag)
end

--请求发送短信
function MoblieBinder.HttpSendMsg(sPhone, nCode)
    local sHttp = dbInfo.sHttp.."SendSMS?PhoneNumber=%s&Code=%d"
    sHttp = string.format(sHttp, sPhone, nCode)
    tBase.Log("打印手机绑定url:"..sHttp)

    local tRet = {}

    local nErrCode ,tCode,sHeaders,nStatus = http.request(sHttp)     
    -- tBase.Log(" ----------------------> sHeaders "..sHeaders)    
    tBase.Log(" ----------------------> nStatus  "..nStatus) 
    
    return tonumber(nErrCode)
end

--发送手机验证码,使用改方法的进程必须预先 require HttpNB并初始化
--http://mjadmin.qygaming.com/Auth/SendSMS?PhoneNumber=13226412332&Code=123456
--sPhone格式类似为: 86-13679573345
function MoblieBinder.SendVeriCodeByPhone(sPhone)
    local nCode = math.random(111111, 999999)
    local sAreaId,sPh =string.match(sPhone,"^(%d?%d?%d?%d?)%-(%d+)$")   --分解为区号，手机号

    local sUrlF =nil
    if sPh=="86" then
        sUrlF=tPublicRedis.GetVeriCodeByPhoneUrl() or "http://mjadmin.qygaming.com/Auth/SendSMS?PhoneNumber=%s&Code=%s&CountryCode=%s"
    else
        sUrlF=tPublicRedis.GetVeriCodeByPhoneUrlForeign() or "http://mjadmin.qygaming.com/Auth/SendSMS?PhoneNumber=%s&Code=%s&CountryCode=%s"
    end

    local isSuccee,sHttp =pcall(string.format,sUrlF,sPh,nCode,sAreaId)  
    if not isSuccee then
        tBase.LogT("SendVeriCodeByPhone Error ",sHttp," ",sUrlF) 
        return false
    end
    local funcRes = function(json_data,nErrCode) 
        tBase.LogT("SendVeriCodeByPhone ",{nErrCode=nErrCode,json_data=json_data,nCode=nCode,sHttp=sHttp}) 
    end
    local funcError = function(nErrCode)
        tBase.LogT("SendVeriCodeByPhone Error ",{nErrCode=nErrCode,nCode=nCode,sHttp=sHttp})
    end
    HttpNB.request(sHttp, funcRes, funcError,"GET",nil)

    --local nErrCode ,tCode,sHeaders,nStatus = http.request(sHttp)   
    --tBase.LogT("SendVeriCodeByPhone ",{nErrCode=nErrCode,tCode=tCode,nStatus=nStatus,nCode=nCode,sHttp=sHttp})  
    --local isSuccee =(tonumber(nErrCode)==0)

    local redis =tBase.m_MyRedisData[1].redis
    local sKey =string.format("PhoneVeri:%s",sPhone)
    redis:setex(sKey,90,nCode)      --90秒有效时间
    return true
end

--发送邮箱验证码 , 使用改方法的进程必须预先 require HttpNB并初始化
--http://192.168.0.215:82/phone/SendEmail?email=395457223@qq.com&code=888888
function MoblieBinder.SendVeriCodeByMail(sMail, nPurpose)
    local nCode =math.random(111111, 999999)
  
    local sUrlF = env.adminHost .. "/api/IMServer/SendMail?address=%s&code=%s"
    local isSuccee,sHttp =pcall(string.format,sUrlF,sMail,nCode)
    if not isSuccee then
        tBase.LogT("SendVeriCodeByMail Error ",sHttp," ",sUrlF)
        return false
    end
    local funcRes = function(json_data,nErrCode)
        tBase.LogT("SendVeriCodeByMail ",{nErrCode=nErrCode,json_data=json_data,nCode=nCode,sHttp=sHttp})
    end
    local funcError = function(nErrCode)
        tBase.LogT("SendVeriCodeByMail Error ",{nErrCode=nErrCode,nCode=nCode,sHttp=sHttp})
    end
    HttpNB.request(sHttp, funcRes, funcError,"GET",nil)
    
   -- local nErrCode ,tCode,sHeaders,nStatus = http.request(sHttp)   
   -- tBase.LogT("SendVeriCodeByMail ",{nErrCode=nErrCode,tCode=tCode,nStatus=nStatus,nCode=nCode,sHttp=sHttp})  
   
    local redis =tBase.m_MyRedisData[1].redis
    local sKey =string.format("MailVeri:%d:%s", nPurpose, sMail)
    redis:setex(sKey,300,nCode)      --300秒有效时间
    return true
end




--发送邮箱验证码
function MoblieBinder.SendVeriCodeByMail_Test(sMail)
    local nCode =123456
    if true then
        local redis =tBase.m_MyRedisData[1].redis
        local sKey =string.format("MailVeri:%s",sMail)
        redis:setex(sKey,300,nCode)      --300秒有效时间
    end
    return true
end
--发送手机验证码
function MoblieBinder.SendVeriCodeByPhone_Test(sPhone)
    local nCode = 123456
    if true then
        local redis =tBase.m_MyRedisData[1].redis
        local sKey =string.format("PhoneVeri:%s",sPhone)
        redis:setex(sKey,90,nCode)      --90秒有效时间
    end
    return true
end


--检验验证码是否正确,isPhone:true(手机验证码),false(邮箱验证码)
--sAddr:手机号或邮箱,视isPhone而定
function MoblieBinder.VerifyCode(sAddr,sCode,isPhone,isTest, nPurpose)
    if isTest then
        return true
    end
    if sCode==nil or sCode=="" then
        return false
    end
    local sKey =string.format("MailVeri:%d:%s", nPurpose, sAddr)
    if isPhone then
        sKey =string.format("PhoneVeri:%s",sAddr)
    end
    local redis =tBase.m_MyRedisData[1].redis
    local sgCode =redis:get(sKey)
    local isPass =(sgCode ==sCode)
    if isPass then
        redis:del(sKey)
    end
    return isPass
end

function MoblieBinder.SetTemp(sCon,sAddr,nSeconds,nPurpose)
    local redis =tBase.m_MyRedisData[1].redis
    sCon =string.format("Temp:%s,%d",sCon,nPurpose)
    sAddr =string.format("Temp:%s,%d",sAddr,nPurpose)
    redis:setex(sCon,nSeconds,0)
    redis:setex(sAddr,nSeconds,0)
end
function MoblieBinder.IsTempExist(sCon,sAddr,nPurpose)
    local redis =tBase.m_MyRedisData[1].redis
    sCon =string.format("Temp:%s,%d",sCon,nPurpose)
    sAddr =string.format("Temp:%s,%d",sAddr,nPurpose)
    local isA =redis:exists(sCon)
    local isB =redis:exists(sAddr)
    return isA or isB
end


return MoblieBinder

