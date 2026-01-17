import std/tables

type
  ArgValueKind* = enum
    avkNull
    avkInt
    avkFloat
    avkString
    avkBool

  ArgValue* = object
    case kind*: ArgValueKind
    of avkNull:
      discard
    of avkInt:
      i*: int64
    of avkFloat:
      f*: float64
    of avkString:
      s*: string
    of avkBool:
      b*: bool

  ScriptArgs* = object
    positional*: seq[ArgValue]
    named*: Table[string, ArgValue]

proc initScriptArgs*(): ScriptArgs =
  ScriptArgs(positional: @[], named: initTable[string, ArgValue]())

proc nullArgValue*(): ArgValue =
  ArgValue(kind: avkNull)

proc toArgValue*(v: ArgValue): ArgValue =
  v

proc toArgValue*(v: bool): ArgValue =
  ArgValue(kind: avkBool, b: v)

proc toArgValue*(v: string): ArgValue =
  ArgValue(kind: avkString, s: v)

proc toArgValue*(v: cstring): ArgValue =
  ArgValue(kind: avkString, s: $v)

proc toArgValue*(v: float32): ArgValue =
  ArgValue(kind: avkFloat, f: float64(v))

proc toArgValue*(v: float): ArgValue =
  ArgValue(kind: avkFloat, f: float64(v))

proc toArgValue*(v: int64): ArgValue =
  ArgValue(kind: avkInt, i: v)

proc toArgValue*(v: int32): ArgValue =
  ArgValue(kind: avkInt, i: int64(v))

proc toArgValue*(v: int): ArgValue =
  ArgValue(kind: avkInt, i: int64(v))

proc addPositional*(args: var ScriptArgs, v: ArgValue) =
  args.positional.add v

proc addNamed*(args: var ScriptArgs, name: string, v: ArgValue) =
  args.named[name] = v
