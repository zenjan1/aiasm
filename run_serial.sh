#!/bin/bash
# AI-ASM Kernel launcher - Serial mode (nographic)
# Type commands directly in this terminal
# Press Ctrl-A then X to quit QEMU

cd /home/a/aiasm-v0.1
qemu-system-i386 -kernel examples/kernel/interactive -nographic -no-reboot
