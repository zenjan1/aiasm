    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start
# 功能：调用write系统调用打印字符串
# 输入：无
# 输出：打印"Hello, AI-ASM!\n"到stdout
# 破坏的寄存器：rax, rdi, rsi, rdx
# 栈使用：0字节
# -----------------------------------------------------------------------------
    .globl _start

msg:
    .byte   72, 101, 108, 108, 111, 44, 32, 65, 73, 45, 65, 83, 77, 33, 10
msg_len = . - msg

_start:
    # write(1, "Hello, AI-ASM!\n", 15)
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg]
    mov     edx, msg_len
    syscall

    # exit(0)
    mov     rax, 60
    mov     rdi, 0
    syscall
