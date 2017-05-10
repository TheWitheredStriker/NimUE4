# Copyright 2016 Xored Software, Inc.
import ropes, hashes, macros, strutils, sequtils

import "../lib/macroutils"

type
  MacroOptKind = enum
    mokKey,
    mokVal,
    mokKeyVal

  MacroOpt = object
    kind: MacroOptKind
    key: string
    val: string

  TypeKind = enum
    tkClass,
    tkStruct,
    tkInterface,
    tkEnum,
    tkPlainClass

  VarDeclaration = ref object
    name: Rope
    genName: Rope
    typeNode: NimNode
    defaultValue: NimNode

  TypeOpt = enum
    coExported

  # TODO: turn all these bools into set[enum] already...
  TypeMethod = ref object
    name: Rope
    genName: Rope
    isVirtual: bool
    isOverride: bool
    isConstructor: bool
    isExported: bool
    isCallSuper: bool
    isCallSuperAfter: bool
    isAbstract: bool
    isUFunction: bool
    isStatic: bool
    isBpExtendable: bool
    isConst: bool
    isObjInitializer: bool
    isEditorOnly: bool
    isNoExceptionWrap: bool
    isRetConst: bool
    extendableName: Rope
    args: seq[VarDeclaration]
    uFunctionParamStr: Rope
      ## can be non-nil even for non-UFunction (for bpExpandable)
    node: NimNode

  TypeField = ref object
    name: Rope
    nameNode: NimNode
    valueType: Rope
    nimTypeNode: NimNode
    defaultValueNode: NimNode
    isUProperty: bool
    uPropertyParamStr: Rope

  TypeDefinition = ref object
    headerName: string
    isUtilityType: bool
    name: Rope
    kind: TypeKind
    paramStr: Rope
    parentNames: seq[string]
    fields: seq[TypeField]
    methods: seq[TypeMethod]
    opts: set[TypeOpt]

let exceptionHandlingStmt {.compileTime.} = parseStmt("""
let e = getCurrentException()
ueError("Unhandled exception: " & (if e.name.isNil: "nil" else: $e.name) & ": " & (if e.msg.isNil: "" else: e.msg & " ") & e.getStackTrace())
{.emit: "if (GLog != nullptr) {GLog->Flush();}".}
requestExit(false)
""")

proc isBlueprintNative(meth: TypeMethod): bool =
  result = meth.isUFunction and ($meth.uFunctionParamStr).contains("BlueprintNativeEvent")

proc isBlueprintImplementable(meth: TypeMethod): bool =
  result = meth.isUFunction and ($meth.uFunctionParamStr).contains("BlueprintImplementableEvent")

proc isImplementationNeeded(meth: TypeMethod): bool =
  result = not (meth.isAbstract or meth.isBlueprintNative() or meth.isBlueprintImplementable())

proc isNimOnly(meth: TypeMethod): bool =
  result = meth.isObjInitializer

template findIt[T](s: seq[T], pred: expr): T =
  var result {.gensym.}: T
  for it {.inject.} in s:
    if pred:
      result = it
      break
  result

proc cppReturnType(n: NimNode): Rope =
  assert(RoutineNodes.contains(n.kind))

  if n[3][0].kind == nnkEmpty:
    result = rope("void")
  else:
    result = toCppType(n[3][0])

proc doc(n: NimNode): string =
  assert(RoutineNodes.contains(n.kind))

  if n.body.len > 0 and n.body[0].kind == nnkCommentStmt:
    result = n.body[0].strVal

proc toCppLiteral(nimLiteral: NimNode): Rope =
  case nimLiteral.kind:
    of nnkStrLit..nnkTripleStrLit:
      result = rope(repr(nimLiteral.strVal))
    of nnkFloatLit..nnkFloat64Lit:
      result = rope(repr(nimLiteral.floatVal))
    of nnkCharLit:
      result = rope(repr(chr(nimLiteral.intVal)))
    of nnkIntLit..nnkUInt64Lit:
      result = rope($(nimLiteral.intVal))
    of nnkIdent:
      result = rope($nimLiteral.ident)
    of nnkNilLit:
      result = rope("0")
    else:
      parseError(nimLiteral, "literal type expected, but got " & $(nimLiteral.kind))

proc toCppArgList(args: seq[VarDeclaration], isUeSignature, isUFunction: bool = false, useGenName: bool = true): Rope {.compileTime.} =
  for i in 0 .. < args.len:
    if result.len != 0:
      result.add(", ")
    let valueType = toCppType(args[i].typeNode, isUeSignature, isUFunction)
    let name = if useGenName: args[i].genName else: args[i].name
    result.add(valueType & " " & name)

proc toCppSignature(meth: TypeMethod, methodName: Rope, isUeSignature, isUFunction: bool): Rope {.compileTime.} =
  result.add(if meth.isVirtual: "virtual " else: nil)
  result.add(if meth.isStatic: "static " else: nil)
  result.add(if meth.isRetConst: "const " else: nil)
  result.add(if not meth.isConstructor: meth.node.cppReturnType() else: nil)
  result.add(" " & methodName & "(" & toCppArgList(meth.args, isUeSignature, isUFunction, false) & ")")
  result.add(if meth.isConst: " const" else: nil)
  result.add(if meth.isOverride: " override" else: nil)

proc toCppFieldName(name: string, valueType: string): Rope {.compileTime.} =
  if valueType == "bool":
    result = rope(name)
  else:
    result = rope(name.capitalizeAscii())

proc genName(name: string, relatedNode: NimNode): Rope {.compileTime.} =
  result = rope(name) & "_nim"

proc toExprEqExpr(node: NimNode): NimNode =
  result = node
  if node.kind == nnkExprColonExpr:
    result = newNimNode(nnkExprEqExpr)
    node.copyChildrenTo(result)
  for childIdx in 0..<result.len:
    result[childIdx] = toExprEqExpr(result[childIdx])

proc extractParamString(callNode: NimNode): Rope =
  ## Extracts string in parens from an expression like
  ## CALL(param1, param2, param3 = value)
  assert(callNode.kind == nnkCall)

  for i in 1 .. callNode.len - 2:
    if result.len != 0:
      result.add(", ")
    if callNode[i].kind notin {nnkIdent, nnkExprEqExpr, nnkExprColonExpr}:
      parseError(callNode[i], "expected ident, assignment or colon expression")
    result.add(toExprEqExpr(callNode[i]).toStrLit.strVal)

template addWithComma(str: expr, addition: expr) =
  if str.len > 0:
    str.add(",")
  str.add(addition)

proc identDefsToTypeField(identDefs: NimNode): TypeField =
  assert(identDefs.kind == nnkIdentDefs)
  var nameNode = identDefs[0]
  let fieldName = $extractIdent(nameNode)
  let typeNode = identDefs[1]
  let defaultValueNode = identDefs[2]

  var isUProperty = removePragma(nameNode, "ue")
  var uPropertyParamStr: Rope
  var displayName: string = nil

  if nameNode.kind == nnkPragmaExpr:
    let pragmaNode = nameNode[1]
    for ident, val, i in pragmas(pragmaNode):
      if ident == !"category":
        let category = val
        if category == nil:
          parseError(pragmaNode, "value expected for category")
        if category.contains('"'):
          parseError(pragmaNode, "category name must not contain quotes")
        uPropertyParamStr.addWithComma("Category = \"" & category & "\"")
      elif ident == !"ue":
        if val != nil:
          displayName = val
      elif ident == !"bpDelegate":
        if val != nil:
          displayName = val
        uPropertyParamStr.addWithComma("BlueprintAssignable")
      elif ident == !"config":
        if val != nil:
          parseError(pragmaNode, "value is not expected for config pragma")
        uPropertyParamStr.addWithComma("Config")
      elif ident == !"transient":
        if val != nil:
          parseError(pragmaNode, "value is not expected for transient pragma")
        uPropertyParamStr.addWithComma("transient")
      elif ident == !"bpReadOnly":
        if val != nil:
          displayName = val
        uPropertyParamStr.addWithComma("BlueprintReadOnly")
      elif ident == !"bpReadWrite":
        if val != nil:
          displayName = val
        uPropertyParamStr.addWithComma("BlueprintReadWrite")
      elif ident == !"editorReadOnly":
        if val != nil:
          displayName = val
        uPropertyParamStr.addWithComma("VisibleAnywhere")
      elif ident == !"editorReadWrite":
        if val != nil:
          displayName = val
        uPropertyParamStr.addWithComma("EditAnywhere")
      else: continue
      isUProperty = true
      pragmaNode.del(i)
    if pragmaNode.len == 0:
      nameNode = nameNode[0]

  if displayName != nil:
    uPropertyParamStr.addWithComma("meta=(DisplayName = \"" & displayName & "\")")

  result = TypeField(name: rope(fieldName),
                     nameNode: nameNode,
                     valueType: toCppType(typeNode),
                     nimTypeNode: typeNode,
                     defaultValueNode: defaultValueNode,
                     isUProperty: isUProperty,
                     uPropertyParamStr: uPropertyParamStr)

proc parseField(node: NimNode): TypeField =
  assert(node.kind == nnkVarSection)

  let identDefs = node[0]
  result = identDefsToTypeField(identDefs)

proc parseUProperty(typeKind: TypeKind, uPropertyNode: NimNode): seq[TypeField] =
  assert(uPropertyNode.kind == nnkCall and uPropertyNode[0].ident == !"UProperty")

  if uPropertyNode[^1].kind != nnkStmtList or uPropertyNode[^1][0].kind != nnkVarSection:
    parseError(uPropertyNode, "expected field declaration after UProperty")

  let paramString = extractParamString(uPropertyNode)
  result = newSeq[TypeField](uPropertyNode[^1].len)
  for i in 0..<uPropertyNode[^1].len:
    if uPropertyNode[^1][i].kind != nnkVarSection:
      parseError(uPropertyNode[^1][i], "expected field declaration after UProperty")
    result[i] = parseField(uPropertyNode[^1][i])
    if result[i].isUProperty:
      parseError(uPropertyNode[^1][i], "UE pragmas are not compatible with UProperty block")
    result[i].isUProperty = true
    result[i].uPropertyParamStr = paramString

proc parseArgs(node: NimNode): seq[VarDeclaration] =
  assert(node.kind == nnkFormalParams)
  result = @[]
  for i in 1 .. < node.len:
    let identDefs = node[i]
    if identDefs.kind != nnkIdentDefs:
      break
    if identDefs[^2].kind == nnkEmpty:
      parseError(identDefs, "type inference is not supported for arguments")

    for nameIndex in 0 .. < identDefs.len - 2:
      let name = $(identDefs[nameIndex].ident)
      let varDecl = VarDeclaration(
        name: rope(name),
        genName: genName(name, node),
        typeNode: identDefs[^2],
        defaultValue: nil
      )
      result.add(varDecl)

proc parseMethod(className: string, node: NimNode): TypeMethod =
  assert(node.kind == nnkProcDef or node.kind == nnkMethodDef)

  if node[2].kind == nnkGenericParams:
    raise newException(ParseError, lineinfo(node[2]) & ": generic params are not supported for now")

  let name = $(node[0].basename.ident)

  # TODO: move into the loop below for better performance
  let isOverride = removePragma(node, "override")
  let isConstructor = removePragma(node, "constructor")
  let isAbstract = removePragma(node, "abstract")
  let isVirtual = removePragma(node, "virtual") or (node.kind == nnkMethodDef) or isOverride or isAbstract
  let isCallSuper = removePragma(node, "callSuper")
  let isCallSuperAfter = removePragma(node, "callSuperAfter")
  let isConst = removePragma(node, "thisConst")
  let isStatic = removePragma(node, "isStatic")
  let isObjInitializer = removePragma(node, "objInitializer")
  let isEditorOnly = removePragma(node, "editorOnly")
  let isNoExceptionWrap = removePragma(node, "noExceptionWrap")
  let isRetConst = removePragma(node, "retConst")
  # TODO: more checks for objInitializer

  var isUFunction = removePragma(node, "ue")
  var uFunctionParamStr: Rope
  var displayName: string = nil
  var isBpExtendable = false
  var extendableName: Rope

  for ident, val, i in pragmas(node.pragma):
    if ident == !"category":
      let category = val
      if category == nil:
        parseError(node, "value expected for category")
      if category.contains('"'):
        parseError(node, "category name must not contain quotes")
      uFunctionParamStr.addWithComma("Category = \"" & category & "\"")
    elif ident == !"console":
      isUFunction = true
      uFunctionParamStr.addWithComma("Exec")
    elif ident == !"bpCallable":
      isUFunction = true
      if val != nil:
        displayName = val
      uFunctionParamStr.addWithComma("BlueprintCallable")
    elif ident == !"bpOverridable":
      isUFunction = true
      if val != nil:
        displayName = val
      if node.body.kind != nnkEmpty:
        uFunctionParamStr.addWithComma("BlueprintNativeEvent")
      else:
        uFunctionParamStr.addWithComma("BlueprintImplementableEvent")
    elif ident == !"bpExtendable":
      extendableName = rope(val)
      isBpExtendable = true
    else: continue
    node.pragma.del(i)

  if isBpExtendable and isUFunction:
    parseError(node, "bpExtendable is not compatible with other BP pragmas")

  if displayName != nil:
    if displayName.contains('"'):
      parseError(node, "the display name must not contain quotes")
    uFunctionParamStr.addWithComma("meta=(DisplayName = \"" & displayName & "\")")

  if (isCallSuper or isCallSuperAfter) and not (isOverride or isConstructor):
    parseError(node, "can only call super from constructor or overriden methods")

  if isOverride and isAbstract:
    parseError(node, "cannot override and be abstract at the same time")

  var procNode = newNimNode(nnkProcDef)
  node.copyChildrenTo(procNode)

  # remove "type modifiers" such as "bycopy"
  for i in 1 .. <procNode[3].len:
    var identDefs = procNode[3][i]
    if identDefs[1].kind == nnkCommand:
      identDefs[1] = identDefs[1][1]

  let methName = rope(if isConstructor: className else: name)
  result = TypeMethod(
    name: methName,
    genName: rope(className) & "_" & genName(name, node),
    isAbstract: isAbstract,
    isOverride: isOverride,
    isVirtual: isVirtual,
    isConstructor: isConstructor,
    isCallSuper: isCallSuper,
    isCallSuperAfter: isCallSuperAfter,
    isConst: isConst,
    isExported: true, # TODO
    isUFunction: isUFunction,
    isObjInitializer: isObjInitializer,
    isStatic: isStatic,
    uFunctionParamStr: uFunctionParamStr,
    isBpExtendable: isBpExtendable,
    isEditorOnly: isEditorOnly,
    isNoExceptionWrap: isNoExceptionWrap,
    isRetConst: isRetConst,
    extendableName: extendableName,
    args: parseArgs(node[3]),
    node: procNode
  )

proc parseUFunction(className: string, node: NimNode): seq[TypeMethod] =
  assert(node.kind == nnkCall and node[0].ident == !"UFunction")
  const supportedRoutines = {nnkProcDef, nnkMethodDef}

  let paramString = extractParamString(node)
  result = newSeq[TypeMethod](node[^1].len)
  for i in 0..<node[^1].len:
    if not supportedRoutines.contains(node[^1][i].kind):
      parseError(node[^1][0], "expected proc or mehtod declaration after `UFunction`")
    result[i] = parseMethod(className, node[^1][i])
    if result[i].isUFunction:
      parseError(node, "shortcut pragmas are not allowed for fully-specified UFunction")

    result[i].isUFunction = true
    result[i].uFunctionParamStr = paramString

proc extractNames(kind: TypeKind, definition: NimNode): tuple[name: string, parentNames: seq[string]] =
  var name: string = nil
  var parentNames: seq[string] = @[]
  if definition.kind == nnkIdent:
    name = $(definition.ident)
  else:
    assert(definition.kind == nnkInfix and definition[0].ident == !"of")
    name = $(definition[1].ident)
    case definition[2].kind:
      of nnkIdent:
        parentNames.add($(definition[2].ident))
      of nnkPar:
        for id in definition[2]:
          assert(id.kind == nnkIdent, "identifier expected")
          parentNames.add($(id.ident))
      else:
        parseError(definition[2], "parent type(s) expected")

  # Verify UE type naming conventions
  macroCheck(definition, name.len > 2 and name[0].isUpper() and name[1].isUpper(),
             "The name must follow UE4 naming conventions (have a proper prefix letter)")
  case kind:
    of tkClass:
      macroCheck(definition, name.startsWith("F") or name.startsWith("A") or name.startsWith("U"),
                 "Class name must start with A, U or F letter, depending on parent class") # TODO: check parent class
    of tkStruct:
      macroCheck(definition, name.startsWith("F"),
                 "Struct name must start with an F")
    of tkPlainClass:
      macroCheck(definition, name.startsWith("F") or name.startsWith("S"),
                 "Plain class name must start with an F or an S (for Slate widgets)")
    of tkInterface:
      macroCheck(definition, name.startsWith("I"),
                 "Interface name must start with an I")
      macroCheck(definition, parentNames.allIt(it.startsWith("I")),
                 "Interface must only inherit from other interfaces")
    of tkEnum:
      macroCheck(definition, name.startsWith("E"),
                 "Enum must start with an E")

  result = (name, parentNames)

proc genCppFields(typeDef: TypeDefinition): Rope {.compileTime.} =
  for field in typeDef.fields:
    if field.isUProperty:
      result.add("UPROPERTY(" & field.uPropertyParamStr & ")\n")
    if typeDef.kind == tkEnum:
      result.add(field.name)
      result.add(",\n")
    else:
      result.add(field.valueType)
      result.add(" ")
      result.add(toCppFieldName($field.name, $field.valueType))
      if field.defaultValueNode != nil and field.defaultValueNode.kind != nnkEmpty:
        result.add(" = " & toCppLiteral(field.defaultValueNode))
      result.add(";\n")

proc genCppMethod(typeDef: TypeDefinition, meth: TypeMethod): Rope {.compileTime.} =
  if meth.isEditorOnly:
    result.add("#if WITH_EDITOR\n")
  var friendArgList = toCppArgList(meth.args, isUeSignature = false)
  let returnType = if meth.isConstructor: rope("void") else: meth.node.cppReturnType()
  var friendSignature = rope("friend ") & returnType & " `" & meth.genName & "`("
  if not typeDef.isUtilityType:
    friendSignature.add(typeDef.name & "*")
    if friendArgList.len != 0:
      friendSignature.add(", ")
  friendSignature.add(friendArgList)
  friendSignature.add(");\n")

  let methNameCapitalized = rope(($meth.name).capitalizeAscii())
  let signature = toCppSignature(meth, methNameCapitalized, isUeSignature = true, isUFunction = meth.isUFunction)

  if meth.isImplementationNeeded() or meth.isBlueprintNative():
    # friend declaration is needed so that Nim procs have access to
    # private/protected fields
    result.add(friendSignature)

  let doc = meth.node.doc()
  if doc != nil:
    result.add("/** \n")
    for line in doc.splitLines():
      result.add(" *  " & line & "\n")
    result.add(" */\n")
  if meth.isUFunction:
    result.add("UFUNCTION($#)\n".format(meth.uFunctionParamStr))

  result.add(signature)
  if meth.isAbstract:
    result.add(" = 0;\n")
  else:
    result.add(";\n")

  if meth.isEditorOnly:
    result.add("#endif //WITH_EDITOR\n")

proc genCppMethods(typeDef: TypeDefinition): Rope {.compileTime.} =
  for meth in typeDef.methods:
    if meth.isNimOnly(): continue
    result.add(genCppMethod(typeDef, meth))
    if meth.isBpExtendable:
      var bpMeth = TypeMethod(
        name: rope("Receive" & ($meth.name).capitalizeAscii()),
        genName: meth.genName,
        args: meth.args,
        node: meth.node,
        isUFunction: true
      )
      let displayName = if meth.extendableName != nil: meth.extendableName
                        else: rope(($meth.name).capitalizeAscii())
      bpMeth.uFunctionParamStr = rope("BlueprintImplementableEvent, meta=(DisplayName=\"") & displayName & "\")"
      bpMeth.uFunctionParamStr.addWithComma(meth.uFunctionParamStr)
      result.add(genCppMethod(typeDef, bpMeth))

proc genCppImplementationCode(typeDef: TypeDefinition): string {.compileTime.} =
  var code: Rope
  for meth in typeDef.methods:
    if meth.isNimOnly(): continue
    if meth.isEditorOnly: code.add("#if WITH_EDITOR\n")
    let methNameCapitalized = ($meth.name).capitalizeAscii()
    if (meth.isBlueprintNative or meth.isImplementationNeeded) and not meth.isConstructor:
      if meth.isRetConst:
        code.add("const ")
      code.add(meth.node.cppReturnType())
      code.add(" ")

    if meth.isBlueprintNative:
      code.add(typeDef.name & "::" & methNameCapitalized & "_Implementation")
      code.add("(" & toCppArgList(meth.args, isUeSignature = true, isUFunction = false, false) & ")")
    elif meth.isImplementationNeeded():
      code.add(typeDef.name & "::" & methNameCapitalized)
      code.add("(" & toCppArgList(meth.args, isUeSignature = true, isUFunction = meth.isUFunction, false) & ")")

    if meth.isBlueprintNative or meth.isImplementationNeeded:
      let invocationArgs = meth.args.mapIt($(it.name)).join(", ")
      var superInvocation = if meth.isConstructor: rope("Super") & "(" & invocationArgs & ")"
                            else: rope("Super::") & methNameCapitalized & "(" & invocationArgs & ");\n"
      let objInitializer = if meth.isConstructor: typeDef.methods.findIt(it.isObjInitializer) else: nil

      if meth.isConstructor:
        if objInitializer != nil:
          if invocationArgs.len > 0:
            parseError(meth.node, "objInitializer is only allowed for default (no arg) constructor")
          superInvocation = rope("Super") & "(*`" & objInitializer.genName & "`(FObjectInitializer::Get()))"
        if typeDef.parentNames.len > 0:
          code.add(":")
          code.add(superInvocation)

      if meth.isConst:
        code.add(" const")

      code.add(" {\n ")

      if meth.isCallSuper and not meth.isConstructor:
        code.add(superInvocation)
      elif meth.isConstructor and typeDef.parentNames.len == 0 and objInitializer != nil:
        code.add("`" & objInitializer.genName & "`(FObjectInitializer::Get());\n")

      if meth.node.body.kind != nnkEmpty:
        var invocationCode: Rope
        for arg in meth.args:
          if invocationCode.len != 0:
            invocationCode.add(", ")
          invocationCode.add(arg.name)
        let needReturn = not(meth.isBpExtendable or meth.isCallSuperAfter or meth.isConstructor or $(meth.node.cppReturnType()) == "void")
        let returnOrNothing = rope(if needReturn: "return" else: "")
        var thisOrNothing = rope(if meth.isStatic: "" elif meth.isConst: "const_cast<" & $typeDef.name & "*>(this)" else: "this")
        if thisOrNothing.len != 0 and invocationCode.len != 0:
          invocationCode = ", " & invocationCode
        invocationCode = thisOrNothing & invocationCode
        code.addf("$# `$#`($#);\n",
                  [returnOrNothing, meth.genName, invocationCode])

      if meth.isBpExtendable:
        let returnOrNothing = if $(meth.node.cppReturnType()) == "void": "" else: "return "
        code.add(returnOrNothing & "`this`->Receive" & methNameCapitalized & "(" & invocationArgs & ");\n")

      if meth.isCallSuperAfter:
        let returnOrNothing = if $(meth.node.cppReturnType()) == "void": "" else: "return "
        code.add(returnOrNothing)
        code.add(superInvocation)

      code.add("}\n\n")
    if meth.isEditorOnly: code.add("#endif //WITH_EDITOR\n")

  if code.len != 0:
    code = rope("/*VARSECTION*/") & code

  result = $code

proc genCppDeclarationCode(typeDef: TypeDefinition): string {.compileTime.} =
  let typeMacro = case typeDef.kind:
    of tkClass: "UCLASS($#)\n" % $typeDef.paramStr
    of tkStruct: "USTRUCT($#)\n" % $typeDef.paramStr
    of tkEnum: "UENUM($#)\n" % $typeDef.paramStr
    of tkInterface, tkPlainClass: ""

  let generatedBodyMacro = case typeDef.kind:
    of tkClass: "GENERATED_BODY()\n"
    of tkStruct: "GENERATED_USTRUCT_BODY()\n"
    of tkInterface: "GENERATED_IINTERFACE_BODY()\n"
    of tkEnum, tkPlainClass: ""

  let typeKindStr = case typeDef.kind:
    of tkClass, tkInterface, tkPlainClass: "class"
    of tkStruct: "struct"
    of tkEnum: "enum class"

  let isAbstractClass = typeDef.methods.anyIt(it.isAbstract)

  var inheritanceExpr = if typeDef.parentNames.len == 0: nil
    else: rope(" : ") & typeDef.parentNames.mapIt("public `" & it & "`").join(", ") & " "

  if typeDef.kind == tkEnum:
    inheritanceExpr = rope(" : uint8")

  let interfaceHelperType = if typeDef.kind != tkInterface: "" else: """
/*BEGIN_UNREAL_TYPE*/
UINTERFACE($1)
class $2 : public `UInterface`
{
  GENERATED_UINTERFACE_BODY()
};
/*END_UNREAL_TYPE*/
$2::$2(const `FObjectInitializer`& ObjectInitializer): Super(ObjectInitializer)
{
}
""".format($typeDef.paramStr, "U" & ($typeDef.name)[1..^1])

  var code = rope("/*TYPESECTION*/\n")
  code.add(interfaceHelperType)
  code.add("/*BEGIN_UNREAL_TYPE*/\n")

  code.add(typeMacro)

  code.add(typeKindStr & " ")
  let exportPlaceholder = if typeDef.opts.contains(coExported): "/*EXPORT_MACRO_PLACEHOLDER*/ " else: ""
  code.add(exportPlaceHolder)
  code.add(typeDef.name & " ")
  code.add(inheritanceExpr)
  code.add("{\n")

  # if not isAbstractClass:
  code.add(generatedBodyMacro)

  if typeDef.kind != tkEnum:
    code.add("public:\n")

  code.add(genCppFields(typeDef))
  code.add(genCppMethods(typeDef))

  code.add("};/*END_UNREAL_TYPE*/\n")

  result = $code

proc genType(typeDef: TypeDefinition): NimNode {.compileTime.} =
  var methDecls: seq[NimNode] = @[]
  var methDefs: seq[NimNode] = @[]
  for meth in typeDef.methods:
    var nodeCopy = meth.node.copyNimTree()
    if not (typeDef.isUtilityType or meth.isStatic or meth.isObjInitializer):
      let thisDef = newNimNode(nnkIdentDefs).add(
        ident("this"), newNimNode(nnkPtrTy).add(ident($typeDef.name)), newEmptyNode())
      nodeCopy[3].insert(1, thisDef)

    if not meth.isConstructor:
      var decl = nodeCopy.copy()
      decl[^1] = newEmptyNode() # remove body
      let cppName = ($meth.name).capitalizeAscii()
      let cppPattern = if typeDef.isUtilityType: $typeDef.name & "::" & cppName & "(@)"
                       else: "#." & cppName & "(@)"
      decl.pragma = parseExpr("{.header: \"$1\", importcpp: \"$2\", nodecl.}".format(typeDef.headerName, cppPattern))
      if meth.isEditorOnly:
        decl = wrapIntoWhen(ident("withEditor"), decl)
      methDecls.add(decl)

    nodeCopy[0] = ident($meth.genName)

    if meth.isImplementationNeeded() or meth.isBlueprintNative():
      if not (meth.isBpExtendable or meth.isBlueprintNative()) or nodeCopy.body.kind != nnkEmpty:
        when not defined(dontWrapNimExceptions):
          if not hasPragma(nodeCopy, "noSideEffect") and not meth.isNoExceptionWrap:
            nodeCopy.body = newStmtList(
              newNimNode(nnkTryStmt).
                add(nodeCopy.body).
                add(
                newNimNode(nnkExceptBranch).
                  add(exceptionHandlingStmt.copyNimTree())))

        let methDef = if meth.isEditorOnly: wrapIntoWhen(ident("withEditor"), nodeCopy)
                      else: nodeCopy
        methDefs.add(methDef)

  if typeDef.kind != tkEnum and not typeDef.isUtilityType:
    let staticClassMeth = parseStmt("""
    proc staticClass*(ty: typedesc[$1]): TSubclassOf[$1] {.header: "$2", importc: "$1::StaticClass".}
""".format(typeDef.name, typeDef.headerName))
    methDecls.add(staticClassMeth)

  let primaryParentName: string = if typeDef.parentNames.len > 0: typeDef.parentNames[0] else: nil
  let ofPostfix = if primaryParentName != nil : " of " & primaryParentName else: ""
  let additionalPragmas = case typeDef.kind:
    of tkEnum: ", pure, size: sizeof(cint)"
    of tkStruct: ", inheritable, bycopy"
    else: ", inheritable"
  let nimTypeKind = if typeDef.kind == tkEnum: "enum" else: "object"
  let enumFields = if typeDef.kind == tkEnum:
    "\n  " & typeDef.fields.mapIt($it.name).join(",")
    else: ""

  var typeDecl = parseStmt("""type $1* {.header: "$2", importcpp: "$1"$3, bycopy, inheritable.} = $4$5$6""".format(
    typeDef.name, typeDef.headerName, additionalPragmas, nimTypeKind, ofPostfix, enumFields))

  if typeDef.kind != tkEnum:
    var recList = newNimNode(nnkRecList)
    for field in typeDef.fields:
      let pragmaNode = newNimNode(nnkPragma).add(
        makeStrPragma("importcpp", $toCppFieldName($field.name, $field.valueType)))
      let varIdent = newNimNode(nnkPragmaExpr).add(field.nameNode, pragmaNode)
      recList.add(newNimNode(nnkIdentDefs).add(varIdent, field.nimTypeNode, newEmptyNode()))
    typeDecl[0][0][2][2] = recList

  result = newStmtList()
  result.add(newNimNode(nnkPragma).add(
              newNimNode(nnkExprColonExpr).add(ident("this"), ident("this"))))
  if not typeDef.isUtilityType:
    result.add(typeDecl)

  for nameInd in 1 .. < typeDef.parentNames.len:
    # generate converter for each secondary parent type
    let parentName = typeDef.parentNames[nameInd]
    var conv = newProc(
      name = postfix(ident("to" & parentName), "*"),
      params = [newNimNode(nnkPtrTy).add(ident(parentName)),
                newIdentDefs(ident("this"), newNimNode(nnkPtrTy).add(ident($typeDef.name)))],
      body = newEmptyNode(),
      procType = nnkConverterDef
    )
    conv.pragma = newNimNode(nnkPragma)
    conv.pragma.add(makeStrPragma("importcpp", "#"))
    conv.pragma.add(ident("nodecl"))
    result.add(conv)

  result.add(methDecls)
  result.add(methDefs)

  let declarationCode = genCppDeclarationCode(typeDef)
  let implementationCode = genCppImplementationCode(typeDef)

  result.add(newNimNode(nnkPragma).add(
              newNimNode(nnkExprColonExpr).add(ident("emit"), newStrLitNode(declarationCode))))

  if implementationCode.len != 0:
    result.add(newNimNode(nnkPragma).add(
              newNimNode(nnkExprColonExpr).add(ident("emit"), newStrLitNode(implementationCode))))

proc parseType(kind: TypeKind, definition: NimNode, callSite: NimNode): TypeDefinition =
  let body = callSite[^1]
  let (name, parentNames) = extractNames(kind, definition)

  var opts: set[TypeOpt] = {}
  var paramStrs: seq[string] = @[]
  for i in 2 .. len(callSite) - 2:
    let optNode = callSite[i]
    if optNode.kind == nnkIdent and optNode.ident == !"exported":
      opts.incl(coExported)
    else:
      paramStrs.add(optNode.toStrLit.strVal)
  let paramString = paramStrs.join(", ")

  var methods: seq[TypeMethod] = @[]
  var fields: seq[TypeField] = @[]
  for statement in body:
    case statement.kind:
      of nnkCall:
        if statement[0].ident == !"UProperty":
          assert(kind != tkInterface)
          fields.add(parseUProperty(kind, statement))
        elif statement[0].ident == !"UFunction":
          var ufunctions = parseUFunction(name, statement)
          for meth in ufunctions:
            if kind == tkInterface:
              meth.isVirtual = true
              meth.isAbstract = true
          methods.add(ufunctions)
        else:
          parseError(statement, "expected UProperty or UFunction")
      of nnkVarSection:
        assert(kind != tkInterface)
        fields.add(parseField(statement))
      of nnkProcDef, nnkMethodDef:
        var meth = parseMethod(name, statement)
        if kind == tkInterface:
          meth.isVirtual = true
          meth.isAbstract = true
        if kind == tkInterface and meth.isUFunction:
          # UHT does some magic behind the scenes to make the method virtual
          # and overridable from blueprints
          meth.isVirtual = false
          meth.isAbstract = false
        methods.add(meth)
      of nnkIdent:
        if kind != tkEnum:
          parseError(statement, "field or method declaration expected")
        let field = TypeField(
          name: rope($statement.ident),
          nameNode: statement
        )
        fields.add(field)
      else:
        parseError(statement, "field or method declaration expected")

  result = TypeDefinition(
    headerName: cppHeaderName(definition),
    name: rope(name),
    kind: kind,
    parentNames: parentNames,
    paramStr: rope(paramString),
    fields: fields,
    methods: methods,
    opts: opts
  )

proc checkCategory(node: NimNode, category: string) =
  if category == nil:
    parseError(node, "category is mandatory for blueprints")
  if category.contains('"'):
    parseError(node, "category name must not contain quotes")

proc convertBlueprintFunction(function: NimNode, category: string): NimNode =
  ## Generates nnkStmtList that turns the specified procedure into UE4 blueprint function
  ## that is accessible from Nim, too
  assert (function.kind == nnkProcDef)

  if function.removePragma("noBlueprint"):
    return function

  let name = $(extractIdent(function.name).ident)

  let uFunctionParamStr = rope("BlueprintCallable, Category=\"") & category & "\""
  let methods = @[TypeMethod(
    name: rope(name),
    genName: genName(name, function),
    isStatic: true,
    args: parseArgs(function[3]),
    isUFunction: true,
    uFunctionParamStr: uFunctionParamStr,
    node: function,
  )]

  let typeDef = TypeDefinition(
    headerName: cppHeaderName(function),
    isUtilityType: true,
    name: rope("UBlueprintLibraryStub_" & name),
    kind: tkClass,
    parentNames: @["UBlueprintFunctionLibrary"],
    fields: @[],
    methods: methods
  )
  result = genType(typeDef)

proc convertBlueprintObject(objNode: NimNode, category: string): NimNode =
  assert(objNode.kind == nnkTypeDef and objNode[2].kind == nnkObjectTy)

  let name = $(extractIdent(objNode[0]).ident)
  let objTy = objNode[2]
  let parentName = if objTy[1].kind == nnkOfInherit: $objTy[1][0].ident else: nil

  var fields = newSeq[TypeField]()
  for fieldIdentDefs in objTy[2]:
    var field = identDefsToTypeField(fieldIdentDefs)
    field.isUProperty = true
    field.uPropertyParamStr = rope("EditAnywhere, BlueprintReadWrite, Category = \"") & category & "\""
    fields.add(field)

  let typeDef = TypeDefinition(
    headerName: cppHeaderName(objNode),
    name: rope(name),
    paramStr: rope("BlueprintType"),
    kind: tkStruct,
    parentNames: if parentName != nil: @[parentName] else: @[],
    fields: fields,
    methods: @[]
  )
  result = genType(typeDef)

proc convertBlueprintEnum(enumNode: NimNode, category: string): NimNode =
  assert(enumNode.kind == nnkTypeDef and enumNode[2].kind == nnkEnumTy)
  let name = $(extractIdent(enumNode[0]).ident)

  let enumTy = enumNode[2]

  var fields = newSeq[TypeField]()
  for fieldIdx in 1..<enumTy.len:
    let enumFieldIdent = enumTy[fieldIdx]
    let field = TypeField(
      name: rope($enumFieldIdent.ident),
      nameNode: enumFieldIdent
    )
    fields.add(field)

  let typeDef = TypeDefinition(
    headerName: cppHeaderName(enumNode),
    name: rope(name),
    paramStr: rope("BlueprintType"),
    kind: tkEnum,
    parentNames: @[],
    fields: fields,
    methods: @[]
  )
  result = genType(typeDef)

proc convertBlueprintType(typeNode: NimNode, category: string): NimNode =
  ## Generates nnkStmtList that turns the specified type definition
  ## into UE4 blueprint type that is accessible from Nim, too
  assert(typeNode.kind == nnkTypeDef)
  checkCategory(typeNode, category)

  if typeNode[1].kind != nnkEmpty:
    parseError(typeNode[1], "Generic params are not supported for blueprint types for now")

  let name = $(extractIdent(typeNode[0]).ident)
  case typeNode[2].kind:
  of nnkObjectTy:
    result = convertBlueprintObject(typeNode, category)
  of nnkEnumTy:
    result = convertBlueprintEnum(typeNode, category)
  else:
    parseError(typeNode[2], "only object and enum types are supported for blueprints")

iterator parseMacroOpts(callSite: NimNode; part: Slice[int]): MacroOpt =
  for i in part:
    let optNode = callSite[i]
    var opt: MacroOpt
    case optNode.kind:
    of nnkExprEqExpr, nnkExprColonExpr:
      if optNode[0].kind != nnkIdent or optNode[1].kind != nnkStrLit:
        parseError(optNode, "Key-value pair expected but found " & repr(optNode))
      opt.kind = mokKeyVal
      opt.key = ($optNode[0].ident).toLower
      opt.val = optNode[1].strVal
    of nnkIdent:
      opt.kind = mokKey
      opt.key = ($optNode[0].ident).toLower
    of nnkStrLit:
      opt.kind = mokVal
      opt.val = optNode.strVal
    else: parseError(optNode, "Unhandled option: " & repr(optNode))
    yield opt

macro uclass*(definition: expr, body: stmt): stmt {.immediate.} =
  let typeDef = parseType(tkClass, definition, callsite())
  result = genType(typeDef)

macro ustruct*(definition: expr, body: stmt): stmt {.immediate.} =
  let typeDef = parseType(tkStruct, definition, callsite())
  result = genType(typeDef)

macro uinterface*(definition: expr, body: stmt): stmt {.immediate.} =
  let typeDef = parseType(tkInterface, definition, callsite())
  result = genType(typeDef)

macro uenum*(definition: expr, body: stmt): stmt {.immediate.} =
  let typeDef = parseType(tkEnum, definition, callsite())
  result = genType(typeDef)

macro class*(definition: expr, body: stmt): stmt {.immediate.} =
  let typeDef = parseType(tkPlainClass, definition, callsite())
  result = genType(typeDef)

macro blueprint*(function: stmt): stmt {.immediate.} =
  if function.kind != nnkProcDef:
    parseError(function, "blueprint pragma is only supported for procs")
  let category = function.removeStrPragma("category")
  if category == nil:
    parseError(function, "blueprint function must have .category pragma")

  result = convertBlueprintFunction(function, category)

macro blueprintSection*(params: expr, body: stmt): stmt {.immediate.} =
  var category: string
  for opt in parseMacroOpts(callsite(), 1..len(callsite()) - 2):
    var handled = true
    case opt.kind:
    of mokKeyVal:
      case opt.key:
      of "category":
        category = opt.val
      else: handled = false
    of mokVal:
      if category == nil:
        category = opt.val
      else:
        handled = false
    else: handled = false
    if not handled:
      parseError(callsite(), "Unknown blueprint section option: " & opt.key)

  if category == nil:
    parseError(params, "category is mandatory for blueprint section")

  result = newStmtList()
  for statement in body:
    case statement.kind:
    of nnkProcDef:
      result.add(convertBlueprintFunction(statement, category))
    of nnkTypeSection:
      for typeDef in statement:
        result.add(convertBlueprintType(typeDef, category))
    else:
      parseError(statement, "only type and proc definitions are supported in blueprint section")