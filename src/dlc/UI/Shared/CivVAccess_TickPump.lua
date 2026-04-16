-- Per-frame pump wired to ContextPtr:SetUpdate. Owns the monotonic frame
-- counter and forwards tick() to the active handler if it defines one.

TickPump = {}

local _frame = 0

function TickPump._reset()
    _frame = 0
end

function TickPump.frame()
    return _frame
end

function TickPump.tick()
    _frame = _frame + 1
    local h = HandlerStack.active()
    if h == nil then return end
    local fn = h.tick
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, h)
    if not ok then
        Log.error("TickPump tick failed on '" .. tostring(h.name)
            .. "': " .. tostring(err))
    end
end

-- Re-appliable: SetUpdate is replace-semantics (the engine exposes ClearUpdate
-- as a counterpart), so re-calling install on a new ContextPtr after a Context
-- rebuild rewires the pump cleanly. No idempotency guard.
function TickPump.install(ctx)
    ctx:SetUpdate(TickPump.tick)
end
