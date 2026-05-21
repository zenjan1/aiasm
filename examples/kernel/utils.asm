    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# utils.asm - 工具函数
# -----------------------------------------------------------------------------
    .code32

# -----------------------------------------------------------------------------
# strlen: 计算字符串长度
# 输入：esi = 字符串指针
# 输出：eax = 长度
# -----------------------------------------------------------------------------
    .globl  utils_strlen
utils_strlen:
    push    edi
    mov     edi, esi
    xor     eax, eax
    mov     ecx, -1
    cld
    repnz   scasb
    mov     eax, -2
    sub     eax, ecx
    pop     edi
    ret

# -----------------------------------------------------------------------------
# strcmp: 比较两个字符串
# 输入：esi = a, edi = b
# 输出：eax = 0 相等, 1 不等
# -----------------------------------------------------------------------------
    .globl  utils_strcmp
utils_strcmp:
    push    esi
    push    edi
1:  mov     al, [esi]
    mov     dl, [edi]
    cmp     al, dl
    jne     .neq
    test    al, al
    jz      .eq
    inc     esi
    inc     edi
    jmp     1b
.eq:
    xor     eax, eax
    jmp     .done
.neq:
    mov     eax, 1
.done:
    pop     edi
    pop     esi
    ret

# -----------------------------------------------------------------------------
# memcpy: 内存拷贝
# 输入：edi = dest, esi = src, ecx = n
# -----------------------------------------------------------------------------
    .globl  utils_memcpy
utils_memcpy:
    push    ecx
    push    esi
    push    edi
    cld
    rep     movsb
    pop     edi
    pop     esi
    pop     ecx
    ret

# -----------------------------------------------------------------------------
# memset: 填充内存
# 输入：edi = dest, al = byte, ecx = n
# -----------------------------------------------------------------------------
    .globl  utils_memset
utils_memset:
    push    edi
    mov     ah, al
    movzx   ebx, ax
    shl     eax, 16
    mov     ax, bx
    rep     stosd
    pop     eax
    ret

# -----------------------------------------------------------------------------
# itoa: 整数转字符串
# 输入：eax = value, edi = buf, dl = base (10 或 16)
# 输出：eax = buf 指针
# -----------------------------------------------------------------------------
    .globl  utils_itoa
utils_itoa:
    push    ebp
    mov     ebp, esp
    push    edi
    push    edx
    push    ecx
    push    ebx

    mov     ecx, edi          # 保存 buf 指针
    add     edi, 31           # 写到缓冲区末尾
    mov     byte ptr [edi], 0 # null 终止
    dec     edi

    test    eax, eax
    jnz     .convert
    mov     byte ptr [edi], '0'
    dec     edi
    jmp     .reverse

.convert:
    test    eax, eax
    jz      .reverse
    xor     edx, edx
    mov     ebx, edx
    mov     bl, dl            # bl = base
    div     ebx               # eax = eax/base, edx = remainder
    cmp     edx, 9
    jle     .digit
    add     edx, 7            # a-f
.digit:
    add     edx, '0'
    mov     [edi], dl
    dec     edi
    jmp     .convert

.reverse:
    inc     edi
    mov     esi, edi          # src = converted string
    mov     edi, ecx          # dest = original buf
1:  mov     al, [esi]
    mov     [edi], al
    test    al, al
    jz      2f
    inc     esi
    inc     edi
    jmp     1b
2:
    mov     eax, ecx

    pop     ebx
    pop     ecx
    pop     edx
    pop     edi
    pop     ebp
    ret
