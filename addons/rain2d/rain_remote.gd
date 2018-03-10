extends Node2D

var texture = null

var _draw_queue = []

func queue_draw(rect, frame, color):
	_draw_queue.append([rect, frame, color])
	pass

func _process(delta):
    update()

func _draw():
	for d in _draw_queue:
		draw_texture_rect_region(texture, d[0], d[1], d[2])
	_draw_queue.clear()
	pass