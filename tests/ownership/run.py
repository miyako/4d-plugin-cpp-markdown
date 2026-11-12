#!/usr/bin/env python3
"""Compile actual plugin sources without invoking either release project."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
here = Path(__file__).resolve().parent
sources = [
    "4D Plugin API/4DPluginAPI.c",
    "4D Plugin API/Classes/C_TEXT.cpp",
    "4D Plugin API/Classes/ARRAY_TEXT.cpp",
    "4D Plugin API/Classes/C_BLOB.cpp",
    "4D Plugin API/Classes/C_LONGINT.cpp",
    "support/4DPlugin-JSON.cpp",
    "4DPlugin-CPP-Markdown.cpp",
    "include/markdown.cpp",
    "include/markdown-tokens.cpp",
]
for name in sources:
    print(hashlib.sha256((root / name).read_bytes()).hexdigest(), name, flush=True)
print(hashlib.sha256((root / "a/libboost_regex.a").read_bytes()).hexdigest(),
      "bundled Boost.Regex dependency", flush=True)
if hashlib.sha256((root / "a/libboost_regex.a").read_bytes()).hexdigest() != (
        "5a7f1035febc9361af788834d081e749b0eadd86edc36d7b00f61dea5cc2ad5c"):
    raise RuntimeError("Bundled Boost.Regex dependency identity changed")
for name in ["4DPluginAPI.h", "PrivateTypes.h", "PublicTypes.h", "EntryPoints.h", "Flags.h"]:
    print(hashlib.sha256((root / "4D Plugin API" / name).read_bytes()).hexdigest(),
          name, flush=True)

with tempfile.TemporaryDirectory(prefix="cpp-markdown-ownership-") as directory:
    out = Path(directory)
    flags = [
        "-g", "-O1", "-fsanitize=address,undefined", "-fno-sanitize=alignment",
        "-fno-omit-frame-pointer", "-Wno-deprecated-declarations", "-Wno-multichar",
        "-Wno-deprecated-builtins",
        "-I" + str(root / "4D Plugin API"),
        "-I" + str(root / "4D Plugin API/Classes"),
        "-I" + str(root / "support"), "-I" + str(root / "include"),
    ]
    objects = []
    for i, name in enumerate(sources + [str(here / "main.mm")]):
        source = root / name
        obj = out / (str(i) + ".o")
        language = ["-x", "c", "-Wno-int-conversion"] if source.suffix == ".c" else [
            "-x", "objective-c++", "-std=c++14"
        ]
        subprocess.run(["clang++", *flags, *language, "-c", str(source), "-o", str(obj)],
                       check=True)
        objects.append(str(obj))
    exe = out / "ownership"
    subprocess.run(["clang++", *flags, *objects, str(root / "a/libboost_regex.a"),
                    "-framework", "Cocoa", "-framework", "CoreFoundation",
                    "-framework", "CoreGraphics", "-o", str(exe)], check=True)
    # Gate linked imports before any plugin code can execute. No project build,
    # dynamic loading, sockets, file APIs, subprocesses or host APIs are allowed.
    imports = subprocess.check_output(["nm", "-u", str(exe)], text=True)
    allowed = (
        "___", "__Z", "_OBJC_CLASS_$_", "_objc_",
    )
    exact = {
        "_abort", "_calloc", "_free", "_malloc", "_realloc", "_memcmp", "_memcpy",
        "_memmove", "_memset", "_strlen", "_strchr", "_strcmp", "_strncmp",
        "_strcpy", "_strerror", "_strtol", "_strtoul", "_strtod", "_strcoll",
        "_strxfrm", "_wcslen", "_wcsrtombs", "_wcrtomb", "_mbrtowc", "_mbsrtowcs",
        "_isalpha", "_isalnum", "_isspace", "_tolower", "_toupper", "_towlower",
        "_towupper", "_iswctype", "_wctype", "_setlocale", "_uselocale",
        "_newlocale", "_freelocale", "_localeconv", "_sprintf", "_snprintf",
        "_vsnprintf", "_fprintf", "_fwrite", "_fputs", "_puts", "_printf",
        "_fputc", "_fflush", "_exit", "_atexit", "_bzero",
        "dyld_stub_binder",
        "__DefaultRuneLocale",
        "__Unwind_Resume", "__tlv_bootstrap", "_memchr", "_pthread_mutex_lock",
        "_pthread_mutex_unlock", "_kCFAllocatorDefault", "_CFRelease",
        "_CFStringCreateWithBytes", "_CFStringCreateWithCharacters", "_CFStringGetLength",
        "_CFStringGetCharacters", "_CFStringGetMaximumSizeForEncoding", "_CFStringGetBytes",
    }
    symbols = [line.strip() for line in imports.splitlines() if line.strip()]
    denied = ("basic_filebuf", "basic_ifstream", "basic_ofstream", "basic_fstream",
              "filesystem", "random_device")
    if any(part in symbol for symbol in symbols for part in denied):
        raise RuntimeError("Forbidden external-data C++ import")
    unexpected = [s for s in symbols if s not in exact and not s.startswith(allowed)]
    if unexpected:
        raise RuntimeError("Unexpected imports: " + repr(unexpected))
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0",
               UBSAN_OPTIONS="halt_on_error=1")
    subprocess.run([str(exe)], check=True, env=env)
