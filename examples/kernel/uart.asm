    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# uart.asm - 16550 UART 串口驱动 (COM1, 115200 baud, 8N1)
# -----------------------------------------------------------------------------
    .code32

UART_BASE   = 0x3F8           # COM1 I/O base

# ============================================================================
# uart_init: 初始化 COM1 串口
# -----------------------------------------------------------------------------
# 波特率: 115200 (divisor = 115200/115200 = 1)
# 格式: 8N1 (8 data, no parity, 1 stop)
# FIFO: enabled, 14-byte trigger
# 中断: disabled
# ============================================================================
    .section .text
    .globl  uart_init
uart_init:
    push    edx
    push    eax

    # 1. Disable all interrupts (IER = 0x00)
    mov     dx, UART_BASE + 1
    xor     al, al
    out     dx, al

    # 2. Enable DLAB (LCR bit 7 = 1)
    mov     dx, UART_BASE + 3
    mov     al, 0x80
    out     dx, al

    # 3. Set divisor: low byte = 1, high byte = 0 (115200 baud)
    mov     dx, UART_BASE + 0
    mov     al, 0x01
    out     dx, al
    mov     dx, UART_BASE + 1
    xor     al, al
    out     dx, al

    # 4. Set 8N1, disable DLAB (LCR = 0x03)
    mov     dx, UART_BASE + 3
    mov     al, 0x03
    out     dx, al

    mov     dx, UART_BASE + 4
    mov     al, 0x03
    out     dx, al

    pop     eax
    pop     edx
    ret

# ============================================================================
# uart_putc: 向串口发送一个字符
# 输入: al = 字符
# 输出: 无
# 破坏: eax, edx
# ============================================================================
    .globl  uart_putc
uart_putc:
    push    edx
    push    eax

    mov     dx, UART_BASE + 5     # LSR
1:  in      al, dx
    test    al, 0x20              # THRE (bit 5): transmit holding register empty
    jz      1b

    pop     eax
    mov     dx, UART_BASE + 0     # THR
    out     dx, al
    pop     edx
    ret

# ============================================================================
# uart_getc: 从串口读取一个字符（阻塞）
# 输入: 无
# 输出: al = 字符
# 破坏: eax, edx
# ============================================================================
    .globl  uart_getc
uart_getc:
    push    edx

    mov     dx, UART_BASE + 5     # LSR
1:  in      al, dx
    test    al, 0x01              # DR (bit 0): data ready
    jz      1b

    mov     dx, UART_BASE + 0     # RBR
    in      al, dx
    pop     edx
    ret

# ============================================================================
# uart_puts: 向串口发送 null-terminated 字符串
# 输入: esi = 字符串指针
# 输出: 无
# 破坏: eax, edx, esi
# ============================================================================
    .globl  uart_puts
uart_puts:
    push    eax
1:  mov     al, [esi]
    test    al, al
    jz      2f
    push    esi
    call    uart_putc
    pop     esi
    inc     esi
    jmp     1b
2:  pop     eax
    ret
