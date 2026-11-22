-- PerHour (Gold and XP Per Hour): gold per hour and experience per hour.
--
-- Each counter has its own Pause and Reset. Only time spent logged in,
-- unpaused and not AFK counts, and the totals survive /reload and logout, so
-- the rate stays honest across sessions until you reset it.
--
-- Gold is the money you make in the world: loot, quest rewards and vendor
-- sales, minus repairs and purchases. Money that moves while the mailbox,
-- trade window, auction house or guild bank is open is a transfer, not
-- farming, and is not counted. Experience shows the time to your next level
-- at the session's rate, and hides itself at max level.
--
-- Drag the window to move it; hover a counter for its totals. If another
-- addon has loaded LibDataBroker, the rates also show on broker bars (Titan
-- Panel and the like), and on a minimap button when LibDBIcon is loaded.
--
--   /goldxp          show or hide the window (also /perhour and /ph, unless
--                    another addon already uses them)
--   /goldxp gold     show or hide the gold counter (/goldxp xp for experience)
--   /goldxp scale N  resize the window, 0.5 to 2
--   /goldxp minimap  show or hide the minimap button
--   /goldxp reset    reset both counters

local WIDTH, HEIGHT, TAB, GAP = 170, 80, 14, 8
local RUNNING, PAUSED, AFK = { 0.25, 0.9, 0.35 }, { 0.9, 0.25, 0.2 }, { 1, 0.8, 0.2 }
local GRACE = 2 -- seconds around a transfer window opening or closing
-- Money moved at these is a transfer, not farming. Interaction types are
-- Enum.PlayerInteractionType (numbers as Questie uses them on this client).
local PIT = Enum and Enum.PlayerInteractionType or {}
local TRANSFER_TYPES = {
    [PIT.TradePartner or 1] = true, [PIT.GuildBanker or 10] = true,
    [PIT.MailInfo or 17] = true, [PIT.Auctioneer or 21] = true,
}
local TRANSFER_FRAMES = { "MailFrame", "TradeFrame", "AuctionHouseFrame", "AuctionFrame", "GuildBankFrame" }
local TRANSFER_EVENTS = { "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED" }

local db, holder, broker, icon
local panels = {}
local graceUntil = 0
local lastMoney, lastXP, lastMax, lastTick, wasMax

local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99PerHour|r: " .. text)
end

local function Rate(t)
    return t.elapsed > 0 and t.total / t.elapsed * 3600 or 0
end

local function Duration(s)
    s = math.floor(s)
    return ("%dh %02dm %02ds"):format(math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60)
end

local function Short(s)
    local m = math.max(math.floor(s / 60), 1)
    if m < 60 then return m .. "m" end
    return ("%dh %02dm"):format(math.floor(m / 60), m % 60)
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

local function Away()
    return UnitIsAFK("player") and true or false
end

local COUNTERS = {
    { key = "gold", title = "Gold", unit = "g/h",
      rate = function(t) return ("%.2f"):format(Rate(t) / 10000) end,
      sub = function(t) return "Session " .. Money(t.total) end,
      total = function(t) return Money(t.total) end,
      note = "Money moved at the mailbox, trade window, auction house or guild bank is not counted." },
    { key = "xp", title = "Experience", unit = "XP/h",
      rate = function(t) return Number(Rate(t)) end,
      sub = function(t)
          local rate = Rate(t)
          if rate <= 0 then return "Level in --" end
          return "Level in " .. Short((UnitXPMax("player") - UnitXP("player")) / rate * 3600)
      end,
      total = function(t) return Number(t.total) .. " XP" end,
      note = "Time to level is the XP still needed at this session's rate." },
}

local function Shown(c)
    return not db.hidden[c.key] and not (c.key == "xp" and MaxLevel())
end

local function Refresh()
    local away, line = Away(), {}
    for _, c in ipairs(COUNTERS) do
        local t, p = db[c.key], panels[c.key]
        local rate = c.rate(t)
        p.rate:SetText(rate .. " |cffffd100" .. c.unit .. "|r")
        p.sub:SetText(c.sub(t))
        p.pause:SetText(t.paused and "Resume" or "Pause")
        p.pause.dot:SetVertexColor(unpack(t.paused and PAUSED or away and AFK or RUNNING))
        if Shown(c) then line[#line + 1] = rate .. " " .. c.unit end
    end
    if broker then broker.text = table.concat(line, "  ") end
end

local function Layout()
    local y = -TAB
    for _, c in ipairs(COUNTERS) do
        local p = panels[c.key]
        p:SetShown(Shown(c))
        if Shown(c) then
            p:ClearAllPoints()
            p:SetPoint("TOP", 0, y)
            y = y - HEIGHT - TAB - GAP
        end
    end
    holder:SetHeight(math.max(-y - GAP, TAB))
    wasMax = MaxLevel()
end

local function Reset(t)
    t.total, t.elapsed = 0, 0
end

local function Toggle()
    db.shown = not db.shown
    holder:SetShown(db.shown)
    if not db.shown then Print("Hidden; it keeps counting. Type /goldxp to show it again.") end
end

-- Counting ------------------------------------------------------------------

-- No open/closed flags to get stuck: ask the game whether a transfer window
-- is open right now, and treat money just around one opening or closing
-- (trade money can land after the window closes) as a transfer too.
local function InTransfer()
    if GetTime() < graceUntil then return true end
    local pim = C_PlayerInteractionManager
    if pim and pim.IsInteractingWithNpcOfType then
        for kind in pairs(TRANSFER_TYPES) do
            if pim.IsInteractingWithNpcOfType(kind) then return true end
        end
    end
    for _, name in ipairs(TRANSFER_FRAMES) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown and f:IsShown() then return true end
    end
    return false
end

local function OnMoney()
    local money = GetMoney()
    if not db.gold.paused and not InTransfer() then
        db.gold.total = db.gold.total + (money - lastMoney)
    end
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
    if not Away() then
        for _, c in ipairs(COUNTERS) do
            local t = db[c.key]
            if not t.paused then t.elapsed = t.elapsed + dt end
        end
    end
    if MaxLevel() ~= wasMax then Layout() end
    Refresh()
end

-- Window --------------------------------------------------------------------

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

local function CreatePanel(c)
    local p = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    p:SetSize(WIDTH, HEIGHT)
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
        GameTooltip:AddLine(c.note, 0.7, 0.7, 0.7, true)
        if Away() then GameTooltip:AddLine("You are AFK: time is not counted.", 1, 0.8, 0.2, true) end
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
    p.rate:SetPoint("TOP", 0, -16)
    p.sub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.sub:SetPoint("TOP", p.rate, "BOTTOM", 0, -4)

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
    holder:SetWidth(WIDTH)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    holder:SetScale(db.scale or 1)
    local pt = db.point or { "CENTER", "CENTER", 300, 0 }
    holder:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    for _, c in ipairs(COUNTERS) do CreatePanel(c) end

    local close = CreateFrame("Button", nil, holder, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", 1, -TAB + 1)
    close:SetFrameLevel(holder:GetFrameLevel() + 10)
    close:SetScript("OnClick", Toggle)

    Layout()
    holder:SetShown(db.shown)
end

local function CreateBroker()
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if not ldb then return end
    broker = ldb:NewDataObject("GoldXPPerHour", {
        type = "data source",
        label = "Gold and XP Per Hour",
        text = "",
        icon = "Interface\\Icons\\INV_Misc_Coin_01",
        OnClick = Toggle,
        OnTooltipShow = function(tt)
            tt:AddLine("Gold and XP Per Hour")
            for _, c in ipairs(COUNTERS) do
                if Shown(c) then tt:AddDoubleLine(c.title, c.rate(db[c.key]) .. " " .. c.unit, 1, 1, 1, 1, 1, 1) end
            end
            tt:AddLine("Click to show or hide the window.", 0.7, 0.7, 0.7)
        end,
    })
    icon = broker and LibStub("LibDBIcon-1.0", true)
    if icon then icon:Register("GoldXPPerHour", broker, db.minimap) end
end

-- Slash commands ------------------------------------------------------------

local function Slash(input)
    if not db then return end
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        Toggle()
    elseif cmd == "reset" then
        for _, c in ipairs(COUNTERS) do Reset(db[c.key]) end
        Refresh()
        Print("counters reset.")
    elseif cmd == "gold" or cmd == "xp" then
        db.hidden[cmd] = not db.hidden[cmd] or nil
        Layout()
        Refresh()
        if cmd == "xp" and MaxLevel() then Print("the XP counter hides itself at max level.") end
    elseif cmd == "scale" and tonumber(arg) then
        db.scale = math.min(math.max(tonumber(arg), 0.5), 2)
        holder:SetScale(db.scale)
    elseif cmd == "minimap" and icon then
        db.minimap.hide = not db.minimap.hide or nil
        if db.minimap.hide then icon:Hide("GoldXPPerHour") else icon:Show("GoldXPPerHour") end
    else
        Print("/goldxp: show or hide | gold, xp: show or hide a counter | scale 0.5-2 | minimap | reset")
    end
end

SLASH_GOLDXPPERHOUR1 = "/goldxp"
SlashCmdList.GOLDXPPERHOUR = Slash

-- /perhour and /ph are also used by other per-hour addons; whichever loads
-- last would take them over. Claim each only if no other addon has.
local function SlashTaken(cmd)
    if type(hash_SlashCmdList) == "table" and hash_SlashCmdList[cmd:upper()] then return true end
    for key in pairs(SlashCmdList) do
        if key ~= "GOLDXPPERHOUR" and key ~= "GOLDXPPERHOURALIAS" then
            local i, name = 1, _G["SLASH_" .. key .. "1"]
            while type(name) == "string" do
                if name:lower() == cmd then return true end
                i = i + 1
                name = _G["SLASH_" .. key .. i]
            end
        end
    end
    return false
end

local function ClaimAliases()
    local n, taken = 0, {}
    for _, cmd in ipairs({ "/perhour", "/ph" }) do
        if SlashTaken(cmd) then
            taken[#taken + 1] = cmd
        else
            n = n + 1
            _G["SLASH_GOLDXPPERHOURALIAS" .. n] = cmd
        end
    end
    if n > 0 then SlashCmdList.GOLDXPPERHOURALIAS = Slash end
    if #taken > 0 then
        Print(table.concat(taken, " and ") .. (#taken == 1 and " is" or " are") .. " used by another addon here; type /goldxp instead.")
    end
end

-- Start ---------------------------------------------------------------------

local events = CreateFrame("Frame")

local function Start()
    PerHourDB = PerHourDB or {}
    db = PerHourDB
    for _, c in ipairs(COUNTERS) do
        db[c.key] = db[c.key] or { total = 0, elapsed = 0 }
    end
    if db.shown == nil then db.shown = true end
    db.hidden = db.hidden or {}
    db.minimap = db.minimap or {}

    lastMoney = GetMoney()
    lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
    lastTick = GetTime()
    CreateWindow()
    CreateBroker()
    Refresh()
    C_Timer.After(3, ClaimAliases) -- after other addons' own login setup
    C_Timer.NewTicker(1, Tick)
    events:RegisterEvent("PLAYER_MONEY")
    events:RegisterEvent("PLAYER_XP_UPDATE")
    -- Unknown event names are a hard error; a client without one just
    -- loses that signal.
    for _, e in ipairs(TRANSFER_EVENTS) do pcall(events.RegisterEvent, events, e) end
    pcall(events.RegisterEvent, events, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    pcall(events.RegisterEvent, events, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
end

events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, kind)
    if event == "PLAYER_MONEY" then
        OnMoney()
    elseif event == "PLAYER_XP_UPDATE" then
        OnXP()
    elseif event == "PLAYER_LOGIN" then
        Start()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if TRANSFER_TYPES[kind] then graceUntil = GetTime() + GRACE end
    else -- a legacy transfer window opened or closed
        graceUntil = GetTime() + GRACE
    end
end)
