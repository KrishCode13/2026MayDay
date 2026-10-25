# MAYDAY — team starter kit (EE2026 I-FDP)

Everything each member needs to build their part independently against one
shared interface. The skeleton already compiles and plays a full level using
placeholder stubs; each member replaces only their own file(s).

## Who does what

| Member | Role | Your brief | Your files |
| --- | --- | --- | --- |
| 1 | Physics engine | `docs/briefs/MEMBER1_physics.md` | `src/member1_physics/physics_engine.v` |
| 2 | World and collision | `docs/briefs/MEMBER2_world.md` | `src/member2_world/world_engine.v` |
| 3 | Rendering and menus | `docs/briefs/MEMBER3_render.md` | `src/member3_render/` (render_engine, palette, sprite_rom, font_rom) |
| 4 | Director, cutscene, integration | `docs/briefs/MEMBER4_director.md` | `src/member4_director/` (all files incl. the top module) |

## Start here (everyone, ~20 minutes)

1. **Get the repo.** Member 4 pushes this folder to a private GitHub repo and adds everyone; clone it.
2. **Get the ICD.** Make sure `docs/ICD.md` is the real exported ICD, not the placeholder.
3. **Make your Vivado project** (your own; never commit it):
   - Add every `.v` file under `src/` plus the template's `Oled_Display.v`.
   - Add `src/shared/game_params.vh` as a design source, and set `src/shared` as a Verilog include directory
     (Settings → General → Verilog options → Include directories).
   - Add `constraints/mayday.xdc` (check the pins against the template's `Basys3_Master.xdc` once).
   - Set `My_Top_Module` as top. Generate the bitstream: you should see an orange box falling on a blue sky.
4. **Brief your AI.** Open your brief and follow "Step 1": attach `docs/ICD.md`, your brief and your stub, paste the prompt, and confirm its 10-bullet summary before it writes code.
5. **Work only in your own files.** Everyone else's stubs keep the whole game running, so you can always test your part in the full system (`sim/` or on the board).

## Getting files and uploading your work (GitHub, no Git needed)

**Get the latest files:** on the repo page, click **Code** → **Download ZIP**.
Do this before you start work each time, so you have everyone's latest modules.

**Upload your work:**

1. On the repo page, open **your own folder** (e.g. `src/member1_physics/`).
2. Click **Add file** → **Upload files**.
3. Drag in your updated file(s). A file with the same name replaces the old one.
4. Write a short message (e.g. "physics: added gusts") and click **Commit changes**.

Upload only into your own folder, and only source files (`.v`, `.vh`, `.md`):
never the Vivado project folder. GitHub keeps every old version, so a bad
upload can always be undone.

If you use Git, `git pull` before you start and `git push` when done works the same way.

## Team rules

1. **Ports are frozen.** Need a change? Ask Member 4, who updates the ICD.
2. **Only Member 4 edits `My_Top_Module.v` and `game_params.vh`.** Propose constant changes in the group chat.
3. **Commit only your own folder.** Pull before you push.
4. **Log your AI use** in `docs/AI_USAGE_LOG.md` as you go.
5. **Understand your code.** You will explain it alone in the graded Q&A.

## Checkpoints (push before the date; Member 4 integrates that evening)

| Date | Milestone |
| --- | --- |
| Wed 28 Oct | First real version of every module replaces its stub |
| Sun 1 Nov | Core features complete; Member 3 delivers `font_rom.v` |
| Wed 4 Nov | All features complete |
| Sun 8 Nov | Feature freeze: tuning, bug fixes, OLED photos, report text |
| Week 13 | Assessment (2–5 min demo, Q&A) |
