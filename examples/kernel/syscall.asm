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

# 文件描述符类型（与 process.asm 中的定义一致）
FD_TYPE_FREE    = 0
FD_TYPE_STDIN   = 1
FD_TYPE_STDOUT  = 2
FD_TYPE_STDERR  = 3
FD_TYPE_VFS     = 4
FD_TYPE_FAT32   = 5

# PCB 结构偏移（与 process.asm 中的定义一致）
PCB_SIZE        = 272
PCB_FD_TABLE    = 208

# ============================================================================
# BSS
# ============================================================================
    .section .bss
    .globl  syscall_count
syscall_count:
    .space  4                   # 系统调用总次数

# 保存原始寄存器值（供 syscall 处理函数使用）
    .globl  syscall_num
syscall_num:
    .space  4                   # 原始 eax（系统调用号）
    .globl  syscall_ebx
syscall_ebx:
    .space  4                   # 原始 ebx（参数1）
    .globl  syscall_ecx
syscall_ecx:
    .space  4                   # 原始 ecx（参数2）
    .globl  syscall_edx
syscall_edx:
    .space  4                   # 原始 edx（参数3）

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

    # 保存原始寄存器值到 BSS（ISR 在 syscall_dispatch 之前推送了寄存器）
    # ISR 推送顺序：err, eax, ecx, edx, ebx, esi, edi, ebp, ds, es, fs, gs
    # 在 syscall_dispatch 的 push ebp 之后，原始 eax 在 [ebp+48]
    mov     eax, [ebp + 48]             # 原始 eax = 系统调用号
    mov     [syscall_num], eax
    mov     eax, [ebp + 20]             # 原始 ebx = 参数1
    mov     [syscall_ebx], eax
    mov     eax, [ebp + 16]             # 原始 ecx = 参数2
    mov     [syscall_ecx], eax
    mov     eax, [ebp + 12]             # 原始 edx = 参数3
    mov     [syscall_edx], eax

    # 获取系统调用号
    mov     eax, [syscall_num]

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

    # 保存返回值到原始 eax 位置（ISR pop eax 时会恢复）
    mov     [ebp + 48], eax

    jmp     .done

.invalid:
    mov     eax, -1                 # 错误：无效系统调用号
    mov     [ebp + 48], eax

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

    # 获取退出状态码（从原始 ebx）
    mov     ebx, [syscall_ebx]

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
    push    edi

    # 检查 fd 类型
    mov     eax, [syscall_ebx]    # fd
    cmp     eax, FD_STDIN
    je      .read_stdin
    cmp     eax, 3
    jl      .not_supported_read   # fd < 0 或保留的
    cmp     eax, 10
    jge     .not_supported_read   # fd >= 10 无效

    # fd >= 3，验证 FD 是否已分配
    call    _get_fd_type          # eax = type, ebx = file_index
    cmp     eax, FD_TYPE_FREE
    je      .not_supported_read   # FD 未分配
    cmp     eax, FD_TYPE_VFS
    je      .file_read_dispatch
    cmp     eax, FD_TYPE_FAT32
    je      .file_read_dispatch
    jmp     .not_supported_read   # 未知类型

.file_read_dispatch:
    call    _file_read
    jmp     .read_done

.read_stdin:
    # 从串口读取（阻塞）
    mov     ecx, [syscall_edx]      # len
    mov     edi, [syscall_ecx]      # buf
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
    pop     edi
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

    mov     eax, [syscall_ebx]    # fd
    cmp     eax, FD_STDOUT
    je      .do_write
    cmp     eax, FD_STDERR
    je      .do_write

    # 检查是否为文件 fd (>= 3)，验证 FD 是否已分配
    cmp     eax, 3
    jge     .do_file_write_check
    cmp     eax, 10
    jl      .not_supported_write  # 0-2 但不是 stdout/stderr

.do_file_write_check:
    call    _get_fd_type          # eax = type, ebx = file_index
    cmp     eax, FD_TYPE_FREE
    je      .not_supported_write  # FD 未分配
    cmp     eax, FD_TYPE_VFS
    je      .do_file_write
    # FAT32 write not yet implemented, reject other types
    jmp     .not_supported_write

.do_write:
    mov     esi, [syscall_ecx]    # buf
    mov     ecx, [syscall_edx]    # len
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

.not_supported_write:
    mov     eax, -1

.write_done:
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# _file_read: 从文件描述符读取（fd >= 3）
# 输入：syscall_ebx = fd, syscall_ecx = buf, syscall_edx = len
# 输出：eax = 读取字节数 或 -1
# ============================================================================
_file_read:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 获取 FD 表项
    mov     eax, [syscall_ebx]
    call    _get_fd_type          # eax = type, ebx = file_index, ecx = offset
    cmp     eax, FD_TYPE_VFS
    je      .file_read_vfs
    cmp     eax, FD_TYPE_FAT32
    je      .file_read_fat32

    # 不支持的类型
    mov     eax, -1
    jmp     .file_read_done

.file_read_vfs:
    # 从 VFS 文件读取
    mov     eax, ebx              # VFS file index
    call    vfs_read_file         # esi = data ptr, ecx = file size
    cmp     ecx, -1
    je      .file_read_fail

    # 实际读取长度 = min(requested_len, file_size - offset)
    mov     edx, [syscall_edx]    # requested len
    cmp     edx, ecx
    jbe     .vfs_read_len_ok
    mov     edx, ecx              # truncate to file size
.vfs_read_len_ok:
    # 复制数据到用户缓冲区
    mov     edi, [syscall_ecx]    # dest buffer
    # esi already set by vfs_read_file (points to VFS data)
    mov     ecx, edx
    cld
    rep     movsb
    mov     eax, edx              # 返回读取字节数
    jmp     .file_read_done

.file_read_fat32:
    # 从 FAT32 文件读取（简化：读取整个簇）
    mov     eax, ebx              # cluster
    mov     edi, [syscall_ecx]    # buffer
    call    fat32_read_cluster
    test    eax, eax
    jnz     .file_read_fail
    # 返回 SecPerClus * 512 字节（简化）
    movzx   eax, byte ptr [sec_per_clus]
    shl     eax, 9                # * 512
    jmp     .file_read_done

.file_read_fail:
    mov     eax, -1

.file_read_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# _file_write: 向文件描述符写入（fd >= 3）
# 输入：syscall_ebx = fd, syscall_ecx = buf, syscall_edx = len
# 输出：eax = 写入字节数 或 -1
# ============================================================================
_file_write:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 获取 FD 表项
    mov     eax, [syscall_ebx]
    call    _get_fd_type          # eax = type, ebx = file_index, ecx = offset
    cmp     eax, FD_TYPE_VFS
    je      .file_write_vfs

    # 不支持的类型（FAT32 write not yet implemented）
    mov     eax, -1
    jmp     .file_write_done

.file_write_vfs:
    # 写入 VFS 文件
    mov     edi, ebx              # VFS file index
    imul    edi, 64
    add     edi, offset vfs_file_table

    # 获取文件大小
    mov     edx, [edi + 36]       # file size
    cmp     edx, 4096             # VFS_DATA_SIZE
    jae     .vfs_write_full       # 文件已满

    # 计算可用空间
    mov     eax, 4096
    sub     eax, edx              # available space

    # 实际写入长度 = min(requested_len, available_space)
    mov     ecx, [syscall_edx]
    cmp     ecx, eax
    jbe     .vfs_write_len_ok
    mov     ecx, eax              # truncate
.vfs_write_len_ok:
    # 复制数据到 VFS 数据区
    mov     esi, [syscall_ecx]    # source buffer
    mov     eax, ebx              # VFS file index
    imul    eax, 256
    add     eax, offset vfs_file_data
    add     eax, edx              # + current offset
    mov     edi, eax
    mov     eax, ecx              # byte count
    cld
    rep     movsb

    # 更新文件大小
    mov     eax, ebx
    imul    eax, 64
    add     eax, offset vfs_file_table
    mov     edx, [eax + 36]       # old size
    add     edx, ecx              # new size
    mov     [eax + 36], edx

    mov     eax, ecx              # 返回写入字节数
    jmp     .file_write_done

.vfs_write_full:
    mov     eax, -1

.file_write_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# _get_fd_type: 获取文件描述符的类型和参数
# 输入：eax = fd number
# 输出：eax = type, ebx = file_index, ecx = offset
# ============================================================================
_get_fd_type:
    push    edx
    push    esi
    mov     edx, [current_pid]
    imul    edx, PCB_SIZE
    add     edx, offset proc_table
    mov     esi, edx
    mov     edx, eax
    imul    edx, 8
    add     edx, esi
    add     edx, PCB_FD_TABLE
    mov     eax, [edx]               # type
    mov     ebx, [edx + 4]           # file_index
    xor     ecx, ecx                 # offset = 0 (not yet tracked)
    pop     esi
    pop     edx
    ret

# ============================================================================
# sys_open: 打开文件（VFS 或 FAT32）
# 输入：ebx = filename (指针), ecx = flags
# 输出：eax = fd (>= 0) 或 -1（错误）
# ============================================================================
sys_open:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 1. 先在 VFS 中查找文件
    mov     esi, [syscall_ebx]    # filename pointer
    mov     ebx, -1               # parent = root
    call    vfs_find_file         # eax = VFS file index or -1

    cmp     eax, -1
    jne     .vfs_found            # 在 VFS 中找到

    # 2. VFS 未找到，尝试 FAT32
    # 需要将文件名转换为 8.3 格式
    mov     esi, [syscall_ebx]
    call    fat32_get_file_info   # eax = cluster, ecx = size
    cmp     eax, 0xFFFFFFFF
    jne     .fat32_found          # 在 FAT32 中找到

    # 3. 都未找到
    mov     eax, -1
    jmp     .open_done

.vfs_found:
    # 在 VFS 中找到文件，检查是否是文件（不是目录）
    push    eax                   # 保存 VFS index
    mov     ebx, eax
    imul    ebx, 64
    add     ebx, offset vfs_file_table
    cmp     dword ptr [ebx + 32], 1   # VFS_TYPE_FILE = 1
    pop     eax
    jne     .not_a_file

    # 分配 FD
    push    eax                   # VFS file index
    call    _alloc_fd             # eax = fd number
    cmp     eax, -1
    je      .no_fd

    # 设置 FD 表项：type=VFS, file_index
    pop     edx                   # VFS file index
    mov     ecx, eax              # fd number
    call    _set_fd_entry         # ecx=fd, type=FD_TYPE_VFS, file_idx=edx, offset=0

    jmp     .open_done

.fat32_found:
    # 在 FAT32 中找到文件
    push    eax                   # cluster
    call    _alloc_fd             # eax = fd number
    cmp     eax, -1
    je      .fat32_no_fd

    pop     edx                   # cluster
    mov     ecx, eax
    call    _set_fd_entry_fat     # ecx=fd, type=FD_TYPE_FAT32, file_idx=edx, offset=0

    jmp     .open_done

.not_a_file:
    mov     eax, -1
    jmp     .open_done

.no_fd:
    pop     eax                   # 清理 VFS index
    mov     eax, -1
    jmp     .open_done

.fat32_no_fd:
    pop     eax                   # 清理 cluster
    mov     eax, -1

.open_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# sys_close: 关闭文件描述符
# 输入：ebx = fd
# 输出：eax = 0 成功, -1 错误
# ============================================================================
sys_close:
    push    ebp
    mov     ebp, esp

    # 验证 fd (0-2 是标准流，不能关闭)
    mov     eax, [syscall_ebx]
    cmp     eax, 3
    jl      .cant_close           # fd < 3，不能关闭标准流
    cmp     eax, 10
    jge     .invalid_fd           # fd >= 10，无效

    # 清空 FD 表项
    mov     ecx, eax
    call    _clear_fd_entry

    xor     eax, eax              # 返回 0

.close_done:
    pop     ebp
    ret

.cant_close:
    mov     eax, -1
    jmp     .close_done

.invalid_fd:
    mov     eax, -1
    jmp     .close_done

# ============================================================================
# _alloc_fd: 分配一个空闲的文件描述符槽
# 输出：eax = fd number (>= 3) 或 -1（无空闲槽）
# ============================================================================
_alloc_fd:
    push    ecx
    push    edx
    push    esi

    mov     ecx, 8                # 最多 8 个 FD
    mov     edx, 3                # 从 FD 3 开始
    mov     eax, [current_pid]
    imul    eax, PCB_SIZE
    add     eax, offset proc_table
    lea     esi, [eax + PCB_FD_TABLE]

.alloc_fd_loop:
    cmp     edx, 10               # 最大 FD = 9
    jge     .alloc_fd_full
    mov     eax, edx
    imul    eax, 8                # 每项 8 字节
    mov     ecx, [esi + eax]
    cmp     ecx, FD_TYPE_FREE
    je      .alloc_fd_found
    inc     edx
    jmp     .alloc_fd_loop

.alloc_fd_found:
    mov     eax, edx              # 返回 fd number

.alloc_fd_done:
    pop     esi
    pop     edx
    pop     ecx
    ret

.alloc_fd_full:
    mov     eax, -1
    jmp     .alloc_fd_done

# ============================================================================
# _set_fd_entry: 设置 VFS 文件描述符表项
# 输入：ecx = fd number, edx = file_index
# ============================================================================
_set_fd_entry:
    push    eax
    push    ebx
    mov     eax, [current_pid]
    imul    eax, PCB_SIZE
    add     eax, offset proc_table
    mov     ebx, ecx
    imul    ebx, 8
    add     ebx, eax
    add     ebx, PCB_FD_TABLE
    mov     dword ptr [ebx], 4    # FD_TYPE_VFS
    mov     [ebx + 4], edx        # file_index
    mov     dword ptr [ebx + 8], 0  # offset = 0
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _set_fd_entry_fat: 设置 FAT32 文件描述符表项
# 输入：ecx = fd number, edx = cluster
# ============================================================================
_set_fd_entry_fat:
    push    eax
    push    ebx
    mov     eax, [current_pid]
    imul    eax, PCB_SIZE
    add     eax, offset proc_table
    mov     ebx, ecx
    imul    ebx, 8
    add     ebx, eax
    add     ebx, PCB_FD_TABLE
    mov     dword ptr [ebx], 5    # FD_TYPE_FAT32
    mov     [ebx + 4], edx        # cluster
    mov     dword ptr [ebx + 8], 0  # offset = 0
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _clear_fd_entry: 清空文件描述符表项
# 输入：ecx = fd number
# ============================================================================
_clear_fd_entry:
    push    eax
    push    ebx
    mov     eax, [current_pid]
    imul    eax, PCB_SIZE
    add     eax, offset proc_table
    mov     ebx, ecx
    imul    ebx, 8
    add     ebx, eax
    add     ebx, PCB_FD_TABLE
    mov     dword ptr [ebx], 0    # FD_TYPE_FREE
    mov     dword ptr [ebx + 4], 0
    mov     dword ptr [ebx + 8], 0
    pop     ebx
    pop     eax
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
