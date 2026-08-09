# RISC-V 32-bit 5-Stage Pipeline + Custom Compression Accelerator

Đề tài Q2: Pattern-Aware Domain-Specific Compression Accelerator with Custom RISC-V Instruction.

Dự án này xây dựng một lõi RISC-V RV32I pipeline 5 tầng, rồi gắn thêm vào đó một bộ tăng tốc nén dữ liệu điều khiển bằng ba lệnh custom. Điểm khác biệt so với các accelerator nén thông thường là người lập trình không phải chọn thuật toán nén: một khối phần cứng nhỏ tên `pattern_detect` sẽ đo đặc tính của từng block dữ liệu rồi tự quyết định dùng thuật toán nào.

---

## Mục lục

1. [Tổng quan kiến trúc](#1-tổng-quan-kiến-trúc)
2. [RISC-V ISA — nền tảng](#2-risc-v-isa--nền-tảng)
3. [Pipeline 5 giai đoạn](#3-pipeline-5-giai-đoạn)
4. [Xử lý hazard](#4-xử-lý-hazard)
5. [Forwarding](#5-forwarding)
6. [Những gì được thêm vào so với RISC-V gốc](#6-những-gì-được-thêm-vào-so-với-risc-v-gốc)
7. [Mã hóa lệnh custom](#7-mã-hóa-lệnh-custom)
8. [Luồng HW/SW co-design](#8-luồng-hwsw-co-design)
9. [Kết quả verification](#9-kết-quả-verification)
10. [Đánh giá](#10-đánh-giá)
11. [Cấu trúc file](#11-cấu-trúc-file)
12. [Chạy simulation](#12-chạy-simulation)
13. [Dữ liệu lớn và cách tái tạo](#13-dữ-liệu-lớn-và-cách-tái-tạo)

---

## 1. Tổng quan kiến trúc

```
┌─────────────────────────────────────────────────────────────────────┐
│                    cpu_top.v                                        │
│                                                                     │
│  [IF]──[IF/ID]──[ID]──[ID/EX]──[EX]──[EX/MEM]──[MEM]──[MEM/WB]──[WB]
│                                  │                  │               │
│                          compress_accel         scratchpad      RegFile
│                         ┌────────────────┐    (dual-port)       write
│                         │ pattern_detect │         ▲
│                         │ comp_zero      │─────────┘ (read)
│                         │ comp_rle       │─────────► (write accel)
│                         │ comp_delta     │
│                         └────────────────┘
│                                                                     │
│  hazard_unit ◄──────── pc_src_ex, mem_read_ex, rd_addr_ex          │
│  forwarding_unit ──────► fwd_a, fwd_b ──► fwd_rs1_ex, fwd_rs2_ex  │
└─────────────────────────────────────────────────────────────────────┘
```

Accelerator gắn vào tầng EX, còn dữ liệu nó đọc và ghi nằm trong một scratchpad dual-port tách khỏi data memory thông thường. Cách bố trí này giữ cho pipeline gốc gần như không đổi: tầng EX chỉ cần thêm một mux chọn giữa kết quả ALU và kết quả accelerator.

Về mặt hiệu quả nén, cơ chế chọn mode tự động cho tỉ số 2.835× trên dataset hỗn hợp, trong khi mode cố định tốt nhất (DELTA) chỉ đạt 1.622×. Chênh lệch này là lý do tồn tại của cả dự án, và mục 10 trình bày chi tiết cách đo.

---

## 2. RISC-V ISA — nền tảng

### Thanh ghi

Kiến trúc có 32 thanh ghi x0 đến x31, mỗi thanh ghi 32-bit. Thanh ghi x0 luôn đọc ra 0 và không ghi được; điều này được ép ngay trong phần cứng tại `id_stage.v:63` chứ không dựa vào compiler.

### Sáu định dạng lệnh

Mọi lệnh đều dài đúng 32 bit, chia thành sáu format:

| Format | Cấu trúc bits | Dùng cho |
|--------|--------------|----------|
| R-type | `[funct7\|rs2\|rs1\|funct3\|rd\|opcode]` | ALU register-register |
| I-type | `[imm12\|rs1\|funct3\|rd\|opcode]` | ADDI, LW, JALR |
| S-type | `[imm[11:5]\|rs2\|rs1\|funct3\|imm[4:0]\|opcode]` | SW |
| B-type | `[imm[12,10:5]\|rs2\|rs1\|funct3\|imm[4:1,11]\|opcode]` | BEQ, BNE |
| U-type | `[imm20\|rd\|opcode]` | LUI, AUIPC |
| J-type | `[imm[20,10:1,11,19:12]\|rd\|opcode]` | JAL |

Ở B-type và J-type, các bit immediate trông như bị xáo trộn lộn xộn. Thực ra đây là lựa chọn có chủ đích của RISC-V: nhờ xáo trộn như vậy mà trường `rd` và `rs1` nằm cùng một vị trí bit ở mọi format, nên phần decode không cần mux để chọn xem lấy chỉ số thanh ghi từ đâu. Cách ráp lại immediate xem tại `id_stage.v:72–97`.

### Tập lệnh được hỗ trợ

```
ALU R-type : ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
ALU I-type : ADDI ANDI ORI XORI SLLI SRLI SRAI SLTI SLTIU
Memory     : LW LB LH LBU LHU  /  SW SB SH
Branch     : BEQ BNE BLT BGE BLTU BGEU
Jump       : JAL JALR
Upper imm  : LUI AUIPC
Custom     : PDETECT CCOMPR CSTAT  (opcode 0x0B)
```

---

## 3. Pipeline 5 giai đoạn

Mỗi lệnh đi qua năm giai đoạn, mỗi giai đoạn tốn một chu kỳ clock. Vì các giai đoạn độc lập nhau nên năm lệnh khác nhau có thể cùng chạy một lúc, mỗi lệnh ở một tầng:

```
Cycle:   1    2    3    4    5    6    7
Lệnh 1: [IF] [ID] [EX] [M]  [WB]
Lệnh 2:      [IF] [ID] [EX] [M]  [WB]
Lệnh 3:           [IF] [ID] [EX] [M]  [WB]
```

### IF — `if_stage.v`

Tầng này chỉ có một việc: lấy lệnh kế tiếp. Thanh ghi PC 32-bit tăng 4 mỗi clock vì lệnh dài 4 byte. Bộ nhớ lệnh được đánh địa chỉ bằng `pc[9:2]`, tức 8 bit word-address, nên chương trình tối đa 256 lệnh.

Giá trị `next_pc` bình thường là `pc+4`, nhưng khi có branch hoặc jump thì lấy `branch_target_ex` từ tầng EX. Nếu `stall_if` bật lên 1 thì PC đứng yên, lệnh cũ được fetch lại — đây là cách pipeline "đóng băng" tầng IF khi cần chờ.

### ID — `id_stage.v`

Tầng ID làm hai việc song song trong cùng một chu kỳ.

Việc thứ nhất là đọc register file. Register file 32×32-bit đọc kiểu tổ hợp, không cần clock:

```
rs1_data = (rs1==0) ? 0 : (WB đang ghi rd==rs1) ? write_data : regfile[rs1]
```

Nhánh giữa là điểm đáng chú ý: nếu tầng WB đang ghi đúng thanh ghi mà ID đang đọc, ta lấy thẳng giá trị sắp ghi thay vì đọc ô nhớ cũ. Không có bypass này thì mỗi lần lệnh cách nhau 3 nhịp cùng dùng một thanh ghi sẽ phải stall một cycle.

Việc thứ hai là giải mã opcode thành các tín hiệu điều khiển:

```
reg_write   — cho phép WB ghi register
alu_src     — ALU in2 từ imm (1) hay rs2 (0)
alu_ctrl    — phép tính ALU (4-bit)
mem_read    — đọc data memory
mem_write   — ghi data memory
mem_to_reg  — WB chọn read_data thay vì ALU result
branch      — lệnh branch
jump        — JAL/JALR
custom_en   — kích accelerator (thêm mới)
custom_op   — PDETECT/CCOMPR/CSTAT (thêm mới)
```

Hai dòng cuối là phần mở rộng của dự án; phần còn lại là RV32I chuẩn.

### EX — `ex_stage.v`

ALU hỗ trợ ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU và LUI, chọn bằng `alu_ctrl` 4-bit. Riêng AUIPC cần cộng với PC thay vì rs1, nên có thêm tín hiệu `alu_opA_sel` để đổi nguồn của input A.

Branch được quyết định tại đây bằng cách so sánh rs1 với rs2, cho ra `branch_taken`. Địa chỉ đích là `pc_ex + imm_ex`, riêng JALR tính `(rs1 + imm) & ~1` vì spec bắt buộc xóa bit 0.

Phần thêm mới của dự án nằm ở một dòng mux:

```verilog
assign ex_writeback_result = custom_en_ex ? custom_result_ex : alu_result_ex;
```

### MEM — `mem_stage.v`

Bộ nhớ dữ liệu `data_mem[0:255]` chứa 256 word. Dự án thêm vào đây một bước decode địa chỉ: nếu `address[12]` bằng 1 thì truy cập rơi vào scratchpad của accelerator, bằng 0 thì vào data memory như bình thường.

Store sub-word (SB, SH) dùng mask `byte_en` cộng với `aligned_wdata` — dữ liệu được nhân bản ra cả 4 byte lane rồi mask mới chọn lane nào thực sự ghi. Chiều ngược lại, load sub-word cần mở rộng dấu: LB mở rộng dấu từ 8 lên 32 bit, còn LBU thì độn 0.

### WB — trong `wb_hazard_fwd.v`

Tầng cuối chọn một trong ba nguồn để ghi ngược về register file:

```
jump=1       → pc+4  (JAL/JALR lưu return address)
mem_to_reg=1 → read_data  (kết quả LW)
else         → alu_result
```

### Pipeline register

Giữa mỗi cặp tầng có một thanh ghi chốt dữ liệu lại:

| Register | Nội dung chính |
|----------|---------------|
| IF/ID | pc, pc+4, instruction |
| ID/EX | rs1_data, rs2_data, imm, toàn bộ control signal, thêm custom_en/custom_op |
| EX/MEM | alu_result, rs2_data, pc+4, reg_write, funct3 |
| MEM/WB | alu_result, read_data, pc+4, reg_write |

Tất cả đều có `rst_n` reset bất đồng bộ và `clk_en` để đóng băng toàn bộ pipeline khi cần.

---

## 4. Xử lý hazard

### Load-use hazard

Đây là trường hợp duy nhất mà forwarding không cứu được. Khi lệnh LW đang ở tầng EX, dữ liệu nó cần chưa được đọc ra khỏi bộ nhớ (phải sang tầng MEM mới có), nên lệnh ngay sau bắt buộc phải chờ một nhịp:

```verilog
// wb_hazard_fwd.v:19
load_use_hazard = mem_read_ex && (rd_addr_ex != 0) &&
                  (rd_addr_ex == rs1_addr_id || rd_addr_ex == rs2_addr_id)
```

Khi phát hiện, phần cứng bật `stall_if` và `stall_id` để giữ hai tầng đầu đứng yên, đồng thời `flush_id` chèn một NOP vào EX để lấp chỗ trống.

### Control hazard

Branch chỉ biết có nhảy hay không khi đã tới tầng EX. Lúc đó hai lệnh phía sau đã lỡ vào IF và ID rồi, và nếu branch thực sự nhảy thì cả hai đều sai. Cách xử lý là xóa chúng đi bằng `flush_if` và `flush_id`, tốn 2 cycle mỗi lần branch được lấy.

---

## 5. Forwarding

Phần lớn data hazard không cần stall — chỉ cần lấy kết quả từ tầng sau chuyển ngược về EX trước khi nó kịp ghi vào register file:

```
fwd_a = 2'b10 → ALU result từ EX/MEM reg  (1 cycle cũ)
fwd_a = 2'b01 → write_data từ MEM/WB reg  (2 cycle cũ)
fwd_a = 2'b00 → từ ID/EX reg              (bình thường)
```

Thứ tự ưu tiên là MEM trước, rồi mới tới WB. Lý do là nếu cùng một thanh ghi bị ghi bởi hai lệnh khác nhau thì lệnh gần hơn (đang ở MEM) mới là giá trị mới nhất, nên phải kiểm `rd_addr_mem` trước.

```asm
add x1, x2, x3   # EX: tính x1
add x4, x1, x5   # EX cần x1, forward thẳng từ EX/MEM nên không phải stall
```

---

## 6. Những gì được thêm vào so với RISC-V gốc

Phần này liệt kê từng thay đổi so với một lõi RV32I thuần, theo thứ tự dữ liệu chảy qua pipeline.

### 6.1 Decoder cho opcode custom

RISC-V dành sẵn opcode 0x0B (custom-0) cho phần mở rộng của người dùng, nên không cần đụng tới bất kỳ opcode chuẩn nào. Ba lệnh mới phân biệt nhau bằng trường funct3:

```verilog
localparam OPC_CUSTOM0 = 7'b0001011;  // = 0x0B (custom-0 theo RISC-V spec)
localparam PDETECT = 3'b000;
localparam CCOMPR  = 3'b001;
localparam CSTAT   = 3'b010;

OPC_CUSTOM0: begin
    custom_en_r = 1'b1;
    custom_op_r = funct3;      // funct3 phân biệt 3 lệnh
    case (funct3)
        PDETECT: reg_write_r = 1'b0;  // không ghi (rd=x0) — xem giải thích bên dưới
        CSTAT:   reg_write_r = 1'b1;  // trả status_word về rd
        CCOMPR:  reg_write_r = 1'b0;  // không ghi (rd=x0)
    endcase
end
```

CCOMPR không bật `reg_write` vì nó chỉ khởi động accelerator chứ không có gì trả về ngay. PDETECT cũng không bật `reg_write` — lý do khác CCOMPR: pipeline chỉ có thể chốt kết quả vào `rd` ngay trong chu kỳ EX của chính lệnh đó, trong khi detection cần thêm 17 chu kỳ mới xong, nên giá trị chốt được lúc đó (nếu có) sẽ luôn là kết quả cũ/rác, không phải kết quả của lần detect vừa gọi. Kết quả nén và kết quả detect đều được lấy sau bằng cách poll CSTAT.

### 6.2 Mở rộng pipeline register

`id_ex_reg` trong `pipeline_regs.v` nhận thêm hai trường:

```verilog
input  wire        custom_en_in,
input  wire [2:0]  custom_op_in,
output reg         custom_en_out,
output reg  [2:0]  custom_op_out,
```

Hai tín hiệu này chỉ cần đi qua ID/EX, không cần lan tới EX/MEM, vì accelerator nối vào tầng EX và tiêu thụ chúng ngay tại đó.

### 6.3 Mux kết quả tại tầng EX

```verilog
// cpu_top.v:269
assign ex_writeback_result = custom_en_ex ? custom_result_ex : alu_result_ex;
```

`custom_result_ex` là tín hiệu tổ hợp nên có giá trị ngay trong cùng chu kỳ. Nhờ vậy CSTAT trả kết quả về thanh ghi đích mà không tốn thêm nhịp nào so với một lệnh ALU thường. PDETECT không hưởng lợi từ cơ chế này — pipeline chốt `rd` cùng chu kỳ lệnh phát ra, nhưng detection cần 17 chu kỳ sau mới có kết quả, nên `reg_write` của PDETECT bị tắt (xem mục 6.1); phần mềm phải đọc kết quả qua CSTAT sau khi poll `done`.

### 6.4 Scratchpad — bộ nhớ dùng chung giữa CPU và accelerator

File `scratchpad.v` là module hoàn toàn mới. Về nguyên tắc accelerator có thể dùng chung `data_mem` của tầng MEM, nhưng khi đó phải có arbiter phân xử giữa CPU và accelerator, và phải xử lý trường hợp cả hai cùng muốn ghi. Tách riêng một khối nhớ dual-port đơn giản hơn nhiều:

```verilog
module scratchpad #(AW=8, DW=32)(
    // Port 0: CPU ghi nguồn (qua SW instruction, byte-strobe)
    input we0, waddr0[AW-1:0], wdata0[DW-1:0], wstrb0[3:0],
    // Port 1: Accelerator ghi kết quả nén (word-wide, ưu tiên cao hơn)
    input we1, waddr1[AW-1:0], wdata1[DW-1:0],
    // Read: Accelerator đọc nguồn (async, 0-cycle latency)
    input raddr[AW-1:0], output rdata[DW-1:0]
);
```

CPU dùng port 0 để nạp dữ liệu nguồn vào, accelerator dùng port 1 để ghi kết quả ra. Cổng đọc là bất đồng bộ, tức accelerator đặt địa chỉ ra và có dữ liệu ngay trong cùng cycle — chi tiết này ảnh hưởng trực tiếp tới latency của cả ba module nén.

Việc phân biệt hai vùng nhớ nằm ở `mem_stage.v`:

```
address[12] = 0  →  data_mem  (0x0000–0x03FC)
address[12] = 1  →  scratchpad (0x1000–0x13FC)
word_addr = address[9:2]  (byte addr ÷ 4)
```

Cách bố trí vùng nhớ trong demo:

```
scratchpad[0..47]    = 3 block nguồn (3×16 word = demo_src.hex)
scratchpad[48..63]   = kết quả nén block 0 (ZERO, 5 word)
scratchpad[64..68]   = kết quả nén block 1 (RLE, 5 word)
scratchpad[69..74]   = kết quả nén block 2 (DELTA, 6 word)
```

### 6.5 `Compress_accel.v` — bộ điều phối

Module này chứa bốn sub-module (ba compressor và một detector) và quyết định cái nào chạy khi nào.

Đầu vào gồm `custom_en`, `custom_op`, cùng hai toán hạng `op_a = fwd_rs1_ex` và `op_b = fwd_rs2_ex`. Điểm cần lưu ý là hai toán hạng lấy từ giá trị đã forward chứ không lấy thẳng từ ID/EX. Nếu lấy thẳng, một lệnh custom đứng ngay sau lệnh tính địa chỉ sẽ nhận phải giá trị cũ.

Tham số được nhét chung vào `op_b` để tiết kiệm số toán hạng:

```
CCOMPR:  src_word  = op_a[AW+1:2]    (byte→word: ÷4)
         dest_word = op_b[AW+1:2]
         req_mode  = op_b[1:0]        ← mode nhét vào 2 bit thấp của địa chỉ
PDETECT: tau1 = op_b[5:0]   (0 → dùng TAU1_DEF=8)
         tau2 = op_b[13:8]
         wmax = op_b[21:16]
```

Mẹo ở đây là địa chỉ đích luôn word-aligned nên hai bit thấp luôn bằng 0, có thể mượn để chở mã mode mà không mất thông tin.

Tín hiệu start được sinh sao cho tại mỗi thời điểm chỉ đúng một sub-module được kích hoạt:

```verilog
wire start_z = (state==S_IDLE) & ccompr_cmd & (req_mode==2'b00) & clk_en;
wire start_r = (state==S_IDLE) & ccompr_cmd & (req_mode==2'b01) & clk_en;
wire start_d = (state==S_IDLE) & ccompr_cmd & (req_mode==2'b10) & clk_en;
wire start_p = (state==S_IDLE) & pdetect_cmd & clk_en;
```

FSM của bộ điều phối chỉ có hai trạng thái. `S_IDLE` chờ lệnh CCOMPR hoặc PDETECT tới rồi chuyển sang `S_RUN`. `S_RUN` chờ sub-module báo done, chốt lại `last_result` và `last_op`, bật `done_r` rồi quay về idle.

Trạng thái được phần mềm đọc qua CSTAT:

```
bit[31] = busy
bit[30] = done    ← SW poll cái này
bit[29] = err
bit[28] = last_op  (0=compress → last_result=out_len; 1=detect → last_result=det_word)
bit[27:0] = last_result
```

### 6.6 `comp_zero.v` — nén zero-suppression

Thuật toán này khai thác trường hợp block có nhiều word bằng 0. Thay vì lưu cả 16 word, ta lưu một bitmap 16-bit đánh dấu word nào khác 0, rồi chỉ lưu các word khác 0 đó.

```
Word 0 (header): {14'b0, 00, bitmap[15:0]}   mode=00 ở bit[17:16]
Word 1..K:        các word non-zero theo thứ tự
out_len = 1 + K   (K = số word ≠ 0)
```

FSM có ba trạng thái. `S_STREAM` đọc từng word một, gặp word khác 0 thì ghi ra đích, set bit tương ứng trong bitmap và tăng con trỏ ghi. `S_HEADER` ghi header vào `dest[0]` rồi báo xong.

Sở dĩ cả quá trình chỉ tốn N+2 cycle là nhờ cổng đọc bất đồng bộ của scratchpad: `rd_addr = src_base_r + idx` là wire tổ hợp nên `rd_data` có sẵn ngay trong cùng cycle, không phải chờ một nhịp cho bộ nhớ trả về.

Ví dụ với block `[0,0,A,0,B,0,...,C,0]` trong đó A, B, C nằm ở vị trí 2, 4, 14:

```
bitmap  = 0b0100000000010100  (bit 2,4,14)
output  = [header, A, B, C]  → out_len=4  (thay vì 16 word, tiết kiệm 75%)
```

### 6.7 `comp_rle.v` — run-length encoding

Khi dữ liệu có nhiều đoạn giá trị lặp lại liên tiếp, lưu cặp (giá trị, số lần) rẻ hơn lưu từng phần tử.

```
Word 0 (header): {14'b0, 01, num_runs[15:0]}
Word 1,2:        (run_val_0, run_cnt_0)
Word 3,4:        (run_val_1, run_cnt_1)   ...
out_len = 1 + 2×num_runs
```

FSM sáu trạng thái, đi theo thứ tự `S_IDLE → S_LOAD → S_SCAN → S_WVAL → S_WCNT → S_HEADER`. Khác với zero-suppression, RLE phải nạp toàn bộ N word vào `wbuf[]` trước rồi mới quét được, vì cần biết một run kết thúc ở đâu trước khi ghi được số đếm của nó.

`S_SCAN` duyệt từ `scan_idx=1`, gặp phần tử trùng với `run_val` thì tăng bộ đếm, gặp phần tử khác thì xả run hiện tại ra. Việc ghi tách làm hai trạng thái `S_WVAL` và `S_WCNT` vì scratchpad chỉ có một cổng ghi, mỗi run tốn 2 cycle.

Ví dụ với `[5,5,5,5,5,5,5,5,5, 7,7,7,7,7,7,7]`:

```
runs    = [(5,9), (7,7)]
output  = [header|2, 5, 9, 7, 7]  → out_len=5  (tiết kiệm 69%)
```

### 6.8 `comp_delta.v` — delta encoding

Dữ liệu cảm biến thường biến thiên chậm, hai mẫu liên tiếp chênh nhau rất ít. Delta encoding lưu giá trị đầu tiên làm gốc rồi lưu các hiệu, và nếu mọi hiệu đều nằm gọn trong 8 bit có dấu thì nhét được 4 hiệu vào một word.

Trường hợp đóng gói được:

```
Word 0 (header): {14'b0, 10, 7'b0, packed=1, 8'b0}
Word 1:           base = block[0]
Word 2:           {diff[4], diff[3], diff[2], diff[1]}   little-endian byte
Word 3:           {diff[8], diff[7], diff[6], diff[5]}
Word 4:           {diff[12], diff[11], diff[10], diff[9]}
Word 5:           {0, diff[15], diff[14], diff[13]}
out_len = 6
```

Nếu có dù chỉ một hiệu vượt khỏi khoảng [-128, 127], module rơi về chế độ raw, lưu nguyên 16 word gốc và chấp nhận out_len = 17. Đây là cái giá phải trả để đảm bảo không mất mát dữ liệu:

```
Word 0 (header): {14'b0, 10, 16'b0}   packed=0
Word 1..16:       16 word gốc
out_len = 17
```

Phép kiểm tra một hiệu có vừa 8-bit signed hay không được viết gọn như sau:

```verilog
// 8-bit signed fit: 25 bit cao [31:7] phải đồng nhất
if (!((&diff[k][31:7]) | (~|diff[k][31:7])))  fits = 1'b0;
```

Ý tưởng là một số 8-bit có dấu khi mở rộng lên 32 bit thì 25 bit cao phải giống hệt nhau. `&diff[k][31:7]` bằng 1 khi tất cả đều là 1 (số âm nhỏ), `~|diff[k][31:7]` bằng 1 khi tất cả đều là 0 (số dương nhỏ). Không rơi vào hai trường hợp đó nghĩa là hiệu quá lớn.

FSM bốn trạng thái `S_IDLE → S_LOAD → S_EMIT → S_FIN`. Trong `S_EMIT`, biến đếm `e` chạy từ 0 tới 5 nếu đóng gói được hoặc từ 0 tới 16 nếu phải dùng raw, mỗi cycle ghi một word; `wr_data` là wire tổ hợp chọn theo `e`.

### 6.9 `pattern_detect.v` — khối phát hiện mẫu

Đây là đóng góp chính của dự án: thay vì để phần mềm đoán nên nén kiểu gì, phần cứng tự đo rồi tự chọn.

#### Hàm `sbits`

Hàm này trả về số bit tối thiểu cần để biểu diễn một số có dấu, tương đương phép đếm số 0 dẫn đầu nhưng làm trên số signed:

```verilog
function [5:0] sbits;
    input [31:0] v;
    integer i; reg [5:0] w;
    begin
        w = 6'd1;                           // tối thiểu 1 bit (chỉ dấu)
        for (i=0; i<31; i=i+1)
            if (v[i] != v[31]) w = i + 2;  // bit khác dấu → cần i+2 bit
        sbits = w;
    end
endfunction
```

Kiểm chứng nhanh: `sbits(5)` bằng 4 vì cần 4 bit có dấu để biểu diễn +5; `sbits(-1)` bằng 1; `sbits(127)` bằng 8; `sbits(128)` bằng 9.

#### Ba chỉ số đo

Detector đo ba con số cho mỗi block: số word bằng 0, số cặp kề nhau trùng giá trị, và bề rộng bit lớn nhất trong các hiệu kề nhau.

```verilog
always @(*) begin
    zero_cnt = 0; run_cnt = 0; delta_w = 0;
    for (k=0; k<N; k=k+1)
        if (wbuf[k]==0) zero_cnt++;              // NOR + popcount

    for (k=1; k<N; k=k+1) begin
        if (wbuf[k]==wbuf[k-1]) run_cnt++;       // comparator + popcount
        dtmp = wbuf[k] - wbuf[k-1];
        dw_i = sbits(dtmp);
        if (dw_i > delta_w) delta_w = dw_i;     // subtractor + LZC + max
    end
end
```

Ba chỉ số này tương ứng đúng với ba thuật toán nén: nhiều số 0 thì hợp với zero-suppression, nhiều cặp trùng thì hợp với RLE, hiệu nhỏ thì hợp với delta. Phần cứng đo được chúng gần như miễn phí vì comparator dùng cho RLE cũng chính là đầu vào của subtractor cho delta, còn subtractor thì dùng chung giữa việc tính hiệu và việc đo bề rộng bit.

#### Chọn mode

```verilog
if (zero_cnt >= tau1_r)     mode_sel = MODE_ZERO;   // 00
else if (run_cnt >= tau2_r) mode_sel = MODE_RLE;    // 01
else if (delta_w <= wmax_r) mode_sel = MODE_DELTA;  // 10
else                        mode_sel = MODE_RAW;    // 11
```

Ngưỡng mặc định `TAU1 = TAU2 = WMAX = 8`, nhưng phần mềm có thể ghi đè qua toán hạng `op_b` của lệnh PDETECT. Thứ tự ưu tiên đặt ZERO lên đầu vì khi block thưa thì zero-suppression gần như luôn thắng, và đặt RAW cuối cùng như lối thoát khi không thuật toán nào có lợi.

#### `det_word`

Bốn thông tin được gói vào một word 32-bit để trả về register file trong một lệnh duy nhất:

```
bit[1:0]   = mode      (00/01/10/11)
bit[7:2]   = zero_cnt  (0–63)
bit[13:8]  = run_cnt   (0–63)
bit[21:16] = delta_w   (0–63)
bit[31:22] = 0
```

Phần mềm thường chỉ cần 2 bit mode, ba trường còn lại hữu ích khi debug hoặc khi muốn tự viết chính sách chọn mode khác.

FSM ba trạng thái: `S_LOAD` nạp N word (tốn N cycle), `S_DONE` chốt kết quả tổ hợp lại và bật `done`.

### 6.10 Nối dây trong `cpu_top.v`

Ba wire mới cho đường ghi của accelerator:

```verilog
wire accel_spad_we;
wire [7:0] accel_spad_waddr;
wire [31:0] accel_spad_wdata;
```

Và scratchpad được nối cả hai cổng:

```verilog
scratchpad u_scratchpad (
    .we0(spad_we), .waddr0(spad_waddr), .wdata0(spad_wdata), .wstrb0(spad_wstrb),
    .we1(accel_spad_we), .waddr1(accel_spad_waddr), .wdata1(accel_spad_wdata),
    .raddr(spad_raddr), .rdata(spad_rdata)
);
```

### 6.11 Lớp phần mềm

#### `compress_api.h`

Ba lệnh custom được bọc lại thành hàm C bằng inline assembly, dùng directive `.insn` nên không cần sửa compiler:

```c
// CSTAT: đọc status (1 instruction, combinational result)
static inline uint32_t accel_cstat(void) {
    uint32_t s;
    asm volatile (".insn r 0x0B, 2, 0, %0, x0, x0" : "=r"(s));
    return s;
}

// Poll loop — chờ bit[30]=done
static inline uint32_t accel_wait(void) {
    uint32_t s;
    do { s = accel_cstat(); } while (!CSTAT_DONE(s));
    return s;
}

// PDETECT — detect mode và trả det_word
static inline uint32_t detect_pattern(uint32_t src, uint32_t thr) {
    uint32_t d;
    asm volatile (".insn r 0x0B, 0, 0, %0, %1, %2" : "=r"(d) : "r"(src), "r"(thr));
    return CSTAT_RESULT(accel_wait());
}

// CCOMPR — nén block và trả out_len
static inline uint32_t compress_block(uint32_t src, uint32_t dest_mode) {
    asm volatile (".insn r 0x0B, 1, 0, x0, %0, %1" :: "r"(src), "r"(dest_mode));
    return CSTAT_RESULT(accel_wait());
}
```

Kèm theo là các macro bóc tách bit:

```c
#define CSTAT_DONE(s)    (((s) >> 30) & 1u)
#define CSTAT_RESULT(s)  ((s) & 0x0FFFFFFFu)
#define DET_MODE(r)      ((r) & 0x3u)
#define DET_ZEROCNT(r)   (((r) >> 2)  & 0x3Fu)
#define DET_RUNCNT(r)    (((r) >> 8)  & 0x3Fu)
#define DET_DELTAW(r)    (((r) >> 16) & 0x3Fu)
```

#### `demo_pipeline.c`

Toàn bộ vòng lặp ứng dụng gọn trong mười dòng, và đó là điểm mấu chốt: phần mềm không hề biết ZERO, RLE hay DELTA là gì, nó chỉ chuyển tiếp mode mà phần cứng trả về:

```c
void run_pipeline(void) {
    uint32_t dst = DST0_BYTE;            // con trỏ đích (byte)
    for (uint32_t i = 0; i < NUM_BLK; i++) {
        uint32_t src = SRC0_BYTE + i * BLOCK_BYTES;
        uint32_t det  = detect_pattern(src, 0);   // thr=0 → default
        uint32_t mode = DET_MODE(det);
        uint32_t out_len = compress_block(src, dst | mode);
        dst += out_len * 4;                        // tiến con trỏ
    }
}
```

#### `asm_riscv.py`

Máy phát triển không có `riscv32-unknown-elf-gcc`, nên dự án tự viết một assembler Python hai lượt để vẫn chạy được chương trình thật trên simulation. Nó hỗ trợ tập con RV32I (ADDI, LUI, SW, LW, BEQ, BNE, JAL, SLL, SRL, ANDI, OR, ADD) cùng ba lệnh custom viết dưới dạng `pdetect rd,rs1,rs2`, `ccompr rs1,rs2` và `cstat rd`, rồi sinh ra `demo_pipeline.hex` gồm 256 word có padding 0.

---

## 7. Mã hóa lệnh custom

Cả ba lệnh dùng opcode `0x0B = 7'b0001011`, tức custom-0 mà RISC-V dành riêng cho phần mở rộng của người dùng, và đều theo R-type format:

```
[31:25]   [24:20]  [19:15]  [14:12]  [11:7]  [6:0]
funct7=0  rs2      rs1      funct3   rd      0001011
```

| Lệnh | funct3 | rs1 | rs2 | rd | Chức năng |
|------|--------|-----|-----|-----|-----------|
| `pdetect rd,rs1,rs2` | 000 | src_addr | ngưỡng | det_word | Detect pattern 1 block |
| `ccompr rs1,rs2` | 001 | src_addr | dst\|mode | x0 | Nén 1 block |
| `cstat rd` | 010 | x0 | x0 | status | Poll status |

Cấu trúc word trạng thái trả về bởi CSTAT:

```
bit[31]   = busy
bit[30]   = done   ← SW poll cái này (beq/bne loop)
bit[29]   = err
bit[28]   = last_op  (0=compress, 1=detect)
bit[27:0] = last_result (out_len hoặc det_word)
```

Cấu trúc `det_word` trả về bởi PDETECT:

```
bit[1:0]   = mode      00=ZERO  01=RLE  10=DELTA  11=RAW
bit[7:2]   = zero_cnt
bit[13:8]  = run_cnt
bit[21:16] = delta_w
```

Và mã mode nhét trong hai bit thấp của `op_b`:

```
00 = ZERO   (zero-suppression + bitmap)
01 = RLE    (run-length encoding)
10 = DELTA  (8-bit signed delta, packed)
11 = RAW    (không nén — accelerator từ chối, err=1)
```

---

## 8. Luồng HW/SW co-design

Dưới đây là toàn bộ vòng xử lý một block, viết bằng assembly để thấy rõ từng lệnh:

```asm
# ① PDETECT: kích detector chạy N=16 cycle load + 1 cycle compute
pdetect x11, x10, x0      # x10=src_addr, x0=thr=0(default), x11=det_word(cũ)

# ② Poll CSTAT đến khi done=1
wait1:
  cstat x12
  srli  x13, x12, 30      # x13 = status[30] = done bit
  andi  x13, x13, 1
  beq   x13, x0, wait1    # lặp nếu done=0

# ③ Lấy mode từ det_word
andi  x14, x12, 3          # mode = status[1:0] = det_word[1:0]

# ④ CCOMPR: kick compression với mode vừa detect
or    x15, x5, x14         # x15 = dst_addr | mode
ccompr x10, x15            # x10=src, x15=dst|mode

# ⑤ Poll CSTAT lần 2
wait2:
  cstat x16
  srli  x17, x16, 30
  andi  x17, x17, 1
  beq   x17, x0, wait2

# ⑥ Lấy out_len, tiến con trỏ đích
andi  x18, x16, 0x7FF      # out_len = status[10:0]
slli  x19, x18, 2           # out_len × 4 byte
add   x5,  x5, x19          # dst += out_len*4
```

Thiết kế chọn mô hình poll thay vì cho pipeline tự stall theo `custom_busy`. Lý do là stall handshake đòi hỏi sửa `hazard_unit` và làm phức tạp phần đã verify xong, trong khi vòng poll bằng phần mềm đã đủ đúng — detector chạy khoảng 18 cycle và phần nén chạy 16 đến 35 cycle tùy mode, đều ngắn hơn thời gian phần mềm quay lại kiểm tra.

---

## 9. Kết quả verification

### Unit test

| Testbench | Module | Kết quả |
|-----------|--------|---------|
| `tb_comp_zero.v` | `comp_zero.v` | PASS (256 block, EXP_LEN=3216) |
| `tb_comp_rle.v` | `comp_rle.v` | PASS (256 block, EXP_LEN=4318) |
| `tb_comp_delta.v` | `comp_delta.v` | PASS (256 block, EXP_LEN=2526) |
| `tb_pattern_detect.v` | `pattern_detect.v` | PASS (256 block, khớp golden) |
| `tb_cpu_top.v` | Toàn bộ pipeline | PASS (37 test case) |

### Integration test

`tb_demo_pipeline.v` chạy trọn vòng detect–chọn–nén trên ba block có đặc tính khác nhau. Detector chọn đúng lần lượt ZERO, RLE, DELTA; độ dài đầu ra lần lượt là 5, 5, 6 word; và nội dung `scratchpad[48..63]` khớp golden model.

### Golden-match qua dispatcher

`tb_compress_top.v` không gọi thẳng từng module nén mà đi qua đúng con đường mà CPU dùng, tức qua lệnh CCOMPR và bộ điều phối. Đây là điểm quan trọng: nếu chỉ test từng module riêng lẻ thì một lỗi ở phần điều phối vẫn lọt.

| Mode | Word ghi ra | Kết quả |
|------|-------------|---------|
| ZERO | 3216 | khớp golden |
| RLE | 4318 | khớp golden |
| DELTA | 2526 | khớp golden |

### Round-trip lossless

Chỉ so khớp với golden model thì chưa đủ để khẳng định không mất dữ liệu — nếu golden model sai thì RTL sai theo mà vẫn báo PASS. Vì vậy `golden_compress.py --roundtrip` có thêm bộ giải nén `decompress_zero/rle/delta` và kiểm tra `decompress(compress(x)) == x` trên toàn bộ 256 block:

| Mode | PASS | FAIL |
|------|------|------|
| ZERO | 256 | 0 |
| RLE | 256 | 0 |
| DELTA | 256 | 0 |
| ADAPTIVE | 256 | 0 |

Ghép hai kết quả lại thì có đủ cơ sở kết luận: RTL sinh ra đúng `compress(x)` (chứng minh ở phần trên), và `decompress(compress(x))` bằng `x` (chứng minh ở phần này), nên đầu ra của RTL giải nén lại đúng dữ liệu gốc.

### Tỉ số nén trên dataset hỗn hợp

| Mode | Ratio |
|------|-------|
| ZERO-only | ~1.5× |
| RLE-only | ~0.9× |
| DELTA-only | 1.622× |
| ADAPTIVE | 2.835× |

Trên 256 block của dataset này, detector chọn ZERO cho 99 block, RLE cho 77 block và DELTA cho 80 block.

---

## 10. Đánh giá

### 10.1 Synthesis FPGA

Toàn bộ thiết kế (`fpga_top` gồm cpu_top, accelerator và detector) được synth và implement trên Nexys A7-100T (xc7a100tcsg324-1) bằng Vivado 2025.2, script `synth_phase5.tcl`.

| Tài nguyên | Dùng | Có sẵn | % |
|-----------|------|--------|---|
| Slice LUT | 4066 | 63400 | 6.41% |
| Slice Register (FF) | 2948 | 126800 | 2.32% |
| Block RAM | 0 | 135 | 0% |
| DSP | 0 | 240 | 0% |

Không có BRAM nào được dùng vì cả ba khối nhớ (instruction memory, data memory và scratchpad, mỗi cái 256 word) đều nhỏ và được Vivado suy ra thành distributed LUTRAM.

| Chỉ số | Giá trị |
|--------|---------|
| Clock target | 100 MHz (10.00 ns) |
| WNS (setup) | −1.816 ns |
| Fmax đạt được | 84.6 MHz |
| Path tới hạn | `u_detect`: li → delta_acc (LZC trên hiệu kề), 11.5 ns, 19 logic level |
| Total On-Chip Power | 0.164 W (dynamic 0.066 + static 0.097, confidence Medium) |

### 10.2 Tối ưu detector

Lần synth đầu tiên phơi ra một vấn đề đáng kể. Bản detector ban đầu tính cả ba chỉ số trong một chu kỳ tổ hợp, nghĩa là cần 15 subtractor, 15 khối `sbits` chạy song song cùng một comparator, cộng thêm một buffer riêng để giữ dữ liệu. Kết quả là khối lẽ ra nhỏ nhất lại trở thành khối to nhất trong accelerator, đồng thời nằm trên critical path và kéo Fmax xuống.

Cách sửa là chuyển sang tính tăng dần: thay vì đợi nạp xong rồi tính một lượt, ta cập nhật ba chỉ số ngay khi từng word chảy vào trong N cycle nạp. Như vậy chỉ cần một subtractor và một khối LZC dùng lại 15 lần, và buffer bỏ được hoàn toàn vì detector chỉ sinh ra `det_word` chứ không cần giữ dữ liệu. Latency vẫn giữ nguyên 17 cycle và `det_word` vẫn bit-exact, nên `tb_pattern_detect` vẫn PASS đủ 256 block.

| Chỉ số | Naive (1 cycle tổ hợp) | Streaming (tối ưu) | Cải thiện |
|--------|------------------------|--------------------|-----------|
| Detector LUT | 1690 | 113 | −93% (15×) |
| Detector FF | 565 | 105 | −81% |
| Detector % accelerator | 55% | 7.5% | |
| Detector % toàn CPU | 31% | 2.8% | |
| Accelerator LUT | 3045 | 1514 | −50% |
| System LUT | 5403 | 4066 | −24.7% |
| System FF | 3398 | 2948 | −13.2% |
| Fmax | 45.3 MHz | 84.6 MHz | +87% |
| Latency PDETECT | 17 cyc | 17 cyc | giữ nguyên |
| det_word | — | bit-exact | y hệt |

Phân bổ tài nguyên sau khi tối ưu:

| Khối | LUT | FF |
|------|-----|----|
| `u_cpu` (toàn CPU) | 4039 | 2903 |
| └ `u_accel` | 1514 | 1374 |
| &nbsp;&nbsp;├ `u_zero` | 134 | 58 |
| &nbsp;&nbsp;├ `u_rle` | 285 | 640 |
| &nbsp;&nbsp;├ `u_delta` | 978 | 544 |
| &nbsp;&nbsp;└ `u_detect` | 113 | 105 |

Con số cuối cùng đáng chú ý ở chỗ detector giờ là khối nhỏ nhất trong accelerator, chỉ 113 LUT tương đương 2.8% diện tích CPU. Phản biện dễ gặp nhất với ý tưởng "để phần cứng tự chọn mode" là chi phí của khối detect sẽ ăn hết phần lợi thu được từ việc chọn đúng, và bảng before/after ở trên là câu trả lời định lượng cho phản biện đó. Báo cáo Vivado gốc nằm ở `../BaoCao/phase5_reports/` cho bản sau tối ưu và `../BaoCao/phase5_reports_naive/` cho bản trước.

### 10.3 Ba dataset tương phản

`gen_datasets.py` sinh ba bộ dữ liệu 128 block mỗi bộ, mỗi bộ mô phỏng một loại dữ liệu thật khác nhau:

| Dataset | Đặc tính | Mô phỏng | Detector chọn |
|---------|----------|----------|---------------|
| `zero_heavy` | 1–4 word ≠ 0, còn lại = 0 | feature map TinyML thưa | ZERO = 128/128 |
| `repetitive` | vài run dài | mask, ảnh nhị phân | RLE = 128/128 |
| `slow_varying` | hiệu kề nhỏ [-8,8] | telemetry cảm biến | DELTA = 128/128 |

Trên cả ba bộ, detector chọn đúng mode với tỉ lệ 100%.

### 10.4 Sweep tỉ số nén

`eval_paper.py` chạy mọi tổ hợp dataset và phương pháp. Ratio tính bằng số word gốc chia số word sau nén, nên càng cao càng tốt và dưới 1 nghĩa là dữ liệu phình ra:

| Dataset | RAW | ZERO-only | RLE-only | DELTA-only | ADAPTIVE |
|---------|-----|-----------|----------|------------|----------|
| zero_heavy | 1.000× | 4.541× | 1.356× | 0.941× | 4.541× |
| repetitive | 1.000× | 0.941× | 2.709× | 0.941× | 2.709× |
| slow_varying | 1.000× | 0.941× | 0.513× | 2.667× | 2.667× |
| mixed | 1.000× | 1.274× | 0.949× | 1.622× | 2.835× |

Bảng này nói được ba điều.

Thứ nhất, trên từng dataset thuần, cột ADAPTIVE bằng đúng cột tốt nhất, không hơn không kém. Điều đó xác nhận detector không chọn nhầm và cũng không tốn phí gì về mặt tỉ số nén.

Thứ hai, trên dataset hỗn hợp, ADAPTIVE đạt 2.835× so với 1.622× của mode cố định tốt nhất, hơn 74.8%. Khoảng cách này chỉ xuất hiện khi luồng dữ liệu có nhiều đặc tính trộn lẫn, và đó chính là tình huống thực tế mà một thiết bị edge phải xử lý.

Thứ ba, mọi mode cố định đều làm phình dữ liệu trên ít nhất một dataset. Nặng nhất là RLE-only trên `slow_varying`, tụt xuống 0.513× tức gần gấp đôi kích thước ban đầu. ADAPTIVE không bao giờ xuống dưới 2.667×. Với một hệ thống nhúng thật, việc đảm bảo không bao giờ phình dữ liệu có khi còn quan trọng hơn con số tỉ số nén trung bình.

### 10.5 Throughput đo từ RTL

| Op | Latency (cycle) | out_len (word) |
|----|-----------------|----------------|
| PDETECT | 17 (≈ N+1, không phụ thuộc dữ liệu) | — |
| CCOMPR ZERO | 17 | 5 |
| CCOMPR RLE | 37 | 5 |
| CCOMPR DELTA | 23 | 6 |

Ghép detect và compress lại thành thời gian xử lý trọn một block:

| Mode | detect + compress = total | Throughput |
|------|---------------------------|------------|
| ZERO | 17 + 17 = 34 cycle | 1.882 byte/cycle |
| RLE | 17 + 37 = 54 cycle | 1.185 byte/cycle |
| DELTA | 17 + 23 = 40 cycle | 1.600 byte/cycle |

Đây là số đo trực tiếp từ simulation chứ không phải ước lượng. Để so sánh, một vòng nén viết thuần bằng phần mềm trên cùng lõi này cần khoảng 16 word nhân với vài lệnh mỗi word, cộng thêm load-use stall, ước chừng 140 cycle mỗi block cho zero-suppression, tức accelerator nhanh hơn khoảng 4 lần. Con số software-only chính xác cần đo bằng cách chạy bản nén assembly trên `cpu_top`, và đó là việc còn dang dở.

---

## 11. Cấu trúc file

Repo chỉ chứa source, script và dataset cỡ nhỏ, tổng cộng khoảng 0.8 MB. Các file do Vivado và ModelSim sinh ra, dataset thô 144 MB cùng các bản báo cáo đều nằm ngoài repo; mục 13 nói cách lấy lại chúng.

```
32bit_RISCV/
├── --- RISC-V pipeline (gốc, có mở rộng) ---
│   ├── if_stage.v             IF stage + instruction_memory
│   ├── if_id_reg.v            IF/ID pipeline register
│   ├── id_stage.v             ID stage + RegFile + Decoder      [mở rộng]
│   ├── id_ex_reg.v            ID/EX pipeline register           [mở rộng]
│   ├── ex_stage.v             EX stage + ALU + Branch
│   ├── mem_stage.v            MEM stage + data_mem              [mở rộng]
│   ├── wb_hazard_fwd.v        WB + Hazard unit + Forwarding unit
│   ├── pipeline_regs.v        EX/MEM + MEM/WB registers
│   └── cpu_top.v              Top-level kết nối                 [mở rộng]
│
├── --- Accelerator (thêm mới) ---
│   ├── Compress_accel.v       Dispatcher FSM + điều phối 4 sub-module
│   ├── comp_zero.v            Zero-suppression compressor
│   ├── comp_rle.v             Run-length encoding compressor
│   ├── comp_delta.v           Delta encoding compressor
│   ├── pattern_detect.v       Pattern detector
│   └── scratchpad.v           Dual-port SRAM
│
├── --- FPGA / Nexys A7 ---
│   ├── fpga_top.v             Top-level cơ bản (switch + LED)
│   ├── fpga_top_uart.v        Top-level có UART streaming
│   ├── fpga_top_uart_fastsim.v  Bản baud nhanh để sim UART
│   ├── fpga_top_fmaxtest.v    Wrapper đo Fmax
│   ├── fmaxtest_wrapper.v     Register-ring cách ly I/O khi đo Fmax
│   ├── uart_tx.v              UART transmitter 8N1
│   ├── nexys_a7.xdc           Constraints cơ bản
│   └── nexys_a7_uart.xdc      Constraints có UART
│
├── --- Testbench ---
│   ├── tb_if_stage.v  tb_id_stage.v  tb_ex_stage.v  tb_mem_stage.v
│   │                          Unit test từng pipeline stage
│   ├── tb_cpu_top.v           Smoke test toàn core
│   ├── tb_comp_zero.v  tb_comp_rle.v  tb_comp_delta.v
│   │                          Unit test 3 compressor (so với golden)
│   ├── tb_pattern_detect.v    Unit test detector
│   ├── tb_compress_top.v      So golden qua dispatcher, 3 mode × 256 block
│   ├── tb_demo_pipeline.v     Integration end-to-end (detect, chọn, nén)
│   ├── tb_demo_sparse.v       Integration trên dữ liệu thưa
│   ├── tb_throughput.v        Đo throughput cycle-accurate
│   ├── tb_cyc_display.v       In cycle count từng mode
│   ├── tb_sw_baseline.v       Baseline nén thuần software trên core
│   ├── tb_lec_baseline.v      Baseline LEC để so thuật toán khác
│   ├── tb_uart_tx.v           Unit test UART TX
│   └── tb_fpga_top_uart.v     Integration FPGA top + UART
│
├── --- Golden model và sinh dữ liệu ---
│   ├── golden_compress.py     Golden model: 3 mode, detector, giải nén, round-trip
│   ├── gen_demo.py            Sinh demo_src.hex và demo_expected_dest.hex
│   ├── gen_datasets.py        Sinh 3 dataset tổng hợp tương phản
│   ├── gen_real_datasets.py   Cắt dataset thật thành real_*.hex (bản nhỏ, có trong repo)
│   └── gen_real_datasets_full.py  Sinh real_*_full.hex từ data.txt (không có trong repo)
│
├── --- Assembler và evaluation ---
│   ├── asm_riscv.py           Assembler Python cho demo_pipeline (cách 2, không cần GCC)
│   ├── asm_sw_baseline.py     Sinh chương trình baseline software
│   ├── asm_lec_baseline.py    Sinh chương trình baseline LEC
│   ├── asm_uart_demo.py       Sinh chương trình demo UART
│   ├── eval_paper.py          Sweep tỉ số nén chính dùng cho paper
│   ├── eval_baselines.py      So sánh với gzip, zlib, LEC
│   ├── eval_composability.py  Đánh giá khả năng ghép nhiều mode
│   ├── eval_lec_winner.py     Phân tích các trường hợp LEC thắng
│   └── read_uart_demo.py      Đọc stream UART từ board qua cổng COM
│
├── --- Lớp phần mềm ---
│   ├── compress_api.h         Wrapper C cho 3 lệnh custom
│   └── demo_pipeline.c        Demo end-to-end -- entry point la c_entry(), goi tu crt0.S
│
├── --- Toolchain RISC-V GCC (thêm mới, nhánh feature/gcc-toolchain) ---
│   ├── link.ld                 Linker script: tách vùng PROGRAM/DATA khớp if_stage.v/mem_stage.v
│   ├── crt0.S                  Khởi động: gán sp, xóa .bss, nhảy vào c_entry()
│   └── Makefile                 `make CROSS=<prefix-> clean all` -> demo_pipeline.hex
│
├── --- Script chạy tự động ---
│   ├── run_modelsim.do        Chạy tb_cpu_top
│   ├── run_modelsim_unit.do   Chạy riêng unit test
│   ├── run_modelsim_lec.do    Chạy riêng baseline LEC
│   ├── run_modelsim_all.do    Chạy tuần tự CẢ 18 testbench trong 1 lệnh
│   ├── synth_phase5.tcl       Vivado: synth, impl và xuất report
│   ├── synth_paper.tcl        Vivado: build cấu hình dùng trong paper
│   ├── synth_uart_demo.tcl    Vivado: build bản demo UART
│   └── synth_fmaxtest.tcl     Vivado: quét Fmax
│
├── --- Dataset nhỏ (có trong repo) ---
│   ├── dataset_zero_heavy.hex  dataset_repetitive.hex  dataset_slow_varying.hex
│   │                          3 dataset tổng hợp tương phản
│   ├── real_temp.hex  real_volt.hex  real_light.hex  real_mixed.hex
│   │                          Dataset thật đã cắt, 20K word mỗi file
│   ├── tb_src_mixed.hex       Dataset nguồn 256 block hỗn hợp
│   ├── tb_expected_zero_mixed.hex   Golden output mode ZERO
│   ├── tb_expected_rle_mixed.hex    Golden output mode RLE
│   ├── tb_expected_delta_mixed.hex  Golden output mode DELTA
│   ├── tb_expected_detect_mixed.hex Golden det_word cho 256 block
│   ├── demo_src.hex           3 block tương phản làm nguồn cho demo
│   ├── demo_expected_dest.hex Golden output của demo
│   └── uart_demo_src.hex      Nguồn cho demo UART
│
├── --- Program image (sinh từ assembler) ---
│   ├── mem_program.hex        Chương trình cho cpu_top
│   ├── demo_pipeline.hex      Chương trình demo end-to-end
│   ├── sw_baseline.hex        Chương trình baseline software
│   ├── lec_baseline.hex       Chương trình baseline LEC
│   └── uart_demo.hex          Chương trình demo UART
│
├── --- Kết quả đo ---
│   ├── eval_paper_sweep.csv        Bảng sweep tỉ số nén đầy đủ
│   ├── eval_paper_policy.csv       So sánh các chính sách chọn mode
│   ├── eval_baselines_results.csv  Kết quả so với gzip, zlib, LEC
│   ├── real_result.csv             Mode và ratio từng block trên dataset thật
│   ├── dfx_runtime.txt             Thời gian reconfig lúc chạy
│   ├── tight_setup_hold_pins.txt   Các pin có setup/hold sát ngưỡng
│   └── demo_expected.txt           Output mong đợi của demo
│
└── --- Khác ---
    ├── arch_flow.svg          Sơ đồ kiến trúc
    ├── README.md              File này
    └── .gitignore             Loại file build và dataset lớn khỏi git
```

---

## 12. Chạy simulation

Toolchain dùng trong dự án là ModelSim Intel FPGA Edition 2020.1.

**Phân biệt 2 nơi gõ lệnh (hay nhầm):**
- `make ...`, `python ...`, `riscv32-unknown-elf-gcc ...` — gõ trong **terminal thường** (Git Bash/cmd/PowerShell), *không* mở ModelSim. Đây là bước sinh file `.hex`/dataset, làm xong trước khi mở ModelSim.
- `vlog ...`, `vsim ...`, `do ...` — 2 cách:
  - Nếu đã **mở ModelSim GUI** sẵn: gõ *không* có chữ `vsim` ở đầu, ngay trong ô **Transcript** — ví dụ `do run_modelsim_all.do` (không phải `vsim -do run_modelsim_all.do`, vì `vsim` chính là chương trình đang chạy rồi).
  - Nếu gõ thẳng từ **terminal thường** (chưa mở GUI): phải có tiền tố `vsim -c -do ...` — ModelSim sẽ tự chạy ở chế độ dòng lệnh (không hiện cửa sổ), in thẳng kết quả ra ngay terminal đó chứ không phải ra Transcript của GUI.

### Bước 0 — sinh dữ liệu

```bash
python golden_compress.py      # sinh tb_expected_*_mixed.hex và in tỉ số nén
python gen_demo.py             # sinh demo_src.hex, demo_expected_dest.hex
```

`demo_pipeline.hex` (chương trình cho testbench tích hợp) có thể sinh bằng 1 trong 2 cách:

**Cách A — RISC-V GCC thật (nhánh `feature/gcc-toolchain`):**

```bash
make CROSS=riscv32-unknown-elf- clean all
```

Trong đó `CROSS` là tiền tố tên bộ 3 công cụ GCC/binutils cài trên máy bạn (ví dụ nếu lệnh `gcc` của bạn tên `riscv32-unknown-elf-gcc` thì gõ đúng như trên; nếu tên khác — ví dụ `riscv64-unknown-elf-gcc` — thì đổi `CROSS=riscv64-unknown-elf-`). Makefile sẽ tự chạy 2 bước:

1. `riscv32-unknown-elf-gcc ... crt0.S demo_pipeline.c -o demo_pipeline.elf` — biên dịch + liên kết theo bản đồ bộ nhớ trong `link.ld`.
2. `riscv32-unknown-elf-objcopy -O verilog --verilog-data-width=4 --reverse-bytes=4 demo_pipeline.elf demo_pipeline.hex` — xuất ra đúng định dạng 1 word 32-bit/dòng mà `$readmemh` cần (2 cờ `--verilog-data-width=4 --reverse-bytes=4` **bắt buộc phải có** — thiếu 1 trong 2 cờ này sẽ ra file `.hex` sai hoàn toàn, xem chú thích trong `Makefile`).

Muốn xem chương trình build ra bao nhiêu byte lệnh (giới hạn 1KB) hoặc xem lại mã máy: `make size` / `make disasm`.

> **Lỗi `bash: make: command not found` (hay gặp trên Git Bash/MINGW64 của Windows):** bản Git for Windows mặc định không cài sẵn `make`. Có 2 hướng xử lý:
>
> - **Không cần cài gì thêm — gõ tay đúng 2 lệnh mà Makefile chạy bên trong:**
>   ```bash
>   riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
>       -mno-relax -Wall -Wextra -ffunction-sections -fdata-sections \
>       -T link.ld -nostdlib -Wl,--no-relax -Wl,--gc-sections \
>       crt0.S demo_pipeline.c -o demo_pipeline.elf
>   riscv32-unknown-elf-objcopy -O verilog --verilog-data-width=4 --reverse-bytes=4 \
>       demo_pipeline.elf demo_pipeline.hex
>   ```
>   (đổi `riscv32-unknown-elf-` thành đúng tiền tố toolchain trên máy bạn ở cả 2 dòng lệnh). Đây chính xác là 2 lệnh `make` gọi ngầm — chỉ khác là bạn gõ tay thay vì để `make` gõ giúp.
> - **Cài `make` để dùng `Makefile` cho tiện về sau** — chọn 1 trong các cách sau (không cần làm hết, máy hầu hết sinh viên chỉ có Git Bash trơn nên **không có sẵn** `choco`/`scoop`/`pacman` — nếu vậy dùng cách GnuWin32 bên dưới, không cần cài package manager trước):
>   - **GnuWin32 (không cần cài package manager trước, khuyên dùng nếu máy chỉ có Git Bash trơn):** tải `make` tại http://gnuwin32.sourceforge.net/packages/make.htm (mục "Binaries" -> file `.zip` hoặc `.exe` cài đặt), cài/giải nén xong sẽ có file `make.exe` (thường nằm trong `...\GnuWin32\bin`). Thêm đường dẫn thư mục `bin` đó vào biến môi trường `PATH` của Windows (Settings -> System -> About -> Advanced system settings -> Environment Variables -> sửa biến `Path`, thêm dòng mới trỏ tới thư mục chứa `make.exe`), rồi **mở lại** cửa sổ Git Bash (bắt buộc, để nó đọc `PATH` mới) và gõ `make --version` để kiểm tra đã nhận lệnh chưa.
>   - `choco install make` — nếu máy đã cài sẵn Chocolatey.
>   - `scoop install make` — nếu máy đã cài sẵn Scoop.
>   - `pacman -S make` — nếu bạn cài MSYS2 đầy đủ riêng (không phải chỉ Git Bash đi kèm Git for Windows).

**Cách B — assembler Python (không cần cài GCC):**

```bash
python asm_riscv.py            # sinh demo_pipeline.hex
```

Cả 2 cách đều ra cùng 1 định dạng file, dùng thay thế cho nhau được — các bước chạy testbench bên dưới không đổi dù bạn chọn cách nào. Lưu ý duy nhất: nếu dùng cách A và có sửa/thêm biến toàn cục trong `demo_pipeline.c`, địa chỉ của `mode_log[]`/`len_log[]` trong bộ nhớ có thể đổi (do trình liên kết tự sắp xếp) — kiểm tra lại bằng `nm demo_pipeline.elf | grep -E "mode_log|len_log"` rồi cập nhật `MODE_BASE`/`LEN_BASE` trong `tb_demo_pipeline.v` và `tb_demo_sparse.v` cho khớp.

### Bảng toàn bộ testbench

Danh sách `.v` cần `vlog` (giữ đúng thứ tự) và cách đọc kết quả PASS/FAIL cho từng testbench:

| Testbench | File `.v` cần vlog thêm | Lệnh `vsim` | Cách đọc kết quả |
|---|---|---|---|
| `tb_if_stage`, `tb_id_stage`, `tb_ex_stage`, `tb_mem_stage` | `if_stage.v id_stage.v ex_stage.v mem_stage.v if_id_reg.v id_ex_reg.v pipeline_regs.v wb_hazard_fwd.v` | `vsim -c tb_if_stage -do "run -all; quit -f"` (đổi tên cho 3 file còn lại) | Mỗi dòng in `PASS [tên_test]` hoặc `FAIL [tên_test]`. Không có dòng `FAIL` nào là qua hết. |
| `tb_cpu_top` | như trên + `scratchpad.v comp_zero.v comp_rle.v comp_delta.v pattern_detect.v Compress_accel.v cpu_top.v` | `vsim -c tb_cpu_top -do "run -all; quit -f"` | Cuối log in `Total: N PASS, 0 FAIL` và `** ALL TESTS PASSED **`. Có số `FAIL` > 0 là có lỗi. |
| `tb_comp_zero` / `tb_comp_rle` / `tb_comp_delta` | `comp_zero.v scratchpad.v` (đổi tên module cho rle/delta) | `vsim -c tb_comp_zero -do "run -all; quit -f"` | Dòng cuối `[PASS] ... matches golden model` hoặc `[FAIL] so loi = N`. |
| `tb_pattern_detect` | `pattern_detect.v` | `vsim -c tb_pattern_detect -do "run -all; quit -f"` | `[PASS] pattern_detect matches golden ...` hoặc `[FAIL] so loi = N / 256 block`. |
| `tb_compress_top` | `comp_zero.v comp_rle.v comp_delta.v pattern_detect.v Compress_accel.v scratchpad.v` | `vsim -c tb_compress_top -do "run -all; quit -f"` | `[PASS] RTL compress (via CCOMPR dispatcher) == golden for all 3 modes` hoặc `[FAIL] tong loi = N`. |
| `tb_demo_pipeline` | `if_stage.v id_stage.v ex_stage.v mem_stage.v if_id_reg.v id_ex_reg.v pipeline_regs.v wb_hazard_fwd.v scratchpad.v comp_zero.v comp_rle.v comp_delta.v pattern_detect.v Compress_accel.v cpu_top.v` | `vsim -c tb_demo_pipeline -do "run -all; quit -f"` | `[MODE OK]` x3 + `[PASS] HW/SW detect->select->compress loop runs correctly on the core`. Bất kỳ dòng `FAIL` nào (MODE/LEN/DEST) là có lỗi. |
| `tb_demo_sparse` | như `tb_demo_pipeline` | `vsim -c tb_demo_sparse -do "run -all; quit -f"` | `[PASS] Runs correctly with SPARSE clk_en -> NO hang.` — kiểm tra không bị treo khi `clk_en` thưa (giống điều kiện thật trên board). |
| `tb_cyc_display` | như `tb_demo_pipeline` | `vsim -c tb_cyc_display -do "run -all; quit -f"` | Không có PASS/FAIL tự động — in `Block i: cyc_lat = N`, tự so bằng mắt với dòng `[DONE] expected: 17 (ZERO), 37 (RLE), 23 (DELTA)`. |
| `tb_sw_baseline` | như `tb_demo_pipeline` | `vsim -c tb_sw_baseline -do "run -all; quit -f"` | `[PASS] SW output MATCHES golden (same format as HW) -> cycle counts are valid.` |
| `tb_lec_baseline` | như `tb_demo_pipeline` (chạy `python asm_lec_baseline.py` trước để sinh `lec_baseline.hex`) | `vsim -c tb_lec_baseline -do "run -all; quit -f"` | `[PASS] SW output MATCHES the golden LEC bit-cost model -> cycle count is valid.` |
| `tb_uart_tx` | `uart_tx.v` | `vsim -c tb_uart_tx -do "run -all; quit -f"` | `[PASS] uart_tx sent 4/4 bytes correctly` hoặc `[FAIL] N loi.` |
| `tb_fpga_top_uart` | `uart_tx.v fpga_top_uart_fastsim.v` + toàn bộ file của `tb_demo_pipeline` (chạy `python asm_uart_demo.py` trước để sinh `uart_demo.hex`) | `vsim -c tb_fpga_top_uart -do "run -all; quit -f"` | `[PASS] UART sent correct mode+out_len for all 14 REAL data blocks` hoặc `[FAIL] N loi.` |
| `tb_throughput` | như `tb_demo_pipeline` (không cần `cpu_top.v`) | `vsim -c tb_throughput -do "run -all; quit -f"` | Không có PASS/FAIL — in bảng cycle/throughput từng mode, đọc bằng mắt, kết thúc bằng `[DONE]`. |

Với mọi testbench: nếu log dừng giữa chừng và in `[TIMEOUT]` thay vì PASS/FAIL, nghĩa là mạch bị treo (không tới điểm kiểm tra) — đây luôn là lỗi, kể cả khi không có dòng `FAIL` nào.

Muốn chạy một lượt thay vì gõ từng lệnh:
- `run_modelsim.do` — riêng `tb_cpu_top` (đã vá thêm 6 module accelerator còn thiếu trong danh sách `vlog`).
- `run_modelsim_unit.do` — riêng 4 testbench unit stage (`tb_if_stage`/`tb_id_stage`/`tb_ex_stage`/`tb_mem_stage`).
- `run_modelsim_lec.do` — riêng `tb_lec_baseline`.
- **`run_modelsim_all.do` — chạy tuần tự CẢ 18 testbench trong 1 lệnh duy nhất:**
  ```bash
  vsim -c -do run_modelsim_all.do
  ```
  (hoặc `do run_modelsim_all.do` nếu gõ trong cửa sổ ModelSim GUI). Script tự biên dịch toàn bộ `.v` + `tb_*.v` một lần, rồi chạy từng testbench, in `===== <tên tb> =====` trước mỗi khối và `----- HET <tên tb> -----` sau khi xong — cuộn Transcript lên, đối chiếu từng khối với cột "Cách đọc kết quả" ở bảng trên để biết khối nào PASS/FAIL. Trước khi chạy, đảm bảo các file `.hex` cần thiết đã có sẵn (đã có sẵn trong repo; chỉ cần sinh lại — xem đầu file `run_modelsim_all.do` — nếu bạn vừa sửa code nguồn tương ứng).

**Kiểm tra chéo bằng golden model / round-trip:**

```bash
python golden_compress.py --roundtrip
python gen_datasets.py        # sinh 3 dataset tương phản
python eval_paper.py          # bảng sweep tỉ số nén, ghi ra eval_paper_sweep.csv
```

---

## 13. Dữ liệu lớn và cách tái tạo

Repo không chứa dataset thô và các file hex đầy đủ vì chúng vượt giới hạn của GitHub (100 MB mỗi file, và thực tế nên giữ dưới 50 MB). Tất cả đều sinh lại được bằng script có sẵn.

### Lấy `data.txt`

Đây là bộ Intel Berkeley Research Lab Sensor Data thu năm 2004, gồm khoảng 2.3 triệu bản ghi từ 54 cảm biến đo nhiệt độ, độ ẩm, ánh sáng và điện áp, mỗi 31 giây trong khoảng một tháng. Tải `data.txt.gz` tại <http://db.csail.mit.edu/labdata/labdata.html>, giải nén rồi đặt `data.txt` vào thư mục gốc của repo.

Mỗi dòng có tám trường cách nhau bằng dấu cách:

```
date time epoch moteid temperature humidity light voltage
2004-02-28 00:59:16.02785 3 1 19.9884 37.0933 45.08 2.69964
```

### Sinh lại file hex từ dataset thật

```bash
# Bản nhỏ đã có sẵn trong repo, chỉ chạy nếu muốn sinh lại
python gen_real_datasets.py        # real_temp.hex, real_volt.hex, real_light.hex, real_mixed.hex

# Bản đầy đủ, cần data.txt ở trên
python gen_real_datasets_full.py   # real_*_full.hex, tổng khoảng 22 MB
```

| File | Kích thước | Trong repo | Sinh bằng |
|------|-----------|------------|-----------|
| `data.txt` | 144 MB | không | tải từ MIT CSAIL |
| `real_*.hex` | 80 KB × 4 | có | `gen_real_datasets.py` |
| `real_temp/volt/light_full.hex` | 3.6 MB × 3 | không | `gen_real_datasets_full.py` |
| `real_mixed_full.hex` | 11 MB | không | `gen_real_datasets_full.py` |

Mọi kết quả trong paper tái lập được chỉ với các file `real_*.hex` bản nhỏ. Bản `_full` chỉ dùng để kiểm chứng rằng tỉ số nén không đổi khi chạy trên dataset đầy đủ.

### Sinh lại dataset tổng hợp và program image

```bash
python golden_compress.py    # tb_expected_*_mixed.hex
python gen_datasets.py       # dataset_zero_heavy/repetitive/slow_varying.hex
python gen_demo.py           # demo_src.hex, demo_expected_dest.hex
python asm_riscv.py          # demo_pipeline.hex
python asm_sw_baseline.py    # sw_baseline.hex
python asm_lec_baseline.py   # lec_baseline.hex
python asm_uart_demo.py      # uart_demo.hex
```

### File build bị `.gitignore` loại bỏ

Các thư mục `RISC_V/`, `project_1/`, `.Xil/`, `work/` cùng `vivado.log`, `vivado.jou`, `transcript`, `modelsim.ini` và `__pycache__/` đều là sản phẩm của công cụ, không phải source. Chúng có thể xóa bất cứ lúc nào và sinh lại bằng cách chạy Vivado hoặc ModelSim theo mục 12.

---

## Ghi chú kỹ thuật

Một vài chi tiết dễ gây vướng khi đọc code hoặc khi tiếp tục phát triển.

`buf` là từ khóa dành riêng trong ModelSim, nên mọi buffer nội bộ trong dự án đặt tên là `wbuf`. Đây là lỗi biên dịch khá khó đoán nếu gặp lần đầu.

Tham số `AW` khác nhau giữa hai ngữ cảnh: trong `cpu_top` là 8, tương ứng scratchpad 256 word; trong testbench standalone là 13, tức 8192 word. Testbench cần vùng lớn hơn vì đầu ra của RLE trên 256 block có thể vượt quá 4096 word.

Pipeline không stall theo `custom_busy`, phần mềm tự poll CSTAT. Cách này đã verify là đủ đúng, nhưng nếu cần một handshake thật thì chỗ phải sửa là `hazard_unit`.

Máy phát triển không có RISC-V GCC nên `asm_riscv.py` đảm nhiệm việc dịch assembly. File `demo_pipeline.c` giữ lại làm bản tham chiếu cho ai có sẵn toolchain đầy đủ.
