extends Node3D

# ---------- CONFIGURACIÓN ----------
@export var capture_directory := "./capture" # 📁 ruta de salida

# ---------- ENUM FORMATO ----------
enum ImageFormat {
	PNG,
	JPG,
	WEBP,
	XPM
}

# ---------- CONSTANTES XPM ----------
const XPM_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,-./:;<=>?@[]^_"


# ---------- UI ----------
@onready var width_spin: SpinBox = $Control/RenderWidth
@onready var height_spin: SpinBox = $Control/RenderHeigth
@onready var captures_spin: SpinBox = $Control/NCaptures
@onready var format_option: OptionButton = $Control/ImageFormat
@onready var capture_button: Button = $Control/Button

# ---------- RENDER ----------
@onready var viewport: SubViewport = $SubViewport
@onready var render_scene: Node3D = $SubViewport/RenderScene

# ---------- VARIABLES ----------
@export var render_width := 512
@export var render_height := 512
@export var capture_count := 36

var image_format: ImageFormat = ImageFormat.PNG

# ---------- READY ----------
func _ready():
	if capture_button.pressed.is_connected(_on_button_pressed):
		capture_button.pressed.disconnect(_on_button_pressed)
	capture_button.pressed.connect(_on_button_pressed)

	# Configurar OptionButton
	format_option.clear()
	format_option.add_item("PNG", ImageFormat.PNG)
	format_option.add_item("JPG", ImageFormat.JPG)
	format_option.add_item("WEBP", ImageFormat.WEBP)
	format_option.add_item("XPM", ImageFormat.XPM)
	format_option.select(ImageFormat.PNG)

	ensure_capture_folder()

# ---------- BOTÓN ----------
func _on_button_pressed():
	print("🔄 Iniciando captura 360°...")

	render_width = int(width_spin.value)
	render_height = int(height_spin.value)
	capture_count = int(captures_spin.value)
	image_format = format_option.get_selected_id()

	viewport.size = Vector2i(render_width, render_height)

	await capture_360()

# ---------- CARPETA ----------
func ensure_capture_folder():
	var base_dir := capture_directory.get_base_dir()
	var folder_name := capture_directory.get_file()

	var dir = DirAccess.open(base_dir)
	if dir == null:
		push_error("❌ Ruta inválida: " + base_dir)
		return

	if not dir.dir_exists(folder_name):
		dir.make_dir(folder_name)

func clear_capture_folder():
	var dir = DirAccess.open(capture_directory)
	if dir == null:
		return

	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if not dir.current_is_dir():
			dir.remove(file)
		file = dir.get_next()
	dir.list_dir_end()

# ---------- CAPTURA ----------
func capture_360():
	ensure_capture_folder()
	clear_capture_folder()

	render_scene.rotation = Vector3.ZERO
	var step_degrees := 360.0 / capture_count

	for i in range(capture_count):
		var angle := step_degrees * i

		render_scene.rotation_degrees.y = angle

		await get_tree().process_frame
		await get_tree().process_frame

		var image: Image = viewport.get_texture().get_image()

		if image_format == ImageFormat.JPG:
			image.convert(Image.FORMAT_RGB8)

		var base_path := "%s/capture_angle_%03d" % [capture_directory, int(angle)]
		save_image(image, base_path)

	print("🎉 Captura 360° completada")
	print("📂 Guardado en:", ProjectSettings.globalize_path(capture_directory))

# ---------- GUARDAR ----------
func save_image(image: Image, base_path: String):
	match image_format:
		ImageFormat.PNG:
			image.save_png(base_path + ".png")
		ImageFormat.JPG:
			image.save_jpg(base_path + ".jpg", 0.95)
		ImageFormat.WEBP:
			image.save_webp(base_path + ".webp")
		ImageFormat.XPM:
			save_xpm_rgba(image, base_path + ".xpm")


func xpm_code(index: int, chars_per_pixel: int) -> String:
	var base := XPM_CHARS.length()
	var code := ""

	for i in range(chars_per_pixel):
		code = XPM_CHARS[index % base] + code
		index = int(index / base)

	return code

func save_xpm_rgb(image: Image, path: String):
	image.convert(Image.FORMAT_RGB8)
	var w: int = image.get_width()
	var h: int = image.get_height()
	# 1. Recoger colores
	var palette := {}  # key: color hex, value: int
	var palette_list := []
	var pixels := []

	for y in range(h):
		var row := []
		for x in range(w):
			var c: Color = image.get_pixel(x, y)
			var key: String = "%02X%02X%02X" % [
				int(c.r * 255),
				int(c.g * 255),
				int(c.b * 255)
			]
			if not palette.has(key):
				palette[key] = palette.size()
				palette_list.append(key)
			row.append(key)
		pixels.append(row)
	# 2. Calcular chars_per_pixel
	var base: int = XPM_CHARS.length()
	var color_count: int = palette.size()
	var chars_per_pixel: int = 1
	while pow(base, chars_per_pixel) < color_count:
		chars_per_pixel += 1
	# 3. Escribir archivo
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("❌ No se pudo escribir XPM en: " + ProjectSettings.globalize_path(path))
		return
	file.store_line("/* XPM */")
	file.store_line("static char * image_xpm[] = {")
	file.store_line("\"%d %d %d %d\"," % [w, h, color_count, chars_per_pixel])
	# Paleta
	for key in palette_list:
		var index: int = palette[key]
		var code: String = xpm_code(index, chars_per_pixel)
		file.store_line("\"%s c #%s\"," % [code, key])
	# Píxeles
	for y in range(h):
		var line: String = ""
		for x in range(w):
			var color_key: String = pixels[y][x]
			var idx: int = palette[color_key]
			line += xpm_code(idx, chars_per_pixel)
		file.store_line("\"%s\"," % line)
	file.store_line("};")
	file.close()

func save_xpm_rgba(image: Image, path: String):
	image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()
	var palette := {}          # key -> index
	var palette_list := []     # index -> key
	var pixels := []

	for y in range(h):
		var row := []
		for x in range(w):
			var c := image.get_pixel(x, y)

			var key: String
			if c.a <= 0.0:
				key = "None"
			else:
				key = "%02X%02X%02X%02X" % [
					int(c.r * 255),
					int(c.g * 255),
					int(c.b * 255),
					int(c.a * 255)
				]
			if not palette.has(key):
				palette[key] = palette.size()
				palette_list.append(key)
			row.append(key)
		pixels.append(row)
		
	var base := XPM_CHARS.length()
	var color_count := palette.size()
	var chars_per_pixel := 1
	
	while pow(base, chars_per_pixel) < color_count:
		chars_per_pixel += 1
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("❌ No se pudo escribir XPM")
		return
	file.store_line("/* XPM */")
	file.store_line("static char * image_xpm[] = {")
	file.store_line("\"%d %d %d %d\"," % [w, h, color_count, chars_per_pixel])
	# Paleta
	for key in palette_list:
		var code := xpm_code(palette[key], chars_per_pixel)
		if key == "None":
			file.store_line("\"%s c None\"," % code)
		else:
			file.store_line("\"%s c #%s\"," % [code, key])
	# Píxeles
	for y in range(h):
		var line := ""
		for x in range(w):
			var idx: int = palette[pixels[y][x]]
			line += xpm_code(idx, chars_per_pixel)
		file.store_line("\"%s\"," % line)
	file.store_line("};")
	file.close()
