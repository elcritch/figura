
import commons
import ../ui/utils

type
  StatefulWidget*[T] = ref object of Figuro
    state*: T

  Button*[T] = ref object of StatefulWidget[T]
    label*: string
    isActive*: bool
    disabled*: bool

proc hover*[T](self: Button[T], kind: EventKind) {.slot.} =
  # self.fill = parseHtmlColor "#9BDFFA"
  # echo "button hover!"
  echo "button:hovered: ", kind, " :: ", self.getId,
          " buttons: ", self.events.mouse
  # if kind == Enter:
  #   self.events.mouse.incl evHover
  # else:
  #   self.events.mouse.excl evHover
  # refresh(self)

proc clicked*[T](self: Button[T],
                  kind: EventKind,
                  buttons: UiButtonView) {.slot.} =
  echo nd(), "button:clicked: ", buttons,
              " kind: ", kind, " :: ", self.getId

  if not self.isActive:
    refresh(self)
  self.isActive = true

proc draw*[T](self: Button[T]) {.slot.} =
  ## button widget!
  withDraw(self):
    
    clipContent true
    cornerRadius 10.0

    if self.disabled:
      fill "#F0F0F0"
    else:
      fill "#2B9FEA"
      onHover:
        fill current.fill.spin(15)
        # this changes the color on hover!

import ../ui/utils

# template button*[T](s: State[T] = state(void),
#                     name: string,
#                     blk: untyped) =
#   button(s, name, void, blk)

# template button*(name: string,
#                  value: untyped,
#                  blk: untyped) =
#   button(state(void), name, value, blk)

# template button*(name: string,
#                  blk: untyped) =
#   button(state(void), name, void, blk)

from sugar import capture
import macros

macro button*(args: varargs[untyped]) =
  echo "button:\n", args.treeRepr
  # echo "do:\n", args[2].treeRepr
  let widget = ident "Button"
  let wargs = args.parseWidgetArgs()

  result = widget.generateBodies(wargs)
  echo "button:result:\n", result.repr
  


# template button*[V](id: string, value: V, blk: untyped) =
# # template button*(id: string, blk: untyped) =
#   button[void, V](void, id, value, blk)
