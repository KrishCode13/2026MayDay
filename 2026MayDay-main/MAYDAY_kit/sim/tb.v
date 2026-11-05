`timescale 1ns/1ps
module tb;
  reg clk=0; always #5 clk=~clk;
  reg btnC=0, btnU=0, btnL=0, btnR=0; reg [15:0] sw=16'h8000;
  wire [15:0] led; wire [6:0] seg; wire dp; wire [3:0] an; wire [7:0] JC;
  My_Top_Module dut(.clk(clk),.btnC(btnC),.btnU(btnU),.btnL(btnL),.btnR(btnR),.btnD(1'b0),
                    .sw(sw),.led(led),.seg(seg),.dp(dp),.an(an),.JC(JC));
  wire [3:0] st=dut.game_state; wire [15:0] alt=dut.altitude[23:8];
  task pressC; begin btnC=1; repeat(1500) @(posedge clk); btnC=0; repeat(25000) @(posedge clk); end endtask
  // ---------- per-level stats ----------
  integer birds=0, debris=0, planes=0, pwarns=0, gusts=0, strikes=0, repairs=0, crates=0, l1_viol=0, l2_viol=0, side_viol=0, i, j, nb, ticks=0;
  reg [5:0] act_d=0; reg pw_d=0, gw_d=0; reg [1:0] ln_d=0; reg [3:0] cr_d=0;
  integer things; reg signed [8:0] yi, yj, xi, xj;
  always @(posedge clk) if (dut.game_tick && (st==5||st==6||st==3||st==4)) begin
    ticks=ticks+1;
    for (i=0;i<6;i=i+1) if (dut.obs_active[i] && !act_d[i]) case (dut.obs_type[2*i+:2]) 1: birds=birds+1; 2: planes=planes+1; 3: debris=debris+1; endcase
    act_d=dut.obs_active;
    if (dut.pwarn_active && !pw_d) pwarns=pwarns+1;  pw_d=dut.pwarn_active;
    if (dut.gust_warn && !gw_d) gusts=gusts+1;       gw_d=dut.gust_warn;
    if (ln_d==1 && dut.lines_snapped==0) repairs=repairs+1; ln_d=dut.lines_snapped;
    for (i=0;i<4;i=i+1) if (dut.crate_active[i] && !cr_d[i]) crates=crates+1; cr_d=dut.crate_active;
    // fairness checks
    things=0; nb=0;
    for (i=0;i<6;i=i+1) if (dut.obs_active[i]) things=things+1;
    for (i=0;i<4;i=i+1) if (dut.crate_active[i]) things=things+1;
    if (dut.gust_warn||dut.gust_active) things=things+1;
    if (dut.level==1 && (st==5||st==6) && things>1) l1_viol=l1_viol+1;
    for (i=0;i<6;i=i+1) for (j=i+1;j<6;j=j+1) if (dut.obs_active[i]&&dut.obs_active[j]&&dut.obs_type[2*i+:2]!=2&&dut.obs_type[2*j+:2]!=2) begin
       yi=$signed(dut.obs_y[8*i+:8]); yj=$signed(dut.obs_y[8*j+:8]); xi=$signed(dut.obs_x[8*i+:8]); xj=$signed(dut.obs_x[8*j+:8]);
       if (((yi>yj)?yi-yj:yj-yi) < 12 && yi > $signed(dut.hero_y)-8 && yi < $signed(dut.hero_y)+24) begin
          if (dut.level<=2) l2_viol=l2_viol+1;
          else if ((xi<44) != (xj<44)) side_viol=side_viol+1;
       end
    end
  end
  always @(posedge clk) if (dut.strike) strikes=strikes+1;
  integer min_crate_alt=9999, wind_in_plane=0; reg [3:0] cr2=0; integer q;
  always @(posedge clk) if (dut.game_tick) begin
    for (q=0;q<4;q=q+1) if (dut.crate_active[q] && !cr2[q] && alt < min_crate_alt) min_crate_alt = alt;
    cr2 = dut.crate_active;
    if (dut.plane_busy && (dut.gust_warn || dut.gust_active)) wind_in_plane = wind_in_plane + 1;
  end
  // ---------- autopilot: dodge the nearest obstacle below, else chase crate / centre ----------
  reg [7:0] goal; integer hx, bestd, ox, oy; reg threat;
  always @(posedge clk) if (dut.game_tick) begin
    hx = $signed(dut.hero_x)+8; goal = 48; threat=0; bestd=999;
    for (i=0;i<6;i=i+1) if (dut.obs_active[i] && dut.obs_type[2*i+:2]!=2) begin
       ox=$signed(dut.obs_x[8*i+:8])+4; oy=$signed(dut.obs_y[8*i+:8]);
       if (oy > $signed(dut.hero_y)-8 && oy < $signed(dut.hero_y)+50 && ((ox>hx)?ox-hx:hx-ox) < 18 && oy<bestd) begin
          bestd=oy; threat=1; goal = (ox < 48) ? 70 : 26; end
    end
    if (!threat && dut.crate_active[0]) goal = dut.crate_x[7:0]+3;
    if (goal < 22) goal = 22; if (goal > 74) goal = 74;
    if (st==3||st==4||st==5||st==6) begin btnL <= (hx > goal+2); btnR <= (hx < goal-2); end
    else begin btnL<=0; btnR<=0; end
    // tug up while a plane is about to pass the hero
    btnU <= 0;
    for (i=0;i<6;i=i+1) if (dut.obs_active[i] && dut.obs_type[2*i+:2]==2) begin
       ox=$signed(dut.obs_x[8*i+:8])+12;
       if (((ox>hx)?ox-hx:hx-ox) < 26) btnU <= (st==5 || st==6);
    end
  end
  integer n=0; reg dep=0, flr=0;
  always @(posedge clk) if (st==3) begin dep<=0; flr<=0; end   // reactive agent reset
  initial begin
    repeat(200) @(posedge clk); sw[15]=0; repeat(200) @(posedge clk);
    pressC;
    while (n < 14) begin
      repeat(2000) @(posedge clk);
      if (st==4 && alt<=930 && !dep) begin dep=1; pressC; end
      if (st==6 && alt<=11 && !flr) begin flr=1; pressC; end
      if (st==9 || st==10) begin
        n=n+1;
        $display("LEVEL %0d %s fail_reason=%0d birds=%0d debris=%0d planes=%0d(warned %0d) gusts=%0d crates=%0d got=%0d/%0d strikes=%0d repairs=%0d stars=%b | viol: L1=%0d band=%0d side=%0d",
          dut.level, (st==9)?"WIN ":"FAIL", dut.fail_reason, birds, debris, planes, pwarns, gusts, crates, dut.crates_got, dut.crates_level_total, strikes, repairs, dut.stars_earned, l1_viol, l2_viol, side_viol);
        $display("      lowest crate spawn at hero alt %0d m (crate itself %0d m above ground); wind ticks during plane = %0d", min_crate_alt, min_crate_alt-44, wind_in_plane); min_crate_alt=9999; wind_in_plane=0;
        if (st==9 && dut.level==5) begin $display("ALL 5 LEVELS DONE"); $finish; end
        birds=0;debris=0;planes=0;pwarns=0;gusts=0;strikes=0;repairs=0;crates=0;l1_viol=0;l2_viol=0;side_viol=0;ticks=0;
        repeat(200*128) @(posedge clk); pressC;
      end
    end
    $display("stopped after 14 results"); $finish;
  end
  // simple named block workaround
  always @(posedge clk) ;
endmodule
