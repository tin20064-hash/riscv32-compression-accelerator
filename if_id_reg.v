`timescale 1ns/1ps

module if_id_reg (
    input  wire        clk,clk_en,
    input  wire        rst_n,
    input  wire        stall,        
    input  wire        flush,        
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] instr_in,
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] instr_out
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_out       <= 32'b0;
        pc_plus4_out <= 32'b0;
        instr_out    <= 32'h0000_0013;        
    end 
    else if (clk_en) begin
    		if (flush) begin
        		pc_out       <= 32'b0;
   		     	pc_plus4_out <= 32'b0;
        		instr_out    <= 32'h0000_0013; 
    	 	end 
    		else if (!stall) begin
        		pc_out       <= pc_in;
        		pc_plus4_out <= pc_plus4_in;
        		instr_out    <= instr_in;
    		end
 	 end
end

endmodule
