# Performance

Budget from the brief: **enemy sim + hit queries < 6 ms per frame at 1,500 enemies** on a desktop CPU.

## Result: PASS

`scenes/benchmark.tscn`, Godot 4.7.2, headless, `--fixed-fps 60`.
CPU: Intel Xeon @ 2.10 GHz, 2 cores (a cloud VM).

The hunter runs a circle with Dual Blades (continuous whirl) plus Orbiting Shards and Thunder Call at level 3; the swarm is refilled to the target count every frame (kills are replaced). 10 s of simulated time per row, after a 0.5 s warm-up.

| Enemies | Sim avg | Sim p95 | of which: weapons | flow field | swarm step | Render avg (MultiMesh fill) |
|---:|---:|---:|---:|---:|---:|---:|
| 500  | 1.35 ms | 1.75 ms | 0.04 ms | 0.37 ms | 0.94 ms | 0.32 ms |
| 1000 | 2.28 ms | 2.92 ms | 0.05 ms | 0.37 ms | 1.86 ms | 0.60 ms |
| **1500** | **3.30 ms** | **4.59 ms** | 0.06 ms | 0.33 ms | 2.91 ms | 0.92 ms |
| 2000 | 4.04 ms | 4.72 ms | 0.06 ms | 0.30 ms | 3.69 ms | 1.15 ms |

- **Sim** = weapon hit queries + flow-field update + swarm step (spatial-hash rebuild, steering, separation, knockback, collision). This is the 6 ms budget.
- **Render** = writing the MultiMesh buffers (one per enemy type) and handing them to the RenderingServer. Reported separately; GPU cost is not measured headless.
- Even at 2,000 enemies both the average and p95 stay under the 6 ms budget.

Reproduce:

```sh
godot --headless --path . --fixed-fps 60 res://scenes/benchmark.tscn
# results also written to user://bench.json
```

## What made it fit

1. **No nodes per enemy.** Enemies are rows in packed arrays with a free-list; spawn/despawn are O(1) swap-removes.
2. **One MultiMesh per enemy type**, buffers rebuilt in place (copy-on-write avoided by taking ownership of the array while writing) and pushed with `RenderingServer.multimesh_set_buffer`.
3. **Fixed custom AABB on the MultiMeshes.** Besides skipping a per-frame bounds recompute, this fixed a real bug: Godot's auto-computed bounds lagged behind the per-frame buffer and culled the entire swarm when the hunter moved.
4. **Counting-sort spatial hash** over a window that follows the hunter (80 px cells): two linear passes, no per-cell arrays, no allocations.
5. **Time-sliced flow field.** BFS over an 84×84 window of 40 px cells is built in a back buffer at ~1,400 cells per frame and swapped in when complete. A synchronous rebuild cost ~8 ms and showed up as p95 spikes of 8–13 ms; slicing removed them.
6. **Inlined hot path.** Obstacle checks and flow-field sampling are inlined into the swarm loop (GDScript function-call overhead dominated). Enemies steer straight at the hunter and only consult the field when a two-point look-ahead along that line hits an obstacle; each field cell caches its downhill target point lazily. (This also fixed a visual artifact: pure 4-neighbor BFS fields funnel crowds into axis-aligned lanes.)
7. **Cheap separation.** Each enemy checks at most 4 neighbors in its own cell, on alternating frames.
8. **Capped juice.** Damage numbers (60), particles (350) and XP gems (400, merging into bigger gems past the cap) are pooled ring buffers.

## Device notes

- Not yet measured on a physical iPhone. Recent A-series cores are generally in the same class as (or faster than) this VM's per-core speed, so 1,500 enemies at 60 fps is the expectation — confirm with the debug fps / enemy-count line (debug builds) before raising `spawner.target_alive`.
- The swarm draws in ~4 batched draw calls regardless of count; the per-frame CPU→GPU upload is ~96 KB per type at the 2,000 cap.
- If you need more headroom later, `EnemySystem` exposes a narrow API (`spawn`, `despawn`, `damage`, `kill`, `rout_squad`, `query_*`, `step`) designed to be ported to a GDExtension (C++) without touching gameplay code.

## Per-weapon cost (2026-10-04, after the gesture/new-weapon update)

`benchmark.tscn -- weapon=<id>` swaps the benchmark's main weapon (default `dual_blades`). At 1,500 enemies on the Ryzen 7 3700X dev box (under background load), the weapons slice of the frame is small for every weapon: Bulwark 0.03 ms, Hand Cannon 0.04, Dual Blades 0.04, Twin Fangs 0.10, Assault Rifle 0.16 (vs ~4.6 ms for the swarm step). Guns are hitscan (`HuntContext.shoot` = one `query_line` + a partial sort by distance), and they only run range queries when a round is due. Gesture moves are not exercised by the benchmark; the heaviest (Gun Kata: 8 rounds every 0.1 s) is about 8 line queries on its firing frames.

Enemy sight/lead/flank AI (same day) adds about 0.5 ms to the swarm step at 1,500 enemies on the dev box (sim avg 5.1 → 5.8 ms, under background load): a per-enemy goal point (lead + flank offset) and an extra square root. Still under the 6 ms budget here, but the headroom is thinner; check device fps at swarm peak.
