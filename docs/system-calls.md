# Linux x86_64 系统调用表

## 常用系统调用

| rax | 名称 | rdi | rsi | rdx | r10 | r8 | r9 | 返回值(rax) |
|-----|------|-----|-----|-----|-----|----|----|-----------|
| 0 | read | fd | buf | len | - | - | - | bytes read |
| 1 | write | fd | buf | len | - | - | - | bytes written |
| 60 | exit | status | - | - | - | - | - | - |
| 2 | open | pathname | flags | mode | - | - | - | fd |
| 12 | brk | addr | - | - | - | - | - | new_brk |
| 9 | mmap | addr | len | prot | flags | fd | offset | addr |

## 使用示例

```asm
; 写入字符串到stdout
mov     rax, 1          ; syscall: write
mov     rdi, 1          ; fd: stdout
lea     rsi, [rel msg]  ; buffer address
mov     rdx, msg_len    ; buffer length
syscall

; 退出程序
mov     rax, 60         ; syscall: exit
mov     rdi, 0          ; exit status
syscall
```
