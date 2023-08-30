import tables, strutils, macros
import std/times

import datatypes
export datatypes
export times

proc wrapResponse*(id: AgentId, resp: RpcParams, kind = Response): AgentResponse = 
  result.kind = kind
  result.id = id
  result.result = resp

proc wrapResponseError*(id: AgentId, err: AgentError): AgentResponse = 
  result.kind = Error
  result.id = id
  result.result = rpcPack(err)

proc wrapResponseError*(
    id: AgentId,
    code: FastErrorCodes,
    msg: string,
    err: ref Exception,
    stacktraces: bool
): AgentResponse = 
  let errobj = AgentError(code: code, msg: msg)
  # when defined(nimscript):
  #   discard
  # else:
  #   if stacktraces and not err.isNil():
  #     errobj.trace = @[]
  #     for se in err.getStackTraceEntries():
  #       let file: string = rsplit($(se.filename), '/', maxsplit=1)[^1]
  #       errobj.trace.add( ($se.procname, file, se.line, ) )
  result = wrapResponseError(id, errobj)

proc parseError*(ss: Variant): AgentError = 
  ss.unpack(result)

proc parseParams*[T](ss: Variant, val: var T) = 
  ss.unpack(val)

proc createRpcRouter*(): AgentRouter =
  result = new(AgentRouter)
  result.procs = initTable[string, AgentProc]()

proc register*(router: var AgentRouter, path, name: string, call: AgentProc) =
  router.procs[name] = call
  echo "registering: ", name

when nimvm:
  var globalRouter {.compileTime.} = AgentRouter()
else:
  when not compiles(globalRouter):
    var globalRouter {.global.} = AgentRouter()

proc register*(path, name: string, call: AgentProc) =
  globalRouter.procs[name] = call
  echo "registering: ", name

proc listMethods*(): seq[string] =
  globalRouter.listMethods()

proc clear*(router: var AgentRouter) =
  router.procs.clear

proc hasMethod*(router: AgentRouter, methodName: string): bool =
  router.procs.hasKey(methodName)

proc callMethod*(
        slot: AgentProc,
        ctx: RpcContext,
        req: AgentRequest,
        # clientId: ClientId,
      ): AgentResponse {.gcsafe, effectsOf: slot.} =
    ## Route's an rpc request. 

    if slot.isNil:
      let msg = req.procName & " is not a registered RPC method."
      let err = AgentError(code: METHOD_NOT_FOUND, msg: msg)
      result = wrapResponseError(req.id, err)
    else:
      try:
        # Handle rpc request the `context` variable is different
        # based on whether the rpc request is a system/regular/subscription
        slot(ctx, req.params)
        let res = rpcPack(true)

        result = AgentResponse(kind: Response, id: req.id, result: res)
      except ConversionError as err:
        result = wrapResponseError(
                    req.id,
                    INVALID_PARAMS,
                    req.procName & " raised an exception",
                    err,
                    true)
      except CatchableError as err:
        result = wrapResponseError(
                    req.id,
                    INTERNAL_ERROR,
                    req.procName & " raised an exception: " & err.msg,
                    err,
                    true)

template packResponse*(res: AgentResponse): Variant =
  var so = newVariant()
  so.pack(res)
  so

proc getSignalName(signal: NimNode): NimNode =
  result = newStrLitNode signal.strVal

import typetraits, sequtils, tables

proc getSignalTuple*(obj, sig: NimNode): NimNode =
  let otp = obj.getTypeInst
  echo "signalObjRaw:sig1: ", sig.treeRepr
  let sigTyp =
    if sig.kind == nnkSym: sig.getTypeInst
    else: sig.getTypeInst
  echo "signalObjRaw:sig2: ", sigTyp.treeRepr
  let stp =
    if sigTyp.kind == nnkProcTy:
      sig.getTypeInst[0]
    else:
      sigTyp.params()
  let isGeneric = otp.kind == nnkBracketExpr

  echo "signalObjRaw:obj: ", otp.repr
  echo "signalObjRaw:obj:tr: ", otp.treeRepr
  echo "signalObjRaw:obj:isGen: ", otp.kind == nnkBracketExpr
  echo "signalObjRaw:sig: ", stp.repr

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
  if result.len == 0:
    result = bindSym"void"
  echo "ARG: ", result.repr
  echo ""

macro signalType*(p: untyped): auto =
  ## gets the type of the signal without 
  ## the Agent proc type
  ## 
  let p = p.getTypeInst
  # echo "signalType: ", p.treeRepr
  if p.kind == nnkNone:
    error("cannot determine type of: " & repr(p), p)
  if p.kind == nnkSym and p.repr == "none":
    error("cannot determine type of: " & repr(p), p)
  let obj = p[0]
  result = nnkTupleConstr.newNimNode()
  for arg in obj[2..^1]:
    result.add arg[1]

macro connect*(
    a: Agent,
    signal: typed,
    b: Agent,
    slot: untyped
) =
  # when getSignalTuple(a, signal) isnot getSignalTuple(b, slot):
  #     {.error: "signal and slot types don't match".}

  echo "\n\nAA:a: ", a.repr
  echo "AA:a: ", a.getTypeImpl.repr
  echo "AA:a:tup: ", getSignalTuple(a, signal).repr

  echo "AA:sig: ", signal.repr
  echo "AA:sig: ", signal.getTypeImpl.repr
  # echo "AA:sig: ", signal.getImpl.repr

  let sigTuple = getSignalTuple(a, signal)

  echo "\nAA:slot:repr: ", slot.treerepr

  echo "\nAA:B:repr: ", b.treeRepr
  echo "\nAA:B:tinst: ", b.getTypeInst().treerepr
  echo "\nAA:B:timpl: ", b.getTypeImpl().repr

  let bTyp = b.getTypeInst()
  # echo "\nAA:B:typ: ", bTyp.treeRepr

  let slotAgent = 
    if slot.kind == nnkIdent:
      nnkCall.newTree(slot, ident bTyp.strVal, ident "AgentProc")
    elif slot.kind == nnkDotExpr:
      echo "SLOT: ", slot.treeRepr
      let s0 = slot[0]
      let s1 = slot[1]
      nnkCall.newTree(s1, s0, ident "AgentProc")
      # quote do:
      #   `s1`(typeof(`b`), typeof(AgentProc))
    else:
      slot

  let procTyp = quote do:
    proc () {.nimcall.}
  # let sigTupleSlot = sigTuple.copyNimTree()
  # sigTupleSlot.insert(0, bTyp)
  for i, ty in sigTuple:
    let empty = nnkEmpty.newNimNode()
    procTyp.params.add nnkIdentDefs.newTree( ident("a" & $i), ty, empty)
  # echo "AA:procTyp: ", procTyp.treeRepr
  # echo "AA:procTyp: ", procTyp.repr

  let name = getSignalName(signal)
  let serror = newStrLitNode("cannot find slot for " & "`" & slotAgent[0].repr & "`")
  # let aname = 
  # echo "AA:NAME: ", name
  # result = newStmtList()
  result = quote do:
    when not compiles(`slotAgent`):
      static:
        {.error: serror.}
    let agentSlot: AgentProc = `slotAgent`
    `a`.addAgentListeners(`name`, `b`, agentSlot)
  echo "CONNECT: ", result.repr

import pretty

proc callSlots*(obj: Agent, req: AgentRequest) {.gcsafe.} =
  {.cast(gcsafe).}:
    let listeners = obj.getAgentListeners(req.procName)

    # echo "call slots:all: ", req.procName, " ", obj.agentId, " :: ", obj.listeners

    for (tgt, slot) in listeners:
      # echo ""
      # echo "call listener:tgt: ", repr tgt
      # echo "call listener:slot: ", repr slot
      let res = slot.callMethod(tgt, req)
      variantMatch case res.result.buf as u
      of AgentError:
        raise newException(AgentSlotError, u.msg)
      else:
        discard

proc emit*(call: (Agent, AgentRequest)) =
  let (obj, req) = call
  callSlots(obj, req)
