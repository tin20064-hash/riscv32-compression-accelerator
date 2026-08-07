`timescale 1ns/1ps
module pattern_detect #(
    parameter AW = 13,
    parameter N  = 16
)(
    input  wire           clk,
    input  wire           rst_n,
    input  wire           clk_en,      // gate: step in lockstep with dispatcher/CPU

    input  wire           start,
    input  wire [AW-1:0]  src_base,

    output wire [AW-1:0]  rd_addr,
    input  wire [31:0]    rd_data,

    output wire           busy,
    output reg            done,
    output reg  [1:0]     mode,
    output reg  [31:0]    det_word
);
    localparam [1:0] S_IDLE = 2'd0,
                     S_LOAD = 2'd1,
                     S_DONE = 2'd2;
    localparam [1:0] MODE_ZERO=2'b00, MODE_RLE=2'b01, MODE_DELTA=2'b10, MODE_RAW=2'b11;
    localparam IW = $clog2(N);

    reg  [1:0]    state;
    reg  [IW:0]   li;
    reg  [AW-1:0] src_base_r;

    reg  [31:0]   prev;
    reg  [5:0]    zero_acc, run_acc, delta_acc;

    assign busy    = (state != S_IDLE);
    assign rd_addr = src_base_r + li;  

    function [5:0] sbits;
        input [31:0] v;
        integer i;
        reg [5:0] w;
        begin
            w = 6'd1;                      
            for (i = 0; i < 31; i = i + 1)
                if (v[i] != v[31]) w = i + 2; 
            sbits = w;
        end
    endfunction

    wire [31:0] dcur   = rd_data - prev;     
    wire [5:0]  dw_cur = sbits(dcur);        
    wire        eq_cur = (rd_data == prev);  

    // ---- EXACT-COST mode select (replaces priority-threshold) ----
    // The three accumulated indices give the EXACT output length of each
    // mode (unit: words):
    //   L_ZERO  = 1 + (N - zero_acc)     header + non-zero words
    //   L_RLE   = 1 + 2*(N - run_acc)    header + (val,cnt) per run
    //   L_DELTA = 6 if delta_w<=8 (8-bit packed), else 17 (raw)
    //   L_RAW   = N
    // Pick the minimum; tie-break ZERO < RLE < DELTA < RAW (matches golden model).
    // No tau threshold anymore -> no parameter calibration needed.
    wire [5:0] len_zero  = (N + 6'd1) - zero_acc;
    wire [5:0] len_rle   = (2*N + 6'd1) - {run_acc[4:0], 1'b0};
    wire [5:0] len_delta = (delta_acc <= 6'd8) ? 6'd6 : 6'd17;
    wire [5:0] len_raw   = N[5:0];

    reg [1:0] mode_sel;
    always @(*) begin
        if ((len_zero <= len_rle) && (len_zero <= len_delta) && (len_zero <= len_raw))
            mode_sel = MODE_ZERO;
        else if ((len_rle <= len_delta) && (len_rle <= len_raw))
            mode_sel = MODE_RLE;
        else if (len_delta <= len_raw)
            mode_sel = MODE_DELTA;
        else
            mode_sel = MODE_RAW;
    end
    wire [31:0] det_pack = { 10'b0, delta_acc, 2'b0, run_acc, zero_acc, mode_sel };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            li         <= {(IW+1){1'b0}};
            src_base_r <= {AW{1'b0}};
            prev       <= 32'b0;
            zero_acc   <= 6'd0;
            run_acc    <= 6'd0;
            delta_acc  <= 6'd0;
            done       <= 1'b0;
            mode       <= 2'b00;
            det_word   <= 32'b0;
        end else if (clk_en) begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        src_base_r <= src_base;
                        li         <= {(IW+1){1'b0}};
                        zero_acc   <= 6'd0;   
                        run_acc    <= 6'd0;
                        delta_acc  <= 6'd0;
                        state      <= S_LOAD;
                    end
                end
                S_LOAD: begin
                    if (rd_data == 32'b0)
                        zero_acc <= zero_acc + 6'd1;
                    if (li != {(IW+1){1'b0}}) begin
                        if (eq_cur)              run_acc   <= run_acc + 6'd1;
                        if (dw_cur > delta_acc)  delta_acc <= dw_cur;
                    end
                    prev <= rd_data;           
                    if (li == N-1)
                        state <= S_DONE;
                    li <= li + 1'b1;
                end
                S_DONE: begin
                    mode     <= mode_sel;     
                    det_word <= det_pack;
                    done     <= 1'b1;
                    state    <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
