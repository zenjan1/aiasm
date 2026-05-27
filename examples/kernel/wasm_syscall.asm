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

# ============================================================================
# WASM 系统调用计数
# ============================================================================
    .section .bss
    .globl  wasm_syscall_count
wasm_syscall_count:
    .space  4

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
    push    eax
    call    get_total_memory
    mov     esi, eax
    push    esi

    mov     esi, offset msg_mem_total
    call    uart_puts

    pop     esi
    mov     eax, esi
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     esi, offset msg_mem_kb
    call    uart_puts

    call    get_free_memory
    push    eax

    mov     esi, offset msg_mem_free
    call    uart_puts

    pop     eax
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     esi, offset msg_mem_kb2
    call    uart_puts

    pop     eax
    xor     eax, eax
    jmp     .done

.host_time:
    call    get_tick_count
    jmp     .done

.host_alloc:
    # ebx = size
    # 简化实现：从 WASM 线性内存末尾分配
    mov     eax, [wasm_memory_pages]
    shl     eax, 16               # eax = 当前内存总大小（字节）
    mov     ecx, eax              # 保存分配起始偏移
    add     eax, ebx              # eax = 新的末尾
    shr     eax, 16               # 新页数
    inc     eax                   # 向上取整到页边界
    cmp     eax, 4               # 最大 4 页 = 256KB
    ja      .alloc_fail
    mov     [wasm_memory_pages], eax

    # 返回分配的偏移（旧末尾）
    mov     eax, ecx
    jmp     .done

.alloc_fail:
    mov     eax, -1
    jmp     .done

.host_free:
    # ebx = ptr
    # 简化实现：暂不支持真正的释放
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
msg_mem_total:
    .asciz  "Total: "
msg_mem_free:
    .asciz  " KB, Free: "
msg_mem_kb:
    .asciz  " KB"
msg_mem_kb2:
    .asciz  " KB\n"
