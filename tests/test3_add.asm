    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start
# 功能：实现加法计算并打印"3 + 5 = 8\n"
# 输入：无
# 输出：打印加法结果到stdout
# 破坏的寄存器：rax, rdi, rsi, rdx, rcx
# 栈使用：32字节
# -----------------------------------------------------------------------------
    .globl _start

# 数据定义
s3:
    .byte   51
s3_len = 1
s5:
    .byte   53
s5_len = 1
s8:
    .byte   56
s8_len = 1
plus:
    .byte   32, 43, 32
plus_len = 3
equals:
    .byte   32, 61, 32
equals_len = 3
nl:
    .byte   10
nl_len = 1

# 打印字符串
# rsi = 地址, rdx = 长度
print_str:
    push    rbp
    mov     rbp, rsp
    mov     rax, 1
    mov     rdi, 1
    syscall
    pop     rbp
    ret

_start:
    lea     rsi, [rip + s3]
    mov     edx, s3_len
    call    print_str

    lea     rsi, [rip + plus]
    mov     edx, plus_len
    call    print_str

    lea     rsi, [rip + s5]
    mov     edx, s5_len
    call    print_str

    lea     rsi, [rip + equals]
    mov     edx, equals_len
    call    print_str

    lea     rsi, [rip + s8]
    mov     edx, s8_len
    call    print_str

    lea     rsi, [rip + nl]
    mov     edx, nl_len
    call    print_str

    # exit(0)
    mov     rax, 60
    xor     rdi, rdi
    syscall
