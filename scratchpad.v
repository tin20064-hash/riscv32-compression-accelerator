`timescale 1ns/1ps

module scratchpad #(
    parameter AW = 8,
    parameter DW = 32,
    parameter SRC_FILE = "demo_src.hex"   // default kept for backward compatibility
)(
    input  wire           clk,

    input  wire           we0,
    input  wire [AW-1:0]  waddr0,
    input  wire [DW-1:0]  wdata0,
    input  wire [3:0]     wstrb0,

    input  wire           we1,
    input  wire [AW-1:0]  waddr1,
    input  wire [DW-1:0]  wdata1,

    // Read (accelerator)
    input  wire [AW-1:0]  raddr,
    output wire [DW-1:0]  rdata
);

    reg [DW-1:0] mem [0:(1<<AW)-1];

    integer i;
    initial begin
        for (i = 0; i < (1<<AW); i = i + 1)
            mem[i] = {DW{1'b0}};

        $readmemh(SRC_FILE, mem);
    end

    always @(posedge clk) begin
        if (we1) begin                            
            mem[waddr1] <= wdata1;
        end else if (we0) begin                    
            if (wstrb0[0]) mem[waddr0][7:0]   <= wdata0[7:0];
            if (wstrb0[1]) mem[waddr0][15:8]  <= wdata0[15:8];
            if (wstrb0[2]) mem[waddr0][23:16] <= wdata0[23:16];
            if (wstrb0[3]) mem[waddr0][31:24] <= wdata0[31:24];
        end
    end

    assign rdata = mem[raddr];

endmodule
