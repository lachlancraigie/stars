class_name CrewMember
extends Resource

# --- Identity ---
@export var crew_id: String = ""
@export var crew_name: String = ""
@export var role: String = ""  # "captain" | "engineer" | "medic" | "scientist" | "general"

# --- Base attributes (set at generation, very slow to change) ---
@export_group("Physical")
@export var strength: float = 0.5
@export var endurance: float = 0.5
@export var dexterity: float = 0.5
@export var constitution: float = 0.5

@export_group("Mental")
@export var intelligence: float = 0.5
@export var focus: float = 0.5
@export var willpower: float = 0.5      # governs fear resistance and panic recovery
@export var empathy: float = 0.5

@export_group("Professional")
@export var primary_skill: String = ""
@export var secondary_skills: Array[String] = []
@export var experience_level: int = 1   # 1–5

# --- Dynamic needs (change each tick) ---
@export_group("Needs")
@export var hunger: float = 0.0         # 0 = satiated,  1 = starving
@export var fatigue: float = 0.0        # 0 = rested,    1 = exhausted
@export var fear: float = 0.0           # 0 = calm,      1 = terrified
@export var pain: float = 0.0           # 0 = healthy,   1 = severe pain
@export var loneliness: float = 0.0     # 0 = connected, 1 = isolated
@export var boredom: float = 0.0        # 0 = engaged,   1 = listless

# --- Health and state ---
@export_group("Health")
@export var morale: float = 1.0                 # composite; recomputed each tick
@export var physical_health: float = 1.0
@export var psychological_health: float = 1.0
@export var is_alive: bool = true

@export_group("State")
@export var current_state: String = "idle"      # see CrewStateMachine constants
@export var location: String = ""               # room_id

# --- Personality (set at generation, very slow to change) ---
@export_group("Personality")
@export var traits: Array[String] = []   # e.g. "cautious", "reckless", "compassionate", "paranoid"
@export var fears: Array[String] = []    # e.g. "confined_spaces", "alien_biology", "death"
@export var values: Array[String] = []   # e.g. "loyalty", "survival", "mission_completion"
@export var goals: Array[String] = []    # short/medium/long-term; updated procedurally

# --- Social ---
@export_group("Social")
@export var ai_trust: float = 0.5              # 0 = distrustful of ship AI, 1 = fully trusting
@export var relationships: Dictionary = {}      # crew_id -> RelationshipState (stub for RelationshipGraph)
