# MAYDAY — Member 2 brief: World and collision

## Step 1: give your AI this context

Attach these files to a new chat with your AI, then paste the prompt below:

1. `docs/ICD.md` (the full Interface Control Document)
2. this brief (`docs/briefs/MEMBER2_world.md`)
3. your stub `src/member2_world/world_engine.v` and `src/shared/game_params.vh`

```text
I am Member 2 of a 4-person team building "MAYDAY", a parachute survival game in
Verilog on a Digilent Basys3 (Artix-7 XC7A35T) with one 96x64 Pmod OLED, for NUS
EE2026. The attached ICD is binding for the whole team. My job is ONLY the module
world_engine.v: obstacles, crates, warning markers, the landing spot, collision
detection, the crate magnet and the difficulty table. Teammates build the other
modules in parallel against the same ICD, so:

- Keep the module name, port names, widths and signedness EXACTLY as in the stub.
  If you think a port must change, tell me why instead of changing it.
- Use only constants from game_params.vh (included inside the module). Never
  hard-code a tuning number; the per-level difficulty table may be a case
  statement on `level` using the values in the ICD.
- Verilog-2001, fully synthesisable, single 100 MHz clock (clk). Update objects
  only when game_tick is high. Pulses (strike, crate_collected) last exactly one
  clk cycle.
- Fixed slots: 6 obstacle slots and 4 crate slots, each with type, signed Q8.8
  position, Q8.8 velocity and an active flag. Outputs are flattened buses with
  slot n in bits [8n+7:8n] (whole-pixel signed positions).
- FPGA resources matter: no dividers, no square roots. Collision is
  axis-aligned box overlap. The magnet uses Manhattan distance |dx|+|dy|.
- Explain every block in plain language, because I must explain this code in a
  graded Q&A. Prefer clear code over clever code.
- Work in the order of the checkpoints in my brief, and give me a self-test
  after each one.
Start by summarising my module's responsibilities back to me in 10 bullet
points, so I can confirm you understood, then wait for my go-ahead.
```

## Your job in one paragraph

You own everything the hero meets during the descent: birds, planes, falling debris, supply crates, the warning markers, and the random landing spot. You spawn objects with your own LFSR, move them, detect collisions against the hero's hitboxes, and report strikes and pickups. You also run the crate magnet after a perfect deploy, and you hold the difficulty table that makes levels 1 to 5 harder. Your Q&A showpiece is **two-hitbox collision** and the **magnet's Manhattan-distance force zones**.

## What you receive and what you produce

| You read | From | You drive | Read by |
| --- | --- | --- | --- |
| `game_tick`, `game_state`, `level`, `level_start`, `seed` | Member 4 | `obs_x`, `obs_y`, `obs_type`, `obs_active`, `obs_flip` | 3 |
| `hero_x`, `hero_y`, `scroll_vy`, `altitude` | Member 1 | `crate_x`, `crate_y`, `crate_active` | 3 |
| `canopy_mode` (which hitboxes are active), `deploy_grade` (magnet trigger) | Member 1 | `warn_x`, `warn_active`, `warn_edge` | 3 |
| | | `target_x` (landing spot, 8–72) | 1, 3 |
| | | `strike`, `strike_side`, `strike_lines` | 1, 3 |
| | | `crate_collected`, `crates_level_total` | 3, 4 |
| | | `magnet_active`, `magnet_ticks_left` | 3, 4 |

Full behaviour: ICD sections "Member 2: World and collision", "Sprite reference" (sizes and hitboxes) and "Tuning constants and difficulty".

## Behaviour checklist (each line is testable)

1. On `level_start`: clear all slots, load the level's difficulty row, set `crates_level_total`, pick a random `target_x` (8–72).
2. LFSR: 16-bit maximal (taps 16, 14, 13, 11), seeded with `seed` XOR `LFSR_CONST_M2`.
3. Every object moves up by `scroll_vy` each tick, plus its own motion. A slot frees once the object is fully off-screen.
4. Bird: enters at y = 64 and moves about 0.3 px/tick sideways with a ±3 px sine wobble (lookup table). `obs_flip` = 1 when moving left.
5. Freefall (FREEFALL_LOCKED): birds only; the level's freefall-bird count; each preceded by a 60-tick warning on the bottom edge.
6. FREEFALL_WINDOW: at most 1 bird active.
7. Canopy: types, spawn interval, plane share and max active come from the difficulty table.
8. Plane: enters from the left or right edge at a random y in the lower half, moving ±1.5 px/tick.
9. Debris: 60-tick warning on the top edge, enters at y = −6, then falls 1.0 px/tick down the screen.
10. Collision: obstacle hitbox against the freefall box (`canopy_mode` 0), or against the canopy box and the body box. On a hit: pulse `strike`, set `strike_lines` (1 for bird or debris, 2 for plane), set `strike_side` (obstacle centre left or right of `hero_x` + 8), and deactivate the obstacle.
11. Crates (CANOPY only): rise by `scroll_vy` − `CRATE_FALL`. Spawn x within ±32 px of `hero_x`, clamped to 8–82. Spread `crates_level_total` crates across the ride.
12. Pickup: the whole 6 × 9 crate overlapping either hero hitbox → pulse `crate_collected` and deactivate the crate.
13. Magnet: on entering CANOPY with `deploy_grade` = 2, run for 300 ticks. Pull by Manhattan distance: over 32 px, none; 16–32 px, 0.25; under 16 px, 0.75 px/tick per axis.
14. No new obstacles after the camera lock (`scroll_vy` = 0 in FINAL_APPROACH).

## Checkpoints (Member 4 integrates on each date)

| Date | You deliver |
| --- | --- |
| **Wed 28 Oct** | Items 1–4, 10: LFSR, slot table, birds, collision and `strike` |
| **Sun 1 Nov** | Items 5–9, 11, 12: all obstacle types, warnings, difficulty table, crates, pickup |
| **Wed 4 Nov** | Items 13, 14: magnet, `target_x`, final-approach rule; all outputs correct |
| **Sun 8 Nov** | Feature freeze: difficulty balanced by play-testing all 5 levels |

## How to test on your own

- **Full-system sim:** run `sim/` with your real `world_engine.v`. Print slot positions and `strike` pulses.
- **On the board:** with the stub renderer, every obstacle shows as a white box and the hero as an orange box. To check collisions, wire `strike` to an LED in a private test top.

## Definition of done

The module builds in the integrated bitstream with no port changes. Every checklist item passes a test you can show. All five levels play fairly, and every crate is reachable.

## Q&A prep: be ready to explain

- Why hardware needs fixed slots, and how a slot is reused.
- How box-overlap collision works with two hero hitboxes, and why the hitboxes are smaller than the art.
- Why debris enters from the top (it falls faster than the hero).
- How the magnet approximates an inverse-distance force without division or square roots.
- How your LFSR works, and why the seed must never be 0.

## AI usage

Log every prompt in `docs/AI_USAGE_LOG.md`, with what you kept or changed. Full penalties apply if AI use is undocumented.
