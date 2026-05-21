# AI-ASM v0.1 - Makefile
# 最小汇编语言工具链构建系统

BUILD=./bin/aiasm-build
TEST=./bin/aiasm-test

.PHONY: all test examples clean release install run-kernel

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
	@qemu-system-x86_64 -kernel examples/minimal_kernel -serial mon:stdio -display none

examples/minimal_kernel: examples/minimal_kernel.asm examples/kernel.ld
	@echo "Building minimal kernel..."
	as --32 -o /tmp/minimal_kernel.o examples/minimal_kernel.asm
	ld -m elf_i386 -T examples/kernel.ld -o examples/minimal_kernel /tmp/minimal_kernel.o
	rm -f /tmp/minimal_kernel.o
	@echo "Kernel ready: examples/minimal_kernel"

clean:
	@find examples -type f ! -name '*.asm' ! -name '*.expect' -delete
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
