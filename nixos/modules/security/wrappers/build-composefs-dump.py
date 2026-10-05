#!/usr/bin/env python3

import json
import os
import sys
from enum import Enum
from pathlib import Path
from typing import Any

from cap_to_xattr import capabilities_to_xattr
from mode_to_octal import mode_to_octal

Attrs = dict[str, Any]

# mkcomposefs hard-limits inline content to LCFS_INLINE_CONTENT_MAX (5000 bytes).
# We stay a bit below that. Files larger than this are served from the basedir
# data-only lower layer via an overlay redirect; files at or below it are
# embedded directly into the erofs metadata image, avoiding the redirect
# indirection at read time and keeping the basedir empty in the common case.
INLINE_CONTENT_MAX = 4096


class FileType(Enum):
    """The filetype as defined by the `st_mode` stat field in octal

    You can check the st_mode stat field of a path in Python with
    `oct(os.stat("/path/").st_mode)`
    """

    directory = "4"
    file = "10"
    symlink = "12"


class ComposefsPath:
    path: str
    size: int
    filetype: FileType
    mode: str
    uid: str
    gid: str
    payload: str
    rdev: str = "0"
    nlink: int = 1
    mtime: str = "1.0"
    content: str = "-"
    digest: str = "-"
    xattrs: dict[str, str]

    def __init__(
        self,
        attrs: Attrs,
        size: int,
        filetype: FileType,
        mode: str,
        payload: str,
        path: str | None = None,
        content: str = "-",
        xattrs: dict[str, str] | None = None,
    ):
        if xattrs is None:
            xattrs = {}
        if path is None:
            path = attrs["target"]
        self.path = path
        self.size = size
        self.filetype = filetype
        self.content = content
        self.xattrs = xattrs

        match len(mode):
            case 3 | 4:
                # We need to pad the mode, because we will later use the concatentation
                # filetype|mode, which assumes that the mode has a length of 4.
                self.mode = f"{mode:0>4}"
            case _:
                raise ValueError(f"mode should be 3 or 4 octal digits, got: {mode}")

        self.uid = attrs["uid"]
        self.gid = attrs["gid"]
        self.payload = payload

    def write_line(self) -> str:
        line_list = [
            str(self.path),
            str(self.size),
            f"{self.filetype.value}{self.mode}",
            str(self.nlink),
            str(self.uid),
            str(self.gid),
            str(self.rdev),
            str(self.mtime),
            str(self.payload),
            str(self.content),
            str(self.digest),
            *(f"{key.replace("=", "\\x3d")}={value}" for key, value in self.xattrs.items())
        ]
        return " ".join(line_list)


def eprint(*args: Any, **kwargs: Any) -> None:
    print(*args, **kwargs, file=sys.stderr)

def escape_bytes(data: bytes) -> str:
    return "".join(f"\\x{b:02x}" for b in data)


# Bytes that may appear unescaped in a composefs-dump field. Everything else
# is encoded as \xHH. See composefs-dump(5).
_DUMP_SHORT_ESCAPES: dict[int, str] = {
    ord("\\"): r"\\",
    ord("\n"): r"\n",
    ord("\r"): r"\r",
    ord("\t"): r"\t",
}


def escape_dump_field(data: bytes) -> str:
    """Escape raw bytes for use as a composefs-dump field.

    The dump format separates fields by a single space and lines by a single
    newline, uses '\\' as the escape character and reserves '-' for unset
    optional fields, so all of these (plus non-printable bytes and '=') must
    be escaped.
    """
    if data == b"":
        # An empty CONTENT field would be indistinguishable from two spaces
        # between PAYLOAD and DIGEST; callers must emit '-' for size-0 files
        # instead of inlining them.
        raise ValueError("cannot escape empty content; emit '-' instead")
    if data == b"-":
        # A bare '-' means "unset"; escape it so it round-trips as content.
        return r"\x2d"
    out: list[str] = []
    for b in data:
        if b in _DUMP_SHORT_ESCAPES:
            out.append(_DUMP_SHORT_ESCAPES[b])
        elif b in (ord(" "), ord("=")) or not (0x20 <= b <= 0x7E):
            out.append(f"\\x{b:02x}")
        else:
            out.append(chr(b))
    return "".join(out)


def normalize_path(path: str) -> str:
    return str("/" + os.path.normpath(path).lstrip("/"))


def leading_directories(path: str) -> list[str]:
    """Return the leading directories of path

    Given the path "alsa/conf.d/50-pipewire.conf", for example, this function
    returns `[ "alsa", "alsa/conf.d" ]`.
    """
    parents = list(Path(path).parents)
    parents.reverse()
    # remove the implicit `.` from the start of a relative path or `/` from an
    # absolute path
    del parents[0]
    return [str(i) for i in parents]


def add_leading_directories(
    target: str, attrs: Attrs, paths: dict[str, ComposefsPath]
) -> None:
    """Add the leading directories of a target path to the composefs paths

    mkcomposefs expects that all leading directories are explicitly listed in
    the dump file. Given the path "alsa/conf.d/50-pipewire.conf", for example,
    this function adds "alsa" and "alsa/conf.d" to the composefs paths.
    """
    path_components = leading_directories(target)
    for component in path_components:
        composefs_path = ComposefsPath(
            attrs,
            path=component,
            size=4096,
            filetype=FileType.directory,
            mode="0755",
            payload="-",
        )
        paths[component] = composefs_path

def main() -> None:
    """Build a composefs dump from a Json config

    This config describes the files that the final composefs image is supposed
    to contain.
    """
    config_file = sys.argv[1]
    if not config_file:
        eprint("No config file was supplied.")
        sys.exit(1)

    with open(config_file, "rb") as f:
        config = json.load(f)

    if not config:
        eprint("Config is empty.")
        sys.exit(1)

    eprint(config)

    eprint("Building composefs dump...")

    paths: dict[str, ComposefsPath] = {}
    for attrs in config.values():
        eprint(attrs)
        if not attrs["enable"]:
            continue

        target = normalize_path(attrs["program"])
        source = os.path.realpath(attrs["source"]) # wrapping of programs may mean we get a symlink here, which breaks metacopy with suid/sgid/caps
        attrs["source"] = source
        attrs["target"] = target

        # composefs expects numeric UIDs, but NixOS wrappers module have names
        # for root this is simple enough to fix, for non-root this is pain and
        # requires setting rigid UIDs for users/groups which have wrappers associated.
        attrs["gid"] = group if (group := attrs["group"]) != "root" else 0
        attrs["uid"] = owner if (owner := attrs["owner"]) != "root" else 0

        # apply/remove suid/sgid bits
        mode = mode_to_octal(attrs["permissions"])
        if attrs["setuid"]:
            mode |= 0o4000
        else:
            mode &= ~0o4000
        if attrs["setgid"]:
            mode |= 0o2000
        else:
            mode &= ~0o2000

        xattrs = { }
        if caps := attrs["capabilities"]:
            xattrs["security.capability"] = escape_bytes(capabilities_to_xattr(caps))

        if True:  # Without globbing
            if True: # source is not dir or symlink
                size = os.stat(source).st_size
                if True:
                    composefs_path = ComposefsPath(
                        attrs,
                        size=size,
                        filetype=FileType.file,
                        mode=f"{mode:04o}",
                        payload=source.removeprefix("/nix/store/"),
                        xattrs=xattrs,
                    )
            paths[target] = composefs_path

    composefs_dump = ["/ 4096 40755 1 0 0 0 0.0 - - -"]  # Root directory
    for key in sorted(paths):
        composefs_path = paths[key]
        eprint(composefs_path.path)
        composefs_dump.append(composefs_path.write_line())

    print("\n".join(composefs_dump))


if __name__ == "__main__":
    main()
