extends RefCounted
class_name FreeformJamState

var jam_context: Node = null

var leader: Node = null
var anchor: Node = null

var members: Array[Node] = []

# Fully joined members capable of recruitment propagation.
var member_join_times := {}

# Auto join delay tracking.
var pending_auto_joins := {}

# JamSpot transfer state.
var pending_jamspot_handoffs := {}
