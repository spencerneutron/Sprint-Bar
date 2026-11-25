-- Bar.lua
-- Stamina bar, exhaustion overlay, warning messages and sounds (own frames only, nothing protected)

local _, ns = ...

local Bar = {}
ns.Bar = Bar

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }

local COLOR_NORMAL = { 0.90, 0.75, 0.20 }
local COLOR_SPRINT = { 0.30, 0.95, 0.30 }
local COLOR_EXHAUSTED = { 0.85, 0.10, 0.10 }
local COLOR_DEBT = { 0.40, 0.00, 0.00 }

local FADE_HOLD = 1.5     -- seconds at full before fading out
local FADE_SECONDS = 0.5  -- full fade duration
local WARN_INTERVAL = 3

local bar, label, debtTex, overlay, overlayTex
local alpha, fullTime, warnTimer = 1, 0, 0
local lastValue

------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------

local function ApplyPosition()
    if not bar then return end
    local pos = ns.db and ns.db.position
    if type(pos) ~= "table" or not pos.point then pos = DEFAULT_POSITION end
    bar:ClearAllPoints()
    bar:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
end

local function SavePosition()
    if not bar or not ns.db then return end
    local point, _, relativePoint, x, y = bar:GetPoint(1)
    if point then
        ns.db.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
end

function Bar.ResetPosition()
    if ns.db then ns.db.position = nil end
    ApplyPosition()
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

local function CreateOverlay()
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("BACKGROUND")
    overlay:EnableMouse(false)
    overlayTex = overlay:CreateTexture(nil, "BACKGROUND")
    overlayTex:SetAllPoints(overlay)
    overlayTex:SetColorTexture(0, 0, 0, 1)
    overlay:SetAlpha(0)
    overlay:Hide()
end

function Bar.Create()
    if bar then return end
    local db = ns.db

    bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetSize(db.barWidth, db.barHeight)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)

    local border = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)

    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.85)

    debtTex = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    debtTex:SetColorTexture(COLOR_DEBT[1], COLOR_DEBT[2], COLOR_DEBT[3], 1)
    debtTex:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    debtTex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    debtTex:SetWidth(1)
    debtTex:Hide()

    label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", bar, "CENTER", 0, 0)

    bar:SetScript("OnDragStart", function(self)
        if ns.db and not ns.db.locked then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    ApplyPosition()
    CreateOverlay()

    ns.On("EXHAUSTED", Bar.OnExhausted)
    ns.On("RECOVERED", Bar.OnRecovered)
    ns.On("VIOLATION_START", function() warnTimer = WARN_INTERVAL end)
    ns.On("VIOLATION_END", function() warnTimer = 0 end)

    Bar.ApplySettings()
end

function Bar.ApplySettings()
    if not bar or not ns.db then return end
    local db = ns.db
    bar:SetScale(db.scale or 1)
    bar:SetSize(db.barWidth, db.barHeight)
    bar:EnableMouse(not db.locked)
    if not db.locked then
        alpha = 1
        fullTime = 0
    end
    if db.enabled or not db.locked then bar:Show() else bar:Hide() end
    if not db.showText then label:SetText("") end
end

------------------------------------------------------------------------
-- Feedback
------------------------------------------------------------------------

local function ErrorMessage(text, r, g, b)
    if UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, r, g, b)
    end
end

function Bar.OnExhausted()
    local db = ns.db
    if not db or not db.enabled then return end
    if db.soundEnabled and type(PlaySound) == "function" and type(SOUNDKIT) == "table" and SOUNDKIT.ALARM_CLOCK_WARNING_2 then
        pcall(PlaySound, SOUNDKIT.ALARM_CLOCK_WARNING_2)
    end
end

function Bar.OnRecovered()
    local db = ns.db
    if not db or not db.enabled then return end
    ErrorMessage("Stamina recovered.", 0.3, 1, 0.3)
end

local function WarnText()
    local key = ns.GetSprintKeyText()
    if key then
        return "Out of stamina. Press " .. key .. " to walk."
    end
    return "Bind a sprint key: /sprintbar"
end

------------------------------------------------------------------------
-- Update
------------------------------------------------------------------------

local function SetColor(c)
    bar:SetStatusBarColor(c[1], c[2], c[3])
end

local function StateLabel(state)
    if state.exhausted then return "EXHAUSTED" end
    local mode = ns.Movement.mode
    if mode == "walk" then return "WALK" end
    if mode == "run" then return "SPRINT" end
    return "?"
end

local function SetBarValue(v)
    if v == lastValue then return end
    lastValue = v
    local enum = Enum and Enum.StatusBarInterpolation
    if enum and enum.ExponentialEaseOut then
        local ok = pcall(bar.SetValue, bar, v, enum.ExponentialEaseOut)
        if ok then return end
    end
    bar:SetValue(v)
end

local function UpdateOverlay(db, state)
    local a = 0
    if db.enabled and db.overlayEnabled then
        local ramp = db.overlayRampSeconds
        if type(ramp) ~= "number" or ramp <= 0 then ramp = 4 end
        local frac = state.violationTime / ramp
        if frac > 1 then frac = 1 end
        a = frac * (db.overlayMaxAlpha or 0.85)
    end
    if a > 0.001 then
        overlay:SetAlpha(a)
        if not overlay:IsShown() then overlay:Show() end
    elseif overlay:IsShown() then
        overlay:SetAlpha(0)
        overlay:Hide()
    end
end

local function UpdateFade(db, dt, state, sprinting)
    local target = 1
    if db.locked and db.fadeWhenFull then
        local full = state.stamina >= 99.5 and not state.exhausted
        if full and not sprinting then
            fullTime = fullTime + dt
            if fullTime >= FADE_HOLD then target = 0 end
        else
            fullTime = 0
        end
    else
        fullTime = 0
    end
    if alpha < target then
        alpha = math.min(target, alpha + dt / (FADE_SECONDS * 0.5))
    elseif alpha > target then
        alpha = math.max(target, alpha - dt / FADE_SECONDS)
    end
    bar:SetAlpha(alpha)
end

function Bar.Update(dt, _, state)
    if not bar then return end
    local db = ns.db
    if not db then return end

    UpdateOverlay(db, state)

    local visible = db.enabled or not db.locked
    if bar:IsShown() ~= visible then
        if visible then bar:Show() else bar:Hide() end
    end
    if not visible then return end

    local sprinting = state.draining
    local value = state.stamina
    SetBarValue(value > 0 and value or 0)

    if value < 0 then
        local frac = -value / (db.debtMax or 30)
        if frac > 1 then frac = 1 end
        debtTex:SetWidth(math.max(1, bar:GetWidth() * frac))
        debtTex:Show()
        SetColor(COLOR_DEBT)
    else
        debtTex:Hide()
        if state.exhausted then
            SetColor(COLOR_EXHAUSTED)
        elseif sprinting then
            SetColor(COLOR_SPRINT)
        else
            SetColor(COLOR_NORMAL)
        end
    end

    if db.showText then
        label:SetFormattedText("%s  %d%%", StateLabel(state), math.floor(value + 0.5))
    end

    UpdateFade(db, dt, state, sprinting)

    if state.violating then
        warnTimer = warnTimer + dt
        if warnTimer >= WARN_INTERVAL then
            warnTimer = 0
            ErrorMessage(WarnText(), 1, 0.2, 0.2)
        end
    end
end
