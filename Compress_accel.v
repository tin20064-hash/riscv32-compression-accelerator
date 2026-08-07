`timescale 1ns/1ps
module compress_accel #(
    parameter AW       = 8,
    parameter N        = 16,
    parameter PDETECT  = 3'b000,
    parameter CCOMPR   = 3'b001,
    parameter CSTAT    = 3'b010
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clk_en,

    input  wire        custom_en,
    input  wire [2:0]  custom_op,

    input  wire [31:0] op_a,
    input  wire [31:0] op_b,

    output wire [AW-1:0] spad_raddr,
    input  wire [31:0]   spad_rdata,

    output wire          spad_we,
    output wire [AW-1:0] spad_waddr,
    output wire [31:0]   spad_wdata,

    output wire [31:0] result,
    output wire        busy,
    output wire        done,

    output wire [31:0] dbg
);

    wire ccompr_cmd  = custom_en & (custom_op == CCOMPR);
    wire pdetect_cmd = custom_en & (custom_op == PDETECT);
    wire cstat_cmd   = custom_en & (custom_op == CSTAT);

    localparam S_IDLE = 1'b0,
               S_RUN  = 1'b1;

    reg         state;
    reg         detect_active;      
    reg  [1:0]  amode;              
    reg  [27:0] last_result;        
    reg         last_op;            
    reg         done_r;
    reg         err_r;

    wire [AW-1:0] src_word  = op_a[AW+1:2];
    wire [AW-1:0] dest_word = op_b[AW+1:2];
    wire [1:0]    req_mode  = op_b[1:0];

    // PDETECT uses EXACT-COST select (no threshold) -> op_b reserved.

    wire start_c = (state == S_IDLE) & ccompr_cmd  & clk_en & (req_mode != 2'b11);
    wire start_z = start_c & (req_mode == 2'b00);
    wire start_r = start_c & (req_mode == 2'b01);
    wire start_d = start_c & (req_mode == 2'b10);
    wire start_p = (state == S_IDLE) & pdetect_cmd & clk_en;

    wire [AW-1:0] z_rd, r_rd, d_rd;
    wire          z_we, r_we, d_we;
    wire [AW-1:0] z_wa, r_wa, d_wa;
    wire [31:0]   z_wd, r_wd, d_wd;
    wire          z_done, r_done, d_done;
    wire [AW:0]   z_len, r_len, d_len;

    comp_zero #(.AW(AW), .N(N)) u_zero (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .start(start_z), .src_base(src_word), .dest_base(dest_word),
        .rd_addr(z_rd), .rd_data(spad_rdata),
        .wr_en(z_we), .wr_addr(z_wa), .wr_data(z_wd),
        .busy(), .done(z_done), .out_len(z_len)
    );

    comp_rle #(.AW(AW), .N(N)) u_rle (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .start(start_r), .src_base(src_word), .dest_base(dest_word),
        .rd_addr(r_rd), .rd_data(spad_rdata),
        .wr_en(r_we), .wr_addr(r_wa), .wr_data(r_wd),
        .busy(), .done(r_done), .out_len(r_len)
    );

    comp_delta #(.AW(AW), .N(N)) u_delta (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .start(start_d), .src_base(src_word), .dest_base(dest_word),
        .rd_addr(d_rd), .rd_data(spad_rdata),
        .wr_en(d_we), .wr_addr(d_wa), .wr_data(d_wd),
        .busy(), .done(d_done), .out_len(d_len)
    );

    wire [AW-1:0] p_rd;
    wire          p_done;
    wire [1:0]    p_mode;
    wire [31:0]   p_detword;

    pattern_detect #(.AW(AW), .N(N)) u_detect (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .start(start_p), .src_base(src_word),
        .rd_addr(p_rd), .rd_data(spad_rdata),
        .busy(), .done(p_done), .mode(p_mode), .det_word(p_detword)
    );

    assign spad_raddr = detect_active   ? p_rd :
                        (amode == 2'b00) ? z_rd :
                        (amode == 2'b01) ? r_rd :
                                           d_rd;

    assign spad_we    = z_we | r_we | d_we;
    assign spad_waddr = z_we ? z_wa : r_we ? r_wa : d_wa;
    assign spad_wdata = z_we ? z_wd : r_we ? r_wd : d_wd;

    wire        comp_done = z_done | r_done | d_done;
    wire [AW:0] comp_len  = z_done ? z_len : r_done ? r_len : d_done ? d_len : {(AW+1){1'b0}};

    assign busy = (state == S_RUN);
    assign done = done_r;

    wire [31:0] status_word = { busy, done_r, err_r, last_op, last_result };

    // dbg[29] = busy, added so fpga_top can count real cycles (7-seg display)
    assign dbg = { done_r, last_op, busy, 11'b0, amode, 7'b0, last_result[8:0] };

    assign result = cstat_cmd   ? status_word          :
                    pdetect_cmd ? {10'b0, p_detword[21:0]} : 
                    ccompr_cmd  ? {19'b0, comp_len}        :
                                  32'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            detect_active <= 1'b0;
            amode         <= 2'b00;
            last_result   <= 28'd0;
            last_op       <= 1'b0;
            done_r        <= 1'b0;
            err_r         <= 1'b0;
        end else if (clk_en) begin
            case (state)
                S_IDLE: begin
                    if (ccompr_cmd) begin
                        done_r <= 1'b0;
                        if (req_mode == 2'b11) begin
                            err_r <= 1'b1;                  
                        end else begin
                            amode         <= req_mode;
                            detect_active <= 1'b0;
                            err_r         <= 1'b0;
                            state         <= S_RUN;
                        end
                    end else if (pdetect_cmd) begin
                        detect_active <= 1'b1;
                        done_r        <= 1'b0;
                        err_r         <= 1'b0;
                        state         <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (detect_active) begin
                        if (p_done) begin
                            last_result <= {6'b0, p_detword[21:0]};
                            last_op     <= 1'b1;
                            done_r      <= 1'b1;
                            state       <= S_IDLE;
                        end
                    end else begin
                        if (comp_done) begin
                            last_result <= {{(28-(AW+1)){1'b0}}, comp_len};
                            last_op     <= 1'b0;
                            done_r      <= 1'b1;
                            state       <= S_IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule
