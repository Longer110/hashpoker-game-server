--[[
	服务器配置需要从数据库mysql加载
	服务器IP 和 Port ,
	配置文件禁止写逻辑,只存储数据
-- ]]
package.path = "../lua/?.lua;./lua/?.lua;" .. package.path
package.path = "../lua/base/?.lua;./lua/base/?.lua;" .. package.path


ServerInfo = {
    nServerId = 0,
    nPort = 0,
    SType = -1,     --游戏列表：
    nIp = "",  
    nStype = -1,
    nSocketType = 0,
    sName = "-1",
}
 

return ServerInfo
