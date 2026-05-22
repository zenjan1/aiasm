OUTPUT_FORMAT("elf32-i386")
ENTRY(_start)
SECTIONS
{
    . = 0x00100000;

    /* Multiboot header must be within first 8KB of file */
    .note.Xen : {
        KEEP(*(.note.Xen))
    }
    .multiboot : {
        KEEP(*(.multiboot))
    }

    .text : {
        *(.multiboot)
        *(.text)
        *(.text.*)
    }

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }

    .data : {
        *(.data)
        *(.data.*)
    }

    .bss : {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end = .;
        __bss_size = __bss_end - __bss_start;
    }
}
