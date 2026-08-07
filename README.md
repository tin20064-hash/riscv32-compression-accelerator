# RISC-V 32-bit 5-Stage Pipeline + Custom Compression Accelerator

Đề tài Q2: **Pattern-Aware Domain-Specific Compression Accelerator with Custom RISC-V Instruction**

---

## Mục lục

1. [Tổng quan kiến trúc](#1-tổng-quan-kiến-trúc)
2. [RISC-V ISA — Nền tảng](#2-risc-v-isa--nền-tảng)
3. [Pipeline 5 giai đoạn](#3-pipeline-5-giai-đoạn)
4. [Hazard Handling](#4-hazard-handling)
5. [Forwarding](#5-forwarding)
6. [Những gì được THÊM VÀO so với RISC-V gốc](#6-những-gì-được-thêm-vào-so-với-risc-v-gốc)
   - 6.1 [Custom Opcode Decoder](#61-thêm-1--custom-opcode-decoder-trong-id_stagev)
   - 6.2 [Pipeline Register mở rộng](#62-thêm-2--pipeline-register-mở-rộng)
   - 6.3 [Mux kết quả tại EX](#63-thêm-3--mux-kết-quả-tại-ex-stage)
   - 6.4 [Scratchpad](#64-thêm-4--scratchpad-bộ-nhớ-dùng-chung-hwsw)
   - 6.5 [compress_accel — Bộ điều phối](#65-thêm-5--compress_accelv-bộ-điều-phối-chính)
   - 6.6 [comp_zero — Zero-Suppression](#66-thêm-6--comp_zerov-nén-zero-suppression)
   - 6.7 [comp_rle — Run-Length Encoding](#67-thêm-7--comp_rlev-nén-run-length-encoding)
   - 6.8 [comp_delta — Delta Encoding](#68-thêm-8--comp_deltav-nén-delta-encoding)
   - 6.9 [pattern_detect — Phát hiện mẫu (NOVELTY)](#69-thêm-9--pattern_detectv-phát-hiện-mẫu-novelty)
   - 6.10 [Wiring trong cpu_top](#610-thêm-10--wiring-trong-cpu_topv)
   - 6.11 [Software Layer](#611-thêm-11--software-layer-hwsw-co-design)
7. [Custom Instruction Encoding](#7-custom-instruction-encoding)
8. [HW/SW Co-Design Flow](#8-hwsw-co-design-flow)
9. [Kết quả Verification](#9-kết-quả-verification)
10. [Đánh giá — Evaluation (GĐ6)](#10-đánh-giá--evaluation-gđ6)
11. [Cấu trúc file](#11-cấu-trúc-file)
12. [Chạy Simulation (ModelSim)](#12-chạy-simulation-modelsim)
13. [Dữ liệu lớn — cách tái tạo](#13-dữ-liệu-lớn--cách-tái-tạo)
14. [Các file KHÔNG nằm trong repo](#14-các-file-không-nằm-trong-repo)
15. [Đưa dự án lên GitHub](#15-đưa-dự-án-lên-github)

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

**Điểm novelty:** Thay vì người lập trình chọn mode nén, module `pattern_detect` **tự đo** đặc tính dữ liệu và chọn mode tốt nhất mỗi block → ADAPTIVE = **2.835×** vs fixed tốt nhất (DELTA-only) = 1.622×.

---

## 2. RISC-V ISA — Nền tảng

### Thanh ghi

32 thanh ghi **x0–x31**, mỗi cái 32-bit. `x0` luôn = 0, không ghi được (hardware enforce tại `id_stage.v:63`).

### 6 định dạng lệnh (tất cả 32-bit fixed-width)

| Format | Cấu trúc bits | Dùng cho |
|--------|--------------|----------|
| R-type | `[funct7\|rs2\|rs1\|funct3\|rd\|opcode]` | ALU register-register |
| I-type | `[imm12\|rs1\|funct3\|rd\|opcode]` | ADDI, LW, JALR |
| S-type | `[imm[11:5]\|rs2\|rs1\|funct3\|imm[4:0]\|opcode]` | SW |
| B-type | `[imm[12,10:5]\|rs2\|rs1\|funct3\|imm[4:1,11]\|opcode]` | BEQ, BNE |
| U-type | `[imm20\|rd\|opcode]` | LUI, AUIPC |
| J-type | `[imm[20,10:1,11,19:12]\|rd\|opcode]` | JAL |

**Lưu ý immediate encoding:** B và J type có các bit immediate bị xáo trộn để giữ `rd`, `rs1` cùng vị trí giữa các format — tiết kiệm mux trong silicon. Xem `id_stage.v:72–97` để xem cách assembly lại.

### Tập lệnh hỗ trợ

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

Một lệnh đi qua 5 giai đoạn tuần tự, mỗi giai đoạn 1 clock. 5 lệnh khác nhau chạy song song:

```
Cycle:   1    2    3    4    5    6    7
Lệnh 1: [IF] [ID] [EX] [M]  [WB]
Lệnh 2:      [IF] [ID] [EX] [M]  [WB]
Lệnh 3:           [IF] [ID] [EX] [M]  [WB]
```

### IF — `if_stage.v`

- **PC register** 32-bit: mỗi clock tăng +4 (word-aligned).
- Đọc `instruction_memory` bằng `pc[9:2]` (8-bit word addr → 256 lệnh tối đa).
- `next_pc` đến từ `branch_target_ex` (khi branch/jump) hoặc `pc+4`.
- `stall_if=1` → PC không thay đổi (freeze, fetch lại lệnh cũ).

### ID — `id_stage.v`

Làm 2 việc song song:

**a) Register File read** (32×32-bit, đọc async/combinational):
```
rs1_data = (rs1==0) ? 0 : (WB đang ghi rd==rs1) ? write_data : regfile[rs1]
```
WB bypass ngay tại ID tránh 1 cycle stall.

**b) Control signal decode** (combinational từ opcode):
```
reg_write   — cho phép WB ghi register
alu_src     — ALU in2 từ imm (1) hay rs2 (0)
alu_ctrl    — phép tính ALU (4-bit)
mem_read    — đọc data memory
mem_write   — ghi data memory
mem_to_reg  — WB chọn read_data thay vì ALU result
branch      — lệnh branch
jump        — JAL/JALR
custom_en   — kích accelerator (THÊM MỚI)
custom_op   — PDETECT/CCOMPR/CSTAT (THÊM MỚI)
```

### EX — `ex_stage.v`

- **ALU**: ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU/LUI (4-bit `alu_ctrl`).
- **AUIPC**: `alu_opA_sel=1` → ALU input A = PC (không phải rs1).
- **Branch resolution**: so sánh `rs1` vs `rs2` → `branch_taken`.
- **Branch target**: `pc_ex + imm_ex`. JALR: `(rs1 + imm) & ~1` (clear bit 0).
- **Custom mux** (THÊM MỚI):
  ```verilog
  assign ex_writeback_result = custom_en_ex ? custom_result_ex : alu_result_ex;
  ```

### MEM — `mem_stage.v`

- `data_mem[0:255]` — 256 word bộ nhớ dữ liệu thông thường.
- **Address decode** (THÊM MỚI): `address[12]=1` → scratchpad, `=0` → data_mem.
- Sub-word store: SB/SH dùng `byte_en` mask và `aligned_wdata` (replicate byte/halfword).
- Load sign-extension: LB sign-extend 8→32 bit; LBU zero-extend.

### WB — `wb_stage` trong `wb_hazard_fwd.v`

```
jump=1       → pc+4  (JAL/JALR lưu return address)
mem_to_reg=1 → read_data  (kết quả LW)
else         → alu_result
```

### Pipeline Registers

| Register | Nội dung chính |
|----------|---------------|
| IF/ID | pc, pc+4, instruction |
| ID/EX | rs1_data, rs2_data, imm, tất cả control signals + **custom_en/op** |
| EX/MEM | alu_result, rs2_data, pc+4, reg_write, funct3 |
| MEM/WB | alu_result, read_data, pc+4, reg_write |

Tất cả có `rst_n` (async reset) và `clk_en` (freeze toàn pipeline).

---

## 4. Hazard Handling

### Data hazard — Load-Use

LW ở EX, lệnh ngay sau cần kết quả → phải chờ 1 cycle:
```verilog
// wb_hazard_fwd.v:19
load_use_hazard = mem_read_ex && (rd_addr_ex != 0) &&
                  (rd_addr_ex == rs1_addr_id || rd_addr_ex == rs2_addr_id)
```
Khi detect: `stall_if=1`, `stall_id=1`, `flush_id=1` (chèn bubble NOP vào EX).

### Control hazard — Branch/Jump

Branch taken biết ở EX — 2 lệnh sau đã vào IF/ID sai:
```
flush_if=1  → xóa lệnh đang trong IF
flush_id=1  → xóa lệnh đang trong ID
```
Penalty = 2 cycles mỗi lần branch taken.

---

## 5. Forwarding

Hầu hết data hazard (không phải load-use) giải quyết bằng forward kết quả từ stage sau về EX — không cần stall:

```
fwd_a = 2'b10 → ALU result từ EX/MEM reg  (1 cycle cũ)
fwd_a = 2'b01 → write_data từ MEM/WB reg  (2 cycle cũ)
fwd_a = 2'b00 → từ ID/EX reg              (bình thường)
```

Priority: MEM > WB > bình thường (kiểm tra `rd_addr_mem` trước).

```asm
add x1, x2, x3   # EX: tính x1
add x4, x1, x5   # EX cần x1 → forward từ EX/MEM, không stall!
```

---

## 6. Những gì được THÊM VÀO so với RISC-V gốc

### 6.1 Thêm 1 — Custom Opcode Decoder trong `id_stage.v`

```verilog
localparam OPC_CUSTOM0 = 7'b0001011;  // = 0x0B (custom-0 theo RISC-V spec)
localparam PDETECT = 3'b000;
localparam CCOMPR  = 3'b001;
localparam CSTAT   = 3'b010;

OPC_CUSTOM0: begin
    custom_en_r = 1'b1;
    custom_op_r = funct3;      // funct3 phân biệt 3 lệnh
    case (funct3)
        PDETECT: reg_write_r = 1'b1;  // trả det_word về rd
        CSTAT:   reg_write_r = 1'b1;  // trả status_word về rd
        CCOMPR:  reg_write_r = 1'b0;  // không ghi (rd=x0)
    endcase
end
```

CCOMPR không ghi regfile vì chỉ kick accelerator — kết quả lấy sau qua CSTAT poll.

### 6.2 Thêm 2 — Pipeline Register mở rộng

`id_ex_reg` trong `pipeline_regs.v` thêm 2 field mới:
```verilog
input  wire        custom_en_in,
input  wire [2:0]  custom_op_in,
output reg         custom_en_out,
output reg  [2:0]  custom_op_out,
```
Chỉ qua ID/EX (không cần qua EX/MEM) vì accelerator kết nối tại stage EX.

### 6.3 Thêm 3 — Mux kết quả tại EX stage

```verilog
// cpu_top.v:269
assign ex_writeback_result = custom_en_ex ? custom_result_ex : alu_result_ex;
```
Khi `custom_en_ex=1`, kết quả accelerator thay thế ALU result vào pipeline. `custom_result_ex` trả về **ngay trong cùng cycle** (combinational) — CSTAT trả status_word, PDETECT trả det_word.

### 6.4 Thêm 4 — Scratchpad: Bộ nhớ dùng chung HW/SW

File `scratchpad.v` — **hoàn toàn mới**. Lý do: accelerator không thể dùng `data_mem` của MEM stage mà không làm phức tạp arbitration.

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

**Address decode** trong `mem_stage.v`:
```
address[12] = 0  →  data_mem  (0x0000–0x03FC)
address[12] = 1  →  scratchpad (0x1000–0x13FC)
word_addr = address[9:2]  (byte addr ÷ 4)
```

**Vùng địa chỉ dự án:**
```
scratchpad[0..47]    = 3 block nguồn (3×16 word = demo_src.hex)
scratchpad[48..63]   = kết quả nén block 0 (ZERO, 5 word)
scratchpad[64..68]   = kết quả nén block 1 (RLE, 5 word)
scratchpad[69..74]   = kết quả nén block 2 (DELTA, 6 word)
```

### 6.5 Thêm 5 — `compress_accel.v`: Bộ điều phối chính

File `Compress_accel.v` — **hoàn toàn mới**. Chứa 4 sub-module và điều phối chúng.

**Tín hiệu vào:** `custom_en`, `custom_op`, `op_a=fwd_rs1_ex`, `op_b=fwd_rs2_ex`
> `op_a/op_b` lấy từ **forwarded** value — luôn nhận giá trị đúng nhất, kể cả khi forward từ MEM/WB.

**Tách tham số từ op_b:**
```
CCOMPR:  src_word  = op_a[AW+1:2]    (byte→word: ÷4)
         dest_word = op_b[AW+1:2]
         req_mode  = op_b[1:0]        ← mode nhét vào 2 bit thấp của địa chỉ
PDETECT: tau1 = op_b[5:0]   (0 → dùng TAU1_DEF=8)
         tau2 = op_b[13:8]
         wmax = op_b[21:16]
```

**Signal START cho sub-module:**
```verilog
wire start_z = (state==S_IDLE) & ccompr_cmd & (req_mode==2'b00) & clk_en;
wire start_r = (state==S_IDLE) & ccompr_cmd & (req_mode==2'b01) & clk_en;
wire start_d = (state==S_IDLE) & ccompr_cmd & (req_mode==2'b10) & clk_en;
wire start_p = (state==S_IDLE) & pdetect_cmd & clk_en;
```
Chỉ đúng 1 sub-module nhận `start=1` tại mỗi thời điểm.

**FSM 2 state:**
```
S_IDLE: chờ CCOMPR/PDETECT → S_RUN
S_RUN:  chờ sub-module done → latch last_result, last_op → done_r=1 → S_IDLE
```

**CSTAT word:**
```
bit[31] = busy
bit[30] = done    ← SW poll cái này
bit[29] = err
bit[28] = last_op  (0=compress → last_result=out_len; 1=detect → last_result=det_word)
bit[27:0] = last_result
```

### 6.6 Thêm 6 — `comp_zero.v`: Nén Zero-Suppression

**Ý tưởng:** Block có nhiều word=0 → lưu bitmap 16-bit + chỉ các word khác 0.

**Format output:**
```
Word 0 (header): {14'b0, 00, bitmap[15:0]}   mode=00 ở bit[17:16]
Word 1..K:        các word non-zero theo thứ tự
out_len = 1 + K   (K = số word ≠ 0)
```

**FSM 3 state** (`S_IDLE → S_STREAM → S_HEADER`):
- `S_STREAM`: đọc từng word async (mỗi cycle 1 word). Nếu word≠0: ghi dest, set `bitmap[idx]`, `wptr++`.
- `S_HEADER`: ghi header vào `dest[0]`, báo done.

**Trick async read:** `rd_addr = src_base_r + idx` là wire tổ hợp → `rd_data` sẵn sàng ngay trong cùng cycle → N+2 cycles tổng.

**Ví dụ:** `[0,0,A,0,B,0,...,C,0]` (A,B,C non-zero ở vị trí 2,4,14)
```
bitmap  = 0b0100000000010100  (bit 2,4,14)
output  = [header, A, B, C]  → out_len=4  (thay vì 16 word, tiết kiệm 75%)
```

### 6.7 Thêm 7 — `comp_rle.v`: Nén Run-Length Encoding

**Ý tưởng:** Block có đoạn lặp → lưu (value, count) thay vì từng phần tử.

**Format output:**
```
Word 0 (header): {14'b0, 01, num_runs[15:0]}
Word 1,2:        (run_val_0, run_cnt_0)
Word 3,4:        (run_val_1, run_cnt_1)   ...
out_len = 1 + 2×num_runs
```

**FSM 6 state** (`S_IDLE → S_LOAD → S_SCAN → S_WVAL → S_WCNT → S_HEADER`):
- `S_LOAD`: nạp toàn bộ N word vào `wbuf[]` (cần buffer trước khi scan).
- `S_SCAN`: duyệt từ `scan_idx=1`, nếu `wbuf[scan_idx]==run_val` → `run_cnt++`, ngược lại → xả run.
- `S_WVAL/S_WCNT`: mỗi state ghi 1 word vào scratchpad (1 write port → 2 cycles mỗi run).
- `S_HEADER`: ghi header, done.

**Ví dụ:** `[5,5,5,5,5,5,5,5,5, 7,7,7,7,7,7,7]`
```
runs    = [(5,9), (7,7)]
output  = [header|2, 5, 9, 7, 7]  → out_len=5  (tiết kiệm 69%)
```

### 6.8 Thêm 8 — `comp_delta.v`: Nén Delta Encoding

**Ý tưởng:** Dữ liệu biến thiên chậm → lưu base + các hiệu 8-bit signed (4 hiệu/word).

**Format output (packed — khi tất cả hiệu fit [-128,127]):**
```
Word 0 (header): {14'b0, 10, 7'b0, packed=1, 8'b0}
Word 1:           base = block[0]
Word 2:           {diff[4], diff[3], diff[2], diff[1]}   little-endian byte
Word 3:           {diff[8], diff[7], diff[6], diff[5]}
Word 4:           {diff[12], diff[11], diff[10], diff[9]}
Word 5:           {0, diff[15], diff[14], diff[13]}
out_len = 6
```

**Format output (raw fallback — có hiệu không fit):**
```
Word 0 (header): {14'b0, 10, 16'b0}   packed=0
Word 1..16:       16 word gốc
out_len = 17
```

**Kiểm tra `fits` — tổ hợp trên buffer:**
```verilog
// 8-bit signed fit: 25 bit cao [31:7] phải đồng nhất
if (!((&diff[k][31:7]) | (~|diff[k][31:7])))  fits = 1'b0;
```
`&diff[k][31:7]`=1 nếu all-1 (số âm nhỏ); `~|diff[k][31:7]`=1 nếu all-0 (số dương nhỏ).

**FSM 4 state** (`S_IDLE → S_LOAD → S_EMIT → S_FIN`):
- `S_EMIT`: counter `e` chạy 0→5 (packed) hoặc 0→16 (raw); mỗi cycle ghi 1 word; `wr_data` là wire tổ hợp từ `e`.

### 6.9 Thêm 9 — `pattern_detect.v`: Phát hiện mẫu (NOVELTY)

Đây là **đóng góp khoa học chính** — phần cứng tự đo đặc tính và chọn mode nén.

#### Hàm `sbits` — Bề rộng bit signed tối thiểu (= LZC trên số signed)

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

`sbits(5)=4` (cần 4-bit signed để biểu diễn +5); `sbits(-1)=1`; `sbits(127)=8`; `sbits(128)=9`.

#### Ba chỉ số đo song song (combinational từ `wbuf[]`)

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

**Tái dùng phần cứng:** comparator `==` dùng cho cả RLE và input subtractor Delta; subtractor `−` dùng cho cả Delta compress và LZC → tiết kiệm diện tích.

#### Priority logic — Chọn mode

```verilog
if (zero_cnt >= tau1_r)     mode_sel = MODE_ZERO;   // 00
else if (run_cnt >= tau2_r) mode_sel = MODE_RLE;    // 01
else if (delta_w <= wmax_r) mode_sel = MODE_DELTA;  // 10
else                        mode_sel = MODE_RAW;    // 11
```

**Ngưỡng mặc định:** `TAU1=TAU2=WMAX=8` (cấu hình qua `op_b` của PDETECT).

#### `det_word` — Gói 4 thông tin vào 1 word 32-bit

```
bit[1:0]   = mode      (00/01/10/11)
bit[7:2]   = zero_cnt  (0–63)
bit[13:8]  = run_cnt   (0–63)
bit[21:16] = delta_w   (0–63)
bit[31:22] = 0
```

#### FSM 3 state (`S_IDLE → S_LOAD → S_DONE`)

- `S_LOAD`: nạp N word vào `wbuf[]` (N cycles).
- `S_DONE`: 3 chỉ số tính tổ hợp → latch `mode`, `det_word`; `done=1`.

### 6.10 Thêm 10 — Wiring trong `cpu_top.v`

3 wire mới cho accel write path:
```verilog
wire accel_spad_we;
wire [7:0] accel_spad_waddr;
wire [31:0] accel_spad_wdata;
```

Scratchpad kết nối dual-port:
```verilog
scratchpad u_scratchpad (
    .we0(spad_we), .waddr0(spad_waddr), .wdata0(spad_wdata), .wstrb0(spad_wstrb),
    .we1(accel_spad_we), .waddr1(accel_spad_waddr), .wdata1(accel_spad_wdata),
    .raddr(spad_raddr), .rdata(spad_rdata)
);
```

### 6.11 Thêm 11 — Software Layer (HW/SW Co-design)

#### `compress_api.h` — Wrapper C cho 3 custom instruction

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

**Macro bóc tách CSTAT:**
```c
#define CSTAT_DONE(s)    (((s) >> 30) & 1u)
#define CSTAT_RESULT(s)  ((s) & 0x0FFFFFFFu)
#define DET_MODE(r)      ((r) & 0x3u)
#define DET_ZEROCNT(r)   (((r) >> 2)  & 0x3Fu)
#define DET_RUNCNT(r)    (((r) >> 8)  & 0x3Fu)
#define DET_DELTAW(r)    (((r) >> 16) & 0x3Fu)
```

#### `demo_pipeline.c` — Vòng lặp detect→choose→compress

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

#### `asm_riscv.py` — Assembler Python thay RISC-V GCC

Vì máy không có `riscv32-unknown-elf-gcc`, một assembler Python 2-pass được viết hỗ trợ:
- RV32I subset (ADDI, LUI, SW, LW, BEQ, BNE, JAL, SLL, SRL, ANDI, OR, ADD)
- 3 custom instruction: `pdetect rd,rs1,rs2` / `ccompr rs1,rs2` / `cstat rd`
- Sinh `demo_pipeline.hex` (256 word, padding 0)

---

## 7. Custom Instruction Encoding

**Opcode:** `0x0B = 7'b0001011` (RISC-V custom-0, dành cho user extension)

**R-type format:**
```
[31:25]   [24:20]  [19:15]  [14:12]  [11:7]  [6:0]
funct7=0  rs2      rs1      funct3   rd      0001011
```

| Lệnh | funct3 | rs1 | rs2 | rd | Chức năng |
|------|--------|-----|-----|-----|-----------|
| `pdetect rd,rs1,rs2` | 000 | src_addr | ngưỡng | det_word | Detect pattern 1 block |
| `ccompr rs1,rs2` | 001 | src_addr | dst\|mode | x0 | Nén 1 block |
| `cstat rd` | 010 | x0 | x0 | status | Poll status |

**CSTAT word:**
```
bit[31]   = busy
bit[30]   = done   ← SW poll cái này (beq/bne loop)
bit[29]   = err
bit[28]   = last_op  (0=compress, 1=detect)
bit[27:0] = last_result (out_len hoặc det_word)
```

**det_word:**
```
bit[1:0]   = mode      00=ZERO  01=RLE  10=DELTA  11=RAW
bit[7:2]   = zero_cnt
bit[13:8]  = run_cnt
bit[21:16] = delta_w
```

**Compression mode encoding trong `op_b[1:0]`:**
```
00 = ZERO   (zero-suppression + bitmap)
01 = RLE    (run-length encoding)
10 = DELTA  (8-bit signed delta, packed)
11 = RAW    (không nén — accelerator từ chối, err=1)
```

---

## 8. HW/SW Co-Design Flow

Vòng lặp cho 1 block (assembly tương đương):

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

**Mô hình poll (no-stall):** Pipeline không stall theo `custom_busy`. SW tự poll CSTAT. Đã verified: detector chạy ~18 cycles, nén chạy 16–35 cycles tùy mode.

---

## 9. Kết quả Verification

### Unit tests (ModelSim)

| Testbench | Module | Kết quả |
|-----------|--------|---------|
| `tb_comp_zero.v` | `comp_zero.v` | PASS (256 block, EXP_LEN=3216) |
| `tb_comp_rle.v` | `comp_rle.v` | PASS (256 block, EXP_LEN=4318) |
| `tb_comp_delta.v` | `comp_delta.v` | PASS (256 block, EXP_LEN=2526) |
| `tb_pattern_detect.v` | `pattern_detect.v` | PASS (256 block, khớp golden) |
| `tb_cpu_top.v` | Toàn bộ pipeline | PASS (37 test cases) |

### Integration test (ModelSim)

| Testbench | Kết quả |
|-----------|---------|
| `tb_demo_pipeline.v` | PASS — detector chọn đúng [ZERO,RLE,DELTA]; out_len=[5,5,6]; scratchpad[48..63] khớp golden |

### GĐ4 — Verification chặt

**4.1 — Golden-match testbench tự động** (`tb_compress_top.v`): drive `compress_accel` dispatcher qua custom instruction CCOMPR cho cả 3 mode (đúng đường mà CPU dùng), so output từng word với golden:

| Mode | Word ghi ra | Kết quả |
|------|-------------|---------|
| ZERO | 3216 | PASS == golden |
| RLE | 4318 | PASS == golden |
| DELTA | 2526 | PASS == golden |

→ `[PASS] RTL nén (qua CCOMPR dispatcher) == golden cả 3 mode, 256 block.`

**4.2 — Round-trip lossless** (`golden_compress.py --roundtrip`): viết bộ giải nén `decompress_zero/rle/delta`, kiểm `decompress(compress(x)) == x` trên toàn bộ 256 block:

| Mode | PASS | FAIL | Kết quả |
|------|------|------|---------|
| ZERO | 256 | 0 | LOSSLESS |
| RLE | 256 | 0 | LOSSLESS |
| DELTA | 256 | 0 | LOSSLESS |
| ADAPTIVE | 256 | 0 | LOSSLESS |

→ `[PASS] Round-trip lossless 100%: decompress(compress(x)) == x trên toàn bộ 256 block, cả 3 mode + adaptive.`

Vì RTL đã được verify byte-by-byte = `compress(x)` (4.1) và `decompress(compress(x)) = x` (4.2), suy ra **output RTL giải nén lại đúng dữ liệu gốc** — chứng minh lossless hoàn chỉnh.

### Compression ratio (golden_compress.py trên 256-block mixed dataset)

| Mode | Ratio |
|------|-------|
| ZERO-only | ~1.5× |
| RLE-only | ~0.9× |
| DELTA-only | 1.622× |
| **ADAPTIVE** (detector chọn/block) | **2.835×** |

Phân bố mode trên mixed: ZERO=99 block / RLE=77 block / DELTA=80 block.

---

## 10. Đánh giá — Evaluation (GĐ5 + GĐ6)

### 10.0 — Synthesis FPGA (GĐ5): area / timing / power

Synth + implement toàn thiết kế (`fpga_top` = cpu_top + accel + detector) trên **Nexys A7-100T (xc7a100tcsg324-1)** bằng Vivado 2025.2 (`synth_phase5.tcl`).

**Utilization (post-implementation, detector đã tối ưu):**

| Tài nguyên | Dùng | Có sẵn | % |
|-----------|------|--------|---|
| Slice LUT | 4066 | 63400 | 6.41% |
| Slice Register (FF) | 2948 | 126800 | 2.32% |
| Block RAM | 0 | 135 | 0% |
| DSP | 0 | 240 | 0% |

> Các bộ nhớ (imem/data_mem/scratchpad 256 word) suy ra thành **distributed LUTRAM**, không dùng BRAM.

**Timing & Power:**

| Chỉ số | Giá trị |
|--------|---------|
| Clock target | 100 MHz (10.00 ns) |
| WNS (setup) | −1.816 ns |
| **Fmax đạt được** | **84.6 MHz** |
| Path tới hạn | `u_detect`: li → delta_acc (LZC trên hiệu kề), 11.5ns, 19 logic levels |
| Total On-Chip Power | **0.164 W** (dynamic 0.066 + static 0.097, confidence Medium) |

### 10.0b — Tối ưu detector + chi phí detection (GĐ5.2) — before/after

**Vấn đề phát hiện qua synth lần đầu:** bản detector "naive" tính 3 chỉ số (15 subtractor + 15 LZC `sbits` + comparator) **tổ hợp trong 1 cycle** với buffer riêng → vừa to nhất vừa là path tới hạn.

**Tối ưu (streaming):** tính **tăng dần** ngay khi từng word chảy vào trong N cycle nạp → chỉ **1 subtractor + 1 LZC tái dùng 15 lần**, **bỏ hẳn buffer** (detector chỉ sinh `det_word`, không cần lưu data). Giữ nguyên latency 17 cycle và `det_word` **bit-exact** (tb_pattern_detect vẫn PASS 256 block).

| Chỉ số | Naive (1 cycle tổ hợp) | **Streaming (tối ưu)** | Cải thiện |
|--------|------------------------|------------------------|-----------|
| Detector LUT | 1690 | **113** | **−93% (15×)** |
| Detector FF | 565 | **105** | −81% |
| Detector % accelerator | 55% | **7.5%** | |
| Detector % toàn CPU | 31% | **2.8%** | |
| Accelerator LUT | 3045 | 1514 | −50% |
| System LUT | 5403 | 4066 | −24.7% |
| System FF | 3398 | 2948 | −13.2% |
| **Fmax** | 45.3 MHz | **84.6 MHz** | **+87%** |
| Latency PDETECT | 17 cyc | 17 cyc | giữ nguyên |
| det_word | — | bit-exact | y hệt |

**Hierarchical utilization (sau tối ưu):**

| Khối | LUT | FF |
|------|-----|----|
| `u_cpu` (toàn CPU) | 4039 | 2903 |
| └ `u_accel` | 1514 | 1374 |
| &nbsp;&nbsp;├ `u_zero` | 134 | 58 |
| &nbsp;&nbsp;├ `u_rle` | 285 | 640 |
| &nbsp;&nbsp;├ `u_delta` | 978 | 544 |
| &nbsp;&nbsp;└ **`u_detect`** | **113** | **105** |

**Kết luận (luận điểm cho bài):** sau tối ưu, detector là **khối NHỎ NHẤT** trong accelerator (113 LUT) — chỉ **2.8% diện tích CPU** — đúng tinh thần "**siêu nhẹ**" của novelty. Bảng before/after là bằng chứng định lượng cho mẹo "tái dùng phần cứng" (GĐ1) và phản bác trực diện rủi ro "detection ăn hết lợi ích". Báo cáo gốc lưu ở `../BaoCao/phase5_reports/` (sau tối ưu) và `../BaoCao/phase5_reports_naive/` (trước tối ưu) — xem [mục 14](#14-các-file-không-nằm-trong-repo).

---

### 10.1 — Ba dataset tương phản (`gen_datasets.py`)

Sinh 3 bộ dữ liệu đặc tính khác hẳn nhau (128 block/bộ), mô phỏng domain thật:

| Dataset | Đặc tính | Mô phỏng | Detector chọn |
|---------|----------|----------|---------------|
| `zero_heavy` | 1–4 word ≠ 0, còn lại = 0 | feature map TinyML thưa | ZERO = 128/128 |
| `repetitive` | vài run dài | mask / ảnh nhị phân | RLE = 128/128 |
| `slow_varying` | hiệu kề nhỏ [-8,8] | telemetry cảm biến | DELTA = 128/128 |

→ **Detector chọn đúng mode 100%** trên mỗi dataset thuần.

### 10.2 — Sweep compression-ratio (`eval_paper.py`)

Bảng (dataset × method), ratio = word gốc / word nén (cao = tốt; <1 = phình to):

| Dataset | RAW | ZERO-only | RLE-only | DELTA-only | **ADAPTIVE** |
|---------|-----|-----------|----------|------------|--------------|
| zero_heavy | 1.000× | **4.541×** | 1.356× | 0.941× | **4.541×** |
| repetitive | 1.000× | 0.941× | **2.709×** | 0.941× | **2.709×** |
| slow_varying | 1.000× | 0.941× | 0.513× | **2.667×** | **2.667×** |
| mixed | 1.000× | 1.274× | 0.949× | 1.622× | **2.835×** |

**Kết luận chính (Figure thuyết phục nhất):**
- Trên mỗi dataset thuần: ADAPTIVE = best single-mode (**+0.0%** — chọn tối ưu từng block).
- Trên `mixed` (hỗn hợp): ADAPTIVE = 2.835× **thắng best-fixed (DELTA 1.622×) +74.8%** — vì không mode cố định nào tốt cho luồng dữ liệu đa đặc tính.
- **Mọi single-mode đều PHÌNH dữ liệu** (ratio < 1) trên ít nhất 1 dataset (RLE-only phình `slow_varying` xuống 0.513× — gần gấp đôi kích thước). ADAPTIVE không bao giờ < 2.667×.

→ Đây chính là bằng chứng định lượng cho luận điểm "multi-mode + detection" có giá trị thật (đáp trả rủi ro reviewer "single-mode là đủ").

### 10.3 — Throughput cycle-accurate (`tb_throughput.v`, đo từ RTL)

| Op | Latency (cycle) | out_len (word) |
|----|-----------------|----------------|
| PDETECT | 17 (≈ N+1, data-independent) | — |
| CCOMPR ZERO | 17 | 5 |
| CCOMPR RLE | 37 | 5 |
| CCOMPR DELTA | 23 | 6 |

**End-to-end (detect + compress) / block — throughput byte vào / cycle:**

| Mode | detect + compress = total | Throughput |
|------|---------------------------|------------|
| ZERO | 17 + 17 = 34 cycle | 1.882 byte/cycle |
| RLE | 17 + 37 = 54 cycle | 1.185 byte/cycle |
| DELTA | 17 + 23 = 40 cycle | 1.600 byte/cycle |

> Đây là số liệu **đo bằng sim** (không phải ước lượng). So với software-only trên cùng core (vòng lặp ~16 word × nhiều lệnh/word + load-use stall, ước tính ~140 cycle/block cho zero-suppression) → accelerator nhanh **~4× end-to-end**. Con số software-only chính xác sẽ được **đo** bằng cách chạy bản nén assembly trên `cpu_top` (follow-up).
>
> **Năng lượng/byte** = power × thời gian / byte cần Vivado Power Report → thuộc **GĐ5** (Vivado chưa cài đầy đủ trên máy).

---

## 11. Cấu trúc file

> Repo chỉ chứa **source + script + dataset nhỏ** (~0.8 MB). File build (Vivado/ModelSim), dataset thô 144 MB và các bản báo cáo đã được tách ra — xem [mục 13](#13-dữ-liệu-lớn--cách-tái-tạo) và [mục 14](#14-các-file-không-nằm-trong-repo).

```
32bit_RISCV/
├── --- RISC-V pipeline (gốc, có mở rộng) ---
│   ├── if_stage.v             IF stage + instruction_memory
│   ├── if_id_reg.v            IF/ID pipeline register
│   ├── id_stage.v             ID stage + RegFile + Decoder      [MỞ RỘNG]
│   ├── id_ex_reg.v            ID/EX pipeline register           [MỞ RỘNG]
│   ├── ex_stage.v             EX stage + ALU + Branch
│   ├── mem_stage.v            MEM stage + data_mem              [MỞ RỘNG]
│   ├── wb_hazard_fwd.v        WB + Hazard unit + Forwarding unit
│   ├── pipeline_regs.v        EX/MEM + MEM/WB registers
│   └── cpu_top.v              Top-level kết nối                 [MỞ RỘNG]
│
├── --- Accelerator (thêm mới) ---
│   ├── Compress_accel.v       Dispatcher FSM + điều phối 4 sub-module
│   ├── comp_zero.v            Zero-suppression compressor
│   ├── comp_rle.v             Run-length encoding compressor
│   ├── comp_delta.v           Delta encoding compressor
│   ├── pattern_detect.v       Pattern detector (NOVELTY)
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
├── --- Testbenches ---
│   ├── tb_if_stage.v  tb_id_stage.v  tb_ex_stage.v  tb_mem_stage.v
│   │                          Unit test từng pipeline stage
│   ├── tb_cpu_top.v           Smoke test toàn core
│   ├── tb_comp_zero.v  tb_comp_rle.v  tb_comp_delta.v
│   │                          Unit test 3 compressor (golden-match)
│   ├── tb_pattern_detect.v    Unit test detector
│   ├── tb_compress_top.v      Golden-match qua dispatcher, 3 mode × 256 block
│   ├── tb_demo_pipeline.v     Integration end-to-end (detect→chọn→nén)
│   ├── tb_demo_sparse.v       Integration trên dữ liệu thưa
│   ├── tb_throughput.v        Đo throughput cycle-accurate
│   ├── tb_cyc_display.v       In cycle count từng mode
│   ├── tb_sw_baseline.v       Baseline nén thuần software trên core
│   ├── tb_lec_baseline.v      Baseline LEC (so sánh thuật toán khác)
│   ├── tb_uart_tx.v           Unit test UART TX
│   └── tb_fpga_top_uart.v     Integration FPGA top + UART
│
├── --- Golden model + sinh dữ liệu ---
│   ├── golden_compress.py     Golden model (3 mode + detector + decompress + round-trip)
│   ├── gen_demo.py            Sinh demo_src.hex + demo_expected_dest.hex
│   ├── gen_datasets.py        Sinh 3 dataset tổng hợp tương phản
│   ├── gen_real_datasets.py   Cắt dataset thật → real_*.hex (bản nhỏ, có trong repo)
│   └── gen_real_datasets_full.py  Sinh real_*_full.hex từ data.txt (KHÔNG có trong repo)
│
├── --- Assembler + Evaluation ---
│   ├── asm_riscv.py           Assembler Python (thay RISC-V GCC)
│   ├── asm_sw_baseline.py     Sinh chương trình baseline software
│   ├── asm_lec_baseline.py    Sinh chương trình baseline LEC
│   ├── asm_uart_demo.py       Sinh chương trình demo UART
│   ├── eval_paper.py          Sweep compression-ratio chính cho paper
│   ├── eval_baselines.py      So sánh với gzip/zlib/LEC
│   ├── eval_composability.py  Đánh giá khả năng ghép mode
│   ├── eval_lec_winner.py     Phân tích khi nào LEC thắng
│   ├── verify_paper_numbers.py  Kiểm tra chéo mọi con số trong paper
│   └── read_uart_demo.py      Đọc stream UART từ board qua COM port
│
├── --- Software layer ---
│   ├── compress_api.h         C wrapper cho 3 custom instruction
│   └── demo_pipeline.c        Demo end-to-end (cần RISC-V GCC)
│
├── --- Script chạy tự động ---
│   ├── run_modelsim.do        Chạy full regression ModelSim
│   ├── run_modelsim_unit.do   Chạy riêng unit test
│   ├── run_modelsim_lec.do    Chạy riêng baseline LEC
│   ├── synth_phase5.tcl       Vivado: synth + impl + report GĐ5
│   ├── synth_paper.tcl        Vivado: build cấu hình dùng cho paper
│   ├── synth_uart_demo.tcl    Vivado: build bản demo UART
│   └── synth_fmaxtest.tcl     Vivado: quét Fmax
│
├── --- Dataset (nhỏ, có trong repo) ---
│   ├── dataset_zero_heavy.hex  dataset_repetitive.hex  dataset_slow_varying.hex
│   │                          3 dataset tổng hợp tương phản
│   ├── real_temp.hex  real_volt.hex  real_light.hex  real_mixed.hex
│   │                          Dataset thật đã cắt (20K word mỗi file)
│   ├── tb_src_mixed.hex       256-block mixed dataset nguồn
│   ├── tb_expected_zero_mixed.hex   Golden output ZERO mode
│   ├── tb_expected_rle_mixed.hex    Golden output RLE mode
│   ├── tb_expected_delta_mixed.hex  Golden output DELTA mode
│   ├── tb_expected_detect_mixed.hex Golden det_word 256 block
│   ├── demo_src.hex           3 block tương phản nguồn
│   ├── demo_expected_dest.hex Golden output demo
│   └── uart_demo_src.hex      Nguồn cho demo UART
│
├── --- Program image (sinh từ assembler) ---
│   ├── mem_program.hex        Program cho cpu_top
│   ├── demo_pipeline.hex      Program demo end-to-end
│   ├── sw_baseline.hex        Program baseline software
│   ├── lec_baseline.hex       Program baseline LEC
│   └── uart_demo.hex          Program demo UART
│
├── --- Kết quả đo (commit để tra cứu) ---
│   ├── eval_paper_sweep.csv        Bảng sweep ratio đầy đủ
│   ├── eval_paper_policy.csv       So sánh policy chọn mode
│   ├── eval_baselines_results.csv  Kết quả so với gzip/zlib/LEC
│   ├── real_result.csv             Mode + ratio từng block trên dataset thật
│   ├── dfx_runtime.txt             Thời gian reconfig runtime
│   ├── tight_setup_hold_pins.txt   Pin có setup/hold sát ngưỡng
│   └── demo_expected.txt           Output mong đợi của demo
│
└── --- Khác ---
    ├── arch_flow.svg          Sơ đồ kiến trúc
    ├── README.md              File này
    └── .gitignore             Loại file build + dataset lớn khỏi git
```

---

## 12. Chạy Simulation (ModelSim)

> Toolchain: **ModelSim Intel FPGA Edition 2020.1** (chỉ công cụ available trên máy).

### Bước 0: Sinh data files

```bash
python golden_compress.py      # sinh tb_expected_*_mixed.hex + báo cáo ratio
python gen_demo.py             # sinh demo_src.hex, demo_expected_dest.hex
python asm_riscv.py            # sinh demo_pipeline.hex
```

### Bước 1: Chạy unit test từng module nén

```bash
# ModelSim command
vlog comp_zero.v scratchpad.v tb_comp_zero.v
vsim -c tb_comp_zero -do "run -all; quit -f"

vlog comp_rle.v scratchpad.v tb_comp_rle.v
vsim -c tb_comp_rle -do "run -all; quit -f"

vlog comp_delta.v scratchpad.v tb_comp_delta.v
vsim -c tb_comp_delta -do "run -all; quit -f"
```

### Bước 2: Chạy unit test pattern detector

```bash
vlog pattern_detect.v tb_pattern_detect.v
vsim -c tb_pattern_detect -do "run -all; quit -f"
```

### Bước 3: Chạy integration test (toàn bộ CPU)

```bash
vlog if_stage.v id_stage.v ex_stage.v mem_stage.v wb_hazard_fwd.v \
     pipeline_regs.v cpu_top.v scratchpad.v \
     comp_zero.v comp_rle.v comp_delta.v pattern_detect.v Compress_accel.v \
     tb_demo_pipeline.v
vsim -c tb_demo_pipeline -do "run -all; quit -f"
```

Kết quả mong đợi:
```
[MODE OK]   block 0 -> mode 0  (ZERO)
[MODE OK]   block 1 -> mode 1  (RLE)
[MODE OK]   block 2 -> mode 2  (DELTA)
[PASS] Vong HW/SW detect->chon->nen chay dung tren core (3 block, 3 mode).
```

### Bước 4: Verification chặt (GĐ4)

**4.1 — Golden-match qua dispatcher:**
```bash
vlog comp_zero.v comp_rle.v comp_delta.v pattern_detect.v Compress_accel.v tb_compress_top.v
vsim -c tb_compress_top -do "run -all; quit -f"
# → [PASS] RTL nén (qua CCOMPR dispatcher) == golden cả 3 mode, 256 block.
```

**4.2 — Round-trip lossless:**
```bash
python golden_compress.py --roundtrip    # decompress(compress(x)) == x cho 256 block
# → [PASS] Round-trip lossless 100% (3 mode + adaptive)
```

### Bước 5: Evaluation (GĐ6)

```bash
python gen_datasets.py        # sinh 3 dataset tương phản (zero_heavy/repetitive/slow_varying)
python eval_paper.py          # bảng sweep compression-ratio + eval_paper_sweep.csv

# Throughput đo từ RTL:
vlog comp_zero.v comp_rle.v comp_delta.v pattern_detect.v Compress_accel.v tb_throughput.v
vsim -c tb_throughput -do "run -all; quit -f"
```

---

## 13. Dữ liệu lớn — cách tái tạo

Repo **không chứa** dataset thô và các file hex đầy đủ vì vượt giới hạn của GitHub (100 MB/file, khuyến nghị < 50 MB). Chúng được sinh lại bằng script trong repo.

### 13.1 — `data.txt` (144 MB) — dataset cảm biến thật

Nguồn: **Intel Berkeley Research Lab Sensor Data** (2004) — 2.3 triệu bản ghi từ 54 cảm biến (nhiệt độ, độ ẩm, ánh sáng, điện áp), đo mỗi 31 giây trong ~1 tháng.

Trang chủ: <http://db.csail.mit.edu/labdata/labdata.html> → tải `data.txt.gz`, giải nén thành `data.txt` và đặt vào thư mục gốc repo.

Định dạng mỗi dòng (space-separated):

```
date time epoch moteid temperature humidity light voltage
2004-02-28 00:59:16.02785 3 1 19.9884 37.0933 45.08 2.69964
```

### 13.2 — Sinh lại các file hex

```bash
# Bản nhỏ (đã có sẵn trong repo — chỉ chạy nếu muốn sinh lại)
python gen_real_datasets.py        # → real_temp.hex, real_volt.hex, real_light.hex, real_mixed.hex

# Bản đầy đủ (KHÔNG có trong repo — cần data.txt ở trên)
python gen_real_datasets_full.py   # → real_temp_full.hex, real_volt_full.hex,
                                   #   real_light_full.hex, real_mixed_full.hex  (~22 MB)
```

| File | Kích thước | Trong repo? | Sinh bằng |
|------|-----------|-------------|-----------|
| `data.txt` | 144 MB | Không | Tải từ MIT CSAIL (13.1) |
| `real_*.hex` | 80 KB × 4 | **Có** | `gen_real_datasets.py` |
| `real_temp/volt/light_full.hex` | 3.6 MB × 3 | Không | `gen_real_datasets_full.py` |
| `real_mixed_full.hex` | 11 MB | Không | `gen_real_datasets_full.py` |

> Toàn bộ kết quả trong paper có thể tái lập chỉ với `real_*.hex` (bản nhỏ). Bản `_full` chỉ dùng để kiểm chứng rằng tỉ số nén ổn định trên dataset đầy đủ.

### 13.3 — Sinh lại các file hex tổng hợp / program image

```bash
python golden_compress.py    # tb_expected_*_mixed.hex
python gen_datasets.py       # dataset_zero_heavy/repetitive/slow_varying.hex
python gen_demo.py           # demo_src.hex, demo_expected_dest.hex
python asm_riscv.py          # demo_pipeline.hex
python asm_sw_baseline.py    # sw_baseline.hex
python asm_lec_baseline.py   # lec_baseline.hex
python asm_uart_demo.py      # uart_demo.hex
```

---

## 14. Các file KHÔNG nằm trong repo

### 14.1 — Báo cáo & paper → `../BaoCao/`

Đã tách ra thư mục `Final_Project/32bit_RISCV/BaoCao/` (ngoài repo):

| File / thư mục | Nội dung |
|----------------|----------|
| `paper_pacomp_v2.pdf` / `.tex` | Bản paper chính |
| `nwest.tex` | Bản nộp hội nghị |
| `BAO_CAO_V2_THAY_DOI_VA_KIEM_CHUNG.md` | Báo cáo thay đổi + kiểm chứng V2 |
| `BAO_CAO_SUA_LOI_VA_CAI_TIEN.txt` | Nhật ký sửa lỗi và cải tiến |
| `HUONG_DAN_KIEM_TRA.md` | Hướng dẫn kiểm tra/nghiệm thu |
| `eval_paper_results.md` | Bảng kết quả dạng markdown |
| `phase5_reports/` | Vivado report **sau** tối ưu detector (+ `fpga_top.bit`) |
| `phase5_reports_naive/` | Vivado report **trước** tối ưu (để so before/after) |
| `phase5_reports_paper/` | Report của cấu hình dùng trong paper |
| `phase5_reports_uart/` | Report bản có UART (+ `fpga_top_uart.bit`) |

> Nếu muốn công bố kèm repo, tạo GitHub **Release** rồi đính `paper_pacomp_v2.pdf` và các file `.bit` vào đó — không commit trực tiếp.

### 14.2 — File build (bị `.gitignore` loại, vẫn nằm trên máy)

| Nhóm | File / thư mục | Sinh lại bằng |
|------|----------------|---------------|
| Vivado project | `RISC_V/`, `project_1/`, `.Xil/` | `vivado -mode batch -source synth_phase5.tcl` |
| Vivado log | `vivado.log`, `vivado.jou`, `clockInfo.txt` | tự sinh khi chạy Vivado |
| ModelSim | `work/`, `transcript`, `modelsim.ini`, `RISC-V_32bit.mpf` | `vlog` / `vsim` (xem mục 12) |
| Python | `__pycache__/` | tự sinh |

Có thể xóa an toàn bất cứ lúc nào — mọi thứ trong bảng này đều tái tạo được từ source trong repo.

---

## 15. Đưa dự án lên GitHub

### 15.1 — Chuẩn bị (một lần duy nhất)

Cài **Git for Windows**: <https://git-scm.com/download/win> — cài xong mở **Git Bash** hoặc PowerShell.

```bash
git config --global user.name  "Tên của bạn"
git config --global user.email "email@github.com"   # dùng đúng email đăng ký GitHub
```

### 15.2 — Tạo repo rỗng trên GitHub

Vào <https://github.com/new>:

- **Repository name**: `riscv32-compression-accelerator` (hoặc tên bạn muốn)
- **Visibility**: Public hoặc Private
- **KHÔNG** tích "Add a README file", "Add .gitignore", "Choose a license" — repo phải rỗng hoàn toàn, vì bạn đã có sẵn ở local.

Bấm **Create repository** → copy URL dạng `https://github.com/<username>/<repo>.git`.

### 15.3 — Khởi tạo và push

Mở terminal **tại thư mục** `C:\Users\tin20\Desktop\Final_Project\32bit_RISCV\32bit_RISCV`:

```bash
cd "C:\Users\tin20\Desktop\Final_Project\32bit_RISCV\32bit_RISCV"

git init
git add .
git status              # KIỂM TRA: phải ~95 file, KHÔNG có data.txt / RISC_V/ / work/
git commit -m "RISC-V 32-bit pipeline + pattern-aware compression accelerator"

git branch -M main
git remote add origin https://github.com/<username>/<repo>.git
git push -u origin main
```

Lần push đầu tiên Git sẽ hỏi đăng nhập → chọn **Sign in with your browser**, đăng nhập GitHub, xong.

> **Nếu bị hỏi username/password:** GitHub không còn nhận mật khẩu tài khoản. Vào <https://github.com/settings/tokens> → *Generate new token (classic)* → tích quyền `repo` → copy token và **dán token đó vào ô password**.

### 15.4 — Kiểm tra trước khi push (khuyến nghị)

```bash
# Xem tổng dung lượng sắp commit — phải < 1 MB
git count-objects -vH

# Liệt kê 10 file lớn nhất sắp commit
git ls-files -z | xargs -0 ls -lS 2>/dev/null | head -10

# Xem file nào đang bị .gitignore loại (để chắc chắn không loại nhầm source)
git status --ignored --short | grep "^!!"
```

Nếu thấy `data.txt` hoặc `RISC_V/` trong danh sách sắp commit → `.gitignore` chưa được áp dụng, chạy:

```bash
git rm -r --cached .
git add .
git status
```

### 15.5 — Cập nhật sau này

```bash
git add .
git commit -m "Mô tả ngắn gọn thay đổi"
git push
```

### 15.6 — Đính kèm paper và bitstream (GitHub Release)

Vì `.pdf` và `.bit` không nằm trong repo, cách chuẩn để chia sẻ là Release:

1. Vào repo trên GitHub → tab **Releases** → **Create a new release**
2. **Tag**: `v1.0` — **Title**: `Paper + FPGA bitstream`
3. Kéo thả `BaoCao/paper_pacomp_v2.pdf`, `BaoCao/phase5_reports/fpga_top.bit`, `BaoCao/phase5_reports_uart/fpga_top_uart.bit` vào ô attach
4. **Publish release**

### 15.7 — Xử lý sự cố thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|-----|-------------|-----------|
| `remote: error: File data.txt is 144.00 MB; this exceeds GitHub's file size limit of 100.00 MB` | Đã lỡ commit file lớn | `git rm --cached data.txt` → sửa `.gitignore` → `git commit --amend -C HEAD` → push lại. Nếu file đã nằm ở commit cũ, phải dùng `git filter-repo` hoặc tạo lại repo. |
| `fatal: remote origin already exists` | Đã add remote trước đó | `git remote set-url origin <URL mới>` |
| `Updates were rejected because the remote contains work that you do not have locally` | Repo trên GitHub không rỗng | `git pull --rebase origin main` rồi push lại |
| `error: failed to push some refs` + nhánh tên `master` | Nhánh local là `master`, GitHub mặc định `main` | `git branch -M main` rồi `git push -u origin main` |
| Tiếng Việt hiển thị lỗi font trong `git log` | Encoding console | `git config --global i18n.logOutputEncoding utf-8` và chạy `chcp 65001` trong CMD |

---

## Ghi chú kỹ thuật

- **`buf` là reserved keyword trong ModelSim** → tất cả buffer nội bộ đặt tên `wbuf`.
- **Pipeline không stall theo `custom_busy`** → SW poll CSTAT (đã verify là đủ). Nếu reviewer yêu cầu: thêm stall handshake trong `hazard_unit` sau.
- **`AW=8` trong `cpu_top`** (256 word scratchpad), **`AW=13` trong testbench standalone** (8192 word — cần vì dest RLE có thể vượt 4096 word trên 256 block).
- **Không có RISC-V GCC trên máy** → dùng `asm_riscv.py` để chứng minh chạy được trên sim. File `demo_pipeline.c` là reference cho máy có toolchain.
- **FPGA synthesis (GĐ5)** cần Vivado (chưa cài) → dùng `fpga_top.v` + `nexys_a7.xdc` khi có Vivado.
