import std/[strutils, options]

import ./errors
import ./tmplLexer

type
  ExprKind* = enum
    ExprVar # variable reference
    ExprString # string literal
    ExprInt # int literal
    ExprFloat # float literal
    ExprBool # bool literal
    ExprNull # null literal
    ExprBinOp # binary operation
    ExprUnaryOp # unary operation (not)

  BinOpKind* = enum
    BinEq # ==
    BinNe # !=
    BinLt # <
    BinLe # <=
    BinGt # >
    BinGe # >=
    BinAnd # and
    BinOr # or

  Expr* = ref object
    line*: int
    col*: int
    case kind*: ExprKind
    of ExprVar:
      varName*: string
    of ExprString:
      strVal*: string
    of ExprInt:
      intVal*: int64
    of ExprFloat:
      floatVal*: float64
    of ExprBool:
      boolVal*: bool
    of ExprNull:
      discard
    of ExprBinOp:
      binOp*: BinOpKind
      left*: Expr
      right*: Expr
    of ExprUnaryOp:
      unaryOp*: string # "not"
      operand*: Expr

  TmplNodeKind* = enum
    TmplText # raw text
    TmplIf # if/else-if/else block
    TmplInclude # include directive

  ElseBranch* = object
    body*: seq[TmplNode]

  ElseIfBranch* = object
    condition*: Expr
    body*: seq[TmplNode]

  TmplNode* = ref object
    line*: int
    col*: int
    case kind*: TmplNodeKind
    of TmplText:
      text*: string
    of TmplIf:
      condition*: Expr
      thenBranch*: seq[TmplNode]
      elseIfBranches*: seq[ElseIfBranch]
      elseBranch*: Option[ElseBranch]
    of TmplInclude:
      includePath*: string

# Expression parser using recursive descent
type ExprParser = object
  tokens: seq[TmplToken]
  pos: int
  scriptName: string

proc initExprParser(tokens: seq[TmplToken], scriptName: string = ""): ExprParser =
  ExprParser(tokens: tokens, pos: 0, scriptName: scriptName)

proc atEnd(p: ExprParser): bool =
  p.pos >= p.tokens.len

proc peek(p: ExprParser): TmplToken =
  if p.atEnd():
    TmplToken(kind: TkEof)
  else:
    p.tokens[p.pos]

proc advance(p: var ExprParser): TmplToken =
  result = p.peek()
  if not p.atEnd():
    p.pos.inc

proc error(p: ExprParser, msg: string): ref TemplateError =
  let tok = p.peek()
  let location =
    if p.scriptName.len > 0:
      p.scriptName & ":" & $tok.line
    else:
      "line " & $tok.line
  newException(TemplateError, location & ": " & msg)

proc parseExpr(p: var ExprParser): Expr
proc parseOrExpr(p: var ExprParser): Expr
proc parseAndExpr(p: var ExprParser): Expr
proc parseNotExpr(p: var ExprParser): Expr
proc parseCmpExpr(p: var ExprParser): Expr
proc parsePrimary(p: var ExprParser): Expr

proc parseExpr(p: var ExprParser): Expr =
  p.parseOrExpr()

proc parseOrExpr(p: var ExprParser): Expr =
  result = p.parseAndExpr()
  while p.peek().kind == TkOr:
    let tok = p.advance()
    let right = p.parseAndExpr()
    result = Expr(
      kind: ExprBinOp,
      binOp: BinOr,
      left: result,
      right: right,
      line: tok.line,
      col: tok.col,
    )

proc parseAndExpr(p: var ExprParser): Expr =
  result = p.parseNotExpr()
  while p.peek().kind == TkAnd:
    let tok = p.advance()
    let right = p.parseNotExpr()
    result = Expr(
      kind: ExprBinOp,
      binOp: BinAnd,
      left: result,
      right: right,
      line: tok.line,
      col: tok.col,
    )

proc parseNotExpr(p: var ExprParser): Expr =
  if p.peek().kind == TkNot:
    let tok = p.advance()
    let operand = p.parseNotExpr()
    Expr(
      kind: ExprUnaryOp, unaryOp: "not", operand: operand, line: tok.line, col: tok.col
    )
  else:
    p.parseCmpExpr()

proc parseCmpExpr(p: var ExprParser): Expr =
  result = p.parsePrimary()
  let tok = p.peek()
  case tok.kind
  of TkEq:
    discard p.advance()
    let right = p.parsePrimary()
    result = Expr(
      kind: ExprBinOp,
      binOp: BinEq,
      left: result,
      right: right,
      line: tok.line,
      col: tok.col,
    )
  of TkNe:
    discard p.advance()
    let right = p.parsePrimary()
    result = Expr(
      kind: ExprBinOp,
      binOp: BinNe,
      left: result,
      right: right,
      line: tok.line,
      col: tok.col,
    )
  of TkLt:
    discard p.advance()
    let right = p.parsePrimary()
    result = Expr(
      kind: ExprBinOp,
      binOp: BinLt,
      left: result,
      right: right,
      line: tok.line,
      col: tok.col,
    )
  of TkLe:
    discard p.advance()
    let right = p.parsePrimary()
    result = Expr(
      kind: ExprBinOp,
      binOp: BinLe,
      left: result,
      right: right,
      line: tok.line,
      col: tok.col,
    )
  of TkGt:
    discard p.advance()
    let right = p.parsePrimary()
    result = Expr(
      kind: ExprBinOp,
      binOp: BinGt,
      left: result,
      right: right,
      line: tok.line,
      col: tok.col,
    )
  of TkGe:
    discard p.advance()
    let right = p.parsePrimary()
    result = Expr(
      kind: ExprBinOp,
      binOp: BinGe,
      left: result,
      right: right,
      line: tok.line,
      col: tok.col,
    )
  else:
    discard

proc parsePrimary(p: var ExprParser): Expr =
  let tok = p.peek()
  case tok.kind
  of TkIdent:
    discard p.advance()
    result = Expr(kind: ExprVar, varName: tok.value, line: tok.line, col: tok.col)
  of TkString:
    discard p.advance()
    result = Expr(kind: ExprString, strVal: tok.value, line: tok.line, col: tok.col)
  of TkInt:
    discard p.advance()
    result = Expr(
      kind: ExprInt, intVal: parseBiggestInt(tok.value), line: tok.line, col: tok.col
    )
  of TkFloat:
    discard p.advance()
    result = Expr(
      kind: ExprFloat, floatVal: parseFloat(tok.value), line: tok.line, col: tok.col
    )
  of TkTrue:
    discard p.advance()
    result = Expr(kind: ExprBool, boolVal: true, line: tok.line, col: tok.col)
  of TkFalse:
    discard p.advance()
    result = Expr(kind: ExprBool, boolVal: false, line: tok.line, col: tok.col)
  of TkNull:
    discard p.advance()
    result = Expr(kind: ExprNull, line: tok.line, col: tok.col)
  of TkLParen:
    discard p.advance()
    result = p.parseExpr()
    if p.peek().kind != TkRParen:
      raise p.error("Expected ')' after expression")
    discard p.advance()
  of TkEof:
    raise p.error("Unexpected end of expression")
  else:
    raise p.error("Unexpected token: " & $tok.kind)

proc parseExprTokens*(tokens: seq[TmplToken], scriptName: string = ""): Expr =
  var parser = initExprParser(tokens, scriptName)
  result = parser.parseExpr()
  if not parser.atEnd():
    raise parser.error("Unexpected token after expression: " & $parser.peek().kind)

# Template parser: convert TmplBlocks to TmplNodes
type TmplParser = object
  blocks: seq[TmplBlock]
  pos: int
  scriptName: string

proc initTmplParser(blocks: seq[TmplBlock], scriptName: string = ""): TmplParser =
  TmplParser(blocks: blocks, pos: 0, scriptName: scriptName)

proc atEnd(p: TmplParser): bool =
  p.pos >= p.blocks.len

proc peek(p: TmplParser): TmplBlock =
  if p.atEnd():
    TmplBlock(kind: TkEof)
  else:
    p.blocks[p.pos]

proc advance(p: var TmplParser): TmplBlock =
  result = p.peek()
  if not p.atEnd():
    p.pos.inc

proc error(p: TmplParser, msg: string, line: int = 0): ref TemplateError =
  let loc =
    if p.scriptName.len > 0:
      p.scriptName & ":" & $line
    else:
      "line " & $line
  newException(TemplateError, loc & ": " & msg)

proc parseNodes(p: var TmplParser): seq[TmplNode]

proc parseIfBlock(p: var TmplParser): TmplNode =
  let ifBlock = p.advance() # consume TkIf
  let condition = parseExprTokens(ifBlock.exprTokens, p.scriptName)

  var thenBranch: seq[TmplNode] = @[]
  var elseIfBranches: seq[ElseIfBranch] = @[]
  var elseBranch: Option[ElseBranch] = none(ElseBranch)

  # Parse then branch
  while not p.atEnd():
    let blk = p.peek()
    if blk.kind in {TkElseIf, TkElse, TkEndIf}:
      break
    thenBranch.add p.parseNodes()

  # Parse else-if branches
  while not p.atEnd() and p.peek().kind == TkElseIf:
    let elseIfBlock = p.advance()
    let elseIfCond = parseExprTokens(elseIfBlock.exprTokens, p.scriptName)
    var elseIfBody: seq[TmplNode] = @[]
    while not p.atEnd():
      let blk = p.peek()
      if blk.kind in {TkElseIf, TkElse, TkEndIf}:
        break
      elseIfBody.add p.parseNodes()
    elseIfBranches.add ElseIfBranch(condition: elseIfCond, body: elseIfBody)

  # Parse else branch
  if not p.atEnd() and p.peek().kind == TkElse:
    discard p.advance() # consume TkElse
    var elseBody: seq[TmplNode] = @[]
    while not p.atEnd():
      let blk = p.peek()
      if blk.kind == TkEndIf:
        break
      elseBody.add p.parseNodes()
    elseBranch = some(ElseBranch(body: elseBody))

  # Expect TkEndIf
  if p.atEnd() or p.peek().kind != TkEndIf:
    raise p.error("Expected {/if}", ifBlock.line)
  discard p.advance() # consume TkEndIf

  TmplNode(
    kind: TmplIf,
    condition: condition,
    thenBranch: thenBranch,
    elseIfBranches: elseIfBranches,
    elseBranch: elseBranch,
    line: ifBlock.line,
    col: ifBlock.col,
  )

proc parseNodes(p: var TmplParser): seq[TmplNode] =
  result = @[]
  while not p.atEnd():
    let blk = p.peek()
    case blk.kind
    of TkText:
      discard p.advance()
      result.add TmplNode(kind: TmplText, text: blk.text, line: blk.line, col: blk.col)
    of TkIf:
      result.add p.parseIfBlock()
    of TkInclude:
      discard p.advance()
      result.add TmplNode(
        kind: TmplInclude, includePath: blk.includePath, line: blk.line, col: blk.col
      )
    of TkElseIf, TkElse, TkEndIf:
      # These are handled by parseIfBlock, return to caller
      break
    of TkEof:
      break
    else:
      raise p.error("Unexpected block type: " & $blk.kind, blk.line)

proc parseTemplate*(input: string, scriptName: string = ""): seq[TmplNode] =
  let blocks = lexTemplate(input)
  var parser = initTmplParser(blocks, scriptName)
  parser.parseNodes()
