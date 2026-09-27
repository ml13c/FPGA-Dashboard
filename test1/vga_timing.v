
/*
    VGA timing module for 640x480 resolution
    running at 25 MHzz since board has 100 MHz clock and we advance every 4 clock cycles
*/
module vga_timing (
    input  wire        clk,
    output reg  [9:0]  x,
    output reg  [9:0]  y,
    output wire        hsync,
    output wire        vsync,
    output wire        video_on
);

    // 25 MHz VGA pixel rate
    reg [1:0] pixel_cnt = 0;

    wire pixel_tick;

    assign pixel_tick = (pixel_cnt == 2'b11);

    always @(posedge clk) begin
        pixel_cnt <= pixel_cnt + 1'b1;
    end

    // 640x480 VGA timing
    // horizontal:
    // 640 visible
    // 16 front porch
    // 96 sync
    // 48 back porch
    // 800 total
    //
    // vertical:
    // 480 visible
    // 10 front porch
    // 2 sync
    // 33 back porch
    // 525 total

    initial begin
        x = 0;
        y = 0;
    end

    always @(posedge clk) begin
        if (pixel_tick) begin

            if (x == 799) begin
                x <= 0;

                if (y == 524)
                    y <= 0;
                else
                    y <= y + 1'b1;

            end else begin
                x <= x + 1'b1;
            end

        end
    end

    // active-low sync pulses
    assign hsync = ~((x >= 656) && (x < 752));
    assign vsync = ~((y >= 490) && (y < 492));

    // visible region
    assign video_on = (x < 640) && (y < 480);

endmodule