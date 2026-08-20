class_name TrackQueryResult

var initialized: bool = false
var segment_index: int = 0
var segment_t: int = 0         
var progress: int = 0         
var height: int = 0           
var half_width: int = 0      
var surface_kind: int = Track.Surface.ASPHALTE
var lateral_offset: int = 0   
var closest_x: int = 0        
var closest_z: int = 0
var forward_x: int = 0         
var forward_z: int = Fixed.ONE
var right_x: int = Fixed.ONE    
var right_z: int = 0

func reset() -> void:
	initialized = false
	segment_index = 0
	segment_t = 0
	progress = 0
	surface_kind = Track.Surface.ASPHALTE
