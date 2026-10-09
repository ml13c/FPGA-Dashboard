// stage 4: verify that real pixel data reaches the fpga from the ov7670
// this is a diagnostic, not an image framebuffer or a color decoder
module camera_pixel_activity (
    input  wire       clk100,
    input  wire       cam_pclk,
    input  wire       cam_vsync,
    input  wire       cam_href,
    input  wire [7:0] cam_d,
    input  wire       cam_resetn,
    output reg        pixel_bytes_seen = 1'b0,
    output reg        line_count_ok = 1'b0,
    output reg  [7:0] data_bits_changed = 8'b0
);
    // pixel domain: sample d0-d7 ONLY when the camera says a line is active.
    // a rising vsync ends the current frame and snapshots its measurements.
    // camera outputs should be synchronous to its pclk; this module uses pclk.
    reg href_prev = 1'b0;
    reg vsync_prev = 1'b0;
    reg [7:0] prev_d = 8'h00;
    reg have_prev = 1'b0;
    reg [7:0] change_mask = 8'h00;
    reg [23:0] byte_count = 24'd0;
    reg [10:0] line_count = 11'd0;

    // req/ack handshake holds the entire multi-bit snapshot stable while it
    // passes from the camera pixel clock domain into the 100 mhz led domain.
    reg req_toggle = 1'b0;
    reg snap_bytes = 1'b0;
    reg snap_lines = 1'b0;
    reg [7:0] snap_mask = 8'h00;
    reg ack_toggle = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [2:0] req_sync = 3'b000;

    always @(posedge cam_pclk or negedge cam_resetn) begin
        if (!cam_resetn) begin
            href_prev <= 1'b0;
            vsync_prev <= 1'b0;
            prev_d <= 8'h00;
            have_prev <= 1'b0;
            change_mask <= 8'h00;
            byte_count <= 24'd0;
            line_count <= 11'd0;
            req_toggle <= 1'b0;
            snap_bytes <= 1'b0;
            snap_lines <= 1'b0;
            snap_mask <= 8'h00;
            ack_sync <= 2'b00;
        end else begin
            ack_sync <= {ack_sync[0], ack_toggle};
            href_prev <= cam_href;
            vsync_prev <= cam_vsync;

            if (cam_vsync && !vsync_prev) begin
                // capture the frame that has just finished, if the previous
                // snapshot has already been consumed by the 100 mhz logic.
                if (req_toggle == ack_sync[1]) begin
                    snap_bytes <= (byte_count >= 24'd100);
                    // expected ~480 lines at vga or ~240 lines at qvga
                    snap_lines <= (line_count >= 11'd200 &&
                                   line_count <= 11'd800);
                    snap_mask <= change_mask;
                    req_toggle <= ~req_toggle;
                end
                byte_count <= 24'd0;
                line_count <= 11'd0;
                change_mask <= 8'h00;
                have_prev <= 1'b0;
            end else if (cam_href && !cam_vsync) begin
                if (!href_prev && line_count != 11'h7ff)
                    line_count <= line_count + 1'b1;

                if (byte_count != 24'hffffff)
                    byte_count <= byte_count + 1'b1;

                if (have_prev)
                    change_mask <= change_mask | (cam_d ^ prev_d);
                prev_d <= cam_d;
                have_prev <= 1'b1;
            end
        end
    end

    always @(posedge clk100) begin
        req_sync <= {req_sync[1:0], req_toggle};
        if (req_sync[2] != ack_toggle) begin
            // the pixel-domain snapshot is stable until this acknowledgment;
            // req passes through a 3-stage synchronizer before we read it.
            pixel_bytes_seen <= snap_bytes;
            line_count_ok <= snap_lines;
            data_bits_changed <= snap_mask;
            ack_toggle <= req_sync[2];
        end
    end
endmodule
