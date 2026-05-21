    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start
# 功能：循环打印1到5，每行一个数字
# 输入：无
# 输出："1\n2\n3\n4\n5\n"
# 破坏的寄存器：rax, rdi, rsi, rdx, rcx
# 栈使用：16字节
# -----------------------------------------------------------------------------
    .globl _start

nl:
    .byte   10
nl_len = 1

# 打印单个字符+换行
# rdi = 字符
print_char_nl:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 24                 # 8(rcx) + 16(buf)
    push    rcx                     # 保存rcx(syscall会覆盖)
    mov     byte ptr [rsp + 8], dil  # 字符
    mov     byte ptr [rsp + 9], 10  # 换行

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rsp + 8]
    mov     edx, 2
    syscall

    pop     rcx                     # 恢复rcx
    add     rsp, 24
    pop     rbp
    ret

_start:
    mov     rcx, 1

.loop:
    cmp     rcx, 5
    jg      .done

    mov     rdi, rcx
    add     rdi, '0'                # 转为ASCII
    call    print_char_nl

    inc     rcx
    jmp     .loop

.done:
    mov     rax, 60
    xor     rdi, rdi
    syscall
