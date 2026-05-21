# AI-ASM v0.1

专为AI设计的最小汇编语言工具链。基于标准x86_64 GNU汇编语法（Intel模式），零依赖，纯bash工具链。

## 安装

```bash
# 方式1：直接使用（无需编译）
chmod +x bin/aiasm-*

# 方式2：安装到系统
make install    # 需要root权限

# 方式3：仅测试，不安装
make test
```

## 快速开始

```bash
# 创建新项目
bin/aiasm-new my_project
cd my_project

# 编译
bin/aiasm-build src/hello.asm

# 运行
./hello

# 运行所有测试
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

# 运行所有测试
bin/aiasm-test tests/

# 详细输出
bin/aiasm-test -v tests/
```

### aiasm-new

```bash
bin/aiasm-new my_project
```

## 格式规范

所有汇编代码必须遵循AI-ASM格式规范：

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

测试覆盖：exit系统调用、write系统调用、加法运算、循环打印、函数调用、栈操作。

## 示例

```bash
make examples   # 编译并运行所有示例
```

包含Hello World、加法计算器、最小内核。

## Linux系统调用

| rax | 名称 | 参数 |
|-----|------|------|
| 1 | write | rdi=fd, rsi=buf, rdx=len |
| 60 | exit | rdi=status |

完整列表见 `docs/system-calls.md`。

## 许可证

MIT License. 详见LICENSE。
