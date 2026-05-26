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
# BSS (only small variables)
# ============================================================================
    .section .bss

    .globl  vfs_file_count
vfs_file_count:
    .space  4

    .globl  vfs_current_dir
vfs_current_dir:
    .space  4

path_temp:
    .space  VFS_MAX_NAME

# ============================================================================
# VFS 文件表放在 .data 段（保证被正确加载且可写）
# ============================================================================
    .section .data, "aw", @progbits
    .align  64

    .globl  vfs_file_table
vfs_file_table:
    # Entry 0: root "/"
    .ascii  "/"
    .space  31, 0
    .long   VFS_TYPE_DIR
    .long   0
    .long   -1
    .long   0
    .space  16, 0
    # Entry 1: "etc" dir
    .ascii  "etc"
    .space  29, 0
    .long   VFS_TYPE_DIR
    .long   0
    .long   -1
    .long   0
    .space  16, 0
    # Entry 2: "version" file
    .ascii  "version"
    .space  25, 0
    .long   VFS_TYPE_FILE
    .long   5
    .long   1
    .long   0
    .space  16, 0
    # Entry 3: "motd" file
    .ascii  "motd"
    .space  28, 0
    .long   VFS_TYPE_FILE
    .long   18
    .long   1
    .long   0
    .space  16, 0
    # Entry 4: "bin" dir
    .ascii  "bin"
    .space  29, 0
    .long   VFS_TYPE_DIR
    .long   0
    .long   -1
    .long   0
    .space  16, 0
    # Entry 5-31: zeros
    .space  27 * VFS_ENTRY_SIZE

# 文件数据区也在 .data 段
vfs_file_data:
    .space  256                   # entry 0 (root): no data
    .space  256                   # entry 1 (etc): no data
    .ascii  "v0.4\n"              # entry 2 (version)
    .space  251
    .ascii  "Welcome to AI-ASM\n" # entry 3 (motd)
    .space  238
    .space  256                   # entry 4 (bin): no data
    .space  27 * 256              # remaining entries

# ============================================================================
# vfs_init: 设置运行时状态
# ============================================================================
    .section .text
    .globl  vfs_init
vfs_init:
    # 数据已在 .text 中预填充，只需设置运行时变量
    mov     dword ptr [vfs_current_dir], -1
    mov     dword ptr [vfs_file_count], 5
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
    mov     eax, [ebp + 12]       # type
    mov     [ebx + 32], eax
    mov     eax, [ebp + 8]        # size
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
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    mov     eax, offset vfs_file_table

vfs_list_loop:
    # 检查名称首字节，null = 未使用条目（终止）
    cmp     byte ptr [eax], 0
    jz      vfs_list_done

    mov     edx, eax              # 保存条目基地址

    # 跳过根目录条目（名称为 "/"）
    cmp     byte ptr [eax], '/'
    je      .vfs_skip

    # 检查父目录
    mov     edi, [eax + 40]       # parent
    cmp     edi, ebx
    jne     .vfs_skip

    # 打印名称
    mov     esi, eax
.vfs_print:
    lodsb
    test    al, al
    jz      .vfs_end_name
    cmp     al, ' '
    jb      .vfs_end_name
    push    eax
    push    esi
    call    uart_putc
    pop     esi
    pop     eax
    jmp     .vfs_print
.vfs_end_name:

    # 目录加 / 后缀
    cmp     dword ptr [edx + 32], VFS_TYPE_DIR
    jne     .vfs_not_dir
    mov     al, '/'
    call    uart_putc
.vfs_not_dir:
    mov     al, ' '
    call    uart_putc

.vfs_skip:
    mov     eax, edx              # 恢复条目基地址（被 lodsb 破坏）
    add     eax, VFS_ENTRY_SIZE
    jmp     vfs_list_loop

vfs_list_done:
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc

    pop     edi
    pop     esi
    pop     edx
    pop     ebx
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
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    edi

    mov     ecx, [vfs_file_count]
    xor     ebp, ebp              # ebp = entry index

vfs_find_loop:
    cmp     ebp, ecx
    jge     vfs_find_not_found

    # Get entry address: edx = ebp * 64 + vfs_file_table
    mov     edx, ebp
    imul    edx, VFS_ENTRY_SIZE
    add     edx, offset vfs_file_table

    # Check parent directory
    cmp     dword ptr [edx + 40], ebx
    jne     vfs_find_next

    # Parent matches — compare name
    # Inline strcmp: esi = search string, edx = entry address
    push    esi                   # save search string pointer
    push    edx                   # save entry address
    push    ecx                   # save file count

    mov     edi, edx              # entry name address

1:  mov     al, [edi]
    mov     dl, [esi]
    cmp     al, dl
    jne     2f                    # mismatch
    test    al, al
    jz      3f                    # both null = match
    inc     edi
    inc     esi
    jmp     1b

2:  # No match — restore and try next entry
    pop     ecx
    pop     edx
    pop     esi
    jmp     vfs_find_next

3:  # Match found
    pop     ecx
    pop     edx
    pop     esi
    mov     eax, ebp
    jmp     vfs_find_done

vfs_find_next:
    inc     ebp
    jmp     vfs_find_loop

vfs_find_not_found:
    mov     eax, -1

vfs_find_done:
    pop     edi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
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
# vfs_create_file_ext: 创建文件（外部接口）
# 输入：esi = 文件名, ebx = 父目录索引
# 输出：eax = 文件索引（-1 = 失败）
# ============================================================================
    .globl  vfs_create_file_ext
vfs_create_file_ext:
    push    ebp
    mov     ebp, esp
    push    esi
    push    ebx

    push    0                     # parent
    push    0                     # size
    push    1                     # type = file
    push    esi                   # name
    call    _vfs_create_entry
    add     esp, 16

    pop     ebx
    pop     esi
    pop     ebp
    ret

# ============================================================================
# vfs_strcmp: 比较条目名称和给定字符串
# 输入：edi = 条目地址（名称在偏移0）, esi = 字符串
# 输出：eax = 0 相等, 1 不等
# ============================================================================
vfs_strcmp:
    push    edi
    push    esi
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

# ============================================================================
# vfs_find_by_path: 通过完整路径查找文件（支持绝对路径）
# 输入：esi = 路径字符串（如 "/etc/version" 或 "version"）
# 输出：eax = 文件索引（-1 = 未找到）
# ============================================================================
    .globl  vfs_find_by_path
vfs_find_by_path:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    mov     al, [esi]
    cmp     al, '/'
    jne     .find_relative         # 相对路径：在当前目录查找

    # 绝对路径：从根目录开始逐层解析
    inc     esi                    # 跳过开头的 '/'
    mov     ebx, -1                # ebx = 当前目录（-1 = 根）

.find_next:
    cmp     byte ptr [esi], 0
    je      .find_done             # 路径结束，返回最后的目录
    mov     edi, offset path_temp
    mov     ecx, VFS_MAX_NAME - 1

.find_copy:
    mov     al, [esi]
    cmp     al, 0
    je      .find_end_component
    cmp     al, '/'
    je      .find_end_component
    mov     [edi], al
    inc     esi
    inc     edi
    dec     ecx
    jnz     .find_copy
.find_end_component:
    xor     al, al
    mov     [edi], al             # null 终止
    cmp     byte ptr [esi], '/'
    je      .find_skip
    jmp     .find_last
.find_skip:
    inc     esi                    # 跳过 '/' 分隔符
    push    esi                    # save esi (points past '/')

    # 在当前目录查找该分量
    mov     esi, offset path_temp  # name = path_temp
    call    vfs_find_file          # eax = found index or -1

    pop     esi                    # restore esi

    cmp     eax, -1
    je      .find_not_found

    # 检查是否为目录
    mov     ebx, eax
    imul    eax, VFS_ENTRY_SIZE
    add     eax, offset vfs_file_table
    cmp     dword ptr [eax + 32], VFS_TYPE_FILE
    je      .find_not_found         # 是文件不是目录，路径解析失败
    jmp     .find_next

.find_last:
    mov     esi, offset path_temp   # name = path_temp
    jmp     .find_by_name

.find_relative:
    mov     ebx, -1
    jmp     .find_by_name

.find_by_name:
    # esi = 名称, ebx = 父目录
    call    vfs_find_file
    jmp     .find_done

.find_not_found:
    mov     eax, -1

.find_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
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
