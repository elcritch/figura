import std/unicode

import commons
import utils

type
  TextDirection* = enum
    left
    right

  TextBox* = ref object
    selection*: Slice[int]
    growing*: TextDirection # Text editors store selection direction to control how keys behave
    selectionRects*: seq[Box]
    cursorRect*: Box
    selHash: Hash
    layout*: GlyphArrangement
    font*: UiFont
    box*: Box

proc runes*(self: TextBox): var seq[Rune] = self.layout.runes

proc toSlice[T](a: T): Slice[T] = a..a # Shortcut 
proc hasSelection*(self: TextBox): bool =
  self.selection != 0..0 and self.layout.runes.len() > 0
proc clamped*(self: TextBox, dir = right, offset = 0): int =
  let ln = self.layout.runes.len()
  case dir
  of left:
    result = clamp(self.selection.a + offset, 0, ln)
  of right:
    result = clamp(self.selection.b + offset, 0, ln)

proc newTextBox*(box: Box, font: UiFont): TextBox =
  result = TextBox()
  result.box = box
  result.font = font
  result.layout = GlyphArrangement()

proc updateLayout*(self: var TextBox, box = self.box, font = self.font) =
  ## Update layout from runes.
  ## 
  ## This appends an extra character at the end to get the cursor
  ## position at the end, which depends on the next character.
  ## Otherwise, this character is ignored.
  self.box = box
  self.font = font
  let spans = {self.font: $self.runes(),
               self.font: "."}
  self.layout = internal.getTypeset(self.box, spans)
  self.runes().setLen(self.runes().len() - 1)

iterator slices(selection: Slice[int], lines: seq[Slice[int]]): Slice[int] =
  ## get the slices for each line given a `selection`
  for line in lines:
    if selection.a in line or
       selection.b in line or
       (selection.a < line.a and line.b < selection.b):
      # handle partial lines
      yield max(line.a, selection.a)..min(line.b, selection.b)
    else: # handle full lines
      yield line.a..line.a

import pretty

proc updateCursor(self: var TextBox) =
  # print "updateCursor:sel: ", self.selection
  # print "updateCursor:selRect: ", self.selectionRects
  # print "updateCursor:layout: ", self.layout

  var cursor: Rect
  case self.growing:
  of left:
    cursor = self.layout.selectionRects[self.selection.a]
  of right:
    cursor = self.layout.selectionRects[self.selection.b]

  ## this is gross but works for now
  let fontSize = self.font.size.scaled()
  let width = max(0.08*fontSize, 2.0)
  cursor.x = cursor.x - width/2.0
  cursor.y = cursor.y - 0.04*fontSize
  cursor.w = width
  cursor.h = 0.9*fontSize
  self.cursorRect = cursor.descaled()

proc updateSelection*(self: var TextBox) =
  ## update selection boxes, each line has it's own selection box
  self.selectionRects.setLen(0)
  for sel in self.selection.slices(self.layout.lines):
    let lhs = self.layout.selectionRects[sel.a]
    let rhs = self.layout.selectionRects[sel.b]
    # rect starts on left hand side
    var rect = lhs
    # find the width and height of the rect
    rect.w = rhs.x - lhs.x
    rect.h = (rhs.y + rhs.h) - lhs.y
    self.selectionRects.add rect.descaled()
    # let fs = self.theme.font.size.scaled
    # var rs = self.selectionRects[i]
    # rs.y = rs.y - 0.1*fs
  self.selection = self.clamped(left) .. self.clamped(right)
  self.updateCursor()

proc update*(self: var TextBox) =
  self.updateLayout()
  self.updateSelection()

proc findLine*(self: TextBox, down: bool, isGrowingSelection = false): int =
  result = -1
  let lhs = self.selection.a
  let rhs = self.selection.b
  for idx, line in self.layout.lines:
    if isGrowingSelection:
      if self.growing == left and lhs in line:
        return idx
      if self.growing == right and rhs in line:
        return idx
    else:
      if down:
        if rhs in line:
          return idx
      elif lhs in line:
        return idx

proc findPrevWord*(self: TextBox): int =
  result = -1
  for i in countdown(max(0,self.selection.a-2), 0):
    if self.runes()[i].isWhiteSpace():
      return i

proc findNextWord*(self: TextBox): int =
  result = self.runes().len()
  for i in countup(self.selection.a+1, self.runes().len()-1):
    if self.runes()[i].isWhiteSpace():
      return i

proc delete*(self: var TextBox) =
  if self.selection.len() > 1:
    let delSlice = self.clamped(left) .. self.clamped(right, offset = -1)
    if self.runes().len() > 1:
      self.runes().delete(delSlice)
    self.selection = self.clamped(left).toSlice()
  elif self.selection.len() == 1:
    if self.runes().len() > 1:
      self.layout.runes.delete(self.clamped(left, offset = -1))
    self.selection = toSlice(self.clamped(left, offset = -1))

proc insert*(self: var TextBox, rune: Rune) =
  self.delete()
  self.runes.insert(rune, self.clamped(left))
  self.selection = toSlice(self.selection.a + 1)

proc cursorLeft*(self: var TextBox, growSelection = false) =
  if growSelection:
    if self.selection.len() == 1: self.growing = left
    case self.growing:
    of left:
      self.selection.a = self.clamped(left, offset = -1)
    of right:
      self.selection.b = self.clamped(right, offset = -1)
  else:
    self.selection = toSlice self.clamped(self.growing, offset = -1)

proc cursorStart*(self: var TextBox, growSelection = false) =
  if growSelection:
    self.selection.a = 0
    self.growing = left
  else:
    self.selection = 0..0

proc cursorEnd*(self: var TextBox, growSelection = false) =
  if growSelection:
    self.selection.b = self.runes.len
    self.growing = right
  else:
    self.selection = toSlice self.runes.len()

proc cursorRight*(self: var TextBox, growSelection = false) =
  if growSelection:
    if self.selection.len() > 1: self.growing = left
    case self.growing:
    of left:
      self.selection.a = self.clamped(left, offset = 1)
    of right:
      self.selection.b = self.clamped(right, offset = 1)
  else:
    # if self.selection.len != 1 and growing == right:
    self.selection = toSlice self.clamped(self.growing, offset = 1)

proc cursorDown*(self: var TextBox, growSelection = false) =
  ## Move cursor or selection down
  let
    presentLine = self.findLine(true, growSelection)
    startCurrLine = self.layout.lines[presentLine].a
    nextLine = clamp(presentLine + 1, 0, self.layout.lines.high)
    lineStart = self.layout.lines[nextLine]

  if presentLine == self.layout.lines.high:
    # if last line, goto end
    self.selection = toSlice(self.layout.lines[^1].b)
  else:
    let lineDiff = 
      if growSelection:
        self.clamped(dir=self.growing) - startCurrLine
      else:
        self.clamped(right) - startCurrLine
    self.selection = toSlice(min(lineStart.a + lineDiff, lineStart.b))
  # textBox.adjustScroll()

proc cursorUp*(self: var TextBox, growSelection = false) =
  ## Move cursor or selection up
  let
    presentLine = self.findLine(true, growSelection)
    startCurrLine = self.layout.lines[presentLine].a
    nextLine = clamp(presentLine + 1, 0, self.layout.lines.high)
    lineStart = self.layout.lines[nextLine]

  if presentLine == 0:
    # if first line, goto start
    self.selection = toSlice(0)
  else:
    let lineDiff = 
      if growSelection:
        self.clamped(dir=self.growing) - startCurrLine
      else:
        self.clamped(left) - startCurrLine
    self.selection = toSlice(min(lineStart.a + lineDiff, lineStart.b))
  # textBox.adjustScroll()

proc cursorSelectAll*(self: var TextBox) =
  self.selection = 0..self.runes.len

