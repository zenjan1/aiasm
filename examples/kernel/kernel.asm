    .intel_syntax noprefix
    .code32

# =============================================================================
# Multiboot Header (must be in first 8KB of ELF file)
# =============================================================================
    .set MULTIBOOT_MAGIC,    0x1BADB002
    .set MULTIBOOT_FLAGS,    0x00000003    # Page align + memory info request
    .set MULTIBOOT_CHECKSUM, -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)

    .section .multiboot, "a"
    .align 4
multiboot_header:
    .long MULTIBOOT_MAGIC
    .long MULTIBOOT_FLAGS
    .long MULTIBOOT_CHECKSUM

# =============================================================================
# Xen note section (for Xen compatibility)
# =============================================================================
    .section ".note.Xen","a",@note
    .align  4
    .long 4; .long  4; .long  18
    .ascii "Xen"; .byte  0; .long  _start

# =============================================================================
# Entry Point
# =============================================================================
    .section .text
    .globl _start
_start:
    # Save Multiboot info pointer (ebx) from GRUB
    mov     [multiboot_info_ptr], ebx
    # Set up stack
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

    # === FPU Initialization ===
    # Enable FPU: Clear EM (Emulation) bit, Set MP (Monitor co-processor) bit
    mov     eax, cr0
    and     eax, ~0x04           # Clear EM bit (bit 2)
    or      eax, 0x02            # Set MP bit (bit 1)
    mov     cr0, eax
    fninit                       # Initialize FPU state

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

    # Initialize static IP (DHCP will override if used)
    mov     dword ptr [e1000_our_ip], 0x0F02000A  # 10.0.2.15
    mov     dword ptr [e1000_arp_ip], 0x0F02000A
    mov     dword ptr [e1000_our_ip_ready], 1

    # Read IRQ line from PCI config (offset 60)
    mov     dx, 0xCF8
    mov     eax, 0x8000183C      # bus=0, dev=3, func=0, offset=0x3C
    out     dx, eax
    mov     dx, 0xCFC
    in      eax, dx
    and     eax, 0xFF            # IRQ line in low byte
    mov     [e1000_irq_line], eax

    # Register e1000 IRQ handler (vector = IRQ + 32)
    add     eax, 32
    mov     edi, eax
    mov     eax, offset e1000_irq_handler
    call    idt_set_gate

    # Enable e1000 interrupts (set IMS register)
    mov     ebx, [e1000_mmio_base]
    mov     dword ptr [ebx + 0x00D0], 0x0000009D  # RX|RXO|RXDMT0|LSC|TXDW

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
    call    tss_init; mov esi, offset msg_tss; mov edi, 1; call log_print
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
    call    ata_init; mov esi, offset msg_ata; mov edi, 1; call log_print
    call    fat32_init; mov esi, offset msg_fat32; mov edi, 1; call log_print

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

    # Initialize TCP HTTP server enabled by default
    mov     dword ptr [tcp_http_enabled], 1

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

    # Mark e1000 initialized successfully
    mov     dword ptr [e1000_status], 1

    popad
    ret

.e1000_fail:
    mov     esi, offset msg_e100fail
    call    uart_puts
    popad
    ret

# ============================================================================
# e1000_transmit: Send a packet via e1000
# Input: esi = packet address, ecx = packet length
# Output: eax = 0 success, 1 failure
# ============================================================================
    .globl  e1000_transmit
e1000_transmit:
    pushad
    mov     ebx, [e1000_mmio_base]

    # Copy packet data to TX buffer
    mov     edi, offset e1000_tx_buf
    mov     eax, ecx             # save length
    shr     ecx, 2               # dword count
    cld
    rep     movsd
    mov     ecx, eax
    and     ecx, 3               # remaining bytes
    rep     movsb
    mov     ecx, eax             # restore length

    # Set TX descriptor 0
    mov     edi, offset e1000_tx_desc
    mov     eax, offset e1000_tx_buf
    mov     [edi], eax           # buffer address low
    mov     dword ptr [edi + 4], 0  # buffer address high
    mov     word ptr [edi + 8], cx    # length
    mov     word ptr [edi + 10], 0    # CSO/CSS (checksum offset)

    # Set CMD: EOP=bit0 | RS=bit3 | IFCS=bit4 = 0x0B
    mov     byte ptr [edi + 12], 0x0B
    mov     byte ptr [edi + 13], 0    # reserved

    # Send: write TDT=1 (one descriptor ready; TDH=0, so TDT must be > TDH)
    mov     dword ptr [ebx + 0x3818], 1

    # Wait for completion: poll DD bit (bit 0) in status byte at offset 10
    # Use PIT ticks to yield to QEMU event loop (avoid busy-wait deadlock in TCG)
    mov     edx, 100
    mov     esi, 3                     # max retry count
.tx_poll:
    dec     edx
    jz      .tx_retry

    # Check status byte: DD bit set by hardware when done
    test    byte ptr [edi + 10], 1
    jnz     .tx_success

    # Yield: read PIT channel 0 to give QEMU event loop a chance
    in      al, 0x40
    jmp     .tx_poll

.tx_success:
    mov     [e1000_tx_len], ecx
    xor     eax, eax             # success
    jmp     .tx_done

.tx_timeout:
    # TX timeout - expected in QEMU without network backend
    # e1000 may still transmit but DD bit may not be set in TCG
    mov     eax, 1               # failure

.tx_done:
    popad
    ret

.tx_retry:
    dec     esi
    jz      .tx_timeout              # retry limit exceeded
    mov     edx, 100                 # reset timeout counter
    # Re-notify: set TDT=1
    mov     dword ptr [ebx + 0x3818], 1
.tx_poll2:
    dec     edx
    jz      .tx_timeout
    # Check status byte: DD bit set by hardware when done
    test    byte ptr [edi + 10], 1
    jnz     .tx_success
    # Yield: read PIT channel 0
    in      al, 0x40
    jmp     .tx_poll2

    mov     [e1000_tx_len], ecx
    xor     eax, eax             # success
    jmp     .tx_done

# ============================================================================
# e1000_poll: Check for received packets, process ICMP
# Output: eax = number of packets received
# ============================================================================
    .globl  e1000_poll
e1000_poll:
    pushad
    mov     ebx, [e1000_mmio_base]

    # Read RDT (Receive Descriptor Tail)
    mov     eax, [ebx + 0x2818]
    mov     [e1000_rx_idx], eax

    # Check if hardware has written to descriptor (DD bit)
    # Get current RDH
    mov     eax, [ebx + 0x2810]
    cmp     eax, [e1000_rx_idx]
    je      .poll_none          # no new packets

    # There are packets to process
    # For simplicity, process one packet at a time from the shared buffer
    mov     esi, offset e1000_rx_buf

    # Check Ethernet type
    cmp     word ptr [esi + 12], 0x0608  # little-endian 0x0806 = ARP
    je      .poll_arp

    # Check for IPv4 (0x0800)
    cmp     word ptr [esi + 12], 0x0008
    jne     .poll_next

    # Check IP protocol (offset 23)
    cmp     byte ptr [esi + 23], 6         # TCP
    je      .poll_tcp
    cmp     byte ptr [esi + 23], 17        # UDP
    je      .poll_udp
    cmp     byte ptr [esi + 23], 1         # ICMP
    jne     .poll_next

    # This is an ICMP packet, handle it
    call    e1000_handle_icmp
    jmp     .poll_next

.poll_udp:
    call    e1000_handle_udp
    jmp     .poll_next

.poll_tcp:
    call    e1000_handle_tcp
    jmp     .poll_next

.poll_arp:
    call    e1000_handle_arp

.poll_next:
    # Reset the descriptor and update RDT
    # Re-give all descriptors to hardware
    mov     dword ptr [ebx + 0x2818], 7

    mov     eax, 1               # 1 packet processed
    jmp     .poll_done

.poll_none:
    xor     eax, eax

.poll_done:
    popad
    ret

# e1000_poll_delay: Poll for packets with a small delay (for ping timeout)
# Polls and burns ~10ms of CPU time
    .globl  e1000_poll_delay
e1000_poll_delay:
    push    eax
    push    ecx
    push    edx
    call    e1000_poll
    mov     ecx, 100000           # ~10ms delay loop
.poll_delay_loop:
    dec     ecx
    jnz     .poll_delay_loop
    pop     edx
    pop     ecx
    pop     eax
    ret

# ============================================================================
# e1000_handle_icmp: Handle ICMP Echo Request, send Echo Reply
# Input: esi = packet buffer address (RX buffer)
# Uses: e1000_tx_buf for reply
# ============================================================================
e1000_handle_icmp:
    pushad

    # Check if this is an ICMP Echo Reply (type=0) for our ping
    # ICMP type at offset: 14(IP) + 20(ICMP header start) = 34
    movzx   eax, byte ptr [esi + 34]
    cmp     al, 0                  # Echo Reply
    jne     .icmp_check_request

    # Check identifier matches our ping (0x5555)
    movzx   eax, word ptr [esi + 38]
    cmp     ax, 0x5555
    jne     .icmp_check_request

    # It's our ping reply - signal ready
    mov     dword ptr [e1000_icmp_reply_ready], 1
    mov     dword ptr [e1000_icmp_reply_rtt], 1  # approximate RTT

.icmp_check_request:
    # Check if this is an Echo Request (type=8)
    movzx   eax, byte ptr [esi + 34]
    cmp     al, 8
    jne     .icmp_not_ours

    # Original echo request handling continues below
    # Swap source/dest MAC
    mov     edi, offset e1000_tx_buf

    # Dest MAC = source MAC of received packet (offset 6 in RX)
    mov     eax, [esi]
    mov     [edi], eax
    mov     ax, [esi + 4]
    mov     [edi + 4], ax

    # Source MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax

    # EtherType = IPv4 (0x0800)
    mov     word ptr [edi + 12], 0x0800

    # Build IP header
    mov     edi, offset e1000_tx_buf + 14

    # Version + IHL = 0x45
    mov     byte ptr [edi], 0x45
    # TOS = 0
    mov     byte ptr [edi + 1], 0
    # Total length = 20 (IP) + 8 (ICMP) + payload
    # Copy from received packet
    mov     eax, [esi + 16]     # received total length
    mov     [edi + 2], ax

    # Identification
    mov     ax, [esi + 4]
    mov     [edi + 4], ax

    # Flags + Fragment offset
    mov     ax, [esi + 6]
    mov     [edi + 6], ax

    # TTL = 64
    mov     byte ptr [edi + 8], 64
    # Protocol = ICMP (1)
    mov     byte ptr [edi + 9], 1

    # Swap source/dest IP
    mov     eax, [esi + 26]     # dest IP (was target)
    mov     [edi + 12], eax     # becomes source IP
    mov     eax, [esi + 30]     # source IP (was sender)
    mov     [edi + 16], eax     # becomes dest IP

    # Checksum = 0 for calculation
    mov     word ptr [edi + 10], 0

    # Calculate IP checksum
    mov     ecx, 10             # 10 words
    xor     edx, edx            # sum
    mov     esi_temp, edi       # save edi pointer
.ip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .ip_cksum

    # Fold sum
.fold_cksum:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .fold_done
    add     eax, 1
.fold_done:
    not     ax
    mov     edi, esi_temp
    add     edi, 10
    mov     [edi], ax

    # Build ICMP Echo Reply (type 0, code 0)
    mov     edi, esi_temp
    add     edi, 20             # skip IP header
    mov     byte ptr [edi], 0   # type = Echo Reply
    mov     byte ptr [edi + 1], 0  # code = 0

    # ICMP checksum = 0 for calc
    mov     word ptr [edi + 2], 0

    # Copy identifier + sequence from request
    mov     eax, [esi + 34]
    mov     [edi + 4], eax

    # Copy ICMP payload
    mov     eax, [esi + 18]     # IP total length
    sub     eax, 28             # subtract IP(20) + ICMP(8)
    mov     ecx, eax
    shr     ecx, 2
    mov     esi, offset e1000_rx_buf + 38
    mov     edi, offset e1000_tx_buf + 38
    rep     movsd

    # Calculate ICMP checksum
    mov     eax, [esi + 18]     # IP total length
    sub     eax, 20             # IP header only
    mov     ecx, eax
    shr     ecx, 1              # word count
    mov     edi, esi_temp
    add     edi, 20             # start of ICMP
    xor     edx, edx
.icmp_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .icmp_cksum

    # Fold
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .icmp_fold_done
    add     eax, 1
.icmp_fold_done:
    not     ax
    mov     edi, esi_temp
    add     edi, 22
    mov     [edi], ax

    # Calculate packet length and transmit
    mov     eax, [esi + 18]     # IP total length
    add     eax, 14             # + Ethernet header

    mov     esi, offset e1000_tx_buf
    mov     ecx, eax
    call    e1000_transmit

    # Print "ICMP reply sent"
    mov     esi, offset msg_icmp_sent
    call    uart_puts

.icmp_not_ours:
    popad
    ret

# ============================================================================
# e1000_handle_arp: Handle ARP packet (request or reply)
# Input: esi = packet buffer address (RX buffer)
# ============================================================================
e1000_handle_arp:
    pushad

    # Check ARP operation (offset 20: 1=request, 2=reply)
    cmp     word ptr [esi + 20], 1    # ARP request?
    je      .handle_arp_request
    cmp     word ptr [esi + 20], 2    # ARP reply?
    je      .handle_arp_reply
    jmp     .arp_done

.handle_arp_request:
    # Cache sender IP->MAC from request
    mov     eax, [esi + 28]           # sender IP
    push    esi
    add     esi, 22                   # pointer to sender MAC
    call    arp_cache_insert
    pop     esi

    # Check if request is for our IP
    mov     eax, [esi + 38]           # target IP in request
    cmp     eax, [e1000_arp_ip]
    jne     .arp_done

    # Build ARP reply in TX buffer
    mov     edi, offset e1000_tx_buf

    # Dest MAC = sender MAC (offset 22)
    mov     eax, [esi + 22]
    mov     [edi], eax
    mov     ax, [esi + 26]
    mov     [edi + 4], ax

    # Source MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax

    # EtherType = ARP (0x0806)
    mov     word ptr [edi + 12], 0x0608

    # ARP reply header
    mov     word ptr [edi + 14], 1     # HW type = Ethernet
    mov     word ptr [edi + 16], 0x0800  # Protocol = IPv4
    mov     byte ptr [edi + 18], 6     # HW size
    mov     byte ptr [edi + 19], 4     # Protocol size
    mov     word ptr [edi + 20], 2     # Operation = reply

    # Sender MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 22], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 26], ax

    # Sender IP = our IP
    mov     eax, [e1000_arp_ip]
    mov     [edi + 28], eax

    # Target MAC = request sender MAC (already copied above)
    mov     eax, [esi + 22]
    mov     [edi + 32], eax
    mov     ax, [esi + 26]
    mov     [edi + 36], ax

    # Target IP = request sender IP (offset 28)
    mov     eax, [esi + 28]
    mov     [edi + 38], eax

    # Send ARP reply (42 bytes: 14 eth + 28 ARP)
    mov     esi, offset e1000_tx_buf
    mov     ecx, 42
    call    e1000_transmit

    jmp     .arp_done

.handle_arp_reply:
    # Save sender MAC for our pending request
    mov     eax, [esi + 22]
    mov     [e1000_arp_mac], eax
    mov     ax, [esi + 26]
    mov     [e1000_arp_mac + 4], ax

    # Also insert into ARP cache
    # Sender IP is at offset 28, sender MAC at offset 22
    mov     eax, [esi + 28]      # sender IP
    push    esi
    add     esi, 22              # pointer to sender MAC
    call    arp_cache_insert
    pop     esi

    # Signal that ARP reply was received
    mov     dword ptr [e1000_arp_ready], 1

.arp_done:
    popad
    ret

# ============================================================================
# arp_cache_lookup: Look up IP in ARP cache
# Input: eax = IP address
# Output: eax = 0 if found (MAC in [e1000_arp_mac]), 1 if not found
# ============================================================================
arp_cache_lookup:
    push    ecx
    push    edx
    push    esi

    mov     ecx, [e1000_arp_cache_size]
    test    ecx, ecx
    jz      .acl_not_found

    lea     esi, [e1000_arp_cache]
.acl_loop:
    cmp     dword ptr [esi], eax    # compare IP
    je      .acl_found
    add     esi, 12                 # next entry
    loop    .acl_loop

.acl_not_found:
    mov     eax, 1
    jmp     .acl_done

.acl_found:
    # Copy MAC to e1000_arp_mac
    mov     eax, [esi + 4]
    mov     [e1000_arp_mac], eax
    mov     ax, [esi + 8]
    mov     [e1000_arp_mac + 4], ax
    xor     eax, eax                # success

.acl_done:
    pop     esi
    pop     edx
    pop     ecx
    ret

# ============================================================================
# arp_cache_insert: Insert IP->MAC mapping into ARP cache
# Input: eax = IP, esi = pointer to 6-byte MAC
# ============================================================================
arp_cache_insert:
    pushad

    # Check if entry already exists
    call    arp_cache_lookup
    test    eax, eax
    jz      .aci_done               # already in cache

    # Get cache size
    mov     ecx, [e1000_arp_cache_size]
    cmp     ecx, 8
    jge     .aci_done               # cache full

    # Calculate offset = ecx * 12
    mov     edx, ecx
    shl     ecx, 3                   # ecx * 8
    shl     edx, 2                   # edx * 4
    add     ecx, edx                 # ecx = size * 12
    lea     edi, [e1000_arp_cache + ecx]

    # Restore IP and MAC from stack (saved by pushad)
    # IP was in eax before call, now at [esp + 28] (saved eax in pushad)
    mov     eax, [esp + 28]
    mov     [edi], eax               # store IP

    # MAC pointer was in esi, at [esp + 20]
    mov     esi, [esp + 20]
    mov     eax, [esi]
    mov     [edi + 4], eax
    mov     ax, [esi + 4]
    mov     [edi + 8], ax

    # Increment count
    inc     dword ptr [e1000_arp_cache_size]

.aci_done:
    popad
    ret

# ============================================================================
# tcp_conn_lookup: Find connection by remote IP + port
# Input: eax = remote IP, cx = remote port
# Output: eax = slot index (0-3), or -1 if not found
#         ebx = pointer to connection entry (if found)
# ============================================================================
tcp_conn_lookup:
    push    ecx
    push    edx
    push    esi

    movzx   edx, cx                  # remote port in edx
    mov     ecx, TCP_MAX_CONN
    lea     esi, [tcp_conn_table]

.tcp_lookup_loop:
    test    ecx, ecx
    jz      .tcp_lookup_not_found

    # Check if slot is active (state != 0)
    cmp     byte ptr [esi], 0
    je      .tcp_lookup_next

    # Check IP match
    cmp     dword ptr [esi + 4], eax
    jne     .tcp_lookup_next

    # Check port match
    cmp     word ptr [esi + 8], dx
    je      .tcp_lookup_found

.tcp_lookup_next:
    add     esi, TCP_CONN_ENTRY_SIZE
    dec     ecx
    jmp     .tcp_lookup_loop

.tcp_lookup_found:
    # Calculate slot index: (esi - tcp_conn_table) / 24
    mov     eax, esi
    sub     eax, offset tcp_conn_table
    mov     edx, TCP_CONN_ENTRY_SIZE
    xor     ecx, ecx
.tcp_lookup_div:
    cmp     eax, edx
    jl      .tcp_lookup_div_done
    sub     eax, edx
    inc     ecx
    jmp     .tcp_lookup_div
.tcp_lookup_div_done:
    mov     ebx, esi                 # ebx = entry pointer
    pop     esi
    pop     edx
    pop     ecx
    ret

.tcp_lookup_not_found:
    mov     eax, -1
    xor     ebx, ebx
    pop     esi
    pop     edx
    pop     ecx
    ret

# ============================================================================
# tcp_conn_alloc: Allocate a new connection slot
# Input: eax = remote IP, cx = remote port
# Output: eax = slot index, ebx = pointer to entry, or eax = -1 if full
# ============================================================================
tcp_conn_alloc:
    push    ecx
    push    edx
    push    esi

    movzx   edx, cx
    mov     ecx, TCP_MAX_CONN
    lea     esi, [tcp_conn_table]

.tcp_alloc_loop:
    test    ecx, ecx
    jz      .tcp_alloc_full

    # Check if slot is free (state == 0)
    cmp     byte ptr [esi], 0
    je      .tcp_alloc_found

    add     esi, TCP_CONN_ENTRY_SIZE
    dec     ecx
    jmp     .tcp_alloc_loop

.tcp_alloc_found:
    # Initialize connection entry
    mov     byte ptr [esi], 3        # state = SYN_RECV (incoming SYN)
    mov     [esi + 4], eax           # remote IP
    mov     [esi + 8], dx            # remote port
    mov     dword ptr [esi + 12], 0  # local_seq (will be set)
    mov     dword ptr [esi + 16], 0  # remote_seq
    mov     dword ptr [esi + 20], 0  # remote_ack
    mov     dword ptr [esi + 24], 0  # recv_len (past entry, use separate var)

    # Calculate slot index
    mov     eax, esi
    sub     eax, offset tcp_conn_table
    mov     edx, TCP_CONN_ENTRY_SIZE
    xor     ecx, ecx
.tcp_alloc_div:
    cmp     eax, edx
    jl      .tcp_alloc_div_done
    sub     eax, edx
    inc     ecx
    jmp     .tcp_alloc_div
.tcp_alloc_div_done:

    # Increment active count
    inc     dword ptr [tcp_conn_active_count]

    pop     esi
    pop     edx
    pop     ecx
    ret

.tcp_alloc_full:
    mov     eax, -1
    xor     ebx, ebx
    pop     esi
    pop     edx
    pop     ecx
    ret

# ============================================================================
# tcp_conn_free: Free a connection slot (called on FIN/RST close)
# Input: ebx = pointer to connection entry (or NULL)
# ============================================================================
tcp_conn_free:
    push    eax
    push    ecx
    push    esi

    test    ebx, ebx
    jz      .free_done

    # Zero out the connection entry
    mov     esi, ebx
    mov     ecx, TCP_CONN_ENTRY_SIZE / 4
    xor     eax, eax
.clear_loop:
    mov     [esi], eax
    add     esi, 4
    loop    .clear_loop

    # Decrement active count
    mov     eax, [tcp_conn_active_count]
    test    eax, eax
    jz      .free_done
    dec     eax
    mov     [tcp_conn_active_count], eax

    # Clear global slot pointer
    xor     ebx, ebx
    mov     [tcp_conn_slot_ptr], ebx

.free_done:
    pop     esi
    pop     ecx
    pop     eax
    ret

# ============================================================================
# e1000_send_icmp_echo: Send ICMP Echo Request (ping)
# Input: eax = target IP (host byte order: 10.0.2.2 = 0x0A000202)
# ============================================================================
e1000_send_icmp_echo:
    pushad

    # Save target IP
    mov     [e1000_ping_target_ip], eax

    # Clear ready flag
    xor     eax, eax
    mov     [e1000_icmp_reply_ready], eax

    # Build Ethernet frame in TX buffer
    mov     edi, offset e1000_tx_buf

    # Dest MAC = broadcast (ARP not resolved yet)
    mov     dword ptr [edi], 0xFFFFFFFF
    mov     word ptr [edi + 4], 0xFFFF

    # Source MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax

    # EtherType = IPv4
    mov     word ptr [edi + 12], 0x0008

    # IP header at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45       # Version 4, IHL 5
    mov     byte ptr [edi + 1], 0      # TOS
    mov     word ptr [edi + 2], 60     # Total length: 20(IP) + 8(ICMP) + 32(data)
    mov     word ptr [edi + 4], 0x1234 # Identification
    mov     word ptr [edi + 6], 0x4000 # Don't fragment
    mov     byte ptr [edi + 8], 64     # TTL
    mov     byte ptr [edi + 9], 1      # Protocol = ICMP
    mov     word ptr [edi + 10], 0     # Checksum (placeholder)
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi + 12], eax  # Source IP: 10.0.2.15
    mov     eax, [e1000_ping_target_ip]
    mov     [edi + 16], eax

    # IP checksum
    push    edi
    xor     edx, edx
    mov     ecx, 10
.ipcsum_loop:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .ipcsum_loop
.ipcsum_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .ipcsum_fold_done
    add     eax, 1
.ipcsum_fold_done:
    not     ax
    pop     edi
    mov     [edi + 10], ax

    # ICMP Echo Request header at offset 34
    mov     edi, offset e1000_tx_buf + 34
    mov     byte ptr [edi], 8        # type = Echo Request
    mov     byte ptr [edi + 1], 0    # code = 0
    mov     word ptr [edi + 2], 0    # checksum placeholder
    mov     word ptr [edi + 4], 0x5555  # identifier
    mov     eax, [icmp_echo_seq]
    mov     [edi + 6], ax              # sequence number

    # ICMP payload: 32 bytes of test data
    mov     edi, offset e1000_tx_buf + 42
    mov     eax, 0x01020304
    mov     [edi], eax
    mov     [edi + 4], eax
    mov     [edi + 8], eax
    mov     [edi + 12], eax
    mov     eax, 0x05060708
    mov     [edi + 16], eax
    mov     [edi + 20], eax
    mov     [edi + 24], eax
    mov     [edi + 28], eax

    # Calculate ICMP checksum (8 header + 32 data = 40 bytes)
    mov     esi, offset e1000_tx_buf + 34
    mov     ecx, 40
    call    ip_checksum
    mov     [e1000_tx_buf + 34 + 2], ax

    # Increment sequence number
    mov     eax, [icmp_echo_seq]
    inc     eax
    mov     [icmp_echo_seq], eax

    # Send: 14(eth) + 20(IP) + 8(ICMP) + 32(data) = 74 bytes
    mov     esi, offset e1000_tx_buf
    mov     ecx, 74
    call    e1000_transmit

    # Wait for reply (poll for ~2 seconds)
    mov     edx, 200              # 200 * 10ms = 2s timeout
.icmp_wait_loop:
    call    e1000_poll_delay
    cmp     dword ptr [e1000_icmp_reply_ready], 1
    je      .icmp_reply_received
    dec     edx
    jnz     .icmp_wait_loop

    # Timeout - no reply
    mov     esi, offset msg_ping_timeout
    call    uart_puts
    jmp     .icmp_echo_done

.icmp_reply_received:
    mov     esi, offset msg_ping_reply
    call    uart_puts
    mov     eax, [e1000_icmp_reply_rtt]
    call    print_dec5
    mov     esi, offset msg_ping_ms
    call    uart_puts

.icmp_echo_done:
    popad
    ret

# ============================================================================
# e1000_send_dhcp_discover: Send DHCP Discover (UDP broadcast)
# ============================================================================
    .globl  e1000_send_dhcp_discover
e1000_send_dhcp_discover:
    pushad

    # Generate random XID
    mov     eax, [tick_count]
    mov     [e1000_dhcp_xid], eax

    # Build Ethernet frame in TX buffer
    mov     edi, offset e1000_tx_buf

    # Dest MAC = broadcast (FF:FF:FF:FF:FF:FF)
    mov     dword ptr [edi], 0xFFFFFFFF
    mov     word ptr [edi + 4], 0xFFFF

    # Source MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax

    # EtherType = IPv4
    mov     word ptr [edi + 12], 0x0008

    # IP header at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45       # Version 4, IHL 5
    mov     byte ptr [edi + 1], 0x10   # TOS
    mov     word ptr [edi + 2], 300    # Total length: 20(IP) + 8(UDP) + DHCP payload
    mov     word ptr [edi + 4], 0x1234
    mov     word ptr [edi + 6], 0x0000 # Don't fragment
    mov     byte ptr [edi + 8], 128    # TTL
    mov     byte ptr [edi + 9], 17     # Protocol = UDP
    mov     word ptr [edi + 10], 0     # Checksum placeholder
    mov     dword ptr [edi + 12], 0    # Source IP = 0.0.0.0
    mov     dword ptr [edi + 16], 0xFFFFFFFF  # Dest IP = 255.255.255.255

    # IP checksum
    push    edi
    xor     edx, edx
    mov     ecx, 10
.dhcip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .dhcip_cksum
.dhcip_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .dhcip_fold_done
    add     eax, 1
.dhcip_fold_done:
    not     ax
    pop     edi
    mov     [edi + 10], ax

    # UDP header at offset 34
    mov     edi, offset e1000_tx_buf + 34
    mov     word ptr [edi], 68         # Source port = 68 (DHCP client)
    mov     word ptr [edi + 2], 67     # Dest port = 67 (DHCP server)
    mov     word ptr [edi + 4], 272    # UDP length = 8 + DHCP payload (264)
    mov     word ptr [edi + 6], 0      # UDP checksum = 0

    # DHCP payload at offset 42
    mov     edi, offset e1000_tx_buf + 42
    mov     byte ptr [edi], 1          # op = 1 (request)
    mov     byte ptr [edi + 1], 1      # htype = 1 (Ethernet)
    mov     byte ptr [edi + 2], 6      # hlen = 6
    mov     byte ptr [edi + 3], 0      # hops = 0
    mov     eax, [e1000_dhcp_xid]
    mov     [edi + 4], eax             # xid
    mov     word ptr [edi + 8], 0      # secs = 0
    mov     word ptr [edi + 10], 0x8000 # flags = broadcast (0x8000)
    mov     dword ptr [edi + 12], 0    # ciaddr = 0.0.0.0
    mov     dword ptr [edi + 16], 0    # yiaddr = 0.0.0.0
    mov     dword ptr [edi + 20], 0    # siaddr = 0.0.0.0
    mov     dword ptr [edi + 24], 0    # giaddr = 0.0.0.0

    # chaddr = our MAC (16 bytes)
    mov     eax, [e1000_mac]
    mov     [edi + 28], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 32], ax

    # sname (64 bytes) = 0
    mov     ecx, 16
    lea     esi, [edi + 44]
    xor     eax, eax
.clear_sname:
    mov     [esi], eax
    add     esi, 4
    loop    .clear_sname

    # file (128 bytes) = 0
    mov     ecx, 32
.clear_file:
    mov     [esi], eax
    add     esi, 4
    loop    .clear_file

    # DHCP options magic cookie
    mov     dword ptr [edi + 236], 0x63825363

    # DHCP options: Message Type = Discover (1)
    mov     byte ptr [edi + 240], 53   # Option 53: DHCP Message Type
    mov     byte ptr [edi + 241], 1    # Length
    mov     byte ptr [edi + 242], 1    # Value = Discover
    # Option: Parameter Request (max msg size, router, DNS)
    mov     byte ptr [edi + 243], 55   # Option 55: Parameter Request List
    mov     byte ptr [edi + 244], 3    # Length
    mov     byte ptr [edi + 245], 1    # Subnet mask
    mov     byte ptr [edi + 246], 3    # Router
    mov     byte ptr [edi + 247], 6    # DNS
    # End option
    mov     byte ptr [edi + 248], 255  # Option 255: End

    # Update UDP and IP total lengths (actual = 249 bytes of DHCP)
    mov     word ptr [e1000_tx_buf + 34 + 4], 257  # UDP length = 8 + 249
    mov     word ptr [e1000_tx_buf + 14 + 2], 277  # IP total = 20 + 8 + 249

    # Recalculate IP checksum with correct length
    mov     edi, offset e1000_tx_buf + 14
    mov     word ptr [edi + 10], 0     # clear checksum
    xor     edx, edx
    mov     ecx, 10
.dhcip2_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .dhcip2_cksum
.dhcip2_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .dhcip2_fold_done
    add     eax, 1
.dhcip2_fold_done:
    not     ax
    lea     edi, [e1000_tx_buf + 14 + 10]
    mov     [edi], ax

    # Set DHCP state
    mov     dword ptr [e1000_dhcp_state], 1  # sent_discover

    # Send: 14 + 20 + 8 + 249 = 291 bytes
    mov     esi, offset e1000_tx_buf
    mov     ecx, 291
    call    e1000_transmit

    # Print "DHCP Discover sent"
    mov     esi, offset msg_dhcp_discover_sent
    call    uart_puts

    popad
    ret

# ============================================================================
# e1000_send_dhcp_request: Send DHCP Request (after receiving Offer)
# ============================================================================
    .globl  e1000_send_dhcp_request
e1000_send_dhcp_request:
    pushad

    # Use same XID
    mov     eax, [e1000_dhcp_xid]

    # Build Ethernet frame
    mov     edi, offset e1000_tx_buf
    mov     dword ptr [edi], 0xFFFFFFFF
    mov     word ptr [edi + 4], 0xFFFF
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax
    mov     word ptr [edi + 12], 0x0008

    # IP header
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45
    mov     byte ptr [edi + 1], 0x10
    mov     word ptr [edi + 2], 300
    mov     word ptr [edi + 4], 0x1235
    mov     word ptr [edi + 6], 0x0000
    mov     byte ptr [edi + 8], 128
    mov     byte ptr [edi + 9], 17
    mov     word ptr [edi + 10], 0
    mov     dword ptr [edi + 12], 0
    mov     dword ptr [edi + 16], 0xFFFFFFFF

    # IP checksum
    push    edi
    xor     edx, edx
    mov     ecx, 10
.dhreq_ip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .dhreq_ip_cksum
.dhreq_ip_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .dhreq_ip_fold_done
    add     eax, 1
.dhreq_ip_fold_done:
    not     ax
    pop     edi
    mov     [edi + 10], ax

    # UDP header
    mov     edi, offset e1000_tx_buf + 34
    mov     word ptr [edi], 68
    mov     word ptr [edi + 2], 67
    mov     word ptr [edi + 4], 272
    mov     word ptr [edi + 6], 0

    # DHCP payload
    mov     edi, offset e1000_tx_buf + 42
    mov     byte ptr [edi], 1
    mov     byte ptr [edi + 1], 1
    mov     byte ptr [edi + 2], 6
    mov     byte ptr [edi + 3], 0
    mov     eax, [e1000_dhcp_xid]
    mov     [edi + 4], eax
    mov     word ptr [edi + 8], 0
    mov     word ptr [edi + 10], 0x8000
    mov     dword ptr [edi + 12], 0            # ciaddr = 0.0.0.0
    mov     eax, [e1000_offer_ip]
    mov     [edi + 16], eax                    # yiaddr = offered IP
    mov     dword ptr [edi + 20], 0
    mov     dword ptr [edi + 24], 0

    # chaddr = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 28], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 32], ax

    # Clear sname and file
    lea     esi, [edi + 44]
    mov     ecx, 48
    xor     eax, eax
.dhreq_clear:
    mov     [esi], eax
    add     esi, 4
    loop    .dhreq_clear

    # Magic cookie
    mov     dword ptr [edi + 236], 0x63825363

    # Options: Message Type = Request (3)
    mov     byte ptr [edi + 240], 53
    mov     byte ptr [edi + 241], 1
    mov     byte ptr [edi + 242], 3
    # Option 54: Server Identifier (from offer siaddr)
    mov     byte ptr [edi + 243], 54
    mov     byte ptr [edi + 244], 4
    mov     eax, [edi + 20]  # siaddr (may be 0 for local server)
    mov     [edi + 245], eax
    # Option 50: Requested IP Address
    mov     byte ptr [edi + 249], 50
    mov     byte ptr [edi + 250], 4
    mov     eax, [e1000_offer_ip]
    mov     [edi + 251], eax
    # End
    mov     byte ptr [edi + 255], 255

    # Update lengths
    mov     word ptr [e1000_tx_buf + 34 + 4], 264
    mov     word ptr [e1000_tx_buf + 14 + 2], 284

    # Recalculate IP checksum
    mov     edi, offset e1000_tx_buf + 14
    mov     word ptr [edi + 10], 0
    xor     edx, edx
    mov     ecx, 10
.dhreq_ip_cksum2:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .dhreq_ip_cksum2
.dhreq_ip_fold2:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .dhreq_ip_fold2_done
    add     eax, 1
.dhreq_ip_fold2_done:
    not     ax
    lea     edi, [e1000_tx_buf + 14 + 10]
    mov     [edi], ax

    mov     dword ptr [e1000_dhcp_state], 1  # back to waiting

    mov     esi, offset e1000_tx_buf
    mov     ecx, 298
    call    e1000_transmit

    mov     esi, offset msg_dhcp_request_sent
    call    uart_puts

    popad
    ret

# ============================================================================
# e1000_handle_dhcp: Handle DHCP response
# Input: esi = RX buffer (pointing to Ethernet header)
# ============================================================================
e1000_handle_dhcp:
    pushad

    # DHCP payload starts at: 14(eth) + 20(IP) + 8(UDP) = 42
    mov     edi, offset e1000_rx_buf + 42

    # Check DHCP op (should be 2 = reply)
    cmp     byte ptr [edi], 2
    jne     .dhcp_done

    # Verify XID matches
    mov     eax, [edi + 4]
    cmp     eax, [e1000_dhcp_xid]
    jne     .dhcp_done

    # Check DHCP message type option
    lea     esi, [edi + 240]         # options area (after magic cookie)
    # Actually options start right after magic cookie at offset 236
    lea     esi, [edi + 240]
.dhcp_parse_options:
    movzx   eax, byte ptr [esi]
    cmp     al, 255                  # End option
    je      .dhcp_done
    cmp     al, 0                    # Padding
    je      .dhcp_opt_next
    cmp     al, 53                   # DHCP Message Type
    jne     .dhcp_opt_next

    # Found message type option
    movzx   ecx, byte ptr [esi + 1]  # length
    movzx   eax, byte ptr [esi + 2]  # value

    cmp     al, 2                    # DHCP Offer
    je      .dhcp_got_offer
    cmp     al, 5                    # DHCP ACK
    je      .dhcp_got_ack
    jmp     .dhcp_done

.dhcp_opt_next:
    movzx   ecx, byte ptr [esi + 1]  # option length
    add     esi, ecx
    inc     esi                      # skip type byte
    jmp     .dhcp_parse_options

.dhcp_got_offer:
    # Save offered IP address (yiaddr at offset +16)
    mov     eax, [edi + 16]
    mov     [e1000_offer_ip], eax
    mov     dword ptr [e1000_dhcp_state], 2  # got_offer

    # Print offer
    mov     esi, offset msg_dhcp_offer
    call    uart_puts
    mov     eax, [e1000_offer_ip]
    call    print_ip_uart
    jmp     .dhcp_done

.dhcp_got_ack:
    # Save assigned IP address (yiaddr at offset +16)
    mov     eax, [edi + 16]
    mov     [e1000_our_ip], eax
    mov     [e1000_arp_ip], eax
    mov     dword ptr [e1000_our_ip_ready], 1
    mov     dword ptr [e1000_dhcp_state], 3  # bound

    # Parse options for gateway, subnet mask, DNS
    lea     esi, [edi + 240]
.dhcp_ack_options:
    movzx   eax, byte ptr [esi]
    cmp     al, 255
    je      .dhcp_done
    cmp     al, 0
    je      .dhcp_ack_next
    movzx   ecx, byte ptr [esi + 1]
    cmp     al, 1                    # Subnet mask
    jne     .dhcp_ack_router
    cmp     ecx, 4
    jne     .dhcp_ack_next
    mov     eax, [esi + 2]
    mov     [e1000_subnet_mask], eax
    jmp     .dhcp_ack_next

.dhcp_ack_router:
    cmp     al, 3                    # Router/Gateway
    jne     .dhcp_ack_dns
    cmp     ecx, 4
    jne     .dhcp_ack_next
    mov     eax, [esi + 2]
    mov     [e1000_gateway_ip], eax
    jmp     .dhcp_ack_next

.dhcp_ack_dns:
    cmp     al, 6                    # DNS
    jne     .dhcp_ack_next
    cmp     ecx, 4
    jne     .dhcp_ack_next
    mov     eax, [esi + 2]
    mov     [e1000_dns_ip], eax

.dhcp_ack_next:
    add     esi, ecx
    inc     esi
    jmp     .dhcp_ack_options

.dhcp_done:
    popad
    ret

# ============================================================================
# print_ip_uart: Print an IP address to UART
# Input: eax = IP in little-endian (e.g., 10.0.2.15 = 0x0F02000A)
# ============================================================================
print_ip_uart:
    push    eax
    push    ebx
    push    ecx
    push    edx

    mov     ecx, 4
.print_ip_loop:
    dec     ecx
    mov     ebx, eax
    shr     ebx, cl
    shr     ebx, 8
    and     ebx, 0xFF
    mov     eax, ebx
    push    ecx
    call    print_dec_byte_uart
    pop     ecx
    test    ecx, ecx
    jz      .print_ip_done
    mov     al, '.'
    call    uart_putc
    mov     eax, [esp]  # restore original eax from stack... actually let me just use the original
    mov     eax, [esp + 12]  # original eax is at esp+12 (4 pushed regs + ecx)
    jmp     .print_ip_loop
.print_ip_done:
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

# print_dec_byte_uart: Print a byte (0-255) as decimal to UART
# Input: al = value
print_dec_byte_uart:
    push    ebx
    push    ecx
    push    edx
    xor     ebx, ebx
    mov     bl, al

    # Hundreds
    xor     ecx, ecx
.hundreds:
    cmp     ebx, 100
    jb      .tens
    sub     ebx, 100
    inc     ecx
    jmp     .hundreds
.tens:
    test    ecx, ecx
    jz      .do_tens
    add     ecx, '0'
    mov     al, cl
    call    uart_putc
.do_tens:
    xor     ecx, ecx
.do_tens_loop:
    cmp     ebx, 10
    jb      .do_ones
    sub     ebx, 10
    inc     ecx
    jmp     .do_tens_loop
.do_ones:
    add     ebx, '0'
    mov     al, bl
    call    uart_putc
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# e1000_send_arp: Send ARP request for target IP
# Input: eax = target IP (host byte order: 10.0.2.2 = 0x0A000202)
# Output: eax = 0 success, 1 failure
# ============================================================================
    .globl  e1000_send_arp
e1000_send_arp:
    pushad

    # Clear ARP ready flag
    xor     eax, eax
    mov     [e1000_arp_ready], eax

    # Build Ethernet frame in TX buffer
    mov     edi, offset e1000_tx_buf

    # Dest MAC = broadcast (FF:FF:FF:FF:FF:FF)
    mov     dword ptr [edi], 0xFFFFFFFF
    mov     word ptr [edi + 4], 0xFFFF

    # Source MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax

    # EtherType = ARP (0x0806)
    mov     word ptr [edi + 12], 0x0608

    # ARP request header
    mov     word ptr [edi + 14], 1     # HW type = Ethernet
    mov     word ptr [edi + 16], 0x0800  # Protocol = IPv4
    mov     byte ptr [edi + 18], 6     # HW size
    mov     byte ptr [edi + 19], 4     # Protocol size
    mov     word ptr [edi + 20], 1     # Operation = request

    # Sender MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 22], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 26], ax

    # Sender IP = our IP
    mov     eax, [e1000_arp_ip]
    mov     [edi + 28], eax

    # Target MAC = 00:00:00:00:00:00 (unknown)
    xor     eax, eax
    mov     [edi + 32], eax
    mov     word ptr [edi + 36], ax

    # Target IP = target IP (from eax argument, restore from stack)
    # We pushedad, so eax is at [esp]... restore original eax
    mov     eax, [esp + 36]  # saved eax before pushad
    mov     [edi + 38], eax

    # Send ARP request (42 bytes)
    mov     esi, offset e1000_tx_buf
    mov     ecx, 42
    call    e1000_transmit
    test    eax, eax
    jnz     .arp_send_fail

    # Wait for ARP reply (poll up to 2 seconds)
    mov     edx, 200           # 200 * 10ms = 2s
.arp_wait_loop:
    # Small delay
    mov     ecx, 500000
.arp_delay:
    dec     ecx
    jnz     .arp_delay

    # Poll for received packets
    call    e1000_poll

    # Check if ARP reply arrived
    cmp     dword ptr [e1000_arp_ready], 1
    je      .arp_resolved

    dec     edx
    jnz     .arp_wait_loop

.arp_timeout:
    mov     eax, 1             # timeout
    jmp     .arp_send_done

.arp_resolved:
    xor     eax, eax           # success

.arp_send_fail:
.arp_send_done:
    popad
    ret

# ============================================================================
# e1000_send_udp: Send a UDP packet
# Input: eax = dest IP, cx = dest port, dx = src port, esi = data, ecx_data = len
# Uses global e1000_tx_buf for packet construction
# ============================================================================
    .globl  e1000_send_udp
e1000_send_udp:
    pushad

    # Save parameters
    mov     [udp_send_dest_ip], eax
    mov     [udp_send_dest_port], cx
    mov     [udp_send_src_port], dx
    mov     [udp_send_data_ptr], esi
    mov     [udp_send_data_len], ecx

    # Build Ethernet frame
    mov     edi, offset e1000_tx_buf

    # ARP cache lookup for gateway (10.0.2.2 = 0x0A000202)
    mov     eax, 0x0A000202
    call    arp_cache_lookup
    test    eax, eax
    jnz     .udp_arp_miss

    # Cache hit - MAC already in e1000_arp_mac
    mov     eax, [e1000_arp_mac]
    mov     [edi], eax
    mov     ax, [e1000_arp_mac + 4]
    mov     [edi + 4], ax
    jmp     .udp_mac_done

.udp_arp_miss:
    # Cache miss - use existing gateway MAC (may be from last ARP)
    mov     eax, [e1000_arp_mac]
    mov     [edi], eax
    mov     ax, [e1000_arp_mac + 4]
    mov     [edi + 4], ax

.udp_mac_done:

    # Source MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax

    # EtherType = IPv4
    mov     word ptr [edi + 12], 0x0800

    # IP header (20 bytes) at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45          # Version=4, IHL=5
    mov     byte ptr [edi + 1], 0         # TOS
    mov     ax, [udp_send_data_len]
    add     ax, 28                        # IP(20) + UDP(8)
    mov     [edi + 2], ax                 # Total length
    mov     word ptr [edi + 4], 0x1234    # Identification
    mov     word ptr [edi + 6], 0x4000    # Flags: Don't fragment
    mov     byte ptr [edi + 8], 64        # TTL
    mov     byte ptr [edi + 9], 17        # Protocol = UDP
    mov     word ptr [edi + 10], 0        # Checksum (to calc)

    # Source IP: 10.0.2.15
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi + 12], eax

    # Dest IP
    mov     eax, [udp_send_dest_ip]
    mov     [edi + 16], eax

    # Calculate IP checksum
    push    edi
    xor     edx, edx
    mov     ecx, 10
.ip_cksum_loop:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .ip_cksum_loop
.fold_ip_cksum:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .ip_cksum_fold_done
    add     eax, 1
.ip_cksum_fold_done:
    not     ax
    pop     edi
    mov     [edi + 10], ax

    # UDP header (8 bytes) at offset 34
    mov     edi, offset e1000_tx_buf + 34
    mov     ax, [udp_send_src_port]
    mov     [edi], ax                     # Source port
    mov     ax, [udp_send_dest_port]
    mov     [edi + 2], ax                 # Dest port
    mov     ax, [udp_send_data_len]
    add     ax, 8                         # UDP length
    mov     [edi + 4], ax                 # UDP length
    mov     word ptr [edi + 6], 0         # Checksum (placeholder)

    # Copy payload at offset 42
    mov     edi, offset e1000_tx_buf + 42
    mov     esi, [udp_send_data_ptr]
    mov     ecx, [udp_send_data_len]
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb

    # Calculate UDP checksum (header + payload with pseudo-header)
    mov     dword ptr [udp_cksum_src], offset e1000_tx_buf + 34
    mov     cx, [udp_send_data_len]
    add     cx, 8                         # UDP header + payload
    call    udp_checksum
    mov     [e1000_tx_buf + 34 + 6], ax

    # Calculate total packet length
    mov     eax, [udp_send_data_len]
    add     eax, 42                       # 14(eth) + 20(IP) + 8(UDP)

    # Send
    mov     esi, offset e1000_tx_buf
    mov     ecx, eax
    call    e1000_transmit

    popad
    ret

# print_dec5: Write 5 zero-padded decimal digits of eax to [edi]
# Input: eax = value, edi = output buffer
print_dec5:
    push    ebx
    push    edx
    mov     ebx, 10000
    xor     edx, edx
    div     ebx                          # eax = value/10000, edx = rem
    add     al, '0'
    mov     [edi], al
    inc     edi
    mov     eax, edx

    mov     ebx, 1000
    xor     edx, edx
    div     ebx                          # eax = value/1000
    add     al, '0'
    mov     [edi], al
    inc     edi
    mov     eax, edx

    mov     ebx, 100
    xor     edx, edx
    div     ebx                          # eax = value/100
    add     al, '0'
    mov     [edi], al
    inc     edi
    mov     eax, edx

    mov     ebx, 10
    xor     edx, edx
    div     ebx                          # eax = value/10
    add     al, '0'
    mov     [edi], al
    inc     edi
    mov     eax, edx

    add     al, '0'
    mov     [edi], al
    inc     edi

    pop     edx
    pop     ebx
    ret

# ip_checksum: Calculate IP-style one's complement checksum
# Input: esi = pointer to data, ecx = length in bytes (must be even)
# Output: eax = checksum value
ip_checksum:
    push    ecx
    push    edx
    push    esi
    xor     edx, edx            # running sum
.ipcs_loop:
    test    ecx, ecx
    jz      .ipcs_done
    movzx   eax, word ptr [esi]
    add     edx, eax
    add     esi, 2
    sub     ecx, 2
    jmp     .ipcs_loop
.ipcs_done:
.ipcs_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .ipcs_fold_done
    add     eax, 1
.ipcs_fold_done:
    not     ax
    pop     esi
    pop     edx
    pop     ecx
    ret

# tcp_checksum: Calculate TCP checksum with pseudo-header
# Input: esi = TCP header + data pointer, ecx = TCP segment length
#        edi = destination IP (stored in tcp_recv_src_ip)
# Uses: tcp_cksum_buf as workspace
tcp_checksum:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    lea     edi, [tcp_cksum_buf]

    # Build pseudo-header:
    # Source IP (4 bytes) - our IP is 10.0.2.15 = 0x0F02000A
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi], eax
    # Dest IP (4 bytes) - remote IP from tcp_recv_src_ip
    mov     eax, [tcp_recv_src_ip]
    mov     [edi + 4], eax
    # Zero (1 byte) + Protocol (1 byte = 6 for TCP)
    mov     word ptr [edi + 8], 0x0006
    # TCP length (2 bytes)
    mov     ax, cx
    mov     [edi + 10], ax

    # Copy TCP header + data after pseudo-header
    mov     esi, [tcp_cksum_src]   # source pointer (set by caller)
    mov     edi, offset tcp_cksum_buf + 12
    mov     edx, ecx
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb

    # Calculate checksum over pseudo-header + TCP segment
    mov     esi, offset tcp_cksum_buf
    mov     ecx, edx
    add     ecx, 12                # pseudo-header length
    # Make even if odd
    test    cl, 1
    jz      .tcpcs_even
    mov     byte ptr [esi + ecx], 0
    inc     ecx
.tcpcs_even:
    call    ip_checksum

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

# udp_checksum: Calculate UDP checksum with pseudo-header
# Input: esi = UDP header + data pointer, ecx = UDP segment length
# Uses: udp_cksum_buf as workspace
udp_checksum:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    lea     edi, [udp_cksum_buf]

    # Build pseudo-header:
    # Source IP (4 bytes) - 10.0.2.15
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi], eax
    # Dest IP (4 bytes) - from udp_send_dest_ip
    mov     eax, [udp_send_dest_ip]
    mov     [edi + 4], eax
    # Zero (1 byte) + Protocol (1 byte = 17 for UDP)
    mov     word ptr [edi + 8], 0x0011
    # UDP length (2 bytes)
    mov     ax, cx
    mov     [edi + 10], ax

    # Copy UDP header + data after pseudo-header
    mov     esi, [udp_cksum_src]   # source pointer (set by caller)
    mov     edi, offset udp_cksum_buf + 12
    mov     edx, ecx
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb

    # Calculate checksum over pseudo-header + UDP segment
    mov     esi, offset udp_cksum_buf
    mov     ecx, edx
    add     ecx, 12                # pseudo-header length
    test    cl, 1
    jz      .udpcs_even
    mov     byte ptr [esi + ecx], 0
    inc     ecx
.udpcs_even:
    call    ip_checksum

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

# ============================================================================
# http_parse_request: Parse HTTP request from tcp_recv_buf
# Extracts method (GET/POST), URL path, and Host header
# Input: esi = tcp_recv_buf pointer (already set by caller)
# Output: http_method[0] = 'G' for GET, 'P' for POST, 0 for unknown
#         http_url[] = URL path (max 256 bytes)
#         http_host[] = Host header value (max 128 bytes)
#         eax = 1 if valid HTTP, 0 otherwise
# ============================================================================
http_parse_request:
    pushad

    mov     esi, offset tcp_recv_buf

    # Check for "GET " (0x20544547 little-endian)
    mov     eax, [esi]
    cmp     eax, 0x20544547
    je      .http_is_get

    # Check for "POST" (0x54534f50 little-endian)
    cmp     eax, 0x54534f50
    je      .http_is_post

    # Not a recognized HTTP method
    xor     eax, eax
    mov     [http_method], al
    popad
    ret

.http_is_get:
    mov     byte ptr [http_method], 'G'
    mov     byte ptr [http_method + 1], 'E'
    mov     byte ptr [http_method + 2], 'T'
    mov     byte ptr [http_method + 3], 0
    mov     ecx, 4                     # skip "GET "
    jmp     .http_parse_url

.http_is_post:
    mov     byte ptr [http_method], 'P'
    mov     byte ptr [http_method + 1], 'O'
    mov     byte ptr [http_method + 2], 'S'
    mov     byte ptr [http_method + 3], 'T'
    mov     byte ptr [http_method + 4], 0
    mov     ecx, 5                     # skip "POST "

.http_parse_url:
    # Copy URL path (until space or CR)
    lea     edi, [http_url]
    mov     esi, offset tcp_recv_buf
    add     esi, ecx                   # skip method

.http_url_loop:
    mov     al, [esi]
    test    al, al
    jz      .http_url_done
    cmp     al, 13                     # CR
    je      .http_url_done
    cmp     al, ' '
    je      .http_url_done
    cmp     ecx, 256                   # max URL length
    jge     .http_url_done
    mov     [edi], al
    inc     esi
    inc     edi
    inc     ecx
    jmp     .http_url_loop

.http_url_done:
    mov     byte ptr [edi], 0

    # Try to find "Host: " header
    lea     esi, [tcp_recv_buf]
    mov     ecx, 512                   # search limit

.http_host_search:
    cmp     ecx, 0
    je      .http_host_not_found
    mov     eax, [esi]
    # Check for "Host" (0x74736f48 little-endian)
    cmp     eax, 0x74736f48
    je      .http_host_found_check
    inc     esi
    dec     ecx
    jmp     .http_host_search

.http_host_found_check:
    cmp     word ptr [esi + 4], 0x3a20  # ": "
    jne     .http_host_search
    # Copy host value
    add     esi, 6
    lea     edi, [http_host]
    mov     ecx, 0

.http_host_copy:
    mov     al, [esi]
    cmp     al, 13
    je      .http_host_done
    test    al, al
    je      .http_host_done
    cmp     ecx, 127
    je      .http_host_done
    mov     [edi], al
    inc     esi
    inc     edi
    inc     ecx
    jmp     .http_host_copy

.http_host_done:
    mov     byte ptr [edi], 0
    jmp     .http_parse_done

.http_host_not_found:
    mov     byte ptr [http_host], 0

.http_parse_done:
    mov     eax, 1
    popad
    ret

# ============================================================================
# e1000_handle_udp: Handle received UDP packet
# Input: esi = RX buffer (pointing to Ethernet header)
# ============================================================================
e1000_handle_udp:
    pushad

    # Extract UDP ports
    # IP header starts at offset 14
    movzx   eax, byte ptr [esi + 23]     # Protocol
    cmp     al, 17                        # UDP
    jne     .udp_done

    # UDP header at offset 14+20=34
    movzx   eax, word ptr [esi + 34]      # Dest port
    mov     [udp_recv_dest_port], ax
    movzx   eax, word ptr [esi + 36]      # Source port
    mov     [udp_recv_src_port], ax

    # Check if this is a DHCP response (dest port 68)
    cmp     ax, 68
    je      .udp_dhcp
    movzx   eax, word ptr [esi + 38]      # UDP length
    sub     eax, 8                        # payload length
    mov     [udp_recv_len], eax

    # Copy payload to udp_recv_buf
    mov     ecx, eax
    cmp     ecx, 1500                     # max buffer size
    jg      .udp_done
    mov     esi, offset e1000_rx_buf + 42
    mov     edi, offset udp_recv_buf
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb

    # Save source IP
    mov     eax, [esi - 8]               # src IP from IP header (esi was at 34+eth=48, need IP at 14+12=26)
    # Actually: esi points to RX buf start, IP src is at offset 26
    mov     esi, offset e1000_rx_buf
    mov     eax, [esi + 26]
    mov     [udp_recv_src_ip], eax

    # Signal data available
    mov     dword ptr [udp_recv_ready], 1

    # Check if echo port (port 7) for auto echo server
    movzx   eax, word ptr [esi + 34]      # Dest port
    cmp     ax, 7
    jne     .udp_done

    # Auto-respond: send echo reply
    call    e1000_echo_server

.udp_dhcp:
    # DHCP response (dest port 68)
    call    e1000_handle_dhcp
    jmp     .udp_done

.udp_done:
    popad
    ret

# ============================================================================
# e1000_handle_tcp: Handle received TCP packet
# Input: esi = RX buffer (pointing to Ethernet header)
# Supports: SYN, SYN-ACK, ACK, PSH-ACK, FIN
# Implements simple TCP echo server on port 80
# ============================================================================
e1000_handle_tcp:
    pushad

    # TCP header starts at: 14 (eth) + (IHL * 4) (IP)
    movzx   eax, byte ptr [esi + 14]      # Version + IHL
    and     eax, 0x0F
    shl     eax, 2                        # IHL * 4 = IP header length
    add     eax, 14                       # + Ethernet header
    mov     ebp, eax                      # ebp = TCP header offset

    # Get source/dest ports
    movzx   eax, word ptr [esi + ebp]      # Source port
    mov     [tcp_recv_src_port], ax
    movzx   eax, word ptr [esi + ebp + 2]  # Dest port
    mov     [tcp_recv_dst_port], ax

    # Get TCP flags (offset 13 in TCP header)
    movzx   eax, byte ptr [esi + ebp + 13]

    # Check for RST first (highest priority)
    test    al, 0x04                       # RST flag
    jz      .tcp_check_port
    mov     dword ptr [tcp_rst_received], 1
    mov     dword ptr [tcp_state], 0       # CLOSED
    # Look up and free connection if it exists
    mov     eax, [esi + 26]               # remote IP
    movzx   ecx, word ptr [esi + ebp]      # remote port
    push    esi
    push    ebp
    call    tcp_conn_lookup
    pop     ebp
    pop     esi
    cmp     eax, -1
    je      .tcp_rst_done                 # no connection, just done
    call    tcp_conn_free                 # ebx = entry pointer from lookup
.tcp_rst_done:
    jmp     .tcp_done

.tcp_check_port:
    # Save flags for later use (al gets overwritten below)
    mov     byte ptr [tcp_flags_tmp], al

    # Check if dest port matches our listen port (80)
    cmp     ax, 80
    jne     .tcp_not_our

    # Connection tracking: look up or allocate connection slot
    mov     eax, [esi + 26]               # remote IP
    movzx   ecx, word ptr [esi + ebp]      # remote port
    push    esi
    push    ebp
    call    tcp_conn_lookup
    pop     ebp
    pop     esi
    cmp     eax, -1
    jne     .tcp_conn_found

    # New connection: allocate slot (only on SYN)
    movzx   eax, byte ptr [tcp_flags_tmp]
    test    al, 0x02                       # SYN flag
    jz      .tcp_no_data                   # non-SYN to unknown conn, ignore

    mov     eax, [esi + 26]               # remote IP
    movzx   ecx, word ptr [esi + ebp]      # remote port
    push    esi
    push    ebp
    call    tcp_conn_alloc
    pop     ebp
    pop     esi
    cmp     eax, -1
    je      .tcp_conn_full                 # no free slots

    # Save the slot index and pointer
    mov     [tcp_conn_slot_idx], eax
    mov     [tcp_conn_slot_ptr], ebx

.tcp_conn_found:
    mov     [tcp_conn_slot_idx], eax
    mov     [tcp_conn_slot_ptr], ebx

    # Load per-connection state into globals for send functions
    test    ebx, ebx
    jz      .conn_skip_load
    mov     eax, [ebx + 12]               # local_seq from entry
    mov     [tcp_local_seq], eax
    mov     eax, [ebx + 20]               # remote_ack from entry
    mov     [tcp_remote_ack], eax

.conn_skip_load:
    mov     eax, [tcp_conn_count]
    inc     eax
    mov     [tcp_conn_count], eax

    # Save source IP for reply
    mov     eax, [esi + 26]
    mov     [tcp_recv_src_ip], eax

    # Get sequence and ack numbers
    mov     eax, [esi + ebp + 4]
    mov     [tcp_remote_seq], eax
    mov     eax, [esi + ebp + 8]
    mov     [tcp_remote_ack], eax

    # Check for SYN
    movzx   eax, byte ptr [tcp_flags_tmp]
    test    al, 0x02                       # SYN flag
    jz      .tcp_check_ack

    # Check if SYN-ACK (we already have a connection)
    test    al, 0x10                       # ACK flag
    jnz     .tcp_synack_recv

    # SYN received - send SYN-ACK
    mov     dword ptr [tcp_state], 3       # SYN_RECV
    # Update connection entry state
    mov     ebx, [tcp_conn_slot_ptr]
    test    ebx, ebx
    jz      .syn_skip_state
    mov     byte ptr [ebx], 3              # SYN_RECV

.syn_skip_state:
    # Set our initial sequence number
    mov     dword ptr [tcp_local_seq], 0x00001234
    # Also store in connection entry
    test    ebx, ebx
    jz      .syn_skip_seq
    mov     dword ptr [ebx + 12], 0x00001234
    # Store remote seq
    mov     eax, [tcp_remote_seq]
    mov     [ebx + 16], eax

.syn_skip_seq:
    call    e1000_send_synack
    jmp     .tcp_done

.tcp_synack_recv:
    # This shouldn't happen as server, but handle gracefully
    mov     dword ptr [tcp_state], 4       # ESTABLISHED
    mov     ebx, [tcp_conn_slot_ptr]
    test    ebx, ebx
    jz      .synack_skip
    mov     byte ptr [ebx], 4              # ESTABLISHED
.synack_skip:
    jmp     .tcp_done

.tcp_conn_full:
    # Connection table full, send RST
    mov     eax, [esi + 26]
    mov     [tcp_recv_src_ip], eax
    movzx   eax, word ptr [esi + ebp]
    mov     [tcp_recv_src_port], ax
    movzx   eax, word ptr [esi + ebp + 2]
    mov     [tcp_recv_dst_port], ax
    call    e1000_send_rst
    jmp     .tcp_done

.tcp_check_ack:
    # Check for ACK flag
    movzx   eax, byte ptr [tcp_flags_tmp]
    test    al, 0x10
    jz      .tcp_check_fin

    # Check if we have PSH (data)
    test    al, 0x08                       # PSH flag
    jz      .tcp_no_data

    # TCP data received - save for processing
    # Calculate data length: TCP segment length - header length
    movzx   ecx, byte ptr [esi + ebp + 12] # Data offset (upper 4 bits)
    shr     ecx, 4
    shl     ecx, 2                         # * 4 = TCP header length
    mov     [tcp_hdr_len], cx
    # IP total length at offset 2
    movzx   edx, word ptr [esi + 2]
    sub     dx, cx                         # - TCP header
    sub     dx, 20                         # - IP header = payload
    movzx   eax, dx
    cmp     eax, 0
    jle     .tcp_no_data

    # Copy payload to tcp_recv_buf
    mov     ecx, eax
    cmp     ecx, 1500
    jg      .tcp_done
    mov     [tcp_recv_len], ecx
    mov     esi, offset e1000_rx_buf
    add     esi, ebp
    add     esi, ecx                       # skip TCP header to payload
    mov     edi, offset tcp_recv_buf
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb
    mov     dword ptr [tcp_recv_ready], 1
    mov     dword ptr [tcp_state], 4       # ESTABLISHED
    # Update connection entry state
    mov     ebx, [tcp_conn_slot_ptr]
    test    ebx, ebx
    jz      .psh_skip_state
    mov     byte ptr [ebx], 4              # ESTABLISHED
.psh_skip_state:

    # Send ACK for received data
    call    e1000_send_tcp_ack

    # Check if HTTP request (starts with "GET " or "POST ")
    mov     esi, offset tcp_recv_buf
    mov     eax, [esi]
    cmp     eax, 0x20544547                # "GET " (little-endian)
    je      .tcp_http_request
    mov     eax, [esi]
    cmp     eax, 0x54534f50                # "POST" (little-endian)
    je      .tcp_http_request

    # Otherwise, echo the data back (TCP echo server)
    call    e1000_send_tcp_data
    jmp     .tcp_no_data

.tcp_http_request:
    # Parse HTTP request to extract URL
    call    http_parse_request

    # Route based on http_url
    lea     esi, [http_url]

    # Check "/" (root)
    mov     al, [esi]
    test    al, al
    jz      .http_route_root             # empty URL = root
    cmp     al, '/'
    jne     .http_route_notfound
    mov     al, [esi + 1]
    test    al, al
    jz      .http_route_root             # "/" alone = root

    # Check "/status"
    cmp     dword ptr [esi], 0x75746174  # "stat"
    je      .http_route_status
    cmp     dword ptr [esi], 0x69726576  # "veri"
    je      .http_route_version
    cmp     dword ptr [esi], 0x70637074  # "tcp"
    je      .http_route_tcpstatus
    jmp     .http_route_notfound

.http_route_root:
    # Body: hello message
    mov     edi, offset tcp_http_body
    mov     esi, offset http_body_hello
    mov     ecx, http_body_hello_len
    jmp     .http_send

.http_route_status:
    # Build status body with live connection count
    mov     edi, offset tcp_http_body
    # Copy static part (up to "TCP connections: ")
    mov     esi, offset http_body_status
    mov     ecx, 17                     # "Kernel Status: OK\nTCP connections: "
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb
    # Append connection count as 5-digit decimal
    mov     eax, [tcp_conn_count]
    mov     edi, offset tcp_http_body + 32   # after the prefix
    call    print_dec5
    # Copy the rest of status body (network info line)
    mov     esi, offset http_body_status + 37  # skip prefix + count area
    mov     edi, offset tcp_http_body + 38
    mov     ecx, http_body_status_len - 38
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb
    mov     eax, http_body_status_len
    jmp     .http_send

.http_route_version:
    mov     edi, offset tcp_http_body
    mov     esi, offset http_body_version
    mov     ecx, http_body_version_len
    jmp     .http_send

.http_route_tcpstatus:
    # Build TCP status body
    mov     edi, offset tcp_http_body
    mov     esi, offset http_body_tcpstatus
    mov     ecx, 21                     # "TCP Connection Status:\n"
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb
    # Append "Active: X, Total: Y" with live values
    mov     eax, [tcp_conn_active_count]
    mov     edi, offset tcp_http_body + 21
    call    print_dec5
    mov     eax, [tcp_conn_count]
    mov     edi, offset tcp_http_body + 34
    call    print_dec5
    # Copy the rest
    mov     esi, offset http_body_tcpstatus + 43
    mov     edi, offset tcp_http_body + 46
    mov     ecx, http_body_tcpstatus_len - 46
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb
    mov     eax, http_body_tcpstatus_len
    jmp     .http_send

.http_route_notfound:
    mov     edi, offset tcp_http_body
    mov     esi, offset http_body_notfound
    mov     ecx, http_body_notfound_len

.http_send:
    mov     [tcp_recv_len], eax          # payload length for send_http_response
    call    e1000_send_http_response

.tcp_no_data:
    # Check for FIN
.tcp_check_fin:
    movzx   eax, byte ptr [tcp_flags_tmp]
    test    al, 0x01                       # FIN flag
    jz      .tcp_done
    mov     dword ptr [tcp_fin_received], 1
    mov     dword ptr [tcp_state], 0       # CLOSED
    # Send FIN-ACK back for graceful close
    call    e1000_send_fin_ack
    # Free connection slot (graceful close complete)
    mov     ebx, [tcp_conn_slot_ptr]
    call    tcp_conn_free
    jmp     .tcp_done

.tcp_not_our:
    # Not our port, send RST if SYN received
    movzx   eax, byte ptr [tcp_flags_tmp]
    test    al, 0x02                       # SYN flag
    jz      .tcp_done
    # Save info for RST
    mov     eax, [esi + 26]
    mov     [tcp_recv_src_ip], eax
    movzx   eax, word ptr [esi + ebp]
    mov     [tcp_recv_src_port], ax
    movzx   eax, word ptr [esi + ebp + 2]
    mov     [tcp_recv_dst_port], ax
    call    e1000_send_rst

.tcp_done:
    popad
    ret

# ============================================================================
# e1000_send_synack: Send TCP SYN-ACK response
# ============================================================================
e1000_send_synack:
    pushad

    # Build Ethernet frame
    mov     edi, offset e1000_tx_buf

    # ARP cache lookup for remote IP
    mov     eax, [tcp_recv_src_ip]
    call    arp_cache_lookup
    test    eax, eax
    jnz     .synack_arp_miss

    # Cache hit - MAC already in e1000_arp_mac
    mov     eax, [e1000_arp_mac]
    mov     [edi], eax
    mov     ax, [e1000_arp_mac + 4]
    mov     [edi + 4], ax
    jmp     .synack_mac_done

.synack_arp_miss:
    # Cache miss - use last known MAC
    mov     eax, [e1000_arp_mac]
    mov     [edi], eax
    mov     ax, [e1000_arp_mac + 4]
    mov     [edi + 4], ax

.synack_mac_done:

    # Source MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax
    mov     word ptr [edi + 12], 0x0800    # IPv4

    # IP header at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45
    mov     byte ptr [edi + 1], 0
    mov     word ptr [edi + 2], 44         # 20(IP) + 24(TCP with no options)
    mov     word ptr [edi + 4], 0x5679
    mov     word ptr [edi + 6], 0x4000     # Don't fragment
    mov     byte ptr [edi + 8], 64         # TTL
    mov     byte ptr [edi + 9], 6          # TCP
    mov     word ptr [edi + 10], 0         # Checksum
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi + 12], eax  # 10.0.2.15
    mov     eax, [tcp_recv_src_ip]
    mov     [edi + 16], eax

    # IP checksum
    push    edi
    xor     edx, edx
    mov     ecx, 10
.synack_ip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .synack_ip_cksum
.synack_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .synack_ip_fold_done
    add     eax, 1
.synack_ip_fold_done:
    not     ax
    pop     edi
    mov     [edi + 10], ax

    # TCP header at offset 34
    mov     edi, offset e1000_tx_buf + 34
    mov     word ptr [edi], 80             # Source port = 80
    mov     ax, [tcp_recv_src_port]
    mov     [edi + 2], ax                  # Dest port
    mov     eax, [tcp_local_seq]
    mov     [edi + 4], eax                 # Seq number
    mov     eax, [tcp_remote_seq]
    inc     eax                            # ACK = SYN seq + 1
    mov     [edi + 8], eax                 # Ack number
    mov     byte ptr [edi + 12], 0x50      # Data offset: 5 (20 bytes, no options)
    mov     byte ptr [edi + 13], 0x12      # Flags: SYN + ACK
    mov     word ptr [edi + 14], 65535     # Window size
    mov     word ptr [edi + 16], 0         # Checksum (placeholder)
    mov     word ptr [edi + 18], 0         # Urgent pointer

    # Calculate TCP checksum
    mov     dword ptr [tcp_cksum_src], offset e1000_tx_buf + 34
    mov     cx, 20                         # TCP header only, no data
    call    tcp_checksum
    mov     [e1000_tx_buf + 34 + 16], ax   # store checksum at TCP offset 16

    # Send: 14 + 20 + 20 = 54 bytes
    mov     esi, offset e1000_tx_buf
    mov     ecx, 54
    call    e1000_transmit

    # SYN consumes 1 sequence number - update globals and connection entry
    mov     eax, [tcp_local_seq]
    inc     eax
    mov     [tcp_local_seq], eax
    mov     ebx, [tcp_conn_slot_ptr]
    test    ebx, ebx
    jz      .synack_skip_sync
    mov     [ebx + 12], eax                # update entry local_seq

.synack_skip_sync:
    popad
    ret

# ============================================================================
# e1000_send_tcp_ack: Send TCP ACK for received data
# Acknowledges the received data (seq = remote_seq + data_len)
# ============================================================================
e1000_send_tcp_ack:
    pushad

    # Save payload length for sequence update
    mov     edx, [tcp_recv_len]

    # Build Ethernet frame
    mov     edi, offset e1000_tx_buf

    # ARP cache lookup for remote IP
    mov     eax, [tcp_recv_src_ip]
    call    arp_cache_lookup
    # Use result regardless of hit/miss
    mov     eax, [e1000_arp_mac]
    mov     [edi], eax
    mov     ax, [e1000_arp_mac + 4]
    mov     [edi + 4], ax
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax
    mov     word ptr [edi + 12], 0x0800

    # IP header at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45
    mov     byte ptr [edi + 1], 0
    mov     word ptr [edi + 2], 40         # 20(IP) + 20(TCP)
    mov     word ptr [edi + 4], 0x5680
    mov     word ptr [edi + 6], 0x4000
    mov     byte ptr [edi + 8], 64
    mov     byte ptr [edi + 9], 6          # TCP
    mov     word ptr [edi + 10], 0
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi + 12], eax  # 10.0.2.15
    mov     eax, [tcp_recv_src_ip]
    mov     [edi + 16], eax

    # IP checksum
    push    edi
    push    edx
    xor     edx, edx
    mov     ecx, 10
.ack_ip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .ack_ip_cksum
.ack_ip_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .ack_ip_fold_done
    add     eax, 1
.ack_ip_fold_done:
    not     ax
    pop     edx
    pop     edi
    mov     [edi + 10], ax

    # TCP header at offset 34
    mov     edi, offset e1000_tx_buf + 34
    mov     word ptr [edi], 80             # Source port = 80
    mov     ax, [tcp_recv_src_port]
    mov     [edi + 2], ax                  # Dest port

    # Seq = our initial seq + data length we're acknowledging
    mov     eax, [tcp_local_seq]
    mov     [edi + 4], eax                 # Seq number

    # Ack = remote seq + data length + 1 (for PSH)
    mov     eax, [tcp_remote_seq]
    add     eax, edx                       # + data length
    mov     [edi + 8], eax                 # Ack number

    mov     byte ptr [edi + 12], 0x50      # Data offset: 5
    mov     byte ptr [edi + 13], 0x10      # Flags: ACK
    mov     word ptr [edi + 14], 65535     # Window size
    mov     word ptr [edi + 16], 0         # Checksum (placeholder)
    mov     word ptr [edi + 18], 0

    # Calculate TCP checksum
    mov     dword ptr [tcp_cksum_src], offset e1000_tx_buf + 34
    mov     cx, 20                         # TCP header only
    call    tcp_checksum
    mov     [e1000_tx_buf + 34 + 16], ax

    # Send: 14 + 20 + 20 = 54 bytes
    mov     esi, offset e1000_tx_buf
    mov     ecx, 54
    call    e1000_transmit

    popad
    ret

# ============================================================================
# e1000_send_tcp_data: Send TCP data with PSH-ACK (echo server)
# Input: uses tcp_recv_buf as data source, tcp_recv_len as length
# ============================================================================
e1000_send_tcp_data:
    pushad

    mov     edx, [tcp_recv_len]            # payload length
    add     edx, 40                        # + 20(IP) + 20(TCP)
    mov     [tcp_tx_total_len], dx

    # Build Ethernet frame
    mov     edi, offset e1000_tx_buf

    # ARP cache lookup for remote IP
    mov     eax, [tcp_recv_src_ip]
    call    arp_cache_lookup
    # Use result regardless of hit/miss
    mov     eax, [e1000_arp_mac]
    mov     [edi], eax
    mov     ax, [e1000_arp_mac + 4]
    mov     [edi + 4], ax
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax
    mov     word ptr [edi + 12], 0x0800

    # IP header at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45
    mov     byte ptr [edi + 1], 0
    mov     ax, [tcp_tx_total_len]
    mov     [edi + 2], ax
    mov     word ptr [edi + 4], 0x5681
    mov     word ptr [edi + 6], 0x4000
    mov     byte ptr [edi + 8], 64
    mov     byte ptr [edi + 9], 6          # TCP
    mov     word ptr [edi + 10], 0
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi + 12], eax  # 10.0.2.15
    mov     eax, [tcp_recv_src_ip]
    mov     [edi + 16], eax

    # IP checksum
    push    edi
    push    edx
    xor     edx, edx
    mov     ecx, 10
.data_ip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .data_ip_cksum
.data_ip_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .data_ip_fold_done
    add     eax, 1
.data_ip_fold_done:
    not     ax
    pop     edx
    pop     edi
    mov     [edi + 10], ax

    # TCP header at offset 34
    mov     edi, offset e1000_tx_buf + 34
    mov     word ptr [edi], 80             # Source port = 80
    mov     ax, [tcp_recv_src_port]
    mov     [edi + 2], ax                  # Dest port

    # Seq = our seq
    mov     eax, [tcp_local_seq]
    mov     [edi + 4], eax

    # Ack = remote seq + their data len + 1
    mov     eax, [tcp_remote_seq]
    add     eax, [tcp_recv_len]
    mov     [edi + 8], eax

    mov     byte ptr [edi + 12], 0x50      # Data offset: 5
    mov     byte ptr [edi + 13], 0x18      # Flags: PSH + ACK
    mov     word ptr [edi + 14], 65535     # Window size
    mov     word ptr [edi + 16], 0         # Checksum (placeholder)
    mov     word ptr [edi + 18], 0

    # Copy payload (echo data back)
    mov     edi, offset e1000_tx_buf + 54
    mov     esi, offset tcp_recv_buf
    mov     ecx, [tcp_recv_len]
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb

    # Calculate TCP checksum (header + payload)
    mov     dword ptr [tcp_cksum_src], offset e1000_tx_buf + 34
    mov     cx, [tcp_recv_len]
    add     cx, 20                         # header + payload
    call    tcp_checksum
    mov     [e1000_tx_buf + 34 + 16], ax

    # Send
    mov     eax, [tcp_tx_total_len]
    add     eax, 14                        # + Ethernet
    mov     esi, offset e1000_tx_buf
    mov     ecx, eax
    call    e1000_transmit

    # Update our seq
    mov     eax, [tcp_local_seq]
    add     eax, [tcp_recv_len]
    mov     [tcp_local_seq], eax

    # Also update connection entry's local_seq
    mov     ebx, [tcp_conn_slot_ptr]
    test    ebx, ebx
    jz      .send_data_skip_sync
    mov     [ebx + 12], eax                # update entry local_seq
    mov     eax, [tcp_remote_seq]
    add     eax, [tcp_recv_len]
    mov     [ebx + 16], eax                # update entry remote_seq

.send_data_skip_sync:

    popad
    ret

# ============================================================================
# e1000_send_http_response: Send HTTP 200 OK response
# Input: tcp_http_body already contains the response body
#        tcp_recv_len contains body length
# ============================================================================
e1000_send_http_response:
    pushad

    # Build full HTTP response in tcp_http_body (prepend headers)
    # First, save body content to a temp location
    mov     esi, offset tcp_http_body
    mov     edi, offset http_body_tmp
    mov     ecx, [tcp_recv_len]
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb
    mov     ebx, [tcp_recv_len]              # save body length

    # Copy HTTP header to tcp_http_body
    mov     esi, offset http_response_header
    mov     edi, offset tcp_http_body
    mov     ecx, http_response_header_len
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb

    # Patch Content-Length: find "XXXXX" at offset 58 (after "Content-Length: ")
    # "HTTP/1.1 200 OK\r\n" = 17, "Content-Type: text/plain\r\n" = 26
    # "Content-Length: XXXXX\r\n" - XXXX starts at offset 43+16 = offset 59
    mov     eax, ebx                          # body length
    mov     edi, offset tcp_http_body + 59    # Content-Length value position
    call    print_dec5

    # Copy saved body after header
    mov     esi, offset http_body_tmp
    mov     edi, offset tcp_http_body
    add     edi, http_response_header_len
    mov     ecx, ebx                          # body length
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb

    # Total payload = header + body
    mov     eax, ebx
    add     eax, http_response_header_len
    mov     [tcp_recv_len], eax

    # Reuse send_tcp_data path
    call    e1000_send_tcp_data

    popad
    ret

# ============================================================================
# e1000_send_fin_ack: Send TCP FIN-ACK for graceful connection close
# ============================================================================
e1000_send_fin_ack:
    pushad

    # Build Ethernet frame
    mov     edi, offset e1000_tx_buf

    # ARP cache lookup for remote IP
    mov     eax, [tcp_recv_src_ip]
    call    arp_cache_lookup
    # Use result regardless of hit/miss
    mov     eax, [e1000_arp_mac]
    mov     [edi], eax
    mov     ax, [e1000_arp_mac + 4]
    mov     [edi + 4], ax
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax
    mov     word ptr [edi + 12], 0x0800

    # IP header at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45
    mov     byte ptr [edi + 1], 0
    mov     word ptr [edi + 2], 40         # 20(IP) + 20(TCP)
    mov     word ptr [edi + 4], 0x5682
    mov     word ptr [edi + 6], 0x4000
    mov     byte ptr [edi + 8], 64
    mov     byte ptr [edi + 9], 6          # TCP
    mov     word ptr [edi + 10], 0
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi + 12], eax  # 10.0.2.15
    mov     eax, [tcp_recv_src_ip]
    mov     [edi + 16], eax

    # IP checksum
    push    edi
    xor     edx, edx
    mov     ecx, 10
.finack_ip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .finack_ip_cksum
.finack_ip_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .finack_ip_fold_done
    add     eax, 1
.finack_ip_fold_done:
    not     ax
    pop     edi
    mov     [edi + 10], ax

    # TCP header at offset 34
    mov     edi, offset e1000_tx_buf + 34
    mov     word ptr [edi], 80             # Source port = 80
    mov     ax, [tcp_recv_src_port]
    mov     [edi + 2], ax                  # Dest port
    mov     eax, [tcp_local_seq]
    mov     [edi + 4], eax                 # Seq number
    mov     eax, [tcp_remote_seq]
    add     eax, [tcp_recv_len]            # ACK = remote seq + data len
    mov     [edi + 8], eax                 # Ack number
    mov     byte ptr [edi + 12], 0x50      # Data offset: 5
    mov     byte ptr [edi + 13], 0x11      # Flags: FIN + ACK
    mov     word ptr [edi + 14], 65535     # Window size
    mov     word ptr [edi + 16], 0         # Checksum (placeholder)
    mov     word ptr [edi + 18], 0

    # Calculate TCP checksum
    mov     dword ptr [tcp_cksum_src], offset e1000_tx_buf + 34
    mov     cx, 20                         # TCP header only
    call    tcp_checksum
    mov     [e1000_tx_buf + 34 + 16], ax

    # Send: 14 + 20 + 20 = 54 bytes
    mov     esi, offset e1000_tx_buf
    mov     ecx, 54
    call    e1000_transmit

    # FIN consumes 1 sequence number - update entry
    mov     eax, [tcp_local_seq]
    inc     eax
    mov     [tcp_local_seq], eax
    mov     ebx, [tcp_conn_slot_ptr]
    test    ebx, ebx
    jz      .finack_skip_sync
    mov     [ebx + 12], eax                # update entry local_seq
    mov     byte ptr [ebx], 5              # state = FIN_WAIT

.finack_skip_sync:
    mov     dword ptr [tcp_fin_sent], 1

    popad
    ret

# ============================================================================
# e1000_send_rst: Send TCP RST packet
# ============================================================================
e1000_send_rst:
    pushad

    # Build Ethernet frame
    mov     edi, offset e1000_tx_buf

    # ARP cache lookup for remote IP
    mov     eax, [tcp_recv_src_ip]
    call    arp_cache_lookup
    # Use result regardless of hit/miss
    mov     eax, [e1000_arp_mac]
    mov     [edi], eax
    mov     ax, [e1000_arp_mac + 4]
    mov     [edi + 4], ax
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax
    mov     word ptr [edi + 12], 0x0800

    # IP header at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45
    mov     byte ptr [edi + 1], 0
    mov     word ptr [edi + 2], 40         # 20(IP) + 20(TCP)
    mov     word ptr [edi + 4], 0x5683
    mov     word ptr [edi + 6], 0x4000
    mov     byte ptr [edi + 8], 64
    mov     byte ptr [edi + 9], 6          # TCP
    mov     word ptr [edi + 10], 0
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi + 12], eax  # 10.0.2.15
    mov     eax, [tcp_recv_src_ip]
    mov     [edi + 16], eax

    # IP checksum
    push    edi
    xor     edx, edx
    mov     ecx, 10
.rst_ip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .rst_ip_cksum
.rst_ip_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .rst_ip_fold_done
    add     eax, 1
.rst_ip_fold_done:
    not     ax
    pop     edi
    mov     [edi + 10], ax

    # TCP header at offset 34
    mov     edi, offset e1000_tx_buf + 34
    mov     word ptr [edi], 80             # Source port = 80
    mov     ax, [tcp_recv_src_port]
    mov     [edi + 2], ax                  # Dest port
    xor     eax, eax
    mov     [edi + 4], eax                 # Seq = 0
    mov     [edi + 8], eax                 # Ack = 0
    mov     byte ptr [edi + 12], 0x50      # Data offset: 5
    mov     byte ptr [edi + 13], 0x04      # Flags: RST
    mov     word ptr [edi + 14], 0         # Window = 0 (RST)
    mov     word ptr [edi + 16], 0         # Checksum (placeholder)
    mov     word ptr [edi + 18], 0

    # Calculate TCP checksum
    mov     dword ptr [tcp_cksum_src], offset e1000_tx_buf + 34
    mov     cx, 20                         # TCP header only
    call    tcp_checksum
    mov     [e1000_tx_buf + 34 + 16], ax

    # Send: 14 + 20 + 20 = 54 bytes
    mov     esi, offset e1000_tx_buf
    mov     ecx, 54
    call    e1000_transmit

    popad
    ret

# ============================================================================
# e1000_echo_server: Echo UDP packet back to sender (port 7)
# Input: esi = RX buffer (Ethernet header)
# ============================================================================
e1000_echo_server:
    pushad

    # Build Ethernet frame in TX buffer
    mov     edi, offset e1000_tx_buf

    # Dest MAC = source MAC of received packet (offset 6 in RX)
    mov     eax, [esi + 6]
    mov     [edi], eax
    mov     ax, [esi + 10]
    mov     [edi + 4], ax

    # Source MAC = our MAC
    mov     eax, [e1000_mac]
    mov     [edi + 6], eax
    mov     ax, [e1000_mac + 4]
    mov     [edi + 10], ax

    # EtherType = IPv4
    mov     word ptr [edi + 12], 0x0800

    # IP header at offset 14
    mov     edi, offset e1000_tx_buf + 14
    mov     byte ptr [edi], 0x45          # Version=4, IHL=5
    mov     byte ptr [edi + 1], 0         # TOS
    mov     ax, [esi + 2]                 # Total length from received packet
    mov     [edi + 2], ax
    mov     word ptr [edi + 4], 0x5678    # New identification
    mov     word ptr [edi + 6], 0x4000    # Flags: Don't fragment
    mov     byte ptr [edi + 8], 64        # TTL
    mov     byte ptr [edi + 9], 17        # Protocol = UDP
    mov     word ptr [edi + 10], 0        # Checksum (to calc)

    # Source IP = our IP
    mov     eax, [e1000_our_ip]
    mov     dword ptr [edi + 12], eax  # 10.0.2.15

    # Dest IP = source IP of received packet
    mov     eax, [esi + 26]
    mov     [edi + 16], eax

    # Calculate IP checksum
    push    edi
    xor     edx, edx
    mov     ecx, 10
.echo_ip_cksum:
    movzx   eax, word ptr [edi]
    add     edx, eax
    add     edi, 2
    loop    .echo_ip_cksum
.echo_fold:
    mov     eax, edx
    shr     edx, 16
    and     eax, 0xFFFF
    add     eax, edx
    jnc     .echo_ip_fold_done
    add     eax, 1
.echo_ip_fold_done:
    not     ax
    pop     edi
    mov     [edi + 10], ax

    # UDP header at offset 34
    mov     edi, offset e1000_tx_buf + 34

    # Swap source/dest ports
    mov     ax, [esi + 36]              # Original source port -> dest
    mov     [edi + 2], ax
    mov     ax, [esi + 34]              # Original dest port -> source
    mov     [edi], ax
    mov     ax, [esi + 38]              # Same UDP length
    mov     [edi + 4], ax
    mov     word ptr [edi + 6], 0        # Checksum (placeholder)

    # Copy payload (same as received)
    mov     edi, offset e1000_tx_buf + 42
    mov     esi, offset e1000_rx_buf + 42
    mov     ecx, [udp_recv_len]
    push    ecx
    shr     ecx, 2
    cld
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb

    # Calculate UDP checksum (with pseudo-header)
    mov     dword ptr [udp_cksum_src], offset e1000_tx_buf + 34
    mov     ecx, 8
    add     ecx, [udp_recv_len]          # UDP header + payload length
    call    udp_checksum
    mov     [e1000_tx_buf + 34 + 6], ax  # store checksum

    # Send packet
    mov     eax, [udp_recv_len]
    add     eax, 42                      # 14(eth) + 20(IP) + 8(UDP)
    mov     esi, offset e1000_tx_buf
    mov     ecx, eax
    call    e1000_transmit

    popad
    ret

# ============================================================================
# e1000_irq_handler: e1000 NIC interrupt handler
# Called on NIC IRQ line
# ============================================================================
    .globl  e1000_irq_handler
e1000_irq_handler:
    pushad

    # Read interrupt cause register (ICR) - read clears
    mov     ebx, [e1000_mmio_base]
    mov     eax, [ebx + 0x00C0]

    # Check for RX interrupt (bit 7 = RXDW)
    test    eax, 0x80
    jz      .irq_check_tx
    # Process received packets
    call    e1000_poll

.irq_check_tx:
    # Check for TX interrupt (bit 1 = TXDW)
    test    eax, 0x02
    jz      .irq_done

.irq_done:
    # Send EOI
    mov     eax, [e1000_irq_line]
    call    pic_send_eoi

    popad
    iretd

esi_temp:
    .space  4

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

    .globl  print_hex8
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

# ============================================================================
# enter_ring3: 进入用户模式 (ring 3)
# 使用 iret 指令从 ring 0 切换到 ring 3
# iret 从栈中弹出: EIP, CS, EFLAGS, ESP, SS
# ============================================================================
    .globl  enter_ring3
enter_ring3:
    # 设置用户栈地址
    mov     edx, offset user_stack_top

    # 设置 iret 结构 (从栈顶向下)
    # SS = 用户数据段选择子 | DPL=3 (0x20 | 3 = 0x23)
    push    0x23
    # ESP = 用户栈顶
    push    edx
    # EFLAGS (当前值) - 使用 pushf (32位模式下 pushfd)
    pushf
    # 设置 IF 位 (bit 9) 开启中断
    or      dword ptr [esp], 0x200
    # CS = 用户代码段选择子 | DPL=3 (0x18 | 3 = 0x1B)
    push    0x1B
    # EIP = 用户代码入口
    push    offset ring3_test

    # 进入 ring 3
    iret

# ============================================================================
# enter_wasm_ring3: 进入 WASM 用户模式 (ring 3)
# 使用 wasm_user_stack 和 wasm_ring3_test
# ============================================================================
    .globl  enter_wasm_ring3
enter_wasm_ring3:
    # 设置 WASM 用户栈地址
    mov     edx, offset wasm_user_stack_top

    # 设置 iret 结构 (从栈顶向下)
    # SS = 用户数据段选择子 | DPL=3 (0x20 | 3 = 0x23)
    push    0x23
    # ESP = WASM 用户栈顶
    push    edx
    # EFLAGS (当前值) - 使用 pushf (32位模式下 pushfd)
    pushf
    # 设置 IF 位 (bit 9) 开启中断
    or      dword ptr [esp], 0x200
    # CS = 用户代码段选择子 | DPL=3 (0x18 | 3 = 0x1B)
    push    0x1B
    # EIP = WASM ring3 测试代码入口
    push    offset wasm_ring3_test

    # 进入 ring 3
    iret

# ============================================================================
# ring3_test: 用户模式测试代码
# 在 ring 3 执行，使用 INT 0x80 系统调用
# ============================================================================
    .globl  ring3_test
ring3_test:
    # 用户模式代码 - 打印消息
    # 由于用户模式无法直接调用内核函数，使用 INT 0x80 系统调用
    # 系统调用号 0 = print_string, 参数: esi = 字符串指针
    mov     esi, offset msg_ring3_user
    mov     eax, 0              # syscall 0 = print_string
    int     0x80

    # 无限循环 (无法返回内核)
1:  jmp     1b

# ============================================================================
# wasm_ring3_test: WASM 用户模式测试代码
# 在 ring 3 执行，使用 INT 0x80 系统调用打印 "WASM"
# ============================================================================
    .globl  wasm_ring3_test
wasm_ring3_test:
    # 在 ring 3 执行简单 syscall 打印 "WASM"
    mov     eax, 2              # putchar syscall
    mov     ebx, 'W'            # 'W'
    int     0x80
    mov     eax, 2
    mov     ebx, 'A'            # 'A'
    int     0x80
    mov     eax, 2
    mov     ebx, 'S'            # 'S'
    int     0x80
    mov     eax, 2
    mov     ebx, 'M'            # 'M'
    int     0x80
    # 打印换行
    mov     eax, 2
    mov     ebx, 0x0D           # CR
    int     0x80
    mov     eax, 2
    mov     ebx, 0x0A           # LF
    int     0x80
    # 死循环
1:  jmp     1b

# ============================================================================
# 用户模式消息
# ============================================================================
msg_ring3_user:
    .asciz  "Hello from Ring 3 (User Mode)!\r\n"

# ============================================================================
# e1000_send_udp_wasm: WASM wrapper for UDP send
# Input: [esp+4] = ip, [esp+8] = port, [esp+12] = data ptr, [esp+16] = len
# ============================================================================
    .globl  e1000_send_udp_wasm
e1000_send_udp_wasm:
    push    ebp
    mov     ebp, esp
    pushad

    mov     eax, [ebp + 8]           # dest IP
    movzx   ecx, word ptr [ebp + 12] # dest port
    mov     dx, 12345                # src port (fixed)
    mov     esi, [ebp + 16]          # data ptr
    mov     ecx, [ebp + 20]          # data len (overwrites port)

    # Save len to temp variable
    mov     [udp_send_data_len], ecx

    # Set up registers for e1000_send_udp: eax=ip, cx=port, dx=src_port, esi=ptr
    mov     eax, [ebp + 8]           # dest IP
    movzx   ecx, word ptr [ebp + 12] # dest port
    mov     dx, 12345                # src port
    mov     esi, [ebp + 16]          # data ptr
    call    e1000_send_udp

    popad
    mov     eax, 1                  # return 1 = sent OK
    pop     ebp
    ret     16

# ============================================================================
# e1000_send_tcp_data_wasm: WASM wrapper for TCP send
# Input: [esp+4] = ip, [esp+8] = port, [esp+12] = data ptr, [esp+16] = len
# ============================================================================
    .globl  e1000_send_tcp_data_wasm
e1000_send_tcp_data_wasm:
    push    ebp
    mov     ebp, esp
    pushad

    # Copy data to tcp_recv_buf (source for e1000_send_tcp_data)
    mov     esi, [ebp + 16]
    mov     edi, offset tcp_recv_buf
    mov     ecx, [ebp + 20]
    push    ecx
    shr     ecx, 2
    rep     movsd
    pop     ecx
    and     ecx, 3
    rep     movsb
    mov     [tcp_recv_len], ecx

    # Set remote IP/port for TCP response
    mov     eax, [ebp + 8]
    mov     [tcp_recv_src_ip], eax
    movzx   eax, word ptr [ebp + 12]
    mov     [tcp_recv_src_port], ax

    # Call TCP data send
    call    e1000_send_tcp_data

    popad
    pop     ebp
    ret     16

    .section .bss
    .space  8192
    .globl  stack_top
stack_top:

# Multiboot info pointer (saved from ebx by _start)
multiboot_info_ptr:
    .globl  multiboot_info_ptr
    .space  4

virtio_pci_temp:
    .space  4
virtio_pci_temp2:
    .space  4
virtio_pci_temp3:
    .space  4
e1000_mmio_base:
    .globl  e1000_mmio_base
    .space  4
e1000_rx_buf:
    .space  2048               # shared RX buffer for demo
e1000_tx_buf:
    .globl  e1000_tx_buf
    .space  2048
e1000_rx_desc:
    .space  128                # 8 descriptors * 16 bytes
e1000_tx_desc:
    .space  128                # 8 descriptors * 16 bytes
e1000_mac:
    .globl  e1000_mac
    .globl  e1000_mac_addr
e1000_mac_addr:
    .space  6
e1000_status:
    .globl  e1000_status
    .space  4                  # 1 = e1000 initialized successfully
e1000_rx_idx:
    .globl  e1000_rx_idx
    .space  4                  # current RX descriptor index
e1000_tx_len:
    .space  4                  # last TX length
e1000_arp_ip:
    .globl  e1000_arp_ip
    .space  4                  # our IP address (for ARP)
e1000_our_ip:
    .globl  e1000_our_ip
    .space  4                  # our IP address (from DHCP or static)
e1000_gateway_ip:
    .globl  e1000_gateway_ip
    .space  4                  # gateway IP (from DHCP)
e1000_subnet_mask:
    .space  4                  # subnet mask (from DHCP)
e1000_dns_ip:
    .globl  e1000_dns_ip
    .space  4                  # DNS server IP (from DHCP)
e1000_dhcp_state:
    .globl  e1000_dhcp_state
    .space  4                  # 0=idle, 1=sent_discover, 2=got_offer, 3=bound
e1000_dhcp_xid:
    .space  4                  # DHCP transaction ID
e1000_our_ip_ready:
    .space  4                  # 1 = IP address assigned
e1000_offer_ip:
    .space  4                  # IP address from DHCP offer
e1000_arp_mac:
    .globl  e1000_arp_mac
    .space  6                  # resolved MAC for last ARP lookup
e1000_arp_ready:
    .globl  e1000_arp_ready
    .space  4                  # 1 = ARP reply received

# ICMP ping state
e1000_ping_target_ip:
    .space  4                  # target IP for ping
e1000_icmp_reply_ready:
    .space  4                  # 1 = ICMP Echo Reply received
e1000_icmp_reply_rtt:
    .space  4                  # round-trip time (approximate ticks)
icmp_echo_seq:
    .space  4                  # ICMP echo sequence number
e1000_irq_line:
    .space  4                  # IRQ line assigned by PCI

# UDP send parameters
udp_send_dest_ip:
    .globl  udp_send_dest_ip
    .space  4
udp_send_dest_port:
    .space  2
udp_send_src_port:
    .space  2
udp_send_data_ptr:
    .space  4
udp_send_data_len:
    .globl  udp_send_data_len
    .space  4

# UDP receive buffer and state
udp_recv_buf:
    .globl  udp_recv_buf
    .space  1500               # max UDP payload
udp_recv_src_ip:
    .globl  udp_recv_src_ip
    .space  4
udp_recv_src_port:
    .globl  udp_recv_src_port
    .space  2
udp_recv_dest_port:
    .globl  udp_recv_dest_port
    .space  2
udp_recv_len:
    .globl  udp_recv_len
    .space  4
udp_recv_ready:
    .globl  udp_recv_ready
    .space  4                  # 1 = data available

# ARP cache (8 entries, each 12 bytes: 4 IP + 6 MAC + 1 valid + 1 padding)
e1000_arp_cache:
    .globl  e1000_arp_cache
    .space  96                 # 8 * 12 bytes
e1000_arp_cache_size:
    .globl  e1000_arp_cache_size
    .space  4                  # number of valid entries

# TCP connection table (4 concurrent connections)
# Each entry: 4(remote_ip) + 2(remote_port) + 1(state) + 1(padding) +
#             4(local_seq) + 4(remote_seq) + 4(remote_ack) + 4(recv_len) = 24 bytes
# Total: 4 * 24 = 96 bytes
TCP_MAX_CONN = 4
TCP_CONN_ENTRY_SIZE = 24       # bytes per connection entry
tcp_conn_table:
    .globl  tcp_conn_table
    .space  96                 # 4 connections * 24 bytes each

# Connection entry offsets within each 24-byte entry
# conn[entry]: state at +0 (byte), remote_ip at +4, remote_port at +8 (word)
# local_seq at +12, remote_seq at +16, remote_ack at +20
tcp_conn_active_count:
    .globl  tcp_conn_active_count
    .space  4                  # number of active connections

# TCP/UDP checksum workspace
tcp_cksum_buf:
    .space  2048               # workspace for TCP checksum (pseudo-header + segment)
tcp_cksum_src:
    .space  4                  # source pointer for TCP checksum
udp_cksum_buf:
    .space  1548               # workspace for UDP checksum (pseudo-header + segment)
udp_cksum_src:
    .space  4                  # source pointer for UDP checksum
udp_cksum_len:
    .space  2                  # UDP segment length for checksum

# TCP state
tcp_state:
    .globl  tcp_state
    .space  4                  # 0=CLOSED, 1=LISTEN, 2=SYN_SENT, 3=SYN_RECV, 4=ESTABLISHED
tcp_local_seq:
    .space  4                  # our sequence number
tcp_remote_seq:
    .space  4                  # remote sequence number
tcp_remote_ack:
    .space  4                  # expected ACK from remote
tcp_recv_buf:
    .globl  tcp_recv_buf
    .space  1500               # TCP receive buffer
tcp_recv_len:
    .globl  tcp_recv_len
    .space  4                  # received data length
tcp_recv_src_ip:
    .globl  tcp_recv_src_ip
    .space  4
tcp_recv_src_port:
    .globl  tcp_recv_src_port
    .space  2
tcp_recv_dst_port:
    .space  2
tcp_recv_ready:
    .globl  tcp_recv_ready
    .space  4                  # 1 = TCP data available
tcp_listen_port:
    .globl  tcp_listen_port
    .space  2                  # port we're listening on (default 80)
tcp_hdr_len:
    .space  2                  # TCP header length
tcp_tx_total_len:
    .space  2                  # Total IP+TCP payload length for TX
tcp_http_body:
    .space  1024               # HTTP response body buffer
tcp_conn_count:
    .globl  tcp_conn_count
    .space  4                  # Total connections received
tcp_rst_received:
    .globl  tcp_rst_received
    .space  4                  # 1 = RST received
tcp_fin_received:
    .globl  tcp_fin_received
    .space  4                  # 1 = FIN received
tcp_fin_sent:
    .space  4                  # 1 = FIN sent
tcp_http_enabled:
    .globl  tcp_http_enabled
    .space  4                  # 1 = HTTP server enabled (default on)
tcp_flags_tmp:
    .space  1                  # Temporary storage for TCP flags byte

tcp_conn_slot_idx:
    .space  4                  # Current connection slot index
tcp_conn_slot_ptr:
    .space  4                  # Pointer to current connection entry

# HTTP request parsing
http_method:
    .space  5                  # "GET\0" or "POST\0"
http_url:
    .space  256                # URL path
http_host:
    .space  128                # Host header value
http_url_len:
    .space  4                  # URL length
http_active_conn:
    .space  4                  # current connection slot index
http_body_tmp:
    .space  1024               # Temporary buffer for HTTP body during header construction

# User mode stack (for ring 3)
    .align  16
user_stack:
    .globl  user_stack
    .space  4096               # 4KB user stack
user_stack_top:
    .globl  user_stack_top

# WASM user mode stack (for ring 3 WASM execution)
    .align  16
wasm_user_stack:
    .globl  wasm_user_stack
    .space  4096               # 4KB WASM user stack
wasm_user_stack_top:
    .globl  wasm_user_stack_top

    .section .rodata

# HTTP response header template (no body, dynamic Content-Length)
http_response_header:
    .ascii  "HTTP/1.1 200 OK"
    .byte   13, 10
    .ascii  "Content-Type: text/plain"
    .byte   13, 10
    .ascii  "Content-Length: XXXXX"
    .byte   13, 10
    .ascii  "Server: aiasm/v1.46"
    .byte   13, 10
    .ascii  "Connection: close"
    .byte   13, 10, 13, 10
http_response_header_end:
http_response_header_len = http_response_header_end - http_response_header

# Route response bodies
http_body_hello:
    .ascii  "Hello from AI-ASM Kernel v1.46!"
    .byte   13, 10
http_body_hello_end:
http_body_hello_len = http_body_hello_end - http_body_hello

http_body_status:
    .ascii  "Kernel Status: OK"
    .byte   13, 10
    .ascii  "TCP connections: "
    .ascii  "00000"
    .byte   13, 10
    .ascii  "Network: e1000 (Intel 82540EM)"
    .byte   13, 10
http_body_status_end:
http_body_status_len = http_body_status_end - http_body_status

http_body_version:
    .ascii  "AI-ASM Kernel v1.46"
    .byte   13, 10
    .ascii  "x86 32-bit + WASM runtime"
    .byte   13, 10
http_body_version_end:
http_body_version_len = http_body_version_end - http_body_version

http_body_notfound:
    .ascii  "404 Not Found"
    .byte   13, 10
    .ascii  "Try: / /status /version /tcpstatus"
    .byte   13, 10
http_body_notfound_end:
http_body_notfound_len = http_body_notfound_end - http_body_notfound

http_body_tcpstatus:
    .ascii  "TCP Connection Status:"
    .byte   13, 10
    .ascii  "Active: 0, Total: 00000"
    .byte   13, 10
    .ascii  "Listen port: 80"
    .byte   13, 10
http_body_tcpstatus_end:
http_body_tcpstatus_len = http_body_tcpstatus_end - http_body_tcpstatus

msg_bar:    .asciz  "BAR0 = "
msg_vfound: .asciz "\n  virtio-net found (MMIO in ISA hole - not accessible)\n"
msg_vfail:  .asciz  "  Skipping virtio (needs MMIO mapping)\n"
msg_e1000:  .asciz "\n  e1000 found: "
msg_e100mac:.asciz "  MAC = "
msg_e100ok: .asciz "  e1000 initialized\n"
msg_e100fail:.asciz "  e1000 reset timeout!\n"
msg_net_skip:.asciz "  No known NIC found\n"
msg_icmp_sent:.asciz "  ICMP echo reply sent\n"
msg_ping_timeout:.asciz "  Request timeout\n"
msg_ping_reply:.asciz "  Reply received, RTT="
msg_ping_ms:.asciz "ms\n"
msg_ping_sent:.asciz "  PING "
msg_ping_ip:.asciz " sent\n"
msg_dhcp_discover_sent:.asciz "  DHCP Discover sent, waiting for Offer...\n"
msg_dhcp_request_sent:.asciz "  DHCP Request sent, waiting for ACK...\n"
msg_dhcp_offer:.asciz "  DHCP Offer: "
msg_dhcp_ack:.asciz "  DHCP ACK: IP="
msg_dhcp_bound:.asciz "  DHCP Bound: IP="
msg_dhcp_info:.asciz "  GW="
msg_dhcp_noip:.asciz "  DHCP: No IP assigned\n"
msg_dhcp_state:.asciz "  DHCP state="
msg_boot:    .asciz  "AI-ASM Kernel v1.19 booting..."
msg_udp_send_debug:
    .asciz  "[UDP_SEND] Calling e1000_send_udp\n"
msg_udp_send_done:
    .asciz  "[UDP_SEND] Done, returning 1\n"
msg_gdt:     .asciz  "  GDT loaded"
msg_idt:     .asciz  "  IDT loaded (256 vectors)"
msg_tss:     .asciz  "  TSS loaded (selector 0x28)"
msg_pic:     .asciz  "  PIC remapped"
msg_pit:     .asciz  "  PIT initialized (100Hz)"
msg_kbd:     .asciz  "  Keyboard initialized"
msg_mem:     .asciz  "  Physical memory manager initialized"
msg_proc:    .asciz  "  Process scheduler initialized"
msg_syscall: .asciz  "  Syscall interface (INT 0x80) ready"
msg_vfs:     .asciz  "  Virtual filesystem initialized"
msg_wasm:    .asciz  "  WASM runtime initialized"
msg_ata:     .asciz  "  ATA disk driver initialized"
msg_fat32:   .asciz  "  FAT32 filesystem initialized"
