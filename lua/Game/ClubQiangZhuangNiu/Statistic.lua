local RecordDbr =require("RecordDbr")
local tPublicRedis =require("PublicRedis")

local tBase 	= require("base")         -- 基础功能接口
local cjson     = require("cjson")        -- json 

local Statistic = {}


function Statistic:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
    t.tUserIdToInfo ={}
    t.tRobotIdToTime={}
	return t
end

function Statistic:Init()
    self.tUserIdToInfo ={}
end

function Statistic:SetIsAndroid(nUserId,isAndroid,sNickName,sFaceID)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.isAndroid =isAndroid
    tInfo.sNickName =sNickName
    tInfo.sFaceID =sFaceID
    self.tUserIdToInfo[nUserId] =tInfo
    --tBase.Log("Statistic SetIsAndroid %s",cjson.encode(tInfo))
end

function Statistic:UserProfit(nUserId,nProfit)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.nProfit =nProfit
    self.tUserIdToInfo[nUserId] =tInfo
end

--持久化
--nClubId (大厅统一用0表示)
function Statistic:DoPersist(sTableId,nGameId,nClubId,nPool,nInsurPool,nGoldType,nKeepTime,sTableName,nGroupId)
    --tBase.Log("Statistic_TestMemory-------------#tUserIdToInfo_%d",#self.tUserIdToInfo)
    --tBase.Log("Statistic_TestMemory-------------#tRobotIdToTime_%d",#self.tRobotIdToTime)
    local arrTableUsers ={}
    local nNow =os.time()
    for nUserId,v in  pairs(self.tUserIdToInfo) do
        local tData ={}
        tData.nUserId =nUserId                                      --玩家Id
        tData.isAndroid =v.isAndroid                                --是否机器人
        tData.nProfitSum=v.nProfit                                  --总盈亏(包含保险)
        tData.nInPoolCount= 0                                       --1:有入池 0:否
        tData.nRaiseCountBFlop= 0                                   --1:有翻前加注 0:否
        tData.nAllInAndWinCount= 0                                  --1:AllIn且获胜 0:否
        tData.nTakeInAdd =0                                         --带入
        tData.nInsurance =0                                         --保险盈亏
        tData.sFaceId =v.sFaceID                                    --头像
        tData.sName =v.sNickName                                    --昵称
        
        if nClubId ==0 then
            local nLastTime =nil
            if v.isAndroid then
                nLastTime =self.tRobotIdToTime[nUserId] or 0
                self.tRobotIdToTime[nUserId]=nNow
            else
                nLastTime =tPublicRedis.GetLastTexaTime(sTableName,nUserId) or 0
                tPublicRedis.SetTexaTime(sTableName,nUserId,nNow)
            end
            local a =7200               --两小时为一局
            -- tData.nJuShu =((nNow//a) ~=(nLastTime//a)) and 1 or 0
            tData.nJuShu = (math.floor(nNow / a) ~= math.floor(nLastTime / a)) and 1 or 0
        end
        table.insert(arrTableUsers,tData)
    end

    local tTableInfo ={}
    tTableInfo.sTableId =sTableId
    tTableInfo.nGameId =nGameId
    tTableInfo.nClubId =nClubId
    tTableInfo.nPool =0
    tTableInfo.nInsurPool =0
    tTableInfo.nGoldType =nGoldType
    tTableInfo.nKeepTime =nKeepTime
    tTableInfo.sTableName =sTableName
    tTableInfo.nGroupId =nGroupId
    RecordDbr.TexaStatistic_WriteN(tTableInfo,arrTableUsers)     --持久化到数据库
    tPublicRedis.TexaStatistic_WriteN(tTableInfo,arrTableUsers)  --持久化到redis
end


return Statistic