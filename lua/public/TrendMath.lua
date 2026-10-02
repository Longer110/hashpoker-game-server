--露珠图  好路判断
local TrendMath = {
    nHe = 0,
    nXian = 1,
    nZhuang = 2,
    tTrendType = {
        LongZhuang = 1, --长庄
        LongXian = 2, --长闲
        SingleJump = 3,--大路单跳
        DoubleJump = 4,--大路双跳
        JumpZhuang = 5,--逢庄跳
        JumpXian = 6,--逢闲跳
        OneTwoZhuang = 7,--一厅两房（庄）
        OneTwoXian = 8,--一厅两房（闲）
        SeriesZhuang = 9,--逢庄连
        SeriesXian = 10,--逢闲连
        Clap = 11,--拍拍黐
        Slope = 12,--斜坡路
        LongSingleJump = 13,--长路转单挑
    },
}

--根据走势图获取下注区域
--@params arrTrend={0,1,2,...} 0:和 1:闲 2:庄
--@retrun nBetArea 0:和 1:闲 2:庄
function TrendMath.GetBetAreaByTrend(arrTrend) 
    local isLongSingleJump,nBrea = TrendMath.IsLongSingleJump(arrTrend)
    if isLongSingleJump then  --长路转单挑  
        if not nBrea then 
            nBrea = arrTrend[#arrTrend-1] or 1 
        end 
        return TrendMath.tTrendType.LongSingleJump,nBrea --选前一列的结果
    end
    local arrSerTrend = TrendMath.ToSerialization(arrTrend) --序列化数组 
    arrSerTrend = TrendMath.Reverse(arrSerTrend)--反转序列化数组   


    if TrendMath.IsSlope(arrSerTrend) then
        --是否是斜坡路
        if #arrSerTrend[1]>#arrSerTrend[2] then --最后一列比前一列大，选前一列的结果
            return TrendMath.tTrendType.Slope,arrSerTrend[2][1]
        else
            return TrendMath.tTrendType.Slope,arrSerTrend[1][1] --最后一列小于等于前一列，继续选本列的结果
        end
    end

    if TrendMath.IsDoubleJump(arrSerTrend) then
        --是否是大路双跳
        if #arrSerTrend[1]==2 then --最后一列满2个，选前一列的结果
            return TrendMath.tTrendType.DoubleJump,arrSerTrend[2][1]
        else
            return TrendMath.tTrendType.DoubleJump,arrSerTrend[1][1] --最后一列不满2个，选本列的结果
        end
    end

    if TrendMath.IsSingleJump(arrSerTrend) then
        --是否符合大路单跳
        return TrendMath.tTrendType.SingleJump,arrSerTrend[2][1] --选前一列的结果
    end

    if TrendMath.IsClap(arrSerTrend) then
        --是否符合拍拍黐
        if #arrSerTrend[1]<=3 then --最后一列小于等于两个结果，选本列的结果
            return TrendMath.tTrendType.Clap,arrSerTrend[1][1]
        end
    end

    if TrendMath.IsOneTwoZhuang(arrSerTrend) then
        --是否符一厅两房（庄）
        if #arrSerTrend[1]==2 then --如果最后一列结果有两个，选庄
            return TrendMath.tTrendType.OneTwoZhuang,TrendMath.nZhuang
        elseif #arrSerTrend[1]==1 then --如果最后一列结果只有一个，选闲
            return TrendMath.tTrendType.OneTwoZhuang,TrendMath.nXian
        end
    end

    if TrendMath.IsOneTwoXian(arrSerTrend) then
        --是否符一厅两房（闲）
        if #arrSerTrend[1]==2 then --如果最后一列结果有两个，选闲
            return TrendMath.tTrendType.OneTwoXian,TrendMath.nXian
        elseif #arrSerTrend[1]==1 then --如果最后一列结果只有一个，选庄
            return TrendMath.tTrendType.OneTwoXian,TrendMath.nZhuang
        end
    end

    if TrendMath.IsJumpZhuang(arrSerTrend) then
        --是否符合逢庄跳
        return TrendMath.tTrendType.JumpZhuang,TrendMath.nXian
    end

    if TrendMath.IsJumpXian(arrSerTrend) then
        --是否符合逢闲跳
        return TrendMath.tTrendType.JumpXian,TrendMath.nZhuang
    end

    if TrendMath.IsSeriesZhuang(arrSerTrend) then
        --是否符合逢庄连
        return TrendMath.tTrendType.SeriesZhuang,TrendMath.nZhuang
    end

    if TrendMath.IsSeriesXian(arrSerTrend) then
        --是否符合逢闲连
        return TrendMath.tTrendType.SeriesXian,TrendMath.nXian
    end

    if TrendMath.IsLongZhuang(arrSerTrend) then
        --是否长庄
        return TrendMath.tTrendType.LongZhuang,TrendMath.nZhuang
    end

    if TrendMath.IsLongXian(arrSerTrend) then
        --是否长闲
        return TrendMath.tTrendType.LongXian,TrendMath.nXian 
    end
end

--把趋势图序列化,连续相同的结果放一列
--@params arrTrend={0,1,2,...} 0:和 1:闲 2:庄
--@return arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...}
function TrendMath.ToSerialization(arrTrend)
    local arrSerTrend = {}
    for i=1,#arrTrend do
        if i==1 then
            arrSerTrend[1] = {arrTrend[i]}
        elseif arrTrend[i]==arrTrend[i-1] then
            --目前的结果与上一个相同，放同一列
            table.insert(arrSerTrend[#arrSerTrend],arrTrend[i])
        elseif arrTrend[i]~=arrTrend[i-1] then
            --目前的结果与上一个不相同，放新的一列
            arrSerTrend[#arrSerTrend+1] = {arrTrend[i]}
        end
    end
    return arrSerTrend
end

--把序列化后的走势图反转
--@params arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun arrNewSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
function TrendMath.Reverse(arrSerTrend)
    local arrNewSerTrend = {}
    if #arrSerTrend>0 then
        for i=#arrSerTrend,1,-1 do
            table.insert(arrNewSerTrend,arrSerTrend[i])
        end
    end
    return arrNewSerTrend
end

--是否是长庄(连续有4个或4个以上的庄,中间有和并不影响，庄-庄-和-庄-庄的结果仍为长庄)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsLongZhuang(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>0 then
        local nCnt = 0
        for i=1,nLen do
            if arrSerTrend[i][1]==TrendMath.nXian then --中间遇到闲，返回false
                return false
            elseif arrSerTrend[i][1]==TrendMath.nZhuang then --中间遇到庄，计数
                nCnt = nCnt + #arrSerTrend[i]
            end

            if nCnt>=4 then
                return true
            end
        end
    end
    return false
end

--是否是长闲(连续有4个或4个以上的闲,中间有和并不影响，闲-闲-和-闲-闲的结果仍为长闲)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsLongXian(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>0 then
        local nCnt = 0
        for i=1,nLen do
            if arrSerTrend[i][1]==TrendMath.nXian then --中间遇到闲，计数
                nCnt = nCnt + #arrSerTrend[i]
            elseif arrSerTrend[i][1]==TrendMath.nZhuang then --中间遇到庄，返回false
                return false
            end

            if nCnt>=4 then
                return true
            end
        end
    end
    return false
end

--是否是大路单跳(单个庄闲连环追逐地出现，（庄闲开头不限）连续4个或4个以上,如庄闲庄闲)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsSingleJump(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen >= 4 then
        for i=1,4 do --查看前4列
            if #arrSerTrend[i]~=1 then --每列不是只有一个结果
                return false
            end
            local nLast = arrSerTrend[i][1] --本列结果
            if nLast~=TrendMath.nZhuang and nLast~=TrendMath.nXian then --不是庄或闲
                return false
            end
        end
        if arrSerTrend[1][1]==arrSerTrend[3][1] and arrSerTrend[2][1]==arrSerTrend[4][1] 
            and arrSerTrend[1][1]~=arrSerTrend[2][1] then
            --1,3列相同 and 2,4列相同 and 1,2列不同
            return true
        end
    end
    return false
end

--是否是大路双跳(两个庄闲连环追逐地出现，（庄闲开头不限）连续4个或4个以上,如庄庄闲闲庄庄闲闲)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsDoubleJump(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>=4 then
        if #arrSerTrend[nLen]==1 and nLen>=5 then --最后一列是一个,如庄庄闲闲庄庄闲闲庄
            for i=1,5 do --查看5列
                if i~=1 and #arrSerTrend[i]~=2 then --每列不是只有两个结果
                    return false
                end
                local nLast = arrSerTrend[i][1] --本列结果
                if nLast~=TrendMath.nZhuang and nLast~=TrendMath.nXian then --不是庄或闲
                    return false
                end
            end
            if arrSerTrend[1][1]==arrSerTrend[3][1] and arrSerTrend[1][1]==arrSerTrend[5][1] 
            and arrSerTrend[2][1]==arrSerTrend[4][1] and arrSerTrend[1][1]~=arrSerTrend[2][1] then
                --1,3,5列相同 and 2,4列相同 and 1,2列不同
                return true
            end
        elseif #arrSerTrend[nLen]==2 then--最后一列是两个
            for i=1,4 do --查看前4列
                if #arrSerTrend[i]~=2 then --每列不是只有两个结果
                    return false
                end
                local nLast = arrSerTrend[i][1] --本列结果
                if nLast~=TrendMath.nZhuang and nLast~=TrendMath.nXian then --不是庄或闲
                    return false
                end
            end
            if arrSerTrend[1][1]==arrSerTrend[3][1] and arrSerTrend[2][1]==arrSerTrend[4][1] 
                and arrSerTrend[1][1]~=arrSerTrend[2][1] then
                --1,3列相同 and 2,4列相同 and 1,2列不同
                return true
            end
        end
    end
    return false
end

--是否是逢庄跳(每逢出现庄，下把就一定闲，连续3次或3次以上,如庄闲闲庄闲闲庄)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsJumpZhuang(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>=5 then
        if arrSerTrend[1][1]==TrendMath.nZhuang and #arrSerTrend[1]==1 then
            local nCnt = 0
            for i=2,nLen do
                if arrSerTrend[i][1]==TrendMath.nZhuang then --找到庄
                    if #arrSerTrend[i]~=1 then --这一列数目不是1，返回false
                        return false
                    end
                    if arrSerTrend[i-1][1]~=TrendMath.nXian then --庄的下一列不是闲，返回false
                        return false
                    end
                    nCnt = nCnt + 1
                end
                if nCnt>=2 then
                    break
                end
            end
            return true
        end
    end
    return false
end

--是否是逢闲跳(每逢出现闲，下把就一定庄，连续3次或3次以上,如闲庄庄闲庄闲)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsJumpXian(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>=5 then
        if arrSerTrend[1][1]==TrendMath.nXian and #arrSerTrend[1]==1 then
            local nCnt = 0
            for i=2,nLen do
                if arrSerTrend[i][1]==TrendMath.nXian then --找到闲
                    if #arrSerTrend[i]~=1 then --这一列数目不是1，返回false
                        return false
                    end
                    if arrSerTrend[i-1][1]~=TrendMath.nZhuang then --闲的下一列不是庄，返回false
                        return false
                    end
                    nCnt = nCnt + 1
                end
                if nCnt>=2 then
                    break
                end
            end
            return true
        end
    end
    return false
end

--是否是一厅两房(庄)(庄-闲-闲这三个结果连续出现两次或以上,如庄闲闲庄闲闲)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsOneTwoZhuang(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>=4 then
        if arrSerTrend[1][1]==TrendMath.nXian and #arrSerTrend[1]==2 then
            --第1列是两个闲,如庄闲闲庄闲闲
            for i=1,4 do
                local nLast = arrSerTrend[i][1] --本列结果
                if nLast~=TrendMath.nZhuang and nLast~=TrendMath.nXian then --不是庄或闲
                    return false
                end

                if i%2==1 and (#arrSerTrend[i]~=2 or nLast~=TrendMath.nXian) then --单列，不是两个闲
                    return false
                elseif i%2==0 and (#arrSerTrend[i]~=1 or nLast~=TrendMath.nZhuang) then --双列，不是一个庄
                    return false
                end
            end

            return true
        elseif arrSerTrend[1][1]==TrendMath.nXian and #arrSerTrend[1]==1 and nLen>=6 then
            --第1列是一个闲,如庄闲闲庄闲闲庄闲
            for i=1,6 do
                local nLast = arrSerTrend[i][1] --本列结果
                if nLast~=TrendMath.nZhuang and nLast~=TrendMath.nXian then --不是庄或闲
                    return false
                end

                if i~=1 and i%2==1 and (#arrSerTrend[i]~=2 or nLast~=TrendMath.nXian) then --单列，不是两个闲(除了第一列)
                    return false
                elseif i%2==0 and (#arrSerTrend[i]~=1 or nLast~=TrendMath.nZhuang) then --双列，不是一个庄
                    return false
                end
            end
            return true
        elseif arrSerTrend[1][1]==TrendMath.nZhuang and #arrSerTrend[1]==1 and nLen>=5 then
            --第1列是一个庄,如庄闲闲庄闲闲庄
            for i=1,5 do
                local nLast = arrSerTrend[i][1] --本列结果
                if nLast~=TrendMath.nZhuang and nLast~=TrendMath.nXian then --不是庄或闲
                    return false
                end

                if i%2==1 and (#arrSerTrend[i]~=1 or nLast~=TrendMath.nZhuang) then --单列，不是一个庄
                    return false
                elseif i%2==0 and (#arrSerTrend[i]~=2 or nLast~=TrendMath.nXian) then --双列，不是两个闲
                    return false
                end
            end
            return true
        end
    end
    return false
end

--是否是一厅两房(闲)(闲-庄-庄这三个结果连续出现两次或以上,如闲庄庄闲庄庄)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsOneTwoXian(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>=4 then
        if arrSerTrend[1][1]==TrendMath.nZhuang and #arrSerTrend[1]==2 then
            --第1列是两个庄,如闲庄庄闲庄庄
            for i=1,4 do
                local nLast = arrSerTrend[i][1] --本列结果
                if nLast~=TrendMath.nZhuang and nLast~=TrendMath.nXian then --不是庄或闲
                    return false
                end

                if i%2==1 and (#arrSerTrend[i]~=2 or nLast~=TrendMath.nZhuang) then --单列，不是两个庄
                    return false
                elseif i%2==0 and (#arrSerTrend[i]~=1 or nLast~=TrendMath.nXian) then --双列，不是一个闲
                    return false
                end
            end

            return true
        elseif arrSerTrend[1][1]==TrendMath.nZhuang and #arrSerTrend[1]==1 and nLen>=6 then
            --第1列是一个庄,如闲庄庄闲庄庄闲庄
            for i=1,6 do
                local nLast = arrSerTrend[i][1] --本列结果
                if nLast~=TrendMath.nZhuang and nLast~=TrendMath.nXian then --不是庄或闲
                    return false
                end

                if i~=1 and i%2==1 and (#arrSerTrend[i]~=2 or nLast~=TrendMath.nZhuang) then --单列，不是两个庄(除了第一列)
                    return false
                elseif i%2==0 and (#arrSerTrend[i]~=1 or nLast~=TrendMath.nXian) then --双列，不是一个闲
                    return false
                end
            end
            return true
        elseif arrSerTrend[1][1]==TrendMath.nXian and #arrSerTrend[1]==1 and nLen>=5 then
            --第1列是一个闲,如闲庄庄闲庄庄闲
            for i=1,5 do
                local nLast = arrSerTrend[i][1] --本列结果
                if nLast~=TrendMath.nZhuang and nLast~=TrendMath.nXian then --不是庄或闲
                    return false
                end

                if i%2==1 and (#arrSerTrend[i]~=1 or nLast~=TrendMath.nXian) then --单列，不是一个闲
                    return false
                elseif i%2==0 and (#arrSerTrend[i]~=2 or nLast~=TrendMath.nZhuang) then --双列，不是两个庄
                    return false
                end
            end
            return true
        end
    end
    return false
end

--是否是逢庄连(出现前两次开庄时皆有连庄两次或以上,到第三次开庄时,如庄庄闲庄庄闲庄)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsSeriesZhuang(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>=5 then
        if #arrSerTrend[1]==1 and arrSerTrend[1][1]==TrendMath.nZhuang  then
            --第1列是一个庄
            if arrSerTrend[2][1]==TrendMath.nXian then
                if #arrSerTrend[3]>=2 and arrSerTrend[3][1]==TrendMath.nZhuang then
                    if arrSerTrend[4][1]==TrendMath.nXian then
                        if #arrSerTrend[5]>=2 and arrSerTrend[5][1]==TrendMath.nZhuang then
                            --前两次开庄都连续两次或以上
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

--是否是逢闲连(出现前两次开闲时皆有连闲两次或以上,到第三次开闲时,如闲闲庄闲闲庄闲)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsSeriesXian(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>=5 then
        if #arrSerTrend[1]==1 and arrSerTrend[1][1]==TrendMath.nXian  then
            --第1列是一个闲
            if arrSerTrend[2][1]==TrendMath.nZhuang then
                if #arrSerTrend[3]>=2 and arrSerTrend[3][1]==TrendMath.nXian then
                    if arrSerTrend[4][1]==TrendMath.nZhuang then
                        if #arrSerTrend[5]>=2 and arrSerTrend[5][1]==TrendMath.nXian then
                            --前两次开闲都连续两次或以上
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

--是否是拍拍黐(中间3个(庄闲不限)且相邻两列的庄闲都有两个或两个以上,如闲闲庄庄庄闲闲)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsClap(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>=3 then
        for i=1,3 do
            if arrSerTrend[i][1]~=TrendMath.nZhuang and arrSerTrend[i][1]~=TrendMath.nXian then
                return false
            end
            if #arrSerTrend[i]==3 then
                if arrSerTrend[i+1] and #arrSerTrend[i+1]>=2 and (arrSerTrend[i+1][1]==TrendMath.nZhuang or arrSerTrend[i+1][1]==TrendMath.nXian) then
                    if arrSerTrend[i-1] and #arrSerTrend[i-1]>=2 and (arrSerTrend[i-1][1]==TrendMath.nZhuang or arrSerTrend[i-1][1]==TrendMath.nXian) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--是否是斜坡路(后一列比前一列多一个的，4行或连续4行以上的，如庄闲闲庄庄庄闲闲闲闲)
--@params 反转后的序列化数组arrSerTrend = {[1,1,1],[2],[0,0,0],[2,2,2],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsSlope(arrSerTrend)
    local nLen = #arrSerTrend
    if nLen>=4 then
        if arrSerTrend[1][1]==TrendMath.nXian or arrSerTrend[1][1]==TrendMath.nZhuang then
            if arrSerTrend[2][1]==TrendMath.nXian or arrSerTrend[2][1]==TrendMath.nZhuang then
                local nLenFirst = #arrSerTrend[1]
                local nLenSecond = #arrSerTrend[2]
                if nLenFirst>=4 and nLenFirst>nLenSecond then
                    for i=2,nLen do
                        if arrSerTrend[i][1]==TrendMath.nXian and arrSerTrend[i][1]==TrendMath.nZhuang  then
                            return false
                        end
                        if (nLenFirst-i+1) ~= #arrSerTrend[i] then
                            return false
                        end
                    end
                    return true
                elseif nLenFirst<=nLenSecond and nLenSecond>=4 then
                    for i=3,nLen do
                        if arrSerTrend[i][1]==TrendMath.nXian and arrSerTrend[i][1]==TrendMath.nZhuang  then
                            return false
                        end
                        if (nLenSecond-i+2) ~= #arrSerTrend[i] then
                            return false
                        end
                    end
                    return true
                end
            end
        end
    end
    return false
end

--长路转单挑 (出现“长庄”或“长闲”后，再出现 “大路单跳” )
--@params 反转后的序列化数组arrSerTrend = {[1,1,1,1],[2],[1],[2],[1],...} 0:和 1:闲 2:庄
--@retrun true:是  false:不是
function TrendMath.IsLongSingleJump(arrTrend) 
    -- 去 和:  备注：当好路的大路上出现和局时，好路的模型还是保持，所以出现和局不影响判断好路。
    local arr = {}
    for _, v in ipairs(arrTrend) do
        if v ~= TrendMath.nHe then 
            table.insert(arr,v)
        end         
    end   
    if arr and #arr == 0 then return false end
    if arr and #arr < 8 then return false end
    -- m.Log("_IsLongSingleJump    arrTrend: %s arr: %s ",cjson.encode(arrTrend),cjson.encode(arr)) 
    local arrSerTrend1 = TrendMath.ToSerialization(arr) --序列化数组  
    local arrSerTrend = TrendMath.Reverse(arrSerTrend1)--反转序列化数组    
    -- m.Log("_IsLongSingleJump     arrSerTrend_1: %s %s  ",cjson.encode(arrSerTrend_1),cjson.encode(arrSerTrend))

    local nLen = #arrSerTrend
    if nLen < 5 then return false end 
    if TrendMath.IsSingleJump(arrSerTrend) then --是否符合大路单跳 
        for i = 5, nLen, 1 do        
            if #arrSerTrend[i] == 2 or #arrSerTrend[i] == 3 then  
                break 
            end  
            if arrSerTrend[i][1] ~= arrSerTrend[i-1][1] then  
                if #arrSerTrend[i] >= 4 and arrSerTrend[i][1]==arrSerTrend[1][1] then 
                    return true,arrSerTrend[2][1]
                end    
            end          
        end 
    end 
    return false
end
 
--获取好路类型名字
function TrendMath.GetGoodTrendNameByType(nType)
    local sName = ""
    if nType==1 then
        sName = "长庄"
    elseif nType==2 then 
        sName = "长闲"
    elseif nType==3 then 
        sName = "大路单跳"
    elseif nType==4 then 
        sName = "大路双跳"
    elseif nType==5 then 
        sName = "逢庄跳"
    elseif nType==6 then 
        sName = "逢闲跳"
    elseif nType==7 then 
        sName = "一厅两房（庄）"
    elseif nType==8 then 
        sName = "一厅两房（闲）"
    elseif nType==9 then 
        sName = "逢庄连"
    elseif nType==10 then 
        sName = "逢闲连"
    elseif nType==11 then 
        sName = "拍拍黐"
    elseif nType==12 then 
        sName = "斜坡路"
    elseif nType==13 then 
        sName = "长路转单挑"
    end
    return sName
end


function __Test() 
    -- local m = require("base") -- 基础功能接口 
    -- local cjson = require("cjson") -- json 

    -- local TrendMath =require("TrendMath")
    -- local arrTrend_1 = {}
    -- arrTrend_1[1] ={1,2,1,2}     -- 大路转单挑
    -- arrTrend_1[2] ={1,2,0,1,2}   -- Y
    -- arrTrend_1[3] ={2,1,2,1,2}   -- Y
    -- arrTrend_1[4] ={1,1,2,1,2}   -- N 
    -- arrTrend_1[5] ={0,1,2,1,2}   -- Y
    -- arrTrend_1[6] ={1,2,0,1,2,1,2}   -- Y
    -- arrTrend_1[7] ={2,1,0,1,2,1,2}   -- Y
    -- arrTrend_1[8] ={2,0,2,2,2,0,1,2,0,1,2,0,1,2,1}   -- Y
    -- arrTrend_1[9] ={2,0,1,1,1,0,1,2,0,1,2,0,1,2,1}   -- Y
 
    -- local nIndex = 9
    -- local arrTrend =arrTrend_1[nIndex]  
    -- local nType,nBetArea = TrendMath.GetBetAreaByTrend(arrTrend)   
    -- if nType and nType > 0 then 
    --     local sName = TrendMath.GetGoodTrendNameByType(nType) 
    --     m.Log("__Test  有好路    nType_%d  %s  nBetArea_%d  %s ",nType or -1,sName,nBetArea or -1,cjson.encode(arrTrend)) 
    -- else 
    --     m.Log("__Test   无好路   nType_%d  nBetArea_%d   ",nType or -1,nBetArea or -1) 
    -- end       
end 

return TrendMath