// =====================================================================
// palette.v  --  MEMBER 3 (32-entry RGB565 Colour Palette & Swapper)
// Translates a 5-bit sprite/layer colour index into 16-bit RGB565.
// Environment indices (3, 4, 12, 13, 15) swap based on level setting
// during gameplay; menus always use the Day palette.
// =====================================================================
module palette (
    input  wire [4:0]  color_idx,
    input  wire [2:0]  level,
    input  wire        is_menu,
    output reg  [15:0] rgb565
);

    localparam [1:0] SET_DAY    = 2'd0;
    localparam [1:0] SET_NIGHT  = 2'd1;
    localparam [1:0] SET_SUNSET = 2'd2;

    reg [1:0] setting;
    always @* begin
        if (is_menu) begin
            setting = SET_DAY;
        end else begin
            case (level)
                3'd2, 3'd4: setting = SET_NIGHT;
                3'd5:       setting = SET_SUNSET;
                default:    setting = SET_DAY;
            endcase
        end
    end

    always @* begin
        case (color_idx)
            5'd0:  rgb565 = 16'h0000; // Transparent
            5'd1:  rgb565 = 16'h0000; // Black
            5'd2:  rgb565 = 16'hFFFF; // White
            5'd3: begin               // Clouds
                case (setting)
                    SET_NIGHT:  rgb565 = 16'h298A;
                    SET_SUNSET: rgb565 = 16'hF518;
                    default:    rgb565 = 16'hDEDB;
                endcase
            end
            5'd4: begin               // Birds/Lines
                case (setting)
                    SET_NIGHT:  rgb565 = 16'hC618;
                    default:    rgb565 = 16'h528A;
                endcase
            end
            5'd5:  rgb565 = 16'hFC60; // Canopy orange
            5'd6:  rgb565 = 16'hC280; // Canopy shading
            5'd7:  rgb565 = 16'h194D; // Navy
            5'd8:  rgb565 = 16'hF612; // Skin
            5'd9:  rgb565 = 16'h8AC5; // Brown
            5'd10: rgb565 = 16'hFEA0; // Gold
            5'd11: rgb565 = 16'hE104; // Red
            5'd12: begin              // Ground main
                case (setting)
                    SET_NIGHT:  rgb565 = 16'h39C8;
                    SET_SUNSET: rgb565 = 16'h11C3;
                    default:    rgb565 = 16'h3506;
                endcase
            end
            5'd13: begin              // Ground detail
                case (setting)
                    SET_NIGHT:  rgb565 = 16'hFEA0;
                    SET_SUNSET: rgb565 = 16'h0000;
                    default:    rgb565 = 16'h1B43;
                endcase
            end
            5'd14: rgb565 = 16'h371E; // Cyan
            5'd15: begin              // Sky base
                case (setting)
                    SET_NIGHT:  rgb565 = 16'h0885;
                    SET_SUNSET: rgb565 = 16'h69D1;
                    default:    rgb565 = 16'h4D5F;
                endcase
            end
            5'd16: rgb565 = 16'hCE7A; // Silver
            5'd17: rgb565 = 16'h7C11; // Steel
            5'd18: rgb565 = 16'hEE4F; // Sand
            5'd19: rgb565 = 16'h2709; // Bright green
            5'd20: rgb565 = 16'hDE98; // Cabin beige
            5'd21: rgb565 = 16'h5AEC; // Tarmac
            5'd22: rgb565 = 16'hB7FF; // Ice-cyan wind streak highlight
            5'd23: rgb565 = 16'hFD80; // Bright flame amber for plane debris
            5'd24: rgb565 = 16'h9000; // Deep crimson alert banner background
            default: rgb565 = 16'h0000;
        endcase
    end
endmodule
