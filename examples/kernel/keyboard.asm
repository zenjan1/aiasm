    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# keyboard.asm - PS/2 键盘驱动 (IRQ1)
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# BSS
# ============================================================================
    .section .bss
    .globl  kbd_buffer
kbd_buffer:
    .space  64                # 循环缓冲区
    .globl  kbd_head
kbd_head:
    .space  4
    .globl  kbd_tail
kbd_tail:
    .space  4

kbd_in_break:
    .space  1
kbd_shift:
    .space  1
kbd_caps:
    .space  1

# ============================================================================
# 扫描码表 (scan code set 1, 0-0x57)
# ============================================================================
    .section .rodata
kbd_scancode_table:
    # 0x00
    .byte   0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0, 0
    # 0x10
    .byte   'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0, 0
    # 0x1E
    .byte   'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0, 0
    # 0x2C
    .byte   'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, 0, 0, ' ', 0
    # 0x3B-0x57 (F1-F12, etc) - skip for now
kbd_scancode_table_end:

# ============================================================================
# keyboard_init: 注册 IRQ1 处理函数
# ============================================================================
    .section .text
    .globl  keyboard_init
keyboard_init:
    push    edi
    push    eax

    xor     eax, eax
    mov     [kbd_head], eax
    mov     [kbd_tail], eax
    mov     byte ptr [kbd_in_break], 0
    mov     byte ptr [kbd_shift], 0
    mov     byte ptr [kbd_caps], 0

    # 注册 IRQ1
    mov     edi, 1
    mov     eax, offset keyboard_irq_handler
    call    idt_set_gate

    pop     eax
    pop     edi
    ret

# ============================================================================
# keyboard_irq_handler: IRQ1 处理
# ============================================================================
    .globl  keyboard_irq_handler
keyboard_irq_handler:
    push    eax
    push    edx

    # 读取扫描码
    in      al, 0x60

    # 判断 break code (0xF0)
    cmp     al, 0xF0
    je      .set_break

    # 如果之前在 break 状态，忽略 (键释放)
    cmp     byte ptr [kbd_in_break], 0
    jne     .clear_break_and_exit

    # Shift 按下
    cmp     al, 0x2A            # left shift
    je      .shift_down
    cmp     al, 0x36            # right shift
    je      .shift_down

    # Shift 释放
    cmp     al, 0xAA            # left shift release
    je      .shift_up
    cmp     al, 0xB6            # right shift release
    je      .shift_up

    # Caps Lock
    cmp     al, 0x3A
    jne     .not_caps
    mov     bl, [kbd_caps]
    xor     bl, 1
    mov     [kbd_caps], bl
    jmp     .send_eoi

.not_caps:
    # 查表转换扫描码
    cmp     al, 0x57
    ja      .send_eoi           # 超出范围

    xor     ah, ah
    lea     edx, [kbd_scancode_table + eax]
    mov     al, [edx]
    test    al, al
    jz      .send_eoi           # 无效键

    # 大小写转换
    cmp     al, 'a'
    jl      .no_case
    cmp     al, 'z'
    jg      .no_case

    # 是字母: 检查 shift/caps
    mov     bl, [kbd_shift]
    or      bl, [kbd_caps]
    test    bl, bl
    jz      .no_case
    and     al, 0xDF            # 转大写

.no_case:
    # 存入循环缓冲区
    push    eax
    mov     eax, [kbd_tail]
    mov     edx, [kbd_tail]
    inc     edx
    and     edx, 0x3F           # mod 64
    mov     [kbd_buffer + eax], al
    mov     [kbd_tail], edx
    pop     eax

.send_eoi:
    mov     eax, 1              # IRQ1
    jmp     pic_send_eoi

.set_break:
    mov     byte ptr [kbd_in_break], 1
    mov     eax, 1
    jmp     pic_send_eoi

.clear_break_and_exit:
    xor     eax, eax
    mov     [kbd_in_break], al
    mov     eax, 1
    jmp     pic_send_eoi

.shift_down:
    mov     byte ptr [kbd_shift], 1
    jmp     .send_eoi

.shift_up:
    mov     byte ptr [kbd_shift], 0
    jmp     .send_eoi

# ============================================================================
# keyboard_getchar: 阻塞读取字符
# 输出: al = 字符
# ============================================================================
    .globl  keyboard_getchar
keyboard_getchar:
1:  call    keyboard_haschar
    test    eax, eax
    jz      1b

    # 从缓冲区读取
    mov     eax, [kbd_head]
    movzx   eax, byte ptr [kbd_buffer + eax]
    mov     edx, [kbd_head]
    inc     edx
    and     edx, 0x3F
    mov     [kbd_head], edx
    ret

# ============================================================================
# keyboard_haschar: 检查缓冲区是否有字符
# 输出: eax = 1 有, 0 无
# ============================================================================
    .globl  keyboard_haschar
keyboard_haschar:
    mov     eax, [kbd_head]
    cmp     eax, [kbd_tail]
    jne     .has
    xor     eax, eax
    ret
.has:
    mov     eax, 1
    ret
