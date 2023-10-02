
## This minimal example shows 5 blue squares.
import figuro/widgets/button
import figuro/widgets/scrollpane
import figuro/widget
import figuro

type
  Main* = ref object of Figuro
    value: float
    hasHovered: bool

proc hover*(self: Main, kind: EventKind) {.slot.} =
  self.hasHovered = kind == Enter
  refresh(self)

proc draw*(self: Main) {.slot.} =
  withDraw(self):
    offset 1'pp, 1'pp
    size 100'pp, 100'pp
    name "root"

    scroll "scroll":
      size 90'pp, 80'pp
      contents "children":
        # Setup CSS Grid Template
        offset 4'pp, 4'pp
        setGridCols 1'fr
        setGridRows csContentMax()
        gridAutoRows 70'ux
        gridAutoFlow grRow
        justifyContent CxCenter

        for i in 0 .. 9:
          button "button", captures(i):
            # current.gridItem = nil
            size 90'pp, 70'ux
            fill rgba(66, 177, 44, 197).to(Color).spin(i.toFloat*50)
            connect(current, doHover, self, Main.hover)

var main = Main.new()
connect(main, doDraw, main, Main.draw)

echo "main: ", main.listeners

app.width = 600
app.height = 480

startFiguro(main)
