#if defined(NANA_MACOS)
#include <nana/gui/msgbox.hpp>
#import <Cocoa/Cocoa.h>

namespace nana {

	msgbox::pick_t msgbox::show() const
	{
		NSAlert *alert = [[NSAlert alloc] init];

		// Set the title as the message text
		if (!title_.empty())
		{
			alert.messageText = [NSString stringWithUTF8String:title_.c_str()];
		}

		// Set the streamed content as the informative text
		std::string msg = sstream_.str();
		if (!msg.empty())
		{
			alert.informativeText = [NSString stringWithUTF8String:msg.c_str()];
		}

		// Map icon to NSAlert style
		switch (icon_)
		{
		case icon_information:
			alert.alertStyle = NSAlertStyleInformational;
			break;
		case icon_warning:
			alert.alertStyle = NSAlertStyleWarning;
			break;
		case icon_error:
			alert.alertStyle = NSAlertStyleCritical;
			break;
		default:
			break;
		}

		// Add buttons based on button type
		switch (button_)
		{
		case ok:
			[alert addButtonWithTitle:@"OK"];
			break;
		case yes_no:
			[alert addButtonWithTitle:@"Yes"];
			[alert addButtonWithTitle:@"No"];
			break;
		case yes_no_cancel:
			[alert addButtonWithTitle:@"Yes"];
			[alert addButtonWithTitle:@"No"];
			[alert addButtonWithTitle:@"Cancel"];
			break;
		}

		NSModalResponse response = [alert runModal];
		[alert release];

		// Map NSModalResponse to pick_t
		switch (button_)
		{
		case ok:
			return pick_ok;
		case yes_no:
			return (response == NSAlertFirstButtonReturn) ? pick_yes : pick_no;
		case yes_no_cancel:
			if (response == NSAlertFirstButtonReturn)
				return pick_yes;
			if (response == NSAlertSecondButtonReturn)
				return pick_no;
			return pick_cancel;
		}

		return pick_ok;
	}

}
#endif
