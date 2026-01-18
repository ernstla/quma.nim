import std/[tables, options]

import ./errors
import ./args
import ./tmplParser

proc typeName(v: ArgValue): string =
  case v.kind
  of avkNull: "null"
  of avkInt: "int"
  of avkFloat: "float"
  of avkString: "string"
  of avkBool: "bool"

proc typeName(e: Expr): string =
  case e.kind
  of ExprNull: "null"
  of ExprInt: "int"
  of ExprFloat: "float"
  of ExprString: "string"
  of ExprBool: "bool"
  of ExprVar: "variable"
  of ExprBinOp: "binary expression"
  of ExprUnaryOp: "unary expression"

proc makeError(scriptName: string, line: int, msg: string): ref TemplateError =
  let loc =
    if scriptName.len > 0:
      scriptName & ":" & $line
    else:
      "line " & $line
  newException(TemplateError, loc & ": " & msg)

proc evalExpr*(
    expr: Expr, vars: Table[string, ArgValue], scriptName: string = ""
): ArgValue =
  case expr.kind
  of ExprVar:
    if expr.varName notin vars:
      raise makeError(scriptName, expr.line, "Unknown variable: '" & expr.varName & "'")
    vars[expr.varName]
  of ExprString:
    ArgValue(kind: avkString, s: expr.strVal)
  of ExprInt:
    ArgValue(kind: avkInt, i: expr.intVal)
  of ExprFloat:
    ArgValue(kind: avkFloat, f: expr.floatVal)
  of ExprBool:
    ArgValue(kind: avkBool, b: expr.boolVal)
  of ExprNull:
    ArgValue(kind: avkNull)
  of ExprUnaryOp:
    # Only "not" is supported
    let operandVal = evalExpr(expr.operand, vars, scriptName)
    if operandVal.kind != avkBool:
      raise makeError(
        scriptName, expr.line, "Expected bool for 'not', got " & typeName(operandVal)
      )
    ArgValue(kind: avkBool, b: not operandVal.b)
  of ExprBinOp:
    let leftVal = evalExpr(expr.left, vars, scriptName)
    let rightVal = evalExpr(expr.right, vars, scriptName)
    case expr.binOp
    of BinAnd:
      if leftVal.kind != avkBool:
        raise makeError(
          scriptName, expr.line, "Expected bool for 'and', got " & typeName(leftVal)
        )
      if rightVal.kind != avkBool:
        raise makeError(
          scriptName, expr.line, "Expected bool for 'and', got " & typeName(rightVal)
        )
      ArgValue(kind: avkBool, b: leftVal.b and rightVal.b)
    of BinOr:
      if leftVal.kind != avkBool:
        raise makeError(
          scriptName, expr.line, "Expected bool for 'or', got " & typeName(leftVal)
        )
      if rightVal.kind != avkBool:
        raise makeError(
          scriptName, expr.line, "Expected bool for 'or', got " & typeName(rightVal)
        )
      ArgValue(kind: avkBool, b: leftVal.b or rightVal.b)
    of BinEq:
      # Allow comparison of same types, plus null with anything
      if leftVal.kind == avkNull or rightVal.kind == avkNull:
        ArgValue(kind: avkBool, b: leftVal.kind == rightVal.kind)
      elif leftVal.kind != rightVal.kind:
        # int/float comparison allowed
        if leftVal.kind == avkInt and rightVal.kind == avkFloat:
          ArgValue(kind: avkBool, b: float64(leftVal.i) == rightVal.f)
        elif leftVal.kind == avkFloat and rightVal.kind == avkInt:
          ArgValue(kind: avkBool, b: leftVal.f == float64(rightVal.i))
        else:
          raise makeError(
            scriptName,
            expr.line,
            "Cannot compare " & typeName(leftVal) & " with " & typeName(rightVal),
          )
      else:
        case leftVal.kind
        of avkInt:
          ArgValue(kind: avkBool, b: leftVal.i == rightVal.i)
        of avkFloat:
          ArgValue(kind: avkBool, b: leftVal.f == rightVal.f)
        of avkString:
          ArgValue(kind: avkBool, b: leftVal.s == rightVal.s)
        of avkBool:
          ArgValue(kind: avkBool, b: leftVal.b == rightVal.b)
        of avkNull:
          ArgValue(kind: avkBool, b: true)
    of BinNe:
      # Reuse BinEq logic
      let eqResult = evalExpr(
        Expr(
          kind: ExprBinOp,
          binOp: BinEq,
          left: expr.left,
          right: expr.right,
          line: expr.line,
          col: expr.col,
        ),
        vars,
        scriptName,
      )
      ArgValue(kind: avkBool, b: not eqResult.b)
    of BinLt, BinLe, BinGt, BinGe:
      # Numeric comparisons only
      var leftNum, rightNum: float64
      if leftVal.kind == avkInt:
        leftNum = float64(leftVal.i)
      elif leftVal.kind == avkFloat:
        leftNum = leftVal.f
      else:
        raise makeError(
          scriptName,
          expr.line,
          "Expected numeric type for comparison, got " & typeName(leftVal),
        )
      if rightVal.kind == avkInt:
        rightNum = float64(rightVal.i)
      elif rightVal.kind == avkFloat:
        rightNum = rightVal.f
      else:
        raise makeError(
          scriptName,
          expr.line,
          "Expected numeric type for comparison, got " & typeName(rightVal),
        )
      case expr.binOp
      of BinLt:
        ArgValue(kind: avkBool, b: leftNum < rightNum)
      of BinLe:
        ArgValue(kind: avkBool, b: leftNum <= rightNum)
      of BinGt:
        ArgValue(kind: avkBool, b: leftNum > rightNum)
      of BinGe:
        ArgValue(kind: avkBool, b: leftNum >= rightNum)
      else:
        ArgValue(kind: avkBool, b: false) # unreachable

proc evalToBool*(
    expr: Expr, vars: Table[string, ArgValue], scriptName: string = ""
): bool =
  let val = evalExpr(expr, vars, scriptName)
  if val.kind != avkBool:
    raise
      makeError(scriptName, expr.line, "Condition must be bool, got " & typeName(val))
  val.b

proc renderTemplate*(
    nodes: seq[TmplNode], vars: Table[string, ArgValue], scriptName: string = ""
): string =
  result = ""
  for node in nodes:
    case node.kind
    of TmplText:
      result.add node.text
    of TmplIf:
      if evalToBool(node.condition, vars, scriptName):
        result.add renderTemplate(node.thenBranch, vars, scriptName)
      else:
        var matched = false
        for branch in node.elseIfBranches:
          if evalToBool(branch.condition, vars, scriptName):
            result.add renderTemplate(branch.body, vars, scriptName)
            matched = true
            break
        if not matched and node.elseBranch.isSome:
          result.add renderTemplate(node.elseBranch.get.body, vars, scriptName)

proc renderTemplate*(
    templateStr: string, vars: Table[string, ArgValue], scriptName: string = ""
): string =
  let nodes = parseTemplate(templateStr, scriptName)
  renderTemplate(nodes, vars, scriptName)
