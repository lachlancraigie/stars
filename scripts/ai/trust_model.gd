class_name TrustModel
extends RefCounted

# Trust delta amounts. All values are small — trust is slow to build, faster to lose.
const DIRECTIVE_FOLLOWED:   float =  0.005
const ADVICE_ACCURATE:      float =  0.020
const ADVICE_INACCURATE:    float = -0.030
const DISOBEDIENCE_MINOR:   float = -0.050
const DISOBEDIENCE_MAJOR:   float = -0.200
const CREW_VOUCHES_FOR:     float =  0.040
const CREW_VOUCHES_AGAINST: float = -0.060
const EVENT_IMPLICATES_AI:  float = -0.150
const EVENT_EXONERATES_AI:  float =  0.080


static func modify(crew_id: String, amount: float) -> void:
	GameState.set_ai_trust(crew_id, GameState.get_ai_trust(crew_id) + amount)


static func modify_all(amount: float) -> void:
	for crew_id: String in GameState.crew:
		modify(crew_id, amount)
