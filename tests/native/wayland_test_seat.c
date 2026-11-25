// Input for the private headless Weston 14 test desktop. Each byte on its
// private FIFO requests one task-switcher gesture on this compositor's seat.
#include <libweston/libweston.h>
#include <libweston/version.h>
#include <fcntl.h>
#include <linux/input-event-codes.h>
#include <stdlib.h>
#include <unistd.h>

#if WESTON_VERSION_MAJOR != 14
#error "The test seat uses Weston's version 14 backend API"
#endif

// libweston exports these backend entry points separately from its shell API.
void weston_seat_init(struct weston_seat *, struct weston_compositor *, const char *);
int weston_seat_init_pointer(struct weston_seat *);
int weston_seat_init_keyboard(struct weston_seat *, struct xkb_keymap *);
void weston_seat_release(struct weston_seat *);
void notify_key(struct weston_seat *, const struct timespec *, uint32_t,
                enum wl_keyboard_key_state, enum weston_key_state_update);
void notify_motion_absolute(struct weston_seat *, const struct timespec *, struct weston_coord_global);
void notify_pointer_frame(struct weston_seat *);

static struct weston_seat seat;
static struct wl_event_source *input;
static struct wl_listener shutdown;
static int control = -1;

static void key(uint32_t code, enum wl_keyboard_key_state state) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    notify_key(&seat, &now, code, state, STATE_UPDATE_AUTOMATIC);
}

static int switch_window(int fd, uint32_t mask, void *data) {
    char count;
    while (read(fd, &count, 1) == 1) {
        if (count != '1' && count != '2') continue;
        key(KEY_LEFTMETA, WL_KEYBOARD_KEY_STATE_PRESSED);
        for (int i = 0; i < count - '0'; ++i) {
            key(KEY_TAB, WL_KEYBOARD_KEY_STATE_PRESSED);
            key(KEY_TAB, WL_KEYBOARD_KEY_STATE_RELEASED);
        }
        key(KEY_LEFTMETA, WL_KEYBOARD_KEY_STATE_RELEASED);
    }
    return 0;
}

static void destroy(struct wl_listener *listener, void *data) {
    if (input) wl_event_source_remove(input);
    wl_list_remove(&listener->link);
    if (control >= 0) close(control);
    weston_seat_release(&seat);
}

WL_EXPORT int wet_module_init(struct weston_compositor *compositor, int *argc, char **argv) {
    const char *path = getenv("GODOT_JFX_WESTON_SEAT");
    weston_seat_init(&seat, compositor, "fixture");
    if (path) {
        control = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
        if (control < 0 || weston_seat_init_pointer(&seat) < 0 ||
                weston_seat_init_keyboard(&seat, NULL) < 0) goto failed;
        input = wl_event_loop_add_fd(wl_display_get_event_loop(compositor->wl_display),
                                     control, WL_EVENT_READABLE, switch_window, NULL);
        if (!input) goto failed;
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        notify_motion_absolute(&seat, &now, (struct weston_coord_global){ .c = {780, 520} });
        notify_pointer_frame(&seat);
    }
    shutdown.notify = destroy;
    wl_signal_add(&compositor->destroy_signal, &shutdown);
    return 0;

failed:
    weston_seat_release(&seat);
    if (control >= 0) close(control);
    return -1;
}
