import tables, strutils, typetraits, macros

import datatypes

export datatypes
# import router
# export router

proc makeProcName(s: string): string =
  result = ""
  for c in s:
    if c.isAlphaNumeric: result.add c

proc hasReturnType(params: NimNode): bool =
  if params != nil and params.len > 0 and params[0] != nil and
     params[0].kind != nnkEmpty:
    result = true

proc firstArgument(params: NimNode): (NimNode, NimNode) =
  if params != nil and
      params.len > 0 and
      params[1] != nil and
      params[1].kind == nnkIdentDefs:
    result = (ident params[1][0].strVal, params[1][1])
  else:
    result = (ident "", newNimNode(nnkEmpty))

iterator paramsIter(params: NimNode): tuple[name, ntype: NimNode] =
  for i in 1 ..< params.len:
    let arg = params[i]
    let argType = arg[^2]
    for j in 0 ..< arg.len-2:
      yield (arg[j], argType)

proc identPub*(name: string): NimNode =
  result = nnkPostfix.newTree(newIdentNode("*"), ident name)

proc signalTuple*(sig: NimNode): NimNode =
  let otp = nnkEmpty.newTree()
  # echo "signalObjRaw:sig1: ", sig.treeRepr
  let sigTyp =
    if sig.kind == nnkSym: sig.getTypeInst
    else: sig.getTypeInst
  # echo "signalObjRaw:sig2: ", sigTyp.treeRepr
  let stp =
    if sigTyp.kind == nnkProcTy:
      sig.getTypeInst[0]
    else:
      sigTyp.params()
  let isGeneric = false

  # echo "signalObjRaw:obj: ", otp.repr
  # echo "signalObjRaw:obj:tr: ", otp.treeRepr
  # echo "signalObjRaw:obj:isGen: ", otp.kind == nnkBracketExpr
  # echo "signalObjRaw:sig: ", stp.repr

  var args: seq[NimNode]
  for i in 2..<stp.len:
    args.add stp[i]

  result = nnkTupleConstr.newTree()
  if isGeneric:
    template genArgs(n): auto = n[1][1]
    var genKinds: Table[string, NimNode]
    for i in 1..<stp.genArgs.len:
      genKinds[repr stp.genArgs[i]] = otp[i]
    for arg in args:
      result.add genKinds[arg[1].repr]
  else:
    # genKinds
    # echo "ARGS: ", args.repr
    for arg in args:
      result.add arg[1]
  # echo "ARG: ", result.repr
  # echo ""
  if result.len == 0:
    # result = bindSym"void"
    result = quote do:
      tuple[]

proc mkParamsVars(paramsIdent, paramsType, params: NimNode): NimNode =
  ## Create local variables for each parameter in the actual RPC call proc
  if params.isNil: return

  result = newStmtList()
  var varList = newSeq[NimNode]()
  var cnt = 0
  for paramid, paramType in paramsIter(params):
    let idx = newIntLitNode(cnt)
    let vars = quote do:
      var `paramid`: `paramType` = `paramsIdent`[`idx`]
    varList.add vars
    cnt.inc()
  result.add varList
  # echo "paramsSetup return:\n", treeRepr result

proc mkParamsType*(paramsIdent, paramsType, params, genericParams: NimNode): NimNode =
  ## Create a type that represents the arguments for this rpc call
  ## 
  ## Example: 
  ## 
  ##   proc multiplyrpc(a, b: int): int {.rpc.} =
  ##     result = a * b
  ## 
  ## Becomes:
  ##   proc multiplyrpc(params: RpcType_multiplyrpc): int = 
  ##     var a = params.a
  ##     var b = params.b
  ##   
  ##   proc multiplyrpc(params: RpcType_multiplyrpc): int = 
  ## 
  if params.isNil: return

  var tup = quote do:
    type `paramsType` = tuple[]
  for paramIdent, paramType in paramsIter(params):
    # processing multiple variables of one type
    tup[0][2].add newIdentDefs(paramIdent, paramType)
  result = tup
  result[0][1] = genericParams.copyNimTree()
  # echo "mkParamsType: ", genericParams.treeRepr

proc updateProcsSig(node: NimNode,
                    isPublic: bool,
                    gens: NimNode,
                    procLineInfo: LineInfo) =
  if node.kind in [nnkProcDef, nnkTemplateDef]:
    node[0].setLineInfo(procLineInfo)
    let name = node[0]
    if isPublic:
      node[0] = nnkPostfix.newTree(newIdentNode("*"), name)
    node[2] = gens.copyNimTree()
    node[^1].setLineInfo(procLineInfo)
  else:
    for ch in node:
      ch.updateProcsSig(isPublic, gens, procLineInfo)

proc makeGenerics*(node: NimNode, gens: seq[string], isIdentDefs = false) =
  discard
  if node.kind == nnkGenericParams:
    return
  else:
    for i, ch in node:
      # echo "MAKE GEN: CH: ", ch.treeRepr
      if ch.kind == nnkBracketExpr:
        var allIdents = true
        for n in ch:
          if n.kind notin [nnkIdentDefs, nnkIdent]: allIdents = false
        if not allIdents:
          break
        let idType = ch
        let genParam =
          if idType[1].kind == nnkIdentDefs:
            idType[1][0]
          else: idType[1]
        # echo "MAKE GEN: ", ch.treeRepr
        # echo "MAKE GEN:idType: ", idType.treeRepr
        node[i] = nnkCall.newTree(
          bindSym("[]", brOpen),
          ident idType[0].repr,
          genParam,
        )
      ch.makeGenerics(gens)

macro rpcImpl*(p: untyped, publish: untyped, qarg: untyped): untyped =
  ## Define a remote procedure call.
  ## Input and return parameters are defined using proc's with the `rpc` 
  ## pragma. 
  ## 
  ## For example:
  ## .. code-block:: nim
  ##    proc methodname(param1: int, param2: float): string {.rpc.} =
  ##      result = $param1 & " " & $param2
  ##    ```
  ## 
  ## Input parameters are automatically marshalled from fast rpc binary 
  ## format (msgpack) and output parameters are automatically marshalled
  ## back to the fast rpc binary format (msgpack) for transport.
  
  let
    path = $p[0]
    procLineInfo = p.lineInfoObj
    genericParams = p[2]
    params = p[3]
    # pragmas = p[4]
    body = p[6]

  result = newStmtList()
  var
    (_, firstType) = params.firstArgument()
    parameters = params.copyNimTree()

  let
    # determine if this is a "signal" rpc method
    isSignal = publish.kind == nnkStrLit and publish.strVal == "signal"
  
  parameters.del(0, 1)
  # echo "parameters: ", parameters.treeRepr

  let
    # rpc method names
    pathStr = $path
    signalName = pathStr.strip(false, true, {'*'})
    procNameStr = p.name().repr
    isPublic = pathStr.endsWith("*")
    isGeneric = genericParams.kind != nnkEmpty

    # public rpc proc
    # rpcSlot = ident(procNameStr & "Slot")
    rpcMethodGen = genSym(nskProc, procNameStr)
    rpcMethodGenName = newStrLitNode repr rpcMethodGen
    procName = ident(procNameStr) # ident("agentSlot_" & rpcMethodGen.repr)
    rpcMethod = ident(procNameStr)
    rpcSlot = ident("agentSlot_" & procNameStr)

    # ctxName = ident("context")
    # parameter type name
    # paramsIdent = genSym(nskParam, "args")
    paramsIdent = ident("args")
    paramTypeName = ident("RpcType" & procNameStr)

  # echo "SLOTS:slot:NAME: ", p.name(), " => ", procNameStr, " genname: ", rpcMethodGen
  # echo "SLOTS:paramTypeName:NAME: ", paramTypeName
  # echo "SLOTS:generic: ", genericParams.treeRepr
  # echo "SLOTS: rpcMethodGen:hash: ", rpcMethodGen.symBodyHash()
  # echo "SLOTS: rpcMethodGen:signatureHash: ", rpcMethodGen.signatureHash()

  var
    # process the argument types
    paramSetups = mkParamsVars(paramsIdent, paramTypeName, parameters)
    paramTypes = mkParamsType(paramsIdent, paramTypeName, parameters, genericParams)

    procBody =  if body.kind == nnkStmtList: body
                elif body.kind == nnkEmpty: body
                else: body.body

  let
    contextType = firstType
    kd = ident "kd"
    tp = ident "tp"
    agent = ident "agent"

  var signalTyp = nnkTupleConstr.newTree()
  for i in 2..<params.len:
    signalTyp.add params[i][1]
  if params.len == 2:
    # signalTyp = bindSym"void"
    signalTyp = quote do:
      tuple[]

  # Create the proc's that hold the users code 
  if not isSignal:

    # result.add quote do:
    #   `paramTypes`

    let rmCall = nnkCall.newTree(rpcMethodGen)
    for param in parameters:
      rmCall.add param[0]
    let rm = quote do:
      proc `rpcMethod`() {.nimcall.} =
        `procBody`
    for param in parameters:
      rm[3].add param
    result.add rm

    var rpcType = paramTypeName.copyNimTree()
    if isGeneric:
      rpcType = nnkBracketExpr.newTree(paramTypeName)
      for arg in genericParams:
        rpcType.add arg

    # Create the rpc wrapper procs
    let objId = ident "obj"
    var tupTyp = nnkTupleConstr.newTree()
    for pt in paramTypes[0][^1]:
      tupTyp.add pt[1]
    if tupTyp.len() == 0:
      tupTyp = nnkTupleTy.newTree()
    let mcall = nnkCall.newTree(rpcMethod)
    mcall.add(objId)
    for param in parameters[1..^1]:
      # echo "PARAMS: ", param.treeRepr
      mcall.add param[0]

    let agentSlotImpl = quote do:
      proc slot(
          context: Agent,
          params: RpcParams,
      ) {.nimcall.} =
        if context == nil:
          raise newException(ValueError, "bad value")
        let `objId` = `contextType`(context)
        if `objId` == nil:
          raise newException(ConversionError, "bad cast")
        var `paramsIdent`: `tupTyp`
        rpcUnpack(`paramsIdent`, params)
        `paramSetups`
        `mcall`

    let procTyp = quote do:
      proc () {.nimcall.}
    procTyp.params = params.copyNimTree()

    result.add quote do:
      proc `rpcMethod`(`kd`: typedesc[SignalTypes],
                       `tp`: typedesc[`contextType`]): `signalTyp` =
        discard
      proc `rpcMethod`(`tp`: typedesc[`contextType`]): AgentProc =
        `agentSlotImpl`
        slot

    result.updateProcsSig(isPublic, genericParams, procLineInfo)

  elif isSignal:
    var construct = nnkTupleConstr.newTree()
    for param in parameters[1..^1]:
      construct.add param[0]

    result.add quote do:
      proc `rpcMethod`(): (Agent, AgentRequest) =
        let args = `construct`
        let req = initAgentRequest(procName=`signalName`, args=args)
        result = (obj, req)

    result[0][3].add nnkIdentDefs.newTree(
      ident "obj",
      firstType,
      nnkEmpty.newNimNode()
    )
    for param in parameters[1..^1]:
      result[0][3].add param

    result.add quote do:
      proc `rpcMethod`(`kd`: typedesc[SignalTypes],
                       `tp`: typedesc[`contextType`]): `signalTyp` =
        discard

    result.updateProcsSig(isPublic, genericParams, procLineInfo)

  var gens: seq[string]
  for gen in genericParams:
    gens.add gen[0].strVal
  result.makeGenerics(gens)

  # echo "slot: "
  # echo result.lispRepr
  echo "slot:repr:"
  echo result.repr

template slot*(p: untyped): untyped =
  rpcImpl(p, nil, nil)

template signal*(p: untyped): untyped =
  rpcImpl(p, "signal", nil)
