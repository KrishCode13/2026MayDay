// =====================================================================
// game_params.vh  --  MAYDAY shared constants (EE2026 I-FDP)
// Owner: Member 4. Every module includes it INSIDE its module body:
//     module xyz (...);
//         `include "game_params.vh"
// RULE: no tuning number is hard-coded anywhere else. Change it HERE.
// Units: Q8.8 = value x 256 (signed 16-bit). Altitude = Q16.8 (24-bit),
//        whole metres = altitude[23:8].
// =====================================================================

// ---------------- Game states (game_state[3:0]) ----------------------
localparam [3:0] S_HOME            = 4'd0;
localparam [3:0] S_CUTSCENE        = 4'd1;
localparam [3:0] S_LEVEL_INTRO     = 4'd2;
localparam [3:0] S_FREEFALL_LOCKED = 4'd3;
localparam [3:0] S_FREEFALL_WINDOW = 4'd4;
localparam [3:0] S_CANOPY          = 4'd5;
localparam [3:0] S_FINAL_APPROACH  = 4'd6;
localparam [3:0] S_LANDING         = 4'd7;
localparam [3:0] S_CRASH           = 4'd8;
localparam [3:0] S_LEVEL_COMPLETE  = 4'd9;
localparam [3:0] S_LEVEL_FAILED    = 4'd10;
localparam [3:0] S_VICTORY         = 4'd11;

// ---------------- Enumerations ----------------------------------------
localparam [1:0] CM_FREEFALL = 2'd0, CM_OPEN = 2'd1, CM_BRAKING = 2'd2, CM_STALLED = 2'd3; // canopy_mode
localparam [1:0] DG_NONE = 2'd0, DG_EARLY = 2'd1, DG_PERFECT = 2'd2, DG_LATE = 2'd3;      // deploy_grade
localparam [1:0] CC_COLLAPSE = 2'd0, CC_EDGE = 2'd1, CC_MISSED_FLARE = 2'd2;               // crash_cause
localparam [1:0] FR_TOO_LATE = 2'd0, FR_LINES_CUT = 2'd1, FR_TURBULENCE = 2'd2, FR_HARD_IMPACT = 2'd3; // fail_reason
localparam [1:0] OBS_EMPTY = 2'd0, OBS_BIRD = 2'd1, OBS_PLANE = 2'd2, OBS_DEBRIS = 2'd3;   // obs_type

// ---------------- Screen / geometry -----------------------------------
localparam SCREEN_W       = 96;
localparam SCREEN_H       = 64;
localparam HERO_REST_X    = 40;
localparam HERO_REST_Y    = 10;
localparam HERO_FRAME_W   = 16;
localparam HERO_FRAME_H   = 20;
localparam EDGE_LEFT_MAX  = 2;    // hitbox pixel x <= 2  -> turbulence death
localparam EDGE_RIGHT_MIN = 93;   // hitbox pixel x >= 93 -> turbulence death
localparam GROUND_LOCK_Y  = 54;   // camera locks when ground top reaches this y
localparam BRAKE_MAX_RISE = 8;    // px above rest

// Hitboxes: offset (x,y) from sprite/frame top-left, size (w,h)
localparam HB_CANOPY_X = 1,  HB_CANOPY_Y = 0,  HB_CANOPY_W = 14, HB_CANOPY_H = 5;
localparam HB_BODY_X   = 6,  HB_BODY_Y   = 12, HB_BODY_W   = 4,  HB_BODY_H   = 8;
localparam HB_FF_X     = 4,  HB_FF_Y     = 13, HB_FF_W     = 8,  HB_FF_H     = 6;  // freefall box, in hero frame
localparam FF_SPRITE_X = 3,  FF_SPRITE_Y = 12;                                     // freefall sprite offset in frame
localparam HB_BIRD_X   = 1,  HB_BIRD_Y   = 1,  HB_BIRD_W   = 6,  HB_BIRD_H   = 4;
localparam HB_PLANE_X  = 1,  HB_PLANE_Y  = 2,  HB_PLANE_W  = 22, HB_PLANE_H  = 5;
localparam HB_DEBRIS_X = 1,  HB_DEBRIS_Y = 1,  HB_DEBRIS_W = 4,  HB_DEBRIS_H = 4;
localparam BIRD_W = 8, BIRD_H = 6, PLANE_W = 24, PLANE_H = 8, DEBRIS_W = 6, DEBRIS_H = 6;
localparam CRATE_W = 6, CRATE_H = 9;
localparam SPOT_W = 16;
localparam TARGET_X_MIN = 8, TARGET_X_MAX = 72;
localparam FLARE_LANE_X = 86;     // lane occupies x 86..91

// ---------------- Physics (Member 1), Q8.8 -----------------------------
localparam signed [15:0] V_FREEFALL   = 16'sd512;  // 2.0 px/tick
localparam signed [15:0] GRAVITY      = 16'sd13;   // 0.05 px/tick^2
localparam signed [15:0] V_CANOPY     = 16'sd128;  // 0.5
localparam signed [15:0] V_DAMAGE     = 16'sd64;   // +0.25 per snapped line
localparam signed [15:0] V_STALL      = 16'sd384;  // 1.5
localparam signed [15:0] STEER_ACC    = 16'sd8;    // 0.03 (half in freefall)
localparam               DRAG_SHIFT   = 4;         // vx = vx - (vx >>> 4)
localparam signed [15:0] GUST_ACC_1   = 16'sd4;    // 0.015
localparam signed [15:0] GUST_ACC_2   = 16'sd8;    // 0.03
localparam signed [15:0] GUST_ACC_3   = 16'sd12;   // 0.045
localparam signed [15:0] BRAKE_RISE   = 16'sd128;  // 0.5 px/tick up
localparam signed [15:0] BRAKE_RETURN = 16'sd32;   // 0.125 px/tick back
localparam signed [15:0] DRIFT_ACC    = 16'sd3;    // 0.01 toward damaged side
localparam OPEN_TICKS      = 60;
localparam GUST_TICKS      = 60;
localparam GUST_WARN_TICKS = 30;
localparam STALL_HOLD      = 60;
localparam STALL_TICKS     = 60;
localparam [15:0] LFSR_CONST_M1 = 16'hA5A5;

// ---------------- Altitudes (whole metres; compare with altitude[23:8]) --
localparam [15:0] ALT_START        = 16'd2000;
localparam [15:0] ALT_UNLOCK       = 16'd1700;
localparam [15:0] ALT_PERFECT_HI   = 16'd1550;
localparam [15:0] ALT_PERFECT_LO   = 16'd1450;
localparam [15:0] ALT_TOO_LATE     = 16'd1400;
localparam [15:0] ALT_FINAL        = 16'd150;
localparam [15:0] FLARE_SOFT_HI    = 16'd15;
localparam [15:0] FLARE_SOFT_LO    = 16'd5;
localparam [15:0] FLARE_HARD_HI    = 16'd25;   // hard window: 25..15 and 5..1
localparam [15:0] FLARE_HARD_LO    = 16'd1;

// ---------------- World (Member 2) --------------------------------------
localparam signed [15:0] CRATE_FALL   = 16'sd64;   // 0.25
localparam signed [15:0] BIRD_VX      = 16'sd77;   // ~0.3
localparam signed [15:0] PLANE_VX     = 16'sd384;  // 1.5
localparam signed [15:0] DEBRIS_VY    = 16'sd256;  // 1.0 down-screen
localparam signed [15:0] MAGNET_FAR   = 16'sd64;   // 0.25 (Manhattan 16..32)
localparam signed [15:0] MAGNET_NEAR  = 16'sd192;  // 0.75 (Manhattan < 16)
localparam MAGNET_TICKS      = 300;
localparam WARN_TICKS        = 60;
localparam CRATE_SPAWN_RANGE = 32;   // spawn within +/-32 px of hero_x
localparam CRATE_X_MIN = 8, CRATE_X_MAX = 82;
localparam [15:0] LFSR_CONST_M2 = 16'h5A5A;
// Difficulty table (per level 1..5) is implemented by Member 2 as a
// case statement on `level`; values are in docs/ICD.md "Difficulty table".

// ---------------- Inputs (Member 4, input_ctrl.v) ------------------------
// Define FAST_SIM in a testbench to shrink "1 ms" to 100 cycles (1000x
// faster sim). Never define it in Vivado synthesis.
`ifdef FAST_SIM
localparam SAMPLE_CYCLES    = 100;      // sim: 1 "ms" = 100 clk cycles
`else
localparam SAMPLE_CYCLES    = 100000;   // 1 ms at 100 MHz (must be < 131072)
`endif
localparam DEBOUNCE_SAMPLES = 5;        // 5 equal 1 ms samples to change a held level
localparam LOCKOUT_MS       = 200;      // min 200 ms between press pulses (<= 255)

// ---------------- Director menus (Member 4, game_director.v) -------------
localparam NUM_LEVELS = 5;
localparam [2:0] MC_NEXT  = 3'd0, MC_RETRY = 3'd1, MC_HOME = 3'd2;  // LEVEL_COMPLETE cursor
localparam [2:0] MF_RETRY = 3'd0, MF_HOME  = 3'd1;                  // LEVEL_FAILED cursor

// ---------------- Seven-segment (Member 4, seg7_ctrl.v) ------------------
`ifdef FAST_SIM
localparam SEG_REFRESH_BITS = 6;        // sim: 16 cycles per digit
localparam SEG_SPIN_CYCLES  = 200;      // sim: spin-down step
`else
localparam SEG_REFRESH_BITS = 18;       // top 2 bits pick the digit: 0.66 ms each, ~380 Hz
localparam SEG_SPIN_CYCLES  = 2000000;  // 20 ms per crash spin-down step
`endif
localparam SEG_SPIN_SHIFT   = 3;        // each step removes value/8 + 1
localparam SEG_MAX_VALUE    = 9999;     // 4 digits; larger values are clamped

// ---------------- LEDs (Member 4, led_ctrl.v) ----------------------------
localparam LED_CHASE_BIT = 3;           // chaser steps every 2^3 = 8 ticks (~133 ms)
localparam LED_FLASH_BIT = 2;           // flashing toggles every 2^2 = 4 ticks (~7.5 Hz)
localparam WIND_LEN_1 = 3, WIND_LEN_2 = 5, WIND_LEN_3 = 8;   // LEDs lit per gust strength

// ---------------- Cutscene timeline (Member 4, cutscene_engine.v) --------
// Scene n runs from the previous end tick up to CUT_Sn_END (60 ticks = 1 s).
localparam CUT_S1_END = 300;            // 1 Boarding   5 s
localparam CUT_S2_END = 660;            // 2 Briefing   6 s
localparam CUT_S3_END = 900;            // 3 Flight     4 s
localparam CUT_S4_END = 1140;           // 4 Explosion  4 s
localparam CUT_TOTAL  = 1260;           // 5 Jump       2 s  (21 s total)
localparam CUT_WALK_BIT = 2;            // walking legs swap every 2^2 = 4 ticks
localparam CUT_FLASH_TICKS = 3;         // white flash frames at the explosion
localparam CUT_SHAKE_TICKS = 30;        // screen shake length after the explosion
localparam CUT_SHAKE_PX    = 2;         // shake offset, +/- px
localparam CUT_PART_LIFE   = 36;        // particle lifetime, ticks
localparam signed [15:0] CUT_PART_GRAVITY = 16'sd16;  // 0.0625 px/tick^2 added to vy (Q8.8)
localparam CUT_SMOKE_BIT   = 3;         // one smoke puff every 2^3 = 8 ticks
localparam CUT_SMOKE_LIFE  = 63;        // smoke puff lifetime, ticks

// ---------------- Timed states (ticks) ---------------------------------
localparam T_LEVEL_INTRO   = 120;
localparam T_CRASH_PLUNGE  = 120;
localparam T_CRASH_IMPACT  = 30;
localparam T_LANDING       = 90;
localparam T_STAR1 = 30, T_STAR2 = 60, T_STAR3 = 90;
localparam T_SHAKE         = 10;
localparam T_SPARKLE       = 10;
