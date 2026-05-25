.intel_syntax noprefix
# -----------------------------------------------------------------------------
# vfs.asm - 虚拟文件系统（RAM 文件系统）
# -----------------------------------------------------------------------------
# 简单的 RAM 文件系统，支持：
#   - 文件和目录的创建/读取
#   - ls, cat, mkdir, touch 命令
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# VFS 常量定义
# ============================================================================
VFS_MAX_FILES   = 32              # 最大文件数
VFS_MAX_NAME    = 32              # 最大文件名长度
VFS_ENTRY_SIZE  = 64              # 每个文件条目大小
VFS_DATA_SIZE   = 4096            # 每个文件数据区最大 4KB

# 文件类型
VFS_TYPE_DIR    = 0
VFS_TYPE_FILE   = 1

# VFS 条目结构（64 字节/条目）：
#   [0]  name[32]     - 文件名（以 null 结尾）
#   [32] type         - 文件类型（4 字节）
#   [36] size         - 文件大小（4 字节）
#   [40] parent       - 父目录索引（4 字节，根目录为 -1）
#   [44] created      - 创建时间 tick（4 字节）
#   [48] data[16]     - 保留

# ============================================================================
# BSS
# ============================================================================
    .section .bss
    .align  64

    .globl  vfs_file_table
vfs_file_table:
    .space  VFS_MAX_FILES * VFS_ENTRY_SIZE

    .globl  vfs_file_count
vfs_file_count:
    .space  4                   # 当前文件数

    .globl  vfs_current_dir
vfs_current_dir:
    .space  4                   # 当前目录索引（-1 = 根）

# 文件数据区（每个文件 256 字节，最大 32 个文件 = 8KB）
vfs_file_data:
    .space  VFS_MAX_FILES * 256

# ============================================================================
# vfs_init: 初始化虚拟文件系统
# ============================================================================
    .section .text
    .globl  vfs_init
vfs_init:
    push    eax
    push    ecx
    push    edi
    push    esi

    # 清零文件表
    mov     edi, offset vfs_file_table
    mov     ecx, (VFS_MAX_FILES * VFS_ENTRY_SIZE) / 4
    xor     eax, eax
    cld
    rep     stosd

    # 清零文件数据区
    mov     edi, offset vfs_file_data
    mov     ecx, (VFS_MAX_FILES * 256) / 4
    xor     eax, eax
    rep     stosd

    mov     dword ptr [vfs_file_count], 0
    mov     dword ptr [vfs_current_dir], -1  # 根目录

    # 创建根目录
    mov     edi, offset vfs_file_table
    mov     esi, offset root_name
    mov     ecx, 5
    rep     movsb
    mov     dword ptr [edi + 32], VFS_TYPE_DIR    # type = dir
    mov     dword ptr [edi + 36], 0               # size = 0
    mov     dword ptr [edi + 40], -1              # parent = root
    call    get_tick_count
    mov     [edi + 44], eax

    # 创建 /etc 目录
    call    get_tick_count
    mov     [vfs_init_tick], eax
    mov     dword ptr [vfs_file_count], 1
    push    offset etc_name
    push    VFS_TYPE_DIR
    push    -1
    push    0                                     # size
    call    _vfs_create_entry
    add     esp, 16

    # 创建 /etc/version 文件
    push    offset version_content
    push    5                                     # size
    push    VFS_TYPE_FILE
    push    1                                     # parent = /etc (index 1)
    push    offset version_name
    call    _vfs_create_file
    add     esp, 20

    # 创建 /etc/motd 文件
    push    offset motd_content
    push    16                                    # size
    push    VFS_TYPE_FILE
    push    1                                     # parent = /etc
    push    offset motd_name
    call    _vfs_create_file
    add     esp, 20

    # 创建 /bin 目录
    push    offset bin_name
    push    VFS_TYPE_DIR
    push    -1                                    # parent = root
    push    0                                     # size
    call    _vfs_create_entry
    add     esp, 16

    pop     esi
    pop     edi
    pop     ecx
    pop     eax
    ret

# ============================================================================
# _vfs_create_entry: 创建目录条目（内部函数）
# 输入：[esp+16] name_ptr, [esp+12] size, [esp+8] type, [esp+4] parent
# 输出：eax = 条目索引（-1 = 失败）
# ============================================================================
_vfs_create_entry:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    mov     eax, [vfs_file_count]
    cmp     eax, VFS_MAX_FILES
    jge     _vfs_create_full

    # 获取新条目地址
    imul    ebx, eax, VFS_ENTRY_SIZE
    add     ebx, offset vfs_file_table
    mov     edi, ebx              # edi = 新条目地址

    # 复制名称
    mov     esi, [ebp + 16]       # name_ptr
    mov     ecx, VFS_MAX_NAME - 1
    cld
1:  mov     al, [esi]
    test    al, al
    jz      2f
    mov     [edi], al
    inc     esi
    inc     edi
    dec     ecx
    jnz     1b
2:  xor     al, al
    mov     [edi], al             # null 终止

    # 设置属性
    mov     eax, [ebp + 8]        # type
    mov     [ebx + 32], eax
    mov     eax, [ebp + 12]       # size
    mov     [ebx + 36], eax
    mov     eax, [ebp + 4]        # parent
    mov     [ebx + 40], eax

    # 记录创建时间
    call    get_tick_count
    mov     [ebx + 44], eax

    # 增加文件计数
    inc     dword ptr [vfs_file_count]

    # 返回条目索引
    mov     eax, [vfs_file_count]
    dec     eax
    jmp     _vfs_create_done

_vfs_create_full:
    mov     eax, -1

_vfs_create_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# _vfs_create_file: 创建文件条目（内部函数）
# 输入：[esp+20] name_ptr, [esp+16] parent, [esp+12] type, [esp+8] size, [esp+4] data_ptr
# ============================================================================
_vfs_create_file:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    mov     eax, [vfs_file_count]
    cmp     eax, VFS_MAX_FILES
    jge     _vfs_create_full

    # 获取新条目地址
    imul    ebx, eax, VFS_ENTRY_SIZE
    add     ebx, offset vfs_file_table
    mov     edi, ebx              # edi = 新条目地址

    # 复制名称
    mov     esi, [ebp + 20]       # name_ptr
    mov     ecx, VFS_MAX_NAME - 1
    cld
1:  mov     al, [esi]
    test    al, al
    jz      2f
    mov     [edi], al
    inc     esi
    inc     edi
    dec     ecx
    jnz     1b
2:  xor     al, al
    mov     [edi], al             # null 终止

    # 设置属性
    mov     eax, [ebp + 12]       # type
    mov     [ebx + 32], eax
    mov     eax, [ebp + 8]        # size
    mov     [ebx + 36], eax
    mov     eax, [ebp + 16]       # parent
    mov     [ebx + 40], eax

    # 复制数据
    mov     esi, [ebp + 4]        # data_ptr
    mov     ecx, [ebp + 8]        # size
    mov     edx, [vfs_file_count] # 文件索引
    imul    edx, 256
    add     edx, offset vfs_file_data
    cld
    rep     movsb

    # 记录创建时间
    call    get_tick_count
    mov     [ebx + 44], eax

    # 增加文件计数
    inc     dword ptr [vfs_file_count]

    # 返回条目索引
    mov     eax, [vfs_file_count]
    dec     eax

_vfs_file_create_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# ============================================================================
# vfs_list_dir: 列出目录内容
# 输入：ebx = 目录索引（-1 = 根目录）
# 输出：无（直接打印到串口）
# ============================================================================
    .globl  vfs_list_dir
vfs_list_dir:
    push    eax
    push    ecx
    push    edx
    push    esi
    push    edi

    # 获取目标目录索引
    mov     eax, [vfs_current_dir]

    mov     ecx, [vfs_file_count]
    test    ecx, ecx
    jz      vfs_list_empty

    xor     edx, edx              # 遍历索引

vfs_list_loop:
    cmp     edx, ecx
    jge     vfs_list_done

    # 获取条目地址
    mov     eax, edx
    imul    eax, VFS_ENTRY_SIZE
    add     eax, offset vfs_file_table
    mov     esi, eax              # esi = 条目地址

    # 检查父目录是否匹配
    mov     edi, [eax + 40]       # parent
    cmp     edi, ebx              # ebx = 目标目录
    jne     vfs_next_entry

    # 打印名称
    mov     esi, eax              # 条目地址
    push    eax
    push    edx
1:  mov     al, [esi]
    test    al, al
    jz      2f
    cmp     al, ' '
    jb      2f                    # 遇到非打印字符就停止
    push    esi
    call    uart_putc
    pop     esi
    inc     esi
    jmp     1b
2:  pop     edx
    pop     eax

    # 如果是目录，添加 / 后缀
    cmp     dword ptr [eax + 32], VFS_TYPE_DIR
    jne     vfs_not_dir
    mov     al, '/'
    call    uart_putc
vfs_not_dir:

    # 打印空格分隔
    mov     al, ' '
    call    uart_putc

vfs_next_entry:
    inc     edx
    jmp     vfs_list_loop

vfs_list_empty:
    mov     esi, offset vfs_msg_no_files
    call    uart_puts

vfs_list_done:
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     eax
    ret

# ============================================================================
# vfs_find_file: 查找文件
# 输入：esi = 文件名, ebx = 父目录索引（-1 = 根）
# 输出：eax = 文件索引（-1 = 未找到）
# ============================================================================
    .globl  vfs_find_file
vfs_find_file:
    push    ecx
    push    edx
    push    edi
    push    esi

    mov     ecx, [vfs_file_count]
    xor     edx, edx

vfs_find_loop:
    cmp     edx, ecx
    jge     vfs_find_not_found

    # 获取条目
    mov     eax, edx
    imul    eax, VFS_ENTRY_SIZE
    add     eax, offset vfs_file_table

    # 检查父目录
    cmp     [eax + 40], ebx
    jne     vfs_find_next

    # 比较名称
    push    edx
    mov     edi, eax              # 条目名称地址
    call    vfs_strcmp
    test    eax, eax
    jz      vfs_find_found        # 找到了

    pop     edx
vfs_find_next:
    inc     edx
    jmp     vfs_find_loop

vfs_find_found:
    pop     edx
    mov     eax, edx
    jmp     vfs_find_done

vfs_find_not_found:
    mov     eax, -1

vfs_find_done:
    pop     esi
    pop     edi
    pop     edx
    pop     ecx
    ret

# ============================================================================
# vfs_read_file: 读取文件内容
# 输入：eax = 文件索引
# 输出：esi = 内容指针, ecx = 大小（-1 = 失败）
# ============================================================================
    .globl  vfs_read_file
vfs_read_file:
    push    ebx

    # 检查索引合法性
    cmp     eax, [vfs_file_count]
    jae     vfs_read_err

    # 获取条目
    mov     ebx, eax
    imul    ebx, VFS_ENTRY_SIZE
    add     ebx, offset vfs_file_table

    # 检查是否是文件
    cmp     dword ptr [ebx + 32], VFS_TYPE_FILE
    jne     vfs_read_err

    # 计算数据地址
    mov     ecx, [ebx + 36]       # 文件大小
    mov     esi, eax
    imul    esi, 256
    add     esi, offset vfs_file_data
    jmp     vfs_read_ok

vfs_read_err:
    mov     ecx, -1

vfs_read_ok:
    pop     ebx
    ret

# ============================================================================
# vfs_create_file: 创建文件（外部接口）
# 输入：esi = 文件名, ebx = 父目录索引
# 输出：eax = 文件索引（-1 = 失败）
# ============================================================================
    .globl  vfs_create_file_ext
vfs_create_file_ext:
    push    esi
    push    ebx
    push    1                     # type = file
    push    -1                    # parent (will be set below)
    push    0                     # size
    push    esi                   # name
    call    _vfs_create_entry
    add     esp, 20
    pop     ebx
    pop     esi
    ret

# ============================================================================
# vfs_strcmp: 比较条目名称和给定字符串
# 输入：edi = 条目地址, esi = 字符串
# 输出：eax = 0 相等, 1 不等
# ============================================================================
vfs_strcmp:
    push    edi
    push    esi

    mov     edi, [edi]            # 条目名称（前 4 字节，假设短名称）
    # 实际上需要逐字节比较
    mov     edi, [esp + 4]        # 恢复条目地址

1:  mov     al, [edi]
    mov     dl, [esi]
    cmp     al, dl
    jne     vfs_str_ne
    test    al, al
    jz      vfs_str_eq
    inc     edi
    inc     esi
    jmp     1b

vfs_str_eq:
    pop     esi
    pop     edi
    xor     eax, eax
    ret

vfs_str_ne:
    pop     esi
    pop     edi
    mov     eax, 1
    ret

    .section .rodata
root_name:
    .asciz  "/"
etc_name:
    .asciz  "etc"
bin_name:
    .asciz  "bin"
version_name:
    .asciz  "version"
version_content:
    .asciz  "v0.4\n"
motd_name:
    .asciz  "motd"
motd_content:
    .asciz  "Welcome to AI-ASM\n"

    .section .bss
vfs_init_tick:
    .space  4

    .section .rodata
vfs_msg_no_files:
    .asciz  "(empty)"
