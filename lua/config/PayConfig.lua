local PayCfg = {}
local env = require("env")    -- 环境配置
--PayCfg.host = "http://127.0.0.1:4133"

PayCfg.host = "http://172.10.97.164:4133"
PayCfg.manageHost = env.adminHost
PayCfg.kafkaIP = "172.10.31.103:9092"

--0:固定 1:比例
PayCfg.withdrawCostType = 0 
PayCfg.WithdrawCostFixed = 3
PayCfg.WithdrawCostRate = 0.03


return PayCfg
