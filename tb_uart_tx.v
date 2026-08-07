`timescale 1ns/1ps
// ===================================================================
// tb_uart_tx.v -- check uart_tx.v: send 4 bytes, re-decode TX,
// compare with written values -> PASS/FAIL. Use a fast baud (small CLK_HZ) to
// simulate fast, no effect on logic (only the divider ratio).
// ===================================================================
module tb_uart_tx;
    localparam CLK_HZ = 10000;
    localparam BAUD   = 1000;          // DIV = 10, fast for simulation
    localparam integer DIV = CLK_HZ / BAUD;

    reg clk = 0, rst_n = 0;
    reg start;
    reg [7:0] tx_data;
    wire busy, TX;

    always #50 clk = ~clk;             // 100ns period ~ 10kHz (ratio only, needn't be real)

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .tx_data(tx_data),
        .busy(busy), .TX(TX)
    );

    // ---- bo giai ma TX (mo phong may thu UART ben ngoai) ----
    reg [7:0] rx_byte;
    reg       rx_valid;
    integer   errors = 0;

    task automatic rx_capture(input [7:0] expected);
        integer i;
        begin
            rx_valid = 0;
            @(negedge TX);                       // start-bit edge
            #(DIV*100/2);                        // vao giua bit start
            if (TX !== 1'b0) begin
                $display("  [FAIL] start bit not at expected position");
                errors = errors + 1;
            end
            rx_byte = 0;
            for (i = 0; i < 8; i = i + 1) begin
                #(DIV*100);                      // move to the middle of the next data bit
                rx_byte[i] = TX;
            end
            #(DIV*100);                          // sang giua stop bit
            if (TX !== 1'b1) begin
                $display("  [FAIL] stop bit sai");
                errors = errors + 1;
            end
            if (rx_byte !== expected) begin
                $display("  [FAIL] byte got=%02h  expected=%02h", rx_byte, expected);
                errors = errors + 1;
            end else begin
                $display("  [OK] received correct byte 0x%02h", rx_byte);
            end
        end
    endtask

    initial begin
        start = 0; tx_data = 8'h00;
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // send 4 bytes in turn, check each
        // (use #1 after each posedge to avoid a blocking-assignment race with the DUT)
        fork
            begin
                @(posedge clk); #1; start = 1; tx_data = 8'hA5;
                @(posedge clk); #1; start = 0;
                wait (!busy); repeat(3) @(posedge clk);
                @(posedge clk); #1; start = 1; tx_data = 8'h00;
                @(posedge clk); #1; start = 0;
                wait (!busy); repeat(3) @(posedge clk);
                @(posedge clk); #1; start = 1; tx_data = 8'hFF;
                @(posedge clk); #1; start = 0;
                wait (!busy); repeat(3) @(posedge clk);
                @(posedge clk); #1; start = 1; tx_data = 8'h42;
                @(posedge clk); #1; start = 0;
            end
            begin
                rx_capture(8'hA5);
                rx_capture(8'h00);
                rx_capture(8'hFF);
                rx_capture(8'h42);
            end
        join

        $display("");
        if (errors == 0) $display("  [PASS] uart_tx sent 4/4 bytes correctly (start/data/stop in proper 8N1 format).");
        else             $display("  [FAIL] %0d loi.", errors);
        $finish;
    end

    initial begin #2_000_000; $display("  [TIMEOUT]"); $finish; end
endmodule
