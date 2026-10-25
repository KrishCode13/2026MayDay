// =====================================================================
// physics_engine.v  --  MEMBER 1 (Physics engine)
// STATUS: STUB from the integrator. Ports are FINAL (see docs/ICD.md).
// Placeholder behaviour: hero falls straight down, deploy slows him,
// lands softly at 0 m. REPLACE the body with your real implementation.
// =====================================================================
module physics_engine (
    input  wire               clk,
    input  wire               rst,
    // from Member 4
    input  wire               game_tick,
    input  wire [3:0]         game_state,
    input  wire [2:0]         level,
    input  wire               level_start,
    input  wire [7:0]         state_timer,
    input  wire [15:0]        seed,
    input  wire               steer_left_held,
    input  wire               steer_right_held,
    // from Member 2
    input  wire               strike,
    input  wire               strike_side,
    input  wire [1:0]         strike_lines,
    input  wire [7:0]         target_x,
    // outputs
    output reg  signed [7:0]  hero_x,
    output reg  signed [7:0]  hero_y,
    output reg  signed [15:0] scroll_vy,
    output reg  [23:0]        altitude,
    output reg  [1:0]         canopy_mode,
    output reg  [1:0]         lines_snapped,
    output reg                damaged_side,
    output reg                gust_warn,
    output reg                gust_active,
    output reg                gust_dir,
    output reg  [1:0]         gust_strength,
    output reg  [1:0]         deploy_grade,
    output reg                hero_crash,
    output reg  [1:0]         crash_cause,
    output reg                hero_landed,
    output reg                landing_grade,
    output reg                landed_on_spot
);
    `include "game_params.vh"

    reg signed [15:0] vy;   // Q8.8 fall speed

    always @(posedge clk) begin
        hero_crash  <= 1'b0;        // pulses default low
        hero_landed <= 1'b0;
        if (rst || level_start) begin
            hero_x <= HERO_REST_X;  hero_y <= HERO_REST_Y;
            vy <= 16'sd0;  scroll_vy <= 16'sd0;
            altitude <= {ALT_START, 8'd0};
            canopy_mode <= CM_FREEFALL;  lines_snapped <= 2'd0;  damaged_side <= 1'b0;
            gust_warn <= 1'b0; gust_active <= 1'b0; gust_dir <= 1'b0; gust_strength <= 2'd0;
            deploy_grade <= DG_NONE;  crash_cause <= CC_COLLAPSE;
            landing_grade <= 1'b0;  landed_on_spot <= 1'b0;
        end else if (game_tick) begin
            case (game_state)
                S_FREEFALL_LOCKED, S_FREEFALL_WINDOW: begin
                    canopy_mode <= CM_FREEFALL;
                    vy <= (vy + GRAVITY > V_FREEFALL) ? V_FREEFALL : vy + GRAVITY;
                end
                S_CANOPY, S_FINAL_APPROACH: begin
                    canopy_mode <= CM_OPEN;
                    if (deploy_grade == DG_NONE) deploy_grade <= DG_EARLY;   // STUB grading
                    vy <= V_CANOPY;
                end
                default: vy <= 16'sd0;
            endcase
            scroll_vy <= vy;
            // altitude -= vy (clamped at 0)
            if (altitude > {8'd0, vy}) altitude <= altitude - {8'd0, vy};
            else if (game_state == S_FINAL_APPROACH) begin
                altitude <= 24'd0;
                hero_landed <= 1'b1;               // STUB: always a soft landing
            end else altitude <= 24'd0;
        end
    end
endmodule
