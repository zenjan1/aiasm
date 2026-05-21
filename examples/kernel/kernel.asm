    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# kernel.asm - 内核入口、启动序列、主循环
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# Multiboot1 header
# ============================================================================
    .section .multiboot
mb_start:
    .long  0x1BADB002          # magic
    .long  0x00000003          # flags: memory info + load ELF
    .long  0xE4524FFB          # checksum: -(magic + flags)

# ============================================================================
# PVH ELF Note for QEMU 8+ -kernel
# ============================================================================
    .section ".note.Xen","a",@note
    .align  4
    .long  4                   # namesz
    .long  4                   # descsz (32-bit entry)
    .long  18                  # type: XEN_ELFNOTE_PHYS32_ENTRY
    .ascii "Xen"
    .byte  0
    .long  _start

# ============================================================================
# Entry point - 32-bit protected mode (PVH boots with paging enabled)
# ============================================================================
    .section .text
    .globl _start
_start:
    # 设置栈
    lea     esp, [stack_top]

    # 禁用分页（PVH boot 开启了分页，但我们需要直接访问物理内存）
    mov     eax, cr0
    and     eax, ~0x80000000    # 清除 PG 位
    mov     cr0, eax

    # 初始化串口
    call    serial_init

    # 打印启动信息
    mov     esi, offset boot_msg
    mov     ecx, boot_msg_len
    call    serial_print_string

    # 加载 GDT
    call    gdt_load
    mov     al, 'G'
    call    serial_putchar
    mov     al, ' '
    call    serial_putchar

    # 加载 IDT
    call    idt_load
    mov     al, 'I'
    call    serial_putchar
    mov     al, ' '
    call    serial_putchar

    # 重映射 PIC
    call    pic_remap
    mov     al, 'P'
    call    serial_putchar
    mov     al, ' '
    call    serial_putchar

    # 初始化 PIT 定时器
    call    pit_init
    mov     al, 'T'
    call    serial_putchar
    mov     al, ' '
    call    serial_putchar

    # 初始化键盘
    call    keyboard_init
    mov     al, 'K'
    call    serial_putchar
    mov     al, 0x0a
    call    serial_putchar

    # 清屏 (串口 ANSI)
    mov     esi, offset ansi_clear
    mov     ecx, ansi_clear_len
    call    serial_print_string

    # 打印 VGA 启动信息 (串口输出)
    mov     esi, offset boot_msg_vga
    mov     ecx, boot_msg_vga_len
    call    serial_print_string

    # 开中断
    sti

    # 进入 shell
    call    shell_run

    # 不应该到达这里
    cli
1:  hlt
    jmp     1b

# ============================================================================
# kernel_halt: 挂起系统
# ============================================================================
    .globl  kernel_halt
kernel_halt:
    cli
1:  hlt
    jmp     1b

# ============================================================================
# kernel_reboot: 重启系统
# ============================================================================
    .globl  kernel_reboot
kernel_reboot:
    cli
    mov     al, 0xFE
    out     0x64, al
1:  hlt
    jmp     1b

# ============================================================================
# Serial output (COM1, 38400 baud)
# ============================================================================
serial_init:
    push    edx
    push    eax

    mov     dx, 0x3fb
    mov     al, 0x80
    out     dx, al

    mov     dx, 0x3f8
    mov     al, 0x03
    out     dx, al
    mov     dx, 0x3f9
    xor     al, al
    out     dx, al

    mov     dx, 0x3fb
    mov     al, 0x03
    out     dx, al

    pop     eax
    pop     edx
    ret

serial_putchar:
    push    eax
    push    edx

    mov     dx, 0x3fd
1:  in      al, dx
    test    al, 0x20
    jz      1b

    pop     eax
    mov     dx, 0x3f8
    out     dx, al
    pop     edx
    ret

serial_print_string:
    push    esi
    push    ecx
1:  cmp     ecx, 0
    je      2f
    mov     al, [esi]
    push    eax
    call    serial_putchar
    pop     eax
    inc     esi
    dec     ecx
    jmp     1b
2:  pop     ecx
    pop     esi
    ret

    .globl  serial_print_string
    .globl  serial_putchar
    .globl  serial_init

# ============================================================================
# BSS
# ============================================================================
    .section .bss
    .space  8192
stack_top:

    .section .rodata
boot_msg:
    .ascii  "AI-ASM Kernel v0.2 booting... "
boot_msg_len = . - boot_msg
    .space  32                  # 预留空间避免缓冲区溢出

boot_msg_vga:
    .ascii  "AI-ASM Kernel v0.2"
    .byte   13, 10
boot_msg_vga_len = . - boot_msg_vga

ansi_clear:
    .byte   0x1B, '[', '2', 'J', 0x1B, '[', 'H'
ansi_clear_len = . - ansi_clear
