extends RefCounted

static func draw(canvas: CanvasItem, center: Vector2, direction: int) -> void:
	var forward := Vector2.UP.rotated(direction * PI * 0.5)
	var side := forward.rotated(PI * 0.5)
	canvas.draw_rect(Rect2(center - Vector2(21,21),Vector2(42,42)),Color("#263d40"))
	canvas.draw_rect(Rect2(center - Vector2(19,19),Vector2(38,38)),Color("#637b78"),false,3)
	canvas.draw_line(center - forward * 17,center,Color("#dec58c"),5)
	for axis: Vector2 in [forward,side]:
		var color := Color("#9be5bb") if axis == forward else Color("#efb86d")
		canvas.draw_line(center,center + axis * 12,color,4)
		var tip: Vector2 = center + axis * 19
		var across := axis.rotated(PI * 0.5)
		canvas.draw_colored_polygon(PackedVector2Array([tip,tip - axis * 8 + across * 5,tip - axis * 8 - across * 5]),color)
	canvas.draw_circle(center,6,Color("#233438"))
	canvas.draw_line(center - side * 5 - forward * 3,center + side * 5 - forward * 3,Color("#e7cc8d"),2)
	canvas.draw_line(center - side * 4 - forward * 2,center + forward * 3,Color("#e7cc8d"),2)
	canvas.draw_line(center + side * 4 - forward * 2,center + forward * 3,Color("#e7cc8d"),2)
