class_name AccessLevel
extends RefCounted

const NONE  = 0
const READ  = 1
const WRITE = 2
const FULL  = 3

# System domains
const DOORS        = "doors"
const LIFE_SUPPORT = "life_support"
const POWER        = "power"
const SENSORS      = "sensors"
const COMMS        = "comms"
const WEAPONS      = "weapons"
const MEDICAL      = "medical"
const NAVIGATION   = "navigation"

const ALL_DOMAINS: Array[String] = [
	DOORS, LIFE_SUPPORT, POWER, SENSORS, COMMS, WEAPONS, MEDICAL, NAVIGATION
]


static func can_issue(directive: AIDirective) -> bool:
	var domain: String = domain_for_directive(directive)
	return GameState.get_ai_access(domain) >= min_access_for_type(directive.type)


static func domain_for_directive(directive: AIDirective) -> String:
	match directive.target_type:
		AIDirective.TargetType.SYSTEM: return directive.target_id
		AIDirective.TargetType.ROOM:   return DOORS
		_:                              return COMMS


static func min_access_for_type(type: AIDirective.Type) -> int:
	match type:
		AIDirective.Type.SUGGESTION:       return READ
		AIDirective.Type.RECOMMENDATION:   return READ
		AIDirective.Type.INSTRUCTION:      return WRITE
		AIDirective.Type.ALERT:            return READ
		AIDirective.Type.OVERRIDE_ATTEMPT: return FULL
		_:                                  return WRITE
