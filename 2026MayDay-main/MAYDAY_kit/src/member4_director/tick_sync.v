// tick_sync.v -- MEMBER 4. Working minimal version (2-FF synchroniser +
// rising-edge detect + pause gate). Ports FINAL. Refine/own as needed.
module tick_sync (
    input  wire clk,          // 100 MHz
    input  wire frame_begin,  // from Oled_Display (6.25 MHz domain)
    input  wire pause,        // SW0
    output wire game_tick     // one 100 MHz cycle per OLED frame
);
    reg s1 = 1'b0, s2 = 1'b0, s3 = 1'b0;
    always @(posedge clk) begin
        s1 <= frame_begin;   // stage 1 (may go metastable)
        s2 <= s1;            // stage 2 (stable)
        s3 <= s2;            // previous value for edge detect
    end
    assign game_tick = s2 & ~s3 & ~pause;
endmodule
