#include "session.h"
#include "mapped_file.h"
#include <algorithm>
#include <cstdint>

namespace godot_javafx::wayland_robot {
namespace {
using Copy = ext_image_copy_capture_session_v1;
using Frame = ext_image_copy_capture_frame_v1;
struct Result {
	uint32_t width = 0, height = 0, format = UINT32_MAX, transform = WL_OUTPUT_TRANSFORM_NORMAL;
	bool configured = false, stopped = false, ready = false;
	int failure = -1;
};
const ext_image_copy_capture_session_v1_listener constraints = {
	.buffer_size = [](void *d, Copy *, uint32_t w, uint32_t h) {
		auto &r = *static_cast<Result *>(d); r.width = w; r.height = h;
	},
	.shm_format = [](void *d, Copy *, uint32_t f) {
		if (f == WL_SHM_FORMAT_XRGB8888 || f == WL_SHM_FORMAT_ARGB8888) static_cast<Result *>(d)->format = f;
	},
	.dmabuf_device = [](void *, Copy *, wl_array *) {},
	.dmabuf_format = [](void *, Copy *, uint32_t, wl_array *) {},
	.done = [](void *d, Copy *) { static_cast<Result *>(d)->configured = true; },
	.stopped = [](void *d, Copy *) { static_cast<Result *>(d)->stopped = true; },
};
const ext_image_copy_capture_frame_v1_listener frame_events = {
	.transform = [](void *d, Frame *, uint32_t t) { static_cast<Result *>(d)->transform = t; },
	.damage = [](void *, Frame *, int32_t, int32_t, int32_t, int32_t) {},
	.presentation_time = [](void *, Frame *, uint32_t, uint32_t, uint32_t) {},
	.ready = [](void *d, Frame *) { static_cast<Result *>(d)->ready = true; },
	.failed = [](void *d, Frame *, uint32_t reason) { static_cast<Result *>(d)->failure = int(reason); },
};
}

std::vector<int32_t> Session::capture(int x, int y, int width, int height) {
	if (width <= 0 || height <= 0 || int64_t(width)*height > 16*1024*1024) throw std::invalid_argument("Invalid Wayland Robot capture size");
	sync();
	std::vector<int32_t> result(size_t(width)*height);
	for (auto &entry : outputs) {
		auto &o = entry.second;
		const int64_t left = std::max(x, o.x), top = std::max(y, o.y);
		const int64_t right = std::min(int64_t(x)+width, int64_t(o.x)+o.width);
		const int64_t bottom = std::min(int64_t(y)+height, int64_t(o.y)+o.height);
		if (right <= left || bottom <= top) continue;
		for (int attempt = 0; ; ++attempt) {
			Result r;
			std::unique_ptr<Copy, decltype(&ext_image_copy_capture_session_v1_destroy)> session(ext_image_copy_capture_manager_v1_create_session(captures.get(), o.source.get(), 0), ext_image_copy_capture_session_v1_destroy);
			ext_image_copy_capture_session_v1_add_listener(session.get(), &constraints, &r);
			wait([&] { return r.configured || r.stopped; });
			if (r.stopped || r.format == UINT32_MAX) throw Unsupported("Wayland output does not offer a readable 32-bit capture buffer");
			const uint32_t w = r.width, h = r.height;
			if (!w || !h || uint64_t(w)*h > 64*1024*1024) throw Unsupported("Wayland output capture buffer dimensions exceed the supported limit");
			MappedFile pixels(size_t(w)*h*4);
			std::unique_ptr<wl_shm_pool, decltype(&wl_shm_pool_destroy)> pool(wl_shm_create_pool(shm.get(), pixels.fd(), int(w*h*4)), wl_shm_pool_destroy);
			std::unique_ptr<wl_buffer, decltype(&wl_buffer_destroy)> buffer(wl_shm_pool_create_buffer(pool.get(), 0, w, h, w*4, r.format), wl_buffer_destroy);
			std::unique_ptr<Frame, decltype(&ext_image_copy_capture_frame_v1_destroy)> frame(ext_image_copy_capture_session_v1_create_frame(session.get()), ext_image_copy_capture_frame_v1_destroy);
			ext_image_copy_capture_frame_v1_add_listener(frame.get(), &frame_events, &r);
			ext_image_copy_capture_frame_v1_attach_buffer(frame.get(), buffer.get());
			ext_image_copy_capture_frame_v1_damage_buffer(frame.get(), 0, 0, w, h);
			ext_image_copy_capture_frame_v1_capture(frame.get());
			wait([&] { return r.ready || r.failure >= 0 || r.stopped; });
			if (!r.ready) {
				if (attempt == 0 && r.failure == EXT_IMAGE_COPY_CAPTURE_FRAME_V1_FAILURE_REASON_BUFFER_CONSTRAINTS) continue;
				throw std::runtime_error("Wayland compositor could not capture the output");
			}
			const auto *src = static_cast<const uint32_t *>(pixels.data());
			const unsigned rotation = r.transform & 3;
			for (int64_t py = top; py < bottom; ++py) {
				for (int64_t px = left; px < right; ++px) {
					const int u = int((px-o.x)*((rotation & 1) ? h : w)/o.width);
					const int v = int((py-o.y)*((rotation & 1) ? w : h)/o.height);
					int sx = u, sy = v;
					switch (rotation) {
						case 1: sx = int(w)-1-v; sy = u; break;
						case 2: sx = int(w)-1-u; sy = int(h)-1-v; break;
						case 3: sx = v; sy = int(h)-1-u; break;
					}
					if (r.transform & 4) sx = int(w)-1-sx;
					result[(py-y)*width + px-x] = int32_t(src[size_t(sy)*w+sx] | 0xff000000u);
				}
			}
			break;
		}
	}
	return result;
}
}
