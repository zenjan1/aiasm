    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# shell.asm - 命令行交互界面（串口终端）
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# BSS
# ============================================================================
    .section .bss
    .globl  shell_cmd_buf
shell_cmd_buf:
    .space  128
    .globl  shell_cmd_len
shell_cmd_len:
    .space  4
    .globl  shell_cursor_pos    # 当前光标在缓冲中的位置（支持左右移动）
shell_cursor_pos:
    .space  4
    .globl  shell_history_buf   # 上一条命令缓冲区 (128 字节)
shell_history_buf:
    .space  128

# ============================================================================
# shell_run: 主循环（串口终端）
# ============================================================================
    .section .text
    .globl  shell_run
shell_run:
    # 打印提示符（串口 + VGA）
    mov     esi, offset shell_prompt
    call    uart_puts
    mov     esi, offset shell_prompt
    call    vga_print_string_len

    # 清空命令缓冲
    xor     eax, eax
    mov     [shell_cmd_len], eax
    mov     [shell_cursor_pos], eax

1:  # 读取字符（串口输入）
    call    uart_getc

    cmp     al, 0x1B          # ESC — 可能是方向键
    je      .escape_seq
    cmp     al, 0x08          # 退格
    je      .backspace
    cmp     al, 0x7F          # 退格
    je      .backspace
    cmp     al, 0x0D          # 回车
    je      .enter
    cmp     al, 0x0A          # 换行
    je      .enter
    cmp     al, 0x03          # Ctrl+C — 关机
    je      .ctrl_c
    cmp     al, 0x20          # 可打印字符起始
    jb      1b                # 忽略控制字符
    cmp     al, 0x7E
    ja      1b

    # 普通字符: 追加到缓冲末尾
    mov     ecx, [shell_cmd_len]
    cmp     ecx, 127
    jge     1b                # 缓冲满

    # 存入缓冲区
    mov     [shell_cmd_buf + ecx], al
    inc     ecx
    mov     [shell_cmd_len], ecx
    mov     [shell_cursor_pos], ecx

    # 回显（字符仍在 al 中）
    push    eax
    call    uart_putc         # 回显到串口
    pop     eax
    push    eax
    call    vga_putchar       # 回显到VGA
    pop     eax
    jmp     1b

.escape_seq:
    # 读取 ESC [ X 序列
    call    uart_getc
    cmp     al, '['
    jne     1b                # 不是 [ 开头的 ESC 序列，忽略

    call    uart_getc
    cmp     al, 'A'           # 上箭头
    je      .arrow_up
    cmp     al, 'B'           # 下箭头
    je      .arrow_down
    cmp     al, 'C'           # 右箭头
    je      .arrow_right
    cmp     al, 'D'           # 左箭头
    je      .arrow_left
    jmp     1b                # 其他 ESC 序列，忽略

.arrow_up:
    # 从历史缓冲区恢复上一条命令
    mov     esi, offset shell_history_buf
    mov     edi, offset shell_cmd_buf
    mov     ecx, 128
    cld
    rep     movsb

    # 计算长度
    mov     esi, offset shell_cmd_buf
    call    utils_strlen
    mov     [shell_cmd_len], eax
    mov     [shell_cursor_pos], eax

    # 回显整行
    test    eax, eax
    jz      9f
    mov     esi, offset shell_cmd_buf
    mov     ecx, eax
4:  movzx   eax, byte ptr [esi]
    push    eax
    call    uart_putc
    pop     eax
    push    eax
    call    vga_putchar
    pop     eax
    inc     esi
    dec     ecx
    jnz     4b
9:  jmp     1b

.arrow_down:
    # 清空缓冲区（没有历史可前进）
    xor     eax, eax
    mov     [shell_cmd_len], eax
    mov     [shell_cursor_pos], eax
    jmp     1b

.arrow_right:
    # 光标右移
    mov     ecx, [shell_cursor_pos]
    cmp     ecx, [shell_cmd_len]
    jge     1b
    inc     dword ptr [shell_cursor_pos]
    # 串口光标右移 (ANSI)
    mov     esi, offset ansi_cursor_right
    call    uart_puts
    jmp     1b

.arrow_left:
    # 光标左移
    mov     ecx, [shell_cursor_pos]
    test    ecx, ecx
    jz      1b
    dec     dword ptr [shell_cursor_pos]
    # 串口光标左移 (ANSI)
    mov     esi, offset ansi_cursor_left
    call    uart_puts
    jmp     1b

.backspace:
    mov     ecx, [shell_cmd_len]
    test    ecx, ecx
    jz      1b                # 缓冲为空
    dec     ecx
    mov     [shell_cmd_len], ecx
    mov     [shell_cursor_pos], ecx

    # 末尾补空格（覆盖最后一个字符）
    mov     byte ptr [shell_cmd_buf + ecx], ' '

    # 回显退格序列（串口）
    mov     al, 0x08
    call    uart_putc
    mov     al, ' '
    call    uart_putc
    mov     al, 0x08
    call    uart_putc

    # VGA退格：回退光标
    mov     eax, [vga_cursor]
    test    eax, eax
    jz      1b
    dec     eax
    mov     [vga_cursor], eax
    call    vga_set_cursor_hw

    jmp     1b

.enter:
    # 终止字符串
    mov     ecx, [shell_cmd_len]
    lea     edx, [shell_cmd_buf + ecx]
    mov     byte ptr [edx], 0

    # 保存到历史缓冲区
    mov     esi, offset shell_cmd_buf
    mov     edi, offset shell_history_buf
    mov     ecx, 128
    cld
    rep     movsb

    # 打印换行（串口 + VGA）
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    mov     al, 0x0a
    call    vga_putchar
    mov     al, 0x0d
    call    vga_putchar

    # 分发命令
    call    shell_dispatch

    # 新提示符（串口 + VGA）
    mov     esi, offset shell_prompt
    call    uart_puts
    mov     esi, offset shell_prompt
    call    vga_print_string_len

    # 重置缓冲
    xor     eax, eax
    mov     [shell_cmd_len], eax
    mov     [shell_cursor_pos], eax

    jmp     1b

.ctrl_c:
    # 打印 "^C" 然后关机
    mov     al, '^'
    call    uart_putc
    mov     al, 'C'
    call    uart_putc
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    jmp     kernel_halt

# ============================================================================
# vga_print_string_len: VGA 输出指定长度字符串
# 输入: esi = 字符串指针, ecx = 长度
# （shell 内部使用，因为历史回显等场景已知长度但无 null 终止）
# ============================================================================
    .globl  vga_print_string_len
vga_print_string_len:
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
# shell_dispatch: 命令分发
# ============================================================================
    .globl  shell_dispatch
shell_dispatch:
    push    esi
    push    edi
    push    ecx

    mov     esi, offset shell_cmd_buf

    # "help"
    mov     edi, offset cmd_help
    call    utils_strcmp
    test    eax, eax
    jz      .do_help

    # "clear"
    mov     edi, offset cmd_clear
    call    utils_strcmp
    test    eax, eax
    jz      .do_clear

    # "version"
    mov     edi, offset cmd_version
    call    utils_strcmp
    test    eax, eax
    jz      .do_version

    # "tick"
    mov     edi, offset cmd_tick
    call    utils_strcmp
    test    eax, eax
    jz      .do_tick

    # "reboot"
    mov     edi, offset cmd_reboot
    call    utils_strcmp
    test    eax, eax
    jz      .do_reboot

    # "shutdown"
    mov     edi, offset cmd_shutdown
    call    utils_strcmp
    test    eax, eax
    jz      .do_shutdown

    # "echo <text>" - prefix match (5 chars: "echo ")
    mov     edi, offset cmd_echo_prefix
    mov     ecx, 5
    call    utils_strncmp
    test    eax, eax
    jz      .do_echo

    # 未知命令
    mov     esi, offset msg_unknown
    call    uart_puts
    mov     esi, offset shell_cmd_buf
    call    utils_strlen
    push    eax
    push    esi
    call    uart_puts
    pop     esi
    pop     ecx
    # 换行
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    pop     ecx
    pop     edi
    pop     esi
    ret

.do_help:
    mov     esi, offset help_text
    call    uart_puts
    mov     esi, offset help_text
    call    vga_print_string_len
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_clear:
    # ANSI 清屏（串口）
    mov     esi, offset ansi_clear
    call    uart_puts
    # VGA 清屏
    call    vga_clear
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_version:
    mov     esi, offset version_text
    call    uart_puts
    mov     esi, offset version_text
    call    vga_print_string_len
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_tick:
    call    get_tick_count
    push    eax
    mov     esi, offset tick_prefix
    call    uart_puts
    mov     esi, offset tick_prefix
    call    vga_print_string_len
    pop     eax
    lea     edi, [shell_cmd_buf]
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    utils_strlen
    mov     ecx, eax
    push    esi               # 保存 buffer 指针
    call    uart_puts
    pop     esi               # 恢复 buffer 指针
    call    vga_print_string_len
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_reboot:
    pop     ecx
    pop     edi
    pop     esi
    jmp     kernel_reboot

.do_shutdown:
    pop     ecx
    pop     edi
    pop     esi
    jmp     kernel_halt

.do_echo:
    # 跳过 "echo " 前缀 (5 字符)
    lea     esi, [shell_cmd_buf + 5]
    call    utils_strlen
    mov     ecx, eax
    cmp     ecx, 0
    je      .echo_done

    # 去除首尾双引号
    movzx   eax, byte ptr [esi]
    cmp     al, '"'
    jne     .echo_print
    dec     ecx             # 跳过开头引号
    inc     esi
    movzx   eax, byte ptr [esi + ecx - 1]
    cmp     al, '"'
    jne     .echo_print
    dec     ecx             # 跳过结尾引号

.echo_print:
    test    ecx, ecx
    jz      .echo_done
    # 临时 null 终止以便 uart_puts
    push    esi
    push    ecx
    mov     eax, esi
    add     eax, ecx
    push    eax
    mov     byte ptr [eax], 0
    call    uart_puts
    pop     eax
    pop     ecx
    pop     esi
    push    esi
    push    ecx
    call    vga_print_string_len
    pop     ecx
    pop     esi

.echo_done:
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

# ============================================================================
# 命令字符串
# ============================================================================
    .section .rodata

shell_prompt:
    .asciz  "aiasm> "

cmd_help:
    .asciz  "help"
cmd_clear:
    .asciz  "clear"
cmd_version:
    .asciz  "version"
cmd_tick:
    .asciz  "tick"
cmd_reboot:
    .asciz  "reboot"
cmd_shutdown:
    .asciz  "shutdown"
cmd_echo_prefix:
    .asciz  "echo "

version_text:
    .ascii  "AI-ASM Kernel v0.2"
    .byte   13, 10, 0

help_text:
    .ascii  "Commands:"
    .byte   13, 10
    .ascii  "  help          - Show this help"
    .byte   13, 10
    .ascii  "  clear         - Clear screen"
    .byte   13, 10
    .ascii  "  echo <text>   - Print text"
    .byte   13, 10
    .ascii  "  version       - Show version"
    .byte   13, 10
    .ascii  "  tick          - Show system tick count"
    .byte   13, 10
    .ascii  "  reboot        - Reboot system"
    .byte   13, 10
    .ascii  "  shutdown      - Halt system"
    .byte   13, 10, 0

tick_prefix:
    .asciz  "System ticks: "

msg_unknown:
    .asciz  "Unknown command: "

ansi_clear:
    .byte   0x1B, '[', '2', 'J', 0x1B, '[', 'H', 0

ansi_cursor_right:
    .byte   0x1B, '[', 'C', 0

ansi_cursor_left:
    .byte   0x1B, '[', 'D', 0
