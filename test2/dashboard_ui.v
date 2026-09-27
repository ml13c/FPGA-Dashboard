module dashboard_ui (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire        video_on,
    input  wire [7:0]  speed,
    input  wire [3:0]  battery,
    input  wire        warning,
    input  wire        turn_left,
    input  wire        turn_right,
    output reg  [11:0] rgb
);

    wire [7:0] hundreds;
    wire [7:0] tens;
    wire [7:0] ones;

    wire [15:0] speed_scaled;
    wire [7:0]  speed_bar_width;
    wire [7:0]  battery_bar_width;

    assign hundreds = speed / 8'd100;
    assign tens     = (speed % 8'd100) / 8'd10;
    assign ones     = speed % 8'd10;

    assign speed_scaled = speed * 8'd160;
    assign speed_bar_width = speed_scaled[15:8];

    assign battery_bar_width = battery * 8'd8;

    function seg_pixel;
        input [3:0] digit;
        input [9:0] px;
        input [9:0] py;
        input [9:0] x0;
        input [9:0] y0;

        reg [6:0] seg;
        reg a;
        reg b;
        reg c;
        reg d;
        reg e;
        reg f;
        reg g;

        begin
            case (digit)
                4'd0: seg = 7'b1111110;
                4'd1: seg = 7'b0110000;
                4'd2: seg = 7'b1101101;
                4'd3: seg = 7'b1111001;
                4'd4: seg = 7'b0110011;
                4'd5: seg = 7'b1011011;
                4'd6: seg = 7'b1011111;
                4'd7: seg = 7'b1110000;
                4'd8: seg = 7'b1111111;
                4'd9: seg = 7'b1111011;
                default: seg = 7'b0000000;
            endcase

            a = seg[6] &&
                (px >= x0 + 10'd5) &&
                (px <  x0 + 10'd25) &&
                (py >= y0) &&
                (py <  y0 + 10'd5);

            b = seg[5] &&
                (px >= x0 + 10'd25) &&
                (px <  x0 + 10'd30) &&
                (py >= y0 + 10'd5) &&
                (py <  y0 + 10'd25);

            c = seg[4] &&
                (px >= x0 + 10'd25) &&
                (px <  x0 + 10'd30) &&
                (py >= y0 + 10'd30) &&
                (py <  y0 + 10'd50);

            d = seg[3] &&
                (px >= x0 + 10'd5) &&
                (px <  x0 + 10'd25) &&
                (py >= y0 + 10'd50) &&
                (py <  y0 + 10'd55);

            e = seg[2] &&
                (px >= x0) &&
                (px <  x0 + 10'd5) &&
                (py >= y0 + 10'd30) &&
                (py <  y0 + 10'd50);

            f = seg[1] &&
                (px >= x0) &&
                (px <  x0 + 10'd5) &&
                (py >= y0 + 10'd5) &&
                (py <  y0 + 10'd25);

            g = seg[0] &&
                (px >= x0 + 10'd5) &&
                (px <  x0 + 10'd25) &&
                (py >= y0 + 10'd25) &&
                (py <  y0 + 10'd30);

            seg_pixel = a | b | c | d | e | f | g;
        end
    endfunction

    always @(*) begin
        rgb = 12'h000;

        if (video_on) begin
            // main background
            rgb = 12'h012;

            // top status strip
            if ((x >= 10'd20) && (x < 10'd620) &&
                (y >= 10'd20) && (y < 10'd55))
                rgb = 12'h124;

            // speed panel outer area
            if ((x >= 10'd25) && (x < 10'd220) &&
                (y >= 10'd85) && (y < 10'd260))
                rgb = 12'h234;

            // speed panel inner area
            if ((x >= 10'd30) && (x < 10'd215) &&
                (y >= 10'd90) && (y < 10'd255))
                rgb = 12'h012;

            // speed digits
            if (seg_pixel(hundreds[3:0], x, y, 10'd55,  10'd115) ||
                seg_pixel(tens[3:0],     x, y, 10'd95,  10'd115) ||
                seg_pixel(ones[3:0],     x, y, 10'd135, 10'd115))
                rgb = 12'h0FF;

            // blank leading hundreds digit when speed < 100
            if ((speed < 8'd100) &&
                (x >= 10'd55) && (x < 10'd85) &&
                (y >= 10'd115) && (y < 10'd170))
                rgb = 12'h012;

            // blank leading tens digit when speed < 10
            if ((speed < 8'd10) &&
                (x >= 10'd95) && (x < 10'd125) &&
                (y >= 10'd115) && (y < 10'd170))
                rgb = 12'h012;

            // speed bar border
            if ((x >= 10'd45) && (x < 10'd207) &&
                (y >= 10'd205) && (y < 10'd232))
                rgb = 12'h777;

            // speed bar background
            if ((x >= 10'd46) && (x < 10'd206) &&
                (y >= 10'd206) && (y < 10'd231))
                rgb = 12'h111;

            // speed bar fill
            if ((x >= 10'd46) &&
                (x < (10'd46 + speed_bar_width)) &&
                (y >= 10'd206) && (y < 10'd231))
                rgb = 12'h0CF;

            // camera placeholder border
            if ((x >= 10'd250) && (x < 10'd590) &&
                (y >= 10'd90) && (y < 10'd350))
                rgb = 12'h456;

            // camera placeholder interior
            if ((x >= 10'd255) && (x < 10'd585) &&
                (y >= 10'd95) && (y < 10'd345))
                rgb = 12'h001;

            // camera placeholder grid
            if ((x >= 10'd255) && (x < 10'd585) &&
                (y >= 10'd95) && (y < 10'd345) &&
                ((x[5:0] == 6'd0) || (y[5:0] == 6'd0)))
                rgb = 12'h123;

            // battery outline
            if ((x >= 10'd440) && (x < 10'd565) &&
                (y >= 10'd30) && (y < 10'd48))
                rgb = 12'hAAA;

            // battery interior
            if ((x >= 10'd442) && (x < 10'd562) &&
                (y >= 10'd32) && (y < 10'd46))
                rgb = 12'h111;

            // battery fill
            if ((x >= 10'd442) &&
                (x < (10'd442 + battery_bar_width)) &&
                (y >= 10'd32) && (y < 10'd46))
                rgb = (battery < 4'd4) ? 12'hF20 : 12'h0F3;

            // battery terminal
            if ((x >= 10'd565) && (x < 10'd572) &&
                (y >= 10'd34) && (y < 10'd44))
                rgb = 12'hAAA;

            // left turn indicator
            if (turn_left &&
                (x >= 10'd45) && (x < 10'd85) &&
                (y >= 10'd35) && (y < 10'd45))
                rgb = 12'hFD0;

            if (turn_left &&
                (x >= 10'd35) && (x < 10'd55) &&
                (y >= 10'd30) && (y < 10'd50))
                rgb = 12'hFD0;

            // right turn indicator
            if (turn_right &&
                (x >= 10'd555) && (x < 10'd595) &&
                (y >= 10'd35) && (y < 10'd45))
                rgb = 12'hFD0;

            if (turn_right &&
                (x >= 10'd585) && (x < 10'd605) &&
                (y >= 10'd30) && (y < 10'd50))
                rgb = 12'hFD0;

            // bottom status panel
            if ((x >= 10'd25) && (x < 10'd615) &&
                (y >= 10'd380) && (y < 10'd445))
                rgb = 12'h123;

            // simulated telemetry bars
            if ((x >= 10'd55) && (x < 10'd165) &&
                (y >= 10'd400) && (y < 10'd415))
                rgb = 12'h0A4;

            if ((x >= 10'd55) && (x < 10'd125) &&
                (y >= 10'd422) && (y < 10'd432))
                rgb = 12'h08C;

            // warning overlay gets highest priority
            if (warning &&
                (x >= 10'd170) && (x < 10'd470) &&
                (y >= 10'd390) && (y < 10'd435)) begin

                if ((x < 10'd180) || (x >= 10'd460) ||
                    (y < 10'd400) || (y >= 10'd425))
                    rgb = 12'hFF0;
                else
                    rgb = 12'hF00;
            end
        end
    end

endmodule
