`timescale 1ns/1ps
module tb;
  reg clk = 0; always #5 clk = ~clk;
  reg btnC = 0, btnU = 0, btnL = 0, btnR = 0, btnD = 0;
  reg [15:0] sw = 16'h8002;                     // reset on, skip cutscene on
  wire [15:0] led; wire [6:0] seg; wire dp; wire [3:0] an; wire [7:0] JC;
  My_Top_Module dut(.clk(clk), .btnC(btnC), .btnU(btnU), .btnL(btnL), .btnR(btnR), .btnD(btnD),
                    .sw(sw), .led(led), .seg(seg), .dp(dp), .an(an), .JC(JC));
  task press; begin btnC = 1; repeat (50) @(posedge clk); btnC = 0; repeat (50) @(posedge clk); end endtask
  reg [3:0] last = 15; reg deployed = 0; integer k;
  always @(posedge clk) if (dut.game_state != last) begin
    $display("t=%0t ms  state=%0d  alt=%0d m", $time/1000000, dut.game_state, dut.altitude[23:8]);
    last = dut.game_state;
  end
  initial begin
    repeat (100) @(posedge clk); sw[15] = 0; repeat (100) @(posedge clk);
    press;                                              // HOME -> start
    wait (dut.game_state == 4); press; deployed = 1;    // deploy in window
    wait (dut.game_state == 9);                         // LEVEL_COMPLETE
    $display("PASS: reached LEVEL_COMPLETE");  $finish;
  end
  initial begin #200000000; $display("TIMEOUT state=%0d", dut.game_state); $finish; end
endmodule
