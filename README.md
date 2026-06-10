# AI-ASM v1.71

专为 AI 设计的最小汇编语言工具链，包含一个从零编写的 32 位 x86 交互操作系统内核，内置 WASM 字节码运行时引擎和完整网络协议栈。基于 GNU AS 汇编语法（Intel 模式），零依赖，纯汇编实现。

**当前版本**: v1.72 | **内核版本**: v1.20 | **代码行数**: 290,163 行 | **测试状态**: ✅ 5000+ WASM 测试通过 | **Bug 修复**: ✅ 44+ 个 bug 已修复

## 目录

- [安装](#安装)
- [快速开始](#快速开始)
- [工具链](#工具链)
- [交互内核](#交互内核)
  - [运行方式](#运行方式)
  - [内置命令](#内置命令)
  - [快捷键](#快捷键)
  - [WASM 运行时](#wasm-运行时)
- [内核架构](#内核架构)
- [v0.62 新特性](#v062-新特性)
  - [三层架构](#三层架构)
  - [网络协议栈](#网络协议栈)
  - [WASM 运行时](#wasm-运行时)
  - [Shell 命令](#shell-命令)
- [格式规范](#格式规范)
- [测试](#测试)
- [示例](#示例)
- [许可证](#许可证)

## 安装

```bash
# 方式1：直接使用（无需安装）
chmod +x bin/aiasm-*

# 方式2：安装到系统路径
sudo make install

# 方式3：仅测试
make test
```

### 依赖

- `binutils`（`as`、`ld`）— 标准 GNU 汇编工具链
- `qemu-system-i386` 或 `qemu-system-x86_64` — 运行内核
- `bash` — 构建脚本

## 快速开始

```bash
# 编译交互内核
make examples/kernel/interactive

# 运行内核
make run-interactive
# 或
qemu-system-i386 -kernel examples/kernel/interactive -nographic -no-reboot
```

## 工具链

| 工具 | 功能 |
|------|------|
| `aiasm-build` | 格式验证 + 汇编 + 链接 |
| `aiasm-test` | 自动编译、运行、比对输出 |
| `aiasm-new` | 生成项目模板 |

## 交互内核

32 位 x86 交互操作系统内核，纯汇编实现，支持串口终端和 VGA 显示。

### 内核特性

- **Multiboot1** 兼容引导头，支持 QEMU 直接 `-kernel` 加载
- **VGA 文本模式**：80x25 彩色字符显示，自动滚屏
- **串口 I/O**：COM1 (0x3F8)，115200 baud，16550 UART 驱动
- **中断系统**：256 项 IDT，PIC 8259A 重映射到向量 32-47
- **PIT 定时器**：IRQ0，~100Hz 系统时钟滴答，驱动时间片调度
- **PS/2 键盘**：IRQ1 扫描码转 ASCII，Shift 支持
- **命令行 Shell**：28 个内置命令，支持退格、方向键历史
- **物理内存管理**：位图式分配器，支持 128MB，4KB 页
- **虚拟内存分页**：32 位两级分页，内核恒等映射
- **进程管理**：最多 16 进程，时间片轮转调度
- **系统调用**：INT 0x80 接口，8 个系统调用，支持 VFS/FAT32 文件操作 (open/close/read/write)
- **文件描述符表**：每进程 8 个 FD，支持 stdin/stdout/stderr/VFS/FAT32，fork 继承
- **WASM 运行时**：238 条指令，完整核心 WASM 指令集
- **网络协议栈**：e1000 驱动、ARP、ICMP ping、UDP、TCP、DHCP、HTTP 服务器

### 运行方式

#### 方式1：Makefile（最简单）

```bash
make run-interactive
```

#### 方式2：nographic 模式（推荐）

```bash
qemu-system-i386 -kernel examples/kernel/interactive -nographic -no-reboot -netdev user,id=net0 -device e1000,netdev=net0
```

#### 方式3：TCP 串口

```bash
bash run_tcp2.sh
```

#### 方式4：GTK 窗口

```bash
bash run_gtk.sh
```

### 内置命令 (28 个)

| 命令 | 功能 |
|------|------|
| `help` | 显示帮助信息 |
| `clear` | 清屏 |
| `echo <text>` | 打印文本 |
| `version` | 显示内核版本 (v1.71) |
| `tick` | 显示系统时钟滴答数 |
| `reboot` | 重启系统 |
| `shutdown` | 关闭系统 |
| `meminfo` | 显示物理内存信息 |
| `ps` | 显示进程列表 |
| `kill <pid>` | 终止进程 |
| `date` | 显示系统运行时间 |
| `ls` | 列出虚拟文件 |
| `cat <file>` | 显示文件内容 |
| `touch <file>` | 创建空文件 |
| `wasm` | 显示 WASM 模块信息 |
| `wasmrun` | 运行 WASM 测试模块 |
| `wasmtest2-11` | WASM 测试 (返回 42/倒计时/putchar 等) |
| `wasmapp <app>` | WASM 应用 (fibonacci/factorial/multiply/sum/hello/countdown/uptime) |
| `ping <ip>` | 发送 ICMP Echo Request |
| `udpsend <ip> <port> <data>` | 发送 UDP 数据包 |
| `udprecv` | 检查接收的 UDP 数据 |
| `tcpstatus` | 显示 TCP 连接状态 |
| `httpserver` | HTTP 服务器开关 (on/off/status) |
| `dhcp` | DHCP 客户端 (自动配置 IP) |
| `netpoll` | 轮询网络数据包 |
| `netstat` | 显示 TCP 连接表 (4 槽位) |
| `arp` | 显示 ARP 缓存表 (8 槽位) |

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Enter` | 执行命令 |
| `Backspace` | 删除字符 |
| `Ctrl+C` | 立即关机 |
| `上/下箭头` | 命令历史 |

## 内核架构

### 文件结构 (22 个文件, 254,065 行)

```
examples/kernel/
  kernel.asm       # 内核核心 (114KB): 引导、e1000驱动、TCP/IP、HTTP服务器
  gdt.asm          # 全局描述符表 (4.3KB)
  idt.asm          # 中断描述符表 (6.4KB, 256 向量)
  pic.asm          # 8259A PIC 重映射 (1.9KB)
  pit.asm          # PIT 定时器 (1.9KB, 100Hz)
  vga.asm          # VGA 文本驱动 (5.8KB)
  keyboard.asm     # PS/2 键盘驱动 (5.1KB)
  uart.asm         # 16550 UART 串口驱动 (3.2KB)
  log.asm          # 内核日志系统 (8.9KB)
  memory.asm       # 物理内存管理 (6.7KB, 位图式)
  paging.asm       # 虚拟内存分页 (8.5KB, 两级页表)
  process.asm      # 进程管理 (14KB, PCB+fork/yield/exit)
  syscall.asm      # 系统调用 (8.5KB, INT 0x80)
  shell.asm        # 命令行 Shell (7.0MB, 28+ 命令)
  utils.asm        # 工具函数 (7.8KB)
  vfs.asm          # 虚拟文件系统 (16KB)
  virtio_net.asm   # virtio-net 驱动框架 (21KB)
  ata.asm          # ATA 磁盘驱动 (9.4KB)
  fat32.asm        # FAT32 文件系统 (9.4KB)
  wasm_parser.asm  # WASM 字节码解析器 (29KB)
  wasm_vm.asm      # WASM 虚拟机 (170KB, 238 指令)
  wasm_syscall.asm # WASM 系统调用桥接 (16KB)
  linker.ld        # 链接脚本
```

### 引导流程

```
_start → 清零 BSS → 禁用分页 → 串口初始化 → VGA 清屏 → 日志初始化
       → GDT 加载 → IDT 加载 (256 向量) → PIC 重映射
       → PIT 初始化 → 键盘初始化 → e1000 网卡初始化
       → 物理内存初始化 → 进程管理初始化 → 系统调用初始化
       → VFS 初始化 → WASM 运行时初始化 → STI 开中断
       → Shell 启动 → aiasm> 提示符
```

## v0.62 新特性

### 三层架构

```
┌─────────────────────────────────────────────────┐
│ 应用层 (Application Layer)                       │
│ Shell: 28 命令 + WASM 应用: 7 个                  │
│ fibonacci/factorial/multiply/sum/hello/...      │
├─────────────────────────────────────────────────┤
│ WASM 中间解释层 (WASM Interpreter Layer)         │
│ wasm_parser.asm: 字节码解析器                    │
│ wasm_vm.asm: 238 条指令虚拟机                    │
│ wasm_syscall.asm: 系统调用桥接                   │
├─────────────────────────────────────────────────┤
│ 汇编底层 (Assembly Layer + WASM Runtime)         │
│ kernel.asm: 内核核心 + e1000 驱动 + TCP/IP       │
│ memory.asm: 物理内存管理 (位图式, 128MB)         │
│ paging.asm: 两级页表虚拟内存                     │
│ process.asm: PCB + fork/yield/exit              │
│ gdt/idt/pic/pit/keyboard/vga: CPU 基础设施       │
│ WASM 运行时: 内嵌于 kernel.asm                   │
└─────────────────────────────────────────────────┘
```

### 网络协议栈

| 协议 | 功能 |
|------|------|
| **e1000 驱动** | Intel 82540EM 网卡驱动 (MMIO) |
| **ARP** | ARP 缓存 (8 槽位)，自动填充 |
| **ICMP** | Echo Request/Reply (ping) |
| **UDP** | 发送/接收 + Echo Server (端口 7) |
| **TCP** | 4 并发连接，完整状态机，HTTP 服务器 (端口 80) |
| **DHCP** | Discover/Request/ACK，自动配置 IP |
| **HTTP** | URL 路由 (/status/version/tcpstatus)，动态响应 |

### WASM 运行时 (238 指令)

- **控制流**: unreachable, nop, block, loop, if, else, end, br, br_if, br_table, return, call, call_indirect
- **参数**: drop, select
- **变量**: local.get/set/tee, global.get/set
- **内存**: i32/i64/f32/f64.load/store, memory.size/grow
- **数值**: i32/i64/f32/f64 所有算术、比较、转换指令
- **宿主函数**: print, println, putchar, getchar, meminfo, time, alloc, free

### Shell 命令分类

| 类别 | 命令 |
|------|------|
| 系统 | help, version, tick, reboot, shutdown, clear, echo |
| 内存 | meminfo |
| 进程 | ps, kill |
| 文件 | ls, cat, touch, date |
| WASM | wasm, wasmrun, wasmtest2-11, wasmapp |
| 网络 | ping, udpsend, udprecv, tcpstatus, httpserver, dhcp, netpoll, netstat, arp |

## 格式规范

所有汇编代码遵循 AI-ASM 格式规范（Intel 语法）：

```asm
    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：add
# 功能：两个数相加
# 输入：rdi = a, rsi = b
# 输出：rax = result
# -----------------------------------------------------------------------------
    .globl  add
add:
    mov     rax, rdi
    add     rax, rsi
    ret
```

## 测试

```bash
make test       # 运行所有测试

# QEMU 内核测试
make examples/kernel/interactive
qemu-system-i386 -kernel examples/kernel/interactive -nographic -no-reboot
```

WASM 测试全部通过：wasmtest2-11 + wasmapp (fibonacci/factorial/multiply/sum)

## 示例

| 示例 | 说明 |
|------|------|
| `hello.asm` | Hello World 用户态程序 |
| `calculator.asm` | 简单算术运算 |
| `minimal_kernel.asm` | 最小 32 位内核 |
| `kernel/interactive` | 完整交互内核 (v0.58) |

## 版本历史

| 版本 | 主要特性 |
|------|----------|
| v1.72 | 🎉 正式发布 - 44+ bug修复 + FD表系统 + syscall重构 + 进程管理增强 |
| v1.71 | 🎉 正式发布 - README 完善 + 项目发布准备 + .gitignore |
| v1.70 | 5000 WASM 测试超级里程碑，wasmtest4501-5000 |
| v1.69 | 内核 HTTP 响应头版本更新 |
| v1.68 | 4000 WASM 测试里程碑，wasmtest3501-4000 |
| v1.67 | 3500 WASM 测试，wasmtest3001-3500 |
| v1.66 | 3000 WASM 测试，wasmtest2501-3000 |
| v1.65 | 2500 WASM 测试，wasmtest2101-2500 |
| v1.64 | 2100 WASM 测试，wasmtest2001-2100 |
| v0.99 | ATA 磁盘驱动 (diskinfo/diskread 命令) |
| v0.98 | 用户模式进入 (ring 3) |
| v0.97 | TSS 任务状态段支持 |
| v0.96 | Multiboot 引导加载器支持 |
| v0.95 | WASM 交互式 REPL |
| v0.94 | WASM syscall 应用测试 |
| v0.93 | WASM 文件加载功能 |
| v0.92 | wasmtest86-95 完整转换运算测试 |
| v0.91 | wasmtest81-85 f32/f64 copysign和转换测试 |
| v0.50-0.90 | 网络协议栈 + WASM 运行时完善 |
| v0.01-0.49 | 内核核心 + WASM 基础 |

## 许可证

MIT License. 详见 LICENSE。

## v1.72 更新日志

### Bug 修复 (44+)
- **进程管理**: PCB_SIZE 统一到 272 字节 (含 FD 表), yield() 寄存器保存修复, exit() FD 清理
- **系统调用**: 正确栈帧读取 (ebp+48), 寄存器保存/恢复, FD 验证 (FD_TYPE_FREE 检查)
- **分页系统**: get_physical_address 页偏移修复, demand_page_alloc 页表索引修复
- **FAT32**: 多扇区根目录遍历, FAT 链跟随, read_cluster LBA 保存修复
- **僵尸进程**: _reap_zombies 循环计数器修复 (eax→esi)
- **其他**: shell.asm PCB 偏移修复, 死代码清理, 重复定义删除

### 新功能
- **文件描述符表**: 每进程 8 个 FD (stdin/stdout/stderr + 5 个文件), fork 继承
- **sys_open/sys_close**: VFS + FAT32 文件打开/关闭
- **FD 类型系统**: FD_TYPE_FREE/STDIN/STDOUT/STDERR/VFS/FAT32
- **FPU 支持**: FPU 初始化, PCB FPU 状态保存区