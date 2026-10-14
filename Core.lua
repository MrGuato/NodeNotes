-- NodeNotes: a personal record of the gathering nodes you have used.
--
-- It records a node when you finish a herb or mining cast and the loot
-- window opens, or when you land a catch while fishing: where you stood, what
-- it gave you, and when. Nothing is shared with other players and nothing is
-- automated. Every record comes from something you did yourself.

local ADDON, ns = ...

-- Two gathers of the same kind closer than this (in map coordinates, where a
-- whole zone is 1.0 wide) count as the same node. Herbs and veins stand still,
-- so about 10 to 15 yards. A fishing spot is wherever you stood on the shore,
-- so it gets more room.
local MERGE_RADIUS = { herb = 0.003, ore = 0.003, other = 0.003, fish = 0.008 }
-- Seconds allowed between a gather cast finishing and its loot showing up.
local GATHER_WINDOW = 6
-- A mining vein takes several hits and a fishing session takes many casts.
-- Gathers this close together in time count as one visit.
local VISIT_WINDOW = { herb = 90, ore = 90, other = 90, fish = 600 }
local SENT_WINDOW = 15
local DEBUG_MAX = 300

local DEFAULTS = { pins = true, minimap = true, fishing = true, chests = false, debug = false }

local db
local pending      -- the last gather cast that finished, waiting for its loot
local sentTarget   -- name of the object the last cast was aimed at
local lootHandled = false

local function say(msg)
    print("|cff7fd45aNodeNotes|r: " .. tostring(msg))
end
ns.Say = say

-- Some values are hidden from addons in combat. Never touch one.
local function secret(v)
    local f = rawget(_G, "issecretvalue")
    if type(f) ~= "function" then
        return false
    end
    local ok, res = pcall(f, v)
    return ok and res == true
end

local function show(v)
    if secret(v) then
        return "<secret>"
    end
    return tostring(v)
end

local function log(fmt, ...)
    if not (db and db.settings.debug) then
        return
    end
    local ok, msg = pcall(string.format, fmt, ...)
    local list = db.debugLog
    list[#list + 1] = date("%H:%M:%S ") .. (ok and msg or fmt)
    if #list > DEBUG_MAX then
        table.remove(list, 1)
    end
end

local function classify(spellName)
    if type(spellName) ~= "string" then
        return nil
    end
    local lower = spellName:lower()
    if lower:find("herb", 1, true) then
        return "herb"
    end
    if lower:find("mining", 1, true) then
        return "ore"
    end
    return nil
end

function ns.PlayerPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or secret(mapID) then
        return nil
    end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then
        return nil
    end
    local x, y = pos:GetXY()
    if not x or not y or secret(x) or secret(y) or (x == 0 and y == 0) then
        return nil
    end
    return mapID, x, y
end

function ns.MapName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or ("Map " .. tostring(mapID))
end

function ns.Ago(t)
    if not t then
        return "never"
    end
    local diff = time() - t
    if diff < 60 then
        return "just now"
    elseif diff < 3600 then
        return ("%dm ago"):format(math.floor(diff / 60))
    elseif diff < 86400 then
        return ("%dh ago"):format(math.floor(diff / 3600))
    end
    return ("%dd ago"):format(math.floor(diff / 86400))
end

-- {{name=, qty=}, ...} -> "3x Stranglekelp, 1x Blackmouth"
function ns.LootText(list, limit)
    local parts = {}
    for i = 1, #list do
        if limit and i > limit then
            parts[#parts + 1] = "..."
            break
        end
        parts[#parts + 1] = ("%dx %s"):format(list[i].qty, list[i].name)
    end
    return table.concat(parts, ", ")
end

local function sortedTotals(totals)
    local list = {}
    for name, qty in pairs(totals) do
        list[#list + 1] = { name = name, qty = qty }
    end
    table.sort(list, function(a, b)
        if a.qty ~= b.qty then
            return a.qty > b.qty
        end
        return a.name < b.name
    end)
    return list
end

function ns.Describe(node, mapID)
    local lines = {}
    lines[#lines + 1] = ("%s  %.1f, %.1f"):format(ns.MapName(mapID), node.x * 100, node.y * 100)
    local verb = node.kind == "fish" and "Fished" or "Gathered"
    lines[#lines + 1] = ("%s %d time%s, last %s"):format(verb, node.count, node.count == 1 and "" or "s", ns.Ago(node.last))
    if node.loot and #node.loot > 0 then
        lines[#lines + 1] = "Last yield: " .. ns.LootText(node.loot)
    end
    local totals = sortedTotals(node.totals or {})
    if #totals > 0 and node.count > 1 then
        lines[#lines + 1] = "All time: " .. ns.LootText(totals, 4)
    end
    return lines
end

function ns.NodesForMap(mapID)
    return (db and mapID and db.nodes[mapID]) or {}
end

function ns.Settings()
    return db and db.settings
end

local function changed()
    if ns.Map then
        ns.Map.Refresh()
    end
    if ns.Mini then
        ns.Mini.Refresh()
    end
    if ns.Note then
        ns.Note.Refresh()
    end
end

-- Record one gather. Returns the node and whether it is new.
function ns.RecordGather(mapID, x, y, kind, name, objectID, items, now)
    now = now or time()
    local list = db.nodes[mapID]
    if not list then
        list = {}
        db.nodes[mapID] = list
    end

    local radius = MERGE_RADIUS[kind] or MERGE_RADIUS.other
    local node, best
    for i = 1, #list do
        local n = list[i]
        if n.kind == kind then
            local dx, dy = n.x - x, n.y - y
            local d = dx * dx + dy * dy
            if d <= radius * radius and (not best or d < best) then
                node, best = n, d
            end
        end
    end

    local isNew = false
    if not node then
        node = { x = x, y = y, kind = kind, count = 0, first = now, totals = {}, note = "" }
        list[#list + 1] = node
        isNew = true
    end

    local window = VISIT_WINDOW[kind] or VISIT_WINDOW.other
    local sameVisit = node.last and (now - node.last) < window
    if not sameVisit then
        node.count = node.count + 1
        node.loot = {}
    end
    node.loot = node.loot or {}
    node.last = now

    if name and name ~= "" then
        node.name = name
    elseif not node.name then
        node.name = (items[1] and items[1].name) or "Unknown node"
    end
    if objectID then
        node.obj = objectID
    end
    if items[1] and items[1].icon then
        node.icon = items[1].icon
    end

    for i = 1, #items do
        local item = items[i]
        node.totals[item.name] = (node.totals[item.name] or 0) + item.qty
        local merged = false
        for j = 1, #node.loot do
            if node.loot[j].name == item.name then
                node.loot[j].qty = node.loot[j].qty + item.qty
                merged = true
                break
            end
        end
        if not merged then
            node.loot[#node.loot + 1] = { name = item.name, qty = item.qty, id = item.id }
        end
    end

    ns.last = { mapID = mapID, node = node }
    changed()
    return node, isNew
end

function ns.SetNote(node, text)
    text = (text or ""):match("^%s*(.-)%s*$")
    node.note = text
    changed()
end

function ns.DeleteNode(mapID, node)
    local list = db.nodes[mapID]
    if not list then
        return false
    end
    for i = 1, #list do
        if list[i] == node then
            table.remove(list, i)
            if ns.last and ns.last.node == node then
                ns.last = nil
            end
            changed()
            return true
        end
    end
    return false
end

-- The most recently gathered node across all maps.
function ns.FindLast()
    if ns.last then
        return ns.last.mapID, ns.last.node
    end
    local bestMap, bestNode
    for mapID, list in pairs(db.nodes) do
        for i = 1, #list do
            if list[i].last and (not bestNode or list[i].last > bestNode.last) then
                bestMap, bestNode = mapID, list[i]
            end
        end
    end
    return bestMap, bestNode
end

local function readLoot()
    local items, objectID, fromObject = {}, nil, false
    local count = GetNumLootItems() or 0
    local getType = rawget(_G, "GetLootSlotType")
    for slot = 1, count do
        local icon, name, qty = GetLootSlotInfo(slot)
        local isItem = true
        if type(getType) == "function" then
            isItem = getType(slot) == 1
        end
        if isItem and type(name) == "string" and not secret(name) and name ~= "" then
            if secret(qty) or type(qty) ~= "number" or qty < 1 then
                qty = 1
            end
            local link = GetLootSlotLink(slot)
            local id
            if type(link) == "string" and not secret(link) then
                id = tonumber(link:match("item:(%d+)"))
            end
            if secret(icon) then
                icon = nil
            end
            items[#items + 1] = { name = name, qty = qty, id = id, icon = icon }
        end
        local guid = GetLootSourceInfo(slot)
        if type(guid) == "string" and not secret(guid) then
            local gtype, entry = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
            if gtype == "GameObject" then
                fromObject = true
                objectID = tonumber(entry)
            end
        end
    end
    return items, objectID, fromObject
end

local function handleLoot()
    if lootHandled then
        return
    end
    lootHandled = true

    local gather = pending
    pending = nil
    if gather and (GetTime() - gather.t) > GATHER_WINDOW then
        gather = nil
    end

    local ok, items, objectID, fromObject = pcall(readLoot)
    if not ok then
        log("loot read failed: %s", tostring(items))
        return
    end
    local fishing = IsFishingLoot and IsFishingLoot()
    log("loot: %d item(s) [%s] object=%s gather=%s fishing=%s", #items, ns.LootText(items),
        tostring(objectID), gather and gather.kind or "none", tostring(fishing))

    if #items == 0 then
        return
    end

    local kind, name
    if fishing then
        -- The client says so itself, no cast needed. The loot comes from your
        -- own bobber, so the object id means nothing here.
        if not db.settings.fishing then
            return
        end
        kind, name, gather, objectID = "fish", "Fishing Spot", nil, nil
    else
        kind = gather and gather.kind
        name = gather and gather.name
        if not kind and fromObject and db.settings.chests then
            kind = "other"
        end
    end
    if not kind then
        return
    end

    local mapID, x, y
    if gather and gather.mapID then
        mapID, x, y = gather.mapID, gather.x, gather.y
    else
        mapID, x, y = ns.PlayerPosition()
    end
    if not mapID then
        log("no map position, not recorded")
        return
    end

    local node, isNew = ns.RecordGather(mapID, x, y, kind, name, objectID, items)
    if isNew then
        if kind == "fish" then
            say(("new fishing spot in %s. Type /nn to add a note."):format(ns.MapName(mapID)))
        else
            say(("new node: %s in %s. Type /nn to add a note."):format(node.name, ns.MapName(mapID)))
        end
    end
end

local function onCastSent(unit, target, _, spellID)
    if secret(unit) or unit ~= "player" then
        return
    end
    if type(target) == "string" and not secret(target) and target ~= "" then
        sentTarget = { name = target, t = GetTime() }
    else
        sentTarget = nil
    end
    log("sent: spell=%s target=%s", show(spellID), show(target))
end

local function onCastSucceeded(unit, _, spellID)
    if secret(unit) or unit ~= "player" then
        return
    end
    if secret(spellID) or type(spellID) ~= "number" then
        return
    end
    local name = C_Spell.GetSpellName(spellID)
    if secret(name) then
        return
    end
    local kind = classify(name)
    log("cast: %s (%d) kind=%s", tostring(name), spellID, tostring(kind))
    if not kind then
        return
    end
    local target
    if sentTarget and (GetTime() - sentTarget.t) <= SENT_WINDOW then
        target = sentTarget.name
    end
    local mapID, x, y = ns.PlayerPosition()
    pending = { kind = kind, t = GetTime(), name = target, mapID = mapID, x = x, y = y }
end

local function countNodes()
    local nodes, maps = 0, 0
    for _, list in pairs(db.nodes) do
        maps = maps + 1
        nodes = nodes + #list
    end
    return nodes, maps
end

local function setFlag(key, arg, label)
    if arg == "on" or arg == "off" then
        db.settings[key] = (arg == "on")
        say(label .. " " .. arg)
        changed()
    else
        say(("%s is %s. Use on or off."):format(label, db.settings[key] and "on" or "off"))
    end
end

local function onSlash(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "last" then
        local mapID, node = ns.FindLast()
        if not node then
            say("no nodes recorded yet. Gather a herb, mine a vein, or catch a fish first.")
            return
        end
        ns.Note.Open(mapID, node)
    elseif cmd == "note" then
        local mapID, node = ns.FindLast()
        if not node then
            say("no nodes recorded yet.")
            return
        end
        ns.SetNote(node, rest)
        say(("note saved on %s in %s."):format(node.name, ns.MapName(mapID)))
    elseif cmd == "list" then
        local mapID = ns.PlayerPosition()
        local list = ns.NodesForMap(mapID)
        say(("%d node(s) in %s"):format(#list, ns.MapName(mapID)))
        for i = 1, math.min(#list, 20) do
            local n = list[i]
            local note = (n.note and n.note ~= "") and ("  \"" .. n.note .. "\"") or ""
            say(("  %s %.1f, %.1f  x%d  %s%s"):format(n.name, n.x * 100, n.y * 100, n.count, ns.Ago(n.last), note))
        end
    elseif cmd == "pins" then
        setFlag("pins", rest:lower(), "world map pins")
    elseif cmd == "minimap" then
        setFlag("minimap", rest:lower(), "minimap pins")
    elseif cmd == "fishing" then
        setFlag("fishing", rest:lower(), "recording fishing spots")
    elseif cmd == "chests" then
        setFlag("chests", rest:lower(), "recording chests and other objects")
    elseif cmd == "debug" then
        setFlag("debug", rest:lower(), "debug log")
    elseif cmd == "status" then
        local nodes, maps = countNodes()
        say(("%d node(s) across %d map(s). Session %d."):format(nodes, maps, db.sessions))
    else
        say("/nn  open the note for your last node")
        say("/nn note <text>  set that note from chat")
        say("/nn list  nodes in this zone")
        say("/nn pins on|off, /nn minimap on|off")
        say("/nn fishing on|off, /nn chests on|off")
        say("/nn debug on|off, /nn status")
    end
end

local function initDB()
    if type(NodeNotesDB) ~= "table" then
        NodeNotesDB = {}
    end
    db = NodeNotesDB
    db.version = 1
    db.nodes = db.nodes or {}
    db.settings = db.settings or {}
    for key, value in pairs(DEFAULTS) do
        if db.settings[key] == nil then
            db.settings[key] = value
        end
    end
    db.debugLog = db.debugLog or {}
    -- Counts sessions that found saved data. Shows whether the client is
    -- reading saved variables back at login.
    db.sessions = (db.sessions or 0) + 1
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        initDB()
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("LOOT_READY")
        self:RegisterEvent("LOOT_OPENED")
        self:RegisterEvent("LOOT_CLOSED")
        if self.RegisterUnitEvent then
            self:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
            self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        else
            self:RegisterEvent("UNIT_SPELLCAST_SENT")
            self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        end
        SLASH_NODENOTES1 = "/nodenotes"
        SLASH_NODENOTES2 = "/nn"
        SlashCmdList["NODENOTES"] = onSlash
    elseif event == "PLAYER_LOGIN" then
        ns.Map.Init()
        ns.Mini.Init()
        local nodes = countNodes()
        say(("loaded, %d node(s) on record. /nn help for commands."):format(nodes))
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        handleLoot()
    elseif event == "LOOT_CLOSED" then
        lootHandled = false
    elseif event == "UNIT_SPELLCAST_SENT" then
        onCastSent(...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        onCastSucceeded(...)
    end
end)
