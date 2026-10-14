-- World map pins.
--
-- Pins are plain frames parented to the world map's canvas and positioned by
-- hand. The addon only listens to the map through secure hooks, so it does not
-- replace or interfere with any of the map's own code.

local _, ns = ...

local Map = {}
ns.Map = Map

local PIN_SIZE = 18
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

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
    if self.node then
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

    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Gold corner marks a node that has a note.
    pin.mark = pin:CreateTexture(nil, "OVERLAY")
    pin.mark:SetSize(7, 7)
    pin.mark:SetPoint("TOPRIGHT", 2, 2)
    pin.mark:SetColorTexture(1, 0.82, 0, 1)

    pin:SetScript("OnEnter", onEnter)
    pin:SetScript("OnLeave", onLeave)
    pin:SetScript("OnClick", onClick)
    pins[index] = pin
    return pin
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
    local nodes = ns.NodesForMap(mapID)
    if #nodes == 0 then
        return
    end

    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local canvasScale = canvas:GetScale()
    if not canvasScale or canvasScale <= 0 then
        canvasScale = 1
    end
    -- Counter the canvas zoom so pins stay the same size on screen.
    local scale = 1 / canvasScale
    local level = pinLevel()

    for i = 1, #nodes do
        local node = nodes[i]
        local pin = acquire(i)
        pin.node, pin.mapID = node, mapID
        pin:SetFrameLevel(level)
        pin:SetScale(scale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", (node.x * width) / scale, -(node.y * height) / scale)
        pin.icon:SetTexture(node.icon or FALLBACK_ICON)
        if node.note and node.note ~= "" then
            pin.mark:Show()
        else
            pin.mark:Hide()
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
