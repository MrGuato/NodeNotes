# Changelog

## 0.3.0

- Fishing. Catches are recorded as fishing spots with the same pins, history
  and notes as herb and ore nodes. Casts from one stretch of shore within ten
  minutes count as a single visit.
- `/nn fishing on|off`, on by default.
- Added a luacheck configuration, and a GitHub Actions check that runs
  luacheck and the test harness on every push.

## 0.2.0

- Minimap pins for nodes in your current zone, with a tooltip. Works with a
  rotating minimap and follows minimap zoom.
- `/nn minimap on|off`.
- The diagnostic log is now off by default.

## 0.1.0

- Records herb and mining nodes when you gather them: position, yield, time.
- World map pins with history tooltips.
- Note window on pin click, `/nn` and `/nn note <text>`.
