// =====================================================================
// game_director.v  --  MEMBER 4 (Game director)
// STATUS: STUB. Ports are FINAL (see docs/ICD.md).
// Placeholder: linear flow HOME -> (CUTSCENE once) -> LEVEL_INTRO ->
// freefall -> canopy -> final approach -> LANDING -> LEVEL_COMPLETE ->
// HOME, with CRASH -> LEVEL_FAILED -> HOME. Level is always 1.
// TODO(M4): level select, Next/Retry/Home menus, stars + best stars,
//           crate counting, VICTORY, full fail_reason mapping.
// =====================================================================
module game_director (
    input  wire        clk,
    input  wire        rst,
    input  wire        game_tick,
    input  wire        left_press,
    input  wire        right_press,
    input  wire        center_press,
    input  wire        sw_skip,            // SW1
    input  wire        cutscene_done,
    // from Member 1
    input  wire [23:0] altitude,
    input  wire        hero_crash,
    input  wire [1:0]  crash_cause,
    input  wire        hero_landed,
    input  wire        landing_grade,
    input  wire        landed_on_spot,
    input  wire [1:0]  lines_snapped,
    // from Member 2
    input  wire        crate_collected,
    input  wire [2:0]  crates_level_total,
    // outputs (broadcast)
    output reg  [3:0]  game_state,
    output reg  [2:0]  level,
    output reg         level_start,
    output reg  [7:0]  state_timer,
    output reg  [15:0] seed,
    output reg  [2:0]  menu_cursor,
    output reg  [2:0]  stars_earned,
    output reg  [9:0]  best_stars,
    output reg  [3:0]  total_stars,
    output reg  [2:0]  crates_got,
    output reg  [1:0]  fail_reason
);
    `include "game_params.vh"

    wire [15:0] alt_m = altitude[23:8];      // whole metres
    reg  [15:0] free_cnt;                    // free-running counter for the seed
    reg         cutscene_seen;
    reg  [3:0]  next_state;

    always @* begin
        next_state = game_state;
        case (game_state)
            S_HOME:            if (center_press) next_state = cutscene_seen ? S_LEVEL_INTRO : S_CUTSCENE;
            S_CUTSCENE:        if (cutscene_done || sw_skip) next_state = S_LEVEL_INTRO;
            S_LEVEL_INTRO:     if (state_timer >= T_LEVEL_INTRO) next_state = S_FREEFALL_LOCKED;
            S_FREEFALL_LOCKED: if (alt_m <= ALT_UNLOCK) next_state = S_FREEFALL_WINDOW;
            S_FREEFALL_WINDOW: if (center_press) next_state = S_CANOPY;
                               else if (alt_m <= ALT_TOO_LATE) next_state = S_CRASH;
            S_CANOPY:          if (hero_crash) next_state = S_CRASH;
                               else if (alt_m <= ALT_FINAL) next_state = S_FINAL_APPROACH;
            S_FINAL_APPROACH:  if (hero_crash) next_state = S_CRASH;
                               else if (hero_landed) next_state = S_LANDING;
            S_LANDING:         if (state_timer >= T_LANDING) next_state = S_LEVEL_COMPLETE;
            S_CRASH:           if (state_timer >= T_CRASH_PLUNGE) next_state = S_LEVEL_FAILED;
            S_LEVEL_COMPLETE,
            S_LEVEL_FAILED,
            S_VICTORY:         if (center_press) next_state = S_HOME;
            default:           next_state = S_HOME;
        endcase
    end

    always @(posedge clk) begin
        free_cnt    <= free_cnt + 1'b1;
        level_start <= 1'b0;
        if (rst) begin
            game_state <= S_HOME; level <= 3'd1; state_timer <= 8'd0;
            seed <= 16'd1; menu_cursor <= 3'd0; stars_earned <= 3'd0;
            best_stars <= 10'd0; total_stars <= 4'd0; crates_got <= 3'd0;
            fail_reason <= FR_TOO_LATE;  cutscene_seen <= 1'b0;
        end else begin
            if (next_state != game_state) begin
                game_state  <= next_state;
                state_timer <= 8'd0;
                if (game_state == S_CUTSCENE) cutscene_seen <= 1'b1;
                if (next_state == S_LEVEL_INTRO) begin
                    level_start <= 1'b1;
                    seed        <= (free_cnt == 16'd0) ? 16'd1 : free_cnt;
                    crates_got  <= 3'd0;
                end
                if (next_state == S_CRASH)
                    fail_reason <= hero_crash ? (crash_cause + 2'd1) : FR_TOO_LATE;
            end else if (game_tick && state_timer != 8'd255)
                state_timer <= state_timer + 1'b1;     // saturating
            if (crate_collected) crates_got <= crates_got + 1'b1;
        end
    end
endmodule
