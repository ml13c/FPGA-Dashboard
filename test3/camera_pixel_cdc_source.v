// stage 6 camera-side stream source.
//
// Runs entirely from CAM_PCLK. It assembles the OV7670's two RGB565 bytes,
// selects one pixel from each 2x2 block (320x240 -> 160x120), and pushes
// framed 18-bit tokens into the asynchronous FIFO:
//   2'b00 + RGB565 pixel
//   2'b01 + frame sequence number (SOF)
//   2'b10 + accepted pixel count   (EOF)
module camera_pixel_cdc_source #(
    parameter integer CAM_WIDTH  = 320,
    parameter integer CAM_HEIGHT = 240
)(
    input  wire        camera_pclk,
    input  wire        resetn,
    input  wire        config_done,
    input  wire        byte_swap,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_d,
    input  wire        fifo_full,
    output wire        fifo_wr_en,
    output wire [17:0] fifo_wr_data
);
    localparam [1:0] TOKEN_PIXEL = 2'b00;
    localparam [1:0] TOKEN_SOF   = 2'b01;
    localparam [1:0] TOKEN_EOF   = 2'b10;

    (* ASYNC_REG = "TRUE" *) reg [1:0] config_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] swap_sync = 2'b00;

    reg vsync_d = 1'b0;
    reg href_d = 1'b0;
    reg frame_active = 1'b0;
    reg [9:0] line_number = 10'd0;
    reg [9:0] line_index = 10'd0;
    reg [9:0] pixel_x = 10'd0;
    reg       byte_phase = 1'b0;
    reg [7:0] first_byte = 8'd0;
    reg [15:0] sampled_pixels = 16'd0;
    reg [15:0] frame_sequence = 16'd0;

    wire vsync_rise = cam_vsync && !vsync_d;
    wire vsync_fall = !cam_vsync && vsync_d;

    // second byte of a complete RGB565 pixel is present while byte_phase=1.
    wire pixel_complete = frame_active && !cam_vsync && cam_href && href_d &&
                          byte_phase && line_index < CAM_HEIGHT &&
                          pixel_x < CAM_WIDTH;
    wire pixel_selected = pixel_complete && !line_index[0] && !pixel_x[0];

    wire [7:0] upper_byte = swap_sync[1] ? cam_d : first_byte;
    wire [7:0] lower_byte = swap_sync[1] ? first_byte : cam_d;
    wire [15:0] rgb565_pixel = {upper_byte, lower_byte};

    wire push_sof = vsync_fall && config_sync[1];
    wire push_eof = vsync_rise && frame_active;
    wire push_pixel = pixel_selected;

    // frame markers have priority, although they occur outside active HREF.
    assign fifo_wr_en = push_eof || push_sof || push_pixel;
    assign fifo_wr_data = push_eof ? {TOKEN_EOF, sampled_pixels} :
                          push_sof ? {TOKEN_SOF, frame_sequence} :
                                     {TOKEN_PIXEL, rgb565_pixel};

    always @(posedge camera_pclk or negedge resetn) begin
        if (!resetn) begin
            config_sync <= 2'b00;
            swap_sync <= 2'b00;
            vsync_d <= 1'b0;
            href_d <= 1'b0;
            frame_active <= 1'b0;
            line_number <= 10'd0;
            line_index <= 10'd0;
            pixel_x <= 10'd0;
            byte_phase <= 1'b0;
            first_byte <= 8'd0;
            sampled_pixels <= 16'd0;
            frame_sequence <= 16'd0;
        end else begin
            config_sync <= {config_sync[0], config_done};
            swap_sync <= {swap_sync[0], byte_swap};
            vsync_d <= cam_vsync;
            href_d <= cam_href;

            // VSYNC is high between frames in the working OV7670 setup.
            // Falling edge starts a new active frame; rising edge ends it.
            if (vsync_fall) begin
                frame_active <= config_sync[1];
                line_number <= 10'd0;
                line_index <= 10'd0;
                pixel_x <= 10'd0;
                byte_phase <= 1'b0;
                sampled_pixels <= 16'd0;
                if (config_sync[1])
                    frame_sequence <= frame_sequence + 1'b1;
            end else if (vsync_rise) begin
                frame_active <= 1'b0;
                byte_phase <= 1'b0;
            end else if (frame_active && !cam_vsync) begin
                if (cam_href) begin
                    if (!href_d) begin
                        // first byte of the first pixel in this line.
                        line_index <= line_number;
                        line_number <= line_number + 1'b1;
                        pixel_x <= 10'd0;
                        first_byte <= cam_d;
                        byte_phase <= 1'b1;
                    end else if (!byte_phase) begin
                        first_byte <= cam_d;
                        byte_phase <= 1'b1;
                    end else begin
                        // current cam_d is the second byte.
                        byte_phase <= 1'b0;
                        if (pixel_selected && !fifo_full)
                            sampled_pixels <= sampled_pixels + 1'b1;
                        pixel_x <= pixel_x + 1'b1;
                    end
                end else begin
                    byte_phase <= 1'b0;
                end
            end
        end
    end
endmodule
