extends Node

# MusicManager (autoload) — mood-driven ambient soundtrack.
#
# Source material: docs/music-direction.md §2's mood taxonomy, 78 MP3s hand-generated
# under assets/music/<mood>/<mood>_<NN>.mp3 (9 moods). That tree is GITIGNORED (large
# generated audio, not every clone has it) and therefore has no reliable .import
# metadata — resource load() cannot be trusted against it. Streams are instead built
# from raw bytes at runtime, the same technique CrewMemberNode already uses for its
# gitignored dialogue MP3s (scripts/crew/crew_member_node.gd VOICE_DIR / _play_voice_line).
#
# Mood decision reads ScenarioDirector.effective_heat() (the Overseer's one difficulty
# dial), GameState.scenario_tone, ScenarioRunner.active_scenarios (concurrency + pressure
# axis), IntruderSystem.active_intruders() and a handful of EventBus signals. Nothing here
# mutates any of that state — read-only, EventBus/autoload-only per CLAUDE.md's
# architecture rules.
#
# Env hooks: SHIPAI_MUSIC=0 disables the whole system (no scan, no players, no signals).
# SHIPAI_MUSIC_DEBUG=1 logs every scan result, mood decision and track pick.

# --- Mood folder names (docs/music-direction.md §2 table — exact contract) ---
const MOOD_CALM: String = "calm_routine"
const MOOD_LOW_TENSION: String = "low_tension_unease"
const MOOD_TENSE: String = "tense_crisis"
const MOOD_COMBAT: String = "combat_danger"
const MOOD_AFTERMATH: String = "aftermath_somber"
const MOOD_EERIE: String = "eerie_derelict"
const MOOD_OVERSEER: String = "overseer_ai_motif"
const MOOD_MENU: String = "main_menu_title"          # scanned for completeness; no in-game
const MOOD_VICTORY: String = "victory_arrival"        # driver selects it today (title-screen only)

const KNOWN_MOODS: Array[String] = [
	MOOD_CALM, MOOD_LOW_TENSION, MOOD_TENSE, MOOD_COMBAT, MOOD_AFTERMATH,
	MOOD_EERIE, MOOD_OVERSEER, MOOD_MENU, MOOD_VICTORY,
]

# Moods that bypass the switch-rate hysteresis in both directions (spec: "don't switch
# moods more than once per ~25s except for the death/victory overrides").
const IMMEDIATE_MOODS: Array[String] = [MOOD_AFTERMATH, MOOD_VICTORY]

const MUSIC_ROOT: String = "res://assets/music/"

# --- Baseline heat bands (docs/music-direction.md §2) ---
const HEAT_LOW_TENSION_MIN: float = 0.2
const HEAT_TENSE_MIN: float = 0.4
const HEAT_COMBAT_MIN: float = 0.75
const COMBAT_CONCURRENT_SCENARIOS_MIN: int = 2

# --- eerie_derelict gate: dread tone band + a mystery/bio axis scenario active ---
const EERIE_TONE_MIN: float = 0.45
const EERIE_TONE_MAX: float = 0.9
const EERIE_AXES: Array[String] = ["mystery", "bio"]

# --- Overrides ---
const AFTERMATH_COOLDOWN_SECONDS: float = 45.0   # how long crew_died holds aftermath_somber

# --- Pacing / mixing ---
const EVAL_INTERVAL_SECONDS: float = 5.0   # periodic re-evaluation cadence ("every few seconds")
const HYSTERESIS_SECONDS: float = 25.0     # min gap between non-override mood switches
const CROSSFADE_SECONDS: float = 3.0       # 2-4s crossfade between beds
const BED_VOLUME_DB: float = -12.0         # "modest volume" per spec
const SILENT_VOLUME_DB: float = -40.0
const ANTI_REPEAT_ATTEMPTS: int = 8        # retries when picking a random track, avoiding immediate repeat

var current_mood: String = ""              # "" until the first decision lands (forces an immediate pick)

var _enabled: bool = false
var _debug: bool = false
var _moods: Dictionary = {}                # mood name -> Array[String] of res:// file paths
var _clock: float = 0.0                    # free-running real-time clock (Engine delta, pause-independent)
var _eval_accum: float = 0.0
var _last_switch_time: float = 0.0
var _aftermath_until: float = -1.0
var _victory_active: bool = false
var _last_track_path: String = ""

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_index: int = 0                 # 0 -> _player_a is foreground, 1 -> _player_b


func _ready() -> void:
	_debug = OS.get_environment("SHIPAI_MUSIC_DEBUG") == "1"
	if OS.get_environment("SHIPAI_MUSIC") == "0":
		if _debug:
			print("[MUSIC] disabled via SHIPAI_MUSIC=0")
		return
	_scan_music()
	if not _enabled:
		return
	_setup_players()
	EventBus.crew_died.connect(_on_crew_died)
	EventBus.scenario_ended.connect(_on_scenario_ended)
	EventBus.mission_completed.connect(_on_mission_completed)
	EventBus.recent_event.connect(_on_recent_event)
	EventBus.ai_core_status_changed.connect(func(_old, _new): _apply_decision())
	EventBus.intruder_spawned.connect(func(_id, _room, _visible): _apply_decision())
	EventBus.intruder_killed.connect(func(_id, _room): _apply_decision())
	_apply_decision()  # current_mood == "" -> always bypasses hysteresis, picks the first bed


func _process(delta: float) -> void:
	if not _enabled:
		return
	_clock += delta
	_eval_accum += delta
	if _eval_accum >= EVAL_INTERVAL_SECONDS:
		_eval_accum = 0.0
		_apply_decision()


# ---------------------------------------------------------------------------
# Scan (repo-clone-safe: assets/music/ is gitignored, may not exist at all)
# ---------------------------------------------------------------------------

func _scan_music() -> void:
	if DirAccess.open(MUSIC_ROOT) == null:
		_disable("assets/music/ not found")
		return
	var moods_found: int = 0
	var total_tracks: int = 0
	for mood: String in KNOWN_MOODS:
		var dir_path: String = MUSIC_ROOT + mood + "/"
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			continue
		var files: Array[String] = []
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".mp3"):
				files.append(dir_path + fname)
			fname = dir.get_next()
		dir.list_dir_end()
		if not files.is_empty():
			files.sort()
			_moods[mood] = files
			moods_found += 1
			total_tracks += files.size()
	if moods_found == 0 or total_tracks == 0:
		_disable("assets/music/ present but empty")
		return
	_enabled = true
	if _debug:
		print("[MUSIC] scan complete: %d moods, %d tracks" % [moods_found, total_tracks])


func _disable(reason: String) -> void:
	_enabled = false
	push_warning("MusicManager: %s — soundtrack disabled (expected on repo clones without generated audio)." % reason)


func _setup_players() -> void:
	var bus_name: String = "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"
	_player_a = AudioStreamPlayer.new()
	_player_a.name = "MusicPlayerA"
	_player_a.bus = bus_name
	_player_a.volume_db = SILENT_VOLUME_DB
	add_child(_player_a)
	_player_a.finished.connect(_on_player_finished.bind(_player_a))

	_player_b = AudioStreamPlayer.new()
	_player_b.name = "MusicPlayerB"
	_player_b.bus = bus_name
	_player_b.volume_db = SILENT_VOLUME_DB
	add_child(_player_b)
	_player_b.finished.connect(_on_player_finished.bind(_player_b))


func _active_player() -> AudioStreamPlayer:
	return _player_a if _active_index == 0 else _player_b


func _inactive_player() -> AudioStreamPlayer:
	return _player_b if _active_index == 0 else _player_a


# ---------------------------------------------------------------------------
# Mood decision (re-evaluated on EVAL_INTERVAL_SECONDS + the key signals above)
# ---------------------------------------------------------------------------

func _decide_mood() -> String:
	if _victory_active:
		return MOOD_VICTORY
	if _clock < _aftermath_until:
		return MOOD_AFTERMATH
	if GameState.ai_core_status != "online":
		return MOOD_OVERSEER
	if _eerie_condition():
		return MOOD_EERIE
	return _baseline_mood()


func _baseline_mood() -> String:
	var h: float = ScenarioDirector.effective_heat()
	var concurrent: int = ScenarioRunner.active_scenarios.size()
	var intruders_present: bool = not IntruderSystem.active_intruders().is_empty()
	if h >= HEAT_COMBAT_MIN or concurrent >= COMBAT_CONCURRENT_SCENARIOS_MIN or intruders_present:
		return MOOD_COMBAT
	# docs/music-direction.md §2: calm_routine is the "no active scenario, all
	# systems green" cruising state — NOT purely a heat band. The Overseer's
	# NEUTRAL heat is 0.5 (mid tense_crisis band by threshold alone), so without
	# this clause a fresh boot starts audibly tense before anything has happened.
	if concurrent == 0 and GameState.reactor_online and GameState.life_support_online:
		return MOOD_CALM
	if h >= HEAT_TENSE_MIN:
		return MOOD_TENSE
	if h >= HEAT_LOW_TENSION_MIN:
		return MOOD_LOW_TENSION
	return MOOD_CALM


func _eerie_condition() -> bool:
	var tone: float = GameState.scenario_tone
	if tone < EERIE_TONE_MIN or tone > EERIE_TONE_MAX:
		return false
	return _any_active_axis_in(EERIE_AXES)


func _any_active_axis_in(axes: Array[String]) -> bool:
	for instance_id: String in ScenarioRunner.active_scenarios:
		var instance: Dictionary = ScenarioRunner.active_scenarios[instance_id]
		var sid: String = String(instance.get("scenario_id", ""))
		if _scenario_axis(sid) in axes:
			return true
	return false


# Mirrors ScenarioRunner._scenario_axis() (private there) using its public
# BESPOKE_SCENARIO_AXIS const + ScenarioCatalog.defs() rather than duplicating the
# lookup table — kept in sync automatically since both read the same source.
func _scenario_axis(scenario_id: String) -> String:
	if ScenarioRunner.BESPOKE_SCENARIO_AXIS.has(scenario_id):
		return String(ScenarioRunner.BESPOKE_SCENARIO_AXIS[scenario_id])
	return String(ScenarioCatalog.defs(scenario_id).get("pressure_axis", ""))


func _apply_decision() -> void:
	if not _enabled:
		return
	var desired: String = _decide_mood()
	if desired == current_mood:
		return
	var bypass: bool = current_mood == "" or desired in IMMEDIATE_MOODS or current_mood in IMMEDIATE_MOODS
	if not bypass and (_clock - _last_switch_time) < HYSTERESIS_SECONDS:
		return
	_switch_mood(desired)


func _switch_mood(new_mood: String) -> void:
	if _debug:
		print("[MUSIC] mood: %s -> %s (heat=%.2f effective=%.2f tone=%.2f ai_core=%s concurrent=%d)" % [
			current_mood, new_mood, ScenarioDirector.heat, ScenarioDirector.effective_heat(),
			GameState.scenario_tone, GameState.ai_core_status, ScenarioRunner.active_scenarios.size(),
		])
	current_mood = new_mood
	_last_switch_time = _clock
	_play_track(new_mood)


# ---------------------------------------------------------------------------
# Playback: two AudioStreamPlayers crossfaded, random track per mood avoiding
# immediate repeats, manual re-pick-on-finished loop (stream.loop is forced off
# so `finished` actually fires instead of the stream self-looping).
# ---------------------------------------------------------------------------

func _play_track(mood: String) -> void:
	var path: String = _pick_track(mood)
	if path == "":
		if _debug:
			print("[MUSIC] no tracks available for mood=%s, holding current bed" % mood)
		return
	if _debug:
		print("[MUSIC] track pick: mood=%s path=%s" % [mood, path])
	_crossfade_to(path)


func _pick_track(mood: String) -> String:
	var files: Array = _moods.get(mood, [])
	if files.is_empty():
		return ""
	if files.size() == 1:
		return files[0]
	var pick: String = files[randi() % files.size()]
	var attempts: int = 0
	while pick == _last_track_path and attempts < ANTI_REPEAT_ATTEMPTS:
		pick = files[randi() % files.size()]
		attempts += 1
	return pick


func _crossfade_to(path: String) -> void:
	var stream: AudioStreamMP3 = _load_stream(path)
	if stream == null:
		return
	var incoming: AudioStreamPlayer = _inactive_player()
	var outgoing: AudioStreamPlayer = _active_player()
	incoming.stream = stream
	incoming.volume_db = SILENT_VOLUME_DB
	incoming.play()

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(incoming, "volume_db", BED_VOLUME_DB, CROSSFADE_SECONDS)
	tw.tween_property(outgoing, "volume_db", SILENT_VOLUME_DB, CROSSFADE_SECONDS)
	tw.chain().tween_callback(outgoing.stop)

	_active_index = 1 - _active_index
	_last_track_path = path


func _load_stream(path: String) -> AudioStreamMP3:
	if not FileAccess.file_exists(path):
		push_warning("MusicManager: track missing on disk: %s" % path)
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var stream: AudioStreamMP3 = AudioStreamMP3.new()
	stream.data = bytes
	stream.loop = false   # manual re-pick-on-finished loop, not the stream's own self-loop
	return stream


func _on_player_finished(player: AudioStreamPlayer) -> void:
	if not _enabled or player != _active_player():
		return
	if current_mood == MOOD_VICTORY:
		_victory_active = false
		if _debug:
			print("[MUSIC] victory stinger finished -> re-evaluating baseline")
		_apply_decision()
	else:
		_play_track(current_mood)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_crew_died(_crew_id: String, _cause: String) -> void:
	_aftermath_until = _clock + AFTERMATH_COOLDOWN_SECONDS
	if _debug:
		print("[MUSIC] crew_died -> aftermath_somber for %.0fs" % AFTERMATH_COOLDOWN_SECONDS)
	_apply_decision()


func _on_scenario_ended(outcome: String) -> void:
	if outcome == "success":
		_trigger_victory()


func _on_mission_completed(_mission_id: String, outcome: String) -> void:
	if outcome == "mission_success":
		_trigger_victory()


func _on_recent_event(event_id: String, _data: Dictionary) -> void:
	if event_id == "crisis_resolved":
		_trigger_victory()


func _trigger_victory() -> void:
	if _victory_active:
		return  # stinger already playing this window — spec: fires ONCE, not restarted
	_victory_active = true
	if _debug:
		print("[MUSIC] victory trigger -> victory_arrival stinger")
	_apply_decision()
