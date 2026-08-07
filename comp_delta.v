`timescale 1ns/1ps
module comp_delta #(
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
    localparam [1:0] S_IDLE = 2'd0,
                     S_LOAD = 2'd1,
                     S_EMIT = 2'd2,
                     S_FIN  = 2'd3;
    localparam [1:0] MODE_DELTA = 2'b10;
    localparam IW = $clog2(N);

    reg  [1:0]    state;
    reg  [31:0]   wbuf [0:N-1];
    reg  [IW:0]   li;
    reg  [IW+1:0] e;                      
    reg  [AW-1:0] src_base_r, dest_base_r;

    assign busy    = (state != S_IDLE);
    assign rd_addr = src_base_r + li;

    integer k;
    reg [31:0] diff [1:N-1];
    reg        fits;
    always @(*) begin
        fits = 1'b1;
        for (k = 1; k < N; k = k + 1) begin
            diff[k] = wbuf[k] - wbuf[k-1];

            if (!((&diff[k][31:7]) | (~|diff[k][31:7])))
                fits = 1'b0;
        end
    end

    wire [31:0] pw0 = { diff[4][7:0],  diff[3][7:0],  diff[2][7:0],  diff[1][7:0]  };
    wire [31:0] pw1 = { diff[8][7:0],  diff[7][7:0],  diff[6][7:0],  diff[5][7:0]  };
    wire [31:0] pw2 = { diff[12][7:0], diff[11][7:0], diff[10][7:0], diff[9][7:0]  };
    wire [31:0] pw3 = { 8'b0,          diff[15][7:0], diff[14][7:0], diff[13][7:0] };

    wire [31:0] header_packed = { {(32-2-16){1'b0}}, MODE_DELTA, 7'b0, 1'b1, 8'b0 };
    wire [31:0] header_raw    = { {(32-2-16){1'b0}}, MODE_DELTA, 16'b0 };

    wire [AW:0] emit_total = fits ? 7'd6 : 7'd17;

    always @(*) begin
        wr_en   = 1'b0;
        wr_addr = {AW{1'b0}};
        wr_data = 32'b0;
        if (state == S_EMIT) begin
            wr_en   = 1'b1;
            wr_addr = dest_base_r + e;
            if (fits) begin
                case (e)
                    0: wr_data = header_packed;
                    1: wr_data = wbuf[0];
                    2: wr_data = pw0;
                    3: wr_data = pw1;
                    4: wr_data = pw2;
                    default: wr_data = pw3;        
                endcase
            end else begin
                wr_data = (e == 0) ? header_raw : wbuf[e-1];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            li          <= {(IW+1){1'b0}};
            e           <= {(IW+2){1'b0}};
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
                        li          <= {(IW+1){1'b0}};
                        state       <= S_LOAD;
                    end
                end
                S_LOAD: begin
                    wbuf[li] <= rd_data;
                    if (li == N-1) begin
                        e     <= {(IW+2){1'b0}};
                        state <= S_EMIT;
                    end
                    li <= li + 1'b1;
                end
                S_EMIT: begin
                    if (e == emit_total - 1'b1)
                        state <= S_FIN;
                    e <= e + 1'b1;
                end
                S_FIN: begin
                    out_len <= emit_total;
                    done    <= 1'b1;
                    state   <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
