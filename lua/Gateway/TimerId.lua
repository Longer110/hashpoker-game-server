
--60000以下的id保留为Table里使用

local TimerId ={}
local arrFixTimerId ={}
for i=1,100 do
    table.insert(arrFixTimerId,60000+i)
end

function TimerId.GetATimerId()
    return table.remove(arrFixTimerId)
end

TimerId.TimerID_Maintain =TimerId.GetATimerId()

return TimerId