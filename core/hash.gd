# Hash déterministe (FNV-1a 64 bits, replié sur des mots de 64 bits plutôt
# que des octets). Sert au harness de déterminisme (tools/run_tests.gd) et,
# plus tard, au « hash de l'état final » exigé pour chaque run.
#
# Les littéraux ci-dessous sont l'écriture signée (complément à deux) des
# constantes FNV-1a habituelles, qui dépassent l'amplitude d'un int64 signé ;
# le débordement de multiplication est silencieux et déterministe en GDScript.
class_name FixedHash

const OFFSET_BASIS: int = -3750763034362895579  # 0xcbf29ce484222325
const PRIME: int = 1099511628211  # 0x100000001b3

static func start() -> int:
	return OFFSET_BASIS

static func combine(h: int, v: int) -> int:
	var r: int = h ^ v
	return r * PRIME

static func combine_all(h: int, values: PackedInt64Array) -> int:
	var r: int = h
	for v in values:
		r = combine(r, v)
	return r
