`timescale 1ns/1ps
// ===================================================================
// uart_tx.v -- Simple UART TRANSMITTER, 8N1, fixed baud
// -------------------------------------------------------------------
// CLK_HZ / BAUD must be an integer (default 100MHz / 115200).
// Interface: CPU writes 1 byte + a start pulse (1 cycle) -> the module
// serially sends 10 bits (1 start + 8 data LSB-first + 1 stop) on TX.
// busy=1 while sending; the CPU must wait for busy=0 before the next byte.
// ===================================================================
module uart_tx #(
    parameter CLK_HZ = 100_000_000,
    parameter BAUD   = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       start,        // 1-cycle pulse: start sending tx_data
    input  wire [7:0] tx_data,

    output wire       busy,
    output reg        TX            // external serial pin (idle = 1)
);
    localparam integer DIV = CLK_HZ / BAUD;          // ~868 @100MHz/115200
    localparam integer DW  = $clog2(DIV);

    localparam [1:0] S_IDLE = 2'd0, S_BIT = 2'd1;

    reg [1:0]        state;
    reg [DW-1:0]     baud_cnt;
    reg [3:0]        bit_idx;       // 0..9 (start,0..7,stop)
    reg [9:0]        shift;         // {stop=1, data[7:0], start=0}

    assign busy = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            baud_cnt <= {DW{1'b0}};
            bit_idx  <= 4'd0;
            shift    <= 10'b1111111111;
            TX       <= 1'b1;                        // idle = high
        end else begin
            case (state)
                S_IDLE: begin
                    TX <= 1'b1;
                    if (start) begin
                        shift    <= {1'b1, tx_data, 1'b0};  // stop,data,start
                        bit_idx  <= 4'd0;
                        baud_cnt <= {DW{1'b0}};
                        state    <= S_BIT;
                    end
                end
                S_BIT: begin
                    TX <= shift[0];
                    if (baud_cnt == DIV - 1) begin
                        baud_cnt <= {DW{1'b0}};
                        shift    <= {1'b1, shift[9:1]};
                        if (bit_idx == 4'd9) begin
                            state <= S_IDLE;
                        end else begin
                            bit_idx <= bit_idx + 4'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
