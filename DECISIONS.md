# Decisions

One line each: choices made where the brief was ambiguous or silent.

- Engine pinned to Godot 4.7.2 (latest stable at build time); project uses only core features, so later 4.x patch releases should open it unchanged.
- Godot 4.7 ships a native `VirtualJoystick` class, so the floating stick is named `TouchStick` to avoid the clash.
- `bundle id com.example.huntsurvivors` is a placeholder — **must be changed** to your own reverse-DNS id before signing; App Store Team ID is intentionally left blank.
- iOS preset is "Export Project only" (Xcode project), no device signing attempted, per the brief.
- Enemy types: grunt, runner (fast/fragile, from ~1:00), brute (tanky, from ~2:30), officer (squad leader); only the officer does not rotate so its banner stays upright.
- Squad soldiers routed by an officer's death count as KOs immediately (Musou-style), drop XP where they stood, then flee and despawn; killing a fleeing soldier later does not double-count.
- Musou kills never refill the Musou gauge, and the gauge is locked for 20 s after a Musou; without both, a full screen of KOs instantly re-filled it and chained Musous forever.
- Musou gauge gain per KO is fractional (0.25 per grunt) so the first Musou lands around 1.5–2 min and roughly every 30–60 s after.
- Great Sword got two defensive additions to make "plant your feet" viable in a 1,500-enemy swarm: a planted stance (50% damage taken while charging) and a short "brace" shove each time a charge level is reached; a release also grants 0.3 s of i-frames.
- Great Sword "Steady Grip" interprets "charge retains 50% after moving" as: after a release, the next charge starts at 50% of the charge you just spent.
- Dual Blades reversal is detected against a smoothed heading (~0.15 s), with a 0.22 s grace so a thumb passing through the dead zone still counts; circling the stick never triggers a dash cut.
- Dual Blades momentum builds only above 80% (post-curve) deflection and also grants up to +18% move speed.
- Dual Blades "Burning Cut" leaves a flame line along the dash cut (re-using the burning-ground system).
- Lingering ground damage (afterimages, flames) deals 30% damage to the monster; otherwise stacked patches melted Ironhorn in ~30 s.
- Ironhorn has 14,000 HP (bot telemetry: a level-30 build takes it to roughly half in ~2 minutes); part break thresholds: horns 900, tail 800, back 1,300 (part damage is tracked separately from body HP).
- Ironhorn's tail sweep is a 270° arc centered on its rear (the 90° wedge in front of it is safe); its charge crushes swarm enemies (they count as your KOs) and stops early if it slams into a rock.
- Ironhorn pursues using the same flow field as the swarm so it routes around rocks instead of grinding against them.
- When the monster "flees" at 10:00 the hunt fails immediately (with a banner), rather than continuing without a target.
- Captured outposts suppress spawns within 1,300 px (35% spawn rate), heal 6 HP/s inside, and give +10% damage each; the bonus stacks.
- Level-up cards: main-weapon upgrades are weighted slightly higher than passives; when everything is maxed a "Field Ration" (heal 30%) card is offered.
- XP curve: `8 + 5·(L−1) + 0.5·(L−1)²` per level — a good run reaches roughly level 25–35 by the time Ironhorn falls.
- Swarm HP grows 80% per minute (×8 at 9:00) so late-game builds don't trivialize the crowd.
- Swarm steering goes straight at the hunter and only follows the flow field when a look-ahead along that line hits a rock (pure grid fields funnel crowds into axis-aligned lanes); each enemy also has a small fixed heading "wobble" so crowds fan out.
- The flow-field BFS is time-sliced (~1,400 cells/frame into a back buffer, swapped when complete) to avoid frame spikes; enemies outside its 84×40 px window head straight for the hunter.
- MultiMeshes use a fixed custom AABB: Godot's auto-computed bounds were stale under per-frame `multimesh_set_buffer` and culled the whole swarm off-screen.
- Placeholder FX (slashes, rings, telegraphs) are drawn procedurally; their colors still come from ArtRegistry ids (`fx.*`), and sprites can be overridden via `art/manifest.json` without code changes.
- Menus and HUD are built in code (no hand-authored Control scenes) so the look is defined in one place (`ui/ui_kit.gd` + ArtRegistry colors).
- Desktop testing: WASD/arrows move at full deflection, mouse drag emulates the touch stick (`emulate_touch_from_mouse`), Space = Musou, Esc = pause, Enter on the title = start.
- Settings and best scores persist in `user://save.json`; screen shake has three modes (Full / Reduced / Off).
- Debug builds show a small fps / enemy-count line above the XP bar; release exports hide it.
- No audio in this prototype (placeholder blips were optional).
- Smoke runs use a scripted "competent-ish" bot (`systems/bot_input.gd`) that kites, plants/charges, captures outposts and dodges telegraphs; it is for coverage and rough balance telemetry, not a skill benchmark.
