extends Node2D

export(PackedScene) var DropTemplate = null

export(NodePath) var camera = null
export(NodePath) var player = null

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

export(NodePath) var Remote_Hit_Drawer = null

# rain area
#export( int ) var Polygon_Point_Count =200


# Member Variables
var rain_direction
var drops = []

var shape
var shape_transform

# manage frames
var Drop_Texture = null

var Hframes = 1
var Vframes = 1
var framesize = Vector2()
var framerects = []
var framesequence = []
var nframe_start = 0
var nframe_drop = 0
var nframe_hit = 0

var screen_radius = 0.0
var screen_drop_length = 0.0
var screen_drop_extend = 0.0
var polygon_areas = []

var cached_viewport_base = Vector2()
var cached_viewport_size = Vector2()

var _remote_hit_drawer = null

# Inner classes
class Drop:
	var pos = Vector2()
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
	func _on_collide( a, b, c, d, e ):
		if a == Physics2DServer.AREA_BODY_REMOVED:
			return
		state = 2
		timer = 0.0
		total_time = 0.0

func _ready():
	set_process(false)
	randomize()
	
	# search for a colision polygon child
	var dropobj = DropTemplate.instance()

	if not dropobj:
		print( get_name(), ": could not find a child rain drop" )
		return
	
	for c in get_children():
		polygon_areas.append([c, calculate_areas(c)])
		pass
	
	var st = get_viewport().get_visible_rect().size
	screen_radius = st.length() * Drop_Radius_Factor
	
	# the rain direction
	rain_direction = Vector2( cos( Drop_Angle * PI / 180 ), sin( Drop_Angle * PI / 180 ) )
	rain_direction = rain_direction.normalized()
	
	# the texture
	Drop_Texture = dropobj.get_texture()
	if not Drop_Texture: return
	var texsize = Drop_Texture.get_size()
	Hframes = dropobj.get_hframes()
	Vframes = dropobj.get_vframes()
	framesize = Vector2( texsize.x / Hframes, texsize.y / Vframes )
	for y in range( Vframes ):
		for x in range( Hframes ):
			framerects.append( Rect2( Vector2( x * framesize.x, y * framesize.y ), framesize ) )
	
	framesize *= Size
	
	if Remote_Hit_Drawer:
		_remote_hit_drawer = get_node(Remote_Hit_Drawer)
		_remote_hit_drawer.texture = Drop_Texture
	
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
	else:
		nframe_hit = 0
	print("[rain] frame sequence: " + str(framesequence))
	print("[rain] frame counts: %d %d %d" % [nframe_start, nframe_drop, nframe_hit])
	
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
	
	call_deferred("initialize")

func initialize():
	randomize()
	var vrect = get_viewport().get_visible_rect()
	var st = vrect.size
	var zoom = Vector2(1.0, 1.0)
	if camera:
		zoom = camera.get_zoom()
	var pp = vrect.position + vrect.size * 0.5
	if player:
		pp = player.get_global_position()
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
	
	print("[rain] initializing drop system with %d drops" % drop_count)
	
	for i in range(drop_count):
		# instance drop
		var d = Drop.new()
		# speed
		d.speed = rand_range( Min_Drop_Speed, Max_Drop_Speed )
		# area
		
		if not Passive:
			d.area = Physics2DServer.area_create()
			Physics2DServer.area_set_space( d.area, get_world_2d().get_space() )
			Physics2DServer.area_add_shape( d.area, shape )
			Physics2DServer.area_set_collision_layer( d.area, get_layer_mask() )
			Physics2DServer.area_set_collision_mask( d.area, get_collision_mask() )
			Physics2DServer.area_set_monitor_callback( d.area, d, "_on_collide" )
		
		d.total_time = Start_Alpha_Time # so that the new drops start with full alpha
		
		random_drop_point(d)
		random_modulate(d)
		
		if d.drop_through:
			d.pos = d.pos + rain_direction * rand_range(0.0, screen_drop_length)
		else:
			d.pos = d.endpos - rain_direction * rand_range(0.0, Drop_Length) #p
		
		shapepos( d )
		drops.append( d )
	
	# start the process
	set_process( true )
	pass

func shapepos( d ):
	if Passive:
		return
	
	var mat = Matrix32( shape_transform )
	mat.o += d.pos + get_pos()
	
	if not Passive:
		Physics2DServer.area_set_transform( d.area, mat )

func random_modulate(d):
	if Frame_Modulate:
		d.col = Frame_Modulate.interpolate(rand_range(0.0, 1.0))

func _process( delta ):
	if camera:
		var vt = camera.get_viewport_transform()
		var zoom = camera.get_zoom()
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
					d.frame += 1
					if d.frame == nframe_start:
						d.state = 1
			else:
				d.frame = nframe_start
				d.state = 1
		if d.state == 1:
			# play drop animation by shifting frames
			d.timer += delta
			if d.timer >= DropAnim_Interval:
				d.timer -= DropAnim_Interval
				d.frame += 1
				if d.frame >= nframe_start + nframe_drop:
					# cycle?
					d.frame = nframe_start
					
			# update old position
			d.oldpos = d.pos
			# compute new position
			d.pos += delta * d.speed * rain_direction

			shapepos( d )

			if d.drop_through:
				if d.pos.y > (cached_viewport_base.y + cached_viewport_size.y) or d.pos.y < (cached_viewport_base.y - cached_viewport_size.y):
					d.state = 3
					if not Drop_Through:
						d.drop_through = false
					pass
			else:
				if ( sign( rain_direction.x ) > 0 and d.pos.x > d.endpos.x ) or \
					( sign( rain_direction.x ) < 0 and d.pos.x < d.endpos.x ) or \
					( sign( rain_direction.y ) > 0 and d.pos.y > d.endpos.y ) or \
					( sign( rain_direction.y ) < 0 and d.pos.y < d.endpos.y ):
					
					d.state = 2
					pass
				
		elif d.state == 2:
			# play coliding animation by shifting frames
			d.timer += delta
			if d.timer >= HitAnim_Interval:
				d.timer -= HitAnim_Interval
				d.frame += 1
				if d.frame >= nframe_start + nframe_drop + nframe_hit:
					# reset drop
					d.state = 3
					d.frame = 0
					d.total_time = 0.0
				else:
					pass
		elif d.state == 3: # reset
			d.state = 0
			
			random_drop_point(d)
			random_modulate(d)
			shapepos(d)
	update()


func _draw():
	for d in drops:
		# check if this drop is to be drawn
		if d.pos.x < cached_viewport_base.x or d.pos.x > ( cached_viewport_base.x + cached_viewport_size.x ) or \
			d.pos.y < cached_viewport_base.y or d.pos.y > ( cached_viewport_base.y + cached_viewport_size.y ):
			continue
		# draw drop
		var c = d.col
		var fac = clamp(d.total_time, 0.0, Start_Alpha_Time) / Start_Alpha_Time
		c.a = c.a * fac
		if d.state == 2 and _remote_hit_drawer:
			_remote_hit_drawer.queue_draw(Rect2(d.pos, framesize), framerects[ framesequence[d.frame] ], c)
			pass
		else:
			draw_texture_rect_region( Drop_Texture, \
				Rect2( d.pos, framesize ), framerects[ framesequence[ d.frame ] ], c )

func random_drop_point(d):
	
#	if polygon_areas.size() > 0:
#		var info = polygon_areas[randi() % polygon_areas.size()]
#		return utils.random_point_in_weighted_areas(info[0], info[1][0], info[1][1])
	
	if not Drop_Through:
		var angle = rand_range(-PI, PI)
		var dir = Vector2(cos(angle), -sin(angle))
		var fac = rand_range(0.0, screen_radius)
		var center = Vector2()
		if camera:
			center = camera.get_camera_screen_center()
		d.endpos = center + dir * fac
		d.pos = d.endpos - rain_direction * Drop_Length
		
		var canDrop = false
		for pa in polygon_areas:
			if is_point_inside_polygon_full(d.endpos, pa[0]):
				canDrop = true
				break
		
		if not canDrop:
			if not Drop_Through_On_Miss:
				d.state = 3
			else:
				d.drop_through = true
	else:
		d.drop_through = true
	
	if d.drop_through:
		d.pos = Vector2(cached_viewport_base.x + rand_range(-screen_drop_extend - Drop_Through_Side_Spread, cached_viewport_size.x + Drop_Through_Side_Spread),\
			cached_viewport_base.y)
		pass

func point_in_any_area(p):
	if polygon_areas.size() > 0:
		for pa in polygon_areas:
			if is_point_inside_polygon(p, pa[0]):
				return true
		return false
	return true

static func calculate_areas(poly):
	var areas = []
	var total_area = 0.0

	var points = poly.get_polygon()
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

static func area_of_triangle(A, B, C):
	return abs(A.x * B.y + A.y * C.x + B.x * C.y - C.x * B.y - C.y * A.x - A.y * B.x) / 2.0

static func is_point_inside_polygon_full( p, poly ):
	# adapted from http://www.ariel.com.au/a/python-point-int-poly.html
	var points = poly.get_polygon()
	var trans = poly.get_global_transform()
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


static func is_point_inside_polygon( p, poly ):
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