-- Which of your weapons a combat log line belongs to, and its icon, worked out from what the
-- Hordes of Azeroth server tells its own damage meter.
--
-- The server sends the game's addon `BONK~` lines over CHAT_MSG_SYSTEM:
--   loadout~w:<icon>:<rank>:<max>,e:<icon>:...,p:<icon>:...~<slots>~<passive slots>
--   pw~<index>~<weapon name>~...           (one per weapon, in loadout order)
--   state~...~<damage>:<kills>,...~...     (field 13: per weapon damage, about once a second)
--   glyphinfo~<id>~<name>~<icon>~...
--   support~<icon>:<healed>:<absorbed>:<name>,...
--
-- A weapon's combat log lines carry the names of the spells and creatures behind it, which are
-- often not the weapon's name: Arcane Barrage casts Arcane Shot, and Call Pet's damage arrives
-- as the beast's swings, its Bite and its DoTs. The meter's per-weapon damage counts all of it
-- (pets and DoTs are credited to the weapon that made them), so each unknown name is matched to
-- the weapon whose damage moves with it:
--   * a weapon whose meter total didn't move in a second where the name did damage gets a
--     strike; one whose damage its known names already explain gets half a strike. A strike
--     and a half rules it out (a hit can land either side of a state line);
--   * when the amounts match closely, or only one weapon had damage nothing else explains,
--     that weapon gets a vote.
-- One weapon left, or two votes for a weapon without strikes, and the name is learned and
-- saved. The meter caps a killing blow at the health the enemy had left while the log shows
-- the whole hit, so amounts only ever vote.
--
-- A summon's abilities belong to the summon: "Cat's Bite" counts as Cat's weapon's damage.
-- Glyph and support names (the server names them in glyphinfo and support lines) are kept out:
-- glyphs are built to overkill, so their hits would only muddy the numbers.

local HST = HoAScrollingText
local Icons = {}
HST.Icons = Icons

local PREFIX = "BONK~"
local ICON_PATH = "Interface\\Icons\\"
local QUESTION = "INV_Misc_QuestionMark"
local MATCH_SHARE = 0.12
local MATCH_SLACK = 3
local VOTES_TO_LEARN = 2
local STRIKES_TO_RULE_OUT = 1.5
local IDLE_STRIKE = 1
local EXPLAINED_STRIKE = 0.5
local SECONDS_TO_SETTLE = 3

local weapons = {}       -- index -> { icon = path, name = weapon name }
local byWeapon = {}      -- weapon name -> index, this run
local byName = {}        -- other names with an icon: glyphs, support, spellbook
local notOurs = {}       -- glyph and support names: the server counts those apart from weapons
local lastDamage = {}    -- weapon index -> meter damage at the last state line
local seen = {}          -- combat log name -> damage since the last state line
local owners = {}        -- combat log name -> the summon that used it ("Bite" -> "Cat")
local evidence = {}      -- combat log name -> { strikes = {}, votes = {}, seconds = n }
local notWeapons = {}    -- names ruled out for every weapon this run (glyph procs and such)

-- A creature has no icon in 1.12, so each Hordes of Azeroth summon gets the icon that fits it,
-- by its creature name (the server's English and Chinese names). Every icon here is one the game
-- already uses, or a stock hunter pet family icon. Summons not listed keep their weapon's icon.
local SUMMON_ICONS = {
    { "Spell_Shadow_SummonImp", "Imp", "小鬼" },
    { "Spell_Shadow_SummonVoidWalker", "Voidwalker", "虚空行者" },
    { "Spell_Shadow_SummonSuccubus", "Succubus", "魅魔" },
    { "Spell_Shadow_SummonFelHunter", "Felhunter", "恶魔猎犬" },
    { "Spell_Shadow_SummonInfernal", "Infernal", "地狱火" },
    { "Spell_Shadow_AntiMagicShell", "Doomguard", "末日守卫" },
    { "Spell_Shadow_RaiseDead", "Risen Skeleton", "复活的骷髅" },
    { "Ability_Hunter_Pet_Wolf", "Wolf", "狼" },
    { "Ability_Hunter_Pet_Cat", "Cat", "猫" },
    { "Ability_Hunter_Pet_Boar", "Boar", "野猪" },
    { "Ability_Hunter_Pet_Bear", "Bear", "熊" },
    { "Ability_Hunter_Pet_Wyvern", "Wyvern", "双足飞龙" },
    { "Ability_Hunter_Quickshot", "Venomous Snake", "毒蛇" },
    { "Spell_Frost_SummonWaterElemental", "Water Elemental", "水元素" },
    { "Spell_Fire_Fire", "Fire Elemental", "火元素" },
    { "Spell_Nature_SpiritWolf", "Spirit Wolf", "灵魂之狼" },
    { "Spell_Fire_SearingTotem", "Searing Totem", "灼热图腾" },
    { "Spell_Fire_SelfDestruct", "Magma Totem", "熔岩图腾" },
    { "Spell_Nature_ForceOfNature", "Treant", "树人" },
}

local summonIcons = {}
for _, row in ipairs(SUMMON_ICONS) do
    summonIcons[row[2]] = "Interface\\Icons\\" .. row[1]
    summonIcons[row[3]] = "Interface\\Icons\\" .. row[1]
end

-- The summon's own icon, by its creature name, or nil.
function Icons.Summon(name)
    return name and summonIcons[name]
end

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
    return HST.db and HST.db.learnedWeapons
end

-- The weapon a combat log name belongs to in this run: its index, or nil.
local function IndexOf(name)
    if not name then
        return nil
    end
    local index = byWeapon[name]
    if index then
        return index
    end
    local learned = Learned()
    local weapon = learned and learned[name]
    return weapon and byWeapon[weapon]
end

-- The weapon behind a combat log spell or creature name: weapon name, icon. Nil if unknown.
function Icons.Weapon(name)
    local index = IndexOf(name)
    local weapon = index and weapons[index]
    if weapon and weapon.name then
        return weapon.name, weapon.icon
    end
    return nil
end

-- An icon for any name: a weapon's, then glyphs, support effects and the spellbook.
function Icons.For(name)
    if not name then
        return nil
    end
    local _, icon = Icons.Weapon(name)
    if icon then
        return icon
    end
    if byName[name] then
        return byName[name]
    end
    -- Saved by older versions, which learned icons but not weapons.
    local old = HST.db and HST.db.learnedIcons
    return old and old[name]
end

function Icons.IsWeaponName(name)
    return name and byWeapon[name] and true or false
end

local function Remember(name, icon)
    if not name or name == "" then
        return
    end
    notOurs[name] = true
    local path = Path(icon)
    if path then
        byName[name] = path
    end
end

local function ResetLearning()
    lastDamage = {}
    seen = {}
    owners = {}
    evidence = {}
    notWeapons = {}
end

local handlers = {}

handlers["start"] = function()
    weapons = {}
    byWeapon = {}
    ResetLearning()
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
            -- A slot whose icon changed holds a new or evolved weapon: its name comes next.
            if old and old.icon == path then
                fresh[index] = old
            else
                fresh[index] = { icon = path }
            end
        end
    end
    weapons = fresh
    byWeapon = {}
    for at, weapon in pairs(weapons) do
        if weapon.name then
            byWeapon[weapon.name] = at
        end
    end
    -- What's being matched against changed: start the evidence again.
    ResetLearning()
end

handlers["pw"] = function(f)
    local index = tonumber(f[2])
    local weapon = index and weapons[index]
    if weapon and f[3] and f[3] ~= "" then
        weapon.name = f[3]
        byWeapon[f[3]] = index
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

local function Close(a, b)
    local difference = a - b
    if difference < 0 then
        difference = -difference
    end
    return difference <= MATCH_SLACK or difference <= a * MATCH_SHARE
end

local function Evidence(name)
    local entry = evidence[name]
    if not entry then
        entry = { strikes = {}, votes = {}, seconds = 0 }
        evidence[name] = entry
    end
    return entry
end

local function Learn(name, index)
    local learned = Learned()
    local weapon = weapons[index]
    if learned and weapon and weapon.name then
        learned[name] = weapon.name
    end
    evidence[name] = nil
end

-- Settle a name once the evidence points at one weapon.
local function Decide(name, deltas)
    local entry = evidence[name]
    local left, count = nil, 0
    for index in pairs(deltas) do
        if (entry.strikes[index] or 0) < STRIKES_TO_RULE_OUT then
            left, count = index, count + 1
        end
    end
    if count == 0 then
        notWeapons[name] = true
        evidence[name] = nil
        return
    end
    if count == 1 and entry.seconds >= SECONDS_TO_SETTLE then
        Learn(name, left)
        return
    end
    for index, votes in pairs(entry.votes) do
        if votes >= VOTES_TO_LEARN and not entry.strikes[index] then
            Learn(name, index)
            return
        end
    end
end

handlers["state"] = function(f)
    local totals = f[13] and Split(f[13], ",") or {}
    local deltas = {}
    local reset = false
    for index in pairs(weapons) do
        local damage = tonumber((Split(totals[index] or "", ":"))[1] or "")
        if damage then
            local before = lastDamage[index]
            if before and damage >= before then
                deltas[index] = damage - before
            elseif before then
                reset = true
            end
            lastDamage[index] = damage
        end
    end
    local heard, heardOwners = seen, owners
    seen, owners = {}, {}
    if reset or not next(deltas) then
        return
    end

    -- What each weapon did that its known names don't account for.
    local unexplained = {}
    for index, delta in pairs(deltas) do
        unexplained[index] = delta
    end
    local unknown = {}
    for name, amount in pairs(heard) do
        local index = IndexOf(name) or IndexOf(heardOwners[name])
        if index then
            if unexplained[index] then
                unexplained[index] = unexplained[index] - amount
            end
        elseif not notWeapons[name] then
            tinsert(unknown, name)
        end
    end

    local busy, busyCount = nil, 0
    for index, left in pairs(unexplained) do
        if left > MATCH_SLACK then
            busy, busyCount = index, busyCount + 1
        end
    end

    for _, name in ipairs(unknown) do
        local amount = heard[name]
        local entry = Evidence(name)
        entry.seconds = entry.seconds + 1
        local close, closeCount = nil, 0
        for index, delta in pairs(deltas) do
            if delta <= 0 then
                entry.strikes[index] = (entry.strikes[index] or 0) + IDLE_STRIKE
            elseif unexplained[index] <= MATCH_SLACK then
                entry.strikes[index] = (entry.strikes[index] or 0) + EXPLAINED_STRIKE
            elseif Close(unexplained[index], amount) then
                close, closeCount = index, closeCount + 1
            end
        end
        if closeCount == 1 then
            entry.votes[close] = (entry.votes[close] or 0) + 1
        elseif busyCount == 1 then
            entry.votes[busy] = (entry.votes[busy] or 0) + 1
        end
        Decide(name, deltas)
    end
end

-- Events.lua reports every outgoing and summon damage line here, by spell or creature name;
-- `owner` is the summon behind an ability, if any.
function Icons.NoteDamage(name, amount, owner)
    if name and amount and amount > 0 and next(weapons) and not notOurs[name] then
        seen[name] = (seen[name] or 0) + amount
        if owner and owner ~= name then
            owners[name] = owner
        end
    end
end

-- Anything in the player's own spellbook: real spells there have their own icon.
function Icons.ScanSpellbook()
    if not GetSpellName or not GetSpellTexture then
        return
    end
    local book = BOOKTYPE_SPELL or "spell"
    local index = 1
    while index <= 1024 do
        local name = GetSpellName(index, book)
        if not name then
            break
        end
        local texture = GetSpellTexture(index, book)
        if texture and not byName[name] then
            byName[name] = texture
        end
        index = index + 1
    end
end

function Icons.Summary()
    local learned, weaponCount = 0, 0
    for _ in pairs(Learned() or {}) do
        learned = learned + 1
    end
    for _ in pairs(weapons) do
        weaponCount = weaponCount + 1
    end
    return learned, weaponCount
end

function Icons.Forget()
    if HST.db then
        HST.db.learnedWeapons = {}
        HST.db.learnedIcons = {}
    end
    evidence = {}
    notWeapons = {}
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
