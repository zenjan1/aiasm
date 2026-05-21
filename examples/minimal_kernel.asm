    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：_start (Multiboot1内核入口)
# 功能：最小32位保护模式内核，通过VGA和串口打印字符串
# 输入：EAX = Multiboot magic (0x2BADB002), EBX = Multiboot info
# 输出：在屏幕上显示"Hello from AI-ASM Kernel!"，串口输出相同内容
# -----------------------------------------------------------------------------
# 运行方式: make run-kernel
# -----------------------------------------------------------------------------

    .code32

# ============================================================================
# Multiboot1 header + PVH ELF Note - must be within first 8KB of ELF file
# ============================================================================
    .section .multiboot
    .globl _start
_start:
    .long  0x1BADB002          # magic
    .long  0x00000003          # flags: bit0=memory info, bit1=load ELF
    .long  0xE4524FFB          # checksum: -(magic + flags)

# PVH ELF Note for QEMU 8+ -kernel support
# type=0 (XEN_ELFNOTE_PHYS32_ENTRY), name="Xen"
# Must be in a NOTE section so it appears in PT_NOTE segment
    .section ".note.Xen","a",@note
    .align 4
pvh_note_start:
    .long  4                   # namesz
    .long  4                   # descsz (32-bit entry point)
    .long  0                   # type: XEN_ELFNOTE_PHYS32_ENTRY
    .ascii "Xen"               # name
    .byte  0                   # null terminator (padded to 4 bytes)
    .long  _start              # 32-bit entry point
pvh_note_end:
    .text

# ============================================================================
# Entry point - 32-bit protected mode
# ============================================================================
    .section .text

    # Set up stack
    lea     esp, [stack_top]

    # Init serial
    call    serial_init

    # Print message (both VGA and serial)
    call    print_msg

    # Halt
    cli
1:  hlt
    jmp     1b

# ============================================================================
# Serial port output (COM1 at 0x3f8)
# ============================================================================
serial_init:
    push    eax
    push    edx

    # Enable DLAB
    mov     dx, 0x3fb
    mov     al, 0x80
    out     dx, al

    # Set divisor (38400 baud, 115200/38400=3)
    mov     dx, 0x3f8
    mov     al, 0x03
    out     dx, al
    mov     dx, 0x3f9
    xor     al, al
    out     dx, al

    # 8-bit, no parity, 1 stop bit
    mov     dx, 0x3fb
    mov     al, 0x03
    out     dx, al

    pop     edx
    pop     eax
    ret

serial_putchar:
    push    edx
    push    eax

    # Wait for TX empty
    mov     dx, 0x3fd
1:  in      al, dx
    test    al, 0x20
    jz      1b

    # Send character
    pop     eax
    mov     dx, 0x3f8
    out     dx, al
    pop     edx
    ret

# ============================================================================
# VGA text output
# ============================================================================
vga_putchar:
    push    edx
    push    ecx
    push    ebx
    push    eax

    mov     ebx, [vga_cursor]
    mov     ecx, ebx

    # Handle newline
    cmp     al, 0x0a
    jne     .not_nl
    xor     edx, edx
    mov     eax, ecx
    mov     ecx, 80
    div     ecx
    inc     eax
    imul    ebx, eax, 80
    jmp     .done

.not_nl:
    # Handle carriage return
    cmp     al, 0x0d
    jne     .not_cr
    xor     edx, edx
    mov     eax, ecx
    mov     ecx, 80
    div     ecx
    imul    ebx, eax, 80
    jmp     .done

.not_cr:
    # Write char + attribute to VGA buffer at 0xb8000
    mov     edx, 0xb8000
    lea     edx, [edx + ebx * 2]
    mov     [edx], al
    mov     byte ptr [edx + 1], 0x07
    inc     ebx

.done:
    # Clamp cursor to screen size (80*25=2000)
    cmp     ebx, 2000
    jl      .store
    mov     ebx, 0

.store:
    mov     [vga_cursor], ebx
    pop     eax
    pop     ebx
    pop     ecx
    pop     edx
    ret

# ============================================================================
# Print message to both VGA and serial
# ============================================================================
print_msg:
    push    esi
    push    ecx
    push    edx
    push    ebx

    lea     esi, [msg]
    mov     ecx, msg_len

1:  cmp     ecx, 0
    je      2f
    movzx   eax, byte ptr [esi]

    # VGA output (preserves eax)
    push    eax
    call    vga_putchar
    pop     eax

    # Serial output
    push    eax
    call    serial_putchar
    pop     eax

    inc     esi
    dec     ecx
    jmp     1b

2:  pop     ebx
    pop     edx
    pop     ecx
    pop     esi
    ret

# ============================================================================
# BSS - stack and cursor
# ============================================================================
    .section .bss
    .space  4096
stack_top:

    .globl  vga_cursor
vga_cursor:
    .space  4

# ============================================================================
# Data
# ============================================================================
    .section .rodata
msg:
    .ascii  "Hello from AI-ASM Kernel!"
    .byte   13, 10
msg_len = . - msg
