// Simulation-only stand-in for the template's Oled_Display.v
module Oled_Display(input clk, input reset, output reg frame_begin, output sending_pixels,
  output sample_pixel, output reg [12:0] pixel_index, input [15:0] pixel_data,
  output cs, sdin, sclk, d_cn, resn, vccen, pmoden);
  initial begin frame_begin = 0; pixel_index = 0; end
  reg [5:0] c = 0;
  always @(posedge clk) begin
    c <= c + 1; frame_begin <= (c == 0);
    pixel_index <= (pixel_index == 6143) ? 0 : pixel_index + 1;
  end
  assign sending_pixels = 1; assign sample_pixel = 1;
  assign {cs, sdin, sclk, d_cn, resn, vccen, pmoden} = 7'b0;
endmodule
