#pragma once
#include <cstddef>
#include <functional>
#include <list>
#include <iterator>
#include <unordered_map>
#include <utility>

namespace godot_javafx {
// Main-thread cache. The list owns values; the index owns only list iterators.
// Weight is supplied by the caller and must describe immutable entry content.
template <class Key, class Value, class Hasher = std::hash<Key>>
class BoundedLruCache {
	struct Entry { Key key; Value value; size_t bytes; };
	using List = std::list<Entry>;
	List entries;
	std::unordered_map<Key, typename List::iterator, Hasher> index;
	size_t bytes_used = 0;
	const size_t byte_limit, entry_limit;
public:
	BoundedLruCache(size_t p_bytes, size_t p_entries) : byte_limit(p_bytes), entry_limit(p_entries) {}
	BoundedLruCache(const BoundedLruCache &) = delete;
	BoundedLruCache &operator=(const BoundedLruCache &) = delete;

	template <class Matches>
	const Value *get(const Key &p_key, Matches p_matches) {
		auto found = index.find(p_key);
		if (found == index.end() || !p_matches(found->second->value)) return nullptr;
		entries.splice(entries.begin(), entries, found->second);
		return &found->second->value;
	}

	bool put(const Key &p_key, Value p_value, size_t p_bytes) {
		if (p_bytes > byte_limit || entry_limit == 0) return false;
		auto existing = index.find(p_key);
		entries.push_front({p_key, std::move(p_value), p_bytes});
		if (existing != index.end()) {
			auto previous = existing->second;
			existing->second = entries.begin();
			bytes_used -= previous->bytes;
			entries.erase(previous);
		} else {
			try {
				index.emplace(p_key, entries.begin());
			} catch (...) {
				entries.pop_front(); // preserve old entries and accounting on failure
				throw;
			}
		}
		// Subtract before addition so the accounting cannot overflow, even
		// when configured with a near-SIZE_MAX budget.
		while (bytes_used > byte_limit - p_bytes || entries.size() > entry_limit) {
			auto oldest = std::prev(entries.end());
			bytes_used -= oldest->bytes;
			index.erase(oldest->key);
			entries.erase(oldest);
		}
		bytes_used += p_bytes;
		return true;
	}
	void clear() { index.clear(); entries.clear(); bytes_used = 0; }
	size_t size() const { return entries.size(); }
	size_t bytes() const { return bytes_used; }
};
} // namespace godot_javafx
