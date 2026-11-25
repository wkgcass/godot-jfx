#include <cstddef>
#include <cstdlib>
#include <new>

int allocations_before_failure = -1;
void *operator new(std::size_t size) {
	if (allocations_before_failure == 0) { allocations_before_failure = -1; throw std::bad_alloc(); }
	if (allocations_before_failure > 0) --allocations_before_failure;
	if (void *memory = std::malloc(size ? size : 1)) return memory;
	throw std::bad_alloc();
}
void operator delete(void *memory) noexcept { std::free(memory); }
void operator delete(void *memory, std::size_t) noexcept { std::free(memory); }
