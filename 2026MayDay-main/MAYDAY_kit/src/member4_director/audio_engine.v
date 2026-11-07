// =====================================================================
// audio_engine.v  --  MEMBER 4. Sound for the Digilent Pmod.
//
// The AMP2 has one audio input (AIN), its own low-pass filter and a class-D
// amplifier, so the FPGA sends a fast 1-bit stream whose average level is
// the sound: a first-order delta-sigma modulator at 100 MHz.
//
// Sound map (by game_state):
//   lobby music  : HOME, LEVEL_INTRO, LEVEL_COMPLETE, LEVEL_FAILED, VICTORY
//   soft wind    : CUTSCENE (plus explosion), CANOPY, FINAL_APPROACH
//   loud wind    : FREEFALL_LOCKED, FREEFALL_WINDOW
//   death tune   : CRASH ("wah wah wah waaah")
//   victory tune : LANDING (2 s)
//   SW1 = mute (amp shut down, output silent)
// All tunes are ORIGINAL compositions.
//   Lobby: 100 bpm pop groove, I-V-vi-IV in C, plucked syncopated lead,
//          bouncing 3-3-2 bass, kick on beats 1 and 3, clap on 2 and 4.
// Wind = noise through a 2-pole low-pass whose loudness AND brightness follow
// a gust envelope (swell ~1 s, fade ~2 s, random peak each gust) - a periodic
// "whoosh" instead of constant static.
// =====================================================================
module audio_engine (
    input  wire       clk,            // 100 MHz
    input  wire       rst,
    input  wire [3:0] game_state,
    input  wire [2:0] fail_reason,    // (reserved: all crashes use the death tune)
    input  wire       explode,        // 1-cycle pulse from cutscene_engine (explosion)
    input  wire       scene_wind,     // cutscene plane is flying -> soft wind
    input  wire       pause,          // SW0 pause -> silence and freeze the music
    input  wire       plane_on,       // plane warned or flying  -> engine drone
    input  wire       wind_on,        // a gust is blowing       -> wind
    input  wire       bird_new,       // 1-cycle pulse when a NEW bird appears -> 1 s of chirps
    input  wire       mute,           // SW1
    output reg        amp_ain = 1'b0, // Pmod AMP2 pin 1: audio in
    output wire       amp_gain,       // Pmod AMP2 pin 2: 1 = 6 dB, 0 = 12 dB
    output wire       amp_shutdown_n  // Pmod AMP2 pin 4: 0 = amplifier off
);
    `include "game_params.vh"

    assign amp_gain       = 1'b1;     // 6 dB (quieter, safer for headphones)
    assign amp_shutdown_n = ~mute;

    // ---------------- sample clock: 100 MHz / 4096 = 24.4 kHz ----------------
    reg [11:0] sdiv = 12'd0;
`ifdef AUDIO_FAST
    wire       sample_en = (sdiv[3:0] == 4'd0);   // simulation only: 16x faster, same sound
`else
    wire       sample_en = (sdiv == 12'd0);
`endif
    always @(posedge clk) sdiv <= sdiv + 12'd1;

    // ---------------- note table: 24-bit phase step per sample ----------------
    function [23:0] note_inc; input [6:0] n;
        case (n)
            7'd40: note_inc = 24'd56630;   // E2 82.4 Hz
            7'd41: note_inc = 24'd59997;   // F2 87.3 Hz
            7'd42: note_inc = 24'd63565;   // Fs2 92.5 Hz
            7'd43: note_inc = 24'd67344;   // G2 98.0 Hz
            7'd44: note_inc = 24'd71349;   // Gs2 103.8 Hz
            7'd45: note_inc = 24'd75591;   // A2 110.0 Hz
            7'd46: note_inc = 24'd80086;   // As2 116.5 Hz
            7'd47: note_inc = 24'd84849;   // B2 123.5 Hz
            7'd48: note_inc = 24'd89894;   // C3 130.8 Hz
            7'd49: note_inc = 24'd95239;   // Cs3 138.6 Hz
            7'd50: note_inc = 24'd100902;   // D3 146.8 Hz
            7'd51: note_inc = 24'd106902;   // Ds3 155.6 Hz
            7'd52: note_inc = 24'd113259;   // E3 164.8 Hz
            7'd53: note_inc = 24'd119994;   // F3 174.6 Hz
            7'd54: note_inc = 24'd127129;   // Fs3 185.0 Hz
            7'd55: note_inc = 24'd134689;   // G3 196.0 Hz
            7'd56: note_inc = 24'd142698;   // Gs3 207.7 Hz
            7'd57: note_inc = 24'd151183;   // A3 220.0 Hz
            7'd58: note_inc = 24'd160173;   // As3 233.1 Hz
            7'd59: note_inc = 24'd169697;   // B3 246.9 Hz
            7'd60: note_inc = 24'd179788;   // C4 261.6 Hz
            7'd61: note_inc = 24'd190478;   // Cs4 277.2 Hz
            7'd62: note_inc = 24'd201805;   // D4 293.7 Hz
            7'd63: note_inc = 24'd213805;   // Ds4 311.1 Hz
            7'd64: note_inc = 24'd226518;   // E4 329.6 Hz
            7'd65: note_inc = 24'd239988;   // F4 349.2 Hz
            7'd66: note_inc = 24'd254258;   // Fs4 370.0 Hz
            7'd67: note_inc = 24'd269377;   // G4 392.0 Hz
            7'd68: note_inc = 24'd285395;   // Gs4 415.3 Hz
            7'd69: note_inc = 24'd302366;   // A4 440.0 Hz
            7'd70: note_inc = 24'd320345;   // As4 466.2 Hz
            7'd71: note_inc = 24'd339394;   // B4 493.9 Hz
            7'd72: note_inc = 24'd359575;   // C5 523.3 Hz
            7'd73: note_inc = 24'd380957;   // Cs5 554.4 Hz
            7'd74: note_inc = 24'd403610;   // D5 587.3 Hz
            7'd75: note_inc = 24'd427610;   // Ds5 622.3 Hz
            7'd76: note_inc = 24'd453037;   // E5 659.3 Hz
            7'd77: note_inc = 24'd479976;   // F5 698.5 Hz
            7'd78: note_inc = 24'd508516;   // Fs5 740.0 Hz
            7'd79: note_inc = 24'd538754;   // G5 784.0 Hz
            7'd80: note_inc = 24'd570790;   // Gs5 830.6 Hz
            7'd81: note_inc = 24'd604731;   // A5 880.0 Hz
            7'd82: note_inc = 24'd640691;   // As5 932.3 Hz
            7'd83: note_inc = 24'd678788;   // B5 987.8 Hz
            7'd84: note_inc = 24'd719151;   // C6 1046.5 Hz
            7'd85: note_inc = 24'd761914;   // Cs6 1108.7 Hz
            7'd86: note_inc = 24'd807220;   // D6 1174.7 Hz
            7'd87: note_inc = 24'd855219;   // Ds6 1244.5 Hz
            7'd88: note_inc = 24'd906073;   // E6 1318.5 Hz

            default: note_inc = 24'd0;      // 0 = rest
        endcase
    endfunction

    // ---------------- ORIGINAL tunes ----------------
    // Lobby: 64 sixteenth-notes at 100 bpm (0.15 s each) = 9.6 s loop
    function [6:0] lobby_mel; input [5:0] i;
        case (i)
            6'd0: lobby_mel = 7'd0;
            6'd1: lobby_mel = 7'd0;
            6'd2: lobby_mel = 7'd76;
            6'd3: lobby_mel = 7'd0;
            6'd4: lobby_mel = 7'd79;
            6'd5: lobby_mel = 7'd0;
            6'd6: lobby_mel = 7'd76;
            6'd7: lobby_mel = 7'd74;
            6'd8: lobby_mel = 7'd0;
            6'd9: lobby_mel = 7'd72;
            6'd10: lobby_mel = 7'd0;
            6'd11: lobby_mel = 7'd74;
            6'd12: lobby_mel = 7'd76;
            6'd13: lobby_mel = 7'd0;
            6'd14: lobby_mel = 7'd0;
            6'd15: lobby_mel = 7'd0;
            6'd16: lobby_mel = 7'd0;
            6'd17: lobby_mel = 7'd0;
            6'd18: lobby_mel = 7'd74;
            6'd19: lobby_mel = 7'd0;
            6'd20: lobby_mel = 7'd79;
            6'd21: lobby_mel = 7'd0;
            6'd22: lobby_mel = 7'd74;
            6'd23: lobby_mel = 7'd72;
            6'd24: lobby_mel = 7'd0;
            6'd25: lobby_mel = 7'd71;
            6'd26: lobby_mel = 7'd0;
            6'd27: lobby_mel = 7'd72;
            6'd28: lobby_mel = 7'd74;
            6'd29: lobby_mel = 7'd0;
            6'd30: lobby_mel = 7'd0;
            6'd31: lobby_mel = 7'd0;
            6'd32: lobby_mel = 7'd0;
            6'd33: lobby_mel = 7'd0;
            6'd34: lobby_mel = 7'd72;
            6'd35: lobby_mel = 7'd0;
            6'd36: lobby_mel = 7'd76;
            6'd37: lobby_mel = 7'd0;
            6'd38: lobby_mel = 7'd72;
            6'd39: lobby_mel = 7'd71;
            6'd40: lobby_mel = 7'd0;
            6'd41: lobby_mel = 7'd69;
            6'd42: lobby_mel = 7'd0;
            6'd43: lobby_mel = 7'd71;
            6'd44: lobby_mel = 7'd72;
            6'd45: lobby_mel = 7'd0;
            6'd46: lobby_mel = 7'd76;
            6'd47: lobby_mel = 7'd0;
            6'd48: lobby_mel = 7'd77;
            6'd49: lobby_mel = 7'd0;
            6'd50: lobby_mel = 7'd76;
            6'd51: lobby_mel = 7'd0;
            6'd52: lobby_mel = 7'd74;
            6'd53: lobby_mel = 7'd0;
            6'd54: lobby_mel = 7'd72;
            6'd55: lobby_mel = 7'd0;
            6'd56: lobby_mel = 7'd0;
            6'd57: lobby_mel = 7'd69;
            6'd58: lobby_mel = 7'd0;
            6'd59: lobby_mel = 7'd72;
            6'd60: lobby_mel = 7'd74;
            6'd61: lobby_mel = 7'd0;
            6'd62: lobby_mel = 7'd0;
            6'd63: lobby_mel = 7'd0;
            default: lobby_mel = 7'd0;
        endcase
    endfunction
    function [6:0] lobby_bass; input [5:0] i;
        case (i)
            6'd0: lobby_bass = 7'd48;
            6'd1: lobby_bass = 7'd0;
            6'd2: lobby_bass = 7'd0;
            6'd3: lobby_bass = 7'd60;
            6'd4: lobby_bass = 7'd0;
            6'd5: lobby_bass = 7'd0;
            6'd6: lobby_bass = 7'd48;
            6'd7: lobby_bass = 7'd0;
            6'd8: lobby_bass = 7'd60;
            6'd9: lobby_bass = 7'd0;
            6'd10: lobby_bass = 7'd0;
            6'd11: lobby_bass = 7'd48;
            6'd12: lobby_bass = 7'd0;
            6'd13: lobby_bass = 7'd60;
            6'd14: lobby_bass = 7'd0;
            6'd15: lobby_bass = 7'd0;
            6'd16: lobby_bass = 7'd43;
            6'd17: lobby_bass = 7'd0;
            6'd18: lobby_bass = 7'd0;
            6'd19: lobby_bass = 7'd55;
            6'd20: lobby_bass = 7'd0;
            6'd21: lobby_bass = 7'd0;
            6'd22: lobby_bass = 7'd43;
            6'd23: lobby_bass = 7'd0;
            6'd24: lobby_bass = 7'd55;
            6'd25: lobby_bass = 7'd0;
            6'd26: lobby_bass = 7'd0;
            6'd27: lobby_bass = 7'd43;
            6'd28: lobby_bass = 7'd0;
            6'd29: lobby_bass = 7'd55;
            6'd30: lobby_bass = 7'd0;
            6'd31: lobby_bass = 7'd0;
            6'd32: lobby_bass = 7'd45;
            6'd33: lobby_bass = 7'd0;
            6'd34: lobby_bass = 7'd0;
            6'd35: lobby_bass = 7'd57;
            6'd36: lobby_bass = 7'd0;
            6'd37: lobby_bass = 7'd0;
            6'd38: lobby_bass = 7'd45;
            6'd39: lobby_bass = 7'd0;
            6'd40: lobby_bass = 7'd57;
            6'd41: lobby_bass = 7'd0;
            6'd42: lobby_bass = 7'd0;
            6'd43: lobby_bass = 7'd45;
            6'd44: lobby_bass = 7'd0;
            6'd45: lobby_bass = 7'd57;
            6'd46: lobby_bass = 7'd0;
            6'd47: lobby_bass = 7'd0;
            6'd48: lobby_bass = 7'd41;
            6'd49: lobby_bass = 7'd0;
            6'd50: lobby_bass = 7'd0;
            6'd51: lobby_bass = 7'd53;
            6'd52: lobby_bass = 7'd0;
            6'd53: lobby_bass = 7'd0;
            6'd54: lobby_bass = 7'd41;
            6'd55: lobby_bass = 7'd0;
            6'd56: lobby_bass = 7'd53;
            6'd57: lobby_bass = 7'd0;
            6'd58: lobby_bass = 7'd0;
            6'd59: lobby_bass = 7'd41;
            6'd60: lobby_bass = 7'd0;
            6'd61: lobby_bass = 7'd53;
            6'd62: lobby_bass = 7'd0;
            6'd63: lobby_bass = 7'd0;
            default: lobby_bass = 7'd0;
        endcase
    endfunction
    // Victory: 16 steps of 0.125 s = 2 s rising fanfare
    function [6:0] vic_mel; input [3:0] i;
        case (i)
            4'd0: vic_mel = 7'd72;
            4'd1: vic_mel = 7'd76;
            4'd2: vic_mel = 7'd79;
            4'd3: vic_mel = 7'd84;
            4'd4: vic_mel = 7'd79;
            4'd5: vic_mel = 7'd84;
            4'd6: vic_mel = 7'd88;
            4'd7: vic_mel = 7'd0;
            4'd8: vic_mel = 7'd84;
            4'd9: vic_mel = 7'd84;
            4'd10: vic_mel = 7'd84;
            4'd11: vic_mel = 7'd84;
            4'd12: vic_mel = 7'd84;
            4'd13: vic_mel = 7'd84;
            4'd14: vic_mel = 7'd0;
            4'd15: vic_mel = 7'd0;
            default: vic_mel = 7'd0;
        endcase
    endfunction
    function [6:0] vic_bass; input [3:0] i;
        case (i)
            4'd0: vic_bass = 7'd48;
            4'd1: vic_bass = 7'd55;
            4'd2: vic_bass = 7'd60;
            4'd3: vic_bass = 7'd55;
            4'd4: vic_bass = 7'd53;
            4'd5: vic_bass = 7'd57;
            4'd6: vic_bass = 7'd60;
            4'd7: vic_bass = 7'd57;
            4'd8: vic_bass = 7'd55;
            4'd9: vic_bass = 7'd59;
            4'd10: vic_bass = 7'd62;
            4'd11: vic_bass = 7'd59;
            4'd12: vic_bass = 7'd48;
            4'd13: vic_bass = 7'd48;
            4'd14: vic_bass = 7'd0;
            4'd15: vic_bass = 7'd0;
            default: vic_bass = 7'd0;
        endcase
    endfunction
    // Death: "wah wah wah waaah" - three falling notes then a long low one (0.15 s steps)
    function [6:0] die_mel; input [3:0] i;
        case (i)
            4'd0: die_mel = 7'd67;
            4'd1: die_mel = 7'd67;
            4'd2: die_mel = 7'd0;
            4'd3: die_mel = 7'd66;
            4'd4: die_mel = 7'd66;
            4'd5: die_mel = 7'd0;
            4'd6: die_mel = 7'd65;
            4'd7: die_mel = 7'd65;
            4'd8: die_mel = 7'd0;
            4'd9: die_mel = 7'd64;
            4'd10: die_mel = 7'd64;
            4'd11: die_mel = 7'd64;
            4'd12: die_mel = 7'd64;
            4'd13: die_mel = 7'd64;
            4'd14: die_mel = 7'd64;
            4'd15: die_mel = 7'd0;
            default: die_mel = 7'd0;
        endcase
    endfunction

    // ---------------- which sound ----------------
    // sound map: gameplay is EVENT-driven - plane > wind > bird > silence.
    // The cutscene and plain falling are silent.
    localparam M_MUSIC = 3'd0, M_SOFT = 3'd1, M_LOUD = 3'd2, M_VICTORY = 3'd3, M_DEATH = 3'd4,
               M_SILENT = 3'd5, M_PLANE = 3'd6, M_BIRD = 3'd7;
    // chirp only for 1 s after each new bird (not the whole time it is on screen)
    reg [14:0] bird_t = 15'd0;
    reg        bird_new_l = 1'b0;
    always @(posedge clk) if (bird_new) bird_new_l <= 1'b1; else if (sample_en) bird_new_l <= 1'b0;
    wire       bird_on = (bird_t != 15'd0);
    wire in_play = (game_state >= S_FREEFALL_LOCKED) && (game_state <= S_FINAL_APPROACH);
    reg [2:0] mode;
    always @* begin
        if (in_play)
            mode = plane_on ? M_PLANE : wind_on ? M_LOUD : bird_on ? M_BIRD : M_SILENT;
        else case (game_state)
            S_CUTSCENE: mode = M_SOFT;     // soft wind while the plane flies + explosion
            S_CRASH:    mode = M_DEATH;
            S_LANDING:  mode = M_VICTORY;
            default:    mode = M_MUSIC;
        endcase
    end
    reg [2:0] mode_d = 3'd0;

    // ---------------- sequencer ----------------
    reg [12:0] step_cnt = 13'd0;
    reg [5:0]  step = 6'd0;
    wire [12:0] step_len = (mode == M_VICTORY) ? 13'd3052 : 13'd3662;   // 0.125 s / 0.15 s
    wire [6:0]  mel_note  = (mode == M_VICTORY) ? vic_mel(step[3:0])  :
                            (mode == M_DEATH)   ? die_mel(step[3:0])  : lobby_mel(step);
    wire [6:0]  bass_note = (mode == M_VICTORY) ? vic_bass(step[3:0]) :
                            (mode == M_DEATH)   ? 7'd0                : lobby_bass(step);
    reg [23:0] ph_mel = 24'd0, ph_bass = 24'd0, ph_kick = 24'd0;
    reg [5:0]  env = 6'd0;            // melody envelope
    reg [5:0]  kick_env = 6'd0;  reg [23:0] kick_inc = 24'd0;
    reg [5:0]  clap_env = 6'd0;
    reg [6:0]  vib = 7'd0;            // vibrato counter for the last death note

    // ---------------- noise, gusting wind, explosion ----------------
    reg [15:0] lfsr = 16'hACE1;
    wire signed [11:0] noise = {{4{lfsr[7]}}, lfsr[7:0]};   // -128..127
    reg signed [11:0] w1 = 12'sd0, w2 = 12'sd0;   // 2-pole low-pass
    reg [7:0]  gust = 8'd60;          // gust envelope (loudness + brightness)
    reg [7:0]  gust_peak = 8'd200;
    reg        gust_up = 1'b1;
    reg [8:0]  gdiv = 9'd0;           // envelope update divider
    reg [9:0]  boom_env = 10'd0;
    reg signed [11:0] boom_lp = 12'sd0;
    reg explode_l = 1'b0;
    always @(posedge clk) if (explode) explode_l <= 1'b1; else if (sample_en) explode_l <= 1'b0;

    // brightness: louder gust -> faster filter (higher cutoff)
    wire [1:0] wk = (gust > 8'd170) ? 2'd2 : (gust > 8'd100) ? 2'd3 : 2'd0;   // 2,3 or (0 -> 4)
    wire signed [11:0] d1 = noise - w1;
    wire signed [11:0] d2 = w1 - w2;
    wire signed [11:0] step1 = (wk == 2'd2) ? (d1 >>> 2) : (wk == 2'd3) ? (d1 >>> 3) : (d1 >>> 4);
    wire signed [23:0] wind_w = w2 * $signed({4'd0, gust});
    wire signed [23:0] boom_w = boom_lp * $signed({2'd0, boom_env});

    // bird chirps - two quick falling "tweets" every ~0.55 s
    reg [13:0] chirp_t = 14'd0;                 // samples since the chirp pattern began
    reg [23:0] chirp_inc = 24'd0, ph_chirp = 24'd0;
    wire       chirp_on = (chirp_t < 14'd1200) || (chirp_t >= 14'd2400 && chirp_t < 14'd3600);
    wire signed [11:0] chirp_sq = chirp_on ? (ph_chirp[23] ? 12'sd30 : -12'sd30) : 12'sd0;
    // plane engine - 85 Hz + 170 Hz buzz with a 12 Hz propeller throb and some rumble
    reg [23:0] ph_e1 = 24'd0, ph_e2 = 24'd0;
    reg [11:0] prop = 12'd0;                    // propeller throb counter (~12 Hz)
    wire [5:0] prop_amp = prop[11] ? ~prop[10:5] : prop[10:5];   // triangle 0..63
    wire signed [11:0] eng_raw = (ph_e1[23] ? 12'sd28 : -12'sd28) + (ph_e2[23] ? 12'sd14 : -12'sd14)
                                 + (noise >>> 3);
    wire signed [23:0] eng_w = eng_raw * $signed({6'd0, 6'd40 + prop_amp[5:2]});
    reg signed [11:0] mix = 12'sd0;
    wire signed [11:0] mel_sq  = (mel_note  == 7'd0) ? 12'sd0 : (ph_mel[23]  ? $signed({6'd0, env}) : -$signed({6'd0, env}));
    wire signed [11:0] bass_sq = (bass_note == 7'd0) ? 12'sd0 : (ph_bass[23] ? 12'sd34 : -12'sd34);
    wire signed [11:0] kick_sq = ph_kick[23] ? $signed({6'd0, kick_env}) : -$signed({6'd0, kick_env});
    wire signed [23:0] clap_w  = noise * $signed({6'd0, clap_env});   // full width before shifting
    wire signed [11:0] clap_n  = clap_w[17:6];

    always @(posedge clk) begin
        if (rst) begin
            step <= 6'd0; step_cnt <= 13'd0; ph_mel <= 24'd0; ph_bass <= 24'd0;
            boom_env <= 10'd0; mix <= 12'sd0; mode_d <= M_MUSIC;
        end else if (sample_en && !pause) begin            // everything freezes while paused
            mode_d <= mode;
            if (bird_new_l)            bird_t <= 15'd24414;     // 1 s
            else if (bird_t != 15'd0)  bird_t <= bird_t - 15'd1;
            if (mode != mode_d) begin                       // new sound: start from the top
                step <= 6'd0; step_cnt <= 13'd0; env <= 6'd63;
            end else if (step_cnt >= step_len - 1) begin
                step_cnt <= 13'd0;
                env      <= 6'd63;
                if (mode == M_VICTORY || mode == M_DEATH)
                    step <= (step[3:0] == 4'd15) ? step : step + 6'd1;   // play once, hold the end
                else
                    step <= step + 6'd1;                                   // 64-step loop
                // drums on the lobby groove
                if (mode == M_MUSIC && step[1:0] == 2'b11) begin
                    if (step[3:2] == 2'b11 || step[3:2] == 2'b01) begin clap_env <= 6'd40; end  // beats 2, 4
                    else begin kick_env <= 6'd60; kick_inc <= note_inc(7'd52); end           // beats 1, 3
                end
            end else begin
                step_cnt <= step_cnt + 13'd1;
                // pluck: lobby lead decays fast; fanfare/death sustain
                if (mode == M_MUSIC) begin if (step_cnt[5:0] == 6'd0 && env > 6'd6) env <= env - 6'd1; end
                else if (mode == M_VICTORY) begin if (step_cnt[6:0] == 7'd0 && env > 6'd24) env <= env - 6'd1; end
                else env <= 6'd48;
                if (step_cnt[4:0] == 5'd0) begin
                    if (kick_env != 6'd0) kick_env <= kick_env - 6'd2;
                    if (clap_env != 6'd0) clap_env <= clap_env - 6'd2;
                    kick_inc <= kick_inc - (kick_inc >> 4);                    // pitch drop
                end
            end
            vib <= vib + 7'd1;
            // death tune: wobble the last long note (vibrato)
            ph_mel  <= ph_mel + note_inc(mel_note) +
                       (((mode == M_DEATH) && step[3:0] >= 4'd9 && vib[6]) ? 24'd3000 : 24'd0);
            ph_bass <= ph_bass + note_inc(bass_note);
            ph_kick <= ph_kick + kick_inc;

            // noise + gusting wind
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            w1   <= w1 + step1;
            w2   <= w2 + (d2 >>> 2);
            gdiv <= gdiv + 9'd1;
            if (gdiv[6:0] == 7'd0) begin                                   // ~5 ms steps
                // the whoosh swells in when a gust starts and fades when it ends
                if (mode == M_LOUD) begin if (gust < 8'd230) gust <= gust + 8'd3; end
                else if (mode == M_SOFT && scene_wind) begin   // gentle steady cabin wind
                    if (gust < 8'd120) gust <= gust + 8'd2; else if (gust > 8'd124) gust <= gust - 8'd2;
                end
                else if (gust > 8'd3) gust <= gust - 8'd3; else gust <= 8'd0;
            end
            // explosion: full burst, decays over ~1.3 s
            if (explode_l)               boom_env <= 10'd1023;
            else if (boom_env != 10'd0 && step_cnt[4:0] == 5'd0) boom_env <= boom_env - 10'd1;
            boom_lp <= boom_lp + ((noise - boom_lp) >>> 3);

            // chirp / engine oscillators
            if (mode == M_BIRD) begin
                chirp_t <= (chirp_t >= 14'd13400) ? 14'd0 : chirp_t + 14'd1;
                if (chirp_t == 14'd0 || chirp_t == 14'd2400) chirp_inc <= 24'd2405000;   // 3.5 kHz
                else if (chirp_inc > 24'd1500000) chirp_inc <= chirp_inc - 24'd700;    // sweep down
                ph_chirp <= ph_chirp + chirp_inc;
            end else chirp_t <= 14'd0;
            ph_e1 <= ph_e1 + 24'd58410;      // ~85 Hz
            ph_e2 <= ph_e2 + 24'd116820;     // ~170 Hz
            prop  <= prop + 12'd2;           // ~12 Hz throb

            // ---- mixer (about -300..300) ----
            case (mode)
                M_MUSIC:            mix <= mel_sq + bass_sq + kick_sq + clap_n;
                M_VICTORY, M_DEATH: mix <= mel_sq + bass_sq;
                M_LOUD:             mix <= $signed(wind_w[17:6]) + ($signed(wind_w[17:6]) >>> 1);   // gust whoosh
                M_PLANE:            mix <= $signed(eng_w[17:6]);                                      // engine drone
                M_BIRD:             mix <= chirp_sq;                                                  // chirps
                M_SOFT:             mix <= $signed(wind_w[17:6]) + $signed(boom_w[19:8]);            // cutscene wind (x2) + explosion
                default:            mix <= (gust != 8'd0) ? $signed(wind_w[17:6]) : 12'sd0;         // silence (wind tail fades)
            endcase
        end
    end

    // ---------------- 1st-order delta-sigma DAC at 100 MHz ----------------
    wire [9:0] level = (mute || pause) ? 10'd512 : (10'd512 + mix[9:0]);   // pause = silent
    reg  [10:0] acc = 11'd0;
    always @(posedge clk) begin
        acc     <= {1'b0, acc[9:0]} + {1'b0, level};
        amp_ain <= acc[10];
    end
endmodule
