# Omacade cabinet framework

Each graphical game is an independent Quickshell process registered in
`CabinetRegistry.js`. The arcade lobby launches one cabinet at a time and
returns when that process exits, keeping game loops isolated from each other
and from Omarchy's long-running shell.

## Cabinet contract

A cabinet entry provides:

- a stable `id` and `scoreKey`;
- display metadata (`number`, titles, tagline, description, controls);
- an `entry` QML path relative to `game/`;
- a `status` of `ready` before it becomes launchable.

Cabinet QML should instantiate `ArcadeTheme` for the current Omarchy palette
and `ArcadeData` with its registered `scoreKey`. `ArcadeData` owns the shared
settings file, top-ten persistence, initials, per-cabinet completion counts,
last-run summaries, personal-best flags, achievement unlocks, and compatibility
with Lander's original score format. Existing score files are migrated in
memory so historical runs immediately receive any achievements they satisfy.

The shared achievements currently cover first completion, a fuel-efficient
landing, reaching Rootbound's `/ROOT` zone, binding five Packet Hop ports in one
run, clearing Core Command with every service online, and recording runs across
the original trio and the full four-cabinet stack. Completing the four-contract
Omacade Circuit unlocks its own badge and stores a normalized split table under
the `circuit` score key. New cabinets may add fields to their score row and
extend `ArcadeData.evaluateAchievements()` without changing the launcher contract.

Each cabinet remains responsible for its own physics, rendering, input,
cabinet-specific settings, and sound assets. Closing it returns control to the
lobby automatically.

## Adding a cabinet

1. Create its executable entrypoint as `game/<id>.qml`; Quickshell uses the
   entrypoint directory as its import boundary. Put supporting components and
   assets under `game/cabinets/<id>/` as the cabinet grows.
2. Add one metadata object to `CabinetRegistry.js`.
3. Use `ArcadeTheme` and `ArcadeData { cabinetId: "<scoreKey>" }`.
4. Store score rows through `ArcadeData.recordScore()`.
5. Add cabinet-specific tests and validate both direct and lobby launches.
