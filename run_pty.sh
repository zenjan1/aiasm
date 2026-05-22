#!/bin/bash
# AI-ASM Kernel launcher - PTY serial mode
# Creates a pseudo-terminal, connects your terminal to it

cd /home/a/aiasm-v0.1

echo "Starting QEMU with PTY serial..."

# Use a FIFO for bidirectional communication
FIFO=/tmp/qemu-fifo
rm -f "$FIFO"
mkfifo "$FIFO"

# Start QEMU reading from FIFO, writing to terminal
# -no-reboot: shutdown/Ctrl+C triggers triple-fault to exit QEMU
qemu-system-i386 \
    -kernel examples/kernel/interactive \
    -display none \
    -no-reboot \
    -serial "file:/dev/stdout" &

QEMU_PID=$!
sleep 1

# Forward terminal input to FIFO
while true; do
    read -r line
    echo "$line" > "$FIFO"
done &

READER_PID=$!

wait $QEMU_PID
kill $READER_PID 2>/dev/null
rm -f "$FIFO"
