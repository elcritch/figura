
import std/unittest
import figuro/ui/textboxes
import figuro/ui/apis

let
  typeface = loadTypeFace("IBMPlexSans-Regular.ttf")
  font = UiFont(typefaceId: typeface, size: 22'ui)
  smallFont = UiFont(typefaceId: typeface, size: 12'ui)

import pretty

suite "text boxes (single line)":
  setup:
    var text = newTextBox(initBox(0,0,100,100), font)
    for i in 1..4:
      text.insert(Rune(96+i))
    text.update()

  test "basic setup":
    check text.runes == "abcd".toRunes()
    check text.selection == 4..4

  test "basic insert extra":
    for i in 5..9:
      text.insert(Rune(96+i))
      check text.selection == i..i
      check text.runes == "abcdefghi".toRunes()[0..<i]
    check text.runes == "abcdefghi".toRunes()
    check text.selection == 9..9

  test "basic deletes":
    check text.selection == 4..4
    for i in countdown(3,0):
      text.delete()
      check text.selection == i..i
      check text.runes == "abcdefghi".toRunes()[0..<i]
    check text.runes == "".toRunes()
    check text.selection == 0..0

  test "insert at beginning":
    text.selection = 0..0
    text.insert(Rune('A'))
    check text.selection == 1..1
    check text.runes == "Aabcd".toRunes()

  test "re-insert selected":
    text.selection = 0..1
    text.insert(Rune('A'))
    check text.selection == 1..1
    check text.runes == "Abcd".toRunes()

  test "re-insert selected offset":
    text.selection = 1..2
    text.insert(Rune('B'))
    check text.selection == 2..2
    check text.runes == "aBcd".toRunes()

  test "re-insert at end":
    text.selection = 4..4
    text.insert(Rune('E'))
    check text.selection == 5..5
    check text.runes == "abcdE".toRunes()

  test "double-insert":
    text.selection = 1..3
    text.insert(Rune('B'))
    check text.selection == 2..2
    check text.runes == "aBd".toRunes()

  test "cursor right":
    text.selection = 0..0
    for i in 1..4:
      text.cursorRight()
      check text.selection == i..i
    # extra should clamp
    text.cursorRight()
    check text.selection == 4..4
    check text.runes == "abcd".toRunes()

  test "cursor grow right":
    text.selection = 0..0
    for i in 1..4:
      text.cursorRight(growSelection=true)
      check text.selection == 0..i
    # extra should clamp
    text.cursorRight(growSelection=true)
    check text.selection == 0..4
    check text.runes == "abcd".toRunes()

  test "cursor left":
    text.selection = 4..4
    for i in countdown(3,0):
      text.cursorLeft()
      check text.selection == i..i
    # extra should clamp
    text.cursorLeft()
    check text.selection == 0..0
    check text.runes == "abcd".toRunes()

  test "cursor grow left":
    text.selection = 4..4
    for i in countdown(3,0):
      text.cursorLeft(growSelection=true)
      check text.selection == i..4
    # extra should clamp
    text.cursorLeft(growSelection=true)
    check text.selection == 0..4
    check text.runes == "abcd".toRunes()

  test "cursor up":
    text.selection = 2..2
    text.cursorUp()
    check text.selection == 0..0
    check text.runes == "abcd".toRunes()

  test "cursor up grow":
    text.selection = 2..2
    text.cursorUp(growSelection=true)
    check text.selection == 0..2
    check text.runes == "abcd".toRunes()

  test "cursor down":
    text.selection = 2..2
    text.cursorDown()
    check text.selection == 4..4
    check text.runes == "abcd".toRunes()

  test "cursor down grow":
    text.selection = 2..2
    text.cursorDown(growSelection=true)
    check text.selection == 2..4
    check text.runes == "abcd".toRunes()

  test "inserts":
    var tx = newTextBox(initBox(0,0,100,100), font)
    tx.insert("one".toRunes)
    check tx.selection == 3..3
    check tx.runes == "one".toRunes()

  test "cursor grow direction handling (right)":
    text.selection = 0..0
    text.cursorRight(growSelection=true)
    check text.selection == 0..1
    text.cursorRight(growSelection=true)
    check text.selection == 0..2
    text.cursorLeft(growSelection=true)
    check text.selection == 0..1
    text.cursorLeft(growSelection=true)
    check text.selection == 0..0
    check text.runes == "abcd".toRunes()

  test "cursor grow direction handling (left)":
    text.selection = 2..2
    text.cursorLeft(growSelection=true)
    check text.selection == 1..2
    text.cursorLeft(growSelection=true)
    check text.selection == 0..2
    text.cursorRight(growSelection=true)
    check text.selection == 1..2
    text.cursorRight(growSelection=true)
    check text.selection == 2..2
    check text.runes == "abcd".toRunes()

suite "textboxes (two line)":
  setup:
    var text = newTextBox(initBox(0,0,100,100), font)
    text.insert("one\ntwos".toRunes)
    text.update()

  test "basic":
    check text.runes == "one\ntwos".toRunes()
    check text.selection == 8..8

  test "cursor up":
    text.selection = 6..6
    text.cursorUp()
    check text.selection == 2..2

    text.selection = 5..5
    text.cursorUp()
    check text.selection == 1..1

    text.selection = 7..7
    text.cursorUp()
    check text.selection == 3..3

    text.selection = 8..8
    text.cursorUp()
    check text.selection == 3..3
    check text.runes == "one\ntwos".toRunes()

  test "cursor up grow":
    text.selection = 6..6
    text.cursorUp(growSelection=true)
    check text.selection == 2..6
    text.cursorUp(growSelection=true)
    check text.selection == 0..6
    check text.runes == "one\ntwos".toRunes()

  test "cursor down":
    text.selection = 2..2
    text.cursorDown()
    check text.selection == 6..6
    text.selection = 3..3
    text.cursorDown()
    check text.selection == 7..7
    check text.runes == "one\ntwos".toRunes()

  test "cursor down grow":
    text.selection = 2..2
    text.cursorDown(growSelection=true)
    check text.selection == 2..6
    check text.runes == "one\ntwos".toRunes()

suite "textboxes (three line)":
  setup:
    var text = newTextBox(initBox(0,0,100,100), font)
    text.insert("one\ntwos\nthrees".toRunes)
    text.update()

  test "basic":
    check text.runes == "one\ntwos\nthrees".toRunes()
    check text.selection == 15..15

  test "cursor up":
    text.selection = 10..10
    text.cursorUp()
    check text.selection == 5..5

    text.selection = 11..11
    text.cursorUp()
    check text.selection == 6..6

    text.selection = 12..12
    text.cursorUp()
    check text.selection == 7..7

    text.selection = 14..14
    text.cursorUp()
    check text.selection == 8..8

    text.selection = 15..15
    text.cursorUp()
    check text.selection == 8..8

    check text.runes == "one\ntwos\nthrees".toRunes()

  test "cursor up grow":
    text.selection = 6..6
    text.cursorUp(growSelection=true)
    check text.selection == 2..6
    text.cursorUp(growSelection=true)
    check text.selection == 0..6
    check text.runes == "one\ntwos\nthrees".toRunes()

  test "cursor down":
    text.selection = 2..2
    text.cursorDown()
    check text.selection == 6..6
    text.selection = 3..3
    text.cursorDown()
    check text.selection == 7..7
    check text.runes == "one\ntwos\nthrees".toRunes()

  test "cursor down grow":
    text.selection = 2..2
    text.cursorDown(growSelection=true)
    check text.selection == 2..6
    check text.runes == "one\ntwos\nthrees".toRunes()

suite "textbox move words":
  setup:
    var text = newTextBox(initBox(0,0,100,100), font)
    text.insert("one twos threes".toRunes)
    text.update()

  test "cursor word right":
    text.selection = 0..0
    text.cursorWordRight()
    check text.selection == 3..3

    text.selection = 5..5
    text.cursorWordRight()
    check text.selection == 8..8
    check text.runes == "one twos threes".toRunes()

  test "cursor word right grow":
    text.selection = 0..0
    text.cursorWordRight()
    check text.selection == 3..3

    text.selection = 5..5
    text.cursorWordRight()
    check text.selection == 8..8
    check text.runes == "one twos threes".toRunes()

  test "cursor word left":
    text.selection = 5..5
    text.cursorWordLeft()
    check text.selection == 4..4

    text.cursorWordLeft()
    check text.selection == 0..0
    check text.runes == "one twos threes".toRunes()
