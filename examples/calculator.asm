    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start
# 功能：简单的加法计算器，展示函数调用和参数传递
# 输入：无
# 输出："3 + 5 = 8\n"
# 破坏的寄存器：rax, rdi, rsi, rdx, rcx
# 栈使用：16字节
# -----------------------------------------------------------------------------
    .globl _start

# 数据
s3:
    .byte   51
s3_len = 1
s5:
    .byte   53
s5_len = 1
plus:
    .byte   32, 43, 32
plus_len = 3
equals:
    .byte   32, 61, 32
equals_len = 3
nl:
    .byte   10
nl_len = 1

# 加法函数 rdi=a, rsi=b -> rax=a+b
add:
    push    rbp
    mov     rbp, rsp
    mov     rax, rdi
    add     rax, rsi
    pop     rbp
    ret

# 打印字符串 rsi=地址 rdx=长度
print_str:
    push    rbp
    mov     rbp, rsp
    mov     rax, 1
    mov     rdi, 1
    syscall
    pop     rbp
    ret

# 打印rax中的十进制数字
print_rax:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    mov     r8, 14

.dloop:
    xor     rdx, rdx
    mov     rdi, 10
    div     rdi
    add     dl, '0'
    mov     [rsp + r8], dl
    dec     r8
    test    rax, rax
    jnz     .dloop

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rsp + r8 + 1]
    mov     edx, 14
    sub     edx, r8d
    syscall

    add     rsp, 16
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

    mov     rdi, 3
    mov     rsi, 5
    call    add

    call    print_rax

    lea     rsi, [rip + nl]
    mov     edx, nl_len
    call    print_str

    mov     rax, 60
    xor     rdi, rdi
    syscall
