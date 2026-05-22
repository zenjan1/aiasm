#!/bin/bash
# AI-ASM Kernel launcher - TCP serial with proper terminal
cd /home/a/aiasm-v0.1

PORT=4444

# Kill any existing QEMU
pkill -9 -f 'qemu-system.*interactive' 2>/dev/null
sleep 1

# Start QEMU with serial on TCP port
# -no-reboot: shutdown/Ctrl+C triggers triple-fault to exit QEMU
qemu-system-i386 \
    -kernel examples/kernel/interactive \
    -display none \
    -no-reboot \
    -serial "tcp:localhost:$PORT,server,nowait" \
    2>/dev/null &
QEMU_PID=$!

sleep 2
echo "=== AI-ASM Kernel ==="
echo "Type commands at the aiasm> prompt"
echo "Ctrl-C to quit"
echo "==================="

# Python serial terminal
python3 -u << PYEOF
import socket, tty, termios, sys, os, select

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', $PORT))
s.setblocking(True)

fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
tty.setraw(fd)

try:
    # Read boot message with timeout
    s.settimeout(3)
    try:
        data = s.recv(4096)
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
    except socket.timeout:
        pass
    s.setblocking(False)

    while True:
        r, _, _ = select.select([sys.stdin, s], [], [], 0.1)
        if sys.stdin in r:
            ch = os.read(fd, 1)
            if ch:
                s.send(ch)
        if s in r:
            try:
                data = s.recv(4096)
                if data:
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
                else:
                    break
            except BlockingIOError:
                continue
except KeyboardInterrupt:
    pass
finally:
    termios.tcsetattr(fd, termios.TCSANOW, old)
    s.close()
PYEOF

echo ""
echo "Exiting..."
kill $QEMU_PID 2>/dev/null
wait $QEMU_PID 2>/dev/null
echo "Done."
