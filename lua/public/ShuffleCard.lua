-- knuth 洗牌算法
-- 时间复杂度：O(n)
-- 空间复杂度：O(n)
function table.shuffle(arrCards)
    local k = 0
    for n = #arrCards, 1, -1 do
      k = math.random(n)
      arrCards[n], arrCards[k] = arrCards[k], arrCards[n]
    end

    return arrCards
end


-- 自定义随机种子
-- 注意：不要直接os.time()做随机种子，在短时间内，可能会产生相同的随机数
function random_seed()
    local in_file = io.open("/dev/urandom", "r")
    if in_file ~= nil then
    	  local d= in_file:read(4)
        math.randomseed(os.time() + d:byte(1) + (d:byte(2) * 256) + (d:byte(3) * 65536) + (d:byte(4) * 4294967296))
    else
        math.randomseed(tostring(os.time()):reverse():sub(1, 7))            
    end   
    in_file.close()
end



-- 随机洗牌
function Shuffle(nPackCnt, arrCards)
    local nPackCnt = nPackCnt or 1
    assert(nPackCnt > 0)

    -- 调用自定义随机种子方法
    random_seed()

    local arrTmpCards = {}
    for i=1, nPackCnt do
        for _,nCard in ipairs(arrCards) do
            table.insert(arrTmpCards, nCard)
        end
    end

    --shuffle cards
    table.shuffle(arrTmpCards)
    return arrTmpCards
end

-- test
-- 标准德州牌
-- local arrPackOfCards={
--     0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1a,0x1b,0x1c,0x1d,	--方块 A~K
--     0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2a,0x2b,0x2c,0x2d,	--梅花 A~K
--     0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3a,0x3b,0x3c,0x3d,	--红桃 A~K
--     0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4a,0x4b,0x4c,0x4d,   --黑桃 A~K
-- }

-- -- 短牌:没有2-5
-- local arrShortPackOfCards={
--     0x11,0x16,0x17,0x18,0x19,0x1a,0x1b,0x1c,0x1d,	--方块 A~K
--     0x21,0x26,0x27,0x28,0x29,0x2a,0x2b,0x2c,0x2d,	--梅花 A~K
--     0x31,0x36,0x37,0x38,0x39,0x3a,0x3b,0x3c,0x3d,	--红桃 A~K
--     0x41,0x46,0x47,0x48,0x49,0x4a,0x4b,0x4c,0x4d,   --黑桃 A~K
-- }

-- for i = 0, 10 do
--     local arrCard = Shuffle(1, arrPackOfCards) 
--      local result = ""
--      for i, v in ipairs(arrTmpCards) do 
--          result = result .. string.format("%02x", v)
--          result = result .. " "
--      end

--      print(result)   
-- end