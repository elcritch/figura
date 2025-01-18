
# Compile with nim c -d:ssl
# List text found between HTML tags on the target website.

## This minimal example shows 5 blue squares.
import figuro/widgets/[basics, button]
import figuro/widgets/[scrollpane, vertical, horizontal]
import figuro/widget
import figuro

import hnloader

let
  typeface = loadTypeFace("IBMPlexSans-Regular.ttf")
  font = UiFont(typefaceId: typeface, size: 22)

type
  Main* = ref object of Figuro
    value: float
    hasHovered: bool
    loader: AgentProxy[HtmlLoader]
    loading = false
    stories: seq[Submission]

proc htmlLoad*(tp: Main) {.signal.}

let thr = newSigilThread()

thr.start()

proc hover*(self: Main, kind: EventKind) {.slot.} =
  self.hasHovered = kind == Enter
  # echo "hover: ", kind
  refresh(self)

proc loadStories*(self: Main, stories: seq[Submission]) {.slot.} =
  echo "got stories"
  self.stories = stories
  refresh(self)

proc draw*(self: Main) {.slot.} =
  var node = self
  with node:
    fill css"#0000AA"

  if self.loader.isNil:
    echo "Setting up loading"
    var loader = HtmlLoader(url: "https://news.ycombinator.com")
    self.loader = loader.moveToThread(thr)
    threads.connect(self, htmlLoad, self.loader, HtmlLoader.loadPage())
    threads.connect(self.loader, htmlDone, self, Main.loadStories())

  rectangle "outer":
    with node:
      offset 10'ux, 10'ux
      setGridCols 1'fr
      setGridRows ["top"] 70'ux \
                  ["items"] 1'fr
      gridAutoFlow grRow
      justifyItems CxCenter
      alignItems CxStart

    Button.new "Load":
      with node:
        size 0.5'fr, 50'ux
      proc clickLoad(self: Main,
                      kind: EventKind,
                      buttons: UiButtonView) {.slot.} =
        echo "Load clicked"
        if not self.loading:
          emit self.htmlLoad()
        self.loading = true
        refresh(self)
      connect(node, doClick, self, clickLoad)

      Text.new "text":
        with node:
          fill blackColor
          offset 0'ux, 10'ux
        case self.loading:
        of false:
          node.setText({font: "Load"}, Center, Middle)
        of true:
          node.setText({font: "Loading..."}, Center, Middle)

    ScrollPane.new "scroll":
      with node:
        offset 2'pp, 2'pp
        cornerRadius 7.0'ux
        size 96'pp, 90'pp
      node.settings.size.y = 20'ui
      contents "children":
        Vertical.new "items":
          # Setup CSS Grid Template
          with node:
            offset 10'ux, 10'ux
            itemHeight cx"max-content"
          for idx, story in self.stories:
            capture story:
              Button.new "button":
                with node:
                  size 1'fr, 40'ux
                # connect(node, doHover, self, Main.hover)
                Text.new "text":
                  offset node, 0'ux, 11'ux
                  node.setText({font: $story.link.title}, Center, Middle)

var main = Main.new()
var frame = newAppFrame(main, size=(600'ui, 480'ui))
startFiguro(frame)
