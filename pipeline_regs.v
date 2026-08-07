`timescale 1ns/1ps

module ex_mem_reg (
    input  wire        clk,clk_en,
    input  wire        rst_n,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] pc_plus4_in,
    input  wire        reg_write_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        mem_to_reg_in,
    input  wire        jump_in,
    input  wire [4:0]  rd_addr_in,
    input  wire [2:0]  funct3_in,      
    output reg  [31:0] alu_result_out,
    output reg  [31:0] rs2_data_out,
    output reg  [31:0] pc_plus4_out,
    output reg         reg_write_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         mem_to_reg_out,
    output reg         jump_out,
    output reg  [4:0]  rd_addr_out,
    output reg  [2:0]  funct3_out      
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        alu_result_out  <= 32'b0;
        rs2_data_out    <= 32'b0;
        pc_plus4_out    <= 32'b0;
        reg_write_out   <= 1'b0;
        mem_read_out    <= 1'b0;
        mem_write_out   <= 1'b0;
        mem_to_reg_out  <= 1'b0;
        jump_out        <= 1'b0;
        rd_addr_out     <= 5'b0;
        funct3_out      <= 3'b0;
    end 
    else if (clk_en) begin
        alu_result_out  <= alu_result_in;
        rs2_data_out    <= rs2_data_in;
        pc_plus4_out    <= pc_plus4_in;
        reg_write_out   <= reg_write_in;
        mem_read_out    <= mem_read_in;
        mem_write_out   <= mem_write_in;
        mem_to_reg_out  <= mem_to_reg_in;
        jump_out        <= jump_in;
        rd_addr_out     <= rd_addr_in;
        funct3_out      <= funct3_in;
    end
end

endmodule

module mem_wb_reg (
    input  wire        clk,clk_en,
    input  wire        rst_n,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] read_data_in,
    input  wire [31:0] pc_plus4_in,
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,
    input  wire        jump_in,
    input  wire [4:0]  rd_addr_in,

    output reg  [31:0] alu_result_out,
    output reg  [31:0] read_data_out,
    output reg  [31:0] pc_plus4_out,
    output reg         reg_write_out,
    output reg         mem_to_reg_out,
    output reg         jump_out,
    output reg  [4:0]  rd_addr_out
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        alu_result_out  <= 32'b0;
        read_data_out   <= 32'b0;
        pc_plus4_out    <= 32'b0;
        reg_write_out   <= 1'b0;
        mem_to_reg_out  <= 1'b0;
        jump_out        <= 1'b0;
        rd_addr_out     <= 5'b0;
    end
    else if(clk_en) begin
        alu_result_out  <= alu_result_in;
        read_data_out   <= read_data_in;
        pc_plus4_out    <= pc_plus4_in;
        reg_write_out   <= reg_write_in;
        mem_to_reg_out  <= mem_to_reg_in;
        jump_out        <= jump_in;
        rd_addr_out     <= rd_addr_in;
    end
end

endmodule
