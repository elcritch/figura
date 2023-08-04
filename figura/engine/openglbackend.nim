import std/[os, hashes, strformat, strutils, tables, times]

import pkg/chroma
import pkg/[typography, typography/svgfont]
import pkg/pixie

import ./opengl/[base, context, draw]
import ./[internal, input]
import ../common

when not defined(emscripten) and not defined(fidgetNoAsync):
  import httpClient, asyncdispatch, asyncfutures, json

export input, draw

var
  windowTitle, windowUrl: string

proc drawFrame() =
  # echo "\ndrawFrame"
  clearColorBuffer(color(1.0, 1.0, 1.0, 1.0))
  ctx.beginFrame(windowSize)
  ctx.saveTransform()
  ctx.scale(ctx.pixelScale)

  mouse.cursorStyle = Default

  computeScreenBox(nil, root)
  # Only draw the root after everything was done:
  drawRoot(renderRoot)

  ctx.restoreTransform()
  ctx.endFrame()

  # Only set mouse style when it changes.
  if mouse.prevCursorStyle != mouse.cursorStyle:
    mouse.prevCursorStyle = mouse.cursorStyle
    echo mouse.cursorStyle
    case mouse.cursorStyle:
      of Default:
        setCursor(cursorDefault)
      of Pointer:
        setCursor(cursorPointer)
      of Grab:
        setCursor(cursorGrab)
      of NSResize:
        setCursor(cursorNSResize)

  when defined(testOneFrame):
    ## This is used for test only
    ## Take a screen shot of the first frame and exit.
    var img = takeScreenshot()
    img.writeFile("screenshot.png")
    quit()

proc setupFidget(
    openglVersion: (int, int),
    msaa: MSAA,
    mainLoopMode: MainLoopMode,
    pixelate: bool,
    forcePixelScale: float32,
    atlasSize: int = 1024
) =
  pixelScale = forcePixelScale

  base.start(openglVersion, msaa, mainLoopMode)

  setWindowTitle(windowTitle)
  ctx = newContext(atlasSize = atlasSize, pixelate = pixelate, pixelScale = pixelScale)
  requestedFrame.inc

  base.drawFrame = drawFrame

  useDepthBuffer(false)

  if loadMain != nil:
    loadMain()

proc runApplication*(drawMain: MainCallback) {.thread.} =
  {.gcsafe.}:
    while base.running:
      proc running() {.async.} =
        setupRoot()
        drawMain()
        var rootCopy = root.deepCopy
        renderRoot = rootCopy.move()
        await sleepAsync(16)
      waitFor running()

proc runRenderer*() =
  when defined(emscripten):
    # Emscripten can't block so it will call this callback instead.
    proc emscripten_set_main_loop(f: proc() {.cdecl.}, a: cint, b: bool) {.importc.}
    proc mainLoop() {.cdecl.} =
      asyncPoll()
      renderLoop()
    emscripten_set_main_loop(main_loop, 0, true)
  else:
    while base.running:
      renderLoop()
      if isEvent:
        isEvent = false
        eventTimePost = epochTime()
      sleep(8)

proc startFidget*(
    draw: proc() {.nimcall.} = nil,
    tick: proc() {.nimcall.} = nil,
    load: proc() {.nimcall.} = nil,
    setup: proc() = nil,
    fullscreen = false,
    w: Positive = 1280,
    h: Positive = 800,
    openglVersion = (3, 3),
    msaa = msaaDisabled,
    mainLoopMode: MainLoopMode = RepaintOnEvent,
    pixelate = false,
    pixelScale = 1.0
) =
  ## Starts Fidget UI library
  ## 
  common.fullscreen = fullscreen
  
  if not fullscreen:
    windowSize = vec2(uiScale * w.float32, uiScale * h.float32)
  drawMain = draw
  tickMain = tick
  loadMain = load
  let atlasStartSz = 1024 shl (uiScale.round().toInt() + 1)
  echo fmt"{atlasStartSz=}"
  
  echo "setting up new UI Event "
  uiEvent = newAsyncEvent()
  let uiEventCb =
    proc (fd: AsyncFD): bool =
      echo "UI event!"
      return true
  addEvent(uiEvent, uiEventCb)
  echo "setup new UI Event ", repr uiEvent

  setupFidget(openglVersion, msaa, mainLoopMode, pixelate, pixelScale, atlasStartSz)
  mouse.pixelScale = pixelScale

  if not setup.isNil:
    setup()

  var widgetThread: Thread[MainCallback]
  createThread(widgetThread, runApplication, drawMain)

  runRenderer()
  widgetThread.joinThread()

