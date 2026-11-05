-- Loads NodeNotes under plain Lua 5.1 with a stubbed WoW API and drives it.
local dir = arg[1]
local out = {}
local realprint = print
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end out[#out+1] = table.concat(t, " ") end

local clock, wall = 1000, 1700000000
function GetTime() return clock end
function time() return wall end
function date() return "00:00:00 " end
local function advance(s) clock = clock + s; wall = wall + s end

local frames = {}
local function newFrame(ftype, name)
  local f = { _type = ftype, _events = {}, _scripts = {}, _shown = true, _text = "", _points = {}, _scale = 1, _w = 0, _h = 0, _level = 1 }
  local methods = {
    RegisterEvent = function(self, e) self._events[e] = true end,
    RegisterUnitEvent = function(self, e) self._events[e] = true end,
    UnregisterEvent = function(self, e) self._events[e] = nil end,
    SetScript = function(self, k, fn) self._scripts[k] = fn end,
    HookScript = function(self, k, fn) local old = self._scripts[k]; self._scripts[k] = function(...) if old then old(...) end fn(...) end end,
    Show = function(self) local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end,
    Hide = function(self) local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end,
    IsShown = function(self) return self._shown end,
    SetText = function(self, t) self._text = t end,
    GetText = function(self) return self._text end,
    SetSize = function(self, w, h) self._w, self._h = w, h end,
    GetWidth = function(self) return self._w end,
    GetHeight = function(self) return self._h end,
    SetScale = function(self, s) self._scale = s end,
    GetScale = function(self) return self._scale end,
    SetFrameLevel = function(self, l) self._level = l end,
    GetFrameLevel = function(self) return self._level end,
    ClearAllPoints = function(self) self._points = {} end,
    SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end,
    CreateTexture = function() return newFrame("Texture") end,
    CreateFontString = function() return newFrame("FontString") end,
  }
  setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
  if name then _G[name] = f end
  frames[#frames + 1] = f
  return f
end
function CreateFrame(ftype, name) return newFrame(ftype, name) end
local function fire(event, ...)
  for i = 1, #frames do local f = frames[i]
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
function hooksecurefunc(tbl, name, hook) local orig = tbl[name]; tbl[name] = function(...) local r = orig(...); hook(...); return r end end

UIParent = newFrame("Frame"); UISpecialFrames = {}
Minimap = newFrame("Minimap"); Minimap:SetSize(140, 140); Minimap.IsVisible = function(self) return self._shown end
GameTooltip = newFrame("GameTooltip")
SlashCmdList = {}
local SECRET = {}
function issecretvalue(v) return v == SECRET end

-- map
local pos = { map = 224, x = 0.40, y = 0.60 }
local facing, rotate, viewRadius = 0, "0", 100
function GetPlayerFacing() return facing end
function GetCVar(k) if k == "rotateMinimap" then return rotate end end
C_Minimap = { GetViewRadius = function() return viewRadius end }
-- Stranglethorn Vale (224) sits inside Eastern Kingdoms (1415), inside Azeroth (947).
local parents = { [224] = 1415, [1415] = 947 }
local mapNames = { [224] = "Stranglethorn Vale", [1415] = "Eastern Kingdoms" }
C_Map = {
  GetMapWorldSize = function() return 4000, 3000 end,
  GetBestMapForUnit = function() return pos.map end,
  GetPlayerMapPosition = function() if not pos.x then return nil end return { GetXY = function() return pos.x, pos.y end } end,
  GetMapInfo = function(id) return { name = mapNames[id] or ("Zone" .. id), parentMapID = parents[id] } end,
  GetMapRectOnMap = function(child, outer) if child == 224 and outer == 1415 then return 0.4, 0.6, 0.6, 0.9 end end,
}
local spells = { [2366] = "Herb Gathering", [2575] = "Mining", [133] = "Fireball", [3365] = "Opening", [99366] = "Herb Gathering" }
C_Spell = { GetSpellName = function(id) return spells[id] end }

-- units
local units = {}
function UnitExists(u) return units[u] ~= nil end
function UnitIsPlayer(u) return units[u] ~= nil and units[u].player == true end
function UnitClassification(u) return units[u] and units[u].class or "normal" end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitName(u) if u == "player" then return "Me" end return units[u] and units[u].name end

-- addon messages
local sent = {}
local group, raid, guild, combat = false, false, false, false
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(p, m, ch) sent[#sent + 1] = { p = p, m = m, ch = ch } end,
}
function IsInGroup() return group end
function IsInRaid() return raid end
function IsInGuild() return guild end
function InCombatLockdown() return combat end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end

-- loot window
local loot = {}
function GetNumLootItems() return #loot end
function GetLootSlotInfo(i) local l = loot[i]; return l.icon, l.name, l.qty, nil, l.q, false, l.quest end
function GetLootSlotType(i) return loot[i].coin and 2 or 1 end
function GetLootSlotLink(i) return loot[i].id and ("|cffffffff|Hitem:" .. loot[i].id .. "::::|h[x]|h|r") or nil end
function GetLootSourceInfo(i) return loot[i].guid end
local fishing = false
function IsFishingLoot() return fishing end
local function openLoot(items) loot = items; fire("LOOT_READY", true); fire("LOOT_OPENED", true); fire("LOOT_CLOSED") end
local HERB_GUID = "GameObject-0-3299-0-36-2045-00005E1234"

-- world map
WorldMapFrame = newFrame("Frame"); WorldMapFrame._shown = false
local canvas = newFrame("Frame"); canvas:SetSize(1000, 660); canvas._scale = 0.5; canvas._level = 10
WorldMapFrame.GetCanvas = function() return canvas end
local viewed = 224
WorldMapFrame.GetMapID = function() return viewed end
WorldMapFrame.OnMapChanged = function() end
WorldMapFrame.OnCanvasScaleChanged = function() end

local ns = {}
local FILES = { "Core.lua", "Note.lua", "Map.lua", "Minimap.lua", "Share.lua" }
for _, file in ipairs(FILES) do
  assert(loadfile(dir .. "/" .. file))("NodeNotes", ns)
end
local function tick() for i = 1, #frames do local f = frames[i]; if f._scripts.OnUpdate then f._scripts.OnUpdate(f, 1) end end end
fire("ADDON_LOADED", "Other"); assert(NodeNotesDB == nil)
fire("ADDON_LOADED", "NodeNotes"); fire("PLAYER_LOGIN")
local db = NodeNotesDB
assert(db.sessions == 1 and db.version == 2 and db.settings.pins == true and db.settings.chests == true)
assert(db.settings.minimap == true and db.settings.fishing == true and db.settings.debug == false)
assert(db.settings.rares == true and db.settings.finds == true and db.settings.findQuality == 3 and db.settings.continent == true)
assert(db.settings.share == "off" and db.settings.friends == true and type(db.friends) == "table")
local slash = assert(SlashCmdList.NODENOTES); assert(SLASH_NODENOTES2 == "/nn")
slash("debug on")
slash(""); slash("list"); slash("note hi")   -- nothing recorded yet, must not error

local function gather(spell, target, items)
  fire("UNIT_SPELLCAST_SENT", "player", target, "cast-1", spell)
  advance(2)
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", spell)
  advance(0.3)
  openLoot(items)
end

-- 1. a herb gather is recorded with yield and position
gather(2366, "Stranglekelp", { { name = "Stranglekelp", qty = 3, id = 3820, icon = 134187, guid = HERB_GUID } })
local list = db.nodes[224]; assert(#list == 1)
local n = list[1]
assert(n.name == "Stranglekelp" and n.kind == "herb" and n.count == 1 and n.obj == 2045 and n.icon == 134187)
assert(math.abs(n.x - 0.40) < 1e-9 and n.loot[1].qty == 3 and n.totals.Stranglekelp == 3 and n.loot[1].id == 3820)
assert(ns.LootText(n.loot) == "3x Stranglekelp")

-- 2. LOOT_READY + LOOT_OPENED for one window counts once (checked above: count == 1)
-- 3. same spot later: merged, new visit, last yield replaced, totals add
advance(600); pos.x, pos.y = 0.4012, 0.6009
gather(2366, "Stranglekelp", { { name = "Stranglekelp", qty = 2, guid = HERB_GUID }, { name = "5 Copper", qty = 0, coin = true } })
assert(#list == 1 and n.count == 2 and n.loot[1].qty == 2 and #n.loot == 1 and n.totals.Stranglekelp == 5)

-- 4. a far herb is a separate node; an ore at the first spot is separate too (different kind)
pos.x, pos.y = 0.45, 0.60
gather(2366, "Kingsblood", { { name = "Kingsblood", qty = 1, guid = HERB_GUID } })
assert(#list == 2)
pos.x, pos.y = 0.40, 0.60
gather(2575, "Tin Vein", { { name = "Tin Ore", qty = 2 }, { name = "Coarse Stone", qty = 1 } })
assert(#list == 3 and list[3].kind == "ore" and list[3].name == "Tin Vein")
-- 5. second hit on the vein inside the visit window: same visit, yields merge
advance(4)
gather(2575, "Tin Vein", { { name = "Tin Ore", qty = 1 }, { name = "Shadowgem", qty = 1 } })
local vein = list[3]
assert(vein.count == 1 and vein.loot[1].qty == 3 and #vein.loot == 3 and vein.totals["Tin Ore"] == 3)
assert(ns.LootText(vein.loot) == "3x Tin Ore, 1x Coarse Stone, 1x Shadowgem")

-- 6. things that must not record
local before = #list
slash("chests off")
advance(60)
openLoot({ { name = "Linen Cloth", qty = 2, guid = "Creature-0-3299-0-36-1234-00005E1234" } })          -- mob loot
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 133); openLoot({ { name = "Wool Cloth", qty = 1 } })    -- non-gather cast
openLoot({ { name = "Silk Cloth", qty = 1, guid = "GameObject-0-3299-0-36-99-00005E1234" } })           -- chest, chests off
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2366); advance(30); openLoot({ { name = "Stale", qty = 1 } }) -- cast too old
slash("fishing off")
fishing = true; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2366); openLoot({ { name = "Fish", qty = 1 } }); fishing = false
slash("fishing on")
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "c", 2366); openLoot({ { name = "NotMine", qty = 1 } })      -- someone else
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", SECRET); openLoot({ { name = "Hidden", qty = 1 } })    -- secret spell id
pos.x = nil; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2366); openLoot({ { name = "Indoors", qty = 1 } }); pos.x = 0.40 -- no map position
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2366); openLoot({ { name = SECRET, qty = 1 } })          -- secret loot name
assert(#list == before, "recorded something it should not have: " .. #list .. " vs " .. before)

-- 7. chests on: object loot without a gather cast is recorded as a chest
slash("chests on"); pos.x, pos.y = 0.10, 0.10
openLoot({ { name = "Silk Cloth", qty = 1, guid = "GameObject-0-3299-0-36-99-00005E1234" } })
assert(#list == before + 1 and list[#list].kind == "chest" and list[#list].name == "Silk Cloth" and list[#list].obj == 99)
slash("chests off")

-- 7b. fishing: the client flags the loot, no cast needed. Casts from one stretch of
-- shore merge into one spot, and a session is one visit.
pos.x, pos.y = 0.70, 0.20
fishing = true
openLoot({ { name = "Raw Brilliant Smallfish", qty = 1, guid = "GameObject-0-3299-0-36-35591-00005E1234" } })
local spot = list[#list]
assert(spot.kind == "fish" and spot.name == "Fishing Spot" and spot.count == 1 and spot.obj == nil, "fishing spot not recorded")
assert(out[#out]:find("new fishing spot in Stranglethorn Vale", 1, true), out[#out])
advance(30); pos.x = 0.705   -- 20 yards along the shore: too far for a herb, same fishing spot
openLoot({ { name = "Raw Brilliant Smallfish", qty = 1 }, { name = "Raw Longjaw Mud Snapper", qty = 1 } })
assert(list[#list] == spot and spot.count == 1 and spot.loot[1].qty == 2 and #spot.loot == 2, "second cast must merge")
advance(700)
openLoot({ { name = "Raw Brilliant Smallfish", qty = 1 } })
assert(spot.count == 2 and #spot.loot == 1 and spot.totals["Raw Brilliant Smallfish"] == 3, "later session is a new visit")
assert(ns.Describe(spot, 224)[2]:find("^Fished 2 times"), ns.Describe(spot, 224)[2])
-- a stale herb cast does not turn a catch into a herb
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2366); advance(1)
openLoot({ { name = "Raw Brilliant Smallfish", qty = 1 } })
assert(list[#list] == spot and spot.totals["Raw Brilliant Smallfish"] == 4)
slash("fishing off"); openLoot({ { name = "Raw Brilliant Smallfish", qty = 1 } }); assert(spot.totals["Raw Brilliant Smallfish"] == 4)
slash("fishing on")
fishing = false
-- a herb at the same place is its own node
gather(2366, "Silverleaf", { { name = "Silverleaf", qty = 1, guid = HERB_GUID } })
assert(list[#list].kind == "herb" and list[#list] ~= spot)
pos.x, pos.y = 0.40, 0.60

-- 8. notes: from chat, and through the window (saved on close)
slash("note   3x stranglekelp, behind the wreck  ")
local _, lastNode = ns.FindLast(); assert(lastNode == list[#list] and lastNode.note == "3x stranglekelp, behind the wreck")
ns.Note.Open(224, n)
assert(NodeNotesFrame:IsShown() and ns.Note.Current().node == n)
local edit; for i = 1, #frames do if frames[i]._type == "EditBox" then edit = frames[i] end end
edit:SetText("low tide only")
NodeNotesFrame:Hide()
assert(n.note == "low tide only" and ns.Note.Current() == nil)
-- switching nodes while open keeps the first note
ns.Note.Open(224, n); edit:SetText("first"); ns.Note.Open(224, vein); assert(n.note == "first" and edit:GetText() == "")
NodeNotesFrame:Hide()

-- 9. map pins: only for the viewed map, positioned and counter-scaled
WorldMapFrame:Show()
assert(ns.Map.PinCount() == #list, "pins " .. ns.Map.PinCount())
local pin; for i = 1, #frames do if frames[i]._type == "Button" and frames[i].node == n then pin = frames[i] end end
assert(pin and pin._scale == 2)
local p = pin._points[1]; assert(p[1] == "CENTER" and p[3] == "TOPLEFT" and math.abs(p[4] - 0.40 * 1000 / 2) < 1e-6 and math.abs(p[5] + 0.60 * 660 / 2) < 1e-6)
pin._scripts.OnEnter(pin); pin._scripts.OnClick(pin); assert(ns.Note.Current().node == n); NodeNotesFrame:Hide()
viewed = 999; WorldMapFrame.OnMapChanged(WorldMapFrame); assert(ns.Map.PinCount() == 0)
viewed = 224; WorldMapFrame.OnMapChanged(WorldMapFrame); assert(ns.Map.PinCount() == #list)
slash("pins off"); assert(ns.Map.PinCount() == 0); slash("pins on"); assert(ns.Map.PinCount() == #list)

-- 10. delete needs two clicks and does not write the note back
ns.Note.Open(224, vein)
local del; for i = 1, #frames do if frames[i]._type == "Button" and frames[i]._text == "Delete node" then del = frames[i] end end
local count = #list
del._scripts.OnClick(del); assert(#list == count and del._text == "Confirm delete")
del._scripts.OnClick(del); assert(#list == count - 1 and not NodeNotesFrame:IsShown())
for i = 1, #list do assert(list[i] ~= vein) end
assert(ns.Map.PinCount() == #list)

-- 11. describe, ago, misc commands
advance(7200)
local lines = ns.Describe(n, 224)
assert(lines[1] == "Stranglethorn Vale  40.0, 60.0", lines[1])
assert(lines[2]:find("Gathered 2 times, last 2h ago", 1, true), lines[2])
assert(lines[3] == "Last yield: 2x Stranglekelp" and lines[4] == "All time: 5x Stranglekelp")
slash("list"); slash("status"); slash("help"); slash("debug"); slash("debug off"); slash("last")
assert(NodeNotesFrame:IsShown()); NodeNotesFrame:Hide()
assert(#db.debugLog > 0 and #db.debugLog <= 300)

-- 12. minimap pins. Map is 4000 x 3000 yards, view radius 100 yards, minimap 140 px wide.
local function near(a, b) return math.abs(a - b) < 1e-6 end
-- pure maths first: north of the player is up; with a rotating map the way you face is up
local x, y = ns.Mini.Offset(0, -50, nil, 100, 70); assert(near(x, 0) and near(y, 35))
x, y = ns.Mini.Offset(50, 0, nil, 100, 70); assert(near(x, 35) and near(y, 0))             -- east is right
x, y = ns.Mini.Offset(0, -50, math.pi / 2, 100, 70); assert(near(x, 35) and near(y, 0))    -- facing west: north is right
x, y = ns.Mini.Offset(-50, 0, math.pi / 2, 100, 70); assert(near(x, 0) and near(y, 35))    -- facing west: west is up
x, y = ns.Mini.Offset(50, 0, math.pi, 100, 70); assert(near(x, -35) and near(y, 0))        -- facing south: east is left
assert(ns.Mini.Offset(0, -95, nil, 100, 70) == nil and ns.Mini.Offset(0, -91, nil, 100, 70) ~= nil)
-- through the frames: stand 40 yards south and 20 yards west of the Stranglekelp node (0.40, 0.60)
local function miniPin(node) for i = 1, #frames do if frames[i]._type == "Frame" and frames[i].node == node and frames[i]._shown then return frames[i] end end end
pos.x, pos.y = 0.40 - 20 / 4000, 0.60 + 40 / 3000
tick()
local mp = assert(miniPin(n), "no minimap pin for the nearby node")
local pt = mp._points[1]; assert(pt[1] == "CENTER" and near(pt[4], 20 / 100 * 70) and near(pt[5], 40 / 100 * 70), pt[4] .. "," .. pt[5])
assert(ns.Mini.PinCount() == 1, "far nodes must be hidden: " .. ns.Mini.PinCount())   -- Kingsblood is 200 yards east
mp._scripts.OnEnter(mp)
rotate, facing = "1", math.pi / 2; tick()
mp = assert(miniPin(n)); pt = mp._points[1]; assert(near(pt[4], 40 / 100 * 70) and near(pt[5], -20 / 100 * 70), pt[4] .. "," .. pt[5])
facing = nil; tick(); assert(ns.Mini.PinCount() == 0, "no heading on a rotating map: hide")
rotate, facing = "0", 0; tick(); assert(ns.Mini.PinCount() == 1)
viewRadius = 400; tick(); assert(ns.Mini.PinCount() == 2, "zoomed out should reach the second herb")
viewRadius = 100
slash("minimap off"); tick(); assert(ns.Mini.PinCount() == 0)
slash("minimap on"); tick(); assert(ns.Mini.PinCount() == 1)
pos.map = 999; tick(); assert(ns.Mini.PinCount() == 0); pos.map = 224
pos.x = nil; tick(); assert(ns.Mini.PinCount() == 0); pos.x, pos.y = 0.40, 0.60
Minimap._shown = false; tick(); assert(ns.Mini.PinCount() == 0); Minimap._shown = true

-- 12b. chests: Opening names the chest; objects holding only quest items are left alone
slash("chests on"); pos.x, pos.y = 0.20, 0.30
local count0 = #list
fire("UNIT_SPELLCAST_SENT", "player", "Battered Chest", "c", 3365); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 3365)
openLoot({ { name = "Coarse Thread", qty = 2, guid = "GameObject-0-3299-0-36-2843-00005E1234" } })
local chest = list[#list]
assert(#list == count0 + 1 and chest.kind == "chest" and chest.name == "Battered Chest" and chest.obj == 2843)
assert(out[#out]:find("new chest: Battered Chest", 1, true), out[#out])
assert(ns.Describe(chest, 224)[2]:find("^Looted 1 time"), ns.Describe(chest, 224)[2])
pos.x = 0.25
openLoot({ { name = "Tear of Tilloa", qty = 1, quest = true, guid = "GameObject-0-3299-0-36-2289-00005E1234" } })
assert(#list == count0 + 1, "quest object recorded")
-- a gather spell this file has no id for is still known by its name
pos.x, pos.y = 0.30, 0.30
gather(99366, "Fadeleaf", { { name = "Fadeleaf", qty = 1, guid = HERB_GUID } })
assert(#list == count0 + 2 and list[#list].kind == "herb" and list[#list].name == "Fadeleaf")

-- 12c. special finds: a blue from a mob gets a pin with just the special drop
local MOB = "Creature-0-3299-0-36-1234-00005E1234"
pos.x, pos.y = 0.50, 0.50
openLoot({ { name = "Linen Cloth", qty = 2, q = 1, guid = MOB }, { name = "Cruel Barb", qty = 1, q = 3, id = 5191, icon = 135324, guid = MOB } })
local find = list[#list]
assert(find.kind == "find" and find.name == "Cruel Barb" and #find.loot == 1 and find.best == 3 and find.icon == 135324)
assert(out[#out]:find("special find: Cruel Barb", 1, true), out[#out])
advance(100)
openLoot({ { name = "Gnoll Paw", qty = 1, q = 2, guid = MOB } })
assert(list[#list] == find and find.count == 1, "a green is not special by default")
slash("finds green"); openLoot({ { name = "Gnoll Paw", qty = 1, q = 2, guid = MOB } })
assert(find.count == 2 and find.loot[1].name == "Gnoll Paw" and find.best == 3)
slash("finds off"); advance(100); openLoot({ { name = "Big Find", qty = 1, q = 4, guid = MOB } }); assert(find.count == 2)
slash("finds blue"); assert(db.settings.finds and db.settings.findQuality == 3)
local count1 = #list

-- 12d. rares: seen when you target, hover or see the nameplate; a kill when you loot it
local RARE = "Creature-0-3299-0-36-5555-0000AAAA"
pos.x, pos.y = 0.60, 0.40
units.target = { guid = RARE, name = "Gorlash", class = "rareelite" }
fire("PLAYER_TARGET_CHANGED")
local rare = list[#list]
assert(#list == count1 + 1 and rare.kind == "rare" and rare.npc == 5555 and rare.count == 0 and rare.seenCount == 1)
assert(rare.name == "Gorlash" and out[#out]:find("rare spotted: Gorlash", 1, true), out[#out])
units.mouseover = units.target; fire("UPDATE_MOUSEOVER_UNIT"); assert(rare.seenCount == 1, "same sighting counts once")
units.mouseover = { guid = MOB, name = "Kobold", class = "normal" }; fire("UPDATE_MOUSEOVER_UNIT")
units.mouseover = { guid = "Player-1-0000AAAA", name = "Someone", class = "rare", player = true }; fire("UPDATE_MOUSEOVER_UNIT")
assert(#list == count1 + 1)
pos.x = 0.62
openLoot({ { name = "Linen Cloth", qty = 1, q = 1, guid = RARE }, { name = "Gorlash's Fang", qty = 1, q = 3, guid = RARE } })
assert(#list == count1 + 1 and rare.count == 1 and #rare.loot == 2 and rare.best == 3 and near(rare.x, 0.62))
local rl = ns.Describe(rare, 224)
assert(rl[2] == "Killed 1 time, last just now" and rl[3] == "Seen 1 time, last just now", rl[2] .. " / " .. tostring(rl[3]))
assert(ns.IconFor(rare):find("RaidTargetingIcon_8", 1, true))
advance(400); pos.x = 0.65; fire("PLAYER_TARGET_CHANGED")
assert(rare.seenCount == 2 and near(rare.x, 0.65), "seen again later, the pin follows")
units.nameplate3 = { guid = "Creature-0-3299-0-36-7777-0000CCCC", name = "Mosh'Ogg Brute", class = "rare" }
fire("NAME_PLATE_UNIT_ADDED", "nameplate3"); assert(#list == count1 + 2 and list[#list].npc == 7777)
slash("rares off")
units.target = { guid = "Creature-0-3299-0-36-6666-0000BBBB", name = "Other Rare", class = "rare" }; fire("PLAYER_TARGET_CHANGED")
assert(#list == count1 + 2); slash("rares on")
units.target, units.mouseover, units.nameplate3 = nil, nil, nil
units.target = { guid = SECRET, class = "rare" }; fire("PLAYER_TARGET_CHANGED"); units.target = nil  -- secret guid: ignored
assert(#list == count1 + 2)

-- 12e. continent pins: zone nodes show on the continent map, smaller, in the zone's rectangle
viewed = 1415; WorldMapFrame.OnMapChanged(WorldMapFrame)
assert(ns.Map.PinCount() == #list, "continent pins " .. ns.Map.PinCount())
local function mapPin(node) for i = 1, #frames do local f = frames[i]; if f._type == "Button" and f.node == node and f._shown then return f end end end
pin = assert(mapPin(n)); p = pin._points[1]
assert(near(pin._scale, 0.7 / 0.5) and near(p[4], (0.4 + 0.40 * 0.2) * 1000 / 1.4) and near(p[5], -(0.6 + 0.60 * 0.3) * 660 / 1.4))
slash("continent off"); assert(ns.Map.PinCount() == 0); slash("continent on"); assert(ns.Map.PinCount() == #list)
viewed = 947; WorldMapFrame.OnMapChanged(WorldMapFrame); assert(ns.Map.PinCount() == 0, "no rectangle, no pins")
viewed = 224; WorldMapFrame.OnMapChanged(WorldMapFrame); assert(ns.Map.PinCount() == #list)

-- 12f. square minimap: pins reach into the corners
assert(ns.Mini.Offset(80, -80, nil, 100, 70) == nil and ns.Mini.Offset(80, -80, nil, 100, 70, true) ~= nil)
assert(ns.Mini.Offset(95, 0, nil, 100, 70, true) == nil)
pos.x, pos.y = 0.40 - 80 / 4000, 0.60 + 80 / 3000
tick(); assert(miniPin(n) == nil, "round minimap: corner is outside")
GetMinimapShape = function() return "SQUARE" end
tick(); assert(miniPin(n) ~= nil, "square minimap: corner is inside")
GetMinimapShape = nil
pos.x, pos.y = 0.40, 0.60

-- 12g. sharing: messages are plain, bounded and checked
local sample = { x = 0.4012, y = 0.6, kind = "herb", count = 3, last = wall - 120, icon = 134187, best = 3, name = "Strangle|kelp",
  loot = { { name = "Stranglekelp", qty = 2 } }, note = "behind |Hitem:1|h the\nwreck" }
local msg = ns.Share.Encode(224, sample, wall)
assert(not msg:find("|", 1, true) and not msg:find("\n", 1, true) and #msg <= 250, msg)
local r = assert(ns.Share.Decode(msg))
assert(r.mapID == 224 and near(r.x, 0.4012) and r.kind == "herb" and r.count == 3 and r.ago == 120 and r.icon == 134187 and r.best == 3)
assert(r.name == "Strangle/kelp" and r.lootText == "2x Stranglekelp" and r.note == "behind /Hitem:1/h the wreck", r.note)
sample.note = string.rep("\195\164", 200)   -- 200 two-byte letters
msg = ns.Share.Encode(224, sample, wall); assert(#msg <= 250)
r = assert(ns.Share.Decode(msg)); assert(#r.note > 0 and #r.note % 2 == 0 and r.note:find("^[\195\164]+$"), "cut mid letter")
for _, bad in ipairs({ "", "2\t224", msg .. "\textra", (msg:gsub("^1\t224", "1\t-5")), (msg:gsub("\therb\t", "\tboss\t")),
    (msg:gsub("^(1\t224\t)%d+", "%1nan")), string.rep("x", 300) }) do
  assert(ns.Share.Decode(bad) == nil, "accepted: " .. bad:sub(1, 40))
end
-- sending: off by default, then one message a second to the right channel, never in combat
local function flush() for _ = 1, 6 do tick() end end
assert(ns.Share.Queue(224, n) == false and #sent == 0)
slash("share group"); group = true
assert(ns.Share.Queue(224, n) == true and ns.Share.Queue(224, n) == false and ns.Share.Pending() == 1)
combat = true; flush(); assert(#sent == 0); combat = false
flush(); assert(#sent == 1 and sent[1].ch == "PARTY" and sent[1].p == "NodeNotes" and ns.Share.Pending() == 0)
ns.SetNote(n, "shared note"); flush(); assert(#sent == 2 and sent[2].m:find("shared note", 1, true))
group = false; ns.SetNote(n, "solo"); flush(); assert(#sent == 2 and ns.Share.Pending() == 0, "nobody to send to")
slash("share both"); group, guild = true, true; ns.SetNote(n, "both"); flush()
assert(#sent == 4 and sent[3].ch == "PARTY" and sent[4].ch == "GUILD")
slash("share sync"); assert(ns.Share.Pending() > 1); flush(); flush(); flush()
slash("share off"); assert(ns.Share.Pending() == 0); local quiet = #sent; ns.SetNote(n, "quiet"); flush(); assert(#sent == quiet)
group, guild = false, false
-- receiving: only from your group or guild, never from yourself, kept apart from your own nodes
local function hear(m, ch, who) fire("CHAT_MSG_ADDON", "NodeNotes", m, ch, who) end
local vein2 = { x = 0.90, y = 0.10, kind = "ore", count = 2, last = wall - 60, icon = 135232, name = "Copper Vein",
  loot = { { name = "Copper Ore", qty = 3 } }, note = "top of the hill" }
local fm = ns.Share.Encode(224, vein2, wall)
hear(fm, "WHISPER", "Mira-Realm"); hear(fm, "PARTY", "Me"); hear("garbage", "PARTY", "Mira-Realm")
assert(db.friends[224] == nil, "stored something it should not have")
hear(fm, "PARTY", "Mira-Realm")
local fn = db.friends[224][1]
assert(fn.from == "Mira" and fn.kind == "ore" and fn.last == wall - 60 and fn.note == "top of the hill" and fn.lootText == "3x Copper Ore")
hear(fm, "GUILD", "Mira-Realm"); assert(#db.friends[224] == 1, "same node again updates it")
assert(ns.Map.PinCount() == #list + 1)
local fpin = assert(mapPin(fn)); assert(fpin.friend == true)
fpin._scripts.OnEnter(fpin); fpin._scripts.OnClick(fpin); assert(ns.Note.Current() == nil, "friend pins have no note window")
-- a friend's node where you already have one is not drawn twice
hear(ns.Share.Encode(224, { x = 0.40, y = 0.60, kind = "herb", count = 1, last = wall, name = "Stranglekelp" }, wall), "GUILD", "Kev")
assert(#db.friends[224] == 2 and ns.Map.PinCount() == #list + 1)
-- on the minimap too
pos.x, pos.y = 0.90 - 20 / 4000, 0.10; tick(); assert(miniPin(fn) ~= nil); pos.x, pos.y = 0.40, 0.60
slash("friends off"); assert(ns.Map.PinCount() == #list)
hear(ns.Share.Encode(224, { x = 0.95, y = 0.95, kind = "chest", count = 1, last = wall, name = "Box" }, wall), "PARTY", "Mira")
assert(#db.friends[224] == 2); slash("friends on"); assert(ns.Map.PinCount() == #list + 1)
slash("friends clear"); assert(next(db.friends) == nil and ns.Map.PinCount() == #list)

-- 13. a reload keeps the data, bumps the session counter, and renames 0.3.0 chests
local legacy = { x = 0.1, y = 0.1, kind = "other", count = 1, totals = {}, note = "" }
db.nodes[500] = { legacy }; db.version = 1; db.settings.chests = false
frames = { UIParent, GameTooltip, WorldMapFrame, canvas, Minimap }; local ns2 = {}
for _, file in ipairs(FILES) do assert(loadfile(dir .. "/" .. file))("NodeNotes", ns2) end
fire("ADDON_LOADED", "NodeNotes")
assert(NodeNotesDB == db and db.sessions == 2 and #db.nodes[224] == #list)
assert(legacy.kind == "chest" and db.version == 2 and db.settings.chests == true, "upgrade turns chests on")
-- a later reload keeps the player's own choice
db.settings.chests = false; frames = { UIParent, GameTooltip, WorldMapFrame, canvas, Minimap }; local ns3 = {}
for _, file in ipairs(FILES) do assert(loadfile(dir .. "/" .. file))("NodeNotes", ns3) end
fire("ADDON_LOADED", "NodeNotes"); assert(db.settings.chests == false and db.sessions == 3)
local m, ln = ns2.FindLast(); assert(m == 224 and ln ~= nil)

for _, l in ipairs(out) do realprint(l) end
realprint("NODENOTES HARNESS OK")
