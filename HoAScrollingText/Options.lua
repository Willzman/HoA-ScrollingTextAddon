-- Slash commands and the options window.

local HST = HoAScrollingText
local Options = {}
HST.Options = Options

local WIDTH, HEIGHT = 440, 560
local window

local function Apply()
    HST.Display.RefreshMovers()
    if window and window:IsShown() then
        Options.Refresh()
    end
end

local function FontName(path)
    for _, font in ipairs(HST.FONTS) do
        if font.path == path then
            return font.name
        end
    end
    return path
end

local function NextFont()
    local db = HST.db
    local index = 1
    for n, font in ipairs(HST.FONTS) do
        if font.path == db.font then
            index = n
        end
    end
    db.font = HST.FONTS[math.mod(index, table.getn(HST.FONTS)) + 1].path
    return FontName(db.font)
end

local function CheckBox(parent, label, x, y, get, set)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetWidth(24)
    box:SetHeight(24)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local text = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(label)
    box.get = get
    box:SetScript("OnClick", function()
        set(this:GetChecked() and true or false)
        Apply()
    end)
    return box
end

local sliderCount = 0
local function Slider(parent, label, x, y, low, high, step, get, set, show)
    sliderCount = sliderCount + 1
    local name = "HoAScrollingTextSlider" .. sliderCount
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetWidth(180)
    slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    local title = getglobal(name .. "Text")
    local lowText = getglobal(name .. "Low")
    local highText = getglobal(name .. "High")
    if lowText then
        lowText:SetText(show(low))
    end
    if highText then
        highText:SetText(show(high))
    end
    slider.get = get
    slider.Label = function(value)
        if title then
            title:SetText(label .. ": " .. show(value))
        end
    end
    slider:SetScript("OnValueChanged", function()
        local value = floor(this:GetValue() / step + 0.5) * step
        this.Label(value)
        if not this.refreshing then
            set(value)
            Apply()
        end
    end)
    return slider
end

local function Button(parent, label, width, x, y, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

local function Build()
    window = CreateFrame("Frame", "HoAScrollingTextOptions", UIParent)
    window:SetWidth(WIDTH)
    window:SetHeight(HEIGHT)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    window:SetFrameStrata("DIALOG")
    window:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    window:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
    end)
    window:Hide()
    tinsert(UISpecialFrames, "HoAScrollingTextOptions")

    local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", window, "TOP", 0, -18)
    title:SetText("HoA Scrolling Text")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6)

    local db = function()
        return HST.db
    end
    window.boxes = {}
    window.sliders = {}

    tinsert(window.boxes, CheckBox(window, "Enabled", 24, -46,
        function() return db().enabled end, function(v) db().enabled = v end))
    tinsert(window.boxes, CheckBox(window, "Show spell names", 160, -46,
        function() return db().showSpellNames end, function(v) db().showSpellNames = v end))
    tinsert(window.boxes, CheckBox(window, "Show targets", 300, -46,
        function() return db().showTargets end, function(v) db().showTargets = v end))

    local header = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", window, "TOPLEFT", 26, -80)
    header:SetText("Show")

    for index, category in ipairs(HST.CATEGORIES) do
        local column = math.mod(index - 1, 2)
        local row = floor((index - 1) / 2)
        local key = category.key
        tinsert(window.boxes, CheckBox(window, category.label, 24 + column * 200, -98 - row * 24,
            function() return db().categories[key] end,
            function(v) db().categories[key] = v end))
    end

    local top = -98 - (floor((table.getn(HST.CATEGORIES) + 1) / 2)) * 24 - 24
    tinsert(window.sliders, Slider(window, "Text size", 30, top, 10, 40, 1,
        function() return db().fontSize end, function(v) db().fontSize = v end,
        function(v) return format("%d", v) end))
    tinsert(window.sliders, Slider(window, "Crit size", 230, top, 12, 56, 1,
        function() return db().critSize end, function(v) db().critSize = v end,
        function(v) return format("%d", v) end))
    tinsert(window.sliders, Slider(window, "Merge window", 30, top - 46, 0, 1.5, 0.05,
        function() return db().mergeWindow end, function(v) db().mergeWindow = v end,
        function(v) return v <= 0 and "off" or format("%.2fs", v) end))
    tinsert(window.sliders, Slider(window, "Hide hits below", 230, top - 46, 0, 2000, 25,
        function() return db().minOutgoing end, function(v) db().minOutgoing = v end,
        function(v) return format("%d", v) end))
    tinsert(window.sliders, Slider(window, "Low health warning", 30, top - 92, 5, 75, 5,
        function() return db().lowHealthPercent end, function(v) db().lowHealthPercent = v end,
        function(v) return format("%d%%", v) end))

    local buttons = top - 136
    window.lock = Button(window, "Unlock areas", 120, 24, buttons, function()
        HST.Display.SetUnlocked(not HST.Display.unlocked)
        Options.Refresh()
    end)
    Button(window, "Test", 90, 150, buttons, function()
        HST.Events.Test()
    end)
    window.font = Button(window, "Font", 170, 246, buttons, function()
        NextFont()
        Options.Refresh()
    end)
    Button(window, "Reset to defaults", 150, 24, buttons - 28, function()
        HST.ResetSettings()
        HST.Display.Clear()
        Apply()
        Options.Refresh()
        HST.Print("Settings reset.")
    end)
end

function Options.Refresh()
    if not window then
        return
    end
    for _, box in ipairs(window.boxes) do
        box:SetChecked(box.get() and 1 or nil)
    end
    for _, slider in ipairs(window.sliders) do
        slider.refreshing = true
        slider:SetValue(slider.get())
        slider.Label(slider.get())
        slider.refreshing = nil
    end
    window.lock:SetText(HST.Display.unlocked and "Lock areas" or "Unlock areas")
    window.font:SetText("Font: " .. FontName(HST.db.font))
end

function Options.Toggle()
    if not window then
        Build()
    end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        Options.Refresh()
    end
end

local HELP = {
    "/hst - open the options window",
    "/hst on | off - turn the addon on or off",
    "/hst unlock | lock - show the scroll areas so you can drag them",
    "/hst test - show some sample text",
    "/hst merge <seconds> - merge window for repeated hits (0 = off)",
    "/hst size <n> | critsize <n> - text sizes",
    "/hst min <n> - hide outgoing hits below n",
    "/hst names - show or hide spell names",
    "/hst show - list what can be shown; /hst show <name> toggles it",
    "/hst reset - back to default settings",
}

local function SetNumber(field, value, low, high, label)
    local number = tonumber(value)
    if not number then
        HST.Print(label .. " is " .. tostring(HST.db[field]) .. ".")
        return
    end
    if number < low then
        number = low
    elseif number > high then
        number = high
    end
    HST.db[field] = number
    HST.Print(label .. " set to " .. number .. ".")
    Apply()
end

local function Slash(input)
    local _, _, command, rest = strfind(input or "", "^%s*(%S*)%s*(.-)%s*$")
    command = strlower(command or "")
    local db = HST.db
    if command == "" or command == "config" or command == "options" then
        Options.Toggle()
    elseif command == "help" then
        for _, line in ipairs(HELP) do
            HST.Print(line)
        end
    elseif command == "on" or command == "off" then
        db.enabled = command == "on"
        if not db.enabled then
            HST.Display.Clear()
        end
        HST.Print(db.enabled and "On." or "Off.")
        Apply()
    elseif command == "unlock" or command == "lock" then
        HST.Display.SetUnlocked(command == "unlock")
        HST.Print(command == "unlock" and "Areas unlocked: drag them, then /hst lock." or "Areas locked.")
        Apply()
    elseif command == "test" then
        HST.Events.Test()
    elseif command == "merge" then
        SetNumber("mergeWindow", rest, 0, 3, "Merge window")
    elseif command == "size" then
        SetNumber("fontSize", rest, 8, 48, "Text size")
    elseif command == "critsize" then
        SetNumber("critSize", rest, 8, 64, "Crit size")
    elseif command == "min" then
        SetNumber("minOutgoing", rest, 0, 1000000, "Minimum outgoing hit")
    elseif command == "names" then
        db.showSpellNames = not db.showSpellNames
        HST.Print(db.showSpellNames and "Spell names shown." or "Spell names hidden.")
        Apply()
    elseif command == "show" then
        local wanted = strlower(rest or "")
        if wanted == "" then
            for _, category in ipairs(HST.CATEGORIES) do
                local state = db.categories[category.key] and "|cff00ff00on|r" or "|cffff4444off|r"
                HST.Print(category.key .. " (" .. category.label .. "): " .. state)
            end
            return
        end
        for _, category in ipairs(HST.CATEGORIES) do
            if strlower(category.key) == wanted then
                db.categories[category.key] = not db.categories[category.key]
                HST.Print(category.label .. ": " .. (db.categories[category.key] and "on" or "off"))
                Apply()
                return
            end
        end
        HST.Print("No category called '" .. rest .. "'. Type /hst show for the list.")
    elseif command == "reset" then
        HST.ResetSettings()
        HST.Display.Clear()
        Apply()
        HST.Print("Settings reset.")
    else
        HST.Print("Unknown command. Type /hst help.")
    end
end

function Options.Init()
    SLASH_HOASCROLLINGTEXT1 = "/hst"
    SLASH_HOASCROLLINGTEXT2 = "/hoast"
    SlashCmdList["HOASCROLLINGTEXT"] = Slash
end
