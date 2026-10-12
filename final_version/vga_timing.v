module vga_timing (
    input  wire        clk,
    output reg  [9:0]  x,
    output reg  [9:0]  y,
    output wire        hsync,
    output wire        vsync,
    output wire        video_on
);

    reg [1:0] pixel_cnt = 0;
    wire pixel_tick;

    assign pixel_tick = (pixel_cnt == 2'b11);

    always @(posedge clk)
        pixel_cnt <= pixel_cnt + 1'b1;

    initial begin
        x = 0;
        y = 0;
    end

    always @(posedge clk) begin
        if (pixel_tick) begin
            if (x == 10'd799) begin
                x <= 10'd0;

                if (y == 10'd524)
                    y <= 10'd0;
                else
                    y <= y + 1'b1;
            end
            else begin
                x <= x + 1'b1;
            end
        end
    end

    assign hsync = ~((x >= 10'd656) && (x < 10'd752));
    assign vsync = ~((y >= 10'd490) && (y < 10'd492));
    assign video_on = (x < 10'd640) && (y < 10'd480);

endmodule
