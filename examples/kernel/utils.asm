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
# strncmp: 比较两个字符串的前 n 个字符
# 输入：esi = a, edi = b, ecx = n
# 输出：eax = 0 相等, 1 不等
# -----------------------------------------------------------------------------
    .globl  utils_strncmp
utils_strncmp:
    push    esi
    push    edi
    test    ecx, ecx
    jz      2f
1:  mov     al, [esi]
    mov     dl, [edi]
    cmp     al, dl
    jne     3f
    inc     esi
    inc     edi
    dec     ecx
    jnz     1b
2:  xor     eax, eax
    jmp     4f
3:  mov     eax, 1
4:  pop     edi
    pop     esi
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
    mov     bl, dl            # 保存 base 到 bl (div 会破坏 edx)
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
    movzx   ebx, bl           # ebx = base
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

# -----------------------------------------------------------------------------
# atoi: 字符串转整数
# 输入：esi = 字符串指针
# 输出：eax = 整数值（支持负数）
# -----------------------------------------------------------------------------
    .globl  utils_atoi
utils_atoi:
    push    ebx
    push    ecx
    push    edx

    xor     eax, eax
    xor     ecx, ecx              # sign = 0 (positive)

    # 跳过空白
.skip_ws:
    movzx   edx, byte ptr [esi]
    cmp     edx, ' '
    je      .next_char
    cmp     edx, '\t'
    je      .next_char
    jmp     .check_sign

.next_char:
    inc     esi
    jmp     .skip_ws

.check_sign:
    cmp     edx, '-'
    jne     .check_plus
    mov     ecx, 1
    inc     esi
    jmp     .parse_digits

.check_plus:
    cmp     edx, '+'
    jne     .parse_digits
    inc     esi

.parse_digits:
    movzx   edx, byte ptr [esi]
    cmp     edx, '0'
    jl      .done_parse
    cmp     edx, '9'
    jg      .done_parse

    # eax = eax * 10 + (edx - '0')
    imul    eax, 10
    sub     edx, '0'
    add     eax, edx
    inc     esi
    jmp     .parse_digits

.done_parse:
    test    ecx, ecx
    jz      .atoi_done
    neg     eax

.atoi_done:
    pop     edx
    pop     ecx
    pop     ebx
    ret

# -----------------------------------------------------------------------------
# parse_hex: 解析十六进制字符串
# 输入：esi = 字符串指针 (支持 "0x" 前缀或直接 hex)
# 输出：eax = 整数值
# -----------------------------------------------------------------------------
    .globl  utils_parse_hex
utils_parse_hex:
    push    ebx
    push    ecx
    push    edx

    xor     eax, eax              # result = 0
    xor     ecx, ecx              # digit count

    # 检查 "0x" 前缀
    movzx   edx, byte ptr [esi]
    cmp     edx, '0'
    jne     .parse_hex_start
    inc     esi
    movzx   edx, byte ptr [esi]
    cmp     edx, 'x'
    jne     .parse_hex_start
    inc     esi

.parse_hex_start:
    movzx   edx, byte ptr [esi]
    test    edx, edx
    jz      .parse_hex_done

    # 检查是否是有效的十六进制字符
    cmp     edx, '0'
    jl      .parse_hex_done
    cmp     edx, '9'
    jle     .hex_digit

    cmp     edx, 'a'
    jl      .check_upper
    cmp     edx, 'f'
    jle     .hex_lower

.check_upper:
    cmp     edx, 'A'
    jl      .parse_hex_done
    cmp     edx, 'F'
    jle     .hex_upper

    jmp     .parse_hex_done

.hex_digit:
    sub     edx, '0'
    jmp     .hex_add

.hex_lower:
    sub     edx, 'a'
    add     edx, 10
    jmp     .hex_add

.hex_upper:
    sub     edx, 'A'
    add     edx, 10

.hex_add:
    # eax = eax * 16 + digit
    shl     eax, 4
    add     eax, edx
    inc     esi
    jmp     .parse_hex_start

.parse_hex_done:
    pop     edx
    pop     ecx
    pop     ebx
    ret

# -----------------------------------------------------------------------------
# itoa_single: 单字节转十六进制字符串
# 输入：al = byte value, esi = buffer (至少 3 字节)
# 输出：buffer 包含 2 字符 hex + null
# -----------------------------------------------------------------------------
    .globl  utils_itoa_single
utils_itoa_single:
    push    eax
    push    ecx

    mov     ecx, eax              # 保存原始值

    # 高 4 位
    shr     al, 4
    cmp     al, 9
    jle     .high_digit
    add     al, 7                 # A-F
.high_digit:
    add     al, '0'
    mov     [esi], al

    # 低 4 位
    mov     al, cl
    and     al, 0x0F
    cmp     al, 9
    jle     .low_digit
    add     al, 7
.low_digit:
    add     al, '0'
    mov     [esi + 1], al

    # null 终止
    mov     byte ptr [esi + 2], 0

    pop     ecx
    pop     eax
    ret
