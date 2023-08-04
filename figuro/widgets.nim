import algorithm, chroma, bumpy
import std/[json, macros, tables]
import cssgrid

import common, commonutils

export chroma, common
export commonutils
export cssgrid

import pretty

proc preNode(kind: NodeKind, id: Atom) =
  ## Process the start of the node.

  parent = nodeStack[^1]

  # TODO: maybe a better node differ?
  if parent.nodes.len <= parent.diffIndex:
    # Create Node.
    current = Node()
    current.uid = newUId()
    parent.nodes.add(current)
    refresh()
  else:
    # Reuse Node.
    current = parent.nodes[parent.diffIndex]
    if resetNodes == 0 and
        current.nIndex == parent.diffIndex:
      # Same node.
      discard
    else:
      # Big change.
      current.nIndex = parent.diffIndex
      # current.resetToDefault()
      refresh()

  current.kind = kind
  # current.textStyle = parent.textStyle
  # current.cursorColor = parent.cursorColor
  current.highlight = parent.highlight
  current.transparency = parent.transparency
  current.zlevel = parent.zlevel
  nodeStack.add(current)
  inc parent.diffIndex

  current.diffIndex = 0

proc postNode() =
  current.removeExtraChildren()

  # Pop the stack.
  discard nodeStack.pop()
  if nodeStack.len > 1:
    current = nodeStack[^1]
  else:
    current = nil
  if nodeStack.len > 2:
    parent = nodeStack[^2]
  else:
    parent = nil

template node(kind: NodeKind, id: static string, inner, setup: untyped): untyped =
  ## Base template for node, frame, rectangle...
  preNode(kind, atom(id))
  setup
  inner
  postNode()

template node(kind: NodeKind, id: static string, inner: untyped): untyped =
  ## Base template for node, frame, rectangle...
  preNode(kind, atom(id))
  inner
  postNode()

template withDefaultName(name: untyped): untyped =
  template `name`*(inner: untyped): untyped =
    `name`("", inner)

## ---------------------------------------------
##             Basic Node Creation
## ---------------------------------------------
## 
## Core Fidget Node APIs. These are the main ways to create
## Fidget nodes. 
## 

template frame*(id: static string, inner: untyped): untyped =
  ## Starts a new frame.
  node(nkFrame, id, inner):
    # boxSizeOf parent
    discard
    # current.cxSize = [csAuto(), csAuto()]

template drawable*(id: static string, inner: untyped): untyped =
  ## Starts a drawable node. These don't draw a normal rectangle.
  ## Instead they draw a list of points set in `current.points`
  ## using the nodes fill/stroke. The size of the drawable node
  ## is used for the point sizes, etc. 
  ## 
  ## Note: Experimental!
  node(nkDrawable, id, inner)

template rectangle*(id, inner: untyped): untyped =
  ## Starts a new rectangle.
  node(nkRectangle, id, inner)

## Overloaded Nodes 
## ^^^^^^^^^^^^^^^^
## 
## Various overloaded node APIs

withDefaultName(group)
withDefaultName(frame)
withDefaultName(rectangle)
withDefaultName(text)
withDefaultName(component)
withDefaultName(instance)
withDefaultName(drawable)
withDefaultName(blank)

template rectangle*(color: string|Color) =
  ## Shorthand for rectangle with fill.
  rectangle "":
    box 0, 0, parent.getBox().w, parent.getBox().h
    fill color

template blank*(): untyped =
  ## Starts a new rectangle.
  node(nkComponent, ""):
    discard

## ---------------------------------------------
##             Fidget Node APIs
## ---------------------------------------------
## 
## These APIs provide the APIs for Fidget nodes.
## 

## ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
##             Node User Interactions
## ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
## 
## These APIs provide the basic functionality for
## interacting with user interactions. 
## 

proc boxFrom(x, y, w, h: float32) =
  ## Sets the box dimensions.
  current.box = initBox(x, y, w, h)

proc fltOrZero(x: int|float32|float64|UICoord|Constraint): float32 =
  when x is Constraint:
    0.0
  else:
    x.float32

proc csOrFixed*(x: int|float32|float64|UICoord|Constraint): Constraint =
  when x is Constraint:
    x
  else: csFixed(x.UiScalar)

proc box*(
  x: int|float32|float64|UICoord|Constraint,
  y: int|float32|float64|UICoord|Constraint,
  w: int|float32|float64|UICoord|Constraint,
  h: int|float32|float64|UICoord|Constraint
) =
  ## Sets the box dimensions with integers
  ## Always set box before orgBox when doing constraints.
  boxFrom(fltOrZero x, fltOrZero y, fltOrZero w, fltOrZero h)
  # current.cxOffset = [csOrFixed(x), csOrFixed(y)]
  # current.cxSize = [csOrFixed(w), csOrFixed(h)]
  # orgBox(float32 x, float32 y, float32 w, float32 h)

proc box*(rect: Box) =
  ## Sets the box dimensions with integers
  box(rect.x, rect.y, rect.w, rect.h)

proc size*(
  w: int|float32|float64|UICoord|Constraint,
  h: int|float32|float64|UICoord|Constraint,
) =
  ## Sets the box dimension width and height
  when w is Constraint:
    current.cxSize[dcol] = w
  else:
    current.cxSize[dcol] = csFixed(w.UiScalar)
    current.box.w = w.UICoord
  
  when h is Constraint:
    current.cxSize[drow] = h
  else:
    current.cxSize[drow] = csFixed(h.UiScalar)
    current.box.h = h.UICoord

proc openBrowser*(url: string) =
  ## Opens a URL in a browser
  discard

proc getTitle*(): string =
  ## Gets window title
  windowTitle

proc setTitle*(title: string) =
  ## Sets window title
  if (windowTitle != title):
    windowTitle = title
    setWindowTitle(title)
    refresh()

# proc setWindowBounds*(min, max: Vec2) =
#   base.setWindowBounds(min, max)

proc getUrl*(): string =
  windowUrl

proc setUrl*(url: string) =
  windowUrl = url
  refresh()

proc loadFontAbsolute*(name: string, pathOrUrl: string) =
  ## Loads fonts anywhere in the system.
  ## Not supported on js, emscripten, ios or android.
  if pathOrUrl.endsWith(".svg"):
    fonts[name] = readFontSvg(pathOrUrl)
  elif pathOrUrl.endsWith(".ttf"):
    fonts[name] = readFontTtf(pathOrUrl)
  elif pathOrUrl.endsWith(".otf"):
    fonts[name] = readFontOtf(pathOrUrl)
  else:
    raise newException(Exception, "Unsupported font format")

proc loadFont*(name: string, pathOrUrl: string) =
  ## Loads the font from the dataDir.
  loadFontAbsolute(name, dataDir / pathOrUrl)

proc setItem*(key, value: string) =
  ## Saves value into local storage or file.
  writeFile(&"{key}.data", value)

proc getItem*(key: string): string =
  ## Gets a value into local storage or file.
  readFile(&"{key}.data")

when not defined(emscripten) and not defined(fidgetNoAsync):
  proc httpGetCb(future: Future[string]) =
    refresh()

  proc httpGet*(url: string): HttpCall =
    if url notin httpCalls:
      result = HttpCall()
      var client = newAsyncHttpClient()
      echo "new call"
      result.future = client.getContent(url)
      result.future.addCallback(httpGetCb)
      httpCalls[url] = result
      result.status = Loading
    else:
      result = httpCalls[url]

    if result.status == Loading and result.future.finished:
      result.status = Ready
      try:
        result.data = result.future.read()
        result.json = parseJson(result.data)
      except HttpRequestError:
        echo getCurrentExceptionMsg()
        result.status = Error

    return