`timescale 1ns/1ps

module id_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] instr,
    input  wire        reg_write_wb,
    input  wire [4:0]  rd_addr_wb,
    input  wire [31:0] write_data,
    
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    output wire [31:0] imm,
    output wire        reg_write,
    output wire        alu_src,
    output wire [3:0]  alu_ctrl,
    output wire        mem_read,
    output wire        mem_write,
    output wire        mem_to_reg,
    output wire        branch,
    output wire        jump,

    output wire        alu_opA_sel,
    output wire        jalr_sel,

    output wire        custom_en,    
    output wire [2:0]  custom_op,    

    output wire [4:0]  rs1_addr,
    output wire [4:0]  rs2_addr,
    output wire [4:0]  rd_addr
);

wire [6:0] opcode  = instr[6:0];
wire [4:0] rd      = instr[11:7];
wire [2:0] funct3  = instr[14:12];
wire [4:0] rs1     = instr[19:15];
wire [4:0] rs2     = instr[24:20];
wire [6:0] funct7  = instr[31:25];

localparam OPC_CUSTOM0 = 7'b0001011;   
localparam PDETECT     = 3'b000;
localparam CCOMPR      = 3'b001;
localparam CSTAT       = 3'b010;

assign rs1_addr = rs1;
assign rs2_addr = rs2;
assign rd_addr  = rd;

reg [31:0] regfile [0:31];
integer idx;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (idx = 0; idx < 32; idx = idx + 1)
            regfile[idx] <= 32'b0;
    end else begin
        if (reg_write_wb && rd_addr_wb != 5'b0)
            regfile[rd_addr_wb] <= write_data;
    end
end

assign rs1_data = (rs1 == 5'b0)                              ? 32'b0 :
                  (reg_write_wb && rd_addr_wb == rs1)         ? write_data :
                                                                regfile[rs1];

assign rs2_data = (rs2 == 5'b0)                              ? 32'b0 :
                  (reg_write_wb && rd_addr_wb == rs2)         ? write_data :
                                                                regfile[rs2];

reg [31:0] imm_reg;
always @(*) begin
    case (opcode)
        7'b0010011,        // I-type ALU
        7'b0000011,        // LOAD
        7'b1100111:        // JALR (I-type)
            imm_reg = {{20{instr[31]}}, instr[31:20]};
            
        7'b0100011:        // STORE (S-type)
            imm_reg = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            
        7'b1100011:        // BRANCH (B-type)
            imm_reg = {{19{instr[31]}}, instr[31], instr[7],
                        instr[30:25], instr[11:8], 1'b0};
                        
        7'b1101111:        // JAL (J-type)
            imm_reg = {{11{instr[31]}}, instr[31], instr[19:12],
                        instr[20], instr[30:21], 1'b0};
                        
        7'b0110111,        // LUI (U-type)
        7'b0010111:        // AUIPC (U-type)
            imm_reg = {instr[31:12], 12'b0};
            
        default:
            imm_reg = 32'b0;   
    endcase
end
assign imm = imm_reg;

reg reg_write_r, alu_src_r, mem_read_r, mem_write_r;
reg mem_to_reg_r, branch_r, jump_r;
reg [3:0] alu_ctrl_r;
reg alu_opA_sel_r, jalr_sel_r;
reg custom_en_r;            
reg [2:0] custom_op_r;      

always @(*) begin
    reg_write_r   = 1'b0;
    alu_src_r     = 1'b0;
    mem_read_r    = 1'b0;
    mem_write_r   = 1'b0;
    mem_to_reg_r  = 1'b0;
    branch_r      = 1'b0;
    jump_r        = 1'b0;
    alu_ctrl_r    = 4'b0000;
    alu_opA_sel_r = 1'b0;
    jalr_sel_r    = 1'b0;
    custom_en_r   = 1'b0;      
    custom_op_r   = 3'b000;   

    case (opcode)
        7'b0110011: begin // R-type
            reg_write_r = 1'b1;
            alu_src_r   = 1'b0;
            case ({funct7, funct3})
                10'b0000000_000: alu_ctrl_r = 4'b0000; // ADD
                10'b0100000_000: alu_ctrl_r = 4'b0001; // SUB
                10'b0000000_111: alu_ctrl_r = 4'b0010; // AND
                10'b0000000_110: alu_ctrl_r = 4'b0011; // OR
                10'b0000000_100: alu_ctrl_r = 4'b0100; // XOR
                10'b0000000_001: alu_ctrl_r = 4'b0101; // SLL
                10'b0000000_101: alu_ctrl_r = 4'b0110; // SRL
                10'b0100000_101: alu_ctrl_r = 4'b0111; // SRA
                10'b0000000_010: alu_ctrl_r = 4'b1000; // SLT
                10'b0000000_011: alu_ctrl_r = 4'b1001; // SLTU
                default:         alu_ctrl_r = 4'b0000;
            endcase
        end
        7'b0010011: begin // I-type ALU
            reg_write_r = 1'b1;
            alu_src_r   = 1'b1;
            case (funct3)
                3'b000: alu_ctrl_r = 4'b0000; // ADDI
                3'b111: alu_ctrl_r = 4'b0010; // ANDI
                3'b110: alu_ctrl_r = 4'b0011; // ORI
                3'b100: alu_ctrl_r = 4'b0100; // XORI
                3'b010: alu_ctrl_r = 4'b1000; // SLTI
                3'b011: alu_ctrl_r = 4'b1001; // SLTIU
                3'b001: alu_ctrl_r = 4'b0101; // SLLI
                3'b101: alu_ctrl_r = (funct7[5]) ? 4'b0111 : 4'b0110; // SRAI/SRLI
                default: alu_ctrl_r = 4'b0000;
            endcase
        end
        7'b0000011: begin // LOAD
            reg_write_r  = 1'b1;
            alu_src_r    = 1'b1;
            mem_read_r   = 1'b1;
            mem_to_reg_r = 1'b1;
            alu_ctrl_r   = 4'b0000; // ADD (base+offset)
        end
        7'b0100011: begin // STORE
            alu_src_r   = 1'b1;
            mem_write_r = 1'b1;
            alu_ctrl_r  = 4'b0000; // ADD
        end
        7'b1100011: begin // BRANCH
            branch_r   = 1'b1;
            alu_src_r  = 1'b0;
            alu_ctrl_r = 4'b0001; // SUB
        end
        7'b1101111: begin // JAL
            reg_write_r  = 1'b1;
            jump_r       = 1'b1;
            alu_ctrl_r   = 4'b0000;
        end
        7'b1100111: begin // JALR
            reg_write_r  = 1'b1;
            jump_r       = 1'b1;
            alu_src_r    = 1'b1;
            alu_ctrl_r   = 4'b0000; 
            jalr_sel_r   = 1'b1;    
        end
        7'b0110111: begin // LUI
            reg_write_r  = 1'b1;
            alu_src_r    = 1'b1;
            alu_ctrl_r   = 4'b1010; 
        end
        7'b0010111: begin // AUIPC 
            reg_write_r   = 1'b1;
            alu_src_r     = 1'b1;
            alu_ctrl_r    = 4'b0000; 
            alu_opA_sel_r = 1'b1;    
        end

        OPC_CUSTOM0: begin
            custom_en_r = 1'b1;
            custom_op_r = funct3;
            alu_src_r   = 1'b0;       
            alu_ctrl_r  = 4'b0000;    
            case (funct3)
                PDETECT: reg_write_r = 1'b1;   
                CSTAT:   reg_write_r = 1'b1;  
                CCOMPR:  reg_write_r = 1'b0;   
                default: reg_write_r = 1'b0;
            endcase
        end
        default: begin 
        end
    endcase
end

assign reg_write   = reg_write_r;
assign alu_src     = alu_src_r;
assign mem_read    = mem_read_r;
assign mem_write   = mem_write_r;
assign mem_to_reg  = mem_to_reg_r;
assign branch      = branch_r;
assign jump        = jump_r;
assign alu_ctrl    = alu_ctrl_r;
assign alu_opA_sel = alu_opA_sel_r; 
assign jalr_sel    = jalr_sel_r;    
assign custom_en   = custom_en_r;   
assign custom_op   = custom_op_r;   
endmodule
