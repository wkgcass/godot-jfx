// Weston test module for the private NonRobot display. Send data-device
// messages directly to the requesting fixture's surface without seat input.
#include <libweston/libweston.h>
#include <libweston/desktop.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct format { const char *mime, *bytes; };
static const struct format formats[] = {
    { "text/plain;charset=utf-8", "注入 OLE text 🙂" },
    { "text/uri-list", "https://inject.example/路径 🙂\r\nfile:///tmp/注入-a.txt\r\nfile:///tmp/inject%20乙🙂.txt\r\n" },
    { "text/html", "<b>外部 HTML</b>" },
    { "text/rtf", "{\\rtf1 external}" },
    { "application/x-godot-custom-token", "注入自定义负载 🙂" },
};
#define FORMAT_COUNT (sizeof formats / sizeof formats[0])
#define COPY WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY

static struct {
    struct wl_display *display;
    struct wl_event_source *timer;
    struct wl_listener shutdown;
    const char *directory;
    struct wl_resource *device, *surface, *offer;
    uint32_t serial;
    unsigned received, motions;
    bool timeout, accepted, dropped, replied;
    struct timespec entered;
} peer;

static bool filename(char *buffer, const char *name) {
    int length = snprintf(buffer, PATH_MAX, "%s/%s", peer.directory, name);
    return length > 0 && length < PATH_MAX;
}

static void result(bool ok) {
    if (peer.replied) return;
    peer.replied = true;
    fprintf(stderr, "Wayland drag reply ok=%d timeout=%d accepted=%d dropped=%d formats=0x%x motions=%u\n",
            ok, peer.timeout, peer.accepted, peer.dropped, peer.received, peer.motions);
    char path[PATH_MAX], temp[PATH_MAX];
    if (!filename(temp, "response.tmp") || !filename(path, "response")) return;
    FILE *f = fopen(temp, "w");
    if (!f) return;
    fprintf(f, "%s\n", ok ? (peer.timeout ? "canceled" : "finished") : "failed");
    if (fclose(f) == 0) rename(temp, path);
}

static void accept_mime(struct wl_client *c, struct wl_resource *offer, uint32_t serial, const char *mime) {
    peer.accepted = false;
    if (serial != peer.serial) { result(false); return; }
    for (size_t i = 0; mime && i < FORMAT_COUNT; ++i)
        if (!strcmp(mime, formats[i].mime)) peer.accepted = true;
}

static void receive_mime(struct wl_client *c, struct wl_resource *offer, const char *mime, int fd) {
    for (size_t i = 0; i < (peer.timeout ? 1 : FORMAT_COUNT); ++i) {
        if (strcmp(mime, formats[i].mime)) continue;
        const char *bytes = peer.timeout ? "expired" : formats[i].bytes;
        size_t length = strlen(bytes);
        if (write(fd, bytes, length) == (ssize_t)length) peer.received |= 1u << i;
        break;
    }
    close(fd);
}

static void destroy_offer(struct wl_client *c, struct wl_resource *offer) { wl_resource_destroy(offer); }
static void finish_offer(struct wl_client *c, struct wl_resource *offer) {
    result(!peer.timeout && peer.dropped && peer.accepted && peer.received == (1u << FORMAT_COUNT) - 1u);
}
static void release_offer(struct wl_resource *offer) {
    if (!peer.replied) result(false);
    peer.offer = NULL;
}

static void set_actions(struct wl_client *c, struct wl_resource *offer, uint32_t actions, uint32_t preferred) {
    if (peer.replied || peer.dropped) return;
    fprintf(stderr, "Wayland drag actions=%u preferred=%u accepted=%d\n", actions, preferred, peer.accepted);
    if (!peer.timeout && peer.accepted && (actions & COPY) && preferred == COPY) {
        wl_data_offer_send_action(offer, COPY);
        wl_data_device_send_drop(peer.device);
        wl_data_device_send_leave(peer.device);
        peer.dropped = true;
    } else if (!peer.motions++) {
        wl_data_device_send_motion(peer.device, 1, wl_fixed_from_int(80), wl_fixed_from_int(48));
    } else {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double elapsed = now.tv_sec - peer.entered.tv_sec + (now.tv_nsec - peer.entered.tv_nsec) / 1e9;
        wl_data_device_send_leave(peer.device);
        result(peer.timeout && !actions && !peer.accepted && peer.received == 1 && elapsed >= 1.4);
    }
}

static const struct wl_data_offer_interface offer_impl = {
    .accept=accept_mime, .receive=receive_mime, .destroy=destroy_offer, .finish=finish_offer, .set_actions=set_actions,
};

static enum wl_iterator_result find_resources(struct wl_resource *resource, void *unused) {
    const char *type = wl_resource_get_class(resource);
    if (!strcmp(type, "wl_data_device") && wl_resource_get_version(resource) >= 3) peer.device = resource;
    if (!strcmp(type, "wl_surface")) {
        struct weston_surface *surface = wl_resource_get_user_data(resource);
        if (surface && weston_surface_is_desktop_surface(surface)) {
            const char *title = weston_desktop_surface_get_title(weston_surface_get_desktop_surface(surface));
            if (title && !strcmp(title, peer.timeout ? "OLE_INJECT_BLOCKED" : "OLE_INJECT_READY"))
                peer.surface = resource;
        }
    }
    return WL_ITERATOR_CONTINUE;
}

static int poll_request(void *unused) {
    wl_event_source_timer_update(peer.timer, 40);
    if (peer.offer) return 0;
    char path[PATH_MAX], phase[16];
    if (!filename(path, "request")) return 0;
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    int pid;
    int fields = fscanf(f, "%d %15s", &pid, phase);
    fclose(f);
    if (fields != 2 || pid <= 0 || (strcmp(phase, "timeout") && strcmp(phase, "drop"))) return 0;
    peer.timeout = !strcmp(phase, "timeout");
    struct wl_client *client;
    wl_client_for_each(client, wl_display_get_client_list(peer.display)) {
        pid_t owner;
        wl_client_get_credentials(client, &owner, NULL, NULL);
        if (owner != pid) continue;
        peer.device = peer.surface = NULL;
        wl_client_for_each_resource(client, find_resources, NULL);
        if (!peer.device || !peer.surface) continue;
        unlink(path);
        peer.replied = peer.accepted = peer.dropped = false;
        peer.received = peer.motions = 0;
        peer.offer = wl_resource_create(client, &wl_data_offer_interface, 3, 0);
        if (!peer.offer) { result(false); return 0; }
        wl_resource_set_implementation(peer.offer, &offer_impl, NULL, release_offer);
        wl_data_device_send_data_offer(peer.device, peer.offer);
        for (size_t i = 0; i < (peer.timeout ? 1 : FORMAT_COUNT); ++i)
            wl_data_offer_send_offer(peer.offer, formats[i].mime);
        wl_data_offer_send_source_actions(peer.offer, COPY);
        peer.serial = wl_display_next_serial(peer.display);
        clock_gettime(CLOCK_MONOTONIC, &peer.entered);
        wl_data_device_send_enter(peer.device, peer.serial, peer.surface, wl_fixed_from_int(80),
                                  wl_fixed_from_int(48), peer.offer);
        wl_client_flush(client);
        break;
    }
    return 0;
}

static void shutdown_peer(struct wl_listener *listener, void *data) {
    wl_event_source_remove(peer.timer);
    wl_list_remove(&listener->link);
}

WL_EXPORT int wet_module_init(struct weston_compositor *compositor, int *argc, char *argv[]) {
    peer.directory = getenv("GODOT_JFX_WAYLAND_DND_DIR");
    if (!peer.directory || !*peer.directory) return -1;
    peer.display = compositor->wl_display;
    peer.timer = wl_event_loop_add_timer(wl_display_get_event_loop(peer.display), poll_request, NULL);
    if (!peer.timer) return -1;
    peer.shutdown.notify = shutdown_peer;
    wl_signal_add(&compositor->destroy_signal, &peer.shutdown);
    return wl_event_source_timer_update(peer.timer, 40);
}
