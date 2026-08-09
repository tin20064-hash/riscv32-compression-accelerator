/* ===================================================================
 * link.ld -- Linker script cho RV32I 5-stage core (custom-0 PA-COMP)
 * -------------------------------------------------------------------
 * He thong la Harvard-kieu-tach-doi: khong gian dia chi cua LENH
 * (PC -> if_stage.v: instruction_memory, mem[0:255], doc qua pc[9:2])
 * hoan toan tach biet voi khong gian dia chi DU LIEU (lw/sw -> ALU
 * tinh dia chi -> mem_stage.v: data_mem[0:255], doc/ghi qua
 * address[9:2]; address[12] moi la bit chon data_mem/scratchpad).
 * CPU KHONG co duong doc instruction_memory bang lw -- moi hang so
 * .rodata/.data/.bss deu phai nam trong vung DATA, khong duoc nam
 * trong vung PROGRAM.
 *
 * Kich thuoc: ca 2 vung deu dung 256 word x 4 byte = 1KB (xem
 * if_stage.v dong "reg [31:0] mem [0:255]" va mem_stage.v dong
 * "reg [31:0] data_mem [0:255]").
 * =================================================================== */

MEMORY
{
    PROGRAM (rx)  : ORIGIN = 0x00000000, LENGTH = 1K   /* if_stage.v  : mem[0:255]      */
    DATA    (rw)  : ORIGIN = 0x00000000, LENGTH = 1K   /* mem_stage.v : data_mem[0:255] */
}

/* CPU luon fetch lenh dau tien tai PC = 0x0 sau reset (if_stage.v:
 *   "if (!rst_n) pc_out <= 32'h0000_0000;")
 * nen _start BAT BUOC phai duoc dat dung tai ORIGIN(PROGRAM). */
ENTRY(_start)

SECTIONS
{
    . = ORIGIN(PROGRAM);
    .text : {
        *(.text.start)      /* crt0.S phai la lenh dau tien -> dat len truoc */
        *(.text .text.*)
    } > PROGRAM

    /* Vung du lieu -- tach rieng dia chi 0 cua khong gian DATA (khac
     * hoan toan dia chi 0 cua khong gian PROGRAM o tren, vi 2 bus doc
     * lap nhau -- xem chu thich dau file). */
    . = ORIGIN(DATA);

    .rodata : {
        *(.rodata .rodata.*)
    } > DATA

    .data : {
        _data_start = .;
        *(.data .data.*)
        _data_end = .;
    } > DATA

    /* .bss KHONG co du lieu that trong file .hex (NOLOAD) -- crt0.S
     * phai tu xoa ve 0 luc khoi dong, xem ly do trong crt0.S. */
    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        _bss_end = .;
    } > DATA

    /* Ngan xep dat o dinh vung DATA, lon dan xuong -- danh cho crt0.S
     * gan vao thanh ghi sp (x2) truoc khi goi vao code C. */
    _stack_top = ORIGIN(DATA) + LENGTH(DATA);

    /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
