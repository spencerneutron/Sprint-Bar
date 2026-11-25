-- Options.lua
-- Settings category, sprint-key capture dialog, slash commands and the addon compartment entry

local _, ns = ...

local Options = {}
ns.Options = Options

------------------------------------------------------------------------
-- Sprint key capture dialog
------------------------------------------------------------------------

local capture

local IGNORED_KEYS = {
    UNKNOWN = true,
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}

local function IsIgnoredKey(key)
    if type(key) ~= "string" or key == "" or IGNORED_KEYS[key] then return true end
    if type(IsKeyPressIgnoredForBinding) == "function" then
        local ok, ignored = pcall(IsKeyPressIgnoredForBinding, key)
        if ok and ignored then return true end
    end
    return false
end

local function BuildChord(key)
    if type(CreateKeyChordStringUsingMetaKeyState) == "function" then
        local ok, chord = pcall(CreateKeyChordStringUsingMetaKeyState, key)
        if ok and type(chord) == "string" and chord ~= "" then return chord end
    end
    local parts = {}
    if ns.SafeCheck("IsAltKeyDown") then parts[#parts + 1] = "ALT" end
    if ns.SafeCheck("IsControlKeyDown") then parts[#parts + 1] = "CTRL" end
    if ns.SafeCheck("IsShiftKeyDown") then parts[#parts + 1] = "SHIFT" end
    parts[#parts + 1] = key
    return table.concat(parts, "-")
end

-- Normalise typed input to the canonical ALT-CTRL-SHIFT-META-KEY order.
-- Returns the chord, or nil when the input is not an acceptable sprint key.
local MOD_ORDER = { "ALT", "CTRL", "SHIFT", "META" }
local MOD_SET = { ALT = true, CTRL = true, SHIFT = true, META = true }
local REJECTED_KEYS = {
    BUTTON1 = true, BUTTON2 = true, ESCAPE = true, UNKNOWN = true,
    LALT = true, RALT = true, LCTRL = true, RCTRL = true,
    LSHIFT = true, RSHIFT = true, LMETA = true, RMETA = true,
}
local BIND_USAGE = "Usage: /sprintbar bind <CHORD>, for example SHIFT-F, CTRL+ALT+G or BUTTON4. "
    .. "No spaces; modifiers are ALT, CTRL, SHIFT, META. A modifier alone, BUTTON1, BUTTON2 and ESCAPE are not allowed. "
    .. "For the - and + keys use /sprintbar key."

local function NormalizeChord(input)
    if type(input) ~= "string" then return nil end
    local text = input:upper()
    if text == "" or text:find("%s") then return nil end
    text = text:gsub("%+", "-")
    local tokens = {}
    for token in (text .. "-"):gmatch("([^-]*)-") do
        if token == "" then return nil end
        tokens[#tokens + 1] = token
    end
    local key = tokens[#tokens]
    if not key then return nil end
    local mods = {}
    for i = 1, #tokens - 1 do
        if not MOD_SET[tokens[i]] then return nil end
        mods[tokens[i]] = true
    end
    if MOD_SET[key] or REJECTED_KEYS[key] then return nil end
    local parts = {}
    for _, m in ipairs(MOD_ORDER) do
        if mods[m] then parts[#parts + 1] = m end
    end
    parts[#parts + 1] = key
    return table.concat(parts, "-")
end

local function BindingLabel(action)
    if type(GetBindingName) == "function" then
        local ok, name = pcall(GetBindingName, action)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return action
end

-- GetBindingAction(key, checkOverride): true includes override bindings.
-- Returns the action already bound to the chord, ignoring TOGGLERUN and the addon's own current key.
local function ExistingAction(chord)
    local existing = ns.SafeCall("GetBindingAction", chord, true)
    if type(existing) ~= "string" or existing == "" or existing == "TOGGLERUN" then return nil end
    if ns.db and ns.db.sprintKey == chord then return nil end
    return existing
end

local function SetSprintKey(chord, confirmed)
    if not ns.db then return end
    if not confirmed then
        local existing = ExistingAction(chord)
        if existing then
            ns.Print("Note: " .. chord .. " is already bound to " .. BindingLabel(existing)
                .. ". Sprint Bar's key takes priority while the addon is loaded.")
        end
    end
    ns.db.sprintKey = chord
    ns.ApplySprintBinding()
    ns.Print("Sprint key set to " .. (ns.GetSprintKeyText() or chord) .. " ("
        .. tostring(ns.bindingState) .. ").")
end

local CAPTURE_SECONDS = 15
local CAPTURE_HELP = "Press a key for Sprint (toggles Run/Walk).\n"
    .. "Mouse buttons 3 and up must be clicked on this dialog.\n"
    .. "ESC or Cancel closes it."

-- Every exit path (ESC, Cancel, timeout, key accepted, combat) ends in Hide();
-- OnHide is the single place that turns keyboard capture off.
local function CloseCapture(message)
    if capture and capture:IsShown() then
        capture:Hide()
        if message then ns.Print(message) end
    end
end

-- A chord arrived (key or mouse button). Apply it, or ask for a second press when it is already bound.
local function HandleChord(self, chord)
    if self.pending == chord then
        -- Ignore key auto-repeat: the confirming press must come a moment after the first.
        local now = ns.SafeCall("GetTime")
        if type(now) == "number" and type(self.pendingAt) == "number" and (now - self.pendingAt) < 0.4 then
            return
        end
        CloseCapture()
        SetSprintKey(chord, true)
        return
    end
    local existing = ExistingAction(chord)
    if existing then
        self.pending = chord
        self.pendingAt = ns.SafeCall("GetTime")
        self.remaining = CAPTURE_SECONDS
        self.text:SetText(chord .. " is bound to " .. BindingLabel(existing)
            .. ". Press it again to confirm, or ESC to cancel.")
        return
    end
    CloseCapture()
    SetSprintKey(chord, true)
end

local function CaptureOnUpdate(self, elapsed)
    self.remaining = self.remaining - elapsed
    if self.remaining <= 0 then
        CloseCapture("Sprint key capture timed out.")
        return
    end
    local secs = math.ceil(self.remaining)
    if secs ~= self.shownSeconds then
        self.shownSeconds = secs
        self.timer:SetFormattedText("Closes in %ds", secs)
    end
end

local function CreateCapture()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(400, 150)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)

    local border = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.9, 0.75, 0.2, 1)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.9)

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 12, -12)
    text:SetPoint("TOPRIGHT", -12, -12)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("TOP")
    f.text = text

    local timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetPoint("BOTTOM", 0, 44)
    f.timer = timer

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(100, 24)
    cancel:SetPoint("BOTTOM", 0, 12)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function()
        CloseCapture("Sprint key capture cancelled.")
    end)

    f:SetScript("OnShow", function(self)
        self.pending = nil
        self.remaining = CAPTURE_SECONDS
        self.shownSeconds = nil
        self.text:SetText(CAPTURE_HELP)
        self:EnableKeyboard(true)
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:SetScript("OnUpdate", CaptureOnUpdate)
    end)

    f:SetScript("OnHide", function(self)
        -- Clear the frame's own shown flag too, so a parent hide (cinematic,
        -- UIParent toggle) cannot re-open the capture when the parent returns.
        self:Hide()
        self:EnableKeyboard(false)
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self:SetScript("OnUpdate", nil)
        self.pending = nil
    end)

    -- Keyboard propagation is left at its default (off): the dialog consumes
    -- keys only while shown, and the restricted propagation API is never called.
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            CloseCapture("Sprint key capture cancelled.")
            return
        end
        if IsIgnoredKey(key) then return end
        HandleChord(self, BuildChord(key))
    end)

    f:SetScript("OnMouseDown", function(self, button)
        local conv = button
        if type(GetConvertedKeyOrButton) == "function" then
            local ok, c = pcall(GetConvertedKeyOrButton, button)
            if ok and c then conv = c end
        end
        local n = type(conv) == "string" and tonumber(conv:match("^BUTTON(%d+)$"))
        if n and n >= 3 then
            HandleChord(self, BuildChord(conv))
        end
    end)

    f:SetScript("OnEvent", function()
        CloseCapture("Sprint key capture cancelled (combat).")
    end)
    f:Hide()
    return f
end

function Options.StartCapture()
    if ns.SafeCheck("InCombatLockdown") then
        ns.Print("Cannot capture a key during combat. Try again afterwards.")
        return
    end
    if not capture then
        local ok, result = pcall(CreateCapture)
        if not ok then
            ns.Print("Could not open the key dialog: " .. tostring(result) .. ". Use /sprintbar bind <KEY> instead.")
            return
        end
        capture = result
    end
    capture:Show()
end

------------------------------------------------------------------------
-- Settings category
------------------------------------------------------------------------

local function Pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
local function Secs(v) return string.format("%.1fs", v) end
local function Mult(v) return string.format("x%.1f", v) end
local function Scale(v) return string.format("%.2f", v) end

local ITEMS = {
    { "check", "enabled", "Enabled", "Turn the stamina system on or off." },
    { "check", "locked", "Lock bar", "Unlock to drag the bar. An unlocked bar never fades." },
    { "check", "showText", "Show text", "Show the stamina percentage and state on the bar." },
    { "check", "fadeWhenFull", "Fade when full", "Fade the bar out while stamina is full and you are not sprinting." },
    { "slider", "scale", "Bar scale", "Size of the bar.", 0.5, 2, 0.05, Scale },
    { "slider", "sprintSecondsLevel1", "Sprint seconds at level 1", "How long a full bar lasts while sprinting at level 1.", 2, 60, 1, Secs },
    { "slider", "sprintSecondsMaxLevel", "Sprint seconds at level 60", "How long a full bar lasts while sprinting at level 60 and above.", 5, 180, 1, Secs },
    { "slider", "regenSeconds", "Regeneration seconds", "Seconds to refill an empty bar.", 5, 120, 1, Secs },
    { "slider", "regenDelay", "Regeneration delay", "Seconds after sprinting before stamina regenerates.", 0, 10, 0.5, Secs },
    { "slider", "recoverThreshold", "Recover threshold", "Stamina needed after exhaustion before you may sprint again.", 5, 100, 5, function(v) return string.format("%d", v) end },
    { "slider", "mountedRegenMult", "Mounted regeneration multiplier", "Regeneration speed while on a ground mount.", 1, 3, 0.1, Mult },
    { "slider", "mountedDrainMult", "Mounted drain multiplier", "Drain speed while mounted.", 0, 2, 0.1, Mult },
    { "check", "overlayEnabled", "Exhaustion overlay", "Darken the screen while you sprint with no stamina." },
    { "slider", "overlayMaxAlpha", "Overlay max opacity", "Opacity of the darkening at its strongest.", 0.1, 1, 0.05, Pct },
    { "check", "soundEnabled", "Sound", "Play a sound when you run out of stamina." },
    { "check", "exemptGhost", "Exempt while ghost", "No drain while dead or a ghost." },
    { "check", "debug", "Debug output", "Print diagnostic messages to chat." },
}

local function DefaultFor(key)
    local v = ns.Defaults[key]
    if v == nil then v = ns.StaminaDefaults[key] end
    return v
end

local function OnChanged()
    if ns.Bar and ns.Bar.ApplySettings then ns.Bar.ApplySettings() end
end

local function AddItem(category, item)
    local kind, key, label, tooltip = item[1], item[2], item[3], item[4]
    local varType = Settings.VarType and (kind == "check" and Settings.VarType.Boolean or Settings.VarType.Number)
        or (kind == "check" and "boolean" or "number")
    local setting = Settings.RegisterAddOnSetting(category, "SPRINTBAR_" .. key, key, ns.db, varType, label, DefaultFor(key))
    setting:SetValueChangedCallback(OnChanged)
    if kind == "check" then
        Settings.CreateCheckbox(category, setting, tooltip)
    else
        local opts = Settings.CreateSliderOptions(item[5], item[6], item[7])
        local mixin = MinimalSliderWithSteppersMixin
        if type(opts.SetLabelFormatter) == "function" and mixin and mixin.Label and mixin.Label.Right then
            pcall(opts.SetLabelFormatter, opts, mixin.Label.Right, item[8])
        end
        Settings.CreateSlider(category, setting, opts, tooltip)
    end
end

local registered = false

function Options.Register()
    if registered or not ns.db then return end
    if type(Settings) ~= "table" or type(Settings.RegisterVerticalLayoutCategory) ~= "function" then
        ns.Debug("Settings API unavailable; use slash commands")
        return
    end
    local ok, err = pcall(function()
        local category, layout = Settings.RegisterVerticalLayoutCategory("Sprint Bar")
        Options.category = category

        if type(CreateSettingsButtonInitializer) == "function" and layout and type(layout.AddInitializer) == "function" then
            pcall(function()
                layout:AddInitializer(CreateSettingsButtonInitializer("Sprint key", "Set sprint key",
                    function() Options.StartCapture() end,
                    "Choose the key that toggles run/walk. Also available as /sprintbar key.", true))
            end)
        end

        for _, item in ipairs(ITEMS) do
            local itemOk, itemErr = pcall(AddItem, category, item)
            if not itemOk then ns.Debug("option " .. tostring(item[2]) .. " failed: " .. tostring(itemErr)) end
        end

        Settings.RegisterAddOnCategory(category)
    end)
    if ok then
        registered = true
    else
        ns.Debug("Settings registration failed: " .. tostring(err))
    end
end

function Options.Open()
    if ns.SafeCheck("InCombatLockdown") then
        ns.Print("Options cannot be opened during combat. Try again afterwards.")
        return
    end
    if Options.category and type(Settings) == "table" and type(Settings.OpenToCategory) == "function" then
        local ok = pcall(function() Settings.OpenToCategory(Options.category:GetID()) end)
        if ok then return end
    end
    ns.Print("The options panel is unavailable. Type /sprintbar help for commands.")
end

function SprintBar_OnAddonCompartmentClick()
    Options.Open()
end

------------------------------------------------------------------------
-- Status block
------------------------------------------------------------------------

local function YesNo(v) return v and "yes" or "no" end

function Options.PrintStatus()
    local db, M, state = ns.db, ns.Movement, ns.state
    if not db or not state then ns.Print("Not initialised yet.") return end
    local S = ns.Stamina
    local build = "?"
    local okB, version, buildNum = pcall(GetBuildInfo)
    if okB then build = tostring(version) .. " (" .. tostring(buildNum) .. ")" end

    local level = ns.level
    local lines = {
        "status: Sprint Bar " .. ns.version .. ", client " .. build,
        string.format("level %s, sprintSeconds %.1f, drain %.2f/s, regen %.2f/s (mounted regen x%.1f, drain x%.1f)",
            tostring(level), S.SprintSeconds(level, db), S.DrainRate(level, db), S.RegenRate(db),
            db.mountedRegenMult, db.mountedDrainMult),
        string.format("stamina %.1f, exhausted %s, violating %s, violationTime %.1f",
            state.stamina, YesNo(state.exhausted), YesNo(state.violating), state.violationTime),
        string.format("enabled %s, locked %s, mode %s, pace %s, moving %s",
            YesNo(db.enabled), YesNo(db.locked), tostring(M.mode), tostring(M.pace), YesNo(M.moving)),
    }
    if M.speedReadable then
        lines[#lines + 1] = string.format("speed %.2f (run speed %s), walk ceiling %.1f",
            M.speed, M.runSpeed and string.format("%.2f", M.runSpeed) or "n/a", db.walkSpeedCeiling)
    else
        lines[#lines + 1] = string.format("speed secret/unreadable, walk ceiling %.1f", db.walkSpeedCeiling)
    end
    lines[#lines + 1] = string.format("pace source %s (current %s, runSpeed %s)",
        tostring(M.paceSource), M.speed and string.format("%.2f", M.speed) or "n/a",
        M.runSpeed and string.format("%.2f", M.runSpeed) or "n/a")
    lines[#lines + 1] = "exemption: " .. tostring(M.exemptReason or "none")
        .. "; mounted " .. YesNo(M.mounted) .. ", mountType " .. tostring(M.mountType)
        .. ", ground mount " .. YesNo(M.groundMount)
    lines[#lines + 1] = "sprint key: " .. tostring(ns.GetSprintKeyText()) .. " (addon key "
        .. tostring(db.sprintKey) .. "), override " .. tostring(ns.bindingState)
    lines[#lines + 1] = "toggle hook: setting " .. (db.useToggleHook and "on" or "off")
        .. ", installed " .. YesNo(M.hookInstalled)
    if db.lastBlocked then
        lines[#lines + 1] = "last blocked action: " .. tostring(db.lastBlocked.func)
            .. " at " .. tostring(db.lastBlocked.time)
    else
        lines[#lines + 1] = "last blocked action: none"
    end
    for _, line in ipairs(lines) do ns.Print(line) end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

local HELP = {
    "/sprintbar - open options",
    "/sprintbar key - capture a sprint key; bind <CHORD> (e.g. SHIFT-F, CTRL+G, BUTTON4) / unbind",
    "/sprintbar lock | unlock | reset (position)",
    "/sprintbar enable | disable",
    "/sprintbar hook on|off - run/walk toggle hook (hook off needs /reload)",
    "/sprintbar walkspeed <number> - speed at or below this counts as walking",
    "/sprintbar debug - toggle debug output",
    "/sprintbar status - diagnostic block",
}

local function Slash(msg)
    local db = ns.db
    if not db then return end
    local cmd, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    rest = rest or ""

    if cmd == "" or cmd == "options" or cmd == "config" then
        Options.Open()
    elseif cmd == "key" then
        Options.StartCapture()
    elseif cmd == "bind" then
        local chord = NormalizeChord(rest)
        if chord then
            SetSprintKey(chord)
        else
            ns.Print(BIND_USAGE)
        end
    elseif cmd == "unbind" then
        db.sprintKey = nil
        ns.ApplySprintBinding()
        if ns.bindingState == "will apply after combat" then
            ns.Print("Sprint key cleared; the override will be removed after combat.")
        else
            ns.Print("Sprint key cleared (" .. tostring(ns.bindingState) .. ").")
        end
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = (cmd == "lock")
        ns.Bar.ApplySettings()
        ns.Print("Bar " .. (db.locked and "locked." or "unlocked. Drag it to move."))
    elseif cmd == "reset" then
        ns.Bar.ResetPosition()
        ns.Print("Bar position reset.")
    elseif cmd == "enable" or cmd == "disable" then
        db.enabled = (cmd == "enable")
        ns.Bar.ApplySettings()
        ns.Print(db.enabled and "Enabled." or "Disabled.")
    elseif cmd == "debug" then
        db.debug = not db.debug
        ns.Print("Debug " .. (db.debug and "on." or "off."))
    elseif cmd == "hook" then
        local arg = rest:lower()
        if arg == "on" then
            db.useToggleHook = true
            ns.Movement.InstallHook()
            ns.Print("Toggle hook on.")
        elseif arg == "off" then
            db.useToggleHook = false
            ns.Print("Toggle hook off. Type /reload to remove it completely.")
        else
            ns.Print("Usage: /sprintbar hook on|off")
        end
    elseif cmd == "walkspeed" then
        local n = tonumber(rest)
        if n and n > 0.5 and n < 7 then
            db.walkSpeedCeiling = n
            ns.Print("Walk speed ceiling set to " .. n .. ".")
        else
            ns.Print("Usage: /sprintbar walkspeed <number between 0.5 and 7>. Current: " .. tostring(db.walkSpeedCeiling))
        end
    elseif cmd == "status" then
        Options.PrintStatus()
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end

SLASH_SPRINTBAR1 = "/sprintbar"
SLASH_SPRINTBAR2 = "/sbar"
SlashCmdList["SPRINTBAR"] = function(msg)
    local ok, err = pcall(Slash, msg)
    if not ok then ns.ReportError(err) end
end
