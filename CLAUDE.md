# Hunt Survivors

Portrait, one-thumb survivors-like for iPhone, built in **Godot 4.7.2** (GDScript, Mobile renderer). Repo: https://github.com/taigamura/hunt-survivors (public, `main`).

`README.md` is the player/dev manual (controls, tuning knobs, art swapping, verify commands, project layout). `DECISIONS.md` records every design judgment call, `PERF.md` the benchmark. Read those before changing gameplay; this file is the current state and the working rules.

## Current state (2026-10-04)

- **Playable prototype, feature-complete for the brief.** Title → Weapon Select → Hunt → Results. Two weapons with movement-driven combos (Great Sword: stand still to charge, move to release; Dual Blades: keep moving for momentum, whip the stick back for a dash cut). Musou layer: squads with officers whose deaths rout them, 3 capturable outposts, screen-clearing Musou attack, KO counter. Boss: **Ironhorn** arrives at 2:00, enrages at 9:00 or below 30% HP, escapes at 10:00 (hunt failed); horns, tail and back break separately. Three subweapons (Orbit Shards, Thunder Call, Flame Wake) plus passives via level-up cards. Best KOs / fastest hunt saved per weapon.
- **On TestFlight:** v0.1.0 build 1, uploaded 2026-10-04 (App Store Connect app `6819005826`). The owner is in the internal "Team (Expo)" group, which gets every new build automatically. Not submitted for App Store review; no store listing yet.
- **Not yet played on a real iPhone.** Balance comes from bot telemetry (`systems/bot_input.gd`), not human playtests. Device perf is unmeasured; the debug build shows an fps / enemy-count line above the XP bar.
- **Known gaps:** no audio; placeholder procedural art (monster is stacked shapes); no human balance pass.

## Architecture in one paragraph

Data-oriented swarm: enemies are rows in packed arrays (no node per enemy), drawn with one `MultiMeshInstance2D` per type. `scenes/hunt.gd` runs every system explicitly each frame in a fixed order (input → player → weapons → flow field → swarm → monster → outposts → XP → spawner → timeline → FX → camera → HUD). Weapons and the monster talk to the world only through `systems/hunt_context.gd`. **Every balance number lives in `data/tuning.json`**; gameplay scripts must not hard-code values. All visuals go through `autoload/art_registry.gd` ids (override via `art/manifest.json`). Menus and HUD are built in code (`ui/ui_kit.gd`), not authored Control scenes.

## Verifying changes

```sh
tools/run_checks.sh   # script compile, 47 unit tests, 60 s bot smoke run (both weapons), benchmark, screen-flow check
```

- Everything must pass except, possibly, the **benchmark**: its 6 ms budget at 1,500 enemies is CPU-sensitive. On this box (Ryzen 7 3700X under steady background load, ~7–8 load average) it measures ~6.2 ms and fails; `PERF.md` records 3.3 ms on a quiet 2-core VM. Treat a benchmark-only failure as machine load unless the per-system breakdown regresses relative to `PERF.md` (the owner accepted this on 2026-10-04).
- A new `class_name` needs `godot --headless --path . --import` once (`run_checks.sh` does it).
- Screenshots need a display: `godot --path . --fixed-fps 60 res://tools/shot.tscn -- weapon=dual_blades frames=300,900 out=/tmp/shots`.

## Shipping to TestFlight

`/ship-ios` (config in `.claude/ship.json`) or directly `scripts/ship-ios-godot.sh`. Same Mac build server and pipeline as wildbound (`192.168.50.175`, key `~/.ssh/simple-bookkeeping-buildserver`). Full details and the release **History** live in `README.md` → "Shipping to TestFlight"; that is the file `/ship-ios` appends to.

- Workflow is `direct`: commit and push to `main`, then run the script. It builds the **committed HEAD** (`git archive`), so uncommitted changes never ship.
- Identity: bundle `com.taiga.huntsurvivors`, team `6R43H3SA48`, EAS project `@taigamura/hunt-survivors` (config only, in `eas/`; `ascAppId` pinned in `eas/eas.json`, so submits are non-interactive).
- Version is `application/short_version` in `export_presets.cfg` (0.1.0). `ios/build-number.txt` holds the last uploaded build (1); the script uses +1 and writes it back after a confirmed submit. Commit that file with the History entry.
- Signing credentials: `eas/credentials.json` + `eas/credentials/` (gitignored, never commit). Re-download with `cd eas && npx eas-cli@24.10.0 credentials -p ios` in a real terminal (it is interactive; the `!` prefix has no TTY).
- `eas/` and `ios/` contain a `.gdignore` so Godot does not import `node_modules` or the scripts.
- Uploading only puts the build in TestFlight; external testers, the store listing and App Store review are manual App Store Connect steps.
