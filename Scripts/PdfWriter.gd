class_name PdfWriter
extends RefCounted

# Minimal PDF 1.4 document assembler shared by the build-plan export (main.gd)
# and the What-If report (what_if_machine.gd). Each caller builds its own PDF
# object strings ("N 0 obj << ... >> ... endobj", numbered from 1) since their
# page layouts differ; this stitches them into a valid document with the
# cross-reference table, trailer and EOF marker that both exporters previously
# duplicated inline, plus the identical text-escaping helper.

static func escape_text(value: String) -> String:
	return value.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


static func assemble(objects: Array[String]) -> PackedByteArray:
	var pdf := "%PDF-1.4\n"
	var offsets: Array[int] = [0]
	for object in objects:
		offsets.append(pdf.to_utf8_buffer().size())
		pdf += object + "\n"

	var xref_offset := pdf.to_utf8_buffer().size()
	pdf += "xref\n0 %d\n" % offsets.size()
	pdf += "0000000000 65535 f \n"
	for i in range(1, offsets.size()):
		pdf += "%010d 00000 n \n" % offsets[i]

	pdf += "trailer << /Size %d /Root 1 0 R >>\n" % offsets.size()
	pdf += "startxref\n%d\n%%%%EOF" % xref_offset
	return pdf.to_utf8_buffer()
