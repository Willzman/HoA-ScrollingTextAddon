-- Listens to the combat log, decides what each record looks like and where it goes, and merges
-- bursts of hits from the same spell into one number.

local HST = HoAScrollingText
local Events = {}
HST.Events = Events

local SCHOOL_COLORS = {
    [0] = { 1, 1, 1 },        -- Physical
    [1] = { 1, 0.9, 0.5 },    -- Holy
    [2] = { 1, 0.5, 0.1 },    -- Fire
    [3] = { 0.45, 1, 0.45 },  -- Nature
    [4] = { 0.5, 0.85, 1 },   -- Frost
    [5] = { 0.7, 0.45, 1 },   -- Shadow
    [6] = { 1, 0.55, 1 },     -- Arcane
}
local INCOMING_PHYSICAL = { 1, 0.2, 0.2 }
local HEAL = { 0.2, 1, 0.2 }
local MISS = { 0.75, 0.75, 0.75 }
local PET = { 0.95, 0.7, 0.3 }
local POWER = { 0.4, 0.6, 1 }
local BUFF = { 1, 1, 0.55 }
local FADE = { 0.65, 0.65, 0.65 }
local DEBUFF = { 1, 0.4, 0.4 }
local KILL = { 1, 0.82, 0 }
local COMBAT = { 1, 0.4, 0.2 }
local WARNING = { 1, 0.1, 0.1 }

local MISS_WORDS = {
    MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", RESIST = "Resist",
    IMMUNE = "Immune", EVADE = "Evade", DEFLECT = "Deflect", ABSORB = "Absorb", REFLECT = "Reflect",
}

local function Word(key)
    local value = getglobal(key)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return MISS_WORDS[key] or key
end

local function SchoolColor(record, physicalColor)
    local index = record.schoolIndex
    if not index or index == 0 then
        return physicalColor
    end
    return SCHOOL_COLORS[index] or physicalColor
end

local function Trailers(record)
    local parts = ""
    if record.crushing then
        parts = parts .. " " .. "Crushing"
    end
    if record.glancing then
        parts = parts .. " " .. "Glancing"
    end
    if type(record.resisted) == "number" then
        parts = parts .. " (" .. HST.Comma(record.resisted) .. " " .. Word("RESIST") .. ")"
    end
    if type(record.blocked) == "number" then
        parts = parts .. " (" .. HST.Comma(record.blocked) .. " " .. Word("BLOCK") .. ")"
    end
    if type(record.absorbed) == "number" then
        parts = parts .. " (" .. HST.Comma(record.absorbed) .. " " .. Word("ABSORB") .. ")"
    end
    return parts
end

-- What one record becomes on screen: category toggle, area, colour, a merge key and how to
-- write it for a given total and hit count. Returns nil when it should not be shown.
local function Describe(record)
    local db = HST.db
    local kind, direction = record.kind, record.direction
    local label = db.showSpellNames and record.spell or nil
    if db.showTargets and record.target and direction ~= "in" then
        label = (label and (label .. " ") or "") .. "> " .. record.target
    end

    if kind == "damage" then
        if direction == "out" then
            local category = record.periodic and "outDot" or "outDamage"
            return {
                category = category, area = "outgoing", color = SchoolColor(record, SCHOOL_COLORS[0]),
                key = category .. (record.spell or "melee"), minimum = db.minOutgoing,
                Text = function(total, count)
                    local text = HST.Comma(total)
                    if label then
                        text = text .. " " .. label
                    end
                    if count > 1 then
                        return text .. " x" .. count
                    end
                    return text .. Trailers(record)
                end,
            }
        elseif direction == "pet" then
            local name = record.spell or record.source
            return {
                category = "pet", area = "outgoing", color = PET,
                key = "pet" .. (name or ""), minimum = db.minOutgoing,
                Text = function(total, count)
                    local text = HST.Comma(total)
                    if db.showSpellNames and name then
                        text = text .. " " .. name
                    end
                    return count > 1 and (text .. " x" .. count) or text
                end,
            }
        else
            return {
                category = "inDamage", area = "incoming", color = SchoolColor(record, INCOMING_PHYSICAL),
                key = "in" .. (record.spell or "melee"), minimum = db.minIncoming,
                Text = function(total, count)
                    local text = "-" .. HST.Comma(total)
                    if label then
                        text = text .. " " .. label
                    end
                    if count > 1 then
                        return text .. " x" .. count
                    end
                    return text .. Trailers(record)
                end,
            }
        end
    elseif kind == "heal" then
        local outgoing = direction == "out"
        return {
            category = outgoing and "outHeal" or "inHeal", area = outgoing and "outgoing" or "incoming",
            color = HEAL, key = (outgoing and "oh" or "ih") .. (record.spell or ""),
            Text = function(total, count)
                local text = "+" .. HST.Comma(total)
                if label then
                    text = text .. " " .. label
                end
                return count > 1 and (text .. " x" .. count) or text
            end,
        }
    elseif kind == "miss" then
        local outgoing = direction == "out"
        local word = Word(record.miss or "MISS")
        return {
            category = outgoing and "outMiss" or "inMiss", area = outgoing and "outgoing" or "incoming",
            color = MISS, key = (outgoing and "om" or "im") .. word .. (record.spell or ""), noAmount = true,
            Text = function(_, count)
                local text = word
                if label then
                    text = text .. " " .. label
                end
                return count > 1 and (text .. " x" .. count) or text
            end,
        }
    elseif kind == "power" then
        return {
            category = "power", area = "incoming", color = POWER, key = "pw" .. (record.power or ""),
            Text = function(total, count)
                local text = "+" .. HST.Comma(total) .. " " .. (record.power or "")
                return count > 1 and (text .. " x" .. count) or text
            end,
        }
    elseif kind == "buff" or kind == "debuff" or kind == "fade" then
        local category = kind == "buff" and "buffGain" or (kind == "debuff" and "debuff" or "buffFade")
        local color = kind == "buff" and BUFF or (kind == "debuff" and DEBUFF or FADE)
        local prefix = kind == "fade" and "-" or "+"
        if kind == "debuff" then
            prefix = ""
        end
        return {
            category = category, area = "notification", color = color, key = kind .. (record.spell or ""),
            noAmount = true, noMerge = true,
            Text = function()
                local text = kind == "debuff" and ("[" .. (record.spell or "") .. "]") or (prefix .. (record.spell or ""))
                if record.count and record.count > 1 then
                    text = text .. " (" .. record.count .. ")"
                end
                return text
            end,
        }
    elseif kind == "kill" then
        return {
            category = "kills", area = "notification", color = KILL, key = "kill", noAmount = true,
            Text = function(_, count)
                if count > 1 then
                    return "Killing Blows x" .. count
                end
                return "Killing Blow: " .. (record.target or "")
            end,
        }
    end
    return nil
end

-- Merge buffer: one entry per key, flushed when its window has passed.
local pending = {}
local pendingCount = 0
local ticker = CreateFrame("Frame")
ticker:Hide()

local function Emit(view, total, count, crit)
    local color = view.color
    HST.Display.Add(view.area, view.Text(total, count), color[1], color[2], color[3], crit)
end

local function Flush(force)
    local now = GetTime()
    local window = HST.db.mergeWindow
    for key, entry in pairs(pending) do
        if force or now - entry.born >= window then
            Emit(entry.view, entry.total, entry.count, entry.crit)
            pending[key] = nil
            pendingCount = pendingCount - 1
        end
    end
    if pendingCount <= 0 then
        pendingCount = 0
        ticker:Hide()
    end
end

ticker:SetScript("OnUpdate", function()
    Flush(false)
end)

function Events.Show(record)
    if not record then
        return
    end
    local view = Describe(record)
    if not view or not HST.Enabled(view.category) then
        return
    end
    local amount = record.amount or 0
    if not view.noAmount and view.minimum and amount < view.minimum then
        return
    end
    local crit = record.crit and true or false
    local window = HST.db.mergeWindow or 0
    if view.noMerge or window <= 0 then
        Emit(view, amount, 1, crit)
        return
    end
    -- Crits merge on their own so they keep their pop.
    local key = view.area .. view.key .. (crit and "!" or "")
    local entry = pending[key]
    if entry then
        entry.total = entry.total + amount
        entry.count = entry.count + 1
    else
        pending[key] = { view = view, total = amount, count = 1, crit = crit, born = GetTime() }
        pendingCount = pendingCount + 1
        ticker:Show()
    end
end

function Events.Notify(message, color, sticky)
    if HST.db and HST.db.enabled then
        color = color or KILL
        HST.Display.Add("notification", message, color[1], color[2], color[3], sticky)
    end
end

-- Low health warning, once per dip below the threshold.
local lowHealth = false
local function CheckHealth()
    local maximum = UnitHealthMax("player")
    if not maximum or maximum <= 0 then
        return
    end
    local current = UnitHealth("player")
    local below = current / maximum * 100 < HST.db.lowHealthPercent
    if below and not lowHealth and current > 0 and HST.Enabled("lowHealth") then
        Events.Notify("Low Health! " .. HST.Comma(current), WARNING, true)
    end
    lowHealth = below
end

local frame = CreateFrame("Frame", "HoAScrollingTextEvents")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 ~= "HoAScrollingText" then
            return
        end
        HST.LoadSettings()
        HST.Parser.Init()
        for _, eventName in ipairs(HST.Parser.Events()) do
            this:RegisterEvent(eventName)
        end
        this:RegisterEvent("PLAYER_REGEN_DISABLED")
        this:RegisterEvent("PLAYER_REGEN_ENABLED")
        this:RegisterEvent("UNIT_HEALTH")
        this:UnregisterEvent("ADDON_LOADED")
        if HST.Options and HST.Options.Init then
            HST.Options.Init()
        end
        return
    end
    if not HST.db.enabled then
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        if HST.Enabled("combat") then
            Events.Notify("+Combat", COMBAT)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if HST.Enabled("combat") then
            Events.Notify("-Combat", COMBAT)
        end
    elseif event == "UNIT_HEALTH" then
        if arg1 == "player" then
            CheckHealth()
        end
    else
        Events.Show(HST.Parser.Parse(event, arg1))
    end
end)

-- Runs sample lines through the real parser, so the test shows what the game's own lines do.
local SAMPLES = {
    { "CHAT_MSG_SPELL_SELF_DAMAGE", "SPELLLOGSCHOOLSELFOTHER", "Frostbolt", "Murloc Forager", 412, "Frost" },
    { "CHAT_MSG_SPELL_SELF_DAMAGE", "SPELLLOGCRITSCHOOLSELFOTHER", "Fireball", "Kobold Tunneler", 1288, "Fire" },
    { "CHAT_MSG_SPELL_SELF_DAMAGE", "SPELLLOGSCHOOLSELFOTHER", "Arcane Explosion", "Defias Thug", 233, "Arcane" },
    { "CHAT_MSG_SPELL_SELF_DAMAGE", "SPELLLOGSCHOOLSELFOTHER", "Arcane Explosion", "Defias Pillager", 241, "Arcane" },
    { "CHAT_MSG_SPELL_SELF_DAMAGE", "SPELLLOGSCHOOLSELFOTHER", "Arcane Explosion", "Defias Looter", 229, "Arcane" },
    { "CHAT_MSG_COMBAT_SELF_HITS", "COMBATHITSELFOTHER", "Riverpaw Gnoll", 87 },
    { "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "PERIODICAURADAMAGESELFOTHER", "Kobold Miner", 64, "Shadow", "Corruption" },
    { "CHAT_MSG_COMBAT_SELF_MISSES", "VSDODGESELFOTHER", "Hogger" },
    { "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "COMBATHITOTHERSELF", "Hogger", 134 },
    { "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "COMBATHITCRITOTHERSELF", "Hogger", 301 },
    { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "SPELLLOGSCHOOLOTHERSELF", "Defias Conjurer", "Fireball", 190, "Fire" },
    { "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES", "VSPARRYOTHERSELF", "Hogger" },
    { "CHAT_MSG_SPELL_SELF_BUFF", "HEALEDSELFSELF", "Healing Touch", 540 },
    { "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "PERIODICAURAHEALSELFSELF", 75, "Rejuvenation" },
    { "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "AURAADDEDSELFHELPFUL", "Power Word: Shield" },
    { "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "AURAADDEDSELFHARMFUL", "Rend" },
    { "CHAT_MSG_COMBAT_HOSTILE_DEATH", "SELFKILLOTHER", "Hogger" },
}

-- English text for the samples when the GlobalString is missing (matches Parser's fallbacks).
local SAMPLE_FORMATS = {
    SPELLLOGSCHOOLSELFOTHER = "Your %s hits %s for %d %s damage.",
    SPELLLOGCRITSCHOOLSELFOTHER = "Your %s crits %s for %d %s damage.",
    COMBATHITSELFOTHER = "You hit %s for %d.",
    PERIODICAURADAMAGESELFOTHER = "%s suffers %d %s damage from your %s.",
    VSDODGESELFOTHER = "You attack. %s dodges.",
    COMBATHITOTHERSELF = "%s hits you for %d.",
    COMBATHITCRITOTHERSELF = "%s crits you for %d.",
    SPELLLOGSCHOOLOTHERSELF = "%s's %s hits you for %d %s damage.",
    VSPARRYOTHERSELF = "%s attacks. You parry.",
    HEALEDSELFSELF = "Your %s heals you for %d.",
    PERIODICAURAHEALSELFSELF = "You gain %d health from %s.",
    AURAADDEDSELFHELPFUL = "You gain %s.",
    AURAADDEDSELFHARMFUL = "You are afflicted by %s.",
    SELFKILLOTHER = "You have slain %s!",
}

function Events.Test()
    local unrecognised = 0
    for _, sample in ipairs(SAMPLES) do
        local template = getglobal(sample[2])
        if type(template) ~= "string" or template == "" then
            template = SAMPLE_FORMATS[sample[2]]
        end
        -- A translated template may use positional %1$s, which format() can't fill.
        local ok, line = pcall(format, template, sample[3], sample[4], sample[5], sample[6])
        local record = ok and HST.Parser.Parse(sample[1], line)
        if record then
            Events.Show(record)
        else
            unrecognised = unrecognised + 1
        end
    end
    if HST.Enabled("combat") then
        Events.Notify("+Combat", COMBAT)
    end
    if unrecognised > 0 then
        HST.Print(unrecognised .. " test line(s) were not recognised.")
    end
end

function Events.Reset()
    Flush(true)
end
