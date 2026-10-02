

-- 一致性哈希算法

local CRC = require('CRC32V2')

local ConsistentHashing = {}

local CONSISTENT_BUCKETS = 1024
local VIRTUAL_NODE = 160

local function hash_fn(key)
    return CRC.hash(key)
end

-- in-place quicksort
function quicksort(array,compareFunc)  
    quick(array,1,#array,compareFunc)  
end  

function quick(array,left,right,compareFunc)  
    if(left < right ) then  
        local index = partion(array,left,right,compareFunc)  
        quick(array,left,index-1,compareFunc)  
        quick(array,index+1,right,compareFunc)  
    end  
end  
  
function partion(array,left,right,compareFunc)  
    local key = array[left] 
    local index = left  
    array[index],array[right] = array[right],array[index]
    local i = left  
    while i< right do  
        if compareFunc( key,array[i]) then  
            array[index],array[i] = array[i],array[index]
            index = index + 1  
        end  
        i = i + 1  
    end  
    array[right],array[index] = array[index],array[right]
    return index;  
end  

-- binary search
function ConsistentHashing:chash_find(point)
    local mid, lo, hi = 1, 1, #self.CONTINUUM
    while 1 do
        if point <= self.CONTINUUM[lo][2] or point > self.CONTINUUM[hi][2] then
            return self.CONTINUUM[lo]
        end

        -- test middle point
        mid = lo + math.floor((hi-lo)/2)

        -- perfect match
        if point <= self.CONTINUUM[mid][2] and point > (mid > 1 and self.CONTINUUM[mid-1][2] or 0) then
            return self.CONTINUUM[mid]
        end

        -- too low, go up
        if self.CONTINUUM[mid][2] < point then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
end

function ConsistentHashing:init()
    local n = #self.HASH_PEERS
    if n == 0 then
        print("There is no backend servers")
        return
    end

    local C = {}
    for i,peer in ipairs(self.HASH_PEERS) do
        for k=1, math.floor(VIRTUAL_NODE * peer[1]) do
            local hash_data = peer[2] .. "-" .. (k - 1)
            table.insert(C, {peer[2], hash_fn(hash_data)})
        end
    end

    quicksort(C, function(a,b) return a[2] > b[2] end)
    self.CONTINUUM = C

--[[
    for i=1,#C do
        print(CONTINUUM[i][1],CONTINUUM[i][2])
    end
--]]

    local step = math.floor(0xFFFFFFFF / CONSISTENT_BUCKETS)

    self.BUCKETS = {}
    for i=1, CONSISTENT_BUCKETS do
        table.insert(self.BUCKETS, i, self:chash_find(math.floor(step * (i - 1))))
        -- print(BUCKETS[i][1],BUCKETS[i][2])
    end

end

function ConsistentHashing:get_upstream_crc32(point)
    return self.BUCKETS[(point % CONSISTENT_BUCKETS)+1][1]
end

function ConsistentHashing:get_upstream(key)
    local point = math.floor(hash_fn(key)) 
    return self:get_upstream_crc32(point)
end

function ConsistentHashing:add_upstream(upstream, weigth)
    weight = weight or 1
    table.insert(self.HASH_PEERS, {weight, upstream})
end


function ConsistentHashing:Clear()
    self.HASH_PEERS = {}
    self.CONTINUUM = {}
    self.BUCKETS = {}
end

function ConsistentHashing:new(s)  
    s = s or {} 
    setmetatable(s,{__index=self})

    s.HASH_PEERS = {}
    s.CONTINUUM = {}
    s.BUCKETS = {}

    return s  
end 

return ConsistentHashing

-- local redis_login= {
--     "10.50.1.3:11211",
--     "10.50.1.4:11211",
--     "10.50.1.5:11211",
-- }

-- for k, backend in ipairs(redis_login) do
--     chash_login.add_upstream(backend)
-- end
-- chash_login.init()

-- uid="309473941"
-- chash_login.chash_get_upstream(uid)