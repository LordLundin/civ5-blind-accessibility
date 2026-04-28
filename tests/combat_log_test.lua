-- CombatLog: per-AI-turn capture of combat-readout text. Tests exercise
-- the AI-turn gate (only records between TurnEnd and the next TurnStart),
-- the reset-on-TurnEnd contract, and the survives-across-the-player-turn
-- behavior the F7 popup depends on.

local T = require("support")
local M = {}

local function setup()
    civvaccess_shared = {}
    Events = {
        ActivePlayerTurnEnd = { Add = function(_) end },
        ActivePlayerTurnStart = { Add = function(_) end },
    }
    CombatLog = nil
    dofile("src/dlc/UI/InGame/CivVAccess_CombatLog.lua")
    CombatLog.installListeners()
end

-- During the player's own turn (boot priming flips _inAiTurn false),
-- a recordCombat call is a no-op: combats the player initiated speak in
-- real time and don't belong on the per-AI-turn log.
function M.test_player_turn_records_nothing()
    setup()
    CombatLog.recordCombat("Roman Warrior hit Greek Spearman")
    T.eq(civvaccess_shared.combatLog, nil, "no list created during player turn")
end

-- After ActivePlayerTurnEnd fires, the AI-turn window is open and combat
-- text accumulates onto civvaccess_shared.combatLog in call order.
function M.test_ai_turn_collects_combats_in_order()
    setup()
    CombatLog._onTurnEnd()
    CombatLog.recordCombat("first combat")
    CombatLog.recordCombat("second combat")
    CombatLog.recordCombat("third combat")
    local list = civvaccess_shared.combatLog
    T.eq(type(list), "table", "list created on first record")
    T.eq(#list, 3, "all three combats logged")
    T.eq(list[1], "first combat")
    T.eq(list[2], "second combat")
    T.eq(list[3], "third combat")
end

-- The list must persist through the player's next turn so F7 can show it.
-- Only the *next* TurnEnd resets it (re-opening the window for the new
-- AI turn).
function M.test_list_survives_player_turn_until_next_turn_end()
    setup()
    CombatLog._onTurnEnd()
    CombatLog.recordCombat("ai combat")
    CombatLog._onTurnStart()
    -- Player turn now in progress. List still readable for F7.
    T.eq(#civvaccess_shared.combatLog, 1, "list intact through player turn")
    -- Player initiates an attack: the speech path calls recordCombat but
    -- the gate rejects (window closed). List stays the same.
    CombatLog.recordCombat("player-initiated combat")
    T.eq(#civvaccess_shared.combatLog, 1, "player-turn combat does not append")
    T.eq(civvaccess_shared.combatLog[1], "ai combat", "list contents unchanged")
    -- Player ends turn. The new AI turn window opens; prior list cleared.
    CombatLog._onTurnEnd()
    T.eq(civvaccess_shared.combatLog, nil, "list cleared at next TurnEnd")
end

-- Reinstalling listeners (load-game-from-game) clears prior shared state
-- and resets the AI-turn flag. A combat recorded after reinstall but
-- before the next TurnEnd is dropped (window is closed at install).
function M.test_reinstall_resets_state()
    setup()
    CombatLog._onTurnEnd()
    CombatLog.recordCombat("game1 combat")
    -- Simulate load-game-from-game: civvaccess_shared survives, but the
    -- new Boot calls installListeners, which clears it and re-arms.
    CombatLog.installListeners()
    T.eq(civvaccess_shared.combatLog, nil, "shared list cleared on install")
    CombatLog.recordCombat("would-be combat")
    T.eq(civvaccess_shared.combatLog, nil, "window closed after install until TurnEnd")
end

return M
