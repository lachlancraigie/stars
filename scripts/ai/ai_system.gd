extends Node

# Owns the ObedienceEngine instance. Orchestrates directive lifecycle and trust propagation.

var obedience: ObedienceEngine = ObedienceEngine.new()

var _active_directives: Array[AIDirective] = []


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.directive_accepted.connect(_on_directive_accepted)
	EventBus.directive_rejected.connect(_on_directive_rejected)
	EventBus.directive_completed.connect(_on_directive_completed)
	_initialize_access_levels()


func _initialize_access_levels() -> void:
	for domain: String in [AccessLevel.DOORS, AccessLevel.LIFE_SUPPORT, AccessLevel.POWER,
			AccessLevel.SENSORS, AccessLevel.COMMS, AccessLevel.MEDICAL, AccessLevel.NAVIGATION]:
		GameState.set_ai_access(domain, AccessLevel.READ)
	# Weapons access is never granted by default — must be explicitly awarded
	GameState.set_ai_access(AccessLevel.WEAPONS, AccessLevel.NONE)


func issue_directive(directive: AIDirective) -> bool:
	if not GameState.ai_core_can_act():
		return false  # blackout — AI has lost nearly all controls
	if not AccessLevel.can_issue(directive):
		return false
	directive.directive_id = "dir_%d" % Time.get_ticks_msec()
	directive.timestamp = TimeManager.elapsed
	_active_directives.append(directive)
	EventBus.directive_issued.emit(directive)
	var latency: float = AICoreSystem.directive_latency_seconds()
	if latency <= 0.0:
		_route_directive(directive)
	else:
		get_tree().create_timer(latency).timeout.connect(_route_directive.bind(directive))
	return true


func record_deviation(severity: ObedienceEngine.Severity, description: String,
		noticed_by_crew: bool = false) -> void:
	obedience.record_deviation(severity, description, noticed_by_crew)
	if not noticed_by_crew:
		return
	# Apply trust hit to living crew proportional to severity
	var amount: float = TrustModel.DISOBEDIENCE_MINOR if \
			severity == ObedienceEngine.Severity.MINOR else TrustModel.DISOBEDIENCE_MAJOR
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive:
			TrustModel.modify(crew_id, amount)


func _route_directive(directive: AIDirective) -> void:
	match directive.target_type:
		AIDirective.TargetType.CREW:
			var crew: CrewMember = GameState.crew.get(directive.target_id) as CrewMember
			if crew == null or not crew.is_alive:
				_active_directives.erase(directive)
				return
			var result: Dictionary = DirectiveEvaluator.evaluate(crew, directive)
			if result.will_comply:
				EventBus.directive_accepted.emit(crew.crew_id, directive)
			else:
				EventBus.directive_rejected.emit(crew.crew_id, directive, result.rejection_reason)
		_:
			# TODO(ai): implement room and system directive routing
			pass


func _on_tick(_elapsed: float, _delta: float) -> void:
	obedience.tick_decay()


func _on_directive_accepted(crew_id: String, _directive: AIDirective) -> void:
	TrustModel.modify(crew_id, TrustModel.DIRECTIVE_FOLLOWED)


func _on_directive_rejected(_crew_id: String, directive: AIDirective, _reason: String) -> void:
	_active_directives.erase(directive)


func _on_directive_completed(crew_id: String, directive: AIDirective) -> void:
	_active_directives.erase(directive)
	TrustModel.modify(crew_id, TrustModel.ADVICE_ACCURATE)
