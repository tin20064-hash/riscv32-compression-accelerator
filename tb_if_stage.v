`timescale 1ns/1ps

module tb_if_stage;

reg         clk, rst_n, stall;
reg  [31:0] next_pc;
wire [31:0] pc_out, pc_plus4, instruction;

if_stage dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .stall       (stall),
    .next_pc     (next_pc),
    .pc_out      (pc_out),
    .pc_plus4    (pc_plus4),
    .instruction (instruction)
);

always #5 clk = ~clk;

task check;
    input [31:0] expected_pc;
    input [31:0] expected_instr;
    input [63:0] test_name;
    begin
        if (pc_out !== expected_pc)
            $display("FAIL [%0s] PC: got %08X exp %08X", test_name, pc_out, expected_pc);
        else if (instruction !== expected_instr)
            $display("FAIL [%0s] INSTR: got %08X exp %08X", test_name, instruction, expected_instr);
        else
            $display("PASS [%0s] PC=%08X INSTR=%08X", test_name, pc_out, instruction);
    end
endtask

initial begin
    clk = 0; rst_n = 0; stall = 0;
    next_pc = 32'b0;
    
    $readmemh("mem_program.hex", dut.u_imem.mem);
    if (dut.u_imem.mem[0] !== 32'h0050_0093) begin
        $display("ERROR: mem_program.hex not loaded - check ModelSim working directory");
        $stop;
    end
    
    repeat(3) @(posedge clk);
    rst_n = 1;
    
    @(posedge clk); #1;
    $display("--- IF Stage Tests ---");
    check(32'h00, dut.u_imem.mem[0], "T1_Reset");
    
    next_pc = 32'h04;
    @(posedge clk); #1;
    check(32'h04, dut.u_imem.mem[1], "T2_PC4");
    
    stall   = 1;
    next_pc = 32'h08;
    @(posedge clk); #1;
    check(32'h04, dut.u_imem.mem[1], "T3_Stall");
    
    stall   = 0;
    @(posedge clk); #1;
    check(32'h08, dut.u_imem.mem[2], "T4_AfterStall");
    
    if (pc_plus4 !== pc_out + 4)
        $display("FAIL [T5_PC+4] got %0d", pc_plus4);
    else
        $display("PASS [T5_PC+4] pc_plus4 = %08X", pc_plus4);
        
    stall   = 0;
    next_pc = 32'h3C;
    @(posedge clk); #1;
    check(32'h3C, dut.u_imem.mem[15], "T6_BranchTarget");
    
    rst_n = 0;
    @(posedge clk); #1;
    check(32'h00, dut.u_imem.mem[0], "T7_MidReset");

    $display("--- IF Stage Tests Done ---");
    $finish;
end

endmodule
