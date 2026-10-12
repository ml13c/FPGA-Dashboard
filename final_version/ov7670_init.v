// OV7670 initialization for the Nexys 4 DDR dashboard project.
//
// This keeps the QVGA/scaling settings that already produced live video on
// the user's hardware, then adds the fuller RGB565 color matrix, gamma, AGC,
// AEC and black-level setup used by AngeloJacobo/FPGA_OV7670_Camera_Interface.
//
// 
// COM10 is intentionally 0x00, NOT 0x20. On this dashboard design, suppressing
// PCLK during blanking prevented the framebuffer from completing frames.
module ov7670_init #(
    parameter integer STARTUP_WAIT    = 1000000, // 10 ms at 100 MHz after RESETN
    parameter integer RESET_WAIT      = 2000000, // 20 ms after COM7 software reset
    parameter integer INTERWRITE_WAIT = 100000   // 1 ms between SCCB writes
) (
    input wire clk100,
    input wire resetn,
    input wire sda_in,
    output wire scl_low,
    output wire sda_low,
    output reg config_done = 1'b0,
    output reg any_nack = 1'b0,
    // Kept at 6 bits for compatibility with the existing top.v diagnostic bus.
    // The full internal step index is 7 bits because this table has >64 writes.
    output wire [5:0] current_step
);
    localparam integer SETTINGS = 76;
    localparam [2:0] WAIT_START = 3'd0,
                     SEND       = 3'd1,
                     WAIT_BUSY  = 3'd2,
                     WAIT_DONE  = 3'd3,
                     WAIT_GAP   = 3'd4,
                     COMPLETE   = 3'd5;

    reg [2:0] phase = WAIT_START;
    reg [21:0] delay_count = 22'd0;
    reg [6:0] step_index = 7'd0;
    reg fire = 1'b0;
    reg after_reset = 1'b0;
    wire write_busy, write_done, write_nack;
    reg [15:0] reg_setting;

    assign current_step = step_index[5:0];

    sccb_write24 writer(
        .clk100(clk100), .resetn(resetn), .start(fire),
        .reg_addr(reg_setting[15:8]), .reg_data(reg_setting[7:0]),
        .sda_in(sda_in), .scl_low(scl_low), .sda_low(sda_low),
        .busy(write_busy), .done(write_done), .nack(write_nack)
    );

    // Each entry is {register address, value}.
    // Entries 0..24 preserve the proven live-video timing/QVGA path.
    // The remaining entries add the fuller color-processing setup.
    always @(*) begin
        case (step_index)
             0: reg_setting = 16'h1280; // COM7: software reset
             1: reg_setting = 16'h1101; // CLKRC: keep proven clock divider
             2: reg_setting = 16'h1204; // COM7: RGB output
             3: reg_setting = 16'h8c00; // RGB444: disable alternate packing
             4: reg_setting = 16'h40d0; // COM15: RGB565, full output range
             5: reg_setting = 16'h3a04; // TSLB: RGB byte order
             6: reg_setting = 16'h0c04; // COM3: enable downsampling/scaling
             7: reg_setting = 16'h3e19; // COM14: QVGA scaling / PCLK divisor
             8: reg_setting = 16'h7211; // SCALING_DCWCTR: downsample by two
             9: reg_setting = 16'h73f1; // SCALING_PCLK_DIV
            10: reg_setting = 16'h703a; // SCALING_XSC
            11: reg_setting = 16'h7135; // SCALING_YSC
            12: reg_setting = 16'ha202; // SCALING_PCLK_DELAY
            13: reg_setting = 16'h1716; // HSTART
            14: reg_setting = 16'h1804; // HSTOP
            15: reg_setting = 16'h3224; // HREF alignment
            16: reg_setting = 16'h1902; // VSTART
            17: reg_setting = 16'h1a7a; // VSTOP
            18: reg_setting = 16'h030a; // VREF alignment
            19: reg_setting = 16'h1500; // COM10: free-running PCLK (project fix)
            20: reg_setting = 16'h1e00; // MVFP: no mirror / no vertical flip
            21: reg_setting = 16'h0f41; // COM6: timing
            22: reg_setting = 16'h3c78; // COM12
            23: reg_setting = 16'h330b; // CHLF
            24: reg_setting = 16'h3dc0; // COM13: gamma/color-matrix path
            25: reg_setting = 16'h1418; // COM9: gain ceiling x4

            // RGB matrix / saturation from the referenced working design.
            26: reg_setting = 16'h4fb3; // MTX1
            27: reg_setting = 16'h50b3; // MTX2
            28: reg_setting = 16'h5100; // MTX3
            29: reg_setting = 16'h523d; // MTX4
            30: reg_setting = 16'h53a7; // MTX5
            31: reg_setting = 16'h54e4; // MTX6
            32: reg_setting = 16'h589e; // MTXS

            // Black-level / color tuning used by the referenced design.
            33: reg_setting = 16'hb084;
            34: reg_setting = 16'hb10c;
            35: reg_setting = 16'hb20e;
            36: reg_setting = 16'hb380;
            37: reg_setting = 16'h6900; // GFIX initial
            38: reg_setting = 16'h7400; // REG74 digital gain

            // Gamma curve.
            39: reg_setting = 16'h7a20;
            40: reg_setting = 16'h7b10;
            41: reg_setting = 16'h7c1e;
            42: reg_setting = 16'h7d35;
            43: reg_setting = 16'h7e5a;
            44: reg_setting = 16'h7f69;
            45: reg_setting = 16'h8076;
            46: reg_setting = 16'h8180;
            47: reg_setting = 16'h8288;
            48: reg_setting = 16'h838f;
            49: reg_setting = 16'h8496;
            50: reg_setting = 16'h85a3;
            51: reg_setting = 16'h86af;
            52: reg_setting = 16'h87c4;
            53: reg_setting = 16'h88d7;
            54: reg_setting = 16'h89e8;

            // AGC/AEC setup. Disable while programming limits, then enable.
            55: reg_setting = 16'h13e0; // COM8: temporarily disable AGC/AEC
            56: reg_setting = 16'h0000; // GAIN seed
            57: reg_setting = 16'h1000; // AECH seed
            58: reg_setting = 16'h0d40; // COM4
            59: reg_setting = 16'h1418; // COM9
            60: reg_setting = 16'ha505; // BD50MAX
            61: reg_setting = 16'hab07; // BD60MAX
            62: reg_setting = 16'h2495; // AEW
            63: reg_setting = 16'h2533; // AEB
            64: reg_setting = 16'h26e3; // VPT
            65: reg_setting = 16'h9f78; // HAECC1
            66: reg_setting = 16'ha068; // HAECC2
            67: reg_setting = 16'ha103;
            68: reg_setting = 16'ha6d8; // HAECC3
            69: reg_setting = 16'ha7d8; // HAECC4
            70: reg_setting = 16'ha8f0; // HAECC5
            71: reg_setting = 16'ha990; // HAECC6
            72: reg_setting = 16'haa94; // HAECC7
            73: reg_setting = 16'h13e5; // COM8: enable source's AGC/AEC setup
            74: reg_setting = 16'h1e00; // keep image orientation unchanged
            75: reg_setting = 16'h6906; // RGB gain used by reference setup
            default: reg_setting = 16'h1500;
        endcase
    end

    always @(posedge clk100 or negedge resetn) begin
        if (!resetn) begin
            phase <= WAIT_START;
            delay_count <= 22'd0;
            step_index <= 7'd0;
            fire <= 1'b0;
            after_reset <= 1'b0;
            config_done <= 1'b0;
            any_nack <= 1'b0;
        end else begin
            fire <= 1'b0;
            case (phase)
                WAIT_START: begin
                    if (delay_count >= STARTUP_WAIT-1) begin
                        delay_count <= 22'd0;
                        phase <= SEND;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                SEND: begin
                    fire <= 1'b1;
                    phase <= WAIT_BUSY;
                end

                WAIT_BUSY: begin
                    if (write_busy)
                        phase <= WAIT_DONE;
                end

                WAIT_DONE: begin
                    if (write_done) begin
                        any_nack <= any_nack | write_nack;
                        delay_count <= 22'd0;
                        after_reset <= (step_index == 0);
                        if (step_index == SETTINGS-1)
                            phase <= COMPLETE;
                        else
                            phase <= WAIT_GAP;
                    end
                end

                WAIT_GAP: begin
                    if ((after_reset && delay_count >= RESET_WAIT-1) ||
                        (!after_reset && delay_count >= INTERWRITE_WAIT-1)) begin
                        delay_count <= 22'd0;
                        step_index <= step_index + 1'b1;
                        after_reset <= 1'b0;
                        phase <= SEND;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                COMPLETE: begin
                    config_done <= 1'b1;
                end

                default: begin
                    phase <= WAIT_START;
                    delay_count <= 22'd0;
                end
            endcase
        end
    end
endmodule
