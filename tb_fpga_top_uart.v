`timescale 1ns/1ps
// ===================================================================
// tb_fpga_top_uart.v -- FULL simulation of fpga_top_uart: run 14 blocks of
// lieu that qua CPU that, giai ma chuoi UART TX thuc su (bit-by-bit,
// using the real 115200 baud @100MHz), then compare with the golden model (mode,out_len)
// precomputed for the 14 blocks in uart_demo_src.hex.
// ===================================================================
module tb_fpga_top_uart;
    localparam integer NUM_BLK = 14;
    localparam integer BAUD    = 115_200;
    localparam integer CLK_HZ  = 100_000_000;
    localparam integer DIV     = CLK_HZ / BAUD;     // ~868 cycles/bit
    localparam real    CLK_PERIOD_NS = 10.0;        // 100MHz

    reg clk = 0, rstn = 0;
    wire UART_TXD;
    wire [15:0] LED;
    wire [7:0]  AN;
    wire [6:0]  SEG;

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    fpga_top_uart_fastsim dut (
        .CLK100MHZ (clk),
        .CPU_RESETN(rstn),
        .UART_TXD  (UART_TXD),
        .LED(LED), .AN(AN), .SEG(SEG)
    );

    // ---- golden expected result (mode, out_len) for 14 blocks ----
    // Matches the table printed during data preparation.
    reg [1:0] exp_mode [0:NUM_BLK-1];
    reg [7:0] exp_len  [0:NUM_BLK-1];

    integer i;
    initial begin
        exp_mode[0]=0;  exp_len[0]=3;
        exp_mode[1]=0;  exp_len[1]=1;
        exp_mode[2]=0;  exp_len[2]=1;
        exp_mode[3]=0;  exp_len[3]=1;
        exp_mode[4]=1;  exp_len[4]=5;
        exp_mode[5]=1;  exp_len[5]=3;
        exp_mode[6]=1;  exp_len[6]=3;
        exp_mode[7]=1;  exp_len[7]=3;
        exp_mode[8]=2;  exp_len[8]=6;
        exp_mode[9]=2;  exp_len[9]=6;
        exp_mode[10]=2; exp_len[10]=6;
        exp_mode[11]=2; exp_len[11]=6;
        exp_mode[12]=3; exp_len[12]=16;
        exp_mode[13]=3; exp_len[13]=16;
    end

    // ---- bo giai ma UART TX (mo phong may thu UART that) ----
    reg [7:0] rx_bytes [0:2*NUM_BLK-1];
    integer   rx_count;
    integer   errors;

    task automatic uart_rx_byte(output [7:0] data);
        integer k;
        begin
            @(negedge UART_TXD);                 // start-bit edge
            #(DIV * CLK_PERIOD_NS / 2.0);         // vao giua start bit
            data = 8'h00;
            for (k = 0; k < 8; k = k + 1) begin
                #(DIV * CLK_PERIOD_NS);
                data[k] = UART_TXD;
            end
            #(DIV * CLK_PERIOD_NS);               // middle of the stop bit (value not checked)
        end
    endtask

    initial begin
        rx_count = 0;
        rstn = 0;
        repeat (5) @(posedge clk);
        rstn = 1;
        // collect all 2*NUM_BLK bytes (mode,len per block)
        while (rx_count < 2*NUM_BLK) begin
            uart_rx_byte(rx_bytes[rx_count]);
            $display("t=%0t  UART nhan byte #%0d = %0d (0x%02h)", $time, rx_count, rx_bytes[rx_count], rx_bytes[rx_count]);
            rx_count = rx_count + 1;
        end

        // ---- compare with golden ----
        errors = 0;
        $display("\n  == Compare UART received vs golden model ==");
        for (i = 0; i < NUM_BLK; i = i + 1) begin
            if (rx_bytes[2*i] !== exp_mode[i]) begin
                errors = errors + 1;
                $display("  [MODE FAIL] block %0d: got=%0d expected=%0d", i, rx_bytes[2*i], exp_mode[i]);
            end
            if (rx_bytes[2*i+1] !== exp_len[i]) begin
                errors = errors + 1;
                $display("  [LEN FAIL] block %0d: got=%0d expected=%0d", i, rx_bytes[2*i+1], exp_len[i]);
            end
        end

        $display("");
        if (errors == 0)
            $display("  [PASS] UART sent correct mode+out_len for all %0d REAL data blocks, matching golden model 100%%.", NUM_BLK);
        else
            $display("  [FAIL] %0d loi.", errors);
        $finish;
    end

    initial begin
        #600_000_000;   // 600 ms timeout (fastsim CNT_MAX=19999, du bien do lon)
        $display("  [TIMEOUT] only received %0d/%0d bytes", rx_count, 2*NUM_BLK);
        $finish;
    end
endmodule
