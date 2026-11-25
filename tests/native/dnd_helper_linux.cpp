#include <gtk/gtk.h>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <string>

namespace {
constexpr size_t max_payload = 16 * 1024 * 1024;
char text_target[] = "text/plain;charset=utf-8";
char uri_target[] = "text/uri-list";
char custom_target[] = "application/x-godot-custom-token";
char opaque_target[] = "application/x-drag-fixture-bytes";
GtkTargetEntry targets[] = {{text_target, 0, 0}, {uri_target, 0, 1}, {custom_target, 0, 2}, {opaque_target, 0, 3}};

struct Endpoint {
	FILE *log = nullptr;
	int origin_x = 0, origin_y = 0;
	std::array<std::string, 4> values;
	size_t format_count = 3;
	size_t next = 0;
	bool saw_icon = false;
	bool failed = false;
};

bool observe_icon(Endpoint &peer, int x, int y) {
	const char *probe = std::getenv("GODOT_JFX_WAYLAND_ICON_PROBE");
	if (!probe) return false;
	std::string px = std::to_string(peer.origin_x + x), py = std::to_string(peer.origin_y + y);
	const gchar *args[] = {"python3", probe, px.c_str(), py.c_str(), nullptr};
	gchar *output = nullptr;
	gint status = -1;
	const auto ran = g_spawn_sync(nullptr, const_cast<gchar **>(args), nullptr, G_SPAWN_SEARCH_PATH,
	        nullptr, nullptr, &output, nullptr, &status, nullptr);
	int w = 0, h = 0, bytes = 0;
	bool measured = ran && status == 0 && output && std::sscanf(output, "%d %d %d", &w, &h, &bytes) == 3;
	g_free(output);
	if (measured) std::fprintf(peer.log, "DND_HELPER_ENTER x=%d y=%d effect=1 image=%dx%d bytes=%d\n", x, y, w, h, bytes);
	return measured && w == 8 && h == 6;
}

gboolean motion(GtkWidget *, GdkDragContext *ctx, int x, int y, guint time, gpointer user) {
	auto &peer = *static_cast<Endpoint *>(user);
	if (!peer.saw_icon) peer.saw_icon = observe_icon(peer, x, y);
	gdk_drag_status(ctx, GDK_ACTION_COPY, time);
	return TRUE;
}

void request(GtkWidget *widget, GdkDragContext *ctx, const Endpoint &peer, guint time) {
	gtk_drag_get_data(widget, ctx, gdk_atom_intern(targets[peer.next].target, FALSE), time);
}

gboolean drop(GtkWidget *widget, GdkDragContext *ctx, int, int, guint time, gpointer user) {
	auto &peer = *static_cast<Endpoint *>(user);
	peer.next = 0;
	peer.values = {};
	request(widget, ctx, peer, time);
	return TRUE;
}

void received(GtkWidget *widget, GdkDragContext *ctx, int, int, GtkSelectionData *data,
		guint index, guint time, gpointer user) {
	auto &peer = *static_cast<Endpoint *>(user);
	const int size = gtk_selection_data_get_length(data);
	if (index != peer.next || index >= peer.format_count || size <= 0 || size_t(size) > max_payload ||
			gtk_selection_data_get_format(data) != 8) {
		std::fprintf(peer.log, "DND_HELPER_RECEIVE_FAILED index=%u expected=%zu size=%d format=%d\n", index, peer.next, size, gtk_selection_data_get_format(data));
		gtk_drag_finish(ctx, FALSE, FALSE, time);
		return;
	}
	auto &value = peer.values[index];
	value.assign(reinterpret_cast<const char *>(gtk_selection_data_get_data(data)), size);
	if (index == 3) {
		if (value != std::string("\x00\xff\x01\x00", 4)) {
			gtk_drag_finish(ctx, FALSE, FALSE, time);
			return;
		}
		std::fprintf(peer.log, "DND_HELPER_BINARY_OUT bytes=%d\n", size);
	} else if (value.back() == '\0') {
		value.pop_back();
	}
	if (index != 3 && value.find('\0') != std::string::npos) {
		gtk_drag_finish(ctx, FALSE, FALSE, time);
		return;
	}
	if (++peer.next < peer.format_count) {
		request(widget, ctx, peer, time);
		return;
	}
	char **uris = g_uri_list_extract_uris(peer.values[1].c_str());
	std::string url, first_file;
	int files = 0;
	for (char **uri = uris; uri && *uri; ++uri) {
		char *file = g_filename_from_uri(*uri, nullptr, nullptr);
		if (file) {
			if (++files == 1) first_file = file;
			g_free(file);
		} else if (url.empty()) {
			url = *uri;
		}
	}
	g_strfreev(uris);
	std::fprintf(peer.log, "DND_HELPER_DROP text=[%s] url=[%s] files=%d first=[%s] custom=[%s]\n",
			peer.values[0].c_str(), url.c_str(), files, first_file.c_str(), peer.values[2].c_str());
	gtk_drag_finish(ctx, !url.empty() && files > 0, FALSE, time);
}

void provide(GtkWidget *, GdkDragContext *, GtkSelectionData *data, guint index, guint, gpointer user) {
	const auto &peer = *static_cast<Endpoint *>(user);
	if (index >= peer.format_count) return;
	const auto &bytes = peer.values[index];
	gtk_selection_data_set(data, gtk_selection_data_get_target(data), 8,
			reinterpret_cast<const guchar *>(bytes.data()), bytes.size());
}
}

int main(int argc, char **argv) {
	if (argc < 7) return 2;
	const bool source = std::string(argv[1]) == "source";
	if (source ? argc != 11 : (std::string(argv[1]) != "target" || argc != 7)) return 2;
	gdk_set_allowed_backends("wayland");
	if (!gtk_init_check(nullptr, nullptr)) return 1;
	Endpoint peer;
	if (std::getenv("GODOT_JFX_WAYLAND_TEST_LAYOUT")) peer.format_count = G_N_ELEMENTS(targets);
	peer.origin_x = std::atoi(argv[2]);
	peer.origin_y = std::atoi(argv[3]);
	peer.log = std::fopen(argv[6], "w");
	if (!peer.log) return 1;
	std::setvbuf(peer.log, nullptr, _IOLBF, 0);
	auto *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
	auto *area = gtk_event_box_new();
	gtk_window_set_title(GTK_WINDOW(window), source ? "Drag source fixture" : "Drag target fixture");
	gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
	gtk_window_set_keep_above(GTK_WINDOW(window), TRUE);
	gtk_window_set_accept_focus(GTK_WINDOW(window), FALSE);
	gtk_window_set_default_size(GTK_WINDOW(window), std::atoi(argv[4]), std::atoi(argv[5]));
	gtk_container_add(GTK_CONTAINER(window), area);
	if (source) {
		char *uri = g_filename_to_uri(argv[9], nullptr, nullptr);
		if (!uri) return 2;
		peer.values = {argv[7], std::string(argv[8]) + "\r\n" + uri + "\r\n", argv[10]};
		g_free(uri);
		peer.values[3] = std::string("\xfe\x00\x02\x00", 4);
		gtk_drag_source_set(area, GDK_BUTTON1_MASK, targets, peer.format_count, GDK_ACTION_COPY);
		g_signal_connect(area, "drag-begin", G_CALLBACK(+[](GtkWidget *, GdkDragContext *, gpointer user) {
			static_cast<Endpoint *>(user)->failed = false;
		}), &peer);
		g_signal_connect(area, "drag-data-get", G_CALLBACK(provide), &peer);
		g_signal_connect(area, "drag-failed", G_CALLBACK(+[](GtkWidget *, GdkDragContext *, GtkDragResult, gpointer user) -> gboolean {
			static_cast<Endpoint *>(user)->failed = true;
			return FALSE;
		}), &peer);
		g_signal_connect(area, "drag-end", G_CALLBACK(+[](GtkWidget *, GdkDragContext *ctx, gpointer user) {
			const auto &endpoint = *static_cast<Endpoint *>(user);
			std::fprintf(endpoint.log, "DND_HELPER_SOURCE_DONE effect=%d\n",
					!endpoint.failed && gdk_drag_context_get_selected_action(ctx) == GDK_ACTION_COPY);
		}), &peer);
	} else {
		gtk_drag_dest_set(area, GTK_DEST_DEFAULT_MOTION, targets, peer.format_count, GDK_ACTION_COPY);
		g_signal_connect(area, "drag-motion", G_CALLBACK(motion), &peer);
		g_signal_connect(area, "drag-drop", G_CALLBACK(drop), &peer);
		g_signal_connect(area, "drag-data-received", G_CALLBACK(received), &peer);
	}
	g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), nullptr);
	gtk_widget_show_all(window);
	gdk_display_sync(gdk_display_get_default());
	std::fprintf(peer.log, "DND_HELPER_READY display=%s\n", gdk_display_get_name(gdk_display_get_default()));
	gtk_main();
	std::fclose(peer.log);
}
