// top module
/*
this is just a quick test pattern for VGA output
*/
module top (
    input  wire        CLK100MHZ,

    output reg  [3:0]  VGA_R,
    output reg  [3:0]  VGA_G,
    output reg  [3:0]  VGA_B,

    output wire        VGA_HS,
    output wire        VGA_VS
);

    wire [9:0] x;
    wire [9:0] y;
    wire       video_on;

    // VGA timing generator
    vga_timing timing (
        .clk      (CLK100MHZ),
        .x        (x),
        .y        (y),
        .hsync    (VGA_HS),
        .vsync    (VGA_VS),
        .video_on (video_on)
    );


    // color-bar test pattern
    always @(*) begin

        // black outside visible area
        VGA_R = 4'h0;
        VGA_G = 4'h0;
        VGA_B = 4'h0;

        if (video_on) begin

            if (x < 80) begin
                // white
                VGA_R = 4'hF;
                VGA_G = 4'hF;
                VGA_B = 4'hF;

            end else if (x < 160) begin
                // yellow
                VGA_R = 4'hF;
                VGA_G = 4'hF;
                VGA_B = 4'h0;

            end else if (x < 240) begin
                // cyan
                VGA_R = 4'h0;
                VGA_G = 4'hF;
                VGA_B = 4'hF;

            end else if (x < 320) begin
                // green
                VGA_R = 4'h0;
                VGA_G = 4'hF;
                VGA_B = 4'h0;

            end else if (x < 400) begin
                // magenta
                VGA_R = 4'hF;
                VGA_G = 4'h0;
                VGA_B = 4'hF;

            end else if (x < 480) begin
                // red
                VGA_R = 4'hF;
                VGA_G = 4'h0;
                VGA_B = 4'h0;

            end else if (x < 560) begin
                // blue
                VGA_R = 4'h0;
                VGA_G = 4'h0;
                VGA_B = 4'hF;

            end else begin
                // dark gray
                VGA_R = 4'h4;
                VGA_G = 4'h4;
                VGA_B = 4'h4;
            end

        end
    end

endmodule