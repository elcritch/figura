import std/[monotimes, times]
import pkg/sigils
import pkg/chronicles
import ../commons
import apis

type Fader* = ref object of Agent
  minMax*: Slice[float] = 0.0..1.0
  inTime*: Duration
  outTime*: Duration
  fadingIn: bool = false
  active: bool = false
  amount: float = 0.0
  ts: MonoTime
  ratePerMs: Slice[float]
  targets: seq[Figuro]

proc amount*(fader: Fader): float = fader.amount
proc fadeTick*(fader: Fader, value: tuple[amount, perc: float]) {.signal.}
proc fadeDone*(fader: Fader, value: tuple[amount, perc: float]) {.signal.}

proc addTarget*(self: Fader, node: Figuro) {.slot.} =
  self.targets.addUnique(node)

proc tick*(self: Fader, now: MonoTime, delta: Duration) {.slot.} =
  let rate = if self.fadingIn: self.ratePerMs.a else: self.ratePerMs.b
  let dt = delta.inMilliseconds.toFloat
  if self.fadingIn:
    self.amount = self.amount + rate * dt
    if self.amount >= self.minMax.b:
      self.amount = self.minMax.b
      self.active = false
  elif not self.fadingIn:
    self.amount = self.amount - rate * dt
    if self.amount <= self.minMax.a:
      self.amount = self.minMax.a
      self.active = false
  notice "fader:tick: ", amount = self.amount
  
  let (x,y) = if self.fadingIn: (self.minMax.b, self.minMax.a)
              else: (self.minMax.a, self.minMax.b)

  let val = (amount: self.amount, perc: (self.amount-x)/(y-x))
  if self.active:
    emit self.fadeTick(val)
  else:
    for tgt in self.targets:
      disconnect(tgt.frame[].root, doTick, self)
    emit self.fadeDone(val)

proc stop*(self: Fader) {.slot.} =
  self.active = false
  for tgt in self.targets:
    disconnect(tgt.frame[].root, doTick, self)

proc start*(self: Fader, fadeIn: bool) {.slot.} =
  self.active = true
  self.ts = getMonoTime()
  self.fadingIn = fadeIn
  let delta = self.minMax.b - self.minMax.a
  if self.inTime.inMilliseconds > 0:
    self.ratePerMs.a = delta / self.inTime.inMilliseconds.toFloat
  if self.outTime.inMilliseconds > 0:
    self.ratePerMs.b = delta / self.outTime.inMilliseconds.toFloat
  for tgt in self.targets:
    connect(tgt.frame[].root, doTick, self, tick)
  info "fader:started: ", amt = self.amount, ratePerMs= self.ratePerMs, fadeOn= self.inTime, fadeOut= self.outTime

proc fadeIn*(self: Fader) {.slot.} =
  self.start(true)

proc fadeOut*(self: Fader) {.slot.} =
  self.start(false)

proc setMax*(self: Fader) {.slot.} =
  self.amount = self.minMax.b

proc setMin*(self: Fader) {.slot.} =
  self.amount = self.minMax.a
