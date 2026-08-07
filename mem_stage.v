`timescale 1ns/1ps

module mem_stage (
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  funct3_mem,
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data,

    output wire        spad_we,
    output wire [7:0]  spad_waddr,
    output wire [31:0] spad_wdata,
    output wire [3:0]  spad_wstrb
);

reg [31:0] data_mem [0:255];
wire [7:0] word_addr = address[9:2];

wire spad_sel = address[12];

integer i;
initial begin
    for (i = 0; i < 256; i = i + 1)
        data_mem[i] = 32'b0;
end

wire [3:0] byte_en = (funct3_mem == 3'b000) ? (4'b0001 << address[1:0]) :        // SB
                     (funct3_mem == 3'b001) ? (address[1] ? 4'b1100 : 4'b0011) : // SH
                     (funct3_mem == 3'b010) ? 4'b1111 : 4'b0000;                 // SW

wire [31:0]aligned_wdata = (funct3_mem == 3'b000) ? {4{write_data[7:0]}} :
                           (funct3_mem == 3'b001) ? {2{write_data[15:0]}} :
                            write_data;

assign spad_we    = mem_write & spad_sel;
assign spad_waddr = word_addr;
assign spad_wdata = aligned_wdata;
assign spad_wstrb = byte_en;

always @(posedge clk) begin
    if (mem_write & ~spad_sel) begin
        if (byte_en[0]) data_mem[word_addr][7:0]   <= aligned_wdata[7:0];
        if (byte_en[1]) data_mem[word_addr][15:8]  <= aligned_wdata[15:8];
        if (byte_en[2]) data_mem[word_addr][23:16] <= aligned_wdata[23:16];
        if (byte_en[3]) data_mem[word_addr][31:24] <= aligned_wdata[31:24];
    end
end

wire [31:0] mem_word = data_mem[word_addr];

always @(*) begin
    if (!mem_read) begin
        read_data = 32'b0;
    end else begin
        case (funct3_mem)
            3'b000: // LB
                case (address[1:0])
                    2'b00: read_data = {{24{mem_word[7]}},  mem_word[7:0]};
                    2'b01: read_data = {{24{mem_word[15]}}, mem_word[15:8]};
                    2'b10: read_data = {{24{mem_word[23]}}, mem_word[23:16]};
                    2'b11: read_data = {{24{mem_word[31]}}, mem_word[31:24]};
                endcase
            3'b001: // LH
                read_data = address[1] ? {{16{mem_word[31]}}, mem_word[31:16]}
                                       : {{16{mem_word[15]}}, mem_word[15:0]};
            3'b010: // LW
                read_data = mem_word;
            3'b100: // LBU
                case (address[1:0])
                    2'b00: read_data = {24'b0, mem_word[7:0]};
                    2'b01: read_data = {24'b0, mem_word[15:8]};
                    2'b10: read_data = {24'b0, mem_word[23:16]};
                    2'b11: read_data = {24'b0, mem_word[31:24]};
                endcase
            3'b101: // LHU
                read_data = address[1] ? {16'b0, mem_word[31:16]}
                                       : {16'b0, mem_word[15:0]};
            default: read_data = mem_word;
        endcase
    end
end

endmodule
