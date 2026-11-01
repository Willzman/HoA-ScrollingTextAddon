-- HoA Scrolling Text: shared namespace, saved settings and small helpers.
-- Written for the 1.12.1 grammar the Hordes of Azeroth client runs (Lua 5.0 style:
-- `this`, `event` and `arg1` globals, no `#` operator, no varargs `...`).

HoAScrollingText = {}
local HST = HoAScrollingText

HST.VERSION = "0.1.0"
HST.CHAT_PREFIX = "|cff66ccffHoA Scrolling Text|r: "

HST.FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri", path = "Fonts\\skurri.ttf" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
}

HST.OUTLINES = { "", "OUTLINE", "THICKOUTLINE" }

-- Every toggle the options window and `/hst toggle` know about, in display order.
HST.CATEGORIES = {
    { key = "outDamage", label = "Outgoing damage" },
    { key = "outDot", label = "Outgoing damage over time" },
    { key = "outMiss", label = "Outgoing misses" },
    { key = "outHeal", label = "Outgoing heals" },
    { key = "pet", label = "Pet and guardian damage" },
    { key = "inDamage", label = "Incoming damage" },
    { key = "inMiss", label = "Incoming misses" },
    { key = "inHeal", label = "Incoming heals" },
    { key = "power", label = "Power gains" },
    { key = "buffGain", label = "Buff gains" },
    { key = "buffFade", label = "Buff fades" },
    { key = "debuff", label = "Debuffs" },
    { key = "kills", label = "Killing blows" },
    { key = "combat", label = "Entering and leaving combat" },
    { key = "lowHealth", label = "Low health warning" },
}

HST.AREA_ORDER = { "incoming", "outgoing", "notification" }
HST.AREA_LABELS = { incoming = "Incoming", outgoing = "Outgoing", notification = "Notification" }

HST.DEFAULTS = {
    enabled = true,
    font = "Fonts\\FRIZQT__.TTF",
    outline = "THICKOUTLINE",
    fontSize = 18,
    critSize = 26,
    -- Seconds to gather hits of one spell into a single number; 0 shows every hit.
    -- Hordes of Azeroth fires a lot of AoE, so merging keeps the screen readable.
    mergeWindow = 0.4,
    showSpellNames = true,
    -- Spell icons from the game's damage meter data, shown before the spell name.
    showIcons = true,
    iconReplacesName = false,
    -- Normal lines fade out while they pass behind a crit.
    critFocus = true,
    -- 12.3k, 250k, 9.2m instead of 12,345, 250,400, 9,210,000.
    shortNumbers = true,
    showTargets = false,
    -- Outgoing hits below this are dropped before merging into the screen.
    minOutgoing = 0,
    minIncoming = 0,
    lowHealthPercent = 30,
    -- Show each hit under the name of the weapon behind it ("Call Pet" for your pet's bites).
    weaponNames = true,
    -- Summons show their own icon (Imp, Infernal, Cat...) rather than their weapon's.
    summonIcons = true,
    -- Combat log spell or creature name -> weapon name, learned from the damage meter (Icons.lua).
    learnedWeapons = {},
    -- Out of the box: your own spells and what they hit for. The game already shows incoming
    -- damage and has its own warnings, so the rest starts off; turn it on in /hst.
    categories = {
        outDamage = true, outDot = true, outMiss = false, outHeal = true, pet = true,
        inDamage = false, inMiss = false, inHeal = false, power = false,
        buffGain = false, buffFade = false, debuff = false, kills = false,
        combat = false, lowHealth = false,
    },
    areas = {
        incoming = {
            x = -170, y = -30, height = 220, duration = 2.6, direction = 1,
            style = "parabola", curve = -60, align = "RIGHT", alpha = 1,
        },
        outgoing = {
            x = 170, y = -30, height = 220, duration = 2.6, direction = 1,
            style = "parabola", curve = 60, align = "LEFT", alpha = 1,
        },
        notification = {
            x = 0, y = 160, height = 90, duration = 3, direction = 1,
            style = "straight", curve = 0, align = "CENTER", alpha = 1,
        },
    },
}

local function Copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = Copy(v)
    end
    return out
end
HST.Copy = Copy

-- Fill in anything missing from `saved` with the default, recursively, so new settings in an
-- update show up without wiping the player's old ones.
local function Merge(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = Copy(v)
        elseif type(v) == "table" and type(saved[k]) == "table" then
            Merge(saved[k], v)
        end
    end
    return saved
end

function HST.LoadSettings()
    if type(HoAScrollingTextDB) ~= "table" then
        HoAScrollingTextDB = {}
    end
    HST.db = Merge(HoAScrollingTextDB, HST.DEFAULTS)
end

function HST.ResetSettings()
    HoAScrollingTextDB = Copy(HST.DEFAULTS)
    HST.db = HoAScrollingTextDB
end

function HST.Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(HST.CHAT_PREFIX .. message)
    end
end

local SHORT_UNITS = { { 1000000000, "b" }, { 1000000, "m" }, { 1000, "k" } }

-- 950 -> "950", 12345 -> "12.3k", 250400 -> "250k", 9210000 -> "9.2m". One decimal below 100
-- of a unit, none above; 999,960 rounds up to "1m", not "1000k".
function HST.Short(number)
    local sign = ""
    if number < 0 then
        sign, number = "-", -number
    end
    for index, unit in ipairs(SHORT_UNITS) do
        local value = number / unit[1]
        if value >= 0.9995 then
            local text
            if value >= 99.95 then
                text = format("%d", floor(value + 0.5))
            else
                text = gsub(format("%.1f", floor(value * 10 + 0.5) / 10), "%.0$", "")
            end
            if tonumber(text) >= 1000 and index > 1 then
                local bigger = SHORT_UNITS[index - 1]
                text = gsub(format("%.1f", floor(number / bigger[1] * 10 + 0.5) / 10), "%.0$", "")
                return sign .. text .. bigger[2]
            end
            return sign .. text .. unit[2]
        end
    end
    return sign .. format("%d", floor(number + 0.5))
end

-- An amount as the player chose to see it: short ("12.3k") or in full ("12,345").
function HST.Number(number)
    if HST.db and HST.db.shortNumbers then
        return HST.Short(number)
    end
    return HST.Comma(number)
end

-- 1234567 -> "1,234,567"
function HST.Comma(number)
    local text = format("%d", number)
    local count
    repeat
        text, count = gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
    until count == 0
    return text
end

function HST.Enabled(category)
    local db = HST.db
    return db and db.enabled and db.categories[category]
end
