
--  开启服务器时 定时 3秒后 从数据库 中加载 配置表！
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path 

local tBase = require("base") -- 基础功能接口
local tName = require("typename") -- 类弄定义接口
local cjson = require("cjson") 
local tLocationInfo = require("LocationInfo") -- redis

SignConfig = { 
	
	m_AllCfg = {},
	nNoConfig = 1,  -- 1 有配置， 0 没有配置
	boLoadFinish = false,  -- 是否加载完成
	nIsWeb = 0, -- 0  没有  1  有更新

}


-- Web 更新配置
function SignConfig.Web_SignConfig()
	SignConfig.nIsWeb = 1  
	SignConfig.LoadSignConfig()
	return 
end 

-- 加载 登陆奖励配置表
function SignConfig.LoadSignConfig()
	local sSql = "Call Load_Sign_Config()"
    -- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_DB_SIGN_CONFIG)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())    
	tBase.Log(" 开始加载 登陆奖励配置表 ")
	return 
end

-- 加载 登陆奖励配置表
function SignConfig.DealLoad_SignConfig(sReturnKey, sData, nLen)

    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()   
    local nIndex  = ReadData:GetInt32()

   	tBase.Log(" 登陆奖励配置表 nIndex: %d  ",nIndex) 
   	if nIndex == 0 then
   	  	tBase.Log(" 登陆奖励配置表 没有数据 Error_Info== 178 ")
   	  	SignConfig.boLoadFinish = true
   	  	SignConfig.nNoConfig = 0  
   		return 0
   	end 
	if SignConfig.nIsWeb == 1 then 
    	SignConfig.m_webConfig = {}
    end 
 	
	local arrList = {}
	for i = 0, nIndex - 1  do
		local tPerData = {}		
		tPerData["ItemSetID"] = ReadData:GetInt32()
		tPerData["Weights"] = ReadData:GetInt32()
		tPerData["Type"] = ReadData:GetInt32()
		tPerData["AddDay"] = ReadData:GetInt32()
		tPerData["EmaiIID"] = ReadData:GetInt32()
		tPerData["ItemID"] = ReadData:GetInt32()
		tPerData["Count"] = ReadData:GetInt32() 
		table.insert(arrList , tPerData)		
	end
 
	tBase.Log(" 跟新加载登陆奖励配置表 All tData=%s",cjson.encode(arrList) )  
	local sStr = cjson.encode( arrList ) 
	tLocationInfo.DelLogonAwardConfig()
	tLocationInfo.SetLogonAwardConfig(sStr) 
 
	SignConfig.boLoadFinish = true
	-- test
	SignConfig.TestSignFun() 
	
end

 -- 根据nType获取: 1:7选1奖励 (计算权重） 2：累积奖励(不计算权重)
function SignConfig.GetSignConfig( nType )

	if SignConfig.nNoConfig == 0 then 
		tBase.Log(" 登陆奖励配置表 没有数据 Error_Info==178 nType(1抽奖配置2累计登陆配置): %d  ",nType)
		return 0,nil
	end
	
	local nIndex = 0
	local tt = nil 
	local tConfig = nil -- 存放新的配置表
	local arrList = {}
	tt = tLocationInfo.GetLogonAwardConfig()
	if tt ~= nil then
		tConfig = cjson.decode(tt)		
		for i = 1 , #tConfig do	
			if tConfig[i].Type == nType then 
				local tPerData = {}
				tPerData.ItemSetID = tConfig[i].ItemSetID
				tPerData.Weights = tConfig[i].Weights
				tPerData.AddDay = tConfig[i].AddDay
				tPerData.ItemID = tConfig[i].ItemID
				tPerData.Count = tConfig[i].Count
				tPerData.EmaiIID = tConfig[i].EmaiIID
				table.insert(arrList, tPerData)
				nIndex = nIndex + 1 
			end
		end
	else
		tBase.Log(" 没有nType="..nType.."这种配置 初始化默认值 ")
	end
	
	if arrList == nil or arrList == "{}" or arrList == "" or tt == nil then 
		tBase.Log(" 根据nType获取登陆奖励配置表 失败 Error_Info==10086 nType: %d ", nType)
		return 0,nil
	end 

	return nIndex, arrList

end 

-- 获取奖励信息
function SignConfig.Get_ItemSetID_Info(nItemSetID)	
 
	return
end

-- 测试函数
function SignConfig.TestSignFun()

	tBase.Log(" test 加载登陆配置ntype=2 ")
	local index, tConfig = SignConfig.GetSignConfig( 2 )
	tBase.Log(" LogonIndex: "..index.." tData=%s ",cjson.encode(tConfig) )  

end

return SignConfig