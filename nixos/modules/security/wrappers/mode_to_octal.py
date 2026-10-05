#! /usr/bin/env python3

import re

SYMBOLIC_RE = re.compile(r"([ugoa]*)([-+=]([rwxXst]*|[ugo]))+")
NUMERIC_RE = re.compile(r"([-+=]?)([0-7]+)")
OP_REGEX = re.compile(r"([-+=])([rwxXst]*|[ugo])")

SHIFT_TABLE = {
    "u": 6,
    "g": 3,
    "o": 0,
}

BIT_X = 0o1
BIT_W = 0o2
BIT_R = 0o4
BIT_STICKY = 0o1000
BIT_SGID = 0o2000
BIT_SUID = 0o4000

PERM_TABLE = {
    "r": BIT_R,
    "w": BIT_W,
    "x": BIT_X,
}


def mode_to_octal(mode: str, initial: int = 0o0) -> int:
    # u+rx,g+x,o+x
    octal = initial
    for part in mode.split(","):
        if match := NUMERIC_RE.fullmatch(part):
            op, value = match.groups()
            bits = int(value, 8)
            if op == "+":
                octal |= bits
            elif op == "-":
                octal &= ~bits
            else:
                octal = bits
            continue
        match = SYMBOLIC_RE.fullmatch(part)
        # from man(1) chmod
        assert match is not None, f"invalid mode: {part!r}"
        who = match.group(1) or "a"
        # a -> all, but replace that so we don't have to match it later
        who = "ugo" if "a" in who else who
        operations = part[len(match.group(1)):]
        for op, perms in OP_REGEX.findall(operations):
            for target in who:
                shift = SHIFT_TABLE[target]
                mask = 0o7 << shift
                bits = 0
                for perm in perms:
                    if perm in "rwx":
                        bits |= PERM_TABLE[perm] << shift
                    elif perm == "X":
                        if octal & 0o111:
                            bits |= BIT_X << shift
                    elif perm == "s":
                        if target == "u":
                            bits |= BIT_SUID
                        elif target == "g":
                            bits |= BIT_SGID
                    if perm == "t":
                        bits |= BIT_STICKY
                    if perm in "ugo":
                        source_shift = SHIFT_TABLE[perm]
                        bits |= ((octal >> source_shift) & 0o7) << shift
                if op == "+":
                    octal |= bits
                elif op == "-":
                    octal &= ~bits
                elif op == "=":
                    # only the appropriate shift for our target gets nulled and rewritten
                    octal = (octal & ~mask) | bits
                    if "s" in perms:
                        octal &= ~(BIT_SUID | BIT_SGID)
                        octal |= bits & (BIT_SUID | BIT_SGID)
                    if "t" in perms:
                        octal &= ~BIT_STICKY
                        octal |= bits & BIT_STICKY
    return octal
