class_name InputCommand
extends RefCounted

## World-space unit vector the nose should turn toward.
var aim_dir := Vector3.FORWARD
## Rate command, -1..1. Held, not a target position.
var throttle_delta := 0.0
## Manual roll, -1..1. Positive banks right.
var roll := 0.0
var fire := false
