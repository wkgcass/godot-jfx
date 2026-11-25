#ifdef LINUXBSD_ENABLED
#include "unix_dialogs.h"
#include <gtk/gtk.h>
#include <gdk/gdkwayland.h>

namespace godot_javafx::unix_dialogs {
namespace {
GtkWidget *active_panel = nullptr;

void init_chooser_display(const Request &request) {
	if (!gdk_display_get_default()) {
		gtk_disable_setlocale();
		gdk_set_allowed_backends("wayland");
	}
	if (!gtk_init_check(nullptr, nullptr) || !GDK_IS_WAYLAND_DISPLAY(gdk_display_get_default()))
		throw std::runtime_error("Cannot initialize GTK Wayland display for file chooser");
	if (request.owner >= 0 && request.exported_parent.empty())
		throw std::runtime_error("Wayland compositor did not export the file chooser's parent via xdg-foreign");
}

std::string utf8(const std::u16string &value) {
	auto *result = g_utf16_to_utf8(reinterpret_cast<const gunichar2 *>(value.c_str()), value.size(), nullptr, nullptr, nullptr);
	if (!result) throw std::invalid_argument("Invalid UTF-16 in file dialog");
	std::unique_ptr<char, decltype(&g_free)> storage(result, g_free);
	return result;
}

struct Context {
	std::shared_ptr<Request> request;
	Service *service;
};

void respond(GtkDialog *dialog, gint response, gpointer userdata) {
	auto &context = *static_cast<Context *>(userdata);
	auto request = context.request;
	auto *service = context.service;
	auto *chooser = GTK_FILE_CHOOSER(dialog);
	request->selected = -1;
	if (response == GTK_RESPONSE_ACCEPT) {
		auto *files = gtk_file_chooser_get_filenames(chooser);
		try {
			for (auto *item = files; item; item = item->next) {
				auto *path = static_cast<const char *>(item->data);
				std::unique_ptr<gchar, decltype(&g_free)> text(g_filename_to_utf8(path, -1, nullptr, nullptr, nullptr), g_free);
				std::unique_ptr<gunichar2, decltype(&g_free)> wide(text ? g_utf8_to_utf16(text.get(), -1, nullptr, nullptr, nullptr) : nullptr, g_free);
				if (!wide) throw std::runtime_error("Cannot convert selected filename to UTF-16");
				request->files.emplace_back(reinterpret_cast<const char16_t *>(wide.get()));
			}
			auto *filters = gtk_file_chooser_list_filters(chooser);
			request->selected = g_slist_index(filters, gtk_file_chooser_get_filter(chooser));
			g_slist_free(filters);
		} catch (const std::exception &error) {
			request->error = error.what();
		}
		g_slist_free_full(files, g_free);
	}
	active_panel = nullptr;
	service->panel_closed(dialog);
	gtk_widget_destroy(GTK_WIDGET(dialog));
	request->done.store(true, std::memory_order_release);
}
}

void *panel_present(const std::shared_ptr<Request> &request, Service *service, void *owner) {
	if (active_panel) throw std::runtime_error("A GTK file chooser is already open");
	init_chooser_display(*request);
	auto action = request->mode == 2 ? GTK_FILE_CHOOSER_ACTION_SAVE :
			request->mode == 3 ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER : GTK_FILE_CHOOSER_ACTION_OPEN;
	auto *dialog = gtk_file_chooser_dialog_new(utf8(request->title).c_str(), nullptr, action,
			"_Cancel", GTK_RESPONSE_CANCEL, action == GTK_FILE_CHOOSER_ACTION_SAVE ? "_Save" : "_Open", GTK_RESPONSE_ACCEPT, nullptr);
	std::unique_ptr<GtkWidget, decltype(&gtk_widget_destroy)> guard(dialog, gtk_widget_destroy);
	auto *chooser = GTK_FILE_CHOOSER(dialog);
	gtk_file_chooser_set_select_multiple(chooser, request->mode == 1);
	if (!request->folder.empty()) gtk_file_chooser_set_current_folder(chooser, utf8(request->folder).c_str());
	if (!request->filename.empty()) {
		if (request->mode == 2) gtk_file_chooser_set_current_name(chooser, utf8(request->filename).c_str());
		else {
			auto name = utf8(request->filename);
			auto folder = utf8(request->folder);
			auto *path = g_canonicalize_filename(name.c_str(), g_path_is_absolute(folder.c_str()) ? folder.c_str() : nullptr);
			gtk_file_chooser_set_filename(chooser, path);
			g_free(path);
		}
	}
	for (size_t index = 0; index < request->names.size(); ++index) {
		auto label = utf8(request->names[index]);
		auto patterns = utf8(request->patterns[index]);
		auto *filter = gtk_file_filter_new();
		gtk_file_filter_set_name(filter, label.c_str());
		auto **parts = g_strsplit(patterns.c_str(), ";", -1);
		for (auto **part = parts; *part; ++part) gtk_file_filter_add_pattern(filter, g_str_equal(*part, "*.*") ? "*" : *part);
		g_strfreev(parts);
		gtk_file_chooser_add_filter(chooser, filter);
		if (int(index) == request->selected) gtk_file_chooser_set_filter(chooser, filter);
	}
	gtk_window_set_modal(GTK_WINDOW(dialog), true);
	gtk_widget_realize(dialog);
	if (request->owner >= 0) {
		if (!gdk_wayland_window_set_transient_for_exported(gtk_widget_get_window(dialog), request->exported_parent.data()))
			throw std::runtime_error("Cannot import the Wayland file chooser's parent in GTK");
	}
	auto *context = new Context{ request, service };
	g_signal_connect_data(dialog, "response", G_CALLBACK(respond), context,
			[](gpointer data, GClosure *) { delete static_cast<Context *>(data); }, GConnectFlags(0));
	active_panel = guard.release();
	gtk_widget_show(dialog);
	return dialog;
}

void panel_pump() {
	for (int count = 0; active_panel && count < 32 && g_main_context_pending(nullptr); ++count)
		g_main_context_iteration(nullptr, false);
}
void panel_abort(void *panel) {
	if (panel && panel == active_panel) gtk_dialog_response(GTK_DIALOG(panel), GTK_RESPONSE_CANCEL);
}
void panel_detach(Service *) {
}
}
#endif
