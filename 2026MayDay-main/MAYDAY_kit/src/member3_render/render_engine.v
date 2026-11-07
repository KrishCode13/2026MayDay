// =====================================================================
// render_engine.v - Gameplay Render and Menu - MEBER 3
// Checkpoint 3 build:
//   - Order that ICD exeutes:
//     10: Full-screen flash -> 9: HUD & flare lane -> 8: Effects -> 7: Hero -> 6: Obstacles -> 5: Crates -> 4: Ground & landing spot -> 3: Near clouds -> 2: Far clouds -> 1: Stepped sky gradient.
//   - Shift only two part flare lane mapping (150-30 m top, 30-0 m bottom).
//   - Screen shake, curly wind lines, 8-LUT magnet aura, 10-tick crate pickup sparkle. 
//   - S_CRASH and S_LANDING.
//   - 5 menu screens: S_HOME, S_LEVEL_INTRO, S_LEVEL_COMPLETE, S_LEVEL_FAILED, S_VICTORY.
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
    input  wire [2:0]         fail_reason,   
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
    input  wire [1:0]         landing_grade,  
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
    // plane side-edge warning from Member 2
    input  wire               pwarn_active,
    input  wire               pwarn_right,
    input  wire signed [7:0]  pwarn_y,
    input  wire               flare_locked,   // C pressed -> freeze the flare-lane marker
    input  wire [1:0]         bank_lvl,       // 0 level, 1 slight, 2 hard bank
    input  wire               bank_left,      
    input  wire signed [2:0]  swing_dx,       // body offset under the canopy
    input  wire               stunned,        // hit in freefall -> tumbling
    // output
    output reg  [15:0]        oled_data_game     // RGB565
);
    `include "game_params.vh"

    // -----------------------------------------------------------------
    // Game-State Classification
    // -----------------------------------------------------------------
    wire is_gameplay = (game_state >= S_FREEFALL_LOCKED) && (game_state <= S_CRASH);
    wire is_menu     = !is_gameplay;

    // Crash sub-modes driven by fail reason
    wire is_crash_plunge = (game_state == S_CRASH) && (fail_reason != FR_HARD_IMPACT);
    wire is_crash_impact = (game_state == S_CRASH) && (fail_reason == FR_HARD_IMPACT);
    // crash with the ground already close (e.g. hitting the wall just before landing): no long plunge - he tumbles straight down from where he was and lies there
    wire is_crash_short  = is_crash_plunge && (alt_metres < 16'd60);
    wire signed [9:0] short_fall_y = $signed({hero_y[7], hero_y[7], hero_y}) + $signed({2'd0, state_timer});
    wire signed [9:0] short_land_y = $signed(ground_y_reg[9:0]) - 10'sd18;
    wire short_landed = is_crash_short && (short_fall_y >= short_land_y);
    wire plunge_air  = is_crash_plunge && (is_crash_short ? !short_landed : (state_timer < 8'd90));
    wire plunge_down = is_crash_plunge && !plunge_air;

    // -----------------------------------------------------------------
    // Animation Timers, Parallax Accumulators and 18 bit Ground Y
    // -----------------------------------------------------------------
    reg [7:0]          anim_tick_cnt;
    reg signed [17:0]  ground_y_reg;
    reg signed [15:0]  far_scroll_q88;   // accumulates scroll_vy to 2
    reg signed [15:0]  near_scroll_q88;  // accumulates scroll_vy to 1
    reg [3:0]          shake_timer;      // 10 ticks after strike
    reg [3:0]          sparkle_timer;    // 10 ticks after crate_collected
    reg [6:0]          wind_phase;       // horizontal drift phase for curly wind lines

    wire [15:0] alt_metres = altitude[23:8];

    // Normal ground top - hero_y + 20 + altitude[23:8].
    // During S_CRASH, ground rushes up from y=254 to y=44 at 6 pixels/tick
    // over the first 90 ticks so touchdown/impact happens at tick 90.
    wire signed [17:0] plunge_ground_y =
        (state_timer < 8'd55) ? 18'sd254 :
        (state_timer < 8'd90) ? (18'sd44 + $signed({10'd0, (8'd90 - state_timer) * 8'd6})) :
                                18'sd44;

    wire signed [17:0] ground_y_next =
        (is_crash_plunge && !is_crash_short) ? plunge_ground_y :   // REV7: short fall keeps the real ground
        (is_crash_impact || game_state == S_LANDING) ? 18'sd54 :
        ($signed(hero_y) + 18'sd20 + $signed({2'b00, alt_metres}));

    // Effective vertical scroll speed (6.0 pix/tick = 16'sd1536 in during crash plunge)
    wire signed [15:0] eff_scroll_vy =
        (plunge_air && !is_crash_short) ? 16'sd1536 :
        (game_state == S_LANDING || is_crash_impact || is_crash_short) ? 16'sd0 :
        scroll_vy;

    wire obs_anim_frame = anim_tick_cnt[3]; // Switches every 8 game_ticks (bird/debris)
    wire dmg_flap_frame = anim_tick_cnt[2]; // Switches every 4 game_ticks (damaged canopy)
    wire blink_4hz      = ~anim_tick_cnt[3]; // ~4 Hz flash (8 ticks on, 8 ticks off)

    // -----------------------------------------------------------------
    // REV3: guidance text + crate star pop-up
    //   msg_id: 1 AVOID BIRDS  2 GRAB CRATES  3 WIND! STEER  4 PRESS C AT GREEN 5 STRONGER WIND  6 DEBRIS ABOVE!  7 PLANES! TUG UP 8 FINAL DESCENT  9 REPAIRED!
    //   Level 1 shows a message every time a bird/crate/gust appears (tutorial).
    //   Levels 2-5 show one message only when that level's new element first appears.
    // -----------------------------------------------------------------
    reg [3:0] msg_id = 4'd0;
    reg [7:0] msg_timer = 8'd0;
    reg [4:0] pop_timer = 5'd0;               // star rises for 30 ticks after a crate
    reg [5:0] obs_act_d = 6'd0;
    reg [3:0] crate_act_d = 4'd0;
    reg       gust_warn_d = 1'b0, warn_d = 1'b0, pwarn_d = 1'b0;
    reg [3:0] state_d = 4'd0;
    reg [1:0] lines_d = 2'd0;
    reg       intro_done = 1'b0;
    reg       stun_d = 1'b0;
    always @(posedge clk) stun_d <= stunned;              // levels 2-5: new element message shown once
    integer   m;
    reg       new_bird;
    always @* begin
        new_bird = 1'b0;
        for (m = 0; m < 6; m = m + 1)
            if (obs_active[m] && !obs_act_d[m] && (obs_type[2*m +: 2] == OBS_BIRD)) new_bird = 1'b1;
    end
    wire new_crate = |(crate_active & ~crate_act_d);
    always @(posedge clk) begin
        obs_act_d <= obs_active;  crate_act_d <= crate_active;  gust_warn_d <= gust_warn;
        warn_d <= warn_active;    pwarn_d <= pwarn_active;      state_d <= game_state;
        lines_d <= lines_snapped;
        if (rst || level_start) begin
            msg_id <= 4'd0;  msg_timer <= 8'd0;  pop_timer <= 5'd0;  intro_done <= 1'b0;
        end else begin
            if (game_tick && msg_timer != 8'd0) msg_timer <= msg_timer - 8'd1;
            if (crate_collected)                     pop_timer <= 5'd30;
            else if (game_tick && pop_timer != 5'd0) pop_timer <= pop_timer - 5'd1;

            if (stunned && !stun_d) begin
                msg_id <= 4'd10; msg_timer <= 8'd90;                         // STUNNED!
            end else if ((lines_d == 2'd1) && (lines_snapped == 2'd0) && is_gameplay) begin
                msg_id <= 4'd9;  msg_timer <= 8'd120;                         // REPAIRED!
            end else if (level == 3'd1) begin
                if (new_bird)                          begin msg_id <= 4'd1; msg_timer <= TEXT_TICKS; end
                else if (new_crate)                    begin msg_id <= 4'd2; msg_timer <= TEXT_TICKS; end
                else if (gust_warn && !gust_warn_d)    begin msg_id <= 4'd3; msg_timer <= TEXT_TICKS; end
                else if ((game_state == S_FINAL_APPROACH) && (state_d != S_FINAL_APPROACH))
                                                       begin msg_id <= 4'd4; msg_timer <= 8'd240; end
            end else if (!intro_done) begin
                if ((level == 3'd2) && gust_warn && !gust_warn_d)
                    begin msg_id <= 4'd5; msg_timer <= TEXT_TICKS; intro_done <= 1'b1; end
                else if ((level == 3'd3) && warn_active && !warn_d && warn_edge)
                    begin msg_id <= 4'd6; msg_timer <= TEXT_TICKS; intro_done <= 1'b1; end
                else if ((level == 3'd4) && pwarn_active && !pwarn_d)
                    begin msg_id <= 4'd7; msg_timer <= TEXT_TICKS; intro_done <= 1'b1; end
                else if ((level == 3'd5) && (game_state == S_CANOPY) && (state_d != S_CANOPY))
                    begin msg_id <= 4'd8; msg_timer <= TEXT_TICKS; intro_done <= 1'b1; end
            end
        end
    end
    wire msg_on = is_gameplay && (game_state != S_CRASH) && (msg_timer != 8'd0) && (msg_id != 4'd0);

    // -----------------------------------------------------------------
    // Stepped Sky Gradient (16 bands from altitude[23:8] to 7, on game_tick)
    // -----------------------------------------------------------------
    wire [8:0] alt_shifted = alt_metres[15:7];
    wire [3:0] sky_band    = is_crash_plunge ?
                             ((state_timer < 8'd90) ? (4'd15 - state_timer[6:3]) : 4'd0) :
                             ((alt_shifted >= 9'd15) ? 4'd15 : alt_shifted[3:0]);

    reg [15:0] sky_hi, sky_lo;
    always @* begin
        case (level)
            3'd2, 3'd4: begin // Night city
                sky_hi = 16'h0021;
                sky_lo = 16'h10E8;
            end
            3'd5: begin       // Sunset
                sky_hi = 16'hCBD5;   // lighter pink-purple (was 494F) so birds stand out
                sky_lo = 16'hFE52;   // soft peach (was FCC9)
            end
            default: begin    // Day (levels 1, 3)
                sky_hi = 16'h2B7A;
                sky_lo = 16'h9EBF;
            end
        endcase
    end

    function [5:0] blend_channel;
        input [5:0] c_lo;
        input [5:0] c_hi;
        input [3:0] b;
        reg   [9:0] weighted_sum;
        begin
            weighted_sum = (c_lo << 4)
                         - (b[0] ? c_lo : 10'd0)
                         - (b[1] ? (c_lo << 1) : 10'd0)
                         - (b[2] ? (c_lo << 2) : 10'd0)
                         - (b[3] ? (c_lo << 3) : 10'd0)
                         + (b[0] ? c_hi : 10'd0)
                         + (b[1] ? (c_hi << 1) : 10'd0)
                         + (b[2] ? (c_hi << 2) : 10'd0)
                         + (b[3] ? (c_hi << 3) : 10'd0);
            blend_channel = weighted_sum[9:4];
        end
    endfunction

    wire [5:0] sky_r_blend = blend_channel({1'b0, sky_lo[15:11]}, {1'b0, sky_hi[15:11]}, sky_band);
    wire [5:0] sky_g_blend = blend_channel(sky_lo[10:5],          sky_hi[10:5],          sky_band);
    wire [5:0] sky_b_blend = blend_channel({1'b0, sky_lo[4:0]},   {1'b0, sky_hi[4:0]},   sky_band);

    wire [15:0] sky_rgb_next = (sky_band == 4'd15) ? sky_hi :
                               (sky_band == 4'd0)  ? sky_lo :
                               {sky_r_blend[4:0], sky_g_blend[5:0], sky_b_blend[4:0]};

    reg [15:0] sky_rgb_reg;

    // Synchronous state updates: strictly on game_tick (except single cycle event pulse)
    always @(posedge clk) begin
        if (rst) begin
            anim_tick_cnt   <= 8'd0;
            ground_y_reg    <= 18'sd2030;
            far_scroll_q88  <= 16'sd0;
            near_scroll_q88 <= 16'sd0;
            sky_rgb_reg     <= 16'h2B7A;
            shake_timer     <= 4'd0;
            sparkle_timer   <= 4'd0;
            wind_phase      <= 7'd0;
        end else if (level_start) begin
            anim_tick_cnt   <= 8'd0;
            ground_y_reg    <= ground_y_next;
            far_scroll_q88  <= 16'sd0;
            near_scroll_q88 <= 16'sd0;
            sky_rgb_reg     <= sky_hi;
            shake_timer     <= 4'd0;
            sparkle_timer   <= 4'd0;
            wind_phase      <= 7'd0;
        end else begin
            // Latch 1 cycle event pulses from Member 2 immediately, decrement on game_tick
            if (strike)
                shake_timer <= T_SHAKE[3:0];
            else if (game_tick && shake_timer != 4'd0)
                shake_timer <= shake_timer - 4'd1;

            if (crate_collected)
                sparkle_timer <= T_SPARKLE[3:0];
            else if (game_tick && sparkle_timer != 4'd0)
                sparkle_timer <= sparkle_timer - 4'd1;

            if (game_tick) begin
                anim_tick_cnt   <= anim_tick_cnt + 8'd1;
                ground_y_reg    <= ground_y_next;
                far_scroll_q88  <= far_scroll_q88  + (eff_scroll_vy >>> 2);
                near_scroll_q88 <= near_scroll_q88 + (eff_scroll_vy >>> 1);
                sky_rgb_reg     <= sky_rgb_next;
                if (gust_warn || gust_active)
                    wind_phase <= gust_dir ? (wind_phase - {5'd0, gust_strength}) :
                                             (wind_phase + {5'd0, gust_strength});
            end
        end
    end

    // -----------------------------------------------------------------
    // Layer 10: Full-Screen Impact Flash & Screen Shake Offset
    // -----------------------------------------------------------------
    // Flash on initial strike tick and on ground impact during S_CRASH
    wire crash_flash_on = (is_crash_plunge && (state_timer >= 8'd90 && state_timer < 8'd96)) ||
                          (is_crash_impact && (state_timer < 8'd6));
    wire crash_shake_on = (is_crash_plunge && (state_timer >= 8'd90 && state_timer < 8'd105)) ||
                          (is_crash_impact && (state_timer < 8'd15));

    wire s1_full_flash  = is_gameplay && (crash_flash_on || (shake_timer == T_SHAKE[3:0]));
    wire shake_active   = is_gameplay && ((shake_timer != 4'd0) || crash_shake_on);
    wire signed [8:0] shake_dx = shake_active ? (anim_tick_cnt[0] ? 9'sd2 : -9'sd2) : 9'sd0;

    // Shaken screen X for world/gameplay layers; raw px_raw/py for fixed HUD & menus
    wire signed [8:0] px_raw = {2'b00, pixel_x};
    wire signed [8:0] py     = {3'b000, pixel_y};
    wire signed [8:0] px     = px_raw + shake_dx;

    // -----------------------------------------------------------------
    // Hero Pose, Crash Tumble/Spin-out & Landing Settle/Stumble
    // -----------------------------------------------------------------
    localparam [2:0] POSE_FREEFALL  = 3'd0,
                     POSE_OPEN_1    = 3'd1,
                     POSE_OPEN_2    = 3'd2,
                     POSE_FULL      = 3'd3,
                     POSE_DMG_FLAP1 = 3'd4,
                     POSE_DMG_FLAP2 = 3'd5,
                     POSE_CRUMPLED  = 3'd6,
                     POSE_BRAKE     = 3'd7;   

    reg [2:0] hero_pose_sel;
    reg       hero_mirror_sel;
    reg       hero_vflip_sel;

    // Spin-out horizontal offset for fail_reason == FR_TURBULENCE (reason 2)
    reg signed [8:0] crash_spin_dx;
    always @* begin
        crash_spin_dx = 9'sd0;
        if (is_crash_plunge && (fail_reason == FR_TURBULENCE) && (state_timer < 8'd48)) begin
            case (state_timer[3:2])
                2'd0: crash_spin_dx = -9'sd4;
                2'd1: crash_spin_dx =  9'sd0;
                2'd2: crash_spin_dx =  9'sd4;
                2'd3: crash_spin_dx =  9'sd0;
            endcase
        end
    end

    // hero frame position during gameplay, S_LANDING, and S_CRASH
    // wobble by landing grade - yellow (1) stumbles, red (2) wobbles hard and longer
    wire hard_stumble_on = (game_state == S_LANDING) && (landing_grade != 2'd0) &&
                           (state_timer >= 8'd10) &&
                           (state_timer < ((landing_grade == 2'd2) ? 8'd90 : 8'd45));
    wire signed [8:0] wobble_dx = !hard_stumble_on ? 9'sd0 :
                                  (landing_grade == 2'd2) ? (state_timer[2] ? 9'sd3 : -9'sd3) : 9'sd2;
    // the canopy was never opened (crash in freefall) -> never draw a parachute
    wire no_chute = (canopy_mode == CM_FREEFALL);
    // red-zone flare = death: he lands, wobbles left right for 1 s, then falls flat
    wire red_death  = is_crash_impact && (landing_grade == 2'd2);
    wire [7:0] lie_start = red_death ? 8'd60 : 8'd15;
    wire signed [8:0] death_wob = (red_death && state_timer < 8'd60) ?
                                  (state_timer[2] ? 9'sd3 : -9'sd3) : 9'sd0;

    wire signed [8:0] hx = $signed(hero_x) + crash_spin_dx + wobble_dx + death_wob;
    wire signed [8:0] hy =
        (game_state == S_LANDING) ? (ground_y_reg[8:0] - 9'sd20) :
        is_crash_impact           ? ((state_timer >= lie_start) ? -9'sd64 : (ground_y_reg[8:0] - 9'sd18)) :   // REV5/8: hidden once lying
        (plunge_down && no_chute) ? -9'sd64 :   // REV6: body drawn lying instead
        is_crash_short            ? (short_landed ? short_land_y[8:0] : short_fall_y[8:0]) :   // REV7
        is_crash_plunge           ? ((state_timer < 8'd90) ?
                                     (9'sd10 + $signed({3'b000, state_timer[6:2]})) :
                                     (ground_y_reg[8:0] - 9'sd18)) :
        $signed(hero_y);

    // Settling canopy vertical offset during S_LANDING (rows 0--11 descend into ground)
    wire [4:0] landing_canopy_drop =
        (game_state == S_LANDING) ? ((state_timer < 8'd48) ? state_timer[5:2] : 5'd12) : 5'd0;

    always @* begin
        hero_mirror_sel = 1'b0;
        hero_vflip_sel  = 1'b0;

        if (game_state == S_CRASH) begin
            if (plunge_air) begin
                // Tumbling plunge: alternate freefall & crumpled, flipping H and V
                hero_pose_sel   = no_chute ? POSE_FREEFALL :   // REV6: no parachute if never deployed
                                  (state_timer[3] ? POSE_CRUMPLED : POSE_FREEFALL);
                hero_mirror_sel = state_timer[2];
                hero_vflip_sel  = state_timer[3];
            end else begin
                // On ground after crash impact
                hero_pose_sel   = POSE_CRUMPLED;
                hero_mirror_sel = 1'b0;
            end
        end else if (game_state == S_LANDING) begin
            hero_pose_sel   = (state_timer < 8'd30) ? POSE_FULL : POSE_CRUMPLED;
            hero_mirror_sel = hard_stumble_on && ((landing_grade == 2'd2) ? state_timer[3] : 1'b1);
        end else if (stunned) begin                   // tumbling after a freefall hit
            hero_pose_sel   = POSE_FREEFALL;
            hero_mirror_sel = anim_tick_cnt[2];
            hero_vflip_sel  = anim_tick_cnt[3];
        end else if (game_state == S_FREEFALL_LOCKED || game_state == S_FREEFALL_WINDOW ||
                     canopy_mode == CM_FREEFALL) begin
            hero_pose_sel = POSE_FREEFALL;
        end else if (canopy_mode == CM_STALLED || lines_snapped >= 2'd2) begin
            hero_pose_sel = POSE_CRUMPLED;
        end else if (game_state == S_CANOPY && state_timer < 8'd20) begin
            hero_pose_sel = POSE_OPEN_1;
        end else if (game_state == S_CANOPY && state_timer < 8'd40) begin
            hero_pose_sel = POSE_OPEN_2;
        end else if ((canopy_mode == CM_BRAKING) && (lines_snapped == 2'd0)) begin   // one line gone keeps the damaged sprite
            hero_pose_sel = POSE_BRAKE;      
        end else if (lines_snapped == 2'd1) begin
            hero_pose_sel   = dmg_flap_frame ? POSE_DMG_FLAP2 : POSE_DMG_FLAP1;
            hero_mirror_sel = damaged_side;
        end else begin
            hero_pose_sel = POSE_FULL;
        end
    end

    // -----------------------------------------------------------------
    // STAGE 1: Per-Pixel Layer & Bounding Box Resolution
    // -----------------------------------------------------------------

    // --- Layer 2 & 3: Parallax Clouds (index 3) ---
    wire [5:0] far_y  = pixel_y + far_scroll_q88[13:8];
    wire [5:0] near_y = pixel_y + near_scroll_q88[13:8];
    wire [6:0] px_clamped = (px < 9'sd0) ? 7'd0 : (px > 9'sd95) ? 7'd95 : px[6:0];

    wire in_far_c1 = (px_clamped >= 7'd10 && px_clamped < 7'd22 && far_y >= 6'd10 && far_y < 6'd13) ||
                     (px_clamped >= 7'd13 && px_clamped < 7'd19 && far_y >= 6'd8  && far_y < 6'd10);
    wire in_far_c2 = (px_clamped >= 7'd52 && px_clamped < 7'd64 && far_y >= 6'd30 && far_y < 6'd33) ||
                     (px_clamped >= 7'd55 && px_clamped < 7'd61 && far_y >= 6'd28 && far_y < 6'd30);
    wire in_far_c3 = (px_clamped >= 7'd74 && px_clamped < 7'd86 && far_y >= 6'd52 && far_y < 6'd55) ||
                     (px_clamped >= 7'd77 && px_clamped < 7'd83 && far_y >= 6'd50 && far_y < 6'd52);
    wire s1_in_far_cloud = is_gameplay && (in_far_c1 || in_far_c2 || in_far_c3);

    wire in_near_c1 = (px_clamped >= 7'd20 && px_clamped < 7'd36 && near_y >= 6'd18 && near_y < 6'd22) ||
                      (px_clamped >= 7'd23 && px_clamped < 7'd33 && near_y >= 6'd16 && near_y < 6'd18);
    wire in_near_c2 = (px_clamped >= 7'd62 && px_clamped < 7'd78 && near_y >= 6'd42 && near_y < 6'd46) ||
                      (px_clamped >= 7'd65 && px_clamped < 7'd75 && near_y >= 6'd40 && near_y < 6'd42);
    wire in_near_c3 = (px_clamped >= 7'd4  && px_clamped < 7'd18 && near_y >= 6'd56 && near_y < 6'd60) ||
                      (px_clamped >= 7'd7  && px_clamped < 7'd15 && near_y >= 6'd54 && near_y < 6'd56);
    wire s1_in_near_cloud = is_gameplay && (in_near_c1 || in_near_c2 || in_near_c3);

    // Layer 4: Ground & Setting-Specific Landing Spot
    wire s1_in_ground = is_gameplay && ($signed({10'd0, pixel_y}) >= ground_y_reg);
    wire [5:0] ground_rel_y = s1_in_ground ? (pixel_y - ground_y_reg[5:0]) : 6'd0;
    wire in_spot_x = (px_clamped >= target_x) && (px_clamped < target_x + SPOT_W);
    wire [3:0] spot_rel_x = in_spot_x ? (px_clamped - target_x) : 4'd0;

    reg [4:0] s1_ground_color;
    always @* begin
        s1_ground_color = 5'd12; // Default: Ground main (index 12)
        if (s1_in_ground) begin
            if (in_spot_x && ground_rel_y < 6'd7) begin
                case (level)
                    // Night city (levels 2, 4): Helipad circle with gold ring & white 'H'
                    3'd2, 3'd4: begin
                        if ((ground_rel_y == 6'd0 || ground_rel_y == 6'd6) &&
                            (spot_rel_x >= 4'd3 && spot_rel_x <= 4'd12))
                            s1_ground_color = 5'd10;
                        else if ((ground_rel_y >= 6'd1 && ground_rel_y <= 6'd5) &&
                                 (spot_rel_x == 4'd1 || spot_rel_x == 4'd14))
                            s1_ground_color = 5'd10;
                        else if ((ground_rel_y >= 6'd1 && ground_rel_y <= 6'd5) &&
                                 (spot_rel_x == 4'd6 || spot_rel_x == 4'd9 ||
                                  (ground_rel_y == 6'd3 && spot_rel_x >= 4'd6 && spot_rel_x <= 4'd9)))
                            s1_ground_color = 5'd2;
                        else
                            s1_ground_color = 5'd1;
                    end
                    // Sunset (level 5): Sandpit using palette index 18
                    3'd5: begin
                        if (ground_rel_y < 6'd4) begin
                            if (spot_rel_x == 4'd0 || spot_rel_x == 4'd15 || ground_rel_y == 6'd3)
                                s1_ground_color = 5'd9;
                            else
                                s1_ground_color = 5'd18;
                        end
                    end
                    // Day (levels 1, 3): Target tile pad
                    default: begin
                        if (ground_rel_y < 6'd4) begin
                            if (spot_rel_x == 4'd0 || spot_rel_x == 4'd15 || ground_rel_y == 6'd3)
                                s1_ground_color = 5'd1;
                            else if (spot_rel_x >= 4'd6 && spot_rel_x <= 4'd9)
                                s1_ground_color = 5'd10;
                            else if (spot_rel_x[1])
                                s1_ground_color = 5'd2;
                            else
                                s1_ground_color = 5'd11;
                        end
                    end
                endcase
            end else begin
                case (level)
                    3'd2, 3'd4: begin
                        if ((ground_rel_y >= 6'd2) && (ground_rel_y[1:0] == 2'd1) &&
                            (px_clamped[2:0] == 3'd2 || px_clamped[2:0] == 3'd5))
                            s1_ground_color = 5'd13;
                    end
                    3'd5: begin
                        if (ground_rel_y == 6'd0 || ((ground_rel_y == 6'd1) && px_clamped[0]))
                            s1_ground_color = 5'd13;
                    end
                    default: begin
                        if ((ground_rel_y == 6'd0 && px_clamped[1]) ||
                            (ground_rel_y == 6'd1 && (px_clamped[2:0] == 3'd3)))
                            s1_ground_color = 5'd13;
                    end
                endcase
            end
        end
    end

    // - Layer 5: Crates (4 slots, 6x9) -
    integer c;
    reg        s1_in_crate;
    reg [2:0]  s1_crate_col;
    reg [3:0]  s1_crate_row;
    reg signed [8:0] cx_c, cy_c;

    always @* begin
        s1_in_crate  = 1'b0;
        s1_crate_col = 3'd0;
        s1_crate_row = 4'd0;
        for (c = 0; c < 4; c = c + 1) begin
            cx_c = $signed(crate_x[8*c +: 8]);
            cy_c = $signed(crate_y[8*c +: 8]);
            if (!s1_in_crate && crate_active[c] &&
                (px >= cx_c) && (px < cx_c + CRATE_W) &&
                (py >= cy_c) && (py < cy_c + CRATE_H)) begin
                s1_in_crate  = 1'b1;
                s1_crate_col = px - cx_c;
                s1_crate_row = py - cy_c;
            end
        end
    end

    // -- Layer 6: Obstacles (6 slots: Bird 8x6, Plane 24x8, Debris 6x6) --
    integer i;
    reg        s1_in_obs;
    reg [1:0]  s1_obs_type;
    reg        s1_obs_flip;
    reg [4:0]  s1_obs_col;
    reg [2:0]  s1_obs_row;
    reg signed [8:0] ox_i, oy_i, ow_i, oh_i;
    reg [1:0]        ot_i;

    always @* begin
        s1_in_obs   = 1'b0;
        s1_obs_type = OBS_EMPTY;
        s1_obs_flip = 1'b0;
        s1_obs_col  = 5'd0;
        s1_obs_row  = 3'd0;
        for (i = 0; i < 6; i = i + 1) begin
            ox_i = $signed(obs_x[8*i +: 8]);
            oy_i = $signed(obs_y[8*i +: 8]);
            ot_i = obs_type[2*i +: 2];
            case (ot_i)
                OBS_BIRD:   begin ow_i = BIRD_W;   oh_i = BIRD_H;   end
                OBS_PLANE:  begin ow_i = PLANE_W;  oh_i = PLANE_H;  end
                OBS_DEBRIS: begin ow_i = DEBRIS_W; oh_i = DEBRIS_H; end
                default:    begin ow_i = 9'sd0;    oh_i = 9'sd0;    end
            endcase
            if (!s1_in_obs && obs_active[i] && (ot_i != OBS_EMPTY) &&
                (px >= ox_i) && (px < ox_i + ow_i) &&
                (py >= oy_i) && (py < oy_i + oh_i)) begin
                s1_in_obs   = 1'b1;
                s1_obs_type = ot_i;
                s1_obs_flip = obs_flip[i];
                s1_obs_col  = px - ox_i;
                s1_obs_row  = py - oy_i;
            end
        end
    end

    // --- Layer 7: Hero (16x20 frame, with tumble vflip & landing canopy settle) ---
    // REV6: canopy rows lean toward the bank (1 px slight, 2 px hard); body rows swing under the canopy after a gust (swing_dx). Box widened by 3 px each side.
    wire in_hero_box = is_gameplay &&
                       (px >= hx - 9'sd8) && (px < hx + HERO_FRAME_W + 9'sd8) &&   // REV7: room for the tilt
                       (py >= hy) && (py < hy + HERO_FRAME_H);
    wire        flying_canopy = (game_state == S_CANOPY || game_state == S_FINAL_APPROACH) &&
                                (canopy_mode != CM_FREEFALL);
    wire signed [3:0] lean_mag = (bank_lvl == 2'd2) ? 4'sd2 : (bank_lvl == 2'd1) ? 4'sd1 : 4'sd0;
    wire signed [3:0] lean_px  = !flying_canopy ? 4'sd0 : (bank_left ? -lean_mag : lean_mag);
    wire [4:0] raw_hero_row = in_hero_box ? (py - hy) : 5'd0;

    // During S_LANDING, rows 0..11 (canopy) settle down behind the hero and vanish at tick 48
    wire canopy_settled_out = (game_state == S_LANDING) &&
                              ((raw_hero_row < 5'd12) &&
                               ((state_timer >= 8'd48) || (raw_hero_row < landing_canopy_drop)));

    // REV7: pendulum TILT. The canopy stays put (pivot), every row below is shifted a
    // little more than the one above (at most 1 px between rows), so the lines, the
    // hands and the body always stay connected. Banking right swings the body left
    // (outward); a gust adds the swing_dx offset at the feet.
    // lean_px is already signed by the bank direction (+ right, - left)
    wire signed [5:0] feet_off = (!flying_canopy) ? 6'sd0 :
                                 -({{2{lean_px[3]}}, lean_px} <<< 1) + {{3{swing_dx[2]}}, swing_dx};
    wire signed [10:0] shear     = feet_off * $signed({6'd0, raw_hero_row});
    wire signed [10:0] shear_px  = shear >>> 4;           // row 19 -> about feet_off
    wire signed [3:0]  row_shift = (shear_px > 11'sd7) ? 4'sd7 : (shear_px < -11'sd7) ? -4'sd7 : shear_px[3:0];
    wire signed [8:0] hero_col_s = px - hx - {{5{row_shift[3]}}, row_shift};
    wire s1_in_hero = in_hero_box && !canopy_settled_out &&
                      (hero_col_s >= 9'sd0) && (hero_col_s < 9'sd16);
    wire [3:0] s1_hero_col = s1_in_hero ? hero_col_s[3:0] : 4'd0;
    wire [4:0] s1_hero_row = s1_in_hero ?
        (hero_vflip_sel ? (5'd19 - raw_hero_row) :
         ((game_state == S_LANDING && raw_hero_row < 5'd12) ?
          (raw_hero_row - landing_canopy_drop) : raw_hero_row)) : 5'd0;

    // --- Layer 8: Effects (Magnet Aura, Pickup Sparkle, Curly Wind, Landing/Crash Dust) ---
    // Hero body centre at (hx + 8, hy + 15)
    wire signed [8:0] body_cx = hx + 9'sd8;
    wire signed [8:0] body_cy = hy + 9'sd15;
    wire signed [8:0] rel_bx  = px - body_cx;
    wire signed [8:0] rel_by  = py - body_cy;

    // 8-point circular lookup table around hero body centre for magnet aura (radius ~9 px)
    function signed [8:0] aura_lut_x;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: aura_lut_x =  9'sd0;
                3'd1: aura_lut_x =  9'sd6;
                3'd2: aura_lut_x =  9'sd9;
                3'd3: aura_lut_x =  9'sd6;
                3'd4: aura_lut_x =  9'sd0;
                3'd5: aura_lut_x = -9'sd6;
                3'd6: aura_lut_x = -9'sd9;
                3'd7: aura_lut_x = -9'sd6;
            endcase
        end
    endfunction

    function signed [8:0] aura_lut_y;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: aura_lut_y = -9'sd9;
                3'd1: aura_lut_y = -9'sd6;
                3'd2: aura_lut_y =  9'sd0;
                3'd3: aura_lut_y =  9'sd6;
                3'd4: aura_lut_y =  9'sd9;
                3'd5: aura_lut_y =  9'sd6;
                3'd6: aura_lut_y =  9'sd0;
                3'd7: aura_lut_y = -9'sd6;
            endcase
        end
    endfunction

    // 6 orbiting points selected from the 8 point LUT using anim_tick_cnt[4:2]
    wire [2:0] aura_base = anim_tick_cnt[4:2];
    wire in_aura_pt =
        (rel_bx == aura_lut_x(aura_base + 3'd0) && rel_by == aura_lut_y(aura_base + 3'd0)) ||
        (rel_bx == aura_lut_x(aura_base + 3'd1) && rel_by == aura_lut_y(aura_base + 3'd1)) ||
        (rel_bx == aura_lut_x(aura_base + 3'd2) && rel_by == aura_lut_y(aura_base + 3'd2)) ||
        (rel_bx == aura_lut_x(aura_base + 3'd4) && rel_by == aura_lut_y(aura_base + 3'd4)) ||
        (rel_bx == aura_lut_x(aura_base + 3'd5) && rel_by == aura_lut_y(aura_base + 3'd5)) ||
        (rel_bx == aura_lut_x(aura_base + 3'd6) && rel_by == aura_lut_y(aura_base + 3'd6));
    wire fx_magnet_on = is_gameplay && magnet_active && in_aura_pt;

    // Pickup sparkle: expanding 8 ray gold burst around hero body for 10 ticks
    wire signed [8:0] spk_r = $signed({5'd0, (4'd11 - sparkle_timer)});
    wire in_sparkle_pt =
        ((rel_bx ==  spk_r || rel_bx == -spk_r) && (rel_by == 9'sd0 || rel_by == spk_r || rel_by == -spk_r)) ||
        ((rel_by ==  spk_r || rel_by == -spk_r) && (rel_bx == 9'sd0));
    wire fx_sparkle_on = is_gameplay && (sparkle_timer != 4'd0) && in_sparkle_pt;

    // Curly wind lines: 1..3 cyan wavy streaks drifting toward gust_dir
    wire [6:0] wind_x = px_clamped + wind_phase;
    wire [5:0] curl_dy = wind_x[2] ? 6'd1 : 6'd0;
    wire wind_seg_on = (wind_x[4:0] < 5'd14); // 14-px streak every 32 px horizontally
    wire wind_line1 = (gust_strength >= 2'd1) && wind_seg_on && (pixel_y == (6'd18 + curl_dy));
    wire wind_line2 = (gust_strength >= 2'd2) && ((wind_x + 7'd11) & 7'd16) && (pixel_y == (6'd34 + curl_dy));
    wire wind_line3 = (gust_strength >= 2'd3) && wind_seg_on && (pixel_y == (6'd48 + curl_dy));
    wire fx_wind_on = is_gameplay && (gust_warn || gust_active) &&
                      (wind_line1 || wind_line2 || wind_line3);

    // Hard landing dust puff (ticks 5..45 of S_LANDING when landing_grade == 1)
    // and Crash ground impact debris burst
    wire signed [8:0] foot_y = ground_y_reg[8:0] - 9'sd2;
    wire signed [8:0] dust_r = (game_state == S_LANDING) ?
                               $signed({4'd0, state_timer[5:2]}) : 9'sd6;
    wire in_dust_puff =
        ((py == foot_y || py == foot_y - 9'sd2) &&
         ((px == body_cx - dust_r) || (px == body_cx + dust_r) ||
          (px == body_cx - (dust_r >> 1)) || (px == body_cx + (dust_r >> 1))));
    wire fx_dust_on =
        ((game_state == S_LANDING) && landing_grade && (state_timer >= 8'd4 && state_timer < 8'd44) && in_dust_puff) ||
        ((plunge_down || is_crash_impact) && in_dust_puff);

    // REV5: hero lying flat after a crash landing (16x5), crumpled canopy beside him
    function [4:0] lie_px; input [2:0] r; input [3:0] c;
        reg [79:0] row;
        begin
            case (r)            //  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
                3'd0: row = {5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd5,5'd5,5'd5,5'd0};
                3'd1: row = {5'd1,5'd1,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd5,5'd6,5'd5,5'd5,5'd5};
                3'd2: row = {5'd8,5'd8,5'd8,5'd2,5'd2,5'd11,5'd2,5'd2,5'd7,5'd7,5'd7,5'd7,5'd1,5'd6,5'd5,5'd5};
                3'd3: row = {5'd8,5'd8,5'd8,5'd2,5'd2,5'd11,5'd2,5'd2,5'd7,5'd7,5'd7,5'd7,5'd1,5'd0,5'd0,5'd0};
                default: row = 80'd0;
            endcase
            lie_px = row[5*(15 - c) +: 5];
        end
    endfunction
    wire signed [9:0] lie_x0  = $signed({hero_x[7], hero_x}) + 10'sd0;
    wire signed [9:0] lie_y0  = $signed(ground_y_reg[9:0]) - 10'sd4;
    wire signed [9:0] lie_col = $signed({3'd0, pixel_x}) - lie_x0;
    wire signed [9:0] lie_row = $signed({4'd0, pixel_y}) - lie_y0;
    wire in_lie_box = ((is_crash_impact && (state_timer >= lie_start)) ||
                       (plunge_down && no_chute)) &&   // REV6/7
                      (lie_col >= 10'sd0) && (lie_col < 10'sd16) && (lie_row >= 10'sd0) && (lie_row < 10'sd4);
    reg  [4:0] lie_c;
    reg       s1_in_fx;
    reg [4:0] s1_fx_color;
    always @* begin
        s1_in_fx    = 1'b0;
        lie_c       = lie_px(lie_row[2:0], lie_col[3:0]);
        if (no_chute && (lie_c == 5'd5 || lie_c == 5'd6)) lie_c = 5'd0;   // REV6: no canopy beside him
        s1_fx_color = 5'd0;
        if (in_lie_box && lie_c != 5'd0) begin   // hero lying on the ground ("sleeping")
            s1_in_fx    = 1'b1;
            s1_fx_color = lie_c;
        end else if (fx_sparkle_on) begin
            s1_in_fx    = 1'b1;
            s1_fx_color = 5'd10; // Gold pickup sparkle
        end else if (fx_magnet_on) begin
            s1_in_fx    = 1'b1;
            s1_fx_color = 5'd14; // Cyan magnet aura
        end else if (fx_dust_on) begin
            s1_in_fx    = 1'b1;
            s1_fx_color = (game_state == S_CRASH) ? 5'd5 : 5'd3; // Orange/grey puff
        end else if (fx_wind_on) begin
            s1_in_fx    = 1'b1;
            // REV4: grey wind on the light-blue day levels (cyan was invisible there)
            s1_fx_color = (level == 3'd1 || level == 3'd3) ? 5'd4 : 5'd14;
        end
    end

    // --- Layer 9: HUD Indicators, Edge Bands & Two-Part Flare Lane ---
    // 1. Edge turbulence bands (x <= 2 or x >= 93); brighten when hero is within 8 px
    wire hero_near_left  = (hx <= 9'sd10);
    wire hero_near_right = (hx + HERO_FRAME_W >= 9'sd85);
    wire in_left_band    = is_gameplay && (pixel_x <= EDGE_LEFT_MAX);
    wire in_right_band   = is_gameplay && (pixel_x >= EDGE_RIGHT_MIN);

    wire left_band_on  = in_left_band && (hero_near_left ?
                         (anim_tick_cnt[1] ? (pixel_x[0] ^ pixel_y[0]) : 1'b1) :
                         ((pixel_x[1:0] + pixel_y[1:0]) == 2'b00));
    wire right_band_on = in_right_band && (hero_near_right ?
                         (anim_tick_cnt[1] ? (pixel_x[0] ^ pixel_y[0]) : 1'b1) :
                         ((pixel_x[1:0] + pixel_y[1:0]) == 2'b00));
    wire s1_in_edge_band = left_band_on || right_band_on;

    // 2. Flare lane at x = 86..91 in S_FINAL_APPROACH (y = 4..59; interior y = 5..58, 54 px tall)
    //    Top half (y = 5..31, 27 px) maps 150 m -> 30 m using shifts:
    //      offset = ((150 - alt) >> 2) - ((150 - alt) >> 5)  [maps 120 m span to 27 px]
    //    Bottom half (y = 32..58, 27 px) maps 30 m -> 0 m using shifts:
    //      offset = (30 - alt) - ((30 - alt) >> 3)           [maps 30 m span to 27 px]
    wire [7:0] alt_clamped_150 = (alt_metres > 16'd150) ? 8'd150 : alt_metres[7:0];
    // REV5: once C is pressed the marker FREEZES at the press height, so the
    // player sees which zone they hit (red = crash, yellow = hard, green = soft)
    reg  [7:0] flare_alt_l = 8'd150;
    always @(posedge clk) if (!flare_locked) flare_alt_l <= alt_clamped_150;
    wire [7:0] marker_alt      = flare_locked ? flare_alt_l : alt_clamped_150;
    wire [7:0] d_top           = 8'd150 - marker_alt;
    wire [7:0] d_bot           = (marker_alt > 8'd30) ? 8'd0 : (8'd30 - marker_alt);

    wire [5:0] marker_y_top = 6'd5  + d_top[7:2] - {3'b000, d_top[7:5]};
    wire [5:0] marker_y_bot = 6'd32 + d_bot[5:0] - {3'b000, d_bot[5:3]};
    wire [5:0] flare_marker_y = (marker_alt >= 8'd30) ? marker_y_top : marker_y_bot;

    wire in_flare_lane = (game_state == S_FINAL_APPROACH) &&
                         (pixel_x >= FLARE_LANE_X) && (pixel_x <= FLARE_LANE_X + 7'd5) &&
                         (pixel_y >= 6'd4) && (pixel_y <= 6'd59);
    wire in_flare_marker = in_flare_lane &&
                           (pixel_x >= FLARE_LANE_X + 7'd1) && (pixel_x <= FLARE_LANE_X + 7'd4) &&
                           (pixel_y >= flare_marker_y) && (pixel_y < flare_marker_y + 6'd3);

    reg [4:0] s1_flare_color;
    always @* begin
        s1_flare_color = 5'd1; // Black border / marker
        if (in_flare_lane) begin
            if (in_flare_marker ||
                pixel_x == FLARE_LANE_X || pixel_x == (FLARE_LANE_X + 7'd5) ||
                pixel_y == 6'd4 || pixel_y == 6'd59) begin
                s1_flare_color = 5'd1; // Black 4x3 marker or 1-px lane outline
            end else if (pixel_y < 6'd34) begin
                s1_flare_color = 5'd11; // Red zone (> 28 m)
            end else if (pixel_y < 6'd43) begin
                s1_flare_color = 5'd10; // Yellow hard zone (28..18 m)
            end else if (pixel_y < 6'd55) begin
                s1_flare_color = 5'd19; // Bright green soft zone (18..4 m)
            end else if (pixel_y < 6'd58) begin
                s1_flare_color = 5'd10; // Yellow hard zone (4..1 m)
            end else begin
                s1_flare_color = 5'd11; // Red zone (< 1 m)
            end
        end
    end

    // 3. HUD & Menu Icons via shared sprite_rom icon port
    wire lock_closed_on = (game_state == S_FREEFALL_LOCKED);
    wire lock_open_on   = (game_state == S_FREEFALL_WINDOW) &&
                          (state_timer < T_UNLOCK_ANIM) && (state_timer[2] == 1'b0);
    wire in_lock_box    = (lock_closed_on || lock_open_on) &&
                          (pixel_x >= 7'd4 && pixel_x < 7'd9) &&
                          (pixel_y >= 6'd2 && pixel_y < 6'd8);

    wire [5:0] warn_y_top = warn_edge ? 6'd1 : 6'd58;
    wire in_warn_box      = is_gameplay && warn_active && blink_4hz &&
                            (px_raw >= $signed(warn_x)) && (px_raw < $signed(warn_x) + 9'sd5) &&
                            (pixel_y >= warn_y_top) && (pixel_y < warn_y_top + 6'd5);

    wire camera_unlocked  = (ground_y_reg > GROUND_LOCK_Y);
    // BIG blinking gold arrow (9x9 icon drawn at 2x = 18x18) pointing at the
    // landing spot for the whole final approach: at the bottom edge until the
    // ground appears, then just above the star on the spot.
    wire [7:0] arrow_x0   = target_x - 8'd1;                     // centred on target_x + 8
    wire signed [17:0] arrow_y0s = (ground_y_reg <= 18'sd63) ? (ground_y_reg - 18'sd29) : 18'sd44;
    wire [5:0] arrow_y0   = arrow_y0s[5:0];
    wire in_arrow_box     = (game_state == S_FINAL_APPROACH) && blink_4hz &&
                            (pixel_x >= arrow_x0[6:0]) && (pixel_x < arrow_x0[6:0] + 7'd18) &&
                            (pixel_y >= arrow_y0) && (pixel_y < arrow_y0 + 6'd18);

    // FIX #15: gold 9x9 star standing on the landing spot, so the target is obvious.
    // Shown in FINAL_APPROACH once the ground is on screen.
    wire signed [17:0] spot_star_y0 = ground_y_reg - 18'sd10;
    wire [7:0] spot_star_x0 = target_x + 8'd3;            // centred on the 16-px spot
    wire in_spot_star = (game_state == S_FINAL_APPROACH) && (ground_y_reg <= 18'sd63) &&
                        (pixel_x >= spot_star_x0[6:0]) && (pixel_x < spot_star_x0[6:0] + 7'd9) &&
                        ($signed({12'd0, pixel_y}) >= spot_star_y0) &&
                        ($signed({12'd0, pixel_y}) <  spot_star_y0 + 18'sd9);
    wire [17:0] spot_star_row = $signed({12'd0, pixel_y}) - spot_star_y0;

    // REV3: plane warning triangle, flashing on the left (x=4) or right (x=87) edge
    wire [6:0] pwarn_x0 = pwarn_right ? 7'd87 : 7'd4;
    wire [5:0] pwarn_y0 = (pwarn_y < 8'sd0) ? 6'd0 : (pwarn_y > 8'sd58) ? 6'd58 : pwarn_y[5:0];
    wire in_pwarn_box = is_gameplay && pwarn_active && blink_4hz &&
                        (pixel_x >= pwarn_x0) && (pixel_x < pwarn_x0 + 7'd5) &&
                        (pixel_y >= pwarn_y0) && (pixel_y < pwarn_y0 + 6'd5);
    // REV3: gold star rising from the hero after a crate (30 ticks)
    wire signed [8:0]  pop_x0 = hx + 9'sd3;
    wire signed [9:0]  pop_y0 = $signed({hy[8], hy}) - 10'sd4 - $signed({5'd0, (5'd30 - pop_timer)});
    wire signed [9:0]  pop_row = $signed({4'd0, pixel_y}) - pop_y0;
    wire in_pop_star = is_gameplay && (pop_timer != 5'd0) &&
                       (px_raw >= pop_x0) && (px_raw < pop_x0 + 9'sd9) &&
                       (pop_row >= 10'sd0) && (pop_row < 10'sd9);

    // Menu 9x9 stars on S_LEVEL_COMPLETE (3 vertical rows) and S_VICTORY (double-size 18x18)
    wire in_lc_star1 = (game_state == S_LEVEL_COMPLETE) && (state_timer >= T_STAR1) &&
                       (pixel_x >= 7'd6 && pixel_x < 7'd15) && (pixel_y >= 6'd5  && pixel_y < 6'd14);
    wire in_lc_star2 = (game_state == S_LEVEL_COMPLETE) && (state_timer >= T_STAR2) &&
                       (pixel_x >= 7'd6 && pixel_x < 7'd15) && (pixel_y >= 6'd18 && pixel_y < 6'd27);
    wire in_lc_star3 = (game_state == S_LEVEL_COMPLETE) && (state_timer >= T_STAR3) &&
                       (pixel_x >= 7'd6 && pixel_x < 7'd15) && (pixel_y >= 6'd31 && pixel_y < 6'd40);
    wire in_vic_star = (game_state == S_VICTORY) &&
                       (pixel_x >= 7'd39 && pixel_x < 7'd57) && (pixel_y >= 6'd16 && pixel_y < 6'd34);

    reg       s1_in_icon;
    reg [2:0] s1_icon_id;
    reg [3:0] s1_icon_col;
    reg [3:0] s1_icon_row;
    reg       s1_star_earned;

    always @* begin
        s1_in_icon     = 1'b0;
        s1_icon_id     = 3'd0;
        s1_icon_col    = 4'd0;
        s1_icon_row    = 4'd0;
        s1_star_earned = 1'b1;

        if (in_lock_box) begin
            s1_in_icon  = 1'b1;
            s1_icon_id  = lock_open_on ? 3'd1 : 3'd0;
            s1_icon_col = pixel_x - 7'd4;
            s1_icon_row = pixel_y - 6'd2;
        end else if (in_warn_box) begin
            s1_in_icon  = 1'b1;
            s1_icon_id  = 3'd2;
            s1_icon_col = px_raw - $signed(warn_x);
            s1_icon_row = pixel_y - warn_y_top;
        end else if (in_arrow_box) begin
            s1_in_icon  = 1'b1;
            s1_icon_id  = 3'd3;
            s1_icon_col = (pixel_x - arrow_x0[6:0]) >> 1;   // 2x scale
            s1_icon_row = (pixel_y - arrow_y0) >> 1;
        end else if (in_pwarn_box) begin   // REV3: plane warning on the side edge
            s1_in_icon  = 1'b1;
            s1_icon_id  = 3'd2;
            s1_icon_col = pixel_x - pwarn_x0;
            s1_icon_row = pixel_y - pwarn_y0;
        end else if (in_pop_star) begin    // REV3: crate star pop-up
            s1_in_icon  = 1'b1;
            s1_icon_id  = 3'd4;
            s1_icon_col = px_raw - pop_x0;
            s1_icon_row = pop_row[3:0];
        end else if (in_spot_star) begin   // FIX #15
            s1_in_icon  = 1'b1;
            s1_icon_id  = 3'd4;               // gold star icon
            s1_icon_col = pixel_x - spot_star_x0[6:0];
            s1_icon_row = spot_star_row[3:0];
        end else if (in_lc_star1) begin
            s1_in_icon     = 1'b1;
            s1_icon_id     = 3'd4;
            s1_icon_col    = pixel_x - 7'd6;
            s1_icon_row    = pixel_y - 6'd5;
            s1_star_earned = stars_earned[0];
        end else if (in_lc_star2) begin
            s1_in_icon     = 1'b1;
            s1_icon_id     = 3'd4;
            s1_icon_col    = pixel_x - 7'd6;
            s1_icon_row    = pixel_y - 6'd18;
            s1_star_earned = stars_earned[1];
        end else if (in_lc_star3) begin
            s1_in_icon     = 1'b1;
            s1_icon_id     = 3'd4;
            s1_icon_col    = pixel_x - 7'd6;
            s1_icon_row    = pixel_y - 6'd31;
            s1_star_earned = stars_earned[2];
        end else if (in_vic_star) begin
            s1_in_icon     = 1'b1;
            s1_icon_id     = 3'd4;
            s1_icon_col    = (pixel_x - 7'd39) >> 1;
            s1_icon_row    = (pixel_y - 6'd16) >> 1;
            s1_star_earned = 1'b1;
        end
    end

    // --- Menu Geometry & Shared Font Lookup (All 5 Menu Screens + HUD Counter) ---
    reg        s1_in_menu_rect;
    reg [4:0]  s1_menu_rect_color;
    reg [2:0]  s1_box_level;
    reg        s1_in_box_fill;

    reg        s1_in_text;
    reg [7:0]  s1_text_char;
    reg [2:0]  s1_text_col;
    reg [2:0]  s1_text_row;
    reg [4:0]  s1_text_color;

    reg [2:0]  home_box_id;
    reg        in_any_home_box;
    reg [3:0]  box_rx, box_ry;
    reg [1:0]  box_stars;
    reg [6:0]  tx, char_idx, char_rem;
    reg [5:0]  ty;

    // Helper: divide 0..95 by 6 (character pitch = 5 px glyph + 1 px gap) without a divider
    function [3:0] div6;
        input [6:0] val;
        begin
            if      (val < 7'd6)  div6 = 4'd0;
            else if (val < 7'd12) div6 = 4'd1;
            else if (val < 7'd18) div6 = 4'd2;
            else if (val < 7'd24) div6 = 4'd3;
            else if (val < 7'd30) div6 = 4'd4;
            else if (val < 7'd36) div6 = 4'd5;
            else if (val < 7'd42) div6 = 4'd6;
            else if (val < 7'd48) div6 = 4'd7;
            else if (val < 7'd54) div6 = 4'd8;
            else if (val < 7'd60) div6 = 4'd9;
            else if (val < 7'd66) div6 = 4'd10;
            else if (val < 7'd72) div6 = 4'd11;
            else if (val < 7'd78) div6 = 4'd12;
            else if (val < 7'd84) div6 = 4'd13;
            else                  div6 = 4'd14;
        end
    endfunction

    // REV4: HOME prompt icons. Right arrow 9x7 (shaft + stepped head), circle 7x7.
    function arrow_px; input [2:0] r; input [3:0] c;
        reg [8:0] bits;
        begin
            case (r)
                3'd0: bits = 9'b000001000;
                3'd1: bits = 9'b000001100;
                3'd2: bits = 9'b111111110;
                3'd3: bits = 9'b111111111;
                3'd4: bits = 9'b111111110;
                3'd5: bits = 9'b000001100;
                default: bits = 9'b000001000;
            endcase
            arrow_px = bits[4'd8 - c];
        end
    endfunction
    function circle_px; input [2:0] r; input [2:0] c;
        reg [6:0] bits;
        begin
            case (r)
                3'd0, 3'd6: bits = 7'b0011100;
                3'd1, 3'd5: bits = 7'b0111110;
                default:    bits = 7'b1111111;
            endcase
            circle_px = bits[3'd6 - c];
        end
    endfunction
    reg [5:0] hy7;

    // REV3: message strings (max 16 chars), left edge so the text is centred
    reg [127:0] msg_str;  reg [4:0] msg_len;  reg [6:0] msg_x0;
    always @* begin
        case (msg_id)
            4'd1:    begin msg_str = "AVOID BIRDS";      msg_len = 5'd11; end
            4'd2:    begin msg_str = "GRAB CRATES";      msg_len = 5'd11; end
            4'd3:    begin msg_str = "WIND! STEER";      msg_len = 5'd11; end
            4'd4:    begin msg_str = "C ON GREEN";       msg_len = 5'd10; end   // REV4: shorter (was cut off by the flare lane)
            4'd5:    begin msg_str = "STRONGER WIND";    msg_len = 5'd13; end
            4'd6:    begin msg_str = "DEBRIS ABOVE!";    msg_len = 5'd13; end
            4'd7:    begin msg_str = "PLANES! TUG UP";   msg_len = 5'd14; end
            4'd8:    begin msg_str = "FINAL DESCENT";    msg_len = 5'd13; end
            4'd10:   begin msg_str = "STUNNED!";         msg_len = 5'd8;  end   // REV6
            default: begin msg_str = "REPAIRED!";        msg_len = 5'd9;  end
        endcase
        msg_x0 = (7'd97 - (msg_len * 7'd6)) >> 1;
    end

    // REV4: levels 1, 3 (day) and 5 (sunset) have light skies -> dark HUD text
    wire light_bg = (level == 3'd1) || (level == 3'd3) || (level == 3'd5);
    wire [4:0] hud_txt_col = light_bg ? 5'd7 : 5'd2;    // navy on light skies, white at night
    wire [4:0] hud_hi_col  = light_bg ? 5'd7 : 5'd10;   // navy on light skies, gold at night

    // FIX #14 / #5: when to show the "PRESS C" prompt
    // REV6: shown for the WHOLE deploy window, from the moment the lock disappears
    // REV9: only once the lock icon has gone - exactly when C starts to work
    wire press_c_on = ((game_state == S_FREEFALL_WINDOW) && (state_timer >= T_UNLOCK_ANIM)) ||
                      ((game_state == S_FINAL_APPROACH) &&
                       (alt_metres <= FLARE_SOFT_HI) && (alt_metres >= FLARE_SOFT_LO));

    wire [3:0] tot_tens = (total_stars >= 4'd10) ? 4'd1 : 4'd0;
    wire [3:0] tot_ones = (total_stars >= 4'd10) ? (total_stars - 4'd10) : total_stars;

    always @* begin
        s1_in_menu_rect    = 1'b0;
        s1_menu_rect_color = 5'd7;
        s1_box_level       = level;
        s1_in_box_fill     = 1'b0;

        s1_in_text         = 1'b0;
        s1_text_char       = " ";
        s1_text_col        = 3'd0;
        s1_text_row        = 3'd0;
        s1_text_color      = 5'd2;

        home_box_id        = 3'd0;
        in_any_home_box    = 1'b0;
        box_rx             = 4'd0;
        box_ry             = 4'd0;
        box_stars          = 2'd0;
        tx                 = 7'd0;
        ty                 = 6'd0;
        char_idx           = 7'd0;
        char_rem           = 7'd0;

        // -------------------------------------------------------------
        // 1. Gameplay HUD Crate Counter ("crates_got/crates_level_total")
        // -------------------------------------------------------------
        if ((game_state == S_CANOPY || game_state == S_FINAL_APPROACH) &&
            (pixel_y >= 6'd2 && pixel_y < 6'd9) &&
            (pixel_x >= 7'd4 && pixel_x < 7'd21)) begin
            ty            = pixel_y - 6'd2;
            tx            = pixel_x - 7'd4;
            char_idx      = div6(tx);
            char_rem      = tx - (char_idx * 7'd6);
            s1_text_row   = ty[2:0];
            s1_text_color = hud_txt_col;      // REV4: dark on light skies
            if (char_rem < 7'd5) begin
                s1_in_text  = 1'b1;
                s1_text_col = char_rem[2:0];
                case (char_idx)
                    4'd0: s1_text_char = {5'd0, crates_got};
                    4'd1: s1_text_char = "/";
                    4'd2: s1_text_char = {5'd0, crates_level_total};
                    default: s1_in_text = 1'b0;
                endcase
            end
        end

        // -----------------------------------------------------------------
        // 1b. NEW (FIX #14 / #5): blinking gold "PRESS C" at the top centre
        //     - deploy: perfect window 1,550-1,450 m (LED gauge full)
        //     - landing flare: soft (green) window
        // ---------------------------------------------------------------
        // REV4: moved from the top to the middle of the screen (rows 44-50)
        else if (press_c_on && blink_4hz &&
                 (pixel_y >= 6'd26 && pixel_y < 6'd33) &&
                 (pixel_x >= 7'd28 && pixel_x < 7'd69)) begin
            ty            = pixel_y - 6'd26;      // REV4: mid-screen
            tx            = pixel_x - 7'd28;
            char_idx      = div6(tx);
            char_rem      = tx - (char_idx * 7'd6);
            s1_text_row   = ty[2:0];
            s1_text_color = hud_hi_col;       // REV4: navy on light skies, gold at night
            if (char_rem < 7'd5) begin
                s1_in_text  = 1'b1;
                s1_text_col = char_rem[2:0];
                case (char_idx)
                    4'd0: s1_text_char = "P";
                    4'd1: s1_text_char = "R";
                    4'd2: s1_text_char = "E";
                    4'd3: s1_text_char = "S";
                    4'd4: s1_text_char = "S";
                    4'd6: s1_text_char = "C";
                    default: s1_in_text = 1'b0;
                endcase
            end
        end

        // -------------------------------------------------------------
        // 1c. REV3 guidance text (gold, centred, rows 32-38)
        // -------------------------------------------------------------
        else if (msg_on && (pixel_y >= 6'd35 && pixel_y < 6'd42) &&   // REV4: just below PRESS C
                 (pixel_x >= msg_x0) && (pixel_x < msg_x0 + {msg_len, 2'b00} + {msg_len, 1'b0})) begin
            ty            = pixel_y - 6'd35;
            tx            = pixel_x - msg_x0;
            char_idx      = div6(tx);
            char_rem      = tx - (char_idx * 7'd6);
            s1_text_row   = ty[2:0];
            // REV4: darker text on light skies (navy; REPAIRED! dark green)
            s1_text_color = (msg_id == 4'd9) ? (light_bg ? 5'd13 : 5'd19) : hud_hi_col;
            if (char_rem < 7'd5 && char_idx < msg_len) begin
                s1_in_text   = 1'b1;
                s1_text_col  = char_rem[2:0];
                s1_text_char = msg_str[8*(msg_len - 1 - char_idx) +: 8];
            end
        end

        // -------------------------------------------------------------
        // 2. S_HOME Screen
        // -------------------------------------------------------------
        else if (game_state == S_HOME) begin
            // (a) Double-size "MAYDAY" in Gold (y = 3..16, x = 13..82)
            if (pixel_y >= 6'd3 && pixel_y < 6'd17 && pixel_x >= 7'd13 && pixel_x < 7'd83) begin
                ty            = (pixel_y - 6'd3) >> 1;
                tx            = (pixel_x - 7'd13) >> 1;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = 5'd10;
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (char_idx)
                        4'd0: s1_text_char = "M";
                        4'd1: s1_text_char = "A";
                        4'd2: s1_text_char = "Y";
                        4'd3: s1_text_char = "D";
                        4'd4: s1_text_char = "A";
                        4'd5: s1_text_char = "Y";
                        default: s1_in_text = 1'b0;
                    endcase
                end
            end

            // (b) Five Level Boxes (14x14 at y = 22..35) & Best Stars (y = 38..40)
            if      (pixel_x >= 7'd5  && pixel_x < 7'd19) begin in_any_home_box = 1'b1; home_box_id = 3'd0; box_rx = pixel_x - 7'd5;  end
            else if (pixel_x >= 7'd23 && pixel_x < 7'd37) begin in_any_home_box = 1'b1; home_box_id = 3'd1; box_rx = pixel_x - 7'd23; end
            else if (pixel_x >= 7'd41 && pixel_x < 7'd55) begin in_any_home_box = 1'b1; home_box_id = 3'd2; box_rx = pixel_x - 7'd41; end
            else if (pixel_x >= 7'd59 && pixel_x < 7'd73) begin in_any_home_box = 1'b1; home_box_id = 3'd3; box_rx = pixel_x - 7'd59; end
            else if (pixel_x >= 7'd77 && pixel_x < 7'd91) begin in_any_home_box = 1'b1; home_box_id = 3'd4; box_rx = pixel_x - 7'd77; end

            if (in_any_home_box && (pixel_y >= 6'd22 && pixel_y < 6'd36)) begin
                box_ry          = pixel_y - 6'd22;
                s1_in_menu_rect = 1'b1;
                s1_box_level    = home_box_id + 3'd1;
                if (box_rx == 4'd0 || box_rx == 4'd13 || box_ry == 4'd0 || box_ry == 4'd13 ||
                    ((menu_cursor == home_box_id) &&
                     (box_rx == 4'd1 || box_rx == 4'd12 || box_ry == 4'd1 || box_ry == 4'd12))) begin
                    s1_menu_rect_color = (menu_cursor == home_box_id) ? 5'd10 : 5'd1;
                end else begin
                    s1_in_box_fill     = 1'b1;
                    s1_menu_rect_color = (box_ry >= 4'd10) ? 5'd12 : 5'd15;
                end
                if (box_rx >= 4'd5 && box_rx < 4'd10 && box_ry >= 4'd4 && box_ry < 4'd11) begin
                    s1_in_text    = 1'b1;
                    s1_text_char  = {5'd0, home_box_id + 3'd1};
                    s1_text_col   = box_rx - 4'd5;
                    s1_text_row   = box_ry - 4'd4;
                    s1_text_color = 5'd2;
                end
            end else if (in_any_home_box && (pixel_y >= 6'd38 && pixel_y < 6'd41)) begin
                box_stars = best_stars[2*home_box_id +: 2];
                if (box_rx >= 4'd1 && box_rx <= 4'd3) begin
                    s1_in_menu_rect    = 1'b1;
                    s1_menu_rect_color = (box_stars >= 2'd1) ? 5'd10 : 5'd4;
                end else if (box_rx >= 4'd6 && box_rx <= 4'd8) begin
                    s1_in_menu_rect    = 1'b1;
                    s1_menu_rect_color = (box_stars >= 2'd2) ? 5'd10 : 5'd4;
                end else if (box_rx >= 4'd11 && box_rx <= 4'd13) begin
                    s1_in_menu_rect    = 1'b1;
                    s1_menu_rect_color = (box_stars >= 2'd3) ? 5'd10 : 5'd4;
                end
            end

            // (c) REV4 bottom prompt: [left arrow] [right arrow]  (circle) GO
            //     y = 52..58. Arrows = choose level (BTNL / BTNR),
            //     circle = centre button (BTNC) = start.
            if (pixel_y >= 6'd52 && pixel_y < 6'd59) begin
                hy7 = pixel_y - 6'd52;
                if (pixel_x >= 7'd23 && pixel_x < 7'd32 && arrow_px(hy7[2:0], 4'd8 - (pixel_x - 7'd23))) begin
                    s1_in_menu_rect = 1'b1;  s1_menu_rect_color = 5'd2;            // left arrow
                end else if (pixel_x >= 7'd35 && pixel_x < 7'd44 && arrow_px(hy7[2:0], pixel_x - 7'd35)) begin
                    s1_in_menu_rect = 1'b1;  s1_menu_rect_color = 5'd2;            // right arrow
                end else if (pixel_x >= 7'd51 && pixel_x < 7'd58 && circle_px(hy7[2:0], pixel_x - 7'd51)) begin
                    s1_in_menu_rect = 1'b1;  s1_menu_rect_color = 5'd10;           // gold circle
                end else if (pixel_x >= 7'd61 && pixel_x < 7'd72) begin
                    tx            = pixel_x - 7'd61;
                    char_idx      = div6(tx);
                    char_rem      = tx - (char_idx * 7'd6);
                    s1_text_row   = hy7[2:0];
                    s1_text_color = 5'd2;
                    if (char_rem < 7'd5) begin
                        s1_in_text  = 1'b1;
                        s1_text_col = char_rem[2:0];
                        s1_text_char = (char_idx == 4'd0) ? "G" : "O";
                    end
                end
            end
        end

        // -------------------------------------------------------------
        // 3. S_LEVEL_INTRO Screen ("LEVEL n" at double size + setting name)
        // ----------------------------------------------------------------->
        else if (game_state == S_LEVEL_INTRO) begin
            if (pixel_y >= 6'd14 && pixel_y < 6'd28 && pixel_x >= 7'd7 && pixel_x < 7'd89) begin
                ty            = (pixel_y - 6'd14) >> 1;
                tx            = (pixel_x - 7'd7) >> 1;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = 5'd10;
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (char_idx)
                        4'd0: s1_text_char = "L";
                        4'd1: s1_text_char = "E";
                        4'd2: s1_text_char = "V";
                        4'd3: s1_text_char = "E";
                        4'd4: s1_text_char = "L";
                        4'd6: s1_text_char = {5'd0, level};
                        default: s1_in_text = 1'b0;
                    endcase
                end
            end else if (pixel_y >= 6'd38 && pixel_y < 6'd45) begin
                ty            = pixel_y - 6'd38;
                s1_text_row   = ty[2:0];
                s1_text_color = 5'd2;
                case (level)
                    3'd2, 3'd4: begin // "NIGHT CITY"
                        if (pixel_x >= 7'd19 && pixel_x < 7'd78) begin
                            tx       = pixel_x - 7'd19;
                            char_idx = div6(tx);
                            char_rem = tx - (char_idx * 7'd6);
                            if (char_rem < 7'd5) begin
                                s1_in_text  = 1'b1;
                                s1_text_col = char_rem[2:0];
                                case (char_idx)
                                    4'd0: s1_text_char = "N";
                                    4'd1: s1_text_char = "I";
                                    4'd2: s1_text_char = "G";
                                    4'd3: s1_text_char = "H";
                                    4'd4: s1_text_char = "T";
                                    4'd6: s1_text_char = "C";
                                    4'd7: s1_text_char = "I";
                                    4'd8: s1_text_char = "T";
                                    4'd9: s1_text_char = "Y";
                                    default: s1_in_text = 1'b0;
                                endcase
                            end
                        end
                    end
                    3'd5: begin // "SUNSET"
                        if (pixel_x >= 7'd31 && pixel_x < 7'd66) begin
                            tx       = pixel_x - 7'd31;
                            char_idx = div6(tx);
                            char_rem = tx - (char_idx * 7'd6);
                            if (char_rem < 7'd5) begin
                                s1_in_text  = 1'b1;
                                s1_text_col = char_rem[2:0];
                                case (char_idx)
                                    4'd0: s1_text_char = "S";
                                    4'd1: s1_text_char = "U";
                                    4'd2: s1_text_char = "N";
                                    4'd3: s1_text_char = "S";
                                    4'd4: s1_text_char = "E";
                                    4'd5: s1_text_char = "T";
                                    default: s1_in_text = 1'b0;
                                endcase
                            end
                        end
                    end
                    default: begin // "DAY"
                        if (pixel_x >= 7'd39 && pixel_x < 7'd56) begin
                            tx       = pixel_x - 7'd39;
                            char_idx = div6(tx);
                            char_rem = tx - (char_idx * 7'd6);
                            if (char_rem < 7'd5) begin
                                s1_in_text  = 1'b1;
                                s1_text_col = char_rem[2:0];
                                case (char_idx)
                                    4'd0: s1_text_char = "D";
                                    4'd1: s1_text_char = "A";
                                    4'd2: s1_text_char = "Y";
                                    default: s1_in_text = 1'b0;
                                endcase
                            end
                        end
                    end
                endcase
            end
        end

        // -------------------------------------------------------------
        // 4. S_LEVEL_COMPLETE Screen
        //    Vertical star rows (revealed at ticks 30, 60, 90):
        //      Row 1 (y=6..12):  "ALL CRATES"
        //      Row 2 (y=19..25): "LANDED"
        //      Row 3 (y=32..38): "PERFECT LAND"
        //    Bottom options (y=52..58): "NEXT"/"DONE", "RETRY", "HOME"
        // -------------------------------------------------------------
        else if (game_state == S_LEVEL_COMPLETE) begin
            // Row 1: "ALL CRATES" at x = 18..77, y = 6..12
            if ((state_timer >= T_STAR1) &&
                (pixel_y >= 6'd6 && pixel_y < 6'd13) &&
                (pixel_x >= 7'd18 && pixel_x < 7'd78)) begin
                ty            = pixel_y - 6'd6;
                tx            = pixel_x - 7'd18;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = stars_earned[0] ? 5'd2 : 5'd4;
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (char_idx)
                        4'd0: s1_text_char = "A";
                        4'd1: s1_text_char = "L";
                        4'd2: s1_text_char = "L";
                        4'd4: s1_text_char = "C";
                        4'd5: s1_text_char = "R";
                        4'd6: s1_text_char = "A";
                        4'd7: s1_text_char = "T";
                        4'd8: s1_text_char = "E";
                        4'd9: s1_text_char = "S";
                        default: s1_in_text = 1'b0;
                    endcase
                end
            end
            // Row 2: "LANDED" at x = 18..53, y = 19..25
            else if ((state_timer >= T_STAR2) &&
                     (pixel_y >= 6'd19 && pixel_y < 6'd26) &&
                     (pixel_x >= 7'd18 && pixel_x < 7'd54)) begin
                ty            = pixel_y - 6'd19;
                tx            = pixel_x - 7'd18;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = stars_earned[1] ? 5'd2 : 5'd4;
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (char_idx)
                        4'd0: s1_text_char = "L";
                        4'd1: s1_text_char = "A";
                        4'd2: s1_text_char = "N";
                        4'd3: s1_text_char = "D";
                        4'd4: s1_text_char = "E";
                        4'd5: s1_text_char = "D";
                        default: s1_in_text = 1'b0;
                    endcase
                end
            end
            // Row 3: "PERFECT LAND" at x = 18..89, y = 32..38
            else if ((state_timer >= T_STAR3) &&
                     (pixel_y >= 6'd32 && pixel_y < 6'd39) &&
                     (pixel_x >= 7'd18 && pixel_x < 7'd90)) begin
                ty            = pixel_y - 6'd32;
                tx            = pixel_x - 7'd18;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = stars_earned[2] ? 5'd2 : 5'd4;
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (char_idx)
                        4'd0:  s1_text_char = "P";
                        4'd1:  s1_text_char = "E";
                        4'd2:  s1_text_char = "R";
                        4'd3:  s1_text_char = "F";
                        4'd4:  s1_text_char = "E";
                        4'd5:  s1_text_char = "C";
                        4'd6:  s1_text_char = "T";
                        4'd8:  s1_text_char = "L";
                        4'd9:  s1_text_char = "A";
                        4'd10: s1_text_char = "N";
                        4'd11: s1_text_char = "D";
                        default: s1_in_text = 1'b0;
                    endcase
                end
            end
            // Bottom menu options: NEXT/DONE (x=3..25), RETRY (x=33..61), HOME (x=69..91) at y=52..58
            else if (pixel_y >= 6'd52 && pixel_y < 6'd59) begin
                ty          = pixel_y - 6'd52;
                s1_text_row = ty[2:0];
                if (pixel_x >= 7'd3 && pixel_x < 7'd26) begin
                    tx            = pixel_x - 7'd3;
                    char_idx      = div6(tx);
                    char_rem      = tx - (char_idx * 7'd6);
                    s1_text_color = (menu_cursor == 3'd0) ? 5'd10 : 5'd2;
                    if (char_rem < 7'd5) begin
                        s1_in_text  = 1'b1;
                        s1_text_col = char_rem[2:0];
                        if (level == 3'd5) begin
                            case (char_idx)
                                4'd0: s1_text_char = "D";
                                4'd1: s1_text_char = "O";
                                4'd2: s1_text_char = "N";
                                4'd3: s1_text_char = "E";
                                default: s1_in_text = 1'b0;
                            endcase
                        end else begin
                            case (char_idx)
                                4'd0: s1_text_char = "N";
                                4'd1: s1_text_char = "E";
                                4'd2: s1_text_char = "X";
                                4'd3: s1_text_char = "T";
                                default: s1_in_text = 1'b0;
                            endcase
                        end
                    end
                end else if (pixel_x >= 7'd33 && pixel_x < 7'd62) begin
                    tx            = pixel_x - 7'd33;
                    char_idx      = div6(tx);
                    char_rem      = tx - (char_idx * 7'd6);
                    s1_text_color = (menu_cursor == 3'd1) ? 5'd10 : 5'd2;
                    if (char_rem < 7'd5) begin
                        s1_in_text  = 1'b1;
                        s1_text_col = char_rem[2:0];
                        case (char_idx)
                            4'd0: s1_text_char = "R";
                            4'd1: s1_text_char = "E";
                            4'd2: s1_text_char = "T";
                            4'd3: s1_text_char = "R";
                            4'd4: s1_text_char = "Y";
                            default: s1_in_text = 1'b0;
                        endcase
                    end
                end else if (pixel_x >= 7'd69 && pixel_x < 7'd92) begin
                    tx            = pixel_x - 7'd69;
                    char_idx      = div6(tx);
                    char_rem      = tx - (char_idx * 7'd6);
                    s1_text_color = (menu_cursor == 3'd2) ? 5'd10 : 5'd2;
                    if (char_rem < 7'd5) begin
                        s1_in_text  = 1'b1;
                        s1_text_col = char_rem[2:0];
                        case (char_idx)
                            4'd0: s1_text_char = "H";
                            4'd1: s1_text_char = "O";
                            4'd2: s1_text_char = "M";
                            4'd3: s1_text_char = "E";
                            default: s1_in_text = 1'b0;
                        endcase
                    end
                end
            end
            // Gold underline under selected option at y = 60
            else if (pixel_y == 6'd60) begin
                if ((menu_cursor == 3'd0 && pixel_x >= 7'd3  && pixel_x < 7'd26) ||
                    (menu_cursor == 3'd1 && pixel_x >= 7'd33 && pixel_x < 7'd62) ||
                    (menu_cursor == 3'd2 && pixel_x >= 7'd69 && pixel_x < 7'd92)) begin
                    s1_in_menu_rect    = 1'b1;
                    s1_menu_rect_color = 5'd10;
                end
            end
        end

        // -------------------------------------------------------------
        // 5. S_LEVEL_FAILED Screen ("FAILED" in red, fail_reason, RETRY / HOME)
        // -------------------------------------------------------------
        else if (game_state == S_LEVEL_FAILED) begin
            // (a) Double-size "FAILED" in Red (index 11) at y = 6..19, x = 13..82
            if (pixel_y >= 6'd6 && pixel_y < 6'd20 && pixel_x >= 7'd13 && pixel_x < 7'd83) begin
                ty            = (pixel_y - 6'd6) >> 1;
                tx            = (pixel_x - 7'd13) >> 1;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = 5'd11; // Red
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (char_idx)
                        4'd0: s1_text_char = "F";
                        4'd1: s1_text_char = "A";
                        4'd2: s1_text_char = "I";
                        4'd3: s1_text_char = "L";
                        4'd4: s1_text_char = "E";
                        4'd5: s1_text_char = "D";
                        default: s1_in_text = 1'b0;
                    endcase
                end
            end
            // (b) Reason text at y = 29..35 in White
            else if (pixel_y >= 6'd29 && pixel_y < 6'd36 && pixel_x >= 7'd15 && pixel_x < 7'd81) begin
                ty            = pixel_y - 6'd29;
                tx            = pixel_x - 7'd15;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = 5'd2;
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (fail_reason)
                        FR_TOO_LATE: begin // "TOO LATE"
                            case (char_idx)
                                4'd1: s1_text_char = "T";
                                4'd2: s1_text_char = "O";
                                4'd3: s1_text_char = "O";
                                4'd5: s1_text_char = "L";
                                4'd6: s1_text_char = "A";
                                4'd7: s1_text_char = "T";
                                4'd8: s1_text_char = "E";
                                default: s1_in_text = 1'b0;
                            endcase
                        end
                        FR_LINES_CUT: begin // "LINES CUT"
                            case (char_idx)
                                4'd1: s1_text_char = "L";
                                4'd2: s1_text_char = "I";
                                4'd3: s1_text_char = "N";
                                4'd4: s1_text_char = "E";
                                4'd5: s1_text_char = "S";
                                4'd7: s1_text_char = "C";
                                4'd8: s1_text_char = "U";
                                4'd9: s1_text_char = "T";
                                default: s1_in_text = 1'b0;
                            endcase
                        end
                        FR_TURBULENCE: begin // "TURBULENCE"
                            case (char_idx)
                                4'd0: s1_text_char = "T";
                                4'd1: s1_text_char = "U";
                                4'd2: s1_text_char = "R";
                                4'd3: s1_text_char = "B";
                                4'd4: s1_text_char = "U";
                                4'd5: s1_text_char = "L";
                                4'd6: s1_text_char = "E";
                                4'd7: s1_text_char = "N";
                                4'd8: s1_text_char = "C";
                                4'd9: s1_text_char = "E";
                                default: s1_in_text = 1'b0;
                            endcase
                        end
                        3'd4: begin // REV6 FR_KNOCKED_OUT: "KNOCKED OUT"
                            case (char_idx)
                                4'd0: s1_text_char = "K"; 4'd1: s1_text_char = "N"; 4'd2: s1_text_char = "O";
                                4'd3: s1_text_char = "C"; 4'd4: s1_text_char = "K"; 4'd5: s1_text_char = "E";
                                4'd6: s1_text_char = "D"; 4'd7: s1_text_char = " "; 4'd8: s1_text_char = "O";
                                4'd9: s1_text_char = "U"; 4'd10: s1_text_char = "T";
                                default: s1_in_text = 1'b0;
                            endcase
                        end
                        default: begin // FR_HARD_IMPACT: "HARD IMPACT"
                            case (char_idx)
                                4'd0:  s1_text_char = "H";
                                4'd1:  s1_text_char = "A";
                                4'd2:  s1_text_char = "R";
                                4'd3:  s1_text_char = "D";
                                4'd5:  s1_text_char = "I";
                                4'd6:  s1_text_char = "M";
                                4'd7:  s1_text_char = "P";
                                4'd8:  s1_text_char = "A";
                                4'd9:  s1_text_char = "C";
                                4'd10: s1_text_char = "T";
                                default: s1_in_text = 1'b0;
                            endcase
                        end
                    endcase
                end
            end
            // (c) Bottom options: RETRY (x=15..43) and HOME (x=57..79) at y=50..56
            else if (pixel_y >= 6'd50 && pixel_y < 6'd57) begin
                ty          = pixel_y - 6'd50;
                s1_text_row = ty[2:0];
                if (pixel_x >= 7'd15 && pixel_x < 7'd44) begin
                    tx            = pixel_x - 7'd15;
                    char_idx      = div6(tx);
                    char_rem      = tx - (char_idx * 7'd6);
                    s1_text_color = (menu_cursor == 3'd0) ? 5'd10 : 5'd2;
                    if (char_rem < 7'd5) begin
                        s1_in_text  = 1'b1;
                        s1_text_col = char_rem[2:0];
                        case (char_idx)
                            4'd0: s1_text_char = "R";
                            4'd1: s1_text_char = "E";
                            4'd2: s1_text_char = "T";
                            4'd3: s1_text_char = "R";
                            4'd4: s1_text_char = "Y";
                            default: s1_in_text = 1'b0;
                        endcase
                    end
                end else if (pixel_x >= 7'd57 && pixel_x < 7'd80) begin
                    tx            = pixel_x - 7'd57;
                    char_idx      = div6(tx);
                    char_rem      = tx - (char_idx * 7'd6);
                    s1_text_color = (menu_cursor == 3'd1) ? 5'd10 : 5'd2;
                    if (char_rem < 7'd5) begin
                        s1_in_text  = 1'b1;
                        s1_text_col = char_rem[2:0];
                        case (char_idx)
                            4'd0: s1_text_char = "H";
                            4'd1: s1_text_char = "O";
                            4'd2: s1_text_char = "M";
                            4'd3: s1_text_char = "E";
                            default: s1_in_text = 1'b0;
                        endcase
                    end
                end
            end
            // Underline on selected option at y = 58
            else if (pixel_y == 6'd58) begin
                if ((menu_cursor == 3'd0 && pixel_x >= 7'd15 && pixel_x < 7'd44) ||
                    (menu_cursor == 3'd1 && pixel_x >= 7'd57 && pixel_x < 7'd80)) begin
                    s1_in_menu_rect    = 1'b1;
                    s1_menu_rect_color = 5'd10;
                end
            end
        end

        // -------------------------------------------------------------
        // 6. S_VICTORY Screen ("YOU MADE IT!", big gold star, total_stars/15, "C: HOME")
        // -------------------------------------------------------------
        else if (game_state == S_VICTORY) begin
            // (a) "YOU MADE IT!" in Gold at y = 5..11, x = 13..83
            if (pixel_y >= 6'd5 && pixel_y < 6'd12 && pixel_x >= 7'd13 && pixel_x < 7'd84) begin
                ty            = pixel_y - 6'd5;
                tx            = pixel_x - 7'd13;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = 5'd10;
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (char_idx)
                        4'd0:  s1_text_char = "Y";
                        4'd1:  s1_text_char = "O";
                        4'd2:  s1_text_char = "U";
                        4'd4:  s1_text_char = "M";
                        4'd5:  s1_text_char = "A";
                        4'd6:  s1_text_char = "D";
                        4'd7:  s1_text_char = "E";
                        4'd9:  s1_text_char = "I";
                        4'd10: s1_text_char = "T";
                        4'd11: s1_text_char = "!";
                        default: s1_in_text = 1'b0;
                    endcase
                end
            end
            // (b) "nn/15" total stars at y = 38..44, x = 33..61 in White
            else if (pixel_y >= 6'd38 && pixel_y < 6'd45 && pixel_x >= 7'd33 && pixel_x < 7'd62) begin
                ty            = pixel_y - 6'd38;
                tx            = pixel_x - 7'd33;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = 5'd2;
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (char_idx)
                        4'd0: if (tot_tens != 4'd0) s1_text_char = {4'd0, tot_tens}; else s1_in_text = 1'b0;
                        4'd1: s1_text_char = {4'd0, tot_ones};
                        4'd2: s1_text_char = "/";
                        4'd3: s1_text_char = "1";
                        4'd4: s1_text_char = "5";
                        default: s1_in_text = 1'b0;
                    endcase
                end
            end
            // (c) "C: HOME" at y = 52..58, x = 27..67 in Gold
            else if (pixel_y >= 6'd52 && pixel_y < 6'd59 && pixel_x >= 7'd27 && pixel_x < 7'd68) begin
                ty            = pixel_y - 6'd52;
                tx            = pixel_x - 7'd27;
                char_idx      = div6(tx);
                char_rem      = tx - (char_idx * 7'd6);
                s1_text_row   = ty[2:0];
                s1_text_color = 5'd10;
                if (char_rem < 7'd5) begin
                    s1_in_text  = 1'b1;
                    s1_text_col = char_rem[2:0];
                    case (char_idx)
                        4'd0: s1_text_char = "C";
                        4'd1: s1_text_char = ":";
                        4'd3: s1_text_char = "H";
                        4'd4: s1_text_char = "O";
                        4'd5: s1_text_char = "M";
                        4'd6: s1_text_char = "E";
                        default: s1_in_text = 1'b0;
                    endcase
                end
            end
        end
    end

    // -----------------------------------------------------------------
    // Pipeline Register Stage 1 -> Stage 2
    // -----------------------------------------------------------------
    reg        s2_is_gameplay;
    reg        s2_is_menu;
    reg        s2_full_flash;
    reg        s2_in_far_cloud;
    reg        s2_in_near_cloud;
    reg        s2_in_ground;
    reg [4:0]  s2_ground_color;
    reg        s2_in_crate;
    reg [2:0]  s2_crate_col;
    reg [3:0]  s2_crate_row;
    reg        s2_in_obs;
    reg [1:0]  s2_obs_type;
    reg        s2_obs_flip;
    reg [4:0]  s2_obs_col;
    reg [2:0]  s2_obs_row;
    reg        s2_in_hero;
    reg [3:0]  s2_hero_col;
    reg [4:0]  s2_hero_row;
    reg        s2_in_fx;
    reg [4:0]  s2_fx_color;
    reg        s2_in_edge_band;
    reg        s2_in_flare_lane;
    reg [4:0]  s2_flare_color;
    reg        s2_in_icon;
    reg [2:0]  s2_icon_id;
    reg [3:0]  s2_icon_col;
    reg [3:0]  s2_icon_row;
    reg        s2_star_earned;
    reg        s2_in_menu_rect;
    reg [4:0]  s2_menu_rect_color;
    reg [2:0]  s2_box_level;
    reg        s2_in_box_fill;
    reg        s2_in_text;
    reg [7:0]  s2_text_char;
    reg [2:0]  s2_text_col;
    reg [2:0]  s2_text_row;
    reg [4:0]  s2_text_color;

    always @(posedge clk) begin
        s2_is_gameplay     <= is_gameplay;
        s2_is_menu         <= is_menu;
        s2_full_flash      <= s1_full_flash;
        s2_in_far_cloud    <= s1_in_far_cloud;
        s2_in_near_cloud   <= s1_in_near_cloud;
        s2_in_ground       <= s1_in_ground;
        s2_ground_color    <= s1_ground_color;
        s2_in_crate        <= s1_in_crate;
        s2_crate_col       <= s1_crate_col;
        s2_crate_row       <= s1_crate_row;
        s2_in_obs          <= s1_in_obs;
        s2_obs_type        <= s1_obs_type;
        s2_obs_flip        <= s1_obs_flip;
        s2_obs_col         <= s1_obs_col;
        s2_obs_row         <= s1_obs_row;
        s2_in_hero         <= s1_in_hero;
        s2_hero_col        <= s1_hero_col;
        s2_hero_row        <= s1_hero_row;
        s2_in_fx           <= s1_in_fx;
        s2_fx_color        <= s1_fx_color;
        s2_in_edge_band    <= s1_in_edge_band;
        s2_in_flare_lane   <= in_flare_lane;
        s2_flare_color     <= s1_flare_color;
        s2_in_icon         <= s1_in_icon;
        s2_icon_id         <= s1_icon_id;
        s2_icon_col        <= s1_icon_col;
        s2_icon_row        <= s1_icon_row;
        s2_star_earned     <= s1_star_earned;
        s2_in_menu_rect    <= s1_in_menu_rect;
        s2_menu_rect_color <= s1_menu_rect_color;
        s2_box_level       <= s1_box_level;
        s2_in_box_fill     <= s1_in_box_fill;
        s2_in_text         <= s1_in_text;
        s2_text_char       <= s1_text_char;
        s2_text_col        <= s1_text_col;
        s2_text_row        <= s1_text_row;
        s2_text_color      <= s1_text_color;
    end

    // -----------------------------------------------------------------
    // STAGE 2: Shared Sprite & Font ROM Lookups, 10-Layer Compositor & Palette
    // -----------------------------------------------------------------
    wire [4:0] rom_hero_color;
    wire [4:0] rom_obs_color;
    wire [4:0] rom_crate_color;
    wire [4:0] rom_icon_color;

    sprite_rom u_sprite_rom (
        .hero_pose     (hero_pose_sel),
        .hero_mirror   (hero_mirror_sel),
        .hero_col      (s2_hero_col),
        .hero_row      (s2_hero_row),
        .hero_color    (rom_hero_color),

        .obs_sel_type  (s2_obs_type),
        .obs_sel_frame (obs_anim_frame),
        .obs_sel_flip  (s2_obs_flip),
        .obs_col       (s2_obs_col),
        .obs_row       (s2_obs_row),
        .obs_color     (rom_obs_color),

        .crate_col     (s2_crate_col),
        .crate_row     (s2_crate_row),
        .crate_color   (rom_crate_color),

        .icon_id       (s2_icon_id),
        .icon_col      (s2_icon_col),
        .icon_row      (s2_icon_row),
        .icon_color    (rom_icon_color)
    );

    wire [4:0] font_row_bits;
    font_rom u_font_rom (
        .char_code (s2_text_char),
        .row       (s2_text_row),
        .pixels    (font_row_bits)
    );
    wire font_pixel_on = s2_in_text && font_row_bits[3'd4 - s2_text_col];

    // 10-Layer Priority Compositor (Front-to-Back, ignoring transparent index 0):
    //   10. Full-screen flash (white index 2)
    //    9. HUD (crate counter, lock, warning, landing arrow, flare lane, edge bands)
    //    8. Effects (pickup sparkle, magnet aura, curly wind lines, dust/debris)
    //    7. Hero
    //    6. Obstacles
    //    5. Crates
    //    4. Ground and landing spot
    //    3. Near clouds
    //    2. Far clouds
    //    1. Sky gradient
    reg [4:0] chosen_idx;
    reg       use_sky_gradient;

    always @* begin
        chosen_idx       = 5'd0;
        use_sky_gradient = 1'b0;

        if (!s2_is_gameplay) begin
            // Menu screens: Text > 9x9 Star Icon > Box/Underline > Navy background (index 7)
            if (font_pixel_on)
                chosen_idx = s2_text_color;
            else if (s2_in_icon && (rom_icon_color != 5'd0))
                chosen_idx = s2_star_earned ? rom_icon_color : 5'd4;
            else if (s2_in_menu_rect)
                chosen_idx = s2_menu_rect_color;
            else
                chosen_idx = 5'd7;
        end else begin
            // Gameplay states: strictly enforce ICD 10-layer priority order
            if (s2_full_flash)
                chosen_idx = 5'd2;                        // Layer 10: Full-screen white flash
            else if (font_pixel_on)
                chosen_idx = s2_text_color;               // Layer 9: HUD crate counter
            else if (s2_in_icon && (rom_icon_color != 5'd0))
                chosen_idx = rom_icon_color;              // Layer 9: HUD lock / warning / arrow
            else if (s2_in_flare_lane)
                chosen_idx = s2_flare_color;              // Layer 9: Flare lane & black marker
            else if (s2_in_edge_band)
                chosen_idx = 5'd11;                       // Layer 9: Red turbulence edge band
            else if (s2_in_fx && (s2_fx_color != 5'd0))
                chosen_idx = s2_fx_color;                 // Layer 8: Effects (sparkle/aura/wind/dust)
            else if (s2_in_hero && (rom_hero_color != 5'd0))
                chosen_idx = rom_hero_color;              // Layer 7: Hero
            else if (s2_in_obs && (rom_obs_color != 5'd0))
                chosen_idx = rom_obs_color;               // Layer 6: Obstacles
            else if (s2_in_crate && (rom_crate_color != 5'd0))
                // REV3: medic crate glow - its black border pulses bright green
                chosen_idx = ((rom_crate_color == 5'd1) && anim_tick_cnt[3]) ? 5'd19 : rom_crate_color; // Layer 5
            else if (s2_in_ground)
                chosen_idx = s2_ground_color;             // Layer 4: Ground & landing spot
            else if (s2_in_near_cloud)
                chosen_idx = 5'd3;                        // Layer 3: Near clouds
            else if (s2_in_far_cloud)
                chosen_idx = 5'd3;                        // Layer 2: Far clouds
            else
                use_sky_gradient = 1'b1;                  // Layer 1: Sky gradient
        end
    end

    wire [2:0] pal_level   = s2_in_box_fill ? s2_box_level : level;
    wire       pal_is_menu = s2_is_menu && !s2_in_box_fill;

    wire [15:0] pal_rgb565;
    palette u_palette (
        .color_idx (chosen_idx),
        .level     (pal_level),
        .is_menu   (pal_is_menu),
        .rgb565    (pal_rgb565)
    );

    // Output Register Stage
    always @(posedge clk) begin
        if (rst) begin
            oled_data_game <= 16'h194D;
        end else if (use_sky_gradient) begin
            oled_data_game <= sky_rgb_reg;
        end else begin
            oled_data_game <= pal_rgb565;
        end
    end

endmodule
