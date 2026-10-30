// =====================================================================
// seg7_ctrl.v  --  MEMBER 4. Four-digit seven-segment display.
// Ports unchanged from the kit (FINAL). Outputs are active low,
// seg[0] = CA ... seg[6] = CG; an[0] = rightmost digit.
//
// Pipeline:
//   1. Crash spin-down register (own 20 ms timer)
//   2. Pick the number to show (altitude / spin / stars / total)
//   3. Double dabble, one shift per clock (14 clocks per conversion)
//   4. Pick 4 characters for the current state
//   5. Multiplex: light one digit at a time, fast enough to look steady
// =====================================================================
module seg7_ctrl (
    input  wire        clk,
    input  wire [3:0]  game_state,
    input  wire [2:0]  level,
    input  wire [2:0]  menu_cursor,
    input  wire [23:0] altitude,
    input  wire [2:0]  stars_earned,
    input  wire [3:0]  total_stars,
    output wire [6:0]  seg,     // active low, seg[0] = CA
    output wire        dp,      // active low
    output wire [3:0]  an       // active low
);
    `include "game_params.vh"

    // Character codes (0-9 are the digits themselves).
    localparam [4:0] CH_BLANK = 5'd10, CH_L = 5'd11, CH_DASH = 5'd12, CH_S = 5'd13,
                     CH_T = 5'd14, CH_F = 5'd15, CH_A = 5'd16, CH_I = 5'd17;

    wire [15:0] alt_m       = altitude[23:8];
    wire [13:0] alt_clamped = (alt_m > SEG_MAX_VALUE) ? SEG_MAX_VALUE : alt_m[13:0];

    // ---- 1. Crash spin-down ------------------------------------------
    // Outside CRASH, spin_val tracks altitude. Inside CRASH it falls
    // every 20 ms by value/8 + 1: fast at first, slowing near 0, like a
    // needle spinning down. 1,400 m reaches 0 in 43 steps (0.86 s).
    reg [13:0] spin_val = 14'd0;
    reg [21:0] spin_cnt = 22'd0;
    always @(posedge clk) begin
        if (game_state != S_CRASH) begin
            spin_val <= alt_clamped;
            spin_cnt <= 22'd0;
        end else if (spin_cnt == SEG_SPIN_CYCLES - 1) begin
            spin_cnt <= 22'd0;
            if (spin_val != 14'd0)
                spin_val <= spin_val - (spin_val >> SEG_SPIN_SHIFT) - 1'b1;
        end else
            spin_cnt <= spin_cnt + 1'b1;
    end

    // ---- 2. Number to convert ----------------------------------------
    reg [13:0] bin_val;
    always @* begin
        case (game_state)
            S_CRASH:          bin_val = spin_val;
            S_LEVEL_COMPLETE: bin_val = stars_earned[0] + stars_earned[1] + stars_earned[2];
            S_VICTORY:        bin_val = {10'd0, total_stars};
            default:          bin_val = alt_clamped;
        endcase
    end

    // ---- 3. Double dabble (shift-and-add-3), one bit per clock -------
    // Register layout: [29:14] four BCD digits, [13:0] binary input.
    // For each of the 14 bits: any BCD digit >= 5 gets +3, then the
    // whole register shifts left by one. After 14 shifts the top 16
    // bits hold thousands, hundreds, tens, ones. No divider is used.
    function [3:0] add3;
        input [3:0] d;
        add3 = (d >= 4'd5) ? d + 4'd3 : d;
    endfunction

    reg  [29:0] dd     = 30'd0;
    reg  [3:0]  dd_cnt = 4'd0;            // shifts still to do
    reg  [15:0] bcd    = 16'd0;           // last finished result
    wire [29:0] dd_adj   = {add3(dd[29:26]), add3(dd[25:22]),
                            add3(dd[21:18]), add3(dd[17:14]), dd[13:0]};
    wire [29:0] dd_shift = dd_adj << 1;

    always @(posedge clk) begin
        if (dd_cnt == 4'd0) begin                 // load a fresh value
            dd     <= {16'd0, bin_val};
            dd_cnt <= 4'd14;
        end else begin                            // one adjust + shift
            dd     <= dd_shift;
            dd_cnt <= dd_cnt - 1'b1;
            if (dd_cnt == 4'd1) bcd <= dd_shift[29:14];   // done: publish
        end
    end

    wire [3:0] d3 = bcd[15:12], d2 = bcd[11:8], d1 = bcd[7:4], d0 = bcd[3:0];

    // ---- 4. Characters per state (ICD seven-segment table) ------------
    reg [4:0] ch3, ch2, ch1, ch0;                 // ch3 = leftmost
    always @* begin
        ch3 = CH_BLANK; ch2 = CH_BLANK; ch1 = CH_BLANK; ch0 = CH_BLANK;
        case (game_state)
            S_HOME:        begin ch3 = CH_L; ch2 = CH_DASH; ch0 = menu_cursor + 3'd1; end
            S_LEVEL_INTRO: begin ch3 = CH_L; ch2 = CH_DASH; ch0 = level;              end
            S_FREEFALL_LOCKED, S_FREEFALL_WINDOW, S_CANOPY,
            S_FINAL_APPROACH, S_LANDING, S_CRASH: begin
                // Altitude with leading zeros blanked: "2000", " 150", "   7".
                ch3 = (d3 == 0)                         ? CH_BLANK : d3;
                ch2 = (d3 == 0 && d2 == 0)              ? CH_BLANK : d2;
                ch1 = (d3 == 0 && d2 == 0 && d1 == 0)   ? CH_BLANK : d1;
                ch0 = d0;
            end
            S_LEVEL_COMPLETE: begin ch3 = CH_S; ch2 = CH_T; ch0 = d0; end
            S_LEVEL_FAILED:   begin ch3 = CH_F; ch2 = CH_A; ch1 = CH_I; ch0 = CH_L; end
            S_VICTORY:        begin ch3 = CH_T; ch1 = (d1 == 0) ? CH_BLANK : d1; ch0 = d0; end
            default: ;                                    // CUTSCENE: blank
        endcase
    end

    // Segment patterns, active low, bit order {g,f,e,d,c,b,a}.
    function [6:0] encode;
        input [4:0] c;
        case (c)
            5'd0: encode = 7'b1000000;  5'd1: encode = 7'b1111001;
            5'd2: encode = 7'b0100100;  5'd3: encode = 7'b0110000;
            5'd4: encode = 7'b0011001;  5'd5: encode = 7'b0010010;
            5'd6: encode = 7'b0000010;  5'd7: encode = 7'b1111000;
            5'd8: encode = 7'b0000000;  5'd9: encode = 7'b0010000;
            CH_L:    encode = 7'b1000111;
            CH_DASH: encode = 7'b0111111;
            CH_S:    encode = 7'b0010010;   // same shape as 5
            CH_T:    encode = 7'b0000111;   // lower-case t
            CH_F:    encode = 7'b0001110;
            CH_A:    encode = 7'b0001000;
            CH_I:    encode = 7'b1111001;   // same shape as 1
            default: encode = 7'b1111111;   // blank
        endcase
    endfunction

    // ---- 5. Multiplexing ---------------------------------------------
    // Only one digit is lit at a time. The top 2 bits of a free-running
    // counter choose which; each digit is on for 0.66 ms, so all four
    // refresh at ~380 Hz and the eye sees them all lit at once.
    reg [SEG_REFRESH_BITS-1:0] refresh = 0;
    reg [6:0] seg_r = 7'b1111111;
    reg [3:0] an_r  = 4'b1111;
    always @(posedge clk) begin
        refresh <= refresh + 1'b1;
        case (refresh[SEG_REFRESH_BITS-1 -: 2])
            2'd0: begin an_r <= 4'b1110; seg_r <= encode(ch0); end
            2'd1: begin an_r <= 4'b1101; seg_r <= encode(ch1); end
            2'd2: begin an_r <= 4'b1011; seg_r <= encode(ch2); end
            2'd3: begin an_r <= 4'b0111; seg_r <= encode(ch3); end
        endcase
    end

    assign seg = seg_r;
    assign an  = an_r;
    assign dp  = 1'b1;          // decimal point unused
endmodule
