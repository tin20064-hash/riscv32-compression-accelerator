`timescale 1ns/1ps
// ===================================================================
// fpga_top_uart.v -- REAL-DATA DEMO + RESULTS SENT OVER UART
// -------------------------------------------------------------------
// A SEPARATE top-level for the "real hardware evidence" run (not shared
// with fpga_top.v of the LED/7-seg demo, does not affect the locked
// paper numbers). The CPU runs uart_demo.hex, processing 14 real data blocks
// (uart_demo_src.hex, trich tu real_light.hex, 4 ZERO+4 RLE+4 DELTA+2 RAW),
// each block writes 2 bytes (mode, out_len) to the "mailbox" at word 255 of
// the scratchpad -- external logic (not mem_stage.v) detects that write
// and triggers uart_tx to send the byte on the real UART pin, readable by a PC over
// the COM port (using the same USB cable used to program the board).
// ===================================================================
module fpga_top_uart (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    output wire         UART_TXD,     // noi ra chan UART TX vat ly (xem .xdc)
    output wire [15:0] LED,
    output wire [7:0]  AN,
    output wire [6:0]  SEG
);

    // ~10 CPU steps/s (like the LED demo). IMPORTANT: no logic
    // checks uart_busy before writing the 2nd byte (mode then len) -- the PROGRAM
    // RELIES on the assumption: 1 CPU step (here = 100ms) is always far longer than
    // the time to send 1 real UART byte (~86.8us @115200 baud) -> margin
    // ~1150x, absolutely safe. IF you drop CNT_MAX below ~90000
    // (~900us/step) you MUST add uart_busy polling, else bytes are lost.
    localparam CNT_MAX = 27'd9_999_999;

    reg [26:0] cnt_div;
    reg        cpu_clk_en;

    always @(posedge CLK100MHZ or negedge CPU_RESETN) begin
        if (!CPU_RESETN) begin
            cnt_div    <= 27'd0;
            cpu_clk_en <= 1'b0;
        end else begin
            if (cnt_div == CNT_MAX) begin
                cnt_div    <= 27'd0;
                cpu_clk_en <= 1'b1;
            end else begin
                cnt_div    <= cnt_div + 27'd1;
                cpu_clk_en <= 1'b0;
            end
        end
    end

    wire [31:0] debug_data;
    wire [31:0] accel_dbg;
    wire        spad_we_dbg;
    wire [7:0]  spad_waddr_dbg;
    wire [31:0] spad_wdata_dbg;

    cpu_top #(.PROGRAM_FILE("uart_demo.hex"), .SRC_FILE("uart_demo_src.hex")) u_cpu (
        .clk            (CLK100MHZ),
        .rst_n          (CPU_RESETN),
        .clk_en         (cpu_clk_en),
        .debug_data     (debug_data),
        .accel_dbg      (accel_dbg),
        .spad_we_dbg    (spad_we_dbg),
        .spad_waddr_dbg (spad_waddr_dbg),
        .spad_wdata_dbg (spad_wdata_dbg)
    );

    // UART "mailbox": catch the CPU writing word 255 of the scratchpad -> send 1 byte
    localparam [7:0] MAILBOX_WORD = 8'd255;

    wire mailbox_hit = spad_we_dbg && (spad_waddr_dbg == MAILBOX_WORD);

    // IMPORTANT: mailbox_hit can stay high for MANY consecutive 100MHz cycles
    // (since the pipeline only updates on the CPU's clk_en, ~10Hz -- the sw
    // instruction sits in the MEM register the whole time). If we trigger uart_start
    // directly from mailbox_hit it RESENDS the same byte many times. We must catch
    // the RISING EDGE to guarantee exactly 1 pulse per real write.
    wire       uart_busy;
    reg        mailbox_hit_d;
    reg        uart_start_r;
    reg [7:0]  uart_data_r;

    always @(posedge CLK100MHZ or negedge CPU_RESETN) begin
        if (!CPU_RESETN) begin
            mailbox_hit_d <= 1'b0;
            uart_start_r  <= 1'b0;
            uart_data_r   <= 8'd0;
        end else begin
            mailbox_hit_d <= mailbox_hit;
            uart_start_r  <= mailbox_hit & ~mailbox_hit_d;   // exactly-1-cycle pulse
            if (mailbox_hit & ~mailbox_hit_d) uart_data_r <= spad_wdata_dbg[7:0];
        end
    end

    uart_tx #(.CLK_HZ(100_000_000), .BAUD(115_200)) u_uart (
        .clk     (CLK100MHZ),
        .rst_n   (CPU_RESETN),
        .start   (uart_start_r),
        .tx_data (uart_data_r),
        .busy    (uart_busy),
        .TX      (UART_TXD)
    );

    // ---- LED: count bytes sent (to confirm the demo is running even when
    //      the UART terminal isn't open) + keep 7-seg showing debug_data ----
    reg [15:0] byte_cnt;
    always @(posedge CLK100MHZ or negedge CPU_RESETN) begin
        if (!CPU_RESETN) byte_cnt <= 16'd0;
        else if (mailbox_hit) byte_cnt <= byte_cnt + 16'd1;
    end
    assign LED = byte_cnt;

    reg [16:0] cnt_refresh;
    always @(posedge CLK100MHZ or negedge CPU_RESETN) begin
        if (!CPU_RESETN) cnt_refresh <= 17'd0;
        else             cnt_refresh <= cnt_refresh + 17'd1;
    end
    wire [2:0] digit_sel = cnt_refresh[16:14];

    reg [3:0] hex_digit;
    reg [7:0] an_reg;
    always @(*) begin
        case (digit_sel)
            3'd0: begin an_reg = 8'b1111_1110; hex_digit = debug_data[3:0];   end
            3'd1: begin an_reg = 8'b1111_1101; hex_digit = debug_data[7:4];   end
            3'd2: begin an_reg = 8'b1111_1011; hex_digit = debug_data[11:8];  end
            3'd3: begin an_reg = 8'b1111_0111; hex_digit = debug_data[15:12]; end
            3'd4: begin an_reg = 8'b1110_1111; hex_digit = debug_data[19:16]; end
            3'd5: begin an_reg = 8'b1101_1111; hex_digit = debug_data[23:20]; end
            3'd6: begin an_reg = 8'b1011_1111; hex_digit = debug_data[27:24]; end
            3'd7: begin an_reg = 8'b0111_1111; hex_digit = debug_data[31:28]; end
            default: begin an_reg = 8'b1111_1111; hex_digit = 4'b0000; end
        endcase
    end
    assign AN = an_reg;

    reg [6:0] seg_reg;
    always @(*) begin
        case (hex_digit)
            4'h0: seg_reg = 7'b100_0000;
            4'h1: seg_reg = 7'b111_1001;
            4'h2: seg_reg = 7'b010_0100;
            4'h3: seg_reg = 7'b011_0000;
            4'h4: seg_reg = 7'b001_1001;
            4'h5: seg_reg = 7'b001_0010;
            4'h6: seg_reg = 7'b000_0010;
            4'h7: seg_reg = 7'b111_1000;
            4'h8: seg_reg = 7'b000_0000;
            4'h9: seg_reg = 7'b001_0000;
            4'hA: seg_reg = 7'b000_1000;
            4'hB: seg_reg = 7'b000_0011;
            4'hC: seg_reg = 7'b100_0110;
            4'hD: seg_reg = 7'b010_0001;
            4'hE: seg_reg = 7'b000_0110;
            4'hF: seg_reg = 7'b000_1110;
            default: seg_reg = 7'b111_1111;
        endcase
    end
    assign SEG = seg_reg;

endmodule
