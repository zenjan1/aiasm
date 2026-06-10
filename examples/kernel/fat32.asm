.intel_syntax noprefix
.code32

# =============================================================================
# fat32.asm - FAT32 文件系统支持
# =============================================================================
# FAT32 BPB 字段偏移
    .set BPB_BYTES_PER_SEC,   0x0B    # 每扇区字节数 (2 bytes)
    .set BPB_SEC_PER_CLUS,    0x0D    # 每簇扇区数 (1 byte)
    .set BPB_RSVD_SEC_CNT,    0x0E    # 保留扇区数 (2 bytes)
    .set BPB_NUM_FATS,        0x10    # FAT 表数量 (1 byte)
    .set BPB_FATSZ32,         0x24    # FAT32 大小 (4 bytes)
    .set BPB_ROOT_CLUS,       0x2C    # 根目录簇号 (4 bytes)

# 目录项偏移
    .set DIR_NAME,            0x00    # 文件名 (11 bytes)
    .set DIR_ATTR,            0x0B    # 属性 (1 byte)
    .set DIR_FST_CLUS_LO,     0x1A    # 低16位簇号 (2 bytes)
    .set DIR_FILE_SIZE,       0x1C    # 文件大小 (4 bytes)

# 目录项属性
    .set ATTR_READ_ONLY,      0x01
    .set ATTR_HIDDEN,         0x02
    .set ATTR_SYSTEM,         0x04
    .set ATTR_VOLUME_ID,      0x08
    .set ATTR_DIRECTORY,      0x10
    .set ATTR_ARCHIVE,        0x20
    .set ATTR_LONG_NAME,      0x0F    # 长文件名标记

# =============================================================================
# BSS
# =============================================================================
    .section .bss

# FAT32 BPB 信息
    .globl  sec_per_clus
    .globl  data_region_lba
bytes_per_sec:    .space 2          # 每扇区字节数
sec_per_clus:     .space 1          # 每簇扇区数
rsvd_sec_cnt:     .space 2          # 保留扇区数
num_fats:         .space 1          # FAT 表数量
fat_sz32:         .space 4          # 每个 FAT 的扇区数
root_clus:        .space 4          # 根目录簇号
root_dir_lba:     .space 4          # 根目录 LBA 地址
data_region_lba:  .space 4          # 数据区 LBA 地址

# FAT32 缓冲区
fat32_bpb_buffer: .space 512        # BPB 读取缓冲区
fat32_dir_buffer: .space 512        # 目录项缓冲区

# FAT32 状态
fat32_initialized: .space 1        # 是否已初始化 (0=未初始化, 1=已初始化)

# =============================================================================
# TEXT
# =============================================================================
    .section .text

# =============================================================================
# fat32_init: 初始化 FAT32 文件系统
# 读取 BPB，计算根目录位置
# 返回: eax = 0 成功, -1 失败
# =============================================================================
    .globl fat32_init
fat32_init:
    push    ebx
    push    ecx
    push    edx
    push    edi
    push    esi

    # 读取 Boot Sector (LBA 0)
    mov     eax, 0
    mov     edi, offset fat32_bpb_buffer
    call    ata_read_sector
    cmp     eax, 0
    jne     fat32_init_fail

    # 解析 BPB
    mov     edi, offset fat32_bpb_buffer

    # BytesPerSec (offset 0x0B)
    movzx   eax, word ptr [edi + BPB_BYTES_PER_SEC]
    mov     [bytes_per_sec], ax

    # SecPerClus (offset 0x0D)
    movzx   eax, byte ptr [edi + BPB_SEC_PER_CLUS]
    mov     [sec_per_clus], al

    # RsvdSecCnt (offset 0x0E)
    movzx   eax, word ptr [edi + BPB_RSVD_SEC_CNT]
    mov     [rsvd_sec_cnt], ax

    # NumFATs (offset 0x10)
    movzx   eax, byte ptr [edi + BPB_NUM_FATS]
    mov     [num_fats], al

    # FATSz32 (offset 0x24)
    mov     eax, [edi + BPB_FATSZ32]
    mov     [fat_sz32], eax

    # RootClus (offset 0x2C)
    mov     eax, [edi + BPB_ROOT_CLUS]
    mov     [root_clus], eax

    # 计算根目录 LBA:
    # RootDirLBA = RsvdSecCnt + (NumFATs * FATSz32) + (RootClus - 2) * SecPerClus
    # 简化: 第一簇(簇2)的根目录
    movzx   eax, word ptr [rsvd_sec_cnt]
    movzx   ebx, byte ptr [num_fats]
    imul    ebx, dword ptr [fat_sz32]
    add     eax, ebx
    mov     [root_dir_lba], eax

    # 计算 DataRegionLBA = RsvdSecCnt + (NumFATs * FATSz32)
    # (已在 eax 中)
    mov     [data_region_lba], eax

    # 标记已初始化
    mov     byte ptr [fat32_initialized], 1

    xor     eax, eax              # 返回 0 表示成功
    jmp     fat32_init_done

fat32_init_fail:
    mov     eax, 0xFFFFFFFF       # 返回 -1 表示失败
    mov     byte ptr [fat32_initialized], 0

fat32_init_done:
    pop     esi
    pop     edi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# =============================================================================
# fat32_list_root: 列出根目录文件
# 返回: eax = 文件数量
# =============================================================================
    .globl fat32_list_root
fat32_list_root:
    push    ebx
    push    ecx
    push    edx
    push    edi
    push    esi

    # 检查是否已初始化
    cmp     byte ptr [fat32_initialized], 1
    jne     fat32_list_fail

    # 读取根目录扇区
    mov     eax, [root_dir_lba]
    mov     edi, offset fat32_dir_buffer
    call    ata_read_sector
    cmp     eax, 0
    jne     fat32_list_fail

    # 遍历目录项 (每扇区 512/32 = 16 个目录项)
    mov     esi, offset fat32_dir_buffer
    mov     ecx, 16               # 16 entries per sector
    xor     ebx, ebx              # 文件计数器

fat32_list_loop:
    # 检查目录项第一个字节
    movzx   eax, byte ptr [esi]

    # 0x00 = 目录结束
    cmp     al, 0x00
    je      fat32_list_done

    # 0xE5 = 已删除项，跳过
    cmp     al, 0xE5
    je      fat32_list_next

    # 检查属性字节
    movzx   eax, byte ptr [esi + DIR_ATTR]

    # 跳过长文件名项 (0x0F)
    cmp     al, ATTR_LONG_NAME
    je      fat32_list_next

    # 跳过卷标 (0x08)
    cmp     al, ATTR_VOLUME_ID
    je      fat32_list_next

    # 打印文件名 (11 字符)
    push    ecx
    push    ebx
    mov     ecx, 11

fat32_print_name:
    movzx   eax, byte ptr [esi]
    cmp     al, 0x20              # 空格
    je      fat32_print_skip
    call    uart_putc
fat32_print_skip:
    inc     esi
    dec     ecx
    jnz     fat32_print_name

    # 恢复 esi 指向目录项开始
    sub     esi, 11

    # 打印换行
    mov     al, 0x0D
    call    uart_putc
    mov     al, 0x0A
    call    uart_putc

    pop     ebx
    pop     ecx

    # 增加文件计数
    inc     ebx

fat32_list_next:
    add     esi, 32               # 下一个目录项
    dec     ecx
    jnz     fat32_list_loop

fat32_list_done:
    mov     eax, ebx              # 返回文件数量
    jmp     fat32_list_exit

fat32_list_fail:
    mov     eax, 0xFFFFFFFF       # 返回 -1 表示失败

fat32_list_exit:
    pop     esi
    pop     edi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# =============================================================================
# fat32_get_file_info: 获取文件信息
# 参数: esi = 文件名 (11 字符 8.3 格式)
# 返回: eax = 文件起始簇号, ecx = 文件大小 (如果是目录则 ecx = 0)
#       失败时 eax = 0xFFFFFFFF
# =============================================================================
    .globl fat32_get_file_info
fat32_get_file_info:
    push    ebx
    push    edx
    push    edi
    push    esi

    # 检查是否已初始化
    cmp     byte ptr [fat32_initialized], 1
    jne     fat32_get_fail

    # 读取根目录起始扇区
    mov     eax, [root_dir_lba]
    mov     edi, offset fat32_dir_buffer
    call    ata_read_sector
    cmp     eax, 0
    jne     fat32_get_fail

    # 遍历目录项（支持多扇区/多簇根目录）
    mov     edx, 16              # 16 entries per sector
    mov     ebx, [root_dir_lba]  # current sector LBA
    mov     ecx, [sec_per_clus]  # sectors per cluster counter

fat32_get_loop:
    # 检查目录项
    movzx   eax, byte ptr [edi]
    cmp     al, 0x00
    je      fat32_get_fail       # 目录结束，未找到

    cmp     al, 0xE5
    je      fat32_get_next       # 跳过已删除项

    # 检查属性 (跳过长文件名和卷标)
    movzx   eax, byte ptr [edi + DIR_ATTR]
    cmp     al, ATTR_LONG_NAME
    je      fat32_get_next
    cmp     al, ATTR_VOLUME_ID
    je      fat32_get_next

    # 比较文件名
    push    ecx
    push    edx
    push    esi
    push    edi
    mov     ecx, 11

fat32_get_cmp:
    mov     al, [esi]
    mov     bl, [edi]
    cmp     al, bl
    jne     fat32_get_cmp_fail
    inc     esi
    inc     edi
    dec     ecx
    jnz     fat32_get_cmp

    # 文件名匹配
    pop     edi                  # 恢复目录项指针
    pop     esi
    pop     edx
    pop     ecx

    # 获取簇号 (低 16 位)
    movzx   eax, word ptr [edi + DIR_FST_CLUS_LO]
    # 获取文件大小
    mov     ecx, [edi + DIR_FILE_SIZE]

    jmp     fat32_get_exit

fat32_get_cmp_fail:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    jmp     fat32_get_next

fat32_get_next:
    add     edi, 32
    dec     edx
    jnz     fat32_get_loop

    # 当前扇区读完，读取下一扇区
    inc     ebx
    dec     ecx
    jnz     .read_next_sector    # 同一簇内还有扇区

    # 簇结束，跟随 FAT 链到下一簇
    # ebx = next sector LBA (already incremented past current cluster)
    # 计算当前簇号: cluster = (ebx - data_region_lba) / sec_per_clus + 2
    mov     eax, ebx
    sub     eax, [data_region_lba]
    xor     edx, edx
    movzx   ecx, byte ptr [sec_per_clus]
    div     ecx
    add     eax, 2               # eax = current cluster number

    # 从 FAT 表读取下一簇
    push    ebx
    push    edi
    call    fat32_get_next_cluster   # eax -> next cluster (or >= 0x0FFFFFF8 for EOF)
    pop     edi
    pop     ebx

    cmp     eax, 0x0FFFFFF8
    jae     fat32_get_fail       # EOF, no more clusters

    # 计算下一簇的起始 LBA
    sub     eax, 2
    movzx   ecx, byte ptr [sec_per_clus]
    imul    eax, ecx
    add     eax, [data_region_lba]
    mov     ebx, eax
    movzx   ecx, byte ptr [sec_per_clus]

.read_next_sector:
    mov     eax, ebx
    mov     edi, offset fat32_dir_buffer
    call    ata_read_sector
    cmp     eax, 0
    jne     fat32_get_fail
    mov     edx, 16              # reset entry counter
    jmp     fat32_get_loop

fat32_get_fail:
    mov     eax, 0xFFFFFFFF
    xor     ecx, ecx

fat32_get_exit:
    pop     esi
    pop     edi
    pop     edx
    pop     ebx
    ret

# =============================================================================
# fat32_read_cluster: 读取指定簇的数据
# 参数: eax = 簇号, edi = 缓冲区
# 返回: eax = 0 成功, -1 失败
# =============================================================================
    .globl fat32_read_cluster
fat32_read_cluster:
    push    ebx
    push    ecx
    push    esi

    # Cluster -> LBA: LBA = (Cluster - 2) * SecPerClus + DataRegionLBA
    sub     eax, 2
    movzx   ebx, byte ptr [sec_per_clus]
    imul    eax, ebx
    add     eax, [data_region_lba]

    # 读取簇的所有扇区
    movzx   ecx, byte ptr [sec_per_clus]
    mov     esi, eax            # save LBA in callee-saved register
.read_sector:
    test    ecx, ecx
    jz      .done
    mov     eax, esi            # restore LBA for ata_read_sector
    call    ata_read_sector
    test    eax, eax
    jnz     .read_err
    add     edi, 512
    inc     esi                 # advance to next LBA
    dec     ecx
    jmp     .read_sector

.read_err:
    mov     eax, -1
    jmp     .cleanup

.done:
    xor     eax, eax            # success
.cleanup:
    pop     esi
    pop     ecx
    pop     ebx
    ret