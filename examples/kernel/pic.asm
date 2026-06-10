    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# pic.asm - 8259A PIC 控制 (重映射 IRQ)
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# pic_remap: 重映射 IRQ 0-15 到中断向量 0x20-0x2F
# ============================================================================
    .section .text
    .globl  pic_remap
pic_remap:
    push    eax

    # ICW1: 初始化 + 需要 ICW4
    mov     al, 0x11
    out     0x20, al            # master
    out     0xA0, al            # slave

    # ICW2: 向量偏移
    mov     al, 0x20            # master IRQ 0-7 → 向量 0x20-0x27
    out     0x21, al
    mov     al, 0x28            # slave IRQ 8-15 → 向量 0x28-0x2F
    out     0xA1, al

    # ICW3: 级联信息
    mov     al, 0x04            # master: 从片在 IRQ2 (bit 2)
    out     0x21, al
    mov     al, 0x02            # slave: 级联标识 = 2
    out     0xA1, al

    # ICW4: 8086 模式
    mov     al, 0x01
    out     0x21, al
    out     0xA1, al

    # OCW1: 启用 IRQ0 (PIT) 和 IRQ1 (键盘)，屏蔽其余
    mov     al, 0xFC            # 11111100: IRQ0,1 启用
    out     0x21, al
    mov     al, 0x3F            # 屏蔽从片IRQ8-13，启用IRQ14(IDE1)/IRQ15(IDE2)
    out     0xA1, al

    pop     eax
    ret

# ============================================================================
# pic_send_eoi: 发送 EOI
# 输入：eax = IRQ 编号 (0-15，重映射前)
# ============================================================================
    .globl  pic_send_eoi
pic_send_eoi:
    cmp     eax, 8
    jl      .master
    # 从片 IRQ: 先发从片 EOI
    mov     al, 0x20
    out     0xA0, al
.master:
    mov     al, 0x20
    out     0x20, al            # master EOI
    ret
