module top (
    input  wire        CLK100MHZ,
    input  wire [15:0] SW,
    input  wire        BTNC,
    input  wire        BTNL,
    input  wire        BTNR,

    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS
);

    wire [9:0] x;
    wire [9:0] y;
    wire       video_on;
    wire [11:0] rgb;

    vga_timing timing (
        .clk      (CLK100MHZ),
        .x        (x),
        .y        (y),
        .hsync    (VGA_HS),
        .vsync    (VGA_VS),
        .video_on (video_on)
    );

    dashboard_ui ui (
        .x          (x),
        .y          (y),
        .video_on   (video_on),
        .speed      (SW[7:0]),
        .battery    (SW[15:12]),
        .warning    (BTNC),
        .turn_left  (BTNL),
        .turn_right (BTNR),
        .rgb        (rgb)
    );

    assign VGA_R = video_on ? rgb[11:8] : 4'h0;
    assign VGA_G = video_on ? rgb[7:4]  : 4'h0;
    assign VGA_B = video_on ? rgb[3:0]  : 4'h0;

endmodule
