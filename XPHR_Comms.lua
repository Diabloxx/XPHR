-- XPHR_Comms.lua - Party communications for XPHR (MoP Classic 5.5)

XPHR = XPHR or {}
XPHR.Comms = XPHR.Comms or {}
local Comms = XPHR.Comms

local Now = GetTime

-- API shims
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or rawget(_G, "RegisterAddonMessagePrefix") or function() end
local SendAM = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or rawget(_G, "SendAddonMessage") or function() end

local PREFIX = "XPHR"
local VERSION = 1

local function FullName(unit)
    local n, r = UnitFullName(unit)
    if not n then return nil end
    if r and r ~= "" then return n.."-"..r end
    local realm = GetRealmName() or ""
    realm = realm:gsub("%s+", "")
    if realm ~= "" then return n.."-"..realm end
    return n
end

local function IsMyself(name)
    local me = FullName("player")
    return me and name and me:lower() == name:lower()
end

local function IsInMyGroupByName(name)
    if not name then return false end
    if UnitInParty(name) then return true end
    if UnitInRaid and UnitInRaid(name) then return true end
    if not IsInRaid() then
        for i=1,4 do
            local u = "party"..i
            if UnitExists(u) and FullName(u) == name then return true end
        end
    end
    return false
end

local function InPartyCanSend()
    if IsInRaid() then return false end
    if IsInGroup then
        return IsInGroup(LE_PARTY_CATEGORY_HOME) and not IsInRaid(LE_PARTY_CATEGORY_HOME)
    end
    return (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) > 0
end

-- Serialization
local function BuildPayload()
    local s = XPHR.state or {}
    local name = FullName("player") or UnitName("player")
    local level = UnitLevel("player") or 0
    local sessionXP = s.sessionXP or 0
    local rollingXP = 0 -- we keep only rate; include 0 for future compatibility
    local rxph = math.floor((s.xpPerHour_rolling or 0) + 0.5)
    local sxph = math.floor((s.xpPerHour_session or 0) + 0.5)
    local ttl  = math.floor((s.ttl ~= math.huge and s.ttl or 0) + 0.5)
    return string.format("v=%d|n=%s|l=%d|sx=%d|sr=%d|rxph=%d|sxph=%d|ttl=%d", VERSION, name, level, sessionXP, rollingXP, rxph, sxph, ttl)
end

local function ParsePayload(msg)
    local t = {}
    for k,v in string.gmatch(msg or "", "([^|=]+)=([^|]*)") do
        t[k] = v
    end
    t.v = tonumber(t.v or "")
    t.l = tonumber(t.l or "")
    t.sx = tonumber(t.sx or "")
    t.sr = tonumber(t.sr or "")
    t.rxph = tonumber(t.rxph or "")
    t.sxph = tonumber(t.sxph or "")
    t.ttl = tonumber(t.ttl or "")
    return t
end

local function OnAddonMsg(prefix, msg, channel, sender)
    if prefix ~= PREFIX or not msg or not sender then return end
    if IsMyself(sender) then return end
    if not IsInMyGroupByName(sender) then return end
    local d = ParsePayload(msg)
    if not d or (d.v and d.v > VERSION + 1) then return end

    local name = d.n or sender
    XPHR.party[name] = XPHR.party[name] or {}
    local m = XPHR.party[name]
    m.name = name
    m.level = d.l or m.level
    m.sessionXP = d.sx or m.sessionXP or 0
    m.rollingXP = d.sr or m.rollingXP or 0
    m.xpPerHour_session = d.sxph or m.xpPerHour_session or 0
    m.xpPerHour_rolling = d.rxph or m.xpPerHour_rolling or 0
    m.ttl = d.ttl or m.ttl or 0
    m.lastSeen = Now()

    if XPHR.UI and XPHR.UI.RequestRefresh then XPHR.UI.RequestRefresh() end
end

Comms._lastSend = 0
Comms._lastGain = 0

function Comms.NotifyXPGain()
    Comms._lastGain = Now()
end

function Comms.BuildPayload()
    return BuildPayload()
end

function Comms.Send(payload)
    if not payload or not InPartyCanSend() then return end
    SendAM(PREFIX, payload, "PARTY")
end

function Comms.MaybeSend(reason)
    if not InPartyCanSend() then return end
    local now = Now()
    local minInterval = (reason == "xp" or (now - Comms._lastGain) <= 0.6) and 0.5 or 5.0
    if (now - (Comms._lastSend or 0)) < minInterval then return end
    Comms.Send(BuildPayload())
    Comms._lastSend = now
end

function Comms.Cleanup()
    local now = Now()
    for name, m in pairs(XPHR.party) do
        if IsMyself(name) then
            -- Never evict the local player row
        else
            local tooOld = not m.lastSeen or (now - m.lastSeen) > 15
            local notIn = not (name and (UnitInParty(name) or (UnitInRaid and UnitInRaid(name))))
            if tooOld or notIn then
                XPHR.party[name] = nil
            end
        end
    end
end

local frame
function Comms.Initialize()
    RegisterPrefix(PREFIX)
    if not frame then
        frame = CreateFrame("Frame")
        frame:RegisterEvent("CHAT_MSG_ADDON")
        frame:SetScript("OnEvent", function(_, event, ...)
            if event == "CHAT_MSG_ADDON" then
                local p, msg, channel, sender = ...
                OnAddonMsg(p, msg, channel, sender)
            end
        end)
    end
end

-- Initialize on file load for simplicity
Comms.Initialize()