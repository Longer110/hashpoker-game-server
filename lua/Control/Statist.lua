
Statist = {}

-- 数量
function Statist.Count(t)
    return #t
end

-- 求和
function Statist.Sum(t)
    local sum = 0
    for i,v in pairs(t) do
        sum = sum + v
    end
    return sum
end

-- 最大值
function Statist.Max(t)
    return math.max(table.unpack(t))
end

-- 最小值
function Statist.Min(t)
    return math.min(table.unpack(t))
end

-- 均值
function Statist.Avg(t)
    return Statist.Sum(t)/Statist.Count(t)
end

-- 方差
function Statist.Varp(t, d)

    if d == nil then
        d = 0
    end

    local avg = Statist.Avg(t)
    local sub = 0
    for i,v in pairs(t) do
        sub = sub + (v - avg) ^ 2
    end

    if (Statist.Count(t) - d) == 0 then
        return 0
    end

    return sub / (Statist.Count(t) - d)
end

-- 标准差
function Statist.Stddevp(t, d)

    if d == nil then
        d = 0
    end

    return math.sqrt(Statist.Varp(t, d))
end

-- 协方差
function Statist.Cov(t1, t2)
    local avg1 = Statist.Avg(t1)
    local avg2 = Statist.Avg(t2)
    local temp_datas = {}

    for i,v in pairs(t1) do
        table.insert(temp_datas, (t1[i] - avg1) * (t2[i] - avg2))
    end

    local cov = Statist.Avg(temp_datas)
    return cov
end

-- 相关系数
function Statist.Ppcc(t1, t2, d)

    if d == nil then
        d = 0
    end

    local cov = Statist.Cov(t1, t2)
    local std1 = Statist.Stddevp(t1, d)
    local std2 = Statist.Stddevp(t2, d)
    if (std1*std2) == 0 then
        return 0
    end
    local ppcc = cov/(std1*std2)
    return ppcc
end

-- 阶乘
function Statist.Factorial(n)

    assert(n >= 0)

    n = n * 1.00

    if n == 0.00 then
        return 1.00
    end

    local nVal = 1.00
    for i = 2.00, n, 1.00 do
        nVal = nVal * i
    end

    return nVal
end

-- 组合
function Statist.Combination(n, m)

    assert((n - m) >= 0)

    n = n * 1.00
    m = m * 1.00

    return Statist.Factorial(n) / (Statist.Factorial(m) * Statist.Factorial(n - m))

end

-- 伯努利概型
-- n为试验的次数
-- k为n次试验中事件出现k次的概率
-- p为事件出现的概率
function Statist.Bernoulli(n, k, p)

    assert(p > 0 and p < 1)
    assert(n - k >= 0)

    n = n * 1.00
    k = k * 1.00
    p = p * 1.00

    return Statist.Combination(n, k) * math.pow(p, k) * math.pow(1-p, n - k)
end

return Statist