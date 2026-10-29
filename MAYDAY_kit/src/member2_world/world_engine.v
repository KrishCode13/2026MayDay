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
// STATUS: CORE CHECKPOINT 1 FOR FIRST TEST (LFSR, Slots, Birds, Collision)
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

    // -----------------------------------------------------------------
    // 2. Internal Slot Arrays (Q8.8 Fixed-Point Format)
    // -----------------------------------------------------------------
    reg signed [15:0] slot_x [0:5];
    reg signed [15:0] slot_y [0:5];
    reg        [1:0]  slot_type [0:5];
    reg               slot_active [0:5];
    reg               slot_flip [0:5];
    reg [5:0] bird_wobble_phase [0:5];

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
    // 3. Flatten Registers to Output Buses (Combinational)
    // -----------------------------------------------------------------
    integer s;
    always @(*) begin
        crate_x            = 32'd0;
        crate_y            = 32'd0;
        crate_active       = 4'd0;
        warn_x             = 8'sd0;
        warn_active        = 1'b0;
        warn_edge          = 1'b0;
        magnet_active      = 1'b0;
        magnet_ticks_left  = 9'd0;
        crate_collected    = 1'b0;

        for (s = 0; s < 6; s = s + 1) begin
            obs_x[(s*8)+:8]      = slot_x[s][15:8];
            obs_y[(s*8)+:8]      = slot_y[s][15:8];
            obs_type[(s*2)+:2]   = slot_type[s];
            obs_active[s]        = slot_active[s];
            obs_flip[s]          = slot_flip[s];
        end
    end

    // -----------------------------------------------------------------
    // 4. Collision Detection Matrix (Dual-Hitbox Box Overlap)
    // -----------------------------------------------------------------
    reg        slot_hit [0:5];
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
            if (slot_active[c]) begin
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

    // -----------------------------------------------------------------
    // 5. Sequential Logic (Kinematics & Multi-Hit Event Handling)
    // -----------------------------------------------------------------
    integer i;
    reg [2:0] hit_count;
    reg [2:0] first_hit_idx;
    
    always @(posedge clk) begin
        if (rst || level_start) begin
            strike             <= 1'b0;
            strike_side        <= 1'b0;
            strike_lines       <= 2'd0;
            target_x           <= 8'd40; 
            crates_level_total <= 3'd3;  

            for (i = 0; i < 6; i = i + 1) begin
                slot_x[i]             <= 16'sd0;
                slot_y[i]             <= 16'sd0;
                slot_type[i]          <= OBS_EMPTY;
                slot_active[i]        <= 1'b0;
                slot_flip[i]          <= 1'b0;
                bird_wobble_phase[i]  <= 6'd0;
            end

            if (level_start) begin
                target_x <= TARGET_X_MIN + (lfsr_reg[7:0] % (TARGET_X_MAX - TARGET_X_MIN + 1));
                case (level)
                    3'd1:    crates_level_total <= 3'd3;
                    3'd2:    crates_level_total <= 3'd3;
                    3'd3:    crates_level_total <= 3'd4;
                    3'd4:    crates_level_total <= 3'd4;
                    3'd5:    crates_level_total <= 3'd5;
                    default: crates_level_total <= 3'd3;
                endcase
            end
        end else begin
            strike <= 1'b0; // Pulse default low

            if (game_tick) begin
                // A. Scan for concurrent collisions
                hit_count     = 3'd0;
                first_hit_idx = 3'd7;
                for (i = 0; i < 6; i = i + 1) begin
                   if (slot_active[i] && slot_hit[i]) begin
                      hit_count = hit_count + 1;
                      if (first_hit_idx == 3'd7) first_hit_idx = i[2:0];
                      end
                   end
                  // B. Handle strike triggers and line calculation
                  if (hit_count > 0) begin
                     strike <= 1'b1;
                     strike_side <= ((slot_x[first_hit_idx][15:8] + 8) < (hero_x + 8)) ? 1'b0 : 1'b1;
                     if (hit_count == 3'd1) begin
                        strike_lines <= (slot_type[first_hit_idx] == OBS_PLANE) ? 2'd2 : 2'd1;
                     end else begin
                        strike_lines <= 2'd2; // Multi-hit caps at 2 lines
                     end
                  end
                  // C. Object Kinematics Update
                  for (i = 0; i < 6; i = i + 1) begin
                     if (slot_active[i]) begin
                        if (slot_hit[i]) begin
                           slot_active[i] <= 1'b0; // Deactivate hit objects instantly
                        end else begin
                           slot_y[i] <= slot_y[i] - scroll_vy;
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
                              // Placeholder for future states
                              end
                           endcase
                           // Off-screen clearing
                           if ((slot_y[i][15:8] < -12) || (slot_y[i][15:8] > 70) ||
                               (slot_x[i][15:8] < -30) || (slot_x[i][15:8] > 110)) begin
                              slot_active[i] <= 1'b0;
                           end
                        end
                     end
                  end
                  // D. Injected Test Bird Setup
                 if (game_state >= S_FREEFALL_LOCKED && game_state <= S_FINAL_APPROACH) begin
                    if (!slot_active[0]) begin
                       slot_active[0]        <= 1'b1;
                       slot_type[0]          <= OBS_BIRD;
                       slot_x[0]             <= 16'sd30 <<< 8;
                       slot_y[0]             <= 16'sd64 <<< 8;
                       slot_flip[0]          <= 1'b0;
                       bird_wobble_phase[0]  <= 6'd0;
                 end
              end
           end
        end
     end
endmodule
