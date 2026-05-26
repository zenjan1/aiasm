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
    .globl  shell_date_ticks    # 临时存储 tick 转秒数
shell_date_ticks:
    .space  4

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

    # "wasmtest5" - WASM br_table test (switch: index 2 -> 20)
    mov     edi, offset cmd_wasmtest5
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest5

    # "wasmtest6" - WASM byte memory test (store8/load8_u)
    mov     edi, offset cmd_wasmtest6
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest6

    # "kill <pid>" - 终止进程
    mov     edi, offset cmd_kill
    mov     ecx, 4
    call    utils_strncmp
    test    eax, eax
    jz      .do_kill

    # "date"
    mov     edi, offset cmd_date
    call    utils_strcmp
    test    eax, eax
    jz      .do_date

    # "ls"
    mov     edi, offset cmd_ls
    call    utils_strcmp
    test    eax, eax
    jz      .do_ls

    # "cat <file>" - prefix match (4 chars: "cat ")
    mov     edi, offset cmd_cat
    mov     ecx, 4
    call    utils_strncmp
    test    eax, eax
    jz      .do_cat

    # "touch <file>" - prefix match
    mov     edi, offset cmd_touch
    mov     ecx, 6
    call    utils_strncmp
    test    eax, eax
    jz      .do_touch

    # "wasmapp <name>" - WASM application launcher
    mov     edi, offset cmd_wasmapp
    mov     ecx, 7
    call    utils_strncmp
    test    eax, eax
    jz      .do_wasmapp

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
    call    wasm_load_data

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
    call    wasm_load_data
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
    call    wasm_load_data
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
    call    wasm_load_data
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

.do_wasmtest5:
    # br_table test (switch-case: hardcoded index 1 returns 20)
    mov     esi, offset msg_wasm_test5
    call    uart_puts
    mov     esi, offset wasm_test_brtable_module
    mov     ecx, offset wasm_test_brtable_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    call    wasm_print_info
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_brtable_result
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

.do_wasmtest6:
    # store8/load8 test: store byte 42 at addr 0, load and return
    mov     esi, offset msg_wasm_test6
    call    uart_puts
    mov     esi, offset wasm_test_mem8_module
    mov     ecx, offset wasm_test_mem8_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    call    wasm_print_info
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_mem8_result
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

.do_wasmapp:
    # 解析应用名称：跳过 "wasmapp " 前缀 (8 字符)
    mov     esi, offset shell_cmd_buf + 8
    call    utils_strlen
    mov     ecx, eax
    cmp     ecx, 0
    je      .wasmapp_usage

    # 比较 "uptime"
    mov     edi, offset cmd_wasmapp_uptime
    call    utils_strcmp
    test    eax, eax
    jz      .wasmapp_do_uptime

    # 比较 "sum"
    mov     edi, offset cmd_wasmapp_sum
    call    utils_strcmp
    test    eax, eax
    jz      .wasmapp_do_sum

    # 比较 "hello"
    mov     edi, offset cmd_wasmapp_hello
    call    utils_strcmp
    test    eax, eax
    jz      .wasmapp_do_hello

    # 比较 "fibonacci"
    mov     edi, offset cmd_wasmapp_fib
    call    utils_strcmp
    test    eax, eax
    jz      .wasmapp_do_fib

    # 比较 "factorial"
    mov     edi, offset cmd_wasmapp_fact
    call    utils_strcmp
    test    eax, eax
    jz      .wasmapp_do_fact

    # 比较 "multiply"
    mov     edi, offset cmd_wasmapp_mul
    call    utils_strcmp
    test    eax, eax
    jz      .wasmapp_do_mul

    # 比较 "countdown"
    mov     edi, offset cmd_wasmapp_count
    call    utils_strcmp
    test    eax, eax
    jz      .wasmapp_do_count

    # 未知应用
    mov     esi, offset msg_wasmapp_unknown
    call    uart_puts
    mov     esi, offset shell_cmd_buf + 8
    call    utils_strlen
    push    eax
    push    esi
    call    uart_puts
    pop     esi
    pop     ecx
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.wasmapp_usage:
    mov     esi, offset msg_wasmapp_usage
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret

.wasmapp_do_uptime:
    mov     esi, offset msg_wasmapp_uptime
    call    uart_puts
    mov     esi, offset wasm_app_uptime
    mov     ecx, offset wasm_app_uptime_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    xor     eax, eax
    call    wasm_exec_func
    # eax = tick count
    mov     esi, offset msg_uptime_result
    call    uart_puts
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    pop     eax
    mov     esi, offset msg_uptime_ticks
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret

.wasmapp_do_sum:
    mov     esi, offset msg_wasmapp_sum
    call    uart_puts
    mov     esi, offset wasm_app_sum
    mov     ecx, offset wasm_app_sum_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_sum_result
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

.wasmapp_do_hello:
    mov     esi, offset msg_wasmapp_hello
    call    uart_puts
    mov     esi, offset wasm_app_hello
    mov     ecx, offset wasm_app_hello_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    xor     eax, eax
    call    wasm_exec_func
    pop     ecx
    pop     edi
    pop     esi
    ret

.wasmapp_do_fib:
    mov     esi, offset msg_wasmapp_fib
    call    uart_puts
    mov     esi, offset wasm_app_fib
    mov     ecx, offset wasm_app_fib_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_fib_result
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

.wasmapp_do_fact:
    mov     esi, offset msg_wasmapp_fact
    call    uart_puts
    mov     esi, offset wasm_app_factorial
    mov     ecx, offset wasm_app_factorial_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_fact_result
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

.wasmapp_do_mul:
    mov     esi, offset msg_wasmapp_mul
    call    uart_puts
    mov     esi, offset wasm_app_multiply
    mov     ecx, offset wasm_app_multiply_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_mul_result
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

.wasmapp_do_count:
    mov     esi, offset msg_wasmapp_count
    call    uart_puts
    mov     esi, offset wasm_app_countdown
    mov     ecx, offset wasm_app_countdown_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_count_result
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

.do_ls:
    # 列出根目录内容
    mov     ebx, -1               # 根目录
    call    vfs_list_dir
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_cat:
    # 跳过 "cat " 前缀 (4 字符)
    lea     esi, [shell_cmd_buf + 4]
    call    utils_strlen
    test    eax, eax
    jz      .cat_not_found
    # 使用 vfs_find_by_path 支持绝对路径
    lea     esi, [shell_cmd_buf + 4]
    call    vfs_find_by_path
    cmp     eax, -1
    je      .cat_not_found
    call    vfs_read_file
    cmp     ecx, -1
    je      .cat_not_found
    jecxz   .cat_done             # 空文件
.print_content:
    movzx   eax, byte ptr [esi]
    push    ecx
    push    esi
    call    uart_putc
    pop     esi
    pop     ecx
    inc     esi
    dec     ecx
    jnz     .print_content
.cat_done:
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret
.cat_not_found:
    # Print the filename that wasn't found
    mov     esi, offset msg_cat_nf_prefix
    call    uart_puts
    lea     esi, [shell_cmd_buf + 4]
    call    uart_puts
    mov     esi, offset msg_cat_nf_suffix
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_touch:
    lea     esi, [shell_cmd_buf + 6]
    call    utils_strlen
    mov     ecx, eax
    cmp     ecx, 0
    je      .touch_usage
    mov     ebx, -1
    call    vfs_create_file_ext
    cmp     eax, -1
    je      .touch_fail
    mov     esi, offset msg_file_created
    call    uart_puts
    mov     esi, offset shell_cmd_buf + 6
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret
.touch_usage:
    mov     esi, offset msg_touch_usage
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret
.touch_fail:
    mov     esi, offset msg_touch_fail
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_kill:
    # 跳过 "kill " 前缀 (5 字符)
    lea     esi, [shell_cmd_buf + 5]
    call    utils_strlen
    mov     ecx, eax
    cmp     ecx, 0
    je      .kill_usage

    # 解析 PID
    call    utils_atoi
    cmp     eax, 0
    jl      .kill_usage
    cmp     eax, 16
    jge     .kill_usage

    # 通过系统调用终止进程 (SYS_EXIT = 1, ebx = exit_code)
    # 但 SYS_EXIT 只终止当前进程，我们需要通过 INT 0x80 传递 kill 请求
    # 直接使用内核内部接口：设置进程状态为 ZOMBIE
    push    eax                   # 保存请求的 PID
    mov     edi, eax              # pid
    imul    edi, 256
    add     edi, offset proc_table
    mov     eax, [edi]            # 读取 PCB 中的 PID
    cmp     eax, -1
    je      .kill_not_found
    cmp     eax, [esp]            # 与请求的 PID 比较
    jne     .kill_not_found       # PID 不匹配
    mov     dword ptr [edi + 4], 3  # state = PROC_ZOMBIE
    mov     dword ptr [edi + 80], 9  # exit_code = 9 (killed)
    mov     esi, offset msg_kill_ok
    call    uart_puts
    pop     eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    mov     esi, offset newline_str2
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret

.kill_usage:
    mov     esi, offset msg_kill_usage
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret

.kill_not_found:
    pop     eax
    mov     esi, offset msg_kill_notfound
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_date:
    push    ebx
    push    esi
    push    edi

    call    get_tick_count
    # eax = tick count
    push    eax

    mov     esi, offset msg_date_uptime
    call    uart_puts

    pop     eax
    # ticks to seconds (approximate: divide by 100)
    mov     ebx, 100
    xor     edx, edx
    div     ebx
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     esi, offset msg_date_sec_short
    call    uart_puts

    pop     edi
    pop     esi
    pop     ebx
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
cmd_kill:
    .asciz  "kill"
cmd_date:
    .asciz  "date"
cmd_ls:
    .asciz  "ls"
cmd_cat:
    .asciz  "cat "
cmd_touch:
    .asciz  "touch "
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
cmd_wasmtest5:
    .asciz  "wasmtest5"
cmd_wasmtest6:
    .asciz  "wasmtest6"
cmd_wasmapp:
    .asciz  "wasmapp"
cmd_wasmapp_uptime:
    .asciz  "uptime"
cmd_wasmapp_sum:
    .asciz  "sum"
cmd_wasmapp_hello:
    .asciz  "hello"
cmd_wasmapp_fib:
    .asciz  "fibonacci"
cmd_wasmapp_fact:
    .asciz  "factorial"
cmd_wasmapp_mul:
    .asciz  "multiply"
cmd_wasmapp_count:
    .asciz  "countdown"
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
    .ascii  "  kill <pid>    - Terminate process"
    .byte   13, 10
    .ascii  "  date          - Show system uptime"
    .byte   13, 10
    .ascii  "  ls            - List files"
    .byte   13, 10
    .ascii  "  cat <file>    - Print file content"
    .byte   13, 10
    .ascii  "  touch <file>  - Create empty file"
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
    .byte   13, 10
    .ascii  "  wasmapp <app> - Run WASM app (uptime, sum, hello, fibonacci, factorial, multiply, countdown)"
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
msg_wasm_test5:
    .asciz  "Running WASM test5 (br_table: switch-case)...\r\n"
msg_wasm_test6:
    .asciz  "Running WASM test6 (store8/load8: byte ops)...\r\n"
msg_wasm_result:
    .asciz  "Result: "
msg_wasm_parse_err:
    .asciz  "WASM parse error\r\n"
msg_wasmapp_usage:
    .asciz  "Usage: wasmapp <uptime|sum|hello|fibonacci|factorial|multiply|countdown>\r\n"
msg_wasmapp_unknown:
    .asciz  "Unknown WASM app: "
msg_wasmapp_uptime:
    .asciz  "Running WASM app: uptime\r\n"
msg_wasmapp_sum:
    .asciz  "Running WASM app: sum (1+2+...+10)\r\n"
msg_wasmapp_hello:
    .asciz  "Running WASM app: hello\r\n"
msg_wasmapp_fib:
    .asciz  "Running WASM app: fibonacci (fib(10))\r\n"
msg_wasmapp_fact:
    .asciz  "Running WASM app: factorial (5!)\r\n"
msg_wasmapp_mul:
    .asciz  "Running WASM app: multiply (7*8)\r\n"
msg_wasmapp_count:
    .asciz  "Running WASM app: countdown (from 10)\r\n"
msg_fib_result:
    .asciz  "fib(10) = "
msg_fact_result:
    .asciz  "5! = "
msg_mul_result:
    .asciz  "7*8 = "
msg_count_result:
    .asciz  "Countdown result = "
msg_uptime_result:
    .asciz  "Uptime: "
msg_uptime_ticks:
    .asciz  " ticks\r\n"
msg_sum_result:
    .asciz  "Sum(1..10) = "
msg_brtable_result:
    .asciz  "br_table result = "
msg_mem8_result:
    .asciz  "store8/load8 result = "
msg_kill_ok:
    .asciz  "Killed PID "
msg_kill_usage:
    .asciz  "Usage: kill <pid>\r\n"
msg_kill_notfound:
    .asciz  "Process not found\r\n"
newline_str2:
    .asciz  "\r\n"
msg_file_notfound:
    .asciz  "File not found\r\n"
msg_cat_nf_prefix:
    .asciz  "cat: "
msg_cat_nf_suffix:
    .asciz  ": No such file\r\n"
msg_file_created:
    .asciz  "Created: "
msg_touch_usage:
    .asciz  "Usage: touch <filename>\r\n"
msg_touch_fail:
    .asciz  "Failed to create file\r\n"
msg_date_uptime:
    .asciz  "Uptime: "
msg_date_days:
    .asciz  "d "
msg_date_hours:
    .asciz  "h "
msg_date_min:
    .asciz  "m "
msg_date_sec:
    .asciz  "s\r\n"
msg_date_sec_short:
    .asciz  " seconds\r\n"

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
# loop: counter--; br_if(counter) → continues while counter>0, exits when 0
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
    # code section (id=10, size=24)
    .byte   0x0A                   # section id
    .byte   0x17                   # section size = 23
    .byte   0x01                   # num codes
    .byte   0x16                   # code size = 22
    .byte   0x01                   # 1 local declaration
    .byte   0x01, 0x7F             # 1 local of type i32
    .byte   0x41, 0x05             # i32.const 5
    .byte   0x21, 0x00             # local.set 0
    .byte   0x03, 0x40             # loop (block type void)
    .byte   0x20, 0x00             # local.get 0
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x6B                   # i32.sub
    .byte   0x21, 0x00             # local.set 0
    .byte   0x20, 0x00             # local.get 0 (push counter, br_if loops while non-zero)
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

# ============================================================================
# WASM 应用程序
# ============================================================================

# WASM 应用 1：Uptime - 调用 host_time 获取系统滴答数
# host_time = slot 5, func_index = 1 + 5 = 6
wasm_app_uptime:
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
    # function section (id=3, size=2): 1 func, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section (id=10, size=6)
    .byte   0x0A                   # section id
    .byte   0x06                   # section size = 6
    .byte   0x01                   # num codes
    .byte   0x04                   # code size = 4
    .byte   0x00                   # num locals
    .byte   0x10, 0x06             # call 6 (host slot 5 = time)
    .byte   0x0B                   # end
wasm_app_uptime_size = . - wasm_app_uptime

# WASM 应用 2：Sum - 计算 1+2+...+10 = 55
# locals: $sum(i32), $i(i32)
wasm_app_sum:
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
    # function section (id=3, size=2): 1 func, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section (id=10, size=38)
    .byte   0x0A                   # section id
    .byte   0x26                   # section size = 38
    .byte   0x01                   # num codes
    .byte   0x25                   # code size = 37
    .byte   0x01                   # 1 local entry
    .byte   0x02, 0x7F             # 2 locals of type i32
    .byte   0x41, 0x00             # i32.const 0
    .byte   0x21, 0x00             # local.set 0 (sum=0)
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x21, 0x01             # local.set 1 (i=1)
    .byte   0x03, 0x40             # loop void
    .byte   0x20, 0x00             # local.get 0 (sum)
    .byte   0x20, 0x01             # local.get 1 (i)
    .byte   0x6A                   # i32.add
    .byte   0x21, 0x00             # local.set 0 (sum=sum+i)
    .byte   0x20, 0x01             # local.get 1 (i)
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x6A                   # i32.add
    .byte   0x21, 0x01             # local.set 1 (i=i+1)
    .byte   0x20, 0x01             # local.get 1 (i)
    .byte   0x41, 0x0B             # i32.const 11
    .byte   0x48                   # i32.lt_s
    .byte   0x0D, 0x00             # br_if 0
    .byte   0x20, 0x00             # local.get 0 (sum, result)
    .byte   0x0B                   # end
wasm_app_sum_size = . - wasm_app_sum

# WASM 应用 3：Hello - 打印 "Hi!\n" 使用 host_putchar
# host_putchar = slot 2, func_index = 1 + 2 = 3
wasm_app_hello:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section (id=1, size=3): () -> ()
    .byte   0x01                   # section id
    .byte   0x03                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x00                   # num results
    # function section (id=3, size=2): 1 func, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section (id=10, size=17)
    .byte   0x0A                   # section id
    .byte   0x11                   # section size = 17
    .byte   0x01                   # num codes
    .byte   0x0F                   # code size = 15
    .byte   0x00                   # num locals
    .byte   0x41, 0x48             # i32.const 72 ('H')
    .byte   0x10, 0x03             # call 3 (host_putchar)
    .byte   0x41, 0x69             # i32.const 105 ('i')
    .byte   0x10, 0x03             # call 3 (host_putchar)
    .byte   0x41, 0x21             # i32.const 33 ('!')
    .byte   0x10, 0x03             # call 3 (host_putchar)
    .byte   0x41, 0x0A             # i32.const 10 ('\n')
    .byte   0x10, 0x03             # call 3 (host_putchar)
    .byte   0x0B                   # end
wasm_app_hello_size = . - wasm_app_hello

# WASM 应用 4：Fibonacci - 计算 fib(10) = 55
# locals: $a(i32), $b(i32), $i(i32), $temp(i32)
# a=0, b=1, for i=0..9: (a,b) = (b, a+b)
wasm_app_fib:
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
    # function section (id=3, size=2): 1 func, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section (id=10, size=51)
    .byte   0x0A                   # section id
    .byte   0x33                   # section size = 51
    .byte   0x01                   # num codes
    .byte   0x31                   # code size = 49
    .byte   0x01                   # 1 local entry
    .byte   0x04, 0x7F             # 4 locals of type i32
    # 初始化: a=0, b=1, i=0
    .byte   0x41, 0x00             # i32.const 0
    .byte   0x21, 0x00             # local.set 0 (a=0)
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x21, 0x01             # local.set 1 (b=1)
    .byte   0x41, 0x00             # i32.const 0
    .byte   0x21, 0x02             # local.set 2 (i=0)
    # loop {
    .byte   0x03, 0x40             # loop void
    #   temp = a
    .byte   0x20, 0x00             # local.get 0
    .byte   0x21, 0x03             # local.set 3
    #   a = b
    .byte   0x20, 0x01             # local.get 1
    .byte   0x21, 0x00             # local.set 0
    #   b = temp + b
    .byte   0x20, 0x03             # local.get 3
    .byte   0x20, 0x01             # local.get 1
    .byte   0x6A                   # i32.add
    .byte   0x21, 0x01             # local.set 1
    #   i++
    .byte   0x20, 0x02             # local.get 2
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x6A                   # i32.add
    .byte   0x21, 0x02             # local.set 2
    #   if i < 10, continue
    .byte   0x20, 0x02             # local.get 2
    .byte   0x41, 0x0A             # i32.const 10
    .byte   0x48                   # i32.lt_s
    .byte   0x0D, 0x00             # br_if 0
    # }
    # return a
    .byte   0x20, 0x00             # local.get 0
    .byte   0x0B                   # end
wasm_app_fib_size = . - wasm_app_fib

# WASM 应用 5：Factorial - 计算 5! = 120
# locals: $result(i32), $i(i32)
# result = 1, i = 1, while i <= 5: result *= i, i++
# code body: 3(locals) + 8(init) + 2(loop) + 18(body) + 1(loop_end) + 3(return) = 35 bytes
wasm_app_factorial:
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
    # function section (id=3, size=2): 1 func, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section (id=10)
    .byte   0x0A                   # section id
    .byte   0x25                   # section size = 37 (1 + 1 + 35)
    .byte   0x01                   # num codes
    .byte   0x23                   # code size = 35
    .byte   0x01                   # 1 local entry
    .byte   0x02, 0x7F             # 2 locals of type i32
    # result = 1
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x21, 0x00             # local.set 0 (result=1)
    # i = 1
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x21, 0x01             # local.set 1 (i=1)
    # loop {
    .byte   0x03, 0x40             # loop void
    #   result = result * i
    .byte   0x20, 0x00             # local.get 0 (result)
    .byte   0x20, 0x01             # local.get 1 (i)
    .byte   0x6C                   # i32.mul
    .byte   0x21, 0x00             # local.set 0 (result=result*i)
    #   i = i + 1
    .byte   0x20, 0x01             # local.get 1 (i)
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x6A                   # i32.add
    .byte   0x21, 0x01             # local.set 1 (i=i+1)
    #   if i <= 5, continue loop
    .byte   0x20, 0x01             # local.get 1 (i)
    .byte   0x41, 0x05             # i32.const 5
    .byte   0x4D                   # i32.le_s
    .byte   0x0D, 0x00             # br_if 0 (jump to loop start)
    .byte   0x0B                   # end (loop) - ADDED
    # }
    # return result
    .byte   0x20, 0x00             # local.get 0
    .byte   0x0B                   # end (function)
wasm_app_factorial_size = . - wasm_app_factorial

# WASM 应用 6：Multiply - 计算 7 * 8 = 56
wasm_app_multiply:
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
    # function section (id=3, size=2): 1 func, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section (id=10, size=8)
    .byte   0x0A                   # section id
    .byte   0x08                   # section size = 8
    .byte   0x01                   # num codes
    .byte   0x06                   # code size = 6
    .byte   0x00                   # num locals
    .byte   0x41, 0x07             # i32.const 7
    .byte   0x41, 0x08             # i32.const 8
    .byte   0x6C                   # i32.mul
    .byte   0x0B                   # end
wasm_app_multiply_size = . - wasm_app_multiply

# WASM 应用 7：Countdown - 从 10 倒数到 0，返回 0
# locals: $counter(i32)
# code body: 2(locals) + 4(init) + 2(loop) + 10(body) + 1(loop_end) + 3(return) = 22 bytes
wasm_app_countdown:
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
    # function section (id=3, size=2): 1 func, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section (id=10)
    .byte   0x0A                   # section id
    .byte   0x18                   # section size = 24 (1 + 1 + 22)
    .byte   0x01                   # num codes
    .byte   0x16                   # code size = 22
    .byte   0x01                   # 1 local entry
    .byte   0x01, 0x7F             # 1 local of type i32
    # counter = 10
    .byte   0x41, 0x0A             # i32.const 10
    .byte   0x21, 0x00             # local.set 0 (counter=10)
    # loop {
    .byte   0x03, 0x40             # loop void
    #   counter = counter - 1
    .byte   0x20, 0x00             # local.get 0 (counter)
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x6B                   # i32.sub
    .byte   0x21, 0x00             # local.set 0 (counter=counter-1)
    #   if counter > 0, continue loop
    .byte   0x20, 0x00             # local.get 0 (counter)
    .byte   0x41, 0x00             # i32.const 0
    .byte   0x4A                   # i32.gt_s
    .byte   0x0D, 0x00             # br_if 0 (jump to loop start)
    .byte   0x0B                   # end (loop) - ADDED
    # }
    # return counter
    .byte   0x20, 0x00             # local.get 0
    .byte   0x0B                   # end (function)
wasm_app_countdown_size = . - wasm_app_countdown

# WASM 测试模块 5：br_table - switch-case 分支表
# 输入：索引值 (从栈弹出)
# 输出：根据索引返回不同值 (0->10, 1->20, 2->30, default->99)
wasm_test_brtable_module:
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
    # function section (id=3, size=2)
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: br_table with 3 targets
    .byte   0x0A                   # section id
    .byte   0x15                   # section size = 21
    .byte   0x01                   # num codes
    .byte   0x13                   # code size = 19
    .byte   0x00                   # num locals
    # push test index (1)
    .byte   0x41, 0x01             # i32.const 1 (test index)
    # br_table: 3 labels + default
    .byte   0x0E                   # br_table
    .byte   0x03                   # vec_len = 3
    .byte   0x00                   # label 0
    .byte   0x01                   # label 1
    .byte   0x02                   # label 2
    .byte   0x03                   # default label
    # blocks for each case
    .byte   0x41, 0x63             # i32.const 99 (default)
    .byte   0x0B                   # end block 3
    .byte   0x41, 0x1E             # i32.const 30 (case 2)
    .byte   0x0B                   # end block 2
    .byte   0x41, 0x14             # i32.const 20 (case 1)
    .byte   0x0B                   # end block 1
    .byte   0x41, 0x0A             # i32.const 10 (case 0)
    .byte   0x0B                   # end block 0
wasm_test_brtable_size = . - wasm_test_brtable_module

# WASM 测试模块 6：store8/load8 - 字节内存操作
wasm_test_mem8_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section
    .byte   0x01, 0x04, 0x01, 0x60, 0x00, 0x01, 0x7F
    # function section
    .byte   0x03, 0x02, 0x01, 0x00
    # code section
    .byte   0x0A                   # section id
    .byte   0x0D                   # section size = 13
    .byte   0x01                   # num codes
    .byte   0x0B                   # code size = 11
    .byte   0x00                   # num locals
    # store byte 42 at address 0
    .byte   0x41, 0x00             # i32.const 0 (addr)
    .byte   0x41, 0x2A             # i32.const 42 (value)
    .byte   0x3A, 0x00, 0x00       # i32.store8
    # load byte from address 0
    .byte   0x41, 0x00             # i32.const 0
    .byte   0x2D, 0x00, 0x00       # i32.load8_u
    .byte   0x0B                   # end
wasm_test_mem8_size = . - wasm_test_mem8_module
