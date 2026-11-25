# Sprint Bar

A stamina bar for World of Warcraft: Forever (retail engine, interface `16001`). Running drains stamina. When the bar is empty you are asked to walk, and you get penalties if you keep running.

## The honest limitation

Blizzard gives addons no way to hold a key to sprint or to force your character to walk. The only run/walk control is the built-in `TOGGLERUN` binding, which calls `ToggleRun()`. That function is protected, so no addon may call it, and there is no API that reports the current walk state.

So Sprint Bar cannot force you to walk. It does this instead:

- Your **sprint key is a toggle**, not hold-to-sprint. It is the normal Run/Walk toggle, bound by the addon through an override binding (never saved to your own key bindings).
- It **measures your speed** (`GetUnitSpeed`) to tell walking from running, and watches the toggle to track the mode when speed cannot be read.
- Running while the bar is empty is a violation: the screen darkens, a warning appears every 3 seconds, and the bar goes into debt. Walking lets stamina come back.

## Install

Copy this folder, or junction it, into:

```
World of Warcraft\_forever_\Interface\AddOns\Sprint-Bar
```

Junction example (run in `cmd`, adjust paths):

```
mklink /J "C:\Games\World of Warcraft\_forever_\Interface\AddOns\Sprint-Bar" "F:\GitHub\Sprint-Bar"
```

The folder name must be `Sprint-Bar` so it matches `Sprint-Bar.toc`.

## Use

- Type `/sprintbar key` and press the key you want for sprint. Mouse buttons 3 and up must be clicked on the dialog. The dialog has a Cancel button, closes on ESC, and closes by itself after 15 seconds. If the key is already bound to another action, the dialog names it and asks you to press the key a second time to confirm.
- You can also bind one with `/sprintbar bind SHIFT-F`. Input is upper-cased, `+` works as a separator (`ctrl+alt+g`), and modifiers are put in the order ALT, CTRL, SHIFT, META. A bare modifier, `BUTTON1`, `BUTTON2`, `ESCAPE`, spaces or unknown modifiers are refused with a usage message. For the `-` and `+` keys use `/sprintbar key`.
- The client's run/walk state is unknown until you move; Sprint Bar learns it from your speed and from key presses.
- Unlock the bar with `/sprintbar unlock`, drag it, then lock it again.

## Commands

`/sprintbar` or `/sbar`:

| Command | Effect |
| --- | --- |
| (none), `options` | Open the settings category (refused during combat) |
| `key` | Open the key capture dialog |
| `bind <CHORD>` / `unbind` | Set or clear the sprint key, for example `SHIFT-F`, `CTRL+G`, `BUTTON4`. The reply says "applied" or "will apply after combat" |
| `lock` / `unlock` | Lock or unlock bar dragging |
| `reset` | Reset the bar position |
| `enable` / `disable` | Turn the stamina system on or off |
| `debug` | Toggle debug output |
| `hook on` / `hook off` | Use the `ToggleRun` hook to track mode (`off` needs `/reload` to remove fully) |
| `walkspeed <n>` | Speed (yd/s) at or below which you count as walking, default 3.0 |
| `status` | Print a diagnostic block (including how run/walk was classified and the raw speeds) to paste into a bug report |
| `help` | List commands |

## Options

Enabled, lock bar, show text, fade when full, bar scale, sprint seconds at level 1 and level 60, regeneration seconds and delay, recover threshold, mounted regeneration and drain multipliers, exhaustion overlay and its opacity, sound, exempt while ghost, debug. Changes apply immediately. The "Set sprint key" button is in the same category.

## How stamina works

- Scale 0 to 100, can go down to -30 (debt).
- A full bar lasts 8 seconds of sprinting at level 1 and 30 seconds at level 60, scaling in between.
- Regeneration starts 1.5 s after you stop sprinting and refills in 20 s (1.5x faster on a ground mount).
- At 0 you are exhausted until stamina reaches 25.
- No drain while on a taxi, flying, swimming, or in a vehicle (and while a ghost, if enabled).

## Testing checklist

1. Log in: the addon prints the sprint key line and no Lua errors appear.
2. `/sprintbar status`: version, build, level, rates, mode, speed all filled in.
3. `/sprintbar key`, press a key: the dialog closes and `status` shows the override as applied. Press an already-bound key: the dialog asks for a second press. Wait 15 seconds or click Cancel: it closes with a message.
4. `/sprintbar status` while running, walking and snared: check `pace source` and the raw current / runSpeed values (needed to confirm the walk-mode detection). Run (mode run): the bar drains and the label says SPRINT. Press the key: the label says WALK and the bar refills after 1.5 s.
5. Walk at full stamina: the bar fades out. Sprint: it fades in.
6. Run to empty: sound, overlay ramps up over about 4 seconds and clears within about 2 seconds of walking, warning every 3 seconds, bar goes dark red. Press the key to walk: "Stamina recovered." appears at 25.
7. Mount up on a ground mount: regeneration is faster. Fly, swim, take a taxi: no drain.
8. Enter combat and run: no Lua errors; `status` shows speed as readable or "secret/unreadable" without errors. Change the key in combat: capture refuses; the binding applies after combat.
9. `/sprintbar unlock`, drag, `/reload`: position persists. `/sprintbar reset` restores it.
10. Log out at low stamina, log back in later: stamina is restored plus time-based regeneration.
11. Check chat for a "Blizzard blocked an action" warning. If one appears, run `/sprintbar hook off`, `/reload` and send `/sprintbar status`.
12. Level up (or test with different levels): the sprint seconds in `status` change.
