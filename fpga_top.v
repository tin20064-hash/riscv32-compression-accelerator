`timescale 1ns/1ps

module fpga_top (
    input  wire        CLK100MHZ,  
    input  wire        CPU_RESETN, 
    output wire [15:0] LED,        
    output wire [7:0]  AN,         
    output wire [6:0]  SEG         
);

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

    wire [31:0] cpu_display_data;
    wire [31:0] accel_dbg;

    cpu_top u_cpu (
        .clk        (CLK100MHZ),
        .rst_n      (CPU_RESETN),
        .clk_en     (cpu_clk_en),
        .debug_data (cpu_display_data),
        .accel_dbg  (accel_dbg)
    );

    wire        a_done   = accel_dbg[31];
    wire        a_lastop = accel_dbg[30];
    wire        a_busy   = accel_dbg[29];
    wire [1:0]  a_mode   = accel_dbg[17:16];
    wire [8:0]  a_len    = accel_dbg[8:0];

    reg        a_done_d;
    reg [1:0]  mode_lat;
    reg [8:0]  len_lat;

    always @(posedge CLK100MHZ or negedge CPU_RESETN) begin
        if (!CPU_RESETN) begin
            a_done_d <= 1'b0;
            mode_lat <= 2'b00;
            len_lat  <= 9'd0;
        end else begin
            a_done_d <= a_done;
            if (a_done & ~a_done_d & ~a_lastop) begin
                mode_lat <= a_mode;
                len_lat  <= a_len;
            end
        end
    end

    // Real cycle counter of the most recent COMPRESS operation (detect excluded):
    // count clk_en=1 pulses while a_busy=1, latch into cyc_lat when busy 1->0.
    reg        a_busy_d;
    reg [7:0]  cyc_cnt;
    reg [7:0]  cyc_lat;

    always @(posedge CLK100MHZ or negedge CPU_RESETN) begin
        if (!CPU_RESETN) begin
            a_busy_d <= 1'b0;
            cyc_cnt  <= 8'd0;
            cyc_lat  <= 8'd0;
        end else begin
            a_busy_d <= a_busy;
            if (a_busy & ~a_busy_d) begin
                cyc_cnt <= 8'd0;                 // a new operation just started
            end else if (a_busy & cpu_clk_en) begin
                cyc_cnt <= cyc_cnt + 8'd1;        // count 1 clk_en step while busy
            end
            if (~a_busy & a_busy_d & ~a_lastop) begin
                cyc_lat <= cyc_cnt;                // latch: a COMPRESS just finished
            end
        end
    end

    assign LED[15]   = (mode_lat == 2'b00);
    assign LED[14]   = (mode_lat == 2'b01);
    assign LED[13]   = (mode_lat == 2'b10);
    assign LED[12]   = 1'b0;
    assign LED[11:9] = 3'b000;
    assign LED[8:0]  = len_lat;

    // 7-segment layout (left to right, digit7..digit0):
    //   digit7      = mode (0=ZERO,1=RLE,2=DELTA)
    //   digit6,5    = 0 (blank)
    //   digit4,3    = real cycle count of the compress just finished (cyc_lat, hex)
    //   digit2      = 0 (blank)
    //   digit1,0    = out_len (hex)
    wire [31:0] disp_data = { 2'b00, mode_lat, 8'b0, cyc_lat, 4'b0, len_lat[7:0] };

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
            3'd0: begin an_reg = 8'b1111_1110; hex_digit = disp_data[3:0];   end
            3'd1: begin an_reg = 8'b1111_1101; hex_digit = disp_data[7:4];   end
            3'd2: begin an_reg = 8'b1111_1011; hex_digit = disp_data[11:8];  end
            3'd3: begin an_reg = 8'b1111_0111; hex_digit = disp_data[15:12]; end
            3'd4: begin an_reg = 8'b1110_1111; hex_digit = disp_data[19:16]; end
            3'd5: begin an_reg = 8'b1101_1111; hex_digit = disp_data[23:20]; end
            3'd6: begin an_reg = 8'b1011_1111; hex_digit = disp_data[27:24]; end
            3'd7: begin an_reg = 8'b0111_1111; hex_digit = disp_data[31:28]; end
            default: begin an_reg = 8'b1111_1111; hex_digit = 4'b0000; end
        endcase
    end

    assign AN = an_reg;

    reg [6:0] seg_reg;

    always @(*) begin
        case (hex_digit)
            4'h0: seg_reg = 7'b100_0000; // 0
            4'h1: seg_reg = 7'b111_1001; // 1
            4'h2: seg_reg = 7'b010_0100; // 2
            4'h3: seg_reg = 7'b011_0000; // 3
            4'h4: seg_reg = 7'b001_1001; // 4
            4'h5: seg_reg = 7'b001_0010; // 5
            4'h6: seg_reg = 7'b000_0010; // 6
            4'h7: seg_reg = 7'b111_1000; // 7
            4'h8: seg_reg = 7'b000_0000; // 8
            4'h9: seg_reg = 7'b001_0000; // 9
            4'hA: seg_reg = 7'b000_1000; // A
            4'hB: seg_reg = 7'b000_0011; // b
            4'hC: seg_reg = 7'b100_0110; // C
            4'hD: seg_reg = 7'b010_0001; // d
            4'hE: seg_reg = 7'b000_0110; // E
            4'hF: seg_reg = 7'b000_1110; // F
            default: seg_reg = 7'b111_1111; 
        endcase
    end

    assign SEG = seg_reg;

endmodule