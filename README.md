# Omacade

**Insert no coins.** Omacade is a modular, theme-aware arcade for
[Omarchy](https://omarchy.org/). Version 0.1 ships its first cabinet: **Lander**.

Lander is an original graphical game inspired by the broad lunar-landing genre.
Rotate, manage a limited fuel supply, and settle both feet onto a marked pad.
It runs in its own Quickshell window, uses real key-down/key-up input, and draws
an original pixel-art spacecraft sprite over a theme-aware lunar landscape.
The narrow pad pays more, but every difficulty tightens the safe velocity and
attitude limits. A successful touchdown clears the stage; the next stage
narrows the pads and progressively adds taller mountains, deeper crater bowls,
and rougher terrain. Higher-value pads also gain jagged ridges and crater cuts
around their approaches. Crashes retry the current stage.

## What it feels like

- Opens as a normal tiled graphical window.
- Opens on an animated attract screen with difficulty, records, and controls.
- Uses the active Omarchy palette and updates when the theme changes.
- Draws a shaded lunar surface, illuminated pads, a rotating raster sprite,
  continuous engine plume, twinkling stars, occasional comets, and a
  cabinet-style flight display.
- Adds synthesized engine, control, touchdown, crash, stage-clear, launch, and
  comet sounds, with a persistent mute setting.
- Throws lunar dust on touchdown and sparks, debris, and an expanding blast
  ring on impact.
- Includes Cadet, Pilot, and Ace flight schools.
- Generates a new lunar surface and two scoring pads every flight.
- Rescales the world after Hyprland tiles or resizes the cabinet, and pauses
  behind a clear size warning if there is not enough visible play space.
- Saves the ten best landings locally.
- Has no network access, accounts, telemetry, or dependencies beyond the
  Quickshell runtime already included with Omarchy.
- Keeps the original terminal renderer available as a fallback.

## Controls

| Key | Action |
|---|---|
| ← / A | Rotate counter-clockwise |
| → / D | Rotate clockwise |
| ↑ / W / Space | Main engine |
| 1 / 2 / 3 | Select Cadet / Pilot / Ace and restart |
| P | Pause |
| H | Show or close the top-ten high scores |
| M | Toggle sound effects |
| R | Restart the current stage |
| Q / Escape | Close the cabinet |
| Enter | Advance after landing or retry after impact |

A qualifying landing opens the classic three-character initials prompt. Once
entered, those initials are prefilled for future high scores; typing a new
character replaces the prefill, while Enter accepts it as-is.

## Install

Once this repository has a public Git URL:

```sh
omarchy plugin add https://github.com/keithnyc/omacade.git --enable
```

The plugin installer deliberately only clones and enables reviewed QML. The
bar icon works immediately. To also install the `omacade-gui` graphical command,
`omacade` terminal fallback, Super+Space launcher, and theme-change icon hook, run:

```sh
~/.config/omarchy/plugins/io.github.keithnyc.omacade/scripts/setup-user-entry
```

Then launch the graphical arcade lobby from the bar, Super+Space, or a terminal:

```sh
omacade-gui
```

For development or troubleshooting, launch Lander directly:

```sh
omacade-gui lander
```

The original terminal cabinet remains available with `omacade lander`.

## Local development

From the parent directory of this checkout, link it under its manifest ID:

```sh
ln -s "$PWD/omacade" ~/.config/omarchy/plugins/io.github.keithnyc.omacade
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.keithnyc.omacade
```

Files under `~/.config/omarchy/plugins/` hot-reload. Run the lobby with
`./omacade/omacade-gui`, Lander directly with `./omacade/omacade-gui lander`,
or the terminal fallback with `./omacade/omacade lander`.

## Cabinet framework

`game/arcade.qml` is the arcade lobby. Cabinet identity and launch metadata
live in `game/framework/CabinetRegistry.js`; reusable theme and persistence
services live beside it. Each game runs as an isolated Quickshell process, so
adding a cabinet does not enlarge the Omarchy bar widget or couple its game
loop to Lander. See `game/framework/README.md` for the cabinet contract.

Validate the repository with Omarchy's own validator:

```sh
omarchy-plugin-validate ./omacade
python3 -m py_compile ./omacade/omacade
python3 ./omacade/tests/test_omacade.py
```

## Local data

- Settings: `~/.local/state/omarchy/omacade.json`
- Scores: `~/.local/share/omacade/scores.json`

Score writes are atomic. The top ten retain initials, difficulty, fuel, and
flight time. Omacade reads only its own settings and scores plus Omarchy's
current theme file.

## Optional integration removal

Run this before removing the plugin if you installed the optional user entry:

```sh
~/.config/omarchy/plugins/io.github.keithnyc.omacade/scripts/remove-user-entry
omarchy plugin remove io.github.keithnyc.omacade
```

## Roadmap

The framework is ready for Cabinet 02. The next cabinet should be an original
digging/chase game—not a copy of another game's characters, levels, art, music,
or name.

## License

MIT. See [LICENSE](LICENSE).
