#!/usr/bin/env python3
"""Generate wasmtest4001-4500 assembly code."""

def leb128_encode(value):
    """Encode value as LEB128."""
    result = []
    while True:
        byte = value & 0x7F
        value >>= 7
        if value != 0:
            byte |= 0x80
        result.append(byte)
        if value == 0:
            break
    return result

def gen_cmd_parser(n):
    """Generate command parser code."""
    return f'''
    # "wasmtest{n}"
    mov     edi, offset cmd_wasmtest{n}
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest{n}
'''

def gen_handler(n, milestone=False):
    """Generate handler code."""
    if milestone:
        return f'''# wasmtest{n}: {n} tests milestone - returns {n}
.do_wasmtest{n}:
    push    esi
    push    edi
    push    ecx
    mov     esi, offset msg_wasm_test{n}
    call    uart_puts
    mov     esi, offset wasm_test{n}_module
    mov     ecx, offset wasm_test{n}_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_wasm_result
    call    uart_puts
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    pop     eax
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

'''
    else:
        return f'''# wasmtest{n}: returns {n}
.do_wasmtest{n}:
    push    esi
    push    edi
    push    ecx
    mov     esi, offset msg_wasm_test{n}
    call    uart_puts
    mov     esi, offset wasm_test{n}_module
    mov     ecx, offset wasm_test{n}_size
    call    wasm_parse_module
    test    eax, eax
    jnz     .wasm_parse_err
    call    wasm_load_data
    mov     dword ptr [wasm_stack_top], 0
    mov     dword ptr [wasm_control_top], 0
    mov     dword ptr [wasm_call_top], 0
    xor     eax, eax
    call    wasm_exec_func
    mov     esi, offset msg_wasm_result
    call    uart_puts
    push    eax
    mov     edi, offset shell_cmd_buf
    mov     dl, 10
    call    utils_itoa
    mov     esi, eax
    call    uart_puts
    pop     eax
    mov     al, 0x0a
    call    uart_putc
    mov     al, 0x0d
    call    uart_putc
    pop     ecx
    pop     edi
    pop     esi
    ret

'''

def gen_cmd_string(n):
    """Generate command string."""
    return f'cmd_wasmtest{n}:\n    .asciz  "wasmtest{n}"\n'

def gen_msg_string(n, milestone=False):
    """Generate message string."""
    if milestone:
        return f'msg_wasm_test{n}:\n    .asciz  "wasmtest{n}: {n} tests milestone!\\n"\n'
    else:
        return f'msg_wasm_test{n}:\n    .asciz  "wasmtest{n}\\n"\n'

def gen_wasm_module(n, milestone=False):
    """Generate WASM module bytes."""
    leb = leb128_encode(n)
    # WASM module structure:
    # 0x00 0x61 0x73 0x6D - magic number
    # 0x01 0x00 0x00 0x00 - version
    # 0x01 0x04 0x01 0x60 0x00 0x7F - type section (function with no params, returns i32)
    # 0x03 0x02 0x01 0x00 - function section (one function, type 0)
    # 0x07 0x08 0x01 0x04 0x6D 0x61 0x69 0x6E 0x00 0x00 - export section (export "main" as function 0)
    # 0x0A - code section
    # <size> - section size
    # 0x01 - one function
    # <func_size> - function body size
    # 0x00 - local count
    # 0x41 - i32.const
    # <leb128 value> - the value
    # 0x0B - end
    # 0x0B - end (extra?)
    
    # Calculate sizes
    leb_bytes = len(leb)
    func_body_size = 2 + leb_bytes  # 0x00 + 0x41 + leb + 0x0B
    code_section_size = 1 + 1 + func_body_size  # func count + func body size byte + body
    
    result = []
    if milestone:
        result.append(f'# wasmtest{n}: {n} tests milestone - returns {n}')
    else:
        result.append(f'# wasmtest{n}: returns {n}')
    result.append(f'wasm_test{n}_module:')
    
    # Fixed header
    header = [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
              0x01, 0x04, 0x01, 0x60, 0x00, 0x7F,
              0x03, 0x02, 0x01, 0x00,
              0x07, 0x08, 0x01, 0x04, 0x6D, 0x61, 0x69, 0x6E, 0x00, 0x00,
              0x0A, code_section_size, 0x01, func_body_size, 0x00, 0x41]
    
    # Format bytes
    all_bytes = header + leb + [0x0B, 0x0B]
    
    # Split into lines of 12 bytes
    for i in range(0, len(all_bytes), 12):
        chunk = all_bytes[i:i+12]
        hex_str = ', '.join(f'0x{b:02X}' for b in chunk)
        result.append(f'    .byte   {hex_str}')
    
    result.append(f'wasm_test{n}_size = . - wasm_test{n}_module')
    return '\n'.join(result) + '\n'

# Generate all code
print("#!/bin/bash")
print("# Generated test code for wasmtest4001-4500")

print("\n# === Command Parser Section ===")
for n in range(4001, 4501):
    print(gen_cmd_parser(n))

print("\n# === Handler Section ===")
for n in range(4001, 4501):
    milestone = (n == 4500)
    print(gen_handler(n, milestone))

print("\n# === Command String Section ===")
for n in range(4001, 4501):
    print(gen_cmd_string(n))

print("\n# === Message String Section ===")
for n in range(4001, 4501):
    milestone = (n == 4500)
    print(gen_msg_string(n, milestone))

print("\n# === WASM Module Section ===")
for n in range(4001, 4501):
    milestone = (n == 4500)
    print(gen_wasm_module(n, milestone))
