// snake
// led state: empty (dark), snake (light), food (blink), 1 led: 2 bits
// map: 16 * 16 * led = 16 * 16 * 2 bits
// food position: 8 bits, snake position: 256 * 8 bits
// ticks: 0.5 s = 2 Hz, led matrix refresh = clk: 2048 Hz = 2^(-11) s, food blink: 4 Hz = 0.25 s

module final (
    input 
        clk, // posedge
        reset, // pos level
        up, down, left, right, // snake direction
    output reg [0:15] led_row, led_col,
    output reg [7:0] lcd_db,
    output reg
        lcd_rs, // 0: command, 1: data
        lcd_rw, // 0: write, 1: X
        lcd_en, // 1 -> 0
        lcd_rst // 1: clear
);
    parameter // i means instruction
        i_hide_cursor = 8'b11111100,
        i_show_cursor = 8'b11111101,
        i_show_cursor_flash = 8'b11111111,
        i_flash_character = 8'b11111011,
        i_invert_character = 8'b11110111,
        i_default_character = 8'b11101111;

    reg [4:0] state;
    parameter // s means state
        s_reset = 0,
        s_refresh_led_matrix = 1,
        s_update_snake = 3,
        s_update_snake_loop = 2,
        s_update_map = 4,
        s_generate_food = 10,
        s_generate_food_loop = 7,
        s_update_lcd = 12,
        s_lcd_prepare = 8,
        s_lcd_write = 9,
        s_game_over = 5,
        s_game_over_loop = 11,
        s_game_win = 6,
        s_game_win_loop = 13;
        
    reg gameover;
    parameter win_score = 10;
    wire game_win; assign game_win = snake_length == win_score;

    reg [9:0] counter;
    reg [1:0] map [0:255];
    parameter // m means map
        m_empty = 0, m_snake = 1, m_food = 2;
    
    reg [7:0] snake [0:255]; // 0 (head) ~ snake_length - 1 (tail)
    reg [7:0] snake_length;
    reg [7:0] food;
    
    wire [7:0] snake_head; assign snake_head = snake[0];
    wire [7:0] snake_neck; assign snake_neck = snake[1]; // no neck when snake_length < 2
    wire [7:0] snake_tail; assign snake_tail = snake[snake_length - 1];
    
    wire on_wall_top; assign on_wall_top = snake_head < 16;
    wire on_wall_bottom; assign on_wall_bottom = snake_head > 239;
    wire on_wall_left; assign on_wall_left = snake_head % 16 < 1;
    wire on_wall_right; assign on_wall_right = snake_head % 16 > 14;
    
    wire [7:0] head_top; assign head_top = snake_head - 16;
    wire [7:0] head_bottom; assign head_bottom = snake_head + 16;
    wire [7:0] head_left; assign head_left = snake_head - 1;
    wire [7:0] head_right; assign head_right = snake_head + 1;
    
    wire [7:0] snake_next_head; assign snake_next_head =
        snake_direction == d_up ? head_top :
        snake_direction == d_down ? head_bottom :
        snake_direction == d_left ? head_left :
        snake_direction == d_right ? head_right : 8'bxxxxxxxx;

    reg [1:0] snake_direction;
    parameter // snake direction
        d_up = 0,
        d_down = 1,
        d_left = 2,
        d_right = 3;
    
    parameter lcd_from_lowercase = 8'h41 - "a";
    parameter lcd_from_uppercase = 8'h21 - "A";
    parameter lcd_from_number = 8'h10;
    parameter lcd_char_space = 8'h00;
    parameter lcd_char_exclamation = 8'h01;
    parameter lcd_char_colon = 8'h1A;
    reg [7:0] lcd_text [0:15];
    
    reg [7:0] i, j, k;

    always @(posedge clk) begin
        if (reset) begin
            snake_length <= 5;
            snake[0] <= 128;
            snake[1] <= 129;
            snake[2] <= 130;
            snake[3] <= 131;
            snake[4] <= 132;
            food <= 190;
            counter <= 0;
            snake_direction <= d_up;
            
            // clear map
            for (i = 0; i < 16; i = i + 1)
                for (j = 0; j < 16; j = j + 1)  
                    map[i * 16 + j] <= 0;
            
            lcd_rst <= 1;
            lcd_text[0] <= "L" + lcd_from_uppercase;
            lcd_text[1] <= "e" + lcd_from_lowercase;
            lcd_text[2] <= "n" + lcd_from_lowercase;
            lcd_text[3] <= "g" + lcd_from_lowercase;
            lcd_text[4] <= "t" + lcd_from_lowercase;
            lcd_text[5] <= "h" + lcd_from_lowercase;
            lcd_text[6] <= lcd_char_colon; // :
            for (i = 7; i < 16; i = i + 1) begin
                lcd_text[i] <= lcd_char_space;
            end
            
            state <= s_reset;
            gameover <= 0;
        end
        else begin
            case (state)
                s_reset: begin
                    map[snake_head] <= m_snake; // draw head
                    map[food] <= m_food; // draw food
                    
                    lcd_rst <= 0;
                    lcd_en <= 1;
                    
                    state <= s_generate_food;
                end
                s_refresh_led_matrix: begin
                    led_row <= 16'b1000000000000000 >> counter[3:0];
                    for (i = 0; i < 16; i = i + 1) begin
                        case (map[counter[3:0] * 16 + i])
                            m_empty: led_col[i] <= 0; // dark
                            m_snake: led_col[i] <= 1; // light
                            m_food: led_col[i] <= counter[9]; // blink
                        endcase
                    end
                    counter = counter + 1;

                    // change direction, prevent go back (head go to neck)
                    if (up && (snake_length == 1 || on_wall_top || head_top != snake_neck)) snake_direction <= d_up;
                    else if (down && (snake_length == 1 || on_wall_bottom || head_bottom != snake_neck)) snake_direction <= d_down;
                    else if (left && (snake_length == 1 || on_wall_left || head_left != snake_neck)) snake_direction <= d_left;
                    else if (right && (snake_length == 1 || on_wall_right || head_right != snake_neck)) snake_direction <= d_right;

                    if (counter == 0) begin // reach game tick
                        if (
                            // if bump into wall 
                            (snake_direction == d_up && on_wall_top) ||
                            (snake_direction == d_down && on_wall_bottom) ||
                            (snake_direction == d_left && on_wall_left) ||
                            (snake_direction == d_right && on_wall_right) ||
                            // or eat itself
                            (map[snake_next_head] == m_snake && snake_next_head != snake_tail)
                        ) begin // then game over
                            state <= s_game_over;
                        end
                        else if (game_win) begin // game win
                            state <= s_game_win;
                        end
                        else if (map[snake_next_head] == m_food) begin // eat food
                            snake_length <= snake_length + 1;
                            
                            state <= s_generate_food;
                        end
                        else begin // normal move
                            map[snake_tail] <= m_empty; // erase tail
                            
                            state <= s_update_snake;
                        end
                    end
                end
                s_generate_food: begin
                    i <= 0; // map index
                    j <= $urandom_range(256 - snake_length - 1); // random j-th empty grid
                    
                    state <= s_generate_food_loop;
                end
                s_generate_food_loop: begin // find index of j-th empty grid, do 8 bits at per clock
                    repeat (8) begin
                        if (j != 0) begin
                            if (map[i] == m_empty) j = j - 1;
                            if (j != 0) i = i + 1;
                        end
                    end
                    
                    if (j == 0) begin
                        food = i;
                        map[i] = m_food;
                        
                        state <= s_update_lcd;
                        binary2lcd (lcd_text[8], lcd_text[9], lcd_text[10], snake_length);
                    end
                end
                s_update_lcd: begin
                    lcd_rst <= 1;
                    lcd_rw <= 0;
                    lcd_rs <= 1;
                    i <= 0;
                    
                    state <= s_lcd_prepare;
                end
                s_lcd_prepare: begin
                    lcd_rst <= 0;
                    lcd_en <= 1;
                    lcd_db <= lcd_text[i];
                    
                    state <= s_lcd_write;
                end
                s_lcd_write: begin
                    lcd_en <= 0;
                    if (i != 15) begin
                        i <= i + 1;
                        state <= s_lcd_prepare;
                    end
                    else state <= 
                        gameover ? s_game_over_loop :
                        game_win ? s_game_win_loop :
                        s_update_snake;
                end
                s_update_snake: begin
                    i <= 255; // shift snake from back
                    
                    state <= s_update_snake_loop;
                end
                s_update_snake_loop: begin // seperate 256 input circuit to 8 input * 32 clocks loop
                    repeat (8) begin // update snake body
                        if (i != 0) begin // prevent snake[-1]
                            snake[i] = snake[i - 1];
                            i = i - 1;
                        end
                    end
                    if (i == 0) begin
                        snake[0] <= snake_next_head; // update snake head
                        map[snake_next_head] <= m_snake; // draw new head
                        
                        state <= s_refresh_led_matrix;
                    end
                end
                s_game_over: begin
                    lcd_text[0] <= "G" + lcd_from_uppercase;
                    lcd_text[1] <= "a" + lcd_from_lowercase;
                    lcd_text[2] <= "m" + lcd_from_lowercase;
                    lcd_text[3] <= "e" + lcd_from_lowercase;
                    lcd_text[4] <= lcd_char_space;
                    lcd_text[5] <= "O" + lcd_from_uppercase;
                    lcd_text[6] <= "v" + lcd_from_lowercase;
                    lcd_text[7] <= "e" + lcd_from_lowercase;
                    lcd_text[8] <= "r" + lcd_from_lowercase;
                    for (i = 9; i < 16; i = i + 1) lcd_text[i] <= lcd_char_space;
                    
                    gameover <= 1;
                    state <= s_update_lcd;
                end
                s_game_win: begin
                    lcd_text[0] <= "Y" + lcd_from_uppercase;
                    lcd_text[1] <= "o" + lcd_from_lowercase;
                    lcd_text[2] <= "u" + lcd_from_lowercase;
                    lcd_text[3] <= lcd_char_space;
                    lcd_text[4] <= "W" + lcd_from_uppercase;
                    lcd_text[5] <= "i" + lcd_from_uppercase;
                    lcd_text[6] <= "n" + lcd_from_lowercase;
                    lcd_text[7] <= lcd_char_exclamation;
                    for (i = 8; i < 16; i = i + 1) lcd_text[i] <= lcd_char_space;
                    
                    state <= s_update_lcd;
                end
            endcase
        end
    end
    
    

    task binary2lcd (
        output [7:0] hundreds, tens, units,
        input [7:0] in
    );
        integer i;
        reg [11:0] out;
        
        begin
            out = 0;
            for (i = 0; i < 8; i = i + 1) begin
                if (out[3:0] >= 5) out[3:0] = out[3:0] + 3;
                if (out[7:4] >= 5) out[7:4] = out[7:4] + 3;
                if (out[11:8] >= 5) out[11:8] = out[11:8] + 3;
                
                out = {out[10:0], in[7-i]};
                
                hundreds = out[11:8] == 0 ? lcd_char_space : (out[11:8] + lcd_from_number);
                tens = out[11:4] == 0 ? lcd_char_space : (out[7:4] + lcd_from_number);
                units = out[3:0] + lcd_from_number;
            end
        end
    endtask
endmodule