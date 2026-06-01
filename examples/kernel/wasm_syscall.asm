.intel_syntax noprefix
# -----------------------------------------------------------------------------
# wasm_syscall.asm - WASM 系统调用桥接
# -----------------------------------------------------------------------------
# 扩展系统调用接口，支持 WASM 模块通过宿主函数调用内核服务
# 提供 WASM 程序与内核的交互接口
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# WASM 宿主函数 ID
# ============================================================================
WASM_HOST_PRINT      = 0     # print(ptr, len) -> 打印字符串
WASM_HOST_PRINTLN    = 1     # println(ptr, len) -> 打印字符串并换行
WASM_HOST_PUTCHAR    = 2     # putchar(char) -> 打印单字符
WASM_HOST_GETCHAR    = 3     # getchar() -> char -> 读取单字符
WASM_HOST_MEMINFO    = 4     # meminfo() -> 打印内存信息
WASM_HOST_TIME       = 5     # time() -> 获取系统滴答数
WASM_HOST_ALLOC      = 6     # alloc(size) -> ptr -> 分配内存
WASM_HOST_FREE       = 7     # free(ptr) -> 释放内存
WASM_HOST_NET_SEND   = 8     # net_send(type, dst_ip, dst_port, ptr, len) -> 发送网络数据
WASM_HOST_NET_RECV   = 9     # net_recv(type, ptr, maxlen) -> len -> 接收网络数据
WASM_HOST_NET_STATUS = 10    # net_status() -> 网络状态
WASM_HOST_NET_CONFIG = 11    # net_config(ptr) -> 写入IP/MAC配置到内存

# ============================================================================
# WASM 系统调用计数
# ============================================================================
    .section .bss
    .globl  wasm_syscall_count
wasm_syscall_count:
    .space  4
    .globl  wasm_itoa_buf
wasm_itoa_buf:
    .space  32
    .globl  wasm_itoa_buf2
wasm_itoa_buf2:
    .space  32

# ============================================================================
# wasm_syscall_init: 初始化 WASM 系统调用
# ============================================================================
    .section .text
    .globl  wasm_syscall_init
wasm_syscall_init:
    push    eax
    mov     dword ptr [wasm_syscall_count], 0
    pop     eax
    ret

# ============================================================================
# wasm_host_call: WASM 宿主函数调用
# 输入：eax = 函数 ID, ebx = 参数1, ecx = 参数2, edx = 参数3
# 输出：eax = 返回值
# ============================================================================
    .globl  wasm_host_call
wasm_host_call:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    inc     dword ptr [wasm_syscall_count]

    # 根据函数 ID 分发
    cmp     eax, WASM_HOST_PRINT
    je      .host_print
    cmp     eax, WASM_HOST_PRINTLN
    je      .host_println
    cmp     eax, WASM_HOST_PUTCHAR
    je      .host_putchar
    cmp     eax, WASM_HOST_GETCHAR
    je      .host_getchar
    cmp     eax, WASM_HOST_MEMINFO
    je      .host_meminfo
    cmp     eax, WASM_HOST_TIME
    je      .host_time
    cmp     eax, WASM_HOST_ALLOC
    je      .host_alloc
    cmp     eax, WASM_HOST_FREE
    je      .host_free
    cmp     eax, WASM_HOST_NET_SEND
    je      .host_net_send
    cmp     eax, WASM_HOST_NET_RECV
    je      .host_net_recv
    cmp     eax, WASM_HOST_NET_STATUS
    je      .host_net_status
    cmp     eax, WASM_HOST_NET_CONFIG
    je      .host_net_config

    # 未知函数
    mov     eax, -1
    jmp     .done

.host_print:
    # ebx = ptr (线性内存偏移), ecx = len
    mov     esi, ebx
    add     esi, offset wasm_linear_memory
    mov     edi, ecx              # edi = len
.print_loop:
    test    edi, edi
    jz      .print_done
    movzx   eax, byte ptr [esi]
    push    edi
    call    uart_putc
    pop     edi
    inc     esi
    dec     edi
    jmp     .print_loop
.print_done:
    xor     eax, eax
    jmp     .done

.host_println:
    # ebx = ptr, ecx = len
    mov     esi, ebx
    add     esi, offset wasm_linear_memory
    mov     edi, ecx
.println_loop:
    test    edi, edi
    jz      .println_done
    movzx   eax, byte ptr [esi]
    push    edi
    call    uart_putc
    pop     edi
    inc     esi
    dec     edi
    jmp     .println_loop
.println_done:
    mov     al, 10                # newline
    call    uart_putc
    xor     eax, eax
    jmp     .done

.host_putchar:
    # ebx = char
    mov     eax, ebx
    call    uart_putc
    xor     eax, eax
    jmp     .done

.host_getchar:
    call    uart_getc
    jmp     .done

.host_meminfo:
    # Simplified: just print memory total as hex number
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    call    get_total_memory      # eax = total KB

    # Convert to decimal manually (simple, no itoa)
    mov     ebx, eax              # ebx = value
    mov     edi, offset wasm_itoa_buf
    add     edi, 31
    mov     byte ptr [edi], 0     # null terminator
    dec     edi

    test    ebx, ebx
    jz      .meminfo_zero
.meminfo_loop:
    test    ebx, ebx
    jz      .meminfo_done
    xor     edx, edx
    mov     eax, ebx
    mov     ecx, 10
    div     ecx                   # eax = value/10, edx = remainder
    mov     ebx, eax              # save quotient
    add     dl, '0'
    mov     [edi], dl
    dec     edi
    jmp     .meminfo_loop

.meminfo_done:
    inc     edi                   # edi = string start
    mov     esi, edi
    call    uart_puts

    mov     esi, offset msg_mem_kb2
    call    uart_puts

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    xor     eax, eax
    jmp     .done

.meminfo_zero:
    mov     byte ptr [edi], '0'
    dec     edi
    jmp     .meminfo_done

.host_time:
    call    get_tick_count
    jmp     .done

.host_alloc:
    # ebx = size
    # 从 WASM 线性内存末尾分配（最大 1MB = 16 WASM 页）
    mov     eax, [wasm_memory_pages]
    shl     eax, 16               # eax = 当前内存总大小（字节）
    mov     ecx, eax              # 保存分配起始偏移（返回值）
    add     eax, ebx              # eax = 新的末尾（字节）
    shr     eax, 16               # 新页数（WASM 页）
    inc     eax                   # 向上取整到页边界
    cmp     eax, 16              # 最大 16 WASM 页 = 1MB
    ja      .alloc_fail
    # 计算需要分配的新页数
    mov     edx, eax              # edx = 新页数
    sub     edx, [wasm_memory_pages]  # edx = 新增页数
    # 保存新页数到栈（alloc_page 会破坏 eax）
    push    eax                   # [esp] = 新页数
    mov     esi, edx
    test    esi, esi
    jz      .alloc_skip_pages
.alloc_page_loop:
    call    alloc_page            # eax = 物理页地址
    test    eax, eax
    jz      .alloc_fail_pop
    dec     esi
    jnz     .alloc_page_loop
.alloc_skip_pages:
    pop     eax                   # eax = 新页数
    mov     [wasm_memory_pages], eax

    # 返回分配的偏移（旧末尾）
    mov     eax, ecx
    jmp     .done

.alloc_fail_pop:
    add     esp, 4               # 清理新页数 push
.alloc_fail:
    mov     eax, -1
    jmp     .done

.host_free:
    # ebx = ptr
    # 简化实现：暂不支持真正的释放
    xor     eax, eax
    jmp     .done

.host_net_send:
    # Stack layout after wasm_host_call prologue:
    #   [ebp+8]=ptr, [ebp+12]=len
    #   ebx=type, ecx=dst_ip, edx=dst_port (from .host_5arg)
    mov     esi, [ebp + 8]        # esi = ptr (WASM线性内存偏移)
    mov     edi, [ebp + 12]       # edi = len (save to edi, don't clobber edx=port)
    test    ebx, ebx
    jnz     .net_send_tcp
    # UDP发送
    push    edi                   # len
    add     esi, offset wasm_linear_memory  # esi = 物理地址
    push    esi                   # data ptr
    push    edx                   # port
    push    ecx                   # ip
    call    e1000_send_udp_wasm
    jmp     .done
.net_send_tcp:
    # TCP发送（简化实现，使用当前连接）
    push    edi                   # len
    add     esi, offset wasm_linear_memory
    push    esi                   # data ptr
    push    edx                   # port
    push    ecx                   # ip
    call    e1000_send_tcp_data_wasm
    jmp     .done

.host_net_recv:
    # ebx = type (0=UDP, 1=TCP), ecx = ptr, edx = maxlen
    # 检查是否有数据就绪
    test    ebx, ebx
    jnz     .net_recv_tcp
    # UDP接收
    mov     eax, [udp_recv_ready]
    test    eax, eax
    jz      .net_recv_none
    # 复制数据到WASM线性内存
    mov     esi, offset udp_recv_buf
    mov     edi, ecx
    add     edi, offset wasm_linear_memory
    mov     ecx, [udp_recv_len]
    cmp     ecx, edx
    ja      .net_recv_trunc_udp
    rep     movsb
    mov     eax, [udp_recv_len]
    mov     dword ptr [udp_recv_ready], 0  # 清除标志
    jmp     .done
.net_recv_trunc_udp:
    mov     ecx, edx
    rep     movsb
    mov     eax, edx              # 返回截断长度
    mov     dword ptr [udp_recv_ready], 0
    jmp     .done
.net_recv_tcp:
    # TCP接收
    mov     eax, [tcp_recv_ready]
    test    eax, eax
    jz      .net_recv_none
    mov     esi, offset tcp_recv_buf
    mov     edi, ecx
    add     edi, offset wasm_linear_memory
    mov     ecx, [tcp_recv_len]
    cmp     ecx, edx
    ja      .net_recv_trunc_tcp
    rep     movsb
    mov     eax, [tcp_recv_len]
    mov     dword ptr [tcp_recv_ready], 0
    jmp     .done
.net_recv_trunc_tcp:
    mov     ecx, edx
    rep     movsb
    mov     eax, edx
    mov     dword ptr [tcp_recv_ready], 0
    jmp     .done
.net_recv_none:
    xor     eax, eax              # 返回0表示无数据
    jmp     .done

.host_net_status:
    # 返回网络状态：eax = (e1000_ready << 0) | (dhcp_bound << 8) | (tcp_conn_count << 16)
    movzx   eax, byte ptr [e1000_status]
    movzx   ecx, byte ptr [e1000_dhcp_state]
    cmp     ecx, 3                # DHCP bound?
    jne     .net_status_no_dhcp
    or      eax, 0x100            # DHCP bound bit
.net_status_no_dhcp:
    movzx   ecx, byte ptr [tcp_conn_active_count]
    shl     ecx, 16
    or      eax, ecx
    jmp     .done

.host_net_config:
    # ebx = ptr (WASM线性内存偏移)
    # 写入16字节网络配置：IP(4) + MAC(6) + Gateway(4) + DNS(4) - 2 = 16
    mov     edi, ebx
    add     edi, offset wasm_linear_memory
    # IP地址
    mov     eax, [e1000_our_ip]
    mov     [edi], eax
    # MAC地址
    add     edi, 4
    mov     esi, offset e1000_mac_addr
    mov     ecx, 6
    rep     movsb
    # Gateway
    mov     eax, [e1000_gateway_ip]
    mov     [edi], eax
    add     edi, 4
    # DNS
    mov     eax, [e1000_dns_ip]
    mov     [edi], eax
    xor     eax, eax
    jmp     .done

.done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

    .section .rodata
msg_host_net_send_debug:
    .asciz  "[HOST] net_send called\n"
msg_meminfo_debug:
    .asciz  "[HOST] meminfo called\n"
msg_mem_total:
    .asciz  "Total: "
msg_mem_free:
    .asciz  " KB, Free: "
msg_mem_kb:
    .asciz  " KB"
msg_mem_kb2:
    .asciz  " KB\n"
