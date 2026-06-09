--[[
    ErrorHandler.lua — Centralized error handling utilities for Ser-un-pelo

    Wraps common Roblox operations (HTTP requests, event connections, file I/O,
    service access, tweens) with structured error propagation so failures are
    never silently swallowed.

    Usage:
        local EH = loadstring(readfile("ErrorHandler.lua"))()

        -- Safe HTTP request (returns success, response)
        local ok, res = EH.safeRequest({ Url = "...", Method = "GET" })
        if not ok then warn("Request failed:", res) end

        -- Protected event connection
        EH.safeConnect(button.MouseButton1Click, function()
            -- handler code; errors are caught and logged
        end)
]]

local ErrorHandler = {}

-------------------------------------------------------------------------------
-- Configuration
-------------------------------------------------------------------------------

ErrorHandler.LogErrors   = true   -- print errors to output
ErrorHandler.RethrowFatal = false -- re-throw after logging (set true to fail loud)

local _errorLog = {}

-------------------------------------------------------------------------------
-- Internal helpers
-------------------------------------------------------------------------------

local function _timestamp()
    -- os.clock gives elapsed CPU time; works in both Roblox and vanilla Lua
    return string.format("%.3f", os.clock())
end

local function _record(category, message, context)
    local entry = {
        time     = _timestamp(),
        category = category,
        message  = tostring(message),
        context  = context or "",
    }
    table.insert(_errorLog, entry)

    if ErrorHandler.LogErrors then
        local prefix = "[ErrorHandler/" .. category .. " @ " .. entry.time .. "]"
        if context and context ~= "" then
            warn(prefix, entry.message, "| ctx:", tostring(context))
        else
            warn(prefix, entry.message)
        end
    end

    return entry
end

-------------------------------------------------------------------------------
-- 1. Safe pcall wrapper — ensures the success flag is always checked
--    Returns:  success (bool), result_or_error
-------------------------------------------------------------------------------

function ErrorHandler.try(fn, ...)
    if type(fn) ~= "function" then
        local msg = "ErrorHandler.try: expected function, got " .. type(fn)
        _record("try", msg)
        return false, msg
    end

    local results = table.pack(pcall(fn, ...))
    local ok = results[1]

    if not ok then
        _record("try", results[2], debug.traceback(nil, 2))
        if ErrorHandler.RethrowFatal then
            error(results[2], 2)
        end
    end

    return table.unpack(results, 1, results.n)
end

-------------------------------------------------------------------------------
-- 2. Safe HTTP request — validates input, checks response status
--    Returns:  success (bool), response_or_error
-------------------------------------------------------------------------------

function ErrorHandler.safeRequest(options)
    -- Validate input
    if type(options) ~= "table" then
        local msg = "safeRequest: options must be a table, got " .. type(options)
        _record("request", msg)
        return false, msg
    end
    if type(options.Url) ~= "string" or options.Url == "" then
        local msg = "safeRequest: missing or empty Url field"
        _record("request", msg)
        return false, msg
    end

    -- Resolve the request function (exploit environments expose different names)
    local requestFn = request or http_request or (syn and syn.request) or http and http.request
    if not requestFn then
        local msg = "safeRequest: no HTTP request function available in this environment"
        _record("request", msg)
        return false, msg
    end

    local ok, response = pcall(requestFn, options)
    if not ok then
        _record("request", "HTTP call threw: " .. tostring(response), options.Url)
        return false, response
    end

    if type(response) ~= "table" then
        local msg = "safeRequest: response is not a table (" .. type(response) .. ")"
        _record("request", msg, options.Url)
        return false, msg
    end

    -- Check HTTP status
    local status = response.StatusCode or response.status_code or 0
    if status < 200 or status >= 300 then
        local msg = string.format(
            "safeRequest: HTTP %d for %s — %s",
            status,
            options.Url,
            tostring(response.StatusMessage or response.Body or "")
        )
        _record("request", msg)
        return false, msg
    end

    return true, response
end

-------------------------------------------------------------------------------
-- 3. Safe event connection — wraps the callback in pcall
--    Returns:  the RBXScriptConnection so it can still be disconnected
-------------------------------------------------------------------------------

function ErrorHandler.safeConnect(signal, callback, label)
    if signal == nil or typeof(signal) ~= "RBXScriptSignal" then
        local msg = "safeConnect: first argument is not a valid signal"
        _record("connect", msg, label)
        -- Return a dummy connection so callers don't nil-index
        return { Disconnect = function() end, Connected = false }
    end

    label = label or "anonymous"

    return signal:Connect(function(...)
        local ok, err = pcall(callback, ...)
        if not ok then
            _record("connect", "Handler '" .. label .. "' errored: " .. tostring(err),
                    debug.traceback(nil, 2))
        end
    end)
end

-------------------------------------------------------------------------------
-- 4. Safe file I/O — wraps readfile / writefile / isfile with pcall
-------------------------------------------------------------------------------

function ErrorHandler.safeReadFile(path)
    if type(path) ~= "string" or path == "" then
        return false, "safeReadFile: invalid path"
    end

    local isfileFn = isfile
    if isfileFn then
        local ok, exists = pcall(isfileFn, path)
        if ok and not exists then
            return false, "safeReadFile: file does not exist — " .. path
        end
    end

    local ok, data = pcall(readfile, path)
    if not ok then
        _record("file", "readfile failed: " .. tostring(data), path)
        return false, data
    end
    return true, data
end

function ErrorHandler.safeWriteFile(path, content)
    if type(path) ~= "string" or path == "" then
        return false, "safeWriteFile: invalid path"
    end
    if content == nil then
        return false, "safeWriteFile: content is nil"
    end

    local ok, err = pcall(writefile, path, tostring(content))
    if not ok then
        _record("file", "writefile failed: " .. tostring(err), path)
        return false, err
    end
    return true
end

function ErrorHandler.safeIsFile(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local ok, result = pcall(isfile, path)
    if not ok then
        _record("file", "isfile failed: " .. tostring(result), path)
        return false
    end
    return result
end

-------------------------------------------------------------------------------
-- 5. Safe JSON decode
-------------------------------------------------------------------------------

function ErrorHandler.safeJSONDecode(jsonStr)
    if type(jsonStr) ~= "string" then
        return false, "safeJSONDecode: expected string, got " .. type(jsonStr)
    end

    local HttpService
    local ok, svc = pcall(function()
        return game:GetService("HttpService")
    end)
    if not ok or not svc then
        _record("json", "Cannot access HttpService: " .. tostring(svc))
        return false, svc
    end
    HttpService = svc

    local decodeOk, result = pcall(HttpService.JSONDecode, HttpService, jsonStr)
    if not decodeOk then
        _record("json", "JSONDecode failed: " .. tostring(result))
        return false, result
    end
    return true, result
end

-------------------------------------------------------------------------------
-- 6. Safe service access
-------------------------------------------------------------------------------

function ErrorHandler.safeGetService(serviceName)
    if type(serviceName) ~= "string" then
        return false, "safeGetService: serviceName must be a string"
    end

    local ok, service = pcall(function()
        return game:GetService(serviceName)
    end)
    if not ok then
        _record("service", "GetService failed for: " .. serviceName .. " — " .. tostring(service))
        return false, service
    end
    return true, service
end

-------------------------------------------------------------------------------
-- 7. Safe WaitForChild — times out instead of yielding forever
-------------------------------------------------------------------------------

function ErrorHandler.safeWaitForChild(parent, childName, timeout)
    timeout = timeout or 5

    if not parent or not parent.WaitForChild then
        local msg = "safeWaitForChild: invalid parent"
        _record("instance", msg)
        return false, msg
    end

    local ok, child = pcall(parent.WaitForChild, parent, childName, timeout)
    if not ok then
        _record("instance", "WaitForChild threw: " .. tostring(child), childName)
        return false, child
    end
    if child == nil then
        local msg = "safeWaitForChild: '" .. childName .. "' not found within " .. timeout .. "s"
        _record("instance", msg)
        return false, msg
    end
    return true, child
end

-------------------------------------------------------------------------------
-- 8. Safe Tween creation and playback
-------------------------------------------------------------------------------

function ErrorHandler.safeTween(instance, tweenInfo, properties)
    local ok, svc = pcall(function()
        return game:GetService("TweenService")
    end)
    if not ok or not svc then
        _record("tween", "Cannot access TweenService")
        return false, "TweenService unavailable"
    end

    local createOk, tween = pcall(svc.Create, svc, instance, tweenInfo, properties)
    if not createOk then
        _record("tween", "Tween creation failed: " .. tostring(tween))
        return false, tween
    end

    local playOk, playErr = pcall(tween.Play, tween)
    if not playOk then
        _record("tween", "Tween:Play() failed: " .. tostring(playErr))
        return false, playErr
    end

    return true, tween
end

-------------------------------------------------------------------------------
-- Error log access
-------------------------------------------------------------------------------

function ErrorHandler.getErrorLog()
    return _errorLog
end

function ErrorHandler.clearErrorLog()
    _errorLog = {}
end

function ErrorHandler.getErrorCount()
    return #_errorLog
end

return ErrorHandler
