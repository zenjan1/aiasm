    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# process.asm - 进程管理与调度（时间片轮转）
# -----------------------------------------------------------------------------
# 最多 16 个进程，每个 PCB 256 字节，内核栈 4KB
# 调度器由 PIT IRQ0 驱动，时间片 10 ticks（~100ms）
# PID 0 = 内核主线程
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# 常量定义
# ============================================================================
MAX_PROCS       = 16            # 最大进程数
KERNEL_STACK_SIZE = 4096        # 每个进程内核栈 4KB
TIME_SLICE      = 10            # 时间片（PIT tick 数）

# 进程状态
PROC_FREE       = 0
PROC_RUNNING    = 1
PROC_READY      = 2
PROC_ZOMBIE     = 3

# PCB 结构偏移（字节）
PCB_PID         = 0
PCB_STATE       = 4
PCB_REGS_EAX    = 8
PCB_REGS_EBX    = 12
PCB_REGS_ECX    = 16
PCB_REGS_EDX    = 20
PCB_REGS_ESI    = 24
PCB_REGS_EDI    = 28
PCB_REGS_EBP    = 32
PCB_REGS_ESP    = 36
PCB_REGS_EIP    = 40
PCB_REGS_EFLAGS = 44
PCB_REGS_CS     = 48
PCB_REGS_DS     = 52
PCB_REGS_ES     = 56
PCB_REGS_FS     = 60
PCB_REGS_GS     = 64
PCB_REGS_SS     = 68
PCB_KSTACK      = 72            # 内核栈指针（切换用）
PCB_PARENT_PID  = 76
PCB_EXIT_CODE   = 80
PCB_STACK_BASE  = 84            # 栈基址（释放用）
PCB_TICKS_LEFT  = 88            # 剩余时间片
PCB_FPU_SAVED   = 92            # FPU 状态是否已保存（标志）
PCB_FPU_STATE   = 96            # FPU 状态保存区（108 字节，fnsave 格式）
PCB_FD_TABLE    = 208           # 文件描述符表偏移（8 个 FD × 8 字节 = 64 字节）
PCB_SIZE        = 272           # PCB 大小（字节）- 扩展到 272（含 FD 表）

# 文件描述符结构（8 字节/项）
FD_TYPE         = 0             # 类型：0=空闲, 1=stdin, 2=stdout, 3=stderr, 4=VFS文件, 5=FAT32文件
FD_FILE_IDX     = 4             # 文件索引（VFS entry 或 FAT32 cluster）
# FD 表：8 个条目 × 8 字节 = 64 字节，偏移 PCB_FD_TABLE
# FD 0-2 = 标准流, FD 3+ = 文件

# 文件描述符类型常量
FD_TYPE_FREE    = 0
FD_TYPE_STDIN   = 1
FD_TYPE_STDOUT  = 2
FD_TYPE_STDERR  = 3
FD_TYPE_VFS     = 4
FD_TYPE_FAT32   = 5

# ============================================================================
# BSS 变量
# ============================================================================
    .section .bss
    .align  4096

    # 进程表：16 * 256 = 4096 字节
    .globl  proc_table
proc_table:
    .space  MAX_PROCS * PCB_SIZE

    # 内核栈池：16 * 4096 = 65536 字节
proc_stacks:
    .space  MAX_PROCS * KERNEL_STACK_SIZE

    .globl  current_pid
current_pid:
    .space  4                   # 当前运行进程的 PID

    .globl  next_pid
next_pid:
    .space  4                   # 下一个 PID 分配值

    .globl  scheduler_active
scheduler_active:
    .space  1                   # 调度器是否激活

# ============================================================================
# process_init: 初始化进程管理子系统
# ============================================================================
    .section .text
    .globl  process_init
process_init:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 1. 清零进程表
    mov     edi, offset proc_table
    mov     ecx, (MAX_PROCS * PCB_SIZE) / 4
    xor     eax, eax
    cld
    rep     stosd

    # 2. 创建 PID 0（内核主线程）
    mov     dword ptr [proc_table + PCB_PID], 0
    mov     dword ptr [proc_table + PCB_STATE], PROC_RUNNING
    mov     dword ptr [proc_table + PCB_TICKS_LEFT], TIME_SLICE
    mov     dword ptr [proc_table + PCB_KSTACK], offset proc_stacks + KERNEL_STACK_SIZE
    mov     dword ptr [proc_table + PCB_STACK_BASE], offset proc_stacks + KERNEL_STACK_SIZE

    # 初始化其他进程为 FREE
    mov     ecx, MAX_PROCS - 1
    mov     esi, 1
1:  mov     eax, esi
    imul    eax, PCB_SIZE
    mov     dword ptr [proc_table + eax + PCB_PID], -1    # -1 = 未分配
    mov     dword ptr [proc_table + eax + PCB_STATE], PROC_FREE
    inc     esi
    loop    1b

    # 3. 初始化 PID 0 的文件描述符（0=stdin, 1=stdout, 2=stderr）
    mov     edi, offset proc_table + PCB_FD_TABLE
    mov     dword ptr [edi], FD_TYPE_STDIN        # FD 0 = stdin
    mov     dword ptr [edi + 4], 0
    mov     dword ptr [edi + 8], FD_TYPE_STDOUT   # FD 1 = stdout
    mov     dword ptr [edi + 12], 0
    mov     dword ptr [edi + 16], FD_TYPE_STDERR  # FD 2 = stderr
    mov     dword ptr [edi + 20], 0
    # FD 3-7 = 空闲
    mov     dword ptr [edi + 24], FD_TYPE_FREE
    mov     dword ptr [edi + 28], 0
    mov     dword ptr [edi + 32], FD_TYPE_FREE
    mov     dword ptr [edi + 36], 0
    mov     dword ptr [edi + 40], FD_TYPE_FREE
    mov     dword ptr [edi + 44], 0
    mov     dword ptr [edi + 48], FD_TYPE_FREE
    mov     dword ptr [edi + 52], 0
    mov     dword ptr [edi + 56], FD_TYPE_FREE
    mov     dword ptr [edi + 60], 0

    mov     dword ptr [current_pid], 0
    mov     dword ptr [next_pid], 1
    mov     byte ptr [scheduler_active], 1

    # 调度器由 pit_irq_handler 直接调用，无需注册 IDT gate

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# fork: 创建新进程
# 输出：eax - 父进程返回子进程 PID，子进程返回 0
# ============================================================================
    .globl  fork
fork:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 1. 查找空闲进程槽
    xor     ebx, ebx            # ebx = 进程索引
.find_slot:
    cmp     ebx, MAX_PROCS
    jge     .fail               # 无空闲槽

    mov     eax, ebx
    imul    eax, PCB_SIZE
    mov     eax, [proc_table + eax + PCB_PID]
    cmp     eax, -1
    je      .found_slot
    cmp     eax, 0
    jne     .next_slot
    # PID 0 是内核主线程，跳过
.next_slot:
    inc     ebx
    jmp     .find_slot

.found_slot:
    # 2. 获取当前进程 PCB 指针
    mov     esi, [current_pid]
    imul    esi, PCB_SIZE
    add     esi, offset proc_table  # esi = 当前进程 PCB

    # 2b. 保存当前寄存器到父进程 PCB（fork 调用时 PCB 可能已过时）
    mov     eax, [esi + PCB_PID]    # 保存 PID（后面会用 eax）
    push    eax

    # 保存 EFLAGS
    pushfd
    pop     eax
    mov     [esi + PCB_REGS_EFLAGS], eax

    # 保存 EIP（返回地址）
    mov     eax, [ebp + 4]
    mov     [esi + PCB_REGS_EIP], eax

    # 保存 ESP
    mov     eax, ebp
    mov     [esi + PCB_REGS_ESP], eax

    # 保存通用寄存器
    mov     eax, ebx
    mov     [esi + PCB_REGS_EBX], eax
    mov     eax, ecx
    mov     [esi + PCB_REGS_ECX], eax
    mov     eax, edx
    mov     [esi + PCB_REGS_EDX], eax
    mov     eax, ebp
    mov     [esi + PCB_REGS_EBP], eax

    pop     eax                     # 恢复 PID
    imul    eax, PCB_SIZE
    add     eax, offset proc_table  # esi = 当前进程 PCB（更新）

    # 3. 获取子进程 PCB 指针
    mov     edi, ebx
    imul    edi, PCB_SIZE
    add     edi, offset proc_table  # edi = 子进程 PCB

    # 4. 复制当前进程的寄存器上下文（64 字节）
    mov     ecx, 16             # 16 dwords = 64 bytes
    lea     esi, [esi + PCB_REGS_EAX]
    lea     edi, [edi + PCB_REGS_EAX]
    cld
    rep     movsd

    # 恢复 edi 为子进程 PCB 基址
    sub     edi, PCB_REGS_EAX
    # 恢复 esi 为当前进程 PCB 基址
    sub     esi, PCB_REGS_EAX

    # 5. 分配内核栈
    mov     eax, ebx
    imul    eax, KERNEL_STACK_SIZE
    add     eax, offset proc_stacks
    add     eax, KERNEL_STACK_SIZE      # 栈顶

    mov     [edi + PCB_KSTACK], eax
    mov     [edi + PCB_STACK_BASE], eax

    # 6. 设置子进程 PCB 字段
    mov     ecx, [next_pid]
    mov     [edi + PCB_PID], ecx
    mov     dword ptr [edi + PCB_STATE], PROC_READY
    mov     dword ptr [edi + PCB_TICKS_LEFT], TIME_SLICE
    mov     dword ptr [edi + PCB_FPU_SAVED], 0    # 子进程无 FPU 状态

    # 获取父进程 PID
    mov     eax, [esi + PCB_PID]
    mov     [edi + PCB_PARENT_PID], eax

    # 子进程 fork 返回值为 0
    mov     dword ptr [edi + PCB_REGS_EAX], 0

    # 6b. 继承父进程的文件描述符表（64 字节 = 16 dwords）
    mov     esi, [current_pid]
    imul    esi, PCB_SIZE
    add     esi, offset proc_table
    mov     ecx, 16             # 16 dwords = 64 bytes
    lea     esi, [esi + PCB_FD_TABLE]
    lea     edi, [edi + PCB_FD_TABLE]
    cld
    rep     movsd

    # 7. 递增 next_pid
    inc     dword ptr [next_pid]

    # 8. 父进程返回子进程 PID
    mov     eax, ecx

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

.fail:
    mov     eax, -1             # 失败返回 -1
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# yield: 主动放弃 CPU，切换到下一个进程
# ============================================================================
    .globl  yield
yield:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp
    mov     ebp, esp

    # 保存当前寄存器到当前进程 PCB
    mov     eax, [current_pid]
    imul    eax, PCB_SIZE
    add     eax, offset proc_table

    # 保存通用寄存器（从栈帧读取，偏移基于 push ebx ecx edx esi edi ebp）
    mov     ebx, [ebp - 28]     # 保存调用者的 ebx
    mov     [eax + PCB_REGS_EBX], ebx
    mov     ebx, [ebp - 24]     # ecx
    mov     [eax + PCB_REGS_ECX], ebx
    mov     ebx, [ebp - 20]     # edx
    mov     [eax + PCB_REGS_EDX], ebx
    mov     ebx, [ebp - 16]     # esi
    mov     [eax + PCB_REGS_ESI], ebx
    mov     ebx, [ebp - 12]     # edi
    mov     [eax + PCB_REGS_EDI], ebx
    mov     ebx, [ebp - 8]      # ebp (caller's)
    mov     [eax + PCB_REGS_EBP], ebx

    # 保存栈指针（当前 esp）
    mov     ebx, esp
    mov     [eax + PCB_REGS_ESP], ebx

    # 保存 EIP（返回地址）
    mov     ebx, [ebp + 4]      # 返回地址
    mov     [eax + PCB_REGS_EIP], ebx

    # 保存 EFLAGS
    pushfd
    pop     ebx
    mov     [eax + PCB_REGS_EFLAGS], ebx

    # 更新状态为 READY
    mov     dword ptr [eax + PCB_STATE], PROC_READY

    # 调用调度器
    call    _schedule

    # 调度器返回，恢复寄存器
    mov     eax, [current_pid]
    imul    eax, PCB_SIZE
    add     eax, offset proc_table

    mov     ebx, [eax + PCB_REGS_EBX]
    mov     [esp + 20], ebx     # restore ebx at stack slot
    mov     ebx, [eax + PCB_REGS_ECX]
    mov     [esp + 24], ebx
    mov     ebx, [eax + PCB_REGS_EDX]
    mov     [esp + 28], ebx
    mov     ebx, [eax + PCB_REGS_ESI]
    mov     [esp + 32], ebx
    mov     ebx, [eax + PCB_REGS_EDI]
    mov     [esp + 36], ebx
    mov     ebx, [eax + PCB_REGS_EBP]
    mov     [esp + 40], ebx

    pop     ebp
    ret

# ============================================================================
# exit: 终止当前进程
# 输入：ebx = 退出状态码
# 输出：无（调用调度器切换到下一个进程）
# ============================================================================
    .globl  exit
exit:
    push    eax
    push    ecx

    # 如果是 PID 0，不能退出（内核主线程）
    cmp     dword ptr [current_pid], 0
    je      .cant_exit

    # 关闭所有打开的文件描述符 (FD 3-7)
    mov     eax, [current_pid]
    imul    eax, PCB_SIZE
    add     eax, offset proc_table
    add     eax, PCB_FD_TABLE + 24   # FD 3 起始偏移 (每个 FD 8 字节)
    mov     ecx, 5                   # FD 3-7 共 5 个
.close_fd_loop:
    cmp     dword ptr [eax], FD_TYPE_FREE
    je      .next_fd
    mov     dword ptr [eax], FD_TYPE_FREE
    mov     dword ptr [eax + 4], 0
.next_fd:
    add     eax, 8
    loop    .close_fd_loop

    # 标记当前进程为 ZOMBIE
    mov     eax, [current_pid]
    imul    eax, PCB_SIZE
    add     eax, offset proc_table
    mov     dword ptr [eax + PCB_STATE], PROC_ZOMBIE
    mov     [eax + PCB_EXIT_CODE], ebx

    # 尝试回收僵尸子进程
    call    _reap_zombies

    # 切换到下一个进程
    call    _schedule

.cant_exit:
    pop     ecx
    pop     eax
    ret

# ============================================================================
# getpid: 获取当前进程 PID
# 输出：eax = 当前进程 PID
# ============================================================================
    .globl  getpid
getpid:
    mov     eax, [current_pid]
    ret

# ============================================================================
# _schedule: 内部调度器核心
# 查找下一个 READY 进程并切换到它
# ============================================================================
_schedule:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi

    # 检查是否有可运行的进程
    mov     ecx, MAX_PROCS
    xor     edx, edx            # edx = 起始索引 = current_pid
    mov     esi, [current_pid]

.find_next:
    inc     esi
    cmp     esi, MAX_PROCS
    jl      .check_proc
    xor     esi, esi            # 绕回
.check_proc:
    mov     eax, esi
    imul    eax, PCB_SIZE
    mov     ebx, [proc_table + eax + PCB_STATE]
    cmp     ebx, PROC_READY
    je      .found_proc
    cmp     ebx, PROC_RUNNING
    je      .found_proc

    dec     ecx
    jnz     .find_next

    # 没有找到其他进程，切换回 PID 0
    mov     esi, 0

.found_proc:
    mov     [current_pid], esi

    # 更新新进程状态为 RUNNING
    mov     eax, esi
    imul    eax, PCB_SIZE
    mov     dword ptr [proc_table + eax + PCB_STATE], PROC_RUNNING
    mov     dword ptr [proc_table + eax + PCB_TICKS_LEFT], TIME_SLICE

    # 设置新进程的内核栈
    mov     esp, [proc_table + eax + PCB_KSTACK]

    # 保存当前进程的 FPU 状态（如果已使用）
    mov     edi, [current_pid]
    imul    edi, PCB_SIZE
    cmp     dword ptr [proc_table + edi + PCB_FPU_SAVED], 0
    je      .fpu_skip_save
    fnsave  [proc_table + edi + PCB_FPU_STATE]
.fpu_skip_save:

    # 恢复新进程的寄存器
    mov     ebx, [proc_table + eax + PCB_REGS_EBX]
    mov     ecx, [proc_table + eax + PCB_REGS_ECX]
    mov     edx, [proc_table + eax + PCB_REGS_EDX]

    # 恢复新进程的 FPU 状态（如果已保存）
    cmp     dword ptr [proc_table + eax + PCB_FPU_SAVED], 0
    je      .fpu_skip_restore
    frstor  [proc_table + eax + PCB_FPU_STATE]
    mov     dword ptr [proc_table + eax + PCB_FPU_SAVED], 1
.fpu_skip_restore:

    # 标记新进程 FPU 状态为已保存
    mov     dword ptr [proc_table + eax + PCB_FPU_SAVED], 1

    # 跳转到新进程的 EIP
    mov     eax, [proc_table + eax + PCB_REGS_EIP]
    test    eax, eax
    jz      .no_eip
    push    eax                 # 返回地址压栈
    ret                         # 跳转到 EIP

.no_eip:
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _reap_zombies: 回收僵尸进程
# ============================================================================
_reap_zombies:
    push    eax
    push    ecx
    push    esi
    push    edi

    mov     ecx, MAX_PROCS
    xor     esi, esi            # esi = loop index (preserved across rep stosd)
1:  mov     edx, esi
    imul    edx, PCB_SIZE
    mov     ebx, [proc_table + edx + PCB_STATE]
    cmp     ebx, PROC_ZOMBIE
    jne     .next_zombie

    # Zero PCB (rep stosd clobbers ecx and edi, but not esi or eax)
    push    ecx                 # save loop counter
    mov     edi, edx
    add     edi, offset proc_table
    mov     ecx, PCB_SIZE / 4
    xor     eax, eax
    cld
    rep     stosd
    pop     ecx                 # restore loop counter

    # Mark as FREE
    mov     edx, esi
    imul    edx, PCB_SIZE
    mov     dword ptr [proc_table + edx + PCB_PID], -1
    mov     dword ptr [proc_table + edx + PCB_STATE], PROC_FREE

.next_zombie:
    inc     esi
    loop    1b

    pop     edi
    pop     esi
    pop     ecx
    pop     eax
    ret

# ============================================================================
# schedule_tick: 由 PIT IRQ0 调用，用于时间片轮转调度
# 在 pit_irq_handler 内部调用
# ============================================================================
    .globl  schedule_tick
schedule_tick:
    push    eax
    push    ecx

    # 递减当前进程时间片
    mov     eax, [current_pid]
    imul    eax, PCB_SIZE
    mov     ecx, [proc_table + eax + PCB_TICKS_LEFT]
    dec     ecx
    mov     [proc_table + eax + PCB_TICKS_LEFT], ecx

    # 时间片用完，切换进程
    jnz     .done

    # 标记为 READY（如果还在运行）
    cmp     dword ptr [proc_table + eax + PCB_STATE], PROC_RUNNING
    jne     .done
    mov     dword ptr [proc_table + eax + PCB_STATE], PROC_READY
    mov     dword ptr [proc_table + eax + PCB_TICKS_LEFT], TIME_SLICE

    # 时间片用完，触发调度
    call    _schedule

.done:
    pop     ecx
    pop     eax
    ret

# ============================================================================
# get_proc_count: 获取活跃进程数
# 输出：eax = 活跃进程数
# ============================================================================
    .globl  get_proc_count
get_proc_count:
    push    ebx
    push    ecx
    push    edx

    xor     eax, eax
    mov     ecx, MAX_PROCS
    xor     edx, edx
1:  mov     ebx, edx
    imul    ebx, PCB_SIZE
    mov     ebx, [proc_table + ebx + PCB_STATE]
    cmp     ebx, PROC_RUNNING
    je      .count_it
    cmp     ebx, PROC_READY
    je      .count_it
    cmp     ebx, PROC_ZOMBIE
    je      .count_it
    jmp     .next
.count_it:
    inc     eax
.next:
    inc     edx
    loop    1b

    pop     edx
    pop     ecx
    pop     ebx
    ret
