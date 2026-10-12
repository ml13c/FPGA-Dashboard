// send a 25 mhz clock to the camera using the board's 100 mhz clock
// this generated clock leaves the fpga only; internal logic remains at 100 mhz
// use an mmcm/oddr-based clock output for the final video system
module camera_clock (
    input  wire clk100,
    output wire cam_xclk,
    output wire cam_resetn,
    output wire cam_pwdn
);
    // 2-bit counter cycles 0,1,2,3 every 40 ns
    reg [1:0] div4 = 2'b00;
    always @(posedge clk100)
        div4 <= div4 + 2'b01;

    // bit 1 is low for two clocks and high for two clocks = 25 mhz
    assign cam_xclk = div4[1];

    // keep the ov7670 out of power-down mode
    assign cam_pwdn = 1'b0;

    // hold the active-low reset asserted for 20 ms after fpga config
    reg [20:0] startup = 21'd0;
    always @(posedge clk100) begin
        if (startup < 21'd2000000)
            startup <= startup + 1'b1;
    end
    assign cam_resetn = (startup == 21'd2000000);
endmodule
