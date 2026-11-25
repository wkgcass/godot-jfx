#pragma once

#include <cstdint>
#include <cstdio>
#include <stdexcept>

namespace clipboard_snapshot {
constexpr uint64_t max_bytes = 256ULL * 1024 * 1024;

inline uint64_t add_bytes(uint64_t total, uint64_t size) {
	if (total > max_bytes || size == 0 || size > max_bytes - total) {
		throw std::invalid_argument("Clipboard snapshot exceeds 256 MiB total or contains an empty block; writes refused");
	}
	return total + size;
}

inline void require_unchanged(int64_t expected, int64_t actual) {
	if (expected < 0 || actual < 0 || expected != actual) {
		throw std::invalid_argument("Clipboard changed or change count unavailable; newer content preserved");
	}
}

inline void selftest() {
	if (add_bytes(0, 1) != 1 || add_bytes(max_bytes - 1, 1) != max_bytes) {
		throw std::runtime_error("Incorrect snapshot accounting");
	}
	const uint64_t sizes[][2] = {{0, 0}, {max_bytes, 1}, {max_bytes - 1, 2}, {UINT64_MAX, 1}, {0, UINT64_MAX}};
	for (const auto &pair : sizes) {
		try {
			add_bytes(pair[0], pair[1]);
		} catch (const std::invalid_argument &) {
			continue;
		}
		throw std::runtime_error("Invalid aggregate clipboard size accepted");
	}
	std::puts("CLIPBOARD_SNAPSHOT_BUDGET_PASS (no clipboard access)");
	require_unchanged(42, 42);
	const int64_t counts[][2] = {{42, 43}, {-1, -1}, {42, -1}, {-1, 42}};
	for (const auto &pair : counts) {
		try {
			require_unchanged(pair[0], pair[1]);
		} catch (const std::invalid_argument &) {
			continue;
		}
		throw std::runtime_error("Changed or unavailable clipboard sequence accepted");
	}
	std::puts("CLIPBOARD_SNAPSHOT_GUARD_PASS (no clipboard access)");
}
}
