
## This minimal example shows 5 blue squares.
import figuro/widgets/button
import figuro/widget
import figuro

import std/with

type
  Main* = ref object of Figuro
    value: float
    hasHovered: bool
    hoveredAlpha: float
    mainRect: Figuro

proc draw*(self: Main) {.slot.} =

  withNodes(self):
    rectangle "body":
      with current:
        fill css"#D0D0D0"
        box 10'pp, 10'pp, 80'pp, 80'pp
        cornerRadius 10.0'ui

      button "btn":
        with current:
          box 10'pp, 10'pp, 80'pp, 10'pp
          fill css"#2B9FEA"

      button "btn":
        box 10'pp, 60'pp, 80'pp, 10'pp
        fill "#2B9FEA"

var main = Main.new()
connect(main, doDraw, main, Main.draw)

echo "main: ", main.listeners

app.width = 400
app.height = 400

startFiguro(main)
