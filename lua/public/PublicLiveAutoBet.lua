--俱乐部公用接口
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path
package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path
package.path = "../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" .. package.path

local tBase = require("base")
local cjson = require("cjson")
local ProtoMgr = require("ProtoManager")
local ProtoAux = require("ProtoCoder").Aux
local typename = require("typename") 
local RecordDbr =require("RecordDbr") --记录类
local tReforwardRule  =require("ReforwardRule") 
local tConfig =require("GameConfig") -- 
 


--百家乐中心服协议
local pb_Center =ProtoMgr.BaiJiaLeCenter_pb
local CMD_Center =ProtoMgr.BaiJiaLeCenter_pb.BJLC_Proto()
local ToCMD_Center =function(strProto)
  return CMD_Center.Main_CMD,CMD_Center[strProto..'_CMD']
end

--生成个编解码辅助对象
BaiJiaLeAux =ProtoAux:New(pb_Center,ToCMD_Center)


local PublicLiveAutoBet = { 

}
   
-- 自动下注逻辑 

local function _GetTable(sTableId)   
    return PublicGameScence.arrGameTable[sTableId]
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

-- 是否主播用户
local function _IsLiveUser(nGroupId,nUserId)
    if not nGroupId or nGroupId <= 0 then 
        tBase.Log("_IsLiveUser  nUserId_%d nGroupId: %s  Error  nGroupId is nil ",nUserId," nGroupId: "..nGroupId)
        return false 
    end 
    local arrTable = _GetGroupTable(nGroupId) 
    for sTableId, tTable in pairs(arrTable) do
        if tTable and tTable.nLiveUserID > 0 and tTable.nLiveUserID == nUserId then 
            tBase.Log("_IsLiveUser  nUserId_%d nGroupId: %d sTableId: %s ",nUserId,nGroupId,sTableId)
            return true 
        end 
    end
    return false
end 
 
-- 获取用户数据
local function _AutoBet_GetUserInfo(nUserId)
    local tUserInfo = PublicUserInfo.GetUserInfo(nUserId) 
    if not tUserInfo then 
        PublicLiveAutoBet._LoadUserInfo(nUserId)  
        tBase.Log("_AutoBet_GetUserInfo  nUserId_%d   tUserInfo is nil  ",nUserId or -1)
        return nil
    end 
    tUserInfo.nGold = PublicUserInfo.Get_User_Gold(nUserId)
    if not tUserInfo.nGold then  
        PublicLiveAutoBet._LoadUserInfo(nUserId)  
        tBase.Log("_AutoBet_GetUserInfo   nUserId_%d   nGold is nil tUserInfo:%s ",nUserId or -1,cjson.encode(tUserInfo))
        return nil
    end    
    if not tUserInfo.nShopID then  
        PublicLiveAutoBet._LoadUserInfo(nUserId)  
        tBase.Log("_AutoBet_GetUserInfo   nUserId_%d   nShopID is nil ",nUserId or -1)
        return nil
    end        
    if not tUserInfo.nGroupId then  
        tBase.Log("_AutoBet_GetUserInfo   nUserId_%d   nGroupId is nil ",nUserId or -1)
        local nShopID =  tonumber(tUserInfo.nShopID) or -1   
        local nGroupId = tConfig.GetGroupId(nShopID)
        if nShopID<0 or nGroupId<0 then
            PublicLiveAutoBet._LoadUserInfo(nUserId)  
            tBase.Log("_AutoBet_GetUserInfo nUserId_%d  nShopID_%d nGroupId_%d  小于 0  ",nUserId,nShopID,nGroupId)
            return nil 
        end        
        PublicUserInfo._SetUser_GroupId(nUserId,nGroupId)
        tUserInfo.nGroupId =nGroupId
    end  
    tBase.Log("_AutoBet_GetUserInfo nUserId_%d  nShopID_%d nGroupId_%d    ",nUserId,tonumber(tUserInfo.nShopID),tonumber(tUserInfo.nGroupId))
    return tUserInfo   
end 

-- 是否 好路连赢
local function _IsGoodThreadLinkWin(nUserId,sTableId,nGTType,tStatistics,sPaiJuId,sTableName) 
    nGTType = string.format("%d",nGTType)
    local arrLinkWin = tStatistics.arrGoodThreadWin[sTableId] 
    if arrLinkWin then  
        local tLinkWin = arrLinkWin[nGTType]
        if tLinkWin and tLinkWin.nLinkWin and tLinkWin.isStop then 	
            PublicRedis.PauseByWinStraightRecord(nUserId,{nTrendType=tonumber(nGTType),sPaiJuId=sPaiJuId,sTableName=sTableName})  -- 通知记录
            return true 
        end 
    end  
    return false  
end

-- 是否 桌台连输 
local function _IsTableLinkLose(nUserId,sTableId,tStatistics,sPaiJuId,sTableName)
    local tTableLinkLose = tStatistics.arrTableLinkLose[sTableId] 
    if tTableLinkLose  then 
        local nPauseTime = tonumber(tTableLinkLose.nPauseTime)
        if nPauseTime > 0 then 
            local nStopTime = 60 * 30   -- 暂停30分钟
            if nPauseTime + nStopTime > os.time() then   -- 暂停30 分钟                
                return true 
            end 
        end 
    end     
    return false  
end

-- 是否 达到 亏损/盈利 
local function _IsLoseWinReact(nUserId,cfg)
    local nLossLimit = tonumber(cfg.nLossLimit)      --亏损>x 时停止下注				(<0为无效)
    local nProfitLimit = tonumber(cfg.nProfitLimit)  --盈利>x 时停止追注				(<0为无效)     
    local nUserLoseWin =  0  -- 用户当前输赢情况
    if nUserLoseWin == 0 then 
        return false 
    end 
    if math.abs(nUserLoseWin) >= nProfitLimit or math.abs(nUserLoseWin) >= nLossLimit then 
        return true 
    end  
    return false    
end

-- 获取 自动下注配置
local function _GetAutoBetData(nUserId,tBetInfo,sTableId,tGoodTrend,sPaiJuId,sTableName)      
    if not tBetInfo then return false,1,"无配置"end   
    if tBetInfo.nStopTimestamp >0 and tonumber(tBetInfo.nStopTimestamp) < os.time() then return false,1," nStopTimestamp is stop" end 
    if not tBetInfo.nBet or tonumber(tBetInfo.nBet) <= 0 then return false,2," nBet error" end 
    if tonumber(tBetInfo.nProfitLimit) <= 0 then return false,3,"nProfitLimit < 0" end 

	local nLossLimit = tonumber(tBetInfo.nLossLimit) 			--亏损>x 时停止追注				(<0为无效)
	local nProfitLimit = tonumber(tBetInfo.nProfitLimit)			--盈利>x 时停止追注				(<0为无效)        
	local nProfit = PublicRedis._GetIncrProfit(nUserId)  -- 当前盈利情况
    if math.abs(nProfit) >= nLossLimit then 
        return false,4, " nLossLimit: "..nLossLimit .." < nProfit:  "..nProfit
    end 
    if nProfit >= nProfitLimit then 
        return false,4, " nProfitLimit: "..nProfitLimit .." < nProfit:  "..nProfit
    end 
    if not tBetInfo.arrTableId or #tBetInfo.arrTableId == 0 then return false,5,"arrTableId is not " end  
    if not tBetInfo.arrTrendType or #tBetInfo.arrTrendType == 0 then return false,7,"arrTrendType is nil" end 
    local isSuccee = false  -- 是否 选择该牌桌 
    for _, id in pairs(tBetInfo.arrTableId) do
        if id == sTableId then 
            isSuccee = true 
        end 
    end
    if not isSuccee then return false,8,"没选该牌桌" end 
    local isSuccee = false -- 是否 选择好路 
    for _, id in pairs(tBetInfo.arrTrendType) do
        if id == tGoodTrend.nType then 
            isSuccee = true 
        end 
    end
    if not isSuccee then return false,9,"不符合好路" end 

    -- 以下 满足条件 停止本次下注任务  
	local tStatistics = PublicRedis.GetUserAutoBetStatistics(nUserId)   -- 自动下注统计数据 
    if not tStatistics then 
        return false,14,"没有统计数据"
    end     
    local tBetMultiple = PublicRedis._Handle_AutoBet_BetMultiple(4,nUserId,{sTableId=sTableId})
    if not tBetMultiple or not tBetMultiple.nMultiple then  
        tBase.Log("_GetAutoBetData  nUserId_%d sTableId: %s  nMultiple is nil  arrTableMultiple: %s ",nUserId,sTableId,cjson.encode(tBetMultiple or -1))    
        return false,11,"该牌桌无配置" 
    end 
    -- 是否 该牌桌 连输
    if _IsTableLinkLose(nUserId,sTableId,tStatistics,sPaiJuId,sTableName) then 
        return false,10,"连输"
    end     
    -- 是否 某个牌桌  好路连赢 
    if _IsGoodThreadLinkWin(nUserId,sTableId,tGoodTrend.nType,tStatistics,sPaiJuId,sTableName) then         
        return false,11,"连赢"
    end 
    -- 停止运行时间
    if tBetInfo.nStopTimestamp <= os.time() then 
        return false,12,"停止运行时间"
    end 
    local tUserInfo = _AutoBet_GetUserInfo(nUserId)
    if not tUserInfo then  
        return false,13,"没有用户数据,需要加载 nUserId: "..nUserId 
    end  
    local nGold = PublicUserInfo.Get_User_Gold(nUserId,1)     
    if _IsLiveUser(tonumber(tUserInfo.nGroupId),nUserId) then 
        PublicRedis.StopRecord(nUserId,8)
        return false,13,nUserId.." 是主播,停止自动下注"
    end     
    local nMultiple = tonumber(tBetMultiple.nMultiple)  -- 下注倍数 
    local nBet = nMultiple * tonumber(tBetInfo.nBet)
    if nBet > nGold then 
        tBase.Log("_GetAutoBetData  nUserId_%d   nGold_%.1f nBet_%d [%d %d ]  金币不足",nUserId,nGold,nBet,nMultiple,tonumber(tBetInfo.nBet))           
		PublicRedis.StopRecord(nUserId,6)
        return false,13,"金币不足"
    end     
    local tBet = {}
    tBet.nBetChip = tonumber(tBetInfo.nBet)
    tBet.nBetArea = tGoodTrend.nBetArea 
    tBet.nMultiple = nMultiple    
    tBase.Log("_GetAutoBetData_%s nUserId_%d nGroupId_%d tBet: %s  nMultiple: %s "
    ,sTableName,nUserId,tUserInfo.nGroupId,cjson.encode(tBet),cjson.encode(nMultiple))   

    return true,tBet,""
end     

local function _GetGameServerKey(nUserId,arrSerIdToKey)    
    local nId = nUserId % (#arrSerIdToKey) + 1
    local sGameServerKey = arrSerIdToKey[nId] or arrSerIdToKey[1] 
    return sGameServerKey      
end

-- 获取相应的转发服务器KEY
local function _GetDispatchKey(nUserId,nGroupId,sTableId,arrSerIdToKey) 
    local stypename = typename.BaiJiaLeSlave
    local nCenterServId =tonumber(string.match(sTableId,"(%d+)#"))  
    local arrTypenameServList =tBase._GetTypenameAllKey(stypename) 
    local arr={}
    for _, sKey in pairs(arrTypenameServList) do 
        for _, v in pairs(arrSerIdToKey) do
            if v == sKey then 
                table.insert(arr,sKey) 
            end 
        end        
    end
    if #arr == 0 then 
        -- tBase.Log("_GetGameServerKey  nUserId_%d  不符合 nGroupId_%d_%d  stypename: %s=%d arrTypenameServList: %s   arrSerIdToKey_%s" 
        -- ,nUserId,nGroupId,nCenterServId,stypename,#arrTypenameServList,cjson.encode(arrTypenameServList) or "0" ,cjson.encode(arrSerIdToKey) or "0" )  

        -- tBase.Log("_GetGameServerKey  arrTypenameServList: %s  " ,cjson.encode(arrTypenameServList) or "0")  
        -- tBase.Log("_GetGameServerKey  arrSerIdToKey_%s" ,cjson.encode(arrSerIdToKey) or "0" )  
        
    end  
    local arrKey =tReforwardRule.ServerIdFilter(arr)     
    local sKey = tReforwardRule.PickAServKey(arrKey,nGroupId,nCenterServId,nUserId,stypename)  
    if not sKey then 
        sKey =_GetGameServerKey(nUserId,arrSerIdToKey)   
        -- tBase.Log("_GetGameServerKey  nUserId_%d 规则没有，随机指定  nGroupId_%d nCenterServId_%d stypename: %s=%d  arr_%d  arrSerIdToKey_%d arrKey_%d  sKey: %s"
        -- ,nUserId,nGroupId,nCenterServId,stypename,#arrTypenameServList,#arr,#arrSerIdToKey,#arrKey,sKey)   
    else
        -- tBase.Log("_GetGameServerKey  nUserId_%d  规则中 sKey: %s",nUserId,sKey)   
    end 
    return sKey..":0"
end

-- 获取任务牌桌 id 
local function _GetTableUserId(sTableId)
    local arr = PublicRedis.GetTableAllCfg(sTableId) 
    return arr
end
 
-- 执行自动下注 
function PublicLiveAutoBet.CheckAutoBet(tTable)   
    -- 先待定：也可以由 游戏 进行指定 大厅服进行处理(如同机器人的)  
    local CMD_Backstage =ProtoMgr.Backstage_pb.Backstage_Proto()
    local sTableId = tTable.sTableId    
    local sTableName = tTable.sTableName
    local sPaiJuId = tTable.sPaiJuId
    if tTable.sLobbyKey ~= tBase.m_tKey then 
        -- tBase.Log("_CheckAutoBet  不运行 %s/%s m_tKey_%s  sLobbyKey_%s",sTableName,sTableId,tBase.m_tKey,tTable.sLobbyKey)  
        return 
    end     
    if #tTable.arrSerIdToKey == 0 then 
        tBase.Log("_CheckAutoBet  [%s/%s] arrSerIdToKey_%d  没有游戏服key  ",sTableName,sTableId,#tTable.arrSerIdToKey)   
        return 
    end        
    local arrSerIdToKey={}
    for _, v in ipairs(tTable.arrSerIdToKey) do
        local tVal = publicApi.Split(v,":") 
        table.insert(arrSerIdToKey,tVal[1])        
    end
    local nGroupId = tTable.nGroupId
    -- 多服 进行分压  
    local arrUserId = _GetTableUserId(sTableId)
    if not arrUserId or #arrUserId == 0 then 
        -- tBase.Log("_CheckAutoBet   [%s=%s]  无人设置自动下注任务 ",sTableName,sTableId)  
        return 
    end       
    local arrServer = {}
    for k, v in ipairs(arrUserId) do
        local nUserId = v.nUserId
        local tCfg = v.tCfg
        if tTable.nLiveUserID ~= nUserId then 
            local isSuccess,tBet,sStr = _GetAutoBetData(nUserId,tCfg,sTableId,tTable.tGoodTrend,sPaiJuId,sTableName)
            if isSuccess and tBet then  
                local sGameServerKey = _GetDispatchKey(nUserId,nGroupId,sTableId,arrSerIdToKey)
                if not sGameServerKey then 
                    tBase.Log("_CheckAutoBet  nUserId_%d   sGameServerKey  ",nUserId)   
                    return
                end                  
                local Send = {}
                Send.nUserId = nUserId
                Send.nBetChip = tBet.nBetChip
                Send.nBetArea = tBet.nBetArea
                Send.nMultiple = tBet.nMultiple               
                if not arrServer[sGameServerKey] then 
                    arrServer[sGameServerKey] = {}
                end 
                table.insert(arrServer[sGameServerKey],Send) 
                tTable.arrUserAutoBet[nUserId]={nUserId=nUserId,nBetChip=tBet.nBetChip,nBetArea=tBet.nBetArea,nMultiple=tBet.nMultiple,isSuccess=false}
            else 
                --停止运行记录 
                tBase.Log("_CheckAutoBet [%s=%s] nUserId_%d  不进行自动下注_%d  %s ",sTableName,sTableId,nUserId,tBet,sStr or "")                    
                if (tBet >= 8 and tBet <= 11) then   -- 暂停 

                end 
                if tBet == 9 then 
                    PublicRedis._ResetAutoBetStatistics(nUserId,sTableId,1)   -- 重置连赢
                end  
            end 
        else 
            tBase.Log("_CheckAutoBet [%s=%s] nUserId_%d 主播不进行自动下注_%d ",sTableName,sTableId,nUserId,tTable.tGoodTrend.nBetArea)   
        end 
    end
    local arr ={}
    local Send = ProtoMgr.Backstage_pb.UserAutoBetReq()
    Send.sTableId = sTableId  
    for sGameServerKey,arrAutoBet in pairs(arrServer) do 
        if #arrAutoBet > 150 then 
            for k, v in ipairs(arrAutoBet) do
                table.insert(arr,v)
                if #arr >= 150 or k == #arrAutoBet then 
                    Send.sAutoBetUser= cjson.encode(arr)    
                    local s = tBase.GetSP().new(CMD_Backstage.Main_CMD,CMD_Backstage.UserAutoBetReq_CMD)
                    s:AddString(Send:SerializeToString())        
                    tBase.PostToGateway(sGameServerKey, s:GetData(), s:GetSize()) 
                    arr={}
                    tBase.Log("_CheckAutoBet arrAutoBet_%d  %d %d  ",#arrAutoBet,k,#arr)  
                end 
            end             
        else
            Send.sAutoBetUser= cjson.encode(arrAutoBet)    
            local s = tBase.GetSP().new(CMD_Backstage.Main_CMD,CMD_Backstage.UserAutoBetReq_CMD)
            s:AddString(Send:SerializeToString())        
            tBase.PostToGateway(sGameServerKey, s:GetData(), s:GetSize())                 
        end         
    end
    return 
end

--  写入自动下注记录
function PublicLiveAutoBet._WriteAutoBetRecord(tTable,nGoodTrendType,nGoodTrendArea,sLog)
    local tResultsOfCardOpen = tTable.tResultsOfCardOpen 
    local nPointXian = tResultsOfCardOpen.nPointXian
    local nPointZhuang = tResultsOfCardOpen.nPointZhuang     
    local nCnt = 0  
    local tRecord = {}
    tRecord.nXianD= nPointXian                 --闲家点数
    tRecord.nZhuangD=nPointZhuang              --庄家点数       
    tRecord.sPaiJuId=tTable.sPaiJuId           --牌局id
    tRecord.sTableName=tTable.sTableName       --桌子名称
    tRecord.nTrendType= nGoodTrendType         --好路类型
    
	for nUserId, v in pairs(tTable.arrUserAutoBet) do	
        if v.isSucess then 
            local nBet = v.nBetChip * v.nMultiple
            local nLoseWin =0 
            local sStr = "和了"		
            if tResultsOfCardOpen.nResult ~= 0 then  
                if tResultsOfCardOpen.nResult == v.nBetArea then 
                    nLoseWin = nBet
                    sStr = "赢了"	
                else
                    nLoseWin = -nBet
                    sStr = "输了"	
                end 
            end  
            if tResultsOfCardOpen.nResult == 2 and nLoseWin > 0 then 
                nLoseWin = nLoseWin * 0.95
            end 
            tBase.Log("_WriteAutoBetRecord [%s=%s] sPaiJuId_%s nUserId:%d  【%s/%d = %.1f %s %s 】 好路_%d"
            ,tTable.sTableName,tTable.sTableId,tTable.sPaiJuId,nUserId,v.nBetArea,nBet,nLoseWin,sStr,sLog,nGoodTrendType or -1)  
            nCnt = nCnt + 1     
            --各字段分别为:桌子id,局号,闲点数,庄点数,盈利
            local tD={sTableId=tTable.sTableId,sTableName=tTable.sTableName,sPaiJuId=tTable.sPaiJuId,nXianDian=nPointXian,nZhuangDian=nPointZhuang,nProfit=nLoseWin}	
            PublicRedis.SettleRecord(nUserId,tD)	
        
            tRecord.nUserId=nUserId                       --玩家id    
            tRecord.nBetArea=v.nBetArea or -1             --下注区域
            tRecord.nBetGold= nBet or 0                   --下注金币 
            tRecord.nProfit=nLoseWin or 0                 --盈利
            local nGold = PublicUserInfo.Get_User_Gold(nUserId,1) 
            tRecord.nBalanceAfter=nGold or 0              --本结算后的余额 
            RecordDbr.BJLAutoBetRecord(tRecord)

            if nLoseWin ~= 0 then -- 更新统计数据 
                PublicLiveAutoBet.UpdateAutoBetStatistics(nUserId,tTable.sTableId,nLoseWin,tTable.tGoodTrend.nType or 0,tTable.sTableName,tTable.sPaiJuId) 
            end 
        end 
	end  
    tTable.arrUserAutoBet = {} 

    if tTable.isGameMiantian or tTable.isLobbyMiantian then                 
        return 
    end 
    if nGoodTrendType > 0 then      
        local nTrend,sStr = 0,"逆路"      
        if nGoodTrendArea == tResultsOfCardOpen.nResult then 
            nTrend = 1 
            sStr="顺路"
        end         
        -- tBase.Log("_WriteAutoBetRecord [%s=%s] 遗漏_%s %s 好路[%d %d] [%d/%s]",tTable.sTableName,tTable.sTableId,tTable.sPaiJuId,sLog,nGoodTrendType,nGoodTrendArea,nTrend,sStr)           
        local tLeaveOut = {}
        tLeaveOut.nXianD= nPointXian                 --闲家点数
        tLeaveOut.nZhuangD=nPointZhuang              --庄家点数       
        tLeaveOut.sPaiJuId=tTable.sPaiJuId           --牌局id
        tLeaveOut.sTableName=tTable.sTableName       --桌子名称
        tLeaveOut.nTrendType= nGoodTrendType         --好路类型
        tLeaveOut.STableId= tTable.sTableId          --好路类型  
        tLeaveOut.nGroupId= tTable.nGroupId          --好路类型  
        tLeaveOut.nTrend  =  nTrend                  --1:顺路 0:逆路      

        if tTable.sLobbyKey == tBase.m_tKey then 
            RecordDbr.BJLGTSettleRecord(tLeaveOut)       -- 遗漏 
        end
    end 
    -- tBase.Log("_WriteAutoBetRecord [%s=%s]  %s 自动下注记录 %s  庄闲点数: [%d %d] ",tTable.sTableName,tTable.sTableId,sLog,nCnt,nPointZhuang,nPointXian)  	
    return 
end 
 

-- 重启 场景恢复
function PublicLiveAutoBet._RebootTable(sReturnKey,sTableId)       
    local BJLCScenceReq = {}   -- 请求创建 
    BJLCScenceReq.sTableId = sTableId  
	local tPacket =BaiJiaLeAux:Encode("BJLCScenceReq",BJLCScenceReq)
	tBase.PostToClient(sReturnKey, tPacket:GetData(), tPacket:GetSize())
    tBase.Log("_RebootTable  sTableId: %s  场景恢复请求: %s  ",sTableId,sReturnKey)    
    return 
end 

-- 只能在大厅服 运行


-- 自动下注结果回复
function PublicLiveAutoBet.UserAutoBetRsp(sReturnKey,Data,nLen)
    local s = tBase.GetRP().new(Data, nLen)
    local nMainID = s:GetModuleID() 
    local nSubID = s:GetMsgID()
    local tRead = ProtoMgr.Backstage_pb.UserAutoBetRsp()
    tRead:ParseFromString(s:GetString()) 
    local nUserId = tRead.nUserId
    local sTableId = tRead.sTableId
    local nResult = tRead.nResult     
    local tTable = _GetTable(sTableId) 
    if not tTable then 
        tBase.Log("_UserAutoBetRsp  %s  tTable is nil %d  ",sTableId,nUserId)     
        return 
    end          
    local tBet = tTable.arrUserAutoBet[nUserId]
    if not tBet then 
        tBase.Log("_UserAutoBetRsp [%s=%s] nUserId_%d  没有自动下注",tTable.sTableName,tTable.sTableId,nUserId)        
        return 
    end 
    local sLog = "失败"
    if nResult == 1 then  --各字段分别为:桌子id,局号,好路类型,下注区域,下注金币        
        local nMultiple = tRead.nMultiple or 1  -- 下注倍数
        local tD ={sTableId=tTable.sTableId,sTableName=tTable.sTableName,sPaiJuId=tTable.sPaiJuId,nTrendType=tTable.tGoodTrend.nType or 0,nBetArea=tBet.nBetArea,nBetGold=tBet.nBetChip *nMultiple}
        PublicRedis.AutoBetRecord(nUserId,tD)	
        tTable.arrUserAutoBet[nUserId].isSucess = true        
        sLog = "成功" 
    end          
    tBase.Log("_UserAutoBetRsp [%s=%s] nUserId_%d  自动下注 %s",tTable.sTableName,tTable.sTableId,nUserId,sLog)           
    return 
end


-- 重启 加载 用户数据 
function PublicLiveAutoBet._ReBoostLoadUserInfo()  
	if tBase.m_tKey ~= tBase.m_arrServerList[typename.lobby][1] then
        -- tBase.Log("_ReBoostLoadUserInfo   此线程不处理 ")  
        return  
    end  

    -- 获取运行自动下注 任务id  
    local arr = {}
    local arrUserId = PublicRedis.GetAutoBetUsers()
    for _, nUserId in ipairs(arrUserId) do
        local tUserInfo = PublicUserInfo.GetUserInfo(nUserId) 
        if not tUserInfo or not tUserInfo.nGold then 
            PublicLiveAutoBet._LoadUserInfo(nUserId) 
            table.insert(arr,nUserId)  
        end      
    end 
    tBase.Log("_ReBoostLoadUserInfo    加载用户数据  %s  ",cjson.encode(arr))         
    return 
end 

-- 加载用户数据 
function PublicLiveAutoBet._LoadUserInfo(nUserId)     
    local sKey = tBase.GetUserIdSrcKey(typename.db,nUserId)
    if not sKey then          
        sKey = tBase.GetSrcKey(typename.db,nUserId)
    end       
    local Send = ProtoMgr.PubProto_pb.AutoBetLoadUserInfoReq() 
    Send.nUserId   = nUserId 
    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.AutoBetLoadUserInfoReq)  
    s:AddString(Send:SerializeToString()) 
    tBase.PostToServer(sKey,0,s:GetData(), s:GetSize()) --转发消息到内网   
    return 
end 

function PublicLiveAutoBet.AutoBetLoadUserInfoRep(sReturnKey,Data,nLen) 
    local ReadData = tBase.GetRP().new(Data, nLen)  
    local Read = ProtoMgr.PubProto_pb.AutoBetLoadUserInfoRep()
    Read:ParseFromString(ReadData:GetString())   
    tBase.Log("_AutoBetLoadUserInfoRep   nUserId_%d nResult_%d ",Read.nUserId,Read.nResult)  
    return 
end 
 
-- 计算下局的 下注倍数
local function _ComputeBetMultiple(cfg,arrWinLoseRecord,nWinLose) 
    local nMultiple = 1
    local nBetStrategy= cfg.nBetStrategy or 1 
    local arrMulti= cfg.arrMulti 
    local nLen = #cfg.arrMulti or 1    
    -- 赢顺序,输了重新顺序: 
    local tStrategy1 ={
        [2]=true,           --赢追模式
        [4]=true,           --鸡尾酒下注法
        [112]=true,
        [122]=true,
        [121]=true,
    }    

    -- 无论输赢，都按照顺序：211投注、212投注  
    local tStrategy2 ={
        [211]=true,
        [212]=true,
    }
    -- 输顺序,赢了重新顺序 
    local tStrategy3 ={
        [1]=true,           --输追模式
    }

    -- 赢顺序,输了重新顺序 (连续赢 倍数下完 才算一轮)
    if tStrategy1[nBetStrategy] then   
        if nWinLose > 0 then 
            table.insert(arrWinLoseRecord,nWinLose)
            if #arrWinLoseRecord >= nLen then 
                arrWinLoseRecord = {} 
            end           
        else
            arrWinLoseRecord = {} 
        end  
        local nIndex = #arrWinLoseRecord + 1
        nMultiple = arrMulti[nIndex] 
        return nMultiple,arrWinLoseRecord
    end 

    --  输顺序,赢了重新顺序 (连续赢 倍数下完 才算一轮)
    if tStrategy3[nBetStrategy] then    
        if nWinLose <= 0 then 
            table.insert(arrWinLoseRecord,nWinLose)
            if #arrWinLoseRecord >= nLen then 
                arrWinLoseRecord = {} 
            end             
        else
            arrWinLoseRecord = {} 
        end  
        local nIndex = #arrWinLoseRecord + 1
        nMultiple = arrMulti[nIndex] 
        return nMultiple,arrWinLoseRecord
    end 

    -- 天梯下注法: 连续输,倍数下完 才算一轮 
        -- 如果输，就按(1)(3)(6)(10)(15)顺序继续下注，下到15倍还是输，就从1倍重新开始；
        -- 如果赢，下一局就按(1)(3)(6)(10)(15)的逆推一级下注，赢到1倍还是赢，就从1重新开始（一直赢就一直1倍）
    if nBetStrategy == 5 then 
        if nWinLose <= 0 then 
            table.insert(arrWinLoseRecord,nWinLose)
            if #arrWinLoseRecord >= nLen  then 
                arrWinLoseRecord = {} 
            end           
        else
            if #arrWinLoseRecord ~= 0 then 
                table.remove(arrWinLoseRecord)
            else
                arrWinLoseRecord = {} 
            end 
        end    
        local nIndex = #arrWinLoseRecord + 1        
        nMultiple = arrMulti[nIndex] or -1
        return nMultiple,arrWinLoseRecord
    end 

    -- 以下固定 局数 为一轮 

    -- 无论输赢，都按照顺序：  211投注、212投注
    if tStrategy2[nBetStrategy] then         
        table.insert(arrWinLoseRecord,nWinLose)
        local nIndex = #arrWinLoseRecord + 1
        if #arrWinLoseRecord >= nLen then 
            arrWinLoseRecord = {}
            nIndex =1 
        end 
        if nIndex > nLen then 
            nIndex = 1
        end 
        nMultiple = arrMulti[nIndex] 
        return nMultiple,arrWinLoseRecord
    end 
    -- 五局八星投 策略: 五局一个周期 赢按顺序下注，输，重新开始按顺序下注，当本轮出现输2局时，本轮后续下注全部改为1倍。无论下注到哪个顺序，5局后开始新的一轮
    if nBetStrategy >= 6 and nBetStrategy <= 14 then         
        table.insert(arrWinLoseRecord,nWinLose)
        local nIndex = 1
        if #arrWinLoseRecord >= 5 then 
            arrWinLoseRecord = {}
            nIndex = 1 
        end 
        for k, v in ipairs(arrWinLoseRecord) do
            if v > 0 then 
                nIndex = nIndex + 1 
            else
                nIndex = 1
            end 
        end 
        if #arrWinLoseRecord >= 2 then 
            local nCnt = 0
            for _, v in ipairs(arrWinLoseRecord) do
                if v == 0 then 
                    nCnt = nCnt + 1
                    if nCnt >= 2 then 
                        break 
                    end
                end 
            end
            if nCnt >= 2 then 
                nMultiple = 1  
                return nMultiple,arrWinLoseRecord
            end            
        end  
        nMultiple = arrMulti[nIndex] or -1
        return nMultiple,arrWinLoseRecord
    end 
	return nMultiple,arrWinLoseRecord
end

-- 更新统计数据：   
function PublicLiveAutoBet.UpdateAutoBetStatistics(nUserId,sTableId,nLoseWin,nGTType,sTableName,sPaiJuId)  
	nGTType = string.format("%d",nGTType)
	local cfg = PublicRedis.GetUserAutoBetCfg(nUserId)
	if not cfg then 
		tBase.Log("_UpdateAutoBetStatistics  任务不存在了 nUserId_%d %s",nUserId,sTableId)
		PublicRedis._DelAutoBetStatistics(nUserId)	
		return 
	end  
	local nStopTime = 60 * 30   -- 暂停30分钟
	local nLossLimit = tonumber(cfg.nLossLimit) 			--亏损>x 时停止追注				(<0为无效)
	local nProfitLimit = tonumber(cfg.nProfitLimit)			--盈利>x 时停止追注				(<0为无效)
	local nWinSuccPause = tonumber(cfg.nWinSuccPause)		--好路连赢>x 次后暂停追注		(<0为无效)
	local nLossSuccPause = tonumber(cfg.nLossSuccPause) 	--桌台连输>x 次后暂停下注30分钟	(<0为无效) 
    -- 停止运行时间
    if tonumber(cfg.nStopTimestamp) <= os.time() then 
		tBase.Log("_UpdateAutoBetStatistics  时间到,停止 nUserId_%d [%s= %d] Now_%d ",nUserId,sTableId,cfg.nStopTimestamp,os.time())
		-- PublicRedis.StopRecord(nUserId,3)
		PublicRedis._DelAutoBetStatistics(nUserId)	
        return 
    end 
	local tStatistics = PublicRedis.GetUserAutoBetStatistics(nUserId)
	if not tStatistics then 
		tBase.Log("_UpdateAutoBetStatistics  无统计数据 nUserId_%d",nUserId)
		return 
	end  
	local nProfit = PublicRedis._GetIncrProfit(nUserId)  -- 当前盈利情况
	tStatistics.nLoseWin = nProfit + nLoseWin
	if math.abs(nProfit) >= nLossLimit or  nProfit >= nProfitLimit then 
		local nReason = 1  -- 1触及止损点 2触及止盈点
		if nProfit > 0 then 
			nReason = 2 
		end 
		tBase.Log("_UpdateAutoBetStatistics  止输赢,停止 nUserId_%d [%s= %.1f] 盈亏_%.1f [%d,%d] nProfit_%.1f nReason_%d "
		,nUserId,sTableId,nLoseWin,tStatistics.nLoseWin,nProfitLimit,nLossLimit,nProfit,nReason)

		PublicRedis.StopRecord(nUserId,nReason)
		return 
	end 
	local sLog,Str,arr ="","",{} 
	if nLoseWin > 0 then 
		sLog ="连赢"
		local arrLinkWin = tStatistics.arrGoodThreadWin[sTableId] 
		if arrLinkWin then  
			local tLinkWin = arrLinkWin[nGTType]
			if tLinkWin then 	
				if tLinkWin.isStop then 
					sLog=string.format("%s 已暂停 %d=[%d >= %d]",sLog,nGTType,tLinkWin.nLinkWin,nWinSuccPause)				
				else
					tLinkWin.nLinkWin = tonumber(tLinkWin.nLinkWin) + 1
					if tLinkWin.nLinkWin >= nWinSuccPause then 
						tLinkWin.isStop = true 
						sLog=string.format("%s 触发暂停 %d=[%d >= %d]",sLog,nGTType,tLinkWin.nLinkWin,nWinSuccPause)
					else
						sLog=string.format("%s %d=[%d < %d]",sLog,nGTType,tLinkWin.nLinkWin,nWinSuccPause)
					end 
				end 
				arrLinkWin[nGTType] = tLinkWin
			end 
			-- 重置其他好路
			for nType,v in pairs(arrLinkWin) do			
				if nType ~= nGTType then 
					arrLinkWin[nType] = {isStop=false,nLinkWin=0} 
					table.insert(arr,tonumber(nType))
				end 
			end   
			tStatistics.arrGoodThreadWin[sTableId] = arrLinkWin
		end 
		-- 重置 牌桌连输
		tStatistics.arrTableLinkLose[sTableId] = {sTableId=sTableId,nLinkLose=0,nPauseTime=-1}
		Str="连输"
	elseif nLoseWin < 0 then 
		sLog ="连输"
		--桌台连输
		local tTableLinkLose = tStatistics.arrTableLinkLose[sTableId] 
		if tTableLinkLose then  
			local nPauseTime = tonumber(tTableLinkLose.nPauseTime)  
			if nPauseTime > 0 then 
				if nPauseTime + nStopTime < os.time() then 
					tTableLinkLose.nLinkLose = 1
					tTableLinkLose.nPauseTime = -1	
					sLog=string.format("%s 重置 [%d < %d]",sLog,tTableLinkLose.nLinkLose,nLossSuccPause)
				else
					sLog=string.format("%s [%d >= %d] 已暂停30分钟_%d ",sLog,tTableLinkLose.nLinkLose,nLossSuccPause,tTableLinkLose.nPauseTime)
				end 
			else 
				-- nLinkLose 输次数, nPauseTime：暂停10分钟时间戳,-1则无
				tTableLinkLose.nLinkLose = tonumber(tTableLinkLose.nLinkLose) + 1
				if tTableLinkLose.nLinkLose >= nLossSuccPause then 
					tTableLinkLose.nPauseTime = os.time() 	-- 暂停30分钟时间戳,-1则无
					sLog=string.format("%s [%d >= %d] 暂停30分钟_%d ",sLog,tTableLinkLose.nLinkLose,nLossSuccPause,tTableLinkLose.nPauseTime)     
                    PublicRedis.PauseByLossStraightRecord(nUserId,{sTableId=sTableId,nPauseTime=30,sPaiJuId=sPaiJuId,sTableName=sTableName}) -- 通知记录
				else
					tTableLinkLose.nPauseTime = -1				
					sLog=string.format("%s [%d < %d]",sLog,tTableLinkLose.nLinkLose,nLossSuccPause)
				end 
			end 
			tStatistics.arrTableLinkLose[sTableId]=tTableLinkLose 
		end 	
		-- 重置 好路连赢
		local arrLinkWin = tStatistics.arrGoodThreadWin[sTableId] or {}
		if arrLinkWin then 
			for nType, v in pairs(arrLinkWin) do	
				arrLinkWin[nType] = {isStop=false,nLinkWin=0} 
				table.insert(arr,tonumber(nType))
			end 	
			tStatistics.arrGoodThreadWin[sTableId]=arrLinkWin	
		end 
		Str="连赢"		
	elseif nLoseWin == 0 then  -- 和  
		-- 重置 好路连赢
		local arrLinkWin = tStatistics.arrGoodThreadWin[sTableId] 
		if arrLinkWin then 
			for nType, v in pairs(arrLinkWin) do	
				arrLinkWin[nType] = {isStop=false,nLinkWin=0} 
				table.insert(arr,tonumber(nType))
			end 	
			tStatistics.arrGoodThreadWin[sTableId]=arrLinkWin	
		end 	
		-- 重置牌桌连输 
		if tStatistics.arrTableLinkLose[sTableId] then 
			tStatistics.arrTableLinkLose[sTableId] = {sTableId=sTableId,nLinkLose=0,nPauseTime=-1}
		end 
		Str="连赢输"		
	end 	
	if nLoseWin ~= 0 then   
        local tBetMultiple = PublicRedis._Handle_AutoBet_BetMultiple(4,nUserId,{sTableId=sTableId})
        if not tBetMultiple or not tBetMultiple.arrWinLoseRecord then 
            tBase.Log("_UpdateAutoBetStatistics [%s=%s]  nUserId_%d    tBetMultiple is nil ",sTableName,sTableId,nUserId)
            return 
        end 
        local sWinLose = " 输赢记录 "..cjson.encode(tBetMultiple or {}) 
		local nWinLose = 1    -- 1赢，0 输
		if nLoseWin < 0 then  
			nWinLose = 0
		end 
        local nMultiple,arrWinLoseRecord = _ComputeBetMultiple(cfg,tBetMultiple.arrWinLoseRecord,nWinLose)
        local tBetMultiple = {}
        tBetMultiple.sTableId= sTableId   	     		 
        tBetMultiple.nMultiple = nMultiple          	 -- 策略倍数 
        tBetMultiple.arrWinLoseRecord= arrWinLoseRecord  -- 桌子下注输赢记录
        PublicRedis._Handle_AutoBet_BetMultiple(2,nUserId,tBetMultiple) 
		sWinLose = sWinLose.." 后: "..cjson.encode(tBetMultiple) 	
		tBase.Log("_UpdateAutoBetStatistics [%s=%s] nUserId_%d nMultiple_%d Old_%d nWinLose_%d    Record: %s "
        ,sTableName,sTableId,nUserId,nMultiple,tBetMultiple.nMultiple,nWinLose,sWinLose)
	end 
	sLog = sLog.." 重置"..Str.." "..cjson.encode(arr)
	tBase.Log("_UpdateAutoBetStatistics  [%s/%s] nUserId_%d=(%.1f %d) 盈亏_%.1f nProfit_%.1f %s ",sTableName,sTableId,nUserId,nLoseWin,nGTType,tStatistics.nLoseWin,nProfit,sLog)	
    PublicRedis._ChangeAutoBetStatistics(nUserId,tStatistics)	 
    return 1
end

-- 调试 下注倍数策略
function PublicLiveAutoBet.__Test()    
    if 1 then return end 
    -- tBase.Log("__Test   PublicLiveAutoBet   ")
    local tStToMulti={}
        tStToMulti[112]={(1),(1),(2)}			--112投注	
        tStToMulti[122]={(1),(2),(2)}			--122投注	 
        tStToMulti[121]={(1),(2),(1)}			--121投注
        tStToMulti[211]={(2),(1),(1)}			--211投注	
        tStToMulti[212]={(2),(1),(2)}			--212投注	
        tStToMulti[1]={(1),(2),(4),(8)}			--输追模式
        tStToMulti[2]={(1),(2),(4),(8)} 		--赢追模式
        tStToMulti[3]={(1),(1),(1),(1)} 		--固定底注
        tStToMulti[4]={(1),(3),(2),(6)}			--鸡尾酒下注法
        tStToMulti[5]={(1),(3),(6),(10),(15)} 	--天梯下注法
        tStToMulti[6]={(1),(1),(2),(3),(5)} 	--五局八星A投	
        tStToMulti[7]={(1),(1),(3),(6),(10)} 	--五局八星B投
        tStToMulti[8]={(2),(2),(3),(4),(5)}		--五局八星C投2星级
        tStToMulti[9]={(3),(3),(4),(5),(6)} 	--五局八星C投3星级
        tStToMulti[10]={(4),(4),(5),(6),(7)} 	--五局八星C投4星级
        tStToMulti[11]={(5),(5),(7),(9),(10)} 	--五局八星C投5星级
        tStToMulti[12]={(6),(6),(8),(10),(12)} 	--五局八星C投6星级
        tStToMulti[13]={(7),(7),(9),(12),(15)} 	--五局八星C投7星级
        tStToMulti[14]={(8),(8),(10),(15),(20)} --五局八星C投8星级	

    local function _Strategy(nBetStrategy)
        local cfg = {}
        cfg.nBetStrategy =nBetStrategy
        cfg.arrMulti = tStToMulti[nBetStrategy] 
        local arrWinLoseRecord = {}  
        for j = 1, 100, 1 do 
            local nWinLose = 0
            if math.random(1,100) >= 90 then 
                nWinLose = 0 
            else 
                nWinLose = 1
            end 
            local nMultiple = -1
            nMultiple,arrWinLoseRecord = _ComputeBetMultiple(cfg,arrWinLoseRecord,nWinLose) 
            tBase.Log("__Test nBetStrategy_%d =%d nWinLose_%d  nMultiple_%d  arrWinLoseRecord: %s "
            ,nBetStrategy,j,nWinLose,nMultiple,cjson.encode(arrWinLoseRecord))   
        end   

        if 1 then return end 

        -- 固定局数 
        for j = 1, 100, 1 do
            local arr = {}        
            local arrRecord = {}
            local arrWinLose= {}
            local arrWinLoseRecord = {} 
            for i = 1, 20, 1 do      
                local nWinLose = 0
                if math.random(1,100) >= 50 then 
                    nWinLose = 0 
                else 
                    nWinLose = 1
                end 
                local nMultiple = -1
                nMultiple,arrWinLoseRecord = _ComputeBetMultiple(cfg,arrWinLoseRecord,nWinLose) 
                tBase.Log("__Test %d nWinLose_%d  nMultiple_%d  arrWinLoseRecord: %s ",i,nWinLose,nMultiple,cjson.encode(arrWinLoseRecord))   
                table.insert(arr,nMultiple)     
                table.insert(arrRecord,arrWinLoseRecord)   
            end      
            -- tBase.Log("__Test %d  arr: %s arrWinLose: %s arrRecord: %s ",j,cjson.encode(arr),cjson.encode(arrWinLose),cjson.encode(arrRecord))  
        end   
    end
 
    local arr = {2,4,112,122,121}

    for _, nBetStrategy in pairs(arr) do
        _Strategy(nBetStrategy)            
    end

    -- local nBetStrategy = 5
    -- _Strategy(nBetStrategy)    
    return 
end
 


return PublicLiveAutoBet