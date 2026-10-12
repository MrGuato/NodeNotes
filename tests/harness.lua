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
C_Map = {
  GetMapWorldSize = function() return 4000, 3000 end,
  GetBestMapForUnit = function() return pos.map end,
  GetPlayerMapPosition = function() if not pos.x then return nil end return { GetXY = function() return pos.x, pos.y end } end,
  GetMapInfo = function(id) return { name = id == 224 and "Stranglethorn Vale" or ("Zone" .. id) } end,
}
local spells = { [2366] = "Herb Gathering", [2575] = "Mining", [133] = "Fireball", [3365] = "Opening" }
C_Spell = { GetSpellName = function(id) return spells[id] end }

-- loot window
local loot = {}
function GetNumLootItems() return #loot end
function GetLootSlotInfo(i) local l = loot[i]; return l.icon, l.name, l.qty end
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
local FILES = { "Core.lua", "Note.lua", "Map.lua", "Minimap.lua" }
for _, file in ipairs(FILES) do
  assert(loadfile(dir .. "/" .. file))("NodeNotes", ns)
end
local function tick() for i = 1, #frames do local f = frames[i]; if f._scripts.OnUpdate then f._scripts.OnUpdate(f, 1) end end end
fire("ADDON_LOADED", "Other"); assert(NodeNotesDB == nil)
fire("ADDON_LOADED", "NodeNotes"); fire("PLAYER_LOGIN")
local db = NodeNotesDB
assert(db.sessions == 1 and db.settings.pins == true and db.settings.chests == false)
assert(db.settings.minimap == true and db.settings.debug == false)
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
advance(60)
openLoot({ { name = "Linen Cloth", qty = 2, guid = "Creature-0-3299-0-36-1234-00005E1234" } })          -- mob loot
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 133); openLoot({ { name = "Wool Cloth", qty = 1 } })    -- non-gather cast
openLoot({ { name = "Silk Cloth", qty = 1, guid = "GameObject-0-3299-0-36-99-00005E1234" } })           -- chest, chests off
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2366); advance(30); openLoot({ { name = "Stale", qty = 1 } }) -- cast too old
fishing = true; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2366); openLoot({ { name = "Fish", qty = 1 } }); fishing = false
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "c", 2366); openLoot({ { name = "NotMine", qty = 1 } })      -- someone else
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", SECRET); openLoot({ { name = "Hidden", qty = 1 } })    -- secret spell id
pos.x = nil; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2366); openLoot({ { name = "Indoors", qty = 1 } }); pos.x = 0.40 -- no map position
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2366); openLoot({ { name = SECRET, qty = 1 } })          -- secret loot name
assert(#list == before, "recorded something it should not have: " .. #list .. " vs " .. before)

-- 7. chests on: object loot without a gather cast is recorded as other
slash("chests on"); pos.x, pos.y = 0.10, 0.10
openLoot({ { name = "Silk Cloth", qty = 1, guid = "GameObject-0-3299-0-36-99-00005E1234" } })
assert(#list == before + 1 and list[#list].kind == "other" and list[#list].name == "Silk Cloth")
slash("chests off")

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

-- 13. a reload keeps the data and bumps the session counter
frames = { UIParent, GameTooltip, WorldMapFrame, canvas, Minimap }; local ns2 = {}
for _, file in ipairs(FILES) do assert(loadfile(dir .. "/" .. file))("NodeNotes", ns2) end
fire("ADDON_LOADED", "NodeNotes")
assert(NodeNotesDB == db and db.sessions == 2 and #db.nodes[224] == #list)
local m, ln = ns2.FindLast(); assert(m == 224 and ln ~= nil)

for _, l in ipairs(out) do realprint(l) end
realprint("NODENOTES HARNESS OK")
