// Wires every member's module together exactly as in docs/ICD.md.

module My_Top_Module (
    input  wire        clk,          // 100 MHz
    input  wire        btnC, btnU, btnL, btnR, btnD,
    input  wire [15:0] sw,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an,
    output wire [7:0]  JC,           //  OLED
    output wire [3:0]  JXADC         // PmodAmp2 
);
    `include "game_params.vh"

    // ---------------- Clocks ---------------------------------------
    reg [2:0] div = 3'd0;            // 100 MHz / 16 = 6.25 MHz
    reg       clk6p25m = 1'b0;
    always @(posedge clk) begin
        div <= div + 1'b1;
        if (div == 3'd7) clk6p25m <= ~clk6p25m;
    end

    wire rst   = sw[15];     //If sw[15] is on, then we reset everything to HOME page. But user must switch off sw[15] to play the "refreshed" game again
    wire pause = sw[0];
    wire mute  = sw[1];  

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
    assign JC[2] = 1'b0;  //header pin is not used by Oled 

    // ---------------- Member 4: tick, inputs, director --------------
    wire raw_tick;
    tick_sync u_tick (.clk(clk), .frame_begin(frame_begin), .pause(pause), .game_tick(raw_tick));

    wire game_tick;    //this is gna be the main tick which runs the game. 1 pulse per OLed frame
    reg  [1:0] slow_cnt = 2'd0;  //this is another ticking speed for the slow_mo segment during landing 
    wire [3:0]  game_state; // there are 12 diff game states 
    wire [23:0] altitude; 
    wire slowmo = (game_state == S_FINAL_APPROACH) && (altitude[23:8] <= SLOWMO_ALT);
    always @(posedge clk)
        if (raw_tick) slow_cnt <= (slow_cnt == SLOWMO_DIV - 1) ? 2'd0 : slow_cnt + 2'd1;
    assign game_tick = raw_tick && (!slowmo || (slow_cnt == 2'd0));

    wire left_held, right_held, center_held, left_press, right_press, center_press;
    wire up_held, up_press;  
    input_ctrl u_in (.clk(clk), .btnL(btnL), .btnR(btnR),
        .btnC(btnC), .btnU(btnU),
        .left_held(left_held), .right_held(right_held), .center_held(center_held), .up_held(up_held),
        .left_press(left_press), .right_press(right_press), .center_press(center_press), .up_press(up_press));

    wire [2:0] level;      wire level_start;
    wire [7:0]  state_timer;  wire [15:0] seed;      wire [2:0] menu_cursor;
    wire [2:0]  stars_earned; wire [9:0] best_stars; wire [3:0] total_stars;
    wire [2:0]  crates_got;   wire [2:0] fail_reason; 
    wire        cutscene_done;

    // Member 1 outputs
    wire signed [7:0]  hero_x, hero_y;
    wire signed [15:0] scroll_vy;
    wire [1:0]  canopy_mode, lines_snapped, gust_strength, deploy_grade;
    wire [2:0]  crash_cause;                  
    wire [1:0]  landing_grade;                
    wire [1:0]  bank_lvl;  wire bank_left;  wire signed [2:0] swing_dx;  wire stunned;   
    wire        damaged_side, gust_warn, gust_active, gust_dir;
    wire        hero_crash, hero_landed, landed_on_spot;

    // Member 2 outputs
    wire [47:0] obs_x, obs_y;  wire [11:0] obs_type;  wire [5:0] obs_active, obs_flip;
    wire [31:0] crate_x, crate_y;  wire [3:0] crate_active;
    wire signed [7:0] warn_x;  wire warn_active, warn_edge;
    wire [7:0]  target_x;
    wire        strike, strike_side, crate_collected, magnet_active;
    wire        plane_busy;   
    wire        explode;      
    wire        flare_locked; 
    wire        scene_wind;  
    wire        gust_request, pwarn_active, pwarn_right;  wire signed [7:0] pwarn_y;   
    wire [1:0]  strike_lines;  wire [2:0] crates_level_total;  wire [8:0] magnet_ticks_left;

    game_director u_dir (
        .clk(clk), .rst(rst), .game_tick(game_tick),
        .left_press(left_press), .right_press(right_press), .center_press(center_press),
        .sw_skip(1'b0), .cutscene_done(cutscene_done),
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
        .steer_left_held(left_held), .steer_right_held(right_held), .flare_press(center_press), .brake_held(up_held), 
        .crate_collected(crate_collected), .gust_request(gust_request),   
        .plane_busy(plane_busy),   
        .flare_locked(flare_locked),   
        .bank_lvl(bank_lvl), .bank_left(bank_left), .swing_dx(swing_dx), .stunned(stunned),   
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
        .gust_warn(gust_warn), .gust_active(gust_active),                 
        .gust_request(gust_request), .pwarn_active(pwarn_active), .pwarn_right(pwarn_right), .pwarn_y(pwarn_y),
        .plane_busy(plane_busy),   
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
        .pwarn_active(pwarn_active), .pwarn_right(pwarn_right), .pwarn_y(pwarn_y),   
        .flare_locked(flare_locked),   
        .bank_lvl(bank_lvl), .bank_left(bank_left), .swing_dx(swing_dx), .stunned(stunned),  
        .oled_data_game(oled_data_game));

    // ---------------- Member 4: cutscene + displays -----------------
    cutscene_engine u_cut (
        .clk(clk), .rst(rst), .game_tick(game_tick), .game_state(game_state), .level(level),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .oled_data_cut(oled_data_cut), .cutscene_done(cutscene_done),
        .center_press(center_press),   
        .scene_wind(scene_wind),       
        .explode(explode));

   
    wire [5:0] bird_slots = {obs_type[11:10] == OBS_BIRD, obs_type[9:8] == OBS_BIRD, obs_type[7:6] == OBS_BIRD,
                             obs_type[5:4]   == OBS_BIRD, obs_type[3:2] == OBS_BIRD, obs_type[1:0] == OBS_BIRD};
    reg  [5:0] obs_active_d = 6'd0;
    always @(posedge clk) obs_active_d <= obs_active;
    wire bird_new = |(obs_active & ~obs_active_d & bird_slots);

     // ---------------- audio -----------------
    audio_engine u_audio (.clk(clk), .rst(rst), .game_state(game_state), .explode(explode), .mute(mute),
        .plane_on(plane_busy), .wind_on(gust_active), .bird_new(bird_new),
        .scene_wind(scene_wind), .pause(pause),   
        .fail_reason(fail_reason),
        .amp_ain(JXADC[0]), .amp_gain(JXADC[1]), .amp_shutdown_n(JXADC[3]));
    assign JXADC[2] = 1'b0;

    assign oled_data = (game_state == S_CUTSCENE) ? oled_data_cut : oled_data_game;

    // ---------------- what should display on the anode segments -----------------

    seg7_ctrl u_seg (.clk(clk), .game_state(game_state), .level(level), .menu_cursor(menu_cursor),
        .altitude(altitude), .stars_earned(stars_earned), .total_stars(total_stars),
        .seg(seg), .dp(dp), .an(an));

     // ---------------- led0 to led15 control -----------------
    led_ctrl u_led (.clk(clk), .game_tick(game_tick), .game_state(game_state), .state_timer(state_timer),
        .altitude(altitude), .gust_warn(gust_warn), .gust_active(gust_active),
        .gust_dir(gust_dir), .gust_strength(gust_strength),
        .magnet_active(magnet_active), .magnet_ticks_left(magnet_ticks_left),
        .stars_earned(stars_earned), .led(led));
endmodule
