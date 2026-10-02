--语音房相关
local tPublicRedis = require("PublicRedis")
local mlogger = require("logger")      -- 日志对象
local cjson = require("cjson")
local BaseSink =require("BaseSink")

local VoiceRoom = {}

function VoiceRoom:New(sTableId,nGameId)
    local t = {}
	setmetatable(t, self)
	self.__index = self
    t.arrUserData = {} --语音房玩家数据 {nUserId={...},nUserId={...},...}
    t.sTableId = sTableId
    t.arrRank = {} --盈利排行榜 {nUserId={...},nUserId={...},...}
    t.arrBetDetail = {} --当前局玩家的下注详情 {nUserId={nAreaId=nBetSum,...},...}
    t.arrNeedSupply = {} --需要补充关注列表的玩家
    t.arrRealUserId = {} --真人玩家的id
    t.arrUserWinLose = {} --本局所有玩家的输赢数据
    t.nGameId = nGameId
    t.tBJLArea = { --直播百家乐下注区
        nXian=1,				--闲
        nZhuang=2,				--庄
    }

    t.nLenWL = 20 --单局输赢数据条数
    t.nMaxRank = 50--排行榜玩家最大个数
    t.nMaxConcern = 4 --关注列表最大个数
    t.nMaxRecommen = 20 --推荐列表非上麦玩家最大个数
    return t
end

--添加玩家数据
function VoiceRoom:AddUser(tUserInfo)
    if self.arrUserData[tUserInfo.nUserId] then
        return
    end

    local t = {}
    t.nUserId = tUserInfo.nUserId --玩家id
    t.sFaceId = tUserInfo.sFaceId or '1' --玩家头像
    t.sName = tUserInfo.sName or "No Name" --玩家昵称
    t.sShopAcc = tUserInfo.sShopAcc or "" --第三方玩家id
    t.nIsReal = (tUserInfo.isAndroid and 0) or 1 --是否是真人
    t.nSitId = tUserInfo.nSitId

    t.nTotalBetSum = 0 --累计总下注
    t.nWinLoseSum = 0 --累计总输赢
    t.arrWL = {} --单局输赢（-1:输，0:平，1:赢）{1,-1,1,...}
    t.arrConcern = {} --关注的玩家列表  {nUserId,nUserId,nUserId,nUserId,...}
    t.nLookUserId = nil --查看的玩家
    t.tRecommenUserId = {} --获取的推荐玩家 {nUserId=nUserId,...}
    t.tMicUserData = {} --上麦玩家数据
    t.tMicShopAcc = {} --前端传的上麦玩家第三方id

    t.nWL = 0 --本局输赢

    self.arrUserData[tUserInfo.nUserId]=t

    if not tUserInfo.isAndroid then
        self.arrRealUserId[tUserInfo.nUserId] = tUserInfo.nUserId
    end

    self:SetUserToRedis({tUserInfo.nUserId})
end

--删除玩家数据
--@param arrUserId={{nUserId,sShopAcc},{nUserId,sShopAcc},...}
function VoiceRoom:DelUser(arrUserId)
    if not arrUserId or #arrUserId==0 then
        return
    end

    local arrDelUser = {}
    for _,tLeave in pairs(arrUserId) do
        if self.arrUserData[tLeave.nUserId] then --删除玩家
            table.insert(arrDelUser,{nUserId=tLeave.nUserId,sShopAcc=tLeave.sShopAcc})
            self.arrUserData[tLeave.nUserId] = nil
        end

        self.arrBetDetail[tLeave.nUserId] = nil --删除玩家下注详情
        
        self.arrUserWinLose[tLeave.nUserId] = nil --删除玩家输赢

        self.arrRealUserId[tLeave.nUserId] = nil --删除真人玩家id

        for k,v in pairs(self.arrRank) do --从排行榜中删除
            if tLeave.nUserId==v.nUserId then
                table.remove(self.arrRank,k)
                break
            end
        end

        for _,nUserId in pairs(self.arrRealUserId) do
            local tUser = self.arrUserData[nUserId]
            if tUser then
                self:RemoveFromUserConcernList(tUser.nUserId,tLeave.nUserId) --从关注列表中移除
                tUser.tRecommenUserId[tLeave.nUserId] = nil --从推荐列表Id中移除
                tUser.tMicUserData[tLeave.nUserId] = nil
            end
        end
    end

    if #arrDelUser>0 then
        self:Print("[VoiceRoom:DelUser] %s",cjson.encode(arrDelUser))
        self:RemoveUserInRedis(arrDelUser)
    end
end

--重置玩家单局数据
function VoiceRoom:ResetSingleRoundData()
    --重置需要补充关注列表的玩家
    self.arrNeedSupply = {}

    --重置玩家输赢，补充上麦玩家到上麦列表
    for _,tUser in pairs(self.arrUserData) do
        tUser.nWL = 0
        tUser.isAutoSupply = false
        if tUser.nIsReal==1 and not self:IsUserConcernFull(tUser.nUserId) then
            --真人，而且关注列表不满，需要补充
            table.insert(self.arrNeedSupply,{nUserId=tUser.nUserId,nSitId=tUser.nSitId}) 
        end
    end

    --重置玩家下注
    self.arrBetDetail = {}
    --重置所有玩家输赢
    self.arrUserWinLose = {}
    --更新玩家盈利排行榜
    self:UpdateRankList()
end

--更新玩家的单局输赢，累计总下注，累计总输赢
--@params tData = {nUserId:玩家id,nBetSum=x,nProfitSum=x}
function VoiceRoom:UpdateUserWinLose(tData)
    local nUserId = tData.nUserId
    if nUserId and self.arrUserData[nUserId] then
        if tData.nProfitSum~=0 then
            self.arrUserData[nUserId].nTotalBetSum = self.arrUserData[nUserId].nTotalBetSum + tData.nBetSum
            self.arrUserData[nUserId].nWinLoseSum = self.arrUserData[nUserId].nWinLoseSum + tData.nProfitSum

            local nWL = 0
            if tData.nProfitSum>0 then
                nWL = 1
            elseif tData.nProfitSum<0 then
                nWL = -1
            end

            self.arrUserData[nUserId].nWL = nWL
            table.insert(self.arrUserData[nUserId].arrWL,nWL)

            if #self.arrUserData[nUserId].arrWL>self.nLenWL then
                table.remove(self.arrUserData[nUserId].arrWL,1)
            end
        end
    end
end

--获取玩家单局输赢，累计总下注，累计总输赢
--@param nUserId 玩家id
--@return nWL:单局输赢,nTotalBetSum:累计总下注,nWinLoseSum:累计总输赢 (默认nil,nil,nil)
function VoiceRoom:GetUserWinLose(nUserId)
    if nUserId and self.arrUserData[nUserId] then
        return self.arrUserData[nUserId].nWL,self.arrUserData[nUserId].nTotalBetSum,self.arrUserData[nUserId].nWinLoseSum
    end
    return nil,nil,nil
end

--获取玩家需要保存到redis上的数据
--@param tUser 看VoiceRoom:AddUser()里面的数据
--@return tData 默认{}
function VoiceRoom:GetUserRedisData(tUser)
    local tData = {}
    tData.nUserId = tUser.nUserId
    tData.sFaceId = tUser.sFaceId
    tData.sName = tUser.sName
    tData.nTotalBetSum=tUser.nTotalBetSum						--进入这个房间后的总下注
    tData.nWinLoseSum=tUser.nWinLoseSum							--进入这个房间后的总输赢
    tData.arrWL=tUser.arrWL			                            --每局的输赢情况(有输赢的局)
    tData.sShopAcc = tUser.sShopAcc								--第三方账号
    tData.nIsReal = tUser.nIsReal                               --是否是真人
    return tData
end

--把玩家数据保存到redis(玩家加入房间，玩家下注结算才写入)
--@param arrUserId={nUserId,nUserId,...}
function VoiceRoom:SetUserToRedis(arrUserId)
    local arrData = {}
    for k,v in pairs(arrUserId) do
        if self.arrUserData[v] then
            local tUser = self.arrUserData[v]
            local tData = self:GetUserRedisData(tUser)
            table.insert(arrData,tData)
        end
    end
    if #arrData>0 then
        tPublicRedis.SetRoomUserShareInfoBatch(self.nGameId,self.sTableId,arrData)
    end
end

--把玩家数据从redis上删除
--@param arrUserId={nUserId,nUserId,...}
function VoiceRoom:RemoveUserInRedis(arrUserId)
    tPublicRedis.RemoveRoomUserShareInfoBatch(self.nGameId,self.sTableId,arrUserId) --清除redis上的数据
end

--从redis上获取玩家数据
--@param arrUserId={nUserId,nUserId,...}
--@param isSort 是否进行排序
--@return arrUserData={tUser,tUser,...}
function VoiceRoom:GetUserFromRedis(arrUserId,isSort)
    local arrUserData = {}
    for k,v in ipairs(arrUserId) do
        if self.arrUserData[v] then
            --是本服的玩家就从缓存直接拿数据
            local tUser = self.arrUserData[v]
            local tData = self:GetUserRedisData(tUser)
            table.insert(arrUserData,tData)
        else
            --不是本服的玩家从redis上拿数据
            local tUserInfo = tPublicRedis.GetRoomUserShareInfo(self.nGameId,self.sTableId,v)
            if tUserInfo then
                local tData = self:GetUserRedisData(tUserInfo)
                table.insert(arrUserData,tData)
            end
        end
    end
    if #arrUserData>1 and isSort then
        table.sort(arrUserData,function (a, b)
            return a.nWinLoseSum>b.nWinLoseSum
        end)
    end
    return arrUserData
end

--玩家是否在牌桌里面
--@param nUserId 玩家id
--@return true:在  false:不在
function VoiceRoom:IsInTable(nUserId)
    if not nUserId then
        return false
    end
    if self.arrUserData[nUserId] then
        return true
    end
    local tUserInfo = tPublicRedis.GetRoomUserShareInfo(self.nGameId,self.sTableId,nUserId)
    if tUserInfo then
        return true
    end
    return false
end

--更新玩家盈利排行榜
function VoiceRoom:UpdateRankList()
    self.arrRank = {}
    local arrData = tPublicRedis.GetRoomUserShareInfoBatch(self.nGameId,self.sTableId) --获取房间内玩家的数据
    if #arrData>1 then
        --优先按盈利排序，盈利相同按真人>机器人排序
        table.sort(arrData,function (a, b)
            if a.nWinLoseSum==b.nWinLoseSum then
                return a.nIsReal>b.nIsReal
            else
                return a.nWinLoseSum>b.nWinLoseSum
            end
        end)

        local tAllUserData = {}
        local nLen = math.min(self.nMaxRank,#arrData)
        for i=1,#arrData do
            local tUser = arrData[i]
            local tRankUser = self:GetUserRedisData(tUser)
            tAllUserData[tUser.nUserId] = tRankUser
            if i<=nLen then
                table.insert(self.arrRank,tRankUser)
            end
        end

        --更新上麦玩家的数据
        for _,nUserId in pairs(self.arrRealUserId) do
            local tUser = self.arrUserData[nUserId]
            if tUser then
                for k,v in pairs(tUser.tMicUserData) do
                    if tAllUserData[v.nUserId] then
                        v = tAllUserData[v.nUserId]
                    end
                end
            end
        end
    end

   -- arrRank
end

--检查是否进行排行榜玩家补充
function VoiceRoom:CheckUpdateRankList()
    if #self.arrRank < self.nMaxRecommen then
        --如果排行榜玩家数量小于推荐列表的最大数量,更新排行榜
        self:UpdateRankList()
    end
    -- self:Print("[VoiceRoom:arrRank Len]:%d",#self.arrRank)
end

--获取玩家要发送给前端的数据
--@param tUser 看VoiceRoom:GetUserRedisData()里面的数据
--@return tData 默认{}
function VoiceRoom:GetUserListData(tUser)
    local tData = {}
    tData.nUserId = tUser.nUserId
    tData.sFaceId = tUser.sFaceId
    tData.sName = tUser.sName
    tData.nTotalBetSum=tUser.nTotalBetSum						--进入这个房间后的总下注
    tData.nWinLoseSum=tUser.nWinLoseSum							--进入这个房间后的总输赢
    tData.bIsMic = false                                        --是否是上麦玩家
    tData.bIsConcern = false                                    --是否是关注列表玩家
    tData.bIsLock = false                                       --是否是跟投上锁
    tData.bIsFollow = false                                     --是否是跟投玩家
    tData.sShopAcc = tUser.sShopAcc								--第三方账号
    tData.arrWL=tUser.arrWL			                            --每局的输赢情况(有输赢的局)
    return tData
end

--通过第三方id获取玩家id
--@param arrShopAcc = {sShopAcc,sShopAcc,...}
--@return arrMicUserId = {nUserId,nUserId,..}  tMicUserId = {nUserId=sShopAcc,nUserId=sShopAcc,...}
function VoiceRoom:GetUserIdByShopAcc(arrShopAcc)
    local arrMicUserId = {}
    local tMicUserId = {}
    for _,sShopAcc in pairs(arrShopAcc) do
        local tData = nil

        if not tData then --从缓存玩家中查找玩家
            for _,tUser in pairs(self.arrUserData) do 
                if tUser.sShopAcc == sShopAcc then
                    tData = {nUserId=tUser.nUserId}
                    break
                end

                for k,v in pairs(tUser.tMicUserData) do --从上麦玩家数据中查找
                    if v.sShopAcc==sShopAcc then
                        tData = {nUserId=v.nUserId}
                        break
                    end
                end

                if tData then
                    break
                end
            end
        end

        if not tData then --在排行榜查找玩家
            for _,tUser in pairs(self.arrRank) do
                if tUser.sShopAcc==sShopAcc then
                    tData = {nUserId=tUser.nUserId}
                    break
                end
            end
        end

        if not tData then --在redis读取
            tData = tPublicRedis.GetRoomUserShareInfoByShopAcc(self.nGameId,self.sTableId,sShopAcc)
        end

        if tData and tData.nUserId then
            local nUserId = tData.nUserId
            tMicUserId[nUserId] = sShopAcc
            table.insert(arrMicUserId,nUserId)
            self:Print("GetUserIdByShopAcc sShopAcc_%s nUserId_%d",sShopAcc,nUserId)
        end
    end
    return arrMicUserId,tMicUserId
end

--检查上麦玩家是否有刷新
--@param tMicUserId = {nUserId=sShopAcc,nUserId=sShopAcc,...}
--@Retrun true:有刷新 false:没刷新
function VoiceRoom:UpdateMicUserData(nUserId,tMicUserId)
    local tUser = self.arrUserData[nUserId]
    if tUser then
        local isUpDate = false
        for k,v in pairs(tUser.tMicUserData) do  --遍历上麦玩家数据，不在前端传过来的上麦列表里面的都删了
            if not tMicUserId[v.nUserId] then
                tUser.tMicUserData[v.nUserId] = nil
                isUpDate = true
            end
        end

        local arrAddUserId = {}
        for nMicUserId,sShopAcc in pairs(tMicUserId) do --遍历前端传过来的上麦列表，缓存的上麦玩家里面没有的玩家就添加
            if not tUser.tMicUserData[nMicUserId] and nMicUserId~=nUserId then
                table.insert(arrAddUserId,nMicUserId)
                isUpDate = true
            end
        end

        if #arrAddUserId>0 then
            local arrUser = self:GetUserFromRedis(arrAddUserId,true) --获取玩家信息
            for k,v in pairs(arrUser) do
                tUser.tMicUserData[v.nUserId] = v
            end
        end

        if isUpDate then
            local sLog = ""
            for k,v in pairs(tUser.tMicUserData) do
                sLog = sLog..string.format("nUserId_%d,sShopAcc_%s",v.nUserId,v.sShopAcc)
            end
            self:Print("UpdateMicUserData nUserId_%d tMicUserData_%s",nUserId,sLog)
        end
    end
end

--获取推荐列表
--@param nUserId 玩家id  arrShopAcc = {sShopAcc,sShopAcc,...}
function VoiceRoom:GetRecommonList(nUserId,arrShopAcc)
    local arrMicUserId,tMicUserId = self:GetUserIdByShopAcc(arrShopAcc)
    self:UpdateMicUserData(nUserId,tMicUserId) --更新上麦列表玩家
    local arrMicUser = {}
    if self.arrUserData[nUserId] then
        local tUser = self.arrUserData[nUserId]
        tUser.tMicShopAcc = {}
        for _, sShopAcc in pairs(arrShopAcc) do
            tUser.tMicShopAcc[sShopAcc] = 0
        end
        for k,v in pairs(tUser.tMicUserData) do
            table.insert(arrMicUser,v)
            tUser.tMicShopAcc[v.sShopAcc] = v.nUserId
        end
    end
    
    if not arrShopAcc or #arrShopAcc==0 then --如果前端没传上麦玩家，使用缓存的上麦玩家数据
        for k,v in pairs(arrMicUser) do
            table.insert(arrMicUserId,v.nUserId)
            tMicUserId[v.nUserId] = v.nUserId
        end
    end

    local arrConcern,tConcern = self:GetConcernUserId(nUserId)
    local arrConcernUser = self:GetUserFromRedis(arrConcern,true) --关注列表玩家

    local arrUserList = {}
    local tAlreadyAdd = {} --已经插入到推荐列表的玩家
    --关注玩家最优先放入推荐列表
    for _,tUser in pairs(arrConcernUser) do
        local tItem = self:GetUserListData(tUser)
        tItem.bIsConcern = true
        tItem.bIsMic = (tMicUserId[tUser.nUserId]~=nil)
        table.insert(arrUserList,tItem)
        tAlreadyAdd[tUser.nUserId] = tUser.nUserId
    end

    --上麦玩家其次放入推荐列表，但要排除在关注列表里面的玩家和自己
    for _,tUser in pairs(arrMicUser) do
        if not tAlreadyAdd[tUser.nUserId] and nUserId~=tUser.nUserId then
            local tItem = self:GetUserListData(tUser)
            tItem.bIsMic = (tMicUserId[tUser.nUserId]~=nil)
            table.insert(arrUserList,tItem)
            tAlreadyAdd[tUser.nUserId] = tUser.nUserId
        end
    end

    local nMax = self.nMaxRecommen + #arrMicUserId  --推荐列表最大个数（非麦最大个数+上麦玩家个数）

    --最后是排行榜的玩家放入推荐列表，但要排除在关注列表里面,上麦列表里面的玩家和自己
    for _,tUser in pairs(self.arrRank) do
        if not tAlreadyAdd[tUser.nUserId] and nUserId~=tUser.nUserId then
            local tItem = self:GetUserListData(tUser)
            table.insert(arrUserList,tItem)

            if #arrUserList>=nMax then
                --达到最大个数
                break
            end
        end
    end

    self:UpdateRecommenUserId(nUserId,arrUserList) --更新玩家的推荐列表玩家id

    -- self:Print("VoiceRoom.GetRecommonList arrUserList:%s",cjson.encode(arrUserList))

    return arrUserList
end

--获取关注列表
--@param nUserId 玩家id  arrShopAcc = {sShopAcc,sShopAcc,...}
--@param isNeedRank 是否从排行榜补充关注列表
function VoiceRoom:GetConcernList(nUserId,arrShopAcc,isNeedRank)
    local arrMicUserId,tMicUserId = self:GetUserIdByShopAcc(arrShopAcc)
    self:UpdateMicUserData(nUserId,tMicUserId) --更新上麦列表玩家
    if #arrShopAcc>0 and self.arrUserData[nUserId] then
        local arrMicUser = {}
        if self.arrUserData[nUserId] then
            local tUser = self.arrUserData[nUserId]
            tUser.tMicShopAcc = {}
            for _, sShopAcc in pairs(arrShopAcc) do
                tUser.tMicShopAcc[sShopAcc] = 0
            end
            for k,v in pairs(tUser.tMicUserData) do
                table.insert(arrMicUser,v)
                tUser.tMicShopAcc[v.sShopAcc] = v.nUserId
            end
        end
        self:SupplementConcernList(nUserId,arrMicUser) --从上麦列表补充关注列表
    end

    if isNeedRank then
        self:SupplementUserFromRank(nUserId) --从排行榜补充关注列表
    end

    local arrConcern,tConcern = self:GetConcernUserId(nUserId)
    local arrConcernUser = self:GetUserFromRedis(arrConcern) --关注列表玩家

    local arrUserList = {}
    for _,tUser in pairs(arrConcernUser) do
        local tItem = self:GetUserListData(tUser)
        tItem.bIsConcern = true
        tItem.bIsMic = (tMicUserId[tUser.nUserId]~=nil)
        table.insert(arrUserList,tItem)
    end

    -- self:Print("VoiceRoom.GetConcernList arrUserList:%s",cjson.encode(arrUserList))

    return arrUserList
end

--从上麦玩家中补充关注玩家列表
--@param nUserId 玩家id  arrMicUser = {tUser,tUser,...} tUser 看VoiceRoom:GetUserRedisData()里面的数据
--@return true 补充成功  false 补充失败
function VoiceRoom:SupplementConcernList(nUserId,arrMicUser)
    local isAdd = false
    if nUserId and self.arrUserData[nUserId] then
        local nCnt = self:GetConcernCnt(nUserId)
        if nCnt>=0 and nCnt<self.nMaxConcern then
            --玩家关注列表没满，自动补充上麦玩家
            if #arrMicUser>0 then
                local nLack = self.nMaxConcern-nCnt --最多需要补充多少个
                for i=1,#arrMicUser do
                    local tMicUser = arrMicUser[i]
                    local nMicUserId = tMicUser.nUserId
                    local nRlt = self:AddToUserConcernList(nUserId,nMicUserId)
                    if nRlt == 0 then
                        isAdd = true
                        self:Print("补充上麦玩家到关注列表成功:nUserId_%d,nMicUserId_%d,sMicShopAcc_%s",nUserId,nMicUserId,tMicUser.sShopAcc)
                        nLack = nLack - 1
                        if nLack<=0 then
                            break
                        end
                    else
                        self:Print("补充上麦玩家到关注列表失败:nUserId_%d,nMicUserId_%d,sMicShopAcc_%s,nRlt_%d",nUserId,nMicUserId,tMicUser.sShopAcc,nRlt)
                    end
                end
            end
        end
    end
    return isAdd
end

--获取关注玩家的个数
--@param nUserId 玩家id
--@return nCnt:个数 ，默认:-1
function VoiceRoom:GetConcernCnt(nUserId)
    local nCnt = -1
    if self.arrUserData[nUserId] then
        nCnt = #self.arrUserData[nUserId].arrConcern
    else
        self:Print("GetConcernCnt 玩家数据不存在 nUserId_%d",nUserId)
    end
    return nCnt
end

--获取关注玩家列表
--@param nUserId 玩家id
--@return arrConcern = {nUserId,nUserId,...} tConcern={nUserId=nUserId,nUserId=nUserId,...}
function VoiceRoom:GetConcernUserId(nUserId)
    local arrConcern = {}
    local tConcern = {}
    if self.arrUserData[nUserId] then
        for k,v in ipairs(self.arrUserData[nUserId].arrConcern) do
            table.insert(arrConcern,v)
            tConcern[v] = tConcern
        end
    end
    return arrConcern,tConcern
end

--玩家nUserId2是否在玩家nUserId1的关注列表
--@params nUserId1:玩家1  nUserId2:玩家2
--@return true:在    false:不在
function VoiceRoom:IsInUserConcern(nUserId1,nUserId2)
    if nUserId1 and nUserId2 and self.arrUserData[nUserId1] then
        for k,v in pairs(self.arrUserData[nUserId1].arrConcern) do
            if v==nUserId2 then
                return true
            end
        end
    end
    return false
end

--关注玩家列表是否已满
--@param nUserId 玩家id
--@return true:满  false:没满
function VoiceRoom:IsUserConcernFull(nUserId)
    local nCnt = self:GetConcernCnt(nUserId)
    if nCnt>=0 and nCnt<self.nMaxConcern then
        return false
    end
    return true
end

--玩家1关注列表添加玩家2
--@params nUserId1:玩家1  nUserId2:玩家2
--@return 0:成功 1:参数缺失 2:关注自己 3:操作玩家不存在 4:关注玩家不存在 5:已关注 6:关注列表已满
function VoiceRoom:AddToUserConcernList(nUserId1,nUserId2)
    local nRlt = 0

    if not nUserId1 or not nUserId2 then
        nRlt = 1
        return nRlt
    end

    if nUserId1==nUserId2 then
        nRlt = 2
        return nRlt
    end

    if not self.arrUserData[nUserId1] then
        nRlt = 3
        return nRlt
    end

    if not self:IsInTable(nUserId2) then
        nRlt = 4
        return nRlt
    end

    if self:IsInUserConcern(nUserId1,nUserId2) then
        nRlt = 5
        return nRlt
    end

    if self:IsUserConcernFull(nUserId1) then
        nRlt = 6
        return nRlt
    end

    table.insert(self.arrUserData[nUserId1].arrConcern,nUserId2)
    self:Print("[VoiceRoom:AddToUserConcernList]nUserId1_%d,nUserId2_%d,now_%s",nUserId1,nUserId2,cjson.encode(self.arrUserData[nUserId1].arrConcern))

    return nRlt
end

--玩家1关注列表删除玩家2
--@params nUserId1:玩家1  nUserId2:玩家2
--@return 0:成功 1:参数缺失 3:操作玩家不存在
function VoiceRoom:RemoveFromUserConcernList(nUserId1,nUserId2)
    local nRlt = 0

    if not nUserId1 or not nUserId2 then
        nRlt = 1
        return nRlt
    end

    if not self.arrUserData[nUserId1] then
        nRlt = 3
        return nRlt
    end

    for k,v in pairs(self.arrUserData[nUserId1].arrConcern) do
        if v==nUserId2 then
            table.remove(self.arrUserData[nUserId1].arrConcern,k)
            self:Print("[VoiceRoom:RemoveFromUserConcernList]nUserId1_%d,nUserId2_%d,now_%s",nUserId1,nUserId2,cjson.encode(self.arrUserData[nUserId1].arrConcern))
            break
        end
    end

    if self.arrUserData[nUserId1].nLookUserId==nUserId2 then --删除查看玩家
        self.arrUserData[nUserId1].nLookUserId = 0
    end

    return nRlt
end

--把玩家2设置玩家1的查看玩家
--@params nUserId1:玩家1  nUserId2:玩家2
function VoiceRoom:SetLookUserId(nUserId1,nUserId2)
    if nUserId1 and nUserId2 and self.arrUserData[nUserId1] then
        self.arrUserData[nUserId1].nLookUserId = nUserId2
        self:Print("设置查看玩家 nUserId_%d,nLookUserId_%d",nUserId1,nUserId2)
    end
end

--获取玩家的查看玩家ID
--@params nUserId:玩家id
--@return 查看玩家id nLookUserId（默认nil）
function VoiceRoom:GetLookUserId(nUserId)
    if nUserId and self.arrUserData[nUserId] then
        return self.arrUserData[nUserId].nLookUserId
    end
end

--获取玩家本局下注详情
--@param nUserId 玩家id
--@retrun arrBetInfo = {{nAreaId=1,nSumBet=100},{nAreaId=2,nSumBet=100},...}
function VoiceRoom:GetUserBetDetail(nUserId)
    local arrBetInfo = {}
    if nUserId and self.arrBetDetail[nUserId] then
        for nAreaId,tBet in pairs(self.arrBetDetail[nUserId]) do
            table.insert(arrBetInfo,{nAreaId=nAreaId,nSumBet=tBet.nSumBet})
        end
    end
    return arrBetInfo
end

--保存玩家本局下注详情
--@param tData={nUserId=x,nBetArea=x,nBetChip=x}
function VoiceRoom:SetUserBetDetail(tData)
    if tData.nUserId and tData.nBetArea and tData.nBetChip then
        if not self.arrBetDetail[tData.nUserId] then
            self.arrBetDetail[tData.nUserId] = {}
        end
        if not self.arrBetDetail[tData.nUserId][tData.nBetArea] then
            self.arrBetDetail[tData.nUserId][tData.nBetArea] = {nSumBet=0,nTime=os.time()}
        end
        local nOldBetSum = self.arrBetDetail[tData.nUserId][tData.nBetArea].nSumBet
        self.arrBetDetail[tData.nUserId][tData.nBetArea].nSumBet = nOldBetSum + tData.nBetChip
    end
end

--批量保存玩家本局下注详情
--@param arrData={{nBetArea=x,nBetChip=x},...}
function VoiceRoom:SetUserBetDetailBatch(nUserId,arrData)
    local nNowTime = os.time()
    if nUserId and arrData and #arrData>0 then
        if not self.arrBetDetail[nUserId] then
            self.arrBetDetail[nUserId] = {}
        end
        for _,tData in pairs(arrData) do
            if not self.arrBetDetail[nUserId][tData.nBetArea] then
                self.arrBetDetail[nUserId][tData.nBetArea] = {nSumBet=0,nTime=nNowTime}
            end
            local nOldBetSum = self.arrBetDetail[nUserId][tData.nBetArea].nSumBet
            self.arrBetDetail[nUserId][tData.nBetArea].nSumBet = nOldBetSum + tData.nBetChip
        end
    end
end

--获取玩家下注区域（直播百家乐专用）
function VoiceRoom:GetUserBetAreaBJL(nUserId)
    if self.arrBetDetail[nUserId] then
        if self.arrBetDetail[nUserId][self.tBJLArea.nXian] and self.arrBetDetail[nUserId][self.tBJLArea.nZhuang] then
            --庄闲都有下，优先选最先下的区域
            if self.arrBetDetail[nUserId][self.tBJLArea.nXian].nTime<self.arrBetDetail[nUserId][self.tBJLArea.nZhuang].nTime then
                return self.tBJLArea.nXian
            elseif self.arrBetDetail[nUserId][self.tBJLArea.nXian].nTime>self.arrBetDetail[nUserId][self.tBJLArea.nZhuang].nTime then
                return self.tBJLArea.nZhuang
            else
                --同时下的，优先选下注最多的区域
                if self.arrBetDetail[nUserId][self.tBJLArea.nXian].nSumBet>self.arrBetDetail[nUserId][self.tBJLArea.nZhuang].nSumBet then
                    return self.tBJLArea.nXian
                elseif self.arrBetDetail[nUserId][self.tBJLArea.nXian].nSumBet<self.arrBetDetail[nUserId][self.tBJLArea.nZhuang].nSumBet then
                    return self.tBJLArea.nZhuang
                else
                    return self.tBJLArea.nXian
                end
            end
        elseif self.arrBetDetail[nUserId][self.tBJLArea.nXian] then
            return self.tBJLArea.nXian
        elseif self.arrBetDetail[nUserId][self.tBJLArea.nZhuang] then
            return self.tBJLArea.nZhuang
        end
    end
end

--是否已经下注过庄或者闲了（直播百家乐专用）
function VoiceRoom:IsAlreadyBetZhuangOrXian(nUserId)
    if self.arrBetDetail[nUserId] then
        if self.arrBetDetail[nUserId][self.tBJLArea.nXian] or self.arrBetDetail[nUserId][self.tBJLArea.nZhuang] then
            return true
        end
    end
    return false
end

--更新玩家的推荐列表玩家id
--@param nUserId 玩家id
function VoiceRoom:UpdateRecommenUserId(nUserId,arrRecommonList)
    if nUserId and self.arrUserData[nUserId] then
        self.arrUserData[nUserId].tRecommenUserId = {}
        for k,v in pairs(arrRecommonList) do
            self.arrUserData[nUserId].tRecommenUserId[v.nUserId] = v.nUserId
        end
    end
end

--玩家nUserId2是否在玩家nUserId1的推荐列表
--@params nUserId1:玩家1  nUserId2:玩家2
--@return true:在    false:不在
function VoiceRoom:IsInUserRecommenList(nUserId1,nUserId2)
    if nUserId1 and nUserId2 and self.arrUserData[nUserId1] then
        return (self.arrUserData[nUserId1].tRecommenUserId[nUserId2]~=nil)
    end
    return false
end

--获取玩家进入时，关注了这个玩家的其他玩家
--@params nUserId:玩家  arrLeave={{nUserId,sShopAcc},{nUserId,sShopAcc},...}
--@retuen arrData = {{nUserId,nSitId,arrLeaveUserId},{nUserId,nSitId,arrLeaveUserId},...}
function VoiceRoom:GetNotifyUserByLeave(arrLeave)
    local arrData = {}
    for _,nUserId in pairs(self.arrRealUserId) do
        local tUser = self.arrUserData[nUserId]
        if tUser then
            local arrLeaveUserId = {}
            for _,tLeave in pairs(arrLeave) do
                if self:IsInUserConcern(tUser.nUserId,tLeave.nUserId) or self:IsInUserRecommenList(tUser.nUserId,tLeave.nUserId) then
                    table.insert(arrLeaveUserId,tLeave.nUserId)
                end
            end
            if #arrLeaveUserId>0 then
                table.insert(arrData,{nUserId=tUser.nUserId,nSitId=tUser.nSitId,arrLeaveUserId=arrLeaveUserId})
            end
        end
    end
    return arrData
end

--获取补充了关注列表的玩家
--@return arrData = {{nUserId,nSitId,arrUserList},{nUserId,nSitId,arrUserList},...}
function VoiceRoom:GetSupplementUser()
    local arrData = {}
    if #self.arrNeedSupply>0 then
        for _,v in pairs(self.arrNeedSupply) do
            local tUser = self.arrUserData[v.nUserId]
            if tUser then
                local isAdd = false
                local arrMicUser = {}
                for k,v in pairs(tUser.tMicUserData) do
                    table.insert(arrMicUser,v)
                end
                isAdd = self:SupplementConcernList(v.nUserId,arrMicUser) --从上麦列表补充关注列表
                local isAdd1 = self:SupplementUserFromRank(v.nUserId) --从排行榜的非上麦玩家中补充关注列表
                if isAdd or isAdd1 then
                    --如果有补充
                    local arrConcern = self:GetConcernUserId(v.nUserId)
                    local arrConcernUser = self:GetUserFromRedis(arrConcern) --关注列表玩家
    
                    local arrUserList = {}
                    for _,tConcernUser in pairs(arrConcernUser) do
                        local tItem = self:GetUserListData(tConcernUser)
                        tItem.bIsConcern = true
                        tItem.bIsMic = (tUser.tMicUserData[tConcernUser.nUserId]~=nil)
                        table.insert(arrUserList,tItem)
                    end
                    table.insert(arrData,{nUserId=v.nUserId,nSitId=v.nSitId,arrUserList=arrUserList})
                end
            end
            
        end
    end
    return arrData
end

--从排行榜玩家中非上麦玩家来补充关注列表
function VoiceRoom:SupplementUserFromRank(nUserId)
    local isAdd = false

    local arrConcern,tConcern = self:GetConcernUserId(nUserId)
    local nLackCnt = self.nMaxConcern-#arrConcern
    if nLackCnt>0 then
        local nAddCnt = 0
        local arrUser = {}
        for k,v in pairs(self.arrRank) do
            if v.nUserId~=nUserId and not tConcern[v.nUserId] then
                table.insert(arrUser,v)
                nAddCnt = nAddCnt + 1
                if nAddCnt>=nLackCnt then
                    break
                end
            end
        end
        isAdd = self:SupplementConcernList(nUserId,arrUser)
    end
    return isAdd
end

--获取玩家进入时，关注这个玩家的其他玩家
--@params arrEnter = {{nUserId,sShopAcc},{nUserId,sShopAcc},...}
--@return arrData = {{nUserId,nSitId,arrUserList},{nUserId,nSitId,arrUserList},...}
function VoiceRoom:GetNotifyUserByEnter(arrEnter)
    local arrData = {}
    for _,nUserId in pairs(self.arrRealUserId) do --遍历真人玩家
        local tUser = self.arrUserData[nUserId]
        if tUser then
            local isNotify = false --是否需要通知
            for k,v in pairs(arrEnter) do
                if tUser.tMicShopAcc[v.sShopAcc] then
                    --真人，而且进入玩家在上麦玩家列表里面
                    if tUser.tMicShopAcc[v.sShopAcc]==0 then
                        tUser.tMicShopAcc[v.sShopAcc] = v.nUserId
                    end
                    if not tUser.tMicUserData[v.nUserId] then
                        local arrMicUser = self:GetUserFromRedis({v.nUserId})
                        local tMicUser = arrMicUser[1]
                        if tMicUser then
                            tUser.tMicUserData[v.nUserId] = tMicUser
                            local isAdd = self:SupplementConcernList(tUser.nUserId,{tMicUser}) --从上麦列表补充关注列表
                            if isAdd then
                                --如果有补充，则需要通知玩家
                                isNotify = true
                            end
                        end
                    end
                end
            end
            if isNotify then
                local arrConcern = self:GetConcernUserId(tUser.nUserId)
                local arrConcernUser = self:GetUserFromRedis(arrConcern) --关注列表玩家

                local arrUserList = {}
                for _,tConcernUser in pairs(arrConcernUser) do
                    local tItem = self:GetUserListData(tConcernUser)
                    tItem.bIsConcern = true
                    tItem.bIsMic = (tUser.tMicUserData[tConcernUser.nUserId]~=nil)
                    table.insert(arrUserList,tItem)
                end
                table.insert(arrData,{nUserId=tUser.nUserId,nSitId=tUser.nSitId,arrUserList=arrUserList})
            end
        end
    end
    return arrData
end

--获取玩家结算时，关注这个玩家的其他玩家
--@params arrUserWinLose = {{nUserId,nTotalBetSum,nWinLoseSum,nWL},{nUserId,nTotalBetSum,nWinLoseSum,nWL},...}
--@return arrData = {{nUserId,nSitId,arrWinLoseInfo},{nUserId,nSitId,arrWinLoseInfo},...}
function VoiceRoom:GetNotifyUserByWinLose(arrUserWinLose)
    local arrData = {}
    for _,nUserId in pairs(self.arrRealUserId) do --遍历真人玩家
        local tUser = self.arrUserData[nUserId]
        if tUser then
            local arrWinLoseInfo = {}
            for k,v in pairs(arrUserWinLose) do
                if self:IsInUserConcern(tUser.nUserId,v.nUserId) then
                    --在这个真人玩家tUser.nUserId的关注列表里面
                    local t = {}
                    t.nUserId = v.nUserId
                    t.nTotalBetSum = v.nTotalBetSum
                    t.nWinLoseSum = v.nWinLoseSum
                    t.nWL = v.nWL
                    table.insert(arrWinLoseInfo,t)
                end
            end
            if #arrWinLoseInfo>0 then
                table.insert(arrData,{nUserId=tUser.nUserId,nSitId=tUser.nSitId,arrWinLoseInfo=arrWinLoseInfo})
            end
        end
    end
    return arrData
end

--获取玩家修改跟投锁时，关注这个玩家的其他玩家
--@params nChangeUserId:修改了跟投锁的玩家
--@return arrData = {{nUserId,nSitId},{nUserId,nSitId},...}
function VoiceRoom:GetNotifyUserByLockChange(nChangeUserId)
    local arrData = {}
    for _,nUserId in pairs(self.arrRealUserId) do
        local tUser = self.arrUserData[nUserId]
        if tUser then
            if self:IsInUserConcern(tUser.nUserId,nChangeUserId) or self:IsInUserRecommenList(tUser.nUserId,nChangeUserId) then
                table.insert(arrData,{nUserId=tUser.nUserId,nSitId=tUser.nSitId})
            end
        end
    end
    return arrData
end

--获取玩家下注成功时，查看这个玩家的其他玩家
--@params arrBetUserId = {[nUserId]=nUserId,[nUserId]=nUserId,...}
--@return arrData = {{nUserId,nSitId},{nUserId,nSitId},...}
function VoiceRoom:GetNotifyUserByBet(arrBetUserId)
    local arrData = {}
    for _,nUserId in pairs(self.arrRealUserId) do
        local tUser = self.arrUserData[nUserId]
        if tUser and tUser.nLookUserId then
            if arrBetUserId[tUser.nLookUserId] and self:IsInUserConcern(tUser.nUserId,tUser.nLookUserId) then
                table.insert(arrData,{nUserId=tUser.nUserId,nSitId=tUser.nSitId})
            end
        end
    end
    return arrData
end

--获取本局所有玩家的输赢数据
--@return arrUserWinLose = {nUserId,nTotalBetSum,nWinLoseSum,nWL}
function VoiceRoom:GetUserWinLoseThisRound()
    local arrUserWinLose = {}
    for k,v in pairs(self.arrUserWinLose) do
        table.insert(arrUserWinLose,v)
    end
    return arrUserWinLose
end

--保存本局所有玩家输赢数据
--@params arrUserWinLose = {nUserId,nTotalBetSum,nWinLoseSum,nWL}
function VoiceRoom:SetUserWinLoseThisRound(arrUserWinLose)
    for k,v in pairs(arrUserWinLose) do
        self.arrUserWinLose[v.nUserId] = v
    end
end

--搜索玩家
--@param nUserId 玩家id 
--@param sSearchKey 玩家的昵称或者玩家id
function VoiceRoom:SearchUser(nUserId,sSearchKey)
    local tMicUserId = {} --上麦玩家
    if self.arrUserData[nUserId] then
        local tUser = self.arrUserData[nUserId]
        for k,v in pairs(tUser.tMicUserData) do
            tMicUserId[v.nUserId] = v.nUserId
        end
    end

    --关注玩家的id
    local _,tConcern = self:GetConcernUserId(nUserId)

    local arrUserList = {}
    local arrData = tPublicRedis.GetRoomUserShareInfoBatch(self.nGameId,self.sTableId) --获取房间内玩家的数据
    local nCnt = 0
    for _,tUser in pairs(arrData) do
        if tUser.nUserId~=nUserId then
            local sName = BaseSink.decode(tUser.sName)
            if string.match(sName,sSearchKey) or tostring(tUser.nUserId)==sSearchKey then
                nCnt = nCnt + 1
                local tItem = self:GetUserListData(tUser)
                tItem.bIsMic = (tMicUserId[tUser.nUserId]~=nil)
                tItem.bIsConcern = (tConcern[tUser.nUserId]~=nil)
                table.insert(arrUserList,tItem)
                if nCnt>=10 then
                    break
                end
            end
        end
    end

    if nCnt>1 then
        table.sort(arrUserList,function (a, b)
            return a.nWinLoseSum>b.nWinLoseSum
        end)
    end

    return arrUserList
end

--获取关注了该玩家的玩家
function VoiceRoom:GetConcernByThisUser(nThisUserId)
    local arrUserData = {}
    for _,nUserId in pairs(self.arrRealUserId) do
        local tUser = self.arrUserData[nUserId]
        if tUser then
            if self:IsInUserConcern(tUser.nUserId,nThisUserId) then
                table.insert(arrUserData,{nUserId=tUser.nUserId,nSitId=tUser.nSitId})
            end
        end
    end
    return arrUserData
end

function VoiceRoom:Print(str,...)
	mlogger:info(string.format("Id=>"..self.sTableId.."=>"..str,...))
end

return VoiceRoom