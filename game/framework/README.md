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
and compatibility with Lander's original score format.

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
