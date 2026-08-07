`timescale 1ns/1ps

module hazard_unit (
    input  wire        mem_read_ex,
    input  wire [4:0]  rd_addr_ex,
    input  wire [4:0]  rs1_addr_id,
    input  wire [4:0]  rs2_addr_id,
    
    input  wire        pc_src_ex, 
    
    output wire        stall_if,
    output wire        stall_id,
    output wire        flush_if,  
    output wire        flush_id,  
    output wire        flush_ex
);


wire load_use_hazard = mem_read_ex && (rd_addr_ex != 5'b0) &&
                         ((rd_addr_ex == rs1_addr_id) ||
                          (rd_addr_ex == rs2_addr_id));

wire control_hazard = pc_src_ex;

assign stall_if = load_use_hazard;
assign stall_id = load_use_hazard;

assign flush_if = control_hazard;
assign flush_id = control_hazard | load_use_hazard;

assign flush_ex = 1'b0; 

endmodule


module wb_stage (
    input  wire [31:0] alu_result,
    input  wire [31:0] read_data,
    input  wire [31:0] pc_plus4,
    input  wire        mem_to_reg,
    input  wire        jump,
    output wire [31:0] write_data
);

assign write_data = (jump)       ? pc_plus4  :
                    (mem_to_reg) ? read_data :
                                   alu_result;

endmodule

module forwarding_unit (
    input  wire [4:0] rs1_addr_ex,
    input  wire [4:0] rs2_addr_ex,
    input  wire [4:0] rd_addr_mem,
    input  wire [4:0] rd_addr_wb,
    input  wire       reg_write_mem,
    input  wire       reg_write_wb,
    output reg  [1:0] fwd_a,
    output reg  [1:0] fwd_b
);

always @(*) begin
    if (reg_write_mem && (rd_addr_mem != 5'b0) &&
        (rd_addr_mem == rs1_addr_ex))
        fwd_a = 2'b10;                       
    else if (reg_write_wb && (rd_addr_wb != 5'b0) &&
             (rd_addr_wb == rs1_addr_ex))
        fwd_a = 2'b01;                      
    else
        fwd_a = 2'b00;

    if (reg_write_mem && (rd_addr_mem != 5'b0) &&
        (rd_addr_mem == rs2_addr_ex))
        fwd_b = 2'b10;
    else if (reg_write_wb && (rd_addr_wb != 5'b0) &&
             (rd_addr_wb == rs2_addr_ex))
        fwd_b = 2'b01;
    else
        fwd_b = 2'b00;
end

endmodule
