# HoA Scrolling Text

Scrolling combat text for [Hordes of Azeroth](https://github.com/jonhaldors/hordes-of-azeroth), the survivors-style World of Warcraft 1.12.1 game mode. It works like MikScrollingBattleText: your damage, the damage you take, heals, crits and notifications scroll in three areas you can move around the screen.

## Features

Out of the box it shows one thing: **which of your spells hit, and for how much**. Each line reads like `Frostbolt 412`, with the spell's icon in front. When an AoE spell hits many enemies at once, the hits are added into one line such as `Arcane Explosion 612 (6x102)`: the total, then how many hits for how much each. Crits pop in larger text. Everything else below starts turned off and can be turned on in `/hst`.

- **Three scroll areas.** Outgoing on the right, Incoming on the left, Notifications above your character. Unlock them and drag them anywhere.
- **Crits pop, and stay readable.** Critical hits and heals grow, settle in the middle of their area, then fade. Normal hits fade almost away while they pass behind a crit, so the crit is easy to read. Turn this off with **Fade hits behind crits** in `/hst`.
- **Merging for hordes.** Hits from the same spell within a short window (0.4 s by default) are added into one line, like `Arcane Explosion 2,345 (8x293)`, so AoE against fifty mobs stays readable. Crits merge on their own, so they keep their pop.
- **Every hit under the weapon that made it.** The server tells the game's own meter each weapon's name, icon and damage every second, and this addon reads the same messages. Many weapons show up in the combat log under other names: Arcane Barrage casts Arcane Shot, and Call Pet's damage arrives as the beast's swings, its Bite and its Rake. The addon works out which weapon each of those names belongs to by watching whose meter damage moves with it, then shows the hit with that weapon's name and icon, so all of your pet's attacks, abilities and DoTs read as **Call Pet**. What it learns is saved. Glyphs, support effects and spellbook spells get their own icons.
- **Your summons count.** Hordes of Azeroth summons (Imp, Voidwalker, Infernal, hunter pets, totems and so on) aren't a normal pet as far as the game client is concerned, so their hits are logged like any creature's. The addon picks out the ones that are yours: a creature named after one of your weapons, one already matched to a weapon, or one that attacks an enemy you've been fighting. Each summon shows its own icon (an Imp, an Infernal, a Cat) next to its weapon's name; turn that off with **Summons show their own icon** in `/hst`.
- **Short numbers.** `12.3k`, `250k`, `9.2m` instead of `12,345`, `250,400`, `9,210,000`. Switch with `/hst short`.
- **Colour by school.** Fire is orange, Frost is light blue, Shadow is purple, and so on. Incoming melee is red, heals are green, misses are grey.
- **What it shows:** outgoing damage and DoTs, misses (dodge, parry, resist, immune and so on), pet damage, incoming damage, heals in both directions, power gains, buffs, debuffs and buff fades, killing blows, entering and leaving combat, and a low health warning. Each one can be turned on or off.
- **Works in any client language.** The parser is built from the game's own combat log strings (`GlobalStrings`) when the addon loads, so it reads whatever language Hordes of Azeroth is set to.

## Install

1. Open the Hordes of Azeroth launcher, click the **···** button next to Play, then **Open AddOns folder**. That's `benilla-config\AddOns` in your game folder. Addons don't go in `Interface\AddOns` for this game.
2. Copy the `HoAScrollingText` folder from this repository into it, so you have `benilla-config\AddOns\HoAScrollingText\HoAScrollingText.toc`.
3. Start the game. Type `/hst test` to check that it's working.

Hordes of Azeroth already shows incoming damage next to your character, so this addon's incoming damage starts turned off. Turn it on with `/hst show inDamage` if you'd rather have it here; if you do, turn off **incoming numbers** in the Hordes of Azeroth interface options to avoid seeing it twice.

## Commands

| Command | What it does |
| --- | --- |
| `/hst` | Open the options window |
| `/hst unlock`, `/hst lock` | Show the scroll areas so you can drag them, then lock them again |
| `/hst test` | Show some sample text |
| `/hst on`, `/hst off` | Turn the addon on or off |
| `/hst merge <seconds>` | How long to gather repeated hits into one number. `0` shows every hit |
| `/hst size <n>`, `/hst critsize <n>` | Text sizes |
| `/hst min <n>` | Hide outgoing hits below `n` damage |
| `/hst names` | Show or hide spell names next to the numbers |
| `/hst short` | Switch between short numbers (`12.3k`) and full ones (`12,345`) |
| `/hst icons` | Show or hide spell icons. `/hst icons forget` clears what was learned |
| `/hst weapons` | Name hits after your weapons (the default) or after the combat log's spell names. `/hst weapons list` shows which names were matched to which weapon |
| `/hst show` | List every kind of text and whether it's on. `/hst show <name>` turns one on or off |
| `/hst reset` | Go back to the default settings |

`/hoast` works too. Settings are saved per account in `HoAScrollingTextDB`.

## How it works

The Hordes of Azeroth client is a new client ([benilla](https://github.com/samwhosung/benilla)), but it sends the standard 1.12 combat log events (`CHAT_MSG_SPELL_SELF_DAMAGE`, `CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS` and so on). It writes their lines from the same `GlobalStrings` keys as the original client.

| File | Contents |
| --- | --- |
| `Core.lua` | Settings, defaults and helpers |
| `Parser.lua` | Turns each `GlobalString` (such as `SPELLLOGSCHOOLSELFOTHER`, `"Your %s hits %s for %d %s damage."`) into a Lua pattern, and parses combat log lines into records: spell, source, target, amount, school, crit, and resist, block and absorb amounts |
| `Icons.lua` | Reads the game's `BONK~` addon messages (`loadout`, `pw`, `state`, `glyphinfo`, `support`) to know your weapons and their icons, and matches each combat log spell or creature name to the weapon whose per-second meter damage moves with it |
| `Display.lua` | The scroll areas: animation, crit pops, keeping lines from overlapping, and the movers for unlock mode |
| `Events.lua` | Listens to the combat events, picks colour, area and text for each record, and merges bursts of hits |
| `Options.lua` | Slash commands and the options window |

The code follows the 1.12 Lua rules the client uses: the `this`, `event` and `arg1` globals, `table.getn` instead of `#`, and no `...` varargs.

## Known limits

- The client only logs fights between two creatures within 30 yards of you, so a summon fighting further away than that doesn't show. A summon's first hit on an enemy you haven't touched yet is also skipped, until the addon knows that enemy.

- Icons only cover your own weapons, glyphs, support effects and spellbook spells. Enemy spells have no icon: the 1.12 API can't look one up from a spell name.
- A weapon whose combat log name differs from its own name (or a new pet) shows under the combat log's name for its first few seconds, until the addon has matched it. If two such weapons always fire in the same seconds, it may take longer.
- The game's spell and glyph effects reach this addon only if the server reports them in the combat log. If some Hordes of Azeroth effect never shows up, that's why.
- Chinese text needs a font that has Chinese characters. The fonts in the options window are the game's standard Latin fonts.

## Licence

GPL-3.0, the same as Hordes of Azeroth. See [LICENSE](LICENSE).
