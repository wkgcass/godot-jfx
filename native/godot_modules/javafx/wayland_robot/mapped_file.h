#pragma once
#include <stdexcept>
#include <sys/mman.h>
#include <unistd.h>

namespace godot_javafx::wayland_robot {
class MappedFile {
	int descriptor;
	size_t size;
	void *bytes;
public:
	explicit MappedFile(size_t length) : descriptor(memfd_create("godot-javafx-robot", MFD_CLOEXEC)), size(length), bytes(MAP_FAILED) {
		if (descriptor >= 0 && ftruncate(descriptor, size) == 0) {
			bytes = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
		}
		if (bytes == MAP_FAILED) {
			if (descriptor >= 0) ::close(descriptor);
			throw std::runtime_error("Cannot allocate Wayland Robot shared memory");
		}
	}
	~MappedFile() { munmap(bytes, size); ::close(descriptor); }
	MappedFile(const MappedFile &) = delete;
	MappedFile &operator=(const MappedFile &) = delete;
	int fd() const { return descriptor; }
	void *data() const { return bytes; }
};
}
