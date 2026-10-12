-- The small window that opens when you click a node pin.

local ADDON, ns = ...

local Note = {}
ns.Note = Note

local frame, title, info, edit, deleteButton
local current   -- { mapID =, node = } being shown
local confirmDelete = false

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function commit()
    if current and edit then
        local text = edit:GetText() or ""
        if text ~= (current.node.note or "") then
            ns.SetNote(current.node, text)
        end
    end
end

local function build()
    frame = CreateFrame("Frame", "NodeNotesFrame", UIParent, "BackdropTemplate")
    frame:SetSize(310, 250)
    frame:SetPoint("CENTER", 0, 80)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.92)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetPoint("RIGHT", -32, 0)
    title:SetJustifyH("LEFT")

    info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    info:SetWidth(286)
    info:SetJustifyH("LEFT")
    info:SetJustifyV("TOP")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 10, -122)
    box:SetPoint("BOTTOMRIGHT", -10, 40)
    box:SetBackdrop(BACKDROP)
    box:SetBackdropColor(0.08, 0.08, 0.08, 1)
    box:EnableMouse(true)

    edit = CreateFrame("EditBox", nil, box)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetMaxLetters(240)
    edit:SetPoint("TOPLEFT", 8, -8)
    edit:SetPoint("RIGHT", -8, 0)
    edit:SetWidth(270)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    box:SetScript("OnMouseDown", function()
        edit:SetFocus()
    end)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 2, 3)
    label:SetText("Note")

    local save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    save:SetSize(84, 22)
    save:SetPoint("BOTTOMRIGHT", -10, 10)
    save:SetText("Save")
    save:SetScript("OnClick", function()
        frame:Hide()
    end)

    deleteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deleteButton:SetSize(110, 22)
    deleteButton:SetPoint("BOTTOMLEFT", 10, 10)
    deleteButton:SetText("Delete node")
    deleteButton:SetScript("OnClick", function()
        if not current then
            return
        end
        if not confirmDelete then
            confirmDelete = true
            deleteButton:SetText("Confirm delete")
            return
        end
        local target = current
        current = nil   -- so hiding does not write the note back
        ns.DeleteNode(target.mapID, target.node)
        frame:Hide()
    end)

    -- Closing by any route keeps what was typed.
    frame:SetScript("OnHide", function()
        commit()
        current = nil
    end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "NodeNotesFrame")
    end
end

local function fill()
    local node = current.node
    title:SetText(node.name or "Node")
    info:SetText(table.concat(ns.Describe(node, current.mapID), "\n"))
    confirmDelete = false
    deleteButton:SetText("Delete node")
end

function Note.Open(mapID, node)
    if not frame then
        build()
    end
    if current and current.node ~= node then
        commit()
    end
    current = { mapID = mapID, node = node }
    fill()
    edit:SetText(node.note or "")
    frame:Show()
end

-- Called when node data changes. Updates the stats, leaves the typed text alone.
function Note.Refresh()
    if frame and current and frame:IsShown() then
        fill()
    end
end

function Note.Current()
    return current
end
