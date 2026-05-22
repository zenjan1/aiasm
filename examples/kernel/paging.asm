    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# paging.asm - 32 位两级分页（内核恒等映射 + 用户空间）
# -----------------------------------------------------------------------------
# 页目录位于物理 0x00110000，页表从 0x00111000 开始
# 内核恒等映射：0xC0000000-0xC0FFFFFF -> 物理 0x00000000-0x00FFFFFF (16MB)
# 低区映射：0x00000000-0x00FFFFFF -> 物理 0x00000000-0x00FFFFFF (过渡用)
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# 常量定义
# ============================================================================
PAGE_DIR_ADDR     = 0x00110000      # 页目录物理地址（页对齐）
PAGE_TABLE_BASE   = 0x00111000      # 页表起始物理地址

# 页表项标志
PT_PRESENT    = 0x01                # P: 页存在
PT_WRITABLE   = 0x02                # R/W: 可写
PT_USER       = 0x04                # U/S: 用户态可访问

# ============================================================================
# BSS 变量
# ============================================================================
    .section .bss
    .globl  page_dir_addr
page_dir_addr:
    .space  4
    .globl  paging_enabled
paging_enabled:
    .space  1

    # 页错误信息
    .globl  pf_last_address
pf_last_address:
    .space  4
    .globl  pf_last_error_code
pf_last_error_code:
    .space  4

# ============================================================================
# paging_init: 初始化分页机制
# ============================================================================
    .section .text
    .globl  paging_init
paging_init:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 1. 清零页目录 (1024 项 * 4 字节)
    mov     edi, PAGE_DIR_ADDR
    mov     ecx, 1024
    xor     eax, eax
    cld
    rep     stosd

    # 2. 清零 4 个页表 (4 * 1024 项)
    mov     edi, PAGE_TABLE_BASE
    mov     ecx, 4096
    xor     eax, eax
    rep     stosd

    # 3. 填写页目录项
    # PT 0-3: 低区映射 0x00000000-0x00FFFFFF
    # PT 768-771: 高区映射 0xC0000000-0xC0FFFFFF (复用相同页表)
    mov     esi, 0                # PT 索引
    mov     edi, PAGE_TABLE_BASE  # 页表物理地址
3:  mov     eax, esi
    imul    eax, 4096             # 页表偏移
    add     eax, edi
    or      eax, PT_PRESENT | PT_WRITABLE

    # 低区目录项 (索引 = esi)
    mov     edx, esi
    imul    edx, 4
    mov     [PAGE_DIR_ADDR + edx], eax

    # 高区目录项 (索引 = esi + 768)
    mov     edx, esi
    add     edx, 768
    imul    edx, 4
    mov     [PAGE_DIR_ADDR + edx], eax

    inc     esi
    cmp     esi, 4
    jl      3b

    # 4. 填写页表项
    # 页表 0: 物理 0x00000000-0x003FFFFF
    # 页表 1: 物理 0x00400000-0x007FFFFF
    # 页表 2: 物理 0x00800000-0x00BFFFFF
    # 页表 3: 物理 0x00C00000-0x00FFFFFF
    mov     edi, PAGE_TABLE_BASE
    mov     eax, 0
    mov     ecx, 1024 * 4         # 总共 4096 项

1:  mov     edx, eax
    or      edx, PT_PRESENT | PT_WRITABLE
    mov     [edi], edx
    add     eax, 4096
    add     edi, 4
    dec     ecx
    jnz     1b

    # 5. 加载 CR3
    mov     eax, PAGE_DIR_ADDR
    mov     cr3, eax

    # 6. 启用分页 (CR0.PG = bit 31)
    mov     eax, cr0
    or      eax, 0x80000000
    mov     cr0, eax

    # 7. 跳转至高区虚拟地址
    lea     eax, [.paging_on]
    jmp     eax

.paging_on:
    mov     dword ptr [page_dir_addr], PAGE_DIR_ADDR
    mov     byte ptr [paging_enabled], 1

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# map_page: 将物理地址映射到虚拟地址
# 输入：eax = 虚拟地址, ebx = 物理地址, ecx = 标志 (0=只读内核, 1=可写内核, 2=可写用户)
# 输出：eax = 0 成功, 非 0 失败
# ============================================================================
    .section .text
    .globl  map_page
map_page:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    mov     esi, eax            # 虚拟地址
    mov     edi, ebx            # 物理地址
    mov     edx, ecx            # 标志

    # 页目录索引 = (虚拟地址 >> 22) & 0x3FF
    mov     eax, esi
    shr     eax, 22
    and     eax, 0x3FF

    # 检查页目录项是否存在
    mov     ebx, [PAGE_DIR_ADDR + eax * 4]
    test    ebx, PT_PRESENT
    jnz     .pt_exists

    # 页表不存在，需要创建（简化：返回失败）
    mov     eax, 1
    jmp     .done

.pt_exists:
    and     ebx, 0xFFFFF000     # 页表物理地址

    # 页表内索引 = (虚拟地址 >> 12) & 0x3FF
    mov     ecx, esi
    shr     ecx, 12
    and     ecx, 0x3FF

    # 写入页表项
    mov     eax, edi
    and     eax, 0xFFFFF000

    # 根据标志设置权限
    cmp     edx, 0
    je      .ro_kernel
    cmp     edx, 1
    je      .rw_kernel
    or      eax, PT_PRESENT | PT_WRITABLE | PT_USER
    jmp     .write_entry

.ro_kernel:
    or      eax, PT_PRESENT
    jmp     .write_entry

.rw_kernel:
    or      eax, PT_PRESENT | PT_WRITABLE

.write_entry:
    mov     [ebx + ecx * 4], eax

    # 刷新 TLB
    mov     eax, cr3
    mov     cr3, eax

    xor     eax, eax

.done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# unmap_page: 取消虚拟地址的映射
# 输入：eax = 虚拟地址
# ============================================================================
    .globl  unmap_page
unmap_page:
    push    ebx
    push    ecx
    push    edx

    # 页目录索引
    mov     ebx, eax
    shr     ebx, 22
    and     ebx, 0x3FF

    mov     edx, [PAGE_DIR_ADDR + ebx * 4]
    test    edx, PT_PRESENT
    jz      .unmap_done
    and     edx, 0xFFFFF000

    # 页表内索引
    mov     ecx, eax
    shr     ecx, 12
    and     ecx, 0x3FF

    mov     dword ptr [edx + ecx * 4], 0

    # 刷新 TLB
    mov     ebx, cr3
    mov     cr3, ebx

.unmap_done:
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# get_physical_address: 获取虚拟地址对应的物理地址
# 输入：eax = 虚拟地址
# 输出：eax = 物理地址（0 表示未映射）
# ============================================================================
    .globl  get_physical_address
get_physical_address:
    push    ebx
    push    ecx
    push    edx

    mov     ebx, eax            # 保存虚拟地址

    # 页目录索引
    shr     ebx, 22
    and     ebx, 0x3FF

    mov     ecx, [PAGE_DIR_ADDR + ebx * 4]
    test    ecx, PT_PRESENT
    jz      .gp_not_mapped
    and     ecx, 0xFFFFF000

    # 页表内索引
    mov     edx, eax
    shr     edx, 12
    and     edx, 0x3FF

    mov     eax, [ecx + edx * 4]
    test    eax, PT_PRESENT
    jz      .gp_not_mapped

    # 物理页帧 + 页内偏移
    and     eax, 0xFFFFF000
    mov     ecx, eax            # 保存页帧
    mov     eax, eax
    and     eax, 0xFFF          # 页内偏移（应该已经是 0，因为页对齐）
    mov     eax, ecx

    pop     edx
    pop     ecx
    pop     ebx
    ret

.gp_not_mapped:
    xor     eax, eax
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# page_fault_handler: #PF 处理程序
# ============================================================================
    .globl  page_fault_handler
page_fault_handler:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi

    mov     eax, cr2
    mov     [pf_last_address], eax

    mov     esi, offset pf_msg
    call    uart_puts

    mov     esi, offset pf_addr_prefix
    call    uart_puts

    mov     edi, offset pf_hex_buf
    mov     dl, 16
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     al, 0x0D
    call    uart_putc
    mov     al, 0x0A
    call    uart_putc

    jmp     kernel_halt

    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

    .section .rodata
pf_msg:
    .asciz  "\r\n*** PAGE FAULT ***\r\n"
pf_addr_prefix:
    .asciz  "Faulting address: "
pf_hex_buf:
    .space  16

    .section .text
