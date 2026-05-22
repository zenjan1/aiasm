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
        *(.bss)
        *(.bss.*)
        *(COMMON)
    }
}
