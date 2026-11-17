#pragma once

// macOS has no programmatic touch-keyboard facility behind Glass
// _requestInput/_releaseInput. Return false so the host logs an explicit
// unsupported warning instead of silently ignoring the request.
namespace godot_javafx::macos_tabtip {
inline bool request() { return false; }
inline bool release() { return false; }
}
