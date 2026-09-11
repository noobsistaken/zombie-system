# Zombie system

The server simulates zombie movement and validates shots. Clients render the
zombies, handle weapon input, and update the viewmodel and tracers.

## Modules

`src/server` maps to `ServerScriptService.Server`, `src/client` to
`StarterPlayer.StarterPlayerScripts.Client`, and `src/shared` to
`ReplicatedStorage.Shared`. Services and controllers are ordinary modules with
a `start()` function. Entry points require them in dependency order.

The server starts zombie simulation before binding weapon requests. The client
starts zombie visuals and the viewmodel before weapon input. Modules use direct
requires. Shared modules provide configuration, spatial queries, and steering math.

## Networking

`net/schema.zap` defines the wire format. Zap 0.6.29 generates the client module
at `ReplicatedStorage.Net` and the server module at `ServerScriptService.Net`.

| Message | Direction | Kind | Purpose |
| --- | --- | --- | --- |
| ZombieSnapshot | Server to clients | Reliable event | Positions and alive/dead state at 10 Hz |
| Shoot | Client to server to client | Async function | Shot origin, direction, optional zombie ID, and boolean result |
| HitConfirmed | Server to client | Reliable event | Position of the confirmed hit |

Snapshots are maps keyed by zombie ID, with `P` for position and `H` for health.
IDs use f64 and positions use Vector3. Dead zombies stay in snapshots for one
second, and respawns are queued for three seconds after death. The client hides
local hits until the server confirms the death.

WeaponService checks the firing rate, shot origin, distance along the ray, and
hit radius. Shot requests return a Promise so the render callback can continue
while waiting for the server.

## Dependencies

Packages are pinned in `wally.toml` and `wally.lock`.

| Package | Version | Role |
| --- | --- | --- |
| Promise | 4.0.0 | Async shot result |
| Signal | 2.0.3 | Available for local events |
| Janitor | 1.18.3 | Cleanup |
| Charm | 0.11.0 | Available for reactive state |
| React / ReactRoblox | 17.2.1 | Available for UI |
| ProfileStore | 1.0.3 | Available in ServerPackages |
| Jest / JestGlobals | 3.10.0 | Studio tests, DevPackages only |

ProfileStore is installed for future persistence work; no sessions are opened.
Manage vendored packages through Wally.

## Simulation

The server reuses a neighbor buffer and numeric spatial-grid columns. Separation
filters by the smaller of the search radius and separation radius in one pass.
The steering math and busy loops request native compilation. Single-player
targeting skips the swarm-centroid calculation; multiplayer targeting retains it.
Simulation runs every Heartbeat, with snapshots at 10 Hz.

Separation uses squared distances to avoid square roots in the neighbor loop.

## Tests

Run `scripts/verify.ps1` for Luau analysis, lint, formatting, regression tests,
and Rojo builds. Use `build/test.rbxl` for Studio tests and a Play session to
check startup, rendering, and network messages.

Use Rojo 7.7.0 and its matching Studio plugin on `127.0.0.1:29292`.
