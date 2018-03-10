tool
extends EditorPlugin

var edited_object = null

const rain_script = preload("rain_area.gd")

func get_name(): 
	return "rain"

func _enter_tree():
    add_custom_type("Rain2D", "Node2D", rain_script, preload("icon.png"))


func _exit_tree():
    remove_custom_type("Rain2D")

func handles(o):
	if o.get_script() == rain_script:
		return true
	else:
		return false

func edit(o):
    edited_object = o

func make_visible(b):
    pass
