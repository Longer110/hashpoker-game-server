package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path

local tBase        = require("base")         -- 基础功能接口
local tName        = require("typename")     -- 类弄定义接口
local ProtoMgr     = require("ProtoManager") -- 协议管理对象
local tParserAux = require("ParserAux")
local tRedisdefine = require("redisdefine")
local tRedis       = require("redis")
local tJson        = require("cjson")
local tSrvInfo = require("ServerInfo")
local publicRedis = require("PublicRedis") --redis
local GlobalConfigKey = tRedisdefine.GlobalConfigKey

local BackstageAux =tParserAux.BackstageAux

local DbServer_pb =ProtoMgr.DbServer_pb
local DbProtoEncode =tParserAux.DbProtoEncode                                                        
local DbProtoParse =tParserAux.DbProtoParse
local Backstage_pb =ProtoMgr.Backstage_pb
local BackstageCmd=Backstage_pb.Backstage_Proto()
local dbCmd =DbServer_pb.Db_Proto()

local DbServer1_pb=ProtoMgr.DbServer1_pb
local DbProtoEncode1=tParserAux.DbProtoEncode1
local DbProtoParse1 =tParserAux.DbProtoParse1
local dbCmd1 =DbServer1_pb.Db_Proto1()

local Config ={}
Config.isNeedGameList =true --是否需要获取游戏列表和房间列表
Config.CallBack_ShopListUpdate=nil ----店列表更新完时,会调用所设置的callBakcFunction
Config.nUpdateCount=0       --当前更新次数

local arrShopItemList ={}       --店列表 //
local arrGroupList = {}         --组id列表 //
local tGroupIdToGameList={}     --组id对应的游戏列表 //
local tGroupGameToRoomList ={}  --组与游戏id对应的房间列表

local tGroupGameToStatusInfo={} --组与游戏id对应的维护状态信息 {nGameStatus=?,nStartTime=?}

local function GroupGame(nGroupId,nGameId)
    return string.format("%d_%d",nGroupId,nGameId)
end
local function GroupAndGameId(sGroupGame)
    local sGroupId,sGameId =string.match(sGroupGame,"(%d+)_(%d+)")
    return tonumber(sGroupId),tonumber(sGameId)
end

local function SetGameStatus(nGroupId,nGameId,nGameStatus,nCurrentTime)
    local sKey =GroupGame(nGroupId,nGameId)
    tGroupGameToStatusInfo[sKey]=tGroupGameToStatusInfo[sKey] or {nGameStatus=nGameStatus,nStartTime=0}
    local info =tGroupGameToStatusInfo[sKey]
    if info.nGameStatus ==nGameStatus then
        return
    end
    info.nGameStatus=nGameStatus
    info.nStartTime=nCurrentTime
end


--db服请求:[游戏列表]
function Config.ReqDbGameList(nGroupId,nEcho)
    local strReq ="DbGameListReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0,nGroupId=nGroupId,nEcho=nEcho})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    if not Config.IsRegOnDbGameListRsp then
        tBase.RegFunc(dbCmd.Main_CMD,dbCmd.DbGameListRsp_CMD,Config.OnDbGameListRsp)       --注册游戏列表返回处理
        Config.IsRegOnDbGameListRsp =true
    end
    tBase.PostDatasByType(tName.db, 0, nGroupId, tPacket:GetData(), tPacket:GetSize())    
	return
end
--db服返回:[游戏列表]
function Config.OnDbGameListRsp(sReturnKey, Data, nLen)
    local strReq ="DbGameListRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    local arrGameItems ={}
    local tGroupGameToBool={}
    local nCurrentTime =os.time()
    for _,item in ipairs(tData.arrGameItems) do
        local tempItem ={}
        tempItem.nGameId =item.nGameId        	    --游戏id, 105:扎金花 113:三公 106:21点 104:百人牛牛 103:通比牛牛 ...
        tempItem.nGameOrder =item.nGameOrder  		--游戏排序的位置:1 -- 100 
        tempItem.nGameStatus =item.nGameStatus  	--游戏状态:0默认 1热门 2最新 3即将开启 4正在维护
        tempItem.sIconUrl =item.sIconUrl 		    -- 图标地址
        tempItem.sGamePath =item.sGamePath  		-- 游戏路径
        tempItem.sVersion =item.sVersion   		    -- 版本号
        tempItem.sZipFilePath =item.sZipFilePath 	-- 地址
        tempItem.sMD5FilePath =item.sMD5FilePath	-- 地址
        tempItem.nGroupId =item.nGroupId            --组id
        tempItem.sPlatform = item.sPlatform         --平台
        tempItem.sCUPGroupID =item.sCUPGroupID      --Config_Update_Package的组id
        table.insert(arrGameItems,tempItem)
        tGroupGameToBool[GroupGame(item.nGroupId,item.nGameId)]=true
        SetGameStatus(tData.nGroupId,item.nGameId,item.nGameStatus,nCurrentTime)
    end
    tGroupIdToGameList[tData.nGroupId]=arrGameItems

    --删除已经不应存在的房间列表
    for sGroupGame,_ in pairs(tGroupGameToRoomList) do
        local nGroupId,nGameId =GroupAndGameId(sGroupGame)
        if nGroupId ==tData.nGroupId and  (not tGroupGameToBool[sGroupGame]) then
            tGroupGameToRoomList[sGroupGame]=nil
        end
    end
    --开始获取对应游戏的房间列表
    for _,item in ipairs(arrGameItems) do
        Config.ReqDbRoomList(item.nGameId,item.nGroupId,tData.nEcho)
    end
end

--db服请求:[房间列表]
function Config.ReqDbRoomList(nGameId,nGroupId,nEcho)
    local nGameId =nGameId or 0
    local strReq ="DbRoomListReq"
    local tPacket =DbProtoEncode(strReq,{nGameId=nGameId,nGroupId=nGroupId,nEcho=nEcho})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    if not Config.IsRegOnDbRoomListRsp then
        tBase.RegFunc(dbCmd.Main_CMD,dbCmd.DbRoomListRsp_CMD,Config.OnDbRoomListRsp)       --注册房间列表返回处理
        Config.IsRegOnDbRoomListRsp =true
    end
    tBase.PostDatasByType(tName.db, 0, nGameId, tPacket:GetData(), tPacket:GetSize())    
	return 
end
--db服返回:[房间列表]
function Config.OnDbRoomListRsp(sReturnKey, Data, nLen)
    local strReq ="DbRoomListRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    local arrRoomItems={}
    for _,item in ipairs(tData.arrRoomItems) do
        local tempItem ={}
        tempItem.nGameId=item.nGameId;				        --游戏id
        tempItem.nRoomId=item.nRoomId;   			        --房间(场次)id  1新手 2初级 3中级 4高级 0免费
        tempItem.nEnterFloorLimit= item.nEnterFloorLimit;   --进入下限  
        tempItem.nAnte=item.nAnte ;   		                --底注 (某些游戏才有)
        tempItem.nGroupId =item.nGroupId                    --组id
        tempItem.nTax =item.nTax                            --抽水 (千分之)
        tempItem.tScoreCfg = item.tScoreCfg                 --牌型倍数(数组)
        tempItem.sHelpUI =item.sHelpUI
        table.insert(arrRoomItems,tempItem)
	end
    local sGroupGame =GroupGame(tData.nGroupId,tData.nGameId)
    tGroupGameToRoomList[sGroupGame] =arrRoomItems
end


--db服请求:[店列表]
function Config.ReqDbShopList(nEcho)
    local strReq ="DbShopListReq"
    local tPacket =DbProtoEncode(strReq,{nNoUse=0,nEcho=nEcho})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    if not Config.IsRegOnDbShopListRsp then
        tBase.RegFunc(dbCmd.Main_CMD,dbCmd.DbShopListRsp_CMD,Config.OnDbShopListRsp)       --注册房间列表返回处理
        tBase.RegFunc(BackstageCmd.Main_CMD,BackstageCmd.DbConfigReloadReq_CMD,Config.OnBackstage_DbConfigReloadReq)
        Config.IsRegOnDbShopListRsp =true
    end
    tBase.PostDatasByType(tName.db, 0, 1, tPacket:GetData(), tPacket:GetSize())    
	return 
end

--db服返回:[店列表]
function Config.OnDbShopListRsp(sReturnKey, Data, nLen)
    local strReq ="DbShopListRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end

    local tGroupIdToBool={}
    local arrShops ={}
    for _,item in ipairs(tData.arrShops) do
        local tempItem ={}
        tempItem.nShopId=item.nShopId;				        --店id (渠道)
        tempItem.nGroupId=item.nGroupId;   			        --组id
        tempItem.nSubStore=item.nSubStore;                  --分店
        tempItem.sChannel=item.sChannel;                    --渠道
        tempItem.sTgLink=item.sTgLink;                      --tg客服链接
        table.insert(arrShops,tempItem)
        tGroupIdToBool[item.nGroupId]=true
    end
    arrShopItemList=arrShops
    Config.arrShopList=arrShops                             --保留一个对外的table

    --删除已经不应存在的游戏列表
    for _,nOldGroupId in ipairs(arrGroupList) do
        if not tGroupIdToBool[nOldGroupId] then
            tGroupIdToGameList[nOldGroupId] =nil
        end
    end
    --更新组id列表
    arrGroupList ={}
    for nGroupId,_ in pairs(tGroupIdToBool) do
        table.insert(arrGroupList, nGroupId )
    end
    --通知外部有更新
    if Config.CallBack_ShopListUpdate then
        Config.CallBack_ShopListUpdate()
    end

    --更新服务器对应分组
    Config.ServerGroupRelationReq()
end

--向db服请求服务器对应分组
function Config.ServerGroupRelationReq()
    local strReq ="ServerGroupRelationReq"
    local tPacket =DbProtoEncode1(strReq,{nServerId=tSrvInfo.nServerId})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end

	if not Config.IsRegOnServerGroupRelationRsp then
        tBase.RegFunc(dbCmd1.Main_CMD,dbCmd1.ServerGroupRelationRsp_CMD,Config.OnServerGroupRelationRsp)       --注册服务器对应分组返回处理
        tBase.IsRegOnServerGroupRelationRsp =true
    end

    tBase.PostDatasByType(tName.db, 0, 1, tPacket:GetData(), tPacket:GetSize()) 
    -- tBase.Log("begin to ServerGroupRelationReq")   
end

--db服返回服务器对应分组
function Config.OnServerGroupRelationRsp(sReturnKey, Data, Len)
    local strReq ="ServerGroupRelationRsp"
    local tData =DbProtoParse1(Data, Len,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    
    local arrSGRelation = tBase.GetSGRelation()
    if tData.nPage==1 then
        --第一页
        arrSGRelation ={}
    end
    
	for _,item in ipairs(tData.arrItems) do
		local nServerId= item.nServerId
		local nGroupId= item.nGroupId
        table.insert(arrSGRelation,{nServerId=nServerId,nGroupId=nGroupId})	
	end
    tBase.SetSGRelation(arrSGRelation)
	-- tBase.Log("OnServerGroupRelationRsp arrSGRelation:%s nPage_%d nAllPage_%d",tJson.encode(arrSGRelation),tData.nPage,tData.nAllPage)

    --最后一页
    if tData.nPage==tData.nAllPage then
        local tServerGroup = {} --本服对应的分组 {[nGroupId]=nGroupId,...}
        local arrServerGroup = {} --本服对应的分组 {nGroupId,...}
        for _,v in pairs(arrSGRelation) do
            if v.nServerId==tSrvInfo.nServerId then
                tServerGroup[v.nGroupId] = v.nGroupId
                table.insert(arrServerGroup,v.nGroupId)
            end
        end
        
        if #arrServerGroup>0 then
            tBase.Log("后台有设置本服对应的分组 arrServerGroup:%s",tJson.encode(arrServerGroup))
            --删除非本服对应分组的游戏列表和房间列表
            for nGroupId,_ in pairs(tGroupIdToGameList) do
                if not tServerGroup[nGroupId] then
                    tGroupIdToGameList[nGroupId] = nil
                end
            end
            for sGroupGame,_ in pairs(tGroupGameToRoomList) do
                local nGroupId,nGameId =GroupAndGameId(sGroupGame)
                if not tServerGroup[nGroupId] then
                    tGroupGameToRoomList[sGroupGame] = nil
                end
            end

            --如果有需要则开始获取游戏列表
            if Config.isNeedGameList then
                for _,nGroupId in ipairs(arrGroupList) do
                    if tServerGroup[nGroupId] then --只加载对应分组的游戏列表
                        Config.ReqDbGameList(nGroupId,tData.nEcho)
                    end
                end
            end
        else
            --如果有需要则开始获取游戏列表
            if Config.isNeedGameList then
                for _,nGroupId in ipairs(arrGroupList) do
                    Config.ReqDbGameList(nGroupId,tData.nEcho)
                end
            end
        end
    end
end


function Config.OnBackstage_DbConfigReloadReq(sClientID, Data, len)
    local tReq =BackstageAux:Parser(Data,len,"DbConfigReloadReq")
    assert(tReq~=nil,"DbConfigReloadReq Parser Error")
    tBase.Log("OnBackstage_DbConfigReloadReq nVer:%d",tReq.nWhatChange)

    Config.ReqDbShopList(tReq.nWhatChange)
end

--店列表更新完时,会调用所设置的callBakcFunction
function Config.SetCallBack_ShopListUpdate(callBakcFunction)
    Config.CallBack_ShopListUpdate =callBakcFunction
end

function Config.SetCallFun(cFun)
    Config.OnBackFunc =cFun
end

--
function Config.Req_AllDbConfig()
    Config.nUpdateCount =Config.nUpdateCount+1
    Config.ReqDbShopList(-1)
end


function Config.IsGameMaintaining(nGroupId,nGameId)
    local sKey =GroupGame(nGroupId,nGameId)
    local info =tGroupGameToStatusInfo[sKey]
    if not info then
        return false
    end
    if not (info.nGameStatus==4 or info.nGameStatus==5) then
        return false
    end
    local nCurrentTime =os.time()

    local nTimeOut =60*5    --给5分钟时间，踢出游戏中的玩家
    if nGameId>=200 then
        nTimeOut =60*10     --麻将10分钟
    end
    local isTimeOut = (nCurrentTime-info.nStartTime)>nTimeOut
    return true,isTimeOut
end

--返回所有游戏列表的一个拷贝
function Config.GetGameList(nGroupId)
    if nGroupId then
       local arrGameList = tGroupIdToGameList[nGroupId] or {}
       return tBase.DeepCopy(arrGameList)
    end
    local arrGameListAll={}
    for nGroupId,arrGameList in pairs(tGroupIdToGameList) do
        for _,item in ipairs(arrGameList) do
            table.insert(arrGameListAll,item)
        end
    end
    return tBase.DeepCopy(arrGameListAll)
end

--返回游戏房间列表的一个拷贝(nGameId为0或nil时返回所有游戏房间列表)
--注意:由nGameId nRoomId nGroupId三个字段唯一标识一个房间配置
--数组元素字段
--[[
    nGameId	            --游戏id
    nRoomId   			--房间(场次)id  1新手 2初级 3中级 4高级 0免费
    nEnterFloorLimit    --进入下限  
    nAnte   		    --底注 (某些游戏才有)
    nGroupId            --组id
]]
function Config.GetRoomList(nGameId)
    local arrRoomListAll={}
    for _,arrRoomList in pairs(tGroupGameToRoomList) do
        for _,item in ipairs(arrRoomList) do
            table.insert(arrRoomListAll,item)
        end
    end
    if nGameId==nil or nGameId ==0 then
        return tBase.DeepCopy(arrRoomListAll)
    end
    local arrRoomList ={}
    for _,item in ipairs(arrRoomListAll) do
        if item.nGameId ==nGameId then
            table.insert(arrRoomList,tBase.DeepCopy(item))
        end
    end
    return arrRoomList
end

function Config.GetRoomList_v2(nGroupId,nGameId)
   local sGroupGame = GroupGame(nGroupId,nGameId)
   local arrRoomList =tGroupGameToRoomList[sGroupGame]
   if arrRoomList==nil then
        return {},-1
   end
   return tBase.DeepCopy(arrRoomList)
end
 
function Config.GetGroupByGameIDaneLevel( nGameID,nLevel )
    local GroupList ={}  --
    local tList = Config.GetRoomList(nGameID)  
    local len = #tList
    if (len >0) then
        for i=1, len do 
            if (tList[i].nGameId == nGameID and tList[i].nRoomId == nLevel) then
            
                local nGroupID = tonumber(tList[i].nGroupId) or 0
                --tBase.Log("GetGroupByGameIDaneLevel ====> %d   %d  %d ",nGameID,nLevel,nGroupID)

                if #GroupList >0 then
                    local bflage = true
                    for m,n in pairs(GroupList) do 
                        if n == nGroupID then
                            bflage = false
                            break
                        end
                    end
                    if (bflage) then
                        table.insert(GroupList,nGroupID)
                    end
                else
                    table.insert(GroupList,nGroupID)
                end
            end
        end
    end

    local len = #GroupList
    if (len >0) then
        for i = 1, len do
            for j = i +1, len do
                if (GroupList[i] < GroupList[j]) then
                    GroupList[i], GroupList[j] = GroupList[j], GroupList[i]
                end
            end
        end

        --从小到大排列
        local uList = {}
        for i=len,1,-1 do 
            local ID = GroupList[i]
            table.insert(uList,ID)
         end

        --[[tBase.Log("GameID %d  levelID %d ",nGameID,nLevel)
        for i,v in ipairs(uList) do 
           tBase.Log("排列结果是 %d",v)     
        end]]

        return uList
    else
        tBase.Log("没有发现有数据......................")
    end


    return GroupList
end

--返回店id对应的组配置
function Config.GetGroupConf(nShopId)
    for _,item in ipairs(arrShopItemList) do
        if item.nShopId == nShopId then
            return item
        end
    end
    return {}
end


--返回店id对应的组id(返回-1:表示无效)
function Config.GetGroupId(nShopId)
    for _,item in ipairs(arrShopItemList) do 
        if item.nShopId ==nShopId then
            return item.nGroupId
        end
    end
    return -1
end

--通过渠道返回对应的分店id(返回-1:表示无效)
function Config.GetChannelId(nShopId)
    for _,item in ipairs(arrShopItemList) do
        if tonumber(item.nShopId) == tonumber(nShopId) then
            return item.nSubStore
        end
    end
    return 2
end

--返回店id对应的分店id(返回0:表示默认)
function Config.GetShopIdByStoreChannel(nSubStore,sChannel)
    for _,item in ipairs(arrShopItemList) do
        if item.nSubStore ==nSubStore and item.sChannel == sChannel then
            tBase.Log(" ShopNoticeFind:"..item.nShopId )
            return item.nShopId
        end
    end
    return 0
end

--根据参数，返回对应的一个房间配置拷贝( {nGameId= ,nRoomId= ,nEnterFloorLimit= ,nAnte= ,nGroupId= ,nTax=} )
function Config.GetRoomConfig(nGameId,nRoomId,nShopId)
   local  nGroupId =Config.GetGroupId(nShopId)
   return Config.GetRoomConfig_v2(nGameId,nRoomId,nGroupId)
end

--根据参数，返回对应的一个房间配置拷贝( {nGameId= ,nRoomId= ,nEnterFloorLimit= ,nAnte= ,nGroupId= ,nTax=} )
function Config.GetRoomConfig_v2(nGameId,nRoomId,nGroupId)
    local isMaintaining,isTimeOut =Config.IsGameMaintaining(nGroupId,nGameId)
    if isMaintaining and (not isTimeOut) then    --游戏未开放或维护中
        return nil,-1
    end
    local arrRoomList =Config.GetRoomList_v2(nGroupId,nGameId)
    for _,roomConfig in ipairs(arrRoomList) do
        if roomConfig.nRoomId ==nRoomId then
            return roomConfig,0
        end
    end   
    local arrGameList =tGroupIdToGameList[nGroupId]
    if arrGameList==nil or #arrGameList==0 then
        return nil,-2   --分组关闭
    end
    return nil,-1       --游戏关闭
 end

--获取牌桌最下限
function Config.Get_Config_FloorLimit(nGameId,nRoomId,nGroupId)
     local arrRoomList =Config.GetRoomList_v2(nGroupId,nGameId)
     for _,roomConfig in ipairs(arrRoomList) do
          if roomConfig.nRoomId ==nRoomId then
              return tonumber(roomConfig.nEnterFloorLimit) or -1
          end
     end   
 end

 --获取牌桌底分
function Config.Get_Config_Ante(nGameId,nRoomId,nGroupId)
     local arrRoomList =Config.GetRoomList_v2(nGroupId,nGameId)
     for _,roomConfig in ipairs(arrRoomList) do
          if roomConfig.nRoomId ==nRoomId then
              return tonumber(roomConfig.nAnte)
          end
     end  
     return 1 
 end

function Config.IsRoomIdLegal(nGameId,nRoomId,nShopId)
    local tCfg =Config.GetRoomConfig(nGameId,nRoomId,nShopId)
    return tCfg~=nil
end

--返回分组id列表
function Config.GetGroupList()
    local arrTem ={}
    for _,v in ipairs(arrGroupList) do
        table.insert(arrTem,v)
    end
    return arrTem
end

function Config.SetIsNeedGameList(isNeedGameList)
    Config.isNeedGameList =isNeedGameList
end


--测试用
function Config._SetbrBaijiale(RoomID,nControlTime,nWin)
    local sKey = "_brBaijiale"..math.floor(RoomID)
    local tData = tBase.m_MyRedisData[1].redis:hgetall(sKey)

    local tInfo ={}
    tInfo.R = RoomID    --房间
    tInfo.C = nControlTime   --控牌次数
    if (tData ~=nil) then
        if (tData.v ~= nil) then
            tInfo.v = tData.v..math.floor(nWin)
        else
            tInfo.v = math.floor(nWin)  --结果
        end
    else
        tInfo.v = math.floor(nWin)
    end


    tBase.m_MyRedisData[1].redis:hmset(sKey, tInfo)
end

--db服请求: 全局配置信息
function Config.ReqDbGloBalConfig()
    local strReq = "DbGetGloBalConfigReq"
    local tPacket = DbProtoEncode1(strReq,{})
    if not tPacket then
        tBase.Log("Err happen, DbProtoEncode1_%s fail",strReq)
        return
    end
    if not Config.IsDbGetGloBalConfigRsp then
        tBase.RegFunc(dbCmd1.Main_CMD,dbCmd1.DbGetGloBalConfigRsp_CMD, Config.OnGloBalConfigRsp)       --注册全局配置返回处理
        Config.IsDbGetGloBalConfigRsp =true
    end
    tBase.PostDatasByType(tName.db, 0, 1, tPacket:GetData(), tPacket:GetSize())
	return
end

--db服返回
function Config.OnGloBalConfigRsp(sReturnKey, Data, nLen)
    local strReq = "DbGetGloBalConfigRsp"
    local tData = DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    local arrList = {}
    for _,item in ipairs(tData.nList) do
        local nItem ={}
        nItem.nId =item.nId        	            --id
        nItem.name =item.name  		            --名称
        nItem.detail =item.detail  	            --描述
        nItem.content =item.content 		    --详情
        table.insert(arrList,nItem)
    end
    tBase.Log("GloBalConfig arrList Len:%d", #arrList)
    tBase.LogT(arrList)
    for _,item in ipairs(arrList) do
        publicRedis.HsetRedis1(GlobalConfigKey.ConfigKey, item.name, item.content)
        if tSrvInfo.nStype == 231 then  -- 俱乐部从服
            SlaveData.globalConfig[item.name] = tJson.decode(item.content)
            tBase.LogT(SlaveData.globalConfig)
            if item.name == GlobalConfigKey.ChangeNameTime then
                UserOnTime.TryRestartReNameTimer()
            end
        end
    end
end

function Config.OnBackstage_GloBalConfigNotice(sClientID, Data, len)
    local tReq = BackstageAux:Parser(Data,len,"GloBalConfigNotice")
    assert(tReq~=nil,"OnBackstage_GloBalConfigNotice Parser Error")
end

return Config



