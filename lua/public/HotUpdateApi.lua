
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path

local tBase     = require("base") 

-- 需要热更使用的API（公共接口需要热更）
HotUpdateApi = {}

-- 可以热更（例子）
function HotUpdateApi.Sum(a, b)
    local tempSum = 0
    for i = 1, 10 do
        tempSum = tempSum + i
    end
    return tempSum
end

--可以热更（例子）
function HotUpdateApi.Add(a, b)
    if a < b then
        return a - b
    else
        return a + b
    end
end

-- 最大的数
function HotUpdateApi.Max(tNubmer)
    if tNubmer > 0 then
        for i, v in  pairs(tNubmer) do
            
        end
    end
end
  
 


return HotUpdateApi