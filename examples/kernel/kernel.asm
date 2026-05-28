    .intel_syntax noprefix
    .code32

    .section .text
    .align 4
mb_start:
    .long  0x1BADB002
    .long  0x00000003
    .long  0xE4524FFB

    .section ".note.Xen","a",@note
    .align  4
    .long  4; .long  4; .long  18
    .ascii "Xen"; .byte  0; .long  _start

    .section .text
    .globl _start
_start:
    lea     esp, [stack_top]
    mov     edi, offset __bss_start
    mov     ecx, offset __bss_end
    sub     ecx, edi
    shr     ecx, 2
    xor     eax, eax
    cld
    rep     stosd

    mov     eax, cr0
    and     eax, ~0x80000000
    mov     cr0, eax

    call    uart_init

    # === PCI Network device detection ===
    # Check device 3 on bus 0 (where QEMU places NICs)
    mov     dx, 0xCF8
    mov     eax, 0x80001800      # bus=0, dev=3, func=0, offset=0
    out     dx, eax
    mov     dx, 0xCFC
    in      eax, dx

    mov     esi, eax
    and     eax, 0xFFFF          # Vendor ID

    # Check for virtio-net (Red Hat 0x1AF4)
    cmp     ax, 0x1AF4
    je      .net_found_virtio

    # Check for e1000 (Intel 0x8086, device 0x100E)
    cmp     ax, 0x8086
    jne     .net_skip
    mov     eax, esi
    shr     eax, 16
    cmp     ax, 0x100E
    jne     .net_skip
    # Found e1000
    mov     esi, offset msg_e1000
    call    uart_puts

    # Read BAR0
    mov     dx, 0xCF8
    mov     eax, 0x80001810
    out     dx, eax
    mov     dx, 0xCFC
    in      eax, dx
    and     eax, 0xFFFFFFF0
    mov     [virtio_pci_temp2], eax
    mov     esi, offset msg_bar
    call    uart_puts
    mov     eax, [virtio_pci_temp2]
    call    print_hex8

    # Enable device
    mov     dx, 0xCF8
    mov     eax, 0x80001804
    out     dx, eax
    mov     dx, 0xCFC
    mov     eax, 7
    out     dx, eax

    # Store MMIO base and initialize e1000
    mov     edx, [virtio_pci_temp2]
    mov     [e1000_mmio_base], edx
    call    e1000_init

    jmp     .net_done

.net_found_virtio:
    mov     esi, offset msg_vfound
    call    uart_puts
    mov     dx, 0xCF8
    mov     eax, 0x80001810
    out     dx, eax
    mov     dx, 0xCFC
    in      eax, dx
    mov     [virtio_pci_temp2], eax
    mov     esi, offset msg_bar
    call    uart_puts
    mov     eax, [virtio_pci_temp2]
    call    print_hex8
    mov     esi, offset msg_vfail
    call    uart_puts
    jmp     .net_done

.net_skip:
    mov     esi, offset msg_net_skip
    call    uart_puts

.net_done:

.vdone:
    # Continue with rest of init
    call    vga_clear
    call    log_init

    mov     esi, offset msg_boot; mov edi, 1; call log_print
    call    gdt_load; mov esi, offset msg_gdt; mov edi, 1; call log_print
    call    idt_load; mov esi, offset msg_idt; mov edi, 1; call log_print
    call    pic_remap; mov esi, offset msg_pic; mov edi, 1; call log_print
    call    pit_init; mov esi, offset msg_pit; mov edi, 1; call log_print
    call    keyboard_init; mov esi, offset msg_kbd; mov edi, 1; call log_print
    call    memory_init; mov esi, offset msg_mem; mov edi, 1; call log_print
    call    process_init; mov esi, offset msg_proc; mov edi, 1; call log_print
    call    syscall_init; mov esi, offset msg_syscall; mov edi, 1; call log_print
    call    vfs_init; mov esi, offset msg_vfs; mov edi, 1; call log_print
    call    wasm_parser_init
    call    wasm_vm_init
    call    wasm_syscall_init
    mov     esi, offset msg_wasm; mov edi, 1; call log_print

    sti
    mov     ecx, 100000000
1:  loop    1b
    call    shell_run
    cli
1:  hlt
    jmp     1b

# ============================================================================
# e1000_init: Initialize Intel 82540EM e1000 NIC
# Uses MMIO base address from [e1000_mmio_base]
# ============================================================================
e1000_init:
    pushad
    mov     ebx, [e1000_mmio_base]   # MMIO base in ebx

    # Step 1: Device Reset
    # Set RST bit (bit 26) in CTRL register
    mov     eax, [ebx]               # Read CTRL
    or      eax, (1 << 26)           # Set RST
    mov     [ebx], eax

    # Wait for reset
    mov     ecx, 100000
.e1000_wait_rst:
    dec     ecx
    jz      .e1000_fail
    mov     eax, [ebx]
    test    eax, (1 << 26)
    jnz     .e1000_wait_rst

    # Step 2: Set Link Up (SLU=3, bit 6) and Speed (100Mbps=1, 30Mbps=0)
    # CTRL: SLU | ASDE | FRCSPD | FRCDPLX
    mov     dword ptr [ebx], (1 << 3) | (1 << 5) | (1 << 6)

    # Step 3: Read MAC address from EEPROM
    # EECD register (offset 0x0010)
    mov     eax, [ebx + 0x0010]
    or      eax, (1 << 8) | (1 << 9)   # Set REQ and ACK bits
    mov     [ebx + 0x0010], eax

    # Read EEPROM address 0 (MAC bytes 0-1)
    mov     eax, (0 << 16) | (1 << 26) | (1 << 17) | (1 << 1)
    mov     [ebx + 0x0014], eax

    # Wait for ACK
    mov     ecx, 1000
.e1000_ee_ack:
    dec     ecx
    jz      .e1000_skip_mac
    mov     edx, [ebx + 0x0014]
    test    edx, (1 << 1)
    jz      .e1000_ee_ack

    # Read data (MAC is in high 16 bits)
    mov     eax, [ebx + 0x0014]
    shr     eax, 16
    mov     [e1000_mac], al
    shr     eax, 8
    mov     [e1000_mac + 1], al

    # Read EEPROM address 1 (MAC bytes 2-3)
    mov     eax, (1 << 16) | (1 << 26) | (1 << 17) | (1 << 1)
    mov     [ebx + 0x0014], eax
    mov     ecx, 1000
.e1000_ee_ack2:
    dec     ecx
    jz      .e1000_skip_mac
    mov     edx, [ebx + 0x0014]
    test    edx, (1 << 1)
    jz      .e1000_ee_ack2
    mov     eax, [ebx + 0x0014]
    shr     eax, 16
    mov     [e1000_mac + 2], al
    shr     eax, 8
    mov     [e1000_mac + 3], al

    # Read EEPROM address 2 (MAC bytes 4-5)
    mov     eax, (2 << 16) | (1 << 26) | (1 << 17) | (1 << 1)
    mov     [ebx + 0x0014], eax
    mov     ecx, 1000
.e1000_ee_ack3:
    dec     ecx
    jz      .e1000_skip_mac
    mov     edx, [ebx + 0x0014]
    test    edx, (1 << 1)
    jz      .e1000_ee_ack3
    mov     eax, [ebx + 0x0014]
    shr     eax, 16
    mov     [e1000_mac + 4], al
    shr     eax, 8
    mov     [e1000_mac + 5], al

.e1000_skip_mac:
    # Print MAC address
    mov     esi, offset msg_e100mac
    call    uart_puts
    movzx   eax, byte ptr [e1000_mac]
    call    print_hex2
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [e1000_mac + 1]
    call    print_hex2
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [e1000_mac + 2]
    call    print_hex2
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [e1000_mac + 3]
    call    print_hex2
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [e1000_mac + 4]
    call    print_hex2
    mov     al, ':'
    call    uart_putc
    movzx   eax, byte ptr [e1000_mac + 5]
    call    print_hex2
    mov     al, 0x0D
    call    uart_putc
    mov     al, 0x0A
    call    uart_putc

    # Step 4: Set up Receive
    # Clear RCTL first
    mov     dword ptr [ebx + 0x0100], 0

    # Set RCTL: RXEN=1 | SBP=1 | BSIZE=256 | BSEX=1 | SECRC=1
    mov     dword ptr [ebx + 0x0100], (1 << 1) | (1 << 15) | (1 << 25) | (1 << 26) | (1 << 27)

    # Set up RX descriptor ring
    mov     eax, offset e1000_rx_desc
    mov     [ebx + 0x2800], eax      # RDBAL
    shr     eax, 32
    mov     [ebx + 0x2804], eax      # RDBAH

    # RDLEN: 128 bytes (8 descriptors)
    mov     dword ptr [ebx + 0x2808], 128

    # RDH = 0, RDT = 0
    mov     dword ptr [ebx + 0x2810], 0
    mov     dword ptr [ebx + 0x2818], 0

    # Set RX descriptor 0: buffer address
    mov     eax, offset e1000_rx_buf
    mov     edi, offset e1000_rx_desc
    mov     [edi], eax
    mov     dword ptr [edi + 4], 0
    mov     word ptr [edi + 8], 1536
    mov     word ptr [edi + 10], 0

    # Initialize descriptor 1-7
    mov     ecx, 1
.e1000_init_rx_desc:
    mov     eax, offset e1000_rx_buf
    mov     edi, ecx
    shl     edi, 4               # * 16
    add     edi, offset e1000_rx_desc
    mov     [edi], eax
    mov     dword ptr [edi + 4], 0
    mov     word ptr [edi + 8], 1536
    mov     word ptr [edi + 10], 0
    inc     ecx
    cmp     ecx, 8
    jl      .e1000_init_rx_desc

    # Set RDT = 7 (give all descriptors to hardware)
    mov     dword ptr [ebx + 0x2818], 7

    # Step 5: Set up Transmit
    # TCTL: TXEN=1 | PSP=1 | CT=0x10 | COLD=0x40
    mov     dword ptr [ebx + 0x0400], (1 << 1) | (1 << 3) | (0x10 << 4) | (0x40 << 12)

    # TIPG: inter-packet gap
    mov     dword ptr [ebx + 0x0410], 0x0060200A

    # TX descriptor ring
    mov     eax, offset e1000_tx_desc
    mov     [ebx + 0x3800], eax      # TDBAL
    shr     eax, 32
    mov     [ebx + 0x3804], eax      # TDBAH

    # TDLEN: 128 bytes
    mov     dword ptr [ebx + 0x3808], 128

    # TDH = 0, TDT = 0
    mov     dword ptr [ebx + 0x3810], 0
    mov     dword ptr [ebx + 0x3818], 0

    # Print success
    mov     esi, offset msg_e100ok
    call    uart_puts

    popad
    ret

.e1000_fail:
    mov     esi, offset msg_e100fail
    call    uart_puts
    popad
    ret

# print_hex2: print a byte as 2 hex digits (eax = byte)
print_hex2:
    push    eax
    push    ecx
    mov     ecx, 2
.ph2:
    rol     eax, 4
    mov     edx, eax
    and     edx, 0xF
    cmp     edx, 9
    jbe     .ph2d
    add     edx, 7
.ph2d:
    add     edx, '0'
    mov     al, dl
    call    uart_putc
    loop    .ph2
    pop     ecx
    pop     eax
    ret

print_hex_byte:
    push    eax; push    ecx; push    edx
    mov     ecx, 2
.phb:
    rol     eax, 4
    mov     edx, eax
    and     edx, 0xF
    cmp     edx, 9
    jbe     .b1
    add     edx, 7
.b1:
    add     edx, '0'
    mov     eax, edx
    call    uart_putc
    pop     edx; pop    ecx; pop    eax; ret

print_hex8:
    push    ecx; push    edx; push    esi
    mov     esi, eax; mov     ecx, 8
.phl:
    rol     esi, 4; mov     edx, esi; and     dl, 0x0F
    cmp     dl, 9; jbe     .phld; add     dl, 7
.phld:
    add     dl, '0'; mov     eax, edx; call    uart_putc; loop    .phl
    mov     al, 0x0D; call    uart_putc; mov     al, 0x0A; call    uart_putc
    pop     esi; pop     edx; pop     ecx; ret

    .globl  kernel_halt
kernel_halt:
    cli
    mov     dx, 0xF4; xor al, al; out dx, al
    xor     eax, eax; push eax; push eax; lidt [esp]; add esp, 8
    int     0x03
1:  hlt; jmp 1b

    .globl  kernel_reboot
kernel_reboot:
    cli
    mov     al, 0xFE; out 0x64, al
1:  hlt; jmp 1b

    .section .bss
    .space  8192
stack_top:

virtio_pci_temp:
    .space  4
virtio_pci_temp2:
    .space  4
virtio_pci_temp3:
    .space  4
e1000_mmio_base:
    .space  4
e1000_rx_buf:
    .space  2048
e1000_tx_buf:
    .space  2048
e1000_rx_desc:
    .space  128                # 8 descriptors * 16 bytes
e1000_tx_desc:
    .space  128                # 8 descriptors * 16 bytes
e1000_mac:
    .space  6

    .section .rodata
msg_bar:    .asciz  "BAR0 = "
msg_vfound: .asciz "\n  virtio-net found (MMIO in ISA hole - not accessible)\n"
msg_vfail:  .asciz  "  Skipping virtio (needs MMIO mapping)\n"
msg_e1000:  .asciz "\n  e1000 found: "
msg_e100mac:.asciz "  MAC = "
msg_e100ok: .asciz "  e1000 initialized\n"
msg_e100fail:.asciz "  e1000 reset timeout!\n"
msg_net_skip:.asciz "  No known NIC found\n"
msg_boot:    .asciz  "AI-ASM Kernel v0.5 booting..."
msg_gdt:     .asciz  "  GDT loaded"
msg_idt:     .asciz  "  IDT loaded (256 vectors)"
msg_pic:     .asciz  "  PIC remapped"
msg_pit:     .asciz  "  PIT initialized (100Hz)"
msg_kbd:     .asciz  "  Keyboard initialized"
msg_mem:     .asciz  "  Physical memory manager initialized"
msg_proc:    .asciz  "  Process scheduler initialized"
msg_syscall: .asciz  "  Syscall interface (INT 0x80) ready"
msg_vfs:     .asciz  "  Virtual filesystem initialized"
msg_wasm:    .asciz  "  WASM runtime initialized"
