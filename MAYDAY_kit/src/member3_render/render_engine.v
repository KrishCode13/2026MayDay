// =====================================================================
// render_engine.v  --  MEMBER 3 (Gameplay rendering and menus)
// STATUS: STUB from the integrator. Ports are FINAL (see docs/ICD.md).
// Placeholder behaviour: sky colour, orange box for the hero, white
// boxes for obstacles, flat navy screen for every menu state.
// REPLACE the body with your real implementation.
// =====================================================================
module render_engine (
    input  wire               clk,
    input  wire               rst,
    input  wire [6:0]         pixel_x,
    input  wire [5:0]         pixel_y,
    // from Member 4
    input  wire               game_tick,
    input  wire [3:0]         game_state,
    input  wire [2:0]         level,
    input  wire               level_start,
    input  wire [7:0]         state_timer,
    input  wire [2:0]         menu_cursor,
    input  wire [2:0]         stars_earned,
    input  wire [9:0]         best_stars,
    input  wire [3:0]         total_stars,
    input  wire [2:0]         crates_got,
    input  wire [1:0]         fail_reason,
    // from Member 1
    input  wire signed [7:0]  hero_x,
    input  wire signed [7:0]  hero_y,
    input  wire signed [15:0] scroll_vy,
    input  wire [23:0]        altitude,
    input  wire [1:0]         canopy_mode,
    input  wire [1:0]         lines_snapped,
    input  wire               damaged_side,
    input  wire               gust_warn,
    input  wire               gust_active,
    input  wire               gust_dir,
    input  wire [1:0]         gust_strength,
    input  wire               landing_grade,
    // from Member 2
    input  wire [47:0]        obs_x,
    input  wire [47:0]        obs_y,
    input  wire [11:0]        obs_type,
    input  wire [5:0]         obs_active,
    input  wire [5:0]         obs_flip,
    input  wire [31:0]        crate_x,
    input  wire [31:0]        crate_y,
    input  wire [3:0]         crate_active,
    input  wire signed [7:0]  warn_x,
    input  wire               warn_active,
    input  wire               warn_edge,
    input  wire [7:0]         target_x,
    input  wire               strike,
    input  wire               crate_collected,
    input  wire [2:0]         crates_level_total,
    input  wire               magnet_active,
    // output
    output reg  [15:0]        oled_data_game     // RGB565
);
    `include "game_params.vh"

    // signed screen coordinates for comparisons
    wire signed [8:0] px = {2'b00, pixel_x};
    wire signed [8:0] py = {3'b000, pixel_y};
    wire signed [8:0] hx = hero_x;
    wire signed [8:0] hy = hero_y;

    wire in_hero = (px >= hx) && (px < hx + HERO_FRAME_W) &&
                   (py >= hy) && (py < hy + HERO_FRAME_H);

    integer i;
    reg in_obs;
    always @* begin
        in_obs = 1'b0;
        for (i = 0; i < 6; i = i + 1)
            if (obs_active[i] &&
                px >= $signed(obs_x[8*i +: 8]) && px < $signed(obs_x[8*i +: 8]) + BIRD_W &&
                py >= $signed(obs_y[8*i +: 8]) && py < $signed(obs_y[8*i +: 8]) + BIRD_H)
                in_obs = 1'b1;
    end

    always @(posedge clk) begin
        if (game_state >= S_FREEFALL_LOCKED && game_state <= S_CRASH) begin
            if      (in_hero) oled_data_game <= 16'hFC60;   // canopy orange
            else if (in_obs)  oled_data_game <= 16'hFFFF;   // white
            else              oled_data_game <= 16'h4D5F;   // day sky
        end else
            oled_data_game <= 16'h194D;                     // navy menu screen
    end
endmodule
