-- World map pins.
--
-- Pins are plain frames parented to the world map's canvas and positioned by
-- hand. The addon only listens to the map through secure hooks, so it does not
-- replace or interfere with any of the map's own code.
--
-- A map shows its own nodes, the nodes of the zones and caves inside it (so a
-- continent shows every zone at once, with smaller pins), and nodes your
-- friends shared that you do not already have.

local _, ns = ...

local Map = {}
ns.Map = Map

local PIN_SIZE = 18
local CHILD_SCALE = 0.7     -- pins from a zone shown on its continent
-- Ring colour for a node that has given you something special.
local QUALITY_COLOR = {
    [3] = { 0.0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.0, 0.5, 0.0 },
}

local canvas
local pins = {}
local ready = false

local function onEnter(self)
    local node = self.node
    if not node then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(node.name or "Node")
    if self.friend then
        local lines = ns.Share.Describe(node, self.mapID)
        for i = 2, #lines do
            GameTooltip:AddLine(lines[i], 1, 1, 1, true)
        end
        if node.note and node.note ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(node.note, 1, 0.82, 0, true)
        end
        GameTooltip:AddLine("Shared by " .. (node.from or "a friend"), 0.4, 0.7, 1)
        GameTooltip:Show()
        return
    end
    local lines = ns.Describe(node, self.mapID)
    for i = 2, #lines do
        GameTooltip:AddLine(lines[i], 1, 1, 1, true)
    end
    if node.note and node.note ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(node.note, 1, 0.82, 0, true)
    end
    GameTooltip:AddLine("Click to write a note", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function onLeave()
    GameTooltip:Hide()
end

local function onClick(self)
    if self.node and not self.friend then
        ns.Note.Open(self.mapID, self.node)
    end
end

local function pinLevel()
    local level = canvas:GetFrameLevel() + 500
    local ok, managed = pcall(function()
        return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
    end)
    if ok and type(managed) == "number" then
        level = managed
    end
    return level
end

local function acquire(index)
    local pin = pins[index]
    if pin then
        return pin
    end
    pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:RegisterForClicks("LeftButtonUp")

    -- Coloured ring behind the icon for a node that gave you a blue or better.
    pin.ring = pin:CreateTexture(nil, "BACKGROUND")
    pin.ring:SetPoint("TOPLEFT", -2, 2)
    pin.ring:SetPoint("BOTTOMRIGHT", 2, -2)

    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Gold corner marks a node that has a note.
    pin.mark = pin:CreateTexture(nil, "OVERLAY")
    pin.mark:SetSize(7, 7)
    pin.mark:SetPoint("TOPRIGHT", 2, 2)
    pin.mark:SetColorTexture(1, 0.82, 0, 1)

    -- Blue corner marks a node a friend shared.
    pin.badge = pin:CreateTexture(nil, "OVERLAY")
    pin.badge:SetSize(7, 7)
    pin.badge:SetPoint("BOTTOMLEFT", -2, -2)
    pin.badge:SetColorTexture(0.3, 0.65, 1, 1)

    pin:SetScript("OnEnter", onEnter)
    pin:SetScript("OnLeave", onLeave)
    pin:SetScript("OnClick", onClick)
    pins[index] = pin
    return pin
end

-- Your nodes and your friends' nodes that belong on the viewed map, with their
-- position on it.
function Map.Collect(viewed, settings)
    local out = {}
    local function add(sourceMap, list, friend)
        local rect
        if sourceMap ~= viewed then
            rect = ns.RectOn(sourceMap, viewed)
            if not rect then
                return
            end
        end
        local own = friend and ns.NodesForMap(sourceMap)
        for i = 1, #list do
            local node = list[i]
            if not (own and ns.FindMatch(own, node.kind, node.x, node.y, node.npc)) then
                local x, y = node.x, node.y
                if rect then
                    x = rect[1] + x * (rect[2] - rect[1])
                    y = rect[3] + y * (rect[4] - rect[3])
                end
                out[#out + 1] = { node = node, mapID = sourceMap, x = x, y = y, friend = friend, child = rect ~= nil }
            end
        end
    end
    if settings.friends then
        for mapID, list in pairs(ns.FriendNodes()) do
            if mapID == viewed or settings.continent then
                add(mapID, list, true)
            end
        end
    end
    for mapID, list in pairs(ns.AllNodes()) do
        if mapID == viewed or settings.continent then
            add(mapID, list, false)
        end
    end
    return out
end

function Map.Refresh()
    if not ready then
        return
    end
    for i = 1, #pins do
        pins[i]:Hide()
        pins[i].node = nil
    end
    local settings = ns.Settings()
    if not settings or not settings.pins or not WorldMapFrame:IsShown() then
        return
    end

    local mapID = WorldMapFrame:GetMapID()
    local entries = Map.Collect(mapID, settings)
    if #entries == 0 then
        return
    end

    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local canvasScale = canvas:GetScale()
    if not canvasScale or canvasScale <= 0 then
        canvasScale = 1
    end
    local level = pinLevel()

    for i = 1, #entries do
        local entry = entries[i]
        local node = entry.node
        local pin = acquire(i)
        pin.node, pin.mapID, pin.friend = node, entry.mapID, entry.friend
        -- Counter the canvas zoom so pins stay the same size on screen.
        local scale = (entry.child and CHILD_SCALE or 1) / canvasScale
        -- Your own pins sit above your friends' pins.
        pin:SetFrameLevel(level + (entry.friend and 0 or 1))
        pin:SetScale(scale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", (entry.x * width) / scale, -(entry.y * height) / scale)
        pin.icon:SetTexture(ns.IconFor(node))
        local color = QUALITY_COLOR[node.best or 0]
        if color then
            pin.ring:SetColorTexture(color[1], color[2], color[3], 1)
            pin.ring:Show()
        else
            pin.ring:Hide()
        end
        if node.note and node.note ~= "" then
            pin.mark:Show()
        else
            pin.mark:Hide()
        end
        if entry.friend then
            pin.badge:Show()
        else
            pin.badge:Hide()
        end
        pin:Show()
    end
end

local function attach()
    if ready or type(WorldMapFrame) ~= "table" or type(WorldMapFrame.GetCanvas) ~= "function" then
        return false
    end
    canvas = WorldMapFrame:GetCanvas()
    if not canvas then
        return false
    end
    ready = true
    WorldMapFrame:HookScript("OnShow", Map.Refresh)
    for _, method in ipairs({ "OnMapChanged", "OnCanvasScaleChanged" }) do
        if type(WorldMapFrame[method]) == "function" then
            hooksecurefunc(WorldMapFrame, method, Map.Refresh)
        end
    end
    Map.Refresh()
    return true
end

function Map.Init()
    if attach() then
        return
    end
    -- The world map can load on demand. Wait for it.
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:SetScript("OnEvent", function(self)
        if attach() then
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

function Map.PinCount()
    local shown = 0
    for i = 1, #pins do
        if pins[i]:IsShown() then
            shown = shown + 1
        end
    end
    return shown
end
