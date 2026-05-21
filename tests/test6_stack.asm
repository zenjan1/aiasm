    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start
# 功能：测试栈操作和局部变量，打印"Local variable: 123\n"
# 输入：无
# 输出：局部变量值
# 破坏的寄存器：rax, rdi, rsi, rdx, rcx
# 栈使用：32字节
# -----------------------------------------------------------------------------
    .globl _start

# 数据
prefix:
    .byte   76, 111, 99, 97, 108, 32, 118, 97, 114, 105, 97, 98, 108, 101
    .byte   58, 32
prefix_len = . - prefix
nl:
    .byte   10
nl_len = 1

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
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16

    # 局部变量 [rbp-8] = 123
    mov     qword ptr [rbp - 8], 123

    # 打印"Local variable: "
    lea     rsi, [rip + prefix]
    mov     edx, prefix_len
    call    print_str

    # 打印局部变量值
    mov     rax, [rbp - 8]
    call    print_rax

    # 打印换行
    lea     rsi, [rip + nl]
    mov     edx, nl_len
    call    print_str

    add     rsp, 16
    pop     rbp

    mov     rax, 60
    xor     rdi, rdi
    syscall
