    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# log.asm - 内核日志系统（纯汇编）
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# 常量定义
# ============================================================================
LOG_DEBUG   = 0
LOG_INFO    = 1
LOG_WARN    = 2
LOG_ERROR   = 3

LOG_RING_SIZE = 4096

# ============================================================================
# BSS 变量
# ============================================================================
    .section .bss
    .globl  log_ring_buf
log_ring_buf:
    .space  LOG_RING_SIZE
    .globl  log_ring_head
log_ring_head:
    .space  4
    .globl  log_ring_tail
log_ring_tail:
    .space  4
    .globl  log_min_level
log_min_level:
    .space  1

log_tmp_buf:
    .space  64              # 临时缓冲区（时间戳/格式化输出）

log_saved_msg_ptr:
    .space  4               # log_print 内部用：保存原始消息指针
log_saved_level:
    .space  1               # log_print 内部用：保存当前级别

# ============================================================================
# log_init: 初始化日志系统
# ============================================================================
    .section .text
    .globl  log_init
log_init:
    push    eax
    push    ecx
    push    edi

    xor     eax, eax
    mov     [log_ring_head], eax
    mov     [log_ring_tail], eax
    mov     byte ptr [log_min_level], LOG_DEBUG

    # 清零环形缓冲区
    mov     edi, offset log_ring_buf
    mov     ecx, LOG_RING_SIZE / 4
    rep     stosd

    pop     edi
    pop     ecx
    pop     eax
    ret

# ============================================================================
# log_set_level: 设置最低日志级别
# 输入: edi = 级别 (LOG_DEBUG/LOG_INFO/LOG_WARN/LOG_ERROR)
# ============================================================================
    .globl  log_set_level
log_set_level:
    mov     eax, edi
    mov     [log_min_level], al
    ret

# ============================================================================
# log_ring_push: 将字符存入环形缓冲区
# 输入: al = 字符
# ============================================================================
log_ring_push:
    push    ecx
    push    edx

    mov     ecx, [log_ring_head]
    mov     edx, [log_ring_tail]

    # head = (head + 1) % SIZE
    mov     eax, ecx
    inc     eax
    cmp     eax, LOG_RING_SIZE
    jne     1f
    xor     eax, eax
1:
    # 检查缓冲区是否已满 (new_head == tail)
    cmp     eax, edx
    jne     2f                # 未满，正常写入
    # 已满：丢弃最旧条目，推进 tail
    inc     edx
    cmp     edx, LOG_RING_SIZE
    jne     2f
    xor     edx, edx

2:  mov     [log_ring_buf + ecx], al
    mov     [log_ring_head], eax
    mov     [log_ring_tail], edx

    pop     edx
    pop     ecx
    ret

# ============================================================================
# log_flush_ring: 将环形缓冲区内容输出到串口
# ============================================================================
    .globl  log_flush_ring
log_flush_ring:
    push    eax
    push    ecx

1:  mov     ecx, [log_ring_tail]
    cmp     ecx, [log_ring_head]
    je      2f                # 缓冲区为空

    movzx   eax, byte ptr [log_ring_buf + ecx]
    push    ecx
    call    uart_putc
    pop     ecx

    # tail = (tail + 1) % SIZE
    inc     ecx
    cmp     ecx, LOG_RING_SIZE
    jne     1f
    xor     ecx, ecx
1:  mov     [log_ring_tail], ecx
    jmp     1b

2:  pop     ecx
    pop     eax
    ret

# ============================================================================
# log_timestamp: 格式化时间戳 "[S.mmm]" 到 log_tmp_buf
# 使用 PIT tick_count (100Hz = 10ms/tick)
# 输出: esi = 格式化后字符串指针
# ============================================================================
log_timestamp:
    push    eax
    push    edx
    push    ecx
    push    edi
    push    ebx

    call    get_tick_count        # eax = tick count

    # seconds = eax / 100, remainder = edx
    mov     ecx, 100
    xor     edx, edx
    div     ecx                   # eax = seconds, edx = remainder
    mov     ebx, edx              # 保存余数

    # 写入 '['
    mov     edi, offset log_tmp_buf
    mov     byte ptr [edi], '['
    inc     edi

    # 转换秒数
    push    edi
    mov     dl, 10
    call    utils_itoa            # eax = string pointer
    pop     edi
    # 复制字符串到缓冲区
    mov     esi, eax
1:  movzx   ecx, byte ptr [esi]
    mov     [edi], cl
    test    cl, cl
    je      2f
    inc     edi
    inc     esi
    jmp     1b

2:  # 写入 '.'
    mov     byte ptr [edi], '.'
    inc     edi

    # ms = remainder * 10 (10ms per tick)
    mov     eax, ebx
    imul    eax, 10               # eax = milliseconds (0-990)

    # 转换毫秒数（零填充到3位）
    mov     ebx, edi
    mov     ecx, 100
    xor     edx, edx
    div     ecx                   # eax = 百位, edx = remainder
    add     al, '0'
    mov     [edi], al
    inc     edi

    mov     eax, edx
    mov     ecx, 10
    xor     edx, edx
    div     ecx                   # eax = 十位, edx = 个位
    add     al, '0'
    mov     [edi], al
    inc     edi

    add     dl, '0'
    mov     [edi], dl
    inc     edi

    # 写入 ']' 和 null
    mov     byte ptr [edi], ']'
    inc     edi
    mov     byte ptr [edi], 0

    mov     esi, offset log_tmp_buf

    pop     ebx
    pop     edi
    pop     ecx
    pop     edx
    pop     eax
    ret

# ============================================================================
# log_print_str_len: 打印字符串到串口和 VGA
# 输入: esi = 字符串指针, ecx = 长度, bl = VGA 属性
# ============================================================================
log_print_str_len:
    push    eax
    push    edx
    push    ecx
    push    esi
    push    ebx

    # 保存原始 VGA 属性
    mov     dl, [vga_attr]
    push    edx
    mov     [vga_attr], bl

    push    ecx
    push    esi

    # 串口输出
1:  movzx   eax, byte ptr [esi]
    push    eax
    call    uart_putc
    pop     eax
    inc     esi
    dec     ecx
    jnz     1b

    # VGA 输出
    pop     esi               # 原始 esi
    pop     ecx               # 原始 ecx
2:  movzx   eax, byte ptr [esi]
    push    eax
    call    vga_putchar
    pop     eax
    inc     esi
    dec     ecx
    jnz     2b

    # 恢复 VGA 属性
    pop     edx
    mov     [vga_attr], dl

    pop     ebx
    pop     esi
    pop     ecx
    pop     edx
    pop     eax
    ret

# ============================================================================
# log_print: 打印字符串（带时间戳和级别前缀）
# 输入: esi = 字符串指针, edi = 级别
# ============================================================================
    .globl  log_print
log_print:
    push    ebp
    mov     ebp, esp
    push    esi
    push    edi
    push    eax
    push    ebx
    push    ecx
    push    edx

    # 保存原始参数到局部变量
    mov     [log_saved_msg_ptr], esi
    mov     eax, edi
    mov     [log_saved_level], al

    # 检查日志级别
    movzx   eax, byte ptr [log_min_level]
    cmp     edi, eax
    jl      .done               # 级别太低，跳过

    # 获取时间戳
    call    log_timestamp       # esi = "[S.mmm]" 字符串指针

    # 获取字符串长度
    push    esi
    call    utils_strlen
    mov     ecx, eax
    pop     esi

    # 输出时间戳（串口 + VGA，白色）
    mov     bl, 0x07
    call    log_print_str_len

    # 根据级别选择前缀和颜色
    movzx   eax, byte ptr [log_saved_level]
    cmp     eax, LOG_WARN
    je      .is_warn
    cmp     eax, LOG_ERROR
    je      .is_error
    # DEBUG 或 INFO
.is_info:
    mov     esi, offset str_info
    mov     ebx, 0x07           # 白色
    jmp     .got_prefix
.is_warn:
    mov     esi, offset str_warn
    mov     ebx, 0x06           # 黄色
    jmp     .got_prefix
.is_error:
    mov     esi, offset str_error
    mov     ebx, 0x0C           # 亮红

.got_prefix:
    push    esi
    call    utils_strlen
    mov     ecx, eax
    pop     esi
    call    log_print_str_len

    # 输出原始消息
    mov     esi, [log_saved_msg_ptr]
    push    esi
    call    utils_strlen
    mov     ecx, eax
    pop     esi
    call    log_print_str_len

    # 换行
    mov     al, 0x0A
    call    uart_putc
    call    vga_putchar
    mov     al, 0x0D
    call    uart_putc
    call    vga_putchar

    # 恢复原始 VGA 属性
    mov     byte ptr [vga_attr], 0x07

.done:
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    pop     edi
    pop     esi
    pop     ebp
    ret

    .section .rodata
str_debug:
    .asciz  "[DEBUG] "
str_info:
    .asciz  "[INFO] "
str_warn:
    .asciz  "[WARN] "
str_error:
    .asciz  "[ERROR] "
