# MAYDAY — Interface Control Document (ICD)

Version: 25 Oct 2026 · Owner: Member 4 (integrator)

## How to use this document

This document is the single source of truth for the MAYDAY EE2026 FPGA project. Every member gives it to their own AI before writing any code, and every module must match it exactly.

**Team rules**

1. **Ports are frozen.** Change your module's internals freely. Changing a port requires approval from Member 4 (integrator), who updates this document.
2. **Only Member 4 edits the top module** (`My_Top_Module.v`). Everyone else tests with the kit's stubs or a private test top module.
3. **One owner per signal.** Every signal has exactly one driving module. All other modules only read it.
4. **No hard-coded tuning numbers.** Every speed, threshold and timing lives in the shared parameter file `game_params.vh`, which every module includes.
5. **Integrate every 2 to 3 days.** Everyone uploads source files to the shared GitHub repo; Member 4 builds the full bitstream and checks FPGA utilisation each time.
6. **Keep an AI usage log.** Record the prompts you used and what you kept or changed. The final report requires it (Section 7, Sheet B).

## Project brief

MAYDAY is a physics-driven parachute survival game on the Basys3 and one 96 × 64 OLED, built in Verilog by four members as one integrated bitstream.

**Story.** A civilian passenger boards a normal passenger jet. The flight attendant's safety briefing announces a parachute under every seat and teaches the controls. Mid-flight an engine explodes, and the hero jumps from the open door.

**Freefall (2,000 to 1,400 m).** The parachute is locked until 1,700 m. The player dodges birds, each preceded by a 1 s warning marker. Between 1,700 and 1,400 m the player deploys: early is safe but means a longer ride, perfect (1,550–1,450 m) triggers a 5 s crate magnet, and late snaps a line from opening shock. No deploy by 1,400 m means a fast-forward death plunge.

**Canopy ride.** Random wind gusts push the hero sideways; holding a toggle steers against them. Pulling both toggles brakes: he rises up to 8 px and falls at half speed, but holding longer than 1 s stalls the canopy. Birds, planes and falling debris threaten the canopy's 2 lines. One snapped line makes him drift, sway and fall faster. Two snapped lines collapse the canopy. Supply crates on mini-parachutes rise from below to be collected. The screen edges are turbulence death zones.

**Landing.** In the final 150 m a flare lane appears. The player tugs both toggles when the marker is in the green zone. The ground appears in the last 25 m, with a random landing spot marked by an early gold arrow.

**Stars.** Each level awards up to 3 stars: all crates, landed, and perfect landing (0 damage, soft flare, on the spot). There are 5 levels, all unlocked: days over countryside (1, 3), nights over a city (2, 4) and a sunset (5). Every run is randomly generated.

## Roles and module ownership

| Member | Role | Files | Showpiece for Q&A | Also owns |
| --- | --- | --- | --- | --- |
| 1 (Caleb) | Physics engine | `physics_engine.v` | Fixed-point dynamics (Q8.8), brake and stall model | Wind gusts, steering, damage effects, deploy and flare grading, camera lock, altitude |
| 2 (Arun) | World and collision | `world_engine.v` | Two-hitbox collision, crate magnet with Manhattan-distance force zones | LFSR spawner, obstacle behaviours, warning markers, crates, landing spot, difficulty table |
| 3 (Ruben) | Gameplay rendering and menus | `render_engine.v`, `palette.v`, `font_rom.v`, `sprite_rom.v` | Layered compositor, parallax, palette swapping | Damage and wind visuals, HUD, flare lane, landing and crash animations, all menu and story screens |
| 4 (Sathya) | Director, inputs, cutscene, integration | `My_Top_Module.v`, `game_director.v`, `tick_sync.v`, `input_ctrl.v`, `seg7_ctrl.v`, `led_ctrl.v`, `cutscene_engine.v` | Keyframe cutscene engine, explosion particles | State machine, debouncing, seven-segment altimeter (binary-to-BCD), LEDs, stars, integration |

**Shared assets:** `game_params.vh` (all tuning constants, maintained by Member 4) and `font_rom.v` (5 × 7 font, built by Member 3, also used by Member 4's cutscene captions).

## Global conventions

**Clocks.** All game modules run on the 100 MHz clock `clk`. Only `Oled_Display.v` runs on `clk6p25m`.

**Game tick.** `frame_begin` from `Oled_Display.v` passes through a 2-flip-flop synchroniser and a rising-edge detector into the 100 MHz domain. The result, `game_tick`, is a one-cycle pulse once per OLED frame (about 60 Hz), gated off while paused. Every module updates its game state only on cycles where `game_tick` is high.

**Pulses and levels.** An event pulse is high for exactly one 100 MHz cycle, on the tick the event happens. A level signal holds its value until changed.

**Number formats.**

| Quantity | Format | Width | Range |
| --- | --- | --- | --- |
| Positions and velocities (internal) | Signed Q8.8 | 16 bits | −128 to +127.996 px, step 1/256 px |
| Positions on interfaces | Signed whole pixel (upper 8 bits of Q8.8) | 8 bits | −128 to +127 |
| Altitude | Unsigned Q16.8 | 24 bits | 0 to 65,535 m |
| Palette index | Unsigned | 5 bits | 0 to 31 |

**Scale.** 1 game metre = 1 pixel of scroll. Each tick, altitude drops by the hero's fall speed.

**Coordinates.** The screen is 96 × 64. Origin (0, 0) is the top-left pixel; x increases rightward, y downward. `pixel_x = pixel_index % 96`, `pixel_y = pixel_index / 96`, computed once in the top module. Every position is an object's **top-left corner**.

**Hero frame.** `hero_x`, `hero_y` always give the top-left of the hero's 16 × 20 frame, in every phase. The freefall sprite (10 × 8) is drawn at offset (3, 12) inside it, so the body never jumps at deploy. Rest position: (40, 10).

**Camera.** The hero rests at screen y = 10 and the world scrolls up by `scroll_vy` each tick. While braking, the hero rises up to 8 px above rest. Ground top on screen = `hero_y + 20 + altitude` (whole metres). When that value reaches 54 (about 25 m), the camera locks: `scroll_vy` becomes 0 and the hero moves down the screen for the final descent.

**Edge zones.** If any pixel of the hero's active hitbox is at x ≤ 2 or x ≥ 93, he is lost to turbulence.

**Timers.** `state_timer` counts ticks since entering the current state, resets to 0 on every state change, and **saturates at 255**.

**Randomness.** Member 4 latches `seed[15:0]` from a free-running counter at each `level_start` (forced to 1 if 0). Members 1 and 2 each run their own 16-bit maximal-length LFSR (taps 16, 14, 13, 11), seeded with `seed` XOR a module-specific constant (Member 1: `16'hA5A5`, Member 2: `16'h5A5A`).

## Game states and flow

Member 4's master state machine broadcasts `game_state[3:0]` and `level[2:0]` (1–5); no other module keeps its own idea of the phase.

| Code | State | What happens | Exits to |
| --- | --- | --- | --- |
| 0 | HOME | Title, levels 1–5 (all unlocked), best stars | BTNC: CUTSCENE if not yet seen this power-on, else LEVEL_INTRO |
| 1 | CUTSCENE | 5 scenes, 21 s, rendered by Member 4 | End or SW1: LEVEL_INTRO; sets `cutscene_seen` |
| 2 | LEVEL_INTRO | "LEVEL n" and setting name, 120 ticks | FREEFALL_LOCKED; pulses `level_start` on entry |
| 3 | FREEFALL_LOCKED | 2,000–1,700 m, chute locked, birds only | Altitude ≤ 1,700 m: FREEFALL_WINDOW |
| 4 | FREEFALL_WINDOW | 1,700–1,400 m, deploy allowed | BTNC: CANOPY. Altitude ≤ 1,400 m: CRASH (too late) |
| 5 | CANOPY | Main gameplay; first 60 ticks = canopy opening | Altitude ≤ 150 m: FINAL_APPROACH. `hero_crash`: CRASH |
| 6 | FINAL_APPROACH | Flare lane, landing arrow, camera lock at 25 m; brake disabled | `hero_landed`: LANDING. `hero_crash`: CRASH |
| 7 | LANDING | Soft or hard landing animation, 90 ticks | LEVEL_COMPLETE |
| 8 | CRASH | Death animation (plunge 120 ticks, impact-only 30 ticks) | LEVEL_FAILED |
| 9 | LEVEL_COMPLETE | Stars revealed at ticks 30, 60, 90; Next / Retry / Home | Next: LEVEL_INTRO (level + 1). On level 5, "DONE": VICTORY |
| 10 | LEVEL_FAILED | "FAILED" + reason; Retry / Home | Retry: LEVEL_INTRO. Home: HOME |
| 11 | VICTORY | "YOU MADE IT!", total stars out of 15 | BTNC: HOME |

**Global rules.**

- **Reset (SW15)** returns to HOME from any state and clears best stars. It does not replay the cutscene.
- **Pause (SW0)** gates `game_tick` off; it is a flag, not a state.
- **Retries are unlimited.** There are no lives and no game over.
- **The cutscene plays once per power-on**, on the first level started from HOME.

## Controls and on-board displays

Member 4 owns all inputs, LEDs and the seven-segment display. The input module outputs both a debounced **held** level and a one-shot **press** pulse (200 ms lockout) for each button.

| Input | Gameplay | Menus |
| --- | --- | --- |
| BTNL | Steer left (held) | Cursor left (press) |
| BTNR | Steer right (held) | Cursor right (press) |
| BTNL + BTNR held | Brake; in FINAL_APPROACH, the first both-held moment is the flare | — |
| BTNC | Deploy (FREEFALL_WINDOW only) | Confirm |
| BTNU, BTND | Unassigned | Unassigned |
| SW15 | Reset to HOME | Reset to HOME |
| SW0 | Pause | Pause |
| SW1 | Skip cutscene | — |

**LEDs (16).** One job at a time, chosen by state; in CANOPY the magnet countdown takes priority over wind.

| State | LEDs show |
| --- | --- |
| HOME and menus | Slow chaser pattern |
| FREEFALL_LOCKED | All off |
| FREEFALL_WINDOW | Bar fills as altitude drops from 1,700 m; all 16 steady at 1,550–1,450 m; rapid flashing at 1,450–1,400 m |
| CANOPY, magnet active | 16 LEDs drain to 0 over 300 ticks |
| CANOPY, FINAL_APPROACH | Wind: lights spread from the centre toward `gust_dir`, length set by `gust_strength` |
| CRASH | All flash |
| LEVEL_COMPLETE | Three LED groups light at ticks 30, 60, 90, one per earned star |

**Seven-segment (4 digits).**

| State | Display |
| --- | --- |
| HOME, LEVEL_INTRO | `L- n` (selected or current level) |
| CUTSCENE | Blank |
| FREEFALL_LOCKED to FINAL_APPROACH, LANDING | Live altitude in whole metres via binary-to-BCD (double dabble) |
| CRASH | Fast spin-down to `0` |
| LEVEL_COMPLETE | `St n` (stars earned) |
| LEVEL_FAILED | `FAIL` |
| VICTORY | `t nn` (total stars) |

## Member 1: Physics engine

Member 1 computes the hero's motion, altitude, damage and every physics outcome; all values update once per `game_tick`. Constants are named in the tuning section.

**On `level_start`:** altitude = 2,000 m, hero frame at (40, 10), velocities 0, `lines_snapped` = 0, `deploy_grade` = 0.

**Vertical motion.**

- Freefall: `vy` rises by `GRAVITY` each tick up to `V_FREEFALL` (2.0 px/tick).
- Canopy opening (first 60 ticks of CANOPY, from `state_timer`): `vy` blends from 2.0 to `V_CANOPY` (0.5).
- Canopy: target speed = `V_CANOPY` + `V_DAMAGE` × `lines_snapped`.
- Brake (both toggles held, CANOPY only): speed halved; `hero_y` rises at `BRAKE_RISE` to at most 8 px above rest, and returns at `BRAKE_RETURN` after release.
- Stall: brake held longer than `STALL_HOLD` (60 ticks) gives `vy` = `V_STALL` (1.5) for 60 ticks with `canopy_mode` = 3, then recovery.
- Altitude drops by `vy` every tick. `scroll_vy` = `vy` normally, and 0 once the camera locks (ground top reaches y = 54). After the lock, `hero_y` increases by `vy` instead.

**Horizontal motion.** Each tick: `vx` += steering ± `STEER_ACC` (half in freefall) + gust force + damage drift; then `vx` −= `vx` >> 4 (drag).

**Gusts.** Own LFSR. Interval and maximum strength come from the level's row in the difficulty table. Strength (1 to max) and direction are random. `gust_warn` is high for 30 ticks before a gust; `gust_active` for its 60 ticks.

**Deploy grading** (altitude at the moment CANOPY is entered): early 1,700–1,550 m; perfect 1,550–1,450 m; late 1,450–1,400 m. A late deploy snaps 1 line on a random side (opening shock).

**Damage.** On `strike`: `lines_snapped` += `strike_lines`. The first snap goes on `strike_side`, which becomes `damaged_side`. With 1 line snapped: drift `DRIFT_ACC` toward `damaged_side` plus ±1 px sway once per second (lookup table). At 2 lines: `hero_crash`, `crash_cause` = 0 (collapse). Strikes in freefall count too.

**Edge zones.** Hitbox pixel at x ≤ 2 or x ≥ 93: `hero_crash`, `crash_cause` = 1.

**Flare and touchdown** (FINAL_APPROACH; brake disabled). The flare is the rising edge of both toggles held. It is graded by altitude: soft at 15–5 m; hard at 25–15 or 5–1 m. At altitude 0:

- With a soft or hard flare: pulse `hero_landed`, and set `landing_grade` and `landed_on_spot`. The spot rule: body hitbox centre x within `target_x` to `target_x` + 15.
- With no valid flare (none, or outside both windows): `hero_crash`, `crash_cause` = 2 (missed flare).

## Member 2: World and collision

Member 2 owns every object the hero meets: 6 obstacle slots, 4 crate slots, 1 warning marker and the landing spot. Each slot holds type, Q8.8 position, Q8.8 velocity and an active flag.

**On `level_start`:** clear all slots. Load the level's row from the difficulty table, set `crates_level_total`, and pick `target_x` at random from 8 to 72.

**What spawns when.**

| Phase | Obstacles | Crates |
| --- | --- | --- |
| FREEFALL_LOCKED | Birds only; the level's "freefall birds" count spread over the phase | None |
| FREEFALL_WINDOW | At most 1 bird active | None |
| CANOPY, FINAL_APPROACH | All types allowed by the level, at its spawn interval, up to its max active; none after the camera lock | Spread across the canopy ride, total = `crates_level_total` |

**Warnings.** Every freefall bird (bottom edge) and every debris piece (top edge) is preceded by the warning marker for 60 ticks at its spawn x. Only one warning is pending at a time.

**Obstacle behaviour.** Every object moves up by `scroll_vy` each tick, plus its own motion:

| Type | Enters | Own motion | Lines snapped |
| --- | --- | --- | --- |
| 1 Bird | Below (y = 64) | Sideways about 0.3 px/tick with a ±3 px sine wobble (lookup table) | 1 |
| 2 Plane | Left or right edge, random y in lower half | ±1.5 px/tick sideways | 2 |
| 3 Debris | Top (y = −6), after warning | Falls 1.0 px/tick down the screen | 1 |

`obs_flip` is 1 when an object moves left, so Member 3 mirrors the sprite. Slots free up once an object is fully off-screen.

**Collision.** Each obstacle hitbox is checked against the hero's active hitboxes: the freefall box when `canopy_mode` = 0, otherwise the canopy box and the body box. On overlap:

- Pulse `strike`.
- Set `strike_lines` from the obstacle type.
- Set `strike_side` = 0 if the obstacle's centre x is left of the hero frame centre (`hero_x` + 8), else 1.
- Deactivate that obstacle so it cannot hit twice.

**Crates.** Each crate moves up by `scroll_vy` − `CRATE_FALL` (0.25 px/tick). Spawn x is within ±32 px of `hero_x`, clamped to 8–82, so every crate is reachable. A crate's whole 6 × 9 sprite overlapping either hero hitbox collects it: pulse `crate_collected` and deactivate the crate.

**Crate magnet.** It is triggered when CANOPY is entered with `deploy_grade` = 2 (perfect) and lasts 300 ticks. Each crate moves toward the hero body centre according to Manhattan distance \|dx\| + \|dy\|: more than 32 px, no pull; 16 to 32 px, 0.25 px/tick on each axis; under 16 px, 0.75 px/tick. It outputs `magnet_active` and `magnet_ticks_left`.

## Member 3: Gameplay rendering and menus

Member 3 produces `oled_data_game[15:0]` for every state except CUTSCENE. For each (`pixel_x`, `pixel_y`), it returns the colour of the topmost non-transparent layer.

**Layer order (back to front).**

1. Sky gradient: blends between two colours by altitude, per setting (see the palette section).
2. Far clouds: scroll at `scroll_vy` >> 2.
3. Near clouds: scroll at `scroll_vy` >> 1.
4. Ground and landing spot: the ground top is at `hero_y` + 20 + altitude, drawn only when it is on screen.
5. Crates.
6. Obstacles: mirrored when `obs_flip` = 1.
7. Hero: the sprite is chosen by `canopy_mode`, `lines_snapped`, `damaged_side` and the opening frame.
8. Effects: magnet aura, pickup sparkle, curly wind lines.
9. HUD: crate counter, lock icon, warning marker, landing arrow, flare lane, edge bands.
10. Full-screen flash (impact).

**Palette.** Every sprite pixel is a 5-bit index; index 0 is transparent. In gameplay states, indices 3, 4, 12, 13 and 15 take the level's setting values. Menus always use the day palette.

**Hero sprite selection.**

- **Canopy opening:** `state_timer` 0–19 shows the bundle, 20–39 the half canopy, 40–59 the full canopy.
- **1 line snapped:** the side named by `damaged_side` loses its line and droops; the sprite alternates between 2 flap frames every 4 ticks. A right-side snap mirrors the left-side sprite.
- **Stalled** (`canopy_mode` = 3): the crumpled sprite.

**Effects.**

- **Screen shake:** for 10 ticks after `strike`, offset `pixel_x` by ±2 px on alternating ticks.
- **Wind:** curly cyan lines, 1–3 depending on `gust_strength`, drifting toward `gust_dir` while `gust_warn` or `gust_active`.
- **Magnet aura:** 6 cyan points orbiting the hero, positions from an 8-point lookup table.
- **Pickup sparkle:** a gold burst at the hero body for 10 ticks after `crate_collected`.

**HUD.**

- **Crate counter:** top-left, "`crates_got`/`crates_level_total`" in CANOPY and FINAL_APPROACH.
- **Lock icon:** gold padlock at top-left in FREEFALL_LOCKED; it shows open and flashes 3 times at the start of FREEFALL_WINDOW.
- **Warning marker:** red triangle with "!", flashing at 4 Hz.
- **Landing arrow:** gold, at `target_x` + 8 on the bottom edge, in FINAL_APPROACH until the camera locks.
- **Flare lane:** at x = 86–91 in FINAL_APPROACH. Zones from top to bottom: red (more than 25 m), yellow (25–15), green (15–5), yellow (5–1), red (under 1). The top half of the lane maps 150 to 30 m and the bottom half maps 30 to 0 m. The marker is black, 4 × 3.
- **Edge bands:** faint red dotted bands at x 0–2 and 93–95; they flicker brightly when the hero is within 8 px.

**Crash and landing animations** (from `fail_reason`):

- **Plunge:** reasons 0, 1 and 2. A tumbling hero, the world at 6 px/tick, the ground rushing up, then flash and shake over 120 ticks. Reason 2 (turbulence) adds a spin-out first.
- **Impact only:** reason 3, over 30 ticks.
- **Landing:** 90 ticks. A soft landing shows touchdown with the canopy settling behind him; a hard landing adds a stumble and a dust puff.

**Menu and story screens** (the 5 × 7 font, navy background):

- **HOME:** "MAYDAY" in gold at double size. Five level boxes coloured by setting, the `menu_cursor` box outlined in gold, best stars under each, and `L/R C:GO`.
- **LEVEL_INTRO:** "LEVEL n" at double size, plus the setting name (DAY, NIGHT CITY or SUNSET).
- **LEVEL_COMPLETE:** a vertical list of three 9 × 9 stars labelled `ALL CRATES`, `LANDED` and `PERFECT LAND`, revealed at ticks 30, 60 and 90. Below them, `NEXT RETRY HOME`, with the selected option gold and underlined; NEXT becomes `DONE` on level 5.
- **LEVEL_FAILED:** "FAILED" in red, the reason (`TOO LATE`, `LINES CUT`, `TURBULENCE` or `HARD IMPACT`), then RETRY and HOME.
- **VICTORY:** "YOU MADE IT!", a big gold star, `total_stars`/15, and `C: HOME`.

## Member 4: Director, inputs, cutscene and integration

Member 4 owns the top module, the master state machine, all physical inputs and outputs except the OLED, the cutscene, and integration.

**Top module (`My_Top_Module.v`).**

- Instantiate `Oled_Display.v` and all member modules.
- Generate `clk6p25m`.
- Compute `pixel_x` and `pixel_y`.
- Final pixel: `oled_data` = `oled_data_cut` when `game_state` = CUTSCENE, else `oled_data_game`.

**`tick_sync.v`.** Synchronise `frame_begin` into the 100 MHz domain with 2 flip-flops, edge-detect it, then AND with NOT pause to give `game_tick`.

**`input_ctrl.v`.** For each button, output a debounced held level and a one-shot press pulse (200 ms lockout, sampled every 1 ms).

**`game_director.v`.**

- **State machine:** the transitions in the game states section, including the altitude thresholds 1,700, 1,400 and 150 m.
- **Timing:** `state_timer` (saturating at 255), and `level_start` pulsed on entry to LEVEL_INTRO.
- **Session data:** the `seed` latch, the `cutscene_seen` register, and `menu_cursor`.
- **Failure reason:** `fail_reason` = 0 when the deploy is too late (own check), otherwise `crash_cause` + 1.
- **Crash length:** 120 ticks, or 30 for `fail_reason` = 3.

**Stars** (latched at `hero_landed`; none on failure).

| Bit | Star | Rule |
| --- | --- | --- |
| 0 | All crates | `crates_got` = `crates_level_total` |
| 1 | Landed | `hero_landed` |
| 2 | Perfect land | `lines_snapped` = 0 AND `landing_grade` = soft AND `landed_on_spot` |

`best_stars` holds the best count per level (2 bits × 5), cleared by reset or power-off. `total_stars` is their sum.

**`seg7_ctrl.v` and `led_ctrl.v`.** The behaviour tables in the controls section. Binary-to-BCD conversion uses double dabble.

**`cutscene_engine.v`** produces `oled_data_cut`, using its own wide tick counter (the cutscene lasts about 1,260 ticks).

| Scene | Length | Content |
| --- | --- | --- |
| 1 Boarding | 5 s | Jet parked on tarmac; 4 passengers, including the hero, climb the stairs |
| 2 Briefing | 6 s | Cabin, seated rows, flight attendant (navy, red scarf) holding an orange pack. Captions 2 s each: `C: OPEN CHUTE`, `L/R: STEER`, `L+R: BRAKE/LAND` |
| 3 Flight | 4 s | Jet cruising right; clouds scroll left |
| 4 Explosion | 4 s | 3-frame white flash, 12 particles from the engine under gravity, ±2 px shake, smoke trail, jet sinks |
| 5 Jump | 2 s | Jet descending at right; hero falls from the door in freefall pose |

**Animation engine.** Each scene is a ROM table of keyframes: start and end positions, plus start and end ticks. Positions are linearly interpolated, and every movement lasts a power-of-two number of ticks (32, 64, 128 or 256), so the division becomes a right shift. Particle velocities come from a 12-direction lookup table, with gravity added each tick and a lifetime of 36 ticks. The cutscene uses the selected level's palette.

**Integration duties.** Build the full bitstream every 2 to 3 days, record LUT, FF, BRAM and DSP utilisation each time, and keep `game_params.vh` and this document current.

## Interface signal tables

Every signal crossing a module boundary is listed here with exactly one driver. All modules also take `clk` (100 MHz) and `rst` (SW15, active high). The exact Verilog port lists are in the stub files in `src/`.

**Driven by Member 4** (top module and director)

| Signal | Width | Type | Read by | Meaning |
| --- | --- | --- | --- | --- |
| `game_tick` | 1 | Pulse | 1, 2, 3 | Update now; gated off by pause |
| `game_state` | 4 | Level | 1, 2, 3 | Current state code (0–11) |
| `level` | 3 | Level | 1, 2, 3 | Current level, 1–5 |
| `level_start` | 1 | Pulse | 1, 2, 3 | Reset per-level data |
| `state_timer` | 8 | Level | 1, 3 | Ticks since state entry, saturating at 255 |
| `seed` | 16 | Level | 1, 2 | LFSR seed, never 0 |
| `steer_left_held` | 1 | Level | 1 | BTNL held, debounced |
| `steer_right_held` | 1 | Level | 1 | BTNR held, debounced |
| `pixel_x` | 7 | Level | 3 | `pixel_index % 96` |
| `pixel_y` | 6 | Level | 3 | `pixel_index / 96` |
| `menu_cursor` | 3 | Level | 3 | HOME: level 0–4. COMPLETE: 0 Next, 1 Retry, 2 Home. FAILED: 0 Retry, 1 Home |
| `stars_earned` | 3 | Level | 3 | [0] all crates, [1] landed, [2] perfect land |
| `best_stars` | 10 | Level | 3 | 2 bits per level; level 1 in [1:0] |
| `total_stars` | 4 | Level | 3 | 0–15 |
| `crates_got` | 3 | Level | 3 | Crates collected this level |
| `fail_reason` | 2 | Level | 3 | 0 too late, 1 lines cut, 2 turbulence, 3 hard impact |

**Driven by Member 1** (physics)

| Signal | Width | Type | Read by | Meaning |
| --- | --- | --- | --- | --- |
| `hero_x` | 8 | Signed px | 2, 3 | Hero frame top-left x |
| `hero_y` | 8 | Signed px | 2, 3 | Hero frame top-left y |
| `scroll_vy` | 16 | Signed Q8.8 | 2, 3 | World scroll speed per tick; 0 after camera lock |
| `altitude` | 24 | Unsigned Q16.8 | 2, 3, 4 | Metres above ground |
| `canopy_mode` | 2 | Level | 2, 3 | 0 freefall, 1 open, 2 braking, 3 stalled |
| `lines_snapped` | 2 | Level | 3, 4 | 0–2; 2 = collapse |
| `damaged_side` | 1 | Level | 3 | 0 left, 1 right (valid when 1 line snapped) |
| `gust_warn` | 1 | Level | 3 | Gust starts in 30 ticks or fewer |
| `gust_active` | 1 | Level | 3 | Gust in progress |
| `gust_dir` | 1 | Level | 3, 4 | 0 left, 1 right |
| `gust_strength` | 2 | Level | 3, 4 | 0–3 |
| `deploy_grade` | 2 | Level | 2, 4 | 0 none, 1 early, 2 perfect, 3 late |
| `hero_crash` | 1 | Pulse | 4 | Hero is doomed |
| `crash_cause` | 2 | Level | 4 | 0 collapse, 1 edge zone, 2 missed flare |
| `hero_landed` | 1 | Pulse | 4 | Safe touchdown |
| `landing_grade` | 1 | Level | 3, 4 | 0 soft, 1 hard |
| `landed_on_spot` | 1 | Level | 4 | Body centre within the landing spot at touchdown |

**Driven by Member 2** (world)

| Signal | Width | Type | Read by | Meaning |
| --- | --- | --- | --- | --- |
| `obs_x`, `obs_y` | 48 each | 6 × signed px | 3 | Slot n in bits [8n+7:8n] |
| `obs_type` | 12 | 6 × 2 bits | 3 | 0 empty, 1 bird, 2 plane, 3 debris |
| `obs_active` | 6 | 1 bit per slot | 3 | Slot in use |
| `obs_flip` | 6 | 1 bit per slot | 3 | 1 = moving left, so mirror the sprite |
| `crate_x`, `crate_y` | 32 each | 4 × signed px | 3 | Crate slot positions |
| `crate_active` | 4 | 1 bit per slot | 3 | Crate slot in use |
| `warn_x` | 8 | Signed px | 3 | Warning marker x |
| `warn_active` | 1 | Level | 3 | Show the warning marker |
| `warn_edge` | 1 | Level | 3 | 0 bottom, 1 top |
| `target_x` | 8 | Unsigned px | 1, 3 | Landing spot left edge, 8–72 |
| `strike` | 1 | Pulse | 1, 3 | Hero hit |
| `strike_side` | 1 | Level | 1 | 0 left, 1 right (valid with `strike`) |
| `strike_lines` | 2 | Level | 1 | 1 bird or debris, 2 plane |
| `crate_collected` | 1 | Pulse | 3, 4 | A crate was collected |
| `crates_level_total` | 3 | Level | 3, 4 | Crates in this level |
| `magnet_active` | 1 | Level | 3 | Magnet running |
| `magnet_ticks_left` | 9 | Level | 4 | 300 down to 0 |

**Driven by Member 3** (rendering): `oled_data_game` (16 bits, RGB565), read by the top module.

## Colour palette

The game uses one 32-entry palette (5-bit indices), implemented once in `palette.v`; values below are RGB565. Environment entries change with the setting; all others are fixed.

| Index | Role | Day (levels 1, 3) | Night city (levels 2, 4) | Sunset (level 5) |
| --- | --- | --- | --- | --- |
| 0 | Transparent | — | — | — |
| 1 | Black: outlines | `0000` | same | same |
| 2 | White: text, plane body, flash | `FFFF` | same | same |
| 3 | Clouds (environment) | `DEDB` light grey | `298A` dark blue-grey | `F518` pink |
| 4 | Birds, lines (environment) | `528A` dark grey | `C618` light grey (moonlit) | `528A` dark grey |
| 5 | Canopy orange | `FC60` | same | same |
| 6 | Canopy shading (dark orange) | `C280` | same | same |
| 7 | Navy: trousers, menu background | `194D` | same | same |
| 8 | Skin | `F612` | same | same |
| 9 | Brown: crates, shoes | `8AC5` | same | same |
| 10 | Gold: stars, straps, yellow lane zones | `FEA0` | same | same |
| 11 | Red: tie, warnings, red lane zones | `E104` | same | same |
| 12 | Ground main (environment) | `3506` green fields | `39C8` dark grey buildings | `11C3` dark green silhouette |
| 13 | Ground detail (environment) | `1B43` dark green trees | `FEA0` lit windows | `0000` black |
| 14 | Cyan: magnet aura, wind lines | `371E` | same | same |
| 15 | Sky base (environment) | `4D5F` | `0885` | `69D1` |
| 16 | Silver: debris | `CE7A` | same | same |
| 17 | Steel: debris shading | `7C11` | same | same |
| 18 | Sand: sunset landing spot | `EE4F` | same | same |
| 19 | Bright green: flare perfect zone | `2709` | same | same |
| 20 | Cabin beige (cutscene) | `DE98` | same | same |
| 21 | Tarmac (cutscene) | `5AEC` | same | same |
| 22–31 | Reserved | — | — | — |

**Sky gradient endpoints** (RGB565, blended by altitude; not palette entries):

| Setting | At 2,000 m | Near the ground |
| --- | --- | --- |
| Day | `2B7A` deep blue | `9EBF` light blue |
| Night | `0021` black | `10E8` dark navy |
| Sunset | `494F` purple | `FCC9` warm orange |

Menus always use the day palette. The cutscene uses the selected level's palette.

## Sprite reference

These pixel maps are the approved drafts; Member 3 may polish pixels but never change sizes or hitboxes. Legend: `.` 0 transparent, `K` 1, `W` 2, `G` 4, `O` 5, `D` 6, `N` 7, `S` 8, `B` 9, `Y` 10, `R` 11, `C` 14, `V` 16 silver, `T` 17 steel.

**Sizes and hitboxes** (offsets from the sprite's top-left):

| Object | Sprite (w × h) | Hitbox offset | Hitbox (w × h) | Notes |
| --- | --- | --- | --- | --- |
| Hero frame, canopy open | 16 × 20 | Canopy (1, 0); body (6, 12) | 14 × 5; 4 × 8 | Two boxes |
| Hero, freefall | 10 × 8, drawn at frame offset (3, 12) | (4, 13) in frame | 8 × 6 | One box |
| Bird | 8 × 6, 2 flap frames | (1, 1) | 6 × 4 | Snaps 1 line |
| Plane | 24 × 8 | (1, 2) | 22 × 5 | Snaps 2 lines (instant collapse) |
| Debris | 6 × 6, 2 tumble frames | (1, 1) | 4 × 4 | Snaps 1 line |
| Crate | 6 × 9 | (0, 0) | 6 × 9 | Pickup: whole sprite |
| Landing spot | 16 wide | — | — | Body centre must be within it |

**Hero, canopy open** (2 lines; rows 0–5 canopy, 6–11 lines and hands, 12–19 body):

```
...KKKKKKKKKK...
..KOOOOOOOOOOK..
.KOOODOOOODOOOK.
.KOOODOOOODOOOK.
.KDDDDDDDDDDDDK.
.KKKKKKKKKKKKKK.
..G..........G..
...G........G...
....G......G....
.....G....G.....
.....G....G.....
.....S....S.....
.....WKKKKW.....
.....WSSSSW.....
......WWWW......
......WRWW......
......WRWW......
......NNNN......
......N..N......
......K..K......
```

**Hero, freefall:**

```
SW.KKKK.WS
.WWSSSSWW.
...WRWW...
...WRWW...
...NNNN...
..NN..NN..
.NN....NN.
.K......K.
```

**Damaged canopy (1 line).** The snapped side's line is removed, and that side's canopy pixels shift down by round(k × s²), where s runs from 0 at the centre to 1 at the edge. The two flap frames use k = 6 and k = 3. Right-side damage mirrors left. **Opening frames:** a 4 × 2 orange bundle at rows 7–8 (frame 1), then a 10-wide half canopy at rows 2–5 (frame 2), then the full canopy.

**Bird** (frame 1, frame 2):

```
GG....GG    ........
..G..G..    ...GG...
...GG...    ..GGGGY.
..GGGGY.    .G.GG.G.
...GG...    G......G
........    ........
```

**Plane:**

```
RR......................
RRR.....................
RWWWWWWWWWWWWWWWWWWWW...
WWWGWGWGWGWGWGWGWGWWWW..
WWWWWWWWWWWWWWWWWWWWWWWW
.WWWWWWWWGGGGWWWWWWWWWW.
........GGGGGG..........
.........GGGG...........
```

**Debris** (frame 1, frame 2):

```
RO....    ....OR
OKVVK.    ..KVKO
KVVTVK    .KVVTK
.KVVVK    KVTVVK
.KVTVK    KVVVK.
..KKK.    .KKK..
```

**Crate:**

```
.WWWW.
WWWWWW
G....G
.G..G.
KKKKKK
KBYBBK
KYYYYK
KBYBBK
KKKKKK
```

**HUD icons** (lock 5 × 6, warning 5 × 5, landing arrow 5 × 3, star 9 × 9):

```
.YYY.   ..R..   YYYYY   ....Y....
Y...Y   .RWR.   .YYY.   ...YYY...
YYYYY   .RWR.   ..Y..   ...YYY...
YYKYY   RRRRR           YYYYYYYYY
YYKYY   RRWRR           .YYYYYYY.
YYYYY                   ..YYYYY..
                        ..YY.YY..
                        .YY...YY.
                        YY.....YY
```

## Tuning constants and difficulty

All values below are starting points, stored as named constants in `game_params.vh`, and expected to change during play-testing. Speeds are in px/tick; the Q8.8 column is the stored integer.

**Physics (Member 1)**

| Constant | Value | Q8.8 |
| --- | --- | --- |
| `V_FREEFALL` | 2.0 | 512 |
| `GRAVITY` | 0.05 per tick | 13 |
| `V_CANOPY` | 0.5 | 128 |
| `V_DAMAGE` (per snapped line) | 0.25 | 64 |
| `V_STALL` | 1.5 | 384 |
| `OPEN_TICKS` | 60 ticks | — |
| `STEER_ACC` (half in freefall) | 0.03 per tick | 8 |
| Horizontal drag | `vx` −= `vx` >> 4 | — |
| `GUST_ACC` strength 1 / 2 / 3 | 0.015 / 0.03 / 0.045 per tick | 4 / 8 / 12 |
| `GUST_TICKS` / `GUST_WARN_TICKS` | 60 / 30 ticks | — |
| `BRAKE_RISE` / `BRAKE_RETURN` | 0.5 / 0.125 | 128 / 32 |
| `BRAKE_MAX_RISE` | 8 px | — |
| `STALL_HOLD` / `STALL_TICKS` | 60 / 60 ticks | — |
| `DRIFT_ACC` (1 line snapped) | 0.01 per tick | 3 |

**Altitudes and windows (metres)**

| Constant | Value |
| --- | --- |
| `ALT_START` | 2,000 |
| `ALT_UNLOCK` | 1,700 |
| Deploy early / perfect / late | 1,700–1,550 / 1,550–1,450 / 1,450–1,400 |
| `ALT_TOO_LATE` | 1,400 |
| `ALT_FINAL` (flare lane appears) | 150 |
| Flare soft | 15–5 |
| Flare hard | 25–15 and 5–1 |
| Camera lock | Ground top at screen y = 54 (about 24 m) |

**World (Member 2)**

| Constant | Value |
| --- | --- |
| `CRATE_FALL` | 0.25 px/tick (Q8.8 64) |
| `MAGNET_TICKS` | 300 |
| Magnet zones (Manhattan) | Over 32 px: 0; 16–32 px: 0.25; under 16 px: 0.75 px/tick |
| `WARN_TICKS` | 60 |
| Bird / plane / debris own speed | 0.3 sideways / 1.5 sideways / 1.0 down |

**Difficulty table**

| Level | Setting | Max obstacles | Spawn every | Types | Plane share | Crates | Freefall birds | Gust max | Gust every |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Day | 2 | 2.0 s | Birds | 0% | 3 | 1 | 1 | 6 s |
| 2 | Night city | 3 | 1.6 s | Birds, debris | 0% | 3 | 2 | 2 | 5 s |
| 3 | Day | 4 | 1.3 s | All | 10% | 4 | 2 | 2 | 4 s |
| 4 | Night city | 5 | 1.1 s | All | 20% | 4 | 3 | 3 | 3.5 s |
| 5 | Sunset | 6 | 0.9 s | All | 25% | 5 | 3 | 3 | 3 s |

**Timed states (ticks):** LEVEL_INTRO 120; LANDING 90; CRASH 120 (impact-only 30); star reveals at 30, 60 and 90; screen shake 10; pickup sparkle 10.

## Appendix: decision log

Every decision below was approved by Member 4 for the team. Where a later decision changed an earlier one, the final version is listed and the change is noted.

| ID | Decision | Final outcome |
| --- | --- | --- |
| D1 | Game tick | `frame_begin` through a synchroniser and edge detector; one update per OLED frame, no tearing |
| D2a | Camera | Hero fixed near the top, world scrolls up. Amended: brake rise up to 8 px; camera locks at the ground (V5d) |
| D2b | Number format | Signed Q8.8 for positions and velocities |
| D2c | Reference point | Top-left corner of every object |
| D3a–b | Altitude | 1 m = 1 px of scroll; unsigned Q16.8 |
| D3c | Fall speeds | Freefall 2.0, canopy 0.5, brake halves, +0.25 per snapped line; all tunable |
| D3d | Level length | Start at 2,000 m, about 45–55 s per level |
| D3e–f | Brake and stall | Both toggles held = brake; held over 1 s = stall |
| D3g–h | Flare | Both toggles in final approach; graded by altitude; lane on the right edge |
| D4a–b | Hero size and hitboxes | 16 × 20 frame, rest (40, 10), two hitboxes smaller than the art |
| D4c | Freefall | Locked to 1,700 m; birds with 1 s warnings; no crates |
| D4d–e | Deploy grading | Early, perfect (crate magnet, 5 s), late (opening shock snaps 1 line) |
| D5 | Object slots | 6 obstacles, 4 crates, 1 warning; flattened 8-bit buses |
| D6 | States | 12 states; all levels unlocked; unlimited retries; pause gates the tick; cutscene once per power-on |
| D7 | Signals | One owner per signal; Member 4 takes the cutscene, Member 3 keeps the menus |
| D8 | Damage | **Changed from 3 lines to 2 lines.** 2 snapped = collapse; plane hit snaps 2 (instant collapse); late deploy snaps 1 |
| D8b | Death sequence | Fast 2 s plunge, or impact only for a missed flare; spin-out first for turbulence |
| D9 | Controls and displays | BTNC deploy and confirm, BTNL/BTNR steer, both = brake/flare; SW15 reset, SW0 pause, SW1 skip |
| V1 | Palette and settings | **Expanded from 16 to 32 colours.** Palette swap per setting; sky gradient by altitude |
| V2 | Hero and story | Civilian passenger, normal passenger jet, orange ram-air canopy, parachute under every seat |
| V3 | Obstacles | Bird, plane, silver debris falling from above with top-edge warnings |
| V4 | Crates | Mini-chute crates rising from below, generous pickup, counter top-left |
| V5 | World | Two parallax cloud layers, edge bands, landing spots per setting, random spot with early arrow |
| V6 | Indicators | Lock icon, warning triangle, landing arrow, traffic-light flare lane with two-part mapping |
| V7 | Effects | 3-frame canopy opening; damaged side droops and flaps; curly wind; aura, sparkle, shake |
| V8 | Menus | HOME with setting-coloured boxes; vertical star list (`ALL CRATES`, `LANDED`, `PERFECT LAND`); failure reasons |
| V9 | Cutscene | 5 scenes, 21 s; keyframes with power-of-two durations; 12-particle explosion |
| T1 | Tuning | Difficulty table and physics constants as listed (starting values) |
| T2 | Randomness | Shared seed from Member 4; separate LFSRs in Members 1 and 2 |

## Confirmed defaults

These defaults were proposed while writing this document and confirmed by Member 4 on 25 Oct 2026.

- **LANDING animation:** 90 ticks. A soft landing shows touchdown with the canopy settling behind him; a hard landing adds a stumble and a dust puff.
- **Deploy window traffic:** at most 1 bird active during FREEFALL_WINDOW.
- **Final approach:** no new obstacles spawn after the camera lock at about 25 m.
- **Opening shock side:** a late deploy snaps the line on a random side (from Member 1's LFSR).
- **Hit obstacles disappear:** an obstacle that strikes the hero is deactivated, so it cannot hit twice.
- **Crate reachability rule:** spawn x within ±32 px of `hero_x`, clamped to 8–82.
- **LFSR seed constants:** Member 1 `16'hA5A5`, Member 2 `16'h5A5A`.
- **Display:** OLED only (a VGA monitor request to the lab instructor is pending and not assumed).
