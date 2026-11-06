// Native regression check; opens and closes only its own Settings windows.
#import "../source/native/settings.m"
#include <assert.h>

static void check_layout(HoodSettingsController *controller) {
    [controller.window.contentView layoutSubtreeIfNeeded];
    NSPopUpButton *display=(NSPopUpButton *)controller.controls[@(HoodDisplay)];
    assert(!display.enclosingScrollView);
    NSTabView *tabs=(NSTabView *)controller.window.contentView.subviews.firstObject;
    NSView *form=tabs.selectedTabViewItem.view;
    for(NSControl *control in controller.controls.allValues) {
        if(control.hidden || control.superview.hidden) continue;
        NSRect rect=[control convertRect:control.bounds toView:form];
        assert(NSContainsRect(form.bounds,rect));
    }
    NSControl *icons=controller.controls[@(HoodIconSize)];
    assert([icons convertPoint:NSZeroPoint toView:form].x > NSMidX(form.bounds));
    assert([display convertPoint:NSZeroPoint toView:form].x < NSMidX(form.bounds));
    assert(display.numberOfItems>=2);
    assert([display.itemArray[0].title isEqualToString:@"Primary display"]);
    assert([display.itemArray[1].title isEqualToString:@"All displays"]);
    [tabs selectTabViewItemAtIndex:1];
    [controller.window.contentView layoutSubtreeIfNeeded];
    NSView *runtime=tabs.selectedTabViewItem.view;
    assert(controller.cpuLabel.frame.origin.x > NSMaxX(controller.loginButton.frame));
    assert(controller.loginButton.frame.origin.x < NSMidX(runtime.bounds));
    for(NSView *child in runtime.subviews) assert(NSContainsRect(runtime.bounds,child.frame));
    [tabs selectTabViewItemAtIndex:0];
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
