import std/strutils

import ./errors

type
  ScriptId* = string

  Script* = object
    id*: ScriptId
    sql*: string
    isTemplate*: bool
    origin*: string

  ScriptStore* = ref object of RootObj

proc makeScriptId*(segments: openArray[string]): ScriptId =
  segments.join("/")

method hasNamespace*(store: ScriptStore, name: string): bool {.base.} =
  false

method getScript*(store: ScriptStore, id: ScriptId): Script {.base.} =
  raise newException(QumaError, "ScriptStore.getScript not implemented")
