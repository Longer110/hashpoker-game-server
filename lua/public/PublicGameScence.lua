--俱乐部公用接口
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path
package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path
package.path = "../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" .. package.path

local tBase = require("base")
local cjson = require("cjson")
local ProtoMgr = require("ProtoManager")
local ProtoAux = require("ProtoCoder").Aux
local typename = require("typename")
local tTrendMath = require("TrendMath") 
local tSrvInfo = require("ServerInfo")  
local PublicLiveAutoBet  = require("PublicLiveAutoBet")        
 


--百家乐中心服协议
local pb_Center =ProtoMgr.BaiJiaLeCenter_pb
local CMD_Center =ProtoMgr.BaiJiaLeCenter_pb.BJLC_Proto()
local ToCMD_Center =function(strProto)
  return CMD_Center.Main_CMD,CMD_Center[strProto..'_CMD']
end

--生成个编解码辅助对象
BaiJiaLeAux =ProtoAux:New(pb_Center,ToCMD_Center)


PublicGameScence = {
    arrDataSoureTable = {},       -- 百家乐 数据源牌桌      
    arrGameTable = {},
    arrGroupGameTable = {},       -- 分组牌桌
    
    OpenMenuUser={},   --打开路纸用户
}
 
--以下游戏中心服 进行的逻辑 

-- 检查 自动下注开关 
local function _IsAutoBetSwitch(nGroupId,nGameId)
    local tSwitch = RedisCahche.Get_SwitchConfig(nGameId,nGroupId)
    if tSwitch and tSwitch.nAutoBet > 0 then 
        return true 
    end 
    return false 
end 

-- 是否数据源牌桌 
local function IsDataSoureTable(strProto,tSendData) 
    if strProto == "BJLCTableCreateNotify" then         
        -- if tSendData.tScence.nTableType == 2 then  -- 过滤非区块链牌桌   
            if tSendData.tScence.nGroupId > 0 then -- 过滤数据源牌桌 
                PublicGameScence.arrDataSoureTable[tSendData.sTableId] = tSendData.tScence.nGroupId 
            end 
        -- end
    end     
    if PublicGameScence.arrDataSoureTable[tSendData.sTableId] then
        return false 
    end
    return true  
end

--  过滤无关协议 
local function IsSendProtobuf(strProto)
    local arrProtobuf = {}
    arrProtobuf["BJLCTickNotify"] = true    
    arrProtobuf["BJLCGoldChangeSynNotify"] = true  
    arrProtobuf["BJLCUserBetNotify"] = true    
    arrProtobuf["BJLCAreasBetNotify"] = true  
    arrProtobuf["BJLCApplyCancelNotify"] = true   
    arrProtobuf["BJLCUserLeaveNotify"] = true   
    arrProtobuf["BJLCApplyForBankerNotify"] = true   
    arrProtobuf["BJLCPlayerModeChangeNotify"] = true            -- 模式   
    arrProtobuf["BJLCUserSettleNotify"] = true               
    arrProtobuf["BJLCUserEnterNotify"] = true                   
     
    if arrProtobuf[strProto] then 
        return false  
    end 
    return true  
end 

-- 服务器是否 维护
local function _IsServerIdMainTain(nServerId)    
    local nStatus = RedisCahche.GetServerState(nServerId) 
    if nStatus > 1 then  -- 服务器状态 0:未启用 1:正常 2:维护 3:测试 4:进程没开 (默认1)   
        return true 
    else
        return false
    end 
end

--发送到 Lobby服
function PublicGameScence.SendToLobbyServer(nGameId,strProto,tSendData,tServIdToKey)
    local tPacket
    local sSerIdToKey = cjson.encode(tServIdToKey)
    if nGameId == 122 then      
        local sTableId = tSendData.sTableId or ""       
        if IsDataSoureTable(strProto,tSendData) then     -- 是否数据源牌桌 
            return 
        end 
        if not IsSendProtobuf(strProto) then 
            return 
        end 
        if strProto == "BJLCTableCreateNotify" then   
            sSerIdToKey = cjson.encode(tServIdToKey)
            -- tBase.Log("_SendToLobbyServer [%d=%s]  开桌  sSerIdToKey: %s ",nGameId,sTableId,sSerIdToKey)    

        elseif strProto == "BJLCGoInFreeNotify" then             
            -- tBase.Log("_SendToLobbyServer [%d=%s]  空闲阶段",nGameId,sTableId)     
	        if tSendData.nIsClose ==1 then
                PublicGameScence.arrDataSoureTable[tSendData.sTableId] = nil 
                -- tBase.Log("_SendToLobbyServer [%d=%s]  空闲阶段 关闭桌子 ",nGameId,sTableId)     
            else 
                --故障恢复
                if tSendData.nIsRecover==1 then  
                    sSerIdToKey = cjson.encode(tServIdToKey)
                end   
            end       
        elseif strProto == "BJLCGoInBetStageNotify" then   
            sSerIdToKey = cjson.encode(tServIdToKey)
            -- tBase.Log("_SendToLobbyServer [%d=%s]  下注阶段",nGameId,sTableId)      
        elseif strProto == "BJLCGoInBetStopNotify" then   
            -- tBase.Log("_SendToLobbyServer [%d=%s]  停止下注阶段",nGameId,sTableId)             
        elseif strProto == "BJLCGoInSettleNotify" then      
            -- tBase.Log("_SendToLobbyServer [%d=%s]  结算阶段",nGameId,sTableId)     
        else
            -- tBase.Log("_SendToLobbyServer  nGameId_%d  strProto: %s  sTableId: %s  ",nGameId,strProto,sTableId)
        end 
        tPacket = BaiJiaLeAux:Encode(strProto,tSendData)
    end 
    local arrServerKey = tBase.GetSrcAllKey(typename.lobby)
    if not arrServerKey or #arrServerKey == 0 then 
        tBase.Log("_SendToLobbyServer  nGameId_%d  strProto: %s  sTableId: %s   无大厅服 key",nGameId,strProto,tSendData.sTableId)
        return 
    end 
    local sLobbyKey = arrServerKey[math.random(1,#arrServerKey)] or arrServerKey[1]
    local arrKey = publicApi._GetNotMaintianServerKey(arrServerKey)
    if #arrKey > 0 then 
        sLobbyKey = arrKey[math.random(1,#arrKey)] or arrKey[1] 
    end 
    local s = tBase.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_GATEWEY_BROAD)
    s:AddUint32(nGameId)
    s:AddString(strProto)     -- 当前牌桌协议 
    s:AddString(sLobbyKey)    -- 决定 运行任务 key 
    s:AddBuff(tPacket:GetData(), tPacket:GetSize())
    s:AddString(sSerIdToKey) 
    for _,sKey in pairs(arrServerKey) do
        tBase.PostToServer(sKey,0,s:GetData(),s:GetSize())
    end  
    return 1
end

----- 以下大厅服 进行的逻辑 


-- 监听游戏中心服 通知 
function PublicGameScence.ListenGameProto()    
    tBase.RegFunc(ProtoMgr.GatewayPro.GATEWAY ,ProtoMgr.Sub_GateWay.SUB_GATEWEY_BROAD,PublicGameScence.GameScenceNotify)  
    tBase.RegFunc(ProtoMgr.GatewayPro.GATEWAY ,ProtoMgr.Sub_GateWay.SUB_SendLobby_GameReq,PublicGameScence.OpenMenuUserhandle)         -- 路纸操作
    tBase.RegFunc(CMD_Center.Main_CMD ,CMD_Center.BJLCScenceRsp_CMD ,PublicGameScence.OnBJLCScenceRsp)         --桌子场景创建回复

    local CMD_Backstage =ProtoMgr.Backstage_pb.Backstage_Proto()
    tBase.RegFunc(CMD_Backstage.Main_CMD ,CMD_Backstage.UserAutoBetRsp_CMD,PublicLiveAutoBet.UserAutoBetRsp)    -- 自动下注回复
    tBase.RegFunc(ProtoMgr.Sys.DB,ProtoMgr.Sub_DB.AutoBetLoadUserInfoRep,PublicLiveAutoBet.AutoBetLoadUserInfoRep)          --自动下注加载用户数据 
end 
 

--桌子状态 1:下注阶段 2:开牌阶段 3:空闲(换庄)阶段 其它:未定义
local TableState ={
    nInit =0,           --未开始
    nBet=1,             --下注阶段
    nSettle=2,          --结算阶段(开牌阶段)
    nFree=3,            --空闲阶段
    nShuffle=4,         --洗牌阶段
    nShuffleEnd=5,      --弃牌阶段
    nWaitingSettle=6,   --等待结算
    nFault=7,           --故障中
}

local function _CreateTable(sTableId,tScence,nGameId)     
    local t = {}
    t.sTableId = sTableId
    t.sTableName = tScence.sTableName
    t.sPaiJuId = tScence.sPaiJuId    
    t.nLiveUserID = tScence.nLiveUserID or 0   
    t.nTableType = tScence.nTableType    
    
    t.nStage = TableState.nInit

	t.DurationTime_BetStage =15			--下注阶段时间
	t.DurationTime_SettleStage =12		    --结算阶段时间
	t.DurationTime_FreeStage =2			--空闲阶段时间
	t.DurationTime_ShuffleStage =13		--洗牌阶段时间

	t.sLiveID =tScence.sLiveID				--第三方app需要信息(直播间id)
	t.sPlatformID =tScence.sPlatformID		--第三方app需要信息(app方主播id)
    t.sLiveName =""

	t.isPassWordRoom =tScence.isPassWordRoom   -- 是否密码房
	t.isVoiceRoom =tScence.isVoiceRoom		   -- 是否语音房
	t.isCopyTable=tScence.isCopyTable		   -- 是否副桌

    t.nGroupId = math.floor(tScence.nGroupId)
    t.nGameId = math.floor(nGameId) 
    t.nCount = 0 -- 局数 
    local arrTrend={}          --趋势图
    local arrResult = {}
    for _,item in ipairs(tScence.arrTrend) do
        local itemCp ={nResult=item.nResult,nOrder=item.nOrder,nIsZhuangDui=item.nIsZhuangDui,nIsXianDui=item.nIsXianDui,nPredict=item.nPredict}
        table.insert(arrTrend,itemCp)
        table.insert(arrResult,item.nResult)
    end            
    t.arrTrend = arrTrend
    local tGoodTrend = {nType=0,nBetArea=0} --趋势图好路类型和推荐下注区
    tGoodTrend.nType,tGoodTrend.nBetArea = tTrendMath.GetBetAreaByTrend(arrResult)
    t.tGoodTrend = tGoodTrend          
    t.arrUserAutoBet = {}   -- 自动下注信息
    t.isAutoBet = false     -- 自动下注开关  
    t.nLeaveOut = 1         -- 遗漏： 1顺路，0 逆路
    t.isGameMiantian = false     -- 游戏维护
    t.isLobbyMiantian = false    -- 大厅维护
    t.arrSerIdToKey ={}          -- 游戏服 key  
    PublicGameScence.arrGameTable[sTableId] = t   

    if not PublicGameScence.arrGroupGameTable[t.nGroupId] then 
        PublicGameScence.arrGroupGameTable[t.nGroupId]={}
    end 
    PublicGameScence.arrGroupGameTable[t.nGroupId][sTableId] =true 

    return t
end

local function _GetTable(sTableId)   
    return PublicGameScence.arrGameTable[sTableId]
end 

local function _ClearnTable(sTableId)      
    local tTable = PublicGameScence.arrGameTable[sTableId] 
    if not tTable then 
        tBase.Log("_ClearnTable  sTableId: %s tTable is nil ",sTableId)
        return 
    end 
    local nGroupId=tTable.nGroupId
    PublicGameScence.arrGroupGameTable[nGroupId][sTableId]=nil 
    PublicGameScence.arrGameTable[sTableId] = nil 
end 
 
-- 获取任务牌桌 id 
local function _GetTableUserId(sTableId)
    local arr = PublicRedis.GetTableAllCfg(sTableId) 
    return arr
end

-- 获取分组牌桌
local function _GetGroupTable(nGroupId)
    local arrGroupTable = {}
    local tGroupTable = PublicGameScence.arrGroupGameTable[nGroupId] or {}
    for sTableId, v in pairs(tGroupTable) do
        local tTable = PublicGameScence.arrGameTable[sTableId]
        if v and tTable then 
            arrGroupTable[sTableId] = tTable
        end 
    end  
    return arrGroupTable
end

-- 处理 游戏场景通知
function PublicGameScence.GameScenceNotify(sReturnKey,Data,nLen) 
    local ReadData = tBase.GetRP().new(Data, nLen)
    local MainID = ReadData:GetModuleID()
    local SubID = ReadData:GetMsgID()
    local nGameId = ReadData:GetInt32()
    local strProto = ReadData:GetString()
    local sLobbyKey = ReadData:GetString()
    local Buff, nlen = ReadData:GetBuff()
    local sSerIdToKey = ReadData:GetString()  
    if nGameId == 122 then 
        local tData = BaiJiaLeAux:Parser(Buff, nlen,strProto)
        assert(tData~=nil and tData.sTableId~=nil)        
        local sTableId = tData.sTableId               
        if strProto == "BJLCTableCreateNotify" then     
            local tTable = _CreateTable(sTableId,tData.tScence,nGameId)   
            tTable.arrSerIdToKey = cjson.decode(sSerIdToKey)
            if #tTable.arrSerIdToKey == 0 then  
                tBase.Log("_GameScenceNotify [%s=%s]  开桌 nGroupId_%d sSerIdToKey_%s  没有游戏服key ",tTable.sTableName,sTableId,tTable.nGroupId,sSerIdToKey)   
                return 
            end 
            local sLog=""
            if tTable.isPassWordRoom then  
                sLog="密码房 "
            end 
            if tTable.isVoiceRoom then  
                sLog=sLog.."语言房 "
            end 
            tBase.Log("_GameScenceNotify [%s=%s]  开桌 nGroupId_%d arrTrend_%d  %s ",tTable.sTableName,sTableId,tTable.nGroupId,#tTable.arrTrend,sLog)         
            return 
        end 
        local tTable = _GetTable(sTableId) 
        if not tTable then 
            tBase.Log("_GameScenceNotify [%d=%s]   tTable is nil  strProto_%s ",nGameId,sTableId,strProto)    
            PublicGameScence._RebootTable(sReturnKey,sTableId)   
            return 
        end 
        if strProto == "BJLCGoInFreeNotify" then               
            tTable.isAutoBet = _IsAutoBetSwitch(tTable.nGroupId,nGameId)  -- 是否开启 自动下注  
            tTable.sPaiJuId = tData.sPaiJuId
            if tTable.nLiveUserID ~= tData.nLiveUserID then 
			    tTable.nLiveUserID =tData.nLiveUserID	--app主播id
			    tTable.sPlatformID =tData.sPlatformID	--app主播id
			    tTable.sLiveID =tData.sLiveID			--直播间id    
                if tTable.nLiveUserID > 0 and #tTable.sLiveName ==0 then                 
                    tTable.sLiveName = PublicUserInfo.GetUserNickName(tTable.nLiveUserID)		--主播昵称
                end 
                if tTable.nLiveUserID == 0 then 
                    tTable.sLiveName = ""
                end 
            end 
            tTable.nStage = TableState.nFree
            tTable.nStageEndTime =os.time() +tData.nSeconds       --阶段结束时间

            if #tTable.arrSerIdToKey == 0 then 
                tTable.arrSerIdToKey = cjson.decode(sSerIdToKey)
            end   
	        if tData.nIsClose ==1 then 
                _ClearnTable(sTableId)      
                tBase.Log("_GameScenceNotify [%s=%s]  空闲阶段 关闭桌子 ",tTable.sTableName,sTableId)       
                return  
            else
                --故障恢复
                if tData.nIsRecover==1 then 
                    tTable = _CreateTable(sTableId,tData.tScence,nGameId)  
                    tTable.arrSerIdToKey = cjson.decode(sSerIdToKey)
                end     
            end     

            local nCenterServId =tonumber(string.match(sTableId,"(%d+)#"))   
            if _IsServerIdMainTain(nCenterServId) then  
                tTable.isGameMiantian = true  
            else
                tTable.isGameMiantian = false
            end 
            if _IsServerIdMainTain(tSrvInfo.nServerId) then  
                tTable.isLobbyMiantian = true  
            else
                tTable.isLobbyMiantian = false
            end 
            -- tBase.Log("_GameScenceNotify [%s=%s]  空闲阶段 局数_%d nGroupId_%d nStage_%d  %s"
            -- ,tTable.sTableName,sTableId,tTable.nCount,tTable.nGroupId,tTable.nStage)  

        elseif strProto == "BJLCGoInBetStageNotify" then  
            tTable.sLobbyKey = sLobbyKey   -- 运行 任务的key            
            tTable.isAutoBet = _IsAutoBetSwitch(tTable.nGroupId,nGameId)  
            if #tTable.arrSerIdToKey == 0 then 
                tTable.arrSerIdToKey = cjson.decode(sSerIdToKey)
            end             
            tTable.nStage = TableState.nBet 
            tTable.DurationTime_BetStage =tData.nSeconds          --下注时间
            tTable.nStageEndTime =os.time() +tData.nSeconds       --阶段结束时间
            local Str= ""
            if tTable.nLiveUserID > 0 then 
                Str= Str.." nLiveUserID: ".. math.floor(tTable.nLiveUserID)
            end 
            if #tTable.sLiveID > 1 then 
                Str= Str.." sLiveID: "..tTable.sLiveID
            end 
            if #tTable.sPlatformID > 1 then 
                Str= Str.." sPlatformID: "..tTable.sPlatformID 
            end  
            if #tTable.sPlatformID > 1 then 
                Str= Str.." sPlatformID: "..tTable.sPlatformID 
            end  

            tBase.Log("_GameScenceNotify [%s=%s] 下注阶段 局数_%d nGroupId_%d nBetTime_%d arrTrend_%d  %s"
            ,tTable.sTableName,sTableId,tTable.nCount,tTable.nGroupId,tData.nSeconds,#tTable.arrTrend,Str)  

            -- 开始自动下注
            PublicGameScence._StartAutoBet(tTable)  

            PublicGameScence.OnTableGoInBetStage(tTable.nGroupId,sTableId,tTable.DurationTime_BetStage,tTable.sLiveID,tTable.sPlatformID,tTable.sLiveName)  

        elseif strProto == "BJLCGoInBetStopNotify" then  
            -- tBase.Log("_GameScenceNotify [%s=%s]  停止下注 ",tTable.sTableName,sTableId)  
            tTable.nStage = TableState.nWaitingSettle
            tTable.nStageEndTime =os.time() +tData.nSeconds       --阶段结束时间

        elseif strProto == "BJLCGoInSettleNotify" then      
            tTable.nStage = TableState.nSettle
            tTable.nStageEndTime =os.time() +tData.nSeconds       --阶段结束时间

            local tResultsOfCardOpen = tData.tResultsOfCardOpen
            if tData.nIsNewAgain==1 then 
                tTable.arrTrend = {}
            end 
            local item ={}
            item.nResult =tResultsOfCardOpen.nResult
            item.nIsZhuangDui =tResultsOfCardOpen.nIsZhuangDui
            item.nIsXianDui =tResultsOfCardOpen.nIsXianDui
            item.nPredict =tResultsOfCardOpen.nPredict
            item.nOrder =#tTable.arrTrend +1
            table.insert(tTable.arrTrend,item)  

            local arrTrend = {}
            for k,v in pairs(tTable.arrTrend or {}) do
                table.insert(arrTrend,v.nResult)
            end         
            tTable.tResultsOfCardOpen = tResultsOfCardOpen
            local nGoodTrendType = tTable.tGoodTrend.nType or 0
            local nGoodTrendArea = tTable.tGoodTrend.nBetArea or 0
            local sLog = ""
            if tResultsOfCardOpen.nResult==1 then
                sLog = "闲赢"
            elseif tResultsOfCardOpen.nResult==2 then 
                sLog = "庄赢"
            elseif tResultsOfCardOpen.nResult==0 then 
                sLog = "和"
            end                              
            if nGoodTrendType > 0 then 
                sLog =sLog .." ".. nGoodTrendArea==tResultsOfCardOpen.nResult and "顺路" or "逆路"
            end              
            PublicGameScence._WriteAutoBetRecord(tTable,nGoodTrendType,nGoodTrendArea,sLog) 

            -- 更新好路
            tTable.tGoodTrend.nType,tTable.tGoodTrend.nBetArea = tTrendMath.GetBetAreaByTrend(arrTrend)                         
            if not tTable.tGoodTrend or not tTable.tGoodTrend.nType or not tTable.tGoodTrend.nBetArea then 
                tTable.tGoodTrend ={}
                tTable.tGoodTrend.nType = 0 
                tTable.tGoodTrend.nBetArea = 0 
            end 
            local nPointXian = tResultsOfCardOpen.nPointXian
            local nPointZhuang = tResultsOfCardOpen.nPointZhuang 
            tBase.Log("_GameScenceNotify [%s=%s]  结算阶段 新好路_%d sPaiJuId_%s 庄_%d 闲_%d %s "
            ,tTable.sTableName,sTableId,tTable.tGoodTrend.nType,tData.sPaiJuId,nPointXian,nPointZhuang,sLog)   
            
            if nGoodTrendType > 0 and nGoodTrendType ~= tTable.tGoodTrend.nType then 
                if tTable.tGoodTrend.nType == 0 then 
                    local arrUserId = _GetTableUserId(sTableId)
                    if arrUserId and #arrUserId > 0 then 
                        for k, v in ipairs(arrUserId) do
                            local nUserId = v.nUserId
                            PublicRedis._ResetAutoBetStatistics(nUserId,sTableId,1)   -- 重置连赢                        
                        end 
                    end  
                end 
            end 
            tTable.nCount = tTable.nCount + 1

            PublicGameScence.OnTableTrendChange(tTable.nGroupId,sTableId,item,nGoodTrendType) 

        elseif strProto =="BJLCGoInShuffleNotify" then    
            tTable.nStage = TableState.nShuffle
            tTable.nStageEndTime =os.time() +tData.nSeconds       --阶段结束时间

            tTable.arrTrend={}
            tTable.tGoodTren={}            
            tTable.nCount = 0
            tBase.Log("_GameScenceNotify [%s=%s]  洗牌了  ",tTable.sTableName,sTableId)  
        
        elseif strProto == "BJLCPlayerCntSummaryNotify" then   -- 人数  
            tTable.nUserCntOfSum =tData.nSumCnt 
            -- tBase.Log("_GameScenceNotify [%s=%s]  人数 nUserCntOfSum_%d ",tTable.sTableName,sTableId,tTable.nUserCntOfSum)  
            PublicGameScence.OnTableUserCntChange(tTable.nGroupId,sTableId,tData.nSumCnt)  
        elseif strProto == "BJLCGoInFaultNotify" then   -- 故障中  
            tTable.nStage = TableState.nFault 
            tBase.Log("_GameScenceNotify [%s=%s]  故障中  ",tTable.sTableName,sTableId)    
        elseif strProto == "BJLCTableCloseNotify" then   -- 关桌了  
            _ClearnTable(sTableId)      
            tBase.Log("_GameScenceNotify [%s=%s]   关闭桌子 ",tTable.sTableName,sTableId)      
        else           
            tBase.Log("_GameScenceNotify [%s=%s]  其他协议 %s ",tTable.sTableName,sTableId,strProto)   
            return   
        end  
        return 
    end 

    tBase.Log("_GameScenceNotify [%d= %s]  其他游戏 %s ",nGameId,sTableId,strProto)     
    return 
end

--场景恢复
function PublicGameScence.OnBJLCScenceRsp(sReturnKey,Data,nLen)
    local strReq ="BJLCScenceRsp"
    local tData =BaiJiaLeAux:Parser(Data, nLen,strReq)
    assert(tData~=nil) 
    local nGameId = 122
    local tTable = _CreateTable(tData.sTableId,tData.tScence,nGameId) 
    tBase.Log("_OnBJLCScenceRsp [%s=%s]  场景恢复 nGroupId_%d arrTrend_%d  ",tTable.sTableName,tData.sTableId,tTable.nGroupId,#tTable.arrTrend)    
    return 
end

-- 重启 请求场景
function PublicGameScence._RebootTable(sReturnKey,sTableId)       
    local BJLCScenceReq = {}   -- 请求创建 
    BJLCScenceReq.sTableId = sTableId  
	local tPacket =BaiJiaLeAux:Encode("BJLCScenceReq",BJLCScenceReq)
	tBase.PostToClient(sReturnKey, tPacket:GetData(), tPacket:GetSize())
    tBase.Log("_RebootTable  sTableId: %s  场景恢复请求: %s  ",sTableId,sReturnKey)    
    return 
end 


-- 自动下注逻辑 

-- 开始自动下注
function PublicGameScence._StartAutoBet(tTable)  
    if tTable.isPassWordRoom then   -- 不显示密码房
        tBase.Log("_StartAutoBet [%s=%s] 密码房 不运行自动下注",tTable.sTableName,tTable.sTableId)    
        return 
    end 

    local sStr = string.format("nGroupId_%d",tTable.nGroupId) 
    local isRunAutoBet = true 
    if not tTable.isAutoBet then   
        sStr = string.format("%s isAutoBet is false",sStr)  
        isRunAutoBet = false
    end  
    if tTable.tGoodTrend.nType and tTable.tGoodTrend.nType > 0 and tTable.tGoodTrend.nBetArea >= 0 then 
        sStr = string.format("%s 好路[%d/%d] ",sStr,tTable.tGoodTrend.nType,tTable.tGoodTrend.nBetArea)  
    else                
        isRunAutoBet = false
        sStr = string.format("%s 无好路 ",sStr,tTable.tGoodTrend.nType,tTable.tGoodTrend.nBetArea)                                     
    end 
    if isRunAutoBet then  
        if tTable.isGameMiantian then    
            isRunAutoBet = false  
            sStr = string.format("%s   游戏服维护中",sStr)  
        end 
        if tTable.isLobbyMiantian then 
            isRunAutoBet = false  
            sStr = string.format("%s   大厅服维护中",sStr)   
        end 
        if isRunAutoBet then              
            sStr = string.format("%s 运行自动下注",sStr) 
        end 
    end    
    local function _IsStopServerMaintaining()               
        if tTable.sLobbyKey ~= tBase.m_tKey then  
            return false 
        end    
        if not PublicUserInfo.IsMaintaining(tTable.nGroupId) then 
            return false 
        end 
        local arrUserId = _GetTableUserId(tTable.sTableId)
        if not arrUserId or #arrUserId == 0 then  
            return false 
        end                     
        local arrId = {}
        for k, v in ipairs(arrUserId) do
            PublicRedis.StopRecord(v.nUserId,7)     -- 停服维护,暂停 
            table.insert(arrId, v.nUserId)
        end        
        tBase.Log("_IsStopServerMaintaining [%s=%s] 停机维护,停止运行自动下注_%s ",tTable.sTableName,tTable.sTableId,cjson.encode(arrId))    
        return true   
    end        
    -- 停机维护
    if _IsStopServerMaintaining() then 
        tBase.Log("_StartAutoBet [%s=%s] 停机维护 ",tTable.sTableName,tTable.sTableId)   
        return
    end 

    if _IsServerIdMainTain(tSrvInfo.nServerId) then  
        isRunAutoBet = false  
        sStr = string.format("%s  %d 该服正在维护了,不进行自动下注",sStr,tSrvInfo.nServerId)   
    end 
    if isRunAutoBet then                  
        tBase.Log("_StartAutoBet [%s=%s] %s ",tTable.sTableName,tTable.sTableId,sStr)                 
        PublicLiveAutoBet.CheckAutoBet(tTable)   
    else
        tBase.Log("_StartAutoBet [%s=%s] %s ",tTable.sTableName,tTable.sTableId,sStr)     
    end  
    return
end
 
--  写入自动下注记录
function PublicGameScence._WriteAutoBetRecord(tTable,nGoodTrendType,nGoodTrendArea,sLog)
    if tTable.isPassWordRoom then   -- 不显示密码房
        -- tBase.Log("_WriteAutoBetRecord [%s=%s] 密码房 不写入自动下注记录",tTable.sTableName,tTable.sTableId)    
        return 
    end 
    PublicLiveAutoBet._WriteAutoBetRecord(tTable,nGoodTrendType,nGoodTrendArea,sLog)     
end 
   

-- 百家乐 路纸选台操作

--游戏服<->前端协议
local pb_Slave =ProtoMgr.BaiJiaLeSlave_pb
local CMD_Slave =ProtoMgr.BaiJiaLeSlave_pb.BJLS_Proto()
local ToCMD_Slave =function(strProto)
  return CMD_Slave.Main_CMD,CMD_Slave[strProto..'_CMD']
end
SlaveAux =ProtoAux:New(pb_Slave,ToCMD_Slave)  

local function _GetOpenMenuUser(nGroupId)
    local arrUser = PublicGameScence.OpenMenuUser[nGroupId] or {}
    local arrOpenMenuUser = {}
    local arrUserId = {}
    for nUserId,v in pairs(arrUser) do 
        if v then  
            table.insert(arrOpenMenuUser,v) 
        end
    end
    return arrOpenMenuUser
end


--网络协议发送(发给前端)
local function SendToClient(sClientID,strProto,tSendData)
    local tPacket =SlaveAux:Encode(strProto,tSendData)
    tBase.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize())
end

-- 广播打开路纸用户
local function _BroadCastOpenMuneUser(sTableId,nGroupId,strProto,tData)
    local tTable = _GetTable(sTableId) 
    if not tTable then 
        tBase.Log("_BroadCastOpenMuneUser   tTable is nil sTableId_%s strProto_%s ",sTableId,strProto)     
        return 
    end 
    if tTable.isPassWordRoom then return end 
    local arrOpenMenuUser = _GetOpenMenuUser(nGroupId)
    if #arrOpenMenuUser == 0 then return end     
    local nCnt = 0
    for _,v in ipairs(arrOpenMenuUser) do             
        local isAdd = true  
        if v.nVoiceRoom == 1 then 
            if not tTable.isVoiceRoom then   
                isAdd =false                         
            end
        else
            if tTable.isVoiceRoom then 
                isAdd =false                 
            end
        end 
        if isAdd then
            SendToClient(v.sClientID,strProto,tData) 
            nCnt = nCnt + 1 
        end
    end
    -- tBase.Log("_BroadCastOpenMuneUser  sTableId_%s  nGroupId_%d Cnt_%d %s ",sTableId,nGroupId,nCnt,strProto)
end

-- 获取 牌桌路纸数据
local function GetProtoMenuItem(tTable) 
	local Item ={}
	Item.sTableId=tTable.sTableId			--桌子id(唯一标识)
	Item.sTableName=tTable.sTableName		--桌子名称
	Item.nStageSeconds=tTable.DurationTime_BetStage		--下注阶段总时间   
	Item.nRemainSeconds=0								--当前下注阶段剩余时间 (0时为非下注阶段)
	if tTable.nStage ==TableState.nBet then
		Item.nRemainSeconds =tTable.nStageEndTime-os.time()
		Item.nRemainSeconds =math.max(0,Item.nRemainSeconds)
	end
	if tTable.nStage ==TableState.nFault then
		Item.nIsFault=1
	end
	Item.nUserCnt=tTable.nUserCntOfSum or 0 		--当前人数
	Item.arrTrend=tTable.arrTrend or {}         	--走势图
	Item.arrPredict={}
	Item.sLiveID =tTable.sLiveID				--第三方app需要信息(直播间id)
	Item.sPlatformID =tTable.sPlatformID		--第三方app需要信息(app方主播id)
	Item.nTableType =  tTable.nTableType		--桌子类型
    local nGoodTrendType = tTable.tGoodTrend.nType or 0
	Item.nGoodTrendType = nGoodTrendType
	Item.sLiveName=tTable.sLiveName or ""
	return Item
end

-- 打开/关闭 路纸选台
function PublicGameScence.OpenMenuUserhandle(sReturnKey,Data,nLen) 
    local ReadData = tBase.GetRP().new(Data, nLen)
    local MainID = ReadData:GetModuleID()
    local SubID = ReadData:GetMsgID()
    local nHandle = ReadData:GetInt32()
    local nUserId = ReadData:GetInt32()
    local nGroupId = ReadData:GetInt32()
    local sClientID = ReadData:GetString() 
    local nVoiceRoom = ReadData:GetByte()
    if nHandle== 1 then -- 打开路纸
        if not PublicGameScence.OpenMenuUser[nGroupId] then 
            PublicGameScence.OpenMenuUser[nGroupId]={}            
        end 
        PublicGameScence.OpenMenuUser[nGroupId][nUserId]={sClientID=sClientID,nVoiceRoom=nVoiceRoom}    

        local arrTable =_GetGroupTable(nGroupId)
        local function tem(a,b)
           return a.sTableName<b.sTableName
        end
        table.sort(arrTable,tem)        
        local arrItem ={}
        for sTableId,tTable in pairs(arrTable) do           
            local isAdd = true 
            if tTable.isPassWordRoom then   -- 不显示密码房
                isAdd =false  
            end 
            if tTable.isCopyTable then      -- 不显示副桌
                isAdd =false  
            end 
            if isAdd then 
                if nVoiceRoom == 1 then 
                    if not tTable.isVoiceRoom then   
                        isAdd =false                         
                    end
                else
                    if tTable.isVoiceRoom then 
                        isAdd =false                 
                    end
                end 
            end 
            if isAdd then 
                local tItem = GetProtoMenuItem(tTable)
                table.insert(arrItem,tItem)                             
            end
        end
        tBase.Log("_OpenMenuUserhandle  nUserId_%d  nGroupId_%d   打开路纸选台  arrItem_%d ",nUserId,nGroupId,#arrItem)   
        local arrTem ={}
        for dex,item in ipairs(arrItem) do
            table.insert(arrTem,item)
            if dex%5==0 or dex ==#arrItem then
                local  OpenMenuRsp={}
                OpenMenuRsp.arrItem=arrTem				
                OpenMenuRsp.nCntOfAll=#arrItem	    	--所有桌子条目数量
                OpenMenuRsp.nCntOfRsp=dex				--当前已发出的桌子条目数量
                SendToClient(sClientID,"OpenMenuRsp",OpenMenuRsp)
                arrTem ={}
            end
        end
    else
        tBase.Log("_OpenMenuUserhandle  nUserId_%d  nGroupId_%d   关闭路纸选台  ",nUserId,nUserId)
        if PublicGameScence.OpenMenuUser[nGroupId] and PublicGameScence.OpenMenuUser[nGroupId][nUserId] then 
            PublicGameScence.OpenMenuUser[nGroupId][nUserId]=nil
        end 
    end 
    return
end 

--桌子进入下注阶段回调
function PublicGameScence.OnTableGoInBetStage(nGroupId,sTableId,nStageSeconds,sLiveID,sPlatformID,sLiveNickName)    
    local TableGoInBetStageNotify={}
    TableGoInBetStageNotify.sTableId =sTableId
    TableGoInBetStageNotify.nStageSeconds =nStageSeconds
    TableGoInBetStageNotify.sLiveID =sLiveID
    TableGoInBetStageNotify.sPlatformID =sPlatformID
    TableGoInBetStageNotify.sLiveName =sLiveNickName 
    _BroadCastOpenMuneUser(sTableId,nGroupId,"TableGoInBetStageNotify",TableGoInBetStageNotify)
    return 
end 

--桌子走势图变化回调
function PublicGameScence.OnTableTrendChange(nGroupId,sTableId,tTrendItem,nGoodTrendType)   
    local TrendChangeNotify ={}
    TrendChangeNotify.sTableId =sTableId
    TrendChangeNotify.tTrendItem =tTrendItem
    TrendChangeNotify.nGoodTrendType = nGoodTrendType or 0  
    _BroadCastOpenMuneUser(sTableId,nGroupId,"TrendChangeNotify",TrendChangeNotify)   
end

-- 人数通知
function PublicGameScence.OnTableUserCntChange(nGroupId,sTableId,nUserCnt)   
    _BroadCastOpenMuneUser(sTableId,nGroupId,"UserCntChangeNotify",{arrItem={{sTableId=sTableId,nUserCnt=nUserCnt}}})
end
 



return PublicGameScence