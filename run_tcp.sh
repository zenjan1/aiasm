#!/bin/bash
# AI-ASM Kernel launcher - Telnet serial mode
# Connect with: telnet localhost 4444  (or nc localhost 4444)

cd /home/a/aiasm-v0.1

echo "Starting QEMU with serial on TCP port 4444..."
echo "Connect with: telnet localhost 4444"
echo "   or: nc localhost 4444"
echo ""

# -no-reboot: shutdown/Ctrl+C triggers triple-fault to exit QEMU
qemu-system-i386 \
    -kernel examples/kernel/interactive \
    -display none \
    -no-reboot \
    -serial tcp:localhost:4444,server,nowait
