-- Movement.lua
-- Run/walk detection, exemptions, mount lookup, toggle hook, and the sprint key override binding

local addonName, ns = ...

local Movement = {}
ns.Movement = Movement

Movement.mode = nil          -- "walk" | "run" | nil (unknown)
Movement.pace = nil
Movement.paceSource = nil   -- "speed-run" | "speed-walk" | "speed-slow" | "tracked" | "exempt"
Movement.moving = false
Movement.speed = nil         -- last readable current speed
Movement.runSpeed = nil
Movement.speedReadable = false
Movement.exemptReason = nil
Movement.mounted = false
Movement.groundMount = false
Movement.mountType = nil
Movement.hookInstalled = false

local GROUND_MOUNT_TYPE = 230

------------------------------------------------------------------------
-- Speed sample
------------------------------------------------------------------------

-- File-level so the 20 Hz tick creates no closure. Runs under pcall: every
-- comparison on a possibly secret value happens here, so none can raise outside.
-- Returns current, runSpeed, source or nothing when unreadable or secret.
--   source "run"  : current > ceiling
--   source "walk" : current <= ceiling and runSpeed > ceiling * 1.2 (true walk mode)
--   source "slow" : current <= ceiling and runSpeed <= ceiling * 1.2 or unreadable
--                   (snared runner, or a client that reports walk speed as run speed)
local function ReadSpeed(ceiling)
    local c, r = GetUnitSpeed("player")
    if type(issecretvalue) == "function" and (issecretvalue(c) or issecretvalue(r)) then
        return nil
    end
    if type(c) ~= "number" then return nil end
    if c < 0 then return nil end
    if type(r) ~= "number" or r < 0 then r = nil end
    local source
    if c > ceiling then
        source = "run"
    elseif r and r > ceiling * 1.2 then
        source = "walk"
    else
        source = "slow"
    end
    return c, r, source
end

function Movement.SampleSpeed(ceiling)
    if type(GetUnitSpeed) ~= "function" then return nil end
    local ok, current, run, source = pcall(ReadSpeed, ceiling)
    if not ok or current == nil then return nil end
    return current, run, source
end

------------------------------------------------------------------------
-- Mount lookup (cached)
------------------------------------------------------------------------

local mountDirty, mountTries, mountTimer = false, 0, 0

-- Returns the active mount's mountTypeID, or nil when it cannot be determined.
local function FindActiveMountType()
    local j = C_MountJournal
    if type(j) ~= "table" or type(j.GetMountIDs) ~= "function"
        or type(j.GetMountInfoByID) ~= "function" or type(j.GetMountInfoExtraByID) ~= "function" then
        return nil
    end
    local ok, result = pcall(function()
        local ids = j.GetMountIDs()
        if type(ids) ~= "table" then return nil end
        for i = 1, #ids do
            local id = ids[i]
            local _, _, _, isActive = j.GetMountInfoByID(id)
            if isActive then
                local _, _, _, _, typeID = j.GetMountInfoExtraByID(id)
                if type(typeID) == "number" then return typeID end
                return nil
            end
        end
        return nil
    end)
    if ok then return result end
    return nil
end

local function MarkMountDirty()
    mountDirty, mountTries, mountTimer = true, 0, 0
end

------------------------------------------------------------------------
-- Exemptions
------------------------------------------------------------------------

local function GetExemptReason()
    if ns.SafeCheck("UnitOnTaxi", "player") then return "taxi" end
    if ns.SafeCheck("IsFlying") then return "flying" end
    if ns.SafeCheck("IsSwimming") then return "swimming" end
    if ns.SafeCheck("UnitInVehicle", "player") then return "vehicle" end
    if ns.db and ns.db.exemptGhost and ns.SafeCheck("UnitIsDeadOrGhost", "player") then return "dead/ghost" end
    return nil
end

------------------------------------------------------------------------
-- Per-tick update; returns the context for the stamina model
------------------------------------------------------------------------

local ctx = {}

function Movement.Update(dt)
    local db = ns.db
    local M = Movement

    local reason = GetExemptReason()
    M.exemptReason = reason

    local mounted = ns.SafeCheck("IsMounted")
    if mounted ~= M.mounted then
        M.mounted = mounted
        M.mountType = nil
        if mounted then MarkMountDirty() else mountDirty = false end
    end
    if mounted and mountDirty then
        mountTimer = mountTimer - dt
        if mountTimer <= 0 then
            mountTimer = 0.5
            mountTries = mountTries + 1
            M.mountType = FindActiveMountType()
            if M.mountType ~= nil or mountTries >= 5 then mountDirty = false end
        end
    end
    local flying = ns.SafeCheck("IsFlying")
    M.groundMount = mounted and not flying and (M.mountType == nil or M.mountType == GROUND_MOUNT_TYPE)

    local ceiling = db.walkSpeedCeiling
    if type(ceiling) ~= "number" then ceiling = 3.0 end

    local current, run, source = Movement.SampleSpeed(ceiling)
    if current then
        M.speedReadable = true
        M.speed, M.runSpeed = current, run
        if current > 0.1 then
            M.moving = true
            if reason then
                -- Exempt (taxi, flying, swimming, vehicle, ghost): speed says nothing about run/walk.
                M.pace, M.paceSource = M.mode, "exempt"
            elseif source == "run" then
                M.pace, M.paceSource, M.mode = "run", "speed-run", "run"
            elseif source == "walk" then
                M.pace, M.paceSource, M.mode = "walk", "speed-walk", "walk"
            else
                -- Walk for drain purposes; the mode stays as tracked.
                M.pace, M.paceSource = "walk", "speed-slow"
            end
        else
            M.pace, M.paceSource = M.mode, reason and "exempt" or "tracked"
            M.moving = false
        end
    else
        M.speedReadable = false
        M.speed, M.runSpeed = nil, nil
        M.pace, M.paceSource = M.mode, reason and "exempt" or "tracked"
        M.moving = ns.SafeCheck("IsPlayerMoving")
    end

    -- One context table, updated in place (the 20 Hz tick must not allocate).
    ctx.level = ns.level
    ctx.enabled = db.enabled
    ctx.exempt = reason ~= nil
    ctx.exemptReason = reason
    ctx.moving = M.moving
    ctx.pace = M.pace
    ctx.mounted = mounted
    ctx.groundMount = M.groundMount
    return ctx
end

------------------------------------------------------------------------
-- ToggleRun hook (observe only; never call ToggleRun)
------------------------------------------------------------------------

local function InstallHook()
    if Movement.hookInstalled then return end
    if not (ns.db and ns.db.useToggleHook) then return end
    if type(ToggleRun) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    local ok = pcall(hooksecurefunc, "ToggleRun", function()
        if not (ns.db and ns.db.useToggleHook) then return end
        if Movement.mode == "run" then
            Movement.mode = "walk"
        elseif Movement.mode == "walk" then
            Movement.mode = "run"
        end
    end)
    Movement.hookInstalled = ok
end

Movement.InstallHook = InstallHook

local warned = {}

local function OnActionBlocked(isTainted, funcName)
    if isTainted ~= addonName or not ns.db then return end
    local name = tostring(funcName)
    ns.db.lastBlocked = { func = name, time = time() }
    local kind = name:find("ToggleRun", 1, true) and "toggle" or "other"
    if warned[kind] then return end
    warned[kind] = true
    if kind == "toggle" then
        ns.Print("Blizzard blocked an action attributed to Sprint Bar (" .. name
            .. "). If this started after the run/walk hook was installed, try /sprintbar hook off and then /reload.")
    else
        ns.Print("|cff999999Blizzard reported a blocked action attributed to Sprint Bar (" .. name
            .. "). Shown once per session; see /sprintbar status.|r")
    end
end

function Movement.Init()
    InstallHook()
    ns.RegisterEvent("ADDON_ACTION_BLOCKED", OnActionBlocked)
    ns.RegisterEvent("ADDON_ACTION_FORBIDDEN", OnActionBlocked)
    ns.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", MarkMountDirty)
end

------------------------------------------------------------------------
-- Sprint key (override binding to the TOGGLERUN command)
------------------------------------------------------------------------

local bindOwner = CreateFrame("Frame")
local bindingPending = false

ns.bindingState = "not applied"

function ns.ApplySprintBinding()
    local db = ns.db
    if not db then return end

    if ns.SafeCheck("InCombatLockdown") then
        bindingPending = true
        ns.bindingState = "will apply after combat"
        return
    end
    bindingPending = false

    local ok, err = pcall(function()
        ClearOverrideBindings(bindOwner)
        if type(db.sprintKey) == "string" and db.sprintKey ~= "" then
            SetOverrideBinding(bindOwner, true, db.sprintKey, "TOGGLERUN")
        end
    end)
    if not ok then
        ns.bindingState = "error: " .. tostring(err)
    elseif db.sprintKey and db.sprintKey ~= "" then
        ns.bindingState = "applied"
    else
        ns.bindingState = "no addon key set"
    end
end

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if bindingPending then ns.ApplySprintBinding() end
end)

local function DisplayKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    if type(GetBindingText) == "function" then
        local ok, text = pcall(GetBindingText, key)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return key
end

function ns.GetSprintKeyText()
    if ns.db and type(ns.db.sprintKey) == "string" and ns.db.sprintKey ~= "" then
        return DisplayKey(ns.db.sprintKey)
    end
    if type(GetBindingKey) == "function" then
        local ok, key = pcall(GetBindingKey, "TOGGLERUN")
        if ok then return DisplayKey(key) end
    end
    return nil
end
