
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path
package.path = "../lua/Lobby/Config/?.lua;./lua/Lobby/Config/?.lua;" .. package.path
package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path
package.path = "../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" .. package.path

local  tBase = require("base")
local tRedisdefine = require("redisdefine")
local tJson = require("cjson")
local mlogger = require("logger")
local tConfig =require("GameConfig") -- 

GameCfgRedis = {
    arrRoomList = {},
    NiuNiuRoom = {
        [102] = {5, 10, 15, 20, 25}
    }
}

-- 获取游戏配置房间列表
function GameCfgRedis.GetGameConifg(nGameType, nLevel)
    -- local tData = GameCfgRedis.GetGameRoomData()
    local  tData = tConfig.GetRoomList(nGameType)
     for k , v in pairs (tData) do
        -- mlogger:info(tJson.encode(v))
        if v.nGameId == nGameType and v.nRoomId == nLevel then
            return v 
        end
     end

     return nil
end

-- 获取房间的列表
function GameCfgRedis.GetGameRoomData()
    mlogger:info("GetGameRoomData")
    if #GameCfgRedis.arrRoomList > 0 then
        mlogger:info(#GameCfgRedis.arrRoomList)
        return GameCfgRedis.arrRoomList
    else 
       local sData =  tBase.m_MyRedisData[1].redis:hget(tRedisdefine.Lobby_key.GameConfigRoom, "room")
       mlogger:info(sData)
       local tData = tJson.decode(sData)
      
       GameCfgRedis.arrRoomList = tData
        return GameCfgRedis.arrRoomList
    end
end

return GameCfgRedis