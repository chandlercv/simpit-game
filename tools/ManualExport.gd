extends Node
## Export both of the ship's documents to print-ready HTML, which an external
## browser then prints to PDF (see tools/build_manuals.ps1 — Godot has no PDF
## writer of its own).
##
##   godot --headless res://tools/ManualExport.tscn ++ [out_dir]
##
## `out_dir` defaults to build/manuals, relative to the project root. It is build
## output and is gitignored: the documents' source of truth is the two catalogs,
## and a committed PDF would be a third copy of every figure in them.
##
## WHY THIS RUNS IN GODOT rather than parsing the .gd files from Python: the
## chapters are written with binding placeholders, and resolving them needs the
## live Input Map. Instantiating the real ManualViewer off-tree and calling its
## own _resolve() is what makes the printed page name the same controls the
## in-game page does — the same trick PilotManualSmoke uses to audit them.
##
## The BBCode dialect both documents use is only [b], [i] and [color=#rrggbb]
## (see ManualViewer), so the converter below is a short scan rather than a
## parser. Anything richer would need one, and would be a reason to reach for a
## real markup instead.

const ManualContentScript := preload("res://scenes/displays/PilotManualContent.gd")
const TerminalContentScript := preload("res://scenes/displays/TerminalProceduresContent.gd")
const ViewerScript := preload("res://scenes/displays/ManualViewer.gd")

const DEFAULT_OUT_DIR := "build/manuals"

## One entry per document, mirroring TitleCard.DOCUMENTS so the printed masthead
## matches the one on the reader.
const DOCUMENTS := [
	{
		"file": "pilots-manual",
		"title": "SV KESTREL — PILOT'S MANUAL",
		"subtitle": "SALVAGE CUTTER · OPERATING INSTRUCTIONS AND PROCEDURES",
		"chapters": ManualContentScript,
	},
	{
		"file": "terminal-procedures",
		"title": "TERMINAL PROCEDURES",
		"subtitle": "ISSUED BY HARBOUR CONTROL · NOT A BUILDER PUBLICATION",
		"chapters": TerminalContentScript,
	},
]

## Print styling. Deliberately a light page rather than the reader's dark one —
## this is going onto paper. The body face MUST be monospace: every table in both
## documents is laid out with dot leaders, which only line up in a fixed pitch.
const STYLE := """
@page { size: A4; margin: 18mm 16mm 20mm 16mm; }
* { box-sizing: border-box; }
body {
  font-family: "DejaVu Sans Mono", "Consolas", "Courier New", monospace;
  font-size: 9.5pt; line-height: 1.45; color: #14181f; background: #fff;
  margin: 0;
}
h1 { font-size: 20pt; letter-spacing: 0.06em; margin: 0 0 4pt 0; }
h2 { font-size: 13pt; letter-spacing: 0.04em; margin: 0 0 2pt 0;
     border-bottom: 1px solid #14181f; padding-bottom: 3pt; }
.masthead { font-size: 8pt; letter-spacing: 0.08em; color: #566; margin: 0 0 24pt 0; }
.titlepage { height: 90vh; display: flex; flex-direction: column; justify-content: center; }
.titlepage .note { font-size: 8pt; color: #566; margin-top: 24pt; }
.contents { page-break-after: always; }
.contents ol { padding-left: 1.6em; }
.contents .group { font-weight: bold; letter-spacing: 0.06em; margin: 12pt 0 2pt 0; }
.chapter { page-break-before: always; }
.chapter .group { font-size: 8pt; letter-spacing: 0.08em; color: #566; margin: 0 0 6pt 0; }
.body { white-space: pre-wrap; margin-top: 8pt; }
b { font-weight: 700; }
i { font-style: italic; }
"""

## The reader's palette is tuned for a dark screen; on paper the same roles need
## darker ink to stay legible. Mapped by hex so the content files stay the one
## place the palette is chosen.
const PRINT_INK := {
	"#66ccff": "#0b4f7a",  # sub-heading
	"#f2705c": "#a32014",  # WARNING
	"#f2bf59": "#8a5a00",  # CAUTION
	"#59f28c": "#0a6b34",  # a required condition, and a resolved binding
	"#8c9eb8": "#4a5568",  # NOTE and subordinate text
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else DEFAULT_OUT_DIR
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	var error := DirAccess.make_dir_recursive_absolute(out_dir)
	if error != OK and not DirAccess.dir_exists_absolute(out_dir):
		printerr("MANUAL EXPORT: cannot create %s (%d)" % [out_dir, error])
		get_tree().quit(1)
		return

	# One viewer for both documents: it holds no per-document state that _resolve
	# reads, and building it twice would only cost frames.
	var viewer: ManualViewer = ViewerScript.new()
	var written: Array[String] = []
	for document: Dictionary in DOCUMENTS:
		var path: String = out_dir.path_join("%s.html" % document["file"])
		var html := _render(document, viewer)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("MANUAL EXPORT: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
			viewer.free()
			get_tree().quit(1)
			return
		file.store_string(html)
		file.close()
		written.append(path)
	viewer.free()

	for path in written:
		print("  wrote: %s" % path)
	print("MANUAL EXPORT: %d DOCUMENT(S) WRITTEN" % written.size())
	get_tree().quit(0)


# --- Rendering ---------------------------------------------------------------

func _render(document: Dictionary, viewer: ManualViewer) -> String:
	var chapters: Array = document["chapters"].CHAPTERS
	var title: String = document["title"]
	var out := PackedStringArray()
	out.append("<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">")
	out.append("<title>%s</title>\n<style>%s</style></head><body>\n" % [_escape(title), STYLE])

	# Title page.
	out.append("<section class=\"titlepage\">")
	out.append("<h1>%s</h1>" % _escape(title))
	out.append("<p class=\"masthead\">%s</p>" % _escape(String(document["subtitle"])))
	out.append("<p class=\"note\">Controls are named as they were assigned when this "
			+ "copy was printed. Re-assign at CONTROLS (F7); the copy carried on the "
			+ "ship always names the live binding.</p>")
	out.append("</section>\n")

	# Contents, grouped exactly as the reader's list is.
	out.append("<section class=\"contents\"><h2>CONTENTS</h2>")
	var last_group := ""
	for chapter: Dictionary in chapters:
		var group := String(chapter.get("group", ""))
		if group != last_group:
			out.append("<p class=\"group\">%s</p>" % _escape(group))
			last_group = group
		out.append("<p>%s</p>" % _escape(String(chapter["title"])))
	out.append("</section>\n")

	# One chapter per page, in catalog order.
	for chapter: Dictionary in chapters:
		out.append("<section class=\"chapter\">")
		out.append("<p class=\"group\">%s</p>" % _escape(String(chapter.get("group", ""))))
		out.append("<h2>%s</h2>" % _escape(String(chapter["title"])))
		# The viewer's own resolver, so a printed step names whatever the pilot
		# actually has bound rather than a key this file guessed.
		var body: String = viewer._resolve(String(chapter["body"]))
		out.append("<div class=\"body\">%s</div>" % _bbcode_to_html(body))
		out.append("</section>\n")

	out.append("</body></html>\n")
	return "".join(out)


## The whole BBCode dialect both documents use, converted in one pass: [b], [i]
## and [color=#rrggbb]. Unknown tags are left as escaped literal text so they
## show up on the page instead of vanishing — the same choice ManualViewer makes
## for an unknown placeholder, and for the same reason.
func _bbcode_to_html(text: String) -> String:
	var out := PackedStringArray()
	var rest := text
	while true:
		var open := rest.find("[")
		if open == -1:
			out.append(_escape(rest))
			break
		var close := rest.find("]", open)
		if close == -1:
			out.append(_escape(rest))
			break
		out.append(_escape(rest.substr(0, open)))
		var tag := rest.substr(open + 1, close - open - 1)
		var html := _tag_to_html(tag)
		out.append(html if not html.is_empty() else _escape("[%s]" % tag))
		rest = rest.substr(close + 1)
	return "".join(out)


func _tag_to_html(tag: String) -> String:
	match tag:
		"b":
			return "<b>"
		"/b":
			return "</b>"
		"i":
			return "<i>"
		"/i":
			return "</i>"
		"/color":
			return "</span>"
	if tag.begins_with("color="):
		var hex := tag.substr(6)
		return "<span style=\"color:%s\">" % PRINT_INK.get(hex, hex)
	return ""


func _escape(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
