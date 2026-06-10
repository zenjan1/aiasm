    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# idt.asm - 中断描述符表 (IDT) + 中断处理函数
# -----------------------------------------------------------------------------
# 支持 0-255 向量（INT 0x80 = 128 为系统调用）
# -----------------------------------------------------------------------------
    .code32

NUM_IDT_ENTRIES = 256

# ============================================================================
# IRQ 处理函数表 (16 个指针，由 pit/keyboard 注册)
# ============================================================================
    .section .data
    .align  4
    .globl  irq_handler_table
irq_handler_table:
    .space  64                # 16 * 4 字节

# ============================================================================
# IDT 表 (256 项 × 8 字节 = 2048 字节) — 必须可写，运行时填充
# ============================================================================
    .section .data
    .align  8
idt_table:
    .space  NUM_IDT_ENTRIES * 8

idt_ptr_val:
    .word   NUM_IDT_ENTRIES * 8 - 1
    .long   idt_table

# ============================================================================
# 宏：生成单个中断处理函数
# ============================================================================
.altmacro
.macro PUSH_ERR idx
    .if (\idx == 8 || \idx == 10 || \idx == 11 || \idx == 12 || \idx == 13 || \idx == 14 || \idx == 17)
    # CPU already pushed error code
    .else
    push    0                 # dummy error code
    .endif
.endm

.macro POP_ERR idx
    add     esp, 4            # skip error code (dummy or real)
.endm

.macro DEFINE_ISR idx
    .globl isr_\idx
isr_\idx:
    PUSH_ERR \idx
    push    eax
    push    ecx
    push    edx
    push    ebx
    push    esi
    push    edi
    push    ebp
    push    ds
    push    es
    push    fs
    push    gs

    mov     eax, 0x10
    mov     ds, eax
    mov     es, eax
    mov     fs, eax
    mov     gs, eax

    push    \idx
    call    isr_handler
    add     esp, 4

    mov     eax, 0x10
    mov     ds, eax
    mov     es, eax
    mov     fs, eax
    mov     gs, eax

    pop     gs
    pop     fs
    pop     es
    pop     ds
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    pop     edx
    pop     ecx
    pop     eax

    POP_ERR \idx
    iret
.endm

# 生成 256 个中断处理函数
.set i, 0
.rept 256
    DEFINE_ISR %i
    .set i, i+1
.endr

# ============================================================================
# 中断处理函数地址表 (256 项)
# ============================================================================
    .align  4
isr_address_table:
.altmacro
.macro ADDR_ENTRY idx
    .long isr_\idx
.endm

.set j, 0
.rept 256
    ADDR_ENTRY %j
    .set j, j+1
.endr

# ============================================================================
# isr_handler: 中断分发 (被每个 isr_N 调用)
# 输入: [esp+4] = 中断编号
# ============================================================================
    .section .text
    .globl  isr_handler
isr_handler:
    push    ebp
    mov     ebp, esp
    push    eax
    push    ebx
    push    ecx
    push    edx

    mov     eax, [ebp + 8]    # 中断编号

    # INT 0x80 (128) = 系统调用
    cmp     eax, 128
    je      .syscall

    # 判断是否为 IRQ (32-47)
    cmp     eax, 32
    jl      .is_exception
    cmp     eax, 47
    jg      .unknown

    # IRQ: 查表调用处理函数
    sub     eax, 32
    lea     ebx, [irq_handler_table + eax * 4]
    mov     ebx, [ebx]
    test    ebx, ebx
    jz      .no_handler
    call    ebx
    jmp     .done

.is_exception:
    # 异常: 根据类型分别处理
    cmp     eax, 14             # #PF (Page Fault)
    je      .handle_pf
    cmp     eax, 13             # #GP (General Protection Fault)
    je      .handle_gp
    cmp     eax, 0              # #DE (Divide Error)
    je      .handle_de
    # 其他异常: 打印信息并挂起
    mov     eax, [esp + 8]      # 从原始栈读取异常向量
    jmp     kernel_halt

.handle_pf:
    # Page Fault: 读取 CR2 并打印
    mov     eax, cr2
    push    eax                 # fault address
    call    log_page_fault
    add     esp, 4
    # 如果 paging.asm 有 demand page handler，尝试恢复
    call    demand_page_alloc
    test    eax, eax
    jnz     .done               # 恢复成功
    jmp     kernel_halt

.handle_gp:
    # #GP: 打印 GPF 信息
    mov     eax, [esp + 32]     # error code (deep in ISR stack)
    push    eax
    call    log_gpf
    add     esp, 4
    jmp     kernel_halt

.handle_de:
    # #DE: 除零错误，不挂起，返回错误码
    jmp     .done               # 继续执行，让代码处理错误

.unknown:
    # 未知中断向量: 静默忽略
    jmp     .done

.no_handler:
    # 未注册的 IRQ: 发送 EOI 并静默忽略
    push    eax
    call    pic_send_eoi
    add     esp, 4
.done:
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    pop     ebp
    ret

.syscall:
    call    syscall_dispatch
    add     esp, 4            # pop error code (dummy or real)
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    pop     ebp
    ret

# ============================================================================
# idt_set_gate: 设置单个 IDT 项
# 输入: edi = index, eax = handler address
# ============================================================================
    .globl  idt_set_gate
idt_set_gate:
    push    edx
    push    ecx

    lea     ecx, [idt_table + edi * 8]
    mov     [ecx], ax           # offset low
    shr     eax, 16
    mov     [ecx + 6], ax       # offset high
    mov     word ptr [ecx + 2], 0x08  # selector (kernel code)
    mov     byte ptr [ecx + 4], 0x00  # zero
    mov     byte ptr [ecx + 5], 0x8E  # flags: present, DPL=0, 32-bit interrupt gate

    pop     ecx
    pop     edx
    ret

# ============================================================================
# idt_set_gate_user: 设置用户态可访问的 IDT 项 (DPL=3)
# 输入: edi = index, eax = handler address
# ============================================================================
    .globl  idt_set_gate_user
idt_set_gate_user:
    push    edx
    push    ecx

    lea     ecx, [idt_table + edi * 8]
    mov     [ecx], ax           # offset low
    shr     eax, 16
    mov     [ecx + 6], ax       # offset high
    mov     word ptr [ecx + 2], 0x08  # selector (kernel code)
    mov     byte ptr [ecx + 4], 0x00  # zero
    mov     byte ptr [ecx + 5], 0xEE  # flags: present, DPL=3, 32-bit interrupt gate

    pop     ecx
    pop     edx
    ret

# ============================================================================
# idt_load: 填充 IDT 表并加载
# ============================================================================
    .globl  idt_load
idt_load:
    push    eax
    push    edx
    push    ecx

    xor     ecx, ecx
1:  cmp     ecx, NUM_IDT_ENTRIES
    jge     2f

    lea     edx, [isr_address_table + ecx * 4]
    mov     eax, [edx]

    mov     edi, ecx
    call    idt_set_gate

    inc     ecx
    jmp     1b

2:  lidt    [idt_ptr_val]
    pop     ecx
    pop     edx
    pop     eax
    ret

# ============================================================================
# 外部符号声明
# ============================================================================
    .globl  kernel_halt
    .globl  pic_send_eoi
    .globl  syscall_dispatch

# ============================================================================
# log_page_fault: 打印 Page Fault 信息（CR2 已在 eax 中）
# 输入：[esp+4] = fault address
# ============================================================================
    .globl  log_page_fault
log_page_fault:
    push    ebp
    mov     ebp, esp
    push    eax
    push    esi

    mov     esi, offset pf_log_msg
    call    uart_puts

    # 打印 CR2 值（从参数读取）
    mov     eax, [ebp + 8]
    mov     edi, offset pf_log_hex
    mov     dl, 8
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     al, 0x0D
    call    uart_putc
    mov     al, 0x0A
    call    uart_putc

    pop     esi
    pop     eax
    pop     ebp
    ret

# ============================================================================
# log_gpf: 打印 General Protection Fault 信息
# 输入：[esp+4] = error code
# ============================================================================
    .globl  log_gpf
log_gpf:
    push    ebp
    mov     ebp, esp
    push    eax
    push    esi

    mov     esi, offset gpf_log_msg
    call    uart_puts

    # 打印 error code
    mov     eax, [ebp + 8]
    mov     edi, offset gpf_log_hex
    mov     dl, 8
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     al, 0x0D
    call    uart_putc
    mov     al, 0x0A
    call    uart_putc

    pop     esi
    pop     eax
    pop     ebp
    ret

    .section .rodata
pf_log_msg:
    .asciz  "\r\n*** PAGE FAULT *** CR2=0x"
pf_log_hex:
    .space  16
gpf_log_msg:
    .asciz  "\r\n*** GENERAL PROTECTION FAULT *** ERR=0x"
gpf_log_hex:
    .space  16
