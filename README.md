# Ser-un-pelo

## Error Handling

Both `Code.lua` and `card.lua` are obfuscated and contain operations that
silently swallow errors.  The modules below add structured error propagation
so failures are always visible.

### ErrorHandler.lua

Utility module that wraps common operations with proper error checking:

| Helper | What it guards |
|--------|---------------|
| `EH.try(fn, ...)` | Generic pcall wrapper — logs failures automatically |
| `EH.safeRequest(opts)` | HTTP requests — validates input, checks status codes |
| `EH.safeConnect(signal, cb)` | Event connections — catches handler errors |
| `EH.safeReadFile(path)` | File reads — checks existence first |
| `EH.safeWriteFile(path, data)` | File writes — validates args, catches I/O errors |
| `EH.safeJSONDecode(str)` | JSON parsing — catches malformed input |
| `EH.safeGetService(name)` | Service access — catches unavailable services |
| `EH.safeWaitForChild(parent, name, timeout)` | Instance lookup — times out instead of hanging |
| `EH.safeTween(inst, info, props)` | Tween creation + playback |

```lua
local EH = loadstring(readfile("ErrorHandler.lua"))()

local ok, res = EH.safeRequest({ Url = "https://example.com", Method = "GET" })
if not ok then
    warn("Request failed:", res)
end

EH.safeConnect(button.MouseButton1Click, function()
    -- errors here are caught and logged, not swallowed
end, "ButtonClick")
```

All errors are stored in `EH.getErrorLog()` for later inspection.

### SafeLoader.lua

Wraps execution of `Code.lua` and `card.lua` in error boundaries:

```lua
loadstring(readfile("SafeLoader.lua"))()
```

Any unhandled runtime error is caught and printed instead of crashing silently.

### Issues Found in Obfuscated Code

| Category | Code.lua | card.lua | Risk |
|----------|----------|----------|------|
| `pcall` results potentially unchecked | 50 calls | 8 calls | Silent failures — code continues with nil/invalid data |
| HTTP `request` without error handling | 3 calls | 1 call | Network failures crash or produce nil-index errors |
| `Connect` callbacks without pcall | 29 handlers | 5 handlers | One handler error can break the entire event chain |
| `writefile` / `readfile` without guards | present | present | I/O errors silently lost |
| Only error() usage is tamper detection | 2 calls | 2 calls | No defensive error reporting for operational failures |