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

# ============================================================================
# shell_run: 主循环（串口终端）
# ============================================================================
    .section .text
    .globl  shell_run
shell_run:
    # 打印提示符
    mov     esi, offset shell_prompt
    mov     ecx, shell_prompt_len
    call    serial_print_string

    # 清空命令缓冲
    xor     eax, eax
    mov     [shell_cmd_len], eax

1:  # 读取字符
    call    keyboard_getchar

    cmp     al, 0x08          # 退格
    je      .backspace
    cmp     al, 0x7F          # 退格
    je      .backspace
    cmp     al, 0x0D          # 回车
    je      .enter
    cmp     al, 0x0A          # 换行
    je      .enter
    cmp     al, 0x20          # 可打印字符起始
    jb      1b                # 忽略控制字符
    cmp     al, 0x7E
    ja      1b

    # 普通字符: 追加到缓冲并回显
    push    eax
    mov     ecx, [shell_cmd_len]
    cmp     ecx, 127
    jge     1b                # 缓冲满
    lea     edx, [shell_cmd_buf + ecx]
    mov     [edx], al
    inc     ecx
    mov     [shell_cmd_len], ecx
    pop     eax
    push    eax
    call    serial_putchar    # 回显到串口
    pop     eax
    jmp     1b

.backspace:
    mov     ecx, [shell_cmd_len]
    cmp     ecx, 0
    je      1b
    dec     ecx
    mov     [shell_cmd_len], ecx

    # 回显退格序列
    mov     al, 0x08
    call    serial_putchar
    mov     al, ' '
    call    serial_putchar
    mov     al, 0x08
    call    serial_putchar

    jmp     1b

.enter:
    # 终止字符串
    mov     ecx, [shell_cmd_len]
    lea     edx, [shell_cmd_buf + ecx]
    mov     byte ptr [edx], 0

    # 打印换行
    mov     al, 0x0a
    call    serial_putchar
    mov     al, 0x0d
    call    serial_putchar

    # 分发命令
    call    shell_dispatch

    # 新提示符
    mov     esi, offset shell_prompt
    mov     ecx, shell_prompt_len
    call    serial_print_string

    # 重置缓冲
    xor     eax, eax
    mov     [shell_cmd_len], eax

    jmp     1b

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

    # "echo <text>"
    mov     edi, offset cmd_echo_prefix
    call    utils_strcmp
    test    eax, eax
    jz      .do_echo

    # 未知命令
    mov     esi, offset msg_unknown
    mov     ecx, msg_unknown_len
    call    serial_print_string
    mov     esi, offset shell_cmd_buf
    call    utils_strlen
    mov     ecx, eax
    call    serial_print_string
    mov     al, 0x0a
    call    serial_putchar
    mov     al, 0x0d
    call    serial_putchar

    pop     ecx
    pop     edi
    pop     esi
    ret

.do_help:
    mov     esi, offset help_text
    mov     ecx, help_text_len
    call    serial_print_string
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_clear:
    # ANSI 清屏
    mov     esi, offset ansi_clear
    mov     ecx, ansi_clear_len
    call    serial_print_string
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_version:
    mov     esi, offset version_text
    mov     ecx, version_text_len
    call    serial_print_string
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_tick:
    call    get_tick_count
    push    eax
    mov     esi, offset tick_prefix
    mov     ecx, tick_prefix_len
    call    serial_print_string
    pop     eax
    lea     edi, [shell_cmd_buf]
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    utils_strlen
    mov     ecx, eax
    call    serial_print_string
    mov     al, 0x0a
    call    serial_putchar
    mov     al, 0x0d
    call    serial_putchar
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
    call    serial_print_string
.echo_done:
    mov     al, 0x0a
    call    serial_putchar
    mov     al, 0x0d
    call    serial_putchar
    pop     ecx
    pop     edi
    pop     esi
    ret

# ============================================================================
# 命令字符串
# ============================================================================
    .section .rodata

shell_prompt:
    .ascii  "aiasm> "
shell_prompt_len = . - shell_prompt

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
    .byte   13, 10
version_text_len = . - version_text

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
    .byte   13, 10
help_text_len = . - help_text

tick_prefix:
    .ascii  "System ticks: "
tick_prefix_len = . - tick_prefix

msg_unknown:
    .ascii  "Unknown command: "
msg_unknown_len = . - msg_unknown

ansi_clear:
    .byte   0x1B, '[', '2', 'J', 0x1B, '[', 'H'
ansi_clear_len = . - ansi_clear
