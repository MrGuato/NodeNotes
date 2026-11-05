-- Minimap pins for the nodes in your current zone.
--
-- A node's map position is turned into a distance in yards from the player,
-- then into an offset on the minimap. Pins beyond the minimap's view radius
-- are hidden. Pins show a tooltip but let clicks pass through, so pinging the
-- minimap still works on top of them. A square minimap (from a UI addon that
-- defines GetMinimapShape) keeps pins out to its corners.

local _, ns = ...

local Mini = {}
ns.Mini = Mini

local PIN_SIZE = 12
local INTERVAL = 0.1     -- seconds between position updates
local EDGE = 0.92        -- hide pins this close to the minimap rim

local pins = {}
local driver
local elapsed = 0

local function secret(v)
    local f = rawget(_G, "issecretvalue")
    if type(f) ~= "function" then
        return false
    end
    local ok, res = pcall(f, v)
    return ok and res == true
end

local function onEnter(self)
    local node = self.node
    if not node then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(node.name or "Node")
    if node.loot and #node.loot > 0 then
        GameTooltip:AddLine("Last yield: " .. ns.LootText(node.loot), 1, 1, 1, true)
    elseif node.lootText and node.lootText ~= "" then
        GameTooltip:AddLine("Last yield: " .. node.lootText, 1, 1, 1, true)
    end
    if node.kind == "rare" and not node.last then
        GameTooltip:AddLine("Seen " .. ns.Ago(node.seen), 1, 1, 1)
    else
        GameTooltip:AddLine("Last visited " .. ns.Ago(node.last), 1, 1, 1)
    end
    if node.note and node.note ~= "" then
        GameTooltip:AddLine(node.note, 1, 0.82, 0, true)
    end
    if self.friend then
        GameTooltip:AddLine("Shared by " .. (node.from or "a friend"), 0.4, 0.7, 1)
    end
    GameTooltip:Show()
end

local function onLeave()
    GameTooltip:Hide()
end

local function acquire(index)
    local pin = pins[index]
    if pin then
        return pin
    end
    pin = CreateFrame("Frame", nil, Minimap)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    pin.icon = pin:CreateTexture(nil, "OVERLAY")
    pin.icon:SetAllPoints()
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin:EnableMouse(true)
    if pin.SetMouseClickEnabled then
        pin:SetMouseClickEnabled(false)
    end
    pin:SetScript("OnEnter", onEnter)
    pin:SetScript("OnLeave", onLeave)
    pin:Hide()
    pins[index] = pin
    return pin
end

local function hideFrom(index)
    for i = index, #pins do
        pins[i]:Hide()
        pins[i].node = nil
    end
end

-- Offset of a node from the minimap centre, in minimap pixels (x right, y up).
-- Returns nil when the node is outside the view radius, or outside the square
-- when the minimap is square.
function Mini.Offset(dxYards, dyYards, facing, viewRadius, pixelRadius, square)
    -- Map y grows southward; screen y grows upward.
    local east, north = dxYards, -dyYards
    local x, y = east, north
    if facing then
        -- A rotating minimap turns the world so the way you face is up.
        local sin, cos = math.sin(facing), math.cos(facing)
        x = east * cos + north * sin
        y = -east * sin + north * cos
    end
    if square then
        local limit = viewRadius * EDGE
        if math.abs(x) > limit or math.abs(y) > limit then
            return nil
        end
    elseif (x * x + y * y) > (viewRadius * EDGE) ^ 2 then
        return nil
    end
    return x / viewRadius * pixelRadius, y / viewRadius * pixelRadius
end

function Mini.Update()
    local settings = ns.Settings()
    if not settings or not settings.minimap or not Minimap:IsVisible() then
        hideFrom(1)
        return
    end
    local mapID, px, py = ns.PlayerPosition()
    local nodes = ns.NodesForMap(mapID)
    local friends = (mapID and settings.friends and ns.FriendNodes()[mapID]) or {}
    if not mapID or (#nodes == 0 and #friends == 0) then
        hideFrom(1)
        return
    end

    local width, height = C_Map.GetMapWorldSize(mapID)
    local viewRadius = C_Minimap.GetViewRadius()
    if not width or not height or width <= 0 or height <= 0 or not viewRadius or secret(viewRadius) or viewRadius <= 0 then
        hideFrom(1)
        return
    end

    local facing
    if GetCVar("rotateMinimap") == "1" then
        facing = GetPlayerFacing()
        if not facing or secret(facing) then
            hideFrom(1)   -- cannot place pins on a rotating map without a heading
            return
        end
    end

    local shape = rawget(_G, "GetMinimapShape")
    local square = type(shape) == "function" and shape() == "SQUARE"
    local pixelRadius = Minimap:GetWidth() / 2
    local used = 0
    local function place(node, friend)
        local x, y = Mini.Offset((node.x - px) * width, (node.y - py) * height, facing, viewRadius, pixelRadius, square)
        if x then
            used = used + 1
            local pin = acquire(used)
            pin.node, pin.friend = node, friend
            pin.icon:SetTexture(ns.IconFor(node))
            pin.icon:SetDesaturated(friend)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
            pin:Show()
        end
    end
    for i = 1, #friends do
        local node = friends[i]
        if not ns.FindMatch(nodes, node.kind, node.x, node.y, node.npc) then
            place(node, true)
        end
    end
    for i = 1, #nodes do
        place(nodes[i], false)
    end
    hideFrom(used + 1)
end

-- Node data or settings changed: redraw on the next frame.
function Mini.Refresh()
    elapsed = INTERVAL
end

function Mini.Init()
    if driver or type(Minimap) ~= "table" then
        return
    end
    if not (C_Map.GetMapWorldSize and C_Minimap and C_Minimap.GetViewRadius) then
        return   -- this client cannot tell us distances; leave minimap pins off
    end
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= INTERVAL then
            elapsed = 0
            Mini.Update()
        end
    end)
end

function Mini.PinCount()
    local shown = 0
    for i = 1, #pins do
        if pins[i]:IsShown() then
            shown = shown + 1
        end
    end
    return shown
end
