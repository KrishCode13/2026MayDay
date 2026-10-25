# Full-system simulation

Simulates the whole game with whatever versions of the modules are in `src/`.
A working build reaches LEVEL_COMPLETE (about 40 s of game time; takes seconds to run).

`fake_oled.v` replaces the template's `Oled_Display.v` (simulation only) and
pulses `frame_begin` every 64 OLED clocks, so ticks come much faster than on
the board. Never add `fake_oled.v` to the Vivado project.

## Run (Icarus Verilog, free: `sudo apt install iverilog`, or `brew install icarus-verilog`)

```bash
cd sim
iverilog -g2005 -Wall -I ../src/shared -o sim.out tb.v fake_oled.v \
  ../src/member1_physics/*.v ../src/member2_world/*.v \
  ../src/member3_render/*.v ../src/member4_director/*.v
vvp sim.out
```

Expected end of output: `PASS: reached LEVEL_COMPLETE`.

To watch your own signals, add `$display(...)` lines in `tb.v` using
hierarchical names, e.g. `dut.u_phys.vy`, `dut.u_world.obs_active`.
