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
const CAM_FOV_MIN := 60.0           # vertical; about 91 degrees horizontal at 16:9
const CAM_FOV_MAX := 75.0           # vertical; about 107 degrees horizontal at 16:9

# --- Start state ---
const START_ALTITUDE := 600.0
const START_THROTTLE := 0.6
const START_CLEARANCE := 250.0      # m of air guaranteed under a spawn

# --- Input ---
const FORCE_TOUCH_UI := false       # set true to exercise the touch layout on desktop
const TOUCH_STICK_RADIUS := 110.0   # px of drag for full deflection
const AIM_DEADZONE := 0.04          # fraction of half-height; below this, no command

# --- Combat ---
const BULLET_SPEED := 600.0         # m/s
const FIRE_RATE := 12.0             # rounds per second
const BULLET_DAMAGE := 8.0
const BULLET_LIFETIME := 2.5        # s
const HIT_RADIUS := 6.0             # m, roughly the jet's span
const MUZZLE_FORWARD := 5.0         # m ahead of the model origin
const PLAYER_HP := 100.0
const ENEMY_HP := 30.0

# --- AI ---
const ATTACK_CONE_DEG := 12.0
const ATTACK_RANGE := 600.0         # m
const MIN_SEPARATION := 120.0       # m, below which the AI breaks off
const BREAK_TIME := 2.5             # s
const REPOSITION_ALTITUDE := 450.0  # m, floor the AI climbs back to
const AI_THROTTLE := 0.85
const AIM_JITTER_START_DEG := 8.0
const AIM_JITTER_END_DEG := 2.0

# --- Waves ---
const WAVE_GAP := 3.0               # s between waves
const MAX_WAVE_SIZE := 6
const JITTER_RAMP_WAVES := 10
const SPAWN_RADIUS := 2200.0        # m from the player
const SPAWN_ALTITUDE := 700.0       # m
