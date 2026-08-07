`timescale 1ns/1ps

module if_stage #(
    parameter PROGRAM_FILE = "mem_program.hex"   // default kept for backward compatibility
) (
    input  wire        clk,clk_en,
    input  wire        rst_n,
    input  wire        stall,
    input  wire [31:0] next_pc,
    output reg  [31:0] pc_out,
    output wire [31:0] pc_plus4,
    output wire [31:0] instruction
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pc_out <= 32'h0000_0000;
    else if(clk_en) begin 
		if (!stall)
        	pc_out <= next_pc;
	 end
end

assign pc_plus4 = pc_out + 32'd4;

instruction_memory #(.PROGRAM_FILE(PROGRAM_FILE)) u_imem (
    .pc          (pc_out),
    .instruction (instruction)
);

endmodule

//---------------------------------------//

module instruction_memory #(
    parameter PROGRAM_FILE = "mem_program.hex"
) (
    input  wire [31:0] pc,
    output wire [31:0] instruction
);

(* rom_style = "distributed" *) reg [31:0] mem [0:255];

initial begin
    $readmemh(PROGRAM_FILE, mem);
end

assign instruction = mem[pc[9:2]];

endmodule
