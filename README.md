# AI-ASM v0.2

专为 AI 设计的最小汇编语言工具链，包含一个从零编写的 32 位 x86 交互操作系统内核。基于 GNU AS 汇编语法（Intel 模式），零依赖，纯汇编实现。

## 目录

- [安装](#安装)
- [快速开始](#快速开始)
- [工具链](#工具链)
- [交互内核](#交互内核)
  - [运行方式](#运行方式)
  - [内置命令](#内置命令)
  - [快捷键](#快捷键)
- [内核架构](#内核架构)
- [格式规范](#格式规范)
- [测试](#测试)
- [示例](#示例)
- [系统调用](#系统调用)
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
# 创建新项目
bin/aiasm-new my_project
cd my_project

# 编译
bin/aiasm-build src/hello.asm

# 运行
./hello

# 运行测试
bin/aiasm-test tests/
```

## 工具链

| 工具 | 功能 |
|------|------|
| `aiasm-build` | 格式验证 + 汇编 + 链接 |
| `aiasm-test` | 自动编译、运行、比对输出 |
| `aiasm-new` | 生成项目模板 |

### aiasm-build

```bash
aiasm-build [-s] [-v] [-o output] input.asm [output]

-s, --static    静态链接
-v, --verbose   详细输出
-o, --output    指定输出文件名
```

### aiasm-test

```bash
aiasm-test [-v] [test_directory]
```

### aiasm-new

```bash
bin/aiasm-new my_project
```

## 交互内核

32 位 x86 交互操作系统内核，纯汇编实现，支持串口终端和 VGA 显示。

### 内核特性

- **Multiboot1** 兼容引导头，支持 QEMU 直接 `-kernel` 加载
- **VGA 文本模式**：80x25 彩色字符显示，自动滚屏
- **串口 I/O**：COM1 (0x3F8)，38400 baud
- **中断系统**：48 项 IDT，PIC 8259A 重映射到向量 32-47
- **PIT 定时器**：IRQ0，~100Hz 系统时钟滴答
- **PS/2 键盘**：IRQ1 扫描码转 ASCII，Shift 支持
- **命令行 Shell**：支持退格、方向键历史、引号去除

### 运行方式

#### 方式1：Makefile（最简单）

```bash
make run-interactive
```

#### 方式2：nographic 模式（推荐，直接在终端交互）

```bash
qemu-system-x86_64 -kernel examples/kernel/interactive -nographic -no-reboot
```

#### 方式3：TCP 串口（类 telnet 体验）

```bash
bash run_tcp2.sh
# 自动连接，输入 Ctrl-C 退出
```

#### 方式4：GTK 窗口（需要图形界面）

```bash
bash run_gtk.sh
```

### 重要提示

启动命令 **必须** 加上 `-no-reboot` 参数，否则 `shutdown` 命令会重启 QEMU 而不是退出：

```bash
qemu-system-x86_64 -kernel examples/kernel/interactive -nographic -no-reboot
```

### 内置命令

| 命令 | 功能 |
|------|------|
| `help` | 显示帮助信息 |
| `clear` | 清屏 |
| `echo <text>` | 打印文本（支持引号：`echo "hello"` → `hello`） |
| `version` | 显示内核版本 |
| `tick` | 显示系统时钟滴答数 |
| `reboot` | 重启系统 |
| `shutdown` | 关闭系统并退出 QEMU |

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Enter` | 执行命令 |
| `Backspace` | 删除最后一个字符 |
| `Ctrl+C` | 立即关机 |
| `ESC [ A` (上箭头) | 恢复上一条命令 |
| `ESC [ B` (下箭头) | 清空缓冲区 |
| `ESC [ C` (右箭头) | 光标右移 |
| `ESC [ D` (左箭头) | 光标左移 |

## 内核架构

### 文件结构

```
examples/kernel/
  kernel.asm     # 入口、引导序列、串口 I/O、halt/reboot
  gdt.asm        # 全局描述符表（flat 4GB，内核+用户）
  idt.asm        # 中断描述符表 + 48 个中断处理（宏生成）
  pic.asm        # 8259A PIC 重映射、EOI
  pit.asm        # PIT 定时器（IRQ0，~100Hz 滴答计数器）
  vga.asm        # VGA 文本驱动：putchar、滚屏、光标、颜色
  keyboard.asm   # PS/2 键盘 IRQ1 处理、扫描码转 ASCII
  shell.asm      # 命令行 shell：退格、回车、方向键、命令分发
  utils.asm      # 工具函数：memset、memcpy、strlen、strcmp、strncmp、itoa
  linker.ld      # 链接脚本
```

### 引导流程

```
_start → 禁用分页 → 串口初始化 → VGA 清屏
       → GDT 加载 → IDT 加载 → PIC 重映射
       → PIT 初始化 → 键盘初始化
       → STI（开中断）→ shell_run（交互循环）
```

### 内存布局

| 区域 | 地址 | 说明 |
|------|------|------|
| 内核代码 | 0x100000+ | 由 Multiboot 加载 |
| 栈 | .bss 8KB | 内核栈，从高地址向下生长 |
| VGA 缓冲 | 0xB8000 | 80x25 彩色文本缓冲区 |
| 串口 COM1 | 0x3F8-0x3FF | UART 寄存器 |

### 关键组件

#### GDT

5 个描述符：NULL、内核代码(0x08)、内核数据(0x10)、用户代码(0x18)、用户数据(0x20)。

#### IDT

48 项中断描述符，覆盖异常(0-31)和 IRQ(32-47)。PIC 重映射后，IRQ0(PIT) = 向量 32，IRQ1(键盘) = 向量 33。

#### Shell 输入循环

1. 从串口读取字符
2. 判断控制字符：ESC 序列、退格、回车、Ctrl+C
3. 可打印字符追加到 128 字节命令缓冲区
4. 回车后分发给 `shell_dispatch` 进行命令匹配

## 格式规范

所有汇编代码必须遵循 AI-ASM 格式规范：

```asm
    .intel_syntax noprefix
# -----------------------------------------------------------------------------
# 函数：add
# 功能：两个数相加
# 输入：
#   rdi - a : integer
#   rsi - b : integer
# 输出：
#   rax - result : integer
# 破坏的寄存器：rax
# 栈使用：0字节
# -----------------------------------------------------------------------------
    .globl  add

add:
    mov     rax, rdi
    add     rax, rsi
    ret
```

完整规范见 `docs/format-spec.md`。

## 测试

```bash
make test       # 运行所有测试
```

测试覆盖：exit 系统调用、write 系统调用、加法运算、循环打印、函数调用、栈操作。

## 示例

```bash
make examples   # 编译并运行所有示例
```

| 示例 | 说明 |
|------|------|
| `hello.asm` | Hello World 用户态程序 |
| `calculator.asm` | 简单算术运算 |
| `minimal_kernel.asm` | 最小 32 位内核（串口输出） |
| `kernel/interactive` | 完整交互内核（VGA + 串口 + 键盘 + Shell） |

## 系统调用

### Linux 用户态

| rax | 名称 | 参数 |
|-----|------|------|
| 1 | write | rdi=fd, rsi=buf, rdx=len |
| 60 | exit | rdi=status |

完整列表见 `docs/system-calls.md`。

### 内核 ABI

内核函数通过 `call` 直接调用，不使用系统调用约定。参数通过寄存器或全局变量传递：

| 函数 | 说明 |
|------|------|
| `serial_putchar` | 串口输出单字符（al） |
| `serial_getchar` | 串口输入单字符 → al |
| `serial_print_string` | 串口输出字符串（esi=ptr, ecx=len） |
| `vga_putchar` | VGA 输出单字符（al） |
| `vga_print_string` | VGA 输出字符串（esi=ptr, ecx=len） |
| `vga_clear` | VGA 清屏 |
| `get_tick_count` | 获取系统滴答数 → eax |
| `keyboard_getchar` | 阻塞读取键盘字符 → al |
| `utils_strlen` | 计算字符串长度（esi=str → eax） |
| `utils_strcmp` | 字符串比较（esi=a, edi=b → eax: 0=等, 1=不等） |
| `utils_strncmp` | 字符串前缀比较（esi=a, edi=b, ecx=n → eax） |
| `utils_itoa` | 整数转字符串（eax=value, edi=buf, dl=base → eax=ptr） |
| `kernel_halt` | 关闭系统并退出 QEMU |
| `kernel_reboot` | 重启系统（PS/2 控制器 0xFE） |

## 许可证

MIT License. 详见 LICENSE。
