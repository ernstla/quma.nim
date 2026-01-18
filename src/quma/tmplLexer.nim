import std/strutils

import ./errors

proc hasTemplateContent*(sql: string): bool =
  ## Detects if SQL contains template syntax.
  ## Currently checks for {#if, future: {#include
  "{#if " in sql or "{#if\t" in sql or "{#if\n" in sql

type
  TmplTokenKind* = enum
    TkText # Raw SQL text
    TkIf # {#if
    TkElseIf # {:else if
    TkElse # {:else}
    TkEndIf # {/if}
    TkIdent # variable name
    TkString # 'string' or "string"
    TkInt # 123
    TkFloat # 123.45
    TkTrue # true
    TkFalse # false
    TkNull # null
    TkEq # ==
    TkNe # !=
    TkLt # <
    TkLe # <=
    TkGt # >
    TkGe # >=
    TkAnd # and
    TkOr # or
    TkNot # not
    TkLParen # (
    TkRParen # )
    TkEof

  TmplToken* = object
    kind*: TmplTokenKind
    value*: string
    line*: int
    col*: int

  TmplLexer* = object
    input: string
    pos: int
    line: int
    col: int

proc initTmplLexer*(input: string): TmplLexer =
  TmplLexer(input: input, pos: 0, line: 1, col: 1)

proc atEnd(lex: TmplLexer): bool =
  lex.pos >= lex.input.len

proc peek(lex: TmplLexer, offset: int = 0): char =
  let idx = lex.pos + offset
  if idx < lex.input.len:
    lex.input[idx]
  else:
    '\0'

proc advance(lex: var TmplLexer): char =
  result = lex.peek()
  lex.pos.inc
  if result == '\n':
    lex.line.inc
    lex.col = 1
  else:
    lex.col.inc

proc skipWhitespace(lex: var TmplLexer) =
  while lex.peek() in Whitespace:
    discard lex.advance()

proc makeToken(lex: TmplLexer, kind: TmplTokenKind, value: string = ""): TmplToken =
  TmplToken(kind: kind, value: value, line: lex.line, col: lex.col)

proc startsWithAt(s: string, sub: string, pos: int): bool =
  if pos + sub.len > s.len:
    return false
  for i in 0 ..< sub.len:
    if s[pos + i] != sub[i]:
      return false
  true

proc lexString(lex: var TmplLexer): TmplToken =
  let quote = lex.advance() # consume opening quote
  let startLine = lex.line
  let startCol = lex.col
  var value = ""
  while not lex.atEnd() and lex.peek() != quote:
    if lex.peek() == '\n':
      raise newException(TemplateError, "Unterminated string at line " & $startLine)
    value.add lex.advance()
  if lex.atEnd():
    raise newException(TemplateError, "Unterminated string at line " & $startLine)
  discard lex.advance() # consume closing quote
  TmplToken(kind: TkString, value: value, line: startLine, col: startCol)

proc lexNumber(lex: var TmplLexer): TmplToken =
  let startLine = lex.line
  let startCol = lex.col
  var value = ""
  while lex.peek() in Digits:
    value.add lex.advance()
  if lex.peek() == '.' and lex.peek(1) in Digits:
    value.add lex.advance() # consume '.'
    while lex.peek() in Digits:
      value.add lex.advance()
    TmplToken(kind: TkFloat, value: value, line: startLine, col: startCol)
  else:
    TmplToken(kind: TkInt, value: value, line: startLine, col: startCol)

proc lexIdent(lex: var TmplLexer): TmplToken =
  let startLine = lex.line
  let startCol = lex.col
  var value = ""
  while lex.peek() in IdentChars:
    value.add lex.advance()
  let kind =
    case value
    of "and": TkAnd
    of "or": TkOr
    of "not": TkNot
    of "true": TkTrue
    of "false": TkFalse
    of "null": TkNull
    else: TkIdent
  TmplToken(kind: kind, value: value, line: startLine, col: startCol)

proc lexExprTokens*(lex: var TmplLexer, endMarker: string): seq[TmplToken] =
  ## Lex tokens inside an expression until endMarker (e.g., "}")
  result = @[]
  while not lex.atEnd():
    if lex.input.startsWithAt(endMarker, lex.pos):
      for _ in 0 ..< endMarker.len:
        discard lex.advance()
      break
    lex.skipWhitespace()
    if lex.input.startsWithAt(endMarker, lex.pos):
      for _ in 0 ..< endMarker.len:
        discard lex.advance()
      break
    let c = lex.peek()
    case c
    of '\'', '"':
      result.add lex.lexString()
    of '0' .. '9':
      result.add lex.lexNumber()
    of 'a' .. 'z', 'A' .. 'Z', '_':
      result.add lex.lexIdent()
    of '=':
      if lex.peek(1) == '=':
        result.add lex.makeToken(TkEq, "==")
        discard lex.advance()
        discard lex.advance()
      else:
        raise newException(
          TemplateError, "Unexpected '=' at line " & $lex.line & ", expected '=='"
        )
    of '!':
      if lex.peek(1) == '=':
        result.add lex.makeToken(TkNe, "!=")
        discard lex.advance()
        discard lex.advance()
      else:
        raise newException(
          TemplateError, "Unexpected '!' at line " & $lex.line & ", expected '!='"
        )
    of '<':
      if lex.peek(1) == '=':
        result.add lex.makeToken(TkLe, "<=")
        discard lex.advance()
        discard lex.advance()
      else:
        result.add lex.makeToken(TkLt, "<")
        discard lex.advance()
    of '>':
      if lex.peek(1) == '=':
        result.add lex.makeToken(TkGe, ">=")
        discard lex.advance()
        discard lex.advance()
      else:
        result.add lex.makeToken(TkGt, ">")
        discard lex.advance()
    of '(':
      result.add lex.makeToken(TkLParen, "(")
      discard lex.advance()
    of ')':
      result.add lex.makeToken(TkRParen, ")")
      discard lex.advance()
    else:
      if c in Whitespace:
        lex.skipWhitespace()
      else:
        raise newException(
          TemplateError, "Unexpected character '" & $c & "' at line " & $lex.line
        )

type TmplBlock* = object ## A parsed template block - either text or a control structure
  kind*: TmplTokenKind
  text*: string # for TkText
  exprTokens*: seq[TmplToken] # for TkIf, TkElseIf (the condition tokens)
  line*: int
  col*: int

proc lexTemplate*(input: string): seq[TmplBlock] =
  ## Lex a template into blocks of text and control structures
  var lex = initTmplLexer(input)
  result = @[]
  var textStart = 0
  var textLine = 1
  var textCol = 1

  while not lex.atEnd():
    # Check for control structure markers
    if lex.input.startsWithAt("{#if ", lex.pos) or
        lex.input.startsWithAt("{#if\t", lex.pos) or
        lex.input.startsWithAt("{#if\n", lex.pos):
      # Emit accumulated text
      if lex.pos > textStart:
        result.add TmplBlock(
          kind: TkText,
          text: lex.input[textStart ..< lex.pos],
          line: textLine,
          col: textCol,
        )
      let blockLine = lex.line
      let blockCol = lex.col
      # Skip "{#if "
      for _ in 0 ..< 4:
        discard lex.advance()
      lex.skipWhitespace()
      let exprTokens = lex.lexExprTokens("}")
      result.add TmplBlock(
        kind: TkIf, exprTokens: exprTokens, line: blockLine, col: blockCol
      )
      textStart = lex.pos
      textLine = lex.line
      textCol = lex.col
    elif lex.input.startsWithAt("{:else if ", lex.pos) or
        lex.input.startsWithAt("{:else if\t", lex.pos) or
        lex.input.startsWithAt("{:else if\n", lex.pos):
      if lex.pos > textStart:
        result.add TmplBlock(
          kind: TkText,
          text: lex.input[textStart ..< lex.pos],
          line: textLine,
          col: textCol,
        )
      let blockLine = lex.line
      let blockCol = lex.col
      # Skip "{:else if "
      for _ in 0 ..< 9:
        discard lex.advance()
      lex.skipWhitespace()
      let exprTokens = lex.lexExprTokens("}")
      result.add TmplBlock(
        kind: TkElseIf, exprTokens: exprTokens, line: blockLine, col: blockCol
      )
      textStart = lex.pos
      textLine = lex.line
      textCol = lex.col
    elif lex.input.startsWithAt("{:else}", lex.pos):
      if lex.pos > textStart:
        result.add TmplBlock(
          kind: TkText,
          text: lex.input[textStart ..< lex.pos],
          line: textLine,
          col: textCol,
        )
      let blockLine = lex.line
      let blockCol = lex.col
      for _ in 0 ..< 7:
        discard lex.advance()
      result.add TmplBlock(kind: TkElse, line: blockLine, col: blockCol)
      textStart = lex.pos
      textLine = lex.line
      textCol = lex.col
    elif lex.input.startsWithAt("{/if}", lex.pos):
      if lex.pos > textStart:
        result.add TmplBlock(
          kind: TkText,
          text: lex.input[textStart ..< lex.pos],
          line: textLine,
          col: textCol,
        )
      let blockLine = lex.line
      let blockCol = lex.col
      for _ in 0 ..< 5:
        discard lex.advance()
      result.add TmplBlock(kind: TkEndIf, line: blockLine, col: blockCol)
      textStart = lex.pos
      textLine = lex.line
      textCol = lex.col
    else:
      discard lex.advance()

  # Emit any remaining text
  if lex.pos > textStart:
    result.add TmplBlock(
      kind: TkText, text: lex.input[textStart ..< lex.pos], line: textLine, col: textCol
    )
