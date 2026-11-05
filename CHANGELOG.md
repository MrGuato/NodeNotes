# Changelog

## 0.4.0

- Rares. Targeting, hovering or seeing the nameplate of a rare records where
  you met it, with a skull pin. Looting it adds the kill and its drop.
  `/nn rares on|off`, on by default.
- Special finds. A blue or better from any mob gets its own pin.
  `/nn finds on|off|green|blue|epic`.
- Chests are on by default. Upgrading from 0.3.0 or earlier turns them on
  once; `/nn chests off` turns them off again. Chests are named after the
  chest you opened, or after the first
  item when no name is available. Objects that only hold quest items are
  skipped. Chests from earlier versions are kept.
- A coloured ring on the world map marks a node that ever gave you a blue or
  better.
- Continent maps show the nodes of every zone inside them.
  `/nn continent on|off`.
- Square minimaps from UI addons are supported.
- Herb and mining casts are recognised by spell id and the game's own spell
  name, so non-English clients work.
- Optional sharing with your group or guild, off by default:
  `/nn share group|guild|both|off` and `/nn share sync`. Friends' nodes show
  with a blue corner on the world map and are kept apart from yours.
  `/nn friends on|off|clear`, on by default.
- `/nn status` counts nodes by kind.
- Animated tour in the README.

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
