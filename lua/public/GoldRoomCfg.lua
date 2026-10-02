package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path

local tBase 	  = require("base")         -- 基础功能接口
local tName     = require("typename")     -- 类弄定义接口
local tConfigredis = require("Configredis")

GoldRoomCfg={
	boLoadFinish = false,   -- 是否加载完成
	GoldRoomCfgList = {},
    m_WinLimit_MaxGold   = 10000000,   --输赢限制
}

GoldRoomCfg.nNoConfig = 1   -- ， 0 没有配置   1 有配置
 --金币房手续费
GoldRoomCfg.ServiceCharge =
{   300,900,2700,6000,
    300,900,2700,6000,
    300,900,2700,6000,
    300,900,2700,6000,
}

--开始金币房快速匹配最少金币数量
GoldRoomCfg.MinGoldVal =
{
    2000,30001,90001,50000000,
    2000,30001,90001,50000000,
    2000,30001,90001,50000000,
    2000,30001,90001,50000000,
}    
GoldRoomCfg.GameID ={2,3,4,7,8,9}      --金币房ID
GoldRoomCfg.GetBrokeCount= 3     --金币房破产补助一天只能领多少次
GoldRoomCfg.Broke_Gold   = 5000  --金币房破产补助一次能领多少
GoldRoomCfg.GRoomMinGold = 2000  --玩家最低金币值
GoldRoomCfg.LEVEL = 4            -- 金币场次默认4个等级
GoldRoomCfg.GRoomListName = 
{
    "无鬼自摸新手场","无鬼自摸初级场","无鬼自摸中级场","无鬼自摸高级场",
    "无鬼点炮新手场","无鬼点炮初级场","无鬼点炮中级场","无鬼点炮高级场",
    "有鬼自摸新手场","有鬼自摸初级场","有鬼自摸中级场","有鬼自摸高级场",
    "有鬼点炮新手场","有鬼点炮初级场","有鬼点炮中级场","有鬼点炮高级场",
}


GoldRoomCfg.GoldRoomLeve =
{
	Level_exp               = 0,        --体验场
    
	Level_wnew   	        = 1,	    --无鬼自摸新手场
    Level_wfirst   	        = 2,	    --无鬼自摸初级场
    Level_wmiddle           = 3,        --无鬼自摸中级场
    Level_whigh             = 4,        --无鬼自摸高级场

    Level_wdianpaonew       = 5,        --无鬼点炮新手场
    Level_wdianpaofirst     = 6,        --无鬼点炮初级场
    Level_wdianpaomiddle    = 7,        --无鬼点炮中级场
    Level_wdianpaohigh      = 8,        --无鬼点炮高级场

    Level_ynew 		        = 9,        --有鬼自摸新手场
	Level_yfirst 	        = 10,        --有鬼自摸初级场
	Level_ymiddle 	        = 11,        --有鬼自摸中级场
    Level_yhigh   	        = 12,	    --有鬼自摸高级场

    Level_ydianpapnew 		= 13,        --有鬼点炮新手场
	Level_ydianpaofirst 	= 14,        --有鬼点炮初级场
	Level_ydianpaomiddle 	= 15,        --有鬼点炮中级场
	Level_ydianpaohigh   	= 16,	    --有鬼点炮高级场
}

GoldRoomCfg.nIsWeb = 0  -- 0  没有  1  有更新P

-- Web 更新配置
function GoldRoomCfg.Web_ItemConfig()
    GoldRoomCfg.nIsWeb = 1  

    return 
end 


-- 请求获得金币房配置数据
function GoldRoomCfg.GetGoldRoomData()

    local sSql = "Call PlatformDB.Load_GoldRoom_Config()"
    -- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_GOLDROOMCFG)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())
    tBase.Log(" 玩家数据   请求  SQL   金币房数据     成功  ")  
    return 
end


--金币房配置表
function GoldRoomCfg.LoadGoldRoomCfg(sReturnKey, sData, nLen)
    tBase.Log("大厅服     获取金币房的配置表:   ")
    
    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()
    local sSql = ReadData:GetString()

    GoldRoomCfg.Load_GameServerID_Cfg()
    
    local index  =0
    local cursor = assert (dbSink.PlatformDB_connect:execute(sSql))   
    repeat
        row = cursor:fetch({},"a")
        while row do
        	index = index+1
        	local tData = {}
            tData.Id = index;
            tData.level = tonumber(row.Level)
            tData.ServiceCharge = tonumber(row.ServiceCharge)
            tData.score = tonumber(row.Score)
            tData.mincapital = tonumber(row.Mincapital)
            tData.pima = tonumber(row.PiMa) 
            tData.GameType = tonumber(row.GameType)
            tData.MinGold = tonumber(row.MinGold) or 2000
            tData.Maxcapital =tonumber(row.Maxcapital) or 0

          --  tBase.Log("---->金币房配置:id :%d  level :%d score :%d  min :%d pima :%d nServerid :%d ",
           -- 	tData.Id,tData.level,tData.score,tData.mincapital,tData.pima,tData.nServerID)

            --存到redis
            tConfigredis.SaveGoldRoomData(tData);
            row = cursor:fetch(row,"a")  
        end
        cursor:close()
        cursor = dbSink.PlatformDB_connect:nextres()
    until( cursor == 0 ) 

    local s = tBase.GetSP().new(MainID, SubID)
    s:AddInt32(index)
    tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())
end

-- 加载金币房关联  ServerID  配置
function GoldRoomCfg.Load_GameServerID_Cfg()
    tBase.Log("大厅服     获取金币房的配置表:   ")
    local sSql = "Call PlatformDB.Load_GameServerID_Config(5)"  
    local index  =0
    local cursor = assert (dbSink.PlatformDB_connect:execute(sSql))   
    repeat
        row = cursor:fetch({},"a")
        while row do
            index = index+1
            local tData = {}
            tData.Id = index;
            tData.nServerID = tonumber(row.SrvId)
            tData.nGameServerType = tonumber(row.SType)
            tData.nGoldLevel = tonumber(row.GoldRoomCfgLevel)

            --存到redis
            tConfigredis.Save_GameServerID_Data(tData)
            row = cursor:fetch(row,"a")  
        end
        cursor:close()
        cursor = dbSink.PlatformDB_connect:nextres()
    until( cursor == 0 ) 
end


function GoldRoomCfg.DealLoad(sReturnKey, sData, nLen)
	tBase.Log(" 大厅服      金币房配置表    DealLoad ")
	--机器人管理
    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()  
    local nIndex  = ReadData:GetInt32()

	if nIndex ==0 then
		tBase.Log(" 大厅服  金币房配置表   没有数据  ")
   	  	GoldRoomCfg.boLoadFinish = true
   	  	GoldRoomCfg.nNoConfig = 0 -- 没有配置数据
   		return 0 
	end
	if GoldRoomCfg.nIsWeb == 1 then
		--GoldRoomCfg.arrConfig={}
	end


	if GoldRoomCfg.nIsWeb == 1 then
		GoldRoomCfg.arrAllcfg = {}
		--GoldRoomCfg.arrAllcfg = GoldRoomCfg.arrConfig
		--GoldRoomCfg.arrConfig = nil 
	end

	GoldRoomCfg.boLoadFinish = true

	return 1
end

function GoldRoomCfg.GetGoldRoomList(nGameID)
    local GoldRoomCfgList = {}
	local len = #GoldRoomCfgList
	if (len ==0 ) then
		local tDataList = tConfigredis.GetGoldRoomList()
        for i =1, #tDataList do
            if  nGameID ==  tDataList[i].GameType then
                table.insert(GoldRoomCfgList,tDataList[i])
            end
			
		end
	end

	return GoldRoomCfgList
end

-- 随机过滤 相同房间：   作废
function GoldRoomCfg.RandomFiltration(arrGoldRoom)
    local arr = {}

    -- 获取最大 的等级
    local arrLevel  = {}
    -- for k,v in pairs(arrGoldRoom) do
    --     table.insert(arrLevel,v.level)
    -- end
    -- local nMax = math.max(arrLevel)   -- 获取最高等级
    -- tBase.Log(" 金币房配置表  ----     nMax: %d ",nMax ) 
    --  等级归类   
    for i=1,6 do        
        local t = {}
        for k,v in pairs(arrGoldRoom) do
            if v.level == i then 
                -- tBase.Log(" 金币房配置表  0000===========  k: %d   id: %d  level: %d  ",k,v.Id ,v.level )   
                table.insert(t,v)
            end 
        end 
        table.insert(arr,t)
    end
    local tGoldRoom = {}
    -- 随机过滤
    for k1,v1 in pairs(arr) do
        if #v1 > 1 then 
            local a = #v1
            local nRandom = math.random(1,a)
            tBase.Log(" 金币房配置表  ----a:%d  , nRandom: %d ",a,nRandom ) 
            for k,v in pairs(v1) do 
                if nRandom ~= k then                     
                    tBase.Log(" 金币房配置表  111===========  k: %d   id: %d , level: %d ",k,v.Id,v.level )  
                    table.remove(arrGoldRoom, v.Id)

                end 
            end
        end 
        
    end 
    for k,v in pairs(arrGoldRoom) do
        tBase.Log(" 金币房配置表  2222===========  k: %d   id: %d , level: %d ",k,v.Id,v.level )  
    end
    return  arrGoldRoom
end


--获得服务器时间
function GoldRoomCfg.GetServerTime()
	tBase.Log(" 获得服务器时间 GetServerTime.....")

    local sSql = "Call PlatformDB.Load_GetDateTime()"
    -- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_GETSERVER_ITEM)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())
    tBase.Log(" 玩家数据   请求  SQL   金币房数据     成功  ")  
    return 
end


function GoldRoomCfg.test()
	tConfigredis.Sub_GoldRoom_Online(1 ,0)
end


return GoldRoomCfg


