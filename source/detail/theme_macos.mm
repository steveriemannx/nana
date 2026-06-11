#include "posix/theme.hpp"
#if defined(NANA_MACOS)
#import <Cocoa/Cocoa.h>

namespace nana { namespace detail {

theme::theme()
{
	// On macOS, use the user's home directory as a base for icon lookups
	const char* home = getenv("HOME");
	if (home)
		path_ = home;
}

std::string theme::cursor(const std::string& name) const
{
	// macOS uses system cursors via NSCursor, no file paths needed
	return {};
}

std::string theme::icon(const std::string& name, std::size_t size_wanted) const
{
	// macOS system icons are in CoreTypes.bundle
	// Map common freedesktop icon names to macOS system icon paths
	static const char* coretypes_path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources";

	struct icon_map_entry {
		const char* freedesktop_name;
		const char* macos_filename;
	};

	static const icon_map_entry icon_map[] = {
		{"folder",          "GenericFolderIcon.icns"},
		{"folder-open",     "OpenFolderIcon.icns"},
		{"folder_home",     "HomeFolderIcon.icns"},
		{"drive-harddisk",  "GenericInternalDriveIcon.icns"},
		{"empty",           "GenericDocumentIcon.icns"},
		{"text",            "GenericDocumentIcon.icns"},
		{"text-xml",        "GenericDocumentIcon.icns"},
		{"image",           "GenericDocumentIcon.icns"},
		{"application-pdf", "GenericDocumentIcon.icns"},
		{"exec",            "ExecutableBinaryIcon.icns"},
		{"package",         "GenericArchiveIcon.icns"},
	};

	for (const auto& entry : icon_map)
	{
		if (name == entry.freedesktop_name)
		{
			return std::string(coretypes_path) + "/" + entry.macos_filename;
		}
	}

	return {};
}

}}
#endif
