-- PerHour: gold per hour and experience per hour.
--
-- Each counter has its own Pause and Reset. Only time spent logged in and
-- unpaused counts, and the totals survive /reload and logout, so the rate
-- stays honest across sessions until you reset it. Gold is the net change
-- in your money: loot, quest rewards and vendor sales, minus repairs and
-- purchases. Drag the window to move it; hover a counter for its totals.
--
--   /perhour         show or hide the window (also /ph)
--   /perhour reset   reset both counters

local WIDTH, HEIGHT, TAB = 170, 64, 14
local RUNNING, PAUSED = { 0.25, 0.9, 0.35 }, { 0.9, 0.25, 0.2 }

local db, holder
local panels = {}
local lastMoney, lastXP, lastMax, lastTick

local function Rate(t)
    return t.elapsed > 0 and t.total / t.elapsed * 3600 or 0
end

local function Duration(s)
    s = math.floor(s)
    return ("%dh %02dm %02ds"):format(math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60)
end

local function Money(copper)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    if GetMoneyString then return sign .. GetMoneyString(copper, true) end
    return ("%s%.2fg"):format(sign, copper / 10000)
end

local function Number(n)
    n = math.floor(n + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function MaxLevel()
    if IsPlayerAtEffectiveMaxLevel then return IsPlayerAtEffectiveMaxLevel() end
    return UnitXPMax("player") == 0
end

local COUNTERS = {
    { key = "gold", title = "Gold",
      rate = function(t) return ("%.2f |cffffd100g/h|r"):format(Rate(t) / 10000) end,
      total = function(t) return Money(t.total) end },
    { key = "xp", title = "Experience",
      rate = function(t)
          if MaxLevel() then return "|cff999999Max level|r" end
          return Number(Rate(t)) .. " |cffffd100XP/h|r"
      end,
      total = function(t) return Number(t.total) .. " XP" end },
}

local function Refresh()
    for _, c in ipairs(COUNTERS) do
        local t, p = db[c.key], panels[c.key]
        p.rate:SetText(c.rate(t))
        p.pause:SetText(t.paused and "Resume" or "Pause")
        p.pause.dot:SetVertexColor(unpack(t.paused and PAUSED or RUNNING))
    end
end

local function Reset(t)
    t.total, t.elapsed = 0, 0
end

-- Events ------------------------------------------------------------------

local function OnMoney()
    local money = GetMoney()
    if not db.gold.paused then db.gold.total = db.gold.total + (money - lastMoney) end
    lastMoney = money
end

local function OnXP()
    local xp, max = UnitXP("player"), UnitXPMax("player")
    local gained = xp - lastXP
    if gained < 0 then gained = lastMax - lastXP + xp end -- levelled up
    if not db.xp.paused and gained > 0 then db.xp.total = db.xp.total + gained end
    lastXP, lastMax = xp, max
end

local function Tick()
    local now = GetTime()
    local dt = now - lastTick
    lastTick = now
    for _, c in ipairs(COUNTERS) do
        local t = db[c.key]
        if not t.paused then t.elapsed = t.elapsed + dt end
    end
    Refresh()
end

-- Window ------------------------------------------------------------------

local function Skin(f)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.17, 0.04, 0.03, 0.92)
    f:SetBackdropBorderColor(0.78, 0.62, 0.32, 1)
end

local function StopMoving()
    holder:StopMovingOrSizing()
    local point, _, relPoint, x, y = holder:GetPoint()
    db.point = { point, relPoint, x, y }
end

local function CreatePanel(c, y)
    local p = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    p:SetSize(WIDTH, HEIGHT)
    p:SetPoint("TOP", 0, y)
    Skin(p)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function() holder:StartMoving() end)
    p:SetScript("OnDragStop", StopMoving)
    p:SetScript("OnEnter", function(self)
        local t = db[c.key]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(c.title)
        GameTooltip:AddDoubleLine("Earned", c.total(t), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Time", Duration(t.elapsed), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local tab = CreateFrame("Frame", nil, p, "BackdropTemplate")
    tab:SetSize(96, 22)
    tab:SetPoint("BOTTOM", p, "TOP", 0, -8)
    Skin(tab)
    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", 0, 0)
    title:SetText(c.title)

    p.rate = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    p.rate:SetPoint("TOP", 0, -18)

    local pause = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    pause:SetSize(86, 20)
    pause:SetPoint("BOTTOMLEFT", 12, 8)
    pause.dot = pause:CreateTexture(nil, "OVERLAY")
    pause.dot:SetSize(7, 7)
    pause.dot:SetPoint("LEFT", 10, 0)
    pause.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    if pause.dot.SetRotation then pause.dot:SetRotation(math.rad(45)) end
    pause:SetScript("OnClick", function()
        db[c.key].paused = not db[c.key].paused
        Refresh()
    end)
    p.pause = pause

    local reset = CreateFrame("Button", nil, p)
    reset:SetSize(20, 20)
    reset:SetPoint("BOTTOMRIGHT", -12, 8)
    reset:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    reset:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    reset:SetScript("OnClick", function()
        Reset(db[c.key])
        Refresh()
    end)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset " .. c.title:lower())
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panels[c.key] = p
end

local function CreateWindow()
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(WIDTH, #COUNTERS * (HEIGHT + TAB + 8))
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    local pt = db.point or { "CENTER", "CENTER", 300, 0 }
    holder:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    for i, c in ipairs(COUNTERS) do
        CreatePanel(c, -TAB - (i - 1) * (HEIGHT + TAB + 8))
    end
    holder:SetShown(db.shown)
end

-- Start -------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        PerHourDB = PerHourDB or {}
        db = PerHourDB
        for _, c in ipairs(COUNTERS) do
            db[c.key] = db[c.key] or { total = 0, elapsed = 0 }
        end
        if db.shown == nil then db.shown = true end

        lastMoney = GetMoney()
        lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
        lastTick = GetTime()
        CreateWindow()
        Refresh()
        C_Timer.NewTicker(1, Tick)
        events:RegisterEvent("PLAYER_MONEY")
        events:RegisterEvent("PLAYER_XP_UPDATE")
    elseif event == "PLAYER_MONEY" then
        OnMoney()
    elseif event == "PLAYER_XP_UPDATE" then
        OnXP()
    end
end)

SLASH_PERHOUR1, SLASH_PERHOUR2 = "/perhour", "/ph"
SlashCmdList.PERHOUR = function(input)
    if not db then return end
    if (input or ""):lower():match("^%s*reset") then
        for _, c in ipairs(COUNTERS) do Reset(db[c.key]) end
        Refresh()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99PerHour|r: counters reset.")
    else
        db.shown = not db.shown
        holder:SetShown(db.shown)
    end
end
