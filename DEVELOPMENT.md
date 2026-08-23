# Omacade developer handoff

This document captures the architecture, gameplay contracts, important code
paths, and practical lessons behind the Omacade v1 build. It is intended to be
the first stop for future development sessions.

Last committed checkpoint: **2026-08-22**, commit `72d508e` (`Polish Core
Command rendering and frame pacing`). Since then, a fifth cabinet — **Daemon
Swarm** — was added on top of that checkpoint (not yet committed as of this
writing; check `git log`/`git status` for the current state). The repository
now contains five playable graphical cabinets and a complete five-game Circuit
mode.

## Product state

The arcade floor is:

1. **Lander** — precision lunar flight, staged terrain, difficulty selection,
   landing pads, highscores, and a terminal fallback.
2. **Rootbound** — Dig Dug-inspired filesystem tunneling, daemon purge combat,
   package recovery, hazards, and four filesystem zones.
3. **Packet Hop** — Frogger-inspired network routing with traffic, rideable
   carriers, five destination ports, TTL pressure, route events, and telemetry
   rails.
4. **Core Command** — Missile Command-inspired stack defense using limited
   firewall batteries, expanding quarantine fields, chain reactions, service
   abilities, fork bombs, stealth payloads, rootkits, and zero-day sieges.
5. **Daemon Swarm** — a super-lite survivors game. Auto-fire at the nearest
   rogue process, collect packets to level up, and pick from a small upgrade
   pool (packet burst, firewall ring, patch orbit) as an escalating swarm —
   including splitting forks and periodic telegraphed rootkit elites — closes
   in. No aiming; the whole loop is movement and build choices.

The lobby adds a shared pilot profile, top scores, last-run recaps,
achievements, and **Omacade Circuit**. Circuit runs all five cabinets in
order, normalizes each result to at most 3000 points, and gives the player
two continues.

The guiding design is an original Omarchy-themed arcade, not a pixel-perfect
clone collection. Familiar genre rules make each game immediately readable;
the art, terminology, progression, and implementation are Omacade's own.

## Architecture at a glance

```text
Omarchy bar
  BarWidget.qml -> Panel.qml
                     |
                     | launches
                     v
                omacade-gui
                     |
                     v
              game/arcade.qml
               lobby/orchestrator
                     |
          Quickshell Process, one at a time
            +--------+---------+----------+-------------+-------------+
            |                  |          |             |             |
        shell.qml       rootbound.qml  packet-hop.qml  core-command.qml  daemon-swarm.qml
         Lander
            +------------------+----------+-------------+-------------+
                               |
                   ArcadeData.qml + ArcadeTheme.qml
                               |
                local JSON state + active Omarchy palette
```

The strongest architectural rule is that **each cabinet is its own Quickshell
process**. The lobby launches a cabinet, hides itself, and returns when the
child exits. Do not move the game loops into the lobby or bar widget. Process
isolation keeps animation load, failures, and cabinet-specific state out of
Omarchy's long-running shell.

## Important files

| Path | Responsibility |
|---|---|
| `manifest.json` | Omarchy plugin identity and bar-widget entry point. |
| `BarWidget.qml` | Minimal bar button and panel loader. Right/middle click launches directly. |
| `Panel.qml` | Native Omarchy panel for launch, Lander difficulty, sound, initials, and basic records. |
| `omacade-gui` | Graphical launcher; maps cabinet names to independent QML entry points and creates initial local data files. |
| `omacade` | Original Python terminal Lander and fallback renderer. It shares the Lander config and score files. |
| `game/arcade.qml` | Arcade lobby, pilot profile, cabinet process orchestration, recaps, achievements UI, and Circuit state machine. |
| `game/framework/CabinetRegistry.js` | Stable cabinet IDs, order, display metadata, entry paths, and score keys. Circuit order follows this array. |
| `game/framework/ArcadeData.qml` | Shared settings, atomic score persistence, top-ten logic, run stats, last-run handshake, and achievements. |
| `game/framework/ArcadeTheme.qml` | Watches Omarchy's current `colors.toml` and exposes the shared palette. |
| `game/shell.qml` | Graphical Lander. The generic filename is historical; it is Cabinet 01, not the lobby shell. |
| `game/rootbound.qml` | Rootbound simulation, input pacing, combat, stage generation, sprites, HUD, and scoring. |
| `game/packet-hop.qml` | Packet Hop grid simulation, lane/carrier rules, network events, responsive rails, sprites, and scoring. |
| `game/core-command.qml` | Core Command world simulation, fixed-aspect renderer, threat/interceptor logic, service abilities, and scoring. |
| `game/daemon-swarm.qml` | Daemon Swarm world simulation, auto-fire/leveling/upgrade-pool logic, swarm AI, and scoring. |
| `game/assets/` | Raster sprite sheets, standalone sprites, and synthesized WAV effects. |
| `tests/test_omacade.py` | Terminal physics tests plus graphical architecture/assets/contract regression checks. |
| `scripts/setup-user-entry` | Optional CLI, desktop entry, and theme-hook integration. Never run automatically during plugin installation. |
| `scripts/remove-user-entry` | Removes only integration paths owned by this checkout. |

`game/framework/README.md` contains the shorter cabinet-registration contract.
This document is the broader operational handoff.

## Shared runtime contracts

### Cabinet registration

Every graphical cabinet has one entry in `CabinetRegistry.js` with stable
`id`, `scoreKey`, `entry`, display metadata, controls, and `status`. A cabinet
is launchable only when its status is `ready`.

Every cabinet should:

- import `ArcadeTheme`, `ArcadeData`, and `CabinetRegistry.js`;
- resolve its metadata with `CabinetRegistry.byId()`;
- set `ArcadeData.cabinetId` to the registered `scoreKey`;
- own its simulation, rendering, input, sounds, and overlays;
- write a completed run with `ArcadeData.recordScore()`;
- close its `FloatingWindow` to return control to the lobby.

### Local data

Omacade intentionally has no network access, accounts, telemetry, or cloud
state.

- Settings: `~/.local/state/omarchy/omacade.json`
- Scores: `~/.local/share/omacade/scores.json`
- Theme input: `~/.local/state/omarchy/current/theme/colors.toml`

The shared settings currently contain `difficulty`, `sound`, and `initials`.
Initials are normalized to three uppercase alphanumeric characters.

The score document is append-like in behavior but compact in storage:

```json
{
  "lander": [{ "score": 1234, "initials": "KEW", "stage": 2 }],
  "rootbound": [],
  "packet-hop": [],
  "core-command": [],
  "circuit": [],
  "stats": {
    "lander": { "completed": 12, "lastPlayed": "ISO-8601 timestamp" }
  },
  "lastRuns": {
    "lander": { "score": 1234, "at": "ISO-8601 timestamp" }
  },
  "achievements": {},
  "successful_landings": 12
}
```

Only the best ten rows per score key are retained, but `stats` counts every
recorded run and `lastRuns` always retains the most recent row. Lander's
`successful_landings` field is preserved for compatibility with the original
terminal game and increments only for positive-score landings.

Common score fields are `score`, `initials`, `difficulty`, `stage`, and `at`.
Cabinet-specific fields are part of the progression contract:

- Lander: `fuel`, `time`
- Rootbound: `packages`
- Packet Hop: `ports`, `ttl`
- Core Command: `services`, `threats`, `shots`, `accuracy`, `maxChain`,
  `perfectWaves`
- Daemon Swarm: `time`, `kills`, `elites` (its `stage` field holds level reached)
- Circuit: `continues`, `splits`

`ArcadeData.recordScore()` also annotates rows with `newBest`, `newStage`, and
newly earned `unlocks`. Achievement derivation deliberately recognizes older
score files so new badges can unlock from historical play.

When changing this schema, retain unknown top-level keys and old row fields.
Do not replace the file with a cabinet-only object. All QML writes use
`FileView.atomicWrites`.

## Circuit mode

Circuit is a process-safe state machine in `game/arcade.qml`; it is not a
shared in-process game mode.

1. `beginCircuit()` initializes the ordered run and two continues.
2. `launchCabinet()` records the current cabinet's `lastRuns[id].at` value.
3. The lobby launches the cabinet with `OMACADE_CIRCUIT=1` and hides itself.
4. The cabinet plays normally, records exactly one final run, then closes
   instead of restarting or advancing indefinitely.
5. When the child exits, the lobby reloads scores after a short settling delay.
6. A changed `lastRuns[id].at` is the completion handshake. No change means
   the player quit early, so the lobby shows cabinet-signal recovery instead
   of inventing a result.
7. `circuitPoints()` converts cabinet-specific performance into 0–3000 points.
8. The player can accept the result or spend a continue to replay it before
   the split is committed.
9. `finishCircuit()` records the total under the `circuit` score key.

Every cabinet checks `Quickshell.env("OMACADE_CIRCUIT") === "1"`. Keep
standalone behavior unchanged when adding Circuit-specific exits. In
particular, qualifying initials must be saved before the process closes.

Lander crashes record a zero-point run during Circuit so the lobby receives a
valid completion signal. `circuitPoints()` explicitly returns zero for a
zero-score Lander run; fuel and stage bonuses must never turn a crash into
positive Circuit points.

The normalization formulas are currently hand-tuned. Before v1 release, play
several complete Circuits and compare cabinet splits. Tune formulas from real
runs rather than raw cabinet highscores, and preserve the 3000-point cap.

## Cabinet implementation notes

### Lander

- `game/shell.qml` is the graphical implementation; `omacade` is the terminal
  implementation and physics reference.
- Input uses real key-down/key-up state. Opposite rotation and redirected thrust
  must take effect immediately; do not reintroduce key-repeat gating that drops
  course corrections.
- A landing succeeds when both gear feet are on the pad and velocity/attitude
  are safe. The lander does **not** need to be centered on the pad.
- Successful landings advance to harder stages. Terrain generation narrows
  pads, increases relief, and sculpts jagged approaches around valuable pads.
- The lander is a transparent PNG sprite rendered with preserved aspect ratio.
  Earlier rotated ASCII art became visually garbled.
- Sky effects and particles are kept separate from terrain work where possible;
  a comet should never trigger expensive ground redraw/highlighting.
- `viewportTooSmall` pauses play behind a clear resize warning.

### Rootbound

- The world is a 32×22 cell grid with interpolated `playerVisualX/Y` movement.
- Keyboard auto-repeat is ignored. Movement uses explicit intent, a fixed
  interval, and a pending-turn window. This prevents both held-key acceleration
  and rapid-tap speed exploits while keeping direction changes responsive.
- Player direction variants should be produced from one consistent sprite
  treatment. Mirrored directions must not expose different atlas artifacts.
- Purge/capture interaction is continuous enough to feel fluid; avoid long
  dead waits between inflation steps.
- `/home`, `/var`, `/tmp`, and `/root` deliberately change terrain, hazards,
  enemies, and optional objectives rather than only increasing speed.

### Packet Hop

- The logical board is 15×12 and must preserve square cells. The central
  playfield uses `playfieldAspect`; spare width becomes telemetry rails rather
  than stretching the board.
- Compact layouts hide/reflow the rails. Test both a single wide window and a
  narrow tiled window; this game received multiple passes specifically for
  those two shapes.
- Sprite collision/readability is more important than large art. Vehicles and
  carriers were reduced until gaps became visually trustworthy.
- Network events always have a warning phase, affected-lane callout, active
  HUD state, and visible gameplay effect. The player should not need to infer
  what “packet loss” or “route flap” means.
- Sprite language matters: packets, ports, firewalls, switches, carriers, and
  hazards should read as network objects. Atlas source rectangles must be
  checked carefully; one red hazard previously rendered a duplicated half
  sprite because its crop crossed the wrong cell.
- Neon accents (carrier motion streaks, a pulsing halo behind the player
  courier, glow rings on pickups and bound ports, a warning-phase radar
  sweep on the affected lane) are layered *underneath/around* the existing
  sprites using Core Command's layered-stroke technique, not a replacement
  for them. This was a deliberate choice over redoing the cabinet in pure
  Geometry-Wars primitives: the sprite-based readability above took real
  tuning to get right, and a full rewrite would have re-risked all of it.
  Keep any new accent low-alpha and within roughly the sprite's own
  footprint so it doesn't visually shrink the gaps between vehicles.

### Core Command

- The simulation uses a fixed 1000×600 world. `worldCanvas` preserves the 5:3
  aspect ratio and letterboxes inside the available playfield. Never return to
  independent X/Y stretching: circles, payloads, bases, and collision feedback
  become visibly distorted.
- Mouse coordinates are mapped through `worldCanvas`, not the surrounding
  letterboxed item. Keyboard aiming uses the same world coordinates.
- The main loop uses measured elapsed time capped at 50 ms. This avoids
  slow-motion during a delayed frame without allowing a large catch-up jump.
- The Canvas requests threaded rendering, batches the static grid into one
  stroke, and mutates hot-path objects where safe to reduce allocation churn.
- Neon trails use layered strokes: a broad low-alpha colored beam, a saturated
  inner line, and a narrow foreground core. Avoid `shadowBlur`; it is expensive
  in the QML Canvas renderer and is unnecessary for the Geometry Wars-like look.
- Fork bombs fall vertically before splitting. Children begin their own trails
  at the split position so trail angle and payload trajectory agree.
- Launches are limited by battery cooldown, a shared launch bus, ammunition,
  and two in-flight interceptors per node. Removing those limits makes screen
  flooding the dominant strategy.
- Each surviving service provides a named ability. Every fifth wave introduces
  a three-layer zero-day siege. These mechanics are explained in HUD/briefing
  language, not left as invisible modifiers.

### Daemon Swarm

- The world is a fixed 900×900 square, letterboxed the same way as Core
  Command's `worldCanvas` (never independent X/Y stretch).
- There is no manual aim. All combat resolution (bolts, the firewall ring,
  and orbit shards) happens inside one function, `updateEnemies(dt)`, in a
  single sweep per tick — it checks weapon collisions against the current
  `enemies` array, handles death/rewards/fork-splitting, then moves
  survivors and applies contact damage, before reassigning `enemies` once.
  Splitting this across several functions each doing their own
  slice/reassign of `enemies` invites ordering bugs; keep it unified.
- Enemies always chase the player's live position every frame — there is no
  fixed-target model like Core Command's threats, which is what keeps the
  swarm logic simple.
- A level-up pauses the sim (`mode = "levelup"`) and offers 3 upgrade choices
  drawn from a pool that skips weapons already maxed. `tick()` re-checks
  `mode` between each update phase so a level-up (or death) mid-tick doesn't
  let spawning/orb-collection sneak in one extra step while paused.
- `maxEnemies` (90) caps concurrent enemies, including fork-split children —
  the same "deliberate cap over screen flooding" philosophy as Core Command's
  launch limits.
- The 16ms Timer is gated on `!game.tooSmall`, matching the fix applied to
  Lander/Packet Hop: never let the sim keep running (and the player keep
  taking damage) behind a "too small" overlay the player can't see through.
- The world Canvas is split into `bgCanvas` (background wash, stars, grid,
  arena border — repainted on a slow 120ms Timer, not every tick) and
  `worldCanvas` (everything that actually moves — repainted every 16ms). This
  is the same lesson as Rootbound's `soilCanvas` split, applied for the same
  reason: measured CPU dropped from ~117% of a core to ~44% with this change
  plus a lower `maxParticles` cap (320→200). If adding more per-frame juice,
  measure with `ps -o pcpu=` before assuming it's free — Canvas drawing here
  is CPU-side QPainter work, not GPU shaders (Quickshell's regular QML items
  *are* GPU-composited via the scene graph; `Canvas` is not, `Canvas.Threaded`
  only moves the work off the main thread, it doesn't move it onto the GPU).

## Input, rendering, and sound conventions

- Ignore `event.isAutoRepeat` and model held controls explicitly when continuous
  movement is intended.
- Keep logical simulation coordinates separate from interpolated/rendered
  coordinates.
- Use `Image.PreserveAspectFit`, fixed-aspect canvases, or square-cell layouts
  for raster art and collision-critical geometry.
- Add a visible minimum-size state instead of silently clipping the ground,
  player, ports, or controls.
- Canvas-heavy effects should minimize full-scene work, object allocation, and
  per-frame path submissions. Prefer layered primitives over blur filters.
- `SoundEffect` instances are created once and replayed through a cabinet-level
  helper that respects `ArcadeData.soundEnabled`.
- Keep sound levels conservative. Repeated effects such as digging, hopping,
  firing, and chain blasts should be quieter than stage-clear or impact cues.
- Pause, records, restart, quit, initials, and Circuit-return behavior should
  remain keyboard accessible.

## Development and validation workflow

From the repository root:

```sh
./omacade-gui                 # lobby
./omacade-gui lander
./omacade-gui rootbound
./omacade-gui packet-hop
./omacade-gui core-command

python3 -m unittest tests.test_omacade
python3 -m py_compile omacade
omarchy-plugin-validate .
git diff --check
```

QML files hot-reload in a running `qs` process. A reload also reconstructs
game state, so watch the process log for `Configuration Loaded` and errors.
For a clean launch use `omacade-gui`, which runs `qs -n -p` and avoids coupling
to another Quickshell instance.

### Protect real player data during live tests

Direct GUI tests use the real files under `~/.local`. A completed unattended
game, synthetic crash, or Circuit preview can alter run counts, `lastRuns`,
achievements, and records.

Before destructive or synthetic score-path testing:

1. Back up `~/.local/share/omacade/scores.json` to a named file under `/tmp`.
2. Prefer a disposable HOME or a preview copy of the QML when practical.
3. If testing only rendering, quit the cabinet before it records a run.
4. Compare and restore the exact original JSON afterward.

Never “clean up” by deleting a score row alone: `stats`, `lastRuns`,
`successful_landings`, and achievements may also have changed.

### Responsive visual QA matrix

For every cabinet, inspect at least:

- one wide/fullscreen-like window;
- one tall half-screen tile;
- one short/wide tile;
- the declared minimum size;
- just below minimum size to verify the warning;
- active play, pause, records, initials, stage transition, and game-over states.

Check collision readability, sprite aspect, HUD collisions, footer clipping,
mouse mapping, keyboard focus, and whether animation load changes noticeably
as the window grows.

## Adding another cabinet

1. Add `game/<id>.qml` and its assets/sounds.
2. Register it in `CabinetRegistry.js`. Registry order currently also defines
   lobby and Circuit order.
3. Use `ArcadeTheme` and `ArcadeData` rather than reading shared files directly.
4. Define a stable score row with enough objective fields for recaps,
   achievements, and future normalization.
5. Implement standalone and `OMACADE_CIRCUIT=1` post-run behavior.
6. Add `runDetail()` and `circuitPoints()` handling in `arcade.qml`. Both
   functions already fail loudly (`console.warn` + a safe zero/fallback
   value) for a cabinet ID they don't recognize, rather than silently
   misattributing it to whichever branch happens to be last — keep that
   invariant if you restructure either function.
7. Decide deliberately whether Circuit should include the new cabinet or stay
   at its current length; don't change Circuit length as an accidental side
   effect of a registry append. (Daemon Swarm, cabinet 05, was added directly
   into Circuit rather than staged as a standalone bonus cabinet — see
   `circuitPoints()`'s `daemon-swarm` branch for its normalization formula,
   still hand-tuned and unplaytested against the original four's balance.)
8. Extend achievements only through backward-compatible derivation — add new
   entries, never redefine what an existing achievement (e.g. "Full Stack")
   means for players who already earned it.
9. Add launcher aliases, README controls, tests, and responsive live QA.

As the games grow, move cabinet-specific helpers into
`game/cabinets/<id>/`. Quickshell uses the entrypoint directory as the import
boundary, so keep reusable framework code under `game/framework/`.

## Major development milestones

- `3bb3ee3` — initial lobby/framework around the completed Lander cabinet.
- `0f8620e` through `000bb98` — Rootbound prototype, movement/input fixes,
  sprites, combat, zones, hazards, and objectives.
- `146a054` through `2ab7bf6` — Packet Hop, sprite/collision scaling,
  fixed-proportion layout, responsive telemetry rails, network mechanics, and
  telegraphed events.
- `cf47746` — shared pilot progression, recaps, records, and achievements.
- `c90771c` through `1cef5a2` — Core Command, targeting, launch balance,
  service abilities, and siege waves.
- `cd7763d` — four-cabinet Circuit orchestration, scoring, continues, recovery,
  and Circuit achievement.
- `72d508e` — Core Command fixed-aspect rendering, neon trails, and frame-pacing
  optimization.

Use `git log --oneline --reverse` for the complete iteration history. The small
commits are useful design evidence: most were driven by live play findings such
as held-key acceleration, unclear collision gaps, misleading sprites, layout
stretching, and expensive full-canvas effects.

## Recommended v1 finish

Feature-freeze the cabinet mechanics, then:

1. Play at least three full Circuits (now five contracts) and tune
   normalization from the split data — Daemon Swarm's formula in particular
   is unplaytested against the original four's balance.
2. Run the responsive QA matrix for all five cabinets.
3. Normalize pause/restart/quit/records wording and sound levels.
4. Add concise first-launch guidance for standalone play versus Circuit.
5. Capture privacy-reviewed screenshots, verify a clean install/removal cycle,
   finalize release notes, and submit the plugin.

After v1, good expansion candidates are daily seeded Circuits, optional
mutators, gamepad support, or a sixth cabinet. They should not delay the
five-cabinet release.
