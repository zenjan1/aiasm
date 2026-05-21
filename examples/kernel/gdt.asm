    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# gdt.asm - 全局描述符表 (GDT)
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# GDT 表 (只读)
# ============================================================================
    .section .rodata
    .align  8
gdt_table:
    # 0x00: NULL 描述符
    .quad   0x0000000000000000

    # 0x08: 内核代码段 (ring 0, 执行/读, 4GB)
    # base=0, limit=0xFFFFF, DPL=0, type=0x9A (code, exec/read, accessed)
    .word   0xFFFF              # limit 0-15
    .word   0x0000              # base 0-15
    .byte   0x00                # base 16-23
    .byte   0x9A                # present(1) | DPL(00) | code(1) | exec/read(1010)
    .byte   0xCF                # granularity(1=4KB) | size(1=32-bit) | limit 16-19
    .byte   0x00                # base 24-31

    # 0x10: 内核数据段 (ring 0, 读/写, 4GB)
    # type=0x92 (data, read/write, accessed)
    .word   0xFFFF
    .word   0x0000
    .byte   0x00
    .byte   0x92
    .byte   0xCF
    .byte   0x00

    # 0x18: 用户代码段 (ring 3)
    # type=0xFA (DPL=3, code, exec/read)
    .word   0xFFFF
    .word   0x0000
    .byte   0x00
    .byte   0xFA
    .byte   0xCF
    .byte   0x00

    # 0x20: 用户数据段 (ring 3)
    # type=0xF2 (DPL=3, data, read/write)
    .word   0xFFFF
    .word   0x0000
    .byte   0x00
    .byte   0xF2
    .byte   0xCF
    .byte   0x00

gdt_table_end:

# ============================================================================
# GDT 指针 (6 字节)
# ============================================================================
    .section .data
    .align  4
gdt_ptr:
    .word   gdt_table_end - gdt_table - 1
    .long   gdt_table

# ============================================================================
# gdt_load: 加载 GDT，重新加载段寄存器
# ============================================================================
    .section .text
    .globl  gdt_load
gdt_load:
    lgdt    [gdt_ptr]

    # 重新加载 CS: 远跳转
    lea     eax, [1f]
    push    0x08                # 内核代码段选择子
    push    eax
    retf                        # 远返回 = 跳转

1:
    # 重新加载数据段寄存器
    mov     ax, 0x10            # 内核数据段选择子
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax

    ret
