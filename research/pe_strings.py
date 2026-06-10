#!/usr/bin/env python3
"""Reusable PE analysis helper for XML2 resolution/windowing RE.

Usage:
  py -3.13 pe_strings.py <file.exe|dll> strings [minlen]      # dump ASCII+UTF16 strings w/ file+VA offsets
  py -3.13 pe_strings.py <file> grep <regex> [-i]            # strings whose text matches regex (w/ offsets)
  py -3.13 pe_strings.py <file> xref <hexVA>                 # find code that references absolute address VA (push/mov imm)
  py -3.13 pe_strings.py <file> imports [substr]             # imported funcs (filter by substr)
  py -3.13 pe_strings.py <file> disasm <hexVA> [count]       # disassemble `count` insns at VA
  py -3.13 pe_strings.py <file> at <hexFileOff> [n]          # raw bytes at file offset

Notes: VA = ImageBase + RVA. Offsets printed as file=0x.. va=0x..
"""
import sys, re, pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

def load(path):
    pe = pefile.PE(path, fast_load=True)
    pe.parse_data_directories()
    return pe

def va_to_off(pe, va):
    rva = va - pe.OPTIONAL_HEADER.ImageBase
    return pe.get_offset_from_rva(rva)

def off_to_va(pe, off):
    rva = pe.get_rva_from_offset(off)
    return pe.OPTIONAL_HEADER.ImageBase + rva

def iter_strings(data, minlen=4):
    # ASCII
    for m in re.finditer(rb'[\x20-\x7e]{%d,}' % minlen, data):
        yield m.start(), 'A', m.group().decode('latin1')
    # UTF-16LE
    for m in re.finditer((rb'(?:[\x20-\x7e]\x00){%d,}' % minlen), data):
        yield m.start(), 'W', m.group().decode('utf-16le', 'ignore')

def cmd_strings(pe, data, args):
    minlen = int(args[0]) if args else 4
    for off, kind, s in iter_strings(data, minlen):
        try: va = off_to_va(pe, off)
        except Exception: va = 0
        print(f"file=0x{off:06x} va=0x{va:08x} {kind} {s}")

def cmd_grep(pe, data, args):
    flags = re.IGNORECASE if '-i' in args else 0
    pat = re.compile(args[0].encode() if isinstance(args[0], str) else args[0], 0)
    rx = re.compile(args[0], re.IGNORECASE if '-i' in args else 0)
    for off, kind, s in iter_strings(data, 3):
        if rx.search(s):
            try: va = off_to_va(pe, off)
            except Exception: va = 0
            print(f"file=0x{off:06x} va=0x{va:08x} {kind} {s}")

def cmd_xref(pe, data, args):
    target = int(args[0], 16)
    tb = target.to_bytes(4, 'little')
    # find every place the 4-byte little-endian absolute addr appears in any executable section
    for sec in pe.sections:
        if not (sec.Characteristics & 0x20000000):  # MEM_EXECUTE
            continue
        secdata = sec.get_data()
        base = sec.VirtualAddress + pe.OPTIONAL_HEADER.ImageBase
        start = 0
        while True:
            i = secdata.find(tb, start)
            if i < 0: break
            print(f"xref va=0x{base+i:08x} (file=0x{sec.PointerToRawData+i:06x})")
            start = i + 1

def cmd_imports(pe, data, args):
    sub = args[0].lower() if args else ''
    if not hasattr(pe, 'DIRECTORY_ENTRY_IMPORT'):
        print("no imports"); return
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        dll = entry.dll.decode()
        for imp in entry.imports:
            name = imp.name.decode() if imp.name else f"ord{imp.ordinal}"
            if sub in name.lower() or sub in dll.lower():
                print(f"{dll} -> {name} @ thunk 0x{imp.address:08x}")

def cmd_disasm(pe, data, args):
    va = int(args[0], 16); count = int(args[1]) if len(args) > 1 else 40
    off = va_to_off(pe, va)
    code = data[off:off+count*8]
    md = Cs(CS_ARCH_X86, CS_MODE_32)
    n = 0
    for ins in md.disasm(code, va):
        print(f"0x{ins.address:08x}: {ins.mnemonic:8s} {ins.op_str}")
        n += 1
        if n >= count: break

def cmd_at(pe, data, args):
    off = int(args[0], 16); n = int(args[1]) if len(args) > 1 else 64
    chunk = data[off:off+n]
    print(' '.join(f'{b:02x}' for b in chunk))
    print(repr(chunk))

def main():
    if len(sys.argv) < 3:
        print(__doc__); return
    path, cmd = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    pe = load(path)
    with open(path, 'rb') as f:
        data = f.read()
    {'strings':cmd_strings,'grep':cmd_grep,'xref':cmd_xref,'imports':cmd_imports,
     'disasm':cmd_disasm,'at':cmd_at}[cmd](pe, data, args)

if __name__ == '__main__':
    main()
