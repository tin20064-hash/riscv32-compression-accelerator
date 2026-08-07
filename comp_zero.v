`timescale 1ns/1ps

module comp_zero #(
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
    localparam [1:0] S_IDLE   = 2'd0,
                     S_STREAM = 2'd1,
                     S_HEADER = 2'd2;
    localparam [1:0] MODE_ZERO = 2'b00;
    localparam IW = $clog2(N);         

    reg [1:0]      state;
    reg [AW-1:0]   src_base_r, dest_base_r;
    reg [IW:0]     idx;                
    reg [AW-1:0]   wptr;               
    reg [N-1:0]    bitmap;

    assign busy    = (state != S_IDLE);
    assign rd_addr = src_base_r + idx;           

    wire cur_nonzero = (rd_data != 32'b0);

    always @(*) begin
        wr_en   = 1'b0;
        wr_addr = {AW{1'b0}};
        wr_data = 32'b0;
        case (state)
            S_STREAM: begin
                wr_en   = cur_nonzero;     
                wr_addr = wptr;
                wr_data = rd_data;
            end
            S_HEADER: begin
                wr_en   = 1'b1;
                wr_addr = dest_base_r;
                wr_data = { {(32-2-N){1'b0}}, MODE_ZERO, bitmap };
            end
            default: ;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            idx         <= {(IW+1){1'b0}};
            wptr        <= {AW{1'b0}};
            bitmap      <= {N{1'b0}};
            src_base_r  <= {AW{1'b0}};
            dest_base_r <= {AW{1'b0}};
            done        <= 1'b0;
            out_len     <= {(AW+1){1'b0}};
        end else if (clk_en) begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        src_base_r  <= src_base;
                        dest_base_r <= dest_base;
                        idx         <= {(IW+1){1'b0}};
                        wptr        <= dest_base + 1'b1;   
                        bitmap      <= {N{1'b0}};
                        state       <= S_STREAM;
                    end
                end
                S_STREAM: begin
                    if (cur_nonzero) begin
                        wptr           <= wptr + 1'b1;
                        bitmap[idx[IW-1:0]] <= 1'b1;
                    end
                    idx <= idx + 1'b1;
                    if (idx == N-1)
                        state <= S_HEADER;
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
