// led_ctrl.v -- MEMBER 4. STUB: shows game_state on LD3..LD0 for debugging.
// TODO(M4): per-state LED jobs from the ICD "LEDs" table. Ports FINAL.
module led_ctrl (
    input  wire        clk,
    input  wire        game_tick,
    input  wire [3:0]  game_state,
    input  wire [7:0]  state_timer,
    input  wire [23:0] altitude,
    input  wire        gust_dir,
    input  wire [1:0]  gust_strength,
    input  wire        magnet_active,
    input  wire [8:0]  magnet_ticks_left,
    input  wire [2:0]  stars_earned,
    output wire [15:0] led
);
    assign led = {12'd0, game_state};
endmodule
