# MAYDAY changelog

## Revision 8 (latest)

| Item | Change | File |
|---|---|---|
| Wobbling landing looked unrealistic | Red press now kills: land, wobble for 1 s, fall flat, death tune, failed screen | physics_engine.v, render_engine.v |
| Crate fell with the hero | During a crash crates fly up 3 px/tick and leave | world_engine.v |
| Planes near the ground | None below 300 m | world_engine.v, game_params.vh |
| Busy landing | No new obstacles below 120 m; last 50 m clear of obstacles, crates, warnings and wind | world_engine.v, physics_engine.v, game_params.vh |
| Spots/crates at the edge | Landing spot x 20..60 (whole spot in 20..76); crate spawn x 20..70 | game_params.vh |

**Verified in simulation (14 level-1 runs):** 0 planes below 300 m, 0 ticks with anything on screen in the last 50 m, landing spot always within x 21..58. The red-press death animation compiles but was not captured as an image.

---


## Revision 7 (latest)

| Item | Change | File |
|---|---|---|
| Pause | SW0 also silences and freezes the audio | audio_engine.v, My_Top_Module.v |
| Bank sprite detached | Pendulum tilt: canopy fixed, rows sheared progressively (<= 1 px per row) so the body stays attached; body swings outward | render_engine.v |
| Bank too strong | Push = half steering on banking + a little more as the bank deepens (max = old normal steering, was 2x) | physics_engine.v |
| Explosion sound missing | Restored | audio_engine.v |
| Silent before the explosion | Soft steady wind while the plane flies (scene_wind) | audio_engine.v, cutscene_engine.v |
| Wall hit just before landing | Below 60 m: short tumble straight down to the ground, then lying (no long plunge) | render_engine.v |
| Chirp too long | Chirps for 1 s after each new bird only | audio_engine.v, My_Top_Module.v |
| Bird fell with the hero | During CRASH obstacles fly up 3 px/tick and leave | world_engine.v |
| Skip hint hard to read | "PRESS C TO SKIP", top centre, black (white on night levels) | cutscene_engine.v |

**Verified in simulation:** tilt frames (level, slight right, hard right, hard left) stay connected; audio: explosion, 1 s chirp then silence, pause silences and resumes, music unaffected; full design compiles with no warnings.

---


## Revision 6 (latest)

| Item | Change | Owner / file |
|---|---|---|
| Drift right after one press | Drag `vx - (vx >>> 4)` rounded small positive speeds to 0, so they never decayed; drag now removes at least 1 unit, symmetrically | physics_engine.v (Caleb) |
| Wrong line snaps | Hit side compared an UNSIGNED slice and used +8 for every obstacle; now signed, with real centres (bird +4, plane +12, debris +3) | world_engine.v (Arun) |
| Tug with one line showed 2 lines | Braking sprite only when undamaged; damaged sprite kept; tug rise halved and pull toward the damaged side | render_engine.v (Ruben), physics_engine.v (Caleb) |
| Crash showed a parachute | No parachute if never deployed: tumble, then lying flat; deployed crashes keep the crumpled canopy | render_engine.v (Ruben) |
| Bank + load factor | Bank angle built by holding L/R; sideways accel from the bank; descent x 1/cos(bank) (lookup table); lean sprites (1 px / 2 px) | physics_engine.v (Caleb), render_engine.v (Ruben) |
| Canopy/body swing | Gust drives a spring-damper body offset; renderer shifts body rows under the canopy | physics_engine.v (Caleb), render_engine.v (Ruben) |
| Surface area | Damaged fall speed from v ~ 1/sqrt(A): 1.195 x canopy speed | game_params.vh |
| Flare grades | Red = very hard wobbly landing (survive), yellow = stumble, green = clean; never pressing = crash | physics_engine.v (Caleb), render_engine.v (Ruben), game_director.v (Sathya) |
| Freefall hits | Stun (1 s tumble, "STUNNED!"); 2nd stun = KNOCKED OUT | physics_engine.v (Caleb), render_engine.v (Ruben) |
| PRESS C timing | Shown for the whole deploy window | render_engine.v (Ruben) |
| Cutscene | Every level (HOME and NEXT), silent, "C: SKIP" hint; per-level pages (L1 tutorial, L3 debris, L4 planes); skip rules; RETRY straight to freefall | cutscene_engine.v, game_director.v (Sathya) |
| Sound | Event-driven: plane drone > wind whoosh > bird chirps > silence | audio_engine.v, My_Top_Module.v (Sathya) |

**Verified in simulation:** drift returns to exactly 0; bank reaches slight (30) and hard (64) and doubles the fall speed at 60 deg; first freefall hit stuns without snapping lines, second knocks out (cause 3); a red press freezes the marker and gives landing grade 2; level 1 skip -> pages; level 2 skip -> the jump; Retry -> FREEFALL_LOCKED with a fresh level; audio modes: cutscene and falling silent, bird chirp when a bird appears, death tune on crash. The new sprites (lean, swing, stun tumble, lying without a parachute, debris/plane slides) compile cleanly but were not captured as images this round.

---


## Revision 5 (latest)

| Item | Change | Owner / file |
|---|---|---|
| Keyboard | Removed completely (ps2_keyboard.v deleted, ports and pins removed) | My_Top_Module.v, mayday.xdc (Sathya) |
| Wind sounded like static | Noise through a 2-pole low-pass; loudness and brightness follow a gust envelope (swell ~1 s, fade ~2 s, random peak); loud wind uses the same gusts, louder | audio_engine.v (Sathya) |
| How to get 3 stars | Three tutorial slides after MISSION: AVOID BIRDS (bird), GRAB CRATES (medic crate), LAND ON STAR (star, landing tile, flare lane) | cutscene_engine.v (Sathya) |
| Landing spot unclear | Big blinking gold arrow (18x18) over the landing spot through the whole final approach | render_engine.v, sprite_rom.v (Ruben) |
| Flare marker kept moving | Marker freezes where C is pressed; red press = crash at touchdown, hero lies flat, death tune | physics_engine.v (Caleb), render_engine.v (Ruben), audio_engine.v (Sathya) |
| Lobby music | New original 100 bpm pop-style groove (I-V-vi-IV, plucked lead, 3-3-2 bass, kick + clap) | audio_engine.v (Sathya) |
| Title card | Yellow MAYDAY on a black box in a white screen, no shake | cutscene_engine.v (Sathya) |

**Verified in simulation:** full design compiles; audio recorded with every sound at a sensible level and the wind swelling periodically; title card, three slides, frozen marker, blinking big arrow and lying hero captured from the real renderer and cutscene.

---


## Revision 4: polish, sound, keyboard (latest)

| Item | Change | Owner / file |
|---|---|---|
| White screen in cutscene | Unfinished 6 s briefing replaced by a 1 s white title card, yellow MAYDAY with an earthquake shake; timeline then jumps to the flight | cutscene_engine.v (Sathya) |
| Mission screen | AVOID BIRDS / AVOID DEBRIS / COLLECT CRATES | cutscene_engine.v (Sathya) |
| Crate below the ground | Crates fall 0.15 (was 0.25: they barely rose); none spawn below 200 m hero altitude (crate >= 150 m above ground); crate gaps 450/380/380/300 so all crates still appear | world_engine.v (Arun), game_params.vh |
| Wind invisible on day levels | Grey wind lines on levels 1 and 3 | render_engine.v (Ruben) |
| Text hard to read | Navy HUD text on levels 1, 3, 5 | render_engine.v (Ruben) |
| PRESS C position | Mid-screen (rows 26–32); guidance text moved just below; "C ON GREEN" | render_engine.v (Ruben) |
| HOME prompt | Left/right arrow icons, gold circle, GO | render_engine.v (Ruben) |
| Wind fights the plane dodge | No gust while a plane is warned or flying; an active gust stops | world_engine.v (Arun), physics_engine.v (Caleb) |
| Planes sometimes absent in level 5 | When a plane is due, new obstacles are held back so it always gets its turn | world_engine.v (Arun) |
| Sound | NEW audio_engine.v: original lobby tune and victory jingle (2 square-wave voices), noise-based soft/loud wind and explosion, delta-sigma output to the Pmod AMP2; SW1 mute | audio_engine.v (Sathya) |
| Keyboard | NEW ps2_keyboard.v: PS/2 frame receiver + scan-code decoder; arrows merged with the board buttons (Down = centre) | ps2_keyboard.v, My_Top_Module.v (Sathya) |

**Verified in simulation:** keyboard decoder (press, release, two keys at once, other keys ignored); all four sounds recorded to `mayday_audio_preview.wav` with balanced levels; title card and mission screen captured; HOME prompt and HUD colours captured; all 5 levels completed with every crate spawned (lowest crate >= 218 m above ground) and zero fairness violations.

---


## Revision 3: easier, fairer, guided (latest)

| Feedback | What changed | Owner / file |
|---|---|---|
| Too hard / falling too fast | Canopy 0.5 -> 0.3 px/tick; damage +0.25 -> +0.15; altitudes rescaled (1,400 / 1,100 / 950-850 / 800 m) to keep ~50 s levels | game_params.vh (Sathya) |
| Planes too fast and sudden | Half speed; 2 s side-edge warning; fly level at the hero's body height so tugging UP clears them; only levels 4-5, on their own timer; nothing else spawns around a plane | world_engine.v (Arun), render_engine.v (Ruben) |
| Two birds = unavoidable | Levels 1-2: never two birds in the same band. Levels 3-5: one side always safe, across birds AND debris; birds drift toward their own edge | world_engine.v (Arun) |
| Freefall birds | Straight up; one at a time in levels 1-2 | world_engine.v (Arun) |
| Debris too sudden | Own speed halved; 1 s warning (kept) | game_params.vh |
| Level 1 tutorial | One thing on screen at a time (bird, crate or gust) in random order; gusts requested by world_engine | world_engine.v (Arun), physics_engine.v (Caleb) |
| Level contents | L1-2 birds + wind, L3 + debris, L4 + planes, L5 everything (beatable) | world_engine.v (Arun) |
| Guidance text | Tutorial messages in level 1; one "new element" message in levels 2-5; REPAIRED! | render_engine.v (Ruben) |
| Crates | Green medic crate with white plus and glowing border; repairs a line; rising star pop-up; spawn spacing fixed so all crates appear | sprite_rom.v, render_engine.v (Ruben); physics_engine.v (Caleb); world_engine.v (Arun) |
| Sunset birds hard to see | Lighter pink-peach sky, cream clouds | render_engine.v, palette.v (Ruben); cutscene_engine.v (Sathya) |
| Wind | Max strength 2 everywhere (1 in level 1); steering 0.03 -> 0.04 so steering always wins | physics_engine.v (Caleb), game_params.vh |

**Verified in simulation:** an autopilot completed all 5 levels on the first try. Fairness checks (level 1 one-thing, level 1-2 band, level 3-5 safe side) were all zero. Every crate spawned (3/3, 3/3, 4/4, 4/4, 5/5); crate repairs and plane warnings occurred. Real-renderer frames checked: medic crate, star pop-up, text, plane and warning, sunset sky.

**Tuning knobs** (all in world_engine.v level table or game_params.vh): `cfg_plane_gap` (720 / 540 ticks), `cfg_spawn_interval`, `cfg_max_obs`, `cfg_crate_interval`, `PLANE_Y`, `V_CANOPY`.

---

## Revision 2: play-test fixes

Every change is marked in the code with a `// FIX #n` or `// NEW` comment explaining what and why.
Each member should read their own section before the Q&A.

## Feedback item -> root cause -> fix

| # | Problem | Root cause | Fix | Owner / file |
|---|---|---|---|---|
| 3, 4, 6, 8 | No birds, crates or debris; warning with nothing after it | Off-screen check `slot_y[i][15:8] < -20`: a part-select is UNSIGNED in Verilog, so the test was always true and every object was deleted on its first tick | Wrap in `$signed(...)` (obstacles and crates) | Arun, world_engine.v |
| 3 | Crates rose too fast; endless crates; left spawns broken | Wrong sign on CRATE_FALL; no spawn limit; unsigned clamp | `+ CRATE_FALL`; spawn exactly `crates_level_total` per level, spaced per level; signed clamp | Arun, world_engine.v |
| 8 | Debris rare | 12.5% chance, and the broken LFSR made it 0% | 25% of spawns from level 2 | Arun, world_engine.v |
| 15 | Landing spot always far left | LFSR feedback lost its bit indices (always 0); spot picked before the new seed loaded | Feedback = bits 15^13^12^10; spot picked from the new seed | Arun, world_engine.v |
| 15 | Spot not obvious | — | Gold star drawn on the spot | Ruben, render_engine.v |
| — | **Hits never snapped lines (not reported)** | `strike` pulse arrives the cycle after a tick; physics only read it on a tick | Latch strike until the next tick | Caleb, physics_engine.v |
| 5 | New controls | — | BTNU = brake; BTNC = flare; L/R steer only | Caleb physics_engine.v; Sathya input_ctrl.v, My_Top_Module.v |
| 2 | Perfect landing too hard | Narrow window, full speed | Slow motion (1/3) below 30 m; windows widened to soft 18–4 m, hard 28–18 / 4–1 m; lane colours match | Sathya My_Top_Module.v; game_params.vh; Ruben render_engine.v |
| 11 | Altimeter static while braking | Altitude ignored the hero's own screen movement | Altitude change = fall + on-screen movement (1 px = 1 m), so it climbs while rising | Caleb, physics_engine.v |
| 12 | Brake not visible | No sprite | New POSE_BRAKE sprite (edges pulled down, hands at waist) | Ruben, sprite_rom.v + render_engine.v |
| 13 | Too little wind | Long gaps | Gust gaps halved, moved to game_params.vh | Caleb physics_engine.v; game_params.vh |
| 14 | Players don't know when to press C | — | Blinking gold "PRESS C" in the perfect deploy window and the green flare window | Ruben, render_engine.v |
| New | Players don't know the controls or goal | — | Slow-motion jump, then CONTROLS and MISSION screens at the end of the cutscene | Sathya, cutscene_engine.v |

## Port changes
- `physics_engine`: added `flare_press` (BTNC one-shot) and `brake_held` (BTNU held).
- `input_ctrl`: added input `btnU`, outputs `up_held`, `up_press`.
- `My_Top_Module`: wires the above; `game_tick` now passes through the slow-motion gate.

## New / changed constants (game_params.vh)
FLARE_SOFT_HI 18, FLARE_SOFT_LO 4, FLARE_HARD_HI 28; SLOWMO_ALT 30, SLOWMO_DIV 3; GUST_GAP_L1..L5 = 180/150/120/105/90; CUT_JUMP_SLOW 3, CUT_CTRL_TICKS 240, CUT_GOAL_TICKS 180.

## What changed in your code (Q&A prep)
- **Caleb (physics):** strike latch (pulse-timing bug), flare from BTNC via a latch, brake from BTNU and allowed until camera lock, altitude now includes on-screen movement, gust gaps from game_params.
- **Arun (world):** signed off-screen checks (the main bug), LFSR feedback taps, target_x from the new seed, crate count/spacing/sign fixes, random bits now 1-bit selects, debris share, smaller bird wobble.
- **Ruben (render):** braking sprite, PRESS C prompt, gold star on the landing spot, flare-lane colour bands for the wider windows.
- **Sathya (director):** slow-motion tick gate, BTNU input, flare/brake wiring, cutscene slow-mo jump plus two instruction screens using the shared font.

## Verified in simulation
- Obstacles, warnings, debris and crates appear and stay on screen; crates collected 3/3.
- Strikes now snap lines; 2 lines collapse the canopy.
- Braking raised altitude 1,200 -> 1,203 m; slow motion engages at 25 m.
- C-button flare gives a soft landing on the spot: 3 stars on levels 1 and 2.
- Landing spot differs between levels.
- Cutscene: jump at 1/3 speed (358 ticks), CONTROLS and MISSION screens render correctly, then gameplay starts.

## Notes
- Damage never worked before, so the game will feel harder. If too punishing, lower the level 1-2 bird spawn rate in world_engine.v or the gust strengths.
- `sim/tb.v` now plays a full level with the new controls; run it with `-DFAST_SIM` (see sim/README.md).
