 package.path = require("./lua/Lobby/Head").path

local tBase 	  = require("base")         -- 基础功能接口
local tName     = require("typename")     -- 类弄定义接口
local tApi      = require("publicApi")      -- 共用功能接口
local ProtoMgr  = require("ProtoManager") -- 协议管理对象 

GameListConfig = 
{
	arrShopInfoCfg	  		= {},   -- 分店基本表 配置
	arrGroupCfg	     		= {},   -- 群组基本表 配置
	arrGroupGameListCfg     = {},   -- 渠道游戏列表配置
	arrGameCfg 		  		= {},   -- 游戏配置
	arrGroupGameRelation    = {},   -- 群组 与游戏配置的关系 

	boLoadFinish = false,   -- 是否加载完成
	nNoConfig = 1 ,		   -- 0 没有配置， 1 有配置，
	arrAllCfg = {} ,  -- 所有的配置
	nIsWeb = 0  ,-- 0  没有  1  有更新
}




-- Web 更新配置
function GameListConfig.Web_GameListConfig()
    GameListConfig.nIsWeb = 1  
    GameListConfig.LoadGameListConfig()
    return 
end 

-- 加载 游戏列表配置
function GameListConfig.LoadGameListConfig()
	local tSend = ProtoMgr.PubProto_pb.RUQ_GameListCfg()
	tSend.sSql = "111"
    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_GAMELISTCFG)
    s:AddString(tSend:SerializeToString())
    tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())    
	tBase.Log(" 开始加载 游戏列表配置  ")
	return 
end

-- 开始  游戏列表配置
function GameListConfig.Load_GameListConfig(sReturnKey, sData, nLen)
    tBase.Log(" 加载  游戏列表配置         DealLoad  "..nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()    

    local Read = ProtoMgr.PubProto_pb.RUP_GameListCfg()
    Read:ParseFromString(ReadData:GetString())

    if GameListConfig.nIsWeb == 1 then 
       GameListConfig.arrConfig={}
	end

    local nIndex = 0  	

    for i,v in ipairs(Read.arrShopCfg) do
		local tPerData = {}		
		tPerData.Id 	  = Read.arrShopCfg[i].Id
		tPerData.Shop     = Read.arrShopCfg[i].Shop
		tPerData.GroupID  = Read.arrShopCfg[i].GroupID
		tPerData.DefaultGroupID = Read.arrShopCfg[i].DefaultGroupID
		tPerData.ShopInfo = Read.arrShopCfg[i].FaShopInfotherID
   	  	-- tBase.Log(" 分店基本表 配置  返回   Id:  %d   Shop: %s  ",tPerData.Id,tPerData.Shop )
	    if GameListConfig.nIsWeb == 1 then 
			table.insert(GameListConfig.arrShopInfoCfg , tPerData)
	    else
			table.insert(GameListConfig.arrShopInfoCfg , tPerData)
		end    
		nIndex = nIndex + 1 
    end
   	tBase.Log(" 分店基本表 配置返回   nIndex: %d  ",nIndex)
   	nIndex =  0

 	for i,v in ipairs(Read.arrGroupCfg) do
		local tPerData = {}		
		tPerData.Id 	  = Read.arrGroupCfg[i].Id
		tPerData.GroupName = Read.arrGroupCfg[i].GroupName
		tPerData.GroupInfo = Read.arrGroupCfg[i].GroupInfo

   	  	-- tBase.Log(" 群组基本表  配置返回   Id:  %d   GroupName: %s  ",tPerData.Id,tPerData.GroupName )
	    if GameListConfig.nIsWeb == 1 then 
			table.insert(GameListConfig.arrGroupCfg , tPerData)
	    else
			table.insert(GameListConfig.arrGroupCfg , tPerData)
		end    
		nIndex = nIndex + 1 
    end
   	tBase.Log(" 群组基本表 配置返回   nIndex: %d  ",nIndex)
   	nIndex =  0

 	for i,v in ipairs(Read.arrGroupGameListCfg) do
		local tPerData = {}		
		tPerData.Id 	  	  = tonumber(Read.arrGroupGameListCfg[i].Id)
		tPerData.GroupID 	  = tonumber(Read.arrGroupGameListCfg[i].GroupID)
		tPerData.SType 	  	  = Read.arrGroupGameListCfg[i].SType
		tPerData.GameName     = Read.arrGroupGameListCfg[i].GameName
		tPerData.GameStatus   = Read.arrGroupGameListCfg[i].GameStatus
		tPerData.GameOrder    = Read.arrGroupGameListCfg[i].GameOrder
		tPerData.CGStatus     = Read.arrGroupGameListCfg[i].CGStatus

		tPerData.IconUrl     = Read.arrGroupGameListCfg[i].IconUrl
		tPerData.GamePath     = Read.arrGroupGameListCfg[i].GamePath
		tPerData.Version     = Read.arrGroupGameListCfg[i].Version
		tPerData.ZipFilePath     = Read.arrGroupGameListCfg[i].ZipFilePath
		tPerData.MD5FilePath     = Read.arrGroupGameListCfg[i].MD5FilePath

   	  	-- tBase.Log(" 群组游戏列表配置 Id: %d,   GroupID: %d  SType: %d   ",tPerData.Id,tPerData.GroupID,tPerData.SType)
	    if GameListConfig.nIsWeb == 1 then 
			table.insert(GameListConfig.arrGroupGameListCfg , tPerData)
	    else
			table.insert(GameListConfig.arrGroupGameListCfg , tPerData)
		end    
		nIndex = nIndex + 1 
    end
   	tBase.Log(" 群组游戏列表 配置返回   nIndex: %d  ",nIndex)
   	nIndex =  0

 	for i,v in ipairs(Read.arrGameCfg) do
		local tPerData = {}		
		tPerData.Id 	  = Read.arrGameCfg[i].Id
		tPerData.SType = Read.arrGameCfg[i].SType
		tPerData.Session  = Read.arrGameCfg[i].Session
		tPerData.Floor 	  = Read.arrGameCfg[i].Floor
		tPerData.LowGrade  = Read.arrGameCfg[i].LowGrade
		tPerData.SessionName = Read.arrGameCfg[i].SessionName
		tPerData.Status   = Read.arrGameCfg[i].Status

   	  	-- tBase.Log("  游戏配置  Id:  "..tPerData.Id)
	    if GameListConfig.nIsWeb == 1 then 
			table.insert(GameListConfig.arrGameCfg , tPerData)
	    else
			table.insert(GameListConfig.arrGameCfg , tPerData)
		end    
		nIndex = nIndex + 1 
    end
   	tBase.Log(" 游戏基本配置表 返回   nIndex: %d  ",nIndex)
   	nIndex =  0
 	for i,v in ipairs(Read.arrGroupGameRelation) do
		local tPerData = {}		
		tPerData.Id 				= Read.arrGroupGameRelation[i].Id
		tPerData.GrouplGameListID  = Read.arrGroupGameRelation[i].GrouplGameListID
		tPerData.GameCfgID  	    = Read.arrGroupGameRelation[i].GameCfgID
		tPerData.DefaultSessionName  	    = Read.arrGroupGameRelation[i].DefaultSessionName

   	  	-- tBase.Log("  群组与游戏配置的关系  Id:  "..tPerData.Id)
	    if GameListConfig.nIsWeb == 1 then 
			table.insert(GameListConfig.arrGroupGameRelation , tPerData)
	    else
			table.insert(GameListConfig.arrGroupGameRelation , tPerData)
		end    
		nIndex = nIndex + 1 
    end

   	tBase.Log(" 游戏基本配置表 返回   nIndex: %d  ",nIndex)


   	if nIndex == 0 then
   	  	tBase.Log(" 加载  游戏列表配置   没有数据  ")
   	  	GameListConfig.boLoadFinish = true
   	  	GameListConfig.nNoConfig = 0   -- 没有配置数据
   		return 0 
   	end 

	-- if GameListConfig.nIsWeb == 1 then 
	-- 	GameListConfig.arrGameCfg = {}
	-- 	GameListConfig.arrGameCfg = GameListConfig.arrConfig
	-- 	GameListConfig.arrConfig = nil 
	-- end 

	GameListConfig.boLoadFinish = true
	tBase.Log(" 加载  游戏列表配置   加载完成  ...   ")

	-- 测试
	-- local  nGroupID = GameListConfig.Get_Shop_GroupID(1)
	-- if nGroupID == nil then 
	-- 	tBase.Log(" 该分店  没有配置  ")
	-- else
	-- 	tBase.Log(" 该分店 有配置   nGroupID:  "..nGroupID)
	-- 	local t = GameListConfig.GetGrouplGameListCfg(nGroupID)
	-- 	if t ~= nil then 			
	-- 		for a,b in ipairs(t) do
	-- 			-- tBase.Log("  获取群组游戏列表 配置：Id: %d  GameName:  %s",b.Id ,b.GameName )
	-- 			local t1 =  GameListConfig.Get_GroupGameRelation(b.Id)

	-- 			for x,y in ipairs(t1) do
	-- 				tBase.Log("  获取游戏配置--------> Id: %d  SessionName: %s  ",y.Id,y.SessionName )
	-- 			end 
	-- 		end
	-- 	end
	-- end 
	
    return 
end

-- 获取分店 关联
function GameListConfig.Get_Shop_GroupID(nShopID)
	for i,v in ipairs(GameListConfig.arrShopInfoCfg) do
		if v.Id == nShopID then 
			return v.GroupID
		end 		
	end
	return nil 
end

 -- 根据 游戏列表配置
function GameListConfig.GetGrouplGameListCfg(nShopID)		
	if GameListConfig.nNoConfig == 0 then tBase.Log(" 渠道游戏列表配置   没有数据 ") return  end 


	local  nGroupID = GameListConfig.Get_Shop_GroupID(nShopID)
	if nGroupID == nil then tBase.Log(" 该分店  没有配置  nShopID:  "..nShopID) return  end
	
	local tCfg = {}
	local nCount = 0
	for i,v in ipairs(GameListConfig.arrGroupGameListCfg) do
		if v.GroupID == nGroupID then 		
		    table.insert(tCfg,v)
		    nCount = nCount + 1 		
		end 		
	end
	if nCount == 0 then 
		return nil
	end
	return tCfg
end

--- 根据  群组游戏列表id  获取游戏配置
function GameListConfig.Get_GroupGameRelation(nGroupGameListID)
	local tGameCfg = {}
	local nCount = 0
	for i,v in ipairs(GameListConfig.arrGroupGameRelation) do
		if v.GrouplGameListID == nGroupGameListID then 
			local t  = GameListConfig.Get_GameCfg(v.GameCfgID)
			if t ~= nil  then 
				table.insert(tGameCfg,t)
				nCount = nCount + 1 
			end 
		end 	

	end
	if nCount == 0 then 
		return nil 
	end 
	return tGameCfg 
end

-- 获取 游戏配置
function GameListConfig.Get_GameCfg(GameCfgID)
	for i,v in ipairs(GameListConfig.arrGameCfg) do
		if v.Id == GameCfgID then 
			return v
		end 		
	end
	return nil 
end








return GameListConfig