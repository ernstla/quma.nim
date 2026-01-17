import ./args
import ./store

type
  CursorBase* = ref object of RootObj

  Query* = ref object
    cursor: CursorBase
    scriptId: ScriptId
    scriptArgs: ScriptArgs

proc initQuery*(cursor: CursorBase, scriptId: ScriptId, scriptArgs: ScriptArgs): Query =
  Query(cursor: cursor, scriptId: scriptId, scriptArgs: scriptArgs)

proc scriptId*(q: Query): ScriptId =
  q.scriptId

proc scriptArgs*(q: Query): ScriptArgs =
  q.scriptArgs
