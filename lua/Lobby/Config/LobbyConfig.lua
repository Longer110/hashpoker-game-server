 -- 大厅服  加载配置信息 逻辑（服务器配置，商城配置）
package.path = require("./lua/Lobby/Head").path

local tBase        = require("base")            -- 基础功能接口
local tname        = require("typename")     -- 类弄定义接口
local ProtoMgr     = require("ProtoManager") -- 协议管理对象 
local tGameCfg     = require("GameListConfig")   -- 道具配置

LobbyConfig = {}



 -- 加载 配置（服务器，商城 ，奖励）
function LobbyConfig.Web_LoadConfig()

    tGameCfg.Web_GameListConfig()  -- 商城配置

    return 
end 

 -- 加载 配置
function LobbyConfig.LoadConfig()

    tBase.Log(" 加载   游戏列表配置  ......")
    tGameCfg.LoadGameListConfig()     

    --加载金币房配置
    tBase.SetTimer(1006, 1000*5, 1, LobbyConfig.Check_Load_Lobby_Config) 

end


function LobbyConfig.Check_Load_Lobby_Config()
    if tGameCfg.boLoadFinish == true then
        tBase.Log(" 游戏列表配置  完毕... 111 ")      
    else
        tBase.Log(" 游戏列表配置    失败...  重新请求加载")
        tGameCfg.LoadGameListConfig()     --商城配置
      --  tBase.SetTimer(1007, 1000*3, 1, LobbyConfig.Check_Load_Lobby_Config)
    end

    return
end


return LobbyConfig
