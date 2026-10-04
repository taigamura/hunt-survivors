# Decisions

One line each: choices made where the brief was ambiguous or silent.

- Engine pinned to Godot 4.7.2 (latest stable at build time); project uses only core features, so later 4.x patch releases should open it unchanged.
- Godot 4.7 ships a native `VirtualJoystick` class, so the floating stick is named `TouchStick` to avoid the clash.
- iOS identity: bundle id `com.taiga.huntsurvivors`, team `6R43H3SA48` (originally placeholders; set 2026-10-04 for the first TestFlight upload).
- iOS preset is "Export Project only" (Xcode project); signing and `xcodebuild` are done by `ios/mac-build.sh` on the Mac build server, not by Godot.
- Enemy types: grunt, runner (fast/fragile, from ~1:00), brute (tanky, from ~2:30), officer (squad leader); only the officer does not rotate so its banner stays upright.
- Squad soldiers routed by an officer's death count as KOs immediately, drop XP where they stood, then flee and despawn; killing a fleeing soldier later does not double-count.
- The Musou attack and gauge were removed (2026-10-04, owner's call); officers/rout, outposts and the KO counter stay as crowd texture.
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
- Desktop testing: WASD/arrows move at full deflection, mouse drag emulates touch (left half = stick, right half = gestures), J/K/L = tap/swipe/hold, 1–4 = circle/V/zigzag/triangle, Esc = pause, Enter on the title = start.
- Settings and best scores persist in `user://save.json`; screen shake has three modes (Full / Reduced / Off).
- Debug builds show a small fps / enemy-count line above the XP bar; release exports hide it.
- No audio in this prototype (placeholder blips were optional).
- Smoke runs use a scripted "competent-ish" bot (`systems/bot_input.gd`) that kites, plants/charges, captures outposts and dodges telegraphs; it is for coverage and rough balance telemetry, not a skill benchmark.

## Two-thumb gestures (2026-10-04)

- Design rule: one thumb stays fully playable (every weapon auto-attacks from movement); the second thumb adds optional moves. Nothing requires two thumbs.
- Screen split by halves: the move stick claims touches in its half (left by default, lower 70%), the gesture pad claims the other half below a 14% HUD band. A "Move Stick: Left/Right" setting replaced the old Musou-button-side setting. Zones beat "first touch = stick" because a planted Great Sword/Hand Cannon player has no stick touch, so their gesture would otherwise become a stick.
- Gestures: tap, swipe, hold (detected live after 0.3 s still; drag while held to aim), and four shapes: circle, V, zigzag, triangle. Double-tap was dropped: recognizing it delays every single tap, and taps must be instant for perfect counters.
- Recognizer v2 (2026-10-04, after the first device test of build 2: "triangles and tap-and-hold aren't recognized"). v1 counted sharp corners, but real thumbs round every corner and rarely close a triangle; its tap/hold tolerances were 22–26 viewport px (about 2 mm on an iPhone), so a thumb rolling into the glass broke most holds. v2: (1) tolerances are physical mm (tap/hold 6 mm, swipe 7 mm, shapes 9 mm) via the device DPI; (2) net turning splits closed shapes (circle, triangle: 200°+ with the ends near each other) from open ones (V, zigzag), and an open stroke turning one way evenly (a C) is rejected; (3) a $1-style template matcher picks within the group (templates for every start corner, both directions, several proportions, triangles left slightly open). On 240 random sloppy strokes v2 recognizes 239 (v1: triangles 49/60); a pad test feeds real touch events with 4 mm of thumb roll. Gentle arcs still count as swipes.
- Aim: swipe/V/zigzag strokes and held-and-dragged holds aim along the stroke; tap, circle, triangle and an undragged hold auto-aim (Ironhorn's nearest unbroken part if within range, else the nearest enemy, else facing). Tapping toward a screen point was rejected: the gesture half only covers one side of the hunter.
- Customization: tap/swipe/hold moves are picked per hunt on a Loadout screen (saved per weapon); shapes are unlocked by "New Gesture" level-up cards (from level 3) that pair a random free shape with a random move you don't have; "Gesture Move" cards level a bound move to 3 (+30% damage, −12% cooldown per level). A move can be bound to only one gesture.
- Every weapon's pool = its own 4–5 moves + 2 shared (Dodge Roll, Call Lightning, which scales with Thunder Call). Moves that can't fire (Whirlwind without charge, Point Blank with no target) spend no cooldown.
- Perfect counter: any move fired in the last 0.3 s of a telegraph that would hit you cancels the attack into Ironhorn's recovery (+0.4 s), grants 0.7 s of i-frames, and hits 1.5× harder. The first version staggered Ironhorn instead; a frame-perfect bot then chain-countered it into a permanent stagger, so it now only cancels. The smoke bot attempts a counter on 40% of telegraphs.

## New weapons (2026-10-04)

- Shield is its own weapon (Bulwark), not an off-hand: an off-hand conflicts with the two-handed Dual Blades/Twin Fangs. Its guard is up below full stick (walking or standing), so "run to reposition, walk to hold the line" is the movement mechanic.
- Bulwark blocks only frontal hits (150°); swarm contact damage now reports which enemy touched you (`EnemySystem.last_contact_pos`) so blocks can be directional. Weapons see incoming damage via `Weapon.modify_incoming(amount, from)`.
- Guns are hitscan (`HuntContext.shoot`: nearest `pierce` enemies along the ray, Ironhorn stops the round), not projectiles: no new per-frame system, deterministic for tests, and tracers sell the hit.
- Hand Cannon auto-aims at Ironhorn's nearest unbroken part, making it the part-breaker; Twin Fangs fire perpendicular to your heading (aim by choosing which way to run); the Assault Rifle aims only when a round is due (range queries are the expensive part).
- Guns kill far from the hunter, so their XP lands far away: each gun gets `magnet_mult` (pistol 2.0, rifle 1.7, dual pistols 1.5). Without it the pistol bot hit 700 KOs at level 6.

## Readability (2026-10-04)

- Owner found units hard to see: camera zoom 0.8 → 1.0, player sprite 46 → 62 px (radius 15 → 19), enemy sprites ~+25% (grunt 38 → 48) with collision radii scaled ~+25%, XP gems 16 → 20. Net on-screen size is roughly +55–65%.

## Monster pathing fix (2026-10-04)

- Ironhorn could wedge forever between two rocks: the flow field is built for small enemies, so it routed through gaps the 86 px body (rock collision 0.8 × body) couldn't pass. Its rock collision radius is now 30 px (`monster.rock_collision_radius`; it shoulders through, overlapping rock edges), it slides along rocks instead of grinding into them, and if it makes no progress it chases directly for 2 s, then crashes through rocks for 1.2 s.

## Enemy AI: sight, intercept, flank (2026-10-04)

- Owner: Flame Wake was OP because every enemy homed on the hunter forever, so a running hunter dragged the whole swarm single-file through its own fire. Enemies now:
  - **see** only within `enemies.sight_radius` (720 px, about a screen). In sight they track you; out of sight they walk to where they last saw you, mill there for `lost_time` (3 s), then give up and despawn without XP, so the spawner recycles them around you (from all sides, still biased ahead of your movement).
  - **lead** a moving hunter (aim `lead_factor` 1.0 × up to `lead_max` 2 s ahead) and **flank** (per-enemy side offset, half the distance up to 220 px), so a chasing crowd fans out and cuts across your path.
- Measured with a probe that runs the flame-trail exploit (full-speed loop, Flame Wake level 5, 90 s): crowd within 320 px of the hunter went from 9% ahead / 48% behind to 28% / 28% (rifle) and 16% / 43% → 38% / 25% (Great Sword); fire hits per KO fell from ~1.0 to ~0.4 (rifle); time in contact with enemies rose (Great Sword 8% → 19% of frames). A full-speed runner is still hard to touch (it is 3× faster than a grunt); if the trail is still too strong in play, `subweapons.flame_wake.levels` is the next knob.
- Cost: about +0.5 ms swarm step at 1,500 enemies (sim 5.1 → 5.8 ms on the loaded dev box; still under the 6 ms budget).
