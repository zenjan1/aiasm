.intel_syntax noprefix
    .code32

# =============================================================================
# ata.asm - ATA/IDE 磁盘驱动
# =============================================================================
# Primary IDE Controller ports:
#   0x1F0: Data port (16-bit)
#   0x1F1: Error register
#   0x1F2: Sector count
#   0x1F3: LBA low (0-7)
#   0x1F4: LBA mid (8-15)
#   0x1F5: LBA high (16-23)
#   0x1F6: Drive/LBA (24-27) + drive select
#   0x1F7: Status/Command register
# =============================================================================

    .section .bss
    .globl ata_buffer
ata_buffer:
    .space 512                   # 扇区读取缓冲区

ata_lba_temp:
    .space 4                     # 临时存储 LBA

    .section .text

# =============================================================================
# ata_init: 初始化 ATA 控制器
# =============================================================================
    .globl ata_init
ata_init:
    push    eax
    push    edx

    # 软复位 - 写入 0x04 到 0x3F6 (Device Control)
    mov     dx, 0x3F6
    mov     al, 0x04
    out     dx, al

    # 等待 5us (简化处理)
    mov     ecx, 1000
ata_init_delay1:
    nop
    loop    ata_init_delay1

    # 清除复位 - 写入 0x00 到 0x3F6
    mov     dx, 0x3F6
    xor     al, al
    out     dx, al

    # 等待 BSY 清除
    mov     ecx, 100000          # 超时计数
ata_init_wait_bsy:
    mov     dx, 0x1F7
    in      al, dx
    test    al, 0x80             # BSY bit
    jz      ata_init_ok
    dec     ecx
    jnz     ata_init_wait_bsy
    # 超时，但不返回错误（继续初始化）
ata_init_ok:
    pop     edx
    pop     eax
    ret

# =============================================================================
# ata_wait_ready: 等待控制器就绪 (BSY=0)
# =============================================================================
    .globl ata_wait_ready
ata_wait_ready:
    push    eax
    push    ecx
    push    edx

    mov     ecx, 100000          # 超时计数
ata_wait_ready_loop:
    mov     dx, 0x1F7
    in      al, dx
    test    al, 0x80             # BSY bit
    jz      ata_wait_ready_ok
    dec     ecx
    jnz     ata_wait_ready_loop
    # 超时
    mov     eax, 0xFFFFFFFF
    jmp     ata_wait_ready_done
ata_wait_ready_ok:
    xor     eax, eax             # 返回 0 表示成功
ata_wait_ready_done:
    pop     edx
    pop     ecx
    pop     eax
    ret

# =============================================================================
# ata_wait_data: 等待数据就绪 (DRQ=1)
# =============================================================================
    .globl ata_wait_data
ata_wait_data:
    push    eax
    push    ecx
    push    edx

    mov     ecx, 100000          # 超时计数
ata_wait_data_loop:
    mov     dx, 0x1F7
    in      al, dx
    test    al, 0x08             # DRQ bit
    jnz     ata_wait_data_ready
    test    al, 0x01             # 检查错误位
    jnz     ata_wait_data_error
    dec     ecx
    jnz     ata_wait_data_loop
ata_wait_data_error:
    mov     eax, 0xFFFFFFFF      # 返回 -1 表示错误
    jmp     ata_wait_data_done
ata_wait_data_ready:
    xor     eax, eax             # 返回 0 表示成功
ata_wait_data_done:
    pop     edx
    pop     ecx
    pop     eax
    ret

# =============================================================================
# ata_read_sector: 读取一个扇区
# 参数: eax = LBA 地址 (28-bit), edi = 目标缓冲区
# 返回: eax = 0 成功, -1 失败
# =============================================================================
    .globl ata_read_sector
ata_read_sector:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    edi

    # 保存 LBA
    mov     [ata_lba_temp], eax

    # 1. 等待 BSY=0
    call    ata_wait_ready
    cmp     eax, 0
    jne     ata_read_fail

    # 2. 设置 LBA 地址 (28-bit mode)
    mov     eax, [ata_lba_temp]
    mov     ebx, eax             # 保存 LBA

    # LBA low (bits 0-7) -> 0x1F3
    mov     dx, 0x1F3
    mov     al, bl
    out     dx, al

    # LBA mid (bits 8-15) -> 0x1F4
    mov     dx, 0x1F4
    mov     al, bh
    out     dx, al

    # LBA high (bits 16-23) -> 0x1F5
    shr     ebx, 16
    mov     dx, 0x1F5
    mov     al, bl
    out     dx, al

    # Drive/LBA bits 24-27 + LBA mode + master -> 0x1F6
    mov     dx, 0x1F6
    mov     al, bh
    and     al, 0x0F             # 只取 bits 24-27
    or      al, 0xE0             # LBA mode (bit 6), master drive (bit 4)
    out     dx, al

    # 3. 设置扇区计数 = 1
    mov     dx, 0x1F2
    mov     al, 1
    out     dx, al

    # 4. 发送 READ SECTORS 命令 (0x20)
    mov     dx, 0x1F7
    mov     al, 0x20
    out     dx, al

    # 5. 等待数据就绪 (DRQ=1)
    call    ata_wait_data
    cmp     eax, 0
    jne     ata_read_fail

    # 6. 读取 256 个 16-bit 字
    mov     dx, 0x1F0
    mov     ecx, 256
    mov     edi, [ebp + 8]       # 获取缓冲区指针 (第一个参数)

ata_read_loop:
    in      ax, dx
    mov     [edi], ax
    add     edi, 2
    dec     ecx
    jnz     ata_read_loop

    xor     eax, eax              # 返回 0 表示成功
    jmp     ata_read_done

ata_read_fail:
    mov     eax, 0xFFFFFFFF       # 返回 -1 表示失败
ata_read_done:
    pop     edi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# =============================================================================
# ata_get_status: 获取 ATA 状态
# 返回: al = 状态寄存器值
# =============================================================================
    .globl ata_get_status
ata_get_status:
    push    edx
    mov     dx, 0x1F7
    in      al, dx
    pop     edx
    ret

# =============================================================================
# ata_identify: 识别 ATA 设备 (发送 IDENTIFY 命令)
# 参数: edi = 缓冲区 (512 字节)
# 返回: eax = 0 成功, -1 失败
# =============================================================================
    .globl ata_identify
ata_identify:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    edi

    # 等待就绪
    call    ata_wait_ready
    cmp     eax, 0
    jne     ata_identify_fail

    # 选择主驱动器 (0xE0 = LBA mode, master)
    mov     dx, 0x1F6
    mov     al, 0xE0
    out     dx, al

    # 扇区计数 = 0 (for IDENTIFY)
    mov     dx, 0x1F2
    xor     al, al
    out     dx, al

    # LBA = 0
    mov     dx, 0x1F3
    xor     al, al
    out     dx, al
    mov     dx, 0x1F4
    xor     al, al
    out     dx, al
    mov     dx, 0x1F5
    xor     al, al
    out     dx, al

    # 发送 IDENTIFY 命令 (0xEC)
    mov     dx, 0x1F7
    mov     al, 0xEC
    out     dx, al

    # 等待数据就绪
    call    ata_wait_data
    cmp     eax, 0
    jne     ata_identify_fail

    # 读取 256 个 16-bit 字
    mov     dx, 0x1F0
    mov     ecx, 256
    mov     edi, [ebp + 8]       # 获取缓冲区指针

ata_identify_read:
    in      ax, dx
    mov     [edi], ax
    add     edi, 2
    dec     ecx
    jnz     ata_identify_read

    xor     eax, eax             # 返回成功
    jmp     ata_identify_done

ata_identify_fail:
    mov     eax, 0xFFFFFFFF

ata_identify_done:
    pop     edi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret

# =============================================================================
# ata_write_sector: 写入一个扇区
# 参数: eax = LBA 地址 (28-bit), edi = 源缓冲区
# 返回: eax = 0 成功, -1 失败
# =============================================================================
    .globl ata_write_sector
ata_write_sector:
    push    ebp
    mov     ebp, esp
    push    ebx
    push    ecx
    push    edx
    push    edi

    # 保存 LBA
    mov     [ata_lba_temp], eax

    # 1. 等待 BSY=0
    call    ata_wait_ready
    cmp     eax, 0
    jne     ata_write_fail

    # 2. 设置 LBA 地址 (28-bit mode)
    mov     eax, [ata_lba_temp]
    mov     ebx, eax             # 保存 LBA

    # LBA low (bits 0-7) -> 0x1F3
    mov     dx, 0x1F3
    mov     al, bl
    out     dx, al

    # LBA mid (bits 8-15) -> 0x1F4
    mov     dx, 0x1F4
    mov     al, bh
    out     dx, al

    # LBA high (bits 16-23) -> 0x1F5
    shr     ebx, 16
    mov     dx, 0x1F5
    mov     al, bl
    out     dx, al

    # Drive/LBA bits 24-27 + LBA mode + master -> 0x1F6
    mov     dx, 0x1F6
    mov     al, bh
    and     al, 0x0F             # 只取 bits 24-27
    or      al, 0xE0             # LBA mode (bit 6), master drive (bit 4)
    out     dx, al

    # 3. 设置扇区计数 = 1
    mov     dx, 0x1F2
    mov     al, 1
    out     dx, al

    # 4. 发送 WRITE SECTORS 命令 (0x30)
    mov     dx, 0x1F7
    mov     al, 0x30
    out     dx, al

    # 5. 等待数据就绪 (DRQ=1)
    call    ata_wait_data
    cmp     eax, 0
    jne     ata_write_fail

    # 6. 写入 256 个 16-bit 字
    mov     dx, 0x1F0
    mov     ecx, 256
    mov     edi, [ebp + 8]       # 获取缓冲区指针 (第一个参数)

ata_write_loop:
    mov     ax, [edi]
    out     dx, ax
    add     edi, 2
    dec     ecx
    jnz     ata_write_loop

    # 7. 等待写入完成 (BSY=0)
    call    ata_wait_ready

    xor     eax, eax              # 返回 0 表示成功
    jmp     ata_write_done

ata_write_fail:
    mov     eax, 0xFFFFFFFF       # 返回 -1 表示失败
ata_write_done:
    pop     edi
    pop     edx
    pop     ecx
    pop     ebx
    pop     ebp
    ret