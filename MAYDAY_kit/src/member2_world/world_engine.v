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

    // -----------------------------------------------------------------
    // 1. LFSR Engine (16-bit Maximal-length, taps 16, 14, 13, 11)
    // -----------------------------------------------------------------
    reg [15:0] lfsr_reg;
    wire lfsr_feedback = lfsr_reg ^ lfsr_reg ^ lfsr_reg ^ lfsr_reg;

    always @(posedge clk) begin
        if (rst) begin
            lfsr_reg <= 16'h5A5A; 
        end else if (level_start) begin
            lfsr_reg <= ((seed ^ LFSR_CONST_M2) == 16'h0000) ? 16'h0001 : (seed ^ LFSR_CONST_M2);
        end else if (game_tick) begin
            lfsr_reg <= {lfsr_reg[14:0], lfsr_feedback};
        end
    end

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

    reg signed [15:0] cr_x [0:3];
    reg signed [15:0] cr_y [0:3];
    reg               cr_active [0:3];

    reg [2:0]  cfg_max_obs;
    reg [15:0] cfg_spawn_interval;
    reg [7:0]  cfg_plane_share;
    reg [15:0] obstacle_spawn_timer;
    reg [15:0] crate_spawn_timer;

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
              warning_timer        <= 8'd0;
              warning_pending      <= 1'b0;
              warn_active          <= 1'b0;
              magnet_timer         <= 9'd0;
              magnet_active_reg    <= 1'b0;
              for (i = 0; i < 6; i = i + 1) begin
                 slot_x[i]            <= 16'sd0;
                 slot_y[i]            <= 16'sd0;
                 slot_vx[i]           <= 16'sd0;
                 slot_vy_ind[i]       <= 16'sd0;
                 slot_type[i]         <= OBS_EMPTY;
                 slot_active[i]       <= 1'b0;
                 slot_flip[i]         <= 1'b0;
                 bird_wobble_phase[i] <= 6'd0;
              end 
              for (i = 0; i < 4; i = i + 1) begin
                 cr_x[i]              <= 16'sd0;
                 cr_y[i]              <= 16'sd0;
                 cr_active[i]         <= 1'b0;
              end
              if (level_start) begin
                 target_x <= TARGET_X_MIN + (lfsr_reg[7:0] % (TARGET_X_MAX - TARGET_X_MIN + 1));
                 case (level)
                 3'd1: begin
                    crates_level_total <= 3'd3;  cfg_max_obs <= 3'd2;
                    cfg_spawn_interval <= 16'd120; cfg_plane_share <= 8'd0;
                 end
                 3'd2: begin
                    crates_level_total <= 3'd3;  cfg_max_obs <= 3'd3;
                    cfg_spawn_interval <= 16'd96;  cfg_plane_share <= 8'd0;
                 end
                 3'd3: begin
                    crates_level_total <= 3'd4;  cfg_max_obs <= 3'd4;
                    cfg_spawn_interval <= 16'd78;  cfg_plane_share <= 8'd26;
                 end
                 3'd4: begin
                   crates_level_total <= 3'd4;  cfg_max_obs <= 3'd5;
                   cfg_spawn_interval <= 16'd66;  cfg_plane_share <= 8'd51;
                 end
                 3'd5: begin
                    crates_level_total <= 3'd5;  cfg_max_obs <= 3'd6;
                    cfg_spawn_interval <= 16'd54;  cfg_plane_share <= 8'd64;
                 end
                 default: begin
                    crates_level_total <= 3'd3;  cfg_max_obs <= 3'd2;
                    cfg_spawn_interval <= 16'd120; cfg_plane_share <= 8'd0;
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
                   strike_side <= ((slot_x[first_hit_idx][15:8] + 8) < (hero_x + 8)) ? 1'b0 : 1'b1;
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
                active_obs_count = 3'd0;
                window_bird_present = 1'b0;
                for (i = 0; i < 6; i = i + 1) begin
                   if (slot_active[i]) begin
                      active_obs_count = active_obs_count + 1;
                      if (slot_type[i] == OBS_BIRD) window_bird_present = 1'b1;
                   end
                end
                found_empty_slot = 1'b0;
                empty_slot_idx   = 3'd0;
                for (i = 0; i < 6; i = i + 1) begin
                   if (!slot_active[i] && (!warning_pending || warning_target_slot != i[2:0]) && !found_empty_slot) begin
                      found_empty_slot = 1'b1;
                      empty_slot_idx   = i[2:0];
                   end
                end 
                // Check spawner constraints alongside Checkpoint 3's Final Approach Hard Cutoff rule
                if (game_state >= S_FREEFALL_LOCKED && game_state <= S_FINAL_APPROACH && scroll_vy > 0) begin
                   obstacle_spawn_timer <= obstacle_spawn_timer + 1;
                   if ((obstacle_spawn_timer >= cfg_spawn_interval) && (active_obs_count < cfg_max_obs) && found_empty_slot && !warning_pending) begin
                      if ((game_state == S_FREEFALL_WINDOW) && window_bird_present) begin
                         obstacle_spawn_timer <= cfg_spawn_interval;
                      end else begin
                         if (game_state == S_FREEFALL_LOCKED || game_state == S_FREEFALL_WINDOW) begin
                            warning_pending                     <= 1'b1;
                            warning_timer                       <= 8'd60;
                            warning_target_slot                 <= empty_slot_idx;
                            warn_active                         <= 1'b1;
                            warn_edge                           <= 1'b0;
                            warn_x                              <= 8'd10 + (lfsr_reg[7:0] % 76);
                            slot_type[empty_slot_idx]           <= OBS_BIRD;
                            slot_x[empty_slot_idx]              <= (8'd10 + (lfsr_reg[7:0] % 76)) <<< 8;
                            slot_y[empty_slot_idx]              <= 16'sd64 <<< 8;
                            slot_vx[empty_slot_idx]             <= BIRD_VX;
                            slot_vy_ind[empty_slot_idx]         <= 16'sd0;
                            slot_flip[empty_slot_idx]           = lfsr_reg;
                            bird_wobble_phase[empty_slot_idx]   <= 6'd0;
                         end else begin
                            if (lfsr_reg[7:0] < cfg_plane_share) begin
                               slot_active[empty_slot_idx]     <= 1'b1;
                               slot_type[empty_slot_idx]       <= OBS_PLANE;
                               slot_vy_ind[empty_slot_idx]     <= 16'sd0;
                               obstacle_spawn_timer            <= 16'd0;
                               if (lfsr_reg) begin
                                  slot_x[empty_slot_idx]      <= -16'sd24 <<< 8;
                                  slot_vx[empty_slot_idx]     <= PLANE_VX;
                                  slot_flip[empty_slot_idx]   <= 1'b0;
                               end else begin
                                  slot_x[empty_slot_idx]      <= 16'sd96 <<< 8;
                                  slot_vx[empty_slot_idx]     <= -PLANE_VX;
                                  slot_flip[empty_slot_idx]   <= 1'b1;
                               end
                               slot_y[empty_slot_idx] <= (16'sd32 + (lfsr_reg[14:9] % 24)) <<< 8;
                            end else if (lfsr_reg[15:13] == 3'b111 && level >= 3'd2) begin
                               warning_pending                 <= 1'b1;
                               warning_timer                   <= 8'd60;
                               warning_target_slot             <= empty_slot_idx;
                               warn_active                     <= 1'b1;
                               warn_edge                       <= 1'b1;
                               warn_x                          <= 8'd10 + (lfsr_reg[7:0] % 76);
                               slot_type[empty_slot_idx]       <= OBS_DEBRIS;
                               slot_x[empty_slot_idx]          <= (8'd10 + (lfsr_reg[7:0] % 76)) <<< 8;
                               slot_y[empty_slot_idx]          <= -16'sd6 <<< 8;
                               slot_vx[empty_slot_idx]         <= 16'sd0;
                               slot_vy_ind[empty_slot_idx]     <= DEBRIS_VY;
                            end else begin
                               slot_active[empty_slot_idx]     <= 1'b1;
                               slot_type[empty_slot_idx]       <= OBS_BIRD;
                               slot_x[empty_slot_idx]          <= (8'd10 + (lfsr_reg[7:0] % 76)) <<< 8;
                               slot_y[empty_slot_idx]          <= 16'sd64 <<< 8;
                               slot_vx[empty_slot_idx]         <= BIRD_VX;
                               slot_vy_ind[empty_slot_idx]     <= 16'sd0;
                               slot_flip[empty_slot_idx]       <= lfsr_reg;
                               bird_wobble_phase[empty_slot_idx] <= 6'd0;
                               obstacle_spawn_timer            <= 16'd0;
                            end
                         end
                      end
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
                if (game_state == S_CANOPY && scroll_vy > 0) begin
                   crate_spawn_timer <= crate_spawn_timer + 1;
                   if ((crate_spawn_timer >= 16'd210) && found_empty_crate) begin
                      crate_spawn_timer <= 16'd0;
                      cr_active[empty_crate_idx] <= 1'b1;
                      cr_y[empty_crate_idx]      <= 16'sd64 <<< 8;
                      rand_offset_x = (lfsr_reg[5:0] - 16'sd32);
                      if ((hero_x + rand_offset_x[7:0]) < CRATE_X_MIN) begin
                         cr_x[empty_crate_idx] <= CRATE_X_MIN <<< 8;
                      end else if ((hero_x + rand_offset_x[7:0]) > CRATE_X_MAX) begin
                         cr_x[empty_crate_idx] <= CRATE_X_MAX <<< 8;
                      end else begin
                         cr_x[empty_crate_idx] <= (hero_x + rand_offset_x[7:0]) <<< 8;
                      end
                   end
                end
                // F. Global Kinematics Engine Transformations
                for (i = 0; i < 6; i = i + 1) begin
                   if (slot_active[i]) begin
                      if (slot_hit[i] && (!warning_pending || warning_target_slot != i[2:0])) begin
                         slot_active[i] <= 1'b0;
                      end else begin
                         slot_y[i] <= slot_y[i] + slot_vy_ind[i] - scroll_vy;
                         slot_x[i] <= slot_x[i] + slot_vx[i];
                         case (slot_type[i])
                         OBS_BIRD: begin
                            bird_wobble_phase[i] <= (bird_wobble_phase[i] == 6'd11) ? 6'd0 : bird_wobble_phase[i] + 1;
                            if (slot_flip[i]) begin
                               slot_x[i] <= slot_x[i] - BIRD_VX + (get_sine_wobble(bird_wobble_phase[i][3:0]) <<< 8);
                            end else begin
                               slot_x[i] <= slot_x[i] + BIRD_VX + (get_sine_wobble(bird_wobble_phase[i][3:0]) <<< 8);
                            end
                         end
                         default: begin 
                            // Linear updates handled above
                         end
                         endcase
                         if ((slot_y[i][15:8] < -20) || (slot_y[i][15:8] > 80) ||
                             (slot_x[i][15:8] < -40) || (slot_x[i][15:8] > 120)) begin
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
                           cr_y[i] <= cr_y[i] - CRATE_FALL - scroll_vy;
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
                        cr_y[i] <= cr_y[i] - CRATE_FALL - scroll_vy;
                     end
                     // Clear active registers if crates escape upper bounds
                     if (cr_y[i][15:8] < -16 || cr_y[i][15:8] > 80) begin
                        cr_active[i] <= 1'b0;
                     end
                  end
               end
            end
         end
      end
   endmodule 
