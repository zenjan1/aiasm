    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# kernel.asm - 内核入口、启动序列、主循环
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# Multiboot1 header - must be within first 8KB of ELF file
# ============================================================================
    .section .text
    .align 4
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

    # 清零 BSS 段（QEMU -kernel 不清零 BSS）
    mov     edi, offset __bss_start
    mov     ecx, offset __bss_end
    sub     ecx, edi
    shr     ecx, 2              # ecx = size / 4
    xor     eax, eax
    cld
    rep     stosd

    # 禁用分页
    mov     eax, cr0
    and     eax, ~0x80000000
    mov     cr0, eax

    # 初始化串口（115200 baud）
    call    uart_init

    # 清屏
    call    vga_clear

    # 初始化日志系统
    call    log_init

    # 打印启动信息
    mov     esi, offset msg_boot
    mov     edi, 1              # LOG_INFO
    call    log_print

    # 初始化 GDT
    call    gdt_load
    mov     esi, offset msg_gdt
    mov     edi, 1
    call    log_print

    # 初始化 IDT（256 向量，含 INT 0x80）
    call    idt_load
    mov     esi, offset msg_idt
    mov     edi, 1
    call    log_print

    # 重映射 PIC
    call    pic_remap
    mov     esi, offset msg_pic
    mov     edi, 1
    call    log_print

    # 初始化 PIT (100Hz)
    call    pit_init
    mov     esi, offset msg_pit
    mov     edi, 1
    call    log_print

    # 初始化键盘
    call    keyboard_init
    mov     esi, offset msg_kbd
    mov     edi, 1
    call    log_print

    # 初始化物理内存管理器
    call    memory_init
    mov     esi, offset msg_mem
    mov     edi, 1
    call    log_print

    # 初始化进程管理与调度器
    call    process_init
    mov     esi, offset msg_proc
    mov     edi, 1
    call    log_print

    # 初始化系统调用接口（INT 0x80）
    call    syscall_init
    mov     esi, offset msg_syscall
    mov     edi, 1
    call    log_print

    # 初始化 WASM 运行时
    call    wasm_parser_init
    call    wasm_vm_init
    call    wasm_syscall_init
    mov     esi, offset msg_wasm
    mov     edi, 1
    call    log_print

    # 开中断
    sti

    # 延时让 QEMU stdin 稳定
    mov     ecx, 100000000
1:  loop    1b

    # 进入 shell
    call    shell_run

    cli
1:  hlt
    jmp     1b

# ============================================================================
# kernel_halt: 挂起系统并退出 QEMU
# ============================================================================
    .globl  kernel_halt
kernel_halt:
    cli
    # Method 1: QEMU isa-debug-exit (requires -device isa-debug-exit,iobase=0xf4)
    mov     dx, 0xF4
    xor     al, al
    out     dx, al
    # Method 2: Triple fault — with -no-reboot this exits QEMU
    xor     eax, eax
    push    eax
    push    eax
    lidt    [esp]
    add     esp, 8
    int     0x03            # triggers triple fault with empty IDT
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
# BSS
# ============================================================================
    .section .bss
    .space  8192
stack_top:

    .section .rodata
msg_boot:
    .asciz  "AI-ASM Kernel v0.4 booting..."
msg_gdt:
    .asciz  "  GDT loaded"
msg_idt:
    .asciz  "  IDT loaded (256 vectors)"
msg_pic:
    .asciz  "  PIC remapped"
msg_pit:
    .asciz  "  PIT initialized (100Hz)"
msg_kbd:
    .asciz  "  Keyboard initialized"
msg_mem:
    .asciz  "  Physical memory manager initialized"
msg_proc:
    .asciz  "  Process scheduler initialized"
msg_syscall:
    .asciz  "  Syscall interface (INT 0x80) ready"
msg_wasm:
    .asciz  "  WASM runtime initialized"
