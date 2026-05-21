    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# vga.asm - VGA 文本模式驱动 (0xB8000, 80x25)
# -----------------------------------------------------------------------------
    .code32

VGA_BASE    = 0xB8000
VGA_COLS    = 80
VGA_ROWS    = 25
VGA_SIZE    = 2000
VGA_ATTR    = 0x07            # 浅灰 on 黑

# ============================================================================
# BSS 变量
# ============================================================================
    .section .bss
    .globl  vga_cursor
vga_cursor:
    .space  4
    .globl  vga_attr
vga_attr:
    .space  1

# ============================================================================
# vga_clear: 清屏，光标归零
# ============================================================================
    .section .text
    .globl  vga_clear
vga_clear:
    push    eax
    push    ecx
    push    edi

    mov     edi, VGA_BASE
    mov     ecx, VGA_SIZE
    mov     al, ' '
    mov     ah, VGA_ATTR
1:  mov     [edi], ax
    add     edi, 2
    dec     ecx
    jnz     1b

    mov     dword ptr [vga_cursor], 0
    call    vga_set_cursor_hw

    pop     edi
    pop     ecx
    pop     eax
    ret

# ============================================================================
# vga_putchar: 输出一个字符 (al)
# ============================================================================
    .globl  vga_putchar
vga_putchar:
    push    eax
    push    edx
    push    ecx
    push    ebx

    cmp     al, 0x0a          # 换行
    je      .newline
    cmp     al, 0x0d          # 回车
    je      .carriage_ret

    mov     ebx, [vga_cursor]
    mov     edx, VGA_BASE
    lea     edx, [edx + ebx * 2]
    mov     [edx], al
    mov     byte ptr [edx + 1], VGA_ATTR
    inc     dword ptr [vga_cursor]
    jmp     .check_scroll

.newline:
    mov     ebx, [vga_cursor]
    mov     eax, ebx
    mov     ecx, VGA_COLS
    xor     edx, edx
    div     ecx
    inc     eax
    imul    ebx, eax, VGA_COLS
    mov     [vga_cursor], ebx
    jmp     .check_scroll

.carriage_ret:
    mov     ebx, [vga_cursor]
    mov     eax, ebx
    mov     ecx, VGA_COLS
    xor     edx, edx
    div     ecx
    imul    ebx, eax, VGA_COLS
    mov     [vga_cursor], ebx

.check_scroll:
    mov     ebx, [vga_cursor]
    cmp     ebx, VGA_SIZE
    jl      .done
    call    vga_scroll
    jmp     .done

.done:
    call    vga_set_cursor_hw
    pop     ebx
    pop     ecx
    pop     edx
    pop     eax
    ret

# ============================================================================
# vga_scroll: 向上滚动一行
# ============================================================================
    .globl  vga_scroll
vga_scroll:
    push    eax
    push    ecx
    push    edi
    push    esi

    # 将第 1-24 行复制到第 0-23 行 (160 字节偏移, 3840 字节)
    mov     esi, VGA_BASE + 160
    mov     edi, VGA_BASE
    mov     ecx, 1920         # 3840 / 2 (按 word 移动)
    cld
    rep     movsw

    # 清空最后一行 (偏移 3840)
    mov     edi, VGA_BASE + 3840
    mov     ecx, 40           # 80 cells / 2 = 40 dwords
    mov     eax, 0x07200720   # ' ' + attr 重复
    rep     stosd

    # cursor -= 80
    mov     eax, [vga_cursor]
    sub     eax, VGA_COLS
    mov     [vga_cursor], eax

    pop     esi
    pop     edi
    pop     ecx
    pop     eax
    ret

# ============================================================================
# vga_print_string: 输出字符串 (esi=str, ecx=len)
# ============================================================================
    .globl  vga_print_string
vga_print_string:
    push    edx
    push    ecx
    push    esi
1:  cmp     ecx, 0
    je      2f
    mov     al, [esi]
    push    eax
    call    vga_putchar
    pop     eax
    inc     esi
    dec     ecx
    jmp     1b
2:  pop     esi
    pop     ecx
    pop     edx
    ret

# ============================================================================
# vga_set_cursor_hw: 更新硬件光标 (端口 0x3D4/0x3D5)
# ============================================================================
    .globl  vga_set_cursor_hw
vga_set_cursor_hw:
    push    eax
    push    edx

    mov     eax, [vga_cursor]
    mov     edx, 0x3D4
    mov     al, 0x0E          # 光标位置高字节寄存器
    out     dx, al
    mov     edx, 0x3D5
    mov     al, ah
    out     dx, al

    mov     eax, [vga_cursor]
    mov     edx, 0x3D4
    mov     al, 0x0F          # 光标位置低字节寄存器
    out     dx, al
    mov     edx, 0x3D5
    out     dx, al

    pop     edx
    pop     eax
    ret

# ============================================================================
# vga_print_string_panic: 红色 panic 信息 (esi=str, ecx=len)
# ============================================================================
    .globl  vga_print_string_panic
vga_print_string_panic:
    push    eax
    push    ebx
    push    edx
    push    ecx
    push    esi

    mov     byte ptr [vga_attr], 0x4C  # 红 on 亮红

    push    esi
    mov     esi, offset panic_prefix
    mov     ecx, panic_prefix_len
    call    vga_print_string
    pop     esi

    # 保存原光标
    mov     ebx, [vga_cursor]

1:  cmp     ecx, 0
    je      2f
    mov     al, [esi]
    push    eax
    call    vga_putchar
    pop     eax
    inc     esi
    dec     ecx
    jmp     1b

2:  # 恢复原光标继续写
    mov     [vga_cursor], ebx

    mov     byte ptr [vga_attr], VGA_ATTR

    pop     esi
    pop     ecx
    pop     edx
    pop     ebx
    pop     eax
    ret

    .section .rodata
panic_prefix:
    .ascii  "PANIC: "
panic_prefix_len = . - panic_prefix
