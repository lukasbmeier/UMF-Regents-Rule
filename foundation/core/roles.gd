class_name Roles
## WHO THIS CLIENT IS TO THE SERVER: the `authority` table (public: a list of trusted identities,
## no secrets; the foundation subscribes every client to it, `InterestManager.ALWAYS_TABLES`). An
## admin is the identity that published the module. The client only uses this to decide what to
## SHOW (the rules page, later the admin panel); the server checks `require_admin` on every
## privileged reducer regardless.

## The server's roles (server/src/module/constants.rs).
const ADMIN: int = 0
const SIDECAR: int = 1
const NONE: int = -1


## This client's role, or NONE.
static func local_role() -> int:
	if SpaceTimeSync.local_identity.is_empty():
		return NONE
	var row: RefCounted = SpaceTimeSync.get_row(&"authority", SpaceTimeSync.local_identity)
	return int(row.get(&"role")) if row != null else NONE


static func is_local_admin() -> bool:
	return local_role() == ADMIN
