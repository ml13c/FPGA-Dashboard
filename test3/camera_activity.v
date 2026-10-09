// diagnostic only: sample async timing pins in the 100 mhz clock domain
// detect whether any rising edges occurred during the last observation window
// this is NOT the pixel capture circuit. capture will use pclk as its own clock.
module camera_activity #(
    parameter integer WINDOW_CYCLES = 100000000
) (
    input  wire clk100,
    input  wire cam_pclk,
    input  wire cam_vsync,
    input  wire cam_href,
    output reg  pclk_seen_last_window = 1'b0,
    output reg  vsync_seen_last_window = 1'b0,
    output reg  href_seen_last_window = 1'b0
);
    // two-flop synchronizers for diagnostic status only
    (* ASYNC_REG = "TRUE" *) reg [1:0] pclk_sync  = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] vsync_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] href_sync  = 2'b00;

    reg pclk_last  = 1'b0;
    reg vsync_last = 1'b0;
    reg href_last  = 1'b0;
    reg saw_pclk   = 1'b0;
    reg saw_vsync  = 1'b0;
    reg saw_href   = 1'b0;
    reg [26:0] window_counter = 27'd0;

    always @(posedge clk100) begin
        pclk_sync  <= {pclk_sync[0],  cam_pclk};
        vsync_sync <= {vsync_sync[0], cam_vsync};
        href_sync  <= {href_sync[0],  cam_href};

        pclk_last  <= pclk_sync[1];
        vsync_last <= vsync_sync[1];
        href_last  <= href_sync[1];

        if (pclk_sync[1]  && !pclk_last)  saw_pclk  <= 1'b1;
        if (vsync_sync[1] && !vsync_last) saw_vsync <= 1'b1;
        if (href_sync[1]  && !href_last)  saw_href  <= 1'b1;

        if (window_counter == WINDOW_CYCLES - 1) begin
            window_counter         <= 27'd0;
            pclk_seen_last_window  <= saw_pclk  | (pclk_sync[1]  && !pclk_last);
            vsync_seen_last_window <= saw_vsync | (vsync_sync[1] && !vsync_last);
            href_seen_last_window  <= saw_href  | (href_sync[1]  && !href_last);
            saw_pclk               <= 1'b0;
            saw_vsync              <= 1'b0;
            saw_href               <= 1'b0;
        end else begin
            window_counter <= window_counter + 1'b1;
        end
    end
endmodule
