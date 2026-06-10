    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# memory.asm - 物理内存管理器（位图式分配器）
# -----------------------------------------------------------------------------
# 管理 128MB 物理内存，4KB 页，位图分配
# 自动保留内核区（0-2MB）、VGA（0xB8000）、BIOS ROM（0xF0000-0xFFFFF）
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# 常量定义
# ============================================================================
MAX_MEMORY_MB   = 128
MAX_MEMORY      = MAX_MEMORY_MB * 1024 * 1024
PAGE_SIZE       = 4096
NUM_PAGES       = MAX_MEMORY / PAGE_SIZE        # 32768 页
BITMAP_SIZE     = NUM_PAGES / 8                 # 4096 字节位图

RESERVE_END     = 0x00200000    # 保留 0-2MB

# ============================================================================
# BSS 变量
# ============================================================================
    .section .bss
    .align  16

    # 位图：每 bit 对应一个 4KB 页，0=空闲，1=已分配
    .globl  mem_bitmap
mem_bitmap:
    .space  BITMAP_SIZE

    .globl  total_pages
total_pages:
    .space  4

    .globl  free_pages
free_pages:
    .space  4

    .globl  mem_initialized
mem_initialized:
    .space  1

    .globl  next_alloc_page
next_alloc_page:
    .space  4

# ============================================================================
# memory_init: 初始化物理内存管理器
# ============================================================================
    .section .text
    .globl  memory_init
memory_init:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 1. 清零整个位图
    mov     edi, offset mem_bitmap
    mov     ecx, BITMAP_SIZE / 4
    xor     eax, eax
    cld
    rep     stosd

    # 2. 标记保留区域：0-2MB (512 页)
    mov     ecx, RESERVE_END / PAGE_SIZE        # 512
    xor     edi, edi            # 从页号 0 开始
1:  push    ecx
    mov     eax, edi
    call    _mark_page_used
    inc     edi
    pop     ecx
    loop    1b

    # 3. 标记 VGA 缓冲区（页号 184）
    mov     eax, 184
    call    _mark_page_used

    # 4. 标记 BIOS ROM（页号 240-255，16 页）
    mov     ecx, 16
    mov     edi, 240
2:  push    ecx
    mov     eax, edi
    call    _mark_page_used
    inc     edi
    pop     ecx
    loop    2b

    # 5. 统计空闲页数（总页数 - 已标记页数）
    # 总可用页数 = NUM_PAGES - 已保留页数
    mov     eax, NUM_PAGES
    sub     eax, 512            # 0-2MB
    sub     eax, 1              # VGA
    sub     eax, 16             # BIOS ROM
    mov     [total_pages], eax
    mov     [free_pages], eax
    mov     dword ptr [next_alloc_page], RESERVE_END / PAGE_SIZE

    mov     byte ptr [mem_initialized], 1

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# alloc_page: 分配一个 4KB 物理页
# 输出：eax = 分配的物理地址（0 表示失败）
# ============================================================================
    .globl  alloc_page
alloc_page:
    push    ebx
    push    ecx
    push    edx

    cmp     dword ptr [free_pages], 0
    jz      .fail

    mov     edx, [next_alloc_page]
    mov     ebx, edx

.scan:
    cmp     ebx, NUM_PAGES
    jge     .wrap_around

    # 检查页号 ebx 对应的位
    push    edx                 # save next_alloc_page across div
    mov     eax, ebx
    mov     ecx, 8
    xor     edx, edx
    div     ecx                 # eax=字节偏移, edx=位号
    pop     edx                 # restore next_alloc_page
    mov     ecx, eax

    movzx   eax, byte ptr [mem_bitmap + ecx]
    bt      eax, edx
    jc      .next_page

    # 找到空闲页，标记为已用
    mov     eax, ebx
    call    _mark_page_used

    dec     dword ptr [free_pages]
    inc     dword ptr [next_alloc_page]

    # 返回物理地址
    mov     eax, ebx
    shl     eax, 12

    pop     edx
    pop     ecx
    pop     ebx
    ret

.wrap_around:
    xor     ebx, ebx
    cmp     ebx, edx
    jge     .fail
    jmp     .scan

.next_page:
    inc     ebx
    jmp     .scan

.fail:
    xor     eax, eax
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# free_page: 释放一个 4KB 物理页
# 输入：eax = 物理页地址
# ============================================================================
    .globl  free_page
free_page:
    push    ebx
    push    ecx
    push    edx

    test    eax, eax
    jz      .free_done

    mov     ebx, eax
    shr     ebx, 12

    cmp     ebx, NUM_PAGES
    jae     .free_done

    mov     eax, ebx
    mov     ecx, 8
    xor     edx, edx
    div     ecx
    mov     ecx, eax

    movzx   eax, byte ptr [mem_bitmap + ecx]
    bt      eax, edx
    jnc     .free_done          # 已经空闲

    # 清除位
    mov     edx, 1
    mov     ecx, ebx
    and     ecx, 7
    shl     edx, cl

    mov     ecx, ebx
    shr     ecx, 3
    movzx   eax, byte ptr [mem_bitmap + ecx]
    not     edx
    and     eax, edx
    mov     [mem_bitmap + ecx], al

    inc     dword ptr [free_pages]

.free_done:
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# get_total_memory: 获取系统总物理内存大小（KB）
# ============================================================================
    .globl  get_total_memory
get_total_memory:
    mov     eax, [total_pages]
    imul    eax, 4
    ret

# ============================================================================
# get_free_memory: 获取当前可用物理内存大小（KB）
# ============================================================================
    .globl  get_free_memory
get_free_memory:
    mov     eax, [free_pages]
    imul    eax, 4
    ret

# ============================================================================
# _mark_page_used: 内部函数，标记页号为已使用
# 输入：eax = 页号
# 破坏：ecx, edx
# ============================================================================
_mark_page_used:
    push    eax
    push    edx

    cmp     eax, NUM_PAGES
    jae     .mark_done

    # 字节偏移 = 页号 / 8
    mov     ecx, eax
    shr     ecx, 3

    # 位号 = 页号 % 8
    mov     edx, eax
    and     edx, 7

    # 设置位
    mov     eax, 1
    mov     cl, dl
    shl     eax, cl

    movzx   edx, byte ptr [mem_bitmap + ecx]
    or      edx, eax
    mov     [mem_bitmap + ecx], dl

.mark_done:
    pop     edx
    pop     eax
    ret
