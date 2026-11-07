module physics_engine (
    input  wire               clk,
    input  wire               rst,
    // from member 4
    input  wire               game_tick,
    input  wire [3:0]         game_state,
    input  wire [2:0]         level,
    input  wire               level_start,
    input  wire [7:0]         state_timer,
    input  wire [15:0]        seed,
    input  wire               steer_left_held,
    input  wire               steer_right_held,
    input  wire               flare_press,      
    input  wire               brake_held,       
    input  wire               crate_collected,  
    input  wire               gust_request,     
    input  wire               plane_busy,       
    output wire               flare_locked,     
    output wire [1:0]         bank_lvl,         
    output wire               bank_left,        
    output wire signed [2:0]  swing_dx,        
    output wire               stunned,         
    // from member 2
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
    output reg  [2:0]         crash_cause,      
    output reg                hero_landed,
    output reg  [1:0]         landing_grade,    
    output reg                landed_on_spot
);
    `include "game_params.vh"

    localparam       SWAY_TICKS  = 60;     // +-1 px once per second

    // internal q8.8: bits [15:8] = whole pixels, [7:0] = fraction
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
    reg               flare_done;   // first c press in final_approach used
    assign flare_locked = flare_done;
    reg               flare_ok;     // that edge was soft or hard(not a miss)
    reg               flare_ok_n;
    reg  [1:0]        landing_grade_n;
    reg               touch_sent;   // land / miss-flare pulse already fired
    reg               flare_req;    
    reg signed [15:0] y_next;       
    reg signed [16:0] alt_drop;     
    reg       strike_pend;
    reg       strike_side_l;
    reg [1:0] strike_lines_l;

    // runs every clock, the hit pulse would be gone before the next tick if this waited for game_tick
    always @(posedge clk) begin
        if (rst || level_start) begin
            strike_pend <= 1'b0; 
            strike_side_l <= 1'b0; 
            strike_lines_l <= 2'd0;
        end else if (strike) begin
            if (!strike_pend || game_tick) begin     // first hit since the last tick replaces whatever was stored
                strike_side_l  <= strike_side;        // copy which side this hit was on
                strike_lines_l <= strike_lines;       // copy how many lines this hit cuts
            end else
                // a later hit in the same frame keeps the first side and adds the line counts, stopping at 2
                strike_lines_l <= ((strike_lines_l + strike_lines) >= 2'd2) ? 2'd2 : (strike_lines_l + strike_lines);
            strike_pend <= 1'b1;   // remember that a hit is waiting for the next game_tick
        end else if (game_tick)
            strike_pend <= 1'b0;   // a tick with no new hit drops the latch, so the big block sees the hit for one tick only
    end

    reg crate_pend, gust_req_pend;   // same latch idea for the crate and the level-1 gust request

    always @(posedge clk) begin
        if (rst || level_start) begin
            crate_pend <= 1'b0;  
            gust_req_pend <= 1'b0;
        end else begin
            if (crate_collected) begin
                crate_pend <= 1'b1;          // remember the crate until the next tick uses it
            end else if (game_tick) begin
              crate_pend <= 1'b0;            // the tick that uses it also clears it
            end
            if (gust_request) begin
                gust_req_pend <= 1'b1;       // remember the level-1 gust request
            end else if (game_tick && gust_phase != 2'd0) begin
                 // clear only after a gust has left idle, so a request during the calm band is still waiting later
                 gust_req_pend <= 1'b0;
            end
        end
    end

    // btnc is also one clock and usually misses game_tick, so hold it until the next tick
    always @(posedge clk) begin
        if (rst || level_start)
            flare_req <= 1'b0;
        else if (flare_press && (game_state == S_FINAL_APPROACH))
            flare_req <= 1'b1;   // a press outside final approach is ignored
        else if (game_tick)
            flare_req <= 1'b0;   // the tick that reads the press also clears it
    end

    wire in_freefall = (game_state == S_FREEFALL_LOCKED) || (game_state == S_FREEFALL_WINDOW);   // states 3 and 4
    wire in_canopy = (game_state == S_CANOPY) || (game_state == S_FINAL_APPROACH);             // states 5 and 6
    wire in_flight = in_freefall || in_canopy;   // freefall or canopy, speeds are forced to 0 outside this
    wire opening   = (game_state == S_CANOPY) && (state_timer < OPEN_TICKS);   // first 60 ticks of canopy, fall blends from 2.0 px per tick down to about 0.30
    wire both_held = steer_left_held && steer_right_held;   // worked out and never used, brake and flare do not look at both steer buttons
    wire stalling  = (stall_left != 8'd0);   // stall_left is counting down
    // btnu, in canopy, or in final approach until the camera locks, and not during a stall
    wire braking  = ((game_state == S_CANOPY) || ((game_state == S_FINAL_APPROACH) && !cam_lock)) && brake_held && !stalling;  

    wire signed [15:0] steer_acc = in_freefall ? (STEER_ACC >>> 1) : STEER_ACC;   // 5 in freefall, 10 under the canopy, steer_acc is 10
    wire signed [15:0] brake_rise_now = (lines_snapped == 2'd1) ? (BRAKE_RISE >>> 1) : BRAKE_RISE;   // 128 (0.5 px per tick) with both lines, 64 with one line gone

    reg  signed [7:0]  bank = 8'sd0;        // -64 to 64 = -60 to 60 deg negative = left
    wire        [6:0]  bank_abs = bank[7] ? -bank : bank;   // size of bank, 0 to 64
    assign bank_lvl  = (bank_abs >= BANK_HARD) ? 2'd2 : (bank_abs >= BANK_SLIGHT) ? 2'd1 : 2'd0;   // 40 is about 38 deg, 12 is a slight bank
    assign bank_left = bank[7];   // sign bit, 1 means the bank is to the left
   
    // load factor n = 1/cos(bank), q8.8, 9 steps of 7.5 deg
    function [9:0] load_factor; input [3:0] k;
        case (k)   // k is the angle/7.5, each number is 256 * 1/cos of that angle
            4'd0: load_factor = 10'd256;  4'd1: load_factor = 10'd258;  4'd2: load_factor = 10'd265;
            4'd3: load_factor = 10'd277;  4'd4: load_factor = 10'd296;  4'd5: load_factor = 10'd323;
            4'd6: load_factor = 10'd362;  4'd7: load_factor = 10'd420;  default: load_factor = 10'd512;
        endcase
    endfunction
    wire  [9:0]  lf = load_factor(bank_abs[6:3]);   // bank/8, so each table entry is 7.5 deg, 256 means 1.0 times, 512 means 2.0 times

    // 0 when the bank is 0, any other bank is +-5 plus (bank*10)>>>7, a full bank of 64 only gets to 10
    wire signed [15:0] bank_acc = (bank == 8'sd0) ? 16'sd0 : ((bank[7] ? -(STEER_ACC >>> 1) : (STEER_ACC >>> 1)) + (($signed(bank) * STEER_ACC) >>> 7));
    
    reg  signed [15:0] sw_x = 16'sd0, sw_v = 16'sd0;   // pendulum position and speed, gust kicks it, a spring pulls it back
    assign swing_dx = (sw_x > 16'sd767) ? 3'sd3 : (sw_x < -16'sd767) ? -3'sd3 : sw_x[10:8];   // bit 8 of sw_x is 1 px, bits [10:8] are that pixel, outside +-767, clamp to +-3
    reg  [6:0] stun_t = 7'd0;   // counts down from 60, about 1 second of no steering
    reg  [1:0] ff_hits = 2'd0;  // freefall hits, tested before the add, so hit 1 only stuns and hit 2 kills
    reg        ko_sent = 1'b0;  // knockout pulse already sent
    assign stunned = (stun_t != 7'd0);   // high for every tick the stun timer is still counting

    
    wire signed [15:0] level_vy  = (lines_snapped == 2'd0) ? V_CANOPY : V_CANOPY_DMG;   // 77 (0.30 px per tick) with no lines cut, 92 (0.36, 1.195x) with one, two lines crash instead
    wire signed [25:0] banked_vy = level_vy * $signed({1'b0, lf});   // level_vy times the load factor, both are q8.8
    wire signed [15:0] canopy_vy = banked_vy[23:8];   // bits [23:8] divide that product by 256 and return q8.8, a 60 deg bank falls at 0.60

    // 1/60 ≈ 17/1024 so opening blend needs no divider
    wire signed [31:0] open_num =($signed(V_FREEFALL) - $signed(V_CANOPY)) * $signed({1'b0, state_timer}) * 32'sd17;   // (512-77) * timer * 17
    wire signed [15:0] open_vy = V_FREEFALL - open_num[25:10];   // bits [25:10] divide by 1024, timer 0 is speed 512, timer 60 is about 79, just above 77

    // 0, 4, 8, or 12 added to vx each tick of an active gust, 12 is never rolled
    wire signed [15:0] gust_acc =   (!gust_active) ? 16'sd0 : (gust_strength == 2'd1) ? GUST_ACC_1 : (gust_strength == 2'd2) ? GUST_ACC_2 : (gust_strength == 2'd3) ? GUST_ACC_3 : 16'sd0;

    wire signed [15:0] y_rest_q = HERO_REST_Y <<< 8;   // rest row 10, in q8.8
    wire signed [15:0] y_min_q  = (HERO_REST_Y - BRAKE_MAX_RISE) <<< 8;   // 8 px above rest, the tug cannot rise past this

    // idle gap: 180, 150, 120, 105, 90 ticks for levels 1 to 5, level 1 starts from gust_request instead
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

    // level 1 rolls strength 1 only, every other level rolls 1 or 2
    function [1:0] gust_max;
        input [2:0] lv;
        begin
            case (lv)
                3'd1:    gust_max = 2'd1;
                default: gust_max = 2'd2;   
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
                default: begin   // the strength-3 branch is unreachable because gust_max never returns 3
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
                2'd0:    sway_delta = 16'sd256;   // +1 px in q8.8
                2'd2:    sway_delta = -16'sd256;  // -1 px
                default: sway_delta = 16'sd0;
            endcase
        end
    endfunction

    // next horizontal/vertical speed and x (uses registered stall/brake/gust)
    reg signed [15:0] vx_n, vy_n, x_q_n;
    reg signed [7:0]  hero_x_n;
    reg signed [8:0]  hb_left, hb_right;
    reg               edge_hit;

    // combo block, computes the next speeds and stores nothing, the tick block copies them
    always @(*) begin
        vx_n     = vx;            // start from the stored speeds, a branch below replaces these
        vy_n     = vy;
        x_q_n    = x_q;
        hero_x_n = x_q[15:8];     // pixel part of the stored x, until the new x is worked out
        hb_left  = 9'sd40;        // dummy box, gets replaced once we know hero_x_n
        hb_right = 9'sd50;
        edge_hit = 1'b0;          // stays 0 unless a hitbox edge crosses the screen boundary

        if (in_flight) begin
            // vertical speed
            if (stalling) begin
                vy_n = V_STALL;                 // stall wins over everything, vy is forced to 384, which is 1.5 px per tick
            end else if (in_freefall) begin
                // add 13 until 512, 13/256 is about 0.05 px per tick^2, top speed takes about 39 ticks
                if (vy >= (V_FREEFALL - GRAVITY))
                    vy_n = V_FREEFALL;
                else
                    vy_n = vy + GRAVITY;
            end else if (opening) begin
                vy_n = open_vy;                 // use the blended opening speed from line open_vy
            end else begin
                vy_n = canopy_vy;               // open canopy, already includes the banked sink
            end
            if (braking)
                vy_n = vy_n >>> 1;              // braking halves whatever speed was chosen, a stall cannot reach this, because braking requires !stalling


            if (stunned)
                vx_n = vx;   // stunned leaves vx alone, so a freefall hit removes steering
            else if (!in_freefall)
                vx_n = vx + bank_acc;   // under the canopy the push is the bank, not the button directly
            else if (steer_left_held && !steer_right_held)
                vx_n = vx - steer_acc;   // freefall only, left subtracts 5
            else if (steer_right_held && !steer_left_held)
                vx_n = vx + steer_acc;   // freefall only, right adds 5
            else
                vx_n = vx;   // neither button, or both, leaves the freefall sideways speed unchanged

            if (gust_active) begin              // gust adds +-4 or +-8 after the steering
                if (gust_dir == 1'b0)
                    vx_n = vx_n - gust_acc;   // direction 0 pushes left
                else
                    vx_n = vx_n + gust_acc;   // direction 1 pushes right
            end

            if (lines_snapped == 2'd1) begin    // exactly one line, adds 3 toward damaged_side, or 12 while braking
                // stronger while tugging with one line the uneven wing yaws that way
                if (damaged_side == 1'b0)
                    vx_n = vx_n - (braking ? (DRIFT_ACC <<< 2) : DRIFT_ACC);   // cut on the left = subtract 3, or 12 while braking
                else
                    vx_n = vx_n + (braking ? (DRIFT_ACC <<< 2) : DRIFT_ACC);   // cut on the right = add 3, or 12 while braking
            end

            // drag takes vx>>>4, but at least 1, both ways, a plain >>>4 turned speeds from 1 to 15 into 0 so they never slowed down
            if (vx_n > 16'sd0)
                vx_n = vx_n - (((vx_n >>> DRAG_SHIFT) == 16'sd0) ? 16'sd1 : (vx_n >>> DRAG_SHIFT));   // moving right = subtract vx/16, or 1 if that shift is 0
            else if (vx_n < 16'sd0)
                vx_n = vx_n + ((((-vx_n) >>> DRAG_SHIFT) == 16'sd0) ? 16'sd1 : ((-vx_n) >>> DRAG_SHIFT));   // moving left = add the same amount, so the speed moves toward 0

            x_q_n    = x_q + vx_n;   // new position is old position plus the new speed
            hero_x_n = x_q_n[15:8];  // keep only the whole-pixel part for the sprite and the hitbox

            if (in_freefall) begin
                hb_left  = {hero_x_n[7], hero_x_n} + HB_FF_X;                        // freefall box is hero_x+4 through hero_x+11
                hb_right = {hero_x_n[7], hero_x_n} + HB_FF_X + HB_FF_W - 1;
            end else begin
                hb_left  = {hero_x_n[7], hero_x_n} + HB_CANOPY_X;                    // canopy box is hero_x+1 through hero_x+14
                hb_right = {hero_x_n[7], hero_x_n} + HB_CANOPY_X + HB_CANOPY_W - 1;
            end
            if (($signed(hb_left) <= EDGE_LEFT_MAX) ||
                ($signed(hb_right) >= EDGE_RIGHT_MIN))
                edge_hit = 1'b1;   // die if the left edge is 2 or less, or the right edge is 93 or more
        end else begin
            vy_n = 16'sd0;   // menu, landing, crash = no motion
            vx_n = 16'sd0;
        end
    end

    always @(posedge clk) begin
        // cleared every clock, a later line on a game_tick can set them back to 1, and that later line wins, the pulse is one clock wide
        hero_crash  <= 1'b0;
        hero_landed <= 1'b0;

        if (rst || level_start) begin   // reset and a new level load the same picture
            x_q           <= HERO_REST_X <<< 8;   // pixel 40 stored in q8.8
            y_q           <= HERO_REST_Y <<< 8;
            hero_x        <= HERO_REST_X;
            hero_y        <= HERO_REST_Y;
            vx            <= 16'sd0;
            vy            <= 16'sd0;
            scroll_vy     <= 16'sd0;
            altitude      <= {ALT_START, 8'd0};   // 1400 m, stored as 1400*256
            canopy_mode   <= CM_FREEFALL;
            lines_snapped <= 2'd0;
            damaged_side  <= 1'b0;
            gust_warn     <= 1'b0;
            gust_active   <= 1'b0;
            gust_dir      <= 1'b0;
            gust_strength <= 2'd0;
            deploy_grade  <= DG_NONE;
            crash_cause   <= CC_COLLAPSE;
            landing_grade <= 2'd0;
            bank <= 8'sd0; sw_x <= 16'sd0; sw_v <= 16'sd0; stun_t <= 7'd0; ff_hits <= 2'd0; ko_sent <= 1'b0;
            landed_on_spot<= 1'b0;
            lfsr          <= ((seed ^ LFSR_CONST_M1) == 16'd0)   // seed xor 16'ha5a5, forced to 1 if that is 0, because an lfsr stuck at 0 stays at 0
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
            // lfsr taps 16,14,13,11 (bits 15,13,12,10)
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};   // new bit is bit15 xor bit13 xor bit12 xor bit10, then the register shifts left

          
            lines_n = lines_snapped;   // copy the stored count, = means the lines below see this tick's edits
            side_n  = damaged_side;    // copy the stored side the same way
            if (in_flight && strike_pend && !in_freefall) begin    // canopy hits cut lines, freefall hits skip this and stun instead
                if (lines_n == 2'd0)
                    side_n = strike_side_l;   // only the first cut line records which side, a later cut leaves side_n alone
                if (lines_n + strike_lines_l >= 2'd2)
                    lines_n = 2'd2;           // 2 or more cut lines is a collapse
                else
                    lines_n = lines_n + strike_lines_l;   // if not, add the lines from the hit we saved
            end
            if ((game_state == S_CANOPY) && (deploy_grade == DG_NONE)) begin   // grade is stored once, on the first canopy tick
                if (altitude[23:8] > ALT_PERFECT_HI)
                    deploy_grade <= DG_EARLY;  // above 950
                else if (altitude[23:8] >= ALT_PERFECT_LO)
                    deploy_grade <= DG_PERFECT;  // 950 down to 850
                else
                    deploy_grade <= DG_LATE; // below 850
                if (altitude[23:8] < ALT_PERFECT_LO) begin   // below 850 also snaps a line, side is lfsr[0] if nothing is cut yet, a second line becomes 2 and collapses
                    if (lines_n == 2'd0)
                        side_n = lfsr[0];     // no hit picked a side, so the random bit does
                    if (lines_n >= 2'd1)
                        lines_n = 2'd2;       // a line was already cut, so this late open cuts the second and collapses
                    else
                        lines_n = 2'd1;       // if not, this late open cuts just one line
                end
            end
            
            if (in_flight && crate_pend && (lines_n == 2'd1))
                lines_n = 2'd0;   // a crate repairs exactly one line, it does nothing at 0 or at 2
            lines_snapped <= lines_n;   // store the count after the hit, the late open, and the crate
            damaged_side <= side_n;

            
            if (in_canopy) begin   // gusts exist only in canopy and final approach
                if (gust_timer != 9'd0)
                    gust_timer <= gust_timer - 9'd1;   // <= updates after the clock, so the == 0 tests below still see the old timer, the phase changes on the tick it is already 0
                
                if ((plane_busy || (altitude[23:8] < CALM_ALT)) && (gust_phase != 2'd0)) begin   // a plane, or the last 50 m, kills the gust and reloads the gap
                    gust_phase <= 2'd0;
                    gust_warn <= 1'b0;
                    gust_active <= 1'b0;
                    gust_timer <= gust_gap(level);
                end else
                case (gust_phase)
                    2'd0: begin
                        gust_warn <= 1'b0;     // idle = no warning and no push
                        gust_active <= 1'b0;
                        
                        // level 1 waits for the latched request, other levels wait for the gap, no start below 50 m or while a plane is busy
                        if (((level != 3'd1) ? (gust_timer == 9'd0) : gust_req_pend) && !plane_busy && (altitude[23:8] >= CALM_ALT)) begin   
                            gust_phase <= 2'd1;
                            gust_timer <= GUST_WARN_TICKS;
                            gust_warn <= 1'b1;
                            gust_dir <= lfsr[1];   // direction from lfsr[1], strength from lfsr[3:2], then 30 ticks of warning
                            gust_strength <= rand_strength(gust_max(level), lfsr[3:2]);
                        end
                    end
                    2'd1: begin
                        gust_warn <= 1'b1;     // warning = the renderer can show it, but vx is not pushed yet
                        gust_active <= 1'b0;
                        if (gust_timer == 9'd0) begin
                            gust_phase <= 2'd2;   // warning ends, 60 ticks of push begin
                            gust_timer <= GUST_TICKS;
                            gust_warn <= 1'b0;
                            gust_active <= 1'b1;
                        end
                    end
                    default: begin
                        gust_warn   <= 1'b0;   // blowing = warning is over, and gust_acc is added to vx
                        gust_active <= 1'b1;
                        if (gust_timer == 9'd0) begin
                            gust_phase <= 2'd0;   // push ends, gap starts again
                            gust_timer <= gust_gap(level);
                            gust_active <= 1'b0;
                        end
                    end
                endcase
            end else begin
                gust_warn <= 1'b0;     // any other state clears the flags, phase and timer are left as they are
                gust_active <= 1'b0;
            end


            if (stalling) begin
                stall_left <= stall_left - 8'd1;
                brake_hold <= 8'd0;   // during a stall the hold is cleared, so releasing and pressing again must rebuild the full second
            end else if (braking) begin
                if (brake_hold >= STALL_HOLD - 1) begin
                    stall_left <= STALL_TICKS;   // hold values 0 through 59 are 60 ticks, about 1 second, then stall_left becomes 60
                    brake_hold <= 8'd0;
                end else
                    brake_hold <= brake_hold + 8'd1;
            end else
                brake_hold <= 8'd0;   // releasing btnu clears the hold

            
            flare_ok_n = flare_ok;           // start from the stored result, so a tick with no press keeps the old grade
            landing_grade_n = landing_grade;
            
            if ((game_state == S_FINAL_APPROACH) && flare_req && !flare_done) begin
                flare_done <= 1'b1;   // only the first press counts
                if ((altitude[23:8] <= FLARE_SOFT_HI) &&
                    (altitude[23:8] >= FLARE_SOFT_LO)) begin
                    flare_ok_n = 1'b1;
                    landing_grade_n = 2'd0;          // 18 m down to 4 m, green, and you live
                end else if (((altitude[23:8] <= FLARE_HARD_HI) && (altitude[23:8] >  FLARE_SOFT_HI)) || ((altitude[23:8] <  FLARE_SOFT_LO) && (altitude[23:8] >= FLARE_HARD_LO))) begin
                    flare_ok_n = 1'b1;
                    landing_grade_n = 2'd1;             // 28 to 19 m and 3 to 1 m, yellow, you still live
                end else begin
                    flare_ok_n = 1'b0;             // any other height, grade 2 is stored for the wobble picture
                    landing_grade_n = 2'd2;          // flare_ok 0 means you die at the ground
                end
            end
            flare_ok <= flare_ok_n;             // store this tick's flare result
            landing_grade <= landing_grade_n;   // store this tick's grade, unchanged when no press happened
            both_held_d <= both_held;           // stores both steer buttons, nothing reads it

            
            vx <= vx_n;   // keep the speed the combo block worked out
            vy <= vy_n;
            // one line gone, once per 60 ticks, the whole sprite steps +1, 0, -1, or 0, swing_dx is a different offset and moves only the body
            if ((lines_snapped == 2'd1) && (sway_div == SWAY_TICKS - 1))
                x_q <= x_q_n + sway_delta(sway_phase);
            else
                x_q <= x_q_n;   // every other tick, store x with no sway step
            hero_x <= ((lines_snapped == 2'd1) && (sway_div == SWAY_TICKS - 1))
                    ? ((x_q_n + sway_delta(sway_phase)) >>> 8)   // same sway step, then keep the pixel
                    : hero_x_n;                                  // if not, the pixel of the new x

            if (sway_div == SWAY_TICKS - 1) begin
                sway_div   <= 8'd0;             // the 60-tick counter wraps
                sway_phase <= sway_phase + 2'd1; // phase steps 0, 1, 2, 3, then back to 0
            end else
                sway_div <= sway_div + 8'd1;    // one more tick toward the next sway step

            
            y_next = y_q;
            if (cam_lock && in_flight)
                y_next = y_q + vy_n;   // camera locked = sprite falls down the screen, world stays still
            else if (braking)
                y_next = (y_q > (y_min_q + brake_rise_now)) ? (y_q - brake_rise_now) : y_min_q;   // tug rises by brake_rise_now and stops 8 px above the rest row
            else if (in_flight)
                y_next = (y_q < (y_rest_q - BRAKE_RETURN)) ? (y_q + BRAKE_RETURN) : y_rest_q;   // not tugging = sink back toward row 10 by 0.125 px per tick
            y_q <= y_next;          // store the screen y chosen above
            if (in_flight)
                hero_y <= y_next >>> 8;   // sprite row is the pixel part, outside flight, hero_y stays where it was

            if (in_freefall)   // first match wins, a stalled tug reports stalled, not braking
                canopy_mode <= CM_FREEFALL;   // 0
            else if (stalling)
                canopy_mode <= CM_STALLED;    // 3
            else if (braking)
                canopy_mode <= CM_BRAKING;    // 2
            else if (in_canopy)
                canopy_mode <= CM_OPEN;       // 1, left unchanged in menus, landing, and crash

            
            if (in_flight) begin
                // locked = count vy only, counting the on-screen drop as well would subtract the same m twice
                // unlocked = vy plus the change in screen y, a tug makes that change negative, so altitude increases
                alt_drop = cam_lock ? {vy_n[15], vy_n} : ({vy_n[15], vy_n} + {y_next[15], y_next} - {y_q[15], y_q});
                if (alt_drop > 0) begin
                    if (altitude > {7'd0, alt_drop})
                        altitude <= altitude - {7'd0, alt_drop};   // positive alt_drop subtracts, and it stops at 0
                    else
                        altitude <= 24'd0;
                end else if (alt_drop < 0) begin
                    altitude <= altitude + {7'd0, -alt_drop};   // negative alt_drop is a climb
                end
                if (!cam_lock) begin
                    // hero_y + 20 + m is the ground's screen row, sprite is 20 px tall, 1 px is 1 m, at rest y = 10 this locks near 24 m
                    if (( {8'd0, y_q[15:8]} + HERO_FRAME_H + altitude[23:8] ) <= GROUND_LOCK_Y)
                        cam_lock <= 1'b1;
                end
                if (cam_lock || (( {8'd0, y_q[15:8]} + HERO_FRAME_H + altitude[23:8] ) <= GROUND_LOCK_Y))
                    scroll_vy <= 16'sd0;   // once locked, the world stops scrolling
                else
                    scroll_vy <= vy_n;     // before that, scroll_vy is vy
            end else
                scroll_vy <= 16'sd0;

            if (game_state == S_CANOPY || game_state == S_FINAL_APPROACH) begin   // bank builds only under the canopy, and not while stunned
                if (steer_left_held && !steer_right_held && !stunned)
                    bank <= (bank <= -8'sd64 + BANK_RATE) ? -8'sd64 : bank - BANK_RATE;   // 1 per tick toward -64, a full left bank is about 1 second
                else if (steer_right_held && !steer_left_held && !stunned)
                    bank <= (bank >= 8'sd64 - BANK_RATE) ? 8'sd64 : bank + BANK_RATE;   // 1 per tick toward +64
                else if (bank > 8'sd1)  bank <= bank - 8'sd2;   // neither button = step back by 2 per tick, so it returns in about half a second
                else if (bank < -8'sd1) bank <= bank + 8'sd2;   // banked left with no button = step back toward 0 by 2
                else                    bank <= 8'sd0;   // +-1 snaps to 0
            end else bank <= 8'sd0;   // freefall and every other state flatten the bank immediately
            
            // gust_acc<<<4 kicks the body opposite the gust, so it lags, sw_x>>>4 springs it back, sw_v>>>3 damps it
            sw_v <= sw_v + (gust_active ? (gust_dir ? -(gust_acc <<< 4) : (gust_acc <<< 4)) : 16'sd0) - (sw_x >>> 4) - (sw_v >>> 3);
            sw_x <= sw_x + sw_v;   // adds the old sw_v, because both lines use <=
            if (stun_t != 7'd0) stun_t <= stun_t - 7'd1;   // a tick with no new freefall hit just counts the stun down, a hit below reloads it
            if (in_freefall && strike_pend) begin
                stun_t  <= STUN_TICKS;   // a freefall hit reloads a 1 second stun
                ff_hits <= (ff_hits == 2'd3) ? ff_hits : ff_hits + 2'd1;   // the old count is tested below, 0 means hit 1 only stuns, 1 or more means hit 2 kills
                if ((ff_hits >= 2'd1) && !ko_sent) begin     // old count was already at least 1, so this is the second hit
                    hero_crash <= 1'b1;       // one-clock crash pulse
                    crash_cause <= CC_KNOCKOUT;   // cause 3
                    ko_sent <= 1'b1;          // later hits in freefall do not pulse again
                end
            end

            if (in_flight && (lines_n >= 2'd2) && !collapse_sent) begin
                hero_crash <= 1'b1;       // one-clock crash pulse
                crash_cause <= CC_COLLAPSE;   // cause 0, uses lines_n, the count after this tick's hit
                collapse_sent <= 1'b1;        // block this pulse from firing on later ticks
            end else if (in_flight && !touch_sent && (vy_n > 0) &&
                         (altitude <= {8'd0, vy_n})) begin   // altitude will reach 0 this tick, and the sprite is still moving down
               
                touch_sent <= 1'b1;   // the ground pulse fires once
                if (flare_ok_n) begin   // green or yellow = land, red or no press falls into the else and crashes with cause 2
                    hero_landed <= 1'b1;   // one-clock landing pulse
                    // body centre is hero_x + 6 + 4/2 = hero_x + 8, the result is 1 when that centre sits inside the 16 px spot
                    landed_on_spot  <= (($signed({1'b0, hero_x_n}) + HB_BODY_X + (HB_BODY_W/2)) >= $signed({1'b0, target_x})) && (($signed({1'b0, hero_x_n}) + HB_BODY_X + (HB_BODY_W/2)) <= $signed({1'b0, target_x}) + (SPOT_W - 1));
                end else begin
                    hero_crash  <= 1'b1;          // red press, or no press at all
                    crash_cause <= CC_MISSED_FLARE;   // cause 2
                end
            end else if (in_flight && edge_hit && !collapse_sent && !touch_sent) begin   // edge is last, so a collapse or a landing on the same tick wins over it
                hero_crash  <= 1'b1;       // one-clock crash pulse
                crash_cause <= CC_EDGE;    // cause 1, the hitbox crossed x <= 2 or x >= 93
            end
        end
    end
endmodule
