`timescale 1ns/1ps
module comp_rle #(
    parameter AW = 13,
    parameter N  = 16
)(
    input  wire           clk,
    input  wire           rst_n,
    input  wire           clk_en,      // gate: step in lockstep with dispatcher/CPU

    input  wire           start,
    input  wire [AW-1:0]  src_base,
    input  wire [AW-1:0]  dest_base,

    output wire [AW-1:0]  rd_addr,
    input  wire [31:0]    rd_data,

    output reg            wr_en,
    output reg  [AW-1:0]  wr_addr,
    output reg  [31:0]    wr_data,

    output wire           busy,
    output reg            done,
    output reg  [AW:0]    out_len
);
    localparam [2:0] S_IDLE   = 3'd0,
                     S_LOAD   = 3'd1,
                     S_SCAN   = 3'd2,
                     S_WVAL   = 3'd3,
                     S_WCNT   = 3'd4,
                     S_HEADER = 3'd5;
    localparam [1:0] MODE_RLE = 2'b01;
    localparam IW = $clog2(N);         

    reg  [2:0]    state;
    reg  [31:0]   wbuf [0:N-1];
    reg  [IW:0]   li;                  
    reg  [IW:0]   scan_idx;            
    reg  [31:0]   run_val, run_cnt;
    reg  [15:0]   num_runs;
    reg  [AW-1:0] wptr;
    reg  [AW-1:0] src_base_r, dest_base_r;
    reg           last;                  

    assign busy    = (state != S_IDLE);
    assign rd_addr = src_base_r + li;    

    always @(*) begin
        wr_en   = 1'b0;
        wr_addr = {AW{1'b0}};
        wr_data = 32'b0;
        case (state)
            S_WVAL: begin
                wr_en   = 1'b1;
                wr_addr = wptr;
                wr_data = run_val;
            end
            S_WCNT: begin
                wr_en   = 1'b1;
                wr_addr = wptr;
                wr_data = run_cnt;
            end
            S_HEADER: begin
                wr_en   = 1'b1;
                wr_addr = dest_base_r;
                wr_data = { {(32-2-16){1'b0}}, MODE_RLE, num_runs };
            end
            default: ;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            li          <= {(IW+1){1'b0}};
            scan_idx    <= {(IW+1){1'b0}};
            run_val     <= 32'b0;
            run_cnt     <= 32'b0;
            num_runs    <= 16'b0;
            wptr        <= {AW{1'b0}};
            src_base_r  <= {AW{1'b0}};
            dest_base_r <= {AW{1'b0}};
            last        <= 1'b0;
            done        <= 1'b0;
            out_len     <= {(AW+1){1'b0}};
        end else if (clk_en) begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        src_base_r  <= src_base;
                        dest_base_r <= dest_base;
                        li          <= {(IW+1){1'b0}};
                        state       <= S_LOAD;
                    end
                end
                S_LOAD: begin
                    wbuf[li] <= rd_data;              
                    if (li == N-1) begin
                        run_val  <= wbuf[0];         
                        run_cnt  <= 32'd1;
                        scan_idx <= {{(IW){1'b0}}, 1'b1};   
                        num_runs <= 16'd0;
                        wptr     <= dest_base_r + 1'b1;     
                        state    <= S_SCAN;
                    end
                    li <= li + 1'b1;
                end
                S_SCAN: begin
                    if (scan_idx == N) begin
                        last  <= 1'b1;
                        state <= S_WVAL;           
                    end else if (wbuf[scan_idx[IW-1:0]] == run_val) begin
                        run_cnt  <= run_cnt + 1'b1;
                        scan_idx <= scan_idx + 1'b1;
                    end else begin
                        last  <= 1'b0;
                        state <= S_WVAL;            
                    end
                end
                S_WVAL: begin
                    wptr  <= wptr + 1'b1;           
                    state <= S_WCNT;
                end
                S_WCNT: begin
                    wptr     <= wptr + 1'b1;        
                    num_runs <= num_runs + 1'b1;
                    if (last) begin
                        state <= S_HEADER;
                    end else begin
                        run_val  <= wbuf[scan_idx[IW-1:0]];  
                        run_cnt  <= 32'd1;
                        scan_idx <= scan_idx + 1'b1;
                        state    <= S_SCAN;
                    end
                end
                S_HEADER: begin
                    out_len <= wptr - dest_base_r;   
                    done    <= 1'b1;
                    state   <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
