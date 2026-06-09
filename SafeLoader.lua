--[[
    SafeLoader.lua — Executes Code.lua and card.lua inside error boundaries

    Problem:  Both scripts are obfuscated and contain operations (HTTP requests,
              event connections, file I/O) that silently swallow errors.  When
              something goes wrong the scripts either crash without context or
              fail silently, making debugging nearly impossible.

    Solution: This loader wraps each script's execution in pcall, catches any
              unhandled errors, and reports them through the ErrorHandler module
              so every failure is visible.

    Usage (in a Roblox executor):
        loadstring(readfile("SafeLoader.lua"))()
]]

---------------------------------------------------------------------------
-- 1. Load ErrorHandler
---------------------------------------------------------------------------

local EH
do
    local ok, mod = pcall(function()
        return loadstring(readfile("ErrorHandler.lua"))()
    end)
    if ok and mod then
        EH = mod
    else
        -- Minimal fallback if ErrorHandler can't be loaded
        warn("[SafeLoader] Could not load ErrorHandler.lua:", tostring(mod))
        EH = {
            try = function(fn, ...)
                return pcall(fn, ...)
            end,
            getErrorCount = function() return 0 end,
            getErrorLog   = function() return {} end,
        }
    end
end

---------------------------------------------------------------------------
-- 2. Script loader with error boundary
---------------------------------------------------------------------------

local function loadScript(path, label)
    label = label or path

    -- Check file exists
    if isfile and not isfile(path) then
        warn("[SafeLoader] File not found:", path)
        return false, "File not found: " .. path
    end

    -- Read file
    local readOk, source = pcall(readfile, path)
    if not readOk then
        warn("[SafeLoader] Failed to read " .. label .. ":", tostring(source))
        return false, source
    end

    -- Compile
    local compileFn, compileErr = loadstring(source)
    if not compileFn then
        warn("[SafeLoader] Syntax error in " .. label .. ":", tostring(compileErr))
        return false, compileErr
    end

    -- Execute inside pcall
    local ok, result = pcall(compileFn)
    if not ok then
        warn("[SafeLoader] Runtime error in " .. label .. ":", tostring(result))
        return false, result
    end

    return true, result
end

---------------------------------------------------------------------------
-- 3. Execute both scripts
---------------------------------------------------------------------------

local results = {}

-- Load Code.lua
do
    local ok, err = loadScript("Code.lua", "Code.lua (main)")
    results.Code = { success = ok, error = not ok and err or nil }
    if ok then
        print("[SafeLoader] Code.lua loaded successfully")
    else
        warn("[SafeLoader] Code.lua FAILED:", tostring(err))
    end
end

-- Load card.lua
do
    local ok, err = loadScript("card.lua", "card.lua (card)")
    results.card = { success = ok, error = not ok and err or nil }
    if ok then
        print("[SafeLoader] card.lua loaded successfully")
    else
        warn("[SafeLoader] card.lua FAILED:", tostring(err))
    end
end

---------------------------------------------------------------------------
-- 4. Summary
---------------------------------------------------------------------------

local errorCount = EH.getErrorCount()
if errorCount > 0 then
    warn(string.format(
        "[SafeLoader] Finished with %d error(s) logged. Use ErrorHandler.getErrorLog() for details.",
        errorCount
    ))
else
    print("[SafeLoader] All scripts loaded. No errors recorded.")
end

return results
