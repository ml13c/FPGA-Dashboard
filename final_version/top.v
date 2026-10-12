`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Stage 11: priority compositor / automotive alert modes.
//
// Stage 10 DDR-backed camera/graphics paths and fixed-point alpha blending are
// preserved. Stage 11 adds a display-side z-order compositor with three modes:
// NORMAL, WARNING, and CRITICAL. CRITICAL has the highest per-pixel priority.
//
// The proven Stage 9 three-client DDR arbiter is preserved. The graphics client
// now renders a real ARGB4444 foreground layer into DDR2. The display client
// fetches both camera and graphics layers into matched ping-pong caches, and a
// fixed-point alpha blender composites them over the live video window.
//
// Reuses the proven Stage 5 camera configuration, Stage 6 Gray-code camera
// CDC FIFO, and Stage 8 DDR2/display-cache path.
// -----------------------------------------------------------------------------
module top (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire [15:0] SW,
    input  wire        BTNC, BTNL, BTNR,

    input  wire        CAM_PCLK,
    input  wire        CAM_VSYNC,
    input  wire        CAM_HREF,
    input  wire [7:0]  CAM_D,
    output wire        CAM_XCLK,
    output wire        CAM_RESETN,
    output wire        CAM_PWDN,
    inout  wire        CAM_SIOC,
    inout  wire        CAM_SIOD,

    output wire [15:0] LED,
    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,

    // Nexys 4 DDR onboard DDR2
    inout  wire [15:0] ddr2_dq,
    inout  wire [1:0]  ddr2_dqs_n,
    inout  wire [1:0]  ddr2_dqs_p,
    output wire [12:0] ddr2_addr,
    output wire [2:0]  ddr2_ba,
    output wire        ddr2_ras_n,
    output wire        ddr2_cas_n,
    output wire        ddr2_we_n,
    output wire [0:0]  ddr2_ck_p,
    output wire [0:0]  ddr2_ck_n,
    output wire [0:0]  ddr2_cke,
    output wire [0:0]  ddr2_cs_n,
    output wire [1:0]  ddr2_dm,
    output wire [0:0]  ddr2_odt
);

    // -------------------------------------------------------------------------
    // Board clock. One buffered 100 MHz clock feeds dashboard logic and a
    // 100->200 MHz MMCM feeds the already-proven Stage 7 MIG instance.
    // -------------------------------------------------------------------------
    wire clk100;
    IBUF clk100_input_buffer (.I(CLK100MHZ), .O(clk100));

    wire clk200_raw, clk200;
    wire clkfb_raw, clkfb;
    wire clk200_locked;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(10.000),
        .CLKIN1_PERIOD(10.000),
        .CLKOUT0_DIVIDE_F(5.000),
        .DIVCLK_DIVIDE(1),
        .STARTUP_WAIT("FALSE")
    ) clk200_mmcm (
        .CLKIN1(clk100),
        .CLKFBIN(clkfb),
        .RST(~CPU_RESETN),
        .PWRDWN(1'b0),
        .CLKFBOUT(clkfb_raw),
        .CLKOUT0(clk200_raw),
        .LOCKED(clk200_locked)
    );

    BUFG clkfb_buffer  (.I(clkfb_raw),  .O(clkfb));
    BUFG clk200_buffer (.I(clk200_raw), .O(clk200));

    // -------------------------------------------------------------------------
    // VGA timing / dashboard coordinate generator.
    // -------------------------------------------------------------------------
    wire [9:0] x, y;
    wire video_on, hsync, vsync;
    vga_timing timing(
        .clk(clk100), .x(x), .y(y),
        .hsync(hsync), .vsync(vsync), .video_on(video_on)
    );

    // Detect the start of a VGA frame once, despite x/y remaining constant for
    // four 100 MHz cycles per VGA pixel.
    reg [9:0] x_prev = 10'd0;
    reg [9:0] y_prev = 10'd0;
    always @(posedge clk100) begin
        x_prev <= x;
        y_prev <= y;
    end
    wire vga_frame_start = (x == 10'd0) && (y == 10'd0) &&
                           ((x_prev != 10'd0) || (y_prev != 10'd0));

    // -------------------------------------------------------------------------
    // Camera clock/reset and SCCB configuration. This is the same camera setup
    // that produced correct colors in Stage 5/6.
    // -------------------------------------------------------------------------
    wire cam_resetn_generated;
    wire cam_pwdn_generated;
    camera_clock cam_clock(
        .clk100(clk100),
        .cam_xclk(CAM_XCLK),
        .cam_resetn(cam_resetn_generated),
        .cam_pwdn(cam_pwdn_generated)
    );
    assign CAM_RESETN = cam_resetn_generated & CPU_RESETN;
    assign CAM_PWDN   = cam_pwdn_generated;

    wire sio_clock_low, sio_data_low;
    assign CAM_SIOC = sio_clock_low ? 1'b0 : 1'bz;
    assign CAM_SIOD = sio_data_low  ? 1'b0 : 1'bz;

    wire config_done, any_nack;
    wire [5:0] config_step;
    ov7670_init camera_setup(
        .clk100(clk100),
        .resetn(CAM_RESETN),
        .sda_in(CAM_SIOD),
        .scl_low(sio_clock_low),
        .sda_low(sio_data_low),
        .config_done(config_done),
        .any_nack(any_nack),
        .current_step(config_step)
    );

    // -------------------------------------------------------------------------
    // MIG DDR2 interface (same IP name/configuration that passed Stage 7).
    // -------------------------------------------------------------------------
    wire ui_clk;
    wire ui_clk_sync_rst;
    wire mig_mmcm_locked;
    wire init_calib_complete;
    wire mig_sys_rst_n = CPU_RESETN & clk200_locked;
    wire axi_aresetn   = ~ui_clk_sync_rst;

    wire [0:0]  axi_awid;
    wire [26:0] axi_awaddr;
    wire [7:0]  axi_awlen;
    wire [2:0]  axi_awsize;
    wire [1:0]  axi_awburst;
    wire [0:0]  axi_awlock;
    wire [3:0]  axi_awcache;
    wire [2:0]  axi_awprot;
    wire [3:0]  axi_awqos;
    wire        axi_awvalid;
    wire        axi_awready;

    wire [63:0] axi_wdata;
    wire [7:0]  axi_wstrb;
    wire        axi_wlast;
    wire        axi_wvalid;
    wire        axi_wready;

    wire [0:0]  axi_bid;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;

    wire [0:0]  axi_arid;
    wire [26:0] axi_araddr;
    wire [7:0]  axi_arlen;
    wire [2:0]  axi_arsize;
    wire [1:0]  axi_arburst;
    wire [0:0]  axi_arlock;
    wire [3:0]  axi_arcache;
    wire [2:0]  axi_arprot;
    wire [3:0]  axi_arqos;
    wire        axi_arvalid;
    wire        axi_arready;

    wire [0:0]  axi_rid;
    wire [63:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rlast;
    wire        axi_rvalid;
    wire        axi_rready;

    mig_7series_0 ddr2_controller (
        .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p),
        .ddr2_addr(ddr2_addr),
        .ddr2_ba(ddr2_ba),
        .ddr2_ras_n(ddr2_ras_n),
        .ddr2_cas_n(ddr2_cas_n),
        .ddr2_we_n(ddr2_we_n),
        .ddr2_ck_p(ddr2_ck_p),
        .ddr2_ck_n(ddr2_ck_n),
        .ddr2_cke(ddr2_cke),
        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt),

        .sys_clk_i(clk200),
        .sys_rst(mig_sys_rst_n),
        .ui_clk(ui_clk),
        .ui_clk_sync_rst(ui_clk_sync_rst),
        .mmcm_locked(mig_mmcm_locked),
        .init_calib_complete(init_calib_complete),
        .aresetn(axi_aresetn),

        .app_sr_req(1'b0),
        .app_ref_req(1'b0),
        .app_zq_req(1'b0),

        .s_axi_awid(axi_awid),
        .s_axi_awaddr(axi_awaddr),
        .s_axi_awlen(axi_awlen),
        .s_axi_awsize(axi_awsize),
        .s_axi_awburst(axi_awburst),
        .s_axi_awlock(axi_awlock),
        .s_axi_awcache(axi_awcache),
        .s_axi_awprot(axi_awprot),
        .s_axi_awqos(axi_awqos),
        .s_axi_awvalid(axi_awvalid),
        .s_axi_awready(axi_awready),

        .s_axi_wdata(axi_wdata),
        .s_axi_wstrb(axi_wstrb),
        .s_axi_wlast(axi_wlast),
        .s_axi_wvalid(axi_wvalid),
        .s_axi_wready(axi_wready),

        .s_axi_bid(axi_bid),
        .s_axi_bresp(axi_bresp),
        .s_axi_bvalid(axi_bvalid),
        .s_axi_bready(axi_bready),

        .s_axi_arid(axi_arid),
        .s_axi_araddr(axi_araddr),
        .s_axi_arlen(axi_arlen),
        .s_axi_arsize(axi_arsize),
        .s_axi_arburst(axi_arburst),
        .s_axi_arlock(axi_arlock),
        .s_axi_arcache(axi_arcache),
        .s_axi_arprot(axi_arprot),
        .s_axi_arqos(axi_arqos),
        .s_axi_arvalid(axi_arvalid),
        .s_axi_arready(axi_arready),

        .s_axi_rid(axi_rid),
        .s_axi_rdata(axi_rdata),
        .s_axi_rresp(axi_rresp),
        .s_axi_rlast(axi_rlast),
        .s_axi_rvalid(axi_rvalid),
        .s_axi_rready(axi_rready)
    );

    // -------------------------------------------------------------------------
    // Synchronize MIG calibration into the camera clock domain. Camera stream
    // generation is held reset until DDR2 is ready so the first token observed
    // by the DDR writer begins cleanly at a frame boundary.
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [1:0] calib_cam_sync = 2'b00;
    always @(posedge CAM_PCLK or negedge CPU_RESETN) begin
        if (!CPU_RESETN)
            calib_cam_sync <= 2'b00;
        else
            calib_cam_sync <= {calib_cam_sync[0], init_calib_complete};
    end
    wire camera_stream_resetn = CAM_RESETN & calib_cam_sync[1];

    // -------------------------------------------------------------------------
    // CDC #1: camera PCLK -> MIG UI clock.
    // Stage 10 increases the FIFO from 1024 to 4096 entries because the
    // display client now fetches both camera and graphics layers at strict
    // priority before the writers resume.
    // -------------------------------------------------------------------------
    wire        cam_fifo_wr_en;
    wire [17:0] cam_fifo_wr_data;
    wire        cam_fifo_full;
    wire        cam_fifo_overflow;

    camera_pixel_cdc_source camera_stream(
        .camera_pclk(CAM_PCLK),
        .resetn(camera_stream_resetn),
        .config_done(config_done),
        .byte_swap(SW[9]),
        .cam_vsync(CAM_VSYNC),
        .cam_href(CAM_HREF),
        .cam_d(CAM_D),
        .fifo_full(cam_fifo_full),
        .fifo_wr_en(cam_fifo_wr_en),
        .fifo_wr_data(cam_fifo_wr_data)
    );

    wire        cam_fifo_rd_en;
    wire [17:0] cam_fifo_rd_data;
    wire        cam_fifo_rd_valid;
    wire        cam_fifo_empty;
    wire        cam_fifo_underflow;

    wire stage8_fifo_resetn = CPU_RESETN & camera_stream_resetn & init_calib_complete;

    async_fifo_gray #(
        .DATA_WIDTH(18),
        .ADDR_WIDTH(12)
    ) camera_to_ddr_fifo (
        .rstn_async(stage8_fifo_resetn),
        .wr_clk(CAM_PCLK),
        .wr_en(cam_fifo_wr_en),
        .wr_data(cam_fifo_wr_data),
        .wr_full(cam_fifo_full),
        .wr_overflow(cam_fifo_overflow),
        .rd_clk(ui_clk),
        .rd_en(cam_fifo_rd_en),
        .rd_data(cam_fifo_rd_data),
        .rd_valid(cam_fifo_rd_valid),
        .rd_empty(cam_fifo_empty),
        .rd_underflow(cam_fifo_underflow)
    );

    // -------------------------------------------------------------------------
    // Stage 10 memory system.
    //
    // Camera and graphics are independent DDR write clients. The display read
    // client fetches BOTH layers from DDR into matched on-chip ping-pong caches.
    // Display reads retain strict priority in the custom Stage 9 arbiter, while
    // camera and graphics writes continue to share the remaining bandwidth via
    // round-robin selection.
    // -------------------------------------------------------------------------
    wire        cam_cache_wr_en;
    wire        cam_cache_wr_bank;
    wire [14:0] cam_cache_wr_addr;
    wire [15:0] cam_cache_wr_data;
    wire        gfx_cache_wr_en;
    wire        gfx_cache_wr_bank;
    wire [14:0] gfx_cache_wr_addr;
    wire [15:0] gfx_cache_wr_data;
    wire        cache_frame_valid;
    wire        cache_committed_bank;
    wire        cache_commit_toggle;

    wire committed_frame_valid;
    wire committed_bank;
    wire frame_commit_toggle;
    wire graphics_frame_valid;
    wire graphics_committed_bank;
    wire graphics_commit_toggle;
    wire camera_writer_busy;
    wire display_reader_busy;
    wire graphics_writer_busy;
    wire camera_write_error;
    wire display_read_error;
    wire graphics_write_error;
    wire bad_frame_sticky;
    wire arbiter_axi_error;
    wire arb_display_granted;
    wire arb_camera_granted;
    wire arb_graphics_granted;

    stage10_memory_system memory_system (
        .clk_ui(ui_clk),
        .rst(ui_clk_sync_rst | ~init_calib_complete),

        .cam_fifo_rd_data(cam_fifo_rd_data),
        .cam_fifo_rd_valid(cam_fifo_rd_valid),
        .cam_fifo_empty(cam_fifo_empty),
        .cam_fifo_rd_en(cam_fifo_rd_en),

        .cam_cache_wr_en(cam_cache_wr_en),
        .cam_cache_wr_bank(cam_cache_wr_bank),
        .cam_cache_wr_addr(cam_cache_wr_addr),
        .cam_cache_wr_data(cam_cache_wr_data),
        .gfx_cache_wr_en(gfx_cache_wr_en),
        .gfx_cache_wr_bank(gfx_cache_wr_bank),
        .gfx_cache_wr_addr(gfx_cache_wr_addr),
        .gfx_cache_wr_data(gfx_cache_wr_data),
        .cache_frame_valid(cache_frame_valid),
        .cache_committed_bank(cache_committed_bank),
        .cache_commit_toggle(cache_commit_toggle),

        .committed_frame_valid(committed_frame_valid),
        .committed_bank(committed_bank),
        .frame_commit_toggle(frame_commit_toggle),
        .graphics_frame_valid(graphics_frame_valid),
        .graphics_committed_bank(graphics_committed_bank),
        .graphics_commit_toggle(graphics_commit_toggle),
        .camera_writer_busy(camera_writer_busy),
        .display_reader_busy(display_reader_busy),
        .graphics_writer_busy(graphics_writer_busy),
        .camera_write_error(camera_write_error),
        .display_read_error(display_read_error),
        .graphics_write_error(graphics_write_error),
        .bad_frame_sticky(bad_frame_sticky),
        .arbiter_axi_error(arbiter_axi_error),
        .arb_display_granted(arb_display_granted),
        .arb_camera_granted(arb_camera_granted),
        .arb_graphics_granted(arb_graphics_granted),

        .m_axi_awid(axi_awid),
        .m_axi_awaddr(axi_awaddr),
        .m_axi_awlen(axi_awlen),
        .m_axi_awsize(axi_awsize),
        .m_axi_awburst(axi_awburst),
        .m_axi_awlock(axi_awlock),
        .m_axi_awcache(axi_awcache),
        .m_axi_awprot(axi_awprot),
        .m_axi_awqos(axi_awqos),
        .m_axi_awvalid(axi_awvalid),
        .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata),
        .m_axi_wstrb(axi_wstrb),
        .m_axi_wlast(axi_wlast),
        .m_axi_wvalid(axi_wvalid),
        .m_axi_wready(axi_wready),
        .m_axi_bid(axi_bid),
        .m_axi_bresp(axi_bresp),
        .m_axi_bvalid(axi_bvalid),
        .m_axi_bready(axi_bready),

        .m_axi_arid(axi_arid),
        .m_axi_araddr(axi_araddr),
        .m_axi_arlen(axi_arlen),
        .m_axi_arsize(axi_arsize),
        .m_axi_arburst(axi_arburst),
        .m_axi_arlock(axi_arlock),
        .m_axi_arcache(axi_arcache),
        .m_axi_arprot(axi_arprot),
        .m_axi_arqos(axi_arqos),
        .m_axi_arvalid(axi_arvalid),
        .m_axi_arready(axi_arready),
        .m_axi_rid(axi_rid),
        .m_axi_rdata(axi_rdata),
        .m_axi_rresp(axi_rresp),
        .m_axi_rlast(axi_rlast),
        .m_axi_rvalid(axi_rvalid),
        .m_axi_rready(axi_rready)
    );

    wire [11:0] cached_camera_rgb;
    wire [15:0] cached_graphics_argb;
    wire        cached_camera_active;
    wire        cache_display_valid;

    stage10_display_cache display_cache (
        .ui_clk(ui_clk),
        .resetn_ui(~ui_clk_sync_rst & init_calib_complete),
        .cam_cache_wr_en(cam_cache_wr_en),
        .cam_cache_wr_bank(cam_cache_wr_bank),
        .cam_cache_wr_addr(cam_cache_wr_addr),
        .cam_cache_wr_data(cam_cache_wr_data),
        .gfx_cache_wr_en(gfx_cache_wr_en),
        .gfx_cache_wr_bank(gfx_cache_wr_bank),
        .gfx_cache_wr_addr(gfx_cache_wr_addr),
        .gfx_cache_wr_data(gfx_cache_wr_data),
        .cache_frame_valid(cache_frame_valid),
        .cache_committed_bank(cache_committed_bank),
        .cache_commit_toggle(cache_commit_toggle),

        .clk100(clk100),
        .resetn_vga(CPU_RESETN & init_calib_complete),
        .x(x),
        .y(y),
        .frame_start(vga_frame_start),
        .camera_rgb(cached_camera_rgb),
        .graphics_argb(cached_graphics_argb),
        .camera_active(cached_camera_active),
        .display_valid(cache_display_valid)
    );

    // Preserve the camera color correction that was proven in Stage 5/6.
    wire [11:0] color_checked_rgb = SW[11] ?
        {cached_camera_rgb[3:0], cached_camera_rgb[7:4], cached_camera_rgb[11:8]} :
        cached_camera_rgb;

    // Stage 10 fixed-point alpha blending. The graphics layer is ARGB4444 in
    // DDR. Its 4-bit alpha value is expanded to 8 bits (0x0 -> 0x00,
    // 0xF -> 0xFF). SW10 is an A/B switch: OFF = raw camera, ON = blend.
    wire [7:0] graphics_alpha = SW[10] ?
        {cached_graphics_argb[15:12], cached_graphics_argb[15:12]} : 8'h00;
    wire [11:0] blended_camera_rgb;

    alpha_blend_rgb444_pipe alpha_blender (
        .clk(clk100),
        .resetn(CPU_RESETN & init_calib_complete),
        .background_rgb(color_checked_rgb),
        .foreground_rgb(cached_graphics_argb[11:0]),
        .alpha(graphics_alpha),
        .out_rgb(blended_camera_rgb)
    );

    // The alpha pipeline adds two 100 MHz cycles after the cache read. Delay
    // dashboard coordinates and VGA control by the same amount. Because the VGA
    // coordinate generator advances only every fourth 100 MHz cycle, this also
    // leaves comfortable pixel-domain timing margin.
    reg [9:0] x_d0 = 10'd0, x_d1 = 10'd0, x_d2 = 10'd0;
    reg [9:0] y_d0 = 10'd0, y_d1 = 10'd0, y_d2 = 10'd0;
    reg video_d0 = 1'b0, video_d1 = 1'b0, video_d2 = 1'b0;
    reg hs_d0 = 1'b1, hs_d1 = 1'b1, hs_d2 = 1'b1;
    reg vs_d0 = 1'b1, vs_d1 = 1'b1, vs_d2 = 1'b1;
    reg test_d0 = 1'b0, test_d1 = 1'b0, test_d2 = 1'b0;

    always @(posedge clk100) begin
        x_d0 <= x;       x_d1 <= x_d0;       x_d2 <= x_d1;
        y_d0 <= y;       y_d1 <= y_d0;       y_d2 <= y_d1;
        video_d0 <= video_on; video_d1 <= video_d0; video_d2 <= video_d1;
        hs_d0 <= hsync;  hs_d1 <= hs_d0;     hs_d2 <= hs_d1;
        vs_d0 <= vsync;  vs_d1 <= vs_d0;     vs_d2 <= vs_d1;
        test_d0 <= SW[8]; test_d1 <= test_d0; test_d2 <= test_d1;
    end

    // SW8 remains a display-only test pattern. Generate it from the delayed
    // coordinate so it stays aligned with the Stage 10 video pipeline.
    reg [11:0] test_rgb;
    always @(*) begin
        if (x_d2 < 10'd340)      test_rgb = 12'hf00;
        else if (x_d2 < 10'd420) test_rgb = 12'h0f0;
        else if (x_d2 < 10'd500) test_rgb = 12'h00f;
        else                     test_rgb = 12'hfff;
    end

    wire delayed_camera_active = cache_display_valid &&
        (x_d2 >= 10'd260) && (x_d2 < 10'd580) &&
        (y_d2 >= 10'd100) && (y_d2 < 10'd340);

    // -------------------------------------------------------------------------
    // Stage 11 priority compositor controls. Board pushbuttons are asynchronous
    // to clk100, so synchronize them before they participate in display logic.
    //
    //   NORMAL   : no alert request
    //   WARNING  : BTNL + BTNR together
    //   CRITICAL : BTNC
    //
    // If WARNING and CRITICAL are asserted at the same time, both requests are
    // intentionally kept active so the compositor itself proves that CRITICAL
    // wins by z-order rather than by masking WARNING before it gets there.
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [1:0] btnc_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] btnl_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] btnr_sync = 2'b00;
    always @(posedge clk100) begin
        if (!CPU_RESETN) begin
            btnc_sync <= 2'b00;
            btnl_sync <= 2'b00;
            btnr_sync <= 2'b00;
        end else begin
            btnc_sync <= {btnc_sync[0], BTNC};
            btnl_sync <= {btnl_sync[0], BTNL};
            btnr_sync <= {btnr_sync[0], BTNR};
        end
    end
    wire btnc = btnc_sync[1];
    wire btnl = btnl_sync[1];
    wire btnr = btnr_sync[1];

    // Z0: normal dashboard + live camera + Stage 10 DDR-backed ARGB graphics.
    // The old dashboard warning input is disabled so only the priority compositor
    // owns alert policy. Individual left/right buttons still drive turn icons.
    wire [11:0] base_dashboard_rgb;
    dashboard_ui ui(
        .x(x_d2), .y(y_d2), .video_on(video_d2),
        .speed(SW[7:0]), .battery(SW[15:12]),
        .warning(1'b0), .turn_left(btnl), .turn_right(btnr),
        .camera_active(delayed_camera_active || test_d2),
        .camera_rgb(test_d2 ? test_rgb : blended_camera_rgb),
        .rgb(base_dashboard_rgb)
    );

    // Slow flash phase for CRITICAL mode, updated once per VGA frame.
    reg [5:0] alert_frame_counter = 6'd0;
    always @(posedge clk100) begin
        if (!CPU_RESETN)
            alert_frame_counter <= 6'd0;
        else if (vga_frame_start)
            alert_frame_counter <= alert_frame_counter + 6'd1;
    end

    wire warning_request  = btnl & btnr;
    wire critical_request = btnc;
    wire critical_flash   = alert_frame_counter[4];
    wire [1:0] compositor_level;
    wire [11:0] rgb;

    stage11_priority_compositor priority_compositor (
        .x(x_d2),
        .y(y_d2),
        .video_on(video_d2),
        .base_rgb(base_dashboard_rgb),
        .warning_request(warning_request),
        .critical_request(critical_request),
        .critical_flash(critical_flash),
        .rgb(rgb),
        .active_level(compositor_level)
    );

    assign VGA_R = video_d2 ? rgb[11:8] : 4'h0;
    assign VGA_G = video_d2 ? rgb[7:4]  : 4'h0;
    assign VGA_B = video_d2 ? rgb[3:0]  : 4'h0;
    assign VGA_HS = hs_d2;
    assign VGA_VS = vs_d2;

    // -------------------------------------------------------------------------
    // Diagnostics. Grant indicators remain sticky. Stage 10 adds a synchronized
    // graphics-frame-valid indicator so the board proves that an actual graphics
    // layer has been rendered into DDR, not merely scratch traffic.
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [1:0] calib_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] commit_valid_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] graphics_valid_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] cache_valid_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] cam_err_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] disp_err_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] gfx_err_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] axi_err_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] bad_frame_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] disp_grant_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] cam_grant_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] gfx_grant_sys = 2'b00;

    always @(posedge clk100) begin
        if (!CPU_RESETN) begin
            calib_sys        <= 2'b00;
            commit_valid_sys <= 2'b00;
            graphics_valid_sys <= 2'b00;
            cache_valid_sys  <= 2'b00;
            cam_err_sys      <= 2'b00;
            disp_err_sys     <= 2'b00;
            gfx_err_sys      <= 2'b00;
            axi_err_sys      <= 2'b00;
            bad_frame_sys    <= 2'b00;
            disp_grant_sys   <= 2'b00;
            cam_grant_sys    <= 2'b00;
            gfx_grant_sys    <= 2'b00;
        end else begin
            calib_sys        <= {calib_sys[0], init_calib_complete};
            commit_valid_sys <= {commit_valid_sys[0], committed_frame_valid};
            graphics_valid_sys <= {graphics_valid_sys[0], graphics_frame_valid};
            cache_valid_sys  <= {cache_valid_sys[0], cache_frame_valid};
            cam_err_sys      <= {cam_err_sys[0], camera_write_error};
            disp_err_sys     <= {disp_err_sys[0], display_read_error};
            gfx_err_sys      <= {gfx_err_sys[0], graphics_write_error};
            axi_err_sys      <= {axi_err_sys[0], arbiter_axi_error};
            bad_frame_sys    <= {bad_frame_sys[0], bad_frame_sticky};
            disp_grant_sys   <= {disp_grant_sys[0], arb_display_granted};
            cam_grant_sys    <= {cam_grant_sys[0], arb_camera_granted};
            gfx_grant_sys    <= {gfx_grant_sys[0], arb_graphics_granted};
        end
    end

    reg cam_overflow_sticky = 1'b0;
    always @(posedge CAM_PCLK or negedge camera_stream_resetn) begin
        if (!camera_stream_resetn)
            cam_overflow_sticky <= 1'b0;
        else if (cam_fifo_overflow)
            cam_overflow_sticky <= 1'b1;
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] cam_overflow_sys = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] cam_full_sys = 2'b00;
    always @(posedge clk100) begin
        if (!CPU_RESETN) begin
            cam_overflow_sys <= 2'b00;
            cam_full_sys <= 2'b00;
        end else begin
            cam_overflow_sys <= {cam_overflow_sys[0], cam_overflow_sticky};
            cam_full_sys <= {cam_full_sys[0], cam_fifo_full};
        end
    end

    wire stage11_error = cam_overflow_sys[1] || cam_err_sys[1] ||
                         disp_err_sys[1] || gfx_err_sys[1] ||
                         axi_err_sys[1] || bad_frame_sys[1];

    wire stage11_healthy = calib_sys[1] && config_done &&
                           commit_valid_sys[1] && graphics_valid_sys[1] &&
                           cache_valid_sys[1] && cache_display_valid &&
                           disp_grant_sys[1] && cam_grant_sys[1] &&
                           gfx_grant_sys[1] && !stage11_error;

    // Stage 11 LED map:
    // 0  200 MHz input MMCM locked
    // 1  MIG MMCM locked
    // 2  DDR2 calibration complete
    // 3  OV7670 configuration complete
    // 4  camera frame committed to DDR
    // 5  graphics ARGB layer committed to DDR
    // 6  paired camera+graphics cache loaded
    // 7  WARNING compositor mode active
    // 8  CRITICAL compositor mode active
    // 9  camera FIFO overflow sticky (MUST stay OFF)
    // 10 display-read client has received an arbiter grant
    // 11 camera-write client has received an arbiter grant
    // 12 graphics-write client has received an arbiter grant
    // 13 any AXI/client response error (MUST stay OFF)
    // 14 malformed camera frame (MUST stay OFF)
    // 15 overall Stage 11 healthy
    assign LED[0]  = clk200_locked;
    assign LED[1]  = mig_mmcm_locked;
    assign LED[2]  = calib_sys[1];
    assign LED[3]  = config_done;
    assign LED[4]  = commit_valid_sys[1];
    assign LED[5]  = graphics_valid_sys[1];
    assign LED[6]  = cache_valid_sys[1] & cache_display_valid;
    assign LED[7]  = (compositor_level == 2'd1);
    assign LED[8]  = (compositor_level == 2'd2);
    assign LED[9]  = cam_overflow_sys[1];
    assign LED[10] = disp_grant_sys[1];
    assign LED[11] = cam_grant_sys[1];
    assign LED[12] = gfx_grant_sys[1];
    assign LED[13] = cam_err_sys[1] | disp_err_sys[1] |
                     gfx_err_sys[1] | axi_err_sys[1];
    assign LED[14] = bad_frame_sys[1];
    assign LED[15] = stage11_healthy;

endmodule



// =============================================================================
// STAGE 10 MEMORY SYSTEM - MIG UI CLOCK DOMAIN
// =============================================================================
module stage10_memory_system #(
    parameter integer FRAME_PIXELS   = 19200,
    parameter integer FRAME_BEATS    = 4800,
    parameter [26:0] FRAME0_BASE     = 27'h0000000,
    parameter [26:0] FRAME1_BASE     = 27'h0010000,
    parameter [26:0] GRAPHICS0_BASE  = 27'h0020000,
    parameter [26:0] GRAPHICS1_BASE  = 27'h0030000
)(
    input  wire        clk_ui,
    input  wire        rst,

    input  wire [17:0] cam_fifo_rd_data,
    input  wire        cam_fifo_rd_valid,
    input  wire        cam_fifo_empty,
    output wire        cam_fifo_rd_en,

    output reg         cam_cache_wr_en,
    output reg         cam_cache_wr_bank,
    output reg  [14:0] cam_cache_wr_addr,
    output reg  [15:0] cam_cache_wr_data,
    output reg         gfx_cache_wr_en,
    output reg         gfx_cache_wr_bank,
    output reg  [14:0] gfx_cache_wr_addr,
    output reg  [15:0] gfx_cache_wr_data,
    output reg         cache_frame_valid,
    output reg         cache_committed_bank,
    output reg         cache_commit_toggle,

    output reg         committed_frame_valid,
    output reg         committed_bank,
    output reg         frame_commit_toggle,
    output reg         graphics_frame_valid,
    output reg         graphics_committed_bank,
    output reg         graphics_commit_toggle,
    output wire        camera_writer_busy,
    output wire        display_reader_busy,
    output wire        graphics_writer_busy,
    output reg         camera_write_error,
    output reg         display_read_error,
    output reg         graphics_write_error,
    output reg         bad_frame_sticky,
    output wire        arbiter_axi_error,
    output wire        arb_display_granted,
    output wire        arb_camera_granted,
    output wire        arb_graphics_granted,

    output wire [0:0]  m_axi_awid,
    output wire [26:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire [0:0]  m_axi_awlock,
    output wire [3:0]  m_axi_awcache,
    output wire [2:0]  m_axi_awprot,
    output wire [3:0]  m_axi_awqos,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,

    output wire [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,

    input  wire [0:0]  m_axi_bid,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,

    output wire [0:0]  m_axi_arid,
    output wire [26:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire [0:0]  m_axi_arlock,
    output wire [3:0]  m_axi_arcache,
    output wire [2:0]  m_axi_arprot,
    output wire [3:0]  m_axi_arqos,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,

    input  wire [0:0]  m_axi_rid,
    input  wire [63:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready
);
    localparam [1:0] TOKEN_PIXEL = 2'b00;
    localparam [1:0] TOKEN_SOF   = 2'b01;
    localparam [1:0] TOKEN_EOF   = 2'b10;

    // ---------------------------------------------------------------------
    // Camera write client: unchanged from Stage 9. Four RGB565 pixels are
    // packed into one 64-bit DDR beat.
    // ---------------------------------------------------------------------
    reg        cam_req_valid;
    wire       cam_req_ready;
    reg [26:0] cam_req_addr;
    reg [63:0] cam_req_data;
    wire       cam_rsp_valid;
    wire       cam_rsp_error;
    reg        cam_req_waiting;

    reg        cam_pop_pending;
    reg        in_camera_frame;
    reg        write_bank;
    reg [15:0] camera_pixel_count;
    reg [12:0] write_beat_index;
    reg [1:0]  pack_count;
    reg [63:0] pack_word;

    wire [1:0]  cam_token   = cam_fifo_rd_data[17:16];
    wire [15:0] cam_payload = cam_fifo_rd_data[15:0];
    wire [26:0] write_base  = write_bank ? FRAME1_BASE : FRAME0_BASE;

    assign cam_fifo_rd_en = !cam_pop_pending && !cam_req_valid &&
                            !cam_req_waiting && !cam_fifo_empty;
    assign camera_writer_busy = in_camera_frame || cam_pop_pending ||
                                cam_req_valid || cam_req_waiting;

    always @(posedge clk_ui) begin
        if (rst) begin
            cam_req_valid <= 1'b0;
            cam_req_addr <= 27'd0;
            cam_req_data <= 64'd0;
            cam_req_waiting <= 1'b0;
            cam_pop_pending <= 1'b0;
            in_camera_frame <= 1'b0;
            write_bank <= 1'b0;
            camera_pixel_count <= 16'd0;
            write_beat_index <= 13'd0;
            pack_count <= 2'd0;
            pack_word <= 64'd0;
            committed_frame_valid <= 1'b0;
            committed_bank <= 1'b0;
            frame_commit_toggle <= 1'b0;
            camera_write_error <= 1'b0;
            bad_frame_sticky <= 1'b0;
        end else begin
            if (cam_fifo_rd_en)
                cam_pop_pending <= 1'b1;

            if (cam_req_valid && cam_req_ready) begin
                cam_req_valid <= 1'b0;
                cam_req_waiting <= 1'b1;
            end

            if (cam_rsp_valid) begin
                cam_req_waiting <= 1'b0;
                write_beat_index <= write_beat_index + 1'b1;
                if (cam_rsp_error)
                    camera_write_error <= 1'b1;
            end

            if (cam_fifo_rd_valid) begin
                cam_pop_pending <= 1'b0;

                if (cam_token == TOKEN_SOF) begin
                    if (in_camera_frame)
                        bad_frame_sticky <= 1'b1;
                    write_bank <= committed_frame_valid ? ~committed_bank : 1'b0;
                    in_camera_frame <= 1'b1;
                    camera_pixel_count <= 16'd0;
                    write_beat_index <= 13'd0;
                    pack_count <= 2'd0;
                    pack_word <= 64'd0;
                end else if (cam_token == TOKEN_PIXEL) begin
                    if (in_camera_frame) begin
                        camera_pixel_count <= camera_pixel_count + 1'b1;
                        case (pack_count)
                            2'd0: begin
                                pack_word[15:0] <= cam_payload;
                                pack_count <= 2'd1;
                            end
                            2'd1: begin
                                pack_word[31:16] <= cam_payload;
                                pack_count <= 2'd2;
                            end
                            2'd2: begin
                                pack_word[47:32] <= cam_payload;
                                pack_count <= 2'd3;
                            end
                            default: begin
                                cam_req_addr <= write_base + {write_beat_index, 3'b000};
                                cam_req_data <= {cam_payload, pack_word[47:0]};
                                cam_req_valid <= 1'b1;
                                pack_count <= 2'd0;
                            end
                        endcase
                    end
                end else if (cam_token == TOKEN_EOF) begin
                    if (in_camera_frame &&
                        (camera_pixel_count == FRAME_PIXELS) &&
                        (pack_count == 2'd0) &&
                        (write_beat_index == FRAME_BEATS) &&
                        !cam_req_valid && !cam_req_waiting) begin
                        committed_bank <= write_bank;
                        committed_frame_valid <= 1'b1;
                        frame_commit_toggle <= ~frame_commit_toggle;
                    end else begin
                        bad_frame_sticky <= 1'b1;
                    end
                    in_camera_frame <= 1'b0;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // Graphics write client: Stage 10 turns the Stage 9 scratch writer into a
    // full 160x120 ARGB4444 foreground renderer. Four 16-bit graphics pixels
    // are packed per 64-bit beat, using a separate double-buffered DDR region.
    // ---------------------------------------------------------------------
    reg        gfx_req_valid;
    wire       gfx_req_ready;
    reg [26:0] gfx_req_addr;
    reg [63:0] gfx_req_data;
    wire       gfx_rsp_valid;
    wire       gfx_rsp_error;
    reg        gfx_req_waiting;

    reg        gfx_write_bank;
    reg [12:0] gfx_beat_index;
    reg [5:0]  gfx_beat_x;
    reg [6:0]  gfx_y;
    reg [7:0]  gfx_phase;

    wire [26:0] gfx_write_base = gfx_write_bank ? GRAPHICS1_BASE : GRAPHICS0_BASE;
    wire [7:0] gfx_x0 = {gfx_beat_x, 2'b00};
    wire [7:0] gfx_x1 = gfx_x0 + 8'd1;
    wire [7:0] gfx_x2 = gfx_x0 + 8'd2;
    wire [7:0] gfx_x3 = gfx_x0 + 8'd3;

    function [15:0] graphics_pixel;
        input [7:0] px;
        input [6:0] py;
        input [7:0] phase;
        reg [3:0] a;
        reg [3:0] r;
        reg [3:0] g;
        reg [3:0] b;
        begin
            a = 4'h0; r = 4'h0; g = 4'h0; b = 4'h0;

            // Semi-transparent cyan perimeter around the camera layer.
            if ((px < 8'd2) || (px >= 8'd158) ||
                (py < 7'd2) || (py >= 7'd118)) begin
                a = 4'hB; r = 4'h0; g = 4'hC; b = 4'hF;
            end

            // Translucent cyan HUD panel in the upper-left of the video layer.
            if ((px >= 8'd5) && (px < 8'd62) &&
                (py >= 7'd5) && (py < 7'd20)) begin
                a = 4'h6; r = 4'h0; g = 4'hC; b = 4'hF;
            end

            // Moving green scan line. This changes every completed graphics
            // frame so the DDR-backed foreground is visibly dynamic.
            if ((px == phase) || (px == (phase + 8'd1))) begin
                a = 4'h5; r = 4'h0; g = 4'hF; b = 4'h2;
            end

            // High-alpha yellow center reticle gets highest local priority.
            if ((((px >= 8'd78) && (px <= 8'd81)) &&
                 (py >= 7'd45) && (py <= 7'd75)) ||
                (((py >= 7'd59) && (py <= 7'd62)) &&
                 (px >= 8'd65) && (px <= 8'd95))) begin
                a = 4'hD; r = 4'hF; g = 4'hE; b = 4'h0;
            end

            graphics_pixel = {a, r, g, b};
        end
    endfunction

    wire [15:0] gfx_pixel0 = graphics_pixel(gfx_x0, gfx_y, gfx_phase);
    wire [15:0] gfx_pixel1 = graphics_pixel(gfx_x1, gfx_y, gfx_phase);
    wire [15:0] gfx_pixel2 = graphics_pixel(gfx_x2, gfx_y, gfx_phase);
    wire [15:0] gfx_pixel3 = graphics_pixel(gfx_x3, gfx_y, gfx_phase);

    assign graphics_writer_busy = gfx_req_valid || gfx_req_waiting;

    always @(posedge clk_ui) begin
        if (rst) begin
            gfx_req_valid <= 1'b0;
            gfx_req_addr <= GRAPHICS0_BASE;
            gfx_req_data <= 64'd0;
            gfx_req_waiting <= 1'b0;
            gfx_write_bank <= 1'b0;
            gfx_beat_index <= 13'd0;
            gfx_beat_x <= 6'd0;
            gfx_y <= 7'd0;
            gfx_phase <= 8'd0;
            graphics_frame_valid <= 1'b0;
            graphics_committed_bank <= 1'b0;
            graphics_commit_toggle <= 1'b0;
            graphics_write_error <= 1'b0;
        end else begin
            if (!gfx_req_valid && !gfx_req_waiting) begin
                gfx_req_addr <= gfx_write_base + {gfx_beat_index, 3'b000};
                gfx_req_data <= {gfx_pixel3, gfx_pixel2, gfx_pixel1, gfx_pixel0};
                gfx_req_valid <= 1'b1;
            end

            if (gfx_req_valid && gfx_req_ready) begin
                gfx_req_valid <= 1'b0;
                gfx_req_waiting <= 1'b1;
            end

            if (gfx_rsp_valid) begin
                gfx_req_waiting <= 1'b0;
                if (gfx_rsp_error)
                    graphics_write_error <= 1'b1;

                if (gfx_beat_index == FRAME_BEATS-1) begin
                    graphics_committed_bank <= gfx_write_bank;
                    graphics_frame_valid <= 1'b1;
                    graphics_commit_toggle <= ~graphics_commit_toggle;
                    gfx_write_bank <= ~gfx_write_bank;
                    gfx_beat_index <= 13'd0;
                    gfx_beat_x <= 6'd0;
                    gfx_y <= 7'd0;
                    if (gfx_phase == 8'd158)
                        gfx_phase <= 8'd0;
                    else
                        gfx_phase <= gfx_phase + 8'd1;
                end else begin
                    gfx_beat_index <= gfx_beat_index + 1'b1;
                    if (gfx_beat_x == 6'd39) begin
                        gfx_beat_x <= 6'd0;
                        gfx_y <= gfx_y + 1'b1;
                    end else begin
                        gfx_beat_x <= gfx_beat_x + 1'b1;
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // Display read client. For each new camera frame, capture the latest safe
    // camera DDR bank AND latest safe graphics DDR bank, load both into the
    // same inactive cache bank, then commit them together. The graphics writer
    // writes the opposite DDR bank while its committed bank is being read.
    // ---------------------------------------------------------------------
    localparam [2:0] D_IDLE   = 3'd0,
                     D_REQ    = 3'd1,
                     D_WAIT   = 3'd2,
                     D_CACHE  = 3'd3,
                     D_COMMIT = 3'd4;

    reg [2:0] disp_state;
    reg       disp_req_valid;
    wire      disp_req_ready;
    reg [26:0] disp_req_addr;
    wire      disp_rsp_valid;
    wire [63:0] disp_rsp_data;
    wire      disp_rsp_error;
    reg       last_loaded_camera_commit;
    reg       read_camera_bank;
    reg       read_graphics_bank;
    reg       fill_bank;
    reg       display_layer; // 0=camera, 1=graphics
    reg [12:0] read_beat_index;
    reg [14:0] cache_pixel_index;
    reg [63:0] read_word;
    reg [1:0]  read_lane;

    wire [26:0] camera_read_base = read_camera_bank ? FRAME1_BASE : FRAME0_BASE;
    wire [26:0] graphics_read_base = read_graphics_bank ? GRAPHICS1_BASE : GRAPHICS0_BASE;
    wire [26:0] display_read_base = display_layer ? graphics_read_base : camera_read_base;
    assign display_reader_busy = (disp_state != D_IDLE);

    always @(posedge clk_ui) begin
        if (rst) begin
            disp_state <= D_IDLE;
            disp_req_valid <= 1'b0;
            disp_req_addr <= 27'd0;
            last_loaded_camera_commit <= 1'b0;
            read_camera_bank <= 1'b0;
            read_graphics_bank <= 1'b0;
            fill_bank <= 1'b0;
            display_layer <= 1'b0;
            read_beat_index <= 13'd0;
            cache_pixel_index <= 15'd0;
            read_word <= 64'd0;
            read_lane <= 2'd0;
            cam_cache_wr_en <= 1'b0;
            cam_cache_wr_bank <= 1'b0;
            cam_cache_wr_addr <= 15'd0;
            cam_cache_wr_data <= 16'd0;
            gfx_cache_wr_en <= 1'b0;
            gfx_cache_wr_bank <= 1'b0;
            gfx_cache_wr_addr <= 15'd0;
            gfx_cache_wr_data <= 16'd0;
            cache_frame_valid <= 1'b0;
            cache_committed_bank <= 1'b0;
            cache_commit_toggle <= 1'b0;
            display_read_error <= 1'b0;
        end else begin
            cam_cache_wr_en <= 1'b0;
            gfx_cache_wr_en <= 1'b0;

            case (disp_state)
                D_IDLE: begin
                    if (committed_frame_valid && graphics_frame_valid &&
                        (frame_commit_toggle != last_loaded_camera_commit)) begin
                        read_camera_bank <= committed_bank;
                        read_graphics_bank <= graphics_committed_bank;
                        fill_bank <= cache_frame_valid ? ~cache_committed_bank : 1'b0;
                        display_layer <= 1'b0;
                        read_beat_index <= 13'd0;
                        cache_pixel_index <= 15'd0;
                        disp_state <= D_REQ;
                    end
                end

                D_REQ: begin
                    if (!disp_req_valid) begin
                        disp_req_addr <= display_read_base + {read_beat_index, 3'b000};
                        disp_req_valid <= 1'b1;
                    end
                    if (disp_req_valid && disp_req_ready) begin
                        disp_req_valid <= 1'b0;
                        disp_state <= D_WAIT;
                    end
                end

                D_WAIT: begin
                    if (disp_rsp_valid) begin
                        read_word <= disp_rsp_data;
                        read_lane <= 2'd0;
                        if (disp_rsp_error)
                            display_read_error <= 1'b1;
                        disp_state <= D_CACHE;
                    end
                end

                D_CACHE: begin
                    if (display_layer) begin
                        gfx_cache_wr_en <= 1'b1;
                        gfx_cache_wr_bank <= fill_bank;
                        gfx_cache_wr_addr <= cache_pixel_index;
                        case (read_lane)
                            2'd0: gfx_cache_wr_data <= read_word[15:0];
                            2'd1: gfx_cache_wr_data <= read_word[31:16];
                            2'd2: gfx_cache_wr_data <= read_word[47:32];
                            default: gfx_cache_wr_data <= read_word[63:48];
                        endcase
                    end else begin
                        cam_cache_wr_en <= 1'b1;
                        cam_cache_wr_bank <= fill_bank;
                        cam_cache_wr_addr <= cache_pixel_index;
                        case (read_lane)
                            2'd0: cam_cache_wr_data <= read_word[15:0];
                            2'd1: cam_cache_wr_data <= read_word[31:16];
                            2'd2: cam_cache_wr_data <= read_word[47:32];
                            default: cam_cache_wr_data <= read_word[63:48];
                        endcase
                    end
                    cache_pixel_index <= cache_pixel_index + 1'b1;

                    if (read_lane == 2'd3) begin
                        if (read_beat_index == FRAME_BEATS-1) begin
                            if (!display_layer) begin
                                // Camera layer finished; now fetch the graphics
                                // layer into the matching cache bank.
                                display_layer <= 1'b1;
                                read_beat_index <= 13'd0;
                                cache_pixel_index <= 15'd0;
                                disp_state <= D_REQ;
                            end else begin
                                disp_state <= D_COMMIT;
                            end
                        end else begin
                            read_beat_index <= read_beat_index + 1'b1;
                            disp_state <= D_REQ;
                        end
                    end else begin
                        read_lane <= read_lane + 1'b1;
                    end
                end

                D_COMMIT: begin
                    cache_committed_bank <= fill_bank;
                    cache_frame_valid <= 1'b1;
                    cache_commit_toggle <= ~cache_commit_toggle;
                    last_loaded_camera_commit <= frame_commit_toggle;
                    disp_state <= D_IDLE;
                end

                default: disp_state <= D_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------------
    // Custom three-client arbiter retained from Stage 9.
    // ---------------------------------------------------------------------
    ddr_axi_arbiter arbiter (
        .clk(clk_ui),
        .rst(rst),

        .disp_req_valid(disp_req_valid),
        .disp_req_addr(disp_req_addr),
        .disp_req_ready(disp_req_ready),
        .disp_rsp_valid(disp_rsp_valid),
        .disp_rsp_data(disp_rsp_data),
        .disp_rsp_error(disp_rsp_error),

        .cam_req_valid(cam_req_valid),
        .cam_req_addr(cam_req_addr),
        .cam_req_data(cam_req_data),
        .cam_req_strb(8'hff),
        .cam_req_ready(cam_req_ready),
        .cam_rsp_valid(cam_rsp_valid),
        .cam_rsp_error(cam_rsp_error),

        .gfx_req_valid(gfx_req_valid),
        .gfx_req_addr(gfx_req_addr),
        .gfx_req_data(gfx_req_data),
        .gfx_req_strb(8'hff),
        .gfx_req_ready(gfx_req_ready),
        .gfx_rsp_valid(gfx_rsp_valid),
        .gfx_rsp_error(gfx_rsp_error),

        .display_granted_sticky(arb_display_granted),
        .camera_granted_sticky(arb_camera_granted),
        .graphics_granted_sticky(arb_graphics_granted),
        .axi_error_sticky(arbiter_axi_error),

        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(m_axi_awqos),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),

        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );
endmodule


module ddr_axi_arbiter (
    input  wire        clk,
    input  wire        rst,

    input  wire        disp_req_valid,
    input  wire [26:0] disp_req_addr,
    output reg         disp_req_ready,
    output reg         disp_rsp_valid,
    output reg  [63:0] disp_rsp_data,
    output reg         disp_rsp_error,

    input  wire        cam_req_valid,
    input  wire [26:0] cam_req_addr,
    input  wire [63:0] cam_req_data,
    input  wire [7:0]  cam_req_strb,
    output reg         cam_req_ready,
    output reg         cam_rsp_valid,
    output reg         cam_rsp_error,

    input  wire        gfx_req_valid,
    input  wire [26:0] gfx_req_addr,
    input  wire [63:0] gfx_req_data,
    input  wire [7:0]  gfx_req_strb,
    output reg         gfx_req_ready,
    output reg         gfx_rsp_valid,
    output reg         gfx_rsp_error,

    output reg         display_granted_sticky,
    output reg         camera_granted_sticky,
    output reg         graphics_granted_sticky,
    output reg         axi_error_sticky,

    output wire [0:0]  m_axi_awid,
    output wire [26:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire [0:0]  m_axi_awlock,
    output wire [3:0]  m_axi_awcache,
    output wire [2:0]  m_axi_awprot,
    output wire [3:0]  m_axi_awqos,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,

    output wire [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,

    input  wire [0:0]  m_axi_bid,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,

    output wire [0:0]  m_axi_arid,
    output wire [26:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire [0:0]  m_axi_arlock,
    output wire [3:0]  m_axi_arcache,
    output wire [2:0]  m_axi_arprot,
    output wire [3:0]  m_axi_arqos,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,

    input  wire [0:0]  m_axi_rid,
    input  wire [63:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready
);
    localparam [2:0] A_IDLE = 3'd0,
                     A_AW   = 3'd1,
                     A_W    = 3'd2,
                     A_B    = 3'd3,
                     A_AR   = 3'd4,
                     A_R    = 3'd5;
    localparam [1:0] OWNER_NONE = 2'd0,
                     OWNER_DISP = 2'd1,
                     OWNER_CAM  = 2'd2,
                     OWNER_GFX  = 2'd3;

    reg [2:0] state;
    reg [1:0] owner;
    reg       rr_next_graphics;
    reg [26:0] latched_addr;
    reg [63:0] latched_wdata;
    reg [7:0]  latched_wstrb;

    assign m_axi_awid    = 1'b0;
    assign m_axi_awaddr  = latched_addr;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = 3'd3;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_awvalid = (state == A_AW);

    assign m_axi_wdata   = latched_wdata;
    assign m_axi_wstrb   = latched_wstrb;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wvalid  = (state == A_W);
    assign m_axi_bready  = (state == A_B);

    assign m_axi_arid    = 1'b0;
    assign m_axi_araddr  = latched_addr;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'd3;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_arvalid = (state == A_AR);
    assign m_axi_rready  = (state == A_R);

    always @(posedge clk) begin
        if (rst) begin
            state <= A_IDLE;
            owner <= OWNER_NONE;
            rr_next_graphics <= 1'b0;
            latched_addr <= 27'd0;
            latched_wdata <= 64'd0;
            latched_wstrb <= 8'd0;

            disp_req_ready <= 1'b0;
            disp_rsp_valid <= 1'b0;
            disp_rsp_data <= 64'd0;
            disp_rsp_error <= 1'b0;
            cam_req_ready <= 1'b0;
            cam_rsp_valid <= 1'b0;
            cam_rsp_error <= 1'b0;
            gfx_req_ready <= 1'b0;
            gfx_rsp_valid <= 1'b0;
            gfx_rsp_error <= 1'b0;

            display_granted_sticky <= 1'b0;
            camera_granted_sticky <= 1'b0;
            graphics_granted_sticky <= 1'b0;
            axi_error_sticky <= 1'b0;
        end else begin
            // Handshake/response outputs are one-clock pulses.
            disp_req_ready <= 1'b0;
            disp_rsp_valid <= 1'b0;
            disp_rsp_error <= 1'b0;
            cam_req_ready <= 1'b0;
            cam_rsp_valid <= 1'b0;
            cam_rsp_error <= 1'b0;
            gfx_req_ready <= 1'b0;
            gfx_rsp_valid <= 1'b0;
            gfx_rsp_error <= 1'b0;

            case (state)
                A_IDLE: begin
                    owner <= OWNER_NONE;

                    // Strict priority for the display read client.
                    if (disp_req_valid) begin
                        owner <= OWNER_DISP;
                        latched_addr <= disp_req_addr;
                        disp_req_ready <= 1'b1;
                        display_granted_sticky <= 1'b1;
                        state <= A_AR;
                    end else if (cam_req_valid && gfx_req_valid) begin
                        if (rr_next_graphics) begin
                            owner <= OWNER_GFX;
                            latched_addr <= gfx_req_addr;
                            latched_wdata <= gfx_req_data;
                            latched_wstrb <= gfx_req_strb;
                            gfx_req_ready <= 1'b1;
                            graphics_granted_sticky <= 1'b1;
                            rr_next_graphics <= 1'b0;
                        end else begin
                            owner <= OWNER_CAM;
                            latched_addr <= cam_req_addr;
                            latched_wdata <= cam_req_data;
                            latched_wstrb <= cam_req_strb;
                            cam_req_ready <= 1'b1;
                            camera_granted_sticky <= 1'b1;
                            rr_next_graphics <= 1'b1;
                        end
                        state <= A_AW;
                    end else if (cam_req_valid) begin
                        owner <= OWNER_CAM;
                        latched_addr <= cam_req_addr;
                        latched_wdata <= cam_req_data;
                        latched_wstrb <= cam_req_strb;
                        cam_req_ready <= 1'b1;
                        camera_granted_sticky <= 1'b1;
                        rr_next_graphics <= 1'b1;
                        state <= A_AW;
                    end else if (gfx_req_valid) begin
                        owner <= OWNER_GFX;
                        latched_addr <= gfx_req_addr;
                        latched_wdata <= gfx_req_data;
                        latched_wstrb <= gfx_req_strb;
                        gfx_req_ready <= 1'b1;
                        graphics_granted_sticky <= 1'b1;
                        rr_next_graphics <= 1'b0;
                        state <= A_AW;
                    end
                end

                A_AW: begin
                    if (m_axi_awready)
                        state <= A_W;
                end

                A_W: begin
                    if (m_axi_wready)
                        state <= A_B;
                end

                A_B: begin
                    if (m_axi_bvalid) begin
                        if (m_axi_bresp != 2'b00)
                            axi_error_sticky <= 1'b1;

                        if (owner == OWNER_CAM) begin
                            cam_rsp_valid <= 1'b1;
                            cam_rsp_error <= (m_axi_bresp != 2'b00);
                        end else if (owner == OWNER_GFX) begin
                            gfx_rsp_valid <= 1'b1;
                            gfx_rsp_error <= (m_axi_bresp != 2'b00);
                        end
                        state <= A_IDLE;
                    end
                end

                A_AR: begin
                    if (m_axi_arready)
                        state <= A_R;
                end

                A_R: begin
                    if (m_axi_rvalid) begin
                        disp_rsp_data <= m_axi_rdata;
                        disp_rsp_valid <= 1'b1;
                        disp_rsp_error <= (m_axi_rresp != 2'b00) || !m_axi_rlast;
                        if ((m_axi_rresp != 2'b00) || !m_axi_rlast)
                            axi_error_sticky <= 1'b1;
                        state <= A_IDLE;
                    end
                end

                default: state <= A_IDLE;
            endcase
        end
    end
endmodule




// =============================================================================
// STAGE 10 PAIRED DISPLAY CACHE
//
// Camera pixels are RGB565. Graphics pixels are ARGB4444. Both layers use the
// same ping-pong bank number and are only exposed to VGA after the memory system
// has completely loaded both layers into that bank.
// =============================================================================
module stage10_display_cache #(
    parameter integer FB_WIDTH  = 160,
    parameter integer FB_HEIGHT = 120,
    parameter integer FB_PIXELS = 19200
)(
    input  wire        ui_clk,
    input  wire        resetn_ui,
    input  wire        cam_cache_wr_en,
    input  wire        cam_cache_wr_bank,
    input  wire [14:0] cam_cache_wr_addr,
    input  wire [15:0] cam_cache_wr_data,
    input  wire        gfx_cache_wr_en,
    input  wire        gfx_cache_wr_bank,
    input  wire [14:0] gfx_cache_wr_addr,
    input  wire [15:0] gfx_cache_wr_data,
    input  wire        cache_frame_valid,
    input  wire        cache_committed_bank,
    input  wire        cache_commit_toggle,

    input  wire        clk100,
    input  wire        resetn_vga,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire        frame_start,
    output wire [11:0] camera_rgb,
    output wire [15:0] graphics_argb,
    output reg         camera_active,
    output reg         display_valid
);

    // -------------------------------------------------------------------------
    // Stage 10 BRAM fix:
    // Each cache bank is a true dual-clock simple-dual-port memory:
    //   Port A: MIG UI clock writes a complete frame into the inactive bank.
    //   Port B: 100 MHz display domain performs synchronous reads.
    //
    // Keeping the RAM read itself out of an async-reset process matches the
    // Vivado block-RAM inference template. The previous version placed the
    // memory read inside an asynchronously-reset always block, which caused
    // Vivado to implement the frame caches as distributed LUT RAM.
    // -------------------------------------------------------------------------
    wire in_preview = (x >= 10'd260) && (x < 10'd580) &&
                      (y >= 10'd100) && (y < 10'd340);

    wire [9:0] preview_x = x - 10'd260;
    wire [9:0] preview_y = y - 10'd100;
    wire [7:0] source_x  = preview_x[8:1];
    wire [6:0] source_y  = preview_y[7:1];

    wire [14:0] calculated_read_addr =
        ({8'd0, source_y} << 7) +
        ({8'd0, source_y} << 5) +
        {7'd0, source_x};

    // Never present an out-of-frame address to the BRAM read ports.
    wire [14:0] read_addr = in_preview ? calculated_read_addr : 15'd0;

    wire [15:0] cam_cache0_q;
    wire [15:0] cam_cache1_q;
    wire [15:0] gfx_cache0_q;
    wire [15:0] gfx_cache1_q;

    stage10_dc_bram16 #(.DEPTH(FB_PIXELS)) cam_cache_bank0 (
        .wr_clk (ui_clk),
        .wr_en  (cam_cache_wr_en && !cam_cache_wr_bank),
        .wr_addr(cam_cache_wr_addr),
        .wr_data(cam_cache_wr_data),
        .rd_clk (clk100),
        .rd_addr(read_addr),
        .rd_data(cam_cache0_q)
    );

    stage10_dc_bram16 #(.DEPTH(FB_PIXELS)) cam_cache_bank1 (
        .wr_clk (ui_clk),
        .wr_en  (cam_cache_wr_en && cam_cache_wr_bank),
        .wr_addr(cam_cache_wr_addr),
        .wr_data(cam_cache_wr_data),
        .rd_clk (clk100),
        .rd_addr(read_addr),
        .rd_data(cam_cache1_q)
    );

    stage10_dc_bram16 #(.DEPTH(FB_PIXELS)) gfx_cache_bank0 (
        .wr_clk (ui_clk),
        .wr_en  (gfx_cache_wr_en && !gfx_cache_wr_bank),
        .wr_addr(gfx_cache_wr_addr),
        .wr_data(gfx_cache_wr_data),
        .rd_clk (clk100),
        .rd_addr(read_addr),
        .rd_data(gfx_cache0_q)
    );

    stage10_dc_bram16 #(.DEPTH(FB_PIXELS)) gfx_cache_bank1 (
        .wr_clk (ui_clk),
        .wr_en  (gfx_cache_wr_en && gfx_cache_wr_bank),
        .wr_addr(gfx_cache_wr_addr),
        .wr_data(gfx_cache_wr_data),
        .rd_clk (clk100),
        .rd_addr(read_addr),
        .rd_data(gfx_cache1_q)
    );

    // Commit information crosses from the MIG UI clock domain into the display
    // domain. Frame-bank selection changes only at a VGA frame boundary.
    (* ASYNC_REG = "TRUE" *) reg [2:0] commit_sync = 3'b000;
    (* ASYNC_REG = "TRUE" *) reg [1:0] bank_sync   = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] valid_sync  = 2'b00;

    reg commit_seen = 1'b0;
    reg active_bank = 1'b0;

    always @(posedge clk100 or negedge resetn_vga) begin
        if (!resetn_vga) begin
            commit_sync   <= 3'b000;
            bank_sync     <= 2'b00;
            valid_sync    <= 2'b00;
            commit_seen   <= 1'b0;
            active_bank   <= 1'b0;
            display_valid <= 1'b0;
            camera_active <= 1'b0;
        end else begin
            commit_sync <= {commit_sync[1:0], cache_commit_toggle};
            bank_sync   <= {bank_sync[0], cache_committed_bank};
            valid_sync  <= {valid_sync[0], cache_frame_valid};

            if (frame_start && valid_sync[1] &&
                (commit_sync[2] != commit_seen)) begin
                active_bank   <= bank_sync[1];
                commit_seen   <= commit_sync[2];
                display_valid <= 1'b1;
            end

            // The BRAM read is one clk100 cycle. The rest of Stage 10 already
            // pipelines coordinates/control to match the cache + blender delay.
            camera_active <= in_preview && display_valid;
        end
    end

    wire [15:0] selected_camera_pixel =
        active_bank ? cam_cache1_q : cam_cache0_q;

    wire [15:0] selected_graphics_pixel =
        active_bank ? gfx_cache1_q : gfx_cache0_q;

    assign camera_rgb = {
        selected_camera_pixel[15:12],
        selected_camera_pixel[10:7],
        selected_camera_pixel[4:1]
    };

    // Outside the preview, make the foreground fully transparent.
    assign graphics_argb = camera_active ? selected_graphics_pixel : 16'h0000;

endmodule


// -----------------------------------------------------------------------------
// 16-bit independent-clock simple-dual-port BRAM.
//
// IMPORTANT: Do not add an asynchronous reset to rd_data or the RAM array.
// This coding style is intentionally kept close to the Xilinx/Vivado block-RAM
// inference template so each 19,200 x 16 cache maps to RAMB36/RAMB18 resources
// instead of thousands of distributed-RAM LUTs.
// -----------------------------------------------------------------------------
module stage10_dc_bram16 #(
    parameter integer DEPTH = 19200
)(
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [14:0] wr_addr,
    input  wire [15:0] wr_data,

    input  wire        rd_clk,
    input  wire [14:0] rd_addr,
    output reg  [15:0] rd_data
);

    (* ram_style = "block" *) reg [15:0] mem [0:DEPTH-1];

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end

endmodule


// =============================================================================
// PIPELINED FIXED-POINT RGB444 ALPHA BLENDER
//
// Alpha is unsigned 8-bit fixed point: 0 = background, 255 = foreground.
// For intermediate alpha values:
//   out = (foreground*alpha + background*(255-alpha) + 128) >> 8
// The exact 0 and 255 endpoints are bypassed so fully transparent/opaque pixels
// remain exact. Inputs are expanded from RGB444 to 8 bits before multiplication.
// =============================================================================
module alpha_blend_rgb444_pipe (
    input  wire        clk,
    input  wire        resetn,
    input  wire [11:0] background_rgb,
    input  wire [11:0] foreground_rgb,
    input  wire [7:0]  alpha,
    output reg  [11:0] out_rgb
);
    wire [7:0] bg_r8 = {background_rgb[11:8], background_rgb[11:8]};
    wire [7:0] bg_g8 = {background_rgb[7:4],  background_rgb[7:4]};
    wire [7:0] bg_b8 = {background_rgb[3:0],  background_rgb[3:0]};
    wire [7:0] fg_r8 = {foreground_rgb[11:8], foreground_rgb[11:8]};
    wire [7:0] fg_g8 = {foreground_rgb[7:4],  foreground_rgb[7:4]};
    wire [7:0] fg_b8 = {foreground_rgb[3:0],  foreground_rgb[3:0]};
    wire [7:0] inv_alpha = 8'hff - alpha;

    reg [15:0] fg_r_mul = 16'd0, fg_g_mul = 16'd0, fg_b_mul = 16'd0;
    reg [15:0] bg_r_mul = 16'd0, bg_g_mul = 16'd0, bg_b_mul = 16'd0;
    reg [11:0] bg_hold = 12'd0, fg_hold = 12'd0;
    reg alpha_zero = 1'b1, alpha_full = 1'b0;

    wire [16:0] r_sum = {1'b0, fg_r_mul} + {1'b0, bg_r_mul} + 17'd128;
    wire [16:0] g_sum = {1'b0, fg_g_mul} + {1'b0, bg_g_mul} + 17'd128;
    wire [16:0] b_sum = {1'b0, fg_b_mul} + {1'b0, bg_b_mul} + 17'd128;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            fg_r_mul <= 16'd0; fg_g_mul <= 16'd0; fg_b_mul <= 16'd0;
            bg_r_mul <= 16'd0; bg_g_mul <= 16'd0; bg_b_mul <= 16'd0;
            bg_hold <= 12'd0; fg_hold <= 12'd0;
            alpha_zero <= 1'b1;
            alpha_full <= 1'b0;
            out_rgb <= 12'd0;
        end else begin
            // Pipeline stage 1: six 8x8 fixed-point products.
            fg_r_mul <= fg_r8 * alpha;
            fg_g_mul <= fg_g8 * alpha;
            fg_b_mul <= fg_b8 * alpha;
            bg_r_mul <= bg_r8 * inv_alpha;
            bg_g_mul <= bg_g8 * inv_alpha;
            bg_b_mul <= bg_b8 * inv_alpha;
            bg_hold <= background_rgb;
            fg_hold <= foreground_rgb;
            alpha_zero <= (alpha == 8'h00);
            alpha_full <= (alpha == 8'hff);

            // Pipeline stage 2: add, round and divide by 256 with a shift.
            if (alpha_zero)
                out_rgb <= bg_hold;
            else if (alpha_full)
                out_rgb <= fg_hold;
            else
                out_rgb <= {r_sum[15:12], g_sum[15:12], b_sum[15:12]};
        end
    end
endmodule


// =============================================================================
// STAGE 11 PRIORITY / MULTI-WINDOW COMPOSITOR
// =============================================================================
module stage11_priority_compositor (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire        video_on,
    input  wire [11:0] base_rgb,
    input  wire        warning_request,
    input  wire        critical_request,
    input  wire        critical_flash,
    output reg  [11:0] rgb,
    output reg  [1:0]  active_level
);
    // Main live-video window used by the project. Alert windows are deliberately
    // defined relative to it so the alerts demonstrate true overlay/compositing.
    wire in_camera = (x >= 10'd260) && (x < 10'd580) &&
                     (y >= 10'd100) && (y < 10'd340);

    wire warning_border = in_camera &&
        ((x < 10'd268) || (x >= 10'd572) ||
         (y < 10'd108) || (y >= 10'd332));

    wire warning_banner = (x >= 10'd300) && (x < 10'd540) &&
                          (y >= 10'd112) && (y < 10'd156);

    // Critical modal occupies the center of the live-video window.
    wire critical_panel = (x >= 10'd315) && (x < 10'd525) &&
                          (y >= 10'd165) && (y < 10'd275);
    wire critical_border = critical_panel &&
        ((x < 10'd323) || (x >= 10'd517) ||
         (y < 10'd173) || (y >= 10'd267));

    // Large exclamation mark in the critical modal.
    wire exclamation_stem = (x >= 10'd414) && (x < 10'd426) &&
                            (y >= 10'd187) && (y < 10'd235);
    wire exclamation_dot  = (x >= 10'd414) && (x < 10'd426) &&
                            (y >= 10'd245) && (y < 10'd257);

    // Simple 50% RGB444 blend used by the alert windows. Stage 10 already
    // demonstrates general fixed-point alpha blending; here the fixed blend
    // keeps this priority block small and easy to verify.
    function [11:0] blend50;
        input [11:0] bg;
        input [11:0] fg;
        reg [4:0] rsum, gsum, bsum;
        begin
            rsum = {1'b0,bg[11:8]} + {1'b0,fg[11:8]};
            gsum = {1'b0,bg[7:4]}  + {1'b0,fg[7:4]};
            bsum = {1'b0,bg[3:0]}  + {1'b0,fg[3:0]};
            blend50 = {rsum[4:1], gsum[4:1], bsum[4:1]};
        end
    endfunction

    always @(*) begin
        rgb = video_on ? base_rgb : 12'h000;
        active_level = 2'd0;

        // Z1: warning. Yellow border + translucent amber banner.
        if (video_on && warning_request) begin
            active_level = 2'd1;
            if (warning_border)
                rgb = 12'hFD0;
            if (warning_banner)
                rgb = blend50(base_rgb, 12'hFC0);
        end

        // Z2: critical. This block is intentionally evaluated LAST so it wins
        // whenever WARNING and CRITICAL are both asserted.
        if (video_on && critical_request) begin
            active_level = 2'd2;

            // Permanent red frame around the live video window.
            if (in_camera &&
                ((x < 10'd268) || (x >= 10'd572) ||
                 (y < 10'd108) || (y >= 10'd332)))
                rgb = 12'hF00;

            if (critical_panel) begin
                if (critical_border)
                    rgb = 12'hFFF;
                else if (critical_flash)
                    rgb = blend50(base_rgb, 12'hF00);
                else
                    rgb = 12'h500;
            end

            // The icon remains bright regardless of flash phase.
            if (exclamation_stem || exclamation_dot)
                rgb = 12'hFFF;
        end
    end
endmodule

