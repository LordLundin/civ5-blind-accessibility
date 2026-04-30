-- HotseatMessageBuffer tests. Engine seams stubbed: Game.IsHotSeat,
-- Players[i] (per-player IsHuman), Events.GameplaySetActivePlayer
-- (capturing listener registration). The module manipulates
-- civvaccess_shared.messageBuffer directly, so tests assert on that slot
-- and seed it as the production MessageBuffer would.

local T = require("support")
local M = {}

local activePlayerListeners
local hotseat

local function fireActivePlayerChanged(iActive, iPrev)
    for _, fn in ipairs(activePlayerListeners) do
        fn(iActive, iPrev)
    end
end

local function makePlayer(opts)
    opts = opts or {}
    return {
        IsHuman = function()
            return opts.human ~= false
        end,
    }
end

local function makeBuf(entries, filter, position)
    return {
        entries = entries or {},
        filter = filter or "all",
        position = position or 0,
    }
end

local function setup()
    civvaccess_shared = {}

    dofile("src/dlc/UI/InGame/CivVAccess_HotseatMessageBufferRestore.lua")

    HotseatMessageBuffer._reset()

    hotseat = true
    Game.IsHotSeat = function()
        return hotseat
    end

    activePlayerListeners = {}
    Events.GameplaySetActivePlayer = {
        Add = function(fn)
            activePlayerListeners[#activePlayerListeners + 1] = fn
        end,
    }

    Players = {}

    HotseatMessageBuffer.installListeners()
end

-- Hotseat gate ------------------------------------------------------------

function M.test_no_listener_registered_outside_hotseat()
    setup()
    HotseatMessageBuffer._reset()
    activePlayerListeners = {}
    hotseat = false
    HotseatMessageBuffer.installListeners()
    T.eq(#activePlayerListeners, 0, "non-hotseat install must not register a listener")
end

function M.test_handler_inert_if_hotseat_flips_off_after_install()
    setup()
    Players[0] = makePlayer()
    Players[1] = makePlayer()
    civvaccess_shared.messageBuffer = makeBuf({ { text = "a", category = "combat" } })
    hotseat = false
    fireActivePlayerChanged(1, 0)
    T.eq(civvaccess_shared.messageBuffer.entries[1].text, "a", "live buffer untouched when hotseat off")
end

-- Save on handoff ---------------------------------------------------------

function M.test_human_prior_player_buffer_saved_and_restored()
    setup()
    Players[0] = makePlayer()
    Players[1] = makePlayer()
    -- Player 0's session: their buffer accrues entries.
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p0-msg", category = "combat" } }, "combat", 1)
    -- Hand off 0 -> 1. 0's buffer saved; 1 has no saved entry yet so live
    -- becomes nil (next state() call lazy-creates fresh).
    fireActivePlayerChanged(1, 0)
    T.eq(civvaccess_shared.messageBuffer, nil, "no saved entry for player 1 -> live nil")
    -- Player 1 plays: a fresh buffer would be created on first append. Test
    -- the round-trip by seeding 1's buffer directly.
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p1-msg", category = "reveal" } }, "reveal", 1)
    -- Hand off 1 -> 0. 1's buffer saved; 0's restored.
    fireActivePlayerChanged(0, 1)
    T.eq(#civvaccess_shared.messageBuffer.entries, 1)
    T.eq(civvaccess_shared.messageBuffer.entries[1].text, "p0-msg", "restored player 0's saved entry")
    T.eq(civvaccess_shared.messageBuffer.filter, "combat", "restored filter")
    T.eq(civvaccess_shared.messageBuffer.position, 1, "restored position")
end

function M.test_round_trip_preserves_independent_buffers()
    setup()
    Players[0] = makePlayer()
    Players[1] = makePlayer()
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p0-1", category = "combat" } }, "all", 1)
    fireActivePlayerChanged(1, 0)
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p1-1", category = "reveal" } }, "all", 1)
    fireActivePlayerChanged(0, 1)
    -- Add another entry to p0's restored buffer (simulating their next turn).
    civvaccess_shared.messageBuffer.entries[#civvaccess_shared.messageBuffer.entries + 1] =
        { text = "p0-2", category = "notification" }
    fireActivePlayerChanged(1, 0)
    -- Back to p1: their saved buffer comes back unchanged.
    T.eq(#civvaccess_shared.messageBuffer.entries, 1)
    T.eq(civvaccess_shared.messageBuffer.entries[1].text, "p1-1")
    fireActivePlayerChanged(0, 1)
    -- Back to p0: both their entries are still present.
    T.eq(#civvaccess_shared.messageBuffer.entries, 2)
    T.eq(civvaccess_shared.messageBuffer.entries[1].text, "p0-1")
    T.eq(civvaccess_shared.messageBuffer.entries[2].text, "p0-2")
end

function M.test_first_activation_leaves_live_nil_for_lazy_fresh()
    -- Session start: no saved entries. The first GameplaySetActivePlayer
    -- after install for a player with no saved buffer must leave the live
    -- slot nil so MessageBuffer.state() lazy-creates a fresh one.
    setup()
    Players[0] = makePlayer()
    -- Live buffer was whatever the engine left there (possibly nil from
    -- MessageBuffer.installListeners). Set explicitly nil to make the
    -- assertion unambiguous.
    civvaccess_shared.messageBuffer = nil
    fireActivePlayerChanged(0, -1)
    T.eq(civvaccess_shared.messageBuffer, nil, "no saved -> live remains nil for lazy create")
end

function M.test_ai_prior_player_buffer_not_saved()
    -- Defensive: in hotseat the engine only fires GameplaySetActivePlayer
    -- on human-to-human transitions (CvPlayer.cpp:15812). The IsHuman gate
    -- here is parity with HotseatCursor; the test exercises it.
    setup()
    Players[0] = makePlayer({ human = false })
    Players[1] = makePlayer()
    civvaccess_shared.messageBuffer = makeBuf({ { text = "stale", category = "combat" } })
    fireActivePlayerChanged(1, 0) -- AI 0 -> human 1
    -- Whatever was live got nilled by the restore branch (no saved for 1),
    -- but saved[0] must NOT have been written. Cycle back through to a
    -- human-converted player 0 and confirm the capital fallback would kick
    -- in (saved is empty, so the restore leaves live nil).
    Players[0] = makePlayer({ human = true })
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p1-msg", category = "combat" } })
    fireActivePlayerChanged(0, 1)
    -- saved[0] doesn't exist. Restore sets live to nil.
    T.eq(civvaccess_shared.messageBuffer, nil, "no saved entry for AI-prior player 0 after the cycle")
end

function M.test_no_restore_when_active_player_is_ai()
    setup()
    Players[0] = makePlayer()
    Players[1] = makePlayer({ human = false })
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p0-msg", category = "combat" } })
    fireActivePlayerChanged(1, 0)
    -- 0's buffer saved. No restore for AI 1: live stays untouched.
    T.eq(#civvaccess_shared.messageBuffer.entries, 1)
    T.eq(civvaccess_shared.messageBuffer.entries[1].text, "p0-msg", "live buffer not swapped for AI active")
end

-- Edge cases on event args -----------------------------------------------

function M.test_negative_prev_player_skips_save()
    setup()
    Players[0] = makePlayer()
    civvaccess_shared.messageBuffer = makeBuf({ { text = "live", category = "combat" } })
    fireActivePlayerChanged(0, -1)
    -- Restore for 0: no saved entry -> live becomes nil.
    T.eq(civvaccess_shared.messageBuffer, nil, "restore branch ran for 0 (no saved)")
    -- Confirm save for -1 didn't happen by cycling: arrange a saved entry
    -- for 0, then hand off, then come back. saved[-1] was never written.
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p0", category = "reveal" } })
    Players[1] = makePlayer()
    fireActivePlayerChanged(1, 0) -- saves p0
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p1", category = "reveal" } })
    fireActivePlayerChanged(0, 1)
    T.eq(civvaccess_shared.messageBuffer.entries[1].text, "p0", "round-trip restore still works")
end

function M.test_negative_active_player_skips_restore()
    setup()
    Players[0] = makePlayer()
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p0", category = "combat" } })
    fireActivePlayerChanged(-1, 0)
    -- Save happened (0 is human), no restore (active is -1). Live untouched.
    T.eq(#civvaccess_shared.messageBuffer.entries, 1)
    T.eq(civvaccess_shared.messageBuffer.entries[1].text, "p0")
    -- Confirm save by cycling forward.
    Players[1] = makePlayer()
    civvaccess_shared.messageBuffer = makeBuf({ { text = "live", category = "reveal" } })
    fireActivePlayerChanged(0, 1)
    -- Restoring 0: saved exists.
    T.eq(civvaccess_shared.messageBuffer.entries[1].text, "p0")
end

-- Reset semantics ---------------------------------------------------------

function M.test_install_listeners_wipes_saved()
    setup()
    Players[0] = makePlayer()
    Players[1] = makePlayer()
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p0", category = "combat" } })
    fireActivePlayerChanged(1, 0) -- saves p0
    -- Re-install (load-from-game seam). Saved must be empty.
    HotseatMessageBuffer.installListeners()
    civvaccess_shared.messageBuffer = makeBuf({ { text = "p1", category = "reveal" } })
    fireActivePlayerChanged(0, 1)
    -- After reinstall, p0 has no saved entry: restore leaves live nil.
    T.eq(civvaccess_shared.messageBuffer, nil, "saved table wiped by installListeners")
end

return M
