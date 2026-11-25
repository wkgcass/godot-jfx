#include "bounded_lru_cache.h"
#include <cstdlib>
#include <iostream>
#include <limits>
#include <memory>
#include <new>
#include <stdexcept>
#include <type_traits>

extern int allocations_before_failure;
struct CollisionHash { size_t operator()(int) const { return 0; } };
using Cache = godot_javafx::BoundedLruCache<int, std::shared_ptr<int>, CollisionHash>;
static void require(bool value, const char *message) { if (!value) throw std::runtime_error(message); }
static auto match(int value) { return [value](const std::shared_ptr<int> &entry) { return *entry == value; }; }
int main() {
	static_assert(!std::is_copy_constructible_v<Cache>);
	Cache cache(10, 2);
	cache.put(1, std::make_shared<int>(1), 4);
	auto resource = std::make_shared<int>(2);
	std::weak_ptr<int> retired = resource;
	cache.put(2, resource, 4); resource.reset();
	require(cache.get(1, match(1)), "Hash bucket collision lost entry");
	cache.put(3, std::make_shared<int>(3), 4);
	require(!cache.get(2, match(2)) && retired.expired(), "LRU eviction retained old ownership");
	require(cache.bytes() == 8 && cache.size() == 2, "Entry budget accounting");
	cache.put(4, std::make_shared<int>(4), 8);
	require(cache.size() == 1 && cache.bytes() == 8 && !cache.get(1, match(1)), "Byte eviction failed");
	cache.put(4, std::make_shared<int>(40), 1);
	cache.put(5, std::make_shared<int>(5), 4);
	require(!cache.get(4, match(4)), "Candidate content mismatch accepted");
	cache.put(6, std::make_shared<int>(6), 4);
	require(!cache.get(4, match(40)), "Rejected lookup incorrectly promoted candidate");
	require(!cache.put(7, std::make_shared<int>(7), 11) && cache.bytes() == 8, "Oversized entry changed cache");
	cache.put(5, std::make_shared<int>(50), 10);
	require(cache.size() == 1 && cache.bytes() == 10 && !cache.get(6, match(6)), "Replacement accounting failed");

	auto incoming = std::make_shared<int>(8);
	allocations_before_failure = 1; // list node succeeds, index node allocation fails
	bool failed = false;
	try { cache.put(8, incoming, 1); } catch (const std::bad_alloc &) { failed = true; }
	allocations_before_failure = -1;
	require(failed && cache.bytes() == 10 && cache.size() == 1 && cache.get(5, match(50)), "Insertion failure damaged cache");
	require(incoming.use_count() == 1, "Failed insertion leaked list ownership");
	cache.clear(); require(cache.bytes() == 0 && cache.size() == 0, "Clear retained entries");

	Cache huge(std::numeric_limits<size_t>::max(), 2);
	huge.put(1, incoming, std::numeric_limits<size_t>::max() - 4);
	huge.put(2, incoming, 8);
	require(huge.size() == 1 && huge.bytes() == 8 && !huge.get(1, match(8)), "Budget addition overflowed");
	Cache disabled(10, 0);
	require(!disabled.put(1, incoming, 0), "Disabled entry budget accepted value");
	std::cout << "BOUNDED_LRU_PASS" << std::endl;
}
