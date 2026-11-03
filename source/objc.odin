package main

import ns "core:sys/darwin/Foundation"

foreign import objc "system:objc"

foreign objc {
	objc_msgSend :: proc "c" (self: ns.id, op: ns.SEL, #c_vararg args: ..any) ---
	objc_msgSend_stret :: proc "c" (self: ns.id, op: ns.SEL, #c_vararg args: ..any) ---
}

// Use fixed signatures so arguments follow the native ABI on Apple Silicon.
send :: proc {
	send_0,
	send_1,
	send_2,
}
notify :: proc {
	notify_0,
	notify_1,
	notify_2,
}

send_0 :: proc($R: typeid, object: ^ns.Object, selector: cstring) -> R {
	call := cast(proc "c" (_: ^ns.Object, _: ns.SEL) -> R)objc_msgSend
	return call(object, ns.sel_registerName(selector))
}

send_1 :: proc($R: typeid, object: ^ns.Object, selector: cstring, arg: $A) -> R {
	call := cast(proc "c" (_: ^ns.Object, _: ns.SEL, _: A) -> R)objc_msgSend
	return call(object, ns.sel_registerName(selector), arg)
}

send_2 :: proc($R: typeid, object: ^ns.Object, selector: cstring, first: $A, second: $B) -> R {
	call := cast(proc "c" (_: ^ns.Object, _: ns.SEL, _: A, _: B) -> R)objc_msgSend
	return call(object, ns.sel_registerName(selector), first, second)
}

send_rect :: proc(object: ^ns.Object, selector: cstring) -> ns.Rect {
	when ODIN_ARCH == .amd64 {
		result: ns.Rect
		call := cast(proc "c" (_: ^ns.Rect, _: ^ns.Object, _: ns.SEL))objc_msgSend_stret
		call(&result, object, ns.sel_registerName(selector))
		return result
	} else {
		return send(ns.Rect, object, selector)
	}
}

notify_0 :: proc(object: ^ns.Object, selector: cstring) {
	call := cast(proc "c" (_: ^ns.Object, _: ns.SEL))objc_msgSend
	call(object, ns.sel_registerName(selector))
}

notify_1 :: proc(object: ^ns.Object, selector: cstring, arg: $A) {
	call := cast(proc "c" (_: ^ns.Object, _: ns.SEL, _: A))objc_msgSend
	call(object, ns.sel_registerName(selector), arg)
}

notify_2 :: proc(object: ^ns.Object, selector: cstring, first: $A, second: $B) {
	call := cast(proc "c" (_: ^ns.Object, _: ns.SEL, _: A, _: B))objc_msgSend
	call(object, ns.sel_registerName(selector), first, second)
}
