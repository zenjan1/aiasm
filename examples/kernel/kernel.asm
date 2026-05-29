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
    mov     word ptr [edi + 10], 0    # clear status

    # Set EOP|RS|IFCS (bit 0 | bit 3 | bit 4) in status/cmd
    mov     word ptr [edi + 14], 0x000B  # EOP=1, RS=1, IFCS=1

    # Send: write TDT=0 (notify hardware)
    mov     dword ptr [ebx + 0x3818], 0

    # Wait for completion (RS=1 means report status)
    mov     edx, 100000
    dec     edx
    jz      .tx_timeout

    # Check descriptor status for DD bit (bit 0)
    cmp     word ptr [edi + 12], 0
    je      .tx_wait

    mov     [e1000_tx_len], ecx
    xor     eax, eax             # success
    jmp     .tx_done

.tx_timeout:
    mov     eax, 1               # failure

.tx_done:
    popad
    ret

.tx_wait:
    mov     eax, [ebx + 0x3818]  # check TDT
    test    eax, eax
    jz      .tx_wait2
    jmp     .tx_done

.tx_wait2:
    cmp     word ptr [edi + 12], 0
    je      .tx_wait
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

    # Check IP protocol (offset 23: 1 = ICMP)
    cmp     byte ptr [esi + 23], 1
    jne     .poll_next

    # This is an ICMP packet, handle it
    call    e1000_handle_icmp
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

# ============================================================================
# e1000_handle_icmp: Handle ICMP Echo Request, send Echo Reply
# Input: esi = packet buffer address (RX buffer)
# Uses: e1000_tx_buf for reply
# ============================================================================
e1000_handle_icmp:
    pushad

    # Build Ethernet frame in TX buffer
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

    # Signal that ARP reply was received
    mov     dword ptr [e1000_arp_ready], 1

.arp_done:
    popad
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
    .space  6
e1000_rx_idx:
    .globl  e1000_rx_idx
    .space  4                  # current RX descriptor index
e1000_tx_len:
    .space  4                  # last TX length
e1000_arp_ip:
    .globl  e1000_arp_ip
    .space  4                  # our IP address (for ARP)
e1000_arp_mac:
    .globl  e1000_arp_mac
    .space  6                  # resolved MAC for last ARP lookup
e1000_arp_ready:
    .globl  e1000_arp_ready
    .space  4                  # 1 = ARP reply received

    .section .rodata
msg_bar:    .asciz  "BAR0 = "
msg_vfound: .asciz "\n  virtio-net found (MMIO in ISA hole - not accessible)\n"
msg_vfail:  .asciz  "  Skipping virtio (needs MMIO mapping)\n"
msg_e1000:  .asciz "\n  e1000 found: "
msg_e100mac:.asciz "  MAC = "
msg_e100ok: .asciz "  e1000 initialized\n"
msg_e100fail:.asciz "  e1000 reset timeout!\n"
msg_net_skip:.asciz "  No known NIC found\n"
msg_icmp_sent:.asciz "  ICMP echo reply sent\n"
msg_boot:    .asciz  "AI-ASM Kernel v0.40 booting..."
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
