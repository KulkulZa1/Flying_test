class_name Config
extends RefCounted

# --- Flight ---
const MIN_SPEED := 40.0             # m/s at idle throttle
const MAX_SPEED := 180.0            # m/s at full throttle
const STALL_SPEED := 45.0           # m/s below which the nose sags
const THROTTLE_RATE := 0.8          # throttle units per second
const ENGINE_RESPONSE := 0.9        # 1/s, exponential approach to target speed
const GRAVITY := 9.81               # m/s^2

# --- Turning ---
const MAX_TURN_RATE := 1.8          # rad/s at best turn speed
const BEST_TURN_SPEED := 90.0       # m/s
const MIN_TURN_SCALE := 0.25        # turn authority floor when slow
const HIGH_SPEED_TURN_FLOOR := 0.6  # turn authority floor when fast
const AUTO_BANK_GAIN := 2.5         # bank angle per rad/s of yaw
const MAX_BANK := 1.3               # rad, about 75 degrees
const BANK_RESPONSE := 3.0          # 1/s, how fast bank chases its target
const BANK_SERVO_LIMIT := 2.4       # rad of bank beyond which the servo stops levelling
const BANK_SERVO_FADE := 0.6        # rad over which its authority fades to zero
const MANUAL_ROLL_RATE := 2.5       # rad/s
const SAG_RATE := 1.2               # rad/s of nose drop at zero speed
const AIM_CONE_DEG := 35.0          # max aim offset from the nose
const GROUND_CLEARANCE := 3.0       # m

# --- World ---
const WORLD_SIZE := 8000.0          # m across
const TERRAIN_RES := 64.0           # m per grid cell
const TERRAIN_MAX_HEIGHT := 900.0   # m
const TERRAIN_SEED := 1337
const TERRAIN_FREQUENCY := 0.0006
const BOUNDARY_SOFT_START := 3600.0 # m from centre
const BOUNDARY_STRENGTH := 2.0      # how hard aim is pulled back inside

# --- Camera ---
const CAM_DIST := 18.0
const CAM_HEIGHT := 6.0
const CAM_LAG := 0.12               # seconds
const CAM_LOOK_AHEAD := 40.0        # m ahead of the nose
const CAM_FOV_MIN := 70.0
const CAM_FOV_MAX := 85.0

# --- Start state ---
const START_ALTITUDE := 600.0
const START_THROTTLE := 0.6
const START_CLEARANCE := 250.0      # m of air guaranteed under a spawn

# --- Input ---
const FORCE_TOUCH_UI := false       # set true to exercise the touch layout on desktop
const TOUCH_STICK_RADIUS := 110.0   # px of drag for full deflection
const AIM_DEADZONE := 0.04          # fraction of half-height; below this, no command
