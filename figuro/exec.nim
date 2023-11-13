
when defined(js):
  import figuro/htmlbackend
  export htmlbackend
elif defined(blank):
  import engine/blank
  export blank
else:
  import renderer/opengl
  export opengl

import std/os
import std/sets
import shared, internal
import ui/[core, events]
import common/nodes/ui
import common/nodes/render
import common/nodes/transfer
import widget
import timers

export core, events

when not compileOption("threads"):
  {.error: "This module requires --threads:on compilation flag".}

when not defined(gcArc) and not defined(gcOrc) and not defined(nimdoc):
  {.error: "Figuro requires --gc:arc or --gc:orc".}

var
  mainApp*: proc(frame: AppFrame) {.nimcall.}
  sendRoots*: Table[AppFrame, Chan[RenderNodes]]

const renderPeriodMs {.intdefine.} = 16
const appPeriodMs {.intdefine.} = 16

var frameTickThread, appTickThread: Thread[void]
var appThread, : Thread[AppFrame]

proc renderTicker() {.thread.} =
  while true:
    uiRenderEvent.trigger()
    os.sleep(appPeriodMs - 2)
    app.tickCount.inc()
    if app.tickCount == app.tickCount.typeof.high:
      app.tickCount = 0

proc runRenderer(renderer: Renderer) =
  while app.running:
    wait(uiRenderEvent)
    timeIt(renderAvgTime):
      renderer.render(true)

proc appTicker() {.thread.} =
  while app.running:
    uiAppEvent.trigger()
    os.sleep(renderPeriodMs - 2)

proc runApplication(frame: AppFrame) {.thread.} =
  {.gcsafe.}:
    while app.running:
      wait(uiAppEvent)
      timeIt(appAvgTime):
        mainApp(frame)
        app.frameCount.inc()

proc run*(renderer: Renderer, frame: AppFrame) =

  sendRoots[frame] = renderer.chan
  uiRenderEvent = initUiEvent()
  uiAppEvent = initUiEvent()

  createThread(frameTickThread, renderTicker)
  createThread(appTickThread, appTicker)
  createThread(appThread, runApplication, frame)

  proc ctrlc() {.noconv.} =
    echo "Got Ctrl+C exiting!"
    app.running = false
  setControlCHook(ctrlc)

  runRenderer(renderer)
