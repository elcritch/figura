
import std/[macros, typetraits]


#include <QObject>

import figuro/meta/signals
import figuro/meta/slots

type

  Counter* = ref object of Agent
    value: int

# var router = newAgentRouter()

template emit*(call: untyped) =
  call

proc valueChanged*(tp: Counter, val: int) {.signal.}

proc setValue*(self: Counter, value: int) {.slot.} =
  echo "setValue!"
  self.value = value
  emit self.valueChanged(value)

proc value*(self: Counter): int =
  self.value

import pretty
# print router

echo "ROUTER: ", listMethods()


when isMainModule:
  import unittest

  suite "agent slots":

    test "signal connect":
      var
        a = Counter()
        b = Counter()
        c = Counter()
        d = Counter()
      
      # TODO: how to do this?
      connect(a, valueChanged,
              b, setValue)
      connect(a, valueChanged,
              c, setValue)
      
      check b.value == 0
      check c.value == 0
      check d.value == 0

      a.valueChanged(137)

      check a.value == 0
      check b.value == 137
      check c.value == 137
      check d.value == 0


