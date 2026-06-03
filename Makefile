# AI-ASM v0.1 - Makefile
# 最小汇编语言工具链构建系统

BUILD=./bin/aiasm-build
TEST=./bin/aiasm-test

.PHONY: all test examples clean release install run-kernel run-interactive

all:
	@echo "AI-ASM v0.1 - Build all examples"
	@for f in examples/*.asm; do \
		if [ -f "$$f" ]; then \
			name=$${f%.asm}; \
			bn=$${name##*/}; \
			if [ "$$bn" = "minimal_kernel" ]; then \
				echo "Skipping $$f (use 'make run-kernel')"; \
				continue; \
			fi; \
			echo "Building $$f..."; \
			$(BUILD) -o "$$name" "$$f" || exit 1; \
		fi \
	done
	@echo "Done."

test: all
	@$(TEST) -v tests/

examples: all
	@echo "Running examples:"
	@for f in examples/hello examples/calculator; do \
		if [ -f "$$f" ]; then \
			echo "--- $$f ---"; \
			"./$$f"; \
		fi \
	done

run-kernel: examples/minimal_kernel
	@qemu-system-x86_64 -kernel examples/minimal_kernel -serial mon:stdio -display none -no-reboot

run-interactive: examples/kernel/interactive
	@qemu-system-i386 -kernel examples/kernel/interactive -serial mon:stdio -display none -no-reboot

examples/kernel/interactive: examples/kernel/kernel.asm examples/kernel/gdt.asm \
    examples/kernel/idt.asm examples/kernel/pic.asm examples/kernel/pit.asm \
    examples/kernel/vga.asm examples/kernel/keyboard.asm examples/kernel/shell.asm \
    examples/kernel/utils.asm examples/kernel/uart.asm examples/kernel/log.asm \
    examples/kernel/memory.asm examples/kernel/paging.asm examples/kernel/process.asm \
    examples/kernel/syscall.asm examples/kernel/vfs.asm \
    examples/kernel/wasm_parser.asm examples/kernel/wasm_vm.asm \
    examples/kernel/wasm_syscall.asm examples/kernel/virtio_net.asm \
    examples/kernel/ata.asm examples/kernel/fat32.asm examples/kernel/linker.ld
	@echo "Building interactive kernel..."
	as --32 -o /tmp/ikernel_kernel.o examples/kernel/kernel.asm
	as --32 -o /tmp/ikernel_gdt.o examples/kernel/gdt.asm
	as --32 -o /tmp/ikernel_idt.o examples/kernel/idt.asm
	as --32 -o /tmp/ikernel_pic.o examples/kernel/pic.asm
	as --32 -o /tmp/ikernel_pit.o examples/kernel/pit.asm
	as --32 -o /tmp/ikernel_vga.o examples/kernel/vga.asm
	as --32 -o /tmp/ikernel_keyboard.o examples/kernel/keyboard.asm
	as --32 -o /tmp/ikernel_shell.o examples/kernel/shell.asm
	as --32 -o /tmp/ikernel_utils.o examples/kernel/utils.asm
	as --32 -o /tmp/ikernel_uart.o examples/kernel/uart.asm
	as --32 -o /tmp/ikernel_log.o examples/kernel/log.asm
	as --32 -o /tmp/ikernel_memory.o examples/kernel/memory.asm
	as --32 -o /tmp/ikernel_paging.o examples/kernel/paging.asm
	as --32 -o /tmp/ikernel_process.o examples/kernel/process.asm
	as --32 -o /tmp/ikernel_syscall.o examples/kernel/syscall.asm
	as --32 -o /tmp/ikernel_vfs.o examples/kernel/vfs.asm
	as --32 -o /tmp/ikernel_wasm_parser.o examples/kernel/wasm_parser.asm
	as --32 -o /tmp/ikernel_wasm_vm.o examples/kernel/wasm_vm.asm
	as --32 -o /tmp/ikernel_wasm_syscall.o examples/kernel/wasm_syscall.asm
	as --32 -o /tmp/ikernel_virtio_net.o examples/kernel/virtio_net.asm
	as --32 -o /tmp/ikernel_ata.o examples/kernel/ata.asm
	as --32 -o /tmp/ikernel_fat32.o examples/kernel/fat32.asm
	ld -m elf_i386 -T examples/kernel/linker.ld -o examples/kernel/interactive \
		/tmp/ikernel_kernel.o /tmp/ikernel_gdt.o /tmp/ikernel_idt.o \
		/tmp/ikernel_pic.o /tmp/ikernel_pit.o /tmp/ikernel_vga.o \
		/tmp/ikernel_keyboard.o /tmp/ikernel_shell.o /tmp/ikernel_utils.o \
		/tmp/ikernel_uart.o /tmp/ikernel_log.o \
		/tmp/ikernel_memory.o /tmp/ikernel_paging.o \
		/tmp/ikernel_process.o /tmp/ikernel_syscall.o /tmp/ikernel_vfs.o \
		/tmp/ikernel_wasm_parser.o /tmp/ikernel_wasm_vm.o \
		/tmp/ikernel_wasm_syscall.o /tmp/ikernel_virtio_net.o /tmp/ikernel_ata.o \
		/tmp/ikernel_fat32.o
	rm -f /tmp/ikernel_*.o
	@echo "Interactive kernel ready: examples/kernel/interactive"

examples/minimal_kernel: examples/minimal_kernel.asm examples/kernel.ld
	@echo "Building minimal kernel..."
	as --32 -o /tmp/minimal_kernel.o examples/minimal_kernel.asm
	ld -m elf_i386 -T examples/kernel.ld -o examples/minimal_kernel /tmp/minimal_kernel.o
	rm -f /tmp/minimal_kernel.o
	@echo "Kernel ready: examples/minimal_kernel"

clean:
	@find examples -type f ! -name '*.asm' ! -name '*.expect' ! -name '*.ld' -delete
	@find tests -type f ! -name '*.asm' ! -name '*.expect' -delete
	@echo "Cleaned."

release: clean
	@cd .. && tar czf aiasm-v0.1.tar.gz aiasm-v0.1/
	@echo "Release package: ../aiasm-v0.1.tar.gz"

install:
	@cp -f bin/aiasm-build /usr/local/bin/aiasm-build
	@cp -f bin/aiasm-test /usr/local/bin/aiasm-test
	@cp -f bin/aiasm-new /usr/local/bin/aiasm-new
	@chmod +x /usr/local/bin/aiasm-build /usr/local/bin/aiasm-test /usr/local/bin/aiasm-new
	@echo "Installed to /usr/local/bin/"

# v1.00 - GRUB 可启动 ISO 生成
iso: examples/kernel/interactive
	mkdir -p iso/boot/grub
	cp examples/kernel/interactive iso/boot/kernel.bin
	echo "set timeout=5" > iso/boot/grub/grub.cfg
	echo "set default=0" >> iso/boot/grub/grub.cfg
	echo 'menuentry "AI-ASM Kernel v1.00" { multiboot /boot/kernel.bin; boot }' >> iso/boot/grub/grub.cfg
	grub-mkrescue -o aiasm-v1.00.iso iso/
	rm -rf iso/

iso-clean:
	rm -f *.iso
