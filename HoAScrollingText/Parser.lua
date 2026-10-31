-- Turns combat log chat lines into records.
--
-- The Hordes of Azeroth client builds every combat log line from the install's GlobalStrings
-- (SPELLLOGSCHOOLSELFOTHER and friends), as the 1.12 client did. So instead of hard-coding
-- English sentences, each GlobalString is compiled into a Lua pattern when the addon loads.
-- That keeps the parser right for whatever language the game is set to; the English text below
-- is only used if a GlobalString is missing.

local HST = HoAScrollingText
local Parser = {}
HST.Parser = Parser

-- Each entry: GlobalString key, English fallback, record kind, direction, then the meaning of
-- each format argument in argument order (positional formats such as %2$s are handled).
-- Extra flags: crit, periodic, miss = the miss word key.
local OUT_HITS = {
    { "COMBATHITSCHOOLSELFOTHER", "You hit %s for %d %s damage.", "damage", "out", { "target", "amount", "school" } },
    { "COMBATHITCRITSCHOOLSELFOTHER", "You crit %s for %d %s damage.", "damage", "out", { "target", "amount", "school" }, crit = true },
    { "COMBATHITSELFOTHER", "You hit %s for %d.", "damage", "out", { "target", "amount" } },
    { "COMBATHITCRITSELFOTHER", "You crit %s for %d.", "damage", "out", { "target", "amount" }, crit = true },
}

local OUT_MISSES = {
    { "MISSEDSELFOTHER", "You miss %s.", "miss", "out", { "target" }, miss = "MISS" },
    { "VSDODGESELFOTHER", "You attack. %s dodges.", "miss", "out", { "target" }, miss = "DODGE" },
    { "VSPARRYSELFOTHER", "You attack. %s parries.", "miss", "out", { "target" }, miss = "PARRY" },
    { "VSBLOCKSELFOTHER", "You attack. %s blocks.", "miss", "out", { "target" }, miss = "BLOCK" },
    { "VSABSORBSELFOTHER", "You attack. %s absorbs all the damage.", "miss", "out", { "target" }, miss = "ABSORB" },
    { "VSRESISTSELFOTHER", "You attack. %s resists all the damage.", "miss", "out", { "target" }, miss = "RESIST" },
    { "VSIMMUNESELFOTHER", "You attack but %s is immune.", "miss", "out", { "target" }, miss = "IMMUNE" },
    { "VSEVADESELFOTHER", "You attack. %s evades.", "miss", "out", { "target" }, miss = "EVADE" },
    { "VSDEFLECTSELFOTHER", "You attack. %s deflects.", "miss", "out", { "target" }, miss = "DEFLECT" },
}

local OUT_SPELLS = {
    { "SPELLLOGSCHOOLSELFOTHER", "Your %s hits %s for %d %s damage.", "damage", "out", { "spell", "target", "amount", "school" } },
    { "SPELLLOGCRITSCHOOLSELFOTHER", "Your %s crits %s for %d %s damage.", "damage", "out", { "spell", "target", "amount", "school" }, crit = true },
    { "SPELLLOGSELFOTHER", "Your %s hits %s for %d.", "damage", "out", { "spell", "target", "amount" } },
    { "SPELLLOGCRITSELFOTHER", "Your %s crits %s for %d.", "damage", "out", { "spell", "target", "amount" }, crit = true },
    { "SPELLMISSSELFOTHER", "Your %s missed %s.", "miss", "out", { "spell", "target" }, miss = "MISS" },
    { "SPELLRESISTSELFOTHER", "Your %s was resisted by %s.", "miss", "out", { "spell", "target" }, miss = "RESIST" },
    { "SPELLDODGEDSELFOTHER", "Your %s was dodged by %s.", "miss", "out", { "spell", "target" }, miss = "DODGE" },
    { "SPELLPARRIEDSELFOTHER", "Your %s is parried by %s.", "miss", "out", { "spell", "target" }, miss = "PARRY" },
    { "SPELLBLOCKEDSELFOTHER", "Your %s was blocked by %s.", "miss", "out", { "spell", "target" }, miss = "BLOCK" },
    { "SPELLEVADEDSELFOTHER", "Your %s was evaded by %s.", "miss", "out", { "spell", "target" }, miss = "EVADE" },
    { "SPELLIMMUNESELFOTHER", "Your %s failed. %s is immune.", "miss", "out", { "spell", "target" }, miss = "IMMUNE" },
    { "IMMUNESPELLSELFOTHER", "%s is immune to your %s.", "miss", "out", { "target", "spell" }, miss = "IMMUNE" },
    { "SPELLDEFLECTEDSELFOTHER", "Your %s was deflected by %s.", "miss", "out", { "spell", "target" }, miss = "DEFLECT" },
    { "SPELLLOGABSORBSELFOTHER", "Your %s is absorbed by %s.", "miss", "out", { "spell", "target" }, miss = "ABSORB" },
    { "SPELLREFLECTSELFOTHER", "Your %s is reflected back by %s.", "miss", "out", { "spell", "target" }, miss = "REFLECT" },
    -- Your own spell hitting you lands on the same event.
    { "SPELLLOGSCHOOLSELFSELF", "Your %s hits you for %d %s damage.", "damage", "in", { "spell", "amount", "school" } },
    { "SPELLLOGCRITSCHOOLSELFSELF", "Your %s crits you for %d %s damage.", "damage", "in", { "spell", "amount", "school" }, crit = true },
}

local OUT_PERIODIC = {
    { "PERIODICAURADAMAGESELFOTHER", "%s suffers %d %s damage from your %s.", "damage", "out", { "target", "amount", "school", "spell" }, periodic = true },
}

local OUT_SHIELDS = {
    { "DAMAGESHIELDSELFOTHER", "You reflect %d %s damage to %s.", "damage", "out", { "amount", "school", "target" } },
}

local PET_DAMAGE = {
    { "COMBATHITSCHOOLOTHEROTHER", "%s hits %s for %d %s damage.", "damage", "pet", { "source", "target", "amount", "school" } },
    { "COMBATHITCRITSCHOOLOTHEROTHER", "%s crits %s for %d %s damage.", "damage", "pet", { "source", "target", "amount", "school" }, crit = true },
    { "COMBATHITOTHEROTHER", "%s hits %s for %d.", "damage", "pet", { "source", "target", "amount" } },
    { "COMBATHITCRITOTHEROTHER", "%s crits %s for %d.", "damage", "pet", { "source", "target", "amount" }, crit = true },
    { "SPELLLOGSCHOOLOTHEROTHER", "%s's %s hits %s for %d %s damage.", "damage", "pet", { "source", "spell", "target", "amount", "school" } },
    { "SPELLLOGCRITSCHOOLOTHEROTHER", "%s's %s crits %s for %d %s damage.", "damage", "pet", { "source", "spell", "target", "amount", "school" }, crit = true },
    { "SPELLLOGOTHEROTHER", "%s's %s hits %s for %d.", "damage", "pet", { "source", "spell", "target", "amount" } },
    { "SPELLLOGCRITOTHEROTHER", "%s's %s crits %s for %d.", "damage", "pet", { "source", "spell", "target", "amount" }, crit = true },
}

local IN_HITS = {
    { "COMBATHITOTHERSELF", "%s hits you for %d.", "damage", "in", { "source", "amount" } },
    { "COMBATHITCRITOTHERSELF", "%s crits you for %d.", "damage", "in", { "source", "amount" }, crit = true },
    { "COMBATHITSCHOOLOTHERSELF", "%s hits you for %d %s damage.", "damage", "in", { "source", "amount", "school" } },
    { "COMBATHITCRITSCHOOLOTHERSELF", "%s crits you for %d %s damage.", "damage", "in", { "source", "amount", "school" }, crit = true },
}

local ENVIRONMENT = {
    { "VSENVIRONMENTALDAMAGE_FALLING_SELF", "You fall and lose %d health.", "damage", "in", { "amount" } },
    { "VSENVIRONMENTALDAMAGE_DROWNING_SELF", "You are drowning and lose %d health.", "damage", "in", { "amount" } },
    { "VSENVIRONMENTALDAMAGE_FATIGUE_SELF", "You are exhausted and lose %d health.", "damage", "in", { "amount" } },
    { "VSENVIRONMENTALDAMAGE_FIRE_SELF", "You suffer %d points of fire damage.", "damage", "in", { "amount" } },
    { "VSENVIRONMENTALDAMAGE_LAVA_SELF", "You lose %d health for swimming in lava.", "damage", "in", { "amount" } },
    { "VSENVIRONMENTALDAMAGE_SLIME_SELF", "You lose %d health for swimming in slime.", "damage", "in", { "amount" } },
}

local IN_MISSES = {
    { "MISSEDOTHERSELF", "%s misses you.", "miss", "in", { "source" }, miss = "MISS" },
    { "VSDODGEOTHERSELF", "%s attacks. You dodge.", "miss", "in", { "source" }, miss = "DODGE" },
    { "VSPARRYOTHERSELF", "%s attacks. You parry.", "miss", "in", { "source" }, miss = "PARRY" },
    { "VSBLOCKOTHERSELF", "%s attacks. You block.", "miss", "in", { "source" }, miss = "BLOCK" },
    { "VSABSORBOTHERSELF", "%s attacks. You absorb all the damage.", "miss", "in", { "source" }, miss = "ABSORB" },
    { "VSRESISTOTHERSELF", "%s attacks. You resist all the damage.", "miss", "in", { "source" }, miss = "RESIST" },
    { "VSIMMUNEOTHERSELF", "%s attacks but you are immune.", "miss", "in", { "source" }, miss = "IMMUNE" },
    { "VSEVADEOTHERSELF", "%s attacks. You evade.", "miss", "in", { "source" }, miss = "EVADE" },
    { "VSDEFLECTOTHERSELF", "%s attacks. You deflect.", "miss", "in", { "source" }, miss = "DEFLECT" },
}

local IN_SPELLS = {
    { "SPELLLOGSCHOOLOTHERSELF", "%s's %s hits you for %d %s damage.", "damage", "in", { "source", "spell", "amount", "school" } },
    { "SPELLLOGCRITSCHOOLOTHERSELF", "%s's %s crits you for %d %s damage.", "damage", "in", { "source", "spell", "amount", "school" }, crit = true },
    { "SPELLLOGOTHERSELF", "%s's %s hits you for %d.", "damage", "in", { "source", "spell", "amount" } },
    { "SPELLLOGCRITOTHERSELF", "%s's %s crits you for %d.", "damage", "in", { "source", "spell", "amount" }, crit = true },
    { "SPELLMISSOTHERSELF", "%s's %s misses you.", "miss", "in", { "source", "spell" }, miss = "MISS" },
    { "SPELLRESISTOTHERSELF", "%s's %s was resisted.", "miss", "in", { "source", "spell" }, miss = "RESIST" },
    { "SPELLDODGEDOTHERSELF", "%s's %s was dodged.", "miss", "in", { "source", "spell" }, miss = "DODGE" },
    { "SPELLPARRIEDOTHERSELF", "%s's %s was parried.", "miss", "in", { "source", "spell" }, miss = "PARRY" },
    { "SPELLBLOCKEDOTHERSELF", "%s's %s was blocked.", "miss", "in", { "source", "spell" }, miss = "BLOCK" },
    { "SPELLEVADEDOTHERSELF", "%s's %s was evaded.", "miss", "in", { "source", "spell" }, miss = "EVADE" },
    { "SPELLIMMUNEOTHERSELF", "%s's %s fails. You are immune.", "miss", "in", { "source", "spell" }, miss = "IMMUNE" },
    { "SPELLDEFLECTEDOTHERSELF", "%s's %s was deflected.", "miss", "in", { "source", "spell" }, miss = "DEFLECT" },
    { "SPELLLOGABSORBOTHERSELF", "You absorb %s's %s.", "miss", "in", { "source", "spell" }, miss = "ABSORB" },
}

local IN_PERIODIC = {
    { "PERIODICAURADAMAGEOTHERSELF", "You suffer %d %s damage from %s's %s.", "damage", "in", { "amount", "school", "source", "spell" }, periodic = true },
    { "PERIODICAURADAMAGESELFSELF", "You suffer %d %s damage from your %s.", "damage", "in", { "amount", "school", "spell" }, periodic = true },
    { "AURAADDEDSELFHARMFUL", "You are afflicted by %s.", "debuff", "note", { "spell" } },
    { "AURAAPPLICATIONADDEDSELFHARMFUL", "You are afflicted by %s (%d).", "debuff", "note", { "spell", "count" } },
}

local IN_SHIELDS = {
    { "DAMAGESHIELDOTHERSELF", "%s reflects %d %s damage to you.", "damage", "in", { "source", "amount", "school" } },
}

local SELF_BUFF = {
    { "HEALEDCRITSELFSELF", "Your %s critically heals you for %d.", "heal", "in", { "spell", "amount" }, crit = true },
    { "HEALEDSELFSELF", "Your %s heals you for %d.", "heal", "in", { "spell", "amount" } },
    { "HEALEDCRITSELFOTHER", "Your %s critically heals %s for %d.", "heal", "out", { "spell", "target", "amount" }, crit = true },
    { "HEALEDSELFOTHER", "Your %s heals %s for %d.", "heal", "out", { "spell", "target", "amount" } },
    { "POWERGAINSELFSELF", "You gain %d %s from %s.", "power", "in", { "amount", "power", "spell" } },
}

local PERIODIC_SELF_BUFFS = {
    { "PERIODICAURAHEALSELFSELF", "You gain %d health from %s.", "heal", "in", { "amount", "spell" }, periodic = true },
    { "PERIODICAURAHEALOTHERSELF", "You gain %d health from %s's %s.", "heal", "in", { "amount", "source", "spell" }, periodic = true },
    { "POWERGAINSELFSELF", "You gain %d %s from %s.", "power", "in", { "amount", "power", "spell" } },
    { "POWERGAINOTHERSELF", "You gain %d %s from %s's %s.", "power", "in", { "amount", "power", "source", "spell" } },
    { "AURAADDEDSELFHELPFUL", "You gain %s.", "buff", "note", { "spell" } },
    { "AURAAPPLICATIONADDEDSELFHELPFUL", "You gain %s (%d).", "buff", "note", { "spell", "count" } },
}

local OTHERS_PERIODIC_BUFFS = {
    { "PERIODICAURAHEALSELFOTHER", "%s gains %d health from your %s.", "heal", "out", { "target", "amount", "spell" }, periodic = true },
}

local OTHERS_BUFF = {
    { "HEALEDCRITOTHERSELF", "%s's %s critically heals you for %d.", "heal", "in", { "source", "spell", "amount" }, crit = true },
    { "HEALEDOTHERSELF", "%s's %s heals you for %d.", "heal", "in", { "source", "spell", "amount" } },
}

local AURA_GONE = {
    { "AURAREMOVEDSELF", "%s fades from you.", "fade", "note", { "spell" } },
}

local KILLS = {
    { "SELFKILLOTHER", "You have slain %s!", "kill", "note", { "target" } },
}

-- Combat log event -> the families of lines it can carry.
local EVENT_LISTS = {
    CHAT_MSG_COMBAT_SELF_HITS = { OUT_HITS, ENVIRONMENT },
    CHAT_MSG_COMBAT_SELF_MISSES = { OUT_MISSES },
    CHAT_MSG_SPELL_SELF_DAMAGE = { OUT_SPELLS },
    CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE = { OUT_PERIODIC },
    CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE = { OUT_PERIODIC },
    CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF = { OUT_SHIELDS },
    CHAT_MSG_COMBAT_PET_HITS = { PET_DAMAGE },
    CHAT_MSG_SPELL_PET_DAMAGE = { PET_DAMAGE },

    CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS = { IN_HITS, ENVIRONMENT },
    CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS = { IN_HITS },
    CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES = { IN_MISSES },
    CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES = { IN_MISSES },
    CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE = { IN_SPELLS },
    CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE = { IN_SPELLS },
    CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE = { IN_PERIODIC },
    CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS = { IN_SHIELDS },

    CHAT_MSG_SPELL_SELF_BUFF = { SELF_BUFF },
    CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS = { PERIODIC_SELF_BUFFS },
    CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS = { OTHERS_PERIODIC_BUFFS },
    CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS = { OTHERS_PERIODIC_BUFFS },
    CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS = { OTHERS_PERIODIC_BUFFS },
    CHAT_MSG_SPELL_PARTY_BUFF = { OTHERS_BUFF },
    CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF = { OTHERS_BUFF },
    CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF = { OTHERS_BUFF },
    CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF = { OTHERS_BUFF },
    CHAT_MSG_SPELL_AURA_GONE_SELF = { AURA_GONE },

    CHAT_MSG_COMBAT_HOSTILE_DEATH = { KILLS },
}

local TRAILERS = {
    { "RESIST_TRAILER", " (%d resisted)", "resisted" },
    { "BLOCK_TRAILER", " (%d blocked)", "blocked" },
    { "ABSORB_TRAILER", " (%d absorbed)", "absorbed" },
    { "VULNERABLE_TRAILER", " (+%d vulnerability bonus)", "vulnerable" },
    { "CRUSHING_TRAILER", " (crushing)", "crushing" },
    { "GLANCING_TRAILER", " (glancing)", "glancing" },
}

local function Escape(text)
    return (gsub(text, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- "Your %s hits %s for %d." -> "^Your (.-) hits (.-) for (%d+)%.", { 1, 2, 3 }, literal length.
-- The map turns capture N into argument index map[N], so "%2$s ... %1$s" works.
function Parser.Compile(format_string, anchored)
    local tokens = {}
    local literal = ""
    local nextArg = 0
    local i = 1
    local length = strlen(format_string)
    while i <= length do
        local c = strsub(format_string, i, i)
        if c == "%" then
            local _, stop, position, conversion = strfind(format_string, "^(%d*)%$?([sd%%])", i + 1)
            if not stop then
                return nil
            end
            if conversion == "%" then
                literal = literal .. "%"
            else
                if literal ~= "" then
                    tinsert(tokens, literal)
                    literal = ""
                end
                local index
                if position ~= "" then
                    index = tonumber(position)
                else
                    nextArg = nextArg + 1
                    index = nextArg
                end
                tinsert(tokens, { index = index, conversion = conversion })
            end
            i = stop + 1
        else
            literal = literal .. c
            i = i + 1
        end
    end
    if literal ~= "" then
        tinsert(tokens, literal)
    end

    local pattern = anchored and "^" or ""
    local map = {}
    local literalLength = 0
    local count = table.getn(tokens)
    for n = 1, count do
        local token = tokens[n]
        if type(token) == "string" then
            pattern = pattern .. Escape(token)
            literalLength = literalLength + strlen(token)
        else
            if token.conversion == "d" then
                pattern = pattern .. "(%d+)"
            elseif n == count then
                pattern = pattern .. "(.+)"
            else
                pattern = pattern .. "(.-)"
            end
            tinsert(map, token.index)
        end
    end
    return pattern, map, literalLength
end

local function GlobalOr(key, fallback)
    local value = getglobal(key)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return fallback
end

local function Build(entry)
    local text = GlobalOr(entry[1], entry[2])
    local pattern, map, literalLength = Parser.Compile(text, true)
    if not pattern then
        return nil
    end
    return {
        key = entry[1], pattern = pattern, map = map, literal = literalLength,
        kind = entry[3], direction = entry[4], fields = entry[5],
        crit = entry.crit, periodic = entry.periodic, miss = entry.miss,
    }
end

-- Most specific first: a pattern with more fixed text can't be swallowed by a looser one
-- ("Your %s critically heals you for %d." must be tried before "Your %s heals %s for %d.").
local function Specific(a, b)
    if a.literal ~= b.literal then
        return a.literal > b.literal
    end
    return table.getn(a.map) > table.getn(b.map)
end

Parser.lists = {}
Parser.trailers = {}

function Parser.Init()
    Parser.lists = {}
    for eventName, families in pairs(EVENT_LISTS) do
        local list = {}
        for _, family in ipairs(families) do
            for _, entry in ipairs(family) do
                local built = Build(entry)
                if built then
                    tinsert(list, built)
                end
            end
        end
        table.sort(list, Specific)
        Parser.lists[eventName] = list
    end

    Parser.trailers = {}
    for _, trailer in ipairs(TRAILERS) do
        local text = GlobalOr(trailer[1], trailer[2])
        local pattern = Parser.Compile(text, false)
        if pattern then
            tinsert(Parser.trailers, { pattern = pattern, field = trailer[3] })
        end
    end

    -- School words as the log writes them (SPELL_SCHOOL<n>_CAP), back to their index.
    local english = { "Physical", "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }
    Parser.schools = {}
    for index = 0, 6 do
        Parser.schools[GlobalOr("SPELL_SCHOOL" .. index .. "_CAP", english[index + 1])] = index
        Parser.schools[english[index + 1]] = index
    end
end

function Parser.Events()
    local names = {}
    for eventName in pairs(EVENT_LISTS) do
        tinsert(names, eventName)
    end
    return names
end

local function ReadTrailers(message, record)
    if not strfind(message, "(", 1, true) then
        return
    end
    for _, trailer in ipairs(Parser.trailers) do
        local start, _, amount = strfind(message, trailer.pattern)
        if start then
            record[trailer.field] = tonumber(amount) or true
        end
    end
end

-- Returns a record table, or nil when the line is not one we show.
function Parser.Parse(eventName, message)
    local list = Parser.lists[eventName]
    if not list or not message then
        return nil
    end
    for _, entry in ipairs(list) do
        local captures = { strfind(message, entry.pattern) }
        if captures[1] then
            local record = {
                kind = entry.kind, direction = entry.direction, crit = entry.crit,
                periodic = entry.periodic, miss = entry.miss, key = entry.key,
            }
            for n, argIndex in ipairs(entry.map) do
                local field = entry.fields[argIndex]
                if field then
                    record[field] = captures[n + 2]
                end
            end
            if record.amount then
                record.amount = tonumber(record.amount) or 0
            end
            if record.count then
                record.count = tonumber(record.count)
            end
            if record.school then
                record.schoolIndex = Parser.schools[record.school]
            end
            ReadTrailers(message, record)
            return record
        end
    end
    return nil
end
