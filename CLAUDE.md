# Salvager — contributor guide

## Keep `README.md` in sync with player-facing changes

`README.md` is the source of truth for **controls, displays, the flight HUD, and
the gameplay loop**. Whenever a change alters any of these, update `README.md` in
the *same* change — a control the player can press or a HUD marking they can see
is not "done" until the README describes it. Map the code you touched to the
section that documents it:

| You changed… | Update this README section |
| --- | --- |
| HOTAS / keyboard / switch-panel bindings (`autoload/InputRouter.gd` `PROFILES`, `project.godot` `[input]`) | The matching **Controls** table (X55 / X52 / Switch Panel / Keyboard fallback) |
| Main-display HUD indicators or readouts (`scenes/ui/HUDOverlay.gd`) | **The Main flight HUD** section, and the screenshot caption / alt text |
| Displays, windows, or simpit/multi-display behaviour | **The four displays** / **Simpit / multi-display setup** |
| Gameplay loop, power channels, salvage/market rules | **Core gameplay loop** |
| A new `tools/` scene | The **Handy tool scenes** table |

When a change makes an existing README statement **false**, fix that line — don't
just append. (Example: adding throttle-POV strafe made the old "strafe is
keyboard-only" note wrong; the fix was to reword that note, not add a second one.)

If a change is purely internal (refactor, tests, collision math) with no effect
on what the player presses, sees, or reads, the README needs no change.
