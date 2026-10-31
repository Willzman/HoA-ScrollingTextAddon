# HoA Scrolling Text

Scrolling combat text for [Hordes of Azeroth](https://github.com/jonhaldors/hordes-of-azeroth), the survivors-style World of Warcraft 1.12.1 game mode. It works like MikScrollingBattleText: your damage, the damage you take, heals, crits and notifications scroll in three areas you can move around the screen.

## Features

Out of the box it shows one thing: **which of your spells hit, and for how much**. Each line reads like `Frostbolt 412`, with the spell's icon in front. When an AoE spell hits many enemies at once, the hits are added into one line such as `Arcane Explosion 612 (6x102)`: the total, then how many hits for how much each. Crits pop in larger text. Everything else below starts turned off and can be turned on in `/hst`.

- **Three scroll areas.** Outgoing on the right, Incoming on the left, Notifications above your character. Unlock them and drag them anywhere.
- **Crits pop, and stay readable.** Critical hits and heals grow, settle in the middle of their area, then fade. Normal hits fade almost away while they pass behind a crit, so the crit is easy to read. Turn this off with **Fade hits behind crits** in `/hst`.
- **Merging for hordes.** Hits from the same spell within a short window (0.4 s by default) are added into one line, like `Arcane Explosion 2,345 (8x293)`, so AoE against fifty mobs stays readable. Crits merge on their own, so they keep their pop.
- **Spell icons from the game's damage meter.** The server tells the game's own meter each weapon's icon and name, and this addon reads the same messages. When a weapon casts a spell with a different name (Arcane Barrage casts Arcane Shot), the addon compares the meter's per-weapon damage with the combat log second by second, and learns which icon goes with that name. Learned icons are saved. Glyph, support and spellbook icons are used too.
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
| `/hst icons` | Show or hide spell icons, and say how many are known. `/hst icons forget` clears the learned ones |
| `/hst show` | List every kind of text and whether it's on. `/hst show <name>` turns one on or off |
| `/hst reset` | Go back to the default settings |

`/hoast` works too. Settings are saved per account in `HoAScrollingTextDB`.

## How it works

The Hordes of Azeroth client is a new client ([benilla](https://github.com/samwhosung/benilla)), but it sends the standard 1.12 combat log events (`CHAT_MSG_SPELL_SELF_DAMAGE`, `CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS` and so on). It writes their lines from the same `GlobalStrings` keys as the original client.

| File | Contents |
| --- | --- |
| `Core.lua` | Settings, defaults and helpers |
| `Parser.lua` | Turns each `GlobalString` (such as `SPELLLOGSCHOOLSELFOTHER`, `"Your %s hits %s for %d %s damage."`) into a Lua pattern, and parses combat log lines into records: spell, source, target, amount, school, crit, and resist, block and absorb amounts |
| `Icons.lua` | Reads the game's `BONK~` addon messages (`loadout`, `pw`, `state`, `glyphinfo`, `support`) to find each weapon's icon, and learns the icon for combat log names that differ from the weapon's name |
| `Display.lua` | The scroll areas: animation, crit pops, keeping lines from overlapping, and the movers for unlock mode |
| `Events.lua` | Listens to the combat events, picks colour, area and text for each record, and merges bursts of hits |
| `Options.lua` | Slash commands and the options window |

The code follows the 1.12 Lua rules the client uses: the `this`, `event` and `arg1` globals, `table.getn` instead of `#`, and no `...` varargs.

## Known limits

- Icons only cover your own weapons, glyphs, support effects and spellbook spells. Enemy spells have no icon: the 1.12 API can't look one up from a spell name.
- A renamed weapon gets its icon after about two seconds of it doing damage on its own, the first time you use it. If two such weapons always hit at the same moment for the same damage, the addon can't tell them apart, so neither gets an icon.
- The game's spell and glyph effects reach this addon only if the server reports them in the combat log. If some Hordes of Azeroth effect never shows up, that's why.
- Chinese text needs a font that has Chinese characters. The fonts in the options window are the game's standard Latin fonts.

## Licence

GPL-3.0, the same as Hordes of Azeroth. See [LICENSE](LICENSE).
