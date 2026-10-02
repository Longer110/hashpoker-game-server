

package.path = "../lua/base/?.lua;./lua/base/?.lua;" .. package.path
package.path = "../lua/base/socket/?.lua;./lua/base/socket/?.lua;" .. package.path


--发送错误信息
local tBase 	= require("base")         -- 基础功能接口




ErrorSink = {}


-- DB 异常处理的 错误日志
function ErrorSink.tpLog(e)
    local nIdx = thread.GetIdx()
    logger:error(string.format("Error%d:========================================",nIdx))

    local sPath, sFile = tBase.GetLogPath()
    logger:error(string.format("Error%d: %s \n %s",nIdx, debug.traceback(), e))
    logger:error(string.format("Error%d:========================================",nIdx))

    tBase.SetLogPath("./log/Module/"..tBase.GetPort().."-"..tBase.GetThreadIndex(), "lo")
    logger:error(string.format("Error%d: %s \n %s",nIdx, debug.traceback(), e))

    tBase.SetLogPath(sPath, sFile)

    tBase.Log(" ====================完成错误记录=====================     ")
    return e
end


--实现例子

function  ErrorSink.RunFunction()


	return 0 
end



return ErrorSink

