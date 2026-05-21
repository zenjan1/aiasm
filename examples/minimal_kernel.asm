    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start (BIOS启动入口)
# 功能：最小x86引导扇区，通过串口打印字符串
# 输入：无（由BIOS加载到0x7c00并启动）
# 输出：通过串口发送"Hello from AI-ASM Kernel!"
# -----------------------------------------------------------------------------
# 运行方式: make run-kernel
# -----------------------------------------------------------------------------

    .code16                     # 16位实模式代码
    .globl _start
_start:
    cli                         # 关中断
    cld
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x7c00          # 设置栈

    # 初始化串口 COM1 (0x3f8)
    mov     dx, 0x3fb           # 线路控制寄存器
    mov     al, 0x80            # 使能DLAB
    out     dx, al
    mov     dx, 0x3f8           # 除数锁存低字节
    mov     al, 0x03            # 波特率除数 (115200/38400=3)
    out     dx, al
    mov     dx, 0x3f9           # 除数锁存高字节
    xor     al, al
    out     dx, al
    mov     dx, 0x3fb           # 线路控制寄存器
    mov     al, 0x03            # 8位, 无校验, 1停止位
    out     dx, al

    # 打印字符串
    mov     si, msg
    mov     cx, msg_len

print_loop:
    cmp     cx, 0
    je      done
    mov     al, [si]
    # 等待TX空
    mov     dx, 0x3fd
.wait:
    in      al, dx
    test    al, 0x20
    jz      .wait
    mov     al, [si]
    mov     dx, 0x3f8
    out     dx, al
    inc     si
    dec     cx
    jmp     print_loop

done:
    hlt
    jmp     done

msg:
    .ascii  "Hello from AI-ASM Kernel!"
    .byte   13, 10
msg_len = . - msg

    # 填充到510字节
    .org    510
    .word   0xaa55              # BIOS启动签名
