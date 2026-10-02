TableUtils = {}

function TableUtils:ReverseArray(arr)
    if arr == nil or #arr == 0 then
        return {}
    end
    local reversed = {}
    local len = #arr
    for i = 1, len do
        reversed[i] = arr[len - i + 1]
    end
    return reversed
end

return TableUtils