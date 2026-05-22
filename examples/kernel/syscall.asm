    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# syscall.asm - 系统调用接口（INT 0x80）
# -----------------------------------------------------------------------------
# 系统调用号通过 eax 传递，参数通过 ebx/ecx/edx/esi/edi 传递
# 返回值通过 eax 返回
#
# 系统调用表：
#   1 = exit    (ebx=状态码)
#   2 = fork    (无参数)
#   3 = read    (ebx=fd, ecx=buf, edx=len)
#   4 = write   (ebx=fd, ecx=buf, edx=len)
#   5 = open    (ebx=filename, ecx=flags)
#   6 = close   (ebx=fd)
#   7 = getpid  (无参数)
#   8 = yield   (无参数)
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# 系统调用常量
# ============================================================================
SYS_EXIT    = 1
SYS_FORK    = 2
SYS_READ    = 3
SYS_WRITE   = 4
SYS_OPEN    = 5
SYS_CLOSE   = 6
SYS_GETPID  = 7
SYS_YIELD   = 8

MAX_SYSCALL = 8

# 文件描述符
FD_STDIN    = 0
FD_STDOUT   = 1
FD_STDERR   = 2

# ============================================================================
# BSS
# ============================================================================
    .section .bss
    .globl  syscall_count
syscall_count:
    .space  4                   # 系统调用总次数

# ============================================================================
# syscall_dispatch: INT 0x80 入口，从栈帧读取寄存器并分发
# ============================================================================
# 栈帧结构（从 isr_128 压入）：
#   [esp+48] gs
#   [esp+44] fs
#   [esp+40] es
#   [esp+36] ds
#   [esp+32] ebp
#   [esp+28] edi
#   [esp+24] esi
#   [esp+20] ebx
#   [esp+16] edx
#   [esp+12] ecx
#   [esp+8]  eax（进入中断时的值 = 系统调用号）
#   [esp+4]  错误码
#   [esp+0]  返回地址
# ============================================================================
    .section .text
    .globl  syscall_dispatch
syscall_dispatch:
    push    ebp
    mov     ebp, esp
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi

    # 递增系统调用计数
    inc     dword ptr [syscall_count]

    # 获取系统调用号（从原始栈帧的 eax）
    mov     eax, [ebp + 8 + 8]      # 跳过 ebp+8（我们的栈帧）+ 8（isr_handler 栈帧）= 系统调用号
    # 实际上更简单：从原栈帧读取
    mov     eax, [ebp + 16]         # ebp+16 = 原始 eax 位置（错误码+原始寄存器）

    # 检查系统调用号合法性
    test    eax, eax
    jz      .invalid
    cmp     eax, MAX_SYSCALL
    ja      .invalid

    # 查表调用
    dec     eax                     # 系统调用号从 1 开始，转为 0 索引
    cmp     eax, MAX_SYSCALL - 1
    ja      .invalid
    lea     ebx, [syscall_table + eax * 4]
    mov     ebx, [ebx]
    test    ebx, ebx
    jz      .invalid
    call    ebx

    # 保存返回值到栈帧中的 eax 位置
    mov     [ebp + 16], eax

    jmp     .done

.invalid:
    mov     eax, -1                 # 错误：无效系统调用号
    mov     [ebp + 16], eax

.done:
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    pop     ebp
    ret

# ============================================================================
# 系统调用表
# ============================================================================
    .section .data
    .align  4
    .globl  syscall_table
syscall_table:
    .long   sys_exit            # 1
    .long   sys_fork            # 2
    .long   sys_read            # 3
    .long   sys_write           # 4
    .long   sys_open            # 5
    .long   sys_close           # 6
    .long   sys_getpid          # 7
    .long   sys_yield           # 8

# ============================================================================
# sys_exit: 终止进程
# 输入（从栈帧）：ebx = 退出状态码
# ============================================================================
sys_exit:
    push    ebp
    mov     ebp, esp

    # 获取退出状态码（从调用者的 ebx，在栈帧中）
    mov     eax, [ebp + 8]      # 返回地址之后
    # 实际上需要从 syscall_dispatch 的栈帧读取
    # ebx 在 syscall_dispatch 压栈后位于 [ebp+12]
    mov     ebx, [ebp + 12]

    call    exit                # 调用 process.asm 的 exit

    # exit 不应返回，但如果返回了：
    xor     eax, eax
    pop     ebp
    ret

# ============================================================================
# sys_fork: 创建新进程
# 输出：eax = 子进程 PID（父进程）或 0（子进程）
# ============================================================================
sys_fork:
    push    ebp
    mov     ebp, esp
    call    fork
    pop     ebp
    ret

# ============================================================================
# sys_read: 从文件描述符读取
# 输入：ebx = fd, ecx = buf, edx = len
# 输出：eax = 读取字节数 或 -1（错误）
# ============================================================================
sys_read:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi

    # 只支持 STDIN
    cmp     dword ptr [ebp + 8], FD_STDIN
    jne     .not_supported_read

    # 从串口读取（阻塞）
    mov     ecx, [ebp + 20]     # len
    mov     edi, [ebp + 16]     # buf
    mov     eax, 0              # 已读字节数

.read_loop:
    test    ecx, ecx
    jz      .read_done

    call    uart_getc
    mov     [edi], al
    inc     edi
    inc     eax
    dec     ecx
    jmp     .read_loop

.not_supported_read:
    mov     eax, -1

.read_done:
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# sys_write: 向文件描述符写入
# 输入：ebx = fd, ecx = buf, edx = len
# 输出：eax = 写入字节数 或 -1（错误）
# ============================================================================
sys_write:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi

    mov     eax, [ebp + 8]      # fd
    cmp     eax, FD_STDOUT
    je      .do_write
    cmp     eax, FD_STDERR
    je      .do_write

    # 不支持的 fd
    mov     eax, -1
    jmp     .write_exit

.do_write:
    mov     esi, [ebp + 16]     # buf
    mov     ecx, [ebp + 20]     # len
    mov     eax, 0              # 已写字节数

.write_loop:
    test    ecx, ecx
    jz      .write_done

    movzx   eax, byte ptr [esi]
    push    eax
    call    uart_putc
    pop     eax
    inc     esi
    inc     eax
    dec     ecx
    jmp     .write_loop

.write_done:
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

.write_exit:
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# sys_open: 打开文件（stub）
# 输入：ebx = filename, ecx = flags
# 输出：eax = -1（未实现）
# ============================================================================
sys_open:
    mov     eax, -1
    ret

# ============================================================================
# sys_close: 关闭文件（stub）
# 输入：ebx = fd
# 输出：eax = -1（未实现）
# ============================================================================
sys_close:
    mov     eax, -1
    ret

# ============================================================================
# sys_getpid: 获取当前进程 PID
# 输出：eax = PID
# ============================================================================
sys_getpid:
    mov     eax, [current_pid]
    ret

# ============================================================================
# sys_yield: 主动放弃 CPU
# ============================================================================
sys_yield:
    call    yield
    xor     eax, eax            # 返回 0
    ret

# ============================================================================
# syscall_init: 注册 INT 0x80 系统调用门
# ============================================================================
    .globl  syscall_init
syscall_init:
    push    eax
    push    edi

    mov     dword ptr [syscall_count], 0

    # INT 0x80 = 向量 128
    mov     edi, 128
    mov     eax, offset isr_128
    call    idt_set_gate_user

    pop     edi
    pop     eax
    ret
