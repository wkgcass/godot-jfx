#pragma once

#include <windows.h>

// Windows touch keyboard (TabTip.exe) behind Glass _requestInput/_releaseInput.
// This adapter uses the shell's ITipInvocation toggle for requests and posts
// WM_CLOSE to the keyboard window for release; Toggle is not an idempotent show.
// Report native failures to the host without turning an optional OS facility
// into a JVM failure. Successful calls do not prove that a keyboard is visible.
namespace godot_javafx::windows_tabtip {

struct ITipInvocation : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE Toggle(HWND hwnd) = 0;
};

// {37C994E7-432B-4834-A2F7-DCE1F13B834B}
constexpr GUID IID_ITIP_INVOCATION = { 0x37C994E7, 0x432B, 0x4834, { 0xA2, 0xF7, 0xDC, 0xE1, 0xF1, 0x3B, 0x83, 0x4B } };
// {4CE576FA-83DC-4F88-951C-9D0782B4E376}
constexpr GUID CLSID_UI_HOST_NO_LAUNCH = { 0x4CE576FA, 0x83DC, 0x4F88, { 0x95, 0x1C, 0x9D, 0x07, 0x82, 0xB4, 0xE3, 0x76 } };

inline HRESULT request() {
    ITipInvocation *tip = nullptr;
    const HRESULT result = CoCreateInstance(CLSID_UI_HOST_NO_LAUNCH, nullptr, CLSCTX_INPROC_HANDLER | CLSCTX_LOCAL_SERVER,
            IID_ITIP_INVOCATION, reinterpret_cast<void **>(&tip));
    if (FAILED(result)) return result;
    if (!tip) return E_UNEXPECTED;
    const HRESULT toggled = tip->Toggle(GetDesktopWindow());
    tip->Release();
    return toggled;
}

inline HRESULT release() {
    HWND tip = FindWindowW(L"IPTip_Main_Window", nullptr);
    if (!tip) return S_FALSE; // No window to close is already the desired state.
    if (PostMessageW(tip, WM_CLOSE, 0, 0)) return S_OK;
    const DWORD error = GetLastError();
    return HRESULT_FROM_WIN32(error ? error : ERROR_GEN_FAILURE);
}
}
