import threading/channels
import threading/smartptrs

import std/options
import std/isolation
import std/uri

import meta

export smartptrs

type
  AsyncMessage*[T] = object
    continued*: bool
    handle*: int
    value*: T

  AgentProxyRaw*[T, U] = object
    agents*: Table[int, Agent]
    inputs*: Chan[AsyncMessage[T]]
    outputs*: Chan[AsyncMessage[U]]

  AgentProxy*[T, U] = SharedPtr[AgentProxyRaw[T, U]]

proc newAgentProxy*[T, U](): AgentProxy[T, U] =
  result = newSharedPtr(AgentProxyRaw[T, U])
  result[].inputs = newChan[AsyncMessage[T]]()
  result[].outputs = newChan[AsyncMessage[U]]()

proc send*[T, U](proxy: AgentProxy[T, U], obj: Agent, val: sink Isolated[T]) =
  let wref = obj.getId()
  proxy[].agents[wref] = obj
  proxy[].inputs.send(AsyncMessage[T](handle: wref, value: val.extract()))

template send*[T, U](proxy: AgentProxy[T, U], obj: Agent, val: T) =
  send(proxy, obj, isolate(val))

proc process*[T, U](proxy: AgentProxy[T, U], maxCnt = 20) =
  mixin receive
  var cnt = maxCnt
  var msg: AsyncMessage[U]
  while proxy[].outputs.tryRecv(msg) and cnt > 0:
    let obj = proxy[].agents[msg.handle]
    if not msg.continued:
      proxy[].agents.del(msg.handle)
    receive(msg.value)


type
  ThreadAgent* = ref object of Agent

  HttpRequest* = ref object of ThreadAgent
    url: Uri

proc newHttpRequest*(url: Uri): HttpRequest =
  result = HttpRequest(url: url)

proc newHttpRequest*(url: string): HttpRequest =
  newHttpRequest(parseUri(url))

proc update*(req: HttpRequest, gotByts: int) {.signal.}
proc received*(req: HttpRequest, val: string) {.signal.}
