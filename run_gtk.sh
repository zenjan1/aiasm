#!/bin/bash
# AI-ASM Kernel launcher - GTK window mode
# VGA display + PS/2 keyboard
# Serial output also goes to this terminal

cd /home/a/aiasm-v0.1
qemu-system-i386 -kernel examples/kernel/interactive -display gtk -serial mon:stdio -no-reboot
