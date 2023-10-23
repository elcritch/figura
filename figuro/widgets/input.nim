import std/unicode

import commons
import ../ui/utils
import ../ui/textutils

type
  Input* = ref object of Figuro
    isActive*: bool
    disabled*: bool
    text*: TextBox
    value: int
    cnt: int

proc doKeyCommand*(self: Input,
                   pressed: UiButtonView,
                   down: UiButtonView) {.signal.}

proc tick*(self: Input, tick: int, now: MonoTime) {.slot.} =
  if self.isActive:
    self.cnt.inc()
    self.cnt = self.cnt mod 33
    if self.cnt == 0:
      self.value = (self.value + 1) mod 2
      refresh(self)

proc clicked*(self: Input,
              kind: EventKind,
              buttons: UiButtonView) {.slot.} =
  self.isActive = kind == Enter
  if self.isActive:
    self.listens.signals.incl {evKeyboardInput, evKeyPress}
  else:
    self.listens.signals.excl {evKeyboardInput, evKeyPress}
    self.value = 0
  refresh(self)

proc keyInput*(self: Input,
               rune: Rune) {.slot.} =
  self.text.insert(rune)
  self.text.update()
  refresh(self)

proc getKey(p: UiButtonView): UiButton =
  for x in p:
    if x.ord in KeyRange.low.ord .. KeyRange.high.ord:
      return x

proc keyCommand*(self: Input,
                 pressed: UiButtonView,
                 down: UiButtonView) {.slot.} =
  when defined(debugEvents):
    echo "\nInput:keyPress: ",
            " pressed: ", $pressed,
            " down: ", $down, " :: ", self.selection
  if down == KNone:
    case pressed.getKey
    of KeyBackspace:
      if self.text.hasSelection():
        self.text.delete()
        self.text.update()
    of KeyLeft:
      self.text.cursorLeft()
    of KeyRight:
      self.text.cursorRight()
    of KeyHome:
      self.text.cursorStart()
    of KeyEnd:
      self.text.cursorEnd()
    of KeyUp:
      self.text.cursorUp()
    of KeyDown:
      self.text.cursorDown()
    of KeyEscape:
      self.clicked(Exit, {})
    of KeyEnter:
      self.keyInput Rune '\n'
    else:
      discard
    self.text.updateSelection()

  elif down == KMeta:
    case pressed.getKey
    of KeyA:
      self.text.cursorSelectAll()
    of KeyLeft:
      self.text.cursorStart()
    of KeyRight:
      self.text.cursorEnd()
    else:
      discard
    self.text.updateSelection()

  elif down == KShift:
    case pressed.getKey
    of KeyLeft:
      self.text.cursorLeft(growSelection=true)
    of KeyRight:
      self.text.cursorRight(growSelection=true)
    of KeyUp:
      self.text.cursorUp(growSelection=true)
    of KeyDown:
      self.text.cursorDown(growSelection=true)
    of KeyHome:
      self.text.cursorStart(growSelection=true)
    of KeyEnd:
      self.text.cursorEnd(growSelection=true)
    else:
      discard
    self.text.updateSelection()

  ## todo
  # elif down == KAlt:
  #   case pressed.getKey
  #   of KeyLeft:
  #     let idx = findPrevWord(self)
  #     self.selection = idx+1..idx+1
  #   of KeyRight:
  #     let idx = findNextWord(self)
  #     self.selection = idx..idx
  #   of KeyBackspace:
  #     if aa > 0:
  #       let idx = findPrevWord(self)
  #       self.runes.delete(idx+1..aa-1)
  #       self.selection = idx+1..idx+1
  #       self.updateLayout()
  #   else: discard

  self.value = 1
  self.text.updateSelection()
  refresh(self)

proc keyPress*(self: Input,
               pressed: UiButtonView,
               down: UiButtonView) {.slot.} =
  emit self.doKeyCommand(pressed, down)

proc draw*(self: Input) {.slot.} =
  ## Input widget!
  connect(self, doKeyCommand, self, Input.keyCommand)

  withDraw(self):
    if self.text.isNil:
      self.text = newTextBox(self.box, self.theme.font)

    clipContent true
    cornerRadius 10.0

    text "text":
      # box 10'ux, 10'ux, 400'ux, 100'ux
      fill blackColor
      # current.textLayout = self.layout

      rectangle "cursor":
        boxOf self.text.cursorRect
        fill blackColor
        current.fill.a = self.value.toFloat * 1.0

      for i, selRect in self.text.selectionRects:
        rectangle "selection", captures(i):
          boxOf self.text.selectionRects[i]
          fill "#A0A0FF".parseHtmlColor 
          current.fill.a = 0.4

    if self.disabled:
      fill whiteColor.darken(0.4)
    else:
      fill whiteColor.darken(0.2)
      if self.isActive:
        fill current.fill.lighten(0.15)
        # this changes the color on hover!

exportWidget(input, Input)
