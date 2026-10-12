// parameterized asynchronous FIFO using Gray-code pointer CDC.
//
// Only Gray-coded pointers cross clock domains. Each pointer passes through
// a two-flop synchronizer before being used by the opposite clock domain.
// The storage array is written by wr_clk and read by rd_clk.
module async_fifo_gray #(
    parameter integer DATA_WIDTH = 18,
    parameter integer ADDR_WIDTH = 10   // depth = 2**ADDR_WIDTH
)(
    input  wire                  rstn_async,

    input  wire                  wr_clk,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output reg                   wr_full = 1'b0,
    output reg                   wr_overflow = 1'b0,

    input  wire                  rd_clk,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data = {DATA_WIDTH{1'b0}},
    output reg                   rd_valid = 1'b0,
    output reg                   rd_empty = 1'b1,
    output reg                   rd_underflow = 1'b0
);
    localparam integer DEPTH = (1 << ADDR_WIDTH);
    localparam integer PTR_WIDTH = ADDR_WIDTH + 1;

    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // asynchronous assert, synchronous deassert reset in each clock domain.
    (* ASYNC_REG = "TRUE" *) reg [1:0] wr_reset_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] rd_reset_sync = 2'b00;

    always @(posedge wr_clk or negedge rstn_async) begin
        if (!rstn_async)
            wr_reset_sync <= 2'b00;
        else
            wr_reset_sync <= {wr_reset_sync[0], 1'b1};
    end

    always @(posedge rd_clk or negedge rstn_async) begin
        if (!rstn_async)
            rd_reset_sync <= 2'b00;
        else
            rd_reset_sync <= {rd_reset_sync[0], 1'b1};
    end

    wire wr_ready = wr_reset_sync[1];
    wire rd_ready = rd_reset_sync[1];

    function [PTR_WIDTH-1:0] bin_to_gray;
        input [PTR_WIDTH-1:0] binary_value;
        begin
            bin_to_gray = (binary_value >> 1) ^ binary_value;
        end
    endfunction

    reg [PTR_WIDTH-1:0] wr_bin = {PTR_WIDTH{1'b0}};
    reg [PTR_WIDTH-1:0] wr_gray = {PTR_WIDTH{1'b0}};
    reg [PTR_WIDTH-1:0] rd_bin = {PTR_WIDTH{1'b0}};
    reg [PTR_WIDTH-1:0] rd_gray = {PTR_WIDTH{1'b0}};

    // synchronize read pointer into write domain.
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_wr1 = {PTR_WIDTH{1'b0}};
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_wr2 = {PTR_WIDTH{1'b0}};

    // synchronize write pointer into read domain.
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_rd1 = {PTR_WIDTH{1'b0}};
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_rd2 = {PTR_WIDTH{1'b0}};

    always @(posedge wr_clk) begin
        if (!wr_ready) begin
            rd_gray_wr1 <= {PTR_WIDTH{1'b0}};
            rd_gray_wr2 <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_gray_wr1 <= rd_gray;
            rd_gray_wr2 <= rd_gray_wr1;
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_ready) begin
            wr_gray_rd1 <= {PTR_WIDTH{1'b0}};
            wr_gray_rd2 <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_gray_rd1 <= wr_gray;
            wr_gray_rd2 <= wr_gray_rd1;
        end
    end

    wire wr_accept = wr_en && !wr_full && wr_ready;
    wire rd_accept = rd_en && !rd_empty && rd_ready;

    wire [PTR_WIDTH-1:0] wr_bin_next = wr_bin + wr_accept;
    wire [PTR_WIDTH-1:0] wr_gray_next = bin_to_gray(wr_bin_next);
    wire [PTR_WIDTH-1:0] rd_bin_next = rd_bin + rd_accept;
    wire [PTR_WIDTH-1:0] rd_gray_next = bin_to_gray(rd_bin_next);

    // For an asynchronous FIFO, full occurs when the next write pointer
    // equals the synchronized read pointer with its top two Gray bits inverted.
    wire [PTR_WIDTH-1:0] rd_gray_full_compare =
        {~rd_gray_wr2[PTR_WIDTH-1:PTR_WIDTH-2],
          rd_gray_wr2[PTR_WIDTH-3:0]};
    wire wr_full_next = (wr_gray_next == rd_gray_full_compare);
    wire rd_empty_next = (rd_gray_next == wr_gray_rd2);

    // write domain state and memory port.
    always @(posedge wr_clk) begin
        if (!wr_ready) begin
            wr_bin <= {PTR_WIDTH{1'b0}};
            wr_gray <= {PTR_WIDTH{1'b0}};
            wr_full <= 1'b0;
            wr_overflow <= 1'b0;
        end else begin
            wr_overflow <= wr_en && wr_full;
            if (wr_accept) begin
                mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
                wr_bin <= wr_bin_next;
                wr_gray <= wr_gray_next;
            end
            wr_full <= wr_full_next;
        end
    end

    // read domain state and memory port. rd_valid marks the cycle in which
    // rd_data contains the word requested on the previous active edge.
    always @(posedge rd_clk) begin
        if (!rd_ready) begin
            rd_bin <= {PTR_WIDTH{1'b0}};
            rd_gray <= {PTR_WIDTH{1'b0}};
            rd_empty <= 1'b1;
            rd_data <= {DATA_WIDTH{1'b0}};
            rd_valid <= 1'b0;
            rd_underflow <= 1'b0;
        end else begin
            rd_valid <= 1'b0;
            rd_underflow <= rd_en && rd_empty;
            if (rd_accept) begin
                rd_data <= mem[rd_bin[ADDR_WIDTH-1:0]];
                rd_valid <= 1'b1;
                rd_bin <= rd_bin_next;
                rd_gray <= rd_gray_next;
            end
            rd_empty <= rd_empty_next;
        end
    end
endmodule
