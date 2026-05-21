    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# pit.asm - PIT 定时器 (IRQ0, 100Hz)
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# BSS
# ============================================================================
    .section .bss
    .globl  tick_count
tick_count:
    .space  4

# ============================================================================
# pit_init: 初始化 PIT channel 0, mode 3, ~100Hz
# ============================================================================
    .section .text
    .globl  pit_init
pit_init:
    push    eax
    push    edx

    # 注册 IRQ0 处理函数
    mov     edi, 0
    mov     eax, offset pit_irq_handler
    call    idt_set_gate

    # 编程 PIT: channel 0, mode 3, binary
    mov     al, 0x36
    out     0x43, al

    # divisor = 1193180 / 100 = 11932
    mov     ax, 11932
    out     0x40, al            # low byte
    mov     al, ah
    out     0x40, al            # high byte

    pop     edx
    pop     eax
    ret

# ============================================================================
# pit_irq_handler: IRQ0 处理 - 增加 tick 计数，发送 EOI
# ============================================================================
    .globl  pit_irq_handler
pit_irq_handler:
    inc     dword ptr [tick_count]
    mov     eax, 0              # IRQ0
    jmp     pic_send_eoi

# ============================================================================
# get_tick_count: 返回当前 tick 数
# 输出: eax = tick count
# ============================================================================
    .globl  get_tick_count
get_tick_count:
    mov     eax, [tick_count]
    ret
