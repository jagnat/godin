package godin

slice_find :: proc(slice : []$T, val : T) -> int {
	for s, i in slice {
		if s == val do return i
	}
	return -1
}

slice_contains :: proc(slice : []$T, val : T) -> bool {
	return slice_find(slice, val) != -1
}