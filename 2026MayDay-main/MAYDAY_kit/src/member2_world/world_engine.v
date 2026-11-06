`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.10.2026 17:46:56
// Design Name: 
// Module Name: world_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// =====================================================================
// world_engine.v  --  MEMBER 2 (World and collision)
// STATUS: FINAL PRODUCTION BUILD (CHECKPOINTS 1, 2 & 3 FULLY INTEGRATED)
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
    input  wire               gust_warn,        // REV3: from Member 1 (level 1 takes turns with wind)
    input  wire               gust_active,      // REV3
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
    output reg  [8:0]         magnet_ticks_left,
    // REV3 new outputs
    output reg                gust_request,     // level 1: 1-cycle "start a gust now" to Member 1
    output reg                pwarn_active,     // plane warning on a side edge (2 s)
    output reg                pwarn_right,      // 0 = plane comes from the left, 1 = right
    output reg  signed [7:0]  pwarn_y,          // screen row the plane will fly at
    output wire               plane_busy        // REV4: plane warned or flying -> Member 1 holds the wind
);
    `include "game_params.vh"

    // -----------------------------------------------------------------
    // 1. LFSR Engine (16-bit Maximal-length, taps 16, 14, 13, 11)
    // -----------------------------------------------------------------
    reg [15:0] lfsr_reg;
    // FIX #15: the bit indices were missing, so feedback was always 0 and the
    // LFSR decayed to all-zeros (every "random" value became 0).
    wire lfsr_feedback = lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10];

    always @(posedge clk) begin
        if (rst) begin
            lfsr_reg <= 16'h5A5A; 
        end else if (level_start) begin
            lfsr_reg <= ((seed ^ LFSR_CONST_M2) == 16'h0000) ? 16'h0001 : (seed ^ LFSR_CONST_M2);
        end else if (game_tick) begin
            lfsr_reg <= {lfsr_reg[14:0], lfsr_feedback};
        end
    end

    // FIX #15: value the LFSR is loaded with on level_start. target_x is picked
    // from THIS (the new seed), not from lfsr_reg, which still holds the old,
    // all-zero value on the level_start cycle -> spot was always far left.
    wire [15:0] seeded_val = ((seed ^ LFSR_CONST_M2) == 16'h0000) ? 16'h0001 : (seed ^ LFSR_CONST_M2);

    // -----------------------------------------------------------------
    // 2. Memory Storage Arrays (Obstacles & Crates)
    // -----------------------------------------------------------------
    reg signed [15:0] slot_x [0:5];
    reg signed [15:0] slot_y [0:5];
    reg signed [15:0] slot_vx [0:5];
    reg signed [15:0] slot_vy_ind [0:5]; 
    reg        [1:0]  slot_type [0:5];
    reg               slot_active [0:5];
    reg               slot_flip [0:5];
    reg [5:0] bird_wobble_phase [0:5];
    reg       slot_straight [0:5];
    reg       plane_flying;          // REV4: any active plane (registered copy for plane_busy)
    assign plane_busy = pwarn_active | plane_flying;   // REV3: freefall birds fly straight up (no sideways drift)
    reg [7:0] pwarn_timer;            // REV3: plane warning countdown
    reg [2:0] pwarn_slot;             // REV3: slot reserved for the warned plane
    reg [7:0] l1_gap;                 // REV3: level 1 pause between single items
    reg [2:0] l1_done;                // REV3: level 1 round: [0] bird [1] crate [2] gust shown

    reg signed [15:0] cr_x [0:3];
    reg signed [15:0] cr_y [0:3];
    reg               cr_active [0:3];

    reg [2:0]  cfg_max_obs;
    reg [15:0] cfg_spawn_interval;
    reg [7:0]  cfg_plane_share;
    reg [15:0] cfg_plane_gap;      // REV3: ticks between planes (0 = no planes)
    reg [15:0] plane_timer;
    reg [15:0] obstacle_spawn_timer;
    reg [15:0] crate_spawn_timer;
    reg [15:0] cfg_crate_interval;   // FIX #3: ticks between crates for this level
    reg [2:0]  crates_spawned;       // FIX #3: stop at crates_level_total

    reg [7:0]  warning_timer;
    reg [2:0]  warning_target_slot;
    reg        warning_pending;

    // Magnet Countdown Engine Register Array Elements
    reg [8:0]  magnet_timer;
    reg        magnet_active_reg;

    function signed [7:0] get_sine_wobble;
        input [3:0] index;
        begin
            case (index)
                4'd0:  get_sine_wobble = 8'sd0;  4'd1:  get_sine_wobble = 8'sd1;
                4'd2:  get_sine_wobble = 8'sd2;  4'd3:  get_sine_wobble = 8'sd3;
                4'd4:  get_sine_wobble = 8'sd2;  4'd5:  get_sine_wobble = 8'sd1;
                4'd6:  get_sine_wobble = 8'sd0;  4'd7:  get_sine_wobble = -8'sd1;
                4'd8:  get_sine_wobble = -8'sd2; 4'd9:  get_sine_wobble = -8'sd3;
                4'd10: get_sine_wobble = -8'sd2; 4'd11: get_sine_wobble = -8'sd1;
                default: get_sine_wobble = 8'sd0;
            endcase
        end
    endfunction

    // -----------------------------------------------------------------
    // 3. Bus Flattening Layout Control (Combinational)
    // -----------------------------------------------------------------
    integer s;
    always @(*) begin
        // Link internal magnet registers straight onto output system indicators
        magnet_active     = magnet_active_reg;
        magnet_ticks_left = magnet_timer;

        for (s = 0; s < 6; s = s + 1) begin
            obs_x[(s*8)+:8]      = slot_x[s][15:8]; 
            obs_y[(s*8)+:8]      = slot_y[s][15:8];
            obs_type[(s*2)+:2]   = slot_type[s];
            obs_active[s]        = slot_active[s];
            obs_flip[s]          = slot_flip[s];
        end

        for (s = 0; s < 4; s = s + 1) begin
            crate_x[(s*8)+:8]    = cr_x[s][15:8];
            crate_y[(s*8)+:8]    = cr_y[s][15:8];
            crate_active[s]      = cr_active[s];
        end
    end

    // -----------------------------------------------------------------
    // 4. Collision Detection Matrix (Dual-Hitbox Box Overlap)
    // -----------------------------------------------------------------
    reg        slot_hit [0:5];
    reg        crate_hit [0:3];
    reg signed [7:0] hero_hb_left, hero_hb_right, hero_hb_top, hero_hb_bottom;
    reg signed [7:0] body_hb_left, body_hb_right, body_hb_top, body_hb_bottom;
    
    always @(*) begin
        if (canopy_mode == CM_FREEFALL) begin
            hero_hb_left   = hero_x + HB_FF_X;
            hero_hb_right  = hero_x + HB_FF_X + HB_FF_W - 1;
            hero_hb_top    = hero_y + HB_FF_Y;
            hero_hb_bottom = hero_y + HB_FF_Y + HB_FF_H - 1;
            body_hb_left   = hero_hb_left;   body_hb_right  = hero_hb_right;
            body_hb_top    = hero_hb_top;    body_hb_bottom = hero_hb_bottom;
        end else begin
            hero_hb_left   = hero_x + HB_CANOPY_X;
            hero_hb_right  = hero_x + HB_CANOPY_X + HB_CANOPY_W - 1;
            hero_hb_top    = hero_y + HB_CANOPY_Y;
            hero_hb_bottom = hero_y + HB_CANOPY_Y + HB_CANOPY_H - 1;
            body_hb_left   = hero_x + HB_BODY_X;
            body_hb_right  = hero_x + HB_BODY_X + HB_BODY_W - 1;
            body_hb_top    = hero_y + HB_BODY_Y;
            body_hb_bottom = hero_y + HB_BODY_Y + HB_BODY_H - 1;
        end
    end

    integer c;
    reg signed [7:0] obs_hb_left, obs_hb_right, obs_hb_top, obs_hb_bottom;
    always @(*) begin
        for (c = 0; c < 6; c = c + 1) begin
            slot_hit[c] = 1'b0;
            if (slot_active[c] && (warning_pending == 0 || warning_target_slot != c[2:0])) begin
                case (slot_type[c])
                    OBS_BIRD: begin
                        obs_hb_left   = slot_x[c][15:8] + HB_BIRD_X;
                        obs_hb_right  = slot_x[c][15:8] + HB_BIRD_X + HB_BIRD_W - 1;
                        obs_hb_top    = slot_y[c][15:8] + HB_BIRD_Y;
                        obs_hb_bottom = slot_y[c][15:8] + HB_BIRD_Y + HB_BIRD_H - 1;
                    end
                    OBS_PLANE: begin
                        obs_hb_left   = slot_x[c][15:8] + HB_PLANE_X;
                        obs_hb_right  = slot_x[c][15:8] + HB_PLANE_X + HB_PLANE_W - 1;
                        obs_hb_top    = slot_y[c][15:8] + HB_PLANE_Y;
                        obs_hb_bottom = slot_y[c][15:8] + HB_PLANE_Y + HB_PLANE_H - 1;
                    end
                    OBS_DEBRIS: begin
                        obs_hb_left   = slot_x[c][15:8] + HB_DEBRIS_X;
                        obs_hb_right  = slot_x[c][15:8] + HB_DEBRIS_X + HB_DEBRIS_W - 1;
                        obs_hb_top    = slot_y[c][15:8] + HB_DEBRIS_Y;
                        obs_hb_bottom = slot_y[c][15:8] + HB_DEBRIS_Y + HB_DEBRIS_H - 1;
                    end
                    default: begin
                        obs_hb_left   = 8'sd0; obs_hb_right  = 8'sd0;
                        obs_hb_top    = 8'sd0; obs_hb_bottom = 8'sd0;
                    end
                endcase

                if (canopy_mode == CM_FREEFALL) begin
                    if (!(obs_hb_left > hero_hb_right || obs_hb_right < hero_hb_left ||
                          obs_hb_top > hero_hb_bottom || obs_hb_bottom < hero_hb_top)) begin
                        slot_hit[c] = 1'b1;
                    end
                end else begin
                    if (!(obs_hb_left > hero_hb_right || obs_hb_right < hero_hb_left ||
                          obs_hb_top > hero_hb_bottom || obs_hb_bottom < hero_hb_top) ||
                        !(obs_hb_left > body_hb_right || obs_hb_right < body_hb_left ||
                          obs_hb_top > body_hb_bottom || obs_hb_bottom < body_hb_top)) begin
                        slot_hit[c] = 1'b1;
                    end
                end
            end
        end
    end

    integer cr_idx;
    reg signed [7:0] crate_hb_left, crate_hb_right, crate_hb_top, crate_hb_bottom;
    always @(*) begin
        for (cr_idx = 0; cr_idx < 4; cr_idx = cr_idx + 1) begin
            crate_hit[cr_idx] = 1'b0;
            if (cr_active[cr_idx]) begin
                crate_hb_left   = cr_x[cr_idx][15:8];
                crate_hb_right  = cr_x[cr_idx][15:8] + CRATE_W - 1;
                crate_hb_top    = cr_y[cr_idx][15:8];
                crate_hb_bottom = cr_y[cr_idx][15:8] + CRATE_H - 1;

                if (canopy_mode == CM_FREEFALL) begin
                    if (!(crate_hb_left > hero_hb_right || crate_hb_right < hero_hb_left ||
                          crate_hb_top > hero_hb_bottom || crate_hb_bottom < hero_hb_top)) begin
                        crate_hit[cr_idx] = 1'b1;
                    end
                end else begin
                    if (!(crate_hb_left > hero_hb_right || crate_hb_right < hero_hb_left ||
                          crate_hb_top > hero_hb_bottom || crate_hb_bottom < hero_hb_top) ||
                       !(crate_hb_left > body_hb_right || crate_hb_right < body_hb_left ||
                         crate_hb_top > body_hb_bottom || crate_hb_bottom < body_hb_top)) begin
                            crate_hit[cr_idx] = 1'b1;
                    end
                 end
              end
           end
        end 
        // -----------------------------------------------------------------
        // 5. Sequential Logic Update Loop (All Features Complete)
        // -----------------------------------------------------------------
        integer i;
        reg [2:0] hit_count;
        reg [2:0] first_hit_idx;
        reg [2:0] active_obs_count;
        reg       found_empty_slot;
        reg [2:0] empty_slot_idx;
        reg       found_empty_crate;
        reg [1:0] empty_crate_idx;
        reg       window_bird_present;
        reg signed [15:0] rand_offset_x;
        // REV3 spawner temporaries
        reg plane_on, any_crate, world_clear, band_bot_used, band_bot_left, band_top_used, band_top_left;
        reg bot_ok, spawning, in_ff, spawn_crate;
        reg dbr_used, dbr_left, mb_left, mb_right, debris_ok;   // REV3 cross-direction safe side
        reg calm_zone;   // REV8
        reg [7:0] rand_any_x, rand_left_x, rand_rite_x, bot_x, top_x;
        reg [2:0] l1_avail;  reg [1:0] l1_pick;  reg crate_alt_ok;
        initial spawn_crate = 1'b0;
        // Manhattan proximity local calculation registers
        reg signed [7:0] target_center_x, crate_center_x;
        reg signed [7:0] target_center_y, crate_center_y;
        reg signed [7:0] dx, dy;
        reg [7:0] abs_dx, abs_dy;
        reg [8:0] manhattan_dist;
        always @(posedge clk) begin
           if (rst || level_start) begin
              strike               <= 1'b0;
              strike_side          <= 1'b0;
              strike_lines         <= 2'd0;
              crate_collected      <= 1'b0;
              target_x             <= 8'd40;
              crates_level_total   <= 3'd3;
              obstacle_spawn_timer <= 16'd0;
              crate_spawn_timer    <= 16'd0;
              crates_spawned       <= 3'd0;
              warning_timer        <= 8'd0;
              warning_pending      <= 1'b0;
              warn_active          <= 1'b0;
              magnet_timer         <= 9'd0;
              magnet_active_reg    <= 1'b0;
              gust_request         <= 1'b0;
              pwarn_active         <= 1'b0;
              pwarn_right          <= 1'b0;
              pwarn_y              <= 8'sd40;
              pwarn_timer          <= 8'd0;
              plane_flying         <= 1'b0;
              plane_timer          <= 16'd0;
              pwarn_slot           <= 3'd0;
              l1_gap               <= 8'd0;
              l1_done              <= 3'd0;
              for (i = 0; i < 6; i = i + 1) begin
                 slot_x[i]            <= 16'sd0;
                 slot_y[i]            <= 16'sd0;
                 slot_vx[i]           <= 16'sd0;
                 slot_vy_ind[i]       <= 16'sd0;
                 slot_type[i]         <= OBS_EMPTY;
                 slot_active[i]       <= 1'b0;
                 slot_flip[i]         <= 1'b0;
                 bird_wobble_phase[i] <= 6'd0;
                 slot_straight[i]     <= 1'b0;
              end 
              for (i = 0; i < 4; i = i + 1) begin
                 cr_x[i]              <= 16'sd0;
                 cr_y[i]              <= 16'sd0;
                 cr_active[i]         <= 1'b0;
              end
              if (level_start) begin
                 target_x <= TARGET_X_MIN + ((seeded_val[7:0] ^ seeded_val[15:8]) % (TARGET_X_MAX - TARGET_X_MIN + 1)); // FIX #15 (mix both seed bytes)
                 // REV3 difficulty table (easier; level 5 = old level 3 + planes)
                 //        crates  max-on-screen  spawn-gap  plane-share  crate-gap
                 case (level)
                 3'd1: begin   // tutorial: one thing at a time (see L1 sequencer)
                    crates_level_total <= 3'd3; cfg_max_obs <= 3'd1;
                    cfg_spawn_interval <= 16'd0;   cfg_plane_share <= 8'd0;  cfg_crate_interval <= 16'd0;   cfg_plane_gap <= 16'd0;
                 end
                 3'd2: begin
                    crates_level_total <= 3'd3; cfg_max_obs <= 3'd2;
                    cfg_spawn_interval <= 16'd120; cfg_plane_share <= 8'd0;  cfg_crate_interval <= 16'd450; cfg_plane_gap <= 16'd0;
                 end
                 3'd3: begin   // + debris
                    crates_level_total <= 3'd4; cfg_max_obs <= 3'd2;
                    cfg_spawn_interval <= 16'd108; cfg_plane_share <= 8'd0;  cfg_crate_interval <= 16'd380; cfg_plane_gap <= 16'd0;
                 end
                 3'd4: begin   // + planes (10%)
                    crates_level_total <= 3'd4; cfg_max_obs <= 3'd3;
                    cfg_spawn_interval <= 16'd108; cfg_plane_share <= 8'd26; cfg_crate_interval <= 16'd380; cfg_plane_gap <= 16'd720;  // plane every ~12 s
                 end
                 default: begin // level 5: everything, still beatable (planes 15%)
                    crates_level_total <= 3'd5; cfg_max_obs <= 3'd3;
                    cfg_spawn_interval <= 16'd96;  cfg_plane_share <= 8'd38; cfg_crate_interval <= 16'd300; cfg_plane_gap <= 16'd540;  // plane every ~9 s
                 end
                 endcase 
              end
           end else begin 
              strike          <= 1'b0;
              crate_collected <= 1'b0;
              // Trigger structural countdown checking sequence for perfect deployments
              if (game_state == S_CANOPY && deploy_grade == DG_PERFECT && !magnet_active_reg && (magnet_timer == 0) && (altitude > (ALT_FINAL << 8))) begin
                 magnet_active_reg <= 1'b1;
                 magnet_timer      <= 9'd300; // Initialize 5 second lock
              end
              if (game_tick) begin
                 // Handle active magnet expiration timing
                 if (magnet_active_reg) begin
                    if (magnet_timer == 9'd1) begin
                       magnet_active_reg <= 1'b0;
                       magnet_timer      <= 9'd0;
                    end else begin
                       magnet_timer <= magnet_timer - 1;
                    end
                 end 
                 for (i = 0; i < 4; i = i + 1) begin
                    if (cr_active[i] && crate_hit[i]) begin
                       crate_collected <= 1'b1;
                       cr_active[i]    <= 1'b0;
                    end
                 end
                 hit_count     = 3'd0;
                 first_hit_idx = 3'd7;
                 for (i = 0; i < 6; i = i + 1) begin
                    if (slot_active[i] && slot_hit[i] && (!warning_pending || warning_target_slot != i[2:0])) begin
                       hit_count = hit_count + 1;
                       if (first_hit_idx == 3'd7) first_hit_idx = i[2:0];
                    end
                 end
                if (hit_count > 0) begin
                   strike <= 1'b1;
                   // REV6 FIX: signed compare (slot_x[..][15:8] alone is UNSIGNED) and the
                   // real centre of each obstacle (bird 8 px -> +4, plane 24 -> +12, debris 6 -> +3)
                   strike_side <= (($signed(slot_x[first_hit_idx][15:8]) +
                                    ((slot_type[first_hit_idx] == OBS_PLANE)  ? 10'sd12 :
                                     (slot_type[first_hit_idx] == OBS_DEBRIS) ? 10'sd3  : 10'sd4))
                                   < ($signed(hero_x) + 10'sd8)) ? 1'b0 : 1'b1;
                   if (hit_count == 3'd1) begin
                      strike_lines <= (slot_type[first_hit_idx] == OBS_PLANE) ? 2'd2 : 2'd1;
                   end else begin
                      strike_lines <= 2'd2;
                   end
                end
                if (warning_pending) begin
                   if (warning_timer == 8'd1) begin
                      warning_pending                  <= 1'b0;
                      warn_active                      <= 1'b0;
                      slot_active[warning_target_slot] <= 1'b1;
                      obstacle_spawn_timer             <= 16'd0;
                   end else begin
                       warning_timer <= warning_timer - 1;
                   end
                end
                gust_request <= 1'b0;
                calm_zone = (game_state == S_FINAL_APPROACH) && (altitude[23:8] < CALM_ALT);   // REV8
                if (calm_zone) begin warn_active <= 1'b0; warning_pending <= 1'b0; end
                // =========================================================
                // REV3 SPAWNER. Who is on screen, and which "bands" are taken.
                // A band = the 24 px strip where new objects enter: bottom
                // (birds) or top (debris). Objects in the same band reach the
                // hero at about the same time, so the fairness rules use it.
                // =========================================================
                active_obs_count = 3'd0;  plane_on = 1'b0;  any_crate = 1'b0;
                band_bot_used = 1'b0; band_bot_left = 1'b0; band_top_used = 1'b0; band_top_left = 1'b0;
                dbr_used = 1'b0; dbr_left = 1'b0; mb_left = 1'b0; mb_right = 1'b0;
                for (i = 0; i < 6; i = i + 1) begin
                   if (slot_active[i]) begin
                      active_obs_count = active_obs_count + 1;
                      if (slot_type[i] == OBS_PLANE) plane_on = 1'b1;
                      if ($signed(slot_y[i][15:8]) > (64 - BAND_GAP)) begin
                         band_bot_used = 1'b1;  band_bot_left = ($signed(slot_x[i][15:8]) < 44);
                      end
                      if ($signed(slot_y[i][15:8]) < (BAND_GAP - 6)) begin
                         band_top_used = 1'b1;  band_top_left = ($signed(slot_x[i][15:8]) < 44);
                      end
                      // debris still above / beside the hero (falls past him slowly)
                      if (slot_type[i] == OBS_DEBRIS && $signed(slot_y[i][15:8]) < 40) begin
                         dbr_used = 1'b1;  dbr_left = ($signed(slot_x[i][15:8]) < 44);
                      end
                      // birds still on their way up to the hero
                      if (slot_type[i] == OBS_BIRD && $signed(slot_y[i][15:8]) >= 20) begin
                         if ($signed(slot_x[i][15:8]) < 44) mb_left = 1'b1; else mb_right = 1'b1;
                      end
                   end
                end
                for (i = 0; i < 4; i = i + 1) if (cr_active[i]) any_crate = 1'b1;
                plane_flying <= plane_on;
                crate_alt_ok = (altitude[23:8] >= CRATE_LAST_ALT);   // REV4
                world_clear = (active_obs_count == 3'd0) && !any_crate && !warning_pending &&
                              !pwarn_active && !gust_warn && !gust_active;

                found_empty_slot = 1'b0;
                empty_slot_idx   = 3'd0;
                for (i = 0; i < 6; i = i + 1) begin
                   if (!slot_active[i] && (!warning_pending || warning_target_slot != i[2:0]) &&
                       (!pwarn_active || pwarn_slot != i[2:0]) && !found_empty_slot) begin
                      found_empty_slot = 1'b1;
                      empty_slot_idx   = i[2:0];
                   end
                end
                found_empty_crate = 1'b0;
                empty_crate_idx   = 2'd0;
                for (i = 0; i < 4; i = i + 1) begin
                   if (!cr_active[i] && !found_empty_crate) begin
                      found_empty_crate = 1'b1;
                      empty_crate_idx   = i[1:0];
                   end
                end

                // Random x anywhere, or forced onto one half ("safe side" rule, levels 3-5).
                rand_any_x  = 8'd10 + (lfsr_reg[7:0] % 70);           // 10..79
                rand_left_x = 8'd10 + (lfsr_reg[7:0] % 28);           // 10..37
                rand_rite_x = 8'd50 + (lfsr_reg[7:0] % 28);           // 50..77
                // Safe-side rule (levels 3-5), across BOTH directions: a new bird joins the
                // side of any debris still near the hero; new debris joins the side of birds
                // coming up (and waits if birds are coming up on both sides).
                bot_x = (level >= 3'd3 && dbr_used)      ? (dbr_left      ? rand_left_x : rand_rite_x) :
                        (level >= 3'd3 && band_bot_used) ? (band_bot_left ? rand_left_x : rand_rite_x) : rand_any_x;
                top_x = (mb_left && !mb_right) ? rand_left_x :
                        (mb_right && !mb_left) ? rand_rite_x :
                        band_top_used ? (band_top_left ? rand_left_x : rand_rite_x) : rand_any_x;
                debris_ok = !(mb_left && mb_right);
                // Levels 1-2: never two birds in the same band (only one near the hero at a time).
                bot_ok = (level >= 3'd3) || !band_bot_used;

                // ---- plane warning countdown: spawn the plane when it ends ----
                if (pwarn_active) begin
                   if (pwarn_timer <= 8'd1) begin
                      pwarn_active                <= 1'b0;
                      slot_active[pwarn_slot]     <= 1'b1;
                      slot_type[pwarn_slot]       <= OBS_PLANE;
                      slot_vy_ind[pwarn_slot]     <= 16'sd0;
                      slot_straight[pwarn_slot]   <= 1'b0;
                      slot_y[pwarn_slot]          <= {pwarn_y, 8'd0};
                      if (!pwarn_right) begin
                         slot_x[pwarn_slot] <= -16'sd24 <<< 8;  slot_vx[pwarn_slot] <= PLANE_VX;  slot_flip[pwarn_slot] <= 1'b0;
                      end else begin
                         slot_x[pwarn_slot] <= 16'sd96 <<< 8;   slot_vx[pwarn_slot] <= -PLANE_VX; slot_flip[pwarn_slot] <= 1'b1;
                      end
                      obstacle_spawn_timer <= 16'd0;
                   end else
                      pwarn_timer <= pwarn_timer - 8'd1;
                end

                spawning = (game_state >= S_FREEFALL_LOCKED && game_state <= S_FINAL_APPROACH) && (scroll_vy > 0) &&
                           (altitude[23:8] >= OBS_LAST_ALT);   // REV8: nothing new below 120 m
                in_ff    = (game_state == S_FREEFALL_LOCKED || game_state == S_FREEFALL_WINDOW);

                if (spawning && in_ff) begin
                   // ---- FREEFALL: birds only, 1 s warning, fly STRAIGHT up.
                   //      Levels 1-2: one at a time. Levels 3-5: up to 2.
                   obstacle_spawn_timer <= obstacle_spawn_timer + 1;
                   if ((obstacle_spawn_timer >= 16'd60) && found_empty_slot && !warning_pending && bot_ok &&
                       (active_obs_count < ((level >= 3'd3) ? 3'd2 : 3'd1))) begin
                      warning_pending                   <= 1'b1;
                      warning_timer                     <= 8'd60;
                      warning_target_slot               <= empty_slot_idx;
                      warn_active                       <= 1'b1;
                      warn_edge                         <= 1'b0;
                      warn_x                            <= bot_x;
                      slot_type[empty_slot_idx]         <= OBS_BIRD;
                      slot_x[empty_slot_idx]            <= {bot_x, 8'd0};
                      slot_y[empty_slot_idx]            <= 16'sd64 <<< 8;
                      slot_vx[empty_slot_idx]           <= 16'sd0;
                      slot_vy_ind[empty_slot_idx]       <= 16'sd0;
                      slot_flip[empty_slot_idx]         <= lfsr_reg[8];
                      slot_straight[empty_slot_idx]     <= 1'b1;   // REV3: straight up
                      bird_wobble_phase[empty_slot_idx] <= 6'd0;
                      obstacle_spawn_timer              <= 16'd0;
                   end
                end else if (spawning && level == 3'd1) begin
                   // ---- LEVEL 1 TUTORIAL: exactly ONE thing at a time (bird, crate
                   //      or gust), random order, each shown once per round.
                   l1_gap <= world_clear ? ((l1_gap == 8'd255) ? l1_gap : l1_gap + 8'd1) : 8'd0;
                   if (world_clear && (l1_gap >= L1_GAP_TICKS)) begin
                      l1_gap <= 8'd0;
                      l1_avail = ~l1_done & {1'b1, (crates_spawned < crates_level_total) && crate_alt_ok, 1'b1};
                      if (l1_avail == 3'd0) l1_avail = {1'b1, (crates_spawned < crates_level_total) && crate_alt_ok, 1'b1};
                      // REV4: running out of height with crates left -> give a crate next
                      if ((crates_spawned < crates_level_total) && crate_alt_ok && (altitude[23:8] < 16'd450))
                         l1_avail = 3'b010;
                      // random start, then first available
                      case (lfsr_reg[1:0] % 3)
                         2'd0:    l1_pick = l1_avail[0] ? 2'd0 : l1_avail[1] ? 2'd1 : 2'd2;
                         2'd1:    l1_pick = l1_avail[1] ? 2'd1 : l1_avail[2] ? 2'd2 : 2'd0;
                         default: l1_pick = l1_avail[2] ? 2'd2 : l1_avail[0] ? 2'd0 : 2'd1;
                      endcase
                      // mark it shown; when bird, crate (if any left) and gust have all
                      // been shown once, start a new round
                      l1_done <= (((l1_done | (3'd1 << l1_pick)) |
                                   {1'b0, !(crates_spawned < crates_level_total), 1'b0}) == 3'b111)
                                 ? 3'd0 : (l1_done | (3'd1 << l1_pick));
                      if (l1_pick == 2'd0 && found_empty_slot) begin          // one bird
                         slot_active[empty_slot_idx]       <= 1'b1;
                         slot_type[empty_slot_idx]         <= OBS_BIRD;
                         slot_x[empty_slot_idx]            <= {rand_any_x, 8'd0};
                         slot_y[empty_slot_idx]            <= 16'sd64 <<< 8;
                         slot_vx[empty_slot_idx]           <= BIRD_VX;
                         slot_vy_ind[empty_slot_idx]       <= 16'sd0;
                         slot_flip[empty_slot_idx]         <= lfsr_reg[8];
                         slot_straight[empty_slot_idx]     <= 1'b0;
                         bird_wobble_phase[empty_slot_idx] <= 6'd0;
                      end else if (l1_pick == 2'd1 && found_empty_crate) begin // one crate
                         spawn_crate = 1'b1;
                      end else begin                                          // one gust
                         gust_request <= 1'b1;
                      end
                   end
                end else if (spawning) begin
                   // ---- LEVELS 2-5 canopy spawner ----
                   obstacle_spawn_timer <= obstacle_spawn_timer + 1;
                   // planes run on their own timer (levels 4-5); when due, wait until at
                   // most 1 other obstacle is on screen, then give the 2 s side warning
                   if (cfg_plane_gap != 16'd0 && !plane_on && !pwarn_active && plane_timer < cfg_plane_gap)
                      plane_timer <= plane_timer + 1;
                   if ((cfg_plane_gap != 16'd0) && (plane_timer >= cfg_plane_gap) && !plane_on && !pwarn_active &&
                       (altitude[23:8] >= PLANE_LAST_ALT) &&   // REV8: no planes below 300 m
                       found_empty_slot && !warning_pending && (active_obs_count <= 3'd1)) begin
                      plane_timer  <= 16'd0;
                      begin

                         // PLANE: 2 s warning on the side edge first; nothing else spawns meanwhile
                         pwarn_active <= 1'b1;
                         pwarn_timer  <= PLANE_WARN_TICKS;
                         pwarn_slot   <= empty_slot_idx;
                         pwarn_right  <= lfsr_reg[9];
                         pwarn_y      <= PLANE_Y;   // REV3: level with the hero's body; tug UP to clear it
                      end
                   // REV4: when a plane is due, hold back new obstacles so the screen
                   // thins out and the plane always gets its turn (busy level 5 could
                   // otherwise go a whole level without one)
                   end else if ((obstacle_spawn_timer >= cfg_spawn_interval) && (active_obs_count < cfg_max_obs) &&
                       found_empty_slot && !warning_pending && !pwarn_active && !plane_on &&
                       !((cfg_plane_gap != 16'd0) && (plane_timer >= cfg_plane_gap) && (altitude[23:8] >= PLANE_LAST_ALT))) begin
                      if ((level >= 3'd3) && (lfsr_reg[15:14] == 2'b11) && debris_ok) begin
                         // DEBRIS from the top: 1 s warning, safe-side rule
                         warning_pending                 <= 1'b1;
                         warning_timer                   <= 8'd60;
                         warning_target_slot             <= empty_slot_idx;
                         warn_active                     <= 1'b1;
                         warn_edge                       <= 1'b1;
                         warn_x                          <= top_x;
                         slot_type[empty_slot_idx]       <= OBS_DEBRIS;
                         slot_x[empty_slot_idx]          <= {top_x, 8'd0};
                         slot_y[empty_slot_idx]          <= -16'sd6 <<< 8;
                         slot_vx[empty_slot_idx]         <= 16'sd0;
                         slot_vy_ind[empty_slot_idx]     <= DEBRIS_VY;
                         slot_straight[empty_slot_idx]   <= 1'b1;
                         obstacle_spawn_timer            <= 16'd0;
                      end else if (bot_ok) begin
                         // BIRD from the bottom (diagonal), safe-side rule
                         slot_active[empty_slot_idx]       <= 1'b1;
                         slot_type[empty_slot_idx]         <= OBS_BIRD;
                         slot_x[empty_slot_idx]            <= {bot_x, 8'd0};
                         slot_y[empty_slot_idx]            <= 16'sd64 <<< 8;
                         slot_vx[empty_slot_idx]           <= BIRD_VX;
                         slot_vy_ind[empty_slot_idx]       <= 16'sd0;
                         slot_flip[empty_slot_idx]         <= (bot_x < 8'd44);   // drift toward own edge
                         slot_straight[empty_slot_idx]     <= 1'b0;
                         bird_wobble_phase[empty_slot_idx] <= 6'd0;
                         obstacle_spawn_timer              <= 16'd0;
                      end
                   end
                   // crates on their own timer (levels 2-5)
                   if (game_state == S_CANOPY) begin
                      crate_spawn_timer <= crate_spawn_timer + 1;
                      if ((crate_spawn_timer >= cfg_crate_interval) && found_empty_crate &&
                          (crates_spawned < crates_level_total) && crate_alt_ok) begin   // REV4: >= 150 m above ground
                         crate_spawn_timer <= 16'd0;
                         spawn_crate = 1'b1;
                      end
                   end
                end

                // ---- shared crate spawn (green medic crate) ----
                if (spawn_crate) begin
                   crates_spawned             <= crates_spawned + 3'd1;
                   cr_active[empty_crate_idx] <= 1'b1;
                   cr_y[empty_crate_idx]      <= 16'sd64 <<< 8;
                   rand_offset_x = $signed({10'd0, lfsr_reg[5:0]}) - 16'sd32;
                   if (($signed(hero_x) + rand_offset_x) < $signed(CRATE_X_MIN))
                      cr_x[empty_crate_idx] <= CRATE_X_MIN <<< 8;
                   else if (($signed(hero_x) + rand_offset_x) > $signed(CRATE_X_MAX))
                      cr_x[empty_crate_idx] <= CRATE_X_MAX <<< 8;
                   else
                      cr_x[empty_crate_idx] <= ($signed(hero_x) + rand_offset_x) <<< 8;
                end
                spawn_crate = 1'b0;
                // F. Global Kinematics Engine Transformations
                for (i = 0; i < 6; i = i + 1) begin
                   if (slot_active[i]) begin
                      if (calm_zone) begin
                         slot_active[i] <= 1'b0;                 // REV8: last 50 m is clear
                      end else if (slot_hit[i] && (!warning_pending || warning_target_slot != i[2:0])) begin
                         slot_active[i] <= 1'b0;
                      end else begin
                         // REV7: during a crash everything flies up and away (no longer 'falls with him')
                         slot_y[i] <= slot_y[i] + slot_vy_ind[i] - ((game_state == S_CRASH) ? 16'sd768 : scroll_vy);
                         slot_x[i] <= slot_x[i] + slot_vx[i];
                         case (slot_type[i])
                         OBS_BIRD: begin
                            bird_wobble_phase[i] <= (bird_wobble_phase[i] == 6'd11) ? 6'd0 : bird_wobble_phase[i] + 1;
                            if (slot_straight[i]) begin
                               slot_x[i] <= slot_x[i];        // REV3: freefall birds fly straight up
                            end else if (slot_flip[i]) begin
                               slot_x[i] <= slot_x[i] - BIRD_VX + (get_sine_wobble(bird_wobble_phase[i][3:0]) <<< 5);
                            end else begin
                               slot_x[i] <= slot_x[i] + BIRD_VX + (get_sine_wobble(bird_wobble_phase[i][3:0]) <<< 5);
                            end
                         end
                         OBS_PLANE: begin
                            slot_y[i] <= slot_y[i];   // REV3: planes fly level (no scroll) at PLANE_Y
                         end
                         default: begin 
                            // Linear updates handled above
                         end
                         endcase
                         // FIX #3/#4/#6/#8 (ROOT CAUSE): a part-select like slot_y[i][15:8] is
                         // UNSIGNED in Verilog, so "< -20" compared against a huge number and
                         // was ALWAYS true -> every bird/plane/debris was deleted on its first
                         // tick (the warning showed, then nothing came). Use $signed().
                         if (($signed(slot_y[i][15:8]) < -20) || ($signed(slot_y[i][15:8]) > 80) ||
                             ($signed(slot_x[i][15:8]) < -40) || ($signed(slot_x[i][15:8]) > 120)) begin
                            slot_active[i] <= 1'b0;
                         end
                      end
                   end
                end
                // G. Checkpoint 3 Crate Vector Processing Matrix (Standard Motion vs Proximity Magnet Pull)
                target_center_x = hero_x + HB_BODY_X + (HB_BODY_W / 2);
                target_center_y = hero_y + HB_BODY_Y + (HB_BODY_H / 2);
                for (i = 0; i < 4; i = i + 1) begin
                   if (cr_active[i]) begin
                      if (magnet_active_reg) begin
                         // Calculate current crate center position
                         crate_center_x = cr_x[i][15:8] + (CRATE_W / 2);
                         crate_center_y = cr_y[i][15:8] + (CRATE_H / 2);
                         // Calculate distances per axis
                         dx = target_center_x - crate_center_x;
                         dy = target_center_y - crate_center_y;
                         abs_dx = (dx < 0) ? -dx : dx;
                         abs_dy = (dy < 0) ? -dy : dy;
                         manhattan_dist = abs_dx + abs_dy;
                        // Apply attraction vectors based on distance thresholds
                        if (manhattan_dist > 32) begin
                           // Outside pull threshold, apply standard vertical scroll velocity
                           cr_y[i] <= cr_y[i] + CRATE_FALL - ((game_state == S_CRASH) ? 16'sd768 : scroll_vy);   // REV8: crates fly up during a crash  // FIX #3: crates fall slower than hero (ICD: up by scroll_vy - CRATE_FALL)
                        end else if (manhattan_dist >= 16) begin
                           // Medium Range Proximity Zone: pull smoothly at 0.25 px/tick
                           cr_x[i] <= (dx < 0) ? cr_x[i] - MAGNET_FAR : cr_x[i] + MAGNET_FAR;
                           cr_y[i] <= ((dy < 0) ? cr_y[i] - MAGNET_FAR : cr_y[i] + MAGNET_FAR) - scroll_vy;
                        end else begin
                           // Close Range Proximity Zone: accelerate pull to 0.75 px/tick
                           cr_x[i] <= (dx < 0) ? cr_x[i] - MAGNET_NEAR : cr_x[i] + MAGNET_NEAR;
                           cr_y[i] <= ((dy < 0) ? cr_y[i] - MAGNET_NEAR : cr_y[i] + MAGNET_NEAR) - scroll_vy;
                        end
                     end else begin
                        // Magnet inactive, apply standard cargo scroll translation
                        cr_y[i] <= cr_y[i] + CRATE_FALL - scroll_vy;  // FIX #3: crates fall slower than hero (ICD: up by scroll_vy - CRATE_FALL)
                     end
                     // Clear active registers if crates escape upper bounds
                     if ($signed(cr_y[i][15:8]) < -16 || $signed(cr_y[i][15:8]) > 80 ||
                          ((game_state == S_FINAL_APPROACH) && (altitude[23:8] < CALM_ALT))) begin  // FIX #3 + REV8 calm zone
                        cr_active[i] <= 1'b0;
                     end
                  end
               end
            end
         end
      end
   endmodule 
