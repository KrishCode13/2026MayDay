// =====================================================================
// led_ctrl.v  --  MEMBER 4. The 16 LEDs, one job per state (ICD table).
// PORT CHANGE vs kit: added gust_warn and gust_active (from Member 1) so
// wind is shown only while a gust is coming or blowing. My_Top_Module.v
// is updated to match. `led` is now a registered output.
//
//   HOME, CUTSCENE, LEVEL_INTRO,
//   LEVEL_FAILED, VICTORY      slow chaser (one LED walks LD0 -> LD15)
//   FREEFALL_LOCKED            all off
//   FREEFALL_WINDOW            bar fills 1,700 -> 1,550 m; steady full
//                              1,550 -> 1,450 m; rapid flash below 1,450 m
//   CANOPY / FINAL_APPROACH    magnet drain (priority), else wind
//   LANDING                    off (not in ICD table; keeps focus on OLED)
//   CRASH                      all flash
//   LEVEL_COMPLETE             3 groups light at ticks 30/60/90 per star
// =====================================================================
module led_ctrl (
    input  wire        clk,
    input  wire        game_tick,
    input  wire [3:0]  game_state,
    input  wire [7:0]  state_timer,
    input  wire [23:0] altitude,
    input  wire        gust_warn,
    input  wire        gust_active,
    input  wire        gust_dir,          // 0 left, 1 right
    input  wire [1:0]  gust_strength,
    input  wire        magnet_active,
    input  wire [8:0]  magnet_ticks_left,
    input  wire [2:0]  stars_earned,
    output reg  [15:0] led
);
    `include "game_params.vh"

    wire [15:0] alt_m = altitude[23:8];

    // ---- Own tick counter: drives chaser and flashing ----------------
    // (state_timer stops at 255, so it cannot be used for endless effects)
    reg [15:0] tcnt = 16'd0;
    always @(posedge clk) if (game_tick) tcnt <= tcnt + 1'b1;

    wire       flash     = tcnt[LED_FLASH_BIT];
    wire [3:0] chase_pos = tcnt[LED_CHASE_BIT +: 4];

    // ---- Bar graphs as thermometer codes (no divider) -----------------
    // Each LED has its own constant threshold, worked out at compile time.
    // LED i lights when the value has passed threshold i, so the bar
    // grows one LED at a time.
    //   gauge: LED i on when altitude <= 1700 - (i+1)*150/16
    //   drain: LED i on when magnet_ticks_left > i*300/16
    wire [15:0] gauge, drain;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_bar
            assign gauge[i] = (alt_m <= ALT_UNLOCK - ((i + 1) * (ALT_UNLOCK - ALT_PERFECT_HI)) / 16);
            assign drain[i] = (magnet_ticks_left > (i * MAGNET_TICKS) / 16);
        end
    endgenerate

    // ---- Wind: lights spread from the centre (between LD8 and LD7) ----
    // Right gust (gust_dir = 1) fills LD7 downward; left fills LD8 upward.
    reg [3:0] wlen;
    always @* begin
        case (gust_strength)
            2'd1:    wlen = WIND_LEN_1;
            2'd2:    wlen = WIND_LEN_2;
            2'd3:    wlen = WIND_LEN_3;
            default: wlen = 4'd0;
        endcase
    end
    wire [7:0]  right_half = ~(8'hFF >> wlen);    // top wlen bits of LD7..LD0
    wire [7:0]  left_half  = ~(8'hFF << wlen);    // low wlen bits of LD15..LD8
    wire [15:0] wind       = gust_dir ? {8'h00, right_half} : {left_half, 8'h00};
    wire        show_wind  = gust_warn | gust_active;

    // ---- Star groups: LD15-12, LD9-6, LD3-0 (gaps between groups) -----
    wire s0 = stars_earned[0] && (state_timer >= T_STAR1);   // all crates
    wire s1 = stars_earned[1] && (state_timer >= T_STAR2);   // landed
    wire s2 = stars_earned[2] && (state_timer >= T_STAR3);   // perfect land
    wire [15:0] star_leds = {{4{s0}}, 2'b00, {4{s1}}, 2'b00, {4{s2}}};

    // ---- One job per state (registered output) -----------------------
    initial led = 16'd0;
    always @(posedge clk) begin
        case (game_state)
            S_FREEFALL_LOCKED: led <= 16'h0000;
            S_FREEFALL_WINDOW:
                if (alt_m <= ALT_PERFECT_LO) led <= flash ? 16'hFFFF : 16'h0000;  // late
                else                         led <= gauge;   // full and steady from 1,550 m
            S_CANOPY, S_FINAL_APPROACH:
                if (magnet_active)  led <= drain;
                else if (show_wind) led <= wind;
                else                led <= 16'h0000;
            S_LANDING:         led <= 16'h0000;
            S_CRASH:           led <= flash ? 16'hFFFF : 16'h0000;
            S_LEVEL_COMPLETE:  led <= star_leds;
            default:           led <= 16'h0001 << chase_pos;   // menus and story
        endcase
    end
endmodule
