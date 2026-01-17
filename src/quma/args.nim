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
