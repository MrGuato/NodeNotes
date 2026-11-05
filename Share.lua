-- Sharing nodes with your friends. Off until you turn it on.
--
-- With /nn share group (or guild, or both), every node you record or write a
-- note on is sent to that channel as a hidden addon message: one at a time,
-- about one a second, and never in combat. Friends running NodeNotes keep
-- what they receive apart from their own nodes, show it with a blue corner,
-- and never mix it into their own history. Everything received is checked
-- and cleaned before it is stored or shown.

local _, ns = ...

local Share = {}
ns.Share = Share

local PREFIX = "NodeNotes"
local VERSION = "1"
local SEND_INTERVAL = 1.2     -- seconds between messages, per channel
local MAX_QUEUE = 200
local MAX_FRIEND_NODES = 3000
local MAX_BYTES = 250         -- addon messages stop at 255
local NAME_MAX, LOOT_MAX, NOTE_MAX = 48, 80, 240

local KINDS = { herb = true, ore = true, fish = true, chest = true, rare = true, find = true }
local MODES = { off = true, group = true, guild = true, both = true }
local CHANNELS = { PARTY = true, RAID = true, GUILD = true }

local queue, queued = {}, {}  -- nodes waiting to be sent, oldest first
local driver
local wait = 0
local available = false

local function secret(v)
    return ns.Secret(v)
end

-- One line of plain text: no control characters, no escape codes (a pipe
-- starts a link or a texture in game text), at most limit bytes.
local function clean(text, limit)
    text = tostring(text or ""):gsub("%c", " "):gsub("|", "/")
    text = text:match("^%s*(.-)%s*$")
    if #text > limit then
        -- Cut, then drop a character left half finished.
        text = text:sub(1, limit):gsub("[\192-\255][\128-\191]*$", "")
    end
    return text
end
Share.Clean = clean

local function int(s, lo, hi)
    local n = tonumber(s)
    if not n or n ~= math.floor(n) or n < lo or n > hi then
        return nil
    end
    return n
end

function Share.Encode(mapID, node, now)
    now = now or time()
    local when = node.last or node.seen or now
    local loot = node.loot and #node.loot > 0 and ns.LootText(node.loot, 3) or ""
    local fields = {
        VERSION, mapID,
        math.floor(node.x * 10000 + 0.5), math.floor(node.y * 10000 + 0.5),
        node.kind, node.count or 0, math.max(0, now - when),
        tonumber(node.icon) or 0, node.npc or 0, node.best or 0,
        clean(node.name, NAME_MAX), clean(loot, LOOT_MAX),
    }
    local msg = table.concat(fields, "\t") .. "\t"
    local room = MAX_BYTES - #msg
    if room > 0 and node.note and node.note ~= "" then
        msg = msg .. clean(node.note, math.min(room, NOTE_MAX))
    end
    return msg
end

-- A received message as a plain table, or nil when anything about it is off.
function Share.Decode(msg)
    if type(msg) ~= "string" or #msg > 255 then
        return nil
    end
    local f = {}
    for part in (msg .. "\t"):gmatch("([^\t]*)\t") do
        f[#f + 1] = part
    end
    if f[1] ~= VERSION or #f ~= 13 then
        return nil
    end
    local r = {
        mapID = int(f[2], 1, 1000000),
        x = int(f[3], 0, 10000), y = int(f[4], 0, 10000),
        kind = KINDS[f[5]] and f[5] or nil,
        count = int(f[6], 0, 1000000), ago = int(f[7], 0, 100000000),
        icon = int(f[8], 0, 100000000), npc = int(f[9], 0, 10000000), best = int(f[10], 0, 8),
    }
    for _, key in ipairs({ "mapID", "x", "y", "kind", "count", "ago", "icon", "npc", "best" }) do
        if r[key] == nil then
            return nil
        end
    end
    if r.kind == "rare" and r.npc == 0 then
        return nil
    end
    r.x, r.y = r.x / 10000, r.y / 10000
    r.icon = r.icon > 0 and r.icon or nil
    r.npc = r.npc > 0 and r.npc or nil
    r.best = r.best > 0 and r.best or nil
    r.name = clean(f[11], NAME_MAX)
    if r.name == "" then
        r.name = ns.KIND_LABEL[r.kind]
    end
    r.lootText = clean(f[12], LOOT_MAX)
    r.note = clean(f[13], NOTE_MAX)
    return r
end

local function friendCount()
    local n = 0
    for _, list in pairs(ns.FriendNodes()) do
        n = n + #list
    end
    return n
end

-- Keep a friend's node. Returns it, or nil when there is no room left.
function Share.Store(r, from, now)
    now = now or time()
    local friends = ns.FriendNodes()
    local list = friends[r.mapID]
    local node = list and ns.FindMatch(list, r.kind, r.x, r.y, r.npc)
    if not node then
        if friendCount() >= MAX_FRIEND_NODES then
            return nil
        end
        if not list then
            list = {}
            friends[r.mapID] = list
        end
        node = { kind = r.kind }
        list[#list + 1] = node
    end
    node.x, node.y, node.npc = r.x, r.y, r.npc
    node.name, node.count, node.icon, node.best = r.name, r.count, r.icon, r.best
    node.lootText, node.note, node.from = r.lootText, r.note, from
    node.last = now - r.ago
    ns.Changed()
    return node
end

function Share.Describe(node, mapID)
    local lines = {}
    lines[#lines + 1] = ("%s  %.1f, %.1f"):format(ns.MapName(mapID), node.x * 100, node.y * 100)
    lines[#lines + 1] = ("%s, %d visit%s, last %s"):format(ns.KIND_LABEL[node.kind] or node.kind,
        node.count or 0, node.count == 1 and "" or "s", ns.Ago(node.last))
    if node.lootText and node.lootText ~= "" then
        lines[#lines + 1] = "Last yield: " .. node.lootText
    end
    return lines
end

local function targets(mode)
    local home = rawget(_G, "LE_PARTY_CATEGORY_HOME")
    local out = {}
    if mode == "group" or mode == "both" then
        if IsInRaid(home) then
            out[#out + 1] = "RAID"
        elseif IsInGroup(home) then
            out[#out + 1] = "PARTY"
        end
    end
    if (mode == "guild" or mode == "both") and IsInGuild() then
        out[#out + 1] = "GUILD"
    end
    return out
end

function Share.Queue(mapID, node)
    local settings = ns.Settings()
    if not available or not settings or settings.share == "off" or queued[node] or #queue >= MAX_QUEUE then
        return false
    end
    queued[node] = true
    queue[#queue + 1] = { mapID = mapID, node = node }
    return true
end

local function sendNext()
    if #queue == 0 or InCombatLockdown() then
        return 0
    end
    local channels = targets(ns.Settings().share)
    if #channels == 0 then
        -- Nobody to send to. Do not keep old news for later.
        queue, queued = {}, {}
        return 0
    end
    local item = table.remove(queue, 1)
    queued[item.node] = nil
    local msg = Share.Encode(item.mapID, item.node)
    for i = 1, #channels do
        local ok, err = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channels[i])
        if not ok then
            ns.Log("send failed on %s: %s", channels[i], tostring(err))
        end
    end
    return #channels
end

local function receive(prefix, text, channel, sender)
    if prefix ~= PREFIX or secret(text) or secret(sender) or not CHANNELS[channel] then
        return
    end
    local settings = ns.Settings()
    if not settings or not settings.friends or type(sender) ~= "string" then
        return
    end
    local ambiguate = rawget(_G, "Ambiguate")
    local who = type(ambiguate) == "function" and ambiguate(sender, "none") or sender
    if who == UnitName("player") then
        return
    end
    local r = Share.Decode(text)
    if not r then
        ns.Log("ignored a malformed message from %s", clean(who, NAME_MAX))
        return
    end
    Share.Store(r, clean(who, NAME_MAX))
end

local function sync()
    local mapID = ns.PlayerPosition()
    local list = ns.NodesForMap(mapID)
    local n = 0
    for i = 1, #list do
        if Share.Queue(mapID, list[i]) then
            n = n + 1
        end
    end
    return n, mapID
end

function Share.Command(cmd, arg)
    local settings = ns.Settings()
    local say = ns.Say
    if cmd == "friends" then
        if arg == "on" or arg == "off" then
            settings.friends = (arg == "on")
            say("friends' nodes " .. arg)
            ns.Changed()
        elseif arg == "clear" then
            local db = ns.DB()
            local n = friendCount()
            db.friends = {}
            say(("removed %d node(s) your friends shared."):format(n))
            ns.Changed()
        else
            say(("friends' nodes are %s, %d on record. Use on, off or clear."):format(
                settings.friends and "on" or "off", friendCount()))
        end
        return
    end
    if not available then
        say("sharing is not available on this game client.")
        return
    end
    if MODES[arg] then
        settings.share = arg
        if arg == "off" then
            queue, queued = {}, {}
            say("sharing off. Nothing is sent.")
        else
            say(("sharing with your %s. New nodes and notes are sent as you record them. /nn share sync sends this zone.")
                :format(arg == "both" and "group and guild" or arg))
        end
    elseif arg == "sync" then
        if settings.share == "off" then
            say("sharing is off. Turn it on first with /nn share group, guild or both.")
            return
        end
        local n, mapID = sync()
        say(("sending %d node(s) from %s."):format(n, ns.MapName(mapID)))
    else
        local where = settings.share == "both" and "group and guild" or settings.share
        say(("sharing is %s. Use /nn share off, group, guild or both, and /nn share sync."):format(
            settings.share == "off" and "off" or ("on, with your " .. where)))
    end
end

function Share.Pending()
    return #queue
end

function Share.Init()
    if driver then
        return
    end
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" or type(chat.SendAddonMessage) ~= "function" then
        return   -- this client has no addon messages; sharing stays unavailable
    end
    available = true
    if chat.RegisterAddonMessagePrefix then
        pcall(chat.RegisterAddonMessagePrefix, PREFIX)
    end
    driver = CreateFrame("Frame")
    driver:RegisterEvent("CHAT_MSG_ADDON")
    driver:SetScript("OnEvent", function(_, _, ...)
        receive(...)
    end)
    driver:SetScript("OnUpdate", function(_, dt)
        wait = wait - dt
        if wait <= 0 then
            local sent = sendNext()
            wait = sent > 0 and SEND_INTERVAL * sent or 0.5
        end
    end)
end
