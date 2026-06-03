.intel_syntax noprefix
# -----------------------------------------------------------------------------
# wasm_parser.asm - WASM 字节码解析器
# -----------------------------------------------------------------------------
# 解析 WASM 模块结构：
#   - 魔数：0x00 0x61 0x73 0x6D ("\0asm")
#   - 版本：0x01 0x00 0x00 0x00 (version 1)
#   - Sections: type(1), import(2), function(3), table(4), memory(5),
#               global(6), export(7), start(8), element(9), code(10), data(11)
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# WASM 常量定义
# ============================================================================
WASM_MAGIC      = 0x6D736100  # "\0asm" little-endian
WASM_VERSION    = 0x00000001  # version 1

# Section IDs
SEC_TYPE        = 1
SEC_IMPORT      = 2
SEC_FUNCTION    = 3
SEC_TABLE       = 4
SEC_MEMORY      = 5
SEC_GLOBAL      = 6
SEC_EXPORT      = 7
SEC_START       = 8
SEC_ELEMENT     = 9
SEC_CODE        = 10
SEC_DATA        = 11

# Value types
VALTYPE_I32     = 0x7F
VALTYPE_I64     = 0x7E
VALTYPE_F32     = 0x7D
VALTYPE_F64     = 0x7C
VALTYPE_FUNCREF = 0x70
VALTYPE_EXTERNREF = 0x6F

# Import/Export kinds
KIND_FUNC       = 0
KIND_TABLE      = 1
KIND_MEMORY     = 2
KIND_GLOBAL     = 3

# ============================================================================
# WASM 模块结构（BSS）
# ============================================================================
    .section .bss
    .align  16

    # WASM 模块信息
    .globl  wasm_module_ptr
wasm_module_ptr:
    .space  4                   # 模块数据指针

    .globl  wasm_module_size
wasm_module_size:
    .space  4                   # 模块大小

    # 类型段信息
    .globl  wasm_type_count
wasm_type_count:
    .space  4                   # 函数类型数量

    .globl  wasm_type_table
wasm_type_table:
    .space  256                 # 类型表（最多64个类型）

    # 函数段信息
    .globl  wasm_func_count
wasm_func_count:
    .space  4                   # 函数数量

    .globl  wasm_func_table
wasm_func_table:
    .space  256                 # 函数表（最多64个函数索引）

    # 导出段信息
    .globl  wasm_export_count
wasm_export_count:
    .space  4                   # 导出数量

    .globl  wasm_export_table
wasm_export_table:
    .space  512                 # 导出表（最多32个导出）

    # 代码段信息
    .globl  wasm_code_count
wasm_code_count:
    .space  4                   # 代码段数量

    .globl  wasm_code_table
wasm_code_table:
    .space  1024                # 代码表（最多16个代码体指针）

    # 数据段信息
    .globl  wasm_data_count
wasm_data_count:
    .space  4                   # 数据段数量

    .globl  wasm_data_table
wasm_data_table:
    .space  256                 # 数据段表（最多16个：ptr+offset+size）

    # 内存段信息
    .globl  wasm_memory_count
wasm_memory_count:
    .space  4                   # 内存数量

    .globl  wasm_memory_min
wasm_memory_min:
    .space  4                   # 最小页数

    .globl  wasm_memory_max
wasm_memory_max:
    .space  4                   # 最大页数（0表示无限制）

    # Table 段信息（用于 call_indirect）
    .globl  wasm_table_count
wasm_table_count:
    .space  4                   # 表数量

    .globl  wasm_table_size
wasm_table_size:
    .space  4                   # 表大小（元素数量）

    # Element 段信息（表初始化）
    .globl  wasm_elem_count
wasm_elem_count:
    .space  4                   # 元素段数量

    .globl  wasm_table_entries
wasm_table_entries:
    .space  256                 # 表条目（最多64个函数索引，每个4字节）

    # Global 段信息（全局变量）
    .globl  wasm_global_count
wasm_global_count:
    .space  4                   # 全局变量数量

    # 类型签名存储（用于 call_indirect 全签名比较）
    .globl  wasm_type_sigs
wasm_type_sigs:
    .space  256                 # 类型签名字节（最多64个类型，每个最多4字节：param_cnt + 1 param + ret_cnt + 1 ret）

    # 解析状态
    .globl  wasm_parse_error
wasm_parse_error:
    .space  4                   # 解析错误码

    .globl  wasm_parse_pos
wasm_parse_pos:
    .space  4                   # 当前解析位置

    # 解析结果
    .globl  wasm_parsed
wasm_parsed:
    .space  1                   # 是否已解析

# ============================================================================
# wasm_parser_init: 初始化解析器
# ============================================================================
    .section .text
    .globl  wasm_parser_init
wasm_parser_init:
    push    eax
    push    edi

    # 清零所有 BSS 变量
    mov     edi, offset wasm_module_ptr
    mov     ecx, (wasm_parsed - wasm_module_ptr + 1) / 4
    xor     eax, eax
    cld
    rep     stosd

    mov     byte ptr [wasm_parsed], 0

    pop     edi
    pop     eax
    ret

# ============================================================================
# wasm_parse_module: 解析 WASM 模块
# 输入：esi = 模块数据指针, ecx = 模块大小
# 输出：eax = 0（成功）或错误码
# ============================================================================
    .globl  wasm_parse_module
wasm_parse_module:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 保存模块指针和大小
    mov     [wasm_module_ptr], esi
    mov     [wasm_module_size], ecx
    mov     dword ptr [wasm_parse_pos], 0
    mov     dword ptr [wasm_parse_error], 0

    # 1. 检查最小大小（魔数 + 版本 = 8字节）
    cmp     ecx, 8
    jl      parse_err_size

    # 2. 检查魔数
    mov     eax, [esi]
    cmp     eax, WASM_MAGIC
    jne     parse_err_magic

    # 3. 检查版本
    mov     eax, [esi + 4]
    cmp     eax, WASM_VERSION
    jne     parse_err_version

    # 4. 跳过魔数和版本
    add     dword ptr [wasm_parse_pos], 8

    # 5. 解析各 section
parse_sections_loop:
    mov     esi, [wasm_module_ptr]
    add     esi, [wasm_parse_pos]
    mov     ecx, [wasm_module_size]
    sub     ecx, [wasm_parse_pos]

    # 检查是否到达末尾
    test    ecx, ecx
    jz      parse_done_ok

    # 解析 section header
    call    _parse_section_header
    test    eax, eax
    jnz     parse_error_exit

    jmp     parse_sections_loop

parse_done_ok:
    mov     byte ptr [wasm_parsed], 1
    xor     eax, eax
    jmp     parse_module_done

parse_error_exit:
    mov     eax, [wasm_parse_error]
    jmp     parse_module_done

parse_err_size:
    mov     dword ptr [wasm_parse_error], 1
    mov     eax, 1
    jmp     parse_module_done

parse_err_magic:
    mov     dword ptr [wasm_parse_error], 2
    mov     eax, 2
    jmp     parse_module_done

parse_err_version:
    mov     dword ptr [wasm_parse_error], 3
    mov     eax, 3
    jmp     parse_module_done

parse_module_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# _parse_section_header: 解析 section header
# 输入：esi = 当前位置, ecx = 剩余大小
# 输出：eax = 0（成功）或错误码
# ============================================================================
_parse_section_header:
    push    ebx
    push    ecx
    push    edx

    # 检查是否有足够字节（section id + size）
    cmp     ecx, 2
    jl      section_err_size

    # 读取 section id
    movzx   ebx, byte ptr [esi]
    inc     esi
    dec     ecx

    # 读取 section size (LEB128 编码)
    call    _read_leb128_u32
    test    eax, eax
    js      section_err_leb128
    mov     edx, eax              # edx = section size

    # 检查剩余大小是否足够
    cmp     ecx, edx
    jl      section_err_data

    # 根据 section id 分发处理
    cmp     ebx, SEC_TYPE
    je      handle_type_sec
    cmp     ebx, SEC_IMPORT
    je      handle_import_sec
    cmp     ebx, SEC_FUNCTION
    je      handle_function_sec
    cmp     ebx, SEC_MEMORY
    je      handle_memory_sec
    cmp     ebx, SEC_EXPORT
    je      handle_export_sec
    cmp     ebx, SEC_CODE
    je      handle_code_sec
    cmp     ebx, SEC_DATA
    je      handle_data_sec
    cmp     ebx, SEC_TABLE
    je      handle_table_sec
    cmp     ebx, SEC_ELEMENT
    je      handle_element_sec
    cmp     ebx, SEC_GLOBAL
    je      handle_global_sec

    # 未处理的 section，跳过
    jmp     skip_section

handle_type_sec:
    call    _parse_type_section
    jmp     section_done_ok

handle_import_sec:
    # 暂时跳过 import section
    jmp     skip_section

handle_function_sec:
    call    _parse_function_section
    jmp     section_done_ok

handle_memory_sec:
    call    _parse_memory_section
    jmp     section_done_ok

handle_export_sec:
    call    _parse_export_section
    jmp     section_done_ok

handle_code_sec:
    call    _parse_code_section
    jmp     section_done_ok

handle_data_sec:
    call    _parse_data_section
    jmp     section_done_ok

handle_table_sec:
    call    _parse_table_section
    jmp     section_done_ok

handle_element_sec:
    call    _parse_element_section
    jmp     section_done_ok

handle_global_sec:
    call    _parse_global_section
    jmp     section_done_ok

skip_section:
    # 跳过 section 内容
    add     esi, edx
    jmp     section_done_ok

section_done_ok:
    # 更新解析位置
    mov     eax, esi
    sub     eax, [wasm_module_ptr]
    mov     [wasm_parse_pos], eax

    xor     eax, eax
    jmp     section_header_done

section_err_size:
    mov     eax, 4
    jmp     section_header_done

section_err_leb128:
    mov     eax, 5
    jmp     section_header_done

section_err_data:
    mov     eax, 6
    jmp     section_header_done

section_header_done:
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# _parse_type_section: 解析 type section
# 输入：esi = section 内容, edx = section 大小
# ============================================================================
_parse_type_section:
    push    eax
    push    ebx
    push    ecx
    push    edi
    push    ebp               # save ebp (callee-saved)

    # 读取类型数量
    call    _read_leb128_u32
    mov     [wasm_type_count], eax
    mov     ecx, eax              # ecx = 类型数量

    # edi = 类型表指针 (param_count, result_count)
    mov     edi, offset wasm_type_table
    # ebp = 类型签名存储指针
    mov     ebp, offset wasm_type_sigs

type_entry_loop:
    test    ecx, ecx
    jz      type_section_done

    # 读取 func type magic (0x60)
    movzx   ebx, byte ptr [esi]
    cmp     ebx, 0x60
    jne     type_err_magic
    inc     esi

    # 读取参数数量
    call    _read_leb128_u32
    mov     [edi], eax            # 存储参数数量
    mov     edx, eax              # edx = param_count

    # 存储 param_count 到签名区（1字节）
    mov     [ebp], edx

    # 读取并存储参数类型（最多存第一个）
    mov     ebx, eax
    test    ebx, ebx
    jz      read_results_cnt
    # 存储第一个参数类型
    movzx   eax, byte ptr [esi]
    mov     [ebp + 1], al
    inc     esi
    dec     ebx
skip_params_loop:
    test    ebx, ebx
    jz      read_results_cnt
    inc     esi
    dec     ebx
    jmp     skip_params_loop

read_results_cnt:
    # 读取结果数量
    call    _read_leb128_u32
    mov     [edi + 4], eax        # 存储结果数量
    mov     edx, eax              # edx = result_count

    # 存储 result_count 到签名区
    mov     [ebp + 2], edx

    # 读取并存储结果类型（最多存第一个）
    mov     ebx, eax
    test    ebx, ebx
    jz      next_type_entry
    # 存储第一个结果类型
    movzx   eax, byte ptr [esi]
    mov     [ebp + 3], al
    inc     esi
    dec     ebx
skip_results_loop:
    test    ebx, ebx
    jz      next_type_entry
    inc     esi
    dec     ebx
    jmp     skip_results_loop

next_type_entry:
    add     edi, 8                # 每个类型条目 8 字节
    add     ebp, 4                # 每个签名 4 字节
    dec     ecx
    jmp     type_entry_loop

type_section_done:
    xor     eax, eax
    jmp     type_section_ret

type_err_magic:
    mov     eax, 7
    jmp     type_section_ret

type_section_ret:
    pop     ebp
    pop     edi
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _parse_function_section: 解析 function section
# 输入：esi = section 内容, edx = section 大小
# ============================================================================
_parse_function_section:
    push    eax
    push    ecx
    push    edi

    # 读取函数数量
    call    _read_leb128_u32
    mov     [wasm_func_count], eax
    mov     ecx, eax

    # edi = 函数表指针
    mov     edi, offset wasm_func_table

func_entry_loop:
    test    ecx, ecx
    jz      func_section_done

    # 读取类型索引
    call    _read_leb128_u32
    mov     [edi], eax
    add     edi, 4

    dec     ecx
    jmp     func_entry_loop

func_section_done:
    xor     eax, eax
    pop     edi
    pop     ecx
    pop     eax
    ret

# ============================================================================
# _parse_memory_section: 解析 memory section
# 输入：esi = section 内容, edx = section 大小
# ============================================================================
_parse_memory_section:
    push    eax
    push    ebx

    # 读取内存数量
    call    _read_leb128_u32
    mov     [wasm_memory_count], eax

    # 检查是否只有一个内存
    cmp     eax, 1
    jne     memory_section_done

    # 读取 flags（是否有最大值）
    movzx   ebx, byte ptr [esi]
    inc     esi

    # 读取最小页数
    call    _read_leb128_u32
    mov     [wasm_memory_min], eax

    # 如果 flags & 1，读取最大页数
    test    ebx, 1
    jz      no_memory_max

    call    _read_leb128_u32
    mov     [wasm_memory_max], eax
    jmp     memory_section_done

no_memory_max:
    mov     dword ptr [wasm_memory_max], 0

memory_section_done:
    xor     eax, eax
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _parse_data_section: 解析 data section
# 输入：esi = section 内容, edx = section 大小
# ============================================================================
_parse_data_section:
    push    eax
    push    ebx
    push    ecx
    push    edi

    # 读取数据段数量
    call    _read_leb128_u32
    mov     [wasm_data_count], eax
    mov     ecx, eax

    # edi = 数据段表指针
    mov     edi, offset wasm_data_table

data_entry_loop:
    test    ecx, ecx
    jz      data_section_done

    # 读取 flags
    movzx   ebx, byte ptr [esi]
    inc     esi

    # 读取 offset 表达式：i32.const N, end
    cmp     byte ptr [esi], 0x41    # i32.const
    jne     data_err_format
    inc     esi
    call    _read_leb128_u32
    mov     [edi], eax              # 存储偏移
    add     edi, 4

    # 跳过 end (0x0B)
    cmp     byte ptr [esi], 0x0B
    jne     data_err_format
    inc     esi

    # 读取数据大小
    call    _read_leb128_u32
    mov     ebx, eax                # ebx = 数据大小
    mov     [edi], ebx              # 存储大小
    add     edi, 4

    # 存储数据指针
    mov     [edi], esi
    add     edi, 4

    # 跳过数据内容
    add     esi, ebx

    dec     ecx
    jmp     data_entry_loop

data_section_done:
    xor     eax, eax
    pop     edi
    pop     ecx
    pop     ebx
    pop     eax
    ret

data_err_format:
    mov     eax, 8                  # 错误码：data section 格式错误
    pop     edi
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _parse_export_section: 解析 export section
# 输入：esi = section 内容, edx = section 大小
# ============================================================================
_parse_export_section:
    push    eax
    push    ebx
    push    ecx
    push    edi

    # 读取导出数量
    call    _read_leb128_u32
    mov     [wasm_export_count], eax
    mov     ecx, eax

    # edi = 导出表指针
    mov     edi, offset wasm_export_table

export_entry_loop:
    test    ecx, ecx
    jz      export_section_done

    # 读取名称长度
    call    _read_leb128_u32
    mov     ebx, eax

    # 存储名称指针和长度
    mov     [edi], esi            # 名称指针
    add     edi, 4
    mov     [edi], ebx            # 名称长度
    add     edi, 4

    # 跳过名称
    add     esi, ebx

    # 读取 kind
    movzx   eax, byte ptr [esi]
    inc     esi
    mov     [edi], eax
    add     edi, 4

    # 读取索引
    call    _read_leb128_u32
    mov     [edi], eax
    add     edi, 4

    dec     ecx
    jmp     export_entry_loop

export_section_done:
    xor     eax, eax
    pop     edi
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _parse_code_section: 解析 code section
# 输入：esi = section 内容, edx = section 大小
# ============================================================================
_parse_code_section:
    push    eax
    push    ebx
    push    ecx
    push    edi

    # 读取代码数量
    call    _read_leb128_u32
    mov     [wasm_code_count], eax
    mov     ecx, eax

    # edi = 代码表指针
    mov     edi, offset wasm_code_table

code_entry_loop:
    test    ecx, ecx
    jz      code_section_done

    # 读取代码体大小
    call    _read_leb128_u32
    mov     ebx, eax              # ebx = 代码体大小

    # 存储代码体指针和大小
    mov     [edi], esi            # 代码体指针
    add     edi, 4
    mov     [edi], ebx            # 代码体大小
    add     edi, 4

    # 跳过代码体（暂不解析内部结构）
    add     esi, ebx

    dec     ecx
    jmp     code_entry_loop

code_section_done:
    xor     eax, eax
    pop     edi
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _read_leb128_u32: 读取 LEB128 无符号 32 位整数
# 输入：esi = 数据指针
# 输出：eax = 整数值, esi 更新
# ============================================================================
_read_leb128_u32:
    push    ebx
    push    ecx

    xor     eax, eax              # 结果
    xor     ebx, ebx              # shift count
    mov     ecx, 5                # 最多 5 字节

read_leb128_byte:
    movzx   edx, byte ptr [esi]
    inc     esi

    # 提取低 7 位
    and     edx, 0x7F

    # 组合到结果 (shift edx by ebx bits)
    push    ecx
    mov     ecx, ebx
    shl     edx, cl
    pop     ecx
    or      eax, edx

    # 检查继续位
    movzx   edx, byte ptr [esi - 1]
    test    edx, 0x80
    jz      read_leb128_done

    add     ebx, 7
    dec     ecx
    jnz     read_leb128_byte

    # 超过 5 字节，错误
    mov     eax, -1

read_leb128_done:
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# _parse_table_section: 解析 table section
# 输入：esi = section 内容, edx = section 大小
# ============================================================================
_parse_table_section:
    push    eax
    push    ebx

    # 读取表数量
    call    _read_leb128_u32
    mov     [wasm_table_count], eax

    # 检查是否只有一个表
    cmp     eax, 1
    jne     table_section_done

    # 读取元素类型 (0x70 = funcref)
    movzx   ebx, byte ptr [esi]
    inc     esi

    # 读取 limits: flags + min
    movzx   ebx, byte ptr [esi]
    inc     esi

    # 读取最小大小
    call    _read_leb128_u32
    mov     [wasm_table_size], eax

    # 如果 flags & 1，读取最大值（忽略）
    test    ebx, 1
    jz      table_section_done
    call    _read_leb128_u32

table_section_done:
    xor     eax, eax
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _parse_element_section: 解析 element section
# 输入：esi = section 内容, edx = section 大小
# ============================================================================
_parse_element_section:
    push    eax
    push    ebx
    push    ecx
    push    edi

    # 读取元素段数量
    call    _read_leb128_u32
    mov     [wasm_elem_count], eax
    mov     ecx, eax

    # edi = 表条目指针
    mov     edi, offset wasm_table_entries

element_entry_loop:
    test    ecx, ecx
    jz      element_section_done

    # 读取 table index（应为 0）
    call    _read_leb128_u32

    # 读取 offset 表达式：i32.const N, end
    cmp     byte ptr [esi], 0x41    # i32.const
    jne     element_skip
    inc     esi
    call    _read_leb128_u32        # 基址偏移（存储到 edi）
    push    eax                     # 保存基址偏移

    # 跳过 end (0x0B)
    cmp     byte ptr [esi], 0x0B
    jne     element_skip_end
    inc     esi

    # 读取元素数量
    call    _read_leb128_u32
    mov     ebx, eax                # ebx = 函数索引数量

    # 读取函数索引并填入表
    pop     edx                     # edx = 基址偏移
element_fill_loop:
    test    ebx, ebx
    jz      element_next

    call    _read_leb128_u32        # eax = 函数索引

    # 计算存储位置：wasm_table_entries + (edx + ebx-1) * 4
    push    ebx
    mov     ebx, edx
    add     ebx, [esp + 4]          # 偏移 + 当前索引
    dec     ebx                     # 从 0 开始
    shl     ebx, 2                  # * 4
    mov     [edi + ebx], eax        # 存储函数索引
    pop     ebx

    dec     ebx
    jmp     element_fill_loop

element_next:
    dec     ecx
    jmp     element_entry_loop

element_skip:
    pop     eax                     # 清理栈
element_skip_end:
    # 简化：跳过无法解析的元素段
    dec     ecx
    jmp     element_entry_loop

element_section_done:
    xor     eax, eax
    pop     edi
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# _parse_global_section: 解析 global section
# 输入：esi = section 内容, edx = section 大小
# Global 格式: count, (type, mut, init_expr)*
# type: i32=0x7F, i64=0x7E, f32=0x7D, f64=0x7C
# mut: 0=immutable, 1=mutable
# init_expr: i32.const value, end (or other const expr)
# ============================================================================
_parse_global_section:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    edi

    # 读取全局变量数量
    call    _read_leb128_u32
    mov     [wasm_global_count], eax
    mov     ecx, eax              # ecx = 循环计数器

    # edi = 全局变量存储指针
    mov     edi, offset wasm_globals

global_entry_loop:
    test    ecx, ecx
    jz      global_section_done

    # 读取全局变量类型 (i32=0x7F, i64=0x7E, f32=0x7D, f64=0x7C)
    movzx   eax, byte ptr [esi]
    inc     esi

    # 读取可变性 (0=immutable, 1=mutable)
    movzx   ebx, byte ptr [esi]
    inc     esi

    # 解析初始化表达式
    # 期望: i32.const value, end (opcode 0x41, leb128, 0x0B)
    cmp     byte ptr [esi], 0x41  # i32.const
    jne     global_init_skip

    inc     esi
    call    _read_leb128_u32      # 读取初始值
    mov     [edi], eax            # 存储初始值到 wasm_globals

    # 跳过 end (0x0B)
    cmp     byte ptr [esi], 0x0B
    jne     global_next
    inc     esi

global_next:
    add     edi, 4                # 移动到下一个全局变量槽
    dec     ecx
    jmp     global_entry_loop

global_init_skip:
    # 跳过不支持的初始化表达式
    add     edi, 4
    dec     ecx
    jmp     global_entry_loop

global_section_done:
    xor     eax, eax
    pop     edi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# wasm_get_export_func: 查找导出函数
# 输入：esi = 函数名, ecx = 函数名长度
# 输出：eax = 函数索引（找到）或 -1（未找到）
# ============================================================================
    .globl  wasm_get_export_func
wasm_get_export_func:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    mov     edx, ecx              # edx = 函数名长度
    mov     edi, offset wasm_export_table
    mov     ecx, [wasm_export_count]

search_export_loop:
    test    ecx, ecx
    jz      export_not_found

    # 检查 kind 是否为函数
    mov     eax, [edi + 8]
    cmp     eax, KIND_FUNC
    jne     next_export_entry

    # 检查名称长度
    mov     ebx, [edi + 4]
    cmp     ebx, edx
    jne     next_export_entry

    # 比较名称
    push    ecx
    push    esi
    push    edi

    mov     esi, [edi]            # 导出名称
    mov     edi, [esp + 8]        # 恢复原始 esi（但栈已变化，需要调整）

compare_name_loop:
    test    ebx, ebx
    jz      export_name_match

    mov     al, [esi]
    mov     ah, [edi + 16]        # 原始参数 esi 在栈中
    cmp     al, ah
    jne     export_name_mismatch

    inc     esi
    inc     edi
    dec     ebx
    jmp     compare_name_loop

export_name_match:
    pop     edi
    pop     esi
    pop     ecx

    # 返回函数索引
    mov     eax, [edi + 12]
    jmp     get_export_func_done

export_name_mismatch:
    pop     edi
    pop     esi
    pop     ecx

next_export_entry:
    add     edi, 16               # 每个导出条目 16 字节
    dec     ecx
    jmp     search_export_loop

export_not_found:
    mov     eax, -1

get_export_func_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# wasm_type_sig_match: 比较两个类型签名是否匹配
# 输入：eax = 期望的 type_index, ebx = 实际的 type_index
# 输出：eax = 0 (匹配), 1 (不匹配)
# 签名格式 (wasm_type_sigs + type_index * 4):
#   [0] = param_count, [1] = first_param_type, [2] = result_count, [3] = first_result_type
# ============================================================================
    .globl  wasm_type_sig_match
wasm_type_sig_match:
    push    ecx
    push    edx
    push    esi
    push    edi

    # 计算签名指针
    mov     ecx, eax              # ecx = expected type_index
    mov     edx, ebx              # edx = actual type_index
    shl     ecx, 2                # * 4
    shl     edx, 2                # * 4
    lea     esi, [wasm_type_sigs + ecx]   # esi = expected sig
    lea     edi, [wasm_type_sigs + edx]   # edi = actual sig

    # 比较 4 字节签名
    mov     eax, [esi]
    cmp     eax, [edi]
    jne     .sig_mismatch

    # 匹配
    xor     eax, eax
    jmp     .sig_match_done

.sig_mismatch:
    mov     eax, 1

.sig_match_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    ret

# ============================================================================
# wasm_print_info: 打印 WASM 模块信息
# ============================================================================
    .globl  wasm_print_info
wasm_print_info:
    push    eax
    push    ebx
    push    edi
    push    esi

    mov     esi, offset msg_wasm_ok
    call    uart_puts

    mov     eax, [wasm_type_count]
    mov     edi, offset _print_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     esi, offset msg_wasm_funcs
    call    uart_puts

    mov     eax, [wasm_func_count]
    mov     edi, offset _print_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     esi, offset msg_wasm_code
    call    uart_puts

    mov     eax, [wasm_code_count]
    mov     edi, offset _print_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts

    mov     esi, offset newline_str
    call    uart_puts

    pop     esi
    pop     edi
    pop     ebx
    pop     eax
    ret

    .section .bss
_print_buf:
    .space  16

    .section .rodata
msg_wasm_ok:
    .asciz  "WASM module parsed OK\r\n  types: "
msg_wasm_funcs:
    .asciz  ", funcs: "
msg_wasm_code:
    .asciz  ", code bodies: "
newline_str:
    .asciz  "\r\n"
