-- NodeNotes: a personal record of the nodes you have used.
--
-- It records a node when you finish a herb or mining cast and the loot window
-- opens, when you land a catch while fishing, when you loot a chest, when you
-- meet or kill a rare, and when a mob drops something special: where you
-- stood, what it gave you, and when. Nothing is automated. Every record comes
-- from something you did yourself, and nothing leaves your computer unless you
-- turn sharing on (see Share.lua).

local ADDON, ns = ...

-- Two records of the same kind closer than this (in map coordinates, where a
-- whole zone is 1.0 wide) count as the same node. Herbs, veins and chests
-- stand still, so about 10 to 15 yards. A fishing spot is wherever you stood
-- on the shore, so it gets more room. Rares wander, so they match by creature
-- instead of by distance.
local MERGE_RADIUS = { herb = 0.003, ore = 0.003, chest = 0.003, fish = 0.008, find = 0.005 }
-- Seconds allowed between a gather cast finishing and its loot showing up.
local GATHER_WINDOW = 6
-- A mining vein takes several hits and a fishing session takes many casts.
-- Records this close together in time count as one visit.
local VISIT_WINDOW = { herb = 90, ore = 90, chest = 90, fish = 600, find = 90, rare = 300 }
local SENT_WINDOW = 15
local DEBUG_MAX = 300
local RARE_CACHE_MAX = 50

local DEFAULTS = {
    pins = true, minimap = true, continent = true, fishing = true, chests = true,
    rares = true, finds = true, findQuality = 3, friends = true, share = "off", debug = false,
}

ns.KIND_LABEL = { herb = "Herb", ore = "Ore", fish = "Fishing spot", chest = "Chest", rare = "Rare", find = "Find" }
local VERB = { herb = "Gathered", ore = "Gathered", fish = "Fished", chest = "Looted", find = "Found" }
local QUALITY_NAME = { [2] = "green", [3] = "blue", [4] = "epic" }

-- Gathering spells by id. Any other rank or client is caught by name, first
-- against the client's own name for the first rank so every language works,
-- then against the English words.
local GATHER_SPELLS = {
    [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
    [2575] = "ore", [2576] = "ore", [3564] = "ore", [10248] = "ore",
}
local OPENING_SPELL = 3365

local GUID_PATTERN = "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)"

local db
local pending      -- the last gather cast that finished, waiting for its loot
local sentTarget   -- name of the object the last cast was aimed at
local opened       -- name of the last object you cast Opening on
local lootHandled = false
local rares, rareCount = {}, 0   -- creature GUID -> { npc =, name = } for rares you have met
local localNames                 -- localized spell name -> kind, filled on first use

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
ns.Secret = secret

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
ns.Log = log

local function spellName(id)
    local name = C_Spell.GetSpellName(id)
    if type(name) == "string" and not secret(name) then
        return name
    end
    return nil
end

local function classify(spellID, name)
    local kind = GATHER_SPELLS[spellID]
    if kind then
        return kind
    end
    if type(name) ~= "string" then
        return nil
    end
    if not localNames then
        localNames = {}
        for id, k in pairs({ [2366] = "herb", [2575] = "ore", [OPENING_SPELL] = "open" }) do
            local n = spellName(id)
            if n then
                localNames[n] = k
            end
        end
    end
    if localNames[name] then
        return localNames[name]
    end
    local lower = name:lower()
    if lower:find("herb", 1, true) then
        return "herb"
    end
    if lower:find("mining", 1, true) then
        return "ore"
    end
    if lower == "opening" then
        return "open"
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

-- Where a child map (a zone, or a cave inside a zone) sits on one of the maps
-- above it, as { minX, maxX, minY, maxY } in the outer map's coordinates.
-- Nil when the outer map does not contain the child.
local rects = {}
function ns.RectOn(childID, outerID)
    local key = childID .. ":" .. outerID
    local cached = rects[key]
    if cached ~= nil then
        return cached or nil
    end
    local result = false
    local id, steps = childID, 0
    while id and steps < 10 do
        local info = C_Map.GetMapInfo(id)
        id = info and info.parentMapID
        steps = steps + 1
        if id == outerID then
            local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, childID, outerID)
            if ok and minX and maxX and minY and maxY and maxX > minX and maxY > minY then
                result = { minX, maxX, minY, maxY }
            end
            break
        end
    end
    rects[key] = result
    return result or nil
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

local function times(n)
    return n == 1 and "time" or "times"
end

function ns.Describe(node, mapID)
    local lines = {}
    lines[#lines + 1] = ("%s  %.1f, %.1f"):format(ns.MapName(mapID), node.x * 100, node.y * 100)
    if node.kind == "rare" then
        if node.count > 0 then
            lines[#lines + 1] = ("Killed %d %s, last %s"):format(node.count, times(node.count), ns.Ago(node.last))
        end
        if node.seenCount then
            lines[#lines + 1] = ("Seen %d %s, last %s"):format(node.seenCount, times(node.seenCount), ns.Ago(node.seen))
        end
    else
        local verb = VERB[node.kind] or "Gathered"
        lines[#lines + 1] = ("%s %d %s, last %s"):format(verb, node.count, times(node.count), ns.Ago(node.last))
    end
    if node.loot and #node.loot > 0 then
        lines[#lines + 1] = "Last yield: " .. ns.LootText(node.loot)
    end
    local totals = sortedTotals(node.totals or {})
    if #totals > 0 and node.count > 1 then
        lines[#lines + 1] = "All time: " .. ns.LootText(totals, 4)
    end
    return lines
end

local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function ns.IconFor(node)
    if node.kind == "rare" then
        return SKULL
    end
    return node.icon or FALLBACK_ICON
end

function ns.NodesForMap(mapID)
    return (db and mapID and db.nodes[mapID]) or {}
end

function ns.AllNodes()
    return db and db.nodes or {}
end

function ns.FriendNodes()
    return db and db.friends or {}
end

function ns.Settings()
    return db and db.settings
end

function ns.DB()
    return db
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
ns.Changed = changed

local function shared(mapID, node)
    if ns.Share then
        ns.Share.Queue(mapID, node)
    end
end

-- The node in a list that a new record of this kind belongs to, if any.
function ns.FindMatch(list, kind, x, y, npc)
    if kind == "rare" then
        for i = 1, #list do
            if list[i].kind == "rare" and list[i].npc == npc then
                return list[i]
            end
        end
        return nil
    end
    local radius = MERGE_RADIUS[kind] or MERGE_RADIUS.chest
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
    return node
end

local function listFor(mapID)
    local list = db.nodes[mapID]
    if not list then
        list = {}
        db.nodes[mapID] = list
    end
    return list
end

local function newNode(list, kind, x, y, now, npc)
    local node = { x = x, y = y, kind = kind, count = 0, first = now, totals = {}, note = "", npc = npc }
    list[#list + 1] = node
    return node
end

-- Record one gather, catch, chest, kill or find. Returns the node and whether
-- it is new.
function ns.RecordGather(mapID, x, y, kind, name, objectID, items, now, npc)
    now = now or time()
    local list = listFor(mapID)
    local node = ns.FindMatch(list, kind, x, y, npc)
    local isNew = false
    if not node then
        node = newNode(list, kind, x, y, now, npc)
        isNew = true
    end

    local window = VISIT_WINDOW[kind] or VISIT_WINDOW.chest
    local sameVisit = node.last and (now - node.last) < window
    if not sameVisit then
        node.count = node.count + 1
        node.loot = {}
    end
    node.loot = node.loot or {}
    node.last = now
    if kind == "rare" then
        -- A rare's pin shows where you last met it.
        node.x, node.y = x, y
    end

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
        if item.q and item.q > (node.best or 0) then
            node.best = item.q
        end
        local merged = false
        for j = 1, #node.loot do
            if node.loot[j].name == item.name then
                node.loot[j].qty = node.loot[j].qty + item.qty
                merged = true
                break
            end
        end
        if not merged then
            node.loot[#node.loot + 1] = { name = item.name, qty = item.qty, id = item.id, q = item.q }
        end
    end

    ns.last = { mapID = mapID, node = node }
    changed()
    shared(mapID, node)
    return node, isNew
end

-- You targeted, hovered or saw the nameplate of a rare. Returns the node and
-- whether it is new. Sightings close together in time count once.
function ns.RecordSighting(mapID, x, y, npc, name, now)
    now = now or time()
    local list = listFor(mapID)
    local node = ns.FindMatch(list, "rare", x, y, npc)
    local isNew = false
    if not node then
        node = newNode(list, "rare", x, y, now, npc)
        isNew = true
    end
    if node.seen and (now - node.seen) < VISIT_WINDOW.rare then
        return node, false
    end
    node.seen = now
    node.seenCount = (node.seenCount or 0) + 1
    node.x, node.y = x, y
    node.name = name or node.name or "Rare"
    changed()
    shared(mapID, node)
    return node, isNew
end

local function mapOf(node)
    for mapID, list in pairs(db.nodes) do
        for i = 1, #list do
            if list[i] == node then
                return mapID
            end
        end
    end
    return nil
end

function ns.SetNote(node, text)
    text = (text or ""):match("^%s*(.-)%s*$")
    node.note = text
    changed()
    local mapID = mapOf(node)
    if mapID then
        shared(mapID, node)
    end
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

local function plain(v)
    if secret(v) then
        return nil
    end
    return v
end

-- Remember a rare you can see, and record the sighting.
local function checkUnit(unit)
    if not (db and db.settings.rares) then
        return
    end
    if not plain(UnitExists(unit)) or plain(UnitIsPlayer(unit)) then
        return
    end
    local class = plain(UnitClassification(unit))
    if class ~= "rare" and class ~= "rareelite" then
        return
    end
    local guid = plain(UnitGUID(unit))
    if type(guid) ~= "string" then
        return
    end
    local gtype, entry = guid:match(GUID_PATTERN)
    if gtype ~= "Creature" then
        return
    end
    local name = plain(UnitName(unit))
    if type(name) ~= "string" or name == "" then
        name = nil
    end
    if not rares[guid] then
        if rareCount >= RARE_CACHE_MAX then
            rares, rareCount = {}, 0
        end
        rareCount = rareCount + 1
    end
    rares[guid] = { npc = tonumber(entry), name = name }

    local mapID, x, y = ns.PlayerPosition()
    if not mapID then
        return
    end
    local node, isNew = ns.RecordSighting(mapID, x, y, tonumber(entry), name)
    log("rare: %s (%s) new=%s", tostring(name), tostring(entry), tostring(isNew))
    if isNew then
        say(("rare spotted: %s in %s. Type /nn to add a note once you have looted it."):format(node.name, ns.MapName(mapID)))
    end
end

local function readLoot()
    local items, source = {}, nil
    local count = GetNumLootItems() or 0
    local getType = rawget(_G, "GetLootSlotType")
    for slot = 1, count do
        local icon, name, qty, _, quality, _, isQuest = GetLootSlotInfo(slot)
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
            if secret(quality) or type(quality) ~= "number" then
                quality = nil
            end
            items[#items + 1] = { name = name, qty = qty, id = id, icon = icon, q = quality, quest = plain(isQuest) == true }
        end
        local guid = GetLootSourceInfo(slot)
        if not source and type(guid) == "string" and not secret(guid) then
            local gtype, entry = guid:match(GUID_PATTERN)
            if gtype then
                source = { guid = guid, type = gtype, id = tonumber(entry) }
            end
        end
    end
    return items, source
end

local function rareFor(guid)
    if rares[guid] then
        return rares[guid]
    end
    -- Looting a rare you never targeted: it may still be your target.
    if plain(UnitGUID("target")) == guid then
        checkUnit("target")
    end
    return rares[guid]
end

local function special(items)
    local out = {}
    local threshold = db.settings.findQuality or 3
    for i = 1, #items do
        if items[i].q and items[i].q >= threshold then
            out[#out + 1] = items[i]
        end
    end
    return out
end

local function onlyQuestItems(items)
    for i = 1, #items do
        if not items[i].quest then
            return false
        end
    end
    return true
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

    local ok, items, source = pcall(readLoot)
    if not ok then
        log("loot read failed: %s", tostring(items))
        return
    end
    local fishing = IsFishingLoot and IsFishingLoot()
    log("loot: %d item(s) [%s] source=%s gather=%s fishing=%s", #items, ns.LootText(items),
        source and (source.type .. ":" .. tostring(source.id)) or "none", gather and gather.kind or "none", tostring(fishing))

    if #items == 0 then
        return
    end

    local settings = db.settings
    local fromObject = source and source.type == "GameObject"
    local fromCreature = source and (source.type == "Creature" or source.type == "Vehicle")
    local kind, name, objectID, npc
    if fishing then
        -- The client says so itself, no cast needed. The loot comes from your
        -- own bobber, so the object id means nothing here.
        if not settings.fishing then
            return
        end
        kind, name, gather = "fish", "Fishing Spot", nil
    elseif gather then
        kind, name = gather.kind, gather.name
        objectID = fromObject and source.id or nil
    elseif fromObject then
        -- Objects that only hold quest items are left to quest addons.
        if not settings.chests or onlyQuestItems(items) then
            return
        end
        kind, objectID = "chest", source.id
        if opened and (GetTime() - opened.t) <= SENT_WINDOW then
            name = opened.name
        end
    elseif fromCreature then
        local rare = settings.rares and rareFor(source.guid)
        if rare then
            kind, name, npc = "rare", rare.name, rare.npc
        elseif settings.finds then
            items = special(items)
            if #items == 0 then
                return
            end
            kind, name = "find", items[1].name
        end
    end
    if not kind then
        return
    end
    opened = nil

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

    local node, isNew = ns.RecordGather(mapID, x, y, kind, name, objectID, items, nil, npc)
    if isNew then
        if kind == "fish" then
            say(("new fishing spot in %s. Type /nn to add a note."):format(ns.MapName(mapID)))
        elseif kind == "find" then
            say(("special find: %s in %s. Type /nn to add a note."):format(node.name, ns.MapName(mapID)))
        else
            local label = kind == "chest" and "new chest" or (kind == "rare" and "new rare" or "new node")
            say(("%s: %s in %s. Type /nn to add a note."):format(label, node.name, ns.MapName(mapID)))
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
    local name = spellName(spellID)
    local kind = classify(spellID, name)
    log("cast: %s (%d) kind=%s", tostring(name), spellID, tostring(kind))
    if not kind then
        return
    end
    local target
    if sentTarget and (GetTime() - sentTarget.t) <= SENT_WINDOW then
        target = sentTarget.name
    end
    if kind == "open" then
        opened = target and { name = target, t = GetTime() } or nil
        return
    end
    local mapID, x, y = ns.PlayerPosition()
    pending = { kind = kind, t = GetTime(), name = target, mapID = mapID, x = x, y = y }
end

local function countNodes()
    local nodes, maps = 0, 0
    local kinds = {}
    for _, list in pairs(db.nodes) do
        maps = maps + 1
        nodes = nodes + #list
        for i = 1, #list do
            kinds[list[i].kind] = (kinds[list[i].kind] or 0) + 1
        end
    end
    return nodes, maps, kinds
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

local FIND_LEVELS = { green = 2, blue = 3, epic = 4 }

local function setFinds(arg)
    if FIND_LEVELS[arg] then
        db.settings.finds = true
        db.settings.findQuality = FIND_LEVELS[arg]
        say(("recording mob drops of %s quality or better"):format(arg))
    elseif arg == "on" or arg == "off" then
        db.settings.finds = (arg == "on")
        say("recording special finds " .. arg)
    else
        local level = QUALITY_NAME[db.settings.findQuality] or tostring(db.settings.findQuality)
        say(("special finds are %s, %s or better. Use on, off, green, blue or epic."):format(
            db.settings.finds and "on" or "off", level))
    end
end

local function onSlash(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    local arg = (rest or ""):lower()

    if cmd == "" or cmd == "last" then
        local mapID, node = ns.FindLast()
        if not node then
            say("nothing recorded yet. Gather a herb, mine a vein, catch a fish or open a chest first.")
            return
        end
        ns.Note.Open(mapID, node)
    elseif cmd == "note" then
        local mapID, node = ns.FindLast()
        if not node then
            say("nothing recorded yet.")
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
            local label = ns.KIND_LABEL[n.kind] or n.kind
            say(("  %s: %s %.1f, %.1f  x%d  %s%s"):format(label, n.name, n.x * 100, n.y * 100, n.count,
                ns.Ago(n.last or n.seen), note))
        end
    elseif cmd == "pins" then
        setFlag("pins", arg, "world map pins")
    elseif cmd == "minimap" then
        setFlag("minimap", arg, "minimap pins")
    elseif cmd == "continent" then
        setFlag("continent", arg, "pins on continent maps")
    elseif cmd == "fishing" then
        setFlag("fishing", arg, "recording fishing spots")
    elseif cmd == "chests" then
        setFlag("chests", arg, "recording chests")
    elseif cmd == "rares" then
        setFlag("rares", arg, "recording rares")
    elseif cmd == "finds" then
        setFinds(arg)
    elseif cmd == "share" or cmd == "friends" then
        if ns.Share then
            ns.Share.Command(cmd, arg)
        else
            -- The game only reads files new to the .toc after a full restart.
            say("sharing needs a full game restart after updating, not just /reload.")
        end
    elseif cmd == "debug" then
        setFlag("debug", arg, "debug log")
    elseif cmd == "status" then
        local nodes, maps, kinds = countNodes()
        local parts = {}
        for _, k in ipairs({ "herb", "ore", "fish", "chest", "rare", "find" }) do
            if kinds[k] then
                parts[#parts + 1] = ("%d %s"):format(kinds[k], ns.KIND_LABEL[k]:lower())
            end
        end
        local detail = #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
        say(("%d node(s)%s across %d map(s). Session %d."):format(nodes, detail, maps, db.sessions))
        if ns.Share then
            ns.Share.Command("share", "")
        end
    else
        say("/nn  open the note for your last node")
        say("/nn note <text>  set that note from chat")
        say("/nn list  nodes in this zone, /nn status")
        say("/nn pins|minimap|continent on|off")
        say("/nn fishing|chests|rares on|off")
        say("/nn finds on|off|green|blue|epic  mob drops worth a pin")
        say("/nn share off|group|guild|both, /nn share sync")
        say("/nn friends on|off|clear  nodes your friends shared")
        say("/nn debug on|off")
    end
end

local function initDB()
    if type(NodeNotesDB) ~= "table" then
        NodeNotesDB = {}
    end
    db = NodeNotesDB
    db.nodes = db.nodes or {}
    if db.version == 1 then
        -- 0.3.0 and earlier called chests "other" and kept them off by
        -- default. Upgrading turns them on once.
        for _, list in pairs(db.nodes) do
            for i = 1, #list do
                if list[i].kind == "other" then
                    list[i].kind = "chest"
                end
            end
        end
        if type(db.settings) == "table" then
            db.settings.chests = true
        end
    end
    db.version = 2
    db.friends = db.friends or {}
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
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
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
        if ns.Share then
            ns.Share.Init()
        end
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
    elseif event == "PLAYER_TARGET_CHANGED" then
        checkUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        checkUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        if type(unit) == "string" and not secret(unit) then
            checkUnit(unit)
        end
    end
end)
