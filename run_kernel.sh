#!/bin/bash
# AI-ASM Kernel launcher
# Try 1: nographic (serial terminal)
# If that doesn't work, try 2: GTK display (VGA + keyboard)

cd /home/a/aiasm-v0.1

echo "=== AI-ASM Kernel Launcher ==="
echo "Choose mode:"
echo "  1) Serial terminal (nographic) - type directly"
echo "  2) GTK window (VGA + PS/2 keyboard)"
read -p "Mode [1/2]: " mode

case "$mode" in
    1)
        echo "Starting QEMU in nographic mode..."
        echo "Press Ctrl-A then X to quit"
        echo "---"
        qemu-system-i386 -kernel examples/kernel/interactive -nographic -no-reboot
        ;;
    2)
        echo "Starting QEMU in GTK mode..."
        echo "Click the window to focus, then type."
        qemu-system-i386 -kernel examples/kernel/interactive -display gtk -serial mon:stdio -no-reboot
        ;;
    *)
        echo "Invalid mode"
        ;;
esac
