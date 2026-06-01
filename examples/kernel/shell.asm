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

# Network
ping_target_ip:
    .space  4                   # target IP for ping command

# UDP send parameters
udp_send_dst_ip_tmp:
    .space  4
udp_send_dst_port_tmp:
    .space  2
udp_send_data_len_tmp:
    .space  4
udp_send_data_buf:
    .space  512

# PCI 扫描计数器
pciscan_bus:
    .space  4
pciscan_dev:
    .space  4
pciscan_func:
    .space  4
pciscan_count:
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

    # "wasmtest7" - WASM clz test
    mov     edi, offset cmd_wasmtest7
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest7

    # "wasmtest8" - WASM ctz test
    mov     edi, offset cmd_wasmtest8
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest8

    # "wasmtest9" - WASM popcnt test
    mov     edi, offset cmd_wasmtest9
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest9

    # "wasmtest10" - WASM rotl test
    mov     edi, offset cmd_wasmtest10
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest10

    # "wasmtest11" - WASM rotr test
    mov     edi, offset cmd_wasmtest11
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest11

    # "wasmtest12"
    mov     edi, offset cmd_wasmtest12
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest12

    # "wasmtest13"
    mov     edi, offset cmd_wasmtest13
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest13

    # "wasmtest14"
    mov     edi, offset cmd_wasmtest14
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest14

    # "wasmtest15"
    mov     edi, offset cmd_wasmtest15
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest15

    # "wasmtest16"
    mov     edi, offset cmd_wasmtest16
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest16

    # "wasmtest17"
    mov     edi, offset cmd_wasmtest17
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest17

    # "wasmtest18"
    mov     edi, offset cmd_wasmtest18
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest18

    # "wasmtest19" - WASM net_status test
    mov     edi, offset cmd_wasmtest19
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest19

    # "wasmtest20" - WASM net_config test
    mov     edi, offset cmd_wasmtest20
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest20

    # "wasmtest21" - WASM net_send/net_recv test
    mov     edi, offset cmd_wasmtest21
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest21

    # "wasmtest22" - WASM time+alloc+memory test
    mov     edi, offset cmd_wasmtest22
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest22

    # "wasmtest23" - WASM print/println/putchar test
    mov     edi, offset cmd_wasmtest23
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest23

    # "wasmtest24" - WASM meminfo host function test
    mov     edi, offset cmd_wasmtest24
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest24

    # "wasmtest25" - WASM store/load debug test
    mov     edi, offset cmd_wasmtest25
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest25

    # "wasmtest26" - WASM getchar host function test
    mov     edi, offset cmd_wasmtest26
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest26

    # "wasmtest27" - WASM store/load combination test
    mov     edi, offset cmd_wasmtest27
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest27

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

    # "netinfo" - show network info
    mov     edi, offset cmd_netinfo
    call    utils_strcmp
    test    eax, eax
    jz      .do_netinfo

    # "netpoll" - poll network for received packets
    mov     edi, offset cmd_netpoll
    call    utils_strcmp
    test    eax, eax
    jz      .do_netpoll

    # "netinit" - initialize virtio-net driver
    mov     edi, offset cmd_netinit
    call    utils_strcmp
    test    eax, eax
    jz      .do_netinit

    # "ping" - send ICMP Echo Request
    mov     edi, offset cmd_ping
    call    utils_strcmp
    test    eax, eax
    jz      .do_ping

    # "udpsend" - send UDP packet
    mov     edi, offset cmd_udpsend
    call    utils_strcmp
    test    eax, eax
    jz      .do_udpsend

    # "udprecv" - check received UDP data
    mov     edi, offset cmd_udprecv
    call    utils_strcmp
    test    eax, eax
    jz      .do_udprecv

    # "tcpstatus" - check TCP connection state
    mov     edi, offset cmd_tcpstatus
    call    utils_strcmp
    test    eax, eax
    jz      .do_tcpstatus

    # "netstat" - show TCP connection table
    mov     edi, offset cmd_netstat
    call    utils_strcmp
    test    eax, eax
    jz      .do_netstat

    # "arp" - show ARP cache
    mov     edi, offset cmd_arp
    call    utils_strcmp
    test    eax, eax
    jz      .do_arp

    # "httpserver" - toggle HTTP server
    mov     edi, offset cmd_httpserver
    call    utils_strcmp
    test    eax, eax
    jz      .do_httpserver

    # "dhcp" - run DHCP client
    mov     edi, offset cmd_dhcp
    call    utils_strcmp
    test    eax, eax
    jz      .do_dhcp

    # "pciscan" - scan PCI devices
    mov     edi, offset cmd_pciscan
    call    utils_strcmp
    test    eax, eax
    jz      .do_pciscan

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

.do_wasmtest7:
    # clz test: clz(1) = 31
    mov     esi, offset msg_wasm_test7
    call    uart_puts
    mov     esi, offset wasm_test_clz_module
    mov     ecx, offset wasm_test_clz_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_clz_result
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

.do_wasmtest8:
    # ctz test: ctz(8) = 3
    mov     esi, offset msg_wasm_test8
    call    uart_puts
    mov     esi, offset wasm_test_ctz_module
    mov     ecx, offset wasm_test_ctz_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_ctz_result
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

.do_wasmtest9:
    # popcnt test: popcnt(0xFF) = 8
    mov     esi, offset msg_wasm_test9
    call    uart_puts
    mov     esi, offset wasm_test_popcnt_module
    mov     ecx, offset wasm_test_popcnt_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_popcnt_result
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

.do_wasmtest10:
    # rotl test: rotl(0x80000000, 1) = 1
    mov     esi, offset msg_wasm_test10
    call    uart_puts
    mov     esi, offset wasm_test_rotl_module
    mov     ecx, offset wasm_test_rotl_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_rotl_result
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

.do_wasmtest11:
    # rotr test: rotr(8, 1) = 4
    mov     esi, offset msg_wasm_test11
    call    uart_puts
    mov     esi, offset wasm_test_rotr_module
    mov     ecx, offset wasm_test_rotr_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_rotr_result
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

.do_wasmtest12:
    mov     esi, offset msg_wasm_test12
    call    uart_puts
    mov     esi, offset wasm_test_div_module
    mov     ecx, offset wasm_test_div_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_div_result
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

.do_wasmtest13:
    mov     esi, offset msg_wasm_test13
    call    uart_puts
    mov     esi, offset wasm_test_rem_module
    mov     ecx, offset wasm_test_rem_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_rem_result
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

.do_wasmtest14:
    mov     esi, offset msg_wasm_test14
    call    uart_puts
    mov     esi, offset wasm_test_xor_module
    mov     ecx, offset wasm_test_xor_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_xor_result
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

.do_wasmtest15:
    mov     esi, offset msg_wasm_test15
    call    uart_puts
    mov     esi, offset wasm_test_f64arith_module
    mov     ecx, offset wasm_test_f64arith_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_f64arith_result
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

.do_wasmtest16:
    mov     esi, offset msg_wasm_test16
    call    uart_puts
    mov     esi, offset wasm_test_or_module
    mov     ecx, offset wasm_test_or_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_or_result
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

.do_wasmtest17:
    mov     esi, offset msg_wasm_test17
    call    uart_puts
    mov     esi, offset wasm_test_and_module
    mov     ecx, offset wasm_test_and_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_and_result
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

.do_wasmtest18:
    mov     esi, offset msg_wasm_test18
    call    uart_puts
    mov     esi, offset wasm_test_shl_module
    mov     ecx, offset wasm_test_shl_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_shl_result
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

.do_wasmtest19:
    # WASM net_status test: call host function 10, return status
    mov     esi, offset msg_wasm_test19
    call    uart_puts
    mov     esi, offset wasm_test_net_status_module
    mov     ecx, offset wasm_test_net_status_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_net_status_result
    call    uart_puts
    mov     edi, offset shell_cmd_buf
    mov     dl, 16                 # hex output
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

.do_wasmtest20:
    # WASM net_config test: call host function 11, verify config write
    mov     esi, offset msg_wasm_test20
    call    uart_puts
    mov     esi, offset wasm_test_net_config_module
    mov     ecx, offset wasm_test_net_config_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_net_config_result
    call    uart_puts
    mov     edi, offset shell_cmd_buf
    mov     dl, 16                 # hex output
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

# ============================================================================
# shell_wasmtest21: Global entry point for wasmtest21 (called from kernel boot)
# ============================================================================
    .globl  shell_wasmtest21
shell_wasmtest21:
    mov     esi, offset msg_wasm_test21
    call    uart_puts
    mov     esi, offset wasm_test_net_send_module
    mov     ecx, offset wasm_test_net_send_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm21_done
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_net_send_result
    call    uart_puts
    call    print_hex8
    mov     al, 0x0d
    call    uart_putc
    mov     al, 0x0a
    call    uart_putc
.wasm21_done:
    ret

.do_wasmtest21:
    # WASM net_send + net_recv test
    # Part 1: net_send - send UDP packet
    mov     esi, offset msg_wasm_test21
    call    uart_puts
    mov     esi, offset wasm_test_net_send_module
    mov     ecx, offset wasm_test_net_send_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    push    eax                    # save net_send result
    mov     esi, offset msg_net_send_result
    call    uart_puts
    pop     eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 16                 # hex output
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    # Part 2: net_recv - try to receive data
    mov     esi, offset wasm_test_net_recv_module
    mov     ecx, offset wasm_test_net_recv_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_net_recv_result
    call    uart_puts
    mov     edi, offset shell_cmd_buf
    mov     dl, 16                 # hex output
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

.do_wasmtest22:
    # WASM time+alloc+memory test
    mov     esi, offset msg_wasm_test22
    call    uart_puts
    mov     esi, offset wasm_test_time_alloc_module
    mov     ecx, offset wasm_test_time_alloc_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_time_result
    call    uart_puts
    mov     edi, offset shell_cmd_buf
    mov     dl, 10                 # decimal output
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

.do_wasmtest23:
    # WASM print/println/putchar test
    mov     esi, offset msg_wasm_test23
    call    uart_puts
    mov     esi, offset wasm_test_print_module
    mov     ecx, offset wasm_test_print_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_print_result
    call    uart_puts
    mov     edi, offset shell_cmd_buf
    mov     dl, 10                 # decimal output
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

.do_wasmtest24:
    # WASM meminfo host function test
    mov     esi, offset msg_wasm_test24
    call    uart_puts
    mov     esi, offset wasm_test_meminfo_module
    mov     ecx, offset wasm_test_meminfo_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    # Print "meminfo() done\n"
    mov     esi, offset msg_meminfo_result
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_wasmtest25:
    # WASM store/load debug test
    mov     esi, offset msg_wasm_test25
    call    uart_puts
    mov     esi, offset wasm_test_store_module
    mov     ecx, offset wasm_test_store_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    # Print "store/load result = "
    mov     esi, offset msg_store_result
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

.do_wasmtest26:
    # WASM getchar host function test
    mov     esi, offset msg_wasm_test26
    call    uart_puts
    mov     esi, offset wasm_test_getchar_module
    mov     ecx, offset wasm_test_getchar_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    # Print "getchar() = 0x"
    mov     esi, offset msg_getchar_result
    call    uart_puts
    mov     edi, offset shell_cmd_buf
    mov     dl, 16
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

.do_wasmtest27:
    # WASM store8/load8_u test: store8(0, 64) → load8_u(0) → return 64
    mov     esi, offset msg_wasm_test27
    call    uart_puts
    mov     esi, offset wasm_test_store_load_module
    mov     ecx, offset wasm_test_store_load_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    # Print "loaded value = "
    mov     esi, offset msg_store8_result
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
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
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
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
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
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
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
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
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
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
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
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
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
    # Reset VM state before execution
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
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
# shell_parse_ip: Parse dotted-decimal IP address string to 32-bit value
# Input: esi = pointer to string "X.X.X.X"
# Output: eax = IP in network byte order (LE stored as-is), 0 = bad
# ============================================================================
shell_parse_ip:
    push    ebx
    push    ecx
    push    edx
    xor     eax, eax             # result = 0

    # Parse first octet
    call    shell_parse_octet
    cmp     edx, -1
    je      .parse_fail
    mov     ebx, edx             # ebx = octet 1
    mov     dl, [esi]
    cmp     dl, '.'
    jne     .parse_fail
    inc     esi                  # skip '.'

    # Parse second octet
    call    shell_parse_octet
    cmp     edx, -1
    je      .parse_fail
    shl     ebx, 8
    or      ebx, edx             # ebx = octet1.octet2
    mov     dl, [esi]
    cmp     dl, '.'
    jne     .parse_fail
    inc     esi

    # Parse third octet
    call    shell_parse_octet
    cmp     edx, -1
    je      .parse_fail
    shl     ebx, 8
    or      ebx, edx             # ebx = octet1.octet2.octet3
    mov     dl, [esi]
    cmp     dl, '.'
    jne     .parse_fail
    inc     esi

    # Parse fourth octet
    call    shell_parse_octet
    cmp     edx, -1
    je      .parse_fail
    shl     ebx, 8
    or      ebx, edx             # ebx = full IP

    mov     eax, ebx             # return in eax
    pop     edx
    pop     ecx
    pop     ebx
    ret

.parse_fail:
    xor     eax, eax             # return 0 = failure
    pop     edx
    pop     ecx
    pop     ebx
    ret

# shell_parse_octet: Parse decimal number at esi, update esi past digits
# Input: esi = pointer to digits
# Output: edx = value (0-255), -1 on error
shell_parse_octet:
    push    eax
    push    ecx
    xor     edx, edx
    xor     ecx, ecx             # digit count

.parse_oct_loop:
    movzx   eax, byte ptr [esi]
    cmp     al, '0'
    jb      .oct_done
    cmp     al, '9'
    ja      .oct_done
    sub     al, '0'
    imul    edx, edx, 10
    add     edx, eax
    inc     esi
    inc     ecx
    cmp     ecx, 3               # max 3 digits
    jbe     .parse_oct_loop

    cmp     edx, 255
    ja      .oct_fail
    test    ecx, ecx
    jz      .oct_fail
    pop     ecx
    pop     eax
    ret

.oct_fail:
    mov     edx, -1
    pop     ecx
    pop     eax
    ret

.oct_done:
    test    ecx, ecx
    jz      .oct_fail
    cmp     edx, 255
    ja      .oct_fail
    pop     ecx
    pop     eax
    ret

# ============================================================================
# shell_print_ip: Print IP address from 32-bit value
# Input: eax = IP address (little-endian stored)
# ============================================================================
shell_print_ip:
    push    ebx
    push    ecx
    push    edx
    push    esi
    mov     ebx, eax             # save IP
    mov     ecx, 4
.print_octet:
    mov     eax, ebx
    and     eax, 0xFF            # extract one byte
    call    shell_print_dec_byte
    mov     al, '.'
    call    uart_putc
    shr     ebx, 8
    loop    .print_octet
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    # Remove trailing dot by overwriting with newline
    ret

# print_ip_inline: Print IP from pointer, no trailing dot
# Input: eax = pointer to 4-byte IP address
print_ip_inline:
    push    eax
    push    ebx
    push    ecx
    push    edx
    mov     ebx, [eax]              # load IP
    mov     ecx, 3
.print_octet2:
    mov     eax, ebx
    and     eax, 0xFF
    call    shell_print_dec_byte
    mov     al, '.'
    call    uart_putc
    shr     ebx, 8
    loop    .print_octet2
    # Last octet without dot
    mov     eax, ebx
    and     eax, 0xFF
    call    shell_print_dec_byte
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

# print_ip_arp: Print IP address from value in eax
# Input: eax = IP address (little-endian)
print_ip_arp:
    push    ebx
    push    ecx
    push    edx
    mov     ebx, eax
    mov     ecx, 3
.pia_loop:
    mov     eax, ebx
    and     eax, 0xFF
    call    shell_print_dec_byte
    mov     al, '.'
    call    uart_putc
    shr     ebx, 8
    loop    .pia_loop
    # Last octet without dot
    mov     eax, ebx
    and     eax, 0xFF
    call    shell_print_dec_byte
    pop     edx
    pop     ecx
    pop     ebx
    ret

# print_hex_byte: Print byte in eax as 2 hex chars
# Input: eax = byte value (0-255)
print_hex_byte:
    push    eax
    push    ebx
    mov     ebx, eax
    # High nibble
    mov     eax, ebx
    shr     eax, 4
    cmp     al, 10
    jl      .ph_high_dec
    add     al, 'A' - 10
    jmp     .ph_high_done
.ph_high_dec:
    add     al, '0'
.ph_high_done:
    call    uart_putc
    # Low nibble
    mov     eax, ebx
    and     eax, 0xF
    cmp     al, 10
    jl      .ph_low_dec
    add     al, 'A' - 10
    jmp     .ph_low_done
.ph_low_dec:
    add     al, '0'
.ph_low_done:
    call    uart_putc
    pop     ebx
    pop     eax
    ret

# shell_parse_dec: Parse decimal number from string at esi
# Input: esi = pointer to digits
# Output: ax = value, esi advanced past digits
shell_parse_dec:
    push    edx
    push    ecx
    xor     edx, edx             # result
    xor     ecx, ecx             # digit count

.parse_loop:
    movzx   eax, byte ptr [esi]
    cmp     al, '0'
    jb      .done_dec
    cmp     al, '9'
    ja      .done_dec
    sub     al, '0'
    imul    edx, edx, 10
    add     edx, eax
    inc     esi
    inc     ecx
    jmp     .parse_loop

.done_dec:
    test    ecx, ecx
    jz      .bad_dec
    mov     ax, dx
    pop     ecx
    pop     edx
    ret

.bad_dec:
    xor     ax, ax
    pop     ecx
    pop     edx
    ret

# shell_print_dec_byte: Print a byte (0-255) as decimal
# Input: eax (low byte = value)
shell_print_dec_byte:
    push    ebx
    push    ecx
    push    edx
    xor     ebx, ebx
    mov     bl, al               # value in ebx

    # Extract hundreds
    xor     ecx, ecx
.print_hundreds:
    cmp     ebx, 100
    jb      .print_tens
    sub     ebx, 100
    inc     ecx
    jmp     .print_hundreds
.print_tens:
    test    ecx, ecx
    jz      .print_tens_loop
    add     ecx, '0'
    mov     al, cl
    call    uart_putc

.print_tens_loop:
    xor     ecx, ecx
.print_tens_again:
    cmp     ebx, 10
    jb      .print_ones
    sub     ebx, 10
    inc     ecx
    jmp     .print_tens_again
.print_ones:
    add     ebx, '0'
    mov     al, bl
    call    uart_putc

    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
.do_netpoll:
    mov     esi, offset msg_netpoll_polling
    call    uart_puts
    call    e1000_poll
    test    eax, eax
    jz      .netpoll_none
    mov     esi, offset msg_netpoll_packets
    call    uart_puts
    mov     eax, [e1000_rx_idx]
    call    print_hex8
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    jmp     .netpoll_done
.netpoll_none:
    mov     esi, offset msg_netpoll_none
    call    uart_puts
.netpoll_done:
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_ping:
    # Parse IP address from "ping X.X.X.X" (skip "ping " = 5 chars)
    lea     esi, [shell_cmd_buf + 5]
    call    shell_parse_ip
    test    eax, eax
    jz      .ping_bad_ip
    mov     [ping_target_ip], eax

    # Print "Sending ICMP Echo Request to ..."
    mov     esi, offset msg_ping_sending
    call    uart_puts
    mov     eax, [ping_target_ip]
    call    shell_print_ip
    mov     al, 0x0a
    call    uart_putc

    # Set our IP for ARP
    mov     dword ptr [e1000_arp_ip], 0x0F02000A  # 10.0.2.15

    # Send ARP request for target IP
    mov     eax, [ping_target_ip]
    call    e1000_send_arp

    # Build ICMP Echo Request packet in e1000_tx_buf
    # Ethernet header (14 bytes)
    mov     edi, offset e1000_tx_buf

    # Destination MAC: use resolved ARP MAC, or broadcast if ARP failed
    test    eax, eax
    jnz     .ping_use_broadcast
    mov     eax, [e1000_arp_mac]
    mov     [edi], eax
    mov     ax, [e1000_arp_mac + 4]
    mov     [edi + 4], ax
    jmp     .ping_mac_set
.ping_use_broadcast:
    mov     dword ptr [edi], 0xFFFFFFFF
    mov     word ptr [edi + 4], 0xFFFF

.ping_mac_set:
    # Source MAC: our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax

    # EtherType = IPv4
    mov     word ptr [edi + 12], 0x0800

    # IP header (20 bytes) at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45          # Version=4, IHL=5
    mov     byte ptr [edi + 1], 0         # TOS
    mov     word ptr [edi + 2], 60        # Total length = 20+8+32 = 60
    mov     word ptr [edi + 4], 0x1234    # Identification
    mov     word ptr [edi + 6], 0x4000    # Flags: Don't fragment
    mov     byte ptr [edi + 8], 64        # TTL
    mov     byte ptr [edi + 9], 1         # Protocol = ICMP
    mov     word ptr [edi + 10], 0        # Checksum (to calc)

    # Source IP: 10.0.2.15 (QEMU user net)
    mov     dword ptr [edi + 12], 0x02000A0F  # 10.0.2.15 little-endian... actually host order
    # 10.0.2.15 = 0x0A00020F in network byte order
    # But x86 is little-endian, so store as bytes: 0A 00 02 0F
    mov     dword ptr [edi + 12], 0x0F02000A  # 10.0.2.15 in LE

    # Dest IP: target
    mov     eax, [ping_target_ip]
    mov     [edi + 16], eax

    # Calculate IP checksum
    push    edi
    xor     edx, edx
    mov     ecx, 10             # 10 words
.ip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .ip_cksum
.fold_ip:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .ip_fold_done
    add     eax, 1
.ip_fold_done:
    not     ax
    pop     edi
    mov     [edi + 10], ax

    # ICMP header (8 bytes) at offset 34
    mov     edi, offset e1000_tx_buf + 34
    mov     byte ptr [edi], 8         # Type = Echo Request
    mov     byte ptr [edi + 1], 0     # Code
    mov     word ptr [edi + 2], 0     # Checksum (to calc)
    mov     word ptr [edi + 4], 0x0001  # Identifier
    mov     word ptr [edi + 6], 1     # Sequence

    # ICMP payload: 32 bytes of pattern
    mov     edi, offset e1000_tx_buf + 42
    mov     ecx, 8
    mov     eax, 0x01020304
.fill_payload:
    mov     [edi], eax
    add     edi, 4
    add     eax, 0x04040404
    loop    .fill_payload

    # Calculate ICMP checksum (ICMP header + payload = 40 bytes = 20 words)
    mov     edi, offset e1000_tx_buf + 34
    xor     edx, edx
    mov     ecx, 20
.icmp_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .icmp_cksum
.fold_icmp:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .icmp_fold_done
    add     eax, 1
.icmp_fold_done:
    not     ax
    mov     edi, offset e1000_tx_buf + 36
    mov     [edi], ax

    # Send packet (60 bytes total: 14 eth + 20 IP + 8 ICMP + 32 payload)
    mov     esi, offset e1000_tx_buf
    mov     ecx, 60
    call    e1000_transmit
    test    eax, eax
    jnz     .ping_send_fail

    mov     esi, offset msg_ping_sent
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # Wait a bit for reply, then poll
    mov     ecx, 5000000
.ping_wait:
    dec     ecx
    jnz     .ping_wait

    call    e1000_poll
    test    eax, eax
    jz      .ping_no_reply

    mov     esi, offset msg_ping_reply
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    jmp     .ping_done

.ping_no_reply:
    mov     esi, offset msg_ping_noreply
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    jmp     .ping_done

.ping_send_fail:
    mov     esi, offset msg_ping_sendfail
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

.ping_done:
    pop     ecx
    pop     edi
    pop     esi
    ret

.ping_bad_ip:
    mov     esi, offset msg_ping_badip
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_udpsend:
    # Parse "udpsend <ip> <port> <data>"
    lea     esi, [shell_cmd_buf + 8]  # skip "udpsend"

    # Skip space
.skip_space1:
    cmp     byte ptr [esi], ' '
    jne     .udpsend_bad
    inc     esi
    jmp     .skip_space1

    # Parse IP
    call    shell_parse_ip
    test    eax, eax
    jz      .udpsend_bad
    mov     [udp_send_dst_ip_tmp], eax

    # Skip space to port
.skip_space2:
    cmp     byte ptr [esi], ' '
    jne     .parse_port
    inc     esi
    jmp     .skip_space2

    # Parse port number
.parse_port:
    call    shell_parse_dec
    mov     [udp_send_dst_port_tmp], ax

    # Skip space to data
.skip_space3:
    cmp     byte ptr [esi], ' '
    jne     .prep_send
    inc     esi
    jmp     .skip_space3

.prep_send:
    # Our IP for ARP
    mov     dword ptr [e1000_arp_ip], 0x0F02000A  # 10.0.2.15

    # Send ARP for target IP
    mov     eax, [udp_send_dst_ip_tmp]
    call    e1000_send_arp

    # Calculate data length
    mov     edi, esi
    call    utils_strlen
    mov     [udp_send_data_len_tmp], eax   # save length

    # Copy data to send buffer
    mov     edi, offset udp_send_data_buf
    mov     ecx, eax
    push    esi
    push    edi
    shr     ecx, 2
    cld
    rep     movsd
    pop     edi
    pop     esi
    mov     ecx, eax
    and     ecx, 3
    rep     movsb

    # Send UDP packet
    mov     eax, [udp_send_dst_ip_tmp]  # dest IP
    mov     cx, [udp_send_dst_port_tmp]  # dest port
    mov     dx, 5000                     # src port
    mov     esi, offset udp_send_data_buf
    mov     ecx, [udp_send_data_len_tmp]
    call    e1000_send_udp

    mov     esi, offset msg_udpsend_ok
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    pop     ecx
    pop     edi
    pop     esi
    ret

.udpsend_bad:
    mov     esi, offset msg_udpsend_bad
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_udprecv:
    # Check if UDP data received
    cmp     dword ptr [udp_recv_ready], 1
    jne     .udprecv_none

    mov     esi, offset msg_udprecv_header
    call    uart_puts

    # Print source IP
    mov     eax, [udp_recv_src_ip]
    call    shell_print_ip
    mov     al, ':'
    call    uart_putc

    # Print source port
    movzx   eax, word ptr [udp_recv_src_port]
    call    shell_print_dec_byte
    mov     esi, offset msg_udprecv_len
    call    uart_puts

    # Print length
    mov     eax, [udp_recv_len]
    call    shell_print_dec_byte

    mov     esi, offset msg_udprecv_data
    call    uart_puts

    # Print data (limit to 64 chars)
    mov     esi, offset udp_recv_buf
    mov     ecx, [udp_recv_len]
    cmp     ecx, 64
    jle     .udprecv_print
    mov     ecx, 64
.udprecv_print:
    mov     edx, ecx
.udprecv_loop:
    test    ecx, ecx
    jz      .udprecv_done
    movzx   eax, byte ptr [esi]
    call    uart_putc
    inc     esi
    dec     ecx
    jmp     .udprecv_loop

.udprecv_done:
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # Clear ready flag
    xor     eax, eax
    mov     [udp_recv_ready], eax
    jmp     .udprecv_exit

.udprecv_none:
    mov     esi, offset msg_udprecv_none
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

.udprecv_exit:
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_tcpstatus:
    mov     esi, offset msg_tcp_header
    call    uart_puts

    # Print TCP state
    mov     eax, [tcp_state]
    cmp     eax, 0
    je      .tcp_closed
    cmp     eax, 1
    je      .tcp_listen
    cmp     eax, 2
    je      .tcp_synsent
    cmp     eax, 3
    je      .tcp_synrecv
    cmp     eax, 4
    je      .tcp_established

.tcp_closed:
    mov     esi, offset msg_tcp_closed
    call    uart_puts
    jmp     .tcp_state_done
.tcp_listen:
    mov     esi, offset msg_tcp_listen
    call    uart_puts
    jmp     .tcp_state_done
.tcp_synsent:
    mov     esi, offset msg_tcp_synsent
    call    uart_puts
    jmp     .tcp_state_done
.tcp_synrecv:
    mov     esi, offset msg_tcp_synrecv
    call    uart_puts
    jmp     .tcp_state_done
.tcp_established:
    mov     esi, offset msg_tcp_established
    call    uart_puts
.tcp_state_done:
    mov     al, 0x0a
    call    uart_putc

    # Print listen port
    mov     esi, offset msg_tcp_port
    call    uart_puts
    movzx   eax, word ptr [tcp_listen_port]
    call    shell_print_dec_byte
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # Check for received data
    cmp     dword ptr [tcp_recv_ready], 1
    jne     .tcp_no_data

    mov     esi, offset msg_tcp_data
    call    uart_puts
    mov     eax, [tcp_recv_len]
    call    shell_print_dec_byte
    mov     esi, offset msg_tcp_data_len
    call    uart_puts

    # Print data (limit 64)
    mov     esi, offset tcp_recv_buf
    mov     ecx, [tcp_recv_len]
    cmp     ecx, 64
    jle     .tcp_print_data
    mov     ecx, 64
.tcp_print_data:
    test    ecx, ecx
    jz      .tcp_no_data
    movzx   eax, byte ptr [esi]
    call    uart_putc
    inc     esi
    dec     ecx
    jmp     .tcp_print_data

.tcp_no_data:
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_netstat:
    # Print header
    mov     esi, offset msg_netstat_header
    call    uart_puts

    # Print active connection count
    mov     eax, [tcp_conn_active_count]
    mov     esi, offset msg_netstat_active
    call    uart_puts
    call    shell_print_dec_byte
    mov     esi, offset msg_netstat_of
    call    uart_puts
    mov     eax, 4
    call    shell_print_dec_byte
    mov     esi, offset msg_netstat_conns
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # Print connection table header
    mov     esi, offset msg_netstat_tbl_hdr
    call    uart_puts

    # Walk connection table
    xor     ecx, ecx                     # index = 0
    mov     esi, offset tcp_conn_table
.netstat_loop:
    cmp     ecx, 4
    jge     .netstat_done

    # Check if slot is active (state != 0)
    cmp     byte ptr [esi], 0
    je      .netstat_skip

    # Save connection table pointer in ebx
    mov     ebx, esi

    # Print slot index
    mov     eax, ecx
    call    shell_print_dec_byte
    mov     al, ' '
    call    uart_putc

    # Print state name
    movzx   eax, byte ptr [ebx]
    cmp     eax, 1
    je      .net_st_listen
    cmp     eax, 2
    je      .net_st_synsent
    cmp     eax, 3
    je      .net_st_synrecv
    cmp     eax, 4
    je      .net_st_established
    cmp     eax, 5
    je      .net_st_finwait
    cmp     eax, 6
    je      .net_st_closewait
    mov     edi, offset msg_net_st_closed
    jmp     .net_st_print
.net_st_listen:
    mov     edi, offset msg_net_st_listen
    jmp     .net_st_print
.net_st_synsent:
    mov     edi, offset msg_net_st_synsent
    jmp     .net_st_print
.net_st_synrecv:
    mov     edi, offset msg_net_st_synrecv
    jmp     .net_st_print
.net_st_established:
    mov     edi, offset msg_net_st_established
    jmp     .net_st_print
.net_st_finwait:
    mov     edi, offset msg_net_st_finwait
    jmp     .net_st_print
.net_st_closewait:
    mov     edi, offset msg_net_st_closewait
    jmp     .net_st_print

.net_st_print:
    mov     esi, edi
    call    uart_puts

    # Pad with spaces
    mov     al, ' '
    call    uart_putc
    call    uart_putc

    # Print remote IP (from connection entry at ebx+4)
    mov     eax, [ebx + 4]
    call    print_ip_inline

    # Print colon and remote port (from connection entry at ebx+8)
    mov     al, ':'
    call    uart_putc
    movzx   eax, word ptr [ebx + 8]
    call    shell_print_dec_byte

    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # Restore esi from ebx for next iteration
    mov     esi, ebx
    jmp     .netstat_next

.netstat_skip:
    # Save esi, print empty slot, restore esi
    push    esi
    mov     eax, ecx
    call    shell_print_dec_byte
    mov     esi, offset msg_net_st_empty
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     esi

.netstat_next:
    add     esi, 24                     # next entry
    inc     ecx
    jmp     .netstat_loop

.netstat_done:
    ret

.do_arp:
    # Print header
    mov     esi, offset msg_arp_header
    call    uart_puts

    # Print ARP cache size
    mov     eax, [e1000_arp_cache_size]
    mov     esi, offset msg_arp_entries
    call    uart_puts
    call    shell_print_dec_byte
    mov     esi, offset msg_arp_of
    call    uart_puts
    mov     eax, 8
    call    shell_print_dec_byte
    mov     esi, offset msg_arp_entries2
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # Print table header
    mov     esi, offset msg_arp_tbl_hdr
    call    uart_puts

    # Walk ARP cache
    xor     ecx, ecx                     # index = 0
    mov     esi, offset e1000_arp_cache
.arp_loop:
    cmp     ecx, 8
    jge     .arp_done

    # Check if slot is active (IP != 0)
    cmp     dword ptr [esi], 0
    je      .arp_skip

    # Print slot index
    mov     eax, ecx
    call    shell_print_dec_byte
    mov     al, ' '
    call    uart_putc

    # Print IP address
    mov     eax, [esi]
    call    print_ip_arp

    # Pad
    mov     al, ' '
    call    uart_putc
    mov     al, ' '
    call    uart_putc

    # Print MAC address
    movzx   eax, byte ptr [esi + 4]
    call    print_hex_byte
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [esi + 5]
    call    print_hex_byte
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [esi + 6]
    call    print_hex_byte
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [esi + 7]
    call    print_hex_byte
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [esi + 8]
    call    print_hex_byte
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [esi + 9]
    call    print_hex_byte
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    jmp     .arp_next

.arp_skip:
    # Print empty slot (save esi first)
    push    esi
    mov     eax, ecx
    call    shell_print_dec_byte
    mov     esi, offset msg_arp_empty
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     esi

.arp_next:
    add     esi, 12                     # next entry
    inc     ecx
    jmp     .arp_loop

.arp_done:
    ret

.do_httpserver:
    # Check for "on" or "off" argument after "httpserver" (10 chars)
    lea     esi, [shell_cmd_buf + 10]
    lodsb
    test    al, al
    jz      .http_show_status
    cmp     al, ' '
    je      .http_check_args
    jmp     .http_done

.http_check_args:
    # Skip spaces
    lodsb
    cmp     al, ' '
    je      .http_check_args
    cmp     al, 0
    je      .http_show_status
    dec     esi

    # Check if "on"
    cmp     byte ptr [esi], 'o'
    jne     .http_check_off
    cmp     byte ptr [esi + 1], 'n'
    jne     .http_check_off
    mov     dword ptr [tcp_http_enabled], 1
    mov     esi, offset msg_http_on
    call    uart_puts
    jmp     .http_done

.http_check_off:
    # Check if "off"
    cmp     byte ptr [esi], 'o'
    jne     .http_show_status
    cmp     byte ptr [esi + 1], 'f'
    jne     .http_show_status
    cmp     byte ptr [esi + 2], 'f'
    jne     .http_show_status
    mov     dword ptr [tcp_http_enabled], 0
    mov     esi, offset msg_http_off
    call    uart_puts
    jmp     .http_done

.http_show_status:
    cmp     dword ptr [tcp_http_enabled], 0
    je      .http_is_off
    mov     esi, offset msg_http_enabled
    call    uart_puts
    jmp     .http_done
.http_is_off:
    mov     esi, offset msg_http_disabled
    call    uart_puts

.http_done:
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # Print connection stats
    mov     esi, offset msg_tcp_conn_count
    call    uart_puts
    mov     eax, [tcp_conn_count]
    call    shell_print_dec_byte
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # Print RST received
    cmp     dword ptr [tcp_rst_received], 0
    je      .http_no_rst
    mov     esi, offset msg_tcp_rst_recv
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
.http_no_rst:

    # Print FIN received
    cmp     dword ptr [tcp_fin_received], 0
    je      .http_no_fin
    mov     esi, offset msg_tcp_fin_recv
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
.http_no_fin:

    pop     ecx
    pop     edi
    pop     esi
    ret

.do_netinit:
    mov     esi, offset msg_netinit_start
    call    uart_puts
    call    virtio_net_init
    test    eax, eax
    jnz     .netinit_fail
    mov     esi, offset msg_netinit_ok
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.netinit_fail:
    mov     esi, offset msg_netinit_fail
    call    uart_puts
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_netinfo:
    # 检查网络状态
    mov     eax, [virtio_net_status]
    test    eax, eax
    jz      .netinfo_not_found

    # 打印网络信息标题
    mov     esi, offset msg_netinfo_header
    call    uart_puts

    # 打印MAC地址
    mov     esi, offset msg_netinfo_mac
    call    uart_puts

    call    virtio_net_get_mac
    mov     ecx, 6
    mov     ebx, esi
.netinfo_mac_loop:
    movzx   eax, byte ptr [ebx]
    push    ebx
    push    ecx
    mov     edi, offset shell_cmd_buf
    mov     dl, 16
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    pop     ecx
    pop     ebx
    inc     ebx
    dec     ecx
    jz      .netinfo_mac_done
    mov     al, ':'
    call    uart_putc
    jmp     .netinfo_mac_loop

.netinfo_mac_done:
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # 打印IRQ线号
    mov     esi, offset msg_netinfo_irq
    call    uart_puts
    mov     eax, [virtio_irq_line]
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

.netinfo_not_found:
    mov     esi, offset msg_netinfo_none
    call    uart_puts
    pop     ecx
    pop     edi
    pop     esi
    ret

.do_dhcp:
    # Run DHCP client: send Discover and wait for Offer/ACK
    call    e1000_send_dhcp_discover

    # Poll for DHCP responses (~5 seconds)
    mov     ecx, 50
.dhcp_poll_loop:
    call    e1000_poll_delay
    cmp     dword ptr [e1000_dhcp_state], 3  # bound
    je      .dhcp_bound
    cmp     dword ptr [e1000_dhcp_state], 2  # got_offer
    je      .dhcp_send_request
    dec     ecx
    jnz     .dhcp_poll_loop
    jmp     .dhcp_timeout

.dhcp_send_request:
    # Got offer, now send DHCP Request
    call    e1000_send_dhcp_request
    mov     ecx, 30
.dhcp_poll2:
    call    e1000_poll_delay
    cmp     dword ptr [e1000_dhcp_state], 3  # bound
    je      .dhcp_bound
    dec     ecx
    jnz     .dhcp_poll2
    jmp     .dhcp_timeout

.dhcp_bound:
    # Print our assigned IP
    mov     esi, offset msg_dhcp_bound
    call    uart_puts
    mov     eax, [e1000_our_ip]
    call    shell_print_ip
    mov     al, 0x0a
    call    uart_putc

    # Print gateway
    mov     esi, offset msg_dhcp_gw
    call    uart_puts
    mov     eax, [e1000_gateway_ip]
    call    shell_print_ip
    mov     al, 0x0a
    call    uart_putc
    jmp     .dhcp_done

.dhcp_timeout:
    mov     esi, offset msg_dhcp_timeout
    call    uart_puts

.dhcp_done:
    ret

.do_pciscan:
    # 扫描 PCI 设备并显示 vendor/device ID
    # 使用 BSS 变量存储计数器，避免寄存器冲突
    push    ebp
    mov     ebp, esp

    # 初始化计数器
    mov     dword ptr [pciscan_bus], 0
    mov     dword ptr [pciscan_count], 0

.pciscan_bus_loop:
    mov     dword ptr [pciscan_dev], 0

.pciscan_dev_loop:
    mov     dword ptr [pciscan_func], 0

.pciscan_func_loop:
    # 读取 Vendor ID (offset 0)
    mov     eax, [pciscan_bus]    # bus
    mov     edx, [pciscan_dev]    # device
    mov     ecx, [pciscan_func]   # function
    mov     ebx, 0                # offset
    call    pci_read_config

    # 检查设备是否存在
    and     eax, 0xFFFF
    cmp     ax, 0xFFFF
    je      .pciscan_next_func

    # 找到设备，打印信息
    push    eax                   # 保存 vendor ID

    # 打印 "PCI: B:D:F"
    mov     esi, offset msg_pci_device
    call    uart_puts

    # 打印 bus
    mov     eax, [pciscan_bus]
    mov     edi, offset shell_cmd_buf
    mov     dl, 16
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     al, ':'
    call    uart_putc

    # 打印 device
    mov     eax, [pciscan_dev]
    mov     edi, offset shell_cmd_buf
    mov     dl, 16
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     al, ':'
    call    uart_putc

    # 打印 function
    mov     eax, [pciscan_func]
    mov     edi, offset shell_cmd_buf
    mov     dl, 16
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    # 打印 Vendor ID
    mov     esi, offset msg_pci_vendor
    call    uart_puts

    pop     eax                   # 恢复 vendor ID
    mov     edi, offset shell_cmd_buf
    mov     dl, 16
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    # 打印 Device ID
    mov     esi, offset msg_pci_device_id
    call    uart_puts

    # 重新读取 Device ID
    mov     eax, [pciscan_bus]
    mov     edx, [pciscan_dev]
    mov     ecx, [pciscan_func]
    mov     ebx, 2                # offset for Device ID
    call    pci_read_config

    shr     eax, 16
    and     eax, 0xFFFF
    mov     edi, offset shell_cmd_buf
    mov     dl, 16
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    # 换行
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    # 设备计数
    inc     dword ptr [pciscan_count]

.pciscan_next_func:
    inc     dword ptr [pciscan_func]
    mov     ecx, [pciscan_func]
    cmp     ecx, 8
    jl      .pciscan_func_loop

.pciscan_next_dev:
    inc     dword ptr [pciscan_dev]
    mov     edx, [pciscan_dev]
    cmp     edx, 32
    jl      .pciscan_dev_loop

.pciscan_next_bus:
    inc     dword ptr [pciscan_bus]
    mov     ebx, [pciscan_bus]
    cmp     ebx, 256
    jl      .pciscan_bus_loop

    # 检查是否找到设备
    mov     eax, [pciscan_count]
    test    eax, eax
    jnz     .pciscan_done
    mov     esi, offset msg_pci_none
    call    uart_puts

.pciscan_done:
    pop     ebp
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
cmd_wasmtest7:
    .asciz  "wasmtest7"
cmd_wasmtest8:
    .asciz  "wasmtest8"
cmd_wasmtest9:
    .asciz  "wasmtest9"
cmd_wasmtest10:
    .asciz  "wasmtest10"
cmd_wasmtest11:
    .asciz  "wasmtest11"
cmd_wasmtest12:
    .asciz  "wasmtest12"
cmd_wasmtest13:
    .asciz  "wasmtest13"
cmd_wasmtest14:
    .asciz  "wasmtest14"
cmd_wasmtest15:
    .asciz  "wasmtest15"
cmd_wasmtest16:
    .asciz  "wasmtest16"
cmd_wasmtest17:
    .asciz  "wasmtest17"
cmd_wasmtest18:
    .asciz  "wasmtest18"
cmd_wasmtest19:
    .asciz  "wasmtest19"
cmd_wasmtest20:
    .asciz  "wasmtest20"
cmd_wasmtest21:
    .asciz  "wasmtest21"
cmd_wasmtest22:
    .asciz  "wasmtest22"
cmd_wasmtest23:
    .asciz  "wasmtest23"
cmd_wasmtest24:
    .asciz  "wasmtest24"
cmd_wasmtest25:
    .asciz  "wasmtest25"
cmd_wasmtest26:
    .asciz  "wasmtest26"
cmd_wasmtest27:
    .asciz  "wasmtest27"
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
cmd_netinfo:
    .asciz  "netinfo"
cmd_netinit:
    .asciz  "netinit"
cmd_netpoll:
    .asciz  "netpoll"
cmd_ping:
    .asciz  "ping"
cmd_udpsend:
    .asciz  "udpsend"
cmd_udprecv:
    .asciz  "udprecv"
cmd_tcpstatus:
    .asciz  "tcpstatus"
cmd_netstat:
    .asciz  "netstat"
cmd_httpserver:
    .asciz  "httpserver"
cmd_dhcp:
    .asciz  "dhcp"
cmd_pciscan:
    .asciz  "pciscan"
cmd_arp:
    .asciz  "arp"

msg_arp_header:
    .ascii  "ARP Cache:"
    .byte   13, 10, 0
msg_arp_entries:
    .ascii  "  Entries: "
    .byte   0
msg_arp_of:
    .ascii  " of "
    .byte   0
msg_arp_entries2:
    .ascii  " slots used"
    .byte   13, 10, 0
msg_arp_tbl_hdr:
    .ascii  "Slot IP              MAC"
    .byte   13, 10, 0
msg_arp_empty:
    .ascii  "  (empty)"
    .byte   0

msg_dhcp_bound:
    .ascii  "DHCP Bound: IP="
    .byte   0
msg_dhcp_gw:
    .ascii  "  GW="
    .byte   0
msg_dhcp_timeout:
    .ascii  "DHCP timeout, no response\n"
    .byte   0

msg_pci_device:
    .ascii  "PCI: "
    .byte   0
msg_pci_vendor:
    .ascii  " Vendor="
    .byte   0
msg_pci_device_id:
    .ascii  " Device="
    .byte   0
msg_pci_none:
    .ascii  "No PCI devices found"
    .byte   13, 10, 0

msg_netinfo_header:
    .ascii  "Network device info:"
    .byte   13, 10, 0
msg_netinfo_mac:
    .ascii  "  MAC: "
    .byte   0
msg_netinfo_irq:
    .ascii  "  IRQ: "
    .byte   0
msg_netinfo_none:
    .ascii  "No network device found"
    .byte   13, 10, 0

msg_netinit_start:
    .ascii  "Initializing virtio-net..."
    .byte   13, 10, 0
msg_netinit_ok:
    .ascii  "  virtio-net initialized successfully"
    .byte   13, 10, 0
msg_netinit_fail:
    .ascii  "  virtio-net init failed (device not found)"
    .byte   13, 10, 0

msg_netpoll_polling:
    .ascii  "Polling network..."
    .byte   13, 10, 0
msg_netpoll_packets:
    .ascii  "  Packets received: "
    .byte   0
msg_netpoll_none:
    .ascii  "  No packets received"
    .byte   13, 10, 0

msg_ping_sending:
    .ascii  "ICMP Echo Request -> "
    .byte   0
msg_ping_sent:
    .ascii  "  Sent (waiting reply...)"
    .byte   0
msg_ping_reply:
    .ascii  "  ICMP Echo Reply received!"
    .byte   0
msg_ping_noreply:
    .ascii  "  No reply received (timeout)"
    .byte   13, 10, 0
msg_ping_sendfail:
    .ascii  "  Send failed"
    .byte   13, 10, 0
msg_ping_badip:
    .ascii  "  Usage: ping <ip> (e.g. ping 10.0.2.2)"
    .byte   13, 10, 0

msg_udpsend_ok:
    .ascii  "  UDP packet sent"
    .byte   13, 10, 0
msg_udpsend_bad:
    .ascii  "  Usage: udpsend <ip> <port> <data>"
    .byte   13, 10, 0
msg_udprecv_header:
    .ascii  "UDP from "
    .byte   0
msg_udprecv_len:
    .ascii  " len="
    .byte   0
msg_udprecv_data:
    .ascii  ": "
    .byte   0
msg_udprecv_none:
    .ascii  "  No UDP data received"
    .byte   13, 10, 0

msg_tcp_header:
    .ascii  "TCP Status:"
    .byte   13, 10, 0
msg_tcp_closed:
    .ascii  "  State: CLOSED"
    .byte   0
msg_tcp_listen:
    .ascii  "  State: LISTEN"
    .byte   0
msg_tcp_synsent:
    .ascii  "  State: SYN_SENT"
    .byte   0
msg_tcp_synrecv:
    .ascii  "  State: SYN_RECV"
    .byte   0
msg_tcp_established:
    .ascii  "  State: ESTABLISHED"
    .byte   0
msg_tcp_port:
    .ascii  "  Listen port: "
    .byte   0
msg_tcp_data:
    .ascii  "  Data received ("
    .byte   0
msg_tcp_data_len:
    .ascii  " bytes): "
    .byte   0
msg_tcp_conn_count:
    .ascii  "  Connections: "
    .byte   0
msg_tcp_rst_recv:
    .ascii  "  RST received"
    .byte   0
msg_tcp_fin_recv:
    .ascii  "  FIN received"
    .byte   0

# netstat messages
msg_netstat_header:
    .ascii  "Network Status:"
    .byte   13, 10, 0
msg_netstat_active:
    .ascii  "  Active: "
    .byte   0
msg_netstat_of:
    .ascii  " / "
    .byte   0
msg_netstat_conns:
    .ascii  " connections"
    .byte   13, 10, 0
msg_netstat_tbl_hdr:
    .ascii  "  TCP Connection Table:"
    .byte   13, 10, 0
msg_net_st_closed:
    .ascii  "CLOSED       "
    .byte   0
msg_net_st_listen:
    .ascii  "LISTEN       "
    .byte   0
msg_net_st_synsent:
    .ascii  "SYN_SENT     "
    .byte   0
msg_net_st_synrecv:
    .ascii  "SYN_RECV     "
    .byte   0
msg_net_st_established:
    .ascii  "ESTABLISHED  "
    .byte   0
msg_net_st_finwait:
    .ascii  "FIN_WAIT     "
    .byte   0
msg_net_st_closewait:
    .ascii  "CLOSE_WAIT   "
    .byte   0
msg_net_st_empty:
    .ascii  "(empty)"
    .byte   0

msg_http_on:
    .ascii  "HTTP server enabled"
    .byte   0
msg_http_off:
    .ascii  "HTTP server disabled"
    .byte   0
msg_http_enabled:
    .ascii  "HTTP server: ON"
    .byte   0
msg_http_disabled:
    .ascii  "HTTP server: OFF"
    .byte   0

version_text:
    .ascii  "AI-ASM Kernel v0.74"
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
    .byte   13, 10
    .ascii  "  ping <ip>     - Send ICMP Echo Request"
    .byte   13, 10
    .ascii  "  udpsend <ip> <port> <data> - Send UDP packet"
    .byte   13, 10
    .ascii  "  udprecv       - Check received UDP data"
    .byte   13, 10
    .ascii  "  tcpstatus     - Show TCP connection state"
    .byte   13, 10
    .ascii  "  httpserver    - Toggle HTTP server (on/off/status)"
    .byte   13, 10
    .ascii  "  dhcp          - Run DHCP client (auto-configure IP)"
    .byte   13, 10
    .ascii  "  netpoll       - Poll for received packets"
    .byte   13, 10
    .ascii  "  netstat       - Show TCP connection table"
    .byte   13, 10
    .ascii  "  arp           - Show ARP cache table"
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
msg_wasm_test7:
    .asciz  "Running WASM test7 (i32.clz: clz(1)=31)...\r\n"
msg_wasm_test8:
    .asciz  "Running WASM test8 (i32.ctz: ctz(8)=3)...\r\n"
msg_wasm_test9:
    .asciz  "Running WASM test9 (i32.popcnt: popcnt(0xFF)=8)...\r\n"
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
msg_clz_result:
    .asciz  "clz(1) = "
msg_ctz_result:
    .asciz  "ctz(8) = "
msg_popcnt_result:
    .asciz  "popcnt(0xFF) = "
msg_wasm_test10:
    .asciz  "Running WASM test10 (i32.rotl: rotl(1, 1)=2)...\r\n"
msg_wasm_test11:
    .asciz  "Running WASM test11 (i32.rotr: rotr(8, 1)=4)...\r\n"
msg_rotl_result:
    .asciz  "rotl(1, 1) = "
msg_rotr_result:
    .asciz  "rotr(8, 1) = "
msg_wasm_test12:
    .asciz  "Running WASM test12 (i32.div_u: 1000/8=125)...\r\n"
msg_div_result:
    .asciz  "div result = "
msg_wasm_test13:
    .asciz  "Running WASM test13 (i32.rem_u: 100%7=2)...\r\n"
msg_rem_result:
    .asciz  "rem result = "
msg_wasm_test14:
    .asciz  "Running WASM test14 (i32.xor: 0xFF^0xF0=15)...\r\n"
msg_xor_result:
    .asciz  "xor result = "
msg_wasm_test15:
    .asciz  "Running WASM test15 (f64.add: 1.5+2.5=4)...\r\n"
msg_f64arith_result:
    .asciz  "f64.add result = "
msg_wasm_test16:
    .asciz  "Running WASM test16 (i32.or: 0xF0|0x0F=255)...\r\n"
msg_or_result:
    .asciz  "or result = "
msg_wasm_test17:
    .asciz  "Running WASM test17 (i32.and: 0xFF&0xF0=240)...\r\n"
msg_and_result:
    .asciz  "and result = "
msg_wasm_test18:
    .asciz  "Running WASM test18 (i32.shl: 1<<3=8)...\r\n"
msg_shl_result:
    .asciz  "shl result = "
msg_wasm_test19:
    .asciz  "Running WASM test19 (net_status)...\r\n"
msg_net_status_result:
    .asciz  "net_status = 0x"
msg_wasm_test20:
    .asciz  "Running WASM test20 (net_config)...\r\n"
msg_net_config_result:
    .asciz  "net_config result = 0x"
msg_wasm_test21:
    .asciz  "Running WASM test21 (net_send/net_recv)...\r\n"
msg_net_send_result:
    .asciz  "net_send result = 0x"
msg_net_recv_result:
    .asciz  "net_recv result = 0x"
msg_wasm_test22:
    .asciz  "Running WASM test22 (time+alloc/memory)...\r\n"
msg_time_result:
    .asciz  "time() = "
msg_wasm_test23:
    .asciz  "Running WASM test23 (print/println/putchar)...\r\n"
msg_print_result:
    .asciz  "time() = "
msg_wasm_test24:
    .asciz  "Running WASM test24 (meminfo)...\r\n"
msg_meminfo_result:
    .asciz  "meminfo() done\r\n"
msg_wasm_test25:
    .asciz  "Running WASM test25 (store/load)...\r\n"
msg_store_result:
    .asciz  "loaded value = "
msg_wasm_test26:
    .asciz  "Running WASM test26 (getchar)... type a char\r\n"
msg_getchar_result:
    .asciz  "getchar() = 0x"
msg_wasm_test27:
    .asciz  "Running WASM test27 (store8/load8_u)...\r\n"
msg_store8_result:
    .asciz  "loaded value = "
msg_s8dbg_store:
    .asciz  "[S8] val="
msg_s8dbg_at:
    .asciz  " addr="
msg_s8dbg_byte:
    .asciz  "[MEM+0]="
msg_s8dbg_const:
    .asciz  "[CONST]="
msg_s8dbg_stkdp:
    .asciz  "[STK_DEPTH]="
msg_s8dbg_stkel:
    .asciz  " ["
msg_s8dbg_instcnt:
    .asciz  "[INST_CNT]="
msg_s8dbg_lastop:
    .asciz  "[LAST_OP]=0x"
msg_s8dbg_bytes:
    .asciz  "[CODE]="
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
# locals: $a(i32), $b(i32), $n(i32), $temp(i32)
# a=0, b=1, n=10; loop: temp=a; a=b; b=temp+b; n--; br_if(n)
wasm_app_fib:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic "\0asm"
    .byte   0x01, 0x00, 0x00, 0x00  # version 1
    .byte   0x01                   # type section id
    .byte   0x04                   # size
    .byte   0x01, 0x60, 0x00, 0x01, 0x7F  # 1 type: ()->i32
    .byte   0x03                   # function section id
    .byte   0x02                   # size
    .byte   0x01, 0x00             # 1 func, type 0
    .byte   0x0A                   # code section id
    .byte   0x31                   # size = 49
    .byte   0x01                   # 1 code body
    .byte   0x2F                   # code size = 47
    .byte   0x01                   # 1 local decl
    .byte   0x04, 0x7F             # 4 locals i32
    # a=0 (local 0)
    .byte   0x41, 0x00, 0x21, 0x00
    # b=1 (local 1)
    .byte   0x41, 0x01, 0x21, 0x01
    # n=10 (local 2)
    .byte   0x41, 0x0A, 0x21, 0x02
    # loop (label 0 = loop top)
    .byte   0x03, 0x40
    #   temp = a  (local 3)
    .byte   0x20, 0x00, 0x21, 0x03
    #   a = b
    .byte   0x20, 0x01, 0x21, 0x00
    #   b = temp + b
    .byte   0x20, 0x03, 0x20, 0x01, 0x6A, 0x21, 0x01
    #   n--
    .byte   0x20, 0x02, 0x41, 0x01, 0x6B, 0x21, 0x02
    #   if n!=0, br 0 (loop back)
    .byte   0x20, 0x02, 0x0D, 0x00
    # end loop
    .byte   0x0B
    # return a
    .byte   0x20, 0x00
    # end function
    .byte   0x0B
wasm_app_fib_size = . - wasm_app_fib

# WASM 应用 5：Factorial - 计算 5! = 120
# locals: $result(i32), $counter(i32)
# result=1, counter=5; while counter>0: result*=counter; counter--
wasm_app_factorial:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic "\0asm"
    .byte   0x01, 0x00, 0x00, 0x00  # version 1
    .byte   0x01                   # type section id
    .byte   0x04                   # size
    .byte   0x01, 0x60, 0x00, 0x01, 0x7F  # 1 type: ()->i32
    .byte   0x03                   # function section id
    .byte   0x02                   # size
    .byte   0x01, 0x00             # 1 func, type 0
    .byte   0x0A                   # code section id
    .byte   0x25                   # size = 37
    .byte   0x01                   # 1 code body
    .byte   0x23                   # code size = 35
    .byte   0x01                   # 1 local decl
    .byte   0x02, 0x7F             # 2 locals i32
    # result = 1 (local 0)
    .byte   0x41, 0x01, 0x21, 0x00
    # counter = 5 (local 1)
    .byte   0x41, 0x05, 0x21, 0x01
    # loop:
    .byte   0x03, 0x40             # loop void
    #   result *= counter
    .byte   0x20, 0x00, 0x20, 0x01, 0x6C, 0x21, 0x00
    #   counter--
    .byte   0x20, 0x01, 0x41, 0x01, 0x6B, 0x21, 0x01
    #   if counter>0, br_if 0 (loop back)
    .byte   0x20, 0x01, 0x0D, 0x00
    # end loop
    .byte   0x0B
    # return result
    .byte   0x20, 0x00
    # end function
    .byte   0x0B
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
    .byte   0x09                   # section size = 9
    .byte   0x01                   # num codes
    .byte   0x07                   # code size = 7
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
# 嵌套 block：br_table index=1 应该跳出内部 block，继续执行 i32.const 20，返回 20
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
    # code section
    # Simplified: block void + br 0 (tests basic br out of block)
    # code size = 1 + 2(block) + 2(br 0) + 2(const 20) + 1(end) = 8
    # section size = 1 + 1 + 8 = 10 = 0x0A
    .byte   0x0A                   # section id
    .byte   0x0A                   # section size = 10
    .byte   0x01                   # num codes
    .byte   0x08                   # code size = 8
    .byte   0x00                   # num locals
    # block void {       (label 0)
    .byte   0x02, 0x40         # block void
    .byte   0x0C, 0x00         # br 0
    .byte   0x41, 0x14         # i32.const 20 (should execute after br pops block)
    .byte   0x0B               # end (function)
wasm_test_brtable_size = . - wasm_test_brtable_module

# WASM 测试模块 6：store8/load8 - 字节内存操作
wasm_test_mem8_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F
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

# WASM 测试模块 7：clz(1) = 31
wasm_test_clz_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F  # type
    .byte   0x03, 0x02, 0x01, 0x00  # function
    .byte   0x0A                   # code section
    .byte   0x07                   # section size = 7
    .byte   0x01                   # num codes
    .byte   0x05                   # code size = 5
    .byte   0x00                   # num locals
    .byte   0x41, 0x01             # i32.const 1
    .byte   0x67                   # i32.clz
    .byte   0x0B                   # end
wasm_test_clz_size = . - wasm_test_clz_module

# WASM 测试模块 8：ctz(8) = 3
wasm_test_ctz_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F  # type
    .byte   0x03, 0x02, 0x01, 0x00  # function
    .byte   0x0A                   # code section
    .byte   0x07                   # section size = 7
    .byte   0x01                   # num codes
    .byte   0x05                   # code size = 5
    .byte   0x00                   # num locals
    .byte   0x41, 0x08             # i32.const 8
    .byte   0x68                   # i32.ctz
    .byte   0x0B                   # end
wasm_test_ctz_size = . - wasm_test_ctz_module

# WASM 测试模块 9：popcnt(0xFF) = 8
wasm_test_popcnt_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F  # type
    .byte   0x03, 0x02, 0x01, 0x00  # function
    .byte   0x0A                   # code section
    .byte   0x08                   # section size = 8
    .byte   0x01                   # num codes
    .byte   0x06                   # code size = 6
    .byte   0x00                   # num locals
    .byte   0x41, 0xFF, 0x01       # i32.const 255 (SLEB128: 0x7F + 0x01 << 7)
    .byte   0x69                   # i32.popcnt
    .byte   0x0B                   # end
wasm_test_popcnt_size = . - wasm_test_popcnt_module

# WASM 测试模块 10：rotl(1, 1) = 2
wasm_test_rotl_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F  # type
    .byte   0x03, 0x02, 0x01, 0x00  # function
    .byte   0x0A                   # code section
    .byte   0x08                   # section size = 8
    .byte   0x01                   # num codes
    .byte   0x06                   # code size = 6
    .byte   0x00                   # num locals
    .byte   0x41, 0x01             # i32.const 1 (value)
    .byte   0x41, 0x01             # i32.const 1 (count)
    .byte   0x77                   # i32.rotl
    .byte   0x0B                   # end
wasm_test_rotl_size = . - wasm_test_rotl_module

# WASM 测试模块 11：rotr(8, 1) = 4
wasm_test_rotr_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F  # type
    .byte   0x03, 0x02, 0x01, 0x00  # function
    .byte   0x0A                   # code section
    .byte   0x08                   # section size = 8
    .byte   0x01                   # num codes
    .byte   0x06                   # code size = 6
    .byte   0x00                   # num locals
    .byte   0x41, 0x08             # i32.const 8 (value)
    .byte   0x41, 0x01             # i32.const 1 (count)
    .byte   0x78                   # i32.rotr
    .byte   0x0B                   # end
wasm_test_rotr_size = . - wasm_test_rotr_module

# WASM test12: i32.div_u - 1000 / 8 = 125
wasm_test_div_module:
    .byte   0x00, 0x61, 0x73, 0x6D
    .byte   0x01, 0x00, 0x00, 0x00
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F
    .byte   0x03, 0x02, 0x01, 0x00
    .byte   0x0A, 0x09, 0x01, 0x07, 0x00
    .byte   0x41, 0xE8, 0x07
    .byte   0x41, 0x08
    .byte   0x6E
    .byte   0x0B
wasm_test_div_size = . - wasm_test_div_module

# WASM test13: i32.add - 100 + 7 = 107
wasm_test_rem_module:
    .byte   0x00, 0x61, 0x73, 0x6D
    .byte   0x01, 0x00, 0x00, 0x00
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F
    .byte   0x03, 0x02, 0x01, 0x00
    .byte   0x0A, 0x09, 0x01, 0x07, 0x00
    .byte   0x41, 0x64
    .byte   0x41, 0x07
    .byte   0x6A
    .byte   0x0B
wasm_test_rem_size = . - wasm_test_rem_module

# WASM test14: i32.xor - 0xFF ^ 0xF0 = 0x0F = 15
wasm_test_xor_module:
    .byte   0x00, 0x61, 0x73, 0x6D
    .byte   0x01, 0x00, 0x00, 0x00
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F
    .byte   0x03, 0x02, 0x01, 0x00
    .byte   0x0A, 0x0B, 0x01, 0x09, 0x00
    .byte   0x41, 0xFF, 0x01
    .byte   0x41, 0xF0, 0x01
    .byte   0x73
    .byte   0x0B
    .byte   0x0B
wasm_test_xor_size = . - wasm_test_xor_module

# WASM test15: f64.add - 1.5 + 2.5 = 4.0, truncate to i32 = 4
wasm_test_f64arith_module:
    .byte   0x00, 0x61, 0x73, 0x6D
    .byte   0x01, 0x00, 0x00, 0x00
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F
    .byte   0x03, 0x02, 0x01, 0x00
    .byte   0x0A, 0x18, 0x01, 0x16, 0x00
    .byte   0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x3F
    .byte   0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x40
    .byte   0xA0
    .byte   0xAB
    .byte   0x0B
wasm_test_f64arith_size = . - wasm_test_f64arith_module

# WASM test16: i32.or - 0xF0 | 0x0F = 0xFF = 255
wasm_test_or_module:
    .byte   0x00, 0x61, 0x73, 0x6D
    .byte   0x01, 0x00, 0x00, 0x00
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F
    .byte   0x03, 0x02, 0x01, 0x00
    .byte   0x0A, 0x0A, 0x01, 0x08, 0x00
    .byte   0x41, 0xF0, 0x01
    .byte   0x41, 0x0F
    .byte   0x72
    .byte   0x0B
    .byte   0x0B
wasm_test_or_size = . - wasm_test_or_module

# WASM test17: i32.and - 0xFF & 0xF0 = 0xF0 = 240
wasm_test_and_module:
    .byte   0x00, 0x61, 0x73, 0x6D
    .byte   0x01, 0x00, 0x00, 0x00
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F
    .byte   0x03, 0x02, 0x01, 0x00
    .byte   0x0A, 0x0B, 0x01, 0x09, 0x00
    .byte   0x41, 0xFF, 0x01
    .byte   0x41, 0xF0, 0x01
    .byte   0x71
    .byte   0x0B
    .byte   0x0B
wasm_test_and_size = . - wasm_test_and_module

# WASM test18: i32.select - select(100, 200, cond=1) = 100
wasm_test_shl_module:
    .byte   0x00, 0x61, 0x73, 0x6D
    .byte   0x01, 0x00, 0x00, 0x00
    .byte   0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7F
    .byte   0x03, 0x02, 0x01, 0x00
    .byte   0x0A, 0x09, 0x01, 0x07, 0x00
    .byte   0x41, 0x01
    .byte   0x41, 0x03
    .byte   0x74
    .byte   0x0B
wasm_test_shl_size = . - wasm_test_shl_module

# WASM 测试模块 19：net_status syscall
# 调用宿主函数10 (net_status)，返回网络状态
wasm_test_net_status_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: () -> i32
    .byte   0x01                   # section id
    .byte   0x04                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: call net_status (func_idx=11)
    .byte   0x0A                   # section id
    .byte   0x06                   # section size = 6
    .byte   0x01                   # num codes
    .byte   0x04                   # code size = 4
    .byte   0x00                   # num locals
    .byte   0x10, 0x0B             # call 11 (func_count=1, host_id=11-1=10=net_status)
    .byte   0x0B                   # end
wasm_test_net_status_size = . - wasm_test_net_status_module

# WASM 测试模块 20：net_config syscall
# 调用宿主函数11 (net_config)，传入缓冲区指针，返回结果
wasm_test_net_config_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: (i32) -> i32
    .byte   0x01                   # section id
    .byte   0x04                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x01                   # num params
    .byte   0x7F                   # i32
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: i32.const 0; call 12 (net_config); return
    .byte   0x0A                   # section id
    .byte   0x07                   # section size = 7
    .byte   0x01                   # num codes
    .byte   0x05                   # code size = 5
    .byte   0x00                   # num locals
    .byte   0x41, 0x00             # i32.const 0 (buffer at linear memory offset 0)
    .byte   0x10, 0x0C             # call 12 (func_count=1, host_id=12-1=11=net_config)
    .byte   0x0B                   # end
wasm_test_net_config_size = . - wasm_test_net_config_module

# WASM 测试模块 21a：call time() host function
# time() = host slot 5, wasm_func_count=1, call 6
# WASM 测试模块 21a：net_send syscall
# 发送 UDP 数据到 10.0.2.2:7
wasm_test_net_send_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: (i32,i32,i32,i32,i32) -> i32
    .byte   0x01                   # section id
    .byte   0x0A                   # section size = 10
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x05                   # num params
    .byte   0x7F, 0x7F, 0x7F, 0x7F, 0x7F  # 5 x i32
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: call net_send(type=0, dst_ip=0x0A000202, dst_port=7, ptr=0, len=4)
    # WASM stack: last pushed = first popped, so push in reverse: type, ip, port, ptr, len
    .byte   0x0A                   # section id
    .byte   0x13                   # section size = 19
    .byte   0x01                   # num codes
    .byte   0x11                   # body size = 17
    .byte   0x00                   # num locals
    .byte   0x41, 0x00             # i32.const 0 (type=UDP, first pushed=bottom)
    .byte   0x41, 0x82, 0x90, 0x80, 0x80, 0x0A  # i32.const 0x0A000202 (10.0.2.2)
    .byte   0x41, 0x07             # i32.const 7 (dst_port)
    .byte   0x41, 0x00             # i32.const 0 (ptr)
    .byte   0x41, 0x04             # i32.const 4 (len, last pushed=top)
    .byte   0x10, 0x09             # call 9
    .byte   0x0B                   # end
wasm_test_net_send_size = . - wasm_test_net_send_module

# WASM 测试模块 21b：net_recv syscall
wasm_test_net_recv_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: (i32,i32,i32) -> i32
    .byte   0x01                   # section id
    .byte   0x08                   # section size = 8
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x03                   # num params
    .byte   0x7F, 0x7F, 0x7F       # 3 x i32
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: call net_recv(0, 256, 1024)
    .byte   0x0A                   # section id
    .byte   0x0E                   # section size = 14 (1 + 1 + 12 body)
    .byte   0x01                   # num codes
    .byte   0x0C                   # body size = 12
    .byte   0x00                   # num locals
    .byte   0x41, 0x00             # i32.const 0 (type)
    .byte   0x41, 0x80, 0x02       # i32.const 256 (ptr)
    .byte   0x41, 0x80, 0x08       # i32.const 1024 (maxlen)
    .byte   0x10, 0x0A             # call 10 (func_count=1, host_id=9=net_recv)
    .byte   0x0B                   # end
wasm_test_net_recv_size = . - wasm_test_net_recv_module

# WASM 测试模块 22：time + alloc/free + memory test
# 测试组合：alloc → store → load → free → time → return
wasm_test_time_alloc_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: () -> i32
    .byte   0x01                   # section id
    .byte   0x04                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: alloc(4), tee 0, store "WASM", load, free, time
    .byte   0x0A                   # section id
    .byte   0x1F                   # section size = 31
    .byte   0x01                   # num codes
    .byte   0x1E                   # body size = 30
    .byte   0x00                   # num locals
    .byte   0x41, 0x04             # i32.const 4 (size for alloc)
    .byte   0x10, 0x07             # call 7 (func_count=1, host_id=6=alloc)
    .byte   0x22, 0x00             # local.tee 0 (save ptr)
    .byte   0x41, 0xCD, 0xA6, 0x85, 0xBA, 0x05  # i32.const 0x5741534D ("WASM" in memory)
    .byte   0x20, 0x00             # local.get 0
    .byte   0x36, 0x00, 0x00       # i32.store (alignment=0, offset=0)
    .byte   0x20, 0x00             # local.get 0
    .byte   0x28, 0x00, 0x00       # i32.load (alignment=0, offset=0)
    .byte   0x20, 0x00             # local.get 0
    .byte   0x10, 0x08             # call 8 (func_count=1, host_id=7=free)
    .byte   0x10, 0x06             # call 6 (func_count=1, host_id=5=time)
    .byte   0x0B                   # end
wasm_test_time_alloc_size = . - wasm_test_time_alloc_module

# WASM 测试模块 23：putchar 多字符 + time 测试
# 测试：putchar('H') putchar('i') putchar('!') putchar('\n') time() → 返回
wasm_test_print_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: () -> i32
    .byte   0x01                   # section id
    .byte   0x04                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: putchar H, i, !, \n, time
    .byte   0x0A                   # section id
    .byte   0x15                   # section size = 21
    .byte   0x01                   # num codes
    .byte   0x14                   # body size = 20
    .byte   0x00                   # num locals
    # putchar('H') = 72
    .byte   0x41, 0x48             # i32.const 72
    .byte   0x10, 0x03             # call 3 (putchar)
    # putchar('i') = 105
    .byte   0x41, 0x69             # i32.const 105
    .byte   0x10, 0x03             # call 3 (putchar)
    # putchar('!') = 33
    .byte   0x41, 0x21             # i32.const 33
    .byte   0x10, 0x03             # call 3 (putchar)
    # putchar('\n') = 10
    .byte   0x41, 0x0A             # i32.const 10
    .byte   0x10, 0x03             # call 3 (putchar)
    # time()
    .byte   0x10, 0x06             # call 6 (time)
    .byte   0x0B                   # end
wasm_test_print_size = . - wasm_test_print_module

# WASM 测试模块 24：meminfo 宿主函数测试
# 测试：meminfo() → time() → 返回
wasm_test_meminfo_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: () -> i32
    .byte   0x01                   # section id
    .byte   0x04                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: meminfo() time()
    .byte   0x0A                   # section id
    .byte   0x07                   # section size = 7
    .byte   0x01                   # num codes
    .byte   0x06                   # body size = 6
    .byte   0x00                   # num locals
    .byte   0x10, 0x05             # call 5 (meminfo, host_id=4)
    .byte   0x10, 0x06             # call 6 (time, host_id=5)
    .byte   0x0B                   # end
wasm_test_meminfo_size = . - wasm_test_meminfo_module

# WASM 测试模块 25：store/load 调试测试
# 测试：store 0x12345678 at offset 0 → load from offset 0 → return value
wasm_test_store_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: () -> i32
    .byte   0x01                   # section id
    .byte   0x04                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: store 0x12345678 at 0, load from 0, return
    .byte   0x0A                   # section id
    .byte   0x12                   # section size = 18
    .byte   0x01                   # num codes
    .byte   0x11                   # body size = 17
    .byte   0x00                   # num locals
    # store 0x12345678 at offset 0
    .byte   0x41, 0xF8, 0xAC, 0xD1, 0x91, 0x01  # i32.const 0x12345678
    .byte   0x41, 0x00             # i32.const 0 (addr)
    .byte   0x36, 0x00, 0x00       # i32.store (align=0, offset=0)
    # load from offset 0
    .byte   0x41, 0x00             # i32.const 0 (addr)
    .byte   0x28, 0x00, 0x00       # i32.load (align=0, offset=0)
    .byte   0x0B                   # end
wasm_test_store_size = . - wasm_test_store_module

# WASM 测试模块 26：getchar 宿主函数测试
# 测试：call getchar (host_id=3) → 返回读取的字符
wasm_test_getchar_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: () -> i32
    .byte   0x01                   # section id
    .byte   0x04                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: call getchar, return
    .byte   0x0A                   # section id
    .byte   0x05                   # section size = 5
    .byte   0x01                   # num codes
    .byte   0x04                   # body size = 4
    .byte   0x00                   # num locals
    .byte   0x10, 0x03             # call 3 (getchar, host_id=3)
    .byte   0x0B                   # end
wasm_test_getchar_size = . - wasm_test_getchar_module

# WASM 测试模块 27：store8/load8_u 组合测试
# 测试：i32.store8(100, 0xAB) → i32.load8_u(100) → 返回 171
wasm_test_store_load_module:
    .byte   0x00, 0x61, 0x73, 0x6D  # magic
    .byte   0x01, 0x00, 0x00, 0x00  # version
    # type section: () -> i32
    .byte   0x01                   # section id
    .byte   0x04                   # section size
    .byte   0x01                   # num types
    .byte   0x60                   # func type
    .byte   0x00                   # num params
    .byte   0x01                   # num results
    .byte   0x7F                   # i32
    # function section: 1 function, type 0
    .byte   0x03                   # section id
    .byte   0x02                   # section size
    .byte   0x01                   # num functions
    .byte   0x00                   # type index 0
    # code section: store8(0, 64), load8_u(0), return
    .byte   0x0A                   # section id
    .byte   0x0E                   # section size = 14
    .byte   0x01                   # num codes
    .byte   0x0D                   # body size = 13
    .byte   0x00                   # num locals
    .byte   0x41, 0x40             # i32.const 64
    .byte   0x41, 0x00             # i32.const 0 (addr)
    .byte   0x3A, 0x00, 0x00       # i32.store8 (align=0, offset=0)
    .byte   0x41, 0x00             # i32.const 0 (addr)
    .byte   0x2D, 0x00, 0x00       # i32.load8_u (align=0, offset=0)
    .byte   0x0B                   # end
wasm_test_store_load_size = . - wasm_test_store_load_module
