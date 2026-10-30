// =====================================================================
// physics_engine.v  --  MEMBER 1 (Physics engine)
// STATUS: Checkpoint 3 (items 1-14). Checkpoint 4 = tune / bugfix only.
// Ports are FINAL (docs/ICD.md). Do not change the port list.
//
// Checklist (tick when that behaviour is in this file)
// CP1  [x] 1 reset  [x] 2 freefall  [x] 3 steer/drag  [x] 4 edge
//      [x] 6 opening blend  [x] 7 canopy speed
// CP2  [x] 5 deploy grade  [x] 8 gusts  [x] 9 brake
//      [x] 10 stall  [x] 11 damage  [x] 12 camera lock
// CP3  [x] 13 flare  [x] 14 touchdown
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

    // PROPOSED for game_params.vh (Member 4). ICD difficulty table at ~60 tick/s.
    localparam [8:0] GUST_GAP_L1 = 9'd360; // 6.0 s
    localparam [8:0] GUST_GAP_L2 = 9'd300; // 5.0 s
    localparam [8:0] GUST_GAP_L3 = 9'd240; // 4.0 s
    localparam [8:0] GUST_GAP_L4 = 9'd210; // 3.5 s
    localparam [8:0] GUST_GAP_L5 = 9'd180; // 3.0 s
    localparam       SWAY_TICKS  = 60;     // ±1 px once per second

    // Internal Q8.8: bits [15:8] = whole pixels, [7:0] = fraction.
    reg signed [15:0] vx, vy, x_q, y_q;
    reg [15:0]        lfsr;
    reg [1:0]         gust_phase;   // 0 idle, 1 warn, 2 active
    reg [8:0]         gust_timer;
    reg [7:0]         brake_hold;
    reg [7:0]         stall_left;   // 0 = not stalled
    reg               cam_lock;
    reg [7:0]         sway_div;
    reg [1:0]         sway_phase;
    reg               collapse_sent;
    reg [1:0]         lines_n;      // work copy for same-tick strike + late deploy
    reg               side_n;
    reg               both_held_d;  // previous tick, for flare rising edge
    reg               flare_done;   // first both-held edge in FINAL_APPROACH used
    reg               flare_ok;     // that edge was soft or hard (not a miss)
    reg               flare_ok_n;
    reg               landing_grade_n;
    reg               touch_sent;   // land / miss-flare pulse already fired

    wire in_freefall = (game_state == S_FREEFALL_LOCKED)
                    || (game_state == S_FREEFALL_WINDOW);
    wire in_canopy   = (game_state == S_CANOPY)
                    || (game_state == S_FINAL_APPROACH);
    wire in_flight   = in_freefall || in_canopy;
    wire opening     = (game_state == S_CANOPY) && (state_timer < OPEN_TICKS);
    wire both_held   = steer_left_held && steer_right_held;
    wire stalling    = (stall_left != 8'd0);
    // Item 9: brake is CANOPY only (not FINAL_APPROACH), and not during stall.
    wire braking     = (game_state == S_CANOPY) && both_held && !stalling;

    wire signed [15:0] steer_acc = in_freefall ? (STEER_ACC >>> 1) : STEER_ACC;

    wire signed [15:0] canopy_vy =
        (lines_snapped == 2'd0) ? V_CANOPY :
        (lines_snapped == 2'd1) ? (V_CANOPY + V_DAMAGE) :
                                  (V_CANOPY + (V_DAMAGE <<< 1));

    // 1/60 ≈ 17/1024 so opening blend needs no divider.
    wire signed [31:0] open_num =
        ($signed(V_FREEFALL) - $signed(V_CANOPY))
      * $signed({1'b0, state_timer})
      * 32'sd17;
    wire signed [15:0] open_vy = V_FREEFALL - open_num[25:10];

    wire signed [15:0] gust_acc =
        (!gust_active) ? 16'sd0 :
        (gust_strength == 2'd1) ? GUST_ACC_1 :
        (gust_strength == 2'd2) ? GUST_ACC_2 :
        (gust_strength == 2'd3) ? GUST_ACC_3 : 16'sd0;

    wire signed [15:0] y_rest_q = HERO_REST_Y <<< 8;
    wire signed [15:0] y_min_q  = (HERO_REST_Y - BRAKE_MAX_RISE) <<< 8;

    function [8:0] gust_gap;
        input [2:0] lv;
        begin
            case (lv)
                3'd1:    gust_gap = GUST_GAP_L1;
                3'd2:    gust_gap = GUST_GAP_L2;
                3'd3:    gust_gap = GUST_GAP_L3;
                3'd4:    gust_gap = GUST_GAP_L4;
                default: gust_gap = GUST_GAP_L5;
            endcase
        end
    endfunction

    function [1:0] gust_max;
        input [2:0] lv;
        begin
            case (lv)
                3'd1:    gust_max = 2'd1;
                3'd2:    gust_max = 2'd2;
                3'd3:    gust_max = 2'd2;
                default: gust_max = 2'd3;
            endcase
        end
    endfunction

    function [1:0] rand_strength;
        input [1:0] mx;
        input [1:0] bits;
        begin
            case (mx)
                2'd1: rand_strength = 2'd1;
                2'd2: rand_strength = {1'b0, bits[0]} + 2'd1; // 1 or 2
                default: begin
                    case (bits)
                        2'd2:    rand_strength = 2'd2;
                        2'd3:    rand_strength = 2'd3;
                        default: rand_strength = 2'd1;
                    endcase
                end
            endcase
        end
    endfunction

    function signed [15:0] sway_delta;
        input [1:0] ph;
        begin
            case (ph)
                2'd0:    sway_delta = 16'sd256;   // +1 px in Q8.8
                2'd2:    sway_delta = -16'sd256;  // -1 px
                default: sway_delta = 16'sd0;
            endcase
        end
    endfunction

    // Next horizontal/vertical speed and X (uses registered stall/brake/gust).
    reg signed [15:0] vx_n, vy_n, x_q_n;
    reg signed [7:0]  hero_x_n;
    reg signed [8:0]  hb_left, hb_right;
    reg               edge_hit;

    always @(*) begin
        vx_n     = vx;
        vy_n     = vy;
        x_q_n    = x_q;
        hero_x_n = x_q[15:8];
        hb_left  = 9'sd40;
        hb_right = 9'sd50;
        edge_hit = 1'b0;

        if (in_flight) begin
            // ----- vertical speed -----
            if (stalling) begin
                vy_n = V_STALL;                 // item 10
            end else if (in_freefall) begin
                if (vy >= (V_FREEFALL - GRAVITY))
                    vy_n = V_FREEFALL;
                else
                    vy_n = vy + GRAVITY;
            end else if (opening) begin
                vy_n = open_vy;                 // item 6
            end else begin
                vy_n = canopy_vy;               // item 7
            end
            if (braking)
                vy_n = vy_n >>> 1;              // item 9: half speed

            // ----- horizontal speed -----
            // Steer one side only. Both held is brake (CP2) / flare (CP3).
            if (steer_left_held && !steer_right_held)
                vx_n = vx - steer_acc;
            else if (steer_right_held && !steer_left_held)
                vx_n = vx + steer_acc;
            else
                vx_n = vx;

            if (gust_active) begin              // item 8
                if (gust_dir == 1'b0)
                    vx_n = vx_n - gust_acc;
                else
                    vx_n = vx_n + gust_acc;
            end

            if (lines_snapped == 2'd1) begin    // item 11 drift
                if (damaged_side == 1'b0)
                    vx_n = vx_n - DRIFT_ACC;
                else
                    vx_n = vx_n + DRIFT_ACC;
            end

            vx_n = vx_n - (vx_n >>> DRAG_SHIFT);

            x_q_n    = x_q + vx_n;
            hero_x_n = x_q_n[15:8];

            if (in_freefall) begin
                hb_left  = {hero_x_n[7], hero_x_n} + HB_FF_X;
                hb_right = {hero_x_n[7], hero_x_n} + HB_FF_X + HB_FF_W - 1;
            end else begin
                hb_left  = {hero_x_n[7], hero_x_n} + HB_CANOPY_X;
                hb_right = {hero_x_n[7], hero_x_n} + HB_CANOPY_X + HB_CANOPY_W - 1;
            end
            if (($signed(hb_left) <= EDGE_LEFT_MAX) ||
                ($signed(hb_right) >= EDGE_RIGHT_MIN))
                edge_hit = 1'b1;
        end else begin
            vy_n = 16'sd0;
            vx_n = 16'sd0;
        end
    end

    always @(posedge clk) begin
        hero_crash  <= 1'b0;
        hero_landed <= 1'b0;

        if (rst || level_start) begin
            x_q           <= HERO_REST_X <<< 8;
            y_q           <= HERO_REST_Y <<< 8;
            hero_x        <= HERO_REST_X;
            hero_y        <= HERO_REST_Y;
            vx            <= 16'sd0;
            vy            <= 16'sd0;
            scroll_vy     <= 16'sd0;
            altitude      <= {ALT_START, 8'd0};
            canopy_mode   <= CM_FREEFALL;
            lines_snapped <= 2'd0;
            damaged_side  <= 1'b0;
            gust_warn     <= 1'b0;
            gust_active   <= 1'b0;
            gust_dir      <= 1'b0;
            gust_strength <= 2'd0;
            deploy_grade  <= DG_NONE;
            crash_cause   <= CC_COLLAPSE;
            landing_grade <= 1'b0;
            landed_on_spot<= 1'b0;
            lfsr          <= ((seed ^ LFSR_CONST_M1) == 16'd0)
                           ? 16'd1 : (seed ^ LFSR_CONST_M1);
            gust_phase    <= 2'd0;
            gust_timer    <= gust_gap(level);
            brake_hold    <= 8'd0;
            stall_left    <= 8'd0;
            cam_lock      <= 1'b0;
            sway_div      <= 8'd0;
            sway_phase    <= 2'd0;
            collapse_sent <= 1'b0;
            both_held_d   <= 1'b0;
            flare_done    <= 1'b0;
            flare_ok      <= 1'b0;
            touch_sent    <= 1'b0;
        end else if (game_tick) begin
            // LFSR taps 16,14,13,11 (bits 15,13,12,10).
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

            // ----- items 5 + 11: lines/side (same-tick strike + late deploy) -----
            lines_n = lines_snapped;
            side_n  = damaged_side;
            if (in_flight && strike) begin
                if (lines_n == 2'd0)
                    side_n = strike_side;
                if (lines_n + strike_lines >= 2'd2)
                    lines_n = 2'd2;
                else
                    lines_n = lines_n + strike_lines;
            end
            if ((game_state == S_CANOPY) && (deploy_grade == DG_NONE)) begin
                if (altitude[23:8] > ALT_PERFECT_HI)
                    deploy_grade <= DG_EARLY;           // 1700-1550
                else if (altitude[23:8] >= ALT_PERFECT_LO)
                    deploy_grade <= DG_PERFECT;         // 1550-1450
                else
                    deploy_grade <= DG_LATE;            // 1450-1400
                if (altitude[23:8] < ALT_PERFECT_LO) begin
                    if (lines_n == 2'd0)
                        side_n = lfsr[0];
                    if (lines_n >= 2'd1)
                        lines_n = 2'd2;
                    else
                        lines_n = 2'd1;
                end
            end
            lines_snapped <= lines_n;
            damaged_side  <= side_n;

            // ----- item 8: gust FSM (canopy ride) -----
            if (in_canopy) begin
                if (gust_timer != 9'd0)
                    gust_timer <= gust_timer - 9'd1;
                case (gust_phase)
                    2'd0: begin
                        gust_warn   <= 1'b0;
                        gust_active <= 1'b0;
                        if (gust_timer == 9'd0) begin
                            gust_phase    <= 2'd1;
                            gust_timer    <= GUST_WARN_TICKS;
                            gust_warn     <= 1'b1;
                            gust_dir      <= lfsr[1];
                            gust_strength <= rand_strength(gust_max(level), lfsr[3:2]);
                        end
                    end
                    2'd1: begin
                        gust_warn   <= 1'b1;
                        gust_active <= 1'b0;
                        if (gust_timer == 9'd0) begin
                            gust_phase  <= 2'd2;
                            gust_timer  <= GUST_TICKS;
                            gust_warn   <= 1'b0;
                            gust_active <= 1'b1;
                        end
                    end
                    default: begin
                        gust_warn   <= 1'b0;
                        gust_active <= 1'b1;
                        if (gust_timer == 9'd0) begin
                            gust_phase  <= 2'd0;
                            gust_timer  <= gust_gap(level);
                            gust_active <= 1'b0;
                        end
                    end
                endcase
            end else begin
                gust_warn   <= 1'b0;
                gust_active <= 1'b0;
            end

            // ----- items 9-10: brake hold and stall timer -----
            if (stalling) begin
                stall_left <= stall_left - 8'd1;
                brake_hold <= 8'd0;
            end else if (braking) begin
                if (brake_hold >= STALL_HOLD - 1) begin
                    stall_left <= STALL_TICKS;
                    brake_hold <= 8'd0;
                end else
                    brake_hold <= brake_hold + 8'd1;
            end else
                brake_hold <= 8'd0;

            // ----- item 13: flare, first rising edge of both held in FA -----
            // Brake is already off in FINAL_APPROACH (see `braking`).
            flare_ok_n      = flare_ok;
            landing_grade_n = landing_grade;
            if ((game_state == S_FINAL_APPROACH) && both_held && !both_held_d
                    && !flare_done) begin
                flare_done <= 1'b1;
                if ((altitude[23:8] <= FLARE_SOFT_HI) &&
                    (altitude[23:8] >= FLARE_SOFT_LO)) begin
                    flare_ok_n      = 1'b1;
                    landing_grade_n = 1'b0;             // soft 15-5 m
                end else if (((altitude[23:8] <= FLARE_HARD_HI) &&
                              (altitude[23:8] >  FLARE_SOFT_HI)) ||
                             ((altitude[23:8] <  FLARE_SOFT_LO) &&
                              (altitude[23:8] >= FLARE_HARD_LO))) begin
                    flare_ok_n      = 1'b1;
                    landing_grade_n = 1'b1;             // hard 25-15 or 5-1 m
                end
                // else miss: flare_ok_n stays 0
            end
            flare_ok      <= flare_ok_n;
            landing_grade <= landing_grade_n;
            both_held_d   <= both_held;

            // ----- commit speeds / X -----
            vx     <= vx_n;
            vy     <= vy_n;
            if ((lines_snapped == 2'd1) && (sway_div == SWAY_TICKS - 1))
                x_q <= x_q_n + sway_delta(sway_phase);
            else
                x_q <= x_q_n;
            hero_x <= ((lines_snapped == 2'd1) && (sway_div == SWAY_TICKS - 1))
                    ? ((x_q_n + sway_delta(sway_phase)) >>> 8)
                    : hero_x_n;

            if (sway_div == SWAY_TICKS - 1) begin
                sway_div   <= 8'd0;
                sway_phase <= sway_phase + 2'd1;
            end else
                sway_div <= sway_div + 8'd1;

            // ----- Y: brake rise/return, or camera-lock descent -----
            if (cam_lock && in_flight)
                y_q <= y_q + vy_n;
            else if (braking) begin
                if (y_q > (y_min_q + BRAKE_RISE))
                    y_q <= y_q - BRAKE_RISE;
                else
                    y_q <= y_min_q;
            end else if (in_flight) begin
                if (y_q < (y_rest_q - BRAKE_RETURN))
                    y_q <= y_q + BRAKE_RETURN;
                else
                    y_q <= y_rest_q;
            end

            if (cam_lock && in_flight)
                hero_y <= (y_q + vy_n) >>> 8;
            else if (braking)
                hero_y <= ((y_q > (y_min_q + BRAKE_RISE))
                           ? (y_q - BRAKE_RISE) : y_min_q) >>> 8;
            else if (in_flight)
                hero_y <= ((y_q < (y_rest_q - BRAKE_RETURN))
                           ? (y_q + BRAKE_RETURN) : y_rest_q) >>> 8;

            // canopy_mode for Members 2 and 3
            if (in_freefall)
                canopy_mode <= CM_FREEFALL;
            else if (stalling)
                canopy_mode <= CM_STALLED;
            else if (braking)
                canopy_mode <= CM_BRAKING;
            else if (in_canopy)
                canopy_mode <= CM_OPEN;

            // altitude and camera lock (item 2 + item 12)
            if (in_flight) begin
                if (vy_n > 0) begin
                    if (altitude > {8'd0, vy_n})
                        altitude <= altitude - {8'd0, vy_n};
                    else
                        altitude <= 24'd0;
                end
                if (!cam_lock) begin
                    if (( {8'd0, y_q[15:8]} + HERO_FRAME_H + altitude[23:8] )
                        <= GROUND_LOCK_Y)
                        cam_lock <= 1'b1;
                end
                if (cam_lock ||
                    (( {8'd0, y_q[15:8]} + HERO_FRAME_H + altitude[23:8] )
                     <= GROUND_LOCK_Y))
                    scroll_vy <= 16'sd0;
                else
                    scroll_vy <= vy_n;
            end else
                scroll_vy <= 16'sd0;

            // crashes / landing: collapse, then touchdown, then edge
            if (in_flight && (lines_n >= 2'd2) && !collapse_sent) begin
                hero_crash    <= 1'b1;
                crash_cause   <= CC_COLLAPSE;
                collapse_sent <= 1'b1;
            end else if (in_flight && !touch_sent && (vy_n > 0) &&
                         (altitude <= {8'd0, vy_n})) begin
                // Item 14: altitude reaches 0 this tick
                touch_sent <= 1'b1;
                if (flare_ok_n) begin
                    hero_landed     <= 1'b1;
                    // Body hitbox centre x = hero_x + 6 + 4/2 = hero_x + 8
                    landed_on_spot  <=
                        (($signed({1'b0, hero_x_n}) + HB_BODY_X + (HB_BODY_W/2))
                         >= $signed({1'b0, target_x})) &&
                        (($signed({1'b0, hero_x_n}) + HB_BODY_X + (HB_BODY_W/2))
                         <= $signed({1'b0, target_x}) + (SPOT_W - 1));
                end else begin
                    hero_crash  <= 1'b1;
                    crash_cause <= CC_MISSED_FLARE;
                end
            end else if (in_flight && edge_hit && !collapse_sent && !touch_sent) begin
                hero_crash  <= 1'b1;
                crash_cause <= CC_EDGE;
            end
        end
    end
endmodule
