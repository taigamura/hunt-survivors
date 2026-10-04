# Hunt Survivors

A portrait, one-thumb survivors-like prototype for iPhone, built in **Godot 4.7** (GDScript, Mobile renderer).

Each run is a **hunt**: mow through Musou-scale swarms (1,500+ enemies on screen) to level up, but you win by killing **Ironhorn**, a large monster with breakable horns, tail and back. Your **movement is your combo input**:

- **Great Sword — plant your feet.** Stand still to charge three levels (each level shoves the crowd back); start moving to unleash a wide arc toward where you're heading. Level 3 cleaves everything, with hit-stop.
- **Dual Blades — never stop moving.** Full-deflection movement builds momentum: a faster, wider blade whirl, more speed, and damaging afterimages at 100%. Whip the stick back (>150°) at high momentum for a **dash cut**.

The Musou layer adds officers whose deaths rout their squads, three capturable outposts, a screen-clearing Musou attack, and a big KO counter.

## Run it

**Editor:** install Godot **4.7.x** (standard build), open `project.godot`, press **F5**.

**CLI:** `godot --path .`

Desktop controls (touch is emulated with the mouse):

| Action | Touch (iPhone) | Desktop |
|---|---|---|
| Move | Touch anywhere in the lower 70% and drag (floating stick) | WASD / arrows, or mouse-drag |
| Musou | Big button, bottom corner (left/right in settings) | Space |
| Pause | Top-left button | Esc |

There are no other inputs; attacks are automatic and shaped by how you move.

## Run flow

Title → Weapon Select → Hunt → Results. The monster arrives at 2:00, enrages at 9:00 (or below 30% HP), and escapes at 10:00 (hunt failed). Best KOs and fastest hunt per weapon are saved to `user://save.json`.

## Tuning

Every balance number lives in **`data/tuning.json`** — nothing is hard-coded in gameplay scripts. Curves are `[[time_sec, value], ...]`, linearly interpolated. Edit and re-run; no rebuild step.

Top 5 knobs to playtest first:

1. **`spawner.target_alive` / `spawner.spawn_rate`** — swarm density over time (the core feel, and the perf load).
2. **`enemies.hp_growth_per_min`** — how fast the crowd toughens vs. your build (HP multiplier is `1 + 0.8 × minutes`, so ×8.2 by 9:00).
3. **`monster.max_hp`** + **`monster.parts.*.break_hp`** — length of the Ironhorn fight and how often parts break.
4. **`weapons.great_sword.thresholds`** (+ `planted_damage_mult`, `brace`) and **`weapons.dual_blades.build_time` / `decay_per_sec`** — how each weapon's movement mechanic feels.
5. **`musou.max`**, **`enemies.types.*.ko_musou`**, **`musou.recharge_lock`** — how often the screen-clear fires.

Also handy: `xp.curve_*` (level pace), `camera.zoom`, `controls.dead_zone` / `full_speed_at`, `outposts.*`, `juice.*`, `haptics_ms.*`.

## Swapping in real art

All visuals go through **`autoload/art_registry.gd`**, keyed by ids like `enemy.grunt`, `monster.ironhorn.horns`, `monster.ironhorn.horns_broken`, `outpost.flag`, `fx.slash_arc`, `ui.accent`. Placeholders are generated procedurally at startup.

To replace art without touching code, create **`art/manifest.json`** (see `art/manifest.example.json`):

```json
{
  "enemy.grunt":            { "path": "res://art/grunt.png", "size": [38, 38] },
  "monster.ironhorn.horns": { "path": "res://art/ironhorn_horns.png" },
  "fx.slash_gs3":           { "tint": "#fff6e0" }
}
```

- `path` — texture to use; `size` — world size in px; `tint` — multiply color; `rotate` — whether swarm sprites face their movement direction.
- Sprites are drawn **facing right (+x)**; swarm textures should be mostly white/light so the per-type tint and the white hit-flash read.
- Enemy collision radii are separate (`enemies.types.*.radius` in tuning).

## Verify

All verification is headless (works in CI or over SSH):

```sh
tools/run_checks.sh            # everything below, fails on any test failure or script error
```

| Step | Command |
|---|---|
| Compile every script | `godot --headless --path . res://tools/check_scripts.tscn` |
| Unit tests (47) | `godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn` |
| Smoke run, both weapons, 60 s bot play | `godot --headless --path . --fixed-fps 60 res://tests/smoke.tscn -- seconds=60` |
| Benchmark (500 / 1k / 1.5k / 2k enemies) | `godot --headless --path . --fixed-fps 60 res://scenes/benchmark.tscn` |
| Screen flow (title → … → results) | `godot --headless --path . --fixed-fps 60 res://tools/flow_check.tscn` |

Smoke options: `seconds=600 god=1 arrive=10 weapons=dual_blades seed=3`. With a display you can also capture screenshots: `godot --path . --fixed-fps 60 res://tools/shot.tscn -- weapon=dual_blades frames=300,900 out=/tmp/shots`.

If you add a script with a new `class_name`, run `godot --headless --path . --import` once so the class cache picks it up (`run_checks.sh` does this).

See **PERF.md** for benchmark results and **DECISIONS.md** for every judgment call.

## iOS: build and run on your iPhone

Requirements: a Mac with **Xcode 16+**, the **same Godot version (4.7.x)**, and an Apple ID (a free account works for on-device testing; App Store needs the paid program).

1. **Export templates.** In Godot: *Editor → Manage Export Templates → Download and Install* (must match your editor version).
2. **Set your identity.** *Project → Export…* → select the included **iOS** preset:
   - **App Store Team ID**: your 10-character Team ID (Xcode → Settings → Accounts → your team, or developer.apple.com → Membership).
   - **Bundle Identifier**: replace `com.example.huntsurvivors` with your own, e.g. `com.yourname.huntsurvivors`.
3. **Export the Xcode project.** The preset has *Export Project Only* enabled. Click **Export Project…**, pick an empty folder (e.g. `build/ios/`), keep the name `HuntSurvivors.ipa` (Godot uses it as the project name), uncheck *Export With Debug* for a release build, and export. You'll get `HuntSurvivors.xcodeproj`.
   - CLI alternative: `godot --headless --path . --export-debug "iOS" build/ios/HuntSurvivors.ipa`
4. **Open in Xcode.** Open `build/ios/HuntSurvivors.xcodeproj`. Select the **HuntSurvivors** target → *Signing & Capabilities* → tick *Automatically manage signing* and choose your **Team**. If Xcode complains about the bundle id, make it unique.
5. **Prepare the phone.** Connect the iPhone by cable (or same Wi-Fi after pairing), trust the computer, and enable *Settings → Privacy & Security → Developer Mode* (restart when asked).
6. **Run.** Pick your iPhone as the run destination and press **⌘R**. On first launch with a free account, approve the developer profile under *Settings → General → VPN & Device Management*.

The export is portrait-only and includes the procedurally generated placeholder icon (`art/icon_1024.png`, regenerate with `godot --headless --path . res://tools/make_icon.tscn`). `data/tuning.json` is bundled via the preset's include filter; tests, tools and the benchmark are excluded.

## Shipping to TestFlight

Same Mac build server and pipeline as wildbound. `scripts/ship-ios-godot.sh` (also what `/ship-ios` runs via `.claude/ship.json`) sends the committed `HEAD` to the Mac with `git archive`, imports the signing credentials into a throwaway keychain there, has Godot 4.7.2 write the Xcode project from the `iOS` preset, runs `xcodebuild archive` + `-exportArchive` (`ios/mac-build.sh`), copies the ipa to `dist/ios/`, and uploads it with `eas submit`.

- **Identity:** bundle ID `com.taiga.huntsurvivors`, Apple team `6R43H3SA48`, EAS project `@taigamura/hunt-survivors` (config only, in `eas/`). Version: `application/short_version` in `export_presets.cfg`. Build number: `ios/build-number.txt` holds the last build uploaded; the script builds with +1 and writes it back only after a confirmed submit.
- **Credentials** live on EAS. Download a local copy once (and after any renewal): `cd eas && npx eas-cli@24.10.0 credentials -p ios` → production → credentials.json → Download. That writes `eas/credentials.json` + `eas/credentials/` (gitignored).
- Flags: `--no-submit`, `--unsigned` (no credentials; proves Godot + Xcode compile), `--sync-local` (build the uncommitted tree; test only), `--build-number N`.
- **History** (newest first):
  - 2026-10-04: pipeline set up; unsigned Mac build verified (Godot export + `xcodebuild archive` OK).

## Project layout

```
project.godot            portrait 720×1280 base, canvas_items/expand stretch, Mobile renderer
data/tuning.json         every balance number
autoload/                Tuning, ArtRegistry, GameState (settings, safe area), Save
systems/                 EnemySystem, FlowField, SpatialHash, Spawner, XPSystem, Progression,
                         UpgradePool, FX, Particles, DamageNumbers, GroundPatches, BotInput, Geom,
                         HuntContext (the API weapons/monster use)
player/                  Player, weapons/ (GreatSword, DualBlades), subweapons/ (Orbit, Thunder, Flame)
monster/                 Ironhorn (state machine, telegraphs, breakable parts)
musou/                   Outposts, MusouGauge (officers/rout live in EnemySystem + Hunt)
ui/                      HUD, TouchStick, LevelUpUI, PauseMenu, Title, WeaponSelect, Results, UIKit
scenes/                  hunt.tscn (one run, orchestrates all systems), benchmark.tscn
tests/                   test runner + unit tests, smoke run, FakeHunt
tools/                   run_checks.sh, script checker, flow check, screenshots, icon generator
```

The swarm is data-oriented: enemies are rows in packed arrays rendered with one `MultiMeshInstance2D` per type. `scenes/hunt.gd` runs every system explicitly each frame in a fixed order (input → player → weapons → flow field → swarm → monster → outposts → XP → spawner → timeline → FX → camera → HUD), which keeps timing deterministic and measurable.

## Known gaps

- No audio.
- Balance comes from bot telemetry, not human playtests (see tuning knobs above).
- Placeholder art is deliberately plain; the monster is a stack of simple shapes.
- Not yet profiled on a physical iPhone (no device in the build environment); see PERF.md.
