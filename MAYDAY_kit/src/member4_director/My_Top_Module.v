// =====================================================================
// My_Top_Module.v  --  MAYDAY top level. OWNER: Member 4 ONLY.
// Wires every member's module together exactly as in docs/ICD.md.
// OLED on Pmod header JC (JC[7:0] = JX[0..7] in the lab manual).
// =====================================================================
module My_Top_Module (
    input  wire        clk,          // 100 MHz, W5
    input  wire        btnC, btnU, btnL, btnR, btnD,
    input  wire [15:0] sw,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an,
    output wire [7:0]  JC            // Pmod OLED
);
    `include "game_params.vh"

    // ---------------- Clocks ---------------------------------------
    reg [2:0] div = 3'd0;            // 100 MHz / 16 = 6.25 MHz
    reg       clk6p25m = 1'b0;
    always @(posedge clk) begin
        div <= div + 1'b1;
        if (div == 3'd7) clk6p25m <= ~clk6p25m;
    end

    wire rst   = sw[15];
    wire pause = sw[0];
    wire skip  = sw[1];

    // ---------------- OLED + pixel coordinates ----------------------
    wire        frame_begin, sending_pixels, sample_pixel;
    wire [12:0] pixel_index;
    wire [15:0] oled_data;
    wire [6:0]  pixel_x = pixel_index % 96;
    wire [5:0]  pixel_y = pixel_index / 96;

    Oled_Display oled (
        .clk(clk6p25m), .reset(1'b0),
        .frame_begin(frame_begin), .sending_pixels(sending_pixels),
        .sample_pixel(sample_pixel), .pixel_index(pixel_index),
        .pixel_data(oled_data),
        .cs(JC[0]), .sdin(JC[1]), .sclk(JC[3]), .d_cn(JC[4]),
        .resn(JC[5]), .vccen(JC[6]), .pmoden(JC[7])
    );
    assign JC[2] = 1'b0;

    // ---------------- Member 4: tick, inputs, director --------------
    wire game_tick;
    tick_sync u_tick (.clk(clk), .frame_begin(frame_begin), .pause(pause), .game_tick(game_tick));

    wire left_held, right_held, center_held, left_press, right_press, center_press;
    input_ctrl u_in (.clk(clk), .btnL(btnL), .btnR(btnR), .btnC(btnC),
        .left_held(left_held), .right_held(right_held), .center_held(center_held),
        .left_press(left_press), .right_press(right_press), .center_press(center_press));

    wire [3:0]  game_state;   wire [2:0] level;      wire level_start;
    wire [7:0]  state_timer;  wire [15:0] seed;      wire [2:0] menu_cursor;
    wire [2:0]  stars_earned; wire [9:0] best_stars; wire [3:0] total_stars;
    wire [2:0]  crates_got;   wire [1:0] fail_reason;
    wire        cutscene_done;

    // Member 1 outputs
    wire signed [7:0]  hero_x, hero_y;
    wire signed [15:0] scroll_vy;
    wire [23:0] altitude;
    wire [1:0]  canopy_mode, lines_snapped, gust_strength, deploy_grade, crash_cause;
    wire        damaged_side, gust_warn, gust_active, gust_dir;
    wire        hero_crash, hero_landed, landing_grade, landed_on_spot;

    // Member 2 outputs
    wire [47:0] obs_x, obs_y;  wire [11:0] obs_type;  wire [5:0] obs_active, obs_flip;
    wire [31:0] crate_x, crate_y;  wire [3:0] crate_active;
    wire signed [7:0] warn_x;  wire warn_active, warn_edge;
    wire [7:0]  target_x;
    wire        strike, strike_side, crate_collected, magnet_active;
    wire [1:0]  strike_lines;  wire [2:0] crates_level_total;  wire [8:0] magnet_ticks_left;

    game_director u_dir (
        .clk(clk), .rst(rst), .game_tick(game_tick),
        .left_press(left_press), .right_press(right_press), .center_press(center_press),
        .sw_skip(skip), .cutscene_done(cutscene_done),
        .altitude(altitude), .hero_crash(hero_crash), .crash_cause(crash_cause),
        .hero_landed(hero_landed), .landing_grade(landing_grade), .landed_on_spot(landed_on_spot),
        .lines_snapped(lines_snapped),
        .crate_collected(crate_collected), .crates_level_total(crates_level_total),
        .game_state(game_state), .level(level), .level_start(level_start),
        .state_timer(state_timer), .seed(seed), .menu_cursor(menu_cursor),
        .stars_earned(stars_earned), .best_stars(best_stars), .total_stars(total_stars),
        .crates_got(crates_got), .fail_reason(fail_reason));

    // ---------------- Member 1: physics ----------------------------
    physics_engine u_phys (
        .clk(clk), .rst(rst), .game_tick(game_tick), .game_state(game_state), .level(level),
        .level_start(level_start), .state_timer(state_timer), .seed(seed),
        .steer_left_held(left_held), .steer_right_held(right_held),
        .strike(strike), .strike_side(strike_side), .strike_lines(strike_lines), .target_x(target_x),
        .hero_x(hero_x), .hero_y(hero_y), .scroll_vy(scroll_vy), .altitude(altitude),
        .canopy_mode(canopy_mode), .lines_snapped(lines_snapped), .damaged_side(damaged_side),
        .gust_warn(gust_warn), .gust_active(gust_active), .gust_dir(gust_dir), .gust_strength(gust_strength),
        .deploy_grade(deploy_grade), .hero_crash(hero_crash), .crash_cause(crash_cause),
        .hero_landed(hero_landed), .landing_grade(landing_grade), .landed_on_spot(landed_on_spot));

    // ---------------- Member 2: world -------------------------------
    world_engine u_world (
        .clk(clk), .rst(rst), .game_tick(game_tick), .game_state(game_state), .level(level),
        .level_start(level_start), .seed(seed),
        .hero_x(hero_x), .hero_y(hero_y), .scroll_vy(scroll_vy), .altitude(altitude),
        .canopy_mode(canopy_mode), .deploy_grade(deploy_grade),
        .obs_x(obs_x), .obs_y(obs_y), .obs_type(obs_type), .obs_active(obs_active), .obs_flip(obs_flip),
        .crate_x(crate_x), .crate_y(crate_y), .crate_active(crate_active),
        .warn_x(warn_x), .warn_active(warn_active), .warn_edge(warn_edge), .target_x(target_x),
        .strike(strike), .strike_side(strike_side), .strike_lines(strike_lines),
        .crate_collected(crate_collected), .crates_level_total(crates_level_total),
        .magnet_active(magnet_active), .magnet_ticks_left(magnet_ticks_left));

    // ---------------- Member 3: rendering ---------------------------
    wire [15:0] oled_data_game, oled_data_cut;
    render_engine u_rend (
        .clk(clk), .rst(rst), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .game_tick(game_tick), .game_state(game_state), .level(level), .level_start(level_start),
        .state_timer(state_timer), .menu_cursor(menu_cursor), .stars_earned(stars_earned),
        .best_stars(best_stars), .total_stars(total_stars), .crates_got(crates_got), .fail_reason(fail_reason),
        .hero_x(hero_x), .hero_y(hero_y), .scroll_vy(scroll_vy), .altitude(altitude),
        .canopy_mode(canopy_mode), .lines_snapped(lines_snapped), .damaged_side(damaged_side),
        .gust_warn(gust_warn), .gust_active(gust_active), .gust_dir(gust_dir), .gust_strength(gust_strength),
        .landing_grade(landing_grade),
        .obs_x(obs_x), .obs_y(obs_y), .obs_type(obs_type), .obs_active(obs_active), .obs_flip(obs_flip),
        .crate_x(crate_x), .crate_y(crate_y), .crate_active(crate_active),
        .warn_x(warn_x), .warn_active(warn_active), .warn_edge(warn_edge), .target_x(target_x),
        .strike(strike), .crate_collected(crate_collected), .crates_level_total(crates_level_total),
        .magnet_active(magnet_active),
        .oled_data_game(oled_data_game));

    // ---------------- Member 4: cutscene + displays -----------------
    cutscene_engine u_cut (
        .clk(clk), .rst(rst), .game_tick(game_tick), .game_state(game_state), .level(level),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .oled_data_cut(oled_data_cut), .cutscene_done(cutscene_done));

    assign oled_data = (game_state == S_CUTSCENE) ? oled_data_cut : oled_data_game;

    seg7_ctrl u_seg (.clk(clk), .game_state(game_state), .level(level), .menu_cursor(menu_cursor),
        .altitude(altitude), .stars_earned(stars_earned), .total_stars(total_stars),
        .seg(seg), .dp(dp), .an(an));

    led_ctrl u_led (.clk(clk), .game_tick(game_tick), .game_state(game_state), .state_timer(state_timer),
        .altitude(altitude), .gust_warn(gust_warn), .gust_active(gust_active),
        .gust_dir(gust_dir), .gust_strength(gust_strength),
        .magnet_active(magnet_active), .magnet_ticks_left(magnet_ticks_left),
        .stars_earned(stars_earned), .led(led));
endmodule
