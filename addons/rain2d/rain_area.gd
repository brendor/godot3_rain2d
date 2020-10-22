extends Node2D

export(NodePath) var Navigation_Root = null

export(MultiMesh) var DropMesh = null
export(Texture) var DropTexture = null
export(int) var DropTextureVFrames = 1

export(PackedScene) var DropTemplate = null

# defines which objects are water
export(String) var Water_Group = "water" 

export(float) var Drop_Radius_Factor = 1.0
export(float) var Drops_Per_10_Px = 2.0
export(float) var Drop_Length = 800.0
export(float) var Drop_Angle = 67.0

export(Vector2) var Size = Vector2(2.0, 2.0)
export(Vector2) var Size_Variation = Vector2(1.0, 1.0)

export(bool) var Drop_Through = false # every drop is a drop-through
export(bool) var Drop_Through_On_Miss = true
export(float) var Drop_Through_Side_Spread = 600.0

export(bool) var Passive = true
export(Gradient) var Frame_Modulate = null

export(float) var Start_Alpha_Time = 1.0

export(float) var Min_Drop_Speed = 350.0
export(float) var Max_Drop_Speed = 400.0

export(bool) var Use_StartAnim = false
export(int) var StartAnim_StartFrame = 0
export(int) var StartAnim_EndFrame = 0
export(float) var StartAnim_Interval = 0.1

export(bool) var Use_DropAnim = false
export(int) var DropAnim_StartFrame = 0
export(int) var DropAnim_EndFrame = 0

export(float) var DropAnim_Interval = 0.1
export(bool) var Use_HitAnim = false
export(int) var HitAnim_StartFrame = 0
export(int) var HitAnim_EndFrame = 0
export(float) var HitAnim_Interval = 0.1

export(int) var HitWaterAnim_StartFrame = 0
export(int) var HitWaterAnim_EndFrame = 0
export(float) var HitWaterAnim_Interval = 0.1

export(NodePath) var Remote_Hit_Drawer = null

# Member Variables
var rain_direction
var drops = []

var shape
var shape_transform

var framesequence = []
var nframe_start = 0
var nframe_drop = 0
var nframe_hit = 0
var nframe_hit_water = 0

var screen_radius = 0.0
var screen_drop_length = 0.0
var screen_drop_extend = 0.0
var polygon_areas = []

var cached_viewport_base = Vector2()
var cached_viewport_size = Vector2()
var cached_viewport_center = Vector2()

var _multimesh_instancer = null
var _multimesh_instancer_ground = null

# Inner classes
class Drop:
	var instanceID = 0
	var trans = Transform2D()
	var oldpos = Vector2()
	var speed = 1.0
	var area = RID()
	var state = 0
	var frame = 0
	var timer = 0.0
	var total_time = 0.0
	var endpos = Vector2()
	var col = Color(1.0, 1.0, 1.0, 1.0)
	var drop_through = false
	var water = false
	func _on_collide( a, b, c, d, e ):
		if a == Physics2DServer.AREA_BODY_REMOVED:
			return
		state = 2
		timer = 0.0
		total_time = 0.0
		water = false

func _ready():
	set_process(false)
	randomize()

	for c in get_children():
		if c is CollisionPolygon2D:
			polygon_areas.append([c, calculate_areas(c.get_polygon())])
		pass
		
	if Navigation_Root:
		var nr = get_node(Navigation_Root)
		for cp in nr.get_children():
			if cp is NavigationPolygonInstance:
				for poly_id in range(cp.navpoly.get_outline_count()):
					var outline = cp.navpoly.get_outline(poly_id)
					polygon_areas.append([outline, calculate_areas(outline)])
	
	var st = get_viewport().get_visible_rect().size
	screen_radius = st.length() * Drop_Radius_Factor
	
	# the rain direction
	rain_direction = Vector2( cos( Drop_Angle * PI / 180 ), sin( Drop_Angle * PI / 180 ) )
	rain_direction = rain_direction.normalized()
	
	# the frames
	if Use_StartAnim:
		framesequence += range( StartAnim_StartFrame, StartAnim_EndFrame + 1 )
		nframe_start = StartAnim_EndFrame + 1 - StartAnim_StartFrame
	else:
		nframe_start = 0
	if Use_DropAnim:
		framesequence += range( DropAnim_StartFrame, DropAnim_EndFrame + 1 )
		nframe_drop = DropAnim_EndFrame + 1 - DropAnim_StartFrame
	else:
		framesequence.append( DropAnim_StartFrame )
		nframe_drop = 1
	if Use_HitAnim:
		framesequence += range( HitAnim_StartFrame, HitAnim_EndFrame + 1 )
		nframe_hit = HitAnim_EndFrame + 1 - HitAnim_StartFrame
		
		framesequence += range( HitWaterAnim_StartFrame, HitWaterAnim_EndFrame + 1 )
		nframe_hit_water = HitWaterAnim_EndFrame + 1 - HitWaterAnim_StartFrame
	else:
		nframe_hit = 0
		nframe_hit_water = 0
	
	print("[rain] frame sequence: " + str(framesequence))
	print("[rain] frame counts: %d %d %d %d" % [nframe_start, nframe_drop, nframe_hit, nframe_hit_water])
	
	# search for a colision polygon child
	if DropTemplate:
		var dropobj = DropTemplate.instance()
		# get the drop collision shape
		var children = dropobj.get_children()
		# look for the sprite and the collision shape
		for child in children:
			if child is CollisionShape2D:
				shape = child.get_shape()
				shape_transform = child.get_transform()
				break
		if not shape:
			Passive = true
			print("[rain] No drop collision shape - Passive mode")
		else:
			print("[rain] Drop shape transform: " + str(shape_transform))
		dropobj.queue_free()
	else:
		Passive = true
	
	#call_deferred("initialize")
	
	print("rain ready!")

func _enter_tree():
	initialize()

func initialize():
	print("rain initializing...")
	
	randomize()
	
	update_viewport()
	
	var _sin = sin(deg2rad(Drop_Angle))
	if _sin != 0.0:
		screen_drop_length = cached_viewport_size.y / sin(deg2rad(Drop_Angle))
		screen_drop_extend = screen_drop_length * cos(deg2rad(Drop_Angle))
	else:
		screen_drop_length = cached_viewport_size.y
		screen_drop_extend = 0.0
	
	# create a bunch of drops
	var drop_count = (screen_radius / 10.0) * Drops_Per_10_Px
	
	print("[rain] initializing multimesh")
	
	_multimesh_instancer = MultiMeshInstance2D.new()
	_multimesh_instancer.name = "rain_instancer"
	self.add_child(_multimesh_instancer)
	_multimesh_instancer.set_owner(self)
	_multimesh_instancer.multimesh = DropMesh.duplicate()
	_multimesh_instancer.multimesh.instance_count = drop_count
	_multimesh_instancer.multimesh.visible_instance_count = -1
	_multimesh_instancer.texture = DropTexture
	_multimesh_instancer.material = material
	_multimesh_instancer.material.set_shader_param("frame_count", DropTextureVFrames)
	
	var rhd = get_node(Remote_Hit_Drawer)
	if rhd:
		_multimesh_instancer_ground = MultiMeshInstance2D.new()
		_multimesh_instancer_ground.name = "rain_instancer_remote"
		rhd.add_child(_multimesh_instancer_ground)
		_multimesh_instancer_ground.set_owner(rhd)
		_multimesh_instancer_ground.multimesh = DropMesh.duplicate()
		_multimesh_instancer_ground.multimesh.instance_count = drop_count
		_multimesh_instancer_ground.multimesh.visible_instance_count = -1
		_multimesh_instancer_ground.texture = DropTexture
		_multimesh_instancer_ground.material = material
		_multimesh_instancer_ground.material.set_shader_param("frame_count", DropTextureVFrames)
	
	print("[rain] initializing drop system with %d drops" % drop_count)
	
	for i in range(drop_count):
		# instance drop
		var d = Drop.new()
		d.instanceID = i
		
		# speed
		d.speed = rand_range( Min_Drop_Speed, Max_Drop_Speed )
		# area
		
		if not Passive and shape:
			d.area = Physics2DServer.area_create()
			Physics2DServer.area_set_space( d.area, get_world_2d().get_space() )
			Physics2DServer.area_add_shape( d.area, shape )
			Physics2DServer.area_set_collision_layer( d.area, self.collision_layer )
			Physics2DServer.area_set_collision_mask( d.area, self.collision_mask )
			Physics2DServer.area_set_monitor_callback( d.area, d, "_on_collide" )
		
		d.total_time = Start_Alpha_Time # so that the new drops start with full alpha
		
		set_color(d, Color.white)
		set_frame(d, 0)
		
		random_drop_point(d)
		random_modulate(d)
		
		if d.drop_through:
			d.trans.origin = d.trans.origin + rain_direction * rand_range(0.0, screen_drop_length)
		else:
			d.trans.origin = d.endpos - rain_direction * rand_range(0.0, Drop_Length) #p
		
		shapepos(d)
		drops.append(d)
		
		update_position(d)
	
	# start the process
	set_process( true )
	
	print("rain initialized!")
	pass

func shapepos(d):
	if Passive:
		return
	
	var mat = Transform2D(shape_transform)
	mat.o += d.trans.origin + position
	
	if not Passive:
		Physics2DServer.area_set_transform( d.area, mat )

func random_modulate(d):
	if Frame_Modulate:
		set_color(d, Frame_Modulate.interpolate(rand_range(0.0, 1.0)))

func set_color(d, c):
	d.col = c
	if _multimesh_instancer_ground and d.state == 2:
		_multimesh_instancer.multimesh.set_instance_color(d.instanceID, Color(0.0, 0.0, 0.0, 0.0))
		#_multimesh_instancer.multimesh.set_instance_transform_2d(d.instanceID, Transform2D(0.0, Vector2(0.0, 0.0)))
		_multimesh_instancer_ground.multimesh.set_instance_color(d.instanceID, c)
	else:
		_multimesh_instancer.multimesh.set_instance_color(d.instanceID, c)
		if _multimesh_instancer_ground:
			_multimesh_instancer_ground.multimesh.set_instance_color(d.instanceID, Color(0.0, 0.0, 0.0, 0.0))

func set_color_remote(d, c):
	if not _multimesh_instancer_ground:
		return
	_multimesh_instancer_ground.multimesh.set_instance_color(d.instanceID, c)

func set_frame(d, f):
	d.frame = f
	var c = Color(framesequence[f], 0.0, 0.0, 0.0)
	
	if _multimesh_instancer_ground and d.state == 2:
		_multimesh_instancer_ground.multimesh.set_instance_custom_data(d.instanceID, c)
	else:
		_multimesh_instancer.multimesh.set_instance_custom_data(d.instanceID, c)

func update_position(d):
	if _multimesh_instancer_ground and d.state == 2:
		_multimesh_instancer_ground.multimesh.set_instance_transform_2d(d.instanceID, d.trans)
		_multimesh_instancer_ground.multimesh.visible_instance_count = -1
	else:
		_multimesh_instancer.multimesh.set_instance_transform_2d(d.instanceID, d.trans)
		_multimesh_instancer.multimesh.visible_instance_count = -1

func update_viewport():
	var vtrans = get_canvas_transform()
	var top_left = -vtrans.get_origin() / vtrans.get_scale()
	cached_viewport_base = top_left
	var vsize = get_viewport_rect().size
	cached_viewport_size = vsize / vtrans.get_scale()
	cached_viewport_center = top_left + 0.5 * cached_viewport_size 
	pass

func _process( delta ):
	
	update_viewport()
	
	_multimesh_instancer.multimesh.visible_instance_count = 0
	if _multimesh_instancer_ground:
		_multimesh_instancer_ground.multimesh.visible_instance_count = 0
	
	var newpos
	for d in drops:
		d.total_time += delta
		
		if d.state == 0:
			if Use_StartAnim:
				# play start animation by shifting frames
				d.timer += delta
				if d.timer >= StartAnim_Interval:
					d.timer -= StartAnim_Interval
					set_frame(d, d.frame + 1)
					if d.frame == nframe_start:
						d.state = 1
			else:
				set_frame(d, nframe_start)
				d.state = 1
			update_position(d)
		if d.state == 1:
			# play drop animation by shifting frames
			d.timer += delta
			if d.timer >= DropAnim_Interval:
				d.timer -= DropAnim_Interval
				set_frame(d, d.frame + 1)
				if d.frame >= nframe_start + nframe_drop:
					# cycle?
					set_frame(d, nframe_start)
					
			# update old position
			d.oldpos = d.trans
			# compute new position
			d.trans.origin += delta * d.speed * rain_direction
			
			shapepos(d)

			if d.drop_through:
				if d.trans.origin.y > (cached_viewport_base.y + cached_viewport_size.y) or d.trans.origin.y < (cached_viewport_base.y - cached_viewport_size.y):
					d.state = 3
					set_color(d, d.col)
					if not Drop_Through:
						d.drop_through = false
			else:
				if ( sign( rain_direction.x ) > 0 and d.trans.origin.x > d.endpos.x ) or \
					( sign( rain_direction.x ) < 0 and d.trans.origin.x < d.endpos.x ) or \
					( sign( rain_direction.y ) > 0 and d.trans.origin.y > d.endpos.y ) or \
					( sign( rain_direction.y ) < 0 and d.trans.origin.y < d.endpos.y ):
					
					d.timer = 0.0
					d.state = 2
			
					set_color(d, d.col)
					if d.water:
						set_frame(d, HitWaterAnim_StartFrame)
					else:
						set_frame(d, HitAnim_StartFrame)
			update_position(d)
		elif d.state == 2:
			# play coliding animation by shifting frames
			d.timer += delta

			if not d.water:
				if d.timer >= HitAnim_Interval:
					d.timer = 0.0
					if d.frame + 1 >= nframe_start + nframe_drop + nframe_hit:
						# reset drop
						d.state = 3
						d.total_time = 0.0
					else:
						set_frame(d, d.frame + 1)
			else:
				if d.timer >= HitWaterAnim_Interval:
					d.timer = 0.0
					if d.frame + 1 >= nframe_start + nframe_drop + nframe_hit + nframe_hit_water:
						# reset drop
						d.state = 3
						d.total_time = 0.0
					else:
						set_frame(d, d.frame + 1)
			update_position(d)
		elif d.state == 3: # reset
			# set remote color to blank
			#set_color_remote(d, d.col)
			
			# reset state
			d.state = 0
			
			# reset front frame
			set_frame(d, 0)
			# randomize front color
			random_modulate(d)
			
			# randomize and set front position
			random_drop_point(d)
			shapepos(d)
			update_position(d)
			pass
			

func random_drop_point(d):
	d.water = false
	
	var variation = rand_range(Size_Variation.x, Size_Variation.y)
	d.trans.x.x = Size.x * variation
	d.trans.y.y = Size.y * variation
	
	if not Drop_Through:
		var angle = rand_range(-PI, PI)
		var dir = Vector2(cos(angle), -sin(angle))
		var fac = rand_range(0.0, screen_radius)
		var center = Vector2()
		
		d.endpos = cached_viewport_center + dir * fac
		d.trans.origin = d.endpos - rain_direction * Drop_Length
		
		var intersect = Geometry.line_intersects_line_2d(d.endpos, - rain_direction * Drop_Length, cached_viewport_base, Vector2.RIGHT)
		if intersect is Vector2:
			d.trans.origin = intersect
		
		var canDrop = false
		for pa in polygon_areas:
			if pa[0] is CollisionPolygon2D:
				if is_point_inside_polygon_full(d.endpos, pa[0].get_polygon(), pa[0].get_global_position()):
					canDrop = true
					d.water = pa[0].is_in_group(Water_Group)
					break
			else:
				if is_point_inside_polygon_full(d.endpos, pa[0], Transform2D.IDENTITY):
					canDrop = true
					d.water = false
					break
		
		if not canDrop:
			if not Drop_Through_On_Miss:
				d.state = 3
			else:
				d.drop_through = true
		else:
			d.drop_through = false
	else:
		d.drop_through = true
	
	if d.drop_through:
		d.trans.origin = Vector2(cached_viewport_base.x + rand_range(-screen_drop_extend - Drop_Through_Side_Spread, cached_viewport_size.x + Drop_Through_Side_Spread),\
			cached_viewport_base.y)
#	else:
#		d.trans.origin.y = cached_viewport_base.y

func point_in_any_area(p):
	if polygon_areas.size() > 0:
		for pa in polygon_areas:
			if is_point_inside_polygon(p, pa[0]):
				return true
		return false
	return true

func calculate_areas(points):
	var areas = []
	var total_area = 0.0

	if points.size() < 3:
		return [areas, 0.0]

	for i in range(points.size() - 2):
		var a = points[i]
		var b = points[i + 1]
		var c = points[i + 2]
		var area = area_of_triangle(a, b, c)
		total_area += area
		areas.append(area)
	return [areas, total_area]

func area_of_triangle(A, B, C):
	return abs(A.x * B.y + A.y * C.x + B.x * C.y - C.x * B.y - C.y * A.x - A.y * B.x) / 2.0
	
func is_point_inside_polygon_full( p, points, trans ):
	# adapted from http://www.ariel.com.au/a/python-point-int-poly.html
	#var points = poly.get_polygon()
	#var trans = poly.get_global_transform()
	var n = points.size()
	var inside = false
	var p1 = trans * points[0]
	var p2 = Vector2()
	var xinters = 0.0
	for i in range( n + 1 ):
		p2 = trans * points[ i % n ]
		if p.y > min( p1.y, p2.y ):
			if p.y <= max( p1.y, p2.y ):
				if p.x <= max( p1.x, p2.x ):
					if p1.y != p2.y:
						xinters = ( p.y - p1.y ) * ( p2.x - p1.x ) / ( p2.y - p1.y ) + p1.x
					if p1.x == p2.x or p.x <= xinters:
						inside = not inside
		p1 = p2
	return inside


func is_point_inside_polygon( p, poly ):
	var points = poly.get_polygon()
	if points.size() < 3:
		return false
	var trans = poly.get_global_transform()
	for i in range(points.size() - 2):
		var a = trans * points[i]
		var b = trans * points[i + 1]
		var c = trans * points[i + 2]
		if Geometry.point_is_inside_triangle(p, a, b, c):
			return true
	return false
