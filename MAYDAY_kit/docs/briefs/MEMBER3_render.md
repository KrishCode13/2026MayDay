# MAYDAY — Member 3 brief: Gameplay rendering and menus

## Step 1: give your AI this context

Attach these files to a new chat with your AI, then paste the prompt below:

1. `docs/ICD.md` (the full Interface Control Document; the palette and sprite pixel maps are in it)
2. this brief (`docs/briefs/MEMBER3_render.md`)
3. your stub `src/member3_render/render_engine.v` and `src/shared/game_params.vh`

```text
I am Member 3 of a 4-person team building "MAYDAY", a parachute survival game in
Verilog on a Digilent Basys3 (Artix-7 XC7A35T) with one 96x64 Pmod OLED (16-bit
RGB565), for NUS EE2026. The attached ICD is binding for the whole team. My job is
ONLY rendering: render_engine.v plus my helper files palette.v, sprite_rom.v and
font_rom.v. I draw every OLED pixel in every state except CUTSCENE: gameplay,
HUD, effects and all menu/story screens. Teammates build the other modules in
parallel against the same ICD, so:

- Keep render_engine's name, ports, widths and signedness EXACTLY as in the stub.
  If you think a port must change, tell me why instead of changing it.
- Use only constants from game_params.vh (included inside the module).
- Verilog-2001, fully synthesisable, 100 MHz clock (clk). For each (pixel_x,
  pixel_y) output the colour of the topmost non-transparent layer, in the layer
  order given in the ICD. Animation state updates only on game_tick.
- Sprites are stored as 5-bit palette indices (index 0 = transparent) and looked
  up through ONE 32-entry palette in palette.v. Environment entries 3, 4, 12, 13
  and 15 swap by setting (level 1,3 day; 2,4 night city; 5 sunset); menus always
  use the day palette. Use the pixel maps and RGB565 values from the ICD.
- FPGA resources matter: the comparator count grows with every object checked
  per pixel. No dividers; parallax and lane mapping use shifts.
- font_rom.v (5x7 font: A-Z, 0-9, space and : / + ! -) is a SHARED asset that
  Member 4's cutscene also uses, so keep its interface simple: input a character
  code and a row, output 5 bits.
- Explain every block in plain language, because I must explain this code in a
  graded Q&A.
- Work in the order of the checkpoints in my brief, and give me a self-test
  after each one.
Start by summarising my module's responsibilities back to me in 10 bullet
points, so I can confirm you understood, then wait for my go-ahead.
```

## Your job in one paragraph

You turn the game's numbers into the picture on the OLED. For every pixel you decide which layer is on top: the sky gradient, parallax clouds, the ground and landing spot, crates, obstacles, the hero, effects and the HUD. You also draw every menu and story screen. The palette swap gives the five levels their day, night-city and sunset looks from the same sprites. Your Q&A showpiece is the **layered compositor**, **parallax** and **palette swapping**.

## What you receive and what you produce

You read almost everything (see the render_engine port list), and drive one output: **`oled_data_game[15:0]`**, the RGB565 value for the current pixel. You also deliver **`font_rom.v`** to Member 4 by **Sun 1 Nov**, for the cutscene captions.

Full behaviour: ICD sections "Member 3: Gameplay rendering and menus", "Colour palette" and "Sprite reference".

## Behaviour checklist (each line is testable)

1. `palette.v`: 32 entries, RGB565, with environment swaps by `level` in gameplay states and the day palette in menus.
2. Sprite ROMs from the ICD pixel maps, with index 0 transparent, `obs_flip` mirroring, and the freefall sprite drawn at frame offset (3, 12).
3. Layer order exactly as in the ICD (sky at the back, flash at the front).
4. Sky gradient between the two RGB565 endpoints per setting, blended by altitude.
5. Two cloud layers scrolling at `scroll_vy` >> 2 and >> 1, using cloud index 3.
6. Ground top at `hero_y` + 20 + altitude, with a landing spot per setting (day tile, helipad circle, sandpit) at `target_x`.
7. Hero sprite selection: opening frames from `state_timer` (0–19, 20–39, 40–59). With 1 line snapped, the damaged side droops and flaps (2 frames, mirrored by `damaged_side`). Stalled shows the crumpled sprite.
8. HUD: crate counter (`crates_got`/`crates_level_total`), lock icon, warning triangle (4 Hz, `warn_edge`), landing arrow at `target_x` + 8, edge bands that brighten within 8 px.
9. Flare lane at x 86–91 in FINAL_APPROACH: red, yellow, green, yellow, red zones; two-part mapping (150–30 m on the top half, 30–0 m on the bottom half); black 4 × 3 marker.
10. Effects: curly wind lines (`gust_*`), magnet aura (8-point lookup table), pickup sparkle (10 ticks), screen shake (±2 px on `pixel_x` for 10 ticks after `strike`).
11. Crash animations driven by `fail_reason` (plunge over 120 ticks with spin-out for reason 2; impact only over 30 ticks for reason 3), plus the landing animation (90 ticks).
12. Menus: HOME (levels coloured by setting, `menu_cursor` outline, `best_stars`), LEVEL_INTRO, LEVEL_COMPLETE (vertical list of `ALL CRATES` / `LANDED` / `PERFECT LAND`, revealed at ticks 30, 60, 90), LEVEL_FAILED (reason text), VICTORY.

## Checkpoints (Member 4 integrates on each date)

| Date | You deliver |
| --- | --- |
| **Wed 28 Oct** | Items 1–3: palette, hero and bird sprites, compositor with transparency |
| **Sun 1 Nov** | Items 4–6, 8, plus `font_rom.v`, HOME and LEVEL_INTRO: all sprites, gradient, parallax, ground, HUD |
| **Wed 4 Nov** | Items 7, 9–12: damage visuals, flare lane, effects, crash and landing, remaining screens |
| **Sun 8 Nov** | Feature freeze: polish, plus real OLED photos for the report (the report requires real photos) |

## How to test on your own

- **On the board:** this is the fastest way for you. Build the whole kit with your file swapped in. The stubs give a falling hero and a rising bird, so your sprites appear in real motion immediately.
- **Forcing a test state:** in a private test top, drive `game_state`, `level` and `lines_snapped` from switches, so you can view each screen and each setting's palette without playing.

## Definition of done

Every state renders as specified, on all three settings, with no flicker or tearing, inside the FPGA resource limits, and with no port changes.

## Q&A prep: be ready to explain

- How the compositor picks the top layer for each pixel, and what transparency index 0 does.
- How palette swapping recolours a whole level without new sprites.
- Why parallax layers at half and quarter speed create depth, and why a shift replaces a multiply.
- How mirroring works by reading sprite columns in reverse.
- How the two-part flare-lane mapping enlarges the windows that matter.

## AI usage

Log every prompt in `docs/AI_USAGE_LOG.md`, with what you kept or changed. Full penalties apply if AI use is undocumented.
