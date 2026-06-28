class_name HidefallQrCode
extends RefCounted

const VERSION := 5
const SIZE := 17 + VERSION * 4
const DATA_CODEWORDS := 108
const ECC_CODEWORDS := 26
const QUIET_ZONE := 4
const FORMAT_L := [
	0b111011111000100,
	0b111001011110011,
	0b111110110101010,
	0b111100010011101,
	0b110011000101111,
	0b110001100011000,
	0b110110001000001,
	0b110100101110110
]


static func make_texture(text: String, scale: int = 6) -> Texture2D:
	var modules := make_matrix(text)
	var image_size := (SIZE + QUIET_ZONE * 2) * scale
	var image := Image.create(image_size, image_size, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for y in SIZE:
		for x in SIZE:
			if modules[y][x]:
				_fill_module(image, x + QUIET_ZONE, y + QUIET_ZONE, scale, Color.BLACK)
	return ImageTexture.create_from_image(image)


static func make_matrix(text: String) -> Array:
	var payload := text.to_utf8_buffer()
	if payload.size() > 106:
		push_error("QR payload is too long for Hidefall version 5-L QR code: %d bytes" % payload.size())
		payload = payload.slice(0, 106)
	var modules := []
	var reserved := []
	for y in SIZE:
		var module_row := []
		var reserved_row := []
		for x in SIZE:
			module_row.append(false)
			reserved_row.append(false)
		modules.append(module_row)
		reserved.append(reserved_row)

	_draw_function_patterns(modules, reserved)
	var data := _build_codewords(payload)
	var ecc := _reed_solomon_remainder(data, ECC_CODEWORDS)
	var codewords := data + ecc
	var data_bits := _codewords_to_bits(codewords)
	_draw_codewords(modules, reserved, data_bits)

	var best_modules := modules
	var best_score := 2147483647
	for mask in 8:
		var candidate := _copy_matrix(modules)
		_apply_mask(candidate, reserved, mask)
		_draw_format_bits(candidate, reserved, mask)
		var score := _penalty_score(candidate)
		if score < best_score:
			best_score = score
			best_modules = candidate
	return best_modules


static func _build_codewords(payload: PackedByteArray) -> Array:
	var bits := []
	_append_bits(bits, 0b0100, 4)
	_append_bits(bits, payload.size(), 8)
	for byte_value in payload:
		_append_bits(bits, byte_value, 8)
	var remaining_bits := DATA_CODEWORDS * 8 - bits.size()
	_append_bits(bits, 0, min(4, remaining_bits))
	while bits.size() % 8 != 0:
		bits.append(false)
	var data := []
	for i in range(0, bits.size(), 8):
		var value := 0
		for bit_index in 8:
			value = (value << 1) | (1 if bits[i + bit_index] else 0)
		data.append(value)
	var pad := [0xEC, 0x11]
	var pad_index := 0
	while data.size() < DATA_CODEWORDS:
		data.append(pad[pad_index % 2])
		pad_index += 1
	return data


static func _draw_function_patterns(modules: Array, reserved: Array) -> void:
	_draw_finder(modules, reserved, 0, 0)
	_draw_finder(modules, reserved, SIZE - 7, 0)
	_draw_finder(modules, reserved, 0, SIZE - 7)
	_draw_alignment(modules, reserved, 30, 30)
	for i in range(8, SIZE - 8):
		_set_module(modules, reserved, i, 6, i % 2 == 0, true)
		_set_module(modules, reserved, 6, i, i % 2 == 0, true)
	_set_module(modules, reserved, 8, VERSION * 4 + 9, true, true)
	for i in 9:
		_set_reserved(reserved, 8, i)
		_set_reserved(reserved, i, 8)
	for i in 8:
		_set_reserved(reserved, SIZE - 1 - i, 8)
		_set_reserved(reserved, 8, SIZE - 1 - i)


static func _draw_finder(modules: Array, reserved: Array, left: int, top: int) -> void:
	for y in range(-1, 8):
		for x in range(-1, 8):
			var xx := left + x
			var yy := top + y
			if xx < 0 or yy < 0 or xx >= SIZE or yy >= SIZE:
				continue
			var dark: bool = x >= 0 and x <= 6 and y >= 0 and y <= 6 and (x == 0 or x == 6 or y == 0 or y == 6 or (x >= 2 and x <= 4 and y >= 2 and y <= 4))
			_set_module(modules, reserved, xx, yy, dark, true)


static func _draw_alignment(modules: Array, reserved: Array, center_x: int, center_y: int) -> void:
	for y in range(-2, 3):
		for x in range(-2, 3):
			var dark: bool = max(abs(x), abs(y)) != 1
			_set_module(modules, reserved, center_x + x, center_y + y, dark, true)


static func _draw_codewords(modules: Array, reserved: Array, bits: Array) -> void:
	var bit_index := 0
	var upward := true
	var x := SIZE - 1
	while x > 0:
		if x == 6:
			x -= 1
		for i in SIZE:
			var y := SIZE - 1 - i if upward else i
			for dx in 2:
				var xx := x - dx
				if reserved[y][xx]:
					continue
				modules[y][xx] = bit_index < bits.size() and bits[bit_index]
				bit_index += 1
		upward = not upward
		x -= 2


static func _apply_mask(modules: Array, reserved: Array, mask: int) -> void:
	for y in SIZE:
		for x in SIZE:
			if reserved[y][x]:
				continue
			if _mask_bit(mask, x, y):
				modules[y][x] = not modules[y][x]


static func _mask_bit(mask: int, x: int, y: int) -> bool:
	match mask:
		0:
			return (x + y) % 2 == 0
		1:
			return y % 2 == 0
		2:
			return x % 3 == 0
		3:
			return (x + y) % 3 == 0
		4:
			return (int(y / 2) + int(x / 3)) % 2 == 0
		5:
			return ((x * y) % 2 + (x * y) % 3) == 0
		6:
			return (((x * y) % 2 + (x * y) % 3) % 2) == 0
		_:
			return (((x + y) % 2 + (x * y) % 3) % 2) == 0


static func _draw_format_bits(modules: Array, reserved: Array, mask: int) -> void:
	var bits: int = FORMAT_L[mask]
	for i in 15:
		var dark: bool = ((bits >> i) & 1) == 1
		if i < 6:
			_set_module(modules, reserved, 8, i, dark, true)
		elif i == 6:
			_set_module(modules, reserved, 8, 7, dark, true)
		elif i == 7:
			_set_module(modules, reserved, 8, 8, dark, true)
		elif i == 8:
			_set_module(modules, reserved, 7, 8, dark, true)
		else:
			_set_module(modules, reserved, 14 - i, 8, dark, true)
	for i in 8:
		_set_module(modules, reserved, SIZE - 1 - i, 8, ((bits >> i) & 1) == 1, true)
	for i in range(8, 15):
		_set_module(modules, reserved, 8, SIZE - 15 + i, ((bits >> i) & 1) == 1, true)


static func _reed_solomon_remainder(data: Array, degree: int) -> Array:
	var generator := _reed_solomon_generator(degree)
	var result := []
	for _i in degree:
		result.append(0)
	for byte_value in data:
		var factor: int = int(byte_value) ^ int(result.pop_front())
		result.append(0)
		for i in degree:
			result[i] = int(result[i]) ^ _gf_multiply(generator[i], factor)
	return result


static func _reed_solomon_generator(degree: int) -> Array:
	var result := [1]
	for i in degree:
		var next := []
		for _j in result.size() + 1:
			next.append(0)
		for j in result.size():
			next[j] = int(next[j]) ^ _gf_multiply(result[j], 1)
			next[j + 1] = int(next[j + 1]) ^ _gf_multiply(result[j], _gf_pow(2, i))
		result = next
	result.remove_at(0)
	return result


static func _gf_pow(value: int, power: int) -> int:
	var result := 1
	for _i in power:
		result = _gf_multiply(result, value)
	return result


static func _gf_multiply(left: int, right: int) -> int:
	var result := 0
	var a := left
	var b := right
	while b > 0:
		if (b & 1) != 0:
			result ^= a
		a <<= 1
		if (a & 0x100) != 0:
			a ^= 0x11D
		b >>= 1
	return result & 0xFF


static func _codewords_to_bits(codewords: Array) -> Array:
	var bits := []
	for value in codewords:
		_append_bits(bits, int(value), 8)
	return bits


static func _append_bits(bits: Array, value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append(((value >> i) & 1) == 1)


static func _penalty_score(modules: Array) -> int:
	var score := 0
	for y in SIZE:
		score += _line_penalty(modules[y])
	for x in SIZE:
		var column := []
		for y in SIZE:
			column.append(modules[y][x])
		score += _line_penalty(column)
	for y in SIZE - 1:
		for x in SIZE - 1:
			var color: bool = modules[y][x]
			if modules[y][x + 1] == color and modules[y + 1][x] == color and modules[y + 1][x + 1] == color:
				score += 3
	var dark_count := 0
	for y in SIZE:
		for x in SIZE:
			if modules[y][x]:
				dark_count += 1
	var percent := dark_count * 100 / (SIZE * SIZE)
	score += int(abs(percent - 50) / 5) * 10
	return score


static func _line_penalty(line: Array) -> int:
	var score := 0
	var run_color: bool = line[0]
	var run_length := 1
	for i in range(1, line.size()):
		if line[i] == run_color:
			run_length += 1
			if run_length == 5:
				score += 3
			elif run_length > 5:
				score += 1
		else:
			run_color = line[i]
			run_length = 1
	for i in range(0, line.size() - 10):
		var pattern := [true, false, true, true, true, false, true, false, false, false, false]
		var matches := true
		for j in 11:
			if line[i + j] != pattern[j]:
				matches = false
				break
		if matches:
			score += 40
	return score


static func _set_module(modules: Array, reserved: Array, x: int, y: int, dark: bool, is_reserved: bool) -> void:
	modules[y][x] = dark
	if is_reserved:
		reserved[y][x] = true


static func _set_reserved(reserved: Array, x: int, y: int) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		reserved[y][x] = true


static func _copy_matrix(source: Array) -> Array:
	var copy := []
	for row in source:
		copy.append(row.duplicate())
	return copy


static func _fill_module(image: Image, module_x: int, module_y: int, scale: int, color: Color) -> void:
	var start_x := module_x * scale
	var start_y := module_y * scale
	for y in scale:
		for x in scale:
			image.set_pixel(start_x + x, start_y + y, color)
