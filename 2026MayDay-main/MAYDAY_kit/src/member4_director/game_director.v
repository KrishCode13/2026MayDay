// =====================================================================
// game_director.v  --  MEMBER 4. Master state machine for MAYDAY.
// Ports unchanged from the kit (FINAL, see docs/ICD.md).
//
// Structure (explain in this order at the Q&A):
//   A. next-state logic   (combinational: "where do we go next?")
//   B. state register     (sequential: move there, reset the timer,
//                          do the one-off jobs of entering a state)
//   C. menu cursor        (moves only on press pulses, clamped per menu)
//   D. crates and stars   (count crates, latch stars at hero_landed,
//                          keep the best per level, sum the total)
//
// Stub fixes in this version:
//   1. cutscene_seen is NOT cleared by reset (power-on value only).
//   2. CRASH lasts T_CRASH_IMPACT for fail_reason 3, else T_CRASH_PLUNGE.
//   3. Every register has a power-on value (no X in simulation).
//   4. All menu constants live in game_params.vh.
// Also: hero_crash during FREEFALL_LOCKED/WINDOW now goes to CRASH
// (ICD: "strikes in freefall count too"), otherwise the pulse is lost.
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

    reg [15:0] free_cnt;                     // free-running: seed source
    reg        cutscene_seen;                // set once per power-on
    reg [3:0]  next_state;
    reg [2:0]  next_level;

    // ---- Power-on values (FPGA loads these at configuration) ---------
    // cutscene_seen gets its 0 ONLY here, so SW15 reset cannot replay it.
    initial begin
        game_state = S_HOME;   level = 3'd1;       level_start = 1'b0;
        state_timer = 8'd0;    seed = 16'd1;       menu_cursor = 3'd0;
        stars_earned = 3'd0;   best_stars = 10'd0; total_stars = 4'd0;
        crates_got = 3'd0;     fail_reason = FR_TOO_LATE;
        free_cnt = 16'd0;      cutscene_seen = 1'b0;
    end

    // ---- Helpers ------------------------------------------------------
    // CRASH length depends on why we crashed (impact-only is short).
    wire [7:0] crash_len = (fail_reason == FR_HARD_IMPACT) ? T_CRASH_IMPACT
                                                           : T_CRASH_PLUNGE;
    // Highest legal cursor value in each menu (0 elsewhere).
    wire [2:0] cursor_max = (game_state == S_HOME)           ? NUM_LEVELS - 1 :
                            (game_state == S_LEVEL_COMPLETE) ? MC_HOME :
                            (game_state == S_LEVEL_FAILED)   ? MF_HOME : 3'd0;

    // =================================================================
    // A. Next-state logic. Crash checks come first, so a doomed hero can
    //    never be "rescued" by a deploy or landing in the same cycle.
    // =================================================================
    always @* begin
        next_state = game_state;
        next_level = level;
        case (game_state)
            S_HOME:
                if (center_press) begin
                    next_level = menu_cursor + 3'd1;          // cursor 0..4 -> level 1..5
                    next_state = cutscene_seen ? S_LEVEL_INTRO : S_CUTSCENE;
                end
            S_CUTSCENE:
                if (cutscene_done || sw_skip) next_state = S_LEVEL_INTRO;
            S_LEVEL_INTRO:
                if (state_timer >= T_LEVEL_INTRO) next_state = S_FREEFALL_LOCKED;
            S_FREEFALL_LOCKED:
                if (hero_crash)                next_state = S_CRASH;
                else if (alt_m <= ALT_UNLOCK)  next_state = S_FREEFALL_WINDOW;
            S_FREEFALL_WINDOW:
                if (hero_crash)                 next_state = S_CRASH;
                else if (alt_m <= ALT_TOO_LATE) next_state = S_CRASH;   // too late
                else if (center_press)          next_state = S_CANOPY;  // deploy
            S_CANOPY:
                if (hero_crash)                 next_state = S_CRASH;
                else if (alt_m <= ALT_FINAL)    next_state = S_FINAL_APPROACH;
            S_FINAL_APPROACH:
                if (hero_crash)                 next_state = S_CRASH;
                else if (hero_landed)           next_state = S_LANDING;
            S_LANDING:
                if (state_timer >= T_LANDING)   next_state = S_LEVEL_COMPLETE;
            S_CRASH:
                if (state_timer >= crash_len)   next_state = S_LEVEL_FAILED;
            S_LEVEL_COMPLETE:
                if (center_press) begin
                    if (menu_cursor == MC_NEXT) begin
                        if (level == NUM_LEVELS) next_state = S_VICTORY;   // "DONE"
                        else begin
                            next_level = level + 3'd1;
                            next_state = S_LEVEL_INTRO;
                        end
                    end else if (menu_cursor == MC_RETRY)
                        next_state = S_LEVEL_INTRO;
                    else
                        next_state = S_HOME;
                end
            S_LEVEL_FAILED:
                if (center_press)
                    next_state = (menu_cursor == MF_RETRY) ? S_LEVEL_INTRO : S_HOME;
            S_VICTORY:
                if (center_press) next_state = S_HOME;
            default:
                next_state = S_HOME;
        endcase
    end

    // ---- Star rule (used at the hero_landed moment) -------------------
    // Count a crate that arrives in the very same cycle as touchdown.
    wire [2:0] crates_now   = crates_got + {2'b00, crate_collected};
    wire       star_all     = (crates_now == crates_level_total);
    wire       star_perfect = (lines_snapped == 2'd0) && (landing_grade == 1'b0)
                              && landed_on_spot;
    wire [2:0] new_stars    = {star_perfect, 1'b1, star_all};      // bit1 = landed
    wire [1:0] new_count    = star_all + 2'd1 + star_perfect;      // 1..3
    wire [3:0] best_idx     = {level - 3'd1, 1'b0};                // 2*(level-1)
    wire [1:0] best_now     = best_stars[best_idx +: 2];
    wire       landing_now  = (game_state == S_FINAL_APPROACH) && (next_state == S_LANDING);

    // =================================================================
    // B + C + D. Sequential part.
    // =================================================================
    always @(posedge clk) begin
        free_cnt    <= free_cnt + 1'b1;          // runs regardless of reset
        level_start <= 1'b0;                     // default: no pulse

        // Total = sum of the five 2-bit best fields (registered).
        total_stars <= {2'b00, best_stars[1:0]} + {2'b00, best_stars[3:2]}
                     + {2'b00, best_stars[5:4]} + {2'b00, best_stars[7:6]}
                     + {2'b00, best_stars[9:8]};

        if (rst) begin
            // SW15: back to HOME, best stars cleared.
            // cutscene_seen and seed are deliberately left alone.
            game_state <= S_HOME;  level <= 3'd1;  state_timer <= 8'd0;
            menu_cursor <= 3'd0;   stars_earned <= 3'd0;
            best_stars <= 10'd0;   total_stars <= 4'd0;
            crates_got <= 3'd0;    fail_reason <= FR_TOO_LATE;
        end else begin
            // D1. Crate counter (saturates at 7). Placed before the state
            //     block so a level_start clear below wins over it.
            if (crate_collected && crates_got != 3'd7)
                crates_got <= crates_got + 1'b1;

            // D2. Stars: latched at the touchdown cycle, best kept per level.
            if (landing_now) begin
                stars_earned <= new_stars;
                if (new_count > best_now) best_stars[best_idx +: 2] <= new_count;
            end

            if (next_state != game_state) begin
                // B. Enter a new state.
                game_state  <= next_state;
                level       <= next_level;
                state_timer <= 8'd0;

                // C. Cursor home position for the new screen.
                //    HOME remembers the level just played.
                menu_cursor <= (next_state == S_HOME) ? next_level - 3'd1 : 3'd0;

                if (next_state == S_CUTSCENE) cutscene_seen <= 1'b1;

                if (next_state == S_LEVEL_INTRO) begin
                    level_start  <= 1'b1;                          // one-cycle pulse
                    seed         <= (free_cnt == 16'd0) ? 16'd1 : free_cnt;  // never 0
                    crates_got   <= 3'd0;
                    stars_earned <= 3'd0;
                end

                if (next_state == S_CRASH)
                    fail_reason <= hero_crash ? (crash_cause + 2'd1) : FR_TOO_LATE;
            end else begin
                // B. Same state: count ticks, stop at 255.
                if (game_tick && state_timer != 8'd255)
                    state_timer <= state_timer + 1'b1;

                // C. Cursor moves on press pulses, clamped to the menu size.
                if (left_press && menu_cursor != 3'd0)
                    menu_cursor <= menu_cursor - 1'b1;
                else if (right_press && menu_cursor < cursor_max)
                    menu_cursor <= menu_cursor + 1'b1;
            end
        end
    end
endmodule
