    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start (内核入口点)
# 功能：最小x86_64内核，通过VGA直接写入打印字符串
# 输入：无
# 输出：在屏幕上显示"Hello from AI-ASM Kernel!"
# 破坏的寄存器：全部
# 栈使用：4096字节
# -----------------------------------------------------------------------------
    .globl _start

VGA_BUF     = 0xb8000
WHITE_BLACK = 0x0f

    .section .rodata
msg:
    .byte   72, 101, 108, 108, 111, 32, 102, 114, 111, 109, 32, 65, 73, 45, 65, 83
    .byte   77, 32, 75, 101, 114, 110, 101, 108, 33
msg_len = . - msg

    .section .text
_start:
    # 设置栈指针
    lea     rsp, [rip + stack_top]

    # 打印字符串到VGA缓冲区
    mov     rsi, msg
    mov     rdi, VGA_BUF
    mov     rcx, msg_len

.print_loop:
    cmp     rcx, 0
    je      .done
    mov     al, [rsi]
    mov     [rdi], al
    mov     byte ptr [rdi + 1], WHITE_BLACK
    inc     rsi
    add     rdi, 2
    dec     rcx
    jmp     .print_loop

.done:
    hlt
    jmp     .done

    .section .bss
    .space  4096
stack_top:
