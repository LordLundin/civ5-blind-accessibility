-- Shared Yes/No confirm-overlay sub-handler for the Choose* popups
-- (Pantheon, Ideology, Archaeology, AdmiralNewPort, TradeUnitNewHome). Each
-- of those screens wraps any pick in a "Controls.ChooseConfirm" overlay
-- with a prompt (Controls.ConfirmText) and two buttons. The button control
-- names differ per screen (Pantheon uses Yes/No, the others use
-- ConfirmYes/ConfirmNo) but the container is always Controls.ChooseConfirm.
--
-- Caller pushes this sub after the base's Select* function has shown the
-- overlay. Enter on Yes removes the sub (reactivate=false, because Yes
-- closes the whole popup anyway) and invokes opts.onYes; Enter on No
-- removes the sub (reactivate=true, so the underlying picker re-announces);
-- Esc pops via escapePops. onDeactivate hides the overlay on every exit
-- path so No / Esc / Yes all leave a clean state.

ChooseConfirmSub = {}

function ChooseConfirmSub.push(opts)
    if type(opts) ~= "table" then
        Log.error("ChooseConfirmSub.push: opts must be a table")
        return
    end
    if type(opts.onYes) ~= "function" then
        Log.error("ChooseConfirmSub.push: opts.onYes must be a function")
        return
    end
    local yesControl = opts.yesControl or "ConfirmYes"
    local noControl = opts.noControl or "ConfirmNo"

    local function promptText()
        local c = Controls.ConfirmText
        if c == nil then
            return ""
        end
        local ok, text = pcall(function()
            return c:GetText()
        end)
        if not ok or text == nil then
            return ""
        end
        return tostring(text)
    end

    local sub = BaseMenu.create({
        name = "ChooseConfirm",
        displayName = Text.key("TXT_KEY_CIVVACCESS_SCREEN_CHOOSE_CONFIRM"),
        preamble = promptText,
        capturesAllInput = true,
        escapePops = true,
        escapeAnnounce = Text.key("TXT_KEY_CIVVACCESS_CANCELED"),
        items = {
            BaseMenuItems.Button({
                controlName = yesControl,
                textKey = "TXT_KEY_YES_BUTTON",
                activate = function()
                    HandlerStack.removeByName("ChooseConfirm", false)
                    local ok, err = pcall(opts.onYes)
                    if not ok then
                        Log.error("ChooseConfirmSub onYes failed: " .. tostring(err))
                    end
                end,
            }),
            BaseMenuItems.Button({
                controlName = noControl,
                textKey = "TXT_KEY_NO_BUTTON",
                activate = function()
                    HandlerStack.removeByName("ChooseConfirm", true)
                end,
            }),
        },
    })
    sub.onDeactivate = function()
        if Controls.ChooseConfirm ~= nil then
            Controls.ChooseConfirm:SetHide(true)
        end
    end
    HandlerStack.push(sub)
end

return ChooseConfirmSub
