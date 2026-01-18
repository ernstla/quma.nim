import std/[unittest, tables, options, strutils]

import quma/args
import quma/errors
import quma/tmplLexer
import quma/tmplParser
import quma/tmplEval

suite "Template Lexer":
  test "lexes plain text":
    let blocks = lexTemplate("SELECT * FROM users")
    check blocks.len == 1
    check blocks[0].kind == TkText
    check blocks[0].text == "SELECT * FROM users"

  test "lexes if block":
    let blocks = lexTemplate("{#if active}WHERE active = 1{/if}")
    check blocks.len == 3
    check blocks[0].kind == TkIf
    check blocks[0].exprTokens.len == 1
    check blocks[0].exprTokens[0].kind == TkIdent
    check blocks[0].exprTokens[0].value == "active"
    check blocks[1].kind == TkText
    check blocks[1].text == "WHERE active = 1"
    check blocks[2].kind == TkEndIf

  test "lexes if-else block":
    let blocks = lexTemplate("{#if a}then{:else}else{/if}")
    check blocks.len == 5
    check blocks[0].kind == TkIf
    check blocks[1].kind == TkText
    check blocks[1].text == "then"
    check blocks[2].kind == TkElse
    check blocks[3].kind == TkText
    check blocks[3].text == "else"
    check blocks[4].kind == TkEndIf

  test "lexes if-elseif-else block":
    let blocks = lexTemplate("{#if a}A{:else if b}B{:else}C{/if}")
    check blocks.len == 7
    check blocks[0].kind == TkIf
    check blocks[2].kind == TkElseIf
    check blocks[4].kind == TkElse
    check blocks[6].kind == TkEndIf

  test "lexes comparison operators":
    let blocks = lexTemplate("{#if x >= 10 and y < 5}ok{/if}")
    check blocks[0].kind == TkIf
    let tokens = blocks[0].exprTokens
    check tokens.len == 7 # x, >=, 10, and, y, <, 5
    check tokens[0].kind == TkIdent
    check tokens[1].kind == TkGe
    check tokens[2].kind == TkInt
    check tokens[3].kind == TkAnd
    check tokens[4].kind == TkIdent
    check tokens[5].kind == TkLt
    check tokens[6].kind == TkInt

  test "lexes string literals":
    let blocks = lexTemplate("{#if name == 'Hans'}match{/if}")
    let tokens = blocks[0].exprTokens
    check tokens.len == 3
    check tokens[0].kind == TkIdent
    check tokens[1].kind == TkEq
    check tokens[2].kind == TkString
    check tokens[2].value == "Hans"

suite "Template Parser":
  test "parses simple if":
    let nodes = parseTemplate("{#if active}content{/if}")
    check nodes.len == 1
    check nodes[0].kind == TmplIf
    check nodes[0].condition.kind == ExprVar
    check nodes[0].condition.varName == "active"
    check nodes[0].thenBranch.len == 1
    check nodes[0].thenBranch[0].kind == TmplText
    check nodes[0].thenBranch[0].text == "content"

  test "parses if-else":
    let nodes = parseTemplate("{#if a}then{:else}else{/if}")
    check nodes.len == 1
    check nodes[0].kind == TmplIf
    check nodes[0].thenBranch[0].text == "then"
    check nodes[0].elseBranch.isSome
    check nodes[0].elseBranch.get.body[0].text == "else"

  test "parses if-elseif-else":
    let nodes = parseTemplate("{#if a}A{:else if b}B{:else}C{/if}")
    check nodes.len == 1
    check nodes[0].elseIfBranches.len == 1
    check nodes[0].elseIfBranches[0].condition.kind == ExprVar
    check nodes[0].elseIfBranches[0].body[0].text == "B"
    check nodes[0].elseBranch.isSome

  test "parses comparison expression":
    let nodes = parseTemplate("{#if count > 10}many{/if}")
    check nodes[0].condition.kind == ExprBinOp
    check nodes[0].condition.binOp == BinGt
    check nodes[0].condition.left.kind == ExprVar
    check nodes[0].condition.right.kind == ExprInt

  test "parses compound expression":
    let nodes = parseTemplate("{#if a and b or c}ok{/if}")
    # Should parse as (a and b) or c due to precedence
    check nodes[0].condition.kind == ExprBinOp
    check nodes[0].condition.binOp == BinOr

  test "parses not expression":
    let nodes = parseTemplate("{#if not active}inactive{/if}")
    check nodes[0].condition.kind == ExprUnaryOp
    check nodes[0].condition.unaryOp == "not"
    check nodes[0].condition.operand.kind == ExprVar

  test "parses parenthesized expression":
    let nodes = parseTemplate("{#if (a or b) and c}ok{/if}")
    check nodes[0].condition.kind == ExprBinOp
    check nodes[0].condition.binOp == BinAnd
    check nodes[0].condition.left.kind == ExprBinOp
    check nodes[0].condition.left.binOp == BinOr

  test "errors on unclosed if":
    expect TemplateError:
      discard parseTemplate("{#if a}content")

suite "Template Evaluator":
  test "evaluates simple boolean":
    let vars = {"active": toArgValue(true)}.toTable
    let result = renderTemplate("{#if active}yes{/if}", vars)
    check result == "yes"

  test "evaluates false boolean":
    let vars = {"active": toArgValue(false)}.toTable
    let result = renderTemplate("{#if active}yes{/if}", vars)
    check result == ""

  test "evaluates if-else":
    let vars1 = {"flag": toArgValue(true)}.toTable
    check renderTemplate("{#if flag}A{:else}B{/if}", vars1) == "A"

    let vars2 = {"flag": toArgValue(false)}.toTable
    check renderTemplate("{#if flag}A{:else}B{/if}", vars2) == "B"

  test "evaluates if-elseif-else":
    let vars1 = {"x": toArgValue(1)}.toTable
    check renderTemplate("{#if x == 1}one{:else if x == 2}two{:else}other{/if}", vars1) ==
      "one"

    let vars2 = {"x": toArgValue(2)}.toTable
    check renderTemplate("{#if x == 1}one{:else if x == 2}two{:else}other{/if}", vars2) ==
      "two"

    let vars3 = {"x": toArgValue(99)}.toTable
    check renderTemplate("{#if x == 1}one{:else if x == 2}two{:else}other{/if}", vars3) ==
      "other"

  test "evaluates string comparison":
    let vars = {"name": toArgValue("Hans")}.toTable
    check renderTemplate("{#if name == 'Hans'}match{/if}", vars) == "match"
    check renderTemplate("{#if name == 'Franz'}match{/if}", vars) == ""

  test "evaluates numeric comparisons":
    let vars = {"count": toArgValue(15)}.toTable
    check renderTemplate("{#if count > 10}many{/if}", vars) == "many"
    check renderTemplate("{#if count < 10}few{/if}", vars) == ""
    check renderTemplate("{#if count >= 15}ok{/if}", vars) == "ok"
    check renderTemplate("{#if count <= 15}ok{/if}", vars) == "ok"

  test "evaluates and/or":
    let vars = {"a": toArgValue(true), "b": toArgValue(false)}.toTable
    check renderTemplate("{#if a and b}both{/if}", vars) == ""
    check renderTemplate("{#if a or b}either{/if}", vars) == "either"

  test "evaluates not":
    let vars = {"active": toArgValue(false)}.toTable
    check renderTemplate("{#if not active}inactive{/if}", vars) == "inactive"

  test "evaluates null comparison":
    let vars1 = {"val": ArgValue(kind: avkNull)}.toTable
    check renderTemplate("{#if val == null}null{/if}", vars1) == "null"

    let vars2 = {"val": toArgValue(42)}.toTable
    check renderTemplate("{#if val == null}null{:else}not null{/if}", vars2) ==
      "not null"

  test "preserves text around conditionals":
    let vars = {"active": toArgValue(true)}.toTable
    let result = renderTemplate(
      "SELECT * FROM users{#if active} WHERE active = 1{/if} ORDER BY id", vars
    )
    check result == "SELECT * FROM users WHERE active = 1 ORDER BY id"

  test "errors on unknown variable":
    let vars = initTable[string, ArgValue]()
    expect TemplateError:
      discard renderTemplate("{#if unknown}x{/if}", vars)

  test "errors on type mismatch in and":
    let vars = {"a": toArgValue("string")}.toTable
    expect TemplateError:
      discard renderTemplate("{#if a and true}x{/if}", vars)

  test "errors on type mismatch in comparison":
    let vars = {"a": toArgValue("string"), "b": toArgValue(42)}.toTable
    expect TemplateError:
      discard renderTemplate("{#if a == b}x{/if}", vars)

  test "errors on non-numeric comparison operators":
    let vars = {"a": toArgValue("string")}.toTable
    expect TemplateError:
      discard renderTemplate("{#if a > 10}x{/if}", vars)

  test "int and float comparison works":
    let vars = {"i": toArgValue(10), "f": toArgValue(10.5)}.toTable
    check renderTemplate("{#if i < f}less{/if}", vars) == "less"
    check renderTemplate("{#if f > i}more{/if}", vars) == "more"

  test "real SQL template example":
    let tmpl =
      """SELECT * FROM users
WHERE city = 'Berlin'
{#if filterSize}  {#if sizeOp == 'large'}AND size > 100
  {:else if sizeOp == 'small'}AND size < 100
  {:else}AND size = 100
  {/if}{/if}ORDER BY id"""

    # No filter
    let vars1 = {"filterSize": toArgValue(false), "sizeOp": toArgValue("")}.toTable
    let result1 = renderTemplate(tmpl, vars1)
    check "AND size" notin result1

    # Large filter
    let vars2 = {"filterSize": toArgValue(true), "sizeOp": toArgValue("large")}.toTable
    let result2 = renderTemplate(tmpl, vars2)
    check "AND size > 100" in result2

    # Small filter
    let vars3 = {"filterSize": toArgValue(true), "sizeOp": toArgValue("small")}.toTable
    let result3 = renderTemplate(tmpl, vars3)
    check "AND size < 100" in result3
