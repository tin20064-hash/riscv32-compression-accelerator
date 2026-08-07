`timescale 1ns/1ps

module cpu_top #(
    parameter PROGRAM_FILE = "mem_program.hex",  // mac dinh giu nguyen tuong thich nguoc
    parameter SRC_FILE     = "demo_src.hex"      // mac dinh giu nguyen tuong thich nguoc
) (
    input  wire clk,
    input  wire rst_n,
    input  wire clk_en,
    output wire [31:0] debug_data,
    output wire [31:0] accel_dbg,

    // Pure tap (no new logic) on the CPU's scratchpad write bus, used by the
    // UART demo peripheral (fpga_top_uart.v) to detect a `sw` to the "mailbox"
    // address without touching mem_stage.v/scratchpad.v at all.
    output wire        spad_we_dbg,
    output wire [7:0]  spad_waddr_dbg,
    output wire [31:0] spad_wdata_dbg
);

wire [31:0] pc_if;
wire [31:0] pc_plus4_if;
wire [31:0] instr_if;

wire [31:0] pc_id;
wire [31:0] pc_plus4_id;
wire [31:0] instr_id;
wire [31:0] rs1_data_id;
wire [31:0] rs2_data_id;
wire [31:0] imm_id;
wire        reg_write_id;
wire        alu_src_id;
wire [3:0]  alu_ctrl_id;
wire        mem_read_id;
wire        mem_write_id;
wire        mem_to_reg_id;
wire        branch_id;
wire        jump_id;
wire [4:0]  rs1_addr_id;
wire [4:0]  rs2_addr_id;
wire [4:0]  rd_addr_id;

wire [2:0]  funct3_id = instr_id[14:12];
wire        alu_opA_sel_id;
wire        jalr_sel_id;
wire        custom_en_id;       
wire [2:0]  custom_op_id;       

wire [31:0] pc_ex;
wire [31:0] pc_plus4_ex;
wire [31:0] rs1_data_ex;
wire [31:0] rs2_data_ex;
wire [31:0] imm_ex;
wire        reg_write_ex;
wire        alu_src_ex;
wire [3:0]  alu_ctrl_ex;
wire        mem_read_ex;
wire        mem_write_ex;
wire        mem_to_reg_ex;
wire        branch_ex;
wire        jump_ex;
wire [4:0]  rs1_addr_ex;
wire [4:0]  rs2_addr_ex;
wire [4:0]  rd_addr_ex;

wire [2:0]  funct3_ex;
wire        alu_opA_sel_ex;
wire        jalr_sel_ex;
wire        custom_en_ex;       
wire [2:0]  custom_op_ex;       

wire [31:0] alu_result_ex;
wire        zero_ex;
wire        pc_src_ex;
wire [31:0] branch_target_ex;
wire [31:0] alu_in1_ex;
wire [31:0] alu_in2_ex;
wire [31:0] fwd_rs1_ex;
wire [31:0] fwd_rs2_ex;

wire [31:0] custom_result_ex;
wire        custom_busy_ex;
wire        custom_done_ex;
wire [31:0] ex_writeback_result;

wire        spad_we;
wire [7:0]  spad_waddr;
wire [31:0] spad_wdata;
wire [3:0]  spad_wstrb;
wire [7:0]  spad_raddr;
wire [31:0] spad_rdata;

wire        accel_spad_we;
wire [7:0]  accel_spad_waddr;
wire [31:0] accel_spad_wdata;

wire [31:0] alu_result_mem;
wire [31:0] rs2_data_mem;
wire [31:0] pc_plus4_mem;
wire        reg_write_mem;
wire        mem_read_mem;
wire        mem_write_mem;
wire        mem_to_reg_mem;
wire        jump_mem;
wire [4:0]  rd_addr_mem;
wire [31:0] read_data_mem;

wire [2:0]  funct3_mem;

wire [31:0] alu_result_wb;
wire [31:0] read_data_wb;
wire [31:0] pc_plus4_wb;
wire        reg_write_wb;
wire        mem_to_reg_wb;
wire        jump_wb;
wire [4:0]  rd_addr_wb;
wire [31:0] write_data_wb;

wire        stall_if;
wire        stall_id;
wire        flush_if;
wire        flush_id;
wire        flush_ex;
wire [1:0]  fwd_a;
wire [1:0]  fwd_b;

wire [31:0] next_pc;

assign next_pc = (pc_src_ex) ? branch_target_ex :
                 (jump_ex)   ? branch_target_ex :
                               pc_plus4_if;

if_stage #(.PROGRAM_FILE(PROGRAM_FILE)) u_if_stage (
    .clk_en	  (clk_en),
    .clk          (clk),
    .rst_n        (rst_n),
    .stall        (stall_if),
    .next_pc      (next_pc),
    .pc_out       (pc_if),
    .pc_plus4     (pc_plus4_if),
    .instruction  (instr_if)
);

if_id_reg u_if_id_reg (
    .clk          (clk),
    .clk_en	  (clk_en),
    .rst_n        (rst_n),
    .stall        (stall_id),
    .flush        (flush_if),
    .pc_in        (pc_if),
    .pc_plus4_in  (pc_plus4_if),
    .instr_in     (instr_if),
    .pc_out       (pc_id),
    .pc_plus4_out (pc_plus4_id),
    .instr_out    (instr_id)
);

id_stage u_id_stage (
    .clk          (clk),
    .rst_n        (rst_n),
    .instr        (instr_id),
    .reg_write_wb (reg_write_wb),
    .rd_addr_wb   (rd_addr_wb),
    .write_data   (write_data_wb),
    .rs1_data     (rs1_data_id),
    .rs2_data     (rs2_data_id),
    .imm          (imm_id),
    .reg_write    (reg_write_id),
    .alu_src      (alu_src_id),
    .alu_ctrl     (alu_ctrl_id),
    .mem_read     (mem_read_id),
    .mem_write    (mem_write_id),
    .mem_to_reg   (mem_to_reg_id),
    .branch       (branch_id),
    .jump         (jump_id),
    .alu_opA_sel  (alu_opA_sel_id), 
    .jalr_sel     (jalr_sel_id),    
    .custom_en    (custom_en_id),   
    .custom_op    (custom_op_id),  
    .rs1_addr     (rs1_addr_id),
    .rs2_addr     (rs2_addr_id),
    .rd_addr      (rd_addr_id)
);

id_ex_reg u_id_ex_reg (
    .clk             (clk),
    .clk_en	     (clk_en),
    .rst_n           (rst_n),
    .flush           (flush_id),
    .pc_in           (pc_id),
    .pc_plus4_in     (pc_plus4_id),
    .rs1_data_in     (rs1_data_id),
    .rs2_data_in     (rs2_data_id),
    .imm_in          (imm_id),
    .reg_write_in    (reg_write_id),
    .alu_src_in      (alu_src_id),
    .alu_ctrl_in     (alu_ctrl_id),
    .mem_read_in     (mem_read_id),
    .mem_write_in    (mem_write_id),
    .mem_to_reg_in   (mem_to_reg_id),
    .branch_in       (branch_id),
    .jump_in         (jump_id),
    .alu_opA_sel_in  (alu_opA_sel_id),
    .jalr_sel_in     (jalr_sel_id),
    .custom_en_in    (custom_en_id),   
    .custom_op_in    (custom_op_id),  
    .funct3_in       (funct3_id),
    .rs1_addr_in     (rs1_addr_id),
    .rs2_addr_in     (rs2_addr_id),
    .rd_addr_in      (rd_addr_id),
    
    .pc_out          (pc_ex),
    .pc_plus4_out    (pc_plus4_ex),
    .rs1_data_out    (rs1_data_ex),
    .rs2_data_out    (rs2_data_ex),
    .imm_out         (imm_ex),
    .reg_write_out   (reg_write_ex),
    .alu_src_out     (alu_src_ex),
    .alu_ctrl_out    (alu_ctrl_ex),
    .mem_read_out    (mem_read_ex),
    .mem_write_out   (mem_write_ex),
    .mem_to_reg_out  (mem_to_reg_ex),
    .branch_out      (branch_ex),
    .jump_out        (jump_ex),
    .alu_opA_sel_out (alu_opA_sel_ex),
    .jalr_sel_out    (jalr_sel_ex),
    .custom_en_out   (custom_en_ex),   
    .custom_op_out   (custom_op_ex),   
    .funct3_out      (funct3_ex),
    .rs1_addr_out    (rs1_addr_ex),
    .rs2_addr_out    (rs2_addr_ex),
    .rd_addr_out     (rd_addr_ex)
);

assign fwd_rs1_ex = (fwd_a == 2'b10) ? alu_result_mem  :
                    (fwd_a == 2'b01) ? write_data_wb   :
                                       rs1_data_ex;

assign fwd_rs2_ex = (fwd_b == 2'b10) ? alu_result_mem  :
                    (fwd_b == 2'b01) ? write_data_wb   :
                                       rs2_data_ex;
                                       
assign alu_in1_ex = fwd_rs1_ex;
assign alu_in2_ex = alu_src_ex ? imm_ex : fwd_rs2_ex;

ex_stage u_ex_stage (
    .alu_in1       (alu_in1_ex),
    .alu_in2       (alu_in2_ex),
    .alu_ctrl      (alu_ctrl_ex),
    .pc_ex         (pc_ex),
    .imm_ex        (imm_ex),
    .branch        (branch_ex),
    .jump          (jump_ex),
    .alu_opA_sel   (alu_opA_sel_ex),
    .jalr_sel      (jalr_sel_ex),
    .funct3_ex     (funct3_ex),
    .result        (alu_result_ex),
    .zero          (zero_ex),
    .pc_src        (pc_src_ex),
    .branch_target (branch_target_ex)
);
compress_accel u_accel (
    .clk        (clk),
    .rst_n      (rst_n),
    .clk_en     (clk_en),
    .custom_en  (custom_en_ex),
    .custom_op  (custom_op_ex),
    .op_a       (fwd_rs1_ex),
    .op_b       (fwd_rs2_ex),
    .spad_raddr (spad_raddr),
    .spad_rdata (spad_rdata),
    .spad_we    (accel_spad_we),
    .spad_waddr (accel_spad_waddr),
    .spad_wdata (accel_spad_wdata),
    .result     (custom_result_ex),
    .busy       (custom_busy_ex),
    .done       (custom_done_ex),
    .dbg        (accel_dbg)
);
assign ex_writeback_result = custom_en_ex ? custom_result_ex : alu_result_ex;

ex_mem_reg u_ex_mem_reg (
    .clk             (clk),
    .clk_en	     (clk_en),
    .rst_n           (rst_n),
    .alu_result_in   (ex_writeback_result),   
    .rs2_data_in     (fwd_rs2_ex),
    .pc_plus4_in     (pc_plus4_ex),
    .reg_write_in    (reg_write_ex),
    .mem_read_in     (mem_read_ex),
    .mem_write_in    (mem_write_ex),
    .mem_to_reg_in   (mem_to_reg_ex),
    .jump_in         (jump_ex),
    .rd_addr_in      (rd_addr_ex),
    .funct3_in       (funct3_ex),
    
    .alu_result_out  (alu_result_mem),
    .rs2_data_out    (rs2_data_mem),
    .pc_plus4_out    (pc_plus4_mem),
    .reg_write_out   (reg_write_mem),
    .mem_read_out    (mem_read_mem),
    .mem_write_out   (mem_write_mem),
    .mem_to_reg_out  (mem_to_reg_mem),
    .jump_out        (jump_mem),
    .rd_addr_out     (rd_addr_mem),
    .funct3_out      (funct3_mem)
);

mem_stage u_mem_stage (
    .clk          (clk),
    .mem_read     (mem_read_mem),
    .mem_write    (mem_write_mem),
    .funct3_mem   (funct3_mem),
    .address      (alu_result_mem),
    .write_data   (rs2_data_mem),
    .read_data    (read_data_mem),
    .spad_we      (spad_we),
    .spad_waddr   (spad_waddr),
    .spad_wdata   (spad_wdata),
    .spad_wstrb   (spad_wstrb)
);

scratchpad #(.SRC_FILE(SRC_FILE)) u_scratchpad (
    .clk    (clk),

    .we0    (spad_we),
    .waddr0 (spad_waddr),
    .wdata0 (spad_wdata),
    .wstrb0 (spad_wstrb),

    .we1    (accel_spad_we),
    .waddr1 (accel_spad_waddr),
    .wdata1 (accel_spad_wdata),

    .raddr  (spad_raddr),
    .rdata  (spad_rdata)
);
mem_wb_reg u_mem_wb_reg (
    .clk             (clk),
    .clk_en	     (clk_en),
    .rst_n           (rst_n),
    .alu_result_in   (alu_result_mem),
    .read_data_in    (read_data_mem),
    .pc_plus4_in     (pc_plus4_mem),
    .reg_write_in    (reg_write_mem),
    .mem_to_reg_in   (mem_to_reg_mem),
    .jump_in         (jump_mem),
    .rd_addr_in      (rd_addr_mem),
    
    .alu_result_out  (alu_result_wb),
    .read_data_out   (read_data_wb),
    .pc_plus4_out    (pc_plus4_wb),
    .reg_write_out   (reg_write_wb),
    .mem_to_reg_out  (mem_to_reg_wb),
    .jump_out        (jump_wb),
    .rd_addr_out     (rd_addr_wb)
);

wb_stage u_wb_stage (
    .alu_result  (alu_result_wb),
    .read_data   (read_data_wb),
    .pc_plus4    (pc_plus4_wb),
    .mem_to_reg  (mem_to_reg_wb),
    .jump        (jump_wb),
    .write_data  (write_data_wb)
);

hazard_unit u_hazard (
    .mem_read_ex  (mem_read_ex),
    .rd_addr_ex   (rd_addr_ex),
    .rs1_addr_id  (rs1_addr_id),
    .rs2_addr_id  (rs2_addr_id),
    .pc_src_ex    (pc_src_ex | jump_ex),
    .stall_if     (stall_if),
    .stall_id     (stall_id),
    .flush_if     (flush_if),
    .flush_id     (flush_id),
    .flush_ex     (flush_ex)
);

forwarding_unit u_fwd (
    .rs1_addr_ex   (rs1_addr_ex),
    .rs2_addr_ex   (rs2_addr_ex),
    .rd_addr_mem   (rd_addr_mem),
    .rd_addr_wb    (rd_addr_wb),
    .reg_write_mem (reg_write_mem),
    .reg_write_wb  (reg_write_wb),
    .fwd_a         (fwd_a),
    .fwd_b         (fwd_b)
);

assign debug_data = write_data_wb;

// Pure wire-tap, no new logic (spad_we/waddr/wdata already exist)
assign spad_we_dbg    = spad_we;
assign spad_waddr_dbg = spad_waddr;
assign spad_wdata_dbg = spad_wdata;

endmodule
