#pragma once

#include <cstddef>
#include <string>

// One convention shared by the system clipboard adapter and the drag
// endpoints: a Java MIME "application/x-godot-custom-<suffix>" maps to a
// same-named pasteboard type carrying a single NUL-terminated byte payload,
// so external processes can exchange it without any private structure. The
// suffix stays lowercase [a-z0-9._-] so the MIME<->type mapping is
// unambiguous. NSPasteboard types need no registration, so there is no
// format_for() counterpart here.
//
// Drag sessions publish through NSPasteboardItem, which (macOS 26) rejects
// type strings that are not valid UTIs. Drag endpoints therefore use the UTI
// twin of the MIME name: the prefix's sole '/' becomes '.'. The suffix
// charset contains no '/', so the mapping stays bijective. The general
// pasteboard accepts the raw MIME name, so the system clipboard keeps it.
namespace godot_javafx::custom_format {
constexpr char PREFIX[] = "application/x-godot-custom-";
constexpr size_t PREFIX_LENGTH = sizeof(PREFIX) - 1;
constexpr char UTI_PREFIX[] = "application.x-godot-custom-";
constexpr size_t UTI_PREFIX_LENGTH = sizeof(UTI_PREFIX) - 1;
constexpr size_t MAX_NAME_CHARS = 128;
constexpr size_t MAX_FORMATS = 32;
constexpr size_t MAX_DATA_BYTES = 16 * 1024 * 1024;

inline bool valid_name(const std::u16string &name) {
	if (name.size() <= PREFIX_LENGTH || name.size() > MAX_NAME_CHARS) return false;
	for (size_t i = 0; i < PREFIX_LENGTH; ++i)
		if (name[i] != static_cast<char16_t>(PREFIX[i])) return false;
	for (size_t i = PREFIX_LENGTH; i < name.size(); ++i) {
		const char16_t c = name[i];
		const bool ok = (c >= u'a' && c <= u'z') || (c >= u'0' && c <= u'9') || c == u'-' || c == u'.' || c == u'_';
		if (!ok) return false;
	}
	return true;
}

// Position of the '/' in PREFIX resp. '.' in UTI_PREFIX ("application/...").
constexpr size_t SLASH_INDEX = 11;

// MIME name -> UTI pasteboard type ("application/x-..." -> "application.x-...").
inline std::u16string uti_type(const std::u16string &name) {
	std::u16string type = name;
	type[SLASH_INDEX] = u'.';
	return type;
}

// UTI pasteboard type -> MIME name; false when the type is outside the
// convention (the caller skips it, like any other foreign drag type).
inline bool name_from_uti_type(const std::u16string &type, std::u16string &name) {
	if (type.size() <= UTI_PREFIX_LENGTH || type.size() > MAX_NAME_CHARS) return false;
	for (size_t i = 0; i < UTI_PREFIX_LENGTH; ++i)
		if (type[i] != static_cast<char16_t>(UTI_PREFIX[i])) return false;
	name = type;
	name[SLASH_INDEX] = u'/';
	return valid_name(name);
}
}
