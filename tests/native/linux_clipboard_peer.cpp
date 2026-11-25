#include <gtk/gtk.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>
#include <vector>

namespace {
const char *custom = "application/x-godot-custom-token";
const char *url = "application/x-godot-url";
const std::string files_dir = "/tmp/godot-jfx-clipboard-fixture/";

void expect(bool ok, const std::string &message) {
	if (!ok) {
		std::fprintf(stderr, "Linux clipboard peer: %s\n", message.c_str());
		std::exit(1);
	}
}

void wait_for(const std::string &file) {
	auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(35);
	while (!std::filesystem::exists(file)) {
		expect(std::chrono::steady_clock::now() < deadline, "timed out waiting for " + file);
		while (g_main_context_iteration(nullptr, FALSE)) {}
		std::this_thread::sleep_for(std::chrono::milliseconds(5));
	}
}

void touch(const std::string &file) {
	std::ofstream out(file);
	out << "ready\n";
	out.close();
	expect(bool(out), "cannot write " + file);
}

std::string read_target(GtkClipboard *clipboard, const char *target) {
	auto *data = gtk_clipboard_wait_for_contents(clipboard, gdk_atom_intern(target, FALSE));
	expect(data && gtk_selection_data_get_length(data) > 0, std::string("missing target ") + target);
	std::string bytes(reinterpret_cast<const char *>(gtk_selection_data_get_data(data)), gtk_selection_data_get_length(data));
	gtk_selection_data_free(data);
	return bytes;
}

void check_publication(GtkClipboard *clipboard) {
	auto *text = gtk_clipboard_wait_for_text(clipboard);
	expect(text && std::string(text) == "Godot JavaFX 中文 🙂\nsecond line", "UTF-8 text differs");
	g_free(text);
	expect(read_target(clipboard, "text/html") == "<b>Godot 中文 🙂</b>", "HTML differs");
	expect(read_target(clipboard, "text/rtf") == "{\\rtf1\\ansi Godot \\b rich\\b0}", "RTF differs");
	expect(read_target(clipboard, url) == "https://example.invalid/中文?q=🙂", "URL differs");
	expect(read_target(clipboard, custom) == "剪贴板自定义负载 🙂", "custom data differs");
	auto **uris = gtk_clipboard_wait_for_uris(clipboard);
	expect(uris && g_strv_length(uris) == 2, "file count differs");
	const char *names[] = { "godot-jfx测试/报告 🙂.txt", "README.md" };
	for (int i = 0; i < 2; ++i) {
		char *path = g_filename_from_uri(uris[i], nullptr, nullptr);
		expect(path && files_dir + names[i] == path, "file path differs");
		g_free(path);
	}
	g_strfreev(uris);
	auto *image = gtk_clipboard_wait_for_image(clipboard);
	expect(image && gdk_pixbuf_get_width(image) == 3 && gdk_pixbuf_get_height(image) == 2 &&
			gdk_pixbuf_get_has_alpha(image), "3x2 RGBA image missing");
	const std::array<guchar, 24> expected = {10,20,30,255, 40,50,60,255, 70,80,90,255,
			100,110,120,255, 130,140,150,255, 0,0,0,0};
	for (int row = 0; row < 2; ++row) {
		auto *pixels = gdk_pixbuf_get_pixels(image) + row * gdk_pixbuf_get_rowstride(image);
		expect(std::equal(pixels, pixels + 12, expected.begin() + row * 12), "image pixels differ");
	}
	g_object_unref(image);
}

using Targets = std::vector<std::pair<std::string, std::string>>;

void serve(GtkClipboard *, GtkSelectionData *data, guint index, gpointer context) {
	const auto &value = static_cast<const Targets *>(context)->at(index).second;
	gtk_selection_data_set(data, gtk_selection_data_get_target(data), 8,
			reinterpret_cast<const guchar *>(value.data()), value.size());
}

void publish(GtkClipboard *clipboard, Targets &targets) {
	std::vector<GtkTargetEntry> entries;
	for (guint i = 0; i < targets.size(); ++i) {
		entries.push_back({targets[i].first.data(), 0, i});
	}
	expect(gtk_clipboard_set_with_data(clipboard, entries.data(), entries.size(), serve, nullptr, &targets),
			"could not acquire CLIPBOARD selection");
}

std::string image_png() {
	const guchar rgb[] = {255,0,0, 0,255,0, 0,0,255, 255,255,255};
	auto *image = gdk_pixbuf_new_from_data(rgb, GDK_COLORSPACE_RGB, FALSE, 8, 2, 2, 6, nullptr, nullptr);
	char *buffer = nullptr;
	gsize length = 0;
	expect(gdk_pixbuf_save_to_buffer(image, &buffer, &length, "png", nullptr, nullptr), "cannot encode PNG");
	std::string result(buffer, length);
	g_free(buffer);
	g_object_unref(image);
	return result;
}
}

// Wayland sends selection offers to the keyboard-focused client. Mapping
// and dismissing the peer lets the compositor hand focus between both apps.
void focus_peer(GtkWidget *window) {
	if (!window) return;
	gtk_widget_show_all(window);
	auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
	while (!gtk_window_has_toplevel_focus(GTK_WINDOW(window))) {
		expect(std::chrono::steady_clock::now() < deadline, "Wayland clipboard peer did not receive keyboard focus");
		while (g_main_context_iteration(nullptr, FALSE)) {}
		std::this_thread::sleep_for(std::chrono::milliseconds(5));
	}
	gdk_display_sync(gdk_display_get_default());
	while (g_main_context_iteration(nullptr, FALSE)) {}
}

void release_focus(GtkWidget *window) {
	if (!window) return;
	gdk_display_sync(gdk_display_get_default());
	gtk_widget_hide(window);
	gdk_display_flush(gdk_display_get_default());
}

int main(int argc, char **argv) {
	expect(argc == 3 && std::string(argv[1]) == "exchange", "expected exchange <sync-path>");
	const std::string sync = argv[2];
	gdk_set_allowed_backends("wayland");
	expect(gtk_init_check(&argc, &argv), "cannot open display");
	auto *clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
	GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
	gtk_window_set_title(GTK_WINDOW(window), "JavaFX clipboard exchange");
	gtk_container_add(GTK_CONTAINER(window), gtk_label_new("Testing clipboard formats"));
	wait_for(sync);
	focus_peer(window);
	check_publication(clipboard);
	Targets rich = {{"text/plain;charset=utf-8", "Godot external 中文 🙂"}, {"text/html", "<i>External 中文 🙂</i>"},
			{"text/rtf", "{\\rtf1\\ansi External \\i rich\\i0}"}, {"text/uri-list", "https://external.invalid/目录#🙂\r\n"}};
	publish(clipboard, rich);
	release_focus(window);
	touch(sync + ".external");
	wait_for(sync + ".ack");
	std::string uris;
	for (auto name : {"外部/文件 甲.txt", "外部/乙🙂.png"}) {
		auto *uri = g_filename_to_uri((files_dir + name).c_str(), nullptr, nullptr);
		expect(uri, "cannot encode file URI");
		uris += std::string(uri) + "\r\n";
		g_free(uri);
	}
	Targets raw = {{"text/uri-list", uris}, {"image/png", image_png()}, {url, "https://ansi.invalid/中文路径"},
			{custom, "外部剪贴板负载 🙂"}};
	focus_peer(window);
	publish(clipboard, raw);
	release_focus(window);
	touch(sync + ".external2");
	wait_for(sync + ".ack2");
	gtk_clipboard_set_can_store(clipboard, nullptr, 0);
	gtk_clipboard_store(clipboard);
	std::puts("CLIPBOARD_EXTERNAL_RICH_PASS");
}
