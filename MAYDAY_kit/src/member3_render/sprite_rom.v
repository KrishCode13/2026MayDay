// =====================================================================
// sprite_rom.v  --  MEMBER 3 (Unified Sprite & HUD Icon ROM)
// Stores 5-bit palette indices (0 = transparent).
// Includes explicit POSE_TUG_FLARE (3'd7), high-contrast Bird,
// flaming Plane Debris, and Parachute Crate sprites.
// =====================================================================
module sprite_rom (
    input  wire [2:0] hero_pose,
    input  wire       hero_mirror,
    input  wire [3:0] hero_col,
    input  wire [4:0] hero_row,
    output reg  [4:0] hero_color,

    input  wire [1:0] obs_sel_type,
    input  wire       obs_sel_frame,
    input  wire       obs_sel_flip,
    input  wire [4:0] obs_col,
    input  wire [2:0] obs_row,
    output reg  [4:0] obs_color,

    input  wire [2:0] crate_col,
    input  wire [3:0] crate_row,
    output reg  [4:0] crate_color,

    input  wire [2:0] icon_id,
    input  wire [3:0] icon_col,
    input  wire [3:0] icon_row,
    output reg  [4:0] icon_color
);

    localparam [4:0] __ = 5'd0,  KK = 5'd1,  WW = 5'd2,  GG = 5'd4,
                     OO = 5'd5,  DD = 5'd6,  NN = 5'd7,  SS = 5'd8,
                     BB = 5'd9,  YY = 5'd10, RR = 5'd11, CC = 5'd14,
                     VV = 5'd16, TT = 5'd17;

    localparam [2:0] POSE_FREEFALL  = 3'd0,
                     POSE_OPEN_1    = 3'd1,
                     POSE_OPEN_2    = 3'd2,
                     POSE_FULL      = 3'd3,
                     POSE_DMG_FLAP1 = 3'd4,
                     POSE_DMG_FLAP2 = 3'd5,
                     POSE_CRUMPLED  = 3'd6,
                     POSE_TUG_FLARE = 3'd7;

    // 1. HERO SPRITE ROM
    wire [3:0] h_col_eff = hero_mirror ? (4'd15 - hero_col) : hero_col;
    reg  [79:0] hero_row_bits;

    always @* begin
        hero_row_bits = 80'd0;
        case (hero_pose)
            POSE_FREEFALL: begin
                case (hero_row)
                    5'd12: hero_row_bits = {__,__,__, SS,WW,__,KK,KK,KK,KK,__,WW,SS, __,__,__};
                    5'd13: hero_row_bits = {__,__,__, __,WW,WW,SS,SS,SS,SS,WW,WW,__, __,__,__};
                    5'd14: hero_row_bits = {__,__,__, __,__,__,WW,RR,WW,WW,__,__,__, __,__,__};
                    5'd15: hero_row_bits = {__,__,__, __,__,__,WW,RR,WW,WW,__,__,__, __,__,__};
                    5'd16: hero_row_bits = {__,__,__, __,__,__,NN,NN,NN,NN,__,__,__, __,__,__};
                    5'd17: hero_row_bits = {__,__,__, __,__,NN,NN,__,__,NN,NN,__,__, __,__,__};
                    5'd18: hero_row_bits = {__,__,__, __,NN,NN,__,__,__,__,NN,NN,__, __,__,__};
                    5'd19: hero_row_bits = {__,__,__, __,KK,__,__,__,__,__,__,KK,__, __,__,__};
                    default: hero_row_bits = 80'd0;
                endcase
            end
            POSE_OPEN_1: begin
                case (hero_row)
                    5'd6:  hero_row_bits = {__,__,__,__,__,__,KK,KK,KK,KK,__,__,__,__,__,__};
                    5'd7:  hero_row_bits = {__,__,__,__,__,KK,OO,OO,OO,OO,KK,__,__,__,__,__};
                    5'd8:  hero_row_bits = {__,__,__,__,__,KK,DD,OO,OO,DD,KK,__,__,__,__,__};
                    5'd9:  hero_row_bits = {__,__,__,__,__,__,GG,__,__,GG,__,__,__,__,__,__};
                    5'd10: hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd11: hero_row_bits = {__,__,__,__,__,SS,__,__,__,__,SS,__,__,__,__,__};
                    5'd12: hero_row_bits = {__,__,__,__,__,WW,KK,KK,KK,KK,WW,__,__,__,__,__};
                    5'd13: hero_row_bits = {__,__,__,__,__,WW,SS,SS,SS,SS,WW,__,__,__,__,__};
                    5'd14: hero_row_bits = {__,__,__,__,__,__,WW,WW,WW,WW,__,__,__,__,__,__};
                    5'd15: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd16: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd17: hero_row_bits = {__,__,__,__,__,__,NN,NN,NN,NN,__,__,__,__,__,__};
                    5'd18: hero_row_bits = {__,__,__,__,__,__,NN,__,__,NN,__,__,__,__,__,__};
                    5'd19: hero_row_bits = {__,__,__,__,__,__,KK,__,__,KK,__,__,__,__,__,__};
                    default: hero_row_bits = 80'd0;
                endcase
            end
            POSE_OPEN_2: begin
                case (hero_row)
                    5'd2:  hero_row_bits = {__,__,__,__,KK,KK,KK,KK,KK,KK,KK,KK,__,__,__,__};
                    5'd3:  hero_row_bits = {__,__,__,KK,OO,OO,DD,OO,OO,DD,OO,OO,KK,__,__,__};
                    5'd4:  hero_row_bits = {__,__,__,KK,DD,DD,DD,DD,DD,DD,DD,DD,KK,__,__,__};
                    5'd5:  hero_row_bits = {__,__,__,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,__,__,__};
                    5'd6:  hero_row_bits = {__,__,__,__,GG,__,__,__,__,__,__,GG,__,__,__,__};
                    5'd7:  hero_row_bits = {__,__,__,__,GG,__,__,__,__,__,__,GG,__,__,__,__};
                    5'd8:  hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd9:  hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd10: hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd11: hero_row_bits = {__,__,__,__,__,SS,__,__,__,__,SS,__,__,__,__,__};
                    5'd12: hero_row_bits = {__,__,__,__,__,WW,KK,KK,KK,KK,WW,__,__,__,__,__};
                    5'd13: hero_row_bits = {__,__,__,__,__,WW,SS,SS,SS,SS,WW,__,__,__,__,__};
                    5'd14: hero_row_bits = {__,__,__,__,__,__,WW,WW,WW,WW,__,__,__,__,__,__};
                    5'd15: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd16: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd17: hero_row_bits = {__,__,__,__,__,__,NN,NN,NN,NN,__,__,__,__,__,__};
                    5'd18: hero_row_bits = {__,__,__,__,__,__,NN,__,__,NN,__,__,__,__,__,__};
                    5'd19: hero_row_bits = {__,__,__,__,__,__,KK,__,__,KK,__,__,__,__,__,__};
                    default: hero_row_bits = 80'd0;
                endcase
            end
            POSE_DMG_FLAP1: begin
                case (hero_row)
                    5'd0:  hero_row_bits = {__,__,__,__,__,__,KK,KK,KK,KK,KK,KK,KK,__,__,__};
                    5'd1:  hero_row_bits = {__,__,__,__,__,KK,OO,OO,OO,OO,OO,OO,OO,KK,__,__};
                    5'd2:  hero_row_bits = {__,__,__,__,KK,OO,OO,OO,OO,OO,DD,OO,OO,OO,KK,__};
                    5'd3:  hero_row_bits = {__,__,__,KK,OO,OO,DD,OO,OO,OO,DD,OO,OO,OO,KK,__};
                    5'd4:  hero_row_bits = {__,__,__,OO,OO,DD,DD,DD,DD,DD,DD,DD,DD,DD,KK,__};
                    5'd5:  hero_row_bits = {__,__,KK,OO,DD,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,__};
                    5'd6:  hero_row_bits = {__,__,OO,DD,KK,__,__,__,__,__,__,__,__,GG,__,__};
                    5'd7:  hero_row_bits = {__,__,OO,KK,__,__,__,__,__,__,__,__,GG,__,__,__};
                    5'd8:  hero_row_bits = {__,KK,DD,__,__,__,__,__,__,__,__,GG,__,__,__,__};
                    5'd9:  hero_row_bits = {__,KK,KK,__,__,__,__,__,__,__,GG,__,__,__,__,__};
                    5'd10: hero_row_bits = {__,KK,__,__,__,__,__,__,__,__,GG,__,__,__,__,__};
                    5'd11: hero_row_bits = {__,KK,__,__,__,SS,__,__,__,__,SS,__,__,__,__,__};
                    5'd12: hero_row_bits = {__,__,__,__,__,WW,KK,KK,KK,KK,WW,__,__,__,__,__};
                    5'd13: hero_row_bits = {__,__,__,__,__,WW,SS,SS,SS,SS,WW,__,__,__,__,__};
                    5'd14: hero_row_bits = {__,__,__,__,__,__,WW,WW,WW,WW,__,__,__,__,__,__};
                    5'd15: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd16: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd17: hero_row_bits = {__,__,__,__,__,__,NN,NN,NN,NN,__,__,__,__,__,__};
                    5'd18: hero_row_bits = {__,__,__,__,__,__,NN,__,__,NN,__,__,__,__,__,__};
                    5'd19: hero_row_bits = {__,__,__,__,__,__,KK,__,__,KK,__,__,__,__,__,__};
                    default: hero_row_bits = 80'd0;
                endcase
            end
            POSE_DMG_FLAP2: begin
                case (hero_row)
                    5'd0:  hero_row_bits = {__,__,__,__,__,KK,KK,KK,KK,KK,KK,KK,KK,__,__,__};
                    5'd1:  hero_row_bits = {__,__,__,KK,KK,OO,OO,OO,OO,OO,OO,OO,OO,KK,__,__};
                    5'd2:  hero_row_bits = {__,__,KK,OO,OO,DD,OO,OO,OO,OO,DD,OO,OO,OO,KK,__};
                    5'd3:  hero_row_bits = {__,__,OO,OO,OO,DD,OO,OO,OO,OO,DD,OO,OO,OO,KK,__};
                    5'd4:  hero_row_bits = {__,KK,OO,DD,DD,KK,DD,DD,DD,DD,DD,DD,DD,DD,KK,__};
                    5'd5:  hero_row_bits = {__,KK,OO,KK,KK,__,KK,KK,KK,KK,KK,KK,KK,KK,KK,__};
                    5'd6:  hero_row_bits = {__,KK,DD,__,__,__,__,__,__,__,__,__,__,GG,__,__};
                    5'd7:  hero_row_bits = {__,KK,KK,__,__,__,__,__,__,__,__,__,GG,__,__,__};
                    5'd8:  hero_row_bits = {__,__,__,__,__,__,__,__,__,__,__,GG,__,__,__,__};
                    5'd9:  hero_row_bits = {__,__,__,__,__,__,__,__,__,__,GG,__,__,__,__,__};
                    5'd10: hero_row_bits = {__,__,__,__,__,__,__,__,__,__,GG,__,__,__,__,__};
                    5'd11: hero_row_bits = {__,__,__,__,__,SS,__,__,__,__,SS,__,__,__,__,__};
                    5'd12: hero_row_bits = {__,__,__,__,__,WW,KK,KK,KK,KK,WW,__,__,__,__,__};
                    5'd13: hero_row_bits = {__,__,__,__,__,WW,SS,SS,SS,SS,WW,__,__,__,__,__};
                    5'd14: hero_row_bits = {__,__,__,__,__,__,WW,WW,WW,WW,__,__,__,__,__,__};
                    5'd15: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd16: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd17: hero_row_bits = {__,__,__,__,__,__,NN,NN,NN,NN,__,__,__,__,__,__};
                    5'd18: hero_row_bits = {__,__,__,__,__,__,NN,__,__,NN,__,__,__,__,__,__};
                    5'd19: hero_row_bits = {__,__,__,__,__,__,KK,__,__,KK,__,__,__,__,__,__};
                    default: hero_row_bits = 80'd0;
                endcase
            end
            POSE_CRUMPLED: begin
                case (hero_row)
                    5'd1:  hero_row_bits = {__,__,__,__,__,__,KK,KK,KK,KK,__,__,__,__,__,__};
                    5'd2:  hero_row_bits = {__,__,__,__,__,KK,OO,DD,OO,DD,KK,__,__,__,__,__};
                    5'd3:  hero_row_bits = {__,__,__,__,__,KK,DD,OO,DD,OO,KK,__,__,__,__,__};
                    5'd4:  hero_row_bits = {__,__,__,__,KK,OO,DD,KK,DD,OO,DD,KK,__,__,__,__};
                    5'd5:  hero_row_bits = {__,__,__,__,KK,KK,__,__,__,KK,KK,KK,__,__,__,__};
                    5'd6:  hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd7:  hero_row_bits = {__,__,__,__,__,__,GG,__,__,GG,__,__,__,__,__,__};
                    5'd8:  hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd9:  hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd10: hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd11: hero_row_bits = {__,__,__,__,__,SS,__,__,__,__,SS,__,__,__,__,__};
                    5'd12: hero_row_bits = {__,__,__,__,__,WW,KK,KK,KK,KK,WW,__,__,__,__,__};
                    5'd13: hero_row_bits = {__,__,__,__,__,WW,SS,SS,SS,SS,WW,__,__,__,__,__};
                    5'd14: hero_row_bits = {__,__,__,__,__,__,WW,WW,WW,WW,__,__,__,__,__,__};
                    5'd15: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd16: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd17: hero_row_bits = {__,__,__,__,__,__,NN,NN,NN,NN,__,__,__,__,__,__};
                    5'd18: hero_row_bits = {__,__,__,__,__,__,NN,__,__,NN,__,__,__,__,__,__};
                    5'd19: hero_row_bits = {__,__,__,__,__,__,KK,__,__,KK,__,__,__,__,__,__};
                    default: hero_row_bits = 80'd0;
                endcase
            end
            // #12: Explicit Tug / Flare Pose (3'd7) - Full 16-px flared canopy,
            // bright gold/white tension ribs, taut brake lines, tucked knees!
            POSE_TUG_FLARE: begin
                case (hero_row)
                    5'd0:  hero_row_bits = {__,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,__};
                    5'd1:  hero_row_bits = {KK,YY,OO,OO,YY,OO,OO,WW,WW,OO,OO,YY,OO,OO,YY,KK};
                    5'd2:  hero_row_bits = {KK,OO,OO,DD,YY,OO,OO,WW,WW,OO,OO,YY,DD,OO,OO,KK};
                    5'd3:  hero_row_bits = {KK,DD,DD,DD,DD,DD,DD,DD,DD,DD,DD,DD,DD,DD,DD,KK};
                    5'd4:  hero_row_bits = {KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK};
                    5'd5:  hero_row_bits = {__,WW,__,__,GG,__,__,__,__,__,__,GG,__,__,WW,__};
                    5'd6:  hero_row_bits = {__,__,WW,__,__,GG,__,__,__,__,GG,__,__,WW,__,__};
                    5'd7:  hero_row_bits = {__,__,__,WW,__,__,GG,__,__,GG,__,__,WW,__,__,__};
                    5'd8:  hero_row_bits = {__,__,__,__,WW,__,GG,__,__,GG,__,WW,__,__,__,__};
                    5'd9:  hero_row_bits = {__,__,__,__,YY,WW,__,__,__,__,WW,YY,__,__,__,__};
                    5'd10: hero_row_bits = {__,__,__,__,SS,WW,KK,KK,KK,KK,WW,SS,__,__,__,__};
                    5'd11: hero_row_bits = {__,__,__,__,__,WW,SS,SS,SS,SS,WW,__,__,__,__,__};
                    5'd12: hero_row_bits = {__,__,__,__,__,__,WW,WW,WW,WW,__,__,__,__,__,__};
                    5'd13: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd14: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd15: hero_row_bits = {__,__,__,__,__,NN,NN,NN,NN,NN,NN,__,__,__,__,__};
                    5'd16: hero_row_bits = {__,__,__,__,__,NN,KK,__,__,KK,NN,__,__,__,__,__};
                    5'd17: hero_row_bits = {__,__,__,__,__,__,CC,__,__,CC,__,__,__,__,__,__};
                    default: hero_row_bits = 80'd0;
                endcase
            end
            default: begin // POSE_FULL
                case (hero_row)
                    5'd0:  hero_row_bits = {__,__,__,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,__,__,__};
                    5'd1:  hero_row_bits = {__,__,KK,OO,OO,OO,OO,OO,OO,OO,OO,OO,OO,KK,__,__};
                    5'd2:  hero_row_bits = {__,KK,OO,OO,OO,DD,OO,OO,OO,OO,DD,OO,OO,OO,KK,__};
                    5'd3:  hero_row_bits = {__,KK,OO,OO,OO,DD,OO,OO,OO,OO,DD,OO,OO,OO,KK,__};
                    5'd4:  hero_row_bits = {__,KK,DD,DD,DD,DD,DD,DD,DD,DD,DD,DD,DD,DD,KK,__};
                    5'd5:  hero_row_bits = {__,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,KK,__};
                    5'd6:  hero_row_bits = {__,__,GG,__,__,__,__,__,__,__,__,__,__,GG,__,__};
                    5'd7:  hero_row_bits = {__,__,__,GG,__,__,__,__,__,__,__,__,GG,__,__,__};
                    5'd8:  hero_row_bits = {__,__,__,__,GG,__,__,__,__,__,__,GG,__,__,__,__};
                    5'd9:  hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd10: hero_row_bits = {__,__,__,__,__,GG,__,__,__,__,GG,__,__,__,__,__};
                    5'd11: hero_row_bits = {__,__,__,__,__,SS,__,__,__,__,SS,__,__,__,__,__};
                    5'd12: hero_row_bits = {__,__,__,__,__,WW,KK,KK,KK,KK,WW,__,__,__,__,__};
                    5'd13: hero_row_bits = {__,__,__,__,__,WW,SS,SS,SS,SS,WW,__,__,__,__,__};
                    5'd14: hero_row_bits = {__,__,__,__,__,__,WW,WW,WW,WW,__,__,__,__,__,__};
                    5'd15: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd16: hero_row_bits = {__,__,__,__,__,__,WW,RR,WW,WW,__,__,__,__,__,__};
                    5'd17: hero_row_bits = {__,__,__,__,__,__,NN,NN,NN,NN,__,__,__,__,__,__};
                    5'd18: hero_row_bits = {__,__,__,__,__,__,NN,__,__,NN,__,__,__,__,__,__};
                    5'd19: hero_row_bits = {__,__,__,__,__,__,KK,__,__,KK,__,__,__,__,__,__};
                    default: hero_row_bits = 80'd0;
                endcase
            end
        endcase
        hero_color = hero_row_bits[(4'd15 - h_col_eff) * 5 +: 5];
    end

    // 2. OBSTACLE SPRITE ROM (#4 High-contrast Bird, Plane, #8 Flaming Debris)
    reg [39:0]  bird_row_bits;
    reg [119:0] plane_row_bits;
    reg [29:0]  debris_row_bits;

    wire [2:0] bird_col_eff   = obs_sel_flip ? (3'd7 - obs_col[2:0]) : obs_col[2:0];
    wire [4:0] plane_col_eff  = obs_sel_flip ? (5'd23 - obs_col)     : obs_col;
    wire [2:0] debris_col_eff = obs_sel_flip ? (3'd5 - obs_col[2:0]) : obs_col[2:0];

    always @* begin
        // #4: High-contrast 2-frame flapping bird (white/brown wings, black outline, gold beak)
        bird_row_bits = 40'd0;
        if (!obs_sel_frame) begin
            case (obs_row)
                3'd0: bird_row_bits = {KK,WW,__,__,__,__,WW,KK};
                3'd1: bird_row_bits = {__,KK,WW,__,__,WW,KK,__};
                3'd2: bird_row_bits = {__,__,KK,WW,WW,KK,__,__};
                3'd3: bird_row_bits = {__,KK,BB,WW,WW,KK,YY,YY};
                3'd4: bird_row_bits = {__,__,KK,KK,KK,__,__,__};
                default: bird_row_bits = 40'd0;
            endcase
        end else begin
            case (obs_row)
                3'd1: bird_row_bits = {__,__,KK,WW,WW,KK,__,__};
                3'd2: bird_row_bits = {__,KK,BB,WW,WW,KK,YY,YY};
                3'd3: bird_row_bits = {__,KK,WW,KK,KK,WW,KK,__};
                3'd4: bird_row_bits = {KK,WW,__,__,__,__,WW,KK};
                3'd5: bird_row_bits = {KK,__,__,__,__,__,__,KK};
                default: bird_row_bits = 40'd0;
            endcase
        end

        plane_row_bits = 120'd0;
        case (obs_row)
            3'd0: plane_row_bits = {RR,RR,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__};
            3'd1: plane_row_bits = {RR,RR,RR,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__,__};
            3'd2: plane_row_bits = {RR,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,__,__,__};
            3'd3: plane_row_bits = {WW,WW,WW,GG,WW,GG,WW,GG,WW,GG,WW,GG,WW,GG,WW,GG,WW,GG,WW,WW,WW,WW,__,__};
            3'd4: plane_row_bits = {WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW};
            3'd5: plane_row_bits = {__,WW,WW,WW,WW,WW,WW,WW,WW,GG,GG,GG,GG,WW,WW,WW,WW,WW,WW,WW,WW,WW,WW,__};
            3'd6: plane_row_bits = {__,__,__,__,__,__,__,__,GG,GG,GG,GG,GG,GG,__,__,__,__,__,__,__,__,__,__};
            3'd7: plane_row_bits = {__,__,__,__,__,__,__,__,__,GG,GG,GG,GG,__,__,__,__,__,__,__,__,__,__,__};
        endcase

        // #8: Falling Plane Debris with flickering trailing fire (RR/OO/YY) & torn fuselage (VV/TT)
        debris_row_bits = 30'd0;
        if (!obs_sel_frame) begin
            case (obs_row)
                3'd0: debris_row_bits = {__,RR,YY,OO,__,__};
                3'd1: debris_row_bits = {RR,OO,YY,RR,OO,__};
                3'd2: debris_row_bits = {KK,VV,TT,VV,KK,__};
                3'd3: debris_row_bits = {KK,TT,RR,VV,VV,KK};
                3'd4: debris_row_bits = {__,KK,VV,TT,VV,KK};
                3'd5: debris_row_bits = {__,__,KK,VV,KK,__};
                default: debris_row_bits = 30'd0;
            endcase
        end else begin
            case (obs_row)
                3'd0: debris_row_bits = {__,__,OO,YY,RR,__};
                3'd1: debris_row_bits = {__,OO,RR,YY,OO,RR};
                3'd2: debris_row_bits = {__,KK,VV,TT,VV,KK};
                3'd3: debris_row_bits = {KK,VV,VV,RR,TT,KK};
                3'd4: debris_row_bits = {KK,VV,TT,VV,KK,__};
                3'd5: debris_row_bits = {__,KK,VV,KK,__,__};
                default: debris_row_bits = 30'd0;
            endcase
        end

        case (obs_sel_type)
            2'd1: obs_color = bird_row_bits[(3'd7 - bird_col_eff) * 5 +: 5];
            2'd2: obs_color = plane_row_bits[(5'd23 - plane_col_eff) * 5 +: 5];
            2'd3: obs_color = debris_row_bits[(3'd5 - debris_col_eff) * 5 +: 5];
            default: obs_color = 5'd0;
        endcase
    end

    // 3. CRATE SPRITE ROM (#3: Orange/White mini-chute + Gold/Brown supply crate)
    reg [29:0] crate_row_bits;
    always @* begin
        case (crate_row)
            4'd0: crate_row_bits = {__,OO,WW,WW,OO,__};
            4'd1: crate_row_bits = {OO,WW,OO,OO,WW,OO};
            4'd2: crate_row_bits = {WW,__,__,__,__,WW};
            4'd3: crate_row_bits = {__,WW,__,__,WW,__};
            4'd4: crate_row_bits = {KK,KK,KK,KK,KK,KK};
            4'd5: crate_row_bits = {KK,YY,BB,BB,YY,KK};
            4'd6: crate_row_bits = {KK,BB,YY,YY,BB,KK};
            4'd7: crate_row_bits = {KK,YY,BB,BB,YY,KK};
            4'd8: crate_row_bits = {KK,KK,KK,KK,KK,KK};
            default: crate_row_bits = 30'd0;
        endcase
        crate_color = crate_row_bits[(3'd5 - crate_col) * 5 +: 5];
    end

    // 4. HUD / MENU ICON ROM
    reg [44:0] icon_row_bits;
    always @* begin
        icon_row_bits = 45'd0;
        case (icon_id)
            3'd0: begin // Closed Lock
                case (icon_row)
                    4'd0: icon_row_bits = {__,YY,YY,YY,__, __,__,__,__};
                    4'd1: icon_row_bits = {YY,__,__,__,YY, __,__,__,__};
                    4'd2: icon_row_bits = {YY,YY,YY,YY,YY, __,__,__,__};
                    4'd3: icon_row_bits = {YY,YY,KK,YY,YY, __,__,__,__};
                    4'd4: icon_row_bits = {YY,YY,KK,YY,YY, __,__,__,__};
                    4'd5: icon_row_bits = {YY,YY,YY,YY,YY, __,__,__,__};
                    default: icon_row_bits = 45'd0;
                endcase
            end
            3'd1: begin // Open Lock
                case (icon_row)
                    4'd0: icon_row_bits = {__,YY,YY,YY,__, __,__,__,__};
                    4'd1: icon_row_bits = {YY,__,__,__,__, __,__,__,__};
                    4'd2: icon_row_bits = {YY,YY,YY,YY,YY, __,__,__,__};
                    4'd3: icon_row_bits = {YY,YY,KK,YY,YY, __,__,__,__};
                    4'd4: icon_row_bits = {YY,YY,KK,YY,YY, __,__,__,__};
                    4'd5: icon_row_bits = {YY,YY,YY,YY,YY, __,__,__,__};
                    default: icon_row_bits = 45'd0;
                endcase
            end
            3'd2: begin // Warning Triangle
                case (icon_row)
                    4'd0: icon_row_bits = {__,__,RR,__,__, __,__,__,__};
                    4'd1: icon_row_bits = {__,RR,WW,RR,__, __,__,__,__};
                    4'd2: icon_row_bits = {__,RR,WW,RR,__, __,__,__,__};
                    4'd3: icon_row_bits = {RR,RR,RR,RR,RR, __,__,__,__};
                    4'd4: icon_row_bits = {RR,RR,WW,RR,RR, __,__,__,__};
                    default: icon_row_bits = 45'd0;
                endcase
            end
            3'd3: begin // Landing Arrow
                case (icon_row)
                    4'd0: icon_row_bits = {YY,YY,YY,YY,YY, __,__,__,__};
                    4'd1: icon_row_bits = {__,YY,YY,YY,__, __,__,__,__};
                    4'd2: icon_row_bits = {__,__,YY,__,__, __,__,__,__};
                    default: icon_row_bits = 45'd0;
                endcase
            end
            3'd4: begin // Star (9x9)
                case (icon_row)
                    4'd0: icon_row_bits = {__,__,__,__,YY,__,__,__,__};
                    4'd1: icon_row_bits = {__,__,__,YY,YY,YY,__,__,__};
                    4'd2: icon_row_bits = {__,__,__,YY,YY,YY,__,__,__};
                    4'd3: icon_row_bits = {YY,YY,YY,YY,YY,YY,YY,YY,YY};
                    4'd4: icon_row_bits = {__,YY,YY,YY,YY,YY,YY,YY,__};
                    4'd5: icon_row_bits = {__,__,YY,YY,YY,YY,YY,__,__};
                    4'd6: icon_row_bits = {__,__,YY,YY,__,YY,YY,__,__};
                    4'd7: icon_row_bits = {__,YY,YY,__,__,__,YY,YY,__};
                    4'd8: icon_row_bits = {YY,YY,__,__,__,__,__,YY,YY};
                    default: icon_row_bits = 45'd0;
                endcase
            end
            default: icon_row_bits = 45'd0;
        endcase
        icon_color = icon_row_bits[(4'd8 - icon_col) * 5 +: 5];
    end
endmodule
