# Zombie system

**Author:** noobs

A zombie swarm simulation with client rendering and first-person weapons.
Uses Zap for networking and Wally for packages. See
[ARCHITECTURE.md](ARCHITECTURE.md) for the module layout and network messages.

[Original demo](https://youtu.be/4DUHov4aRN4)

## Setup

From the repository root:

```sh
rokit install
wally install
rojo serve default.project.json --address 127.0.0.1 --port 29292
```

Connect the Rojo **7.7.0** Studio plugin to **localhost:29292**.

WASD to move, mouse to aim, and left click to shoot in first person.

## Development

Edit `net/schema.zap` when changing messages, then regenerate:

```sh
zap --no-warnings net/schema.zap
```

Commit the schema and generated output together. Packages are vendored from
Wally; install them with Wally instead of editing their source.

Run the local checks in PowerShell:

```powershell
./scripts/verify.ps1
```

This runs the Lune regression suite, Selene, StyLua, strict Luau analysis, and
both Rojo builds. It uses the pinned tools on PATH and writes places to `build/`.

The 17 Lune tests cover spatial queries, steering, springs, zombie lifecycle
and snapshots, client interpolation, weapon
input, and server hit validation. They use Roblox datatypes with mocked engine
services. Run them separately with `lune run scripts/tests/run.luau`.

Open `build/test.rbxl` in Studio and run this from the Command Bar:

```lua
require(game.ServerScriptService.Tests)()
```

Read Output for `[tests]` results. Jest needs Studio's source-reading permission
and `LoadStringEnabled`, which is enabled only in the test project. Running it
from an ordinary server Script cannot read module sources.

Press Play to check the normal server and client: zombies render, movement and
viewmodel updates run, and shots receive results over Zap. Local static checks
do not replace this Studio check.

Benchmark results are in [PERFORMANCE.md](PERFORMANCE.md).
