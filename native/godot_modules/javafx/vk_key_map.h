#pragma once

#include "core/os/keyboard.h"

// JavaFX KeyCode values mirror Win32 virtual-key codes on every platform.
// KeyMappingWindows cannot be compiled on macOS (its header includes
// <windows.h>), so this table duplicates its vk_map entries to translate the
// codes Java sends for embedded-scene key input into Godot keys.
namespace godot_javafx {

inline Key vk_to_godot_key(unsigned int p_code) {
	switch (p_code) {
		case 0x08: return Key::BACKSPACE;
		case 0x09: return Key::TAB;
		case 0x0C: return Key::CLEAR;
		case 0x0D: return Key::ENTER;
		case 0x10: return Key::SHIFT;
		case 0x11: return Key::CTRL;
		case 0x12: return Key::ALT;
		case 0x13: return Key::PAUSE;
		case 0x14: return Key::CAPSLOCK;
		case 0x1B: return Key::ESCAPE;
		case 0x20: return Key::SPACE;
		case 0x21: return Key::PAGEUP;
		case 0x22: return Key::PAGEDOWN;
		case 0x23: return Key::END;
		case 0x24: return Key::HOME;
		case 0x25: return Key::LEFT;
		case 0x26: return Key::UP;
		case 0x27: return Key::RIGHT;
		case 0x28: return Key::DOWN;
		case 0x2A: return Key::PRINT;
		case 0x2C: return Key::PRINT;
		case 0x2D: return Key::INSERT;
		case 0x2E: return Key::KEY_DELETE;
		case 0x2F: return Key::HELP;
		case 0x30: return Key::KEY_0;
		case 0x31: return Key::KEY_1;
		case 0x32: return Key::KEY_2;
		case 0x33: return Key::KEY_3;
		case 0x34: return Key::KEY_4;
		case 0x35: return Key::KEY_5;
		case 0x36: return Key::KEY_6;
		case 0x37: return Key::KEY_7;
		case 0x38: return Key::KEY_8;
		case 0x39: return Key::KEY_9;
		case 0x41: return Key::A;
		case 0x42: return Key::B;
		case 0x43: return Key::C;
		case 0x44: return Key::D;
		case 0x45: return Key::E;
		case 0x46: return Key::F;
		case 0x47: return Key::G;
		case 0x48: return Key::H;
		case 0x49: return Key::I;
		case 0x4A: return Key::J;
		case 0x4B: return Key::K;
		case 0x4C: return Key::L;
		case 0x4D: return Key::M;
		case 0x4E: return Key::N;
		case 0x4F: return Key::O;
		case 0x50: return Key::P;
		case 0x51: return Key::Q;
		case 0x52: return Key::R;
		case 0x53: return Key::S;
		case 0x54: return Key::T;
		case 0x55: return Key::U;
		case 0x56: return Key::V;
		case 0x57: return Key::W;
		case 0x58: return Key::X;
		case 0x59: return Key::Y;
		case 0x5A: return Key::Z;
		case 0x5B: return Key::META;
		case 0x5C: return Key::META;
		case 0x5D: return Key::MENU;
		case 0x5F: return Key::STANDBY;
		case 0x60: return Key::KP_0;
		case 0x61: return Key::KP_1;
		case 0x62: return Key::KP_2;
		case 0x63: return Key::KP_3;
		case 0x64: return Key::KP_4;
		case 0x65: return Key::KP_5;
		case 0x66: return Key::KP_6;
		case 0x67: return Key::KP_7;
		case 0x68: return Key::KP_8;
		case 0x69: return Key::KP_9;
		case 0x6A: return Key::KP_MULTIPLY;
		case 0x6B: return Key::KP_ADD;
		case 0x6C: return Key::KP_PERIOD;
		case 0x6D: return Key::KP_SUBTRACT;
		case 0x6E: return Key::KP_PERIOD;
		case 0x6F: return Key::KP_DIVIDE;
		case 0x70: return Key::F1;
		case 0x71: return Key::F2;
		case 0x72: return Key::F3;
		case 0x73: return Key::F4;
		case 0x74: return Key::F5;
		case 0x75: return Key::F6;
		case 0x76: return Key::F7;
		case 0x77: return Key::F8;
		case 0x78: return Key::F9;
		case 0x79: return Key::F10;
		case 0x7A: return Key::F11;
		case 0x7B: return Key::F12;
		case 0x7C: return Key::F13;
		case 0x7D: return Key::F14;
		case 0x7E: return Key::F15;
		case 0x7F: return Key::F16;
		case 0x80: return Key::F17;
		case 0x81: return Key::F18;
		case 0x82: return Key::F19;
		case 0x83: return Key::F20;
		case 0x84: return Key::F21;
		case 0x85: return Key::F22;
		case 0x86: return Key::F23;
		case 0x87: return Key::F24;
		case 0x90: return Key::NUMLOCK;
		case 0x91: return Key::SCROLLLOCK;
		case 0x92: return Key::EQUAL;
		case 0xA0: return Key::SHIFT;
		case 0xA1: return Key::SHIFT;
		case 0xA2: return Key::CTRL;
		case 0xA3: return Key::CTRL;
		case 0xA4: return Key::MENU;
		case 0xA5: return Key::MENU;
		case 0xA6: return Key::BACK;
		case 0xA7: return Key::FORWARD;
		case 0xA8: return Key::REFRESH;
		case 0xA9: return Key::STOP;
		case 0xAA: return Key::SEARCH;
		case 0xAB: return Key::FAVORITES;
		case 0xAC: return Key::HOMEPAGE;
		case 0xAD: return Key::VOLUMEMUTE;
		case 0xAE: return Key::VOLUMEDOWN;
		case 0xAF: return Key::VOLUMEUP;
		case 0xB0: return Key::MEDIANEXT;
		case 0xB1: return Key::MEDIAPREVIOUS;
		case 0xB2: return Key::MEDIASTOP;
		case 0xB3: return Key::MEDIAPLAY;
		case 0xB4: return Key::LAUNCHMAIL;
		case 0xB5: return Key::LAUNCHMEDIA;
		case 0xB6: return Key::LAUNCH0;
		case 0xB7: return Key::LAUNCH1;
		case 0xBA: return Key::SEMICOLON;
		case 0xBB: return Key::EQUAL;
		case 0xBC: return Key::COMMA;
		case 0xBD: return Key::MINUS;
		case 0xBE: return Key::PERIOD;
		case 0xBF: return Key::SLASH;
		case 0xC0: return Key::QUOTELEFT;
		case 0xDB: return Key::BRACKETLEFT;
		case 0xDC: return Key::BACKSLASH;
		case 0xDD: return Key::BRACKETRIGHT;
		case 0xDE: return Key::APOSTROPHE;
		case 0xE2: return Key::BAR;
		case 0xE3: return Key::HELP;
		case 0xE6: return Key::CLEAR;
		case 0xF6: return Key::ESCAPE;
		case 0xF7: return Key::TAB;
		case 0xFA: return Key::MEDIAPLAY;
		case 0xFE: return Key::CLEAR;
		default: return Key::NONE;
	}
}

} // namespace godot_javafx
