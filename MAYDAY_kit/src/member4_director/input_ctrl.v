// input_ctrl.v -- MEMBER 4. STUB: synchronises buttons and makes press
// pulses but does NOT debounce yet. Ports FINAL.
// TODO(M4): debounced held levels + 200 ms lockout press pulses (1 ms sampling).
module input_ctrl (
    input  wire clk,
    input  wire btnL, btnR, btnC,
    output reg  left_held, right_held, center_held,
    output wire left_press, right_press, center_press
);
    reg l_d = 0, r_d = 0, c_d = 0;
    always @(posedge clk) begin
        left_held <= btnL;  right_held <= btnR;  center_held <= btnC;
        l_d <= left_held;   r_d <= right_held;   c_d <= center_held;
    end
    assign left_press   = left_held   & ~l_d;
    assign right_press  = right_held  & ~r_d;
    assign center_press = center_held & ~c_d;
endmodule
