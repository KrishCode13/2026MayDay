// =====================================================================
// cutscene_engine.v  --  MEMBER 4. The 21-second opening cutscene.
// Ports unchanged from the kit (FINAL).
//
// STATUS (CP3a): scenes 1 Boarding, 3 Flight, 4 Explosion, 5 Jump.
//   Scene 2 (Briefing) shows a plain cabin colour until font_rom.v arrives.
//
// HOW IT WORKS (Q&A order)
//  1. Timeline: own tick counter t (0..1260); scene = which band t is in.
//  2. Keyframe ROM: rows of {start tick, object, duration code, hide,
//     x0, y0, x1, y1}, sorted by start tick. Durations are 32/64/128/256
//     ticks = 2^n.
//  3. Loader: between game ticks, a pointer walks the ROM; every row whose
//     start tick has arrived is loaded into its object, one row per clock:
//         pos  = start (Q8.8)
//         step = ((end - start) << 8) >>> n      <- the "divide" is a shift
//         cnt  = 2^n
//  4. Mover: on every game_tick, each object with cnt > 0 does
//         pos = pos + step;  cnt = cnt - 1
//     No multiplier, no divider. With whole-pixel endpoints and n <= 8,
//     step = (end - start) * 2^(8-n) exactly, so the object lands exactly
//     on its end pixel with no rounding drift.
//  5. Pixel pipeline (3 clocks; a pixel lasts 16 clocks, so this is free):
//       A: geometry  - where is this pixel relative to each object?
//       B: sprites   - read sprite ROMs, pick the front-most colour index
//       C: palette   - index -> RGB565 for the selected level's setting
//  6. Explosion (scene 4): 12 particles start at the engine with velocities
//     from a 12-direction lookup table. Every tick, for each live particle:
//         pos = pos + vel;   vy = vy + GRAVITY;   age = age + 1
//     so they burst outward, then arc downward; they die at age 36.
//     Colour follows age: gold -> orange -> red -> grey.
//     Plus a 3-frame white flash, a +/-2 px shake, and a smoke trail
//     (8 puffs in a ring buffer, one emitted every 8 ticks, growing and
//     drifting back).
// =====================================================================
module cutscene_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        game_tick,
    input  wire [3:0]  game_state,
    input  wire [2:0]  level,          // selects palette
    input  wire [6:0]  pixel_x,
    input  wire [5:0]  pixel_y,
    output reg  [15:0] oled_data_cut,
    output reg         cutscene_done   // high when the last scene ends
);
    `include "game_params.vh"

    // ---------------- Objects ------------------------------------------
    localparam OBJ_JET = 0, OBJ_STAIRS = 1, OBJ_P0 = 2, OBJ_P1 = 3, OBJ_P2 = 4,
               OBJ_HERO = 5, OBJ_HERO_FF = 6, NOBJ = 8;   // 6 = hero in freefall pose; 7 spare
    // Duration codes: shift n = 5 + code
    localparam [1:0] D32 = 2'd0, D64 = 2'd1, D128 = 2'd2, D256 = 2'd3;

    // ---------------- Scene layout (art coordinates, not tuning) -------
    localparam JET_W = 40, JET_H = 16, JET_H_AIR = 14,  // rows 14-15 = landing gear
               PAS_W = 4, PAS_H = 8, FF_W = 10, FF_H = 8;
    localparam ENG_X = 17, ENG_Y = 13;          // engine pod centre inside the jet sprite
    localparam CLB_W = 20, CLB_H = 7, CLS_W = 12, CLS_H = 4;   // big / small cloud
    localparam S1_GROUND_Y = 36, S1_TARMAC_Y = 44, S1_LINE_Y = 57;
    localparam STAIR_SUM = 108, STAIR_TOP_Y = 41, STAIR_FOOT_Y = 50;  // band x+y = 108..111

    // Palette indices used by the cutscene (ICD colour table)
    localparam [4:0] P_TRANS = 5'd0, P_BLACK = 5'd1, P_WHITE = 5'd2, P_CLOUD = 5'd3,
                     P_GREY = 5'd4, P_ORANGE = 5'd5, P_NAVY = 5'd7, P_BROWN = 5'd9, P_GOLD = 5'd10,
                     P_RED = 5'd11, P_GROUND = 5'd12, P_DETAIL = 5'd13, P_CYAN = 5'd14,
                     P_SKY = 5'd15, P_SILVER = 5'd16, P_STEEL = 5'd17,
                     P_CABIN = 5'd20, P_TARMAC = 5'd21,
                     P_TIE = 5'd30, P_SHIRT = 5'd31;   // sprite markers, replaced per person

    // =================================================================
    // 2. KEYFRAME ROM (sorted by start tick; last row is a sentinel)
    // =================================================================
    function [48:0] KF;   // pack one row
        input integer start, obj, dcode, hide, x0, y0, x1, y1;
        KF = {start[10:0], obj[2:0], dcode[1:0], hide[0],
              x0[7:0], y0[7:0], x1[7:0], y1[7:0]};
    endfunction

    function [48:0] kf_rom;
        input [5:0] i;
        case (i)
            //               start obj         dur   hide  x0   y0   x1   y1
            // ---- Scene 1: Boarding (t 0..299) ----
            6'd0:  kf_rom = KF(  0, OBJ_JET,    D32,  0,  40,  31,  40,  31); // parked jet, wheels on tarmac
            6'd1:  kf_rom = KF(  0, OBJ_STAIRS, D32,  0,   0,   0,   0,   0); // stair truck at door
            6'd2:  kf_rom = KF(  8, OBJ_P0,     D64,  0, -10,  43,  56,  43); // walk to stairs
            6'd3:  kf_rom = KF( 48, OBJ_P1,     D64,  0, -10,  43,  56,  43);
            6'd4:  kf_rom = KF( 72, OBJ_P0,     D32,  1,  56,  43,  68,  33); // climb, vanish in door
            6'd5:  kf_rom = KF( 88, OBJ_P2,     D64,  0, -10,  43,  56,  43);
            6'd6:  kf_rom = KF(112, OBJ_P1,     D32,  1,  56,  43,  68,  33);
            6'd7:  kf_rom = KF(128, OBJ_HERO,   D64,  0, -10,  43,  56,  43); // hero boards last
            6'd8:  kf_rom = KF(152, OBJ_P2,     D32,  1,  56,  43,  68,  33);
            6'd9:  kf_rom = KF(192, OBJ_HERO,   D32,  1,  56,  43,  68,  33);
            6'd10: kf_rom = KF(240, OBJ_STAIRS, D32,  0,   0,   0, -32,   0); // truck drives off
            // ---- Scene 3: Flight (t 660..899) ----
            6'd11: kf_rom = KF(660, OBJ_JET,    D128, 0, -48,  20,  24,  20); // jet cruises in
            6'd12: kf_rom = KF(788, OBJ_JET,    D64,  0,  24,  20,  24,  23); // gentle bob down
            6'd13: kf_rom = KF(852, OBJ_JET,    D32,  0,  24,  23,  24,  20); // and up
            // ---- Scene 4: Explosion (t 900..1139) - the jet sinks ----
            6'd14: kf_rom = KF(900, OBJ_JET,    D128, 0,  24,  20,  40,  26);
            6'd15: kf_rom = KF(1028,OBJ_JET,    D64,  0,  40,  26,  48,  30);
            6'd16: kf_rom = KF(1092,OBJ_JET,    D32,  0,  48,  30,  52,  32);
            // ---- Scene 5: Jump (t 1140..1259) ----
            6'd17: kf_rom = KF(1140,OBJ_JET,    D128, 0,  52,  32,  84,  56); // descends at right
            6'd18: kf_rom = KF(1152,OBJ_HERO_FF,D32,  0,  80,  38,  70,  56); // hero drops clear of the jet
            6'd19: kf_rom = KF(1184,OBJ_HERO_FF,D64,  1,  70,  56,  62,  74); // falls out of view
            default: kf_rom = KF(2047, 0, D32, 0, 0, 0, 0, 0);               // sentinel: never
        endcase
    endfunction

    // =================================================================
    // 1, 3, 4. TIMELINE, LOADER, MOVER
    // =================================================================
    reg  [10:0] t;                       // ticks since the cutscene began
    reg  [5:0]  kf_ptr;                  // next ROM row to load
    reg  signed [15:0] ox [0:NOBJ-1];    // position x, Q8.8
    reg  signed [15:0] oy [0:NOBJ-1];    // position y, Q8.8
    reg  signed [15:0] vx [0:NOBJ-1];    // step per tick x, Q8.8
    reg  signed [15:0] vy [0:NOBJ-1];    // step per tick y, Q8.8
    reg  [8:0]  cnt [0:NOBJ-1];          // ticks of movement left
    reg  [NOBJ-1:0] vis, hide_end;       // visible / hide when movement ends

    // Decode the current ROM row
    wire [48:0] kf     = kf_rom(kf_ptr);
    wire [10:0] kf_t   = kf[48:38];
    wire [2:0]  kf_obj = kf[37:35];
    wire [1:0]  kf_d   = kf[34:33];
    wire        kf_hid = kf[32];
    wire [7:0]  kf_x0 = kf[31:24], kf_y0 = kf[23:16], kf_x1 = kf[15:8], kf_y1 = kf[7:0];

    // step = ((end - start) << 8) >>> n, with n = 5 + code. 17-bit signed.
    wire signed [8:0]  kf_dx = $signed({kf_x1[7], kf_x1}) - $signed({kf_x0[7], kf_x0});
    wire signed [8:0]  kf_dy = $signed({kf_y1[7], kf_y1}) - $signed({kf_y0[7], kf_y0});
    wire signed [16:0] kf_dx_q = {kf_dx, 8'd0};          // to Q8.8
    wire signed [16:0] kf_dy_q = {kf_dy, 8'd0};
    wire signed [16:0] kf_sx = kf_dx_q >>> (5 + kf_d);   // divide by 2^n = shift
    wire signed [16:0] kf_sy = kf_dy_q >>> (5 + kf_d);

    integer k;
    initial begin
        t = 0; kf_ptr = 0; vis = 0; hide_end = 0; cutscene_done = 0; oled_data_cut = 0;
        for (k = 0; k < NOBJ; k = k + 1) begin
            ox[k] = 0; oy[k] = 0; vx[k] = 0; vy[k] = 0; cnt[k] = 0;
        end
    end

    always @(posedge clk) begin
        if (rst || game_state != S_CUTSCENE) begin
            // Idle: rewind everything so the next play starts fresh.
            t <= 11'd0;  kf_ptr <= 6'd0;  vis <= 0;  cutscene_done <= 1'b0;
            for (k = 0; k < NOBJ; k = k + 1) cnt[k] <= 9'd0;
        end else if (game_tick) begin
            // MOVER: one step for every moving object, once per tick.
            t <= t + 1'b1;
            if (t >= CUT_TOTAL - 1) cutscene_done <= 1'b1;
            for (k = 0; k < NOBJ; k = k + 1)
                if (cnt[k] != 9'd0) begin
                    ox[k]  <= ox[k] + vx[k];
                    oy[k]  <= oy[k] + vy[k];
                    cnt[k] <= cnt[k] - 1'b1;
                    if (cnt[k] == 9'd1 && hide_end[k]) vis[k] <= 1'b0;
                end
        end else if (kf_t <= t) begin
            // LOADER: one due ROM row per clock, between ticks.
            ox[kf_obj]       <= {kf_x0, 8'd0};
            oy[kf_obj]       <= {kf_y0, 8'd0};
            vx[kf_obj]       <= kf_sx[15:0];
            vy[kf_obj]       <= kf_sy[15:0];
            cnt[kf_obj]      <= 9'd1 << (5 + kf_d);    // 32, 64, 128 or 256
            vis[kf_obj]      <= 1'b1;
            hide_end[kf_obj] <= kf_hid;
            kf_ptr           <= kf_ptr + 1'b1;
        end
    end

    // =================================================================
    // 6. EXPLOSION ENGINE: 12 particles + smoke ring buffer
    // =================================================================
    localparam NPART = 12, NSMOKE = 8;

    // 12-direction velocity table, Q8.8. Angle = 30 deg x i. Even entries
    // move at 1.25 px/tick, odd at 0.875 px/tick, so the burst looks
    // ragged rather than a perfect ring. (vy negative = upward.)
    function signed [15:0] pvx0; input [3:0] i;
        case (i)
            4'd0: pvx0 =  16'sd320;  4'd1: pvx0 =  16'sd194;  4'd2:  pvx0 =  16'sd160;
            4'd3: pvx0 =  16'sd0;    4'd4: pvx0 = -16'sd160;  4'd5:  pvx0 = -16'sd194;
            4'd6: pvx0 = -16'sd320;  4'd7: pvx0 = -16'sd194;  4'd8:  pvx0 = -16'sd160;
            4'd9: pvx0 =  16'sd0;    4'd10: pvx0 = 16'sd160;  default: pvx0 = 16'sd194;
        endcase
    endfunction
    function signed [15:0] pvy0; input [3:0] i;
        case (i)
            4'd0: pvy0 =  16'sd0;    4'd1: pvy0 = -16'sd112;  4'd2:  pvy0 = -16'sd277;
            4'd3: pvy0 = -16'sd224;  4'd4: pvy0 = -16'sd277;  4'd5:  pvy0 = -16'sd112;
            4'd6: pvy0 =  16'sd0;    4'd7: pvy0 =  16'sd112;  4'd8:  pvy0 =  16'sd277;
            4'd9: pvy0 =  16'sd224;  4'd10: pvy0 = 16'sd277;  default: pvy0 = 16'sd112;
        endcase
    endfunction

    reg signed [15:0] ppx [0:NPART-1], ppy [0:NPART-1];   // particle position, Q8.8
    reg signed [15:0] pvx [0:NPART-1], pvy [0:NPART-1];   // particle velocity, Q8.8
    reg        [5:0]  page [0:NPART-1];                    // age in ticks
    reg  [NPART-1:0]  palive;

    reg signed [7:0]  smx [0:NSMOKE-1], smy [0:NSMOKE-1]; // puff centre, whole px
    reg        [5:0]  sage [0:NSMOKE-1];
    reg  [NSMOKE-1:0] salive;
    reg        [2:0]  sm_next;                             // ring-buffer write pointer

    // Engine position on screen (whole px) = jet position + engine offset
    wire signed [7:0] eng_x = ox[OBJ_JET][15:8] + ENG_X;
    wire signed [7:0] eng_y = oy[OBJ_JET][15:8] + ENG_Y;

    integer p;
    initial begin
        palive = 0; salive = 0; sm_next = 0;
        for (p = 0; p < NPART; p = p + 1) begin ppx[p] = 0; ppy[p] = 0; pvx[p] = 0; pvy[p] = 0; page[p] = 0; end
        for (p = 0; p < NSMOKE; p = p + 1) begin smx[p] = 0; smy[p] = 0; sage[p] = 0; end
    end

    always @(posedge clk) begin
        if (rst || game_state != S_CUTSCENE) begin
            palive <= 0;  salive <= 0;  sm_next <= 3'd0;
        end else if (game_tick) begin
            if (t == CUT_S3_END - 1) begin
                // BURST: the tick that starts scene 4. All 12 spawn at the engine.
                for (p = 0; p < NPART; p = p + 1) begin
                    ppx[p]  <= {eng_x, 8'd0};
                    ppy[p]  <= {eng_y, 8'd0};
                    pvx[p]  <= pvx0(p);
                    pvy[p]  <= pvy0(p);
                    page[p] <= 6'd0;
                end
                palive <= {NPART{1'b1}};
            end else begin
                // PHYSICS: move, then gravity pulls vy down. Die at CUT_PART_LIFE.
                for (p = 0; p < NPART; p = p + 1)
                    if (palive[p]) begin
                        ppx[p]  <= ppx[p] + pvx[p];
                        ppy[p]  <= ppy[p] + pvy[p];
                        pvy[p]  <= pvy[p] + CUT_PART_GRAVITY;
                        page[p] <= page[p] + 1'b1;
                        if (page[p] == CUT_PART_LIFE - 1) palive[p] <= 1'b0;
                    end
            end

            // SMOKE: every puff drifts back 1 px and ages; a new puff is
            // written over the oldest slot every 8 ticks once scene 4 starts.
            for (p = 0; p < NSMOKE; p = p + 1)
                if (salive[p]) begin
                    smx[p]  <= smx[p] - 8'sd1;
                    sage[p] <= sage[p] + 1'b1;
                    if (sage[p] == CUT_SMOKE_LIFE - 1) salive[p] <= 1'b0;
                end
            if (t >= CUT_S3_END && t[CUT_SMOKE_BIT-1:0] == 0) begin
                smx[sm_next]    <= eng_x - 8'sd2;
                smy[sm_next]    <= eng_y;
                sage[sm_next]   <= 6'd0;
                salive[sm_next] <= 1'b1;
                sm_next         <= sm_next + 1'b1;
            end
        end
    end

    // Scene number from the timeline
    wire [2:0] scene = (t < CUT_S1_END) ? 3'd1 : (t < CUT_S2_END) ? 3'd2 :
                       (t < CUT_S3_END) ? 3'd3 : (t < CUT_S4_END) ? 3'd4 : 3'd5;
    // Ticks since scene 3 began (drives the cloud scroll)
    wire [10:0] ts = t - CUT_S2_END;

    // Setting from level: 0 day (1, 3), 1 night city (2, 4), 2 sunset (5)
    wire [1:0] setting = (level == 3'd5) ? 2'd2 : (level[0] ? 2'd0 : 2'd1);

    // =================================================================
    // SPRITE ROMS (generated from ASCII art by tools/gen_cutscene_sprites.py)
    // Row r of a sprite is one wide constant; column c sits in bits
    // [5c+4 : 5c] as a 5-bit palette index (0 = transparent).
    // =================================================================
    // BEGIN GENERATED SPRITES
    // (generated -- edit gen_cutscene_sprites.py, not this block)
    function [199:0] spr_jet_row;
        input [3:0] r;
        case (r)
            4'd0: spr_jet_row = 200'h0000000000000000000000000000000000000000000005AD60;
            4'd1: spr_jet_row = 200'h00000000000000000000000000000000000000000000B5AD60;
            4'd2: spr_jet_row = 200'h00000000000000000000000000000000000000000016B5AC20;
            4'd3: spr_jet_row = 200'h000000000000000000000000000000000000000002D6B58820;
            4'd4: spr_jet_row = 200'h00000004210842108421084210842108421084210AD6210400;
            4'd5: spr_jet_row = 200'h00001088421084210842108421084210842108421084210400;
            4'd6: spr_jet_row = 200'h0002E708421044711C4711C4711C4711C4711C4711C4210400;
            4'd7: spr_jet_row = 200'h00442108421044210842108421084210842108421084210400;
            4'd8: spr_jet_row = 200'h0896B5AD6B5856B5AD6B5AD6B5AD6B5AD6B5AD6B5AD6B58400;
            4'd9: spr_jet_row = 200'h00442108421044210842108421084210842108421084208000;
            4'd10: spr_jet_row = 200'h00030842108421084210842108421084210842108420100000;
            4'd11: spr_jet_row = 200'h00001084210842108421084210842108421084210842000000;
            4'd12: spr_jet_row = 200'h00000000000000000000000018C6318C420000000000000000;
            4'd13: spr_jet_row = 200'h00000000000000000000000018C6318C420000000000000000;
            4'd14: spr_jet_row = 200'h00000000000040000000000000842108400000000000000000;
            4'd15: spr_jet_row = 200'h00000000000040000000000000040008000000000000000000;
            default: spr_jet_row = 200'd0;
        endcase
    endfunction
    function [19:0] spr_pas_row;
        input [3:0] r;
        case (r)
            4'd0: spr_pas_row = 20'h02100;
            4'd1: spr_pas_row = 20'h02100;
            4'd2: spr_pas_row = 20'hFFFDF;
            4'd3: spr_pas_row = 20'h47FC8;
            4'd4: spr_pas_row = 20'h07FE0;
            4'd5: spr_pas_row = 20'h01CE0;
            4'd6: spr_pas_row = 20'h01CE0;
            4'd7: spr_pas_row = 20'h00420;
            4'd8: spr_pas_row = 20'h02100;
            4'd9: spr_pas_row = 20'h02100;
            4'd10: spr_pas_row = 20'hFFFDF;
            4'd11: spr_pas_row = 20'h47FC8;
            4'd12: spr_pas_row = 20'h07FE0;
            4'd13: spr_pas_row = 20'h01CE0;
            4'd14: spr_pas_row = 20'h38007;
            4'd15: spr_pas_row = 20'h08001;
            default: spr_pas_row = 20'd0;
        endcase
    endfunction
    function [59:0] spr_cls_row;
        input [1:0] r;
        case (r)
            2'd0: spr_cls_row = 60'h0000000C6318000;
            2'd1: spr_cls_row = 60'h00C6318C6318C60;
            2'd2: spr_cls_row = 60'h18C6318C6318C63;
            2'd3: spr_cls_row = 60'h0006318C6318C00;
            default: spr_cls_row = 60'd0;
        endcase
    endfunction
    function [99:0] spr_clb_row;
        input [2:0] r;
        case (r)
            3'd0: spr_clb_row = 100'h00000000000006318C0000000;
            3'd1: spr_clb_row = 100'h000000006318C6318C6318000;
            3'd2: spr_clb_row = 100'h0000318C6318C6318C6318C00;
            3'd3: spr_clb_row = 100'h00C6318C6318C6318C6318C60;
            3'd4: spr_clb_row = 100'h18C6318C6318C6318C6318C63;
            3'd5: spr_clb_row = 100'h00C6318C6318C6318C6318C60;
            3'd6: spr_clb_row = 100'h0000318C6318C6318C6318000;
            default: spr_clb_row = 100'd0;
        endcase
    endfunction
    function [49:0] spr_ff_row;
        input [2:0] r;
        case (r)
            3'd0: spr_ff_row = 50'h1020042108048;
            3'd1: spr_ff_row = 50'h0021210840840;
            3'd2: spr_ff_row = 50'h0000084B10000;
            3'd3: spr_ff_row = 50'h0000084B10000;
            3'd4: spr_ff_row = 50'h00001CE738000;
            3'd5: spr_ff_row = 50'h00039C0039C00;
            3'd6: spr_ff_row = 50'h0073800001CE0;
            3'd7: spr_ff_row = 50'h0010000000020;
            default: spr_ff_row = 50'd0;
        endcase
    endfunction
    // END GENERATED SPRITES

    // Far / near cloud lanes for scene 3+ (base x, y)
    function [7:0] far_base;  input [1:0] i;
        case (i) 2'd0: far_base = 8'd10; 2'd1: far_base = 8'd52; default: far_base = 8'd95; endcase
    endfunction
    function [5:0] far_y;     input [1:0] i;
        case (i) 2'd0: far_y = 6'd6;  2'd1: far_y = 6'd30; default: far_y = 6'd44; endcase
    endfunction
    function [7:0] near_base; input i; near_base = i ? 8'd100 : 8'd30; endfunction
    function [5:0] near_y;    input i; near_y    = i ? 6'd52  : 6'd1;  endfunction

    // Shirt colour per passenger (hero wears white with a red tie)
    function [4:0] shirt; input [1:0] p;
        case (p) 2'd0: shirt = P_BROWN; 2'd1: shirt = P_CYAN; 2'd2: shirt = P_GREY; default: shirt = P_WHITE; endcase
    endfunction

    function signed [9:0] ext8; input [7:0] v; ext8 = {{2{v[7]}}, v}; endfunction

    // Particle colour by age: hot gold -> orange -> red -> cooling grey
    function [4:0] part_colour; input [5:0] age;
        part_colour = (age < 8) ? P_GOLD : (age < 16) ? P_ORANGE : (age < 26) ? P_RED : P_GREY;
    endfunction

    // =================================================================
    // 5A. GEOMETRY STAGE: is this pixel inside each object? where?
    // =================================================================
    // Screen shake (scene 4): sample the picture 2 px left/right on
    // alternate ticks, so the whole image jolts.
    wire shaking = (t >= CUT_S3_END) && (t < CUT_S3_END + CUT_SHAKE_TICKS);
    wire signed [9:0] shake = !shaking ? 10'sd0 : (t[0] ? CUT_SHAKE_PX : -CUT_SHAKE_PX);
    wire signed [9:0] sx = $signed({3'b000, pixel_x}) - shake;
    wire signed [9:0] sy = {4'b0000, pixel_y};

    reg  [6:0]  a_x;   reg [5:0] a_y;   reg [2:0] a_scene;  reg [1:0] a_set;
    reg         a_jet_in;  reg [5:0] a_jet_rx;  reg [3:0] a_jet_ry;
    reg  [3:0]  a_p_in, a_p_frm;  reg [7:0] a_p_rx;  reg [11:0] a_p_ry;   // 4 passengers
    reg         a_stair, a_truck, a_wheel;
    reg  [2:0]  a_cs_in;  reg [11:0] a_cs_rx;  reg [5:0] a_cs_ry;         // 3 small clouds
    reg  [1:0]  a_cb_in;  reg [9:0]  a_cb_rx;  reg [5:0] a_cb_ry;         // 2 big clouds
    reg         a_ff_in;  reg [3:0]  a_ff_rx;  reg [2:0] a_ff_ry;         // hero, freefall pose
    reg  [4:0]  a_part, a_smoke;                                          // explosion colours
    reg         a_flash;

    reg signed [9:0] rx, ry, cx, adx, ady;
    reg [4:0] hit;
    always @(posedge clk) begin
        a_x <= pixel_x;  a_y <= pixel_y;  a_scene <= scene;  a_set <= setting;

        // Jet
        rx = sx - ext8(ox[OBJ_JET][15:8]);
        ry = sy - ext8(oy[OBJ_JET][15:8]);
        a_jet_in <= (rx >= 0) && (rx < JET_W) && (ry >= 0) &&
                    (ry < ((scene == 3'd1) ? JET_H : JET_H_AIR));   // gear up once airborne
        a_jet_rx <= rx[5:0];  a_jet_ry <= ry[3:0];

        // Passengers (objects 2..5)
        for (k = 0; k < 4; k = k + 1) begin
            rx = sx - ext8(ox[OBJ_P0 + k][15:8]);
            ry = sy - ext8(oy[OBJ_P0 + k][15:8]);
            a_p_in[k]         <= vis[OBJ_P0 + k] && (rx >= 0) && (rx < PAS_W) && (ry >= 0) && (ry < PAS_H);
            a_p_rx[k*2 +: 2]  <= rx[1:0];
            a_p_ry[k*3 +: 3]  <= ry[2:0];
            a_p_frm[k]        <= (cnt[OBJ_P0 + k] != 0) && t[CUT_WALK_BIT];   // legs swap while moving
        end

        // Stair truck: a 45-degree band where x + y is constant, plus chassis and wheels
        rx = sx - ext8(ox[OBJ_STAIRS][15:8]);
        a_stair <= (rx + sy >= STAIR_SUM) && (rx + sy <= STAIR_SUM + 3) &&
                   (sy >= STAIR_TOP_Y) && (sy <= STAIR_FOOT_Y);
        a_truck <= (rx >= 46) && (rx <= 58) && (sy >= 49) && (sy <= 52);
        a_wheel <= (sy >= 53) && (sy <= 54) && (((rx >= 48) && (rx <= 49)) || ((rx >= 55) && (rx <= 56)));

        // Small (far) clouds: x = ((base - ts/2) mod 128) - 16 -> slow, wraps around
        for (k = 0; k < 3; k = k + 1) begin
            cx = {3'b000, far_base(k) - ts[7:1]} & 10'h07F;
            cx = cx - 10'sd16;
            rx = sx - cx;  ry = sy - {4'b0000, far_y(k)};
            a_cs_in[k]       <= (rx >= 0) && (rx < CLS_W) && (ry >= 0) && (ry < CLS_H);
            a_cs_rx[k*4 +: 4] <= rx[3:0];
            a_cs_ry[k*2 +: 2] <= ry[1:0];
        end
        // Big (near) clouds: twice as fast -> parallax depth
        for (k = 0; k < 2; k = k + 1) begin
            cx = {3'b000, near_base(k) - ts[7:0]} & 10'h07F;
            cx = cx - 10'sd24;
            rx = sx - cx;  ry = sy - {4'b0000, near_y(k)};
            a_cb_in[k]       <= (rx >= 0) && (rx < CLB_W) && (ry >= 0) && (ry < CLB_H);
            a_cb_rx[k*5 +: 5] <= rx[4:0];
            a_cb_ry[k*3 +: 3] <= ry[2:0];
        end

        // Hero in freefall pose (scene 5)
        rx = sx - ext8(ox[OBJ_HERO_FF][15:8]);
        ry = sy - ext8(oy[OBJ_HERO_FF][15:8]);
        a_ff_in <= vis[OBJ_HERO_FF] && (rx >= 0) && (rx < FF_W) && (ry >= 0) && (ry < FF_H);
        a_ff_rx <= rx[3:0];  a_ff_ry <= ry[2:0];

        // Particles: each is a 2x2 dot, coloured by its age
        hit = P_TRANS;
        for (k = 0; k < NPART; k = k + 1) begin
            rx = sx - ext8(ppx[k][15:8]);
            ry = sy - ext8(ppy[k][15:8]);
            if (palive[k] && (rx >= 0) && (rx < 2) && (ry >= 0) && (ry < 2))
                hit = part_colour(page[k]);
        end
        a_part <= hit;

        // Smoke puffs: a diamond |dx| + |dy| <= r, growing with age
        hit = P_TRANS;
        for (k = 0; k < NSMOKE; k = k + 1) begin
            rx  = sx - ext8(smx[k]);
            ry  = sy - ext8(smy[k]);
            adx = rx[9] ? -rx : rx;
            ady = ry[9] ? -ry : ry;
            if (salive[k] && (adx + ady <= 1 + sage[k][5:4]))
                hit = (sage[k] < 16) ? P_GREY : P_SILVER;
        end
        a_smoke <= hit;

        // 3-frame white flash at the explosion
        a_flash <= (t >= CUT_S3_END) && (t < CUT_S3_END + CUT_FLASH_TICKS);
    end

    // =================================================================
    // 5B. SPRITE STAGE: read ROMs, choose the front-most colour
    // =================================================================
    wire [JET_W*5-1:0] jrow = spr_jet_row(a_jet_ry);
    wire [4:0] jet_pix = a_jet_in ? jrow[a_jet_rx*5 +: 5] : P_TRANS;
    wire [FF_W*5-1:0] frow = spr_ff_row(a_ff_ry);
    wire [4:0] ff_pix  = a_ff_in ? frow[a_ff_rx*5 +: 5] : P_TRANS;

    reg [4:0] pas_pix, cs_pix, cb_pix, v;
    reg [PAS_W*5-1:0] prow;  reg [CLS_W*5-1:0] srow;  reg [CLB_W*5-1:0] brow;
    integer j;
    always @* begin
        // Passengers: lower number drawn in front
        pas_pix = P_TRANS;
        for (j = 3; j >= 0; j = j - 1)
            if (a_p_in[j]) begin
                prow = spr_pas_row({a_p_frm[j], a_p_ry[j*3 +: 3]});
                v    = prow[a_p_rx[j*2 +: 2]*5 +: 5];
                if (v == P_SHIRT)    v = shirt(j);
                else if (v == P_TIE) v = (j == 3) ? P_RED : shirt(j);
                if (v != P_TRANS) pas_pix = v;
            end
        // Clouds
        cs_pix = P_TRANS;
        for (j = 0; j < 3; j = j + 1)
            if (a_cs_in[j]) begin
                srow = spr_cls_row(a_cs_ry[j*2 +: 2]);
                v    = srow[a_cs_rx[j*4 +: 4]*5 +: 5];
                if (v != P_TRANS) cs_pix = v;
            end
        cb_pix = P_TRANS;
        for (j = 0; j < 2; j = j + 1)
            if (a_cb_in[j]) begin
                brow = spr_clb_row(a_cb_ry[j*3 +: 3]);
                v    = brow[a_cb_rx[j*5 +: 5]*5 +: 5];
                if (v != P_TRANS) cb_pix = v;
            end
    end

    // Scene 1 background: sky, ground band (trees / lit windows), tarmac
    wire [4:0] bg1 =
        (a_y < S1_GROUND_Y)  ? P_SKY :
        (a_y < S1_TARMAC_Y)  ? (((a_x[2:1] == 2'b01) && (a_y >= S1_GROUND_Y + 2) && (a_y <= S1_GROUND_Y + 5))
                                ? P_DETAIL : P_GROUND) :
        ((a_y == S1_LINE_Y) && !a_x[3]) ? P_GOLD : P_TARMAC;

    reg [4:0] b_idx = 5'd0;  reg [1:0] b_set = 2'd0;
    always @(posedge clk) begin
        b_set <= a_set;
        case (a_scene)
            3'd1:  b_idx <= (pas_pix != P_TRANS) ? pas_pix :
                            a_stair ? (a_y[0] ? P_SILVER : P_STEEL) :
                            a_wheel ? P_BLACK :
                            a_truck ? P_STEEL :
                            (jet_pix != P_TRANS) ? jet_pix : bg1;
            3'd2:  b_idx <= P_CABIN;                                  // CP3: briefing
            // Scenes 3-5, front to back: flash, particles, hero, near clouds,
            // jet, smoke, far clouds, sky
            default: b_idx <= a_flash                ? P_WHITE :
                              (a_part  != P_TRANS)   ? a_part  :
                              (ff_pix  != P_TRANS)   ? ff_pix  :
                              (cb_pix  != P_TRANS)   ? cb_pix  :
                              (jet_pix != P_TRANS)   ? jet_pix :
                              (a_smoke != P_TRANS)   ? a_smoke :
                              (cs_pix  != P_TRANS)   ? cs_pix  : P_SKY;
        endcase
    end

    // =================================================================
    // 5C. PALETTE STAGE (ICD colour table; setting-dependent 3, 4, 12, 13, 15)
    // TODO(integration): replace with Member 3's palette.v once its ports
    // are known, so the palette exists in exactly one place.
    // =================================================================
    function [15:0] pal;
        input [4:0] idx;  input [1:0] set;
        case (idx)
            5'd1:  pal = 16'h0000;
            5'd2:  pal = 16'hFFFF;
            5'd3:  pal = (set == 2'd0) ? 16'hDEDB : (set == 2'd1) ? 16'h298A : 16'hF518;
            5'd4:  pal = (set == 2'd1) ? 16'hC618 : 16'h528A;
            5'd5:  pal = 16'hFC60;
            5'd6:  pal = 16'hC280;
            5'd7:  pal = 16'h194D;
            5'd8:  pal = 16'hF612;
            5'd9:  pal = 16'h8AC5;
            5'd10: pal = 16'hFEA0;
            5'd11: pal = 16'hE104;
            5'd12: pal = (set == 2'd0) ? 16'h3506 : (set == 2'd1) ? 16'h39C8 : 16'h11C3;
            5'd13: pal = (set == 2'd0) ? 16'h1B43 : (set == 2'd1) ? 16'hFEA0 : 16'h0000;
            5'd14: pal = 16'h371E;
            5'd15: pal = (set == 2'd0) ? 16'h4D5F : (set == 2'd1) ? 16'h0885 : 16'h69D1;
            5'd16: pal = 16'hCE7A;
            5'd17: pal = 16'h7C11;
            5'd18: pal = 16'hEE4F;
            5'd19: pal = 16'h2709;
            5'd20: pal = 16'hDE98;
            5'd21: pal = 16'h5AEC;
            default: pal = 16'h0000;
        endcase
    endfunction

    always @(posedge clk) oled_data_cut <= pal(b_idx, b_set);
endmodule
