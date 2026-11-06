package main

import objcrt "core:sys/darwin/ObjectiveC"
import ns "vendor:darwin/AppKit"

foreign import core_text "system:CoreText.framework"
foreign import core_graphics "system:CoreGraphics.framework"

foreign core_text {
	CTFontManagerRegisterGraphicsFont :: proc "c" (font: rawptr, error: rawptr) -> bool ---
}
foreign core_graphics {
	CGDataProviderCreateWithCFData :: proc "c" (data: rawptr) -> rawptr ---
	CGDataProviderRelease :: proc "c" (provider: rawptr) ---
	CGFontCreateWithDataProvider :: proc "c" (provider: rawptr) -> rawptr ---
	CGFontRelease :: proc "c" (font: rawptr) ---
}

menu_font :: proc() -> ^ns.Object {
	@(static) attempted := false
	if !attempted {
		attempted = true
		bytes := #load("fonts/WorkSans.ttf")
		data := send(^ns.Object, native_class("NSData"), "dataWithBytes:length:", raw_data(bytes), uint(len(bytes)))
		provider := CGDataProviderCreateWithCFData(data)
		if provider != nil {
			defer CGDataProviderRelease(provider)
			font := CGFontCreateWithDataProvider(provider)
			if font != nil {
				CTFontManagerRegisterGraphicsFont(font, nil)
				CGFontRelease(font)
			}
		}
	}
	name := send(^ns.Object, native_class("NSString"), "stringWithUTF8String:", cstring("WorkSans-Regular"))
	return send(^ns.Object, native_class("NSFont"), "fontWithName:size:", name, ns.Float(13))
}

Menu_Choice :: enum {
	None,
	Settings,
	Keep_In_Dock,
	Quit_App,
}

selected_menu_choice: Menu_Choice

menu_selected :: proc "c" (self: ^ns.Object, action: ns.SEL, sender: ^ns.Object) {
	get_tag := cast(proc "c" (_: ^ns.Object, _: ns.SEL) -> int)objc_msgSend
	selected_menu_choice = Menu_Choice(get_tag(sender, objcrt.sel_registerName("tag")))
}

set_menu_item_title :: proc(item: ^ns.Object, title, padded_title: cstring) {
	value := send(^ns.Object, native_class("NSString"), "stringWithUTF8String:", title)
	notify(item, "setTitle:", value)
	if font := menu_font(); font != nil {
		key := send(^ns.Object, native_class("NSString"), "stringWithUTF8String:", cstring("NSFont"))
		attributes := send(^ns.Object, native_class("NSDictionary"), "dictionaryWithObject:forKey:", font, key)
		label := send(^ns.Object, native_class("NSAttributedString"), "alloc")
		text := send(^ns.Object, native_class("NSString"), "stringWithUTF8String:", padded_title)
		label = send(^ns.Object, label, "initWithString:attributes:", text, attributes)
		notify(item, "setAttributedTitle:", label)
		notify(label, "release")
	}
}

show_context_menu :: proc(window: ^ns.Object, app: ^App, kept: bool) -> Menu_Choice {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	action := objcrt.sel_registerName("hoodSelectMenuItem:")
	target_class := objcrt.objc_lookUpClass("HoodMenuTarget")
	if target_class == nil {
		target_class = objcrt.objc_allocateClassPair(objcrt.objc_lookUpClass("NSObject"), "HoodMenuTarget", 0)
		objcrt.class_addMethod(target_class, action, cast(objcrt.IMP)menu_selected, "v@:@")
		objcrt.objc_registerClassPair(target_class)
	}
	target := send(^ns.Object, (^ns.Object)(target_class), "new")
	defer notify(target, "release")
	menu := send(^ns.Object, native_class("NSMenu"), "new")
	defer notify(menu, "release")
	if app != nil && app.bundle_id != "" {
		keep := send(^ns.Object, native_class("NSMenuItem"), "new")
		defer notify(keep, "release")
		set_menu_item_title(keep, "Keep in Dock", "\u00a0\u00a0Keep in Dock\u00a0\u00a0")
		notify(keep, "setTag:", int(Menu_Choice.Keep_In_Dock))
		notify(keep, "setState:", int(1 if kept else 0))
		notify(keep, "setAction:", action)
		notify(keep, "setTarget:", target)
		notify(menu, "addItem:", keep)
		if app.pid != 0 {
			quit := send(^ns.Object, native_class("NSMenuItem"), "new")
			defer notify(quit, "release")
			set_menu_item_title(quit, "Quit the app", "\u00a0\u00a0Quit the app\u00a0\u00a0")
			notify(quit, "setTag:", int(Menu_Choice.Quit_App))
			notify(quit, "setAction:", action)
			notify(quit, "setTarget:", target)
			notify(menu, "addItem:", quit)
		}
		separator := send(^ns.Object, native_class("NSMenuItem"), "separatorItem")
		notify(menu, "addItem:", separator)
	}
	item := send(^ns.Object, native_class("NSMenuItem"), "new")
	defer notify(item, "release")
	set_menu_item_title(item, "Dock Settings", "\u00a0\u00a0Dock Settings\u00a0\u00a0")
	notify(item, "setTag:", int(Menu_Choice.Settings))
	notify(item, "setAction:", action)
	notify(item, "setTarget:", target)
	notify(menu, "addItem:", item)

	view := send(^ns.Object, window, "contentView")
	point := send(ns.Point, window, "mouseLocationOutsideOfEventStream")
	// AppKit handles placement, selection, and dismissal in its menu tracking loop.
	popup := cast(proc "c" (_: ^ns.Object, _: ns.SEL, _: ^ns.Object, _: ns.Point, _: ^ns.Object) -> ns.BOOL)objc_msgSend
	selected_menu_choice = .None
	popup(menu, objcrt.sel_registerName("popUpMenuPositioningItem:atLocation:inView:"), nil, point, view)
	return selected_menu_choice
}
