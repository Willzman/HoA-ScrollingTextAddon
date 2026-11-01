-- Spell icons, taken from what the Hordes of Azeroth server tells its own damage meter.
--
-- The server sends the game's addon `BONK~` lines over CHAT_MSG_SYSTEM:
--   loadout~w:<icon>:<rank>:<max>,e:<icon>:...,p:<icon>:...~<slots>~<passive slots>
--   pw~<index>~<weapon name>~...           (one per weapon, in loadout order)
--   state~...~<damage>:<kills>,...~...     (field 13: per weapon damage, about once a second)
--   glyphinfo~<id>~<name>~<icon>~...
--   support~<icon>:<healed>:<absorbed>:<name>,...
--
-- A weapon's combat log lines carry the name of the spell it casts, which is usually the
-- weapon's name ("Frostbolt") but not always (Arcane Barrage casts Arcane Shot). The names
-- that don't match are learned: the per-weapon damage in each state line is compared with
-- the damage the combat log showed for each unknown spell name over the same second. When one
-- weapon's share lines up twice, the name gets that weapon's icon and is remembered.

local HST = HoAScrollingText
local Icons = {}
HST.Icons = Icons

local PREFIX = "BONK~"
local ICON_PATH = "Interface\\Icons\\"
local QUESTION = "INV_Misc_QuestionMark"
local MATCH_SHARE = 0.12
local MATCH_SLACK = 3
local VOTES_TO_LEARN = 2

local weapons = {}       -- index -> { icon = path, name = weapon name }
local byName = {}        -- spell name -> icon path, from the game's own lists
local nameIndex = {}     -- spell name -> weapon index, for the names we already know
local lastDamage = {}    -- weapon index -> meter damage at the last state line
local seen = {}          -- spell name -> combat log damage since the last state line
local votes = {}         -- spell name -> { [weapon index] = count }
local weaponNames = {}   -- this run's weapon names; a summon weapon is named after its creature

local function Path(icon)
    if not icon or icon == "" or icon == QUESTION then
        return nil
    end
    if strfind(icon, "\\", 1, true) then
        return icon
    end
    return ICON_PATH .. icon
end

local function Split(text, separator)
    local fields = {}
    local start = 1
    while true do
        local found = strfind(text, separator, start, true)
        if not found then
            tinsert(fields, strsub(text, start))
            return fields
        end
        tinsert(fields, strsub(text, start, found - 1))
        start = found + 1
    end
end

local function Learned()
    return HST.db and HST.db.learnedIcons
end

function Icons.IsWeaponName(name)
    return name and weaponNames[name] or false
end

-- The icon for a combat log spell (or pet) name, or nil.
function Icons.For(name)
    if not name then
        return nil
    end
    local icon = byName[name]
    if icon then
        return icon
    end
    local learned = Learned()
    return learned and learned[name]
end

local function Remember(name, icon, index)
    local path = Path(icon)
    if name and name ~= "" and path then
        byName[name] = path
        if index then
            nameIndex[name] = index
        end
    end
end

local function ResetRun()
    weapons = {}
    weaponNames = {}
    nameIndex = {}
    lastDamage = {}
    seen = {}
    votes = {}
end

local handlers = {}

handlers["start"] = function()
    ResetRun()
end

handlers["loadout"] = function(f)
    local index = 0
    local fresh = {}
    for _, item in ipairs(Split(f[2] or "", ",")) do
        local parts = Split(item, ":")
        if parts[1] == "w" or parts[1] == "e" then
            index = index + 1
            local old = weapons[index]
            local path = Path(parts[2])
            -- A slot whose icon changed holds a new or evolved weapon: forget its old name.
            if old and old.icon == path then
                fresh[index] = old
            else
                fresh[index] = { icon = path }
                lastDamage[index] = nil
            end
        end
    end
    weapons = fresh
    for name, at in pairs(nameIndex) do
        if not weapons[at] or weapons[at].name ~= name then
            nameIndex[name] = nil
        end
    end
end

handlers["pw"] = function(f)
    local index = tonumber(f[2])
    local weapon = index and weapons[index]
    if weapon and f[3] and f[3] ~= "" then
        weapon.name = f[3]
        weaponNames[f[3]] = true
        Remember(f[3], weapon.icon and weapon.icon or nil, index)
    end
end

handlers["glyphinfo"] = function(f)
    Remember(f[3], f[4])
end

handlers["support"] = function(f)
    for _, item in ipairs(Split(f[2] or "", ",")) do
        local _, _, icon, name = strfind(item, "^([^:]*):%d+:%d+:(.+)$")
        Remember(name, icon)
    end
end

local function Vote(name, index)
    local learned = Learned()
    local weapon = weapons[index]
    if not learned or not weapon or not weapon.icon then
        return
    end
    votes[name] = votes[name] or {}
    -- A clash with another weapon starts the count again.
    for other in pairs(votes[name]) do
        if other ~= index then
            votes[name] = {}
            break
        end
    end
    votes[name][index] = (votes[name][index] or 0) + 1
    if votes[name][index] >= VOTES_TO_LEARN then
        learned[name] = weapon.icon
        nameIndex[name] = index
    end
end

local function Close(a, b)
    local difference = a - b
    if difference < 0 then
        difference = -difference
    end
    return difference <= MATCH_SLACK or difference <= a * MATCH_SHARE
end

handlers["state"] = function(f)
    local totals = f[13] and Split(f[13], ",") or {}
    local remaining = {}
    local reset = false
    for index in pairs(weapons) do
        local damage = tonumber((Split(totals[index] or "", ":"))[1] or "")
        if damage then
            local before = lastDamage[index]
            if before and damage >= before then
                remaining[index] = damage - before
            elseif before then
                reset = true
            end
            lastDamage[index] = damage
        end
    end
    if reset then
        seen = {}
        return
    end

    -- Take out what the names we already know account for, then match what's left.
    local unknown = {}
    for name, amount in pairs(seen) do
        local index = nameIndex[name]
        if index and remaining[index] then
            remaining[index] = remaining[index] - amount
        elseif not Icons.For(name) then
            tinsert(unknown, name)
        end
    end
    for _, name in ipairs(unknown) do
        local amount = seen[name]
        local match, count = nil, 0
        for index, left in pairs(remaining) do
            if left > 0 and Close(left, amount) then
                match, count = index, count + 1
            end
        end
        if count == 1 then
            Vote(name, match)
            remaining[match] = remaining[match] - amount
        end
    end
    seen = {}
end

-- Events.lua reports every outgoing damage line here, so the next state line can be checked.
function Icons.NoteDamage(name, amount)
    if name and amount and amount > 0 and table.getn(weapons) > 0 then
        seen[name] = (seen[name] or 0) + amount
    end
end

-- Anything in the player's own spellbook: real spells there have their own icon.
function Icons.ScanSpellbook()
    if not GetSpellName or not GetSpellTexture then
        return
    end
    local book = BOOKTYPE_SPELL or "spell"
    local index = 1
    while true do
        local name = GetSpellName(index, book)
        if not name then
            break
        end
        local texture = GetSpellTexture(index, book)
        if texture and not byName[name] then
            byName[name] = texture
        end
        index = index + 1
        if index > 1024 then
            break
        end
    end
end

function Icons.Summary()
    local known, learned = 0, 0
    for _ in pairs(byName) do
        known = known + 1
    end
    for _ in pairs(Learned() or {}) do
        learned = learned + 1
    end
    return known, learned, table.getn(weapons)
end

function Icons.Forget()
    if HST.db then
        HST.db.learnedIcons = {}
    end
    votes = {}
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELLS_CHANGED")
frame:SetScript("OnEvent", function()
    if event ~= "CHAT_MSG_SYSTEM" then
        Icons.ScanSpellbook()
        return
    end
    if not arg1 or strsub(arg1, 1, 5) ~= PREFIX then
        return
    end
    local stop = strfind(arg1, "~", 6, true)
    local handler = handlers[strsub(arg1, 6, stop and stop - 1 or -1)]
    if handler then
        handler(Split(strsub(arg1, 6), "~"))
    end
end)
