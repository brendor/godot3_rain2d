extends Node2D

export(MultiMesh) var DropMesh = null
export(Texture) var DropTexture = null
export(int) var DropTextureVFrames = 1

export(PackedScene) var DropTemplate = null

export(float) var Drop_Radius_Factor = 1.0
export(float) var Drops_Per_10_Px = 2.0
export(float) var Drop_Length = 800.0
export(float) var Drop_Angle = 67.0

export(Vector2) var Size = Vector2(2.0, 2.0)

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

# rain area
#export( int ) var Polygon_Point_Count =200


# Member Variables
var rain_direction
var drops = []

var shape
var shape_transform

# manage frames
#var Drop_Texture = null

var Hframes = 1
var Vframes = 1
#var framesize = Vector2()
#var framerects = []
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

var _remote_hit_drawer = null

var _multimesh_instancer = null

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
		polygon_areas.append([c, utils.calculate_areas(c)])
		pass
	
	var st = get_viewport().get_visible_rect().size
	screen_radius = st.length() * Drop_Radius_Factor
	
	# the rain direction
	rain_direction = Vector2( cos( Drop_Angle * PI / 180 ), sin( Drop_Angle * PI / 180 ) )
	rain_direction = rain_direction.normalized()
	
	# the texture
#	Drop_Texture = dropobj.get_texture()
#	if not Drop_Texture: return
#	var texsize = Drop_Texture.get_size()
#	Hframes = dropobj.get_hframes()
#	Vframes = dropobj.get_vframes()
#	framesize = Vector2( texsize.x / Hframes, texsize.y / Vframes )
#	for y in range( Vframes ):
#		for x in range( Hframes ):
#			framerects.append( Rect2( Vector2( x * framesize.x, y * framesize.y ), framesize ) )
#
#	framesize *= Size
	
	if Remote_Hit_Drawer:
		_remote_hit_drawer = get_node(Remote_Hit_Drawer)
		#_remote_hit_drawer.texture = Drop_Texture
	
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
	
	logger.info("[rain] frame sequence: " + str(framesequence))
	logger.info("[rain] frame counts: %d %d %d %d" % [nframe_start, nframe_drop, nframe_hit, nframe_hit_water])
	
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
			logger.info("[rain] No drop collision shape - Passive mode")
		else:
			logger.info("[rain] Drop shape transform: " + str(shape_transform))
		dropobj.queue_free()
	
	call_deferred("initialize")
	
	logger.info("rain ready!")

func initialize():
	logger.info("rain initializing...")
	
	randomize()
	var vrect = get_viewport().get_visible_rect()
	var st = vrect.size
	
	var zoom = Vector2(1.0, 1.0)
	var pp = vrect.position + vrect.size * 0.5
	
	if global.player:
		pp = global.player.get_global_position()
		zoom = global.player.camera.get_zoom()
		
	cached_viewport_size = Vector2(st.x * zoom.x, st.y * zoom.y)
	cached_viewport_base = pp - cached_viewport_size * 0.5
	
	var _sin = sin(deg2rad(Drop_Angle))
	if _sin != 0.0:
		screen_drop_length = cached_viewport_size.y / sin(deg2rad(Drop_Angle))
		screen_drop_extend = screen_drop_length * cos(deg2rad(Drop_Angle))
	else:
		screen_drop_length = cached_viewport_size.y
		screen_drop_extend = 0.0
	
	# create a bunch of drops
	var drop_count = (screen_radius / 10.0) * Drops_Per_10_Px
	
	logger.info("[rain] initializing multimesh")
	
	_multimesh_instancer = MultiMeshInstance2D.new()
	_multimesh_instancer.name = "rain_instancer"
	utils.reparent(_multimesh_instancer, _remote_hit_drawer if _remote_hit_drawer else self)
	_multimesh_instancer.multimesh = DropMesh
	_multimesh_instancer.multimesh.instance_count = drop_count
	_multimesh_instancer.texture = DropTexture
	_multimesh_instancer.material = material
	#_multimesh_instancer.material.set_shader_param("frame_size", 1.0 / float(framesequence.size()))
	_multimesh_instancer.material.set_shader_param("frame_count", DropTextureVFrames)
	
	logger.info("[rain] initializing drop system with %d drops" % drop_count)
	
	for i in range(drop_count):
		# instance drop
		var d = Drop.new()
		d.instanceID = i
		d.trans.x.x = Size.x
		d.trans.y.y = Size.x
		
		# speed
		d.speed = rand_range( Min_Drop_Speed, Max_Drop_Speed )
		# area
		
		if not Passive:
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
	
	logger.info("rain initialized!")
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
	_multimesh_instancer.multimesh.set_instance_color(d.instanceID, c)

func set_frame(d, f):
	d.frame = f
	var c = Color(framesequence[f], 0.0, 0.0, 0.0)
	_multimesh_instancer.multimesh.set_instance_custom_data(d.instanceID, c)

func update_position(d):
	_multimesh_instancer.multimesh.set_instance_transform_2d(d.instanceID, d.trans)

func _process( delta ):
	if global.player:
		var vt = global.player.camera.get_viewport_transform()
		var zoom = global.player.camera.get_zoom()
		cached_viewport_base = -vt.origin * zoom
	
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
			
			shapepos( d )

			if d.drop_through:
				if d.trans.origin.y > (cached_viewport_base.y + cached_viewport_size.y) or d.trans.origin.y < (cached_viewport_base.y - cached_viewport_size.y):
					d.state = 3
					if not Drop_Through:
						d.drop_through = false
					pass
			else:
				if ( sign( rain_direction.x ) > 0 and d.trans.origin.x > d.endpos.x ) or \
					( sign( rain_direction.x ) < 0 and d.trans.origin.x < d.endpos.x ) or \
					( sign( rain_direction.y ) > 0 and d.trans.origin.y > d.endpos.y ) or \
					( sign( rain_direction.y ) < 0 and d.trans.origin.y < d.endpos.y ):
					
					d.timer = 0.0
					d.state = 2
					
					if d.water:
						set_frame(d, HitWaterAnim_StartFrame)
					else:
						set_frame(d, HitAnim_StartFrame)
					pass
				
		elif d.state == 2:
			# play coliding animation by shifting frames
			d.timer += delta
			if not d.water:
				if d.timer >= HitAnim_Interval:
					d.timer = 0.0
					set_frame(d, d.frame + 1)
					if d.frame >= nframe_start + nframe_drop + nframe_hit:
						# reset drop
						d.state = 3
						set_frame(d, 0)
						d.total_time = 0.0
			else:
				if d.timer >= HitWaterAnim_Interval:
					d.timer = 0.0
					set_frame(d, d.frame + 1)
					if d.frame >= nframe_start + nframe_drop + nframe_hit + nframe_hit_water:
						# reset drop
						d.state = 3
						set_frame(d, 0)
						d.total_time = 0.0
		elif d.state == 3: # reset
			d.state = 0
			
			random_drop_point(d)
			random_modulate(d)
			shapepos(d)
		update_position(d)
	#update()


#func _draw():
#	for d in drops:
#		# check if this drop is to be drawn
#		if d.trans.x < cached_viewport_base.x or d.trans.x > ( cached_viewport_base.x + cached_viewport_size.x ) or \
#			d.trans.y < cached_viewport_base.y or d.trans.y > ( cached_viewport_base.y + cached_viewport_size.y ):
#			continue
#		# draw drop
#		var c = d.col
#		var fac = clamp(d.total_time, 0.0, Start_Alpha_Time) / Start_Alpha_Time
#		c.a = c.a * fac
#		if d.state == 2 and _remote_hit_drawer:
#			_remote_hit_drawer.queue_draw(Rect2(d.trans, framesize), framerects[ framesequence[d.frame] ], c)
#			pass
#		else:
#			draw_texture_rect_region( Drop_Texture, \
#				Rect2( d.trans, framesize ), framerects[ framesequence[ d.frame ] ], c )

func random_drop_point(d):
	d.water = false
	
	if not Drop_Through:
		var angle = rand_range(-PI, PI)
		var dir = Vector2(cos(angle), -sin(angle))
		var fac = rand_range(0.0, screen_radius)
		var center = Vector2()
		if global.player:
			center = global.player.camera.get_camera_screen_center()
		d.endpos = center + dir * fac
		d.trans.origin = d.endpos - rain_direction * Drop_Length
		
		var canDrop = false
		for pa in polygon_areas:
			if utils.is_point_inside_polygon_full(d.endpos, pa[0]):
				canDrop = true
				d.water = pa[0].is_in_group("water")
				break
		
		if not canDrop:
			if not Drop_Through_On_Miss:
				d.state = 3
			else:
				d.drop_through = true
	else:
		d.drop_through = true
	
	if d.drop_through:
		d.trans.origin = Vector2(cached_viewport_base.x + rand_range(-screen_drop_extend - Drop_Through_Side_Spread, cached_viewport_size.x + Drop_Through_Side_Spread),\
			cached_viewport_base.y)
		pass

func point_in_any_area(p):
	if polygon_areas.size() > 0:
		for pa in polygon_areas:
			if utils.is_point_inside_polygon(p, pa[0]):
				return true
		return false
	return true

	
