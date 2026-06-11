#import <Cocoa/Cocoa.h>
#if defined(NANA_MACOS)

extern "C" {

struct nana_macos_screen_info {
	int x, y, width, height;
	bool is_primary;
};

int nana_macos_get_screen_count()
{
	return (int)[[NSScreen screens] count];
}

void nana_macos_get_screen_info(int index, nana_macos_screen_info* info)
{
	NSArray* screens = [NSScreen screens];
	if (index < 0 || index >= (int)[screens count])
		return;

	NSScreen* screen = [screens objectAtIndex:(NSUInteger)index];
	NSRect frame = [screen frame];

	info->x = (int)frame.origin.x;
	info->y = (int)frame.origin.y;
	info->width = (int)frame.size.width;
	info->height = (int)frame.size.height;
	info->is_primary = (index == 0);
}

} // extern "C"

#endif
