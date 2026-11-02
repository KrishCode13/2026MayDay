# MAYDAY changelog: play-test fixes (Revision 2)

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
