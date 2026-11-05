# Full-system simulation

`tb.v` plays all 5 levels with a simple autopilot (deploy, steer, dodge, tug up for planes,
flare with C) and prints per-level stats and fairness checks.

```bash
cd sim
iverilog -g2005 -DFAST_SIM -I ../src/shared -o sim.out tb.v fake_oled.v \
  ../src/member1_physics/*.v ../src/member2_world/*.v \
  ../src/member3_render/*.v ../src/member4_director/*.v
vvp sim.out
```

The real renderer makes this slow (tens of minutes). For quick logic checks,
change `reg [5:0] c` to `reg [2:0] c` in fake_oled.v (8x faster ticks).
Never add `fake_oled.v` or `tb.v` to the Vivado project.
