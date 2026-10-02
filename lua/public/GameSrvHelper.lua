
--玩家所在场景信息

package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path

local tBase 	= require("base")

GameSrvHelper = {}
--根据ServerId跟游戏服通信 nClientId有则传入，没有则传0
function GameSrvHelper.PostToGameRoomBySrvId(nSrvId, nClientId, sData, nLen)
	local arrGame = tBase.m_centerRedis.Mo:keys("*_*_"..nSrvId.."_*")
	if #arrGame == 0 then return end

	tBase.PostToServer(arrGame[1], nClientId, sData, nLen)
end

return GameSrvHelper
