extends SceneTree

## Renders every SVG in a folder (art options for Mac to choose from) to a PNG
## beside it, and one contact sheet with all of them in file-name order:
##   "<godot console exe>" --headless --path . -s res://tools/render_options.gd -- <folder> <sheet.png> [columns] [size]
## The SVGs use the Cburnett canvas (45 x 45); size is each picture's width in
## pixels (default 160). The sheet's background is grey so white pieces show.

const SVG_SIZE := 45.0
const PAD := 12

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: render_options.gd -- <folder> <sheet.png> [columns] [size]")
		quit(1)
		return
	var folder: String = args[0]
	var sheet_path: String = args[1]
	var cols := int(args[2]) if args.size() > 2 else 4
	var size := int(args[3]) if args.size() > 3 else 160
	var files: Array[String] = []
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".svg"):
			files.append(file)
	files.sort()
	var rows := ceili(files.size() / float(cols))
	var sheet := Image.create((size + PAD) * cols + PAD, (size + PAD) * maxi(rows, 1) + PAD, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.58, 0.58, 0.6))
	for i in files.size():
		var image := Image.new()
		var text := FileAccess.get_file_as_string(folder.path_join(files[i]))
		if image.load_svg_from_string(text, size / SVG_SIZE) != OK:
			push_error("Couldn't render " + files[i])
			continue
		image.convert(Image.FORMAT_RGBA8)
		image.save_png(folder.path_join(files[i].get_basename() + ".png"))
		var at := Vector2i(PAD + (i % cols) * (size + PAD), PAD + (i / cols) * (size + PAD))
		sheet.blend_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), at)
	sheet.save_png(sheet_path)
	print("Saved ", sheet_path, " (", files.size(), " pictures)")
	quit()
