`timescale 1ns/1ps
module tb;
  reg clk = 0; always #5 clk = ~clk;
  reg btnC=0, btnU=0, btnL=0, btnR=0, btnD=0;
  reg [15:0] sw = 16'h8002;
  wire [15:0] led; wire [6:0] seg; wire dp; wire [3:0] an; wire [7:0] JC;
  My_Top_Module dut(.clk(clk),.btnC(btnC),.btnU(btnU),.btnL(btnL),.btnR(btnR),.btnD(btnD),
                    .sw(sw),.led(led),.seg(seg),.dp(dp),.an(an),.JC(JC));
  wire [3:0] st = dut.game_state;
  wire [15:0] alt = dut.altitude[23:8];
  task pressC; begin btnC=1; repeat(1500) @(posedge clk); btnC=0; repeat(25000) @(posedge clk); end endtask

  // ---- measurements ----
  integer obs_ticks=0, bird_seen=0, plane_seen=0, debris_seen=0, crate_ticks=0, crate_spawns=0;
  integer warn_cnt=0, strikes=0, collected=0, i;
  reg warn_d=0; reg [3:0] cr_d=0;
  always @(posedge clk) if (dut.game_tick) begin
    if (dut.obs_active != 0) obs_ticks = obs_ticks + 1;
    for (i=0;i<6;i=i+1) if (dut.obs_active[i]) begin
      if (dut.obs_type[2*i+:2]==1) bird_seen=bird_seen+1;
      if (dut.obs_type[2*i+:2]==2) plane_seen=plane_seen+1;
      if (dut.obs_type[2*i+:2]==3) debris_seen=debris_seen+1;
    end
    if (dut.crate_active != 0) crate_ticks = crate_ticks + 1;
    for (i=0;i<4;i=i+1) if (dut.crate_active[i] && !cr_d[i]) crate_spawns = crate_spawns + 1;
    cr_d = dut.crate_active;
    if (dut.warn_active && !warn_d) warn_cnt = warn_cnt + 1;
    warn_d = dut.warn_active;
  end
  always @(posedge clk) begin if (dut.strike) strikes=strikes+1; if (dut.crate_collected) collected=collected+1; end

  // ---- simple autopilot: steer back to centre, chase lowest crate ----
  reg [7:0] goal;
  always @(posedge clk) begin
    if ((st==5 || st==6) && !brake_now) begin
      goal = 40;
      if (dut.crate_active[0]) goal = dut.crate_x[7:0] - 5;
      btnL <= ($signed(dut.hero_x) > $signed(goal)+3);
      btnR <= ($signed(dut.hero_x) < $signed(goal)-3);
    end else if (!brake_now) begin btnL<=0; btnR<=0; end
  end
  reg brake_now=0;

  reg [3:0] last=15; reg [15:0] alt_before; integer lvl_done=0; reg brake_tested=0;
  always @(posedge clk) if (st!=last) begin
    $display("state %0d -> %0d  level=%0d alt=%0d target_x=%0d lines=%0d", last, st, dut.level, alt, dut.target_x, dut.lines_snapped);
    last = st;
  end
  initial begin
    repeat(200) @(posedge clk); sw[15]=0; repeat(200) @(posedge clk);
    pressC;                                   // HOME -> level 1
    repeat (3) begin
      wait (st==4);
      wait (alt <= 1530);  pressC;            // perfect deploy
      $display("  deploy_grade=%0d (2=perfect) magnet=%0d", dut.deploy_grade, dut.magnet_active);
      if (!brake_tested) begin
        wait (alt <= 1200); alt_before = alt;
        brake_now = 1; btnU=1; repeat(20*1024) @(posedge clk);
        $display("  BRAKE TEST: alt before=%0d after 20 ticks braking=%0d canopy_mode=%0d (2=braking)", alt_before, alt, dut.canopy_mode);
        btnU=0; brake_now = 0; brake_tested = 1;
      end
      wait (st==6 || st==8);
      if (st==6) begin
        wait (alt <= 25);
        $display("  slow-mo active=%0d at alt=%0d", dut.slowmo, alt);
        wait (alt <= 12); pressC;
        $display("  flare at alt~12 via BTNC");
      end
      wait (st==9 || st==10);
      $display("  END level %0d: stars=%b crates_got=%0d/%0d landed_on_spot=%0d", dut.level, dut.stars_earned, dut.crates_got, dut.crates_level_total, dut.landed_on_spot);
      repeat(300*1024) @(posedge clk);
      pressC;                                 // Next (complete) or Retry (failed)
    end
    $display("---- TOTALS ----");
    $display("ticks with obstacles=%0d  bird-ticks=%0d plane-ticks=%0d debris-ticks=%0d", obs_ticks, bird_seen, plane_seen, debris_seen);
    $display("warnings=%0d  strikes=%0d  crate spawns=%0d crate-ticks=%0d collected=%0d", warn_cnt, strikes, crate_spawns, crate_ticks, collected);
    $finish;
  end
  initial begin #3000000000; $display("TIMEOUT st=%0d alt=%0d", st, alt); $finish; end
endmodule
