// Native regression check; opens and closes only its own Settings windows.
#import "../source/native/settings.m"
#include <assert.h>

static void check_layout(HoodSettingsController *controller) {
    [controller.window.contentView layoutSubtreeIfNeeded];
    NSPopUpButton *display=(NSPopUpButton *)controller.controls[@(HoodDisplay)];
    NSScrollView *scroll=display.enclosingScrollView;
    assert(scroll);
    NSRect rect=[display convertRect:display.bounds toView:scroll.contentView];
    assert(NSContainsRect(scroll.contentView.bounds,rect));
    assert(display.numberOfItems>=2);
    assert([display.itemArray[0].title isEqualToString:@"Primary display"]);
    assert([display.itemArray[1].title isEqualToString:@"All displays"]);
    assert(scroll.documentView.frame.size.height>=scroll.contentSize.height);
}

int main(void) {
    @autoreleasepool {
        HoodSettingsState state={0};
        state.icon_size=32; state.auto_hide=1; state.tooltip_opacity_percent=100;
        void *handle=hood_settings_create(&state,1,1,0,0);
        HoodSettingsController *controller=(__bridge HoodSettingsController *)handle;
        check_layout(controller);
        assert(!NSColorPanel.sharedColorPanelExists || !NSColorPanel.sharedColorPanel.visible);
        state.auto_hide=0;
        hood_settings_update(handle,&state);
        check_layout(controller);
        [controller openBackgroundColor:(HoodHexColorButton *)controller.controls[@(HoodBackground)]];
        assert(NSColorPanel.sharedColorPanel.visible);
        hood_settings_close(handle);
        assert(!NSColorPanel.sharedColorPanel.visible);
        handle=hood_settings_create(&state,1,1,0,0);
        controller=(__bridge HoodSettingsController *)handle;
        check_layout(controller);
        assert(!NSColorPanel.sharedColorPanel.visible);
        hood_settings_close(handle);
        puts("Display visibility and explicit-only Colors panel checks passed.");
    }
}
