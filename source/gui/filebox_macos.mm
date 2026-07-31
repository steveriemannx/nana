/*
 *	Native macOS File Dialog using NSOpenPanel/NSSavePanel
 *	Nana C++ Library
 */

#import <Cocoa/Cocoa.h>
#include <vector>
#include <string>
#include <utility>

#if defined(NANA_MACOS)

extern "C" {

// Data structures passed between C++ and Objective-C code
// (must match definitions in filebox.cpp)
struct nana_macos_filebox_data {
	const char* title;
	const char* init_path;
	const char* init_file;
	bool is_open;
	bool allow_multi;
	const char** filter_descs;
	const char** filter_patterns;
	int filter_count;
	void* owner_native;
};

struct nana_macos_folderbox_data {
	const char* title;
	const char* init_path;
	bool allow_multi;
	void* owner_native;
};

int nana_macos_show_filebox(nana_macos_filebox_data* data, char*** out_paths, int* out_count) {
	@autoreleasepool {
		*out_paths = nullptr;
		*out_count = 0;

		NSWindow* owner = nil;
		if (data->owner_native) {
			owner = (__bridge NSWindow*)data->owner_native;
		}

		if (data->is_open) {
			NSOpenPanel* panel = [NSOpenPanel openPanel];
			[panel setCanChooseFiles:YES];
			[panel setCanChooseDirectories:NO];
			[panel setAllowsMultipleSelection:data->allow_multi];

			if (data->title && strlen(data->title) > 0)
				[panel setMessage:[NSString stringWithUTF8String:data->title]];

			if (data->init_path && strlen(data->init_path) > 0) {
				NSString* path = [NSString stringWithUTF8String:data->init_path];
				[panel setDirectoryURL:[NSURL fileURLWithPath:path]];
			}

			if (data->init_file && strlen(data->init_file) > 0) {
				NSString* file = [NSString stringWithUTF8String:data->init_file];
				[panel setNameFieldStringValue:file];
			}

			// Set up file type filters
			if (data->filter_count > 0 && data->filter_patterns) {
				NSMutableArray* types = [NSMutableArray array];
				for (int i = 0; i < data->filter_count; ++i) {
					const char* pattern = data->filter_patterns[i];
					if (pattern) {
						std::string p(pattern);
						// Convert "*.txt" to "public.text" or use UTType
						// For simplicity, strip * and . and use as extension
						std::string ext;
						for (char c : p) {
							if (c != '*' && c != '.') ext += c;
						}
						if (!ext.empty())
							[types addObject:[NSString stringWithUTF8String:ext.c_str()]];
					}
				}
				if ([types count] > 0)
					[panel setAllowedFileTypes:types];
			}

			NSModalResponse result;
			if (owner) {
				[panel beginSheetModalForWindow:owner completionHandler:^(NSModalResponse r) {
					[NSApp stopModalWithCode:r];
				}];
				result = [NSApp runModalForWindow:panel];
			} else {
				result = [panel runModal];
			}

			if (result != NSModalResponseOK) return 0;

			NSArray* urls = [panel URLs];
			*out_count = (int)[urls count];
			if (*out_count == 0) return 0;

			*out_paths = (char**)malloc(sizeof(char*) * (*out_count));
			for (int i = 0; i < *out_count; ++i) {
				NSString* path = [[urls objectAtIndex:i] path];
				const char* utf8 = [path UTF8String];
				(*out_paths)[i] = strdup(utf8 ? utf8 : "");
			}
			return 1;
		} else {
			NSSavePanel* panel = [NSSavePanel savePanel];

			if (data->title && strlen(data->title) > 0)
				[panel setMessage:[NSString stringWithUTF8String:data->title]];

			if (data->init_path && strlen(data->init_path) > 0) {
				NSString* path = [NSString stringWithUTF8String:data->init_path];
				[panel setDirectoryURL:[NSURL fileURLWithPath:path]];
			}

			if (data->init_file && strlen(data->init_file) > 0) {
				NSString* file = [NSString stringWithUTF8String:data->init_file];
				[panel setNameFieldStringValue:file];
			}

			// File type filters for save panel
			if (data->filter_count > 0 && data->filter_patterns) {
				NSMutableArray* types = [NSMutableArray array];
				for (int i = 0; i < data->filter_count; ++i) {
					const char* pattern = data->filter_patterns[i];
					if (pattern) {
						std::string p(pattern);
						std::string ext;
						for (char c : p) {
							if (c != '*' && c != '.') ext += c;
						}
						if (!ext.empty())
							[types addObject:[NSString stringWithUTF8String:ext.c_str()]];
					}
				}
				if ([types count] > 0)
					[panel setAllowedFileTypes:types];
			}

			NSModalResponse result;
			if (owner) {
				[panel beginSheetModalForWindow:owner completionHandler:^(NSModalResponse r) {
					[NSApp stopModalWithCode:r];
				}];
				result = [NSApp runModalForWindow:panel];
			} else {
				result = [panel runModal];
			}

			if (result != NSModalResponseOK) return 0;

			NSURL* url = [panel URL];
			if (!url) return 0;

			*out_count = 1;
			*out_paths = (char**)malloc(sizeof(char*));
			const char* utf8 = [[url path] UTF8String];
			(*out_paths)[0] = strdup(utf8 ? utf8 : "");
			return 1;
		}
	}
}

// Folder chooser
int nana_macos_show_folderbox(nana_macos_folderbox_data* data, char*** out_paths, int* out_count) {
	@autoreleasepool {
		*out_paths = nullptr;
		*out_count = 0;

		NSWindow* owner = nil;
		if (data->owner_native) {
			owner = (__bridge NSWindow*)data->owner_native;
		}

		NSOpenPanel* panel = [NSOpenPanel openPanel];
		[panel setCanChooseDirectories:YES];
		[panel setCanChooseFiles:NO];
		[panel setAllowsMultipleSelection:data->allow_multi];

		if (data->title && strlen(data->title) > 0)
			[panel setMessage:[NSString stringWithUTF8String:data->title]];

		if (data->init_path && strlen(data->init_path) > 0) {
			NSString* path = [NSString stringWithUTF8String:data->init_path];
			[panel setDirectoryURL:[NSURL fileURLWithPath:path]];
		}

		NSModalResponse result;
		if (owner) {
			[panel beginSheetModalForWindow:owner completionHandler:^(NSModalResponse r) {
				[NSApp stopModalWithCode:r];
			}];
			result = [NSApp runModalForWindow:panel];
		} else {
			result = [panel runModal];
		}

		if (result != NSModalResponseOK) return 0;

		NSArray* urls = [panel URLs];
		*out_count = (int)[urls count];
		if (*out_count == 0) return 0;

		*out_paths = (char**)malloc(sizeof(char*) * (*out_count));
		for (int i = 0; i < *out_count; ++i) {
			NSString* path = [[urls objectAtIndex:i] path];
			const char* utf8 = [path UTF8String];
			(*out_paths)[i] = strdup(utf8 ? utf8 : "");
		}
		return 1;
	}
}

// Cleanup helper
void nana_macos_free_filebox_result(char** paths, int count) {
	if (paths) {
		for (int i = 0; i < count; ++i) free(paths[i]);
		free(paths);
	}
}

} // extern "C"

#endif // NANA_MACOS
