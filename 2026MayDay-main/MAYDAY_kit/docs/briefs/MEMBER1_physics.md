# MAYDAY — Member 1 brief: Physics engine

## Step 1: give your AI this context

Attach these three files to a new chat with your AI, then paste the prompt below:

1. `docs/ICD.md` (the full Interface Control Document)
2. this brief (`docs/briefs/MEMBER1_physics.md`)
3. your stub `src/member1_physics/physics_engine.v` and `src/shared/game_params.vh`

```text
I am Member 1 of a 4-person team building "MAYDAY", a parachute survival game in
Verilog on a Digilent Basys3 (Artix-7 XC7A35T) with one 96x64 Pmod OLED, for NUS
EE2026. The attached ICD is binding for the whole team. My job is ONLY the module
physics_engine.v. My teammates are building the other modules in parallel
against the same ICD, so:

- Keep the module name, port names, widths and signedness EXACTLY as in the stub.
  If you think a port must change, tell me why instead of changing it.
- Use only constants from game_params.vh (included inside the module). Never
  hard-code a tuning number. If you need a new constant, propose it to me.
- Verilog-2001, fully synthesisable, single 100 MHz clock (clk). Update game
  state only on cycles where game_tick is high. Event pulses (hero_crash,
  hero_landed) are high for exactly one clk cycle.
- Fixed point: positions and velocities are signed Q8.8 (16-bit); altitude is
  unsigned Q16.8 (24-bit). Use shifts instead of division; avoid wide
  multipliers (multiply by constants only).
- Explain every block you write in plain language, because I must explain this
  code myself in a graded Q&A. Prefer clear code over clever code.
- Work in the order of the checkpoints in my brief. After each checkpoint, give
  me a short self-test I can run (simulation or on the board).
Start by summarising my module's responsibilities back to me in 10 bullet
points, so I can confirm you understood, then wait for my go-ahead.
```

## Your job in one paragraph

You are the physics engine. Every game tick you compute the hero's motion and altitude: gravity in freefall, the canopy opening, wind gusts, steering, braking and stalling, damage drift, the camera lock near the ground, and the landing flare. You also decide every physics outcome, sending pulses to Member 4: a perfect, early or late deploy; a collapse; an edge-zone death; a missed flare; or a safe landing. Your Q&A showpiece is **fixed-point dynamics (Q8.8)** and the **brake and stall model**.

## What you receive and what you produce

| You read | From | You drive | Read by |
| --- | --- | --- | --- |
| `game_tick`, `game_state`, `level`, `level_start`, `state_timer`, `seed` | Member 4 | `hero_x`, `hero_y` (signed px, frame top-left) | 2, 3 |
| `steer_left_held`, `steer_right_held` | Member 4 | `scroll_vy` (Q8.8 world scroll; 0 after camera lock) | 2, 3 |
| `strike`, `strike_side`, `strike_lines` | Member 2 | `altitude` (Q16.8) | 2, 3, 4 |
| `target_x` | Member 2 | `canopy_mode`, `lines_snapped`, `damaged_side` | 2, 3, 4 |
| | | `gust_warn`, `gust_active`, `gust_dir`, `gust_strength` | 3, 4 |
| | | `deploy_grade` | 2, 4 |
| | | `hero_crash` + `crash_cause`, `hero_landed` + `landing_grade` + `landed_on_spot` | 4 |

Full behaviour: ICD sections "Global conventions", "Member 1: Physics engine" and "Tuning constants".

## Behaviour checklist (each line is testable)

1. On `level_start`: altitude 2,000 m, hero frame (40, 10), velocities 0, `lines_snapped` 0, `deploy_grade` 0.
2. Freefall: `vy` += `GRAVITY` per tick up to `V_FREEFALL`; altitude −= `vy`; `scroll_vy` = `vy`.
3. Steering: `vx` += ±`STEER_ACC` (half in freefall); drag `vx` −= `vx` >>> 4; `hero_x` += `vx`.
4. Edge zone: active hitbox pixel at x ≤ 2 or x ≥ 93 → `hero_crash`, `crash_cause` = 1.
5. Deploy grading on entry to CANOPY: 1,700–1,550 early, 1,550–1,450 perfect, 1,450–1,400 late. Late snaps 1 line on a random side.
6. Canopy opening: over `state_timer` 0–59, `vy` blends from 2.0 to 0.5.
7. Canopy speed = `V_CANOPY` + `V_DAMAGE` × `lines_snapped`.
8. Gusts (own LFSR, seed XOR `LFSR_CONST_M1`): interval and maximum strength per level (difficulty table); `gust_warn` for 30 ticks, then `gust_active` for 60.
9. Brake (both held, CANOPY only): half speed, `canopy_mode` 2. `hero_y` rises at `BRAKE_RISE` up to 8 px, and returns at `BRAKE_RETURN` after release.
10. Stall: brake held over `STALL_HOLD` → `vy` = `V_STALL` for 60 ticks, `canopy_mode` 3, then recovery.
11. Damage: on `strike`, `lines_snapped` += `strike_lines`. The first snap sets `damaged_side` = `strike_side`. With 1 line: `DRIFT_ACC` toward that side plus ±1 px sway once per second. At 2 or more lines: crash, `crash_cause` 0.
12. Camera lock: when `hero_y` + 20 + altitude ≤ 54, `scroll_vy` = 0 and `hero_y` += `vy`.
13. Flare (FINAL_APPROACH, brake disabled): the first rising edge of both held. Soft at 15–5 m; hard at 25–15 m or 5–1 m; any other timing is a miss.
14. Touchdown at altitude 0: a soft or hard flare gives `hero_landed` + `landing_grade` + `landed_on_spot` (body centre x within `target_x` … +15). Otherwise `hero_crash`, `crash_cause` 2.

## Checkpoints (Member 4 integrates on each date)

| Date | You deliver |
| --- | --- |
| **Wed 28 Oct** | Items 1–4, 6, 7: freefall, steering, drag, opening blend, canopy speed, edge death |
| **Sun 1 Nov** | Items 5, 8–12: deploy grading, gusts, brake, stall, damage, camera lock |
| **Wed 4 Nov** | Items 13–14: flare and touchdown; all outputs correct |
| **Sun 8 Nov** | Feature freeze: constants tuned by play-testing; no known bugs |

## How to test on your own

- **Full-system sim:** in `sim/`, run the testbench with your real `physics_engine.v` and everyone else's stubs (see `sim/README.md`). Add `$display` lines for `vy`, altitude and `hero_x`.
- **On the board:** build the whole kit with your file swapped in. The stub renderer draws your hero as an orange box, so you can see the fall, steering and drift directly.

## Definition of done

The module builds in the integrated bitstream with no port changes. Every checklist item passes a test you can show, and no constant is hard-coded.

## Q&A prep: be ready to explain

- Why Q8.8, and how a 0.05 px/tick² gravity value is stored as 13.
- How drag with a shift by 4 produces a top sideways speed of about 0.5 px/tick.
- Why the brake must stall, and what stops the player braking forever.
- How the camera lock keeps the ground still while the hero descends.
- How the flare is graded from altitude alone.

## AI usage

Log every prompt in `docs/AI_USAGE_LOG.md`, with what you kept or changed. The report requires it, and full penalties apply if AI use is undocumented.
