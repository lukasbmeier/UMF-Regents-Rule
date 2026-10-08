class_name ReducerRequest extends RefCounted
## Handle for one reducer call. Wraps the SDK's call object so callers never see it.
##
## Lifecycle: PENDING → exactly one terminal outcome. `settled` fires once.
## Movement uses `seq_from`/`seq_to` to know which predicted inputs a failure invalidates.

signal settled(req: ReducerRequest)

enum Outcome { PENDING, OK, REJECTED, FAILED, TIMEOUT, DISCONNECTED }

var reducer_name: StringName
var args: Array = []
var outcome: Outcome = Outcome.PENDING
var error_message: String = ""
## Input sequence range carried by this call (movement only). -1 when not applicable.
var seq_from: int = -1
var seq_to: int = -1
var sent_usec: int = 0
var settled_usec: int = 0
## SDK-side request id, for correlating our own row updates.
var request_id: int = -1

func is_pending() -> bool:
	return outcome == Outcome.PENDING

func is_ok() -> bool:
	return outcome == Outcome.OK

func rtt_usec() -> int:
	return settled_usec - sent_usec if settled_usec > 0 else -1

## Called by SpaceTimeSync only.
func _settle(p_outcome: Outcome, p_error: String = "") -> void:
	if outcome != Outcome.PENDING:
		return
	outcome = p_outcome
	error_message = p_error
	settled_usec = Time.get_ticks_usec()
	settled.emit(self)

func _to_string() -> String:
	return "ReducerRequest(%s %s seq=%d..%d)" % [reducer_name, Outcome.keys()[outcome], seq_from, seq_to]
