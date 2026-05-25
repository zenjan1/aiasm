.intel_syntax noprefix
# -----------------------------------------------------------------------------
# wasm_vm.asm - WASM 虚拟机核心（栈式虚拟机）
# -----------------------------------------------------------------------------
# 实现栈式虚拟机，操作数栈和控制栈
# 实现基本指令集：控制流、参数、变量、内存、数值运算
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# WASM 操作码定义
# ============================================================================
# 控制流
OP_UNREACHABLE   = 0x00
OP_NOP           = 0x01
OP_BLOCK         = 0x02
OP_LOOP          = 0x03
OP_IF            = 0x04
OP_ELSE          = 0x05
OP_END           = 0x0B
OP_BR            = 0x0C
OP_BR_IF         = 0x0D
OP_BR_TABLE      = 0x0E
OP_RETURN        = 0x0F
OP_CALL          = 0x10
OP_CALL_INDIRECT = 0x11

# 参数指令
OP_DROP          = 0x1A
OP_SELECT        = 0x1B

# 变量指令
OP_LOCAL_GET     = 0x20
OP_LOCAL_SET     = 0x21
OP_LOCAL_TEE     = 0x22
OP_GLOBAL_GET    = 0x23
OP_GLOBAL_SET    = 0x24

# 内存指令
OP_I32_LOAD      = 0x28
OP_I64_LOAD      = 0x29
OP_F32_LOAD      = 0x2A
OP_F64_LOAD      = 0x2B
OP_I32_LOAD8_S   = 0x2C
OP_I32_LOAD8_U   = 0x2D
OP_I32_LOAD16_S  = 0x2E
OP_I32_LOAD16_U  = 0x2F
OP_I64_LOAD8_S   = 0x30
OP_I64_LOAD8_U   = 0x31
OP_I64_LOAD16_S  = 0x32
OP_I64_LOAD16_U  = 0x33
OP_I64_LOAD32_S  = 0x34
OP_I64_LOAD32_U  = 0x35
OP_I32_STORE     = 0x36
OP_I64_STORE     = 0x37
OP_F32_STORE     = 0x38
OP_F64_STORE     = 0x39
OP_I32_STORE8    = 0x3A
OP_I32_STORE16   = 0x3B
OP_I64_STORE8    = 0x3C
OP_I64_STORE16   = 0x3D
OP_I64_STORE32   = 0x3E
OP_MEMORY_SIZE   = 0x3F
OP_MEMORY_GROW   = 0x40

# 数值常量
OP_I32_CONST     = 0x41
OP_I64_CONST     = 0x42
OP_F32_CONST     = 0x43
OP_F64_CONST     = 0x44

# i32 比较运算
OP_I32_EQZ       = 0x45
OP_I32_EQ        = 0x46
OP_I32_NE        = 0x47
OP_I32_LT_S      = 0x48
OP_I32_LT_U      = 0x49
OP_I32_GT_S      = 0x4A
OP_I32_GT_U      = 0x4B
OP_I32_LE_S      = 0x4C
OP_I32_LE_U      = 0x4D
OP_I32_GE_S      = 0x4E
OP_I32_GE_U      = 0x4F

# i32 算术运算
OP_I32_CLZ       = 0x67
OP_I32_CTZ       = 0x68
OP_I32_POPCNT    = 0x69
OP_I32_ADD       = 0x6A
OP_I32_SUB       = 0x6B
OP_I32_MUL       = 0x6C
OP_I32_DIV_S     = 0x6D
OP_I32_DIV_U     = 0x6E
OP_I32_REM_S     = 0x6F
OP_I32_REM_U     = 0x70
OP_I32_AND       = 0x71
OP_I32_OR        = 0x72
OP_I32_XOR       = 0x73
OP_I32_SHL       = 0x74
OP_I32_SHR_S     = 0x75
OP_I32_SHR_U     = 0x76
OP_I32_ROTL      = 0x77
OP_I32_ROTR      = 0x78

# i64 比较运算
OP_I64_EQZ       = 0x50
OP_I64_EQ        = 0x51
OP_I64_NE        = 0x52
OP_I64_LT_S      = 0x53
OP_I64_LT_U      = 0x54
OP_I64_GT_S      = 0x55
OP_I64_GT_U      = 0x56
OP_I64_LE_S      = 0x57
OP_I64_LE_U      = 0x58
OP_I64_GE_S      = 0x59
OP_I64_GE_U      = 0x5A

# i64 算术运算
OP_I64_CLZ       = 0x79
OP_I64_CTZ       = 0x7A
OP_I64_POPCNT    = 0x7B
OP_I64_ADD       = 0x7C
OP_I64_SUB       = 0x7D
OP_I64_MUL       = 0x7E
OP_I64_DIV_S     = 0x7F
OP_I64_DIV_U     = 0x80
OP_I64_REM_S     = 0x81
OP_I64_REM_U     = 0x82
OP_I64_AND       = 0x83
OP_I64_OR        = 0x84
OP_I64_XOR       = 0x85
OP_I64_SHL       = 0x86
OP_I64_SHR_S     = 0x87
OP_I64_SHR_U     = 0x88
OP_I64_ROTL      = 0x89
OP_I64_ROTR      = 0x8A

# i32/i64 转换
OP_I32_WRAP_I64  = 0xA7
OP_I64_EXTEND_I32_S = 0xAC
OP_I64_EXTEND_I32_U = 0xAD

# ============================================================================
# WASM 宿主函数 ID（与 wasm_syscall.asm 保持一致）
# ============================================================================
WASM_HOST_PRINT      = 0
WASM_HOST_PRINTLN    = 1
WASM_HOST_PUTCHAR    = 2
WASM_HOST_GETCHAR    = 3
WASM_HOST_MEMINFO    = 4
WASM_HOST_TIME       = 5
WASM_HOST_ALLOC      = 6
WASM_HOST_FREE       = 7

# ============================================================================
# 虚拟机状态（BSS）
# ============================================================================
    .section .bss
    .align  16

    # 操作数栈（最大 256 个元素）
    .globl  wasm_operand_stack
wasm_operand_stack:
    .space  1024                  # 256 * 4 字节

    .globl  wasm_stack_top
wasm_stack_top:
    .space  4                   # 栈顶指针（相对于栈基址）

    # 控制栈（最大 32 个控制帧）
    .globl  wasm_control_stack
wasm_control_stack:
    .space  512                 # 32 * 16 字节控制帧

    .globl  wasm_control_top
wasm_control_top:
    .space  4                   # 控制栈顶指针

    # 调用栈（最大 16 层嵌套调用）
    .globl  wasm_call_stack
wasm_call_stack:
    .space  256                 # 16 * 16 字节调用帧

    .globl  wasm_call_top
wasm_call_top:
    .space  4                   # 调用栈顶指针

    # 局部变量（最大 256 个）
    .globl  wasm_locals
wasm_locals:
    .space  1024                # 256 * 4 字节

    # 全局变量（最大 64 个）
    .globl  wasm_globals
wasm_globals:
    .space  256                 # 64 * 4 字节

    # 线性内存（64KB 默认）
    .globl  wasm_linear_memory
wasm_linear_memory:
    .space  65536               # 64KB

    .globl  wasm_memory_pages
wasm_memory_pages:
    .space  4                   # 当前内存页数

    # 执行状态
    .globl  wasm_running
wasm_running:
    .space  1                   # 是否正在执行

    .globl  wasm_pc
wasm_pc:
    .space  4                   # 程序计数器（代码指针）

    .globl  wasm_code_end
wasm_code_end:
    .space  4                   # 代码结束指针

    .globl  wasm_return_value
wasm_return_value:
    .space  4                   # 返回值

    .globl  wasm_exec_error
wasm_exec_error:
    .space  4                   # 执行错误码

    .globl  wasm_loop_start
wasm_loop_start:
    .space  4                   # 当前 loop 块的起始 PC

# ============================================================================
# wasm_vm_init: 初始化虚拟机
# ============================================================================
    .section .text
    .globl  wasm_vm_init
wasm_vm_init:
    push    eax
    push    edi

    # 清零栈和状态
    mov     edi, offset wasm_operand_stack
    mov     ecx, 1024 / 4
    xor     eax, eax
    cld
    rep     stosd

    mov     edi, offset wasm_control_stack
    mov     ecx, 512 / 4
    rep     stosd

    mov     edi, offset wasm_call_stack
    mov     ecx, 256 / 4
    rep     stosd

    mov     edi, offset wasm_locals
    mov     ecx, 1024 / 4
    rep     stosd

    mov     edi, offset wasm_globals
    mov     ecx, 256 / 4
    rep     stosd

    mov     edi, offset wasm_linear_memory
    mov     ecx, 65536 / 4
    rep     stosd

    # 初始化指针
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    mov     dword ptr [wasm_memory_pages], 1    # 1 页 = 64KB
    mov     byte ptr [wasm_running], 0
    mov     dword ptr [wasm_exec_error], 0

    pop     edi
    pop     eax
    ret

# ============================================================================
# wasm_load_data: 将解析后的 data 段加载到线性内存
# 输入：无（使用 wasm_data_table）
# 输出：eax = 0（成功）或错误码
# ============================================================================
    .globl  wasm_load_data
wasm_load_data:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    mov     ecx, [wasm_data_count]
    test    ecx, ecx
    jz      load_data_done_ok

    mov     edi, offset wasm_data_table

load_data_segment:
    test    ecx, ecx
    jz      load_data_done_ok

    # 读取：偏移(4) + 大小(4) + 数据指针(4) = 12 字节/条目
    mov     eax, [edi]            # 偏移
    mov     ebx, [edi + 4]        # 大小
    mov     esi, [edi + 8]        # 数据源指针

    # 检查是否超出线性内存
    mov     edx, [wasm_memory_pages]
    shl     edx, 16               # 内存总大小（字节）
    mov     edx, eax
    add     edx, ebx
    cmp     edx, [wasm_memory_pages]
    shl     edx, 16
    ja      load_data_overflow

    # 复制数据到线性内存
    mov     edi, offset wasm_linear_memory
    add     edi, eax              # 目标地址

    push    ecx                   # 保存段计数器
    mov     ecx, ebx              # ecx = 字节数
    rep     movsb
    pop     ecx

    add     edi, 12               # 下一个数据段条目
    dec     ecx
    jmp     load_data_segment

load_data_done_ok:
    xor     eax, eax
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

load_data_overflow:
    mov     eax, 1
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# wasm_exec_func: 执行 WASM 函数
# 输入：eax = 函数索引
# 输出：eax = 返回值（或错误码）
# ============================================================================
    .globl  wasm_exec_func
wasm_exec_func:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 检查函数索引合法性
    cmp     eax, [wasm_func_count]
    jae     exec_func_err

    # 获取函数的类型索引
    mov     ebx, eax
    shl     ebx, 2
    mov     ebx, [wasm_func_table + ebx]

    # 获取代码体指针和大小
    mov     ebx, eax
    shl     ebx, 3               # 每个条目 8 字节
    mov     esi, [wasm_code_table + ebx]  # esi = 代码体指针
    mov     ecx, [wasm_code_table + ebx + 4]  # ecx = 代码体大小

    # 保存代码范围
    mov     [wasm_pc], esi
    lea     edx, [esi + ecx]
    mov     [wasm_code_end], edx

    # 跳过局部变量声明，读取局部变量条目数量
    call    _read_leb128_vm
    mov     edx, eax              # edx = 局部变量条目数量
    xor     ebx, ebx              # ebx = 当前局部变量索引

    # 初始化局部变量为 0
init_locals_loop:
    test    edx, edx
    jz      start_exec_code

    push    edx                   # _read_leb128_vm 会修改 edx

    # 读取此条目的局部变量数量
    call    _read_leb128_vm
    mov     ecx, eax              # ecx = 此条目有多少个局部变量

    # 跳过类型字节
    call    _read_leb128_vm

    pop     edx                   # 恢复条目数量

    # 将 ecx 个局部变量清零
init_locals_entry:
    test    ecx, ecx
    jz      init_locals_next
    mov     dword ptr [wasm_locals + ebx * 4], 0
    inc     ebx
    dec     ecx
    jmp     init_locals_entry

init_locals_next:
    dec     edx
    jmp     init_locals_loop

start_exec_code:
    mov     byte ptr [wasm_running], 1

exec_code_loop:
    # 检查是否仍在运行
    cmp     byte ptr [wasm_running], 0
    je      exec_code_done

    # 检查是否到达代码末尾
    mov     esi, [wasm_pc]
    cmp     esi, [wasm_code_end]
    jae     exec_code_done

    # 读取操作码
    movzx   ebx, byte ptr [esi]
    inc     esi
    mov     [wasm_pc], esi

    # 分发执行
    call    _dispatch_opcode

    jmp     exec_code_loop

exec_code_done:
    # 从操作数栈弹出返回值
    call    _stack_pop
    mov     [wasm_return_value], eax

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

exec_func_err:
    mov     eax, -1
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# _dispatch_opcode: 操作码分发
# 输入：ebx = 操作码
# ============================================================================
_dispatch_opcode:
    push    eax
    push    ecx

    # 控制流
    cmp     ebx, OP_UNREACHABLE
    je      do_unreachable
    cmp     ebx, OP_NOP
    je      do_nop
    cmp     ebx, OP_BLOCK
    je      do_block
    cmp     ebx, OP_LOOP
    je      do_loop
    cmp     ebx, OP_IF
    je      do_if
    cmp     ebx, OP_ELSE
    je      do_else
    cmp     ebx, OP_END
    je      do_end
    cmp     ebx, OP_BR
    je      do_br
    cmp     ebx, OP_BR_IF
    je      do_br_if
    cmp     ebx, OP_RETURN
    je      do_return
    cmp     ebx, OP_CALL
    je      do_call

    # 参数
    cmp     ebx, OP_DROP
    je      do_drop
    cmp     ebx, OP_SELECT
    je      do_select

    # 变量
    cmp     ebx, OP_LOCAL_GET
    je      do_local_get
    cmp     ebx, OP_LOCAL_SET
    je      do_local_set
    cmp     ebx, OP_LOCAL_TEE
    je      do_local_tee
    cmp     ebx, OP_GLOBAL_GET
    je      do_global_get
    cmp     ebx, OP_GLOBAL_SET
    je      do_global_set

    # 内存
    cmp     ebx, OP_I32_LOAD
    je      do_i32_load
    cmp     ebx, OP_I32_LOAD8_S
    je      do_i32_load8_s
    cmp     ebx, OP_I32_LOAD8_U
    je      do_i32_load8_u
    cmp     ebx, OP_I32_LOAD16_S
    je      do_i32_load16_s
    cmp     ebx, OP_I32_LOAD16_U
    je      do_i32_load16_u
    cmp     ebx, OP_I32_STORE
    je      do_i32_store
    cmp     ebx, OP_I32_STORE8
    je      do_i32_store8
    cmp     ebx, OP_I32_STORE16
    je      do_i32_store16
    cmp     ebx, OP_MEMORY_SIZE
    je      do_memory_size
    cmp     ebx, OP_MEMORY_GROW
    je      do_memory_grow

    # br_table
    cmp     ebx, OP_BR_TABLE
    je      do_br_table

    # 常量
    cmp     ebx, OP_I32_CONST
    je      do_i32_const

    # i32 比较
    cmp     ebx, OP_I32_EQZ
    je      do_i32_eqz
    cmp     ebx, OP_I32_EQ
    je      do_i32_eq
    cmp     ebx, OP_I32_NE
    je      do_i32_ne
    cmp     ebx, OP_I32_LT_S
    je      do_i32_lt_s
    cmp     ebx, OP_I32_LT_U
    je      do_i32_lt_u
    cmp     ebx, OP_I32_GT_S
    je      do_i32_gt_s
    cmp     ebx, OP_I32_GT_U
    je      do_i32_gt_u
    cmp     ebx, OP_I32_LE_S
    je      do_i32_le_s
    cmp     ebx, OP_I32_LE_U
    je      do_i32_le_u
    cmp     ebx, OP_I32_GE_S
    je      do_i32_ge_s

    # i32 算术
    cmp     ebx, OP_I32_ADD
    je      do_i32_add
    cmp     ebx, OP_I32_SUB
    je      do_i32_sub
    cmp     ebx, OP_I32_MUL
    je      do_i32_mul
    cmp     ebx, OP_I32_DIV_S
    je      do_i32_div_s
    cmp     ebx, OP_I32_DIV_U
    je      do_i32_div_u
    cmp     ebx, OP_I32_REM_S
    je      do_i32_rem_s
    cmp     ebx, OP_I32_REM_U
    je      do_i32_rem_u
    cmp     ebx, OP_I32_AND
    je      do_i32_and
    cmp     ebx, OP_I32_OR
    je      do_i32_or
    cmp     ebx, OP_I32_XOR
    je      do_i32_xor
    cmp     ebx, OP_I32_SHL
    je      do_i32_shl
    cmp     ebx, OP_I32_SHR_S
    je      do_i32_shr_s
    cmp     ebx, OP_I32_SHR_U
    je      do_i32_shr_u

    # 未知操作码
    jmp     do_unknown

# 控制流操作
do_unreachable:
    mov     byte ptr [wasm_running], 0
    mov     dword ptr [wasm_exec_error], 1
    jmp     dispatch_done

do_nop:
    jmp     dispatch_done

do_block:
    # 读取 block type，跳过
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    # 控制帧入栈：type=BLOCK, start_pc=当前pc, end_pc=需扫描找end
    call    _ctrl_frame_push_block
    jmp     dispatch_done

do_loop:
    # 读取 block type，跳过
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    # 控制帧入栈：type=LOOP, start_pc=loop开始
    call    _ctrl_frame_push_loop
    jmp     dispatch_done

do_if:
    # 读取 block type
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ebx, eax              # ebx = block type
    # 弹出条件值
    call    _stack_pop
    test    eax, eax
    jnz     do_if_true
    # 条件为假：跳到 else 或 end
    call    _skip_to_else_or_end
    jmp     dispatch_done
do_if_true:
    # 条件为真：push BLOCK frame
    call    _ctrl_frame_push_block
    jmp     dispatch_done

do_else:
    # 找到对应的 if 帧，跳到 end
    call    _ctrl_frame_find_if
    jc      dispatch_done
    call    _skip_to_end
    jmp     dispatch_done

do_end:
    # 弹出控制帧，end 只是退出 block/loop/if，不循环
    call    _ctrl_frame_pop
    jmp     dispatch_done

do_br:
    # 读取 label index
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ebx, eax              # ebx = label index
    # 查找目标帧类型（不出栈）
    call    _ctrl_frame_peek_at
    cmp     eax, 2                # LOOP type
    je      do_br_loop            # LOOP: 不弹出帧，直接跳回
    # BLOCK/IF: 弹出 N+1 帧
    call    _ctrl_frame_pop_n
    jmp     dispatch_done
do_br_loop:
    mov     esi, [wasm_loop_start]
    mov     [wasm_pc], esi
    jmp     dispatch_done

do_br_if:
    # 读取 label index
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ebx, eax              # ebx = label index
    # 弹出条件值
    call    _stack_pop
    test    eax, eax
    jz      dispatch_done
    # 条件为真：查找目标帧类型
    call    _ctrl_frame_peek_at
    cmp     eax, 2                # LOOP type
    je      do_br_if_loop         # LOOP: 不弹出帧，跳回
    # BLOCK/IF: 弹出 N+1 帧
    call    _ctrl_frame_pop_n
    jmp     dispatch_done
do_br_if_loop:
    mov     esi, [wasm_loop_start]
    mov     [wasm_pc], esi
    jmp     dispatch_done

# br_table: 实现 switch-case 分支表
# 格式: br_table vec[label1, label2, ..., labelN] default_label
do_br_table:
    # 读取分支表数量
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ecx, eax              # ecx = 分支数量

    # 弹出选择索引
    call    _stack_pop
    mov     edx, eax              # edx = 索引

    # 检查索引是否在范围内
    cmp     edx, ecx
    jb      .br_table_in_range

    # 索引超出范围，跳到 default label
    # 读取所有 label 并跳过，最后读取 default
.br_table_skip_to_default:
    test    ecx, ecx
    jz      .br_table_read_default
    call    _read_leb128_vm       # 跳过一个 label
    dec     ecx
    jmp     .br_table_skip_to_default

.br_table_read_default:
    call    _read_leb128_vm
    mov     ebx, eax              # ebx = default label
    jmp     .br_table_execute

.br_table_in_range:
    # 读取第 edx 个 label
    test    edx, edx
    jz      .br_table_target_found
    call    _read_leb128_vm       # 跳过一个 label
    dec     edx
    jmp     .br_table_in_range

.br_table_target_found:
    call    _read_leb128_vm
    mov     ebx, eax              # ebx = target label
    # 跳过剩余 labels 和 default
    add     ecx, 1                # 剩余数量 + 1 (default)
.br_table_skip_rest:
    test    ecx, ebx              # 使用 ebx 作为计数器（避免冲突）
    jz      .br_table_execute
    push    ebx                   # 保存 target label
    call    _read_leb128_vm
    pop     ebx
    dec     ecx
    jmp     .br_table_skip_rest

.br_table_execute:
    # 执行分支跳转（与 br 相同的逻辑）
    call    _ctrl_frame_peek_at
    cmp     eax, 2                # LOOP type
    je      .br_table_loop
    call    _ctrl_frame_pop_n
    jmp     dispatch_done
.br_table_loop:
    mov     esi, [wasm_loop_start]
    mov     [wasm_pc], esi
    jmp     dispatch_done

do_return:
    # 检查是否有调用栈帧
    mov     eax, [wasm_call_top]
    test    eax, eax
    jz      do_return_top
    # 从调用栈恢复
    call    _call_frame_pop
    mov     [wasm_pc], esi
    mov     byte ptr [wasm_running], 1
    jmp     dispatch_done
do_return_top:
    mov     byte ptr [wasm_running], 0
    jmp     dispatch_done

do_call:
    # 读取函数索引
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    # 检查是否为宿主函数（索引 >= wasm_func_count）
    cmp     eax, [wasm_func_count]
    jae     do_call_host
    push    eax                 # 保存函数索引
    # 保存当前 PC 到调用栈
    mov     esi, [wasm_pc]      # esi = 返回地址
    call    _call_frame_push
    # 执行被调用函数
    pop     eax
    call    wasm_exec_func_body
    # 返回值已在 eax 中
    push    eax
    call    _stack_push
    pop     eax
    jmp     dispatch_done

do_call_host:
    # Map WASM function index to host function slot
    sub     eax, [wasm_func_count]    # eax = host slot (= host ID)
    mov     ecx, eax              # ecx = host function ID
    push    eax                   # save function ID
    # putchar(2): 1 arg; getchar(3): 0 args; time(5): 0 args
    # print(0), println(1): 2 args; meminfo(4): 0 args
    # alloc(6): 1 arg; free(7): 1 arg
    cmp     ecx, WASM_HOST_PUTCHAR
    je      .host_1arg
    cmp     ecx, WASM_HOST_GETCHAR
    je      .host_0arg
    cmp     ecx, WASM_HOST_TIME
    je      .host_0arg
    cmp     ecx, WASM_HOST_MEMINFO
    je      .host_0arg
    cmp     ecx, WASM_HOST_ALLOC
    je      .host_1arg
    cmp     ecx, WASM_HOST_FREE
    je      .host_1arg
    # default: print/println - 2 args
.host_2arg:
    call    _stack_pop           # 参数2
    mov     ecx, eax
    call    _stack_pop           # 参数1
    mov     ebx, eax
    xor     edx, edx             # 参数3 = 0
    pop     eax
    jmp     .do_host_call
.host_1arg:
    call    _stack_pop           # 参数1
    mov     ebx, eax
    xor     ecx, ecx             # 参数2 = 0
    xor     edx, edx             # 参数3 = 0
    pop     eax
    jmp     .do_host_call
.host_0arg:
    xor     ebx, ebx
    xor     ecx, ecx
    xor     edx, edx
    pop     eax
.do_host_call:
    call    wasm_host_call
    # 返回值压入操作数栈
    push    eax
    call    _stack_push
    pop     eax
    jmp     dispatch_done

# 参数操作
do_drop:
    call    _stack_pop
    jmp     dispatch_done

do_select:
    call    _stack_pop           # 条件
    mov     ecx, eax
    call    _stack_pop           # val2
    mov     edx, eax
    call    _stack_pop           # val1
    test    ecx, ecx
    jz      select_val2
    call    _stack_push
    jmp     dispatch_done
select_val2:
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done

# 变量操作
do_local_get:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ebx, eax
    shl     ebx, 2
    mov     eax, [wasm_locals + ebx]
    call    _stack_push
    jmp     dispatch_done

do_local_set:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ebx, eax
    call    _stack_pop
    shl     ebx, 2
    mov     [wasm_locals + ebx], eax
    jmp     dispatch_done

do_local_tee:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ebx, eax
    call    _stack_top
    shl     ebx, 2
    mov     [wasm_locals + ebx], eax
    jmp     dispatch_done

do_global_get:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ebx, eax
    shl     ebx, 2
    mov     eax, [wasm_globals + ebx]
    call    _stack_push
    jmp     dispatch_done

do_global_set:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ebx, eax
    call    _stack_pop
    shl     ebx, 2
    mov     [wasm_globals + ebx], eax
    jmp     dispatch_done

# 内存操作
do_i32_load:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    call    _read_leb128_vm  # offset
    mov     ebx, eax             # ebx = offset
    call    _stack_pop           # eax = address
    add     eax, ebx
    mov     eax, [wasm_linear_memory + eax]
    call    _stack_push
    jmp     dispatch_done

do_i32_store:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    call    _read_leb128_vm  # offset
    mov     ebx, eax             # ebx = offset
    call    _stack_pop           # eax = value
    mov     edx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    mov     [wasm_linear_memory + eax], edx
    jmp     dispatch_done

# 新增内存操作 - byte 和 word 存取
do_i32_load8_s:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    call    _read_leb128_vm  # offset
    mov     ebx, eax             # ebx = offset
    call    _stack_pop           # eax = address
    add     eax, ebx
    movzx   eax, byte ptr [wasm_linear_memory + eax]
    # sign extend: if high bit set, extend to negative
    test    eax, 0x80
    jz      .load8u_ok
    or      eax, 0xFFFFFF00
.load8u_ok:
    call    _stack_push
    jmp     dispatch_done

do_i32_load8_u:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    call    _read_leb128_vm  # offset
    mov     ebx, eax             # ebx = offset
    call    _stack_pop           # eax = address
    add     eax, ebx
    movzx   eax, byte ptr [wasm_linear_memory + eax]
    call    _stack_push
    jmp     dispatch_done

do_i32_load16_s:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    call    _read_leb128_vm  # offset
    mov     ebx, eax             # ebx = offset
    call    _stack_pop           # eax = address
    add     eax, ebx
    movzx   eax, word ptr [wasm_linear_memory + eax]
    # sign extend: if high bit set, extend to negative
    test    eax, 0x8000
    jz      .load16u_ok
    or      eax, 0xFFFF0000
.load16u_ok:
    call    _stack_push
    jmp     dispatch_done

do_i32_load16_u:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    call    _read_leb128_vm  # offset
    mov     ebx, eax             # ebx = offset
    call    _stack_pop           # eax = address
    add     eax, ebx
    movzx   eax, word ptr [wasm_linear_memory + eax]
    call    _stack_push
    jmp     dispatch_done

do_i32_store8:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    call    _read_leb128_vm  # offset
    mov     ebx, eax             # ebx = offset
    call    _stack_pop           # eax = value
    mov     edx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    mov     [wasm_linear_memory + eax], dl
    jmp     dispatch_done

do_i32_store16:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    call    _read_leb128_vm  # offset
    mov     ebx, eax             # ebx = offset
    call    _stack_pop           # eax = value
    mov     edx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    mov     [wasm_linear_memory + eax], dx
    jmp     dispatch_done

do_memory_size:
    mov     eax, [wasm_memory_pages]
    call    _stack_push
    jmp     dispatch_done

do_memory_grow:
    call    _stack_pop           # eax = 页数
    mov     ebx, eax
    mov     eax, [wasm_memory_pages]
    mov     ecx, eax             # 保存旧页数
    add     eax, ebx
    cmp     eax, 65536           # 最大 65536 页
    ja      grow_fail
    mov     [wasm_memory_pages], eax
    # 返回旧页数
    mov     eax, ecx
    call    _stack_push
    jmp     dispatch_done
grow_fail:
    mov     eax, -1
    call    _stack_push
    jmp     dispatch_done

# 常量
do_i32_const:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    call    _stack_push
    jmp     dispatch_done

# i32 比较
do_i32_eqz:
    call    _stack_pop
    test    eax, eax
    setz    al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_eq:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    sete    al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_ne:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    setne   al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_lt_s:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    setl    al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_gt_s:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    setg    al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_le_s:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    setle   al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_lt_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    setb    al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_gt_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    seta    al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_ge_s:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    setge   al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_le_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    setbe   al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

do_i32_ge_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    cmp     eax, ecx
    setae   al
    movzx   eax, al
    call    _stack_push
    jmp     dispatch_done

# i32 算术
do_i32_add:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    add     eax, ecx
    call    _stack_push
    jmp     dispatch_done

do_i32_sub:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    sub     eax, ecx
    call    _stack_push
    jmp     dispatch_done

do_i32_mul:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    imul    eax, ecx
    call    _stack_push
    jmp     dispatch_done

do_i32_div_s:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    test    ecx, ecx
    jz      div_zero_err
    cdq
    idiv    ecx
    call    _stack_push
    jmp     dispatch_done
div_zero_err:
    mov     eax, -1
    call    _stack_push
    jmp     dispatch_done

do_i32_div_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    test    ecx, ecx
    jz      divu_zero_err
    xor     edx, edx
    div     ecx
    call    _stack_push
    jmp     dispatch_done
divu_zero_err:
    mov     eax, -1
    call    _stack_push
    jmp     dispatch_done

do_i32_rem_s:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    test    ecx, ecx
    jz      rems_zero_err
    cdq
    idiv    ecx
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
rems_zero_err:
    mov     eax, -1
    call    _stack_push
    jmp     dispatch_done

do_i32_rem_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    test    ecx, ecx
    jz      remu_zero_err
    xor     edx, edx
    div     ecx
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
remu_zero_err:
    mov     eax, -1
    call    _stack_push
    jmp     dispatch_done

do_i32_and:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    and     eax, ecx
    call    _stack_push
    jmp     dispatch_done

do_i32_or:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    or      eax, ecx
    call    _stack_push
    jmp     dispatch_done

do_i32_xor:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    xor     eax, ecx
    call    _stack_push
    jmp     dispatch_done

do_i32_shl:
    call    _stack_pop
    mov     ecx, eax
    and     ecx, 31              # 只取低 5 位
    call    _stack_pop
    shl     eax, cl
    call    _stack_push
    jmp     dispatch_done

do_i32_shr_s:
    call    _stack_pop
    mov     ecx, eax
    and     ecx, 31
    call    _stack_pop
    sar     eax, cl
    call    _stack_push
    jmp     dispatch_done

do_i32_shr_u:
    call    _stack_pop
    mov     ecx, eax
    and     ecx, 31
    call    _stack_pop
    shr     eax, cl
    call    _stack_push
    jmp     dispatch_done

do_unknown:
    mov     byte ptr [wasm_running], 0
    mov     dword ptr [wasm_exec_error], 2

dispatch_done:
    pop     ecx
    pop     eax
    ret

# ============================================================================
# 控制帧操作
# 控制帧格式：4字节type + 4字节start_pc + 4字节end_pc + 4字节else_pc = 16字节
# type: 0=plain, 1=if, 2=loop, 3=block
# ============================================================================
CTRL_FRAME_BLOCK  = 3
CTRL_FRAME_LOOP   = 2
CTRL_FRAME_IF     = 1
CTRL_FRAME_PLAIN  = 0

# _ctrl_frame_push_block: 压入 block 帧
# 输入：ebx = block type
_ctrl_frame_push_block:
    push    eax
    push    ecx
    push    edx
    push    edi

    mov     eax, [wasm_control_top]
    imul    eax, 16
    add     eax, offset wasm_control_stack

    mov     ecx, CTRL_FRAME_BLOCK
    mov     [eax], ecx            # type
    mov     ecx, [wasm_pc]
    mov     [eax + 4], ecx        # start_pc
    # end_pc 和 else_pc 设为 0，需要扫描代码找 end
    mov     dword ptr [eax + 8], 0
    mov     dword ptr [eax + 12], 0

    inc     dword ptr [wasm_control_top]

    pop     edi
    pop     edx
    pop     ecx
    pop     eax
    ret

# _ctrl_frame_push_loop: 压入 loop 帧
# 输入：ebx = block type
_ctrl_frame_push_loop:
    push    eax
    push    ecx
    push    edx
    push    edi

    mov     eax, [wasm_control_top]
    imul    eax, 16
    add     eax, offset wasm_control_stack

    mov     ecx, CTRL_FRAME_LOOP
    mov     [eax], ecx            # type
    mov     ecx, [wasm_pc]        # loop 的 start = 当前位置（跳过 block type 后）
    mov     [eax + 4], ecx        # start_pc
    mov     [wasm_loop_start], ecx  # 保存 loop 起始位置
    mov     dword ptr [eax + 8], 0
    mov     dword ptr [eax + 12], 0

    inc     dword ptr [wasm_control_top]

    pop     edi
    pop     edx
    pop     ecx
    pop     eax
    ret

# _ctrl_frame_peek_at: 查看指定深度的控制帧类型（不出栈）
# 输入：ebx = label index (0=最内层)
# 输出：eax = frame type
_ctrl_frame_peek_at:
    push    ecx
    push    edx
    mov     eax, [wasm_control_top]
    sub     eax, ebx              # target = control_top - label_index
    dec     eax                   # adjust: frames are at 0..control_top-1
    test    eax, eax
    jl      _ctrl_peek_empty
    imul    eax, 16
    add     eax, offset wasm_control_stack
    mov     eax, [eax]            # eax = frame type
    pop     edx
    pop     ecx
    ret
_ctrl_peek_empty:
    xor     eax, eax
    pop     edx
    pop     ecx
    ret

# _ctrl_frame_pop: 弹出控制帧
# 输出：eax = frame type, CF=1 if stack was empty
_ctrl_frame_pop:
    push    ebx
    push    ecx

    mov     eax, [wasm_control_top]
    test    eax, eax
    jz      _ctrl_pop_empty

    dec     eax
    mov     [wasm_control_top], eax
    imul    eax, 16
    add     eax, offset wasm_control_stack
    mov     eax, [eax]            # eax = type
    clc
    pop     ecx
    pop     ebx
    ret

_ctrl_pop_empty:
    mov     eax, 0
    stc
    pop     ecx
    pop     ebx
    ret

# _ctrl_frame_pop_n: 弹出 N+1 个控制帧（br/br_if）
# 输入：ebx = label index
# 输出：eax = 最后一个帧的 type
_ctrl_frame_pop_n:
    push    ecx
    mov     ecx, ebx
    inc     ecx                   # N+1
_ctrl_pop_n_loop:
    test    ecx, ecx
    jz      _ctrl_pop_n_done
    call    _ctrl_frame_pop
    dec     ecx
    jmp     _ctrl_pop_n_loop
_ctrl_pop_n_done:
    pop     ecx
    ret

# _ctrl_frame_find_if: 找到最近的 if 帧
_ctrl_frame_find_if:
    push    ebx
    push    ecx

    mov     eax, [wasm_control_top]
    test    eax, eax
    jz      _ctrl_find_if_fail

_ctrl_find_if_loop:
    dec     eax
    mov     [wasm_control_top], eax
    imul    eax, 16
    add     eax, offset wasm_control_stack
    mov     ecx, [eax]
    cmp     ecx, CTRL_FRAME_IF
    je      _ctrl_find_if_ok
    cmp     dword ptr [wasm_control_top], 0
    jg      _ctrl_find_if_loop

_ctrl_find_if_fail:
    stc
    pop     ecx
    pop     ebx
    ret

_ctrl_find_if_ok:
    clc
    pop     ecx
    pop     ebx
    ret

# _skip_to_end: 跳到当前控制帧的 end
_skip_to_end:
    push    eax
    push    ecx
    push    edx

    mov     esi, [wasm_pc]
    mov     ecx, 0                # 嵌套深度
_skip_end_loop:
    movzx   eax, byte ptr [esi]
    cmp     al, OP_BLOCK
    je      _skip_end_block
    cmp     al, OP_LOOP
    je      _skip_end_block
    cmp     al, OP_IF
    je      _skip_end_block
    cmp     al, OP_END
    je      _skip_end_found
_skip_end_next:
    inc     esi
    jmp     _skip_end_loop
_skip_end_block:
    inc     ecx
    jmp     _skip_end_next
_skip_end_found:
    test    ecx, ecx
    jz      _skip_end_done
    dec     ecx
    jmp     _skip_end_next
_skip_end_done:
    inc     esi                   # 跳过 end 字节
    mov     [wasm_pc], esi

    pop     edx
    pop     ecx
    pop     eax
    ret

# _skip_to_else_or_end: if 条件为假时跳到 else 或 end
_skip_to_else_or_end:
    push    eax
    push    ecx
    push    edx

    mov     esi, [wasm_pc]
    mov     ecx, 0                # 嵌套深度
_skip_else_loop:
    movzx   eax, byte ptr [esi]
    cmp     al, OP_BLOCK
    je      _skip_else_block
    cmp     al, OP_LOOP
    je      _skip_else_block
    cmp     al, OP_IF
    je      _skip_else_block
    cmp     al, OP_ELSE
    je      _skip_else_found
    cmp     al, OP_END
    je      _skip_else_end_found
_skip_else_next:
    inc     esi
    jmp     _skip_else_loop
_skip_else_block:
    inc     ecx
    jmp     _skip_else_next
_skip_else_found:
    test    ecx, ecx
    jz      _skip_else_done
    dec     ecx
    jmp     _skip_else_next
_skip_else_end_found:
    test    ecx, ecx
    jz      _skip_else_done
    dec     ecx
    jmp     _skip_else_next
_skip_else_done:
    inc     esi
    mov     [wasm_pc], esi

    pop     edx
    pop     ecx
    pop     eax
    ret

# ============================================================================
# 调用栈操作
# 调用帧格式：4字节return_pc + 4字节saved_pc + 4字节saved_code_end + 4字节saved_frame_ptr = 16字节
# ============================================================================

# _call_frame_push: 压入调用帧
# 输入：esi = 返回地址（caller 的 PC）
_call_frame_push:
    push    eax
    push    ecx
    push    edx

    mov     eax, [wasm_call_top]
    cmp     eax, 16
    jae     _call_push_fail

    imul    eax, 16
    add     eax, offset wasm_call_stack

    mov     ecx, esi
    mov     [eax], ecx            # return_pc
    mov     ecx, [wasm_pc]        # 保存当前 PC（caller 的下一条指令）
    mov     [eax + 4], ecx
    mov     ecx, [wasm_code_end]
    mov     [eax + 8], ecx        # 保存 code_end

    inc     dword ptr [wasm_call_top]
    jmp     _call_push_done

_call_push_fail:
    # 调用栈溢出，停止执行
    mov     byte ptr [wasm_running], 0
    mov     dword ptr [wasm_exec_error], 3

_call_push_done:
    pop     edx
    pop     ecx
    pop     eax
    ret

# _call_frame_pop: 弹出调用帧，恢复 PC
# 输出：esi = 返回地址
_call_frame_pop:
    push    eax

    mov     eax, [wasm_call_top]
    test    eax, eax
    jz      _call_pop_empty

    dec     eax
    mov     [wasm_call_top], eax
    imul    eax, 16
    add     eax, offset wasm_call_stack

    mov     esi, [eax + 4]        # 恢复 caller 的 PC
    mov     edx, [eax + 8]
    mov     [wasm_code_end], edx  # 恢复 code_end

    pop     eax
    ret

_call_pop_empty:
    pop     eax
    ret

# ============================================================================
# wasm_exec_func_body: 内部函数执行（用于 OP_CALL 嵌套调用）
# 输入：eax = 函数索引
# ============================================================================
    .globl  wasm_exec_func_body
wasm_exec_func_body:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 检查函数索引合法性
    cmp     eax, [wasm_func_count]
    jae     exec_body_err

    # 获取代码体指针和大小
    mov     ebx, eax
    shl     ebx, 3
    mov     esi, [wasm_code_table + ebx]
    mov     ecx, [wasm_code_table + ebx + 4]

    # 设置新的代码范围
    mov     [wasm_pc], esi
    lea     edx, [esi + ecx]
    mov     [wasm_code_end], edx

    # 跳过局部变量声明
    call    _read_leb128_vm
    mov     edx, eax              # edx = 局部变量数量

init_body_locals:
    test    edx, edx
    jz      start_body_exec

    call    _read_leb128_vm       # 数量
    call    _read_leb128_vm       # 类型
    dec     edx
    jmp     init_body_locals

start_body_exec:
    mov     byte ptr [wasm_running], 1

body_exec_loop:
    cmp     byte ptr [wasm_running], 0
    je      body_exec_done

    mov     esi, [wasm_pc]
    cmp     esi, [wasm_code_end]
    jae     body_exec_done

    movzx   ebx, byte ptr [esi]
    inc     esi
    mov     [wasm_pc], esi

    call    _dispatch_opcode

    jmp     body_exec_loop

body_exec_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

exec_body_err:
    mov     eax, -1
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# 栈操作函数
# ============================================================================
# _stack_push: 压栈
# 输入：eax = 值
_stack_push:
    push    ebx
    mov     ebx, [wasm_stack_top]
    mov     [wasm_operand_stack + ebx * 4], eax
    inc     dword ptr [wasm_stack_top]
    pop     ebx
    ret

# _stack_pop: 出栈
# 输出：eax = 值
_stack_pop:
    push    ebx
    mov     ebx, [wasm_stack_top]
    test    ebx, ebx
    jz      stack_empty_pop
    dec     ebx
    mov     eax, [wasm_operand_stack + ebx * 4]
    mov     [wasm_stack_top], ebx
    pop     ebx
    ret
stack_empty_pop:
    xor     eax, eax
    pop     ebx
    ret

# _stack_top: 获取栈顶值（不出栈）
# 输出：eax = 值
_stack_top:
    push    ebx
    mov     ebx, [wasm_stack_top]
    test    ebx, ebx
    jz      stack_empty_top
    dec     ebx
    mov     eax, [wasm_operand_stack + ebx * 4]
    pop     ebx
    ret
stack_empty_top:
    xor     eax, eax
    pop     ebx
    ret

# ============================================================================
# _read_leb128_vm: 从当前 PC 读取 LEB128
# 输出：eax = 值, 更新 wasm_pc
# ============================================================================
_read_leb128_vm:
    push    ebx
    push    ecx

    mov     esi, [wasm_pc]

    xor     eax, eax
    xor     ebx, ebx
    mov     ecx, 5

read_leb_vm_byte:
    movzx   edx, byte ptr [esi]
    inc     esi

    and     edx, 0x7F
    push    ecx
    mov     ecx, ebx
    shl     edx, cl
    pop     ecx
    or      eax, edx

    movzx   edx, byte ptr [esi - 1]
    test    edx, 0x80
    jz      read_leb_vm_done

    add     ebx, 7
    dec     ecx
    jnz     read_leb_vm_byte

    mov     eax, -1

read_leb_vm_done:
    mov     [wasm_pc], esi
    pop     ecx
    pop     ebx
    ret
