-- Stamina.lua
-- Pure stamina model: no WoW API calls, takes dt, a context table and settings as arguments

local _, ns = ...
ns = ns or {}

local Stamina = {}
ns.Stamina = Stamina

-- Settings owned by the model. Core merges these into the saved variables.
ns.StaminaDefaults = {
    maxLevel = 60,
    sprintSecondsLevel1 = 8,
    sprintSecondsMaxLevel = 30,
    regenSeconds = 20,
    regenDelay = 1.5,
    recoverThreshold = 25,
    mountedRegenMult = 1.5,
    mountedDrainMult = 1.0,
    debtMax = 30,
}

local D = ns.StaminaDefaults
local DEFAULT_RAMP = 4 -- matches Defaults.overlayRampSeconds in Core.lua

local function opt(s, key)
    local v = s and s[key]
    if type(v) ~= "number" or v ~= v then v = D[key] end
    return v
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Seconds of continuous sprinting that empty a full bar at this level.
function Stamina.SprintSeconds(level, s)
    local maxLevel = opt(s, "maxLevel")
    local t = 0
    if type(level) == "number" and maxLevel > 1 then
        t = clamp((level - 1) / (maxLevel - 1), 0, 1)
    end
    local a, b = opt(s, "sprintSecondsLevel1"), opt(s, "sprintSecondsMaxLevel")
    local seconds = a + (b - a) * t
    if seconds < 0.1 then seconds = 0.1 end
    return seconds
end

function Stamina.DrainRate(level, s)
    return 100 / Stamina.SprintSeconds(level, s)
end

function Stamina.RegenRate(s)
    local seconds = opt(s, "regenSeconds")
    if seconds < 0.1 then seconds = 0.1 end
    return 100 / seconds
end

function Stamina.NewState()
    return {
        stamina = 100,
        exhausted = false,
        draining = false,
        violating = false,
        violationTime = 0,
        sinceDrain = 1000,
    }
end

local function fire(event)
    if type(ns.Fire) == "function" then ns.Fire(event) end
end

-- ctx: { level, enabled, exempt, moving, pace, mounted, groundMount }
function Stamina.Step(state, dt, ctx, s)
    if type(dt) ~= "number" or dt <= 0 then return end
    ctx = ctx or {}

    local debtMax = opt(s, "debtMax")
    local floor = -debtMax

    local draining = ctx.enabled == true and not ctx.exempt and ctx.moving == true and ctx.pace == "run"
    state.draining = draining

    if draining then
        local rate = Stamina.DrainRate(ctx.level, s)
        if ctx.mounted then rate = rate * opt(s, "mountedDrainMult") end
        state.stamina = state.stamina - rate * dt
        state.sinceDrain = 0
    else
        state.sinceDrain = state.sinceDrain + dt
        if state.sinceDrain >= opt(s, "regenDelay") then
            local rate = Stamina.RegenRate(s)
            if ctx.groundMount then rate = rate * opt(s, "mountedRegenMult") end
            state.stamina = state.stamina + rate * dt
        end
    end

    state.stamina = clamp(state.stamina, floor, 100)

    if not state.exhausted and state.stamina <= 0 then
        state.exhausted = true
        fire("EXHAUSTED")
    elseif state.exhausted and state.stamina >= opt(s, "recoverThreshold") then
        state.exhausted = false
        fire("RECOVERED")
    end

    local violating = state.exhausted and draining
    if violating and not state.violating then
        state.violating = true
        fire("VIOLATION_START")
    elseif not violating and state.violating then
        state.violating = false
        fire("VIOLATION_END")
    end

    if violating then
        -- Capped at the overlay ramp length so the overlay clears about
        -- ramp/2 seconds after the player complies, however long the violation lasted.
        local ramp = s and s.overlayRampSeconds
        if type(ramp) ~= "number" or ramp ~= ramp or ramp <= 0 then ramp = DEFAULT_RAMP end
        state.violationTime = state.violationTime + dt
        if state.violationTime > ramp then state.violationTime = ramp end
    else
        state.violationTime = state.violationTime - 2 * dt
        if state.violationTime < 0 then state.violationTime = 0 end
    end
end

-- Persistence helpers (the caller supplies the saved table and the wall clock).
function Stamina.Save(state, saved, now)
    if type(saved) ~= "table" or type(state) ~= "table" then return end
    saved.stamina = state.stamina
    saved.exhausted = state.exhausted and true or false
    saved.savedAt = now
end

function Stamina.Restore(state, saved, now, s)
    if type(saved) ~= "table" or type(state) ~= "table" then return end
    local stamina = saved.stamina
    if type(stamina) ~= "number" or stamina ~= stamina then stamina = 100 end
    local exhausted = saved.exhausted == true

    if type(saved.savedAt) == "number" and type(now) == "number" and now > saved.savedAt then
        stamina = stamina + (now - saved.savedAt) * Stamina.RegenRate(s)
    end

    stamina = clamp(stamina, -opt(s, "debtMax"), 100)
    if exhausted and stamina >= opt(s, "recoverThreshold") then
        exhausted = false
    end
    state.stamina = stamina
    state.exhausted = exhausted
    state.sinceDrain = 1000
end
