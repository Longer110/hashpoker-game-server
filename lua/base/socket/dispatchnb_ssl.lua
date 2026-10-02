-----------------------------------------------------------------------------
-- A hacked dispatcher module
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $$
-----------------------------------------------------------------------------
local table = require("table")
local socket = require("socket")
local baseSSL = _G
local coroutine = require("coroutine")
local dnsip = require("socket.dnsip")
local ssl = require("ssl")
module("dispatchnb_ssl")

-- if too much time goes by without any activity in one of our sockets, we
-- just kill it
TIMEOUT = 10

-----------------------------------------------------------------------------
-- We implement 3 types of dispatchers:
--     sequential
--     coroutine
--     threaded
-- The user can choose whatever one is needed
-----------------------------------------------------------------------------
local handlert = {}

-- default handler is coroutine
function newhandler(mode,wrapParms)
    mode = mode or "coroutine"
    wrapParms = wrapParms or {}
    return handlert[mode](wrapParms)
end

local function seqstart(self, func)
    return func()
end

-- sequential handler simply calls the functions and doesn't wrap I/O
function handlert.sequential()
    return {
        tcp = socket.tcp,
        start = seqstart
    }
end

-----------------------------------------------------------------------------
-- Mega hack. Don't try to do this at home.
-----------------------------------------------------------------------------
-- we can't yield across calls to protect, so we rewrite it with coxpcall
-- make sure you don't require any module that uses socket.protect before
-- loading our hack
function socket.protect(f)
    return function(...)
      local co = coroutine.create(f)
      while true do
        local arg = baseSSL.table.pack(...)
        local results = {coroutine.resume(co, table.unpack(arg))}
        local status = table.remove(results, 1)
        if not status then
          if baseSSL.type(results[1]) == 'table' then
            return nil, results[1][1]
          else baseSSL.error(results[1]) end
        end
        if coroutine.status(co) == "suspended" then
          arg = {coroutine.yield(table.unpack(results))}
        else
          return table.unpack(results)
        end
      end
    end
  end


-----------------------------------------------------------------------------
-- Simple set data structure. O(1) everything.
-----------------------------------------------------------------------------
local function newset()
    local reverse = {}
    local set = {}
    return baseSSL.setmetatable(set, {__index = {
        insert = function(set, value)
            if not reverse[value] then
                baseSSL.table.insert(set, value)
                reverse[value] = #set
            end
        end,
        remove = function(set, value)
            local index = reverse[value]
            if index then
                reverse[value] = nil
                local top = baseSSL.table.remove(set)
                if top ~= value then
                    reverse[top] = index
                    set[index] = top
                end
            end
        end,
        len = function(set)
            return #set
        end,
    }})
end

-----------------------------------------------------------------------------
-- socket.tcp() wrapper for the coroutine dispatcher
-----------------------------------------------------------------------------
local function cowrapTCP(dispr, tcp, error)
    if not tcp then return nil, error end
    -- put it in non-blocking mode right away
    tcp:settimeout(0)
    -- metatable for wrap produces new methods on demand for those that we
    -- don't override explicitly.
    local metat = { __index = function(t, key)
        t[key] = function(...)
            local arg = baseSSL.table.pack(...)
            arg[1] = tcp
            return tcp[key](baseSSL.table.unpack(arg))
        end
        return t[key]
    end}
    -- does our user want to do his own non-blocking I/O?
    local zero = false
    -- create a wrap object that will behave just like a real socket object
    local wrap = {  }
    -- we ignore settimeout to preserve our 0 timeout, but record whether
    -- the user wants to do his own non-blocking I/O
    function wrap:settimeout(value, mode)
        if value == 0 then zero = true
        else zero = false end
        return 1
    end
    -- send in non-blocking mode and yield on timeout
    function wrap:send(data, first, last)
        first = (first or 1) - 1
        local result, error
        while true do
            -- return control to dispatcher and tell it we want to send
            -- if upon return the dispatcher tells us we timed out,
            -- return an error to whoever called us
            if coroutine.yield(dispr.sending, tcp) == "timeout" then
                --socket.mBase.LogT("wrap:send111111-------------error______timeout")
                return nil, "timeout"
            end
            -- try sending
            result, error, first = tcp:send(data, first+1, last)
            -- if we are done, or there was an unexpected error,
            -- break away from loop
            if (error ~= "timeout") and (error ~= "wantwrite") then 
                if error ~= nil then
                    socket.mBase.LogT("wrap:send2-error______",error)
                end
                return result, error, first 
            end
        end
    end
    -- receive in non-blocking mode and yield on timeout
    -- or simply return partial read, if user requested timeout = 0
    function wrap:receive(pattern, partial)

        local error = "timeout"
        local value
        while true do
            -- try receiving
            value, error, partial = tcp:receive(pattern, partial)
            -- if we are done, or there was an unexpected error,
            -- break away from loop. also, if the user requested
            -- zero timeout, return all we got
            if ((error ~= "timeout") and (error ~= "wantread")) or zero then
                if error then
                    socket.mBase.LogT("wrap:receive1--error______",error)
                end

                return value, error, partial
            end

            -- return control to dispatcher and tell it we want to receive
            -- if upon return the dispatcher tells us we timed out,
            -- return an error to whoever called us
            if baseSSL.coroutine.yield(dispr.receiving, tcp) == "timeout" then
                socket.mBase.LogT("wrap:receive2-error______timeout")
                return nil, "timeout"
            end
        end
    end
    -- connect in non-blocking mode and yield on timeout
    function wrap:connect(host, port)

        local sIP, err = dnsip.getipbyhost(host, dispr.udp)
        if err ~= nil or sIP == nil or sIP == "" then
            return nil, err
        end

        local result, error = tcp:connect(sIP, port)
        if error == "timeout" then
            -- return control to dispatcher. we will be writable when
            -- connection succeeds.
            -- if upon return the dispatcher tells us we have a
            -- timeout, just abort
            if coroutine.yield(dispr.sending, tcp) == "timeout" then
                socket.mBase.LogT("wrap:connect1-error______timeout")
                return nil, "timeout"
            end

            -- when we come back, check if connection was successful
            result, error = tcp:connect(sIP, port)

            if result or error == "already connected" then 
                tcp = ssl.wrap(tcp, {mode= dispr.WrapParms.mode or 'client', protocol=dispr.WrapParms.protocol or 'tlsv1',
                verify =dispr.WrapParms.verify or "none",options =dispr.WrapParms.options or "all"})
                tcp:settimeout(0)

                tcp:sni(host)
                
                while true do
                    socket.mBase.LogT("dohandshake....")
                    result, error = tcp:dohandshake()
                    if not result then
                        if error == "timeout" or error == "wantread" then
                            if baseSSL.coroutine.yield(dispr.receiving, tcp) == "timeout" then
                                socket.mBase.LogT("wrap:dohandshake-error___timeout_________")
                                return nil, "timeout"
                            end
                        else
                            return nil, error
                        end
                    else
                        break
                    end
                end

                return result, error
            else 
                --socket.mBase.LogT("wrap:connect111111-------------error______non-blocking connect failed")
                return nil, "non-blocking connect failed" 
            end
        else 
            if error then
                socket.mBase.LogT("wrap:connect2-error______",error)
            end
            return result, error 
        end
    end
    -- accept in non-blocking mode and yield on timeout
    function wrap:accept()
        while 1 do
            -- return control to dispatcher. we will be readable when a
            -- connection arrives.
            -- if upon return the dispatcher tells us we have a
            -- timeout, just abort
            if baseSSL.coroutine.yield(dispr.receiving, tcp) == "timeout" then
                socket.mBase.LogT("wrap:accept1-error___timeout_________")
                return nil, "timeout"
            end
            local client, error = tcp:accept()
            if error ~= "timeout" then
                if error then
                    socket.mBase.LogT("wrap:accept2-error____________",error)
                end

                -- 作为服务器端还没处理，暂用不到
                -- client = assert( ssl.wrap(client, ctx) )
                -- socket.sleep(2) -- force the timeout in the client dohandshake()
                -- assert( client:dohandshake() )
                return cowrapTCP(dispr, client, error)
            end
        end
    end

    -- remove cortn from context
    function wrap:close()

        dispr.sending.set:remove(tcp)
        dispr.sending.cortn[tcp] = nil
        dispr.sending.errfunc[tcp] = nil
        dispr.sending.stamp[tcp] = nil
        dispr.receiving.set:remove(tcp)
        dispr.receiving.cortn[tcp] = nil
        dispr.receiving.errfunc[tcp] = nil
        dispr.receiving.stamp[tcp] = nil
        return tcp:close()
    end
    return baseSSL.setmetatable(wrap, metat)
end

-----------------------------------------------------------------------------
-- socket.udp() wrapper for the coroutine dispatcher
-----------------------------------------------------------------------------
local function cowrapUDP(dispr, udp, error)
    if not udp then return nil, error end
    -- put it in non-blocking mode right away
    udp:settimeout(0)
    -- metatable for wrap produces new methods on demand for those that we
    -- don't override explicitly.
    local metat = { __index = function(t, key)
        t[key] = function(...)
            local arg = baseSSL.table.pack(...)
            arg[1] = udp
            return udp[key](baseSSL.table.unpack(arg))
        end
        return t[key]
    end}
    -- does our user want to do his own non-blocking I/O?
    local zero = false
    -- create a wrap object that will behave just like a real socket object
    local wrap = {  }
    -- we ignore settimeout to preserve our 0 timeout, but record whether
    -- the user wants to do his own non-blocking I/O
    function wrap:settimeout(value, mode)
        if value == 0 then zero = true
        else zero = false end
        return 1
    end

    function wrap:sendto(data, ip, port)
        return udp:sendto(data, ip, port)
    end

    -- receive in non-blocking mode and yield on timeout
    -- or simply return partial read, if user requested timeout = 0
    function wrap:receive(count)
        local error = "timeout"
        local value
        while true do
            -- try receiving
            value, error = udp:receive(count)
            if not value and error then
                socket.mBase.LogT("wrap:receive1-error________",error)
            end

            -- if we are done, or there was an unexpected error,
            -- break away from loop. also, if the user requested
            -- zero timeout, return all we got
            if (error ~= "timeout") or zero then
                if error then
                    socket.mBase.LogT("wrap:receive2-error________",error)
                end
                return value, error
            end

            -- return control to dispatcher and tell it we want to receive
            -- if upon return the dispatcher tells us we timed out,
            -- return an error to whoever called us

            if baseSSL.coroutine.yield(dispr.receiving, udp) == "timeout" then
                socket.mBase.LogT("wrap:receive3-error_______",error)
                return nil, "timeout"
            end
        end
    end
    
    -- remove cortn from context
    function wrap:close()

        dispr.sending.set:remove(udp)
        dispr.sending.cortn[udp] = nil
        dispr.sending.errfunc[udp] = nil
        dispr.sending.stamp[udp] = nil
        dispr.receiving.set:remove(udp)
        dispr.receiving.cortn[udp] = nil
        dispr.receiving.errfunc[udp] = nil
        dispr.receiving.stamp[udp] = nil
        return udp:close()
    end
    return baseSSL.setmetatable(wrap, metat)
end


-----------------------------------------------------------------------------
-- Our coroutine dispatcher
-----------------------------------------------------------------------------
local cometat = { __index = {} }

function schedule(cortn, errfunc, status, operation, tcp)
    if status then
        if cortn and operation then
            operation.set:insert(tcp)
            operation.cortn[tcp] = cortn
            if operation.stamp[tcp] == nil then
                operation.stamp[tcp] = socket.gettime()
            end
            operation.errfunc[tcp] = errfunc
        end
    else
        if errfunc then
            --socket.mBase.LogT("schedule1111111111111---------errfunc（operation）----____________",operation)
            errfunc(operation)
        end
    end
end

function kick(operation, tcp)
    operation.cortn[tcp] = nil
    operation.set:remove(tcp)
    operation.errfunc[tcp] = nil
    operation.stamp[tcp] = nil
end

function wakeup(operation, tcp)
    local cortn = operation.cortn[tcp]
    local errfunc = operation.errfunc[tcp]
    --socket.mBase.LogT("wakeup1111111111111---------errfunc----____________",errfunc)
    -- if cortn is still valid, wake it up
    if cortn then
        kick(operation, tcp)
        return cortn, errfunc, baseSSL.coroutine.resume(cortn)
    -- othrewise, just get scheduler not to do anything
    else
        return nil, errfunc, false
    end
end

function abort(operation, tcp)
    local cortn = operation.cortn[tcp]
    local errfunc = operation.errfunc[tcp]
    if cortn then
        kick(operation, tcp)
        local status, _, errmsg = baseSSL.coroutine.resume(cortn, "timeout")
        if status == false and errfunc then
            socket.mBase.LogT("wakeup-abort errfunc---timeout")
            errfunc("timeout")
        end
    end
end

function cometat.__index:setTIMEOUT(timeout)
    TIMEOUT = timeout
    socket.mBase.LogT("现在的TIMEOUT值为",TIMEOUT)
end

-- step through all active cortns
function cometat.__index:step()
    -- check which sockets are interesting and act on them

    local readable, writable = socket.select(self.receiving.set,
        self.sending.set, 0)

    -- for all readable connections, resume their cortns and reschedule
    -- when they yield back to us
    for _, tcp in baseSSL.ipairs(readable) do
        schedule(wakeup(self.receiving, tcp))
    end
    -- for all writable connections, do the same
    for _, tcp in baseSSL.ipairs(writable) do
        schedule(wakeup(self.sending, tcp))
    end
    -- politely ask replacement I/O functions in idle cortns to
    -- return reporting a timeout
    local now = socket.gettime()

    local tTmp = {}
    for tcp, stamp in baseSSL.pairs(self.stamp) do
        tTmp[tcp] = stamp
    end

    for tcp, stamp in baseSSL.pairs(tTmp) do
        if (tcp.class == "tcp{client}" or tcp.class == "udp{unconnected}") and now - stamp > TIMEOUT then
            abort(self.sending, tcp)
            abort(self.receiving, tcp)
            self.stamp[tcp] = nil

        end
    end
end

function cometat.__index:start(func, errfunc)
    local cortn = coroutine.create(func)
    schedule(cortn, errfunc, coroutine.resume(cortn))
end

function handlert.coroutine(wrapParms)
    local WrapParms = wrapParms or {}
    local stamp = {}
    local dispatcher = {
        WrapParms = WrapParms,
        stamp = stamp,
        sending  = {
            name = "sending",
            set = newset(),
            cortn = {},
            stamp = stamp,
            errfunc = {}
        },
        receiving = {
            name = "receiving",
            set = newset(),
            cortn = {},
            stamp = stamp,
            errfunc = {}
        },
    }
    function dispatcher.tcp()
        return cowrapTCP(dispatcher, socket.tcp())
    end
    function dispatcher.udp()
        return cowrapUDP(dispatcher, socket.udp())
    end
    return baseSSL.setmetatable(dispatcher, cometat)
end

