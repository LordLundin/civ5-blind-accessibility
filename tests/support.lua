-- Test support: assertion helpers and a flat registration/runner model.
-- Tests are (name, fn) pairs appended to T.cases. Each fn either returns
-- normally (pass) or calls error (fail). The runner catches and tallies.

local T = {}
T.cases = {}

function T.case(name, fn)
    T.cases[#T.cases + 1] = { name = name, fn = fn }
end

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.eq(actual, expected, note)
    if actual ~= expected then
        error((note and (note .. ": ") or "")
            .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function T.truthy(v, note)
    if not v then error((note or "expected truthy") .. ", got " .. fmt(v), 2) end
end

function T.falsy(v, note)
    if v then error((note or "expected falsy") .. ", got " .. fmt(v), 2) end
end

function T.run()
    local passed, failed = 0, {}
    for _, c in ipairs(T.cases) do
        local ok, err = pcall(c.fn)
        if ok then
            passed = passed + 1
        else
            failed[#failed + 1] = { name = c.name, err = err }
        end
    end
    print(string.format("%d passed, %d failed (of %d)",
        passed, #failed, #T.cases))
    for _, f in ipairs(failed) do
        print("  FAIL " .. f.name)
        print("       " .. tostring(f.err))
    end
    return #failed == 0
end

return T
