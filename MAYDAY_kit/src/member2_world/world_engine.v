// =====================================================================
// world_engine.v  --  MEMBER 2 (World and collision)
// STATUS: STUB from the integrator. Ports are FINAL (see docs/ICD.md).
// Placeholder behaviour: one bird in slot 0 rises from the bottom and
// respawns when it leaves the top. No collisions, no crates.
// REPLACE the body with your real implementation.
// =====================================================================
module world_engine (
    input  wire               clk,
    input  wire               rst,
    // from Member 4
    input  wire               game_tick,
    input  wire [3:0]         game_state,
    input  wire [2:0]         level,
    input  wire               level_start,
    input  wire [15:0]        seed,
    // from Member 1
    input  wire signed [7:0]  hero_x,
    input  wire signed [7:0]  hero_y,
    input  wire signed [15:0] scroll_vy,
    input  wire [23:0]        altitude,
    input  wire [1:0]         canopy_mode,
    input  wire [1:0]         deploy_grade,
    // outputs to Member 3 (flattened: slot n in bits [8n+7:8n])
    output reg  [47:0]        obs_x,
    output reg  [47:0]        obs_y,
    output reg  [11:0]        obs_type,
    output reg  [5:0]         obs_active,
    output reg  [5:0]         obs_flip,
    output reg  [31:0]        crate_x,
    output reg  [31:0]        crate_y,
    output reg  [3:0]         crate_active,
    output reg  signed [7:0]  warn_x,
    output reg                warn_active,
    output reg                warn_edge,
    output reg  [7:0]         target_x,
    // events
    output reg                strike,
    output reg                strike_side,
    output reg  [1:0]         strike_lines,
    output reg                crate_collected,
    output reg  [2:0]         crates_level_total,
    output reg                magnet_active,
    output reg  [8:0]         magnet_ticks_left
);
    `include "game_params.vh"

    reg signed [15:0] bird_y;   // Q8.8 screen y of slot 0

    always @(posedge clk) begin
        strike <= 1'b0;  crate_collected <= 1'b0;          // pulses default low
        if (rst || level_start) begin
            obs_x <= 48'd0; obs_y <= 48'd0; obs_type <= 12'd0; obs_active <= 6'd0; obs_flip <= 6'd0;
            crate_x <= 32'd0; crate_y <= 32'd0; crate_active <= 4'd0;
            warn_x <= 8'sd0; warn_active <= 1'b0; warn_edge <= 1'b0;
            target_x <= 8'd40;                                 // STUB: centred spot
            strike_side <= 1'b0; strike_lines <= 2'd0;
            crates_level_total <= 3'd0;                        // STUB: no crates
            magnet_active <= 1'b0; magnet_ticks_left <= 9'd0;
            bird_y <= 16'sd64 <<< 8;
        end else if (game_tick) begin
            if (game_state >= S_FREEFALL_LOCKED && game_state <= S_FINAL_APPROACH) begin
                bird_y <= (bird_y < -(16'sd8 <<< 8)) ? (16'sd64 <<< 8) : bird_y - scroll_vy;
                obs_active[0]   <= 1'b1;
                obs_type[1:0]   <= OBS_BIRD;
                obs_x[7:0]      <= 8'd20;
                obs_y[7:0]      <= bird_y[15:8];
            end else obs_active <= 6'd0;
        end
    end
endmodule
