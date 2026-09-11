# Server performance

Paired Studio benchmark with 100 zombies and one stationary player.

| Server update cost | Before | After |
| --- | ---: | ---: |
| Mean | 0.132 ms | 0.087 ms |
| Median | 0.113 ms | 0.079 ms |
| 95th percentile | 0.238 ms | 0.148 ms |

Mean update time fell **33.9%**. These timings measure the server update
callback, not overall server CPU usage.

## Workload

Both versions ran in the same Studio server with one stationary player and 100
zombies spawned using seed 7280. After 1,200 warmup frames, the harness timed
600 updates per version, alternating execution order each frame. Each received
the same Heartbeat delta. Timing covered the real update callback, including
steering, lifecycle work, and snapshot serialization. It excluded the generated
network flush callback, engine work, and client work. Periodic debug logging
was postponed in both benchmark copies.

The baseline allocated neighbor lists and used string keys for grid cells.
The current version reuses a neighbor buffer and uses numeric keys.
Raw results are in [performance-results.json](performance-results.json).

## Changes

- Reuse the neighbor-query buffer instead of allocating and copying state for
  every zombie on every frame.
- Index spatial-grid columns numerically instead of constructing cell strings.
- Filter separation distances once, using squared distances.
- Request native compilation for the numeric loops.
- Skip the centroid calculation for a single player and remove expired deaths
  without allocating a removal list.

Both versions used the same movement settings and snapshot rate. Floating-point
rounding can change individual paths in the crowded swarm; the paired run ended
with a maximum position difference of 1.601 studs after 1,800 steps.

For comparable results, keep the zombie count, player count, and viewing
conditions the same, and let the swarm bunch up before measuring.
