    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start
# 功能：演示函数调用和返回值，打印"Function returned: 42\n"
# 输入：无
# 输出：函数调用结果
# 破坏的寄存器：rax, rdi, rsi, rdx, rcx
# 栈使用：16字节
# -----------------------------------------------------------------------------
    .globl _start

# 数据
prefix:
    .byte   70, 117, 110, 99, 116, 105, 111, 110, 32, 114, 101, 116, 117, 114, 110, 101
    .byte   100, 58, 32
prefix_len = . - prefix
nl:
    .byte   10
nl_len = 1

# 返回42的测试函数
get_answer:
    push    rbp
    mov     rbp, rsp
    mov     rax, 42
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

_start:
    lea     rsi, [rip + prefix]
    mov     edx, prefix_len
    call    print_str

    call    get_answer
    mov     rdi, rax
    mov     edx, 16

.digit_loop:
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

    lea     rsi, [rip + nl]
    mov     edx, nl_len
    call    print_str

    mov     rax, 60
    xor     rdi, rdi
    syscall
