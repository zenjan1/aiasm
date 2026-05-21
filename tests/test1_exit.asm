    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start
# 功能：调用exit系统调用退出，测试基本运行
# 输入：无
# 输出：打印"test1 exit ok"到stdout
# 破坏的寄存器：rax, rdi, rsi, rdx
# 栈使用：0字节
# -----------------------------------------------------------------------------
    .globl _start

msg:
    .byte   116, 101, 115, 116, 49, 32, 101, 120, 105, 116, 32, 111, 107, 10
msg_len = . - msg

_start:
    # write(1, msg, len)
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg]
    mov     edx, msg_len
    syscall

    # exit(0)
    mov     rax, 60
    mov     rdi, 0
    syscall
