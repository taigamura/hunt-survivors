# Hunt Survivors

Portrait survivors-like for iPhone (one thumb moves; an optional second thumb draws gesture moves), built in **Godot 4.7.2** (GDScript, Mobile renderer). Repo: https://github.com/taigamura/hunt-survivors (public, `main`).

`README.md` is the player/dev manual (controls, tuning knobs, art swapping, verify commands, project layout). `DECISIONS.md` records every design judgment call, `PERF.md` the benchmark. Read those before changing gameplay; this file is the current state and the working rules.

## Current state (updated 2026-10-04)

- **Playable prototype.** Title → Weapon Select → Loadout → Hunt → Results. **Six weapons**, each with a movement-driven auto-attack (thumb 1): Great Sword (stand still to charge, move to release), Dual Blades (momentum, whip back to dash-cut), Bulwark (sword & shield: walk/stand to block frontal hits, blocks charge a counter-bash), Hand Cannon (pistol: stand still to steady), Twin Fangs (dual pistols: fire to your flanks while moving, snap-turn spin), Assault Rifle (spin-up stream along your heading).
- **Two-thumb gesture layer** (added 2026-10-04): the half of the screen opposite the stick is a gesture pad. Tap / swipe / hold fire moves picked on the Loadout screen (saved per weapon); level-up cards unlock shape gestures (circle, V, zigzag, triangle) and level moves to 3. A move fired just before a telegraphed Ironhorn attack lands is a PERFECT counter (cancels the attack). Settings: Move Stick Left/Right.
- **Musou attack/gauge removed** (owner's call, 2026-10-04). Kept: squads with officers whose deaths rout them, 3 capturable outposts, KO counter.
- Boss: **Ironhorn** arrives at 2:00, enrages at 9:00 or below 30% HP, escapes at 10:00 (hunt failed); horns, tail and back break separately. Three subweapons (Orbit Shards, Thunder Call, Flame Wake) plus passives via level-up cards. Best KOs / fastest hunt saved per weapon.
- Units were enlarged for readability (camera zoom 1.0, bigger sprites) on 2026-10-04.
- **On TestFlight:** v0.1.0 build 1, uploaded 2026-10-04 (App Store Connect app `6819005826`). The owner is in the internal "Team (Expo)" group, which gets every new build automatically. Not submitted for App Store review; no store listing yet.
- **TestFlight build 1 predates the gesture layer, new weapons and Musou removal**; ship a new build to test them on device.
- **Not yet played on a real iPhone.** Balance comes from bot telemetry (`systems/bot_input.gd`), not human playtests. Device perf is unmeasured; the debug build shows an fps / enemy-count line above the XP bar.
- **Known gaps:** no audio; placeholder procedural art (monster is stacked shapes; all six weapons share the hunter sprite); no human balance pass; gesture recognizer thresholds tuned on synthetic strokes only, not real thumbs.

## Where we left off / next steps

Last session (2026-10-04, second half) added the two-thumb gesture layer, the Loadout screen, four weapons (Bulwark, Hand Cannon, Twin Fangs, Assault Rifle), removed the Musou attack, enlarged units, and fixed Ironhorn wedging between rocks. Earlier the same day: first TestFlight upload (build 1, pre-gestures).

Open, in rough priority order:
1. **Ship build 2 and playtest on device**: gesture recognition with real thumbs (`gestures.*` thresholds), stick/gesture halves and safe-area layout, perfect-counter timing (`gestures.perfect_window`), feel of all six weapons, and fps / enemy count at swarm peak (the 1,500-enemy target has never run on an iPhone).
2. **Balance from human play**: start with the top-5 knobs in `README.md` → Tuning (`data/tuning.json`). Bot telemetry for the new weapons is in DECISIONS.md / the smoke log only.
3. **Audio** (none exists).
4. **Real art** via `art/manifest.json` (placeholders are procedural).
5. Before any App Store release: store listing, privacy policy, screenshots; the Mobile renderer requires an A12+ device (iPhone XS or newer), so settle device requirements before the first public release.

**Keep this file current:** when a session changes what the game does, ships a build, or finishes/starts one of the items above, update "Current state" and this section in the same commit.

## Architecture in one paragraph

Data-oriented swarm: enemies are rows in packed arrays (no node per enemy), drawn with one `MultiMeshInstance2D` per type. `scenes/hunt.gd` runs every system explicitly each frame in a fixed order (input → gestures → player → weapons → flow field → swarm → monster → outposts → XP → spawner → timeline → FX → camera → HUD). Weapons and the monster talk to the world only through `systems/hunt_context.gd` (guns use its hitscan `shoot`). Gestures: `ui/gesture_pad.gd` (touch) → `systems/gesture_recognizer.gd` (classify) → `Hunt.perform_gesture` → `player/move_set.gd` (binding, cooldown, level) → `Weapon.perform_move`. **Every balance number lives in `data/tuning.json`**; gameplay scripts must not hard-code values. All visuals go through `autoload/art_registry.gd` ids (override via `art/manifest.json`). Menus and HUD are built in code (`ui/ui_kit.gd`), not authored Control scenes.

## Verifying changes

```sh
tools/run_checks.sh   # script compile, 80 unit tests, 60 s bot smoke run (all six weapons), benchmark, screen-flow check
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
