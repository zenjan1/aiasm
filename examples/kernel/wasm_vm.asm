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

# f32 运算
OP_F32_ABS       = 0x8B
OP_F32_NEG       = 0x8C
OP_F32_CEIL      = 0x8D
OP_F32_FLOOR     = 0x8E
OP_F32_TRUNC     = 0x8F
OP_F32_NEAREST   = 0x90
OP_F32_SQRT      = 0x91
OP_F32_ADD       = 0x92
OP_F32_SUB       = 0x93
OP_F32_MUL       = 0x94
OP_F32_DIV       = 0x95
OP_F32_MIN       = 0x96
OP_F32_MAX       = 0x97
OP_F32_COPYSIGN  = 0x98

# f64 运算
OP_F64_ABS       = 0x99
OP_F64_NEG       = 0x9A
OP_F64_CEIL      = 0x9B
OP_F64_FLOOR     = 0x9C
OP_F64_TRUNC     = 0x9D
OP_F64_NEAREST   = 0x9E
OP_F64_SQRT      = 0x9F
OP_F64_ADD       = 0xA0
OP_F64_SUB       = 0xA1
OP_F64_MUL       = 0xA2
OP_F64_DIV       = 0xA3
OP_F64_MIN       = 0xA4
OP_F64_MAX       = 0xA5
OP_F64_COPYSIGN  = 0xA6

# i32/i64 转换
OP_I32_WRAP_I64  = 0xA7
OP_I32_TRUNC_F32_S = 0xA8
OP_I32_TRUNC_F32_U = 0xA9
OP_I32_TRUNC_F64_S = 0xAA
OP_I32_TRUNC_F64_U = 0xAB
OP_I64_EXTEND_I32_S = 0xAC
OP_I64_EXTEND_I32_U = 0xAD
OP_I64_TRUNC_F32_S = 0xAE
OP_I64_TRUNC_F32_U = 0xAF
OP_I64_TRUNC_F64_S = 0xB0
OP_I64_TRUNC_F64_U = 0xB1
OP_F32_CONVERT_I32_S = 0xB2
OP_F32_CONVERT_I32_U = 0xB3
OP_F32_CONVERT_I64_S = 0xB4
OP_F32_CONVERT_I64_U = 0xB5
OP_F32_DEMOTE_F64   = 0xB6
OP_F64_CONVERT_I32_S = 0xB7
OP_F64_CONVERT_I32_U = 0xB8
OP_F64_CONVERT_I64_S = 0xB9
OP_F64_CONVERT_I64_U = 0xBA
OP_F64_PROMOTE_F32  = 0xBB

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
WASM_HOST_NET_SEND   = 8
WASM_HOST_NET_RECV   = 9
WASM_HOST_NET_STATUS = 10
WASM_HOST_NET_CONFIG = 11

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

    # 线性内存（1MB = 16 页，支持动态扩展）
    .globl  wasm_linear_memory
wasm_linear_memory:
    .space  1048576             # 1MB

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

    # 临时变量（宿主函数调用参数暂存）
wasm_host_id_tmp:
    .space  4                   # 保存 host function ID
wasm_param_ptr:
    .space  4                   # 保存 ptr 参数
wasm_param_len:
    .space  4                   # 保存 len 参数
wasm_saved_ret_addr:
    .space  4                   # 保存 wasm_exec_func 的返回地址
wasm_dispatch_ret_addr:
    .space  4                   # 保存 _dispatch_opcode 的返回地址

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
    mov     ecx, 1048576 / 4
    rep     stosd

    # 初始化指针
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    mov     dword ptr [wasm_memory_pages], 16   # 16 页 = 1MB
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
    push    ebp

    mov     ecx, [wasm_data_count]
    test    ecx, ecx
    jz      load_data_done_ok

    mov     ebp, offset wasm_data_table   # ebp = 数据段表基址

load_data_segment:
    test    ecx, ecx
    jz      load_data_done_ok

    # 读取：偏移(4) + 大小(4) + 数据指针(4) = 12 字节/条目
    mov     eax, [ebp]            # 偏移
    mov     ebx, [ebp + 4]        # 大小
    mov     esi, [ebp + 8]        # 数据源指针

    # 检查是否超出线性内存
    mov     edx, [wasm_memory_pages]
    shl     edx, 16               # edx = 当前内存总大小
    mov     edi, eax
    add     edi, ebx              # edi = 偏移 + 数据大小
    cmp     edi, edx
    ja      load_data_overflow

    # 复制数据到线性内存
    mov     edi, offset wasm_linear_memory
    add     edi, eax              # 目标地址

    push    ecx                   # 保存段计数器
    mov     ecx, ebx              # ecx = 字节数
    rep     movsb
    pop     ecx

    add     ebp, 12               # 下一个数据段条目
    dec     ecx
    jmp     load_data_segment

load_data_done_ok:
    xor     eax, eax
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

load_data_overflow:
    mov     eax, 1
    pop     ebp
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
    # Save return address (at [esp+20] after 5 pushes)
    mov     ecx, [esp + 20]
    mov     [wasm_saved_ret_addr], ecx

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

    # 同步线性内存页数：如果模块声明了最小页数，使用它
    mov     eax, [wasm_memory_min]
    test    eax, eax
    jz      .skip_memory_sync
    mov     [wasm_memory_pages], eax
.skip_memory_sync:

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
    # Save return address BEFORE call (avoid stack corruption during call)
    lea     edx, [.ret_save]
    mov     [wasm_dispatch_ret_addr], edx
.ret_save:
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
    # Restore saved return address (it got corrupted during WASM execution)
    mov     ecx, [wasm_saved_ret_addr]
    mov     [esp], ecx
    mov     eax, [wasm_return_value]  # 加载返回值到 eax
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
    cmp     ebx, OP_CALL_INDIRECT
    je      do_call_indirect

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
    cmp     ebx, OP_I64_LOAD
    je      do_i64_load
    cmp     ebx, OP_F32_LOAD
    je      do_f32_load
    cmp     ebx, OP_F64_LOAD
    je      do_f64_load
    cmp     ebx, OP_I32_LOAD8_S
    je      do_i32_load8_s
    cmp     ebx, OP_I32_LOAD8_U
    je      do_i32_load8_u
    cmp     ebx, OP_I32_LOAD16_S
    je      do_i32_load16_s
    cmp     ebx, OP_I32_LOAD16_U
    je      do_i32_load16_u
    cmp     ebx, OP_I64_LOAD8_S
    je      do_i64_load8_s
    cmp     ebx, OP_I64_LOAD8_U
    je      do_i64_load8_u
    cmp     ebx, OP_I64_LOAD16_S
    je      do_i64_load16_s
    cmp     ebx, OP_I64_LOAD16_U
    je      do_i64_load16_u
    cmp     ebx, OP_I64_LOAD32_S
    je      do_i64_load32_s
    cmp     ebx, OP_I64_LOAD32_U
    je      do_i64_load32_u
    cmp     ebx, OP_I32_STORE
    je      do_i32_store
    cmp     ebx, OP_I64_STORE
    je      do_i64_store
    cmp     ebx, OP_F32_STORE
    je      do_f32_store
    cmp     ebx, OP_F64_STORE
    je      do_f64_store
    cmp     ebx, OP_I32_STORE8
    je      do_i32_store8
    cmp     ebx, OP_I32_STORE16
    je      do_i32_store16
    cmp     ebx, OP_I64_STORE8
    je      do_i64_store8
    cmp     ebx, OP_I64_STORE16
    je      do_i64_store16
    cmp     ebx, OP_I64_STORE32
    je      do_i64_store32
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
    cmp     ebx, OP_I32_CLZ
    je      do_i32_clz
    cmp     ebx, OP_I32_CTZ
    je      do_i32_ctz
    cmp     ebx, OP_I32_POPCNT
    je      do_i32_popcnt
    cmp     ebx, OP_I32_ROTL
    je      do_i32_rotl
    cmp     ebx, OP_I32_ROTR
    je      do_i32_rotr

    # i64 比较
    cmp     ebx, OP_I64_EQZ
    je      do_i64_eqz
    cmp     ebx, OP_I64_EQ
    je      do_i64_eq
    cmp     ebx, OP_I64_NE
    je      do_i64_ne
    cmp     ebx, OP_I64_LT_S
    je      do_i64_lt_s
    cmp     ebx, OP_I64_LT_U
    je      do_i64_lt_u
    cmp     ebx, OP_I64_GT_S
    je      do_i64_gt_s
    cmp     ebx, OP_I64_GT_U
    je      do_i64_gt_u
    cmp     ebx, OP_I64_LE_S
    je      do_i64_le_s
    cmp     ebx, OP_I64_LE_U
    je      do_i64_le_u
    cmp     ebx, OP_I64_GE_S
    je      do_i64_ge_s
    cmp     ebx, OP_I64_GE_U
    je      do_i64_ge_u

    # i64 算术
    cmp     ebx, OP_I64_ADD
    je      do_i64_add
    cmp     ebx, OP_I64_SUB
    je      do_i64_sub
    cmp     ebx, OP_I64_MUL
    je      do_i64_mul
    cmp     ebx, OP_I64_DIV_S
    je      do_i64_div_s
    cmp     ebx, OP_I64_DIV_U
    je      do_i64_div_u
    cmp     ebx, OP_I64_REM_S
    je      do_i64_rem_s
    cmp     ebx, OP_I64_REM_U
    je      do_i64_rem_u
    cmp     ebx, OP_I64_AND
    je      do_i64_and
    cmp     ebx, OP_I64_OR
    je      do_i64_or
    cmp     ebx, OP_I64_XOR
    je      do_i64_xor
    cmp     ebx, OP_I64_SHL
    je      do_i64_shl
    cmp     ebx, OP_I64_SHR_S
    je      do_i64_shr_s
    cmp     ebx, OP_I64_SHR_U
    je      do_i64_shr_u
    cmp     ebx, OP_I64_CLZ
    je      do_i64_clz
    cmp     ebx, OP_I64_CTZ
    je      do_i64_ctz
    cmp     ebx, OP_I64_POPCNT
    je      do_i64_popcnt
    cmp     ebx, OP_I64_ROTL
    je      do_i64_rotl
    cmp     ebx, OP_I64_ROTR
    je      do_i64_rotr

    # i64 常量
    cmp     ebx, OP_I64_CONST
    je      do_i64_const

    # f32/f64 常量和运算
    cmp     ebx, OP_F32_CONST
    je      do_f32_const
    cmp     ebx, OP_F64_CONST
    je      do_f64_const
    cmp     ebx, OP_F32_ADD
    je      do_f32_add
    cmp     ebx, OP_F32_SUB
    je      do_f32_sub
    cmp     ebx, OP_F32_MUL
    je      do_f32_mul
    cmp     ebx, OP_F32_DIV
    je      do_f32_div
    cmp     ebx, OP_F64_ADD
    je      do_f64_add
    cmp     ebx, OP_F64_SUB
    je      do_f64_sub
    cmp     ebx, OP_F64_MUL
    je      do_f64_mul
    cmp     ebx, OP_F64_DIV
    je      do_f64_div

    # f32/f64 数学函数
    cmp     ebx, OP_F32_ABS
    je      do_f32_abs
    cmp     ebx, OP_F32_NEG
    je      do_f32_neg
    cmp     ebx, OP_F32_SQRT
    je      do_f32_sqrt
    cmp     ebx, OP_F64_ABS
    je      do_f64_abs
    cmp     ebx, OP_F64_NEG
    je      do_f64_neg
    cmp     ebx, OP_F64_SQRT
    je      do_f64_sqrt

    # f32/f64 舍入函数
    cmp     ebx, OP_F32_CEIL
    je      do_f32_ceil
    cmp     ebx, OP_F32_FLOOR
    je      do_f32_floor
    cmp     ebx, OP_F32_TRUNC
    je      do_f32_trunc
    cmp     ebx, OP_F32_NEAREST
    je      do_f32_nearest
    cmp     ebx, OP_F64_CEIL
    je      do_f64_ceil
    cmp     ebx, OP_F64_FLOOR
    je      do_f64_floor
    cmp     ebx, OP_F64_TRUNC
    je      do_f64_trunc
    cmp     ebx, OP_F64_NEAREST
    je      do_f64_nearest

    # f32/f64 min/max/copysign
    cmp     ebx, OP_F32_MIN
    je      do_f32_min
    cmp     ebx, OP_F32_MAX
    je      do_f32_max
    cmp     ebx, OP_F32_COPYSIGN
    je      do_f32_copysign
    cmp     ebx, OP_F64_MIN
    je      do_f64_min
    cmp     ebx, OP_F64_MAX
    je      do_f64_max
    cmp     ebx, OP_F64_COPYSIGN
    je      do_f64_copysign

    # i32/i64 转换
    cmp     ebx, OP_I32_WRAP_I64
    je      do_i32_wrap_i64
    cmp     ebx, OP_I64_EXTEND_I32_S
    je      do_i64_extend_i32_s
    cmp     ebx, OP_I64_EXTEND_I32_U
    je      do_i64_extend_i32_u

    # f32/f64 转换
    cmp     ebx, OP_I32_TRUNC_F32_S
    je      do_i32_trunc_f32_s
    cmp     ebx, OP_I32_TRUNC_F32_U
    je      do_i32_trunc_f32_u
    cmp     ebx, OP_I32_TRUNC_F64_S
    je      do_i32_trunc_f64_s
    cmp     ebx, OP_I32_TRUNC_F64_U
    je      do_i32_trunc_f64_u
    cmp     ebx, OP_I64_TRUNC_F32_S
    je      do_i64_trunc_f32_s
    cmp     ebx, OP_I64_TRUNC_F32_U
    je      do_i64_trunc_f32_u
    cmp     ebx, OP_I64_TRUNC_F64_S
    je      do_i64_trunc_f64_s
    cmp     ebx, OP_I64_TRUNC_F64_U
    je      do_i64_trunc_f64_u
    cmp     ebx, OP_F32_CONVERT_I32_S
    je      do_f32_convert_i32_s
    cmp     ebx, OP_F32_CONVERT_I32_U
    je      do_f32_convert_i32_u
    cmp     ebx, OP_F32_CONVERT_I64_S
    je      do_f32_convert_i64_s
    cmp     ebx, OP_F32_CONVERT_I64_U
    je      do_f32_convert_i64_u
    cmp     ebx, OP_F32_DEMOTE_F64
    je      do_f32_demote_f64
    cmp     ebx, OP_F64_CONVERT_I32_S
    je      do_f64_convert_i32_s
    cmp     ebx, OP_F64_CONVERT_I32_U
    je      do_f64_convert_i32_u
    cmp     ebx, OP_F64_CONVERT_I64_S
    je      do_f64_convert_i64_s
    cmp     ebx, OP_F64_CONVERT_I64_U
    je      do_f64_convert_i64_u
    cmp     ebx, OP_F64_PROMOTE_F32
    je      do_f64_promote_f32

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
    push    eax
    call    _ctrl_frame_pop
    pop     eax
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
    # 读取第 edx 个 label，同时递减 ecx 跟踪剩余数量
    # 注意：_read_leb128_vm 会破坏 edx，需要先保存
    test    edx, edx
    jz      .br_table_target_found
    push    edx                   # 保存 index
    call    _read_leb128_vm       # 跳过一个 label（clobbers edx）
    pop     edx                   # 恢复 index
    dec     edx
    dec     ecx                   # 剩余数量 -1
    jmp     .br_table_in_range

.br_table_target_found:
    call    _read_leb128_vm       # 读取目标 label
    mov     ebx, eax              # ebx = target label
    # 跳过剩余 labels 和 default
    # 此时 ecx = 剩余未读的 label 数量
    # 需要跳过 ecx 个 label + 1 个 default = ecx + 1 个 LEB128
    inc     ecx                   # +1 for default
.br_table_skip_rest:
    test    ecx, ecx
    jz      .br_table_execute
    call    _read_leb128_vm       # 跳过
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
    cmp     ecx, WASM_HOST_NET_STATUS
    je      .host_0arg
    cmp     ecx, WASM_HOST_NET_CONFIG
    je      .host_1arg
    cmp     ecx, WASM_HOST_NET_RECV
    je      .host_3arg
    cmp     ecx, WASM_HOST_NET_SEND
    je      .host_5arg
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
    jmp     .do_host_call
.host_3arg:
    call    _stack_pop           # 参数3 (maxlen)
    mov     edx, eax
    call    _stack_pop           # 参数2 (ptr)
    mov     ecx, eax
    call    _stack_pop           # 参数1 (type)
    mov     ebx, eax
    pop     eax
    jmp     .do_host_call
.host_5arg:
    # 5参数：type, dst_ip, dst_port, ptr, len
    # 先保存host_id（从x86栈顶pop），然后从WASM操作数栈pop 5个参数
    pop     dword ptr [wasm_host_id_tmp]  # host_id → 内存
    call    _stack_pop           # 参数5 (len)
    mov     [wasm_param_len], eax
    call    _stack_pop           # 参数4 (ptr)
    mov     [wasm_param_ptr], eax
    call    _stack_pop           # 参数3 (dst_port)
    mov     edx, eax
    call    _stack_pop           # 参数2 (dst_ip)
    mov     ecx, eax
    call    _stack_pop           # 参数1 (type)
    mov     ebx, eax
    # 把ptr和len压入x86栈（供wasm_host_call通过[ebp+16/20]访问）
    push    dword ptr [wasm_param_len]
    push    dword ptr [wasm_param_ptr]
    # 恢复host_id到eax
    mov     eax, [wasm_host_id_tmp]
    jmp     .do_host_call
.do_host_call:
    call    wasm_host_call
    # 返回值压入操作数栈
    push    eax
    call    _stack_push
    pop     eax
    jmp     dispatch_done

# ============================================================================
# call_indirect: 通过表间接调用函数
# 格式: call_indirect type_index table_index
# 执行: pop index, table[index] -> func_idx, call func_idx
# ============================================================================
do_call_indirect:
    push    ebx
    push    ecx
    push    edx
    push    ebp                   # 保存 ebp 用于临时存储

    # 读取 type index（用于类型检查）
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    mov     ebp, eax              # ebp = 期望的 type_index

    # 读取 table index（暂时只支持 table 0）
    mov     esi, [wasm_pc]
    call    _read_leb128_vm
    # eax = table index (should be 0)

    # 弹出表索引（函数索引在表中的位置）
    call    _stack_pop           # eax = 表内索引

    # 检查索引是否在表范围内
    cmp     eax, [wasm_table_size]
    jae     .call_indirect_out_of_range

    # 从 wasm_table_entries 获取函数索引
    mov     ebx, eax
    shl     ebx, 2               # * 4
    mov     eax, [wasm_table_entries + ebx]
    mov     edx, eax             # edx = 函数索引（保存）

    # 检查是否为有效函数索引（WASM 函数）
    cmp     eax, [wasm_func_count]
    jae     .call_indirect_host

    # ===== 类型签名检查 =====
    # 获取函数的类型索引：wasm_func_table[func_idx * 4]
    mov     ebx, eax
    shl     ebx, 2
    mov     ecx, [wasm_func_table + ebx]  # ecx = 函数的 type_index
    # 全签名比较：期望 type_index (ebp) vs 实际 type_index (ecx)
    mov     eax, ebp              # eax = expected type_index
    mov     ebx, ecx              # ebx = actual type_index
    call    wasm_type_sig_match
    test    eax, eax
    jnz     .call_indirect_type_mismatch

    # 类型匹配，直接调用函数
    push    edx                  # 保存函数索引
    mov     esi, [wasm_pc]       # esi = 返回地址
    call    _call_frame_push
    pop     eax
    call    wasm_exec_func_body
    push    eax
    call    _stack_push
    pop     eax
    jmp     .call_indirect_done

.call_indirect_host:
    # 间接调用宿主函数
    sub     eax, [wasm_func_count]    # eax = host slot
    mov     ecx, eax
    push    eax
    # 宿主函数参数处理（简化：假设 1 个参数）
    call    _stack_pop
    mov     ebx, eax
    xor     ecx, ecx
    xor     edx, edx
    pop     eax
    call    wasm_host_call
    push    eax
    call    _stack_push
    pop     eax
    jmp     .call_indirect_done

.call_indirect_out_of_range:
    # 表索引超出范围，返回错误
    mov     eax, -1
    call    _stack_push
    jmp     .call_indirect_done

.call_indirect_type_mismatch:
    # 类型不匹配，触发 unreachable trap
    mov     dword ptr [wasm_exec_error], 1
    jmp     .call_indirect_done

.call_indirect_done:
    pop     ebp
    pop     edx
    pop     ecx
    pop     ebx
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

# 内存操作（含对齐检查）
# align 参数是 log2(对齐字节数)，如 align=2 表示 4 字节对齐
# 检查: (effective_address & ((1 << align) - 1)) == 0，否则 trap

do_i32_load:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align (log2)
    mov     ecx, eax             # ecx = align log2
    call    _read_leb128_vm  # offset
    mov     ebx, eax             # ebx = offset
    call    _stack_pop           # eax = address
    add     eax, ebx
    # 对齐检查: if align != 0, check (addr & ((1<<align)-1)) == 0
    test    ecx, ecx
    jz      .load_skip_align
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .load_align_fail
.load_skip_align:
    mov     eax, [wasm_linear_memory + eax]
    call    _stack_push
    jmp     dispatch_done
.load_align_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i32_store:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align (log2)
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop           # eax = value
    mov     edx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    test    ecx, ecx
    jz      .store_skip_align
    mov     esi, 1
    shl     esi, cl
    dec     esi
    test    eax, esi
    jnz     .store_align_fail
.store_skip_align:
    mov     [wasm_linear_memory + eax], edx
    jmp     dispatch_done
.store_align_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

# byte 和 word 存取（含对齐检查）
do_i32_load8_s:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align (log2)
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    test    ecx, ecx
    jz      .load8s_skip_align
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .load8s_align_fail
.load8s_skip_align:
    movzx   eax, byte ptr [wasm_linear_memory + eax]
    # sign extend
    test    eax, 0x80
    jz      .load8s_ok
    or      eax, 0xFFFFFF00
.load8s_ok:
    call    _stack_push
    jmp     dispatch_done
.load8s_align_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i32_load8_u:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align (log2)
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    test    ecx, ecx
    jz      .load8u_skip_align
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .load8u_align_fail
.load8u_skip_align:
    movzx   eax, byte ptr [wasm_linear_memory + eax]
    call    _stack_push
    jmp     dispatch_done
.load8u_align_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i32_load16_s:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align (log2)
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    test    ecx, ecx
    jz      .load16s_skip_align
    cmp     ecx, 1
    jb      .load16s_skip_align  # align=0: any alignment ok
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .load16s_align_fail
.load16s_skip_align:
    movzx   eax, word ptr [wasm_linear_memory + eax]
    test    eax, 0x8000
    jz      .load16s_ok
    or      eax, 0xFFFF0000
.load16s_ok:
    call    _stack_push
    jmp     dispatch_done
.load16s_align_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i32_load16_u:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align (log2)
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    test    ecx, ecx
    jz      .load16u_skip_align
    cmp     ecx, 1
    jb      .load16u_skip_align
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .load16u_align_fail
.load16u_skip_align:
    movzx   eax, word ptr [wasm_linear_memory + eax]
    call    _stack_push
    jmp     dispatch_done
.load16u_align_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i32_store8:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align (log2)
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop           # eax = value
    mov     edx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    test    ecx, ecx
    jz      .store8_skip_align
    mov     esi, 1
    shl     esi, cl
    dec     esi
    test    eax, esi
    jnz     .store8_align_fail
.store8_skip_align:
    mov     [wasm_linear_memory + eax], dl
    jmp     dispatch_done
.store8_align_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i32_store16:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align (log2)
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop           # eax = value
    mov     edx, eax
    call    _stack_pop           # eax = address
    add     eax, ebx
    test    ecx, ecx
    jz      .store16_skip_align
    cmp     ecx, 1
    jb      .store16_skip_align
    mov     esi, 1
    shl     esi, cl
    dec     esi
    test    eax, esi
    jnz     .store16_align_fail
.store16_skip_align:
    mov     [wasm_linear_memory + eax], dx
    jmp     dispatch_done
.store16_align_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

# i64 内存操作（含对齐检查）
do_i64_load:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align (log2)
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64l_skip_align
    cmp     ecx, 3
    jb      .i64l_skip_align
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .i64l_align_fail
.i64l_skip_align:
    mov     edx, [wasm_linear_memory + eax]
    mov     eax, [wasm_linear_memory + eax + 4]
    call    _stack_push
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64l_align_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_load8_s:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64l8s_skip
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .i64l8s_fail
.i64l8s_skip:
    movzx   eax, byte ptr [wasm_linear_memory + eax]
    test    eax, 0x80
    jz      .i64l8s_ok
    or      eax, 0xFFFFFF00
.i64l8s_ok:
    xor     edx, edx
    test    eax, eax
    jns     .i64l8s_pos
    mov     edx, -1
.i64l8s_pos:
    call    _stack_push
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64l8s_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_load8_u:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64l8u_skip
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .i64l8u_fail
.i64l8u_skip:
    movzx   eax, byte ptr [wasm_linear_memory + eax]
    xor     edx, edx
    call    _stack_push
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64l8u_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_load16_s:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64l16s_skip
    cmp     ecx, 1
    jb      .i64l16s_skip
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .i64l16s_fail
.i64l16s_skip:
    movzx   eax, word ptr [wasm_linear_memory + eax]
    test    eax, 0x8000
    jz      .i64l16s_ok
    or      eax, 0xFFFF0000
.i64l16s_ok:
    xor     edx, edx
    test    eax, eax
    jns     .i64l16s_pos
    mov     edx, -1
.i64l16s_pos:
    call    _stack_push
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64l16s_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_load16_u:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64l16u_skip
    cmp     ecx, 1
    jb      .i64l16u_skip
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .i64l16u_fail
.i64l16u_skip:
    movzx   eax, word ptr [wasm_linear_memory + eax]
    xor     edx, edx
    call    _stack_push
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64l16u_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_load32_s:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64l32s_skip
    cmp     ecx, 2
    jb      .i64l32s_skip
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .i64l32s_fail
.i64l32s_skip:
    mov     eax, [wasm_linear_memory + eax]
    xor     edx, edx
    test    eax, eax
    jns     .i64l32s_pos
    mov     edx, -1
.i64l32s_pos:
    call    _stack_push
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64l32s_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_load32_u:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64l32u_skip
    cmp     ecx, 2
    jb      .i64l32u_skip
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .i64l32u_fail
.i64l32u_skip:
    mov     eax, [wasm_linear_memory + eax]
    xor     edx, edx
    call    _stack_push
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64l32u_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_store:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    mov     edx, eax
    pop     eax
    push    edx
    call    _stack_pop
    add     eax, ebx
    pop     edx
    test    ecx, ecx
    jz      .i64s_skip
    cmp     ecx, 3
    jb      .i64s_skip
    mov     esi, 1
    shl     esi, cl
    dec     esi
    test    eax, esi
    jnz     .i64s_fail
.i64s_skip:
    mov     [wasm_linear_memory + eax], eax
    mov     [wasm_linear_memory + eax + 4], edx
    jmp     dispatch_done
.i64s_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_store8:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64s8_skip
    mov     esi, 1
    shl     esi, cl
    dec     esi
    test    eax, esi
    jnz     .i64s8_fail
.i64s8_skip:
    mov     [wasm_linear_memory + eax], dl
    jmp     dispatch_done
.i64s8_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_store16:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64s16_skip
    cmp     ecx, 1
    jb      .i64s16_skip
    mov     esi, 1
    shl     esi, cl
    dec     esi
    test    eax, esi
    jnz     .i64s16_fail
.i64s16_skip:
    mov     [wasm_linear_memory + eax], dx
    jmp     dispatch_done
.i64s16_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_i64_store32:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .i64s32_skip
    cmp     ecx, 2
    jb      .i64s32_skip
    mov     esi, 1
    shl     esi, cl
    dec     esi
    test    eax, esi
    jnz     .i64s32_fail
.i64s32_skip:
    mov     [wasm_linear_memory + eax], edx
    jmp     dispatch_done
.i64s32_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

# f32/f64 内存操作（含对齐检查）
do_f32_load:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .f32l_skip
    cmp     ecx, 2
    jb      .f32l_skip
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .f32l_fail
.f32l_skip:
    mov     eax, [wasm_linear_memory + eax]
    call    _stack_push
    jmp     dispatch_done
.f32l_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_f32_store:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .f32s_skip
    cmp     ecx, 2
    jb      .f32s_skip
    mov     esi, 1
    shl     esi, cl
    dec     esi
    test    eax, esi
    jnz     .f32s_fail
.f32s_skip:
    mov     [wasm_linear_memory + eax], edx
    jmp     dispatch_done
.f32s_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_f64_load:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    add     eax, ebx
    test    ecx, ecx
    jz      .f64l_skip
    cmp     ecx, 3
    jb      .f64l_skip
    mov     edx, 1
    shl     edx, cl
    dec     edx
    test    eax, edx
    jnz     .f64l_fail
.f64l_skip:
    mov     edx, [wasm_linear_memory + eax]
    mov     eax, [wasm_linear_memory + eax + 4]
    call    _stack_push
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.f64l_fail:
    mov     dword ptr [wasm_exec_error], 4
    jmp     dispatch_done

do_f64_store:
    mov     esi, [wasm_pc]
    call    _read_leb128_vm  # align
    mov     ecx, eax
    call    _read_leb128_vm  # offset
    mov     ebx, eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    mov     edx, eax
    pop     eax
    push    edx
    call    _stack_pop
    add     eax, ebx
    pop     edx
    test    ecx, ecx
    jz      .f64s_skip
    cmp     ecx, 3
    jb      .f64s_skip
    mov     esi, 1
    shl     esi, cl
    dec     esi
    test    eax, esi
    jnz     .f64s_fail
.f64s_skip:
    mov     [wasm_linear_memory + eax], eax
    mov     [wasm_linear_memory + eax + 4], edx
    jmp     dispatch_done
.f64s_fail:
    mov     dword ptr [wasm_exec_error], 4
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
    cmp     eax, 16               # 最大 4 页 = 1MB（静态分配限制）
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
    call    _read_leb128_s32      # 使用有符号解码器
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

# ============================================================================
# i64 指令实现
# i64 值在 32 位操作数栈上存储为两个连续槽：高 32 位先入栈，低 32 位在栈顶
# ============================================================================

# i64.const: 读取 SLEB128 编码的 64 位常量（最多 10 字节）
do_i64_const:
    mov     esi, [wasm_pc]
    xor     eax, eax
    xor     edx, edx              # edx = high 32 bits
    xor     ebx, ebx              # shift
    mov     ecx, 10               # 最多 10 字节
.i64c_byte:
    movzx   edi, byte ptr [esi]
    inc     esi
    and     edi, 0x7F
    cmp     ebx, 28
    jae     .i64c_high
    push    ecx
    mov     ecx, ebx
    shl     edi, cl
    pop     ecx
    or      eax, edi
    jmp     .i64c_cont
.i64c_high:
    push    ecx
    mov     ecx, ebx
    sub     ecx, 32
    shl     edi, cl
    pop     ecx
    or      edx, edi
    jmp     .i64c_cont
.i64c_cont:
    movzx   edi, byte ptr [esi - 1]
    test    edi, 0x80
    jz      .i64c_done
    add     ebx, 7
    dec     ecx
    jnz     .i64c_byte
.i64c_done:
    # 符号扩展：如果最后字节的 bit 6 为 1，扩展高 32 位
    movzx   edi, byte ptr [esi - 1]
    test    edi, 0x40
    jz      .i64c_no_extend
    # 如果已经读了 >= 63 位，不需要扩展
    cmp     ebx, 63
    jae     .i64c_no_extend
    # 计算需要扩展的位数
    mov     edi, ebx
    add     edi, 7                # edi = 下一位的 shift
    cmp     edi, 64
    jae     .i64c_all_high
    # 高 32 位需要符号扩展
    mov     ecx, edi
    sub     ecx, 32
    jle     .i64c_all_high
    mov     edi, -1
    shl     edi, cl
    or      edx, edi
    jmp     .i64c_no_extend
.i64c_all_high:
    mov     edx, -1
.i64c_no_extend:
    mov     [wasm_pc], esi
    # 推入栈：先高后低
    mov     eax, edx
    call    _stack_push
    mov     eax, eax              # eax already has low 32 bits
    call    _stack_push
    jmp     dispatch_done

# i64.eqz: 弹出 i64，如果为 0 则推入 1，否则 0
do_i64_eqz:
    call    _stack_pop           # low
    mov     ecx, eax
    call    _stack_pop           # high
    or      eax, ecx
    test    eax, edx
    jnz     .i64eqz_ne
    mov     eax, 1
    jmp     .i64eqz_push
.i64eqz_ne:
    xor     eax, eax
.i64eqz_push:
    call    _stack_push
    jmp     dispatch_done

# i64 比较（通用模板）：弹出 b(high,low), a(high,low)，比较后推入 i32 结果
# 使用宏风格内联实现各比较指令
do_i64_eq:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax             # save a_low
    call    _stack_pop           # a_high
    cmp     eax, edx
    jne     .i64cmp_false
    cmp     ebx, ecx
    jne     .i64cmp_false
    mov     eax, 1
    call    _stack_push
    jmp     dispatch_done

do_i64_ne:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    cmp     eax, edx
    jne     .i64cmp_true
    cmp     ebx, ecx
    jne     .i64cmp_true
    mov     eax, 0
    call    _stack_push
    jmp     dispatch_done
.i64cmp_true:
    mov     eax, 1
    call    _stack_push
    jmp     dispatch_done
.i64cmp_false:
    xor     eax, eax
    call    _stack_push
    jmp     dispatch_done

do_i64_lt_s:
    call    _stack_pop
    mov     ecx, eax             # b_low
    call    _stack_pop
    mov     edx, eax             # b_high
    call    _stack_pop
    mov     ebx, eax             # a_low
    call    _stack_pop           # a_high
    cmp     eax, edx
    jl      .i64lt_s_true
    jg      .i64lt_s_false
    cmp     ebx, ecx
.i64lt_s_true:
    jl      .i64cmp_true
.i64lt_s_false:
    mov     eax, 0
    call    _stack_push
    jmp     dispatch_done

do_i64_lt_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    cmp     eax, edx
    jb      .i64cmp_true
    ja      .i64lt_u_false
    cmp     ebx, ecx
    jb      .i64cmp_true
.i64lt_u_false:
    mov     eax, 0
    call    _stack_push
    jmp     dispatch_done

do_i64_gt_s:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    cmp     eax, edx
    jg      .i64cmp_true
    jl      .i64gt_s_false
    cmp     ebx, ecx
    jg      .i64cmp_true
.i64gt_s_false:
    mov     eax, 0
    call    _stack_push
    jmp     dispatch_done

do_i64_gt_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    cmp     eax, edx
    ja      .i64cmp_true
    jb      .i64gt_u_false
    cmp     ebx, ecx
    ja      .i64cmp_true
.i64gt_u_false:
    mov     eax, 0
    call    _stack_push
    jmp     dispatch_done

do_i64_le_s:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    cmp     eax, edx
    jl      .i64cmp_true
    jg      .i64le_s_false
    cmp     ebx, ecx
    jle     .i64cmp_true
.i64le_s_false:
    mov     eax, 0
    call    _stack_push
    jmp     dispatch_done

do_i64_le_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    cmp     eax, edx
    jb      .i64cmp_true
    ja      .i64le_u_false
    cmp     ebx, ecx
    jbe     .i64cmp_true
.i64le_u_false:
    mov     eax, 0
    call    _stack_push
    jmp     dispatch_done

do_i64_ge_s:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    cmp     eax, edx
    jg      .i64cmp_true
    jl      .i64ge_s_false
    cmp     ebx, ecx
    jge     .i64cmp_true
.i64ge_s_false:
    mov     eax, 0
    call    _stack_push
    jmp     dispatch_done

do_i64_ge_u:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    cmp     eax, edx
    ja      .i64cmp_true
    jb      .i64ge_u_false
    cmp     ebx, ecx
    jae     .i64cmp_true
.i64ge_u_false:
    mov     eax, 0
    call    _stack_push
    jmp     dispatch_done

# i64.add: a + b (64-bit)
do_i64_add:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high
    add     ebx, ecx             # low: ebx = a_low + b_low
    adc     eax, edx             # high: eax = a_high + b_high + carry
    # 推入：先 high 后 low
    push    ebx
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# i64.sub: a - b (64-bit)
do_i64_sub:
    call    _stack_pop
    mov     ecx, eax
    call    _stack_pop
    mov     edx, eax
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    sub     ebx, ecx             # low
    sbb     eax, edx             # high
    push    ebx
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# i64.mul: a * b (64-bit × 64-bit → 64-bit 正确实现)
# 4 个 32x32→64 乘法，只保留低 64 位:
#   result[63:0] = (a_low*b_low)[63:0]
#                + ((a_low*b_high)[31:0] << 32)
#                + ((a_high*b_low)[31:0] << 32)
#   a_high*b_high 只影响位 [127:64]，丢弃
do_i64_mul:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high (eax)
    # 保存所有 4 个操作数到栈
    push    eax                  # [esp]    = a_high
    push    ebx                  # [esp+4]  = a_low
    push    ecx                  # [esp+8]  = b_low
    push    edx                  # [esp+12] = b_high
    # Step 1: a_low * b_low → edx:eax
    mov     eax, [esp + 4]
    mul     dword ptr [esp + 8]  # edx:eax = a_low * b_low
    mov     esi, eax             # esi = result_low
    mov     edi, edx             # edi = result_high
    # Step 2: a_low * b_high → edx:eax，只加低 32 位到 result_high
    mov     eax, [esp + 4]
    mul     dword ptr [esp + 12] # edx:eax = a_low * b_high
    add     edi, eax             # edi += (a_low*b_high)低32位
    # edx 对应位 [95:64]，丢弃
    # Step 3: a_high * b_low → edx:eax，只加低 32 位到 result_high
    mov     eax, [esp]
    mul     dword ptr [esp + 8]  # edx:eax = a_high * b_low
    add     edi, eax             # edi += (a_high*b_low)低32位
    # edx 对应位 [95:64]，丢弃
    # Step 4: a_high * b_high → 只影响位 [127:64]，丢弃
    # 清理栈
    add     esp, 16
    mov     eax, esi
    call    _stack_push          # push result_low
    mov     eax, edi
    call    _stack_push          # push result_high
    jmp     dispatch_done

# i64.div_s: 有符号 64 位除法
do_i64_div_s:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high (eax)
    # 立即保存 a_high（后续 cdq/idiv 会破坏 eax/edx）
    push    eax                  # [esp] = a_high
    # 被除数：edx:ebx (high:low)，除数：high:ecx (high:low)
    # 检查高 32 位是否都为 0（小值简化路径）
    mov     eax, [esp]           # eax = a_high
    test    eax, eax
    jnz     .div_s_full
    test    edx, edx             # b_high
    jnz     .div_s_full
    # 简单 32 位有符号除法
    mov     eax, ebx
    cdq
    idiv    ecx                  # eax = a_low / b_low (有符号)
    cdq                          # sign extend to 64-bit
    add     esp, 4               # 清理保存的 a_high
    # 推入商
    push    edx
    mov     eax, eax
    push    eax
    call    _stack_push          # high
    pop     eax
    call    _stack_push          # low
    jmp     dispatch_done
.div_s_full:
    # 完整 64 位有符号除法
    # 保存符号，取绝对值，用无符号除法，最后恢复符号
    mov     esi, [esp]           # esi = a_high (被除数高)
    mov     edi, ebx             # edi = a_low (被除数低)
    # 检查被除数符号
    test    esi, esi
    jns     .div_s_pos_dividend
    # 被除数为负，取反
    not     edi
    not     esi
    add     edi, 1
    adc     esi, 0
    mov     byte ptr [esp + 4], 1  # 标记被除数为负（复用栈上 b_high 位置）
    jmp     .div_s_check_dvsign
.div_s_pos_dividend:
    mov     byte ptr [esp + 4], 0  # 被除数为正
.div_s_check_dvsign:
    # 检查除数符号
    mov     eax, edx             # eax = b_high
    test    eax, eax
    jns     .div_s_pos_divisor
    # 除数为负，取反
    not     ecx
    not     eax
    add     ecx, 1
    adc     eax, 0
    xor     edx, edx             # edx = 0 (divisor high now)
    mov     byte ptr [esp + 5], 1  # 除数为负
    jmp     .div_s_do_unsigned
.div_s_pos_divisor:
    mov     byte ptr [esp + 5], 0  # 除数为正
.div_s_do_unsigned:
    # 现在：被除数 {esi, edi} >= 0, 除数 {edx, ecx} >= 0
    # 如果除数高 32 位为 0，用 64/32 idiv
    test    edx, edx
    jnz     .div_s_64_64
    # 64/32 除法
    test    ecx, ecx
    jz      .div_s_zero
    mov     eax, edi             # eax = dividend_low
    mov     edx, esi             # edx = dividend_high
    div     ecx                  # eax = quotient, edx = remainder
    xor     esi, esi             # quotient_high = 0
    mov     edi, eax             # quotient_low = eax
    jmp     .div_s_apply_sign
.div_s_64_64:
    # 完整 64/64 无符号除法（二进制长除法）
    # 被除数: esi:edi, 除数: edx:ecx
    # 商: edi (结果), 余数: esi
    # 先对齐除数到被除数的最高位
    mov     ebp, 64              # 循环 64 位
    xor     edi, edi             # 商清零
    # 检查除数高 32 位是否为 0（优化路径）
    test    edx, edx
    jz      .div_s_64_32_loop
    # 完整 64 位除数路径
.div_s_64_loop:
    # 被除数左移 1 位（esi:edi），CF 来自最低位
    shl     edi, 1
    rcl     esi, 1
    # 尝试减去除数
    mov     eax, edi
    sub     eax, ecx
    mov     ebx, esi
    sbb     ebx, edx
    # 如果够减
    jnc     .div_s_64_sub
    # 不够减，商位 0
    jmp     .div_s_64_next
.div_s_64_sub:
    mov     edi, eax
    mov     esi, ebx
    or      edi, 1               # 商位 1
.div_s_64_next:
    dec     ebp
    jnz     .div_s_64_loop
    jmp     .div_s_apply_sign
.div_s_64_32_loop:
    # 除数高 32 位为 0，只有低 32 位 (ecx)
    mov     ebp, 64
    xor     edi, edi
.div_s_64_32_iter:
    shl     edi, 1
    rcl     esi, 1
    cmp     esi, ecx
    jb      .div_s_64_32_no_sub
    sub     esi, ecx
    or      edi, 1
.div_s_64_32_no_sub:
    dec     ebp
    jnz     .div_s_64_32_iter
.div_s_apply_sign:
    # esi:edi = 商（无符号）
    # 应用符号：如果被除数和除数符号不同，商为负
    mov     al, [esp + 4]
    mov     bl, [esp + 5]
    xor     al, bl
    test    al, al
    jz      .div_s_pos_result
    # 商为负
    not     edi
    not     esi
    add     edi, 1
    adc     esi, 0
.div_s_pos_result:
    add     esp, 8               # 清理保存的 a_high 和符号标记
    mov     eax, edi
    call    _stack_push          # push quotient_low
    mov     eax, esi
    call    _stack_push          # push quotient_high
    jmp     dispatch_done
.div_s_zero:
    add     esp, 4               # 清理保存的 a_high
    mov     eax, 0xFFFFFFFF      # 除零返回最大值
    call    _stack_push
    call    _stack_push
    jmp     dispatch_done

# i64.div_u: 无符号 64 位除法
do_i64_div_u:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high (eax)
    push    eax                  # [esp] = a_high
    push    ecx                  # [esp+4] = b_low
    push    edx                  # [esp+8] = b_high
    # 检查是否为小值（高 32 位都为 0）
    mov     eax, [esp + 8]       # eax = a_high
    test    eax, eax
    jnz     .div_u_64
    mov     eax, [esp + 4]       # eax = b_high
    test    eax, eax
    jnz     .div_u_64
    # 32/32 除法
    mov     ecx, [esp]           # ecx = b_low
    test    ecx, ecx
    jz      .div_u_zero
    xor     edx, edx
    mov     eax, ebx
    div     ecx
    add     esp, 12
    xor     edx, edx
    call    _stack_push
    mov     eax, eax
    call    _stack_push
    jmp     dispatch_done
.div_u_64:
    # 64/64 无符号除法（二进制恢复法）
    # 余数: esi(high):eax(low), 被除数/商: ebp(high):edi(low)
    # 除数: [esp](low):[esp+4](high)
    mov     edi, ebx             # edi = a_low
    mov     ebp, [esp + 8]       # ebp = a_high
    xor     eax, eax             # eax = remainder_low
    xor     esi, esi             # esi = remainder_high
    mov     ecx, [esp]           # ecx = divisor_low
    mov     edx, [esp + 4]       # edx = divisor_high
    add     esp, 12              # 清理栈
    push    ecx                  # [esp] = divisor_low
    push    edx                  # [esp+4] = divisor_high
    mov     ecx, 64
.div_u_64_loop:
    shl     edi, 1
    rcl     ebp, 1
    rcl     eax, 1
    rcl     esi, 1
    sub     eax, [esp]
    mov     edx, esi
    sbb     edx, [esp + 4]
    jnc     .div_u_64_sub
    add     eax, [esp]
    adc     esi, edx
    jmp     .div_u_64_next
.div_u_64_sub:
    mov     esi, edx
    or      edi, 1
.div_u_64_next:
    dec     ecx
    jnz     .div_u_64_loop
    add     esp, 8
    mov     eax, edi
    call    _stack_push
    mov     eax, ebp
    call    _stack_push
    jmp     dispatch_done
.div_u_zero:
    add     esp, 12
    mov     eax, 0xFFFFFFFF
    call    _stack_push
    call    _stack_push
    jmp     dispatch_done

# i64.rem_s: 有符号 64 位取余
do_i64_rem_s:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high (eax)
    push    eax                  # [esp] = a_high
    # 小值简化路径
    mov     eax, [esp]
    test    eax, eax
    jnz     .rem_s_full
    test    edx, edx             # b_high
    jnz     .rem_s_full
    test    ecx, ecx
    jz      .rem_s_zero
    mov     eax, ebx
    cdq
    idiv    ecx                  # edx = remainder
    cdq
    add     esp, 4
    call    _stack_push          # high
    mov     eax, edx             # low = remainder
    call    _stack_push
    jmp     dispatch_done
.rem_s_full:
    # 64/32 有符号取余: (a_high:a_low) % b_low
    test    ecx, ecx
    jz      .rem_s_zero
    test    edx, edx             # b_high
    jnz     .rem_s_big_divisor
    mov     eax, ebx             # eax = a_low
    mov     edx, [esp]           # edx = a_high
    idiv    ecx                  # edx = remainder
    cdq
    add     esp, 4
    call    _stack_push          # high
    mov     eax, edx             # remainder
    call    _stack_push
    jmp     dispatch_done
.rem_s_big_divisor:
    # 64/64 有符号取余：余数符号与被除数相同
    # 栈：[esp] = a_high，ebx = a_low，edx = b_high，ecx = b_low
    # 保存 dividend 符号，转为绝对值
    push    ebx                  # [esp+4] = a_low
    push    edx                  # [esp+8] = b_high
    push    ecx                  # [esp+12] = b_low
    # 判断被除数符号
    mov     eax, [esp+16]        # eax = a_high
    xor     ebp, ebp             # ebp = 0 (sign flag)
    test    eax, eax
    jns     .rem_s_dividend_pos
    # 被除数为负，取绝对值
    not     ebx                  # a_low
    not     eax                  # a_high
    add     ebx, 1
    adc     eax, 0
    mov     ebp, 1               # sign = negative
    mov     [esp+16], eax        # 更新 a_high
    mov     [esp+4], ebx         # 更新 a_low
.rem_s_dividend_pos:
    # 判断除数符号，转为绝对值
    mov     eax, [esp+8]         # b_high
    test    eax, eax
    jns     .rem_s_divisor_pos
    not     ecx                  # b_low
    not     eax                  # b_high
    add     ecx, 1
    adc     eax, 0
    mov     [esp+8], eax
    mov     [esp+12], ecx
.rem_s_divisor_pos:
    # 检查被除数是否小于除数（此时余数=被除数）
    mov     eax, [esp+16]        # a_high
    cmp     eax, [esp+8]         # a_high vs b_high
    jb      .rem_s_result_is_dividend_abs
    ja      .rem_s_do_unsigned
    mov     eax, [esp+4]         # a_low
    cmp     eax, [esp+12]        # a_low vs b_low
    jb      .rem_s_result_is_dividend_abs
.rem_s_do_unsigned:
    # 运行无符号除法获取 quotient
    mov     esi, [esp+16]        # esi = a_high
    mov     edi, [esp+4]         # edi = a_low
    mov     ebp, 64
.rem_s_64_loop:
    shl     edi, 1
    rcl     esi, 1
    mov     eax, edi
    sub     eax, [esp+12]        # divisor_low
    mov     ebx, esi
    sbb     ebx, [esp+8]         # divisor_high
    jnc     .rem_s_64_sub
    jmp     .rem_s_64_next
.rem_s_64_sub:
    mov     edi, eax
    mov     esi, ebx
    or      edi, 1
.rem_s_64_next:
    dec     ebp
    jnz     .rem_s_64_loop
    # esi:edi = quotient，计算 remainder = dividend - quotient * divisor
    mov     eax, edi
    mul     dword ptr [esp+12]
    mov     ebx, eax
    mov     ecx, edx
    mov     eax, edi
    mul     dword ptr [esp+8]
    add     ecx, eax
    mov     eax, esi
    mul     dword ptr [esp+12]
    add     ecx, eax
    # remainder = dividend - product
    mov     eax, [esp+4]         # dividend_low
    sub     eax, ebx
    mov     ebx, eax
    mov     eax, [esp+16]        # dividend_high
    sbb     eax, ecx
    mov     ecx, eax             # ecx = remainder_high, ebx = remainder_low
    jmp     .rem_s_apply_sign
.rem_s_result_is_dividend_abs:
    mov     ebx, [esp+4]         # remainder_low = a_low
    mov     ecx, [esp+16]        # remainder_high = a_high
.rem_s_apply_sign:
    # 检查原始被除数符号（保存在栈底标记位）
    # 恢复栈并应用符号
    add     esp, 16              # 清理所有 push (但少了原来的 a_high push)
    mov     eax, [esp]           # 原始 a_high (用于判断符号)
    test    eax, eax             # 原始被除数符号
    jns     .rem_s_result_pos
    # 被除数为负，余数也需要为负
    not     ebx
    not     ecx
    add     ebx, 1
    adc     ecx, 0
.rem_s_result_pos:
    add     esp, 4               # 清理原始 a_high push
    mov     eax, ecx
    call    _stack_push          # remainder_high
    mov     eax, ebx
    call    _stack_push          # remainder_low
    jmp     dispatch_done
.rem_s_zero:
    add     esp, 4
    mov     eax, 0xFFFFFFFF
    call    _stack_push
    call    _stack_push
    jmp     dispatch_done

# i64.rem_u: 无符号 64 位取余
do_i64_rem_u:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high (eax)
    push    eax                  # [esp] = a_high
    # 小值简化路径
    mov     eax, [esp]
    test    eax, eax
    jnz     .rem_u_full
    test    edx, edx             # b_high
    jnz     .rem_u_full
    test    ecx, ecx
    jz      .rem_u_zero
    xor     edx, edx
    mov     eax, ebx
    div     ecx                  # edx = remainder
    add     esp, 4
    xor     edx, edx
    call    _stack_push          # high
    mov     eax, edx             # remainder
    call    _stack_push
    jmp     dispatch_done
.rem_u_full:
    # 64/32 无符号取余: (a_high:a_low) % b_low
    test    ecx, ecx
    jz      .rem_u_zero
    test    edx, edx             # b_high
    jnz     .rem_u_big_divisor
    mov     eax, ebx             # eax = a_low
    mov     edx, [esp]           # edx = a_high
    div     ecx                  # edx = remainder
    add     esp, 4
    xor     edx, edx
    call    _stack_push          # high
    mov     eax, edx             # remainder
    call    _stack_push
    jmp     dispatch_done
.rem_u_big_divisor:
    # 完整 64/64 无符号取余：remainder = dividend - quotient * divisor
    # 栈：[esp] = a_high (已push)，ebx = a_low，edx = b_high，ecx = b_low
    # 检查被除数是否小于除数（此时余数=被除数）
    mov     eax, [esp]           # eax = a_high
    cmp     eax, edx             # a_high vs b_high
    jb      .rem_u_result_is_dividend
    ja      .rem_u_do_full_div
    cmp     ebx, ecx             # a_low vs b_low
    jb      .rem_u_result_is_dividend
.rem_u_do_full_div:
    # 被除数 >= 除数，需要做完整除法
    # 保存原始被除数和除数
    push    ebx                  # [esp+4] = a_low
    push    edx                  # [esp+8] = b_high
    push    ecx                  # [esp+12] = b_low
    # 运行二进制长除法
    mov     esi, [esp+16]        # esi = a_high
    mov     edi, ebx             # edi = a_low
    mov     ebp, 64
.rem_u_64_loop:
    shl     edi, 1
    rcl     esi, 1
    mov     eax, edi
    sub     eax, [esp+12]        # compare with divisor_low
    mov     ebx, esi
    sbb     ebx, [esp+8]         # compare with divisor_high
    jnc     .rem_u_64_sub
    jmp     .rem_u_64_next
.rem_u_64_sub:
    mov     edi, eax
    mov     esi, ebx
    or      edi, 1               # quotient bit
.rem_u_64_next:
    dec     ebp
    jnz     .rem_u_64_loop
    # esi:edi = quotient，计算 remainder = dividend - quotient * divisor
    # quotient * divisor (简化：只算低64位，因为余数必定小于除数)
    mov     eax, edi             # quotient_low
    mul     dword ptr [esp+12]   # * divisor_low → edx:eax
    mov     ebx, eax             # product_low
    mov     ecx, edx             # product_high_partial
    mov     eax, edi             # quotient_low
    mul     dword ptr [esp+8]    # * divisor_high
    add     ecx, eax
    mov     eax, esi             # quotient_high
    mul     dword ptr [esp+12]   # * divisor_low
    add     ecx, eax
    # ecx:ebx = product
    # remainder = dividend - product
    mov     eax, [esp+4]         # dividend_low
    sub     eax, ebx
    mov     ebx, eax             # remainder_low
    mov     eax, [esp+16]        # dividend_high
    sbb     eax, ecx             # remainder_high
    add     esp, 16              # 清理 a_high,a_low,b_high,b_low push
    xor     edx, edx
    call    _stack_push          # remainder_high
    mov     eax, ebx
    call    _stack_push          # remainder_low
    jmp     dispatch_done
.rem_u_result_is_dividend:
    # 被除数 < 除数，余数 = 被除数
    add     esp, 4               # 清理 a_high push
    xor     edx, edx
    call    _stack_push          # remainder_high (0)
    mov     eax, ebx             # remainder_low = a_low
    call    _stack_push
    jmp     dispatch_done
.rem_u_zero:
    add     esp, 4
    mov     eax, 0xFFFFFFFF
    call    _stack_push
    call    _stack_push
    jmp     dispatch_done

# i32.clz: 计算前导零的个数
do_i32_clz:
    call    _stack_pop
    test    eax, eax
    jz      .clz_zero
    bsr     ecx, eax             # 找到最高位 1 的位置
    mov     edx, 31
    sub     edx, ecx
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.clz_zero:
    mov     eax, 32
    call    _stack_push
    jmp     dispatch_done

# i32.ctz: 计算尾部零的个数
do_i32_ctz:
    call    _stack_pop
    test    eax, eax
    jz      .ctz_zero
    bsf     ecx, eax             # 找到最低位 1 的位置
    mov     eax, ecx
    call    _stack_push
    jmp     dispatch_done
.ctz_zero:
    mov     eax, 32
    call    _stack_push
    jmp     dispatch_done

# i32.popcnt: 计算 1 的个数
do_i32_popcnt:
    call    _stack_pop
    xor     ecx, ecx
    mov     edx, eax
    test    edx, edx
    jz      .popcnt_done
.popcnt_loop:
    shr     edx, 1
    adc     ecx, 0
    test    edx, edx
    jnz     .popcnt_loop
.popcnt_done:
    mov     eax, ecx
    call    _stack_push
    jmp     dispatch_done

# i32.rotl: 左旋 (value <<< count)
do_i32_rotl:
    call    _stack_pop           # count
    mov     ecx, eax
    and     ecx, 31
    call    _stack_pop           # value
    rol     eax, cl
    call    _stack_push
    jmp     dispatch_done

# i32.rotr: 右旋 (value >>> count)
do_i32_rotr:
    call    _stack_pop           # count
    mov     ecx, eax
    and     ecx, 31
    call    _stack_pop           # value
    ror     eax, cl
    call    _stack_push
    jmp     dispatch_done

# i64.and: {a_high, a_low} & {b_high, b_low}
do_i64_and:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high
    and     eax, edx             # result_high = a_high & b_high
    and     ebx, ecx             # result_low = a_low & b_low
    push    eax
    mov     eax, ebx
    call    _stack_push          # push result_low
    pop     eax
    call    _stack_push          # push result_high
    jmp     dispatch_done

# i64.or
do_i64_or:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high
    or      eax, edx             # result_high = a_high | b_high
    or      ebx, ecx             # result_low = a_low | b_low
    push    eax
    mov     eax, ebx
    call    _stack_push          # push result_low
    pop     eax
    call    _stack_push          # push result_high
    jmp     dispatch_done

# i64.xor
do_i64_xor:
    call    _stack_pop           # b_low
    mov     ecx, eax
    call    _stack_pop           # b_high
    mov     edx, eax
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high
    xor     eax, edx             # result_high = a_high ^ b_high
    xor     ebx, ecx             # result_low = a_low ^ b_low
    push    eax
    mov     eax, ebx
    call    _stack_push          # push result_low
    pop     eax
    call    _stack_push          # push result_high
    jmp     dispatch_done

# i64.shl: a << shift
do_i64_shl:
    call    _stack_pop           # shift (only low 6 bits matter)
    mov     ecx, eax
    and     ecx, 63
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high
    test    ecx, ecx
    jz      .i64shl_done
    cmp     ecx, 32
    jae     .i64shl_big
    # shift < 32: result_high = (a_high << shift) | (a_low >> (32 - shift))
    mov     edx, eax
    shl     edx, cl
    mov     edi, ecx
    mov     eax, ebx
    shr     eax, cl
    or      edx, eax
    shl     ebx, cl               # result_low = a_low << shift
    mov     eax, edx
    jmp     .i64shl_push
.i64shl_big:
    # shift >= 32: result_high = a_low << (shift - 32), result_low = 0
    sub     ecx, 32
    mov     edx, ebx
    shl     edx, cl
    mov     eax, edx
    xor     ebx, ebx
.i64shl_push:
    call    _stack_push           # high
    mov     eax, ebx
    call    _stack_push           # low
    jmp     dispatch_done
.i64shl_done:
    mov     eax, edx             # a_high (already on stack as high)
    call    _stack_push
    mov     eax, ebx             # a_low
    call    _stack_push
    jmp     dispatch_done

# i64.shr_s: 算术右移
do_i64_shr_s:
    call    _stack_pop
    mov     ecx, eax
    and     ecx, 63
    call    _stack_pop
    mov     ebx, eax             # a_low
    call    _stack_pop           # a_high (signed)
    test    ecx, ecx
    jz      .i64sra_done
    cmp     ecx, 32
    jae     .i64sra_big
    mov     edx, eax
    sar     edx, cl              # result_high = a_high >> shift
    mov     edi, ecx
    mov     eax, ebx
    shl     eax, cl
    mov     edi, 32
    sub     edi, ecx
    mov     ecx, edi
    shr     ebx, cl              # result_low = a_low >> shift | (a_high << (32-shift))
    or      ebx, eax
    mov     eax, edx
    call    _stack_push
    mov     eax, ebx
    call    _stack_push
    jmp     dispatch_done
.i64sra_big:
    sub     ecx, 32
    sar     eax, cl              # sign-extend shift from high
    mov     ebx, eax
    xor     eax, eax             # high = 0 (all shifted out)
    sar     eax, 31              # sign extend
    mov     edx, eax
    call    _stack_push
    mov     eax, ebx
    call    _stack_push
    jmp     dispatch_done
.i64sra_done:
    push    eax                  # save a_high
    call    _stack_push          # push high
    pop     eax
    mov     eax, ebx
    call    _stack_push          # push low
    jmp     dispatch_done

# i64.shr_u: 逻辑右移
do_i64_shr_u:
    call    _stack_pop
    mov     ecx, eax
    and     ecx, 63
    call    _stack_pop
    mov     ebx, eax
    call    _stack_pop
    test    ecx, ecx
    jz      .i64srl_done
    cmp     ecx, 32
    jae     .i64srl_big
    mov     edx, eax
    shr     edx, cl
    mov     eax, ebx
    shl     eax, cl
    mov     edi, 32
    sub     edi, ecx
    mov     ecx, edi
    shr     ebx, cl
    or      ebx, eax
    mov     eax, edx
    call    _stack_push
    mov     eax, ebx
    call    _stack_push
    jmp     dispatch_done
.i64srl_big:
    sub     ecx, 32
    shr     eax, cl
    mov     ebx, eax
    xor     eax, eax
    mov     edx, eax
    call    _stack_push
    mov     eax, ebx
    call    _stack_push
    jmp     dispatch_done
.i64srl_done:
    push    eax
    call    _stack_push
    pop     eax
    mov     eax, ebx
    call    _stack_push
    jmp     dispatch_done

# i64.clz: 计算 64 位前导零
do_i64_clz:
    call    _stack_pop           # low
    mov     ecx, eax
    call    _stack_pop           # high
    test    eax, eax
    jnz     .i64clz_high
    # 高 32 位为 0，检查低 32 位
    test    ecx, ecx
    jz      .i64clz_zero
    bsr     edx, ecx
    mov     eax, 63
    sub     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64clz_zero:
    mov     eax, 64              # 全部为 0
    call    _stack_push
    jmp     dispatch_done
.i64clz_high:
    # 高 32 位非 0，找到最高位
    bsr     edx, eax
    mov     eax, 31
    sub     eax, edx
    call    _stack_push
    jmp     dispatch_done

# i64.ctz: 计算 64 位尾随零（返回 i32）
do_i64_ctz:
    call    _stack_pop           # low
    mov     ecx, eax
    call    _stack_pop           # high
    test    ecx, ecx
    jnz     .i64ctz_low
    # 低 32 位为 0，检查高 32 位
    test    eax, eax
    jz      .i64ctz_zero
    bsf     edx, eax
    add     edx, 32
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64ctz_low:
    bsf     edx, ecx
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done
.i64ctz_zero:
    mov     eax, 64
    call    _stack_push
    jmp     dispatch_done

# i64.popcnt: 计算 64 位中 1 的个数（返回 i32）
do_i64_popcnt:
    call    _stack_pop           # low
    mov     ecx, eax
    call    _stack_pop           # high
    xor     edx, edx
    # 计算高 32 位 popcnt
    test    eax, eax
    jz      .i64popcnt_low
.i64popcnt_high:
    shr     eax, 1
    adc     edx, 0
    test    eax, eax
    jnz     .i64popcnt_high
.i64popcnt_low:
    test    ecx, ecx
    jz      .i64popcnt_done
    shr     ecx, 1
    adc     edx, 0
    test    ecx, ecx
    jnz     .i64popcnt_low
.i64popcnt_done:
    mov     eax, edx
    call    _stack_push
    jmp     dispatch_done

# i64.rotl: 64 位左旋 (value <<< count)
do_i64_rotl:
    call    _stack_pop           # count
    mov     ecx, eax
    and     ecx, 63
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high
    # eax=a_high, ebx=a_low, ecx=count
    push    ecx                  # save count on stack (will survive since we clean it)
    test    ecx, ecx
    jz      .i64rotl_noshift
    cmp     ecx, 32
    jae     .i64rotl_big
    # shift < 32:
    #   new_low  = (a_low << count) | (a_high >> (32-count))
    #   new_high = (a_high << count) | (a_low >> (32-count))
    mov     esi, eax             # esi = a_high
    mov     edi, ebx             # edi = a_low
    mov     cl, [esp]            # cl = count
    shl     edi, cl              # edi = a_low << count
    mov     cl, 32
    sub     cl, [esp]
    shr     esi, cl              # esi = a_high >> (32-count)
    or      edi, esi             # edi = new_low
    mov     esi, eax             # esi = a_high
    mov     cl, [esp]
    shl     esi, cl              # esi = a_high << count
    mov     edi, ebx             # edi = a_low
    mov     cl, 32
    sub     cl, [esp]
    shr     edi, cl              # edi = a_low >> (32-count)
    or      esi, edi             # esi = new_high
    pop     ecx                  # clean saved count
    mov     eax, esi             # eax = new_high
    call    _stack_push
    mov     eax, edi             # eax = new_low
    call    _stack_push
    jmp     dispatch_done
.i64rotl_big:
    # shift >= 32: count' = count - 32
    #   new_low  = (a_high << count') | (a_low >> (32-count'))
    #   new_high = (a_low << count') | (a_high >> (32-count'))
    sub     ecx, 32
    push    ecx                  # count'
    mov     esi, eax             # esi = a_high
    mov     edi, ebx             # edi = a_low
    mov     cl, [esp]
    shl     esi, cl              # esi = a_high << count'
    mov     cl, 32
    sub     cl, [esp]
    shr     edi, cl              # edi = a_low >> (32-count')
    or      esi, edi             # esi = new_low
    mov     edi, ebx
    mov     cl, [esp]
    shl     edi, cl              # edi = a_low << count'
    mov     cl, 32
    sub     cl, [esp]
    mov     edx, eax
    shr     edx, cl              # edx = a_high >> (32-count')
    or      edi, edx             # edi = new_high
    pop     ecx                  # clean saved count'
    mov     eax, edi             # eax = new_high
    call    _stack_push
    mov     eax, esi             # eax = new_low
    call    _stack_push
    jmp     dispatch_done
.i64rotl_noshift:
    pop     ecx                  # clean saved count
    call    _stack_push          # push a_high
    mov     eax, ebx
    call    _stack_push          # push a_low
    jmp     dispatch_done

# i64.rotr: 64 位右旋 (value >>> count)
do_i64_rotr:
    call    _stack_pop           # count
    mov     ecx, eax
    and     ecx, 63
    call    _stack_pop           # a_low
    mov     ebx, eax
    call    _stack_pop           # a_high
    # eax=a_high, ebx=a_low, ecx=count
    push    ecx
    test    ecx, ecx
    jz      .i64rotr_noshift
    cmp     ecx, 32
    jae     .i64rotr_big
    # shift < 32:
    #   new_low  = (a_low >> count) | (a_high << (32-count))
    #   new_high = (a_high >> count) | (a_low << (32-count))
    mov     esi, eax             # esi = a_high
    mov     edi, ebx             # edi = a_low
    mov     cl, [esp]
    shr     edi, cl              # edi = a_low >> count
    mov     cl, 32
    sub     cl, [esp]
    shl     esi, cl              # esi = a_high << (32-count)
    or      edi, esi             # edi = new_low
    mov     esi, eax             # esi = a_high
    mov     cl, [esp]
    shr     esi, cl              # esi = a_high >> count
    mov     edi, ebx
    mov     cl, 32
    sub     cl, [esp]
    shl     edi, cl              # edi = a_low << (32-count)
    or      esi, edi             # esi = new_high
    pop     ecx
    mov     eax, esi
    call    _stack_push          # push new_high
    mov     eax, edi
    call    _stack_push          # push new_low
    jmp     dispatch_done
.i64rotr_noshift:
    pop     ecx
    call    _stack_push
    mov     eax, ebx
    call    _stack_push
    jmp     dispatch_done
.i64rotr_big:
    # shift >= 32: count' = count - 32
    #   new_low  = (a_high >> count') | (a_low << (32-count'))
    #   new_high = (a_low >> count') | (a_high << (32-count'))
    sub     ecx, 32
    push    ecx
    # new_low first
    mov     esi, eax             # esi = a_high
    mov     edi, ebx             # edi = a_low
    mov     cl, [esp]
    shr     esi, cl              # esi = a_high >> count'
    mov     cl, 32
    sub     cl, [esp]
    shl     edi, cl              # edi = a_low << (32-count')
    or      edi, esi             # edi = new_low
    # new_high
    mov     esi, ebx             # esi = a_low
    mov     cl, [esp]
    shr     esi, cl              # esi = a_low >> count'
    mov     cl, 32
    sub     cl, [esp]
    mov     edx, eax
    shl     edx, cl              # edx = a_high << (32-count')
    or      esi, edx             # esi = new_high
    pop     ecx
    mov     eax, esi
    call    _stack_push          # push new_high
    mov     eax, edi
    call    _stack_push          # push new_low
    jmp     dispatch_done

# i32.wrap/i64: 弹出 i64，推入 i32（截断高 32 位）
do_i32_wrap_i64:
    call    _stack_pop           # low (丢弃 high)
    call    _stack_pop           # high (discard)
    call    _stack_push
    jmp     dispatch_done

# i64.extend/i32_s: 弹出 i32，符号扩展为 i64
do_i64_extend_i32_s:
    call    _stack_pop
    cdq                          # edx = sign extension of eax
    push    eax
    mov     eax, edx
    call    _stack_push           # high
    pop     eax
    call    _stack_push           # low
    jmp     dispatch_done

# i64.extend/i32_u: 弹出 i32，零扩展为 i64
do_i64_extend_i32_u:
    call    _stack_pop
    push    eax
    xor     eax, eax
    call    _stack_push           # high = 0
    pop     eax
    call    _stack_push           # low
    jmp     dispatch_done

# ============================================================================
# f32/f64 浮点运算（使用 x87 FPU）
# ============================================================================

# f32.const: 读取 4 字节浮点数
do_f32_const:
    mov     esi, [wasm_pc]
    mov     eax, [esi]            # 读取 4 字节（浮点数位表示）
    add     esi, 4
    mov     [wasm_pc], esi
    call    _stack_push
    jmp     dispatch_done

# f64.const: 读取 8 字节浮点数（压入 2 个栈槽）
do_f64_const:
    mov     esi, [wasm_pc]
    mov     eax, [esi + 4]        # high 32 bits
    call    _stack_push
    mov     eax, [esi]            # low 32 bits
    call    _stack_push
    add     esi, 8
    mov     [wasm_pc], esi
    jmp     dispatch_done

# f32.add: 弹出两个 f32，相加，压入结果
do_f32_add:
    call    _stack_pop           # b (位表示)
    push    eax
    call    _stack_pop           # a (位表示)
    # 使用 x87 FPU
    mov     dword ptr [esp + 4], eax  # [esp+4] = b
    fld     dword ptr [esp]      # st0 = a (浮点数)
    fadd    dword ptr [esp + 4]  # st0 = a + b
    fstp    dword ptr [esp + 4]  # 存储结果到 [esp+4]
    pop     eax                  # 清理 a
    pop     eax                  # eax = 结果
    call    _stack_push
    jmp     dispatch_done

# f32.sub: 弹出 a, b，计算 a - b
do_f32_sub:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    fld     dword ptr [esp]      # st0 = a
    fsub    dword ptr [esp + 4]  # st0 = a - b
    fstp    dword ptr [esp + 4]
    pop     eax
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.mul: 弹出 a, b，计算 a * b
do_f32_mul:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    fld     dword ptr [esp]
    fmul    dword ptr [esp + 4]
    fstp    dword ptr [esp + 4]
    pop     eax
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.div: 弹出 a, b，计算 a / b
do_f32_div:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    fld     dword ptr [esp]
    fdiv    dword ptr [esp + 4]
    fstp    dword ptr [esp + 4]
    pop     eax
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.add: 弹出两个 f64（各 2 槽），相加，压入结果
do_f64_add:
    # f64 在栈上：high 在前，low 在后
    # 弹出 b: b_high, b_low
    call    _stack_pop           # b_low
    push    eax
    call    _stack_pop           # b_high
    push    eax
    # 弹出 a: a_high, a_low
    call    _stack_pop           # a_low
    push    eax
    call    _stack_pop           # a_high
    push    eax
    # 现在栈布局: [esp]=a_high, [esp+4]=a_low, [esp+8]=b_high, [esp+12]=b_low
    # x87 FPU 加载 64 位浮点数
    fld     qword ptr [esp]      # st0 = a
    fadd    qword ptr [esp + 8]  # st0 = a + b
    # 存储结果
    fstp    qword ptr [esp]      # 存储到 a 的位置
    # 清理并压入结果
    add     esp, 12              # 清理 a_high, a_low, b_high
    pop     eax                  # result_low
    push    eax                  # 保存
    call    _stack_push          # push result_low
    pop     eax
    call    _stack_push          # push result_high
    jmp     dispatch_done

# f64.sub, mul, div 类似实现
do_f64_sub:
    call    _stack_pop           # b_low
    push    eax
    call    _stack_pop           # b_high
    push    eax
    call    _stack_pop           # a_low
    push    eax
    call    _stack_pop           # a_high
    push    eax
    fld     qword ptr [esp]
    fsub    qword ptr [esp + 8]
    fstp    qword ptr [esp]
    add     esp, 12
    pop     eax
    push    eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

do_f64_mul:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fld     qword ptr [esp]
    fmul    qword ptr [esp + 8]
    fstp    qword ptr [esp]
    add     esp, 12
    pop     eax
    push    eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

do_f64_div:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fld     qword ptr [esp]
    fdiv    qword ptr [esp + 8]
    fstp    qword ptr [esp]
    add     esp, 12
    pop     eax
    push    eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# ============================================================================
# f32/f64 比较运算（使用 x87 FPU fcomip + fstsw）
# ============================================================================

# f32.eq: 比较两个 f32，返回 i32 (0 或 1)
do_f32_eq:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    fld     dword ptr [esp]      # st0 = a
    fcomp   dword ptr [esp + 4]  # 比较 a 和 b，弹出 st0
    fstsw   ax                   # ax = FPU 状态字
    sahf                        # 将 ah 存入 CPU flags
    sete    al                   # al = 1 if equal
    movzx   eax, al
    add     esp, 8               # 清理栈
    call    _stack_push
    jmp     dispatch_done

# f32.ne: 比较两个 f32，返回 i32 (不相等为 1)
do_f32_ne:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    fld     dword ptr [esp]
    fcomp   dword ptr [esp + 4]
    fstsw   ax
    sahf
    setne   al                   # not equal
    movzx   eax, al
    add     esp, 8
    call    _stack_push
    jmp     dispatch_done

# f32.lt: 比较两个 f32，a < b 返回 1
do_f32_lt:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    fld     dword ptr [esp]      # st0 = a
    fcomp   dword ptr [esp + 4]  # compare a, b
    fstsw   ax
    sahf
    setb    al                   # below (a < b)
    movzx   eax, al
    add     esp, 8
    call    _stack_push
    jmp     dispatch_done

# f32.gt: 比较两个 f32，a > b 返回 1
do_f32_gt:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    fld     dword ptr [esp]
    fcomp   dword ptr [esp + 4]
    fstsw   ax
    sahf
    seta    al                   # above (a > b)
    movzx   eax, al
    add     esp, 8
    call    _stack_push
    jmp     dispatch_done

# f32.le: 比较两个 f32，a <= b 返回 1
do_f32_le:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    fld     dword ptr [esp]
    fcomp   dword ptr [esp + 4]
    fstsw   ax
    sahf
    setbe   al                   # below or equal
    movzx   eax, al
    add     esp, 8
    call    _stack_push
    jmp     dispatch_done

# f32.ge: 比较两个 f32，a >= b 返回 1
do_f32_ge:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    fld     dword ptr [esp]
    fcomp   dword ptr [esp + 4]
    fstsw   ax
    sahf
    setae   al                   # above or equal
    movzx   eax, al
    add     esp, 8
    call    _stack_push
    jmp     dispatch_done

# f64.eq: 比较两个 f64（各 2 栈槽），返回 i32
do_f64_eq:
    # 弹出 b: b_low, b_high
    call    _stack_pop           # b_low
    push    eax
    call    _stack_pop           # b_high
    push    eax
    # 弹出 a: a_low, a_high
    call    _stack_pop           # a_low
    push    eax
    call    _stack_pop           # a_high
    push    eax
    # 栈布局: [esp]=a_high, [esp+4]=a_low, [esp+8]=b_high, [esp+12]=b_low
    fld     qword ptr [esp + 4]  # st0 = a (qword from a_low addr)
    fcomp   qword ptr [esp + 12] # compare with b
    fstsw   ax
    sahf
    sete    al
    movzx   eax, al
    add     esp, 16              # 清理所有 push
    call    _stack_push
    jmp     dispatch_done

# f64.ne
do_f64_ne:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fld     qword ptr [esp + 4]
    fcomp   qword ptr [esp + 12]
    fstsw   ax
    sahf
    setne   al
    movzx   eax, al
    add     esp, 16
    call    _stack_push
    jmp     dispatch_done

# f64.lt
do_f64_lt:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fld     qword ptr [esp + 4]
    fcomp   qword ptr [esp + 12]
    fstsw   ax
    sahf
    setb    al
    movzx   eax, al
    add     esp, 16
    call    _stack_push
    jmp     dispatch_done

# f64.gt
do_f64_gt:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fld     qword ptr [esp + 4]
    fcomp   qword ptr [esp + 12]
    fstsw   ax
    sahf
    seta    al
    movzx   eax, al
    add     esp, 16
    call    _stack_push
    jmp     dispatch_done

# f64.le
do_f64_le:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fld     qword ptr [esp + 4]
    fcomp   qword ptr [esp + 12]
    fstsw   ax
    sahf
    setbe   al
    movzx   eax, al
    add     esp, 16
    call    _stack_push
    jmp     dispatch_done

# f64.ge
do_f64_ge:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fld     qword ptr [esp + 4]
    fcomp   qword ptr [esp + 12]
    fstsw   ax
    sahf
    setae   al
    movzx   eax, al
    add     esp, 16
    call    _stack_push
    jmp     dispatch_done

# ============================================================================
# f32/f64 数学函数（使用 x87 FPU）
# ============================================================================

# f32.abs: 取绝对值
do_f32_abs:
    call    _stack_pop
    push    eax
    fld     dword ptr [esp]      # st0 = value
    fabs                        # st0 = |value|
    fstp    dword ptr [esp]      # store result
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.neg: 取负值
do_f32_neg:
    call    _stack_pop
    push    eax
    fld     dword ptr [esp]
    fchs                        # change sign
    fstp    dword ptr [esp]
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.sqrt: 平方根
do_f32_sqrt:
    call    _stack_pop
    push    eax
    fld     dword ptr [esp]
    fsqrt                       # square root
    fstp    dword ptr [esp]
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.abs: 64位绝对值
do_f64_abs:
    call    _stack_pop           # low
    push    eax
    call    _stack_pop           # high
    push    eax
    # [esp] = high, [esp+4] = low
    fld     qword ptr [esp]      # st0 = value
    fabs
    fstp    qword ptr [esp]      # store result
    pop     eax                  # result_high
    call    _stack_push
    pop     eax                  # result_low
    call    _stack_push
    jmp     dispatch_done

# f64.neg: 64位取负
do_f64_neg:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fld     qword ptr [esp]
    fchs
    fstp    qword ptr [esp]
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.sqrt: 64位平方根
do_f64_sqrt:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fld     qword ptr [esp]
    fsqrt
    fstp    qword ptr [esp]
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# ============================================================================
# f32/f64 舍入函数（使用 x87 FPU frndint + 控制字）
# FCW rounding mode bits 10-11: 00=nearest, 01=down, 10=up, 11=toward-zero
# ============================================================================

# f32.ceil: 向上舍入（向 +∞）
do_f32_ceil:
    call    _stack_pop
    push    eax
    # 保存并修改 FPU 控制字
    sub     esp, 2                 # 空间存放 FCW
    fstcw   word ptr [esp]         # 保存当前 FCW
    mov     ax, [esp]
    and     ax, 0xF3FF             # 清除 rounding mode 位
    or      ax, 0x0800             # 设置 ceil 模式 (10 = round up)
    mov     [esp + 4], ax          # 临时存放新 FCW（在 eax 原来的位置）
    fldcw   word ptr [esp + 4]     # 加载新 FCW
    # 执行舍入
    fld     dword ptr [esp + 6]    # 加载操作数（原栈位置 +6）
    frndint                      # 舍入到整数
    fstp    dword ptr [esp + 6]    # 存储结果
    # 恢复 FCW
    fldcw   word ptr [esp]         # 恢复原 FCW
    add     esp, 6                 # 清理 FCW + 操作数
    pop     eax                    # 结果
    call    _stack_push
    jmp     dispatch_done

# f32.floor: 向下舍入（向 -∞）
do_f32_floor:
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0400             # floor 模式 (01 = round down)
    mov     [esp + 4], ax
    fldcw   word ptr [esp + 4]
    fld     dword ptr [esp + 6]
    frndint
    fstp    dword ptr [esp + 6]
    fldcw   word ptr [esp]
    add     esp, 6
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.trunc: 向零舍入（截断）
do_f32_trunc:
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00             # trunc 模式 (11 = toward zero)
    mov     [esp + 4], ax
    fldcw   word ptr [esp + 4]
    fld     dword ptr [esp + 6]
    frndint
    fstp    dword ptr [esp + 6]
    fldcw   word ptr [esp]
    add     esp, 6
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.nearest: 舍入到最近整数
do_f32_nearest:
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF             # nearest 模式 (00 = round to nearest)
    mov     [esp + 4], ax
    fldcw   word ptr [esp + 4]
    fld     dword ptr [esp + 6]
    frndint
    fstp    dword ptr [esp + 6]
    fldcw   word ptr [esp]
    add     esp, 6
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.ceil: 64位向上舍入
do_f64_ceil:
    call    _stack_pop           # low
    push    eax
    call    _stack_pop           # high
    push    eax
    # 栈: [esp]=high, [esp+4]=low
    sub     esp, 2               # FCW 空间
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0800
    mov     [esp + 6], ax        # 新 FCW 在 [esp+6]
    fldcw   word ptr [esp + 6]
    fld     qword ptr [esp + 8]  # 加载 64 位操作数
    frndint
    fstp    qword ptr [esp + 8]
    fldcw   word ptr [esp]       # 恢复 FCW
    add     esp, 2               # 清理 FCW 空间
    pop     eax                  # result_high
    call    _stack_push
    pop     eax                  # result_low
    call    _stack_push
    jmp     dispatch_done

# f64.floor: 64位向下舍入
do_f64_floor:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0400
    mov     [esp + 6], ax
    fldcw   word ptr [esp + 6]
    fld     qword ptr [esp + 8]
    frndint
    fstp    qword ptr [esp + 8]
    fldcw   word ptr [esp]
    add     esp, 2
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.trunc: 64位向零舍入
do_f64_trunc:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00
    mov     [esp + 6], ax
    fldcw   word ptr [esp + 6]
    fld     qword ptr [esp + 8]
    frndint
    fstp    qword ptr [esp + 8]
    fldcw   word ptr [esp]
    add     esp, 2
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.nearest: 64位舍入到最近
do_f64_nearest:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF           # nearest (00)
    mov     [esp + 6], ax
    fldcw   word ptr [esp + 6]
    fld     qword ptr [esp + 8]
    frndint
    fstp    qword ptr [esp + 8]
    fldcw   word ptr [esp]
    add     esp, 2
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# ============================================================================
# f32/f64 min/max/copysign
# ============================================================================

# f32.min: 弹出 a, b，返回 min(a, b)
do_f32_min:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    push    eax
    # [esp] = a, [esp+4] = b
    # WASM spec: if either NaN, return NaN (IEEE 754-2008, not minNum)
    fld     dword ptr [esp]      # st0 = a
    fcomp   dword ptr [esp + 4]  # compare a with b, pop
    fstsw   ax
    sahf
    jp      .f32min_return_a     # unordered -> NaN, return a
    jbe     .f32min_return_a     # a <= b -> return a
    pop     eax                  # discard a
    pop     eax                  # eax = b
    call    _stack_push
    jmp     dispatch_done
.f32min_return_a:
    pop     eax                  # discard b
    pop     eax                  # eax = a
    call    _stack_push
    jmp     dispatch_done

# f32.max: 弹出 a, b，返回 max(a, b)
do_f32_max:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    push    eax
    # WASM spec: if either NaN, return NaN (IEEE 754-2008, not maxNum)
    fld     dword ptr [esp]
    fcomp   dword ptr [esp + 4]
    fstsw   ax
    sahf
    jp      .f32max_return_a     # unordered -> NaN, return a
    jae     .f32max_return_a     # a >= b -> return a
    pop     eax
    pop     eax
    call    _stack_push
    jmp     dispatch_done
.f32max_return_a:
    pop     eax
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.copysign: 弹出 a, b，返回 a with sign of b
do_f32_copysign:
    call    _stack_pop           # b
    push    eax
    call    _stack_pop           # a
    push    eax
    # Extract sign of b (bit 31), magnitude of a (bits 0-30)
    mov     eax, [esp + 4]       # b
    and     eax, 0x80000000      # sign bit of b
    mov     edx, [esp]           # a
    and     edx, 0x7FFFFFFF      # magnitude of a
    or      eax, edx             # combine
    mov     [esp], eax           # store result
    add     esp, 4
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.min: 弹出两个 f64，返回 min
do_f64_min:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    # Stack: [esp]=a_high, [esp+4]=a_low, [esp+8]=b_high, [esp+12]=b_low
    # WASM spec: if either NaN, return NaN (IEEE 754-2008)
    fld     qword ptr [esp]      # st0 = a
    fcomp   qword ptr [esp + 8]  # compare a with b
    fstsw   ax
    sahf
    jp      .f64min_return_a     # unordered -> NaN, return a
    jbe     .f64min_return_a     # a <= b -> return a
    add     esp, 8               # discard a
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done
.f64min_return_a:
    add     esp, 8               # discard b
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.max: 弹出两个 f64，返回 max
do_f64_max:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    # WASM spec: if either NaN, return NaN (IEEE 754-2008)
    fld     qword ptr [esp]
    fcomp   qword ptr [esp + 8]
    fstsw   ax
    sahf
    jp      .f64max_return_a     # unordered -> NaN, return a
    jae     .f64max_return_a     # a >= b -> return a
    add     esp, 8
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done
.f64max_return_a:
    add     esp, 8
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.copysign: 弹出 a, b，返回 a with sign of b
do_f64_copysign:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    # [esp]=a_high, [esp+4]=a_low, [esp+8]=b_high, [esp+12]=b_low
    # Sign bit of f64 is bit 63 = bit 31 of high 32 bits
    mov     eax, [esp + 8]       # b_high
    and     eax, 0x80000000      # sign bit of b
    mov     edx, [esp]           # a_high
    and     edx, 0x7FFFFFFF      # magnitude of a
    or      eax, edx
    mov     [esp], eax           # new a_high
    add     esp, 8               # discard b
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# ============================================================================
# f32/f64 转换操作
# ============================================================================

# i32.trunc_f32_s: 截断 f32 到有符号 i32
do_i32_trunc_f32_s:
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00             # trunc mode (toward zero)
    mov     [esp + 2], ax
    fldcw   word ptr [esp + 2]
    fld     dword ptr [esp + 4]
    frndint
    fistp   dword ptr [esp + 4]    # store as integer
    fldcw   word ptr [esp]         # restore FCW
    add     esp, 6
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# i32.trunc_f32_u: 截断 f32 到无符号 i32
do_i32_trunc_f32_u:
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00
    mov     [esp + 2], ax
    fldcw   word ptr [esp + 2]
    fld     dword ptr [esp + 4]
    frndint
    fistp   dword ptr [esp + 4]
    fldcw   word ptr [esp]
    add     esp, 6
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# i32.trunc_f64_s: 截断 f64 到有符号 i32
do_i32_trunc_f64_s:
    call    _stack_pop           # low
    push    eax
    call    _stack_pop           # high
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00
    mov     [esp + 2], ax
    fldcw   word ptr [esp + 2]
    fld     qword ptr [esp + 4]
    frndint
    fistp   dword ptr [esp + 4]   # store as 32-bit integer
    fldcw   word ptr [esp]
    add     esp, 6                # cleanup FCW + high
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# i32.trunc_f64_u: 截断 f64 到无符号 i32
do_i32_trunc_f64_u:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00
    mov     [esp + 2], ax
    fldcw   word ptr [esp + 2]
    fld     qword ptr [esp + 4]
    frndint
    fistp   dword ptr [esp + 4]
    fldcw   word ptr [esp]
    add     esp, 6
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# i64.trunc_f32_s: 截断 f32 到有符号 i64
do_i64_trunc_f32_s:
    call    _stack_pop           # f32 value
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00
    mov     [esp + 4], ax
    fldcw   word ptr [esp + 4]
    fld     dword ptr [esp + 6]
    frndint
    # i64 result: push high then low
    sub     esp, 4               # space for 64-bit integer
    fistp   qword ptr [esp]      # store 64-bit integer
    fldcw   word ptr [esp + 8]   # restore FCW (original location)
    add     esp, 8               # cleanup FCW + original value
    pop     eax                  # i64 high
    call    _stack_push
    pop     eax                  # i64 low
    call    _stack_push
    jmp     dispatch_done

# i64.trunc_f32_u: 截断 f32 到无符号 i64
do_i64_trunc_f32_u:
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00
    mov     [esp + 4], ax
    fldcw   word ptr [esp + 4]
    fld     dword ptr [esp + 6]
    frndint
    sub     esp, 4
    fistp   qword ptr [esp]
    fldcw   word ptr [esp + 8]
    add     esp, 8
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# i64.trunc_f64_s: 截断 f64 到有符号 i64
do_i64_trunc_f64_s:
    call    _stack_pop           # f64 low
    push    eax
    call    _stack_pop           # f64 high
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00
    mov     [esp + 6], ax
    fldcw   word ptr [esp + 6]
    fld     qword ptr [esp + 8]
    frndint
    sub     esp, 4
    fistp   qword ptr [esp]
    fldcw   word ptr [esp + 10]
    add     esp, 10
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# i64.trunc_f64_u: 截断 f64 到无符号 i64
do_i64_trunc_f64_u:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    sub     esp, 2
    fstcw   word ptr [esp]
    mov     ax, [esp]
    and     ax, 0xF3FF
    or      ax, 0x0C00
    mov     [esp + 6], ax
    fldcw   word ptr [esp + 6]
    fld     qword ptr [esp + 8]
    frndint
    sub     esp, 4
    fistp   qword ptr [esp]
    fldcw   word ptr [esp + 10]
    add     esp, 10
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.convert_i32_s: 有符号 i32 转 f32
do_f32_convert_i32_s:
    call    _stack_pop           # i32
    push    eax
    fild    dword ptr [esp]       # load integer to FPU
    fstp    dword ptr [esp]       # store as f32
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.convert_i32_u: 无符号 i32 转 f32
do_f32_convert_i32_u:
    call    _stack_pop
    push    eax
    fild    dword ptr [esp]
    fstp    dword ptr [esp]
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.convert_i64_s: 有符号 i64 转 f32
do_f32_convert_i64_s:
    call    _stack_pop           # i64 low
    push    eax
    call    _stack_pop           # i64 high
    push    eax
    fild    qword ptr [esp]       # load 64-bit integer
    fstp    dword ptr [esp + 4]   # store as f32 (in low slot)
    add     esp, 4                # cleanup high
    pop     eax                   # f32 result
    call    _stack_push
    jmp     dispatch_done

# f32.convert_i64_u: 无符号 i64 转 f32
do_f32_convert_i64_u:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fild    qword ptr [esp]
    fstp    dword ptr [esp + 4]
    add     esp, 4
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f32.demote_f64: f64 降级为 f32
do_f32_demote_f64:
    call    _stack_pop           # f64 low
    push    eax
    call    _stack_pop           # f64 high
    push    eax
    fld     qword ptr [esp]       # load f64
    fstp    dword ptr [esp + 4]   # store as f32 (precision loss)
    add     esp, 4                # cleanup high
    pop     eax                   # f32 result
    call    _stack_push
    jmp     dispatch_done

# f64.convert_i32_s: 有符号 i32 转 f64
do_f64_convert_i32_s:
    call    _stack_pop           # i32
    push    eax
    push    eax                   # space for f64 result
    fild    dword ptr [esp + 4]   # load integer
    fstp    qword ptr [esp]       # store as f64
    pop     eax                   # f64 high
    call    _stack_push
    pop     eax                   # f64 low
    call    _stack_push
    jmp     dispatch_done

# f64.convert_i32_u: 无符号 i32 转 f64
do_f64_convert_i32_u:
    call    _stack_pop
    push    eax
    push    eax
    fild    dword ptr [esp + 4]
    fstp    qword ptr [esp]
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.convert_i64_s: 有符号 i64 转 f64
do_f64_convert_i64_s:
    call    _stack_pop           # i64 low
    push    eax
    call    _stack_pop           # i64 high
    push    eax
    fild    qword ptr [esp]       # load 64-bit integer
    fstp    qword ptr [esp]       # store as f64
    pop     eax                   # f64 high
    call    _stack_push
    pop     eax                   # f64 low
    call    _stack_push
    jmp     dispatch_done

# f64.convert_i64_u: 无符号 i64 转 f64
do_f64_convert_i64_u:
    call    _stack_pop
    push    eax
    call    _stack_pop
    push    eax
    fild    qword ptr [esp]
    fstp    qword ptr [esp]
    pop     eax
    call    _stack_push
    pop     eax
    call    _stack_push
    jmp     dispatch_done

# f64.promote_f32: f32 升级为 f64
do_f64_promote_f32:
    call    _stack_pop           # f32
    push    eax
    push    eax                   # space for f64 result
    fld     dword ptr [esp + 4]   # load f32
    fstp    qword ptr [esp]       # store as f64 (extended precision)
    pop     eax                   # f64 high
    call    _stack_push
    pop     eax                   # f64 low
    call    _stack_push
    jmp     dispatch_done

do_unknown:
    mov     byte ptr [wasm_running], 0
    mov     dword ptr [wasm_exec_error], 2

dispatch_done:
    pop     ecx
    pop     eax
    # Fix corrupted return address
    mov     edx, [wasm_dispatch_ret_addr]
    cmp     dword ptr [esp], 0x100000
    jae     .ra_ok
    mov     [esp], edx
.ra_ok:
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
    cmp     ebx, 256              # 最大 256 个元素
    jae     stack_overflow_push
    mov     [wasm_operand_stack + ebx * 4], eax
    inc     dword ptr [wasm_stack_top]
    pop     ebx
    ret
stack_overflow_push:
    mov     byte ptr [wasm_running], 0
    mov     dword ptr [wasm_exec_error], 3
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

# ============================================================================
# _read_leb128_s32: 从当前 PC 读取有符号 LEB128（SLEB128）
# 输出：eax = 有符号值, 更新 wasm_pc
# ============================================================================
_read_leb128_s32:
    push    ebx
    push    ecx

    mov     esi, [wasm_pc]

    xor     eax, eax
    xor     ebx, ebx

read_sleb_vm_byte:
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
    jz      read_sleb_vm_done

    add     ebx, 7
    jmp     read_sleb_vm_byte

read_sleb_vm_done:
    # 如果最高数据位（最后字节的 bit 6）为 1，执行符号扩展
    movzx   edx, byte ptr [esi - 1]
    test    edx, 0x40
    jz      read_sleb_vm_no_extend

    # 符号扩展：将高位填充为 1
    mov     edx, ebx
    cmp     edx, 32
    jae     read_sleb_vm_skip_extend  # 已经读了 32 位以上，不需要扩展

    mov     ecx, edx
    mov     edx, -1
    shl     edx, cl
    or      eax, edx

read_sleb_vm_skip_extend:
    mov     [wasm_pc], esi

read_sleb_vm_no_extend:
    # Ensure wasm_pc is always updated (fix: was skipped when sign bit not set)
    mov     [wasm_pc], esi
    pop     ecx
    pop     ebx
    ret
