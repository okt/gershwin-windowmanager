//
//  URSWindowSwitcherOverlay.h
//  uroswm - Alt-Tab Window Switcher Overlay
//
//  Visual overlay showing application icons and names during Alt-Tab cycling
//  Displays a horizontal strip of icons with app names below
//

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

@interface URSWindowSwitcherOverlay : NSWindow

// Singleton access
+ (instancetype)sharedOverlay;

// Display management
- (void)showCenteredOnScreen;
- (void)hide;

// Update display with current titles, icons, and selection
// Pass nil for icons array to use fallback letter-based icons
- (void)updateWithTitles:(NSArray *)titles icons:(NSArray *)icons currentIndex:(NSInteger)index;

@end
