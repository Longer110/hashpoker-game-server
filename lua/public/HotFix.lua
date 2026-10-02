 HotFix = {

}

local function collect_uv(f, uv)
    local i = 1
    while true do
        local name, value = debug.getupvalue(f, i)
        if name == nil then -- 当所有上值收集完时，跳出循环
            break
        end
        if not uv[name] then
            uv[name] = { func = f, index = i } -- 这里就会收集到旧函数 print_index 所有的上值，包括变量 index
            if type(value) == "function" then
                collect_uv(value, uv)
            end
        end
        i = i + 1
    end
end

local function update_func(f, uv) 
    local i = 1
    while true do
        local name, value = debug.getupvalue(f, i)
        if name == nil then -- 当所有上值收集完时，跳出循环
            break
        end
        -- value 值为空(改)，并且这个 name 在 旧的函数中存在
        if uv[name] then 
            local desc = uv[name]
            -- 将新函数 f 的第 i 个上值引用旧模块 func 的第 index 个上值
            debug.upvaluejoin(f, i, desc.func, desc.index)
        end
         -- 只对 function 类型进行递归更新，对基本数据类型（number、boolean、string） 不管
        if type(value) == "function" then
            update_func(value, uv)
        end
        i = i + 1
    end
end

local function update(old, new)
    local uv = {}
    collect_uv(old, uv)
    update_func(new, uv)
end

--旧模块中的状态变量
function HotFix.HotUpdate(sOldModuleName,sNewModuleName)
    local old_module =require(sOldModuleName)
    local tload = package.loaded[sOldModuleName] 
	package.loaded[sOldModuleName] = nil
	local new_module = require(sNewModuleName)
	for valueName,newValue in pairs(new_module) do
		local oldValue =old_module[valueName]
		local isFunctionTypeBoth=( type(oldValue)=="function" and type(newValue) == "function" )
        if  isFunctionTypeBoth then 
			if isFunctionTypeBoth then
				update(oldValue,newValue)
			end			
        end
        old_module[valueName] = newValue
	end
	package.loaded[sOldModuleName]=old_module
    return new_module
end

-- 进行热更新 : 1:文件,2:全局,3:文件中func
function HotFix.WebUpdateFile(tData)    
    if not tData.nType or not tData.sUpdataFile then 
        return 
    end 
    local modulename =  tData.sUpdataFile
    local funcname =  tData.funcname 

    -- 处理 全局函数(注册协议回调函数)
    local function OverrallFunc(Old_module,New_module)
        local arrOverrallAddress = {}  --  全局函数(注册协议回调函数 地址)
        local nCnt = 0
        for k,v in pairs(_G) do
            if type(v) == "table" and type(v.callback) == "function" and v.callback then  
                arrOverrallAddress[v.callback] = k
                nCnt = nCnt + 1 
            end         
        end 
        if nCnt == 0 then return end 
        local nCnt1 = 0
        local arrUpdateAddress = {}
        for valueName,value in pairs(Old_module) do
            if type(value) == "function" and arrOverrallAddress[value] then 
                arrUpdateAddress[valueName] = arrOverrallAddress[value]
                nCnt1 = nCnt1 + 1 
            end         
        end 
        if nCnt1 == 0 then return end         
        for valueName,newValue in pairs(New_module) do
            if type(newValue) == "function" and arrUpdateAddress[valueName] then 
                local scallback = arrUpdateAddress[valueName] 
                if _G[scallback] and _G[scallback].callback then 
                    _G[scallback].callback = newValue
                    base.Log("_OverrallFunc 全局注册回调函数 module: %s=[%s]  _G[%s]  newValue: %s   ",modulename,valueName,scallback,newValue)    
                end 
            end 
        end 
        return 
    end

    -- 处理全局模块
    local function OverrallModulename(New_modulename)
        if New_modulename then 
            modulename = New_modulename
        end 
        if not _G[modulename] then 
            base.Log("_OverrallModulename  _G[%s] is nil ",modulename)             
            return 
        end 
        local Old_module = _G[modulename]
        _G[modulename] =nil 
        package.loaded[modulename] = nil 
        New_module = require(modulename) 
        _G[modulename] =New_module 
        package.loaded[modulename] = New_module 
        Old_module = nil 
        New_module = nil 
        base.Log("_OverrallModulename  _G[%s]  Success ",modulename)    
        return 
    end
    
    -- 处理 单独模块
    local function UpdateFile()   
        local Old_module = require(modulename)
        local arrOldModule = {}
        for k,v in pairs(Old_module) do  
            arrOldModule[k] = v 
            -- if type(v) == "function" then 
            --     base.Log("_WebUpdateFile _Old   k: %s    %s ",k,v)        
            -- end 
        end 
        local New_module = HotFix.HotUpdate(modulename,modulename)
        -- for k,v in pairs(New_module) do 
        --     if type(v) == "function" then 
        --         base.Log("_WebUpdateFile _New   k: %s    %s ",k,v)        
        --     end 
        -- end  
        OverrallFunc(arrOldModule,New_module)  
        base.Log("_UpdateFile  Old_module[%s]  Success ",modulename)     
    end     
    -- 处理模块中指定参数 
    local function UpdateFileFunc()  
        local Old_module = require(modulename)
        package.loaded[modulename] = nil 
        New_module = require(modulename) 
        for valueName,newValue in pairs(New_module) do
            if Old_module[valueName] and funcname == valueName then 
                Old_module[valueName] = newValue 
                if type(newValue) == "function" then 
                    -- OverrallFunc(valueName,newValue)
                end                                 
                break
            end 
        end 
        package.loaded[modulename] = Old_module 
        Old_module = nil 
        New_module = nil 
        base.Log("_UpdateFileFunc  Old_module[%s]  Success ",modulename)    
    end    
    local sLog =""
	local isSuccee,sErr = false,"" 
    if tData.nType == 1 then     -- 全局模块 更新文件 
        sLog = string.format(" 全局模块 %s ",tData.sUpdataFile) 
        isSuccee,sErr = pcall(OverrallModulename)
    elseif tData.nType == 2 then   -- 更新文件
        sLog = string.format(" 热更新文件 %s ",tData.sUpdataFile) 
        isSuccee,sErr = pcall(UpdateFile)
    elseif tData.nType == 3 and tData.sFuncName then   -- 修改指定函数(如某些文件嵌套多层，可选择 只更新函数) 
        sLog = string.format(" 修改指定函数 %s %s ",tData.sUpdataFile,tData.sFuncName)
        isSuccee,sErr = pcall(UpdateFileFunc)
    else
        -- 执行 函数逻辑(特定逻辑)
        base.Log("_UndateScript  执行 函数逻辑  sUpdataFile: %s ",tData.sUpdataFile) 
        return      
    end   
	if not isSuccee then
		base.Log("_WebUpdateFile ErrorMsg sErr: %s",sErr)
        if type(sErr) == "string" then 
            logger:error(sErr)
        end
    else
		base.Log("_WebUpdateFile  Success  %s ",sLog)  
	end 
    -- for k,v in pairs(_G) do 
    --     if type(v) == "table" then 
    --         base.Log("_WebUpdateFile _G    k:  %s   v: %s  ",k,v)                  
    --     end 
    -- end  
    -- for k,v in pairs(_G) do
    --     if type(v) == "table" and type(v.callback) == "function"  and v.callback then 
    --         base.Log("_WebUpdateFile _G  k: %s  callback: %s  ",k,v.callback)        
    --     end                   
    -- end   
    return 
end


return HotFix






