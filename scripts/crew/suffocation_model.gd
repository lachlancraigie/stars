class_name SuffocationModel
extends RefCounted

# Per-crew suffocation, ticked from CrewSystem (docs/rules.md "Survival Conditions >
# Oxygen"). Ship-wide O2-supply-vs-passenger-count bookkeeping is replaced by the
# per-room air quality model (LifeSupportModel) — the rules' two thresholds map onto it:
#   - air < AIR_DISADVANTAGE_THRESHOLD  ("O2 supply < 2x breathing passengers"): all rolls
#     at Disadvantage — handled automatically by CrewMember.has_environmental_disadvantage(),
#     read by every Checks.perform_check().
#   - air < AIR_CRITICAL_THRESHOLD ("O2 supply < breathing passengers"): a Body Save every
#     ~round (10s) or a Death Save.
# Androids consume no O2 (rules.md) and are exempt entirely.

const ROUND_SECONDS: float = 10.0


static func tick(crew: CrewMember, delta: float) -> void:
	if not crew.is_alive or crew.mship_class == "Android":
		return

	var air: float = GameState.get_room_air(crew.location)
	if air >= LifeSupportModel.AIR_CRITICAL_THRESHOLD:
		crew.suffocation_round_timer = 0.0
		# Getting a suffocating crew member back to breathable air counts as the
		# "intervention" that cancels an in-progress Death Save clock (rules.md:
		# "Die in 1d5 rounds without intervention"). Deliberately scoped to "dying"
		# only, not "pending_save" — a pending_save clock means a Lethal Injury Wound
		# is owed a fresh Death Save roll, which fresh air alone shouldn't cancel
		# (no live combat system feeds Wounds today, but this keeps the two death-
		# clock causes from cross-contaminating if/when one does).
		if crew.death_save_mode == "dying":
			WoundTable.stabilize(crew)
		return

	crew.suffocation_round_timer += delta
	if crew.suffocation_round_timer < ROUND_SECONDS:
		return
	crew.suffocation_round_timer = 0.0

	# Iron Lungs' "+5 Body vs air/vacuum" is qualified to exactly this check — the tag
	# system (not the always-on stat_bonus system) is what scopes it here and nowhere else.
	var result: Checks.CheckResult = Checks.perform_check(crew, "body", "", false, false, int(crew.trait_bonus("body_vs_air_bonus")))
	if not result.success:
		WoundTable.death_save(crew)
	# "Survived suffocation/near-vacuum" earn trigger (docs/crew-progression-spec.md §3) —
	# fires once per critical-air round regardless of the roll's outcome; CrewProgression
	# dedupes to once per leg so a prolonged air crisis doesn't spam pending trait rolls.
	EventBus.crew_suffocation_check.emit(crew.crew_id, crew.is_alive)
