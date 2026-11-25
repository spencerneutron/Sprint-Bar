-- Core.lua
-- Private namespace, saved variables, event dispatch, callbacks, and the single update loop

local addonName, ns = ...

ns.name = addonName
ns.prefix = "|cff00ccff[Sprint Bar]|r "

local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata
ns.version = "unknown"
if type(getMeta) == "function" then
    local ok, v = pcall(getMeta, addonName, "Version")
    if ok and type(v) == "string" and v ~= "" then ns.version = v end
end

------------------------------------------------------------------------
-- Defaults and migrations
------------------------------------------------------------------------

ns.Defaults = {
    enabled = true,
    locked = true,
    showText = true,
    fadeWhenFull = true,
    scale = 1.0,
    barWidth = 200,
    barHeight = 14,
    position = nil, -- { point, relativePoint, x, y }

    sprintKey = nil,
    useToggleHook = true,
    walkSpeedCeiling = 3.0,
    exemptGhost = false,

    overlayEnabled = true,
    overlayMaxAlpha = 0.85,
    overlayRampSeconds = 4,
    soundEnabled = true,

    lastBlocked = nil, -- { func = string, time = number }
    debug = false,
    configVersion = 1,
}

ns.CharDefaults = {
    stamina = 100,
    exhausted = false,
    savedAt = nil,
    configVersion = 1,
}

-- Migration table: add functions keyed by the target version number.
ns.migrations = {
    -- [2] = function(db, charDB) ... end,
}

local function MergeDefaults(db, defaults)
    if type(db) ~= "table" or type(defaults) ~= "table" then return end
    for k, v in pairs(defaults) do
        if db[k] == nil then
            db[k] = v
        end
    end
end

local function RunMigrations(db, charDB, fromVersion, target)
    for v = (fromVersion or 0) + 1, target do
        local fn = ns.migrations[v]
        if type(fn) == "function" then
            pcall(fn, db, charDB)
        end
    end
end

------------------------------------------------------------------------
-- Printing, debug, safe helpers
------------------------------------------------------------------------

function ns.Print(msg)
    local text = ns.prefix .. tostring(msg)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    else
        print(text)
    end
end

function ns.Debug(msg)
    if ns.db and ns.db.debug then
        ns.Print("|cff999999" .. tostring(msg) .. "|r")
    end
end

-- File-level helper so SafeCheck allocates nothing per call (no closure, no vararg table).
-- The truthiness test runs inside the pcall so a secret value cannot raise.
local function Truthy(fn, ...)
    if fn(...) then return true end
    return false
end

-- Call a global API by name under pcall; return a boolean (never errors, never leaks secrets).
function ns.SafeCheck(fnName, ...)
    local fn = _G[fnName]
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(Truthy, fn, ...)
    return ok and result == true
end

-- Call a global API by name under pcall; return its first result or nil.
function ns.SafeCall(fnName, ...)
    local fn = _G[fnName]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

function ns.IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, result = pcall(issecretvalue, v)
    return ok and result == true
end

------------------------------------------------------------------------
-- Internal callbacks (Stamina -> Bar)
------------------------------------------------------------------------

local callbacks = {}

function ns.On(event, fn)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end

function ns.Fire(event, ...)
    ns.Debug("event " .. tostring(event))
    local list = callbacks[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ns.ReportError(err) end
    end
end

------------------------------------------------------------------------
-- Error reporting (once per distinct message, capped)
------------------------------------------------------------------------

local seenErrors, seenCount = {}, 0

function ns.ReportError(err)
    local text = tostring(err)
    if seenErrors[text] or seenCount >= 5 then return end
    seenErrors[text] = true
    seenCount = seenCount + 1
    ns.Print("|cffff5555error:|r " .. text)
    ns.Print("Report this with /sprintbar status. Further errors are hidden.")
end

------------------------------------------------------------------------
-- Event dispatch
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then ns.Debug("could not register " .. tostring(event)) end
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ns.ReportError(err) end
    end
end)

------------------------------------------------------------------------
-- Update loop
------------------------------------------------------------------------

local TICK = 0.05
local accumulated = 0
local loopFrame = CreateFrame("Frame")

local function ErrorPassthrough(e) return e end

local function Tick(dt)
    local ctx = ns.Movement.Update(dt)
    ns.Stamina.Step(ns.state, dt, ctx, ns.db)
    ns.Bar.Update(dt, ctx, ns.state)
end

local function OnUpdate(_, elapsed)
    accumulated = accumulated + elapsed
    if accumulated < TICK then return end
    local dt = accumulated
    accumulated = 0
    if dt > 0.5 then dt = 0.5 end
    local ok, err = xpcall(Tick, ErrorPassthrough, dt)
    if not ok then ns.ReportError(err) end
end

function ns.StartLoop()
    loopFrame:SetScript("OnUpdate", OnUpdate)
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

local function InitDB()
    SprintBarDB = SprintBarDB or {}
    SprintBarCharDB = SprintBarCharDB or {}
    local db, charDB = SprintBarDB, SprintBarCharDB

    local current = db.configVersion or 0
    local target = ns.Defaults.configVersion
    if current < target then
        RunMigrations(db, charDB, current, target)
    end
    MergeDefaults(db, ns.Defaults)
    MergeDefaults(db, ns.StaminaDefaults)
    db.configVersion = target

    MergeDefaults(charDB, ns.CharDefaults)
    charDB.configVersion = ns.CharDefaults.configVersion

    ns.db, ns.charDB = db, charDB
end

local function ReadLevel()
    local lvl = ns.SafeCall("UnitLevel", "player")
    if type(lvl) == "number" and not ns.IsSecret(lvl) then
        ns.level = lvl
    end
end

local function OnLogin()
    ReadLevel()
    ns.state = ns.Stamina.NewState()
    ns.Stamina.Restore(ns.state, ns.charDB, time(), ns.db)

    local steps = {
        function() ns.Bar.Create() end,
        function() ns.Movement.Init() end,
        function() ns.ApplySprintBinding() end,
        function() ns.Options.Register() end,
    }
    for _, step in ipairs(steps) do
        local ok, err = pcall(step)
        if not ok then ns.ReportError(err) end
    end

    ns.StartLoop()

    local keyText = ns.GetSprintKeyText()
    if keyText then
        ns.Print("Sprint key: " .. keyText .. " (toggles run/walk). Run/Walk state is unknown until you move. /sprintbar for options.")
    else
        ns.Print("No sprint key set. Type /sprintbar key to choose one. Run/Walk state is unknown until you move.")
    end
end

ns.RegisterEvent("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    InitDB()
end)

ns.RegisterEvent("PLAYER_LOGIN", OnLogin)

ns.RegisterEvent("PLAYER_LEVEL_UP", function(newLevel)
    if type(newLevel) == "number" and not ns.IsSecret(newLevel) then
        ns.level = newLevel
    else
        ReadLevel()
    end
end)

ns.RegisterEvent("PLAYER_LOGOUT", function()
    if ns.state and ns.charDB then
        ns.Stamina.Save(ns.state, ns.charDB, time())
    end
end)
