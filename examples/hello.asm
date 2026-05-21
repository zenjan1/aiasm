    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start
# 功能：最简单的Hello World程序，直接调用Linux系统调用
# 输入：无
# 输出："Hello, World!\n"
# 破坏的寄存器：rax, rdi, rsi, rdx
# 栈使用：0字节
# -----------------------------------------------------------------------------
    .globl _start

msg:
    .byte   72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33, 10
msg_len = . - msg

_start:
    # write(1, "Hello, World!\n", 14)
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg]
    mov     edx, msg_len
    syscall

    # exit(0)
    mov     rax, 60
    mov     rdi, 0
    syscall
