local hotfix =require("HotFix")
local tBase = require("base") -- 基础功能接口


--tBase.Log("new =========patch start")

--[[
if LobbyPatchVersion ~=2 then
    LobbyPatchVersion=2
    tBase.Log("LobbyPatchVersion:"..LobbyPatchVersion)
    hotfix.HotUpdate("GameLogic","GameLogic")
    hotfix.HotUpdate("./lua/Lobby/ClientStart","./lua/Lobby/ClientStart")
end
]]