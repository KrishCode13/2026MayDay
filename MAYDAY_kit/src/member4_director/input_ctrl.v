// =====================================================================
// input_ctrl.v  --  MEMBER 4. Debounced buttons for MAYDAY.
// For each of BTNL, BTNR, BTNC it produces:
//   *_held  : clean level (steering, brake, flare need "is it down now?")
//   *_press : one 100 MHz-cycle pulse per physical press, with a 200 ms
//             lockout (menus and deploy need "it was pressed once")
// Pipeline per button:
//   raw pin -> 2-FF synchroniser -> sampled every 1 ms -> 5-sample
//   agreement filter (held) -> rising-edge detect + lockout (press)
// Ports: same names as the kit stub; the held outputs are now driven by a
// sub-module (wire, not reg). No change needed in My_Top_Module.v.
// =====================================================================
module input_ctrl (
    input  wire clk,
    input  wire btnL, btnR, btnC,
    output wire left_held, right_held, center_held,
    output wire left_press, right_press, center_press
);
    `include "game_params.vh"

    // ---- Shared 1 ms sample strobe ----------------------------------
    // Counts 0 .. SAMPLE_CYCLES-1 and pulses ms_tick for one cycle on wrap.
    // One strobe is shared by all three buttons to save logic.
    reg [16:0] ms_cnt  = 17'd0;
    reg        ms_tick = 1'b0;
    always @(posedge clk) begin
        if (ms_cnt == SAMPLE_CYCLES - 1) begin
            ms_cnt  <= 17'd0;
            ms_tick <= 1'b1;
        end else begin
            ms_cnt  <= ms_cnt + 1'b1;
            ms_tick <= 1'b0;
        end
    end

    // ---- One identical debouncer per button -------------------------
    btn_debounce u_l (.clk(clk), .ms_tick(ms_tick), .btn_raw(btnL),
                      .held(left_held),   .press(left_press));
    btn_debounce u_r (.clk(clk), .ms_tick(ms_tick), .btn_raw(btnR),
                      .held(right_held),  .press(right_press));
    btn_debounce u_c (.clk(clk), .ms_tick(ms_tick), .btn_raw(btnC),
                      .held(center_held), .press(center_press));
endmodule

// =====================================================================
// btn_debounce -- one button. Helper inside input_ctrl.v.
// =====================================================================
module btn_debounce (
    input  wire clk,
    input  wire ms_tick,     // 1-cycle strobe every 1 ms
    input  wire btn_raw,     // asynchronous pin
    output reg  held,        // debounced level
    output reg  press        // 1-cycle pulse, 200 ms lockout
);
    `include "game_params.vh"

    // 1) Synchroniser: the button is asynchronous to clk, so the first
    //    flop may go metastable; the second gives it a full cycle to settle.
    reg sync1, sync2;

    // 2) History of the last DEBOUNCE_SAMPLES 1 ms samples (newest in bit 0).
    reg [DEBOUNCE_SAMPLES-1:0] hist;
    wire [DEBOUNCE_SAMPLES-1:0] hist_next = {hist[DEBOUNCE_SAMPLES-2:0], sync2};

    // 3) Lockout: milliseconds left before another press may be reported.
    reg [7:0] lockout;

    initial begin
        sync1 = 1'b0; sync2 = 1'b0; hist = 0;
        held  = 1'b0; press = 1'b0; lockout = 8'd0;
    end

    always @(posedge clk) begin
        sync1 <= btn_raw;
        sync2 <= sync1;
        press <= 1'b0;                       // default: pulse lasts one cycle

        if (ms_tick) begin
            hist <= hist_next;
            if (lockout != 8'd0) lockout <= lockout - 1'b1;

            // Held changes only when ALL recent samples agree (5 ms stable).
            // Bounces shorter than that never reach held.
            if (&hist_next && !held) begin           // clean 0 -> 1
                held <= 1'b1;
                if (lockout == 8'd0) begin           // press allowed?
                    press   <= 1'b1;
                    lockout <= LOCKOUT_MS;
                end
            end else if (~|hist_next && held) begin  // clean 1 -> 0
                held <= 1'b0;
            end
        end
    end
endmodule
