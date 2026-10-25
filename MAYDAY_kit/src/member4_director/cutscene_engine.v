// cutscene_engine.v -- MEMBER 4. STUB: black screen for 60 ticks, then done.
// TODO(M4): 5-scene keyframe engine + 12-particle explosion (ICD Member 4 spec).
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
    reg [10:0] t;                      // own wide counter (~1,260 ticks real)
    always @(posedge clk) begin
        oled_data_cut <= 16'h0000;
        if (rst || game_state != S_CUTSCENE) begin t <= 0; cutscene_done <= 1'b0; end
        else if (game_tick) begin
            t <= t + 1'b1;
            if (t >= 11'd60) cutscene_done <= 1'b1;
        end
    end
endmodule
