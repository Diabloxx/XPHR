-- XPHR.lua - Core logic for XPHR (MoP Classic 5.5)
-- Tracks XP/hour for the player and coordinates UI and comms.

local addonName = ...

XPHR = XPHR or {}
XPHR.db = XPHR.db or {}
XPHR.state = XPHR.state or {}
XPHR.party = XPHR.party or {}

local UI
local Comms

local function Now()
    return GetTime()
end

-- Defaults
local defaults = {
    version = 1,
    show = true,
    mode = "session", -- or "rolling"
    locked = false,
    pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    lastSessionStart = 0,
}

local function deepcopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local t = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then t[k] = deepcopy(v) else t[k] = v end
    end
    return t
end

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = dst[k] or {}
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Formatting helpers
local function Comma(n)
    local s = tostring(math.floor(n or 0))
    local left, num, right = string.match(s, '^([^%d]*%d)(%d*)(.-)$')
    return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

local function FormatRate(v)
    v = v or 0
    if v >= 1000000 then
        return string.format("%.1fm", v/1e6)
    elseif v >= 1000 then
        return string.format("%.1fk", v/1e3)
    else
        return tostring(math.floor(v + 0.5))
    end
end

local function SecondsToClock(sec)
    if not sec or sec <= 0 or sec == math.huge then return "--:--" end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then
        return string.format("%dh %dm", h, m)
    else
        return string.format("%dm", m)
    end
end

-- State
local state = XPHR.state
state.samples = state.samples or {} -- queue of {t, dx}
state.sessionStart = state.sessionStart or 0
state.sessionXP = state.sessionXP or 0
state.lastXP = state.lastXP or 0
state.lastXPMax = state.lastXPMax or 0
state.lastLevel = state.lastLevel or 0
state.lastUpdate = state.lastUpdate or 0
state.ttl = state.ttl or 0
state.xpPerHour_session = state.xpPerHour_session or 0
state.xpPerHour_rolling = state.xpPerHour_rolling or 0

-- Party helpers
local function IteratePartyUnits()
    local units = {"player"}
    for i = 1, 4 do units[#units+1] = "party"..i end
    return units
end

local function FullName(unit)
    local n, r = UnitFullName(unit)
    if not n then return nil end
    if r and r ~= "" then return n.."-"..r end
    local realm = GetRealmName() or ""
    realm = realm:gsub("%s+", "")
    if realm ~= "" then return n.."-"..realm end
    return n
end

local function RebuildParty()
    local party = XPHR.party
    -- Keep self
    local me = FullName("player")
    for name, _ in pairs(party) do
        party[name]._seen = false
    end
    for _, u in ipairs(IteratePartyUnits()) do
        if UnitExists(u) then
            local name = FullName(u)
            if name then
                party[name] = party[name] or {}
                local m = party[name]
                m.name = name
                m.guid = UnitGUID(u)
                m.level = UnitLevel(u)
                m._seen = true
                if name == me then
                    -- map local state into party row for rendering
                    m.xpPerHour_session = state.xpPerHour_session or 0
                    m.xpPerHour_rolling = state.xpPerHour_rolling or 0
                    m.ttl = state.ttl or 0
                    m.sessionXP = state.sessionXP or 0
                end
            end
        end
    end
    for name, m in pairs(party) do
        if not m._seen and name ~= me then
            party[name] = nil
        end
    end
    if XPHR.UI and XPHR.UI.RequestRefresh then XPHR.UI.RequestRefresh() end
end

-- Rolling samples
local function PushSample(dx)
    if dx <= 0 then return end
    local t = Now()
    table.insert(state.samples, {t = t, dx = dx})
    -- Drop old samples > 600s
    local cutoff = t - 600
    local sum = 0
    local i = 1
    while i <= #state.samples do
        if state.samples[i].t < cutoff then
            table.remove(state.samples, i)
        else
            sum = sum + state.samples[i].dx
            i = i + 1
        end
    end
    local window = math.max(1, math.min(600, t - (state.samples[1] and state.samples[1].t or t)))
    state.xpPerHour_rolling = (sum / window) * 3600
end

local function RecomputeTTL()
    local rate = (XPHR.db.mode == "rolling") and state.xpPerHour_rolling or state.xpPerHour_session
    if rate and rate > 0 then
        local xp = UnitXP("player") or 0
        local xpMax = UnitXPMax("player") or 1
        local toLevel = math.max(0, xpMax - xp)
        state.ttl = (toLevel / rate) * 3600
    else
        state.ttl = math.huge
    end
end

local function UpdateFromPlayerXP(event)
    local now = Now()
    local xp = UnitXP("player") or 0
    local xpMax = UnitXPMax("player") or 1
    local level = UnitLevel("player") or 0

    if state.lastUpdate == 0 then
        state.lastXP = xp
        state.lastXPMax = xpMax
        state.lastLevel = level
        state.lastUpdate = now
        return
    end

    local dx = xp - state.lastXP
    if level > state.lastLevel then
        -- wrap-around: gained (lastXPMax - lastXP) + xp
        dx = (state.lastXPMax - state.lastXP) + xp
    elseif dx < 0 then
        -- rare, but handle decrease as wrap (e.g., rested/bugs); treat as zero
        dx = 0
    end

    if dx > 0 then
        state.sessionXP = (state.sessionXP or 0) + dx
        PushSample(dx)
        if XPHR.Comms and XPHR.Comms.NotifyXPGain then XPHR.Comms.NotifyXPGain() end
    end

    -- Update session rate
    local elapsed = math.max(1, (now - (state.sessionStart or now)))
    state.xpPerHour_session = (state.sessionXP or 0) / elapsed * 3600

    state.lastXP = xp
    state.lastXPMax = xpMax
    state.lastLevel = level
    state.lastUpdate = now

    RecomputeTTL()

    if XPHR.UI and XPHR.UI.RequestRefresh then XPHR.UI.RequestRefresh() end
    if XPHR.Comms and XPHR.Comms.MaybeSend then XPHR.Comms.MaybeSend("xp") end
end

local function ResetSession()
    state.sessionStart = Now()
    state.sessionXP = 0
    state.samples = {}
    state.xpPerHour_session = 0
    state.xpPerHour_rolling = 0
    state.ttl = math.huge
    -- Re-establish baseline so the next XP gain counts
    state.lastXP = UnitXP("player") or 0
    state.lastXPMax = UnitXPMax("player") or 1
    state.lastLevel = UnitLevel("player") or 0
    state.lastUpdate = Now()
    RecomputeTTL()
    if XPHR.UI and XPHR.UI.RequestRefresh then XPHR.UI.RequestRefresh() end
end

-- Slash commands
SLASH_XPHR1 = "/xphr"
SlashCmdList["XPHR"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "reset" then
        ResetSession()
        print("XPHR: session reset.")
    elseif msg:match("^mode") then
        local m = msg:match("mode%s+(%a+)")
        if m == "session" or m == "rolling" then
            XPHR.db.mode = m
            RecomputeTTL()
            if XPHR.UI and XPHR.UI.SetMode then XPHR.UI.SetMode(m) end
        else
            print("XPHR: mode session|rolling")
        end
    elseif msg == "lock" then
        XPHR.db.locked = true
        if XPHR.UI and XPHR.UI.SetLocked then XPHR.UI.SetLocked(true) end
    elseif msg == "unlock" then
        XPHR.db.locked = false
        if XPHR.UI and XPHR.UI.SetLocked then XPHR.UI.SetLocked(false) end
    else
        -- toggle
        XPHR.db.show = not XPHR.db.show
        if XPHR.UI and XPHR.UI.SetShown then XPHR.UI.SetShown(XPHR.db.show) end
    end
end

-- Event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            XPHRDB = XPHRDB or {}
            XPHR.db = XPHRDB
            applyDefaults(XPHR.db, defaults)

            -- Initialize session
            if not state.sessionStart or state.sessionStart == 0 then
                state.sessionStart = Now()
            end
            -- Establish XP baseline immediately so the first XP gain isn't swallowed
            state.lastXP = UnitXP("player") or 0
            state.lastXPMax = UnitXPMax("player") or 1
            state.lastLevel = UnitLevel("player") or 0
            state.lastUpdate = Now()

            -- Create UI
            if XPHR.UI and XPHR.UI.CreateMainFrame then
                XPHR.UI.CreateMainFrame()
                if XPHR.db.pos and XPHR.UI.ApplyPosition then XPHR.UI.ApplyPosition(XPHR.db.pos) end
                if XPHR.UI.SetMode then XPHR.UI.SetMode(XPHR.db.mode) end
                if XPHR.UI.SetLocked then XPHR.UI.SetLocked(XPHR.db.locked) end
                if XPHR.UI.SetShown then XPHR.UI.SetShown(XPHR.db.show) end
            end

            -- Init comms
            if XPHR.Comms and XPHR.Comms.Initialize then XPHR.Comms.Initialize() end
            -- Seed party with self immediately (works solo too)
            RebuildParty()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        RebuildParty()
        UpdateFromPlayerXP(event)
    elseif event == "PLAYER_XP_UPDATE" then
        UpdateFromPlayerXP(event)
    elseif event == "PLAYER_LEVEL_UP" then
        -- ensure wrap handling
        UpdateFromPlayerXP(event)
    elseif event == "GROUP_ROSTER_UPDATE" then
        RebuildParty()
        if XPHR.Comms and XPHR.Comms.Cleanup then XPHR.Comms.Cleanup() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- no-op, keep tidy
    end
end)

-- Lightweight UI refresh ticker (0.5s)
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 0.5 then
        acc = 0
        RecomputeTTL()
        if XPHR.UI and XPHR.UI.Refresh then XPHR.UI.Refresh() end
        if XPHR.Comms and XPHR.Comms.MaybeSend then XPHR.Comms.MaybeSend() end
        if XPHR.Comms and XPHR.Comms.Cleanup then XPHR.Comms.Cleanup() end
    end
end)

-- Expose helpers for UI
XPHR.FormatRate = FormatRate
XPHR.Comma = Comma
XPHR.SecondsToClock = SecondsToClock
XPHR.FullName = FullName
XPHR.RebuildParty = RebuildParty
XPHR.ResetSession = ResetSession
