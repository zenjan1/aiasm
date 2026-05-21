OUTPUT_FORMAT("elf32-i386")
ENTRY(_start)
SECTIONS
{
    . = 0x00100000;

    .note.Xen : {
        KEEP(*(.note.Xen))
    }

    .multiboot : {
        KEEP(*(.multiboot))
    }

    .text : {
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
