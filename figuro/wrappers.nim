
import common/nodes/render
import common/nodes/transfer
import widget

var
  appWidget* {.compileTime.}: FiguroApp
  appMain* {.compileTime.}: proc ()
  appTicker* {.compileTime.}: proc ()

proc appInit() =
  discard

proc appTick*(val: AppStatePartial) =
  app.tickCount = val.tickCount
  app.uiScale = val.uiScale
  appTicker()

proc appDraw*(): int =
  root.diffIndex = 0
  appMain()
  computeScreenBox(nil, root)
  result = app.requestedFrame

proc getRoot*(): seq[Node] =
  result = root.copyInto()

proc getAppState*(): AppState =
  result = app

proc run*(init: proc() {.nimcall.},
          tick: proc(state: AppStatePartial) {.nimcall.},
          draw: proc(): int {.nimcall.},
          getRoot: proc(): seq[Node] {.nimcall.},
          getAppState: proc(): AppState {.nimcall.}
          ) = discard

proc startFiguro*(
    widget: FiguroApp,
    setup: proc() = nil,
    fullscreen = false,
    pixelate = false,
    pixelScale = 1.0
) =
  ## Starts Fidget UI library
  ## 
  mixin draw
  mixin tick
  mixin load

  app.fullscreen = fullscreen
  app.autoUiScale = true
  app.pixelRatio = pixelScale
  app.pixelate = pixelate

  echo "app: ", app.repr
  root = widget
  appWidget = widget

  appMain = proc() =
    emit appWidget.onDraw()
  appTicker = proc() =
    echo "do tick: ", app.tickCount
    emit appWidget.onTick()
    # emit root.eventHover()

  setupRoot(appWidget)

  run(
    appInit,
    appTick,
    appDraw,
    getRoot,
    getAppState
  )
