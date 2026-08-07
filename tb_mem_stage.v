`timescale 1ns/1ps

module tb_mem_stage;

reg        clk, mem_read, mem_write;
reg [31:0] address, write_data;
reg [2:0]  funct3_mem;
wire[31:0] read_data;

mem_stage dut (
    .clk        (clk),
    .mem_read   (mem_read),
    .mem_write  (mem_write),
    .funct3_mem (funct3_mem),
    .address    (address),
    .write_data (write_data),
    .read_data  (read_data)
);

always #5 clk = ~clk;

integer pass_cnt, fail_cnt;

task check;
    input [31:0] exp;
    input [127:0] label;
    begin
        if (read_data !== exp) begin
            $display("FAIL [%0s] got=%08X exp=%08X", label, read_data, exp);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("PASS [%0s] data=%08X", label, read_data);
            pass_cnt = pass_cnt + 1;
        end
    end
endtask

initial begin
    clk=0; mem_read=0; mem_write=0;
    address=0; write_data=0; funct3_mem=0;
    pass_cnt=0; fail_cnt=0;
    #2;
    $display("--- MEM Stage Tests ---");
    
    mem_write=1; mem_read=0; funct3_mem=3'b010; address=32'h0; write_data=32'hDEAD_BEEF;
    @(posedge clk); #1;
    mem_write=0;
    
    mem_read=1; funct3_mem=3'b010; address=32'h0; @(posedge clk); #1;
    check(32'hDEAD_BEEF, "T2_ReadWord0");
    
    mem_read=0; mem_write=1; funct3_mem=3'b010; address=32'h4; write_data=32'h1234_5678;
    @(posedge clk); #1; mem_write=0;

    mem_read=1; funct3_mem=3'b010; address=32'h4; @(posedge clk); #1;
    check(32'h1234_5678, "T3_ReadWord1");
    
    mem_read=0; address=32'h0; #1;
    check(32'h0, "T4_NoRead");
    
    mem_write=1; funct3_mem=3'b010;
    address=32'h8;  write_data=32'hAAAA_AAAA; @(posedge clk); #1;
    address=32'hC;  write_data=32'hBBBB_BBBB; @(posedge clk); #1;
    address=32'h10; write_data=32'hCCCC_CCCC; @(posedge clk); #1;
    mem_write=0;

    mem_read=1; funct3_mem=3'b010; address=32'h8;  @(posedge clk); #1; check(32'hAAAA_AAAA, "T5a_AddrWord2");
    address=32'hC;  @(posedge clk); #1; check(32'hBBBB_BBBB, "T5b_AddrWord3");
    address=32'h10; @(posedge clk); #1; check(32'hCCCC_CCCC, "T5c_AddrWord4");
    
    mem_read=1; funct3_mem=3'b010; address=32'h5; @(posedge clk); #1;
    check(32'h1234_5678, "T6_WordAlign");
    
    mem_read=0; mem_write=1; funct3_mem=3'b010; address=32'h0; write_data=32'hFFFF_FFFF;
    @(posedge clk); #1; mem_write=0;
    
    mem_read=1; funct3_mem=3'b010; address=32'h0; @(posedge clk); #1;
    check(32'hFFFF_FFFF, "T7_Overwrite");
    
    mem_read=0; mem_write=1; funct3_mem=3'b000; address=32'h20; write_data=32'h0000_00AA;
    @(posedge clk); #1;
    funct3_mem=3'b000; address=32'h21; write_data=32'h0000_00BB;
    @(posedge clk); #1;
    funct3_mem=3'b001; address=32'h22; write_data=32'h0000_CCDD;
    @(posedge clk); #1; mem_write=0;
    
    mem_read=1; funct3_mem=3'b010; address=32'h20; @(posedge clk); #1;
    check(32'hCCDD_BBAA, "T8_ByteHalfword_Write");
    
    mem_read=1; funct3_mem=3'b000; address=32'h21; @(posedge clk); #1;
    check(32'hFFFF_FFBB, "T9_LB_SignExt");
    
    mem_read=1; funct3_mem=3'b100; address=32'h21; @(posedge clk); #1;
    check(32'h0000_00BB, "T10_LBU_ZeroExt");

    mem_read=1; funct3_mem=3'b001; address=32'h22; @(posedge clk); #1;
    check(32'hFFFF_CCDD, "T11_LH_SignExt");
    
    mem_read=1; funct3_mem=3'b101; address=32'h22; @(posedge clk); #1;
    check(32'h0000_CCDD, "T12_LHU_ZeroExt");

    $display("--- MEM Stage: %0d PASS, %0d FAIL ---", pass_cnt, fail_cnt);
    $finish;
end

endmodule
