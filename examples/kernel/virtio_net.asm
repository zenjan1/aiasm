.intel_syntax noprefix
# -----------------------------------------------------------------------------
# virtio_net.asm - Virtio-net 网络驱动 (QEMU -device virtio-net-pci)
# -----------------------------------------------------------------------------
# PCI设备发现 + Virtio队列初始化 + 基本收发
# -----------------------------------------------------------------------------
    .code32

# ============================================================================
# Virtio-net 常量定义
# ============================================================================
VIRTIO_NET_VENDOR_ID      = 0x1AF4    # Red Hat, Inc.
VIRTIO_NET_DEVICE_ID      = 0x1000    # virtio-net
VIRTIO_NET_MODERN_DEVICE_ID = 0x1041  # virtio-net modern

# Virtio PCI 配置空间偏移
VIRTIO_PCI_CAP_COMMON     = 1         # Common configuration
VIRTIO_PCI_CAP_NOTIFY     = 2         # Notifications
VIRTIO_PCI_CAP_ISR        = 3         # ISR status
VIRTIO_PCI_CAP_DEVICE     = 4         # Device-specific configuration
VIRTIO_PCI_CAP_PCI_CONFIG = 5         # PCI configuration access

# Virtio 队列常量
VIRTQ_SIZE                = 256       # 队列大小（可用描述符数量）
VIRTQ_DESC_SIZE           = 16        # 描述符大小（16字节）
VIRTQ_AVAIL_SIZE          = 8         # 可用环大小（不含数组）
VIRTQ_USED_SIZE           = 8         # 已用环大小（不含数组）

# Virtio-net 特性位
VIRTIO_NET_F_MAC          = (1 << 5)  # 设备有MAC地址

# Virtio-net 包头
VIRTIO_NET_HDR_SIZE       = 12        # 包头大小

# ============================================================================
# Virtio-net 设备状态
# ============================================================================
    .section .bss
    .align  4
    .globl  virtio_net_status
virtio_net_status:
    .space  4                    # 0=未初始化, 1=已初始化

virtio_pci_io_base:
    .space  4                    # PCI IO基地址

    .globl  virtio_irq_line
virtio_irq_line:
    .space  4                    # IRQ线号

virtio_irq_mask:
    .space  4                    # IRQ mask for PIC

    .globl  virtio_net_mac
virtio_net_mac:
    .space  6                    # MAC地址

# 队列描述符表（接收队列）
virtq_rx_desc:
    .space  VIRTQ_SIZE * VIRTQ_DESC_SIZE

virtq_rx_avail:
    .space  VIRTQ_AVAIL_SIZE + VIRTQ_SIZE * 2

virtq_rx_used:
    .space  VIRTQ_USED_SIZE + VIRTQ_SIZE * 4

# 队列描述符表（发送队列）
virtq_tx_desc:
    .space  VIRTQ_SIZE * VIRTQ_DESC_SIZE

virtq_tx_avail:
    .space  VIRTQ_AVAIL_SIZE + VIRTQ_SIZE * 2

virtq_tx_used:
    .space  VIRTQ_USED_SIZE + VIRTQ_SIZE * 4

# 接收缓冲区
net_rx_buffer:
    .space  2048                 # 单个接收包最大2KB

# 发送缓冲区
net_tx_buffer:
    .space  2048                 # 单个发送包最大2KB

virtq_rx_avail_idx:
    .space  4

virtq_tx_avail_idx:
    .space  4

virtq_rx_used_idx:
    .space  4

virtq_tx_used_idx:
    .space  4

# ============================================================================
# PCI 配置空间访问 (IO端口 0xCF8-0xCFF)
# ============================================================================
    .section .text

# pci_read_config: 读取PCI配置空间
# 输入: eax = bus, edx = device, ecx = function, ebx = offset
# 输出: eax = 32位配置值
    .globl  pci_read_config
pci_read_config:
    push    edx
    push    ecx

    # 构造配置地址: (bus << 16) | (device << 11) | (func << 8) | offset | 0x80000000
    shl     eax, 16              # bus << 16
    and     edx, 0x1F
    shl     edx, 11              # device << 11
    or      eax, edx
    and     ecx, 0x07
    shl     ecx, 8               # function << 8
    or      eax, ecx
    and     ebx, 0xFC            # offset & 0xFC
    or      eax, ebx
    or      eax, 0x80000000      # enable bit

    # 写入地址端口
    mov     dx, 0xCF8
    out     dx, eax

    # 读取数据端口
    mov     dx, 0xCFC
    in      eax, dx

    pop     ecx
    pop     edx
    ret

# pci_write_config: 写入PCI配置空间
# 输入: eax = bus, edx = device, ecx = function, ebx = offset, edi = value
pci_write_config:
    push    eax
    push    edx
    push    ecx

    # 构造配置地址
    shl     eax, 16
    and     edx, 0x1F
    shl     edx, 11
    or      eax, edx
    and     ecx, 0x07
    shl     ecx, 8
    or      eax, ecx
    and     ebx, 0xFC
    or      eax, ebx
    or      eax, 0x80000000

    mov     dx, 0xCF8
    out     dx, eax

    mov     dx, 0xCFC
    mov     eax, edi
    out     dx, eax

    pop     ecx
    pop     edx
    pop     eax
    ret

# ============================================================================
# pci_find_virtio_net: 查找 Virtio-net PCI 设备
# 输出: eax = 1 找到, 0 未找到; [virtio_pci_io_base] = IO基地址
# ============================================================================
    .globl  pci_find_virtio_net
pci_find_virtio_net:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    xor     ebx, ebx             # bus = 0

.pci_bus_loop:
    xor     edx, edx             # device = 0

.pci_dev_loop:
    xor     ecx, ecx             # function = 0

.pci_func_loop:
    # 读取 Vendor ID (offset 0)
    push    ebx
    push    ecx
    push    edx
    mov     eax, ebx
    mov     ebx, 0               # offset = 0
    call    pci_read_config
    pop     edx
    pop     ecx
    pop     ebx

    # 检查设备是否存在 (Vendor ID != 0xFFFF)
    and     eax, 0xFFFF
    cmp     ax, 0xFFFF
    je      .pci_next_func

    # 读取 Device ID (offset 2)
    push    ebx
    push    ecx
    push    edx
    mov     eax, ebx
    mov     ebx, 2
    call    pci_read_config
    pop     edx
    pop     ecx
    pop     ebx

    shr     eax, 16              # Device ID在高16位
    and     eax, 0xFFFF

    # 检查是否是 Virtio-net
    cmp     ax, VIRTIO_NET_DEVICE_ID
    je      .pci_found_legacy
    cmp     ax, VIRTIO_NET_MODERN_DEVICE_ID
    je      .pci_found_modern

    jmp     .pci_next_func

.pci_found_legacy:
    # 读取 BAR0 (offset 16) - IO基地址
    push    ebx
    push    ecx
    push    edx
    mov     eax, ebx
    mov     ebx, 16              # BAR0 offset
    call    pci_read_config
    pop     edx
    pop     ecx
    pop     ebx

    and     eax, 0xFFFFFFFC      # 清除类型位
    mov     [virtio_pci_io_base], eax

    # 读取 IRQ Line (offset 60)
    push    ebx
    push    ecx
    push    edx
    mov     eax, ebx
    mov     ebx, 60              # IRQ Line offset
    call    pci_read_config
    pop     edx
    pop     ecx
    pop     ebx

    and     eax, 0xFF            # IRQ Line在低8位
    mov     [virtio_irq_line], eax

    # 计算IRQ mask: ~(1 << irq)
    mov     ecx, eax
    mov     eax, 1
    shl     eax, cl
    not     eax
    mov     [virtio_irq_mask], eax

    # 启用设备 (设置命令寄存器: IO + Bus Master)
    push    ebx
    push    ecx
    push    edx
    mov     eax, ebx             # bus
    mov     ebx, 4               # Command register offset
    mov     edi, 0x0007          # IO + Bus Master + Memory
    call    pci_write_config
    pop     edx
    pop     ecx
    pop     ebx

    mov     eax, 1               # 找到
    jmp     .pci_done

.pci_found_modern:
    # Modern virtio 使用 MMIO (需要额外处理)
    # 简化: 使用 legacy 模式
    jmp     .pci_next_func

.pci_next_func:
    inc     ecx
    cmp     ecx, 8               # 最多8个function
    jl      .pci_func_loop

.pci_next_dev:
    inc     edx
    cmp     edx, 32              # 最多32个device
    jl      .pci_dev_loop

.pci_next_bus:
    inc     ebx
    cmp     ebx, 256             # 最多256个bus
    jl      .pci_bus_loop

    xor     eax, eax             # 未找到

.pci_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# Virtio IO 端口操作 (legacy mode)
# ============================================================================
# 寄存器偏移:
#   0x00: Device Features (R)
#   0x04: Guest Features (W)
#   0x08: Queue Address (W)
#   0x0C: Queue Size (R)
#   0x10: Queue Select (W)
#   0x14: Queue Notify (W)
#   0x18: Device Status (R/W)
#   0x1C: Config Vector (W)
#   0x20-0x3F: Device Config (net: MAC at 0x00-0x05)
# ============================================================================

VIRTIO_REG_DEVICE_FEATURES = 0x00
VIRTIO_REG_GUEST_FEATURES  = 0x04
VIRTIO_REG_QUEUE_ADDRESS   = 0x08
VIRTIO_REG_QUEUE_SIZE      = 0x0C
VIRTIO_REG_QUEUE_SELECT    = 0x10
VIRTIO_REG_QUEUE_NOTIFY    = 0x14
VIRTIO_REG_DEVICE_STATUS   = 0x18
VIRTIO_REG_CONFIG_VECTOR   = 0x1C
VIRTIO_REG_DEVICE_CONFIG   = 0x20
VIRTIO_REG_ISR_STATUS      = 0x100

# virtio_read_reg: 读取 Virtio 寄存器
# 输入: ecx = 寄存器偏移
# 输出: eax = 值
virtio_read_reg:
    mov     edx, [virtio_pci_io_base]
    add     edx, ecx
    in      eax, dx
    ret

# virtio_write_reg: 写入 Virtio 寄存器
# 输入: ecx = 寄存器偏移, eax = 值
virtio_write_reg:
    mov     edx, [virtio_pci_io_base]
    add     edx, ecx
    out     dx, eax
    ret

# ============================================================================
# virtio_net_init: 初始化 Virtio-net 设备
# 输出: eax = 0 成功, 其他失败
# ============================================================================
    .globl  virtio_net_init
virtio_net_init:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    # 查找设备
    call    pci_find_virtio_net
    test    eax, eax
    jz      .vnet_not_found

    # 重置设备
    mov     ecx, VIRTIO_REG_DEVICE_STATUS
    xor     eax, eax
    call    virtio_write_reg

    # 等待复位完成
    mov     ebx, 100000
.vnet_wait_reset:
    dec     ebx
    jz      .vnet_reset_failed
    mov     ecx, VIRTIO_REG_DEVICE_STATUS
    call    virtio_read_reg
    test    eax, eax
    jnz     .vnet_wait_reset

    # 读取设备特性
    mov     ecx, VIRTIO_REG_DEVICE_FEATURES
    call    virtio_read_reg
    mov     esi, eax

    # 检查 MAC 特性
    test    eax, VIRTIO_NET_F_MAC
    jz      .vnet_no_mac

    # 读取 MAC 地址
    mov     edx, [virtio_pci_io_base]
    add     edx, VIRTIO_REG_DEVICE_CONFIG
    xor     ecx, ecx
.vnet_read_mac:
    in      al, dx
    mov     [virtio_net_mac + ecx], al
    inc     ecx
    inc     edx
    cmp     ecx, 6
    jl      .vnet_read_mac

.vnet_no_mac:

    # 协商特性 (接受 MAC 特性)
    mov     ecx, VIRTIO_REG_GUEST_FEATURES
    mov     eax, VIRTIO_NET_F_MAC
    call    virtio_write_reg

    # 设置设备状态: ACKNOWLEDGE
    mov     ecx, VIRTIO_REG_DEVICE_STATUS
    mov     eax, 1               # ACKNOWLEDGE
    call    virtio_write_reg

    # 设置设备状态: DRIVER
    mov     ecx, VIRTIO_REG_DEVICE_STATUS
    mov     eax, 2               # DRIVER
    call    virtio_write_reg

    # 初始化接收队列 (Queue 0)
    mov     ecx, VIRTIO_REG_QUEUE_SELECT
    xor     eax, eax             # Queue 0 = RX
    call    virtio_write_reg

    # 读取队列大小
    mov     ecx, VIRTIO_REG_QUEUE_SIZE
    call    virtio_read_reg
    mov     edi, eax             # 保存队列大小

    # 设置队列地址 (物理地址, 32位对齐)
    # 描述符表 + 可用环 + 已用环 必须连续
    mov     ecx, VIRTIO_REG_QUEUE_ADDRESS
    mov     eax, offset virtq_rx_desc
    shr     eax, 12              # 页号 (地址 / 4096)
    call    virtio_write_reg

    # 初始化发送队列 (Queue 1)
    mov     ecx, VIRTIO_REG_QUEUE_SELECT
    mov     eax, 1               # Queue 1 = TX
    call    virtio_write_reg

    # 读取队列大小
    mov     ecx, VIRTIO_REG_QUEUE_SIZE
    call    virtio_read_reg

    # 设置队列地址
    mov     ecx, VIRTIO_REG_QUEUE_ADDRESS
    mov     eax, offset virtq_tx_desc
    shr     eax, 12
    call    virtio_write_reg

    # 初始化队列索引
    xor     eax, eax
    mov     [virtq_rx_avail_idx], eax
    mov     [virtq_tx_avail_idx], eax
    mov     [virtq_rx_used_idx], eax
    mov     [virtq_tx_used_idx], eax

    # 初始化接收描述符
    call    virtio_init_rx_desc

    # 设置设备状态: DRIVER_OK
    mov     ecx, VIRTIO_REG_DEVICE_STATUS
    mov     eax, 4               # DRIVER_OK
    call    virtio_write_reg

    # 注册中断处理
    mov     eax, [virtio_irq_line]
    add     eax, 32              # IRQ向量 = IRQ线 + 32
    mov     edi, eax
    mov     eax, offset virtio_net_irq_handler
    call    idt_set_gate

    # 在PIC中启用IRQ
    call    virtio_enable_irq

    mov     dword ptr [virtio_net_status], 1
    xor     eax, eax             # 成功
    jmp     .vnet_done

.vnet_not_found:
    mov     eax, 1
    jmp     .vnet_done

.vnet_reset_failed:
    mov     eax, 2
    jmp     .vnet_done

.vnet_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# virtio_init_rx_desc: 初始化接收描述符
# ============================================================================
virtio_init_rx_desc:
    push    eax
    push    ecx
    push    edx

    # 设置描述符0: 包头 + 数据缓冲区
    # desc[0].addr = net_rx_buffer
    # desc[0].len = VIRTIO_NET_HDR_SIZE + 2048
    # desc[0].flags = VIRTQ_DESC_F_WRITE (设备写入)

    mov     eax, offset net_rx_buffer
    mov     [virtq_rx_desc + 0], eax      # addr low
    mov     dword ptr [virtq_rx_desc + 4], 0  # addr high (32位地址)

    mov     dword ptr [virtq_rx_desc + 8], VIRTIO_NET_HDR_SIZE + 2048  # len

    mov     dword ptr [virtq_rx_desc + 12], 2    # flags = WRITE
    mov     word ptr [virtq_rx_desc + 14], 0     # next (unused for single desc)

    # 初始化可用环
    mov     word ptr [virtq_rx_avail + 0], 0     # flags
    mov     word ptr [virtq_rx_avail + 2], 1     # avail_idx = 1
    mov     word ptr [virtq_rx_avail + 4], 0     # ring[0] = desc index 0

    # 通知设备
    mov     ecx, VIRTIO_REG_QUEUE_NOTIFY
    xor     eax, eax                     # Queue 0 = RX
    call    virtio_write_reg

    pop     edx
    pop     ecx
    pop     eax
    ret

# ============================================================================
# virtio_enable_irq: 在PIC中启用virtio IRQ
# ============================================================================
virtio_enable_irq:
    push    eax
    push    edx

    mov     eax, [virtio_irq_line]
    cmp     eax, 8
    jl      .irq_master

    # 从片IRQ (8-15): 清除从片对应位
    mov     dx, 0xA1
    in      al, dx
    mov     edx, [virtio_irq_mask]
    shr     edx, 8
    and     al, dl
    out     dx, al
    jmp     .irq_done

.irq_master:
    # 主片IRQ (0-7): 清除主片对应位
    mov     dx, 0x21
    in      al, dx
    mov     edx, [virtio_irq_mask]
    and     al, dl
    out     dx, al

.irq_done:
    pop     edx
    pop     eax
    ret

# ============================================================================
# virtio_net_irq_handler: Virtio-net 中断处理
# ============================================================================
    .globl  virtio_net_irq_handler
virtio_net_irq_handler:
    push    eax
    push    ecx
    push    edx

    # 读取 ISR 状态
    mov     edx, [virtio_pci_io_base]
    add     edx, VIRTIO_REG_ISR_STATUS
    in      al, dx

    # 检查是否有已用缓冲区
    test    al, 1                # Used buffer notification
    jz      .irq_no_used

    # 处理接收完成
    call    virtio_process_rx

.irq_no_used:
    # 发送 EOI
    mov     eax, [virtio_irq_line]
    call    pic_send_eoi

    pop     edx
    pop     ecx
    pop     eax
    ret

# ============================================================================
# virtio_process_rx: 处理接收到的包
# ============================================================================
virtio_process_rx:
    push    eax
    push    ecx
    push    edx

    # 读取已用环索引
    mov     eax, [virtq_rx_used_idx]
    mov     edx, [virtq_rx_used + 2]    # used_idx

    # 检查是否有新的已用项
    cmp     eax, edx
    je      .rx_done

    # 有新包: 读取已用环项
    mov     ecx, eax
    and     ecx, 0xFF
    shl     ecx, 3               # * 8 (每个used项8字节)
    add     ecx, offset virtq_rx_used + 8

    # used[0].id = 描述符索引
    # used[0].len = 实际写入长度
    mov     eax, [ecx]           # id
    mov     edx, [ecx + 4]       # len

    # 数据在 net_rx_buffer + VIRTIO_NET_HDR_SIZE
    # (这里简化: 不处理包头，直接输出数据)

    # 更新已用索引
    mov     eax, [virtq_rx_used_idx]
    inc     eax
    and     eax, 0xFF
    mov     [virtq_rx_used_idx], eax

    # 重新提交缓冲区
    call    virtio_init_rx_desc

.rx_done:
    pop     edx
    pop     ecx
    pop     eax
    ret

# ============================================================================
# virtio_net_transmit: 发送网络包
# 输入: esi = 数据地址, ecx = 数据长度
# 输出: eax = 0 成功
# ============================================================================
    .globl  virtio_net_transmit
virtio_net_transmit:
    push    ebx
    push    ecx
    push    edx
    push    edi

    # 复制数据到发送缓冲区 (包头 + 数据)
    # 包头: 前12字节 (flags=0, gso_type=0)
    mov     edi, offset net_tx_buffer
    xor     eax, eax
    mov     [edi], eax           # flags = 0
    mov     [edi + 4], eax       # gso_type = 0
    mov     [edi + 8], eax       # hdr_len = 0

    # 复制数据
    push    ecx
    add     edi, VIRTIO_NET_HDR_SIZE
    shr     ecx, 2               # 字数
    cld
    rep     movsd
    pop     ecx

    # 设置发送描述符
    mov     eax, offset net_tx_buffer
    mov     [virtq_tx_desc + 0], eax
    mov     dword ptr [virtq_tx_desc + 4], 0
    mov     dword ptr [virtq_tx_desc + 8], VIRTIO_NET_HDR_SIZE
    mov     dword ptr [virtq_tx_desc + 12], 0    # flags (设备读取)
    mov     word ptr [virtq_tx_desc + 14], 1     # next = 1

    # 第二个描述符: 数据
    mov     eax, offset net_tx_buffer + VIRTIO_NET_HDR_SIZE
    mov     [virtq_tx_desc + 16], eax
    mov     dword ptr [virtq_tx_desc + 20], 0
    mov     [virtq_tx_desc + 24], ecx            # len
    mov     dword ptr [virtq_tx_desc + 28], 0    # flags
    mov     word ptr [virtq_tx_desc + 30], 0     # next

    # 初始化可用环
    mov     word ptr [virtq_tx_avail + 0], 0     # flags
    mov     word ptr [virtq_tx_avail + 2], 2     # avail_idx = 2
    mov     word ptr [virtq_tx_avail + 4], 0     # ring[0] = desc[0]
    mov     word ptr [virtq_tx_avail + 6], 1     # ring[1] = desc[1]

    # 通知设备
    mov     ecx, VIRTIO_REG_QUEUE_NOTIFY
    mov     eax, 1               # Queue 1 = TX
    call    virtio_write_reg

    xor     eax, eax

    pop     edi
    pop     edx
    pop     ecx
    pop     ebx
    ret

# ============================================================================
# virtio_net_get_mac: 获取MAC地址
# 输出: esi = MAC地址指针
# ============================================================================
    .globl  virtio_net_get_mac
virtio_net_get_mac:
    mov     esi, offset virtio_net_mac
    ret

# ============================================================================
# virtio_net_poll: 检查并处理接收到的包
# ============================================================================
    .globl  virtio_net_poll
virtio_net_poll:
    push    eax
    push    ecx
    push    edx

    # 检查已用环索引
    mov     eax, [virtq_rx_used_idx]
    mov     edx, [virtq_rx_used + 2]

    cmp     eax, edx
    je      .poll_done

    # 有新包，处理
    call    virtio_process_rx

.poll_done:
    pop     edx
    pop     ecx
    pop     eax
    ret

# ============================================================================
# 外部符号
# ============================================================================
    .globl  idt_set_gate
    .globl  pic_send_eoi
