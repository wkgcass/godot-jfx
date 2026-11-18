"""Observe the native modules actually loaded by a Windows test process."""
import ctypes
from ctypes import wintypes
from pathlib import Path


def module_paths(process):
    # Read the actual Windows loader list. Java's -Xlog:library misses DLLs
    # loaded indirectly by Media plugins and the platform loader.
    library = ctypes.WinDLL("psapi")
    enum = library.EnumProcessModulesEx
    enum.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.HMODULE), wintypes.DWORD,
                     ctypes.POINTER(wintypes.DWORD), wintypes.DWORD]
    get_name = library.GetModuleFileNameExW
    get_name.argtypes = [wintypes.HANDLE, wintypes.HMODULE, wintypes.LPWSTR, wintypes.DWORD]
    modules = (wintypes.HMODULE * 2048)()
    size = wintypes.DWORD()
    if not enum(int(process._handle), modules, ctypes.sizeof(modules), ctypes.byref(size), 3):
        return set()
    paths = set()
    buffer = ctypes.create_unicode_buffer(32768)
    for handle in modules[:size.value // ctypes.sizeof(wintypes.HMODULE)]:
        if get_name(int(process._handle), handle, buffer, len(buffer)):
            paths.add(Path(buffer.value))
    return paths
