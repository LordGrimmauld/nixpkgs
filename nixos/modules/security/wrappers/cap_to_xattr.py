#!/usr/bin/env python3

import base64
import re
import struct

# from linux-headers.h
# `sed -nE 's/^#define[[:space:]]+(CAP_[A-Z0-9_]+)[[:space:]]+([0-9]+).*/    "\1": \2,/p' capability.h`
_VFS_CAP_REVISION_2 = 0x02000000
_VFS_CAP_FLAGS_EFFECTIVE = 0x000001
_CAPABILITIES = {
    "CAP_CHOWN": 0,
    "CAP_DAC_OVERRIDE": 1,
    "CAP_DAC_READ_SEARCH": 2,
    "CAP_FOWNER": 3,
    "CAP_FSETID": 4,
    "CAP_KILL": 5,
    "CAP_SETGID": 6,
    "CAP_SETUID": 7,
    "CAP_SETPCAP": 8,
    "CAP_LINUX_IMMUTABLE": 9,
    "CAP_NET_BIND_SERVICE": 10,
    "CAP_NET_BROADCAST": 11,
    "CAP_NET_ADMIN": 12,
    "CAP_NET_RAW": 13,
    "CAP_IPC_LOCK": 14,
    "CAP_IPC_OWNER": 15,
    "CAP_SYS_MODULE": 16,
    "CAP_SYS_RAWIO": 17,
    "CAP_SYS_CHROOT": 18,
    "CAP_SYS_PTRACE": 19,
    "CAP_SYS_PACCT": 20,
    "CAP_SYS_ADMIN": 21,
    "CAP_SYS_BOOT": 22,
    "CAP_SYS_NICE": 23,
    "CAP_SYS_RESOURCE": 24,
    "CAP_SYS_TIME": 25,
    "CAP_SYS_TTY_CONFIG": 26,
    "CAP_MKNOD": 27,
    "CAP_LEASE": 28,
    "CAP_AUDIT_WRITE": 29,
    "CAP_AUDIT_CONTROL": 30,
    "CAP_SETFCAP": 31,
    "CAP_MAC_OVERRIDE": 32,
    "CAP_MAC_ADMIN": 33,
    "CAP_SYSLOG": 34,
    "CAP_WAKE_ALARM": 35,
    "CAP_BLOCK_SUSPEND": 36,
    "CAP_AUDIT_READ": 37,
    "CAP_PERFMON": 38,
    "CAP_BPF": 39,
    "CAP_CHECKPOINT_RESTORE": 40,
}


def capabilities_to_xattr(spec: str) -> str:
    """
    Convert a setcap-style capability specification to the
    base64-encoded value of a revision-2 security.capability xattr.
    """

    assert "-" not in spec  # technically allowed by setcap, but pointless in wrapper setup
    # treating + and = and =+ identically - we are starting from an empty cap set.
    names, flags = re.split(r"=\+|=|\+", spec, maxsplit=1)
    assert re.match(r"[eip]+", flags) is not None  # only allow eip in flags

    permitted = 0
    inheritable = 0

    for name in names.split(","):
        # capability.h lists caps as upper case, so that is what our dict is.
        name = name.strip().upper()

        if not name.startswith("CAP_"):
            name = "CAP_" + name

        try:
            bit = _CAPABILITIES[name]
        except KeyError:
            raise ValueError(f"unknown capability: {name}")

        mask = 1 << bit

        if "e" in flags:
            pass  # effective is a global flag, handled below

        if "p" in flags:
            permitted |= mask

        if "i" in flags:
            inheritable |= mask

    # VFS_CAP_REVISION_2 | VFS_CAP_FLAGS_EFFECTIVE
    magic_etc = _VFS_CAP_REVISION_2
    if "e" in flags:
        magic_etc |= _VFS_CAP_FLAGS_EFFECTIVE

    raw = struct.pack(
        "<5I",
        magic_etc,
        permitted & 0xffffffff,
        inheritable & 0xffffffff,
        permitted >> 32,
        inheritable >> 32,
    )

    return raw


# https://github.com/search?q=repo%3ANixOS%2Fnixpkgs+security+wrappers+%22capabilities+%3D%22+lang%3Anix+path%3Anixos%2Fmodules&type=code
# `setcap '...' foo && getfattr -d -m - foo` to generate expoected strings
_TEST_SET = {
    "cap_net_raw+p": "0sAAAAAgAgAAAAAAAAAAAAAAAAAAA=",
    "cap_net_raw+ep": "0sAQAAAgAgAAAAAAAAAAAAAAAAAAA=",
    "cap_net_admin+ep": "0sAQAAAgAQAAAAAAAAAAAAAAAAAAA=",
    "cap_net_admin+p": "0sAAAAAgAQAAAAAAAAAAAAAAAAAAA=",
    "cap_ipc_lock=ep": "0sAQAAAgBAAAAAAAAAAAAAAAAAAAA=",
    "cap_net_admin,cap_net_raw+eip": "0sAQAAAgAwAAAAMAAAAAAAAAAAAAA=",
    "cap_net_raw,cap_net_admin=eip": "0sAQAAAgAwAAAAMAAAAAAAAAAAAAA=",
    "cap_net_bind_service,cap_net_raw,cap_net_admin=+ep": "0sAQAAAgA0AAAAAAAAAAAAAAAAAAA=",
    "cap_sys_nice+ep": "0sAQAAAgAAgAAAAAAAAAAAAAAAAAA=",
    "cap_sys_nice+eip": "0sAQAAAgAAgAAAAIAAAAAAAAAAAAA=",
    "cap_sys_admin+ep": "0sAQAAAgAAIAAAAAAAAAAAAAAAAAA=",
    "cap_sys_admin+p": "0sAAAAAgAAIAAAAAAAAAAAAAAAAAA=",
    "cap_setuid+ep": "0sAQAAAoAAAAAAAAAAAAAAAAAAAAA=",
    "cap_dac_override+p": "0sAAAAAgIAAAAAAAAAAAAAAAAAAAA=",
    "cap_sys_resource=+ep": "0sAQAAAgAAAAEAAAAAAAAAAAAAAAA=",
    "cap_sys_rawio=ep": "0sAQAAAgAAAgAAAAAAAAAAAAAAAAA=",
    "cap_perfmon+ep": "0sAQAAAgAAAAAAAAAAQAAAAAAAAAA=",
    "cap_dac_read_search+ep": "0sAQAAAgQAAAAAAAAAAAAAAAAAAAA=",
    "cap_dac_read_search,cap_sys_ptrace+ep": "0sAQAAAgQACAAAAAAAAAAAAAAAAAA=",
    "cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep": "0sAQAAAgQwCAAAAAAAAAAAAAAAAAA=",
    "cap_net_admin,cap_net_raw,cap_net_bind_service,cap_sys_ptrace,cap_dac_read_search+ep": "0sAQAAAgQ0CAAAAAAAAAAAAAAAAAA=",
    "cap_net_raw,cap_net_admin+eip": "0sAQAAAgAwAAAAMAAAAAAAAAAAAAA=",
    "cap_fowner+ep": "0sAQAAAggAAAAAAAAAAAAAAAAAAAA=",
    "cap_sys_nice+pie": "0sAQAAAgAAgAAAAIAAAAAAAAAAAAA=",
}

if __name__ == "__main__":
    for spec, expected in _TEST_SET.items():
        xattr = capabilities_to_xattr(spec)
        fattr_format = f"0s{base64.b64encode(xattr).decode("ascii")}"
        print(f"{spec}:\t{fattr_format}")
        assert fattr_format == expected
