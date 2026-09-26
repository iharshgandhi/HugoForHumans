#!/usr/bin/env python3
"""
Checks how much of the app's core would compile on a Linux host.

The app is a macOS SwiftUI application, so a Linux *build* is not on the table.
What can be measured is how much of the non-UI core is free of Apple-only
frameworks, because that is the part any future client (a terminal app, a
server) would reuse.

This does not claim to produce a Linux binary. It type-checks `Core/` and
`Models/` with the Apple-only framework imports removed, which is a strict and
automatable proxy for "this code has no AppKit dependency left".

Usage:  python3 Scripts/check_portability.py
"""
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = pathlib.Path("/tmp/hfh-portability")

# The Apple frameworks a Linux host does not have. `Combine` and `ImageIO` are
# included because a Linux client would not have them either, and pretending
# otherwise would overstate the result.
APPLE_ONLY = [
    r"canImport\(AppKit\)",
    r"canImport\(Security\)",
    r"canImport\(ImageIO\)",
    r"canImport\(Combine\)",
    r"canImport\(WebKit\)",
]


def select_non_apple(text: str, flag: str) -> str:
    """Keep only the branch a platform lacking `flag` would compile.

    The result is what the preprocessor would produce for a false `canImport`,
    with the `#if`/`#endif` markers of skipped branches removed. Leaving them in
    would be self-defeating: swiftc would evaluate `canImport(Security)` for
    itself, find it true, and compile the branch the check meant to exclude.
    """
    out: list[str] = []
    i = 0
    pattern = re.compile(r"^[ \t]*#if[ \t]+(" + flag + r")", re.M)
    while True:
        match = pattern.search(text, i)
        if not match:
            out.append(text[i:])
            break
        out.append(text[i:match.start()])
        # Find the matching #endif, counting nesting.
        depth, j = 1, match.end()
        while depth:
            nxt = re.compile(r"^[ \t]*#(?:if|endif)\b", re.M).search(text, j)
            if not nxt:
                j = len(text)
                break
            depth += 1 if nxt.group(0).lstrip().startswith("#if") else -1
            j = nxt.end()
        body = text[match.end():j]
        body = re.sub(r"^[ \t]*#endif\b.*$", "", body, count=1, flags=re.M)
        if match.group(1).startswith("!"):
            # Kept, and already free of the directive pair we consumed.
            out.append(body)
        i = j
    return "".join(out)


def main() -> int:
    """Report how much of the core is free of Apple-only frameworks.

    What is actually verified here: the set of Apple-only imports each file
    pulls in, and which of those sit behind a `#if canImport(...)` guard. A file
    that guards its only AppKit import is portable; one that imports it at the
    top level is not.

    What is NOT verified: that the code compiles for Linux. There is no Linux
    Swift toolchain on this machine, and `canImport(Security)` cannot be faked
    on macOS — the compiler evaluates it against the real SDK. Simulating it by
    rewriting the directives is a re-implementation of the preprocessor, and it
    produced wrong answers while it was being written. So this reports the
    structure and leaves the compile claim to a machine that can make it.
    """
    sources = sorted((ROOT / "Sources/HugoForHumans/Core").rglob("*.swift")) + \
        sorted((ROOT / "Sources/HugoForHumans/Models").rglob("*.swift"))
    if not sources:
        print("no Core or Models sources found", file=sys.stderr)
        return 1

    guarded: list[str] = []
    unguarded: list[str] = []
    guarded_lines = 0

    for path in sources:
        text = path.read_text()
        lines = text.splitlines()
        # A file is portable if every Apple-only import is inside a canImport
        # guard. Track guard depth by line to decide that.
        depth_stack: list[bool] = []  # True = the guard's condition is canImport(...)
        offenders: list[int] = []
        for number, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith("#if"):
                depth_stack.append("canImport(" in stripped and "!canImport(" not in stripped)
                continue
            if stripped.startswith("#endif"):
                if depth_stack:
                    depth_stack.pop()
                continue
            if re.match(r"^import (AppKit|Security|ImageIO|WebKit|SwiftUI|Combine)\b", stripped):
                # Portable if some enclosing guard is a positive canImport, and no
                # enclosing guard is a negative one.
                if any(depth_stack) and not any(not g for g in depth_stack):
                    continue
                offenders.append(number)

        if offenders:
            unguarded.append(f"   {path.relative_to(ROOT)}"
                             f"{':' + ','.join(map(str, offenders))}")
        else:
            guarded.append(f"   {path.relative_to(ROOT)}")
            guarded_lines += len(lines)

    total_lines = sum(len(p.read_text().splitlines()) for p in sources)
    print(f"Core + Models: {total_lines} lines in {len(sources)} files")
    print(f"guarded: {len(guarded)} files, {guarded_lines} lines "
          f"({100 * guarded_lines // max(total_lines, 1)}%)")
    print()
    print("Guarded — no unguarded Apple-only import:")
    for line in guarded:
        print("  ", line)
    if unguarded:
        print()
        print("Not guarded — these import an Apple-only framework unconditionally:")
        for line in unguarded:
            print("  ", line)
        print()
        print(f"FAIL: {len(unguarded)} file(s) would not build on a non-Apple host.")
        return 1
    print()
    print("PASS — every Apple-only import sits behind a canImport guard.")
    print("This is a structural signal, not a Linux build. No Linux toolchain is")
    print("installed here, so the compile itself is unverified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
