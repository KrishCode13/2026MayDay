# MAYDAY — Member 4 brief: Director, inputs, cutscene and integration

## Step 1: give your AI this context

Attach these files to a new chat with your AI, then paste the prompt below:

1. `docs/ICD.md` (the full Interface Control Document)
2. this brief (`docs/briefs/MEMBER4_director.md`)
3. all files in `src/member4_director/`, plus `src/shared/game_params.vh`

```text
I am Member 4 of a 4-person team building "MAYDAY", a parachute survival game in
Verilog on a Digilent Basys3 (Artix-7 XC7A35T) with one 96x64 Pmod OLED, for NUS
EE2026. The attached ICD is binding for the whole team. I own the top module
My_Top_Module.v and these modules: tick_sync.v, input_ctrl.v, game_director.v,
seg7_ctrl.v, led_ctrl.v and cutscene_engine.v. I am also the integrator: I
merge my teammates' modules every few days. Teammates build their modules in
parallel against the same ICD, so:

- Keep every port of the member modules (physics_engine, world_engine,
  render_engine) EXACTLY as in the ICD. My own helper modules' ports may evolve,
  but tell me when a change affects the top module.
- Use only constants from game_params.vh. Never hard-code a tuning number.
- Verilog-2001, fully synthesisable, 100 MHz clock. Game logic updates on
  game_tick; menu logic reacts to the one-shot press pulses.
- Explain every block in plain language, because I must explain this code in a
  graded Q&A. My showpiece is the cutscene's keyframe animation engine
  (power-of-two movement durations, so interpolation is a shift) and its
  12-particle explosion.
- Work in the order of the checkpoints in my brief, and give me a self-test
  after each one.
Start by summarising my responsibilities back to me in 10 bullet points, so I
can confirm you understood, then wait for my go-ahead.
```

## Your job in one paragraph

You are the director and the integrator. You turn raw buttons and switches into clean inputs, run the master state machine that every other module follows, drive the seven-segment altimeter and the LEDs, award and remember stars, and render the 21-second opening cutscene. You also own the top module and build the full bitstream every few days. Your Q&A showpiece is the **keyframe cutscene engine** and the **explosion particles**; the clock-domain synchroniser and the state machine are strong secondary talking points.

## Your files

| File | State in the kit | What it must become |
| --- | --- | --- |
| `My_Top_Module.v` | Complete; wires all modules | Keep current as ports evolve |
| `tick_sync.v` | Working | Done; be able to explain the 2-flip-flop synchroniser |
| `input_ctrl.v` | Stub (no debounce) | Debounced held levels, plus press pulses with a 200 ms lockout (1 ms sampling) |
| `game_director.v` | Stub (linear flow, level 1 only) | Full 12-state machine, menus, stars, best stars, `fail_reason`, VICTORY |
| `seg7_ctrl.v` | Stub (blank) | Multiplexed 4 digits, double-dabble binary-to-BCD, content per state |
| `led_ctrl.v` | Stub (shows the state) | Per-state LED jobs, including the deploy gauge, magnet countdown and wind |
| `cutscene_engine.v` | Stub (black, 60 ticks) | 5 scenes, keyframes, particles, captions using Member 3's `font_rom.v` |

## Behaviour checklist (each line is testable)

1. Inputs: steering held levels clean (no bounce flicker); one press pulse per physical press, even when held for 5 s.
2. State machine: every transition in the ICD "Game states" table, including level select on HOME, Next/Retry/Home on LEVEL_COMPLETE, Retry/Home on LEVEL_FAILED, and DONE → VICTORY on level 5.
3. `state_timer` saturates at 255. `level_start` is pulsed on entry to LEVEL_INTRO. `seed` is latched there and never 0.
4. `cutscene_seen` plays the cutscene once per power-on; SW1 skips it; reset does not replay it.
5. `fail_reason`: 0 for too late (your own 1,400 m check), otherwise `crash_cause` + 1. CRASH lasts 120 ticks (30 for reason 3).
6. Stars latched at `hero_landed`: bit 0 = `crates_got` == `crates_level_total`; bit 1 = landed; bit 2 = 0 lines, a soft landing and on the spot. `best_stars` holds the best per level; `total_stars` is the sum.
7. Seven-segment: `L- n`, live altitude, spin-down on crash, `St n`, `FAIL` and `t nn`, per the ICD table.
8. LEDs: chaser, off, deploy gauge, magnet drain, wind, crash flash, star groups, per the ICD table.
9. Cutscene: boarding, briefing (3 captions), flight, explosion (flash, 12 particles under gravity, shake, smoke) and jump, using the selected level's palette.
10. Integration: build after each checkpoint, record LUT, FF, BRAM and DSP utilisation, and report any port mismatch to its owner.

## Checkpoints (you integrate on each date)

| Date | You deliver | You integrate |
| --- | --- | --- |
| **Wed 28 Oct** | Items 1–5, 7; first real bitstream | Everyone's first real versions |
| **Sun 1 Nov** | Items 6, 8; cutscene engine with scenes 1 and 3 | Core features from all; receive `font_rom.v` |
| **Wed 4 Nov** | Cutscene scenes 2, 4 and 5 | All features |
| **Sun 8 Nov** | Feature freeze; utilisation check; demo rehearsal; report draft | Final bitstream |

## Integration routine (each checkpoint)

1. Pull everyone's latest files from GitHub.
2. Simulate with `sim/` (it must still reach LEVEL_COMPLETE).
3. Synthesise and implement in Vivado, and note utilisation in `docs/INTEGRATION_LOG.md`.
4. Play one full level on the board.
5. Message each owner with the bugs you found in their module, citing the ICD signal name.

## Q&A prep: be ready to explain

- Why `frame_begin` needs a synchroniser, and how the edge detector makes one pulse per frame.
- How debouncing with a lockout counter works, and why steering needs held levels while menus need pulses.
- How keyframe interpolation avoids a divider.
- How the particle explosion applies gravity each tick.
- How double dabble converts binary altitude into 4 decimal digits.
- How the four modules connect through one state machine, including the walk-through of a bird strike across all four modules.

## AI usage

Log every prompt in `docs/AI_USAGE_LOG.md`, with what you kept or changed. Note in the log that the starter-kit stubs, top module and ICD were AI-assisted.
