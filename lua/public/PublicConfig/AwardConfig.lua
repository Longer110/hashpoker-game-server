
--  开启服务器时 定时 3秒后 从数据库 中加载 配置表！

package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path

local tBase 	= require("base")         -- 基础功能接口
local tName     = require("typename")     -- 类弄定义接口
-- local tPubProto = require("PubProto")	   -- 主协议

AwardConfig = 
{
	arrAllCfg = {},
	nNoConfig = 1,  -- 1 有配置， 0 没有配置
	boLoadFinish = false,  -- 是否加载完成	

	nIsWeb = 0, -- 0  没有  1  有更新
	arrConfig = {}  --web 临时配置
}


-- Web 更新配置
function AwardConfig.Web_AwardConfig()
	AwardConfig.nIsWeb = 1  
	AwardConfig.LoadAwardConfig()
	return 
end 

-- 加载 奖励配置表
function AwardConfig.LoadAwardConfig()
	local sSql = "Call Load_ItemSet_Config()"
    -- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_AWARDCFG)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())    
	tBase.Log(" 开始加载 奖励集合配置表:  ")
	return 
end

-- 加载 奖励配置表
function AwardConfig.DealLoad_AwardConfig(sReturnKey, sData, nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()   
    local nIndex  = ReadData:GetInt32()
    local sKey  = ReadData:GetString()  

   	tBase.Log(" 奖励集合配置表     nIndex: %d   sKey: %s  ",nIndex,sKey ) 
   	AwardConfig.arrAllCfg={}
   	if nIndex == 0 then
   	  	tBase.Log(" 奖励集合配置表   没有数据 Error_Info==175 ")
   	  	AwardConfig.boLoadFinish = true
   	  	AwardConfig.nNoConfig = 0  
   		return 0 
   	end 
	if AwardConfig.nIsWeb == 1 then 
    	AwardConfig.arrConfig = {}
    end 	
    local tAward_Config = {}
    tAward_Config = tBase.m_MyRedisData[1].redis:hgetall(sKey)  
    tBase.m_MyRedisData[1].redis:del(sKey)

	for i = 0, nIndex - 1  do
		local tPerData = {}		
		tPerData["nItemSetID"]      = tonumber(tAward_Config[i..",".."nItemSetID"])
		tPerData["nItemID"]  		= tonumber(tAward_Config[i..",".."nItemID"])
		tPerData["nCount"]  		= tonumber(tAward_Config[i..",".."nCount"])
		tPerData["sAwardInfo"]  	= tAward_Config[i..",".."sAwardInfo"]

	   	if AwardConfig.nIsWeb == 1 then 
	   		table.insert(AwardConfig.arrConfig , tPerData)
	   	else
	   		table.insert(AwardConfig.arrAllCfg , tPerData)
	   	end 	
	end
	if AwardConfig.nIsWeb == 1 then 
		AwardConfig.arrAllCfg = {}
		AwardConfig.arrAllCfg =	AwardConfig.arrConfig
		AwardConfig.arrConfig = {}
	end 
	AwardConfig.boLoadFinish = true
	tBase.Log(" 奖励集合配置表   加载完成  ...   ")

	-- AwardConfig.aaaaaaa()
    return 
end

 -- 根据道具集合ID   来获取 道具 和 数量:  表数目，配置表
function AwardConfig.GetAwardConfig(nItemSetID)	
	if AwardConfig.nNoConfig == 0 then 
		tBase.Log(" 奖励配置表    没有数据	Error_Info==176 nItemSetID: %d  ",nItemSetID)
		return 0,nil 
	end 		
	-- tBase.Log(" 获取    奖励配置  成功   nItemSetID  %d  ",nItemSetID)
	local nLen = #AwardConfig.arrAllCfg
	local nIndex = 0
	local tConfig = {}

	for i = 1 , #AwardConfig.arrAllCfg do	
		if AwardConfig.arrAllCfg[i].nItemSetID == nItemSetID then 
			local tPerData = {}
			tPerData.nItemID = AwardConfig.arrAllCfg[i].nItemID
			tPerData.nCount = AwardConfig.arrAllCfg[i].nCount
			table.insert(tConfig, tPerData)			
			-- tBase.Log(" 获取    奖励配置  成功   nItemID : %d  nCount %d ",AwardConfig.arrAllCfg[i].nItemID,AwardConfig.arrAllCfg[i].nCount)
			nIndex = nIndex + 1 
		end 	
	end	
	if tConfig == nil  then 
		tBase.Log(" 获取   奖励配置  失败	Error_Info==177 nItemSetID：%d ",nItemSetID)
		return 0,nil
	end 
	-- tBase.Log(" 获取   奖励配置  成功   nIndex:  %d ",nIndex)
	return nIndex,tConfig
end 

-- 获取奖励信息
function AwardConfig.Get_ItemSetID_Info(nItemSetID)	
	if AwardConfig.nNoConfig == 0 then   tBase.Log("  nItemSetID: %d    GetItemSetID_Info     Error_Info==178  ",nItemSetID) return  end 		
	local nLen = #AwardConfig.arrAllCfg
	for i = 1 , #AwardConfig.arrAllCfg do	
		if AwardConfig.arrAllCfg[i].nItemSetID == nItemSetID then 
			return AwardConfig.arrAllCfg[i].sAwardInfo
		end 	
	end	
	return  
end

-- 测试   数据
function AwardConfig.aaaaaaa()
	for i=1,10 do
    	tBase.Log(" 测试  ----------------------- ") 
	end
    local nIndex = 0
    local tConfig = {}
    nIndex,tConfig = AwardConfig.GetAwardConfig(2058)
    tBase.Log(" 测试   5555555555   nIndex   %d ",nIndex) 
    local tData = 'INSERT INTO AccountsDB.Email_User_Mail_Award (MaiIID,UserID,ItemID,Count,CreateTime) VALUES '
    local sValues2 = '(nMaiIID,nUserID,'
    for i=1,nIndex do
        local nItemID = tConfig[i].nItemID
        local nCount = tConfig[i].nCount
    	tBase.Log(" 测试   5555555555   nItemID   %d ",nItemID) 
    	tBase.Log(" 测试   5555555555   nCount    %d ",nCount) 
        tData=tData..sValues2..nItemID..","..nCount.."NOW()"..")"
        if i < nIndex then 
            tData = tData..","
        end 
    end
    tBase.Log(" 测试   ---------------------tData:  "..tData) 
end


return AwardConfig