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

    # "meminfo"
    mov     edi, offset cmd_meminfo
    call    utils_strcmp
    test    eax, eax
    jz      .do_meminfo

    # "ps"
    mov     edi, offset cmd_ps
    call    utils_strcmp
    test    eax, eax
    jz      .do_ps

    # "wasm" - show WASM module info
    mov     edi, offset cmd_wasm
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasm

    # "wasmrun" - run WASM test
    mov     edi, offset cmd_wasmrun
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmrun

    # "wasmtest2" - WASM const add test (3+5=8)
    mov     edi, offset cmd_wasmtest2
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest2

    # "wasmtest3" - WASM loop test (countdown 5->0)
    mov     edi, offset cmd_wasmtest3
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest3

    # "wasmtest4" - WASM syscall test (host_putchar 'A')
    mov     edi, offset cmd_wasmtest4
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest4

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

.do_meminfo:
    # 打印 "Memory: "
    mov     esi, offset meminfo_prefix
    call    uart_puts

    # 获取总内存（KB）
    call    get_total_memory
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    # 打印 "KB total, "
    mov     esi, offset meminfo_total_suffix
    call    uart_puts

    # 获取可用内存（KB）
    call    get_free_memory
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    # 打印 "KB free\n"
    mov     esi, offset meminfo_free_suffix
    call    uart_puts
    pop     eax
    pop     eax                 # clean up the first saved eax

    # 打印进程数
    mov     esi, offset meminfo_procs
    call    uart_puts
    call    get_proc_count
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    mov     esi, offset meminfo_procs_suffix
    call    uart_puts
    pop     eax

    pop     ecx
    pop     edi
    pop     esi
    ret

.do_ps:
    mov     esi, offset ps_header
    call    uart_puts

    xor     ebx, ebx            # 进程索引
.ps_loop:
    cmp     ebx, 16
    jge     .ps_done

    mov     eax, ebx
    imul    eax, 256            # PCB_SIZE
    add     eax, offset proc_table

    # 检查进程状态
    mov     esi, [eax]          # PID
    cmp     esi, -1
    je      .ps_next            # 未分配

    # 打印 PID (esi = PID)
    push    esi                 # 保存 PID
    mov     edi, offset shell_cmd_buf
    mov     eax, esi
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    pop     esi                 # 恢复 PID

    mov     esi, offset ps_space
    call    uart_puts

    # 状态
    mov     edi, [eax + 4]      # state (注意 eax 已被 utils_itoa 修改)
    # 需要重新计算 PCB 地址
    mov     edi, ebx
    imul    edi, 256
    add     edi, offset proc_table
    mov     ecx, [edi + 4]      # state

    cmp     ecx, 1
    je      .ps_running
    cmp     ecx, 2
    je      .ps_ready
    cmp     ecx, 3
    je      .ps_zombie
    mov     esi, offset ps_dash
    call    uart_puts
    jmp     .ps_state_done

.ps_running:
    mov     esi, offset ps_run_str
    call    uart_puts
    jmp     .ps_state_done

.ps_ready:
    mov     esi, offset ps_ready_str
    call    uart_puts
    jmp     .ps_state_done

.ps_zombie:
    mov     esi, offset ps_zombie_str
    call    uart_puts

.ps_state_done:
    mov     esi, offset ps_space
    call    uart_puts

    # PPID
    mov     edi, ebx
    imul    edi, 256
    add     edi, offset proc_table
    mov     eax, [edi + 76]     # PPID
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     esi, offset ps_newline
    call    uart_puts

.ps_next:
    inc     ebx
    jmp     .ps_loop

.ps_done:
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_wasm:
    # 打印 WASM 模块信息
    call    wasm_print_info
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_wasmrun:
    # 运行内置测试 WASM 模块
    mov     esi, offset msg_wasm_test
    call    uart_puts

    # 加载测试模块（手工编码的简单加法函数）
    mov     esi, offset wasm_test_module
    mov     ecx, 32              # wasm_test_module size (hardcoded)
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err

    # 打印解析结果
    call    wasm_print_info
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # 执行函数 0
    xor     eax, eax
    call    wasm_exec_func

    # 打印结果
    mov     esi, offset msg_wasm_result
    call    uart_puts
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    pop     eax
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    pop     ecx
    pop     edi
    pop     esi
    ret

.wasm_parse_err:
    mov     esi, offset msg_wasm_parse_err
    call    uart_puts
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_wasmtest2:
    mov     esi, offset msg_wasm_test2
    call    uart_puts
    mov     esi, offset wasm_test_add_module
    mov     ecx, 27              # wasm_test_add_module size (hardcoded)
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_print_info
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_wasm_result
    call    uart_puts
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    pop     eax
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_wasmtest3:
    mov     esi, offset msg_wasm_test3
    call    uart_puts
    mov     esi, offset wasm_test_loop_module
    mov     ecx, offset wasm_test_loop_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_print_info
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_wasm_result
    call    uart_puts
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    pop     eax
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_wasmtest4:
    mov     esi, offset msg_wasm_test4
    call    uart_puts
    mov     esi, offset wasm_test_syscall_module
    mov     ecx, offset wasm_test_syscall_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_print_info
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_wasm_result
    call    uart_puts
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    pop     eax
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

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
cmd_meminfo:
    .asciz  "meminfo"
cmd_ps:
    .asciz  "ps"
cmd_wasm:
    .asciz  "wasm"
cmd_wasmrun:
    .asciz  "wasmrun"
cmd_wasmtest2:
    .asciz  "wasmtest2"
cmd_wasmtest3:
    .asciz  "wasmtest3"
cmd_wasmtest4:
    .asciz  "wasmtest4"
cmd_echo_prefix:
    .asciz  "echo "

version_text:
    .ascii  "AI-ASM Kernel v0.4"
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
    .byte   13, 10
    .ascii  "  meminfo       - Show memory info"
    .byte   13, 10
    .ascii  "  ps            - Show process list"
    .byte   13, 10
    .ascii  "  wasm          - Show WASM module info"
    .byte   13, 10
    .ascii  "  wasmrun       - Run WASM test module"
    .byte   13, 10
    .ascii  "  wasmtest2     - Run WASM const test (returns 42)"
    .byte   13, 10
    .ascii  "  wasmtest3     - Run WASM loop test (countdown)"
    .byte   13, 10
    .ascii  "  wasmtest4     - Run WASM syscall test (putchar 'A')"
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

# meminfo 输出字符串
meminfo_prefix:
    .asciz  "Memory: "
meminfo_total_suffix:
    .asciz  "KB total, "
meminfo_free_suffix:
    .asciz  "KB free\r\n"
meminfo_procs:
    .asciz  "Processes: "
meminfo_procs_suffix:
    .asciz  "\r\n"

# ps 输出字符串
ps_header:
    .asciz  "PID  STATE  PPID\r\n"
ps_space:
    .asciz  "  "
ps_dash:
    .asciz  "-"
ps_run_str:
    .asciz  "RUN"
ps_ready_str:
    .asciz  "RDY"
ps_zombie_str:
    .asciz  "ZOM"
ps_newline:
    .asciz  "\r\n"
ps_debug_prefix:
    .asciz  "current_pid = "

# WASM 相关字符串
msg_wasm_test:
    .asciz  "Running WASM test module (local.get add)...\r\n"
msg_wasm_test2:
    .asciz  "Running WASM test2 (const 42)...\r\n"
msg_wasm_test3:
    .asciz  "Running WASM test3 (loop countdown)...\r\n"
msg_wasm_test4:
    .asciz  "Running WASM test4 (syscall: putchar 'A')...\r\n"
msg_wasm_result:
    .asciz  "Result: "
msg_wasm_parse_err:
    .asciz  "WASM parse error\r\n"

# WASM 测试模块 1：简单加法 (local.get 0 + local.get 1)
# WASM 格式：
#   magic: 0x00 0x61 0x73 0x6D
#   version: 0x01 0x00 0x00 0x00
#   type section content: 01 60 02 7F 7F 01 7F = 7 bytes (num types + func type + params + results)
#   function section: 03 02 01 00  (1 function, type 0)
#   code section: 0A 09 01 07 00 20 00 20 01 6A 0B
wasm_test_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section (id=1, size=7)
    .byte   0x01                   # section id
    .byte   0x07                   # section size (corrected: 7 bytes)
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x02                   # num params
    .byte   0x7F                   # i32
    .byte   0x7F                   # i32
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section (id=3, size=2)
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index
    # code section (id=10, size=9)
    .byte   0x0A                   # section id
    .byte   0x09                   # section size
    .byte   0x01                   # num codes
    .byte   0x07                   # code size
    .byte   0x00                   # num locals
    .byte   0x20, 0x00             # local.get 0
    .byte   0x20, 0x01             # local.get 1
    .byte   0x6A                   # i32.add
    .byte   0x0B                   # end
wasm_test_module_size = . - wasm_test_module

# WASM 测试模块 2：返回常量 42
# type section content: 01 60 00 01 7F = 5 bytes (num types + func type + 0 params + 1 result)
wasm_test_add_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section (id=1, size=5)
    .byte   0x01                   # section id
    .byte   0x05                   # section size (corrected: 5 bytes)
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section (id=3, size=2)
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index
    # code section (id=10, size=6)
    # code body = 00 (num locals) + 41 2A (i32.const 42) + 0B (end) = 4 bytes
    # section content = 01 (num codes) + 04 (code size) + code body = 6 bytes
    .byte   0x0A                   # section id
    .byte   0x06                   # section size = 6
    .byte   0x01                   # num codes
    .byte   0x04                   # code size = 4
    .byte   0x00                   # num locals
    .byte   0x41, 0x2A             # i32.const 42
    .byte   0x0B                   # end
wasm_test_add_size = . - wasm_test_add_module

# WASM 测试模块 3：循环计数 (countdown from 5 to 0)
# type section content: 01 60 00 01 7F = 5 bytes
# code body: 25 bytes (locals 3 + init 4 + loop body 14 + return 3 + ends 1)
# code section content: 01 + 19 + 25 bytes = 27 bytes
wasm_test_loop_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section (id=1, size=5)
    .byte   0x01                   # section id
    .byte   0x05                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section (id=3, size=2)
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index
    # code section (id=10, size=27)
    .byte   0x0A                   # section id
    .byte   0x1B                   # section size = 27
    .byte   0x01                   # num codes
    .byte   0x19                   # code size = 25
    .byte   0x01                   # 1 local declaration
    .byte   0x01, 0x7F             # 1 local of type i32
    .byte   0x41, 0x05             # i32.const 5
    .byte   0x21, 0x00             # local.set 0
    .byte   0x03, 0x40             # loop (block type void)
    .byte   0x20, 0x00             # local.get 0
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x6B                   # i32.sub
    .byte   0x21, 0x00             # local.set 0
    .byte   0x20, 0x00             # local.get 0
    .byte   0x45                   # i32.eqz
    .byte   0x0D, 0x00             # br_if 0
    .byte   0x0B                   # end (loop)
    .byte   0x20, 0x00             # local.get 0
    .byte   0x0B                   # end (function)
wasm_test_loop_size = . - wasm_test_loop_module

# WASM 测试模块 4：系统调用测试 (host_putchar 'A')
# 函数 0: void -> i32, calls host function 1 (putchar) with arg 65
# Host functions start at index 1 (after the 1 module function)
wasm_test_syscall_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section (id=1, size=4): () -> i32
    .byte   0x01                   # section id
    .byte   0x04                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section (id=3, size=2): 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section (id=10, size=7)
    # code body: 00 (num locals) + 41 41 (i32.const 65) + 10 01 (call 1=host_putchar) + 0B (end)
    .byte   0x0A                   # section id
    .byte   0x07                   # section size = 7
    .byte   0x01                   # num codes
    .byte   0x05                   # code size = 5
    .byte   0x00                   # num locals
    .byte   0x41, 0x41             # i32.const 65 ('A')
    .byte   0x10, 0x03             # call 3 (host slot 2 = putchar, since func_count=1)
    .byte   0x0B                   # end
wasm_test_syscall_size = . - wasm_test_syscall_module
