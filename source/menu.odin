package main

import ns "core:sys/darwin/Foundation"

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

menu_selected :: proc "c" (self: ^ns.Object, action: ns.SEL, sender: ^ns.Object) {}

show_context_menu :: proc(window: ^ns.Object) -> bool {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	action := ns.sel_registerName("hoodSelectSettings:")
	target_class := ns.objc_lookUpClass("HoodMenuTarget")
	if target_class == nil {
		target_class = ns.objc_allocateClassPair(ns.objc_lookUpClass("NSObject"), "HoodMenuTarget", 0)
		ns.class_addMethod(target_class, action, cast(ns.IMP)menu_selected, "v@:@")
		ns.objc_registerClassPair(target_class)
	}
	target := send(^ns.Object, (^ns.Object)(target_class), "new")
	defer notify(target, "release")
	menu := send(^ns.Object, native_class("NSMenu"), "new")
	defer notify(menu, "release")
	item := send(^ns.Object, native_class("NSMenuItem"), "new")
	defer notify(item, "release")
	title := send(^ns.Object, native_class("NSString"), "stringWithUTF8String:", cstring("Settings"))
	notify(item, "setTitle:", title)
	if font := menu_font(); font != nil {
		key := send(^ns.Object, native_class("NSString"), "stringWithUTF8String:", cstring("NSFont"))
		attributes := send(^ns.Object, native_class("NSDictionary"), "dictionaryWithObject:forKey:", font, key)
		label := send(^ns.Object, native_class("NSAttributedString"), "alloc")
		// AppKit controls the row height. Nonbreaking spaces add horizontal room to the title.
		padded_title := send(
			^ns.Object,
			native_class("NSString"),
			"stringWithUTF8String:",
			cstring("\u00a0\u00a0Settings\u00a0\u00a0"),
		)
		label = send(^ns.Object, label, "initWithString:attributes:", padded_title, attributes)
		notify(item, "setAttributedTitle:", label)
		notify(label, "release")
	}
	notify(item, "setAction:", action)
	notify(item, "setTarget:", target)
	notify(menu, "addItem:", item)

	view := send(^ns.Object, window, "contentView")
	point := send(ns.Point, window, "mouseLocationOutsideOfEventStream")
	// AppKit handles placement, selection, and dismissal in its menu tracking loop.
	popup := cast(proc "c" (_: ^ns.Object, _: ns.SEL, _: ^ns.Object, _: ns.Point, _: ^ns.Object) -> ns.BOOL)objc_msgSend
	return popup(menu, ns.sel_registerName("popUpMenuPositioningItem:atLocation:inView:"), nil, point, view)
}
