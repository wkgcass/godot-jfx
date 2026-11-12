#include <windows.h>
#include <cassert>
#include <cstdio>

static HRESULT fake_create(REFCLSID, LPUNKNOWN, DWORD, REFIID, LPVOID *);
static HWND fake_desktop();
static HWND fake_find(LPCWSTR, LPCWSTR);
static BOOL fake_post(HWND, UINT, WPARAM, LPARAM);
static DWORD fake_error();
#define CoCreateInstance fake_create
#define GetDesktopWindow fake_desktop
#define FindWindowW fake_find
#define PostMessageW fake_post
#define GetLastError fake_error
#include "windows_tabtip.h"
#undef CoCreateInstance
#undef GetDesktopWindow
#undef FindWindowW
#undef PostMessageW
#undef GetLastError

using namespace godot_javafx::windows_tabtip;
static HRESULT creation = S_OK, toggle_result = S_OK;
static bool null_instance = false, visible = true, post_success = true;
static DWORD last_error = ERROR_ACCESS_DENIED;
static int toggles = 0, releases = 0, posts = 0;
static HWND fake_desktop() { return reinterpret_cast<HWND>(1); }
struct Tip final : ITipInvocation {
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID, void **out) override { *out = nullptr; return E_NOINTERFACE; }
    ULONG STDMETHODCALLTYPE AddRef() override { return 1; }
    ULONG STDMETHODCALLTYPE Release() override { ++releases; return 0; }
    HRESULT STDMETHODCALLTYPE Toggle(HWND hwnd) override {
        assert(hwnd == fake_desktop()); ++toggles; return toggle_result;
    }
};
static Tip instance;
static HRESULT fake_create(REFCLSID, LPUNKNOWN, DWORD, REFIID, LPVOID *out) {
    *out = SUCCEEDED(creation) && !null_instance ? &instance : nullptr;
    return creation;
}
static HWND fake_find(LPCWSTR, LPCWSTR) { return visible ? reinterpret_cast<HWND>(2) : nullptr; }
static BOOL fake_post(HWND hwnd, UINT message, WPARAM w, LPARAM l) {
    assert(hwnd == reinterpret_cast<HWND>(2) && message == WM_CLOSE && w == 0 && l == 0);
    ++posts; return post_success;
}
static DWORD fake_error() { return last_error; }
int main() {
    creation = REGDB_E_CLASSNOTREG;
    assert(request() == REGDB_E_CLASSNOTREG && toggles == 0 && releases == 0);
    creation = S_OK; null_instance = true;
    assert(request() == E_UNEXPECTED && releases == 0);
    null_instance = false; toggle_result = E_ACCESSDENIED;
    assert(request() == E_ACCESSDENIED && toggles == 1 && releases == 1);
    toggle_result = S_OK;
    assert(request() == S_OK && toggles == 2 && releases == 2);
    visible = false;
    assert(release() == S_FALSE && posts == 0);
    visible = true;
    assert(release() == S_OK && posts == 1);
    post_success = false;
    assert(release() == HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED) && posts == 2);
    last_error = 0;
    assert(FAILED(release()) && posts == 3);
    std::puts("TABTIP_RESULT_TEST_PASS");
}
