#!/bin/bash
# AI-ASM Kernel launcher - Unix socket serial mode
# Connect to the serial port using socat or netcat

cd /home/a/aiasm-v0.1
SOCKET=/tmp/qemu-serial.sock

# Clean up old socket
rm -f "$SOCKET"

echo "Starting QEMU with serial on Unix socket..."
echo "Connecting..."

# Start QEMU with serial on Unix socket
qemu-system-i386 \
    -kernel examples/kernel/interactive \
    -display none \
    -no-reboot \
    -serial "unix:$SOCKET,server,nowait" &

QEMU_PID=$!
sleep 1

# Connect with socat if available
if command -v socat &>/dev/null; then
    echo "Connected via socat. Type commands at aiasm> prompt."
    echo "Ctrl-C to quit."
    socat "$SOCKET" -
else
    echo "socat not found. Install it: sudo apt install socat"
    echo "Then run: socat /tmp/qemu-serial.sock -"
    echo "QEMU PID: $QEMU_PID"
fi

kill $QEMU_PID 2>/dev/null
rm -f "$SOCKET"
