import tables, strutils, macros

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

proc mkParamsVars(paramsIdent, paramsType, params: NimNode): NimNode =
  ## Create local variables for each parameter in the actual RPC call proc
  if params.isNil: return

  result = newStmtList()
  var varList = newSeq[NimNode]()
  for paramid, paramType in paramsIter(params):
    varList.add quote do:
      var `paramid`: `paramType` = `paramsIdent`.`paramid`
  result.add varList
  # echo "paramsSetup return:\n", treeRepr result

proc mkParamsType*(paramsIdent, paramsType, params: NimNode): NimNode =
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
    params = p[3]
    # pragmas = p[4]
    body = p[6]

  result = newStmtList()
  var
    (_, firstType) = params.firstArgument()
    parameters = params

  let
    # determine if this is a "signal" rpc method
    isSignal = publish.kind == nnkStrLit and publish.strVal == "signal"
  
  parameters.del(0, 1)

  let

    # rpc method names
    pathStr = $path
    signalName = pathStr.strip(false, true, {'*'})
    procNameStr = pathStr.makeProcName()
    isPublic = pathStr.endsWith("*")

    # public rpc proc
    procName = ident(procNameStr & "AgentSlot")
    rpcMethod = ident(procNameStr)

    # ctxName = ident("context")

    # parameter type name
    # paramsIdent = genSym(nskParam, "args")
    paramsIdent = ident("args")
    paramTypeName = ident("RpcType_" & procNameStr)


  var
    # process the argument types
    paramSetups = mkParamsVars(paramsIdent, paramTypeName, parameters)
    paramTypes = mkParamsType(paramsIdent, paramTypeName, parameters)
    procBody =  if body.kind == nnkStmtList: body
                elif body.kind == nnkEmpty: body
                else: body.body

  proc makePublic(procDef: NimNode) =
      let name = procDef[0]
      procDef[0] = nnkPostfix.newTree(newIdentNode("*"), name)

  let contextType = firstType

  # Create the proc's that hold the users code 
  if not isSignal:

    result.add quote do:
      `paramTypes`

    let rm = quote do:
      proc `rpcMethod`() =
        `procBody`
    
    for param in parameters: rm[3].add param
    result.add rm

    # Create the rpc wrapper procs
    let call = quote do:
        `rpcMethod`(context)
    # echo "call: "
    # echo call.repr
    # echo call.treeRepr
    # echo ""
    let objId = ident("obj")
    let mcall = nnkCall.newTree(rpcMethod)
    mcall.add(ident("obj"))
    for param in parameters[1..^1]:
      mcall.add param[0]

    result.add quote do:
      proc `procName`*(
          context: Agent,
          params: RpcParams,
      ) {.nimcall.} =
        if context == nil:
          raise newException(ValueError, "bad value")
        let obj = `contextType`(context)
        if obj == nil:
          raise newException(ConversionError, "bad cast")
        var `paramsIdent`: `paramTypeName`
        rpcUnpack(`paramsIdent`, params)
        let `objId` = `firstType`(context)
        `paramSetups`
        `mcall`

    if isPublic:
      result[1].makePublic()

    # result.add quote do:
    #   once:
    #     register(currentSourcePath(), `signalName`, `procName`)
    # echo "slots: "
    # echo result.repr

  elif isSignal:
    var construct = nnkTupleConstr.newTree()
    for param in parameters[1..^1]:
      construct.add nnkExprColonExpr.newTree(param[0], param[0])

    result.add quote do:
      proc `rpcMethod`(): (Agent, AgentRequest) =
        let args = `construct`
        let sig = AgentRequest(
          kind: Request,
          id: AgentId(0),
          procName: `signalName`,
          params: rpcPack(args)
        )
        result = (obj, sig)
        # callSlots(obj, sig)

    if isPublic: result[0].makePublic()
    result[0][3].add nnkIdentDefs.newTree(
      ident "obj",
      firstType,
      nnkEmpty.newNimNode()
    )
    for param in parameters[1..^1]:
      result[0][3].add param
  echo "slot: "
  echo result.repr
  echo "\nparameters: ", treeRepr parameters 

template slot*(p: untyped): untyped =
  rpcImpl(p, nil, nil)

template signal*(p: untyped): untyped =
  rpcImpl(p, "signal", nil)
