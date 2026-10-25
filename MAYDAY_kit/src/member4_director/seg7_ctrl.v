// seg7_ctrl.v -- MEMBER 4. STUB: display blank. Ports FINAL.
// TODO(M4): multiplexed 4-digit driver, binary-to-BCD (double dabble),
// per-state content from the ICD "Seven-segment" table.
module seg7_ctrl (
    input  wire        clk,
    input  wire [3:0]  game_state,
    input  wire [2:0]  level,
    input  wire [2:0]  menu_cursor,
    input  wire [23:0] altitude,
    input  wire [2:0]  stars_earned,
    input  wire [3:0]  total_stars,
    output wire [6:0]  seg,     // active low, seg[0] = CA
    output wire        dp,      // active low
    output wire [3:0]  an       // active low
);
    assign seg = 7'b1111111;
    assign dp  = 1'b1;
    assign an  = 4'b1111;
endmodule
