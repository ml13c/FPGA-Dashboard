// 100 khz, three-byte SCCB/I2C-style register writer for the ov7670.
// SIOC and SIOD are OPEN DRAIN: this module ONLY pulls them low or releases.
// external pullups must be connected to a VERIFIED camera-safe IO supply.
module sccb_write24 #(
    parameter integer HALF_CYCLES = 500 // 5 us at 100 mhz -> 100 khz SIOC
) (
    input wire clk100,
    input wire resetn,
    input wire start,
    input wire [7:0] reg_addr,
    input wire [7:0] reg_data,
    input wire sda_in,
    output reg scl_low = 1'b0,
    output reg sda_low = 1'b0,
    output reg busy = 1'b0,
    output reg done = 1'b0,
    output reg nack = 1'b0
);
    localparam [3:0]
        IDLE = 0, START_HI = 1, START_HOLD = 2,
        BIT_LOW = 3, BIT_HIGH = 4, ACK_LOW = 5, ACK_HIGH = 6,
        STOP_LOW = 7, STOP_SCL = 8, STOP_FREE = 9, FINISH = 10;

    reg [3:0] state = IDLE;
    reg [15:0] count = 16'd0;
    reg [23:0] shift = 24'd0;
    reg [2:0] bit_in_byte = 3'd0;
    reg [1:0] byte_index = 2'd0;

    always @(posedge clk100 or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            scl_low <= 1'b0;
            sda_low <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            nack <= 1'b0;
            count <= 16'd0;
            shift <= 24'd0;
            bit_in_byte <= 3'd0;
            byte_index <= 2'd0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    busy <= 1'b0;
                    if (start) begin
                        shift <= {8'h42, reg_addr, reg_data};
                        byte_index <= 0;
                        bit_in_byte <= 3'd7;
                        nack <= 1'b0;
                        busy <= 1'b1;
                        count <= 0;
                        state <= START_HI;
                    end
                end
                START_HI: begin
                    // allow pullups to establish idle-high before START.
                    scl_low <= 0; sda_low <= 0;
                    if (count == HALF_CYCLES-1) begin
                        count <= 0; state <= START_HOLD;
                    end else count <= count+1'b1;
                end
                START_HOLD: begin
                    // SDA falls while SCL is high.
                    scl_low <= 0; sda_low <= 1;
                    if (count == HALF_CYCLES-1) begin
                        count <= 0; state <= BIT_LOW;
                    end else count <= count+1'b1;
                end
                BIT_LOW: begin
                    scl_low <= 1;
                    sda_low <= ~shift[23];
                    if (count == HALF_CYCLES-1) begin
                        count <= 0; state <= BIT_HIGH;
                    end else count <= count+1'b1;
                end
                BIT_HIGH: begin
                    scl_low <= 0; // pullup produces rising clock edge
                    if (count == HALF_CYCLES-1) begin
                        count <= 0;
                        shift <= {shift[22:0], 1'b0};
                        if (bit_in_byte == 0) state <= ACK_LOW;
                        else begin
                            bit_in_byte <= bit_in_byte-1'b1;
                            state <= BIT_LOW;
                        end
                    end else count <= count+1'b1;
                end
                ACK_LOW: begin
                    scl_low <= 1; sda_low <= 0;
                    if (count == HALF_CYCLES-1) begin
                        count <= 0; state <= ACK_HIGH;
                    end else count <= count+1'b1;
                end
                ACK_HIGH: begin
                    scl_low <= 0; sda_low <= 0;
                    // OV7670's SCCB ninth bit can differ from standard I2C.
                    // record missing ACK for diagnostics; do not block setup.
                    if (count == HALF_CYCLES/2) nack <= nack | sda_in;
                    if (count == HALF_CYCLES-1) begin
                        count <= 0;
                        if (byte_index == 2) state <= STOP_LOW;
                        else begin
                            byte_index <= byte_index+1'b1;
                            bit_in_byte <= 3'd7;
                            state <= BIT_LOW;
                        end
                    end else count <= count+1'b1;
                end
                STOP_LOW: begin
                    scl_low <= 1; sda_low <= 1;
                    if (count == HALF_CYCLES-1) begin
                        count <= 0; state <= STOP_SCL;
                    end else count <= count+1'b1;
                end
                STOP_SCL: begin
                    scl_low <= 0; sda_low <= 1;
                    if (count == HALF_CYCLES-1) begin
                        count <= 0; state <= STOP_FREE;
                    end else count <= count+1'b1;
                end
                STOP_FREE: begin
                    scl_low <= 0; sda_low <= 0;
                    if (count == HALF_CYCLES-1) begin
                        count <= 0; state <= FINISH;
                    end else count <= count+1'b1;
                end
                FINISH: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
