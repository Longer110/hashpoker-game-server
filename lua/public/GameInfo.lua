
local tGameIdToInfo={}

--nType 1:非百人游戏 2:百人游戏
--isLive:是否为直播游戏
--直播百人游戏
tGameIdToInfo[121] ={nType =2,isLive=true} --直播鱼虾蟹
tGameIdToInfo[122] ={nType =2,isLive=true} --直播百家乐
tGameIdToInfo[129] ={nType =2,isLive=true} --直播足球
tGameIdToInfo[155] ={nType =2,isLive=true}  --骰宝
tGameIdToInfo[153] ={nType =2,isLive=true} --直播色蝶

--合集百人游戏
tGameIdToInfo[107] ={nType =2,isLive=false}  --合集百家乐
tGameIdToInfo[118] ={nType =2,isLive=false}  --合集百人扎金花
tGameIdToInfo[212] ={nType =2,isLive=false}  --合集鱼虾蟹
tGameIdToInfo[150] ={nType =2,isLive=false}  --合集色蝶
tGameIdToInfo[104] ={nType =2,isLive=false}  --百人牛牛

--直播非百人游戏
tGameIdToInfo[133] ={nType =1,isLive=true} --飞行棋
tGameIdToInfo[157] ={nType =1,isLive=true}  --nFellTree
tGameIdToInfo[159] ={nType =1,isLive=true}  --篮球
tGameIdToInfo[123] ={nType =1,isLive=true}  --德州

--合集非百人游戏
tGameIdToInfo[101] ={nType =1,isLive=false}  --看牌抢庄牛牛
tGameIdToInfo[102] ={nType =1,isLive=false}  --随机庄家牛牛
tGameIdToInfo[103] ={nType =1,isLive=false}  --通比牛牛

tGameIdToInfo[105] ={nType =1,isLive=false}  --扎金花
tGameIdToInfo[106] ={nType =1,isLive=false}  --21点
tGameIdToInfo[109] ={nType =1,isLive=false}  --抢庄百家乐
tGameIdToInfo[110] ={nType =1,isLive=false}  --通比百家乐

tGameIdToInfo[113] ={nType =1,isLive=false}  --三公

tGameIdToInfo[114] ={nType =1,isLive=false}  --抢庄21点
tGameIdToInfo[115] ={nType =1,isLive=false}  --通比21点
tGameIdToInfo[116] ={nType =1,isLive=false}  --牌九

tGameIdToInfo[120] ={nType =1,isLive=false}  --二八杠
tGameIdToInfo[124] ={nType =1,isLive=false}  --博灯
tGameIdToInfo[128] ={nType =1,isLive=false}  --高博

tGameIdToInfo[202] ={nType =1,isLive=false}  --做牌推到胡
tGameIdToInfo[203] ={nType =1,isLive=false}  --潮汕麻将
tGameIdToInfo[204] ={nType =1,isLive=false}  --100张
tGameIdToInfo[207] ={nType =1,isLive=false}  --二人麻将
tGameIdToInfo[208] ={nType =1,isLive=false}  --红中王
tGameIdToInfo[210] ={nType =1,isLive=false}  --血流麻将
tGameIdToInfo[125] ={nType =1,isLive=false}  --俱乐部德州


local function GetGameType(nGameId)
    local tGameInfo =tGameIdToInfo[nGameId]
    if tGameInfo then
        return tGameInfo.nType
    end
    return 1
end
local function IsLiveGame(nGameId)
    local tGameInfo =tGameIdToInfo[nGameId]
    if tGameInfo then
        return tGameInfo.isLive
    end
    return true
end
local function IsBaiRenGame(nGameId)
    return GetGameType(nGameId) ==2
end

local tem ={}
tem.IsBaiRenGame =IsBaiRenGame
tem.IsLiveGame =IsLiveGame

return tem