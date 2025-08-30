-- XPHR_UI.lua - Minimalist UI for XPHR (MoP Classic 5.5)

XPHR = XPHR or {}
XPHR.UI = XPHR.UI or {}
local UI = XPHR.UI

local ROW_HEIGHT = 18
local HEADER_HEIGHT = 22           -- title row
local COLS_HEIGHT = 16             -- column headers row
local WIDTH = 350
local MAX_ROWS = 6

-- Column x positions (relative to frame's left inside padding)
local PAD_LEFT = 6
local NAME_X = PAD_LEFT + 4        -- Name column start
local LEVEL_X = 170                -- Lvl
local RATE_X  = 210                -- XP/hr
local TTL_X   = 260                -- TTL
local SESS_X  = 300                -- Sess

local function CreateBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0,0,0,0.8)
end

local function ClassColorByName(name)
    -- Attempt to resolve via party cache
    for unit in pairs({player=true, party1=true, party2=true, party3=true, party4=true}) do
        if UnitExists(unit) and XPHR.FullName(unit) == name then
            local class = select(2, UnitClass(unit))
            local rcc = rawget(_G, "RAID_CLASS_COLORS")
            if class and rcc and rcc[class] then return rcc[class] end
        end
    end
    return { r=1, g=1, b=1 }
end

local function SortMembers(mode)
    local t = {}
    local me = XPHR.FullName("player")
    local s = XPHR.state
    local foundSelf = false
    for name, m in pairs(XPHR.party) do
        if name == me then
            foundSelf = true
            m = {
                name = name,
                level = UnitLevel("player"),
                sessionXP = s.sessionXP or 0,
                xpPerHour_session = s.xpPerHour_session or 0,
                xpPerHour_rolling = s.xpPerHour_rolling or 0,
                ttl = s.ttl or 0,
                _self = true,
            }
        end
        table.insert(t, m)
    end
    if not foundSelf and me then
        table.insert(t, 1, {
            name = me,
            level = UnitLevel("player"),
            sessionXP = s.sessionXP or 0,
            xpPerHour_session = s.xpPerHour_session or 0,
            xpPerHour_rolling = s.xpPerHour_rolling or 0,
            ttl = s.ttl or 0,
            _self = true,
        })
    end
    table.sort(t, function(a,b)
        local ra = (mode == "rolling") and (a.xpPerHour_rolling or 0) or (a.xpPerHour_session or 0)
        local rb = (mode == "rolling") and (b.xpPerHour_rolling or 0) or (b.xpPerHour_session or 0)
        if (a._self and not b._self) then return true end
        if (b._self and not a._self) then return false end
        return ra > rb
    end)
    return t
end

local function MakeText(parent, size, outline)
    local fs = parent:CreateFontString(nil, "OVERLAY", outline and "GameFontHighlightSmallOutline" or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    local font,_,flags = fs:GetFont()
    fs:SetFont(font, size or 12, flags)
    return fs
end

local function Row_Set(m, row, mode)
    local name = m.name or "?"
    local level = m.level or 0
    local rate = (mode == "rolling") and (m.xpPerHour_rolling or 0) or (m.xpPerHour_session or 0)
    local ttl = m.ttl or 0
    local col = ClassColorByName(name)
    row.name:SetText(name)
    row.name:SetTextColor(col.r, col.g, col.b)
    if m._self then row.name:SetFontObject("GameFontNormal") else row.name:SetFontObject("GameFontHighlight") end
    row.level:SetText(level)
    row.rate:SetText(XPHR.FormatRate(rate))
    row.ttl:SetText(XPHR.SecondsToClock(ttl))
    row.session:SetText(XPHR.Comma(m.sessionXP or 0))
end

local frame, header, toggleBtn, closeBtn
local rows = {}

function UI.CreateMainFrame()
    if frame then return end
    frame = CreateFrame("Frame", "XPHR_MainFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(WIDTH, HEADER_HEIGHT + COLS_HEIGHT + ROW_HEIGHT * MAX_ROWS + 14)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self)
        if not XPHR.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        XPHR.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    CreateBackdrop(frame)

    -- Title/header
    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -6, -6)
    header:SetHeight(HEADER_HEIGHT)

    header.title = MakeText(header, 13, true)
    header.title:SetPoint("LEFT")
    header.title:SetText("XPHR — XP/hour")
    header.title:EnableMouse(true)
    header.title:SetScript("OnEnter", function()
        GameTooltip:SetOwner(header.title, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("XPHR", 1, 1, 1)
        GameTooltip:AddLine("Session: total XP gained / session hours", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("10m Rolling: XP in last 10 minutes / (10/60)h", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    header.title:SetScript("OnLeave", function() GameTooltip:Hide() end)

    toggleBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    toggleBtn:SetSize(64, HEADER_HEIGHT-4)
    toggleBtn:SetPoint("RIGHT", -26, 0)
    toggleBtn:SetScript("OnClick", function()
        local m = XPHR.db.mode == "session" and "rolling" or "session"
        UI.SetMode(m)
    end)

    closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function()
        UI.SetShown(false)
    end)

    -- Column header row (separate line for alignment)
    local cols = CreateFrame("Frame", nil, frame)
    cols:SetPoint("TOPLEFT", 6, -6 - HEADER_HEIGHT)
    cols:SetPoint("TOPRIGHT", -6, -6 - HEADER_HEIGHT)
    cols:SetHeight(COLS_HEIGHT)

    local hname = MakeText(cols, 11, true); hname:SetPoint("LEFT", cols, "LEFT", NAME_X, 0); hname:SetText("Name")
    local hlev  = MakeText(cols, 11, true); hlev:SetPoint("LEFT", cols, "LEFT", LEVEL_X, 0); hlev:SetText("Lvl")
    local hr    = MakeText(cols, 11, true);   hr:SetPoint("LEFT", cols, "LEFT", RATE_X, 0);  hr:SetText("XP/hr")
    local httl  = MakeText(cols, 11, true); httl:SetPoint("LEFT", cols, "LEFT", TTL_X, 0);   httl:SetText("TTL")
    local hs    = MakeText(cols, 11, true);   hs:SetPoint("LEFT", cols, "LEFT", SESS_X, 0);  hs:SetText("Sess")

    -- Rows
    for i=1,MAX_ROWS do
        local r = CreateFrame("Frame", nil, frame)
        r:SetSize(WIDTH-12, ROW_HEIGHT)
    r:SetPoint("TOPLEFT", 6, -HEADER_HEIGHT - COLS_HEIGHT - 8 - (i-1)*ROW_HEIGHT)
    r.name = MakeText(r, 12);   r.name:SetPoint("LEFT", r, "LEFT", NAME_X, 0)
    r.level = MakeText(r, 12);  r.level:SetPoint("LEFT", r, "LEFT", LEVEL_X, 0)
    r.rate  = MakeText(r, 12);  r.rate:SetPoint("LEFT", r, "LEFT", RATE_X, 0)
    r.ttl   = MakeText(r, 12);  r.ttl:SetPoint("LEFT", r, "LEFT", TTL_X, 0)
    r.session = MakeText(r, 11); r.session:SetPoint("LEFT", r, "LEFT", SESS_X, 0)
        rows[i] = r
    end

    -- Right-click menu
    frame:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" then
            local menu = {
                { text = "XPHR", isTitle = true, notCheckable = true },
                { text = "Reset Session", notCheckable = true, func = function() XPHR.ResetSession() end },
                { text = (XPHR.db.mode == "session" and "Switch to 10m Rolling" or "Switch to Session"), notCheckable = true, func = function() UI.SetMode(XPHR.db.mode == "session" and "rolling" or "session") end },
                { text = (XPHR.db.locked and "Unlock" or "Lock"), notCheckable = true, func = function() UI.SetLocked(not XPHR.db.locked) end },
                { text = (XPHR.db.show and "Hide" or "Show"), notCheckable = true, func = function() UI.SetShown(not XPHR.db.show) end },
            }
            local easy = rawget(_G, "EasyMenu")
            if easy then
                easy(menu, CreateFrame("Frame", "XPHR_Dropdown", UIParent, "UIDropDownMenuTemplate"), "cursor", 0 , 0, "MENU")
            end
        end
    end)

    UI.SetMode(XPHR.db.mode)
    UI.SetLocked(XPHR.db.locked)
    UI.SetShown(XPHR.db.show)
end

function UI.ApplyPosition(pos)
    if not frame then return end
    frame:ClearAllPoints()
    local p = pos or XPHR.db.pos
    local point = p and p.point or "CENTER"
    local relPoint = p and p.relPoint or "CENTER"
    frame:SetPoint(point, UIParent, relPoint, p and p.x or 0, p and p.y or 0)
end

function UI.SetMode(mode)
    XPHR.db.mode = (mode == "rolling") and "rolling" or "session"
    if toggleBtn then toggleBtn:SetText(XPHR.db.mode == "rolling" and "10m" or "Session") end
    UI.Refresh()
end

function UI.SetLocked(locked)
    XPHR.db.locked = not not locked
end

function UI.SetShown(show)
    XPHR.db.show = not not show
    if frame then frame:SetShown(XPHR.db.show) end
end

function UI.RequestRefresh()
    UI.Refresh()
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    local list = SortMembers(XPHR.db.mode)
    for i=1,MAX_ROWS do
        local r = rows[i]
        local m = list[i]
        if m then
            Row_Set(m, r, XPHR.db.mode)
            r:Show()
        else
            r:Hide()
        end
    end
end
