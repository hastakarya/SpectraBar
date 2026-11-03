// Private Touch Bar API (DFRFoundation + AppKit) used to sit in the Control Strip
// and show a full-width bar over every app. Not public: a macOS update may remove it.
#import <AppKit/AppKit.h>

extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier identifier, BOOL present);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL show);

@interface NSTouchBarItem (Private)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (Private)
// placement 1 covers the Control Strip too, giving the bar the full width.
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(long long)placement
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier
    NS_SWIFT_NAME(presentSystemModal(_:placement:trayItem:));
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar NS_SWIFT_NAME(minimizeSystemModal(_:));
@end
