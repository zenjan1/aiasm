#!/usr/bin/env python3
"""Update shell.asm with wasmtest4001-4500."""

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
    return f'''    # "wasmtest{n}"
    mov     edi, offset cmd_wasmtest{n}
    call    utils_strcmp
    test    eax, eax
    jz      .do_wasmtest{n}
'''

def gen_handler(n, milestone=False):
    desc = f"{n} tests milestone - returns {n}" if milestone else f"returns {n}"
    return f'''# wasmtest{n}: {desc}
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
    return f'cmd_wasmtest{n}:\n    .asciz  "wasmtest{n}"\n'

def gen_msg_string(n, milestone=False):
    if milestone:
        return f'msg_wasm_test{n}:\n    .asciz  "wasmtest{n}: {n} tests milestone!\\n"\n'
    return f'msg_wasm_test{n}:\n    .asciz  "wasmtest{n}\\n"\n'

def gen_wasm_module(n, milestone=False):
    leb = leb128_encode(n)
    header = [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
              0x01, 0x04, 0x01, 0x60, 0x00, 0x7F,
              0x03, 0x02, 0x01, 0x00,
              0x07, 0x08, 0x01, 0x04, 0x6D, 0x61, 0x69, 0x6E, 0x00, 0x00]
    
    leb_bytes = len(leb)
    func_body_size = 2 + leb_bytes
    code_section_size = 1 + 1 + func_body_size
    header += [0x0A, code_section_size, 0x01, func_body_size, 0x00, 0x41]
    all_bytes = header + leb + [0x0B, 0x0B]
    
    desc = f"{n} tests milestone - returns {n}" if milestone else f"returns {n}"
    lines = [f'# wasmtest{n}: {desc}', f'wasm_test{n}_module:']
    
    for i in range(0, len(all_bytes), 12):
        chunk = all_bytes[i:i+12]
        hex_str = ', '.join(f'0x{b:02X}' for b in chunk)
        lines.append(f'    .byte   {hex_str}')
    
    lines.append(f'wasm_test{n}_size = . - wasm_test{n}_module')
    return '\n'.join(lines) + '\n'

# Read the original file
with open('/home/a/aiasm-v0.1/examples/kernel/shell.asm', 'r') as f:
    content = f.read()

# Update version
content = content.replace('# v1.68 - 4000 WASM tests milestone!', '# v1.69 - 4500 WASM tests milestone!')

# Generate all test code
parser_code = ""
handler_code = ""
cmd_strings = ""
msg_strings = ""
wasm_modules = ""

for n in range(4001, 4501):
    milestone = (n == 4500)
    parser_code += gen_cmd_parser(n)
    handler_code += gen_handler(n, milestone)
    cmd_strings += gen_cmd_string(n)
    msg_strings += gen_msg_string(n, milestone)
    wasm_modules += gen_wasm_module(n, milestone)

# Insert parser code after wasmtest4000 parser
parser_marker = '''    jz      .do_wasmtest4000



    # "wasmring3"'''
content = content.replace(parser_marker, f'''    jz      .do_wasmtest4000
{parser_code}
    # "wasmring3"''')

# Insert handler code after .do_wasmtest4000 handler
handler_marker = '''    ret


.do_wasmring3:'''
content = content.replace(handler_marker, f'''    ret
{handler_code}
.do_wasmring3:''')

# Insert cmd strings after cmd_wasmtest4000
cmd_marker = '''cmd_wasmtest4000:
    .asciz  "wasmtest4000"



    .asciz  "wasmtest2500"'''
content = content.replace(cmd_marker, f'''cmd_wasmtest4000:
    .asciz  "wasmtest4000"
{cmd_strings}
    .asciz  "wasmtest2500"''')

# Insert msg strings after msg_wasm_test4000
msg_marker = '''msg_wasm_test4000:
    .asciz  "wasmtest4000: 4000 tests milestone!\\n"


msg_wasm_milestone3500:'''
content = content.replace(msg_marker, f'''msg_wasm_test4000:
    .asciz  "wasmtest4000: 4000 tests milestone!\\n"
{msg_strings}
msg_wasm_milestone3500:''')

# Insert wasm modules after wasm_test4000_size
wasm_marker = '''wasm_test4000_size = . - wasm_test4000_module
'''
content = content.replace(wasm_marker, f'''wasm_test4000_size = . - wasm_test4000_module
{wasm_modules}''')

# Write the updated file
with open('/home/a/aiasm-v0.1/examples/kernel/shell.asm', 'w') as f:
    f.write(content)

print("shell.asm updated successfully!")
