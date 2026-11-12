#pragma once
#include <array>
#include <deque>
#include <map>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>
#include <cstdint>

namespace godot_javafx {
class NativeWindowTransportStopped : public std::runtime_error {
public:
	NativeWindowTransportStopped() : std::runtime_error("Native window transport is stopped") {}
};
struct NativeWindowCommand {
	int operation = 0; // 1=create, 2=configure, 3=destroy, 4=property, 5=icon
	int64_t id = 0, owner = 0, sequence = 0;
	int x = 0, y = 0, width = 0, height = 0, flags = 0;
	bool visible = false;
	std::u16string title;
	std::vector<uint8_t> icon_pixels; // BGRA_PRE; width/height are zero to clear.
};
// Snapshots: id, owner, native ID, x, y, width, height, visible, focused, mode, ack.
using NativeWindowSnapshot = std::array<int64_t, 11>;
class NativeWindowTransport {
	std::mutex mutex;
	std::deque<NativeWindowCommand> commands;
	std::map<int64_t, int64_t> owners;
	int64_t last_identity = 0;
	std::map<int64_t, NativeWindowSnapshot> snapshots;
	int64_t next = 1, acknowledged = 0;
	bool stopped = false;
	static void erase_tree(std::map<int64_t,int64_t> &tree, int64_t id) {
		std::vector<int64_t> children;
		for (const auto &entry : tree) if (entry.second == id) children.push_back(entry.first);
		for (int64_t child : children) erase_tree(tree, child);
		tree.erase(id);
	}
public:
	int64_t submit(NativeWindowCommand command) {
		std::lock_guard<std::mutex> lock(mutex);
		if (stopped) throw NativeWindowTransportStopped();
		if (commands.size() >= 256 || next == INT64_MAX) throw std::runtime_error("Native window queue limit exceeded");
		if (command.id <= 0 || command.operation < 1 || command.operation > 5)
			throw std::invalid_argument("Invalid native window command");
		if (command.operation == 5) {
			const bool clear = command.width == 0 && command.height == 0 && command.icon_pixels.empty();
			if (!clear && (command.width < 1 || command.height < 1 || command.width > 256 || command.height > 256 ||
					command.icon_pixels.size() != size_t(command.width) * command.height * 4))
				throw std::invalid_argument("Invalid native window icon");
			size_t bytes = command.icon_pixels.size();
			for (const auto &queued : commands) bytes += queued.icon_pixels.size();
			if (bytes > 1024 * 1024) throw std::runtime_error("Native window icon queue limit exceeded");
		} else if (!command.icon_pixels.empty()) {
			throw std::invalid_argument("Unexpected native window icon payload");
		}
		if (command.operation <= 2 && (command.width <= 0 || command.height <= 0 || command.width > 8192 || command.height > 8192 ||
				command.x < -1000000 || command.x > 1000000 || command.y < -1000000 || command.y > 1000000))
			throw std::invalid_argument("Invalid native window bounds");
		if (command.operation == 4) {
			bool valid = false;
			switch (command.flags) {
				case 1: valid = command.title.size() <= 4096; break; // title
				case 4: valid = true; break; // request focus
				case 6: valid = command.x >= 0 && command.x <= 4; break; // Window::Mode
				case 7: case 9: case 15: case 16: case 19: case 20: valid = command.x == 0 || command.x == 1; break;
				case 17: valid = command.x >= -1000000 && command.x <= 1000000 && command.y >= -1000000 && command.y <= 1000000; break;
				case 18: case 22: case 23: valid = command.x == 0 && command.y == 0; break;
				case 12: case 13: valid = command.x >= 0 && command.y >= 0 && command.x <= 8192 && command.y <= 8192; break;
			}
			if (!valid) throw std::invalid_argument("Invalid native window property");
		}
		auto projected = owners;
		if (command.operation == 1) {
			if (command.id <= last_identity || owners.size() >= 64 || command.owner < -1 ||
					(command.owner > 0 && !owners.count(command.owner)) || command.flags < 0 || command.flags > 7 || command.title.size() > 4096)
				throw std::invalid_argument("Invalid native window identity, owner, flags or title");
			projected.emplace(command.id, command.owner);
		} else {
			if (!owners.count(command.id)) throw std::invalid_argument("Unknown or closed native window");
			if (command.operation == 3) erase_tree(projected,command.id);
		}
		command.sequence = next;
		commands.push_back(std::move(command));
		owners.swap(projected);
		if (commands.back().operation == 1) last_identity = commands.back().id;
		return next++;
	}
	bool take(NativeWindowCommand &command) {
		std::lock_guard<std::mutex> lock(mutex);
		if (commands.empty()) return false;
		command = std::move(commands.front()); commands.pop_front(); return true;
	}
	void publish(std::map<int64_t, NativeWindowSnapshot> values, int64_t sequence) {
		std::lock_guard<std::mutex> lock(mutex);
		snapshots.swap(values); acknowledged = sequence;
	}
	std::vector<int64_t> info(int64_t id) {
		std::lock_guard<std::mutex> lock(mutex);
		auto entry = snapshots.find(id);
		return entry == snapshots.end() ? std::vector<int64_t>() : std::vector<int64_t>(entry->second.begin(),entry->second.end());
	}
	int64_t ack() { std::lock_guard<std::mutex> lock(mutex); return acknowledged; }
	int64_t submitted() { std::lock_guard<std::mutex> lock(mutex); return next - 1; }
	void finish() { std::lock_guard<std::mutex> lock(mutex); stopped = true; }
	void stop() { std::lock_guard<std::mutex> lock(mutex); stopped = true; commands.clear(); }
};
}
