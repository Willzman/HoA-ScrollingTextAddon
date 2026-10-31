-- Scroll areas: pools of font strings that rise (or fall) from an anchor point, plus "sticky"
-- crits that pop in the middle of their area, hold, then fade.

local HST = HoAScrollingText
local Display = {}
HST.Display = Display

local MAX_NORMAL = 24
local MAX_STICKY = 6
local GAP = 4
local STICKY_LIFE = 1.6
local STICKY_FADE = 0.5
local POW_GROW = 0.07
local POW_SHRINK = 0.18
local POW_SCALE = 1.6
local FADE_IN = 0.05
local FADE_OUT = 0.3
local MOVER_WIDTH = 170
local ICON_GAP = 3
-- Trim the border every 1.12 icon has baked in.
local ICON_TRIM = 0.07

local holder = CreateFrame("Frame", "HoAScrollingTextFrame", UIParent)
holder:SetFrameStrata("HIGH")
holder:SetAllPoints(UIParent)
holder:EnableMouse(false)
holder:Hide()

local active = {}
local spare = {}
local movers = {}

local function SetSize(text, size)
    if text.SetTextHeight then
        text:SetTextHeight(size)
    else
        text:SetFont(HST.db.font, size, HST.db.outline)
    end
    if text.hasIcon then
        text.icon:SetWidth(size)
        text.icon:SetHeight(size)
    end
end

local function Acquire()
    local text = tremove(spare)
    if not text then
        text = holder:CreateFontString(nil, "OVERLAY")
        text.icon = holder:CreateTexture(nil, "OVERLAY")
        text.icon:SetTexCoord(ICON_TRIM, 1 - ICON_TRIM, ICON_TRIM, 1 - ICON_TRIM)
        text.icon:SetPoint("RIGHT", text, "LEFT", -ICON_GAP, 0)
        text.icon:Hide()
    end
    return text
end

local function Release(index)
    local text = tremove(active, index)
    text:Hide()
    text.icon:Hide()
    text.hasIcon = nil
    text.area = nil
    tinsert(spare, text)
end

local function CountIn(areaKey, sticky)
    local count, oldest, oldestBorn = 0, nil, nil
    for index, text in ipairs(active) do
        if text.area == areaKey and text.sticky == sticky then
            count = count + 1
            if not oldestBorn or text.born < oldestBorn then
                oldest, oldestBorn = index, text.born
            end
        end
    end
    return count, oldest
end

-- How far a text has travelled from its start, in pixels, along its area's direction.
local function Travel(text, area, now)
    if text.sticky then
        return text.offset
    end
    local progress = (now - text.born) / text.duration
    return progress * area.height + text.offset
end

-- Keep a new line from landing on top of the last one: if the newest text in the area has not
-- yet moved a line's height, push everything up by the difference.
local function MakeRoom(areaKey, area, sticky, spacing, now)
    local nearest
    for _, text in ipairs(active) do
        if text.area == areaKey and text.sticky == sticky then
            local travel = Travel(text, area, now)
            if not nearest or travel < nearest then
                nearest = travel
            end
        end
    end
    if nearest and nearest < spacing then
        local shift = spacing - nearest
        for _, text in ipairs(active) do
            if text.area == areaKey and text.sticky == sticky then
                text.offset = text.offset + shift
            end
        end
    end
end

local function Place(text, area, now)
    local age = now - text.born
    local x, y, alpha = area.x, area.y, area.alpha or 1
    if text.sticky then
        y = y + area.direction * (area.height * 0.5 + text.offset)
        if age > text.duration - STICKY_FADE then
            alpha = alpha * (text.duration - age) / STICKY_FADE
        end
        if age < POW_GROW then
            SetSize(text, text.size * (1 + (POW_SCALE - 1) * age / POW_GROW))
        elseif age < POW_GROW + POW_SHRINK then
            SetSize(text, text.size * (POW_SCALE - (POW_SCALE - 1) * (age - POW_GROW) / POW_SHRINK))
        elseif not text.settled then
            SetSize(text, text.size)
            text.settled = true
        end
    else
        local progress = age / text.duration
        y = y + area.direction * (progress * area.height + text.offset)
        if area.style == "parabola" then
            x = x + (area.curve or 0) * 4 * progress * (1 - progress)
        end
        if progress < FADE_IN then
            alpha = alpha * progress / FADE_IN
        elseif progress > 1 - FADE_OUT then
            alpha = alpha * (1 - progress) / FADE_OUT
        end
    end
    if alpha < 0 then
        alpha = 0
    end
    -- Left-aligned text keeps its icon inside the area: the icon sits on the anchor.
    if text.hasIcon and area.align == "LEFT" then
        x = x + text.size + ICON_GAP
    end
    text:ClearAllPoints()
    text:SetPoint(area.align, UIParent, "CENTER", x, y)
    text:SetAlpha(alpha)
    if text.hasIcon then
        text.icon:SetAlpha(alpha)
    end
end

holder:SetScript("OnUpdate", function()
    local now = GetTime()
    local areas = HST.db.areas
    local index = 1
    while index <= table.getn(active) do
        local text = active[index]
        local area = areas[text.area]
        local age = now - text.born
        if not area or age >= text.duration or Travel(text, area, now) > area.height * 1.6 then
            Release(index)
        else
            Place(text, area, now)
            index = index + 1
        end
    end
    if table.getn(active) == 0 then
        this:Hide()
    end
end)

-- Show `message` in scroll area `areaKey`. `sticky` makes it a crit-style pop; `icon` is a
-- texture path shown left of the text.
function Display.Add(areaKey, message, r, g, b, sticky, size, icon)
    local db = HST.db
    local area = db.areas[areaKey]
    if not area or not message then
        return
    end
    sticky = sticky and true or false
    size = size or (sticky and db.critSize or db.fontSize)
    local now = GetTime()

    local count, oldest = CountIn(areaKey, sticky)
    if count >= (sticky and MAX_STICKY or MAX_NORMAL) and oldest then
        Release(oldest)
    end
    MakeRoom(areaKey, area, sticky, size + GAP, now)

    local text = Acquire()
    text:SetFont(db.font, size, db.outline)
    text:SetJustifyH(area.align)
    text:SetText(message)
    text:SetTextColor(r or 1, g or 1, b or 1)
    text.area = areaKey
    text.sticky = sticky
    text.size = size
    text.settled = false
    text.born = now
    text.offset = 0
    text.duration = sticky and STICKY_LIFE or area.duration
    text.hasIcon = icon and true or nil
    if icon then
        text.icon:SetTexture(icon)
        text.icon:SetWidth(size)
        text.icon:SetHeight(size)
        text.icon:Show()
    else
        text.icon:Hide()
    end
    tinsert(active, text)
    Place(text, area, now)
    text:Show()
    holder:Show()
end

function Display.Clear()
    while table.getn(active) > 0 do
        Release(1)
    end
end

-- Unlock mode: a box per area that can be dragged to move it.

local function SaveMover(mover)
    local area = HST.db.areas[mover.areaKey]
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    local left, right = mover:GetLeft(), mover:GetRight()
    if area.align == "LEFT" then
        area.x = floor(left - halfW + 0.5)
    elseif area.align == "RIGHT" then
        area.x = floor(right - halfW + 0.5)
    else
        area.x = floor((left + right) / 2 - halfW + 0.5)
    end
    if area.direction > 0 then
        area.y = floor(mover:GetBottom() - halfH + 0.5)
    else
        area.y = floor(mover:GetTop() - halfH + 0.5)
    end
end

local function PlaceMover(mover)
    local area = HST.db.areas[mover.areaKey]
    mover:ClearAllPoints()
    mover:SetWidth(MOVER_WIDTH)
    mover:SetHeight(area.height)
    local vertical = area.direction > 0 and "BOTTOM" or "TOP"
    local horizontal = area.align == "CENTER" and "" or area.align
    mover:SetPoint(vertical .. horizontal, UIParent, "CENTER", area.x, area.y)
end

local function Mover(areaKey)
    local mover = CreateFrame("Frame", "HoAScrollingTextMover" .. areaKey, UIParent)
    mover.areaKey = areaKey
    mover:SetFrameStrata("DIALOG")
    mover:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    mover:SetBackdropColor(0.1, 0.3, 0.6, 0.45)
    mover:SetBackdropBorderColor(0.4, 0.7, 1, 0.9)
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    mover:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        SaveMover(this)
        PlaceMover(this)
    end)
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", mover, "CENTER", 0, 0)
    label:SetText(HST.AREA_LABELS[areaKey] .. "\n|cffaaaaaadrag to move|r")
    mover:Hide()
    return mover
end

function Display.SetUnlocked(unlocked)
    Display.unlocked = unlocked
    for _, areaKey in ipairs(HST.AREA_ORDER) do
        if not movers[areaKey] then
            movers[areaKey] = Mover(areaKey)
        end
        local mover = movers[areaKey]
        if unlocked then
            PlaceMover(mover)
            mover:Show()
        else
            mover:Hide()
        end
    end
end

function Display.RefreshMovers()
    if Display.unlocked then
        Display.SetUnlocked(true)
    end
end
