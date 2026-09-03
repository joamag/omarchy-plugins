// Tests for joamag.display: Model.js in declaration order, then display.sh
// driven against fake ddcutil / busctl / hyprctl / omarchy helpers on PATH.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { loadModel, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.display")

const RAW = [
  "monitor\tDP-1",
  "bus\t3",
  "brightness\t75",
  "contrast\t60",
  "gamma\t1.35",
  "temperature\t4500",
  "scale\t2.0",
  'displays\t[{"name":"DP-1","enabled":true,"focused":true,"width":3840,"height":2160}]',
  "",
].join("\n")

const snapshot = Model.parseSnapshot(RAW)
// A laptop panel: brightness from the backlight, no DDC/CI, no ramp daemon.
const backlightOnly = Model.parseSnapshot("monitor\teDP-1\nbrightness\t40\n")
const nothing = Model.parseSnapshot("monitor\tDP-1\n")
const neutral = Model.parseSnapshot("brightness\t75\ngamma\t1\ntemperature\t6500\n")

describe("num", () => {
  it("parses numeric strings and rejects the rest", () => {
    assert.equal(Model.num("75"), 75)
    assert.equal(Model.num("1.35"), 1.35)
    assert.ok(Number.isNaN(Model.num("abc")))
    assert.ok(Number.isNaN(Model.num(undefined)))
    assert.ok(Number.isNaN(Model.num("")))
  })
})

describe("parseSnapshot", () => {
  it("reads every field of a full snapshot", () => {
    assert.equal(snapshot.monitor, "DP-1")
    assert.equal(snapshot.bus, "3")
    assert.equal(snapshot.brightness, 75)
    assert.equal(snapshot.contrast, 60)
    assert.equal(snapshot.gamma, 1.35)
    assert.equal(snapshot.temperature, 4500)
    assert.equal(snapshot.scale, "2")
    assert.equal(snapshot.enabledDisplayCount, 1)
    assert.equal(snapshot.displays[0].name, "DP-1")
  })

  it("leaves a control unknown rather than zero when it is absent", () => {
    assert.ok(Number.isNaN(nothing.brightness))
    assert.ok(Number.isNaN(nothing.contrast))
    assert.ok(Number.isNaN(nothing.gamma))
    assert.ok(Number.isNaN(nothing.temperature))
  })

  it("survives empty and malformed input", () => {
    const empty = Model.parseSnapshot("")
    assert.equal(empty.monitor, "")
    assert.deepEqual(empty.displays, [])
    assert.deepEqual(Model.parseSnapshot(null).displays, [])
    assert.deepEqual(Model.parseSnapshot("bogus\nkeyonly\n").displays, [])
    assert.deepEqual(Model.parseSnapshot("displays\tnot json").displays, [])
  })
})

describe("controlValue", () => {
  it("reads a control off the snapshot", () => {
    assert.equal(Model.controlValue(snapshot, "contrast"), 60)
    assert.ok(Number.isNaN(Model.controlValue(snapshot, "bogus")))
    assert.ok(Number.isNaN(Model.controlValue(null, "contrast")))
  })
})

describe("hasControl", () => {
  it("is true only for a control the machine reported", () => {
    assert.equal(Model.hasControl(snapshot, "gamma"), true)
    assert.equal(Model.hasControl(backlightOnly, "contrast"), false)
    assert.equal(Model.hasControl(null, "brightness"), false)
  })
})

describe("visibleControls", () => {
  it("lists the sliders the machine can drive, in panel order", () => {
    assert.deepEqual(Model.visibleControls(snapshot), ["brightness", "contrast", "gamma", "temperature"])
    assert.deepEqual(Model.visibleControls(backlightOnly), ["brightness"])
    assert.deepEqual(Model.visibleControls(nothing), [])
    assert.deepEqual(Model.visibleControls(null), [])
  })
})

describe("controlByKey", () => {
  it("finds a control and rejects an unknown one", () => {
    assert.equal(Model.controlByKey("gamma").title, "GAMMA")
    assert.equal(Model.controlByKey("bogus"), null)
  })
})

describe("controlMinimum", () => {
  it("floors each control on its own scale", () => {
    assert.equal(Model.controlMinimum("brightness"), 1)
    assert.equal(Model.controlMinimum("contrast"), 0)
    assert.equal(Model.controlMinimum("gamma"), 0.3)
    assert.equal(Model.controlMinimum("temperature"), 2500)
    assert.equal(Model.controlMinimum("bogus"), 0)
  })
})

describe("controlMaximum", () => {
  it("caps gamma where the NVIDIA control panel caps it", () => {
    assert.equal(Model.controlMaximum("gamma"), 2.8)
    assert.equal(Model.controlMaximum("brightness"), 100)
    assert.equal(Model.controlMaximum("temperature"), 6500)
    assert.equal(Model.controlMaximum("bogus"), 100)
  })
})

describe("controlStep", () => {
  it("steps each control by a sensible amount of its scale", () => {
    assert.equal(Model.controlStep("brightness"), 1)
    assert.equal(Model.controlStep("gamma"), 0.01)
    assert.equal(Model.controlStep("temperature"), 100)
    assert.equal(Model.controlStep("bogus"), 1)
  })
})

describe("controlDecimals", () => {
  it("marks gamma as the one decimal control", () => {
    assert.equal(Model.controlDecimals("gamma"), 2)
    assert.equal(Model.controlDecimals("brightness"), 0)
    assert.equal(Model.controlDecimals("bogus"), 0)
  })
})

describe("controlTitle", () => {
  it("names each slider", () => {
    assert.equal(Model.controlTitle("brightness"), "BRIGHTNESS")
    assert.equal(Model.controlTitle("temperature"), "TEMPERATURE")
    assert.equal(Model.controlTitle("bogus"), "")
  })
})

describe("controlScope", () => {
  it("separates the monitor's own settings from the session ramp", () => {
    assert.equal(Model.controlScope("brightness"), "monitor")
    assert.equal(Model.controlScope("contrast"), "monitor")
    assert.equal(Model.controlScope("gamma"), "session")
    assert.equal(Model.controlScope("temperature"), "session")
    assert.equal(Model.controlScope("bogus"), "monitor")
  })
})

describe("clampControl", () => {
  it("clamps into each control's own range", () => {
    assert.equal(Model.clampControl("brightness", 0), 1)
    assert.equal(Model.clampControl("brightness", 250), 100)
    assert.equal(Model.clampControl("contrast", -5), 0)
    assert.equal(Model.clampControl("gamma", 5), 2.8)
    assert.equal(Model.clampControl("gamma", 0.1), 0.3)
    assert.equal(Model.clampControl("temperature", 9000), 6500)
    assert.equal(Model.clampControl("temperature", 1000), 2500)
  })

  it("snaps to the control's step without leaving binary dust", () => {
    assert.equal(Model.clampControl("gamma", 1.3487261), 1.35)
    assert.equal(Model.clampControl("gamma", 1.364), 1.36)
    assert.equal(Model.clampControl("temperature", 4530), 4500)
    assert.equal(Model.clampControl("brightness", 74.6), 75)
  })

  it("falls back to neutral, or the floor, for a value that is not a number", () => {
    assert.equal(Model.clampControl("gamma", "abc"), 1)
    assert.equal(Model.clampControl("temperature", "abc"), 6500)
    assert.equal(Model.clampControl("brightness", "abc"), 1)
    assert.equal(Model.clampControl("bogus", 5), 0)
  })
})

describe("clampBrightness", () => {
  it("is the brightness case of clampControl", () => {
    assert.equal(Model.clampBrightness(0), 1)
    assert.equal(Model.clampBrightness(120), 100)
  })
})

describe("clamp01", () => {
  it("holds a fraction inside the unit range", () => {
    assert.equal(Model.clamp01(0.5), 0.5)
    assert.equal(Model.clamp01(-1), 0)
    assert.equal(Model.clamp01(9), 1)
    assert.equal(Model.clamp01("abc"), 0)
  })
})

describe("sliderFromValue", () => {
  it("places a linear control proportionally", () => {
    assert.equal(Model.sliderFromValue("temperature", 4500), 50)
    assert.equal(Model.sliderFromValue("temperature", 6500), 100)
    assert.equal(Model.sliderFromValue("contrast", 25), 25)
  })

  it("gives gamma a log track, so neutral sits near the middle", () => {
    assert.equal(Model.sliderFromValue("gamma", 0.3), 0)
    assert.equal(Model.sliderFromValue("gamma", 2.8), 100)
    // On a linear track 1.00 would sit at 28%, with the whole darkening half
    // crushed into the bottom quarter of the travel.
    const neutralAt = Model.sliderFromValue("gamma", 1)
    assert.ok(neutralAt > 50 && neutralAt < 58, `neutral at ${neutralAt}%`)
  })

  it("spends equal travel on halving and on doubling", () => {
    const neutralAt = Model.sliderFromValue("gamma", 1)
    const below = neutralAt - Model.sliderFromValue("gamma", 0.5)
    const above = Model.sliderFromValue("gamma", 2) - neutralAt
    assert.ok(Math.abs(below - above) < 0.001, `${below} vs ${above}`)
  })

  it("clamps out of range values and falls back to neutral", () => {
    assert.equal(Model.sliderFromValue("gamma", 99), 100)
    assert.equal(Model.sliderFromValue("gamma", 0.01), 0)
    assert.equal(Model.sliderFromValue("gamma", NaN), Model.sliderFromValue("gamma", 1))
    assert.equal(Model.sliderFromValue("brightness", NaN), 0)
    assert.equal(Model.sliderFromValue("bogus", 5), 0)
  })
})

describe("valueFromSlider", () => {
  it("round-trips every control", () => {
    for (const [key, value] of [["brightness", 75], ["contrast", 40], ["gamma", 1.35], ["temperature", 4500]]) {
      assert.equal(Model.valueFromSlider(key, Model.sliderFromValue(key, value)), value, key)
    }
  })

  it("walks the gamma track without a dead stretch", () => {
    // Every tenth of the travel has to be a different, increasing value:
    // that is exactly what the linear track failed to do at the top end.
    let previous = -1
    for (let position = 0; position <= 100; position += 10) {
      const value = Model.valueFromSlider("gamma", position)
      assert.ok(value > previous, `travel ${position}% gave ${value} after ${previous}`)
      previous = value
    }
  })

  it("clamps a position off either end", () => {
    assert.equal(Model.valueFromSlider("gamma", -20), 0.3)
    assert.equal(Model.valueFromSlider("gamma", 500), 2.8)
    assert.equal(Model.valueFromSlider("bogus", 50), 0)
  })
})

describe("controlKeyStep", () => {
  it("moves a log control in smaller steps than a linear one", () => {
    assert.equal(Model.controlKeyStep("gamma"), 2)
    assert.equal(Model.controlKeyStep("brightness"), 5)
    assert.equal(Model.controlKeyStep("bogus"), 5)
  })
})

describe("isNeutral", () => {
  it("knows where each ramp control rests", () => {
    assert.equal(Model.isNeutral("gamma", 1), true)
    assert.equal(Model.isNeutral("gamma", 1.35), false)
    assert.equal(Model.isNeutral("temperature", 6500), true)
    assert.equal(Model.isNeutral("temperature", 4500), false)
    // Brightness has no neutral: any value is as legitimate as another.
    assert.equal(Model.isNeutral("brightness", 100), false)
    assert.equal(Model.isNeutral("bogus", 1), false)
  })
})

describe("formatControl", () => {
  it("writes each control in its own units", () => {
    assert.equal(Model.formatControl("brightness", 75), "75%")
    assert.equal(Model.formatControl("gamma", 1.35), "1.35")
    assert.equal(Model.formatControl("gamma", 1), "1.00")
    assert.equal(Model.formatControl("temperature", 4500), "4500K")
    assert.equal(Model.formatControl("brightness", NaN), "—")
    assert.equal(Model.formatControl("bogus", 5), "5")
  })
})

describe("formatPercent", () => {
  it("rounds and marks an unknown value", () => {
    assert.equal(Model.formatPercent(74.6), "75%")
    assert.equal(Model.formatPercent(NaN), "—")
  })
})

describe("brightnessName", () => {
  it("names each band", () => {
    assert.equal(Model.brightnessName(100), "Sun blast")
    assert.equal(Model.brightnessName(85), "Solar flare")
    assert.equal(Model.brightnessName(70), "Golden hour")
    assert.equal(Model.brightnessName(50), "Even day")
    assert.equal(Model.brightnessName(35), "Soft glow")
    assert.equal(Model.brightnessName(25), "Lamp light")
    assert.equal(Model.brightnessName(15), "Candlelit")
    assert.equal(Model.brightnessName(1), "Night owl")
  })
})

describe("gammaName", () => {
  it("names the curve either side of the 1.00 neutral", () => {
    assert.equal(Model.gammaName(1), "Neutral")
    assert.equal(Model.gammaName(2.8), "Washed out")
    assert.equal(Model.gammaName(1.35), "Lifted midtones")
    assert.equal(Model.gammaName(0.85), "Deepened midtones")
    assert.equal(Model.gammaName(0.4), "Crushed shadows")
    assert.equal(Model.gammaName("x"), "—")
  })
})

describe("temperatureName", () => {
  it("names the white point", () => {
    assert.equal(Model.temperatureName(6500), "Neutral white")
    assert.equal(Model.temperatureName(5800), "Soft warm")
    assert.equal(Model.temperatureName(4800), "Warm")
    assert.equal(Model.temperatureName(4000), "Night light")
    assert.equal(Model.temperatureName(3000), "Ember")
    assert.equal(Model.temperatureName("x"), "—")
  })
})

describe("controlName", () => {
  it("routes each control to its own naming", () => {
    assert.equal(Model.controlName("gamma", 1), "Neutral")
    assert.equal(Model.controlName("temperature", 6500), "Neutral white")
    assert.equal(Model.controlName("brightness", 100), "Sun blast")
    assert.equal(Model.controlName("contrast", 60), "60%")
  })
})

describe("heroStatus", () => {
  it("names the brightness and every ramp control that is off neutral", () => {
    assert.equal(Model.heroStatus(snapshot), "GOLDEN HOUR · LIFTED MIDTONES · WARM")
    assert.equal(Model.heroStatus(snapshot, 20), "LAMP LIGHT · LIFTED MIDTONES · WARM")
    // Sitting at neutral is not worth saying.
    assert.equal(Model.heroStatus(neutral), "GOLDEN HOUR")
    assert.equal(Model.heroStatus(nothing), "FIXED BRIGHTNESS")
    assert.equal(Model.heroStatus(null), "READING DISPLAY")
  })
})

describe("tooltip", () => {
  it("lists what is known and stays quiet about neutral ramp values", () => {
    assert.equal(Model.tooltip(snapshot), "Display · Brightness 75% · Contrast 60% · Gamma 1.35 · Temperature 4500K")
    assert.equal(Model.tooltip(neutral), "Display · Brightness 75%")
    assert.equal(Model.tooltip(nothing), "Display")
    assert.equal(Model.tooltip(null), "Display")
  })
})

describe("unavailableDetail", () => {
  it("explains only when there is nothing to drive", () => {
    assert.equal(Model.unavailableDetail(snapshot), "")
    assert.match(Model.unavailableDetail(nothing), /does not answer DDC\/CI/)
    assert.match(Model.unavailableDetail(Model.parseSnapshot("bus\t7")), /i2c bus 7/)
    assert.equal(Model.unavailableDetail(null), "")
  })
})

describe("rampDetail", () => {
  it("names the daemon only when the ramp controls are missing", () => {
    assert.equal(Model.rampDetail(snapshot), "")
    assert.match(Model.rampDetail(backlightOnly), /wl-gammarelay-rs/)
    assert.equal(Model.rampDetail(null), "")
  })
})

describe("normalizeScale", () => {
  it("trims a scale to two decimals", () => {
    assert.equal(Model.normalizeScale("2.000"), "2")
    assert.equal(Model.normalizeScale(1.666666), "1.67")
    assert.equal(Model.normalizeScale("abc"), "")
  })
})

describe("gcd", () => {
  it("is the greatest common divisor", () => {
    assert.equal(Model.gcd(12, 8), 4)
    assert.equal(Model.gcd(7, 1), 1)
  })
})

describe("cleanScale", () => {
  it("snaps a requested scale to one the mode can express", () => {
    assert.equal(Model.cleanScale(2, 3840, 2160), "2")
    assert.equal(Model.cleanScale(0, 3840, 2160), "")
    assert.equal(Model.cleanScale(2, 0, 2160), "")
    assert.equal(Model.cleanScale("abc", 3840, 2160), "")
  })
})

describe("matchingScaleIndex", () => {
  it("finds the preset that lands on the current scale", () => {
    const scales = ["1", "1.25", "2"]
    assert.equal(Model.matchingScaleIndex(scales, 2, 3840, 2160), 2)
    assert.equal(Model.matchingScaleIndex(scales, "abc", 3840, 2160), -1)
    assert.equal(Model.matchingScaleIndex(null, 2, 3840, 2160), -1)
  })
})

describe("availableScales", () => {
  it("drops presets that collapse onto the same effective scale", () => {
    const scales = Model.availableScales(["1", "1.25", "2"], 3840, 2160)
    assert.ok(scales.length > 0 && scales.length <= 3)
    assert.deepEqual(Model.availableScales(["1", "2"], 0, 0), ["1", "2"])
    assert.deepEqual(Model.availableScales(null, 3840, 2160), [])
  })
})

describe("parseDisplays", () => {
  it("counts the enabled displays and survives junk", () => {
    const parsed = Model.parseDisplays('[{"name":"DP-1","enabled":true},{"name":"HDMI-A-1","enabled":false}]')
    assert.equal(parsed.displays.length, 2)
    assert.equal(parsed.enabledDisplayCount, 1)
    assert.deepEqual(Model.parseDisplays("not json").displays, [])
    assert.deepEqual(Model.parseDisplays('{"not":"an array"}').displays, [])
    assert.deepEqual(Model.parseDisplays("").displays, [])
  })
})

describe("display.sh", () => {
  const MONITORS = JSON.stringify([
    { name: "DP-1", disabled: false, focused: true, width: 3840, height: 2160 },
  ])

  // A machine where the monitor answers DDC/CI and the ramp daemon is up. The
  // contrast maximum is 60 rather than 100 so the percent conversion is
  // actually exercised in both directions.
  function fakeMachine(t, { ddc = true, ramp = true, rampCanStart = false } = {}) {
    const dir = tmpdir(t)
    const log = path.join(dir, "calls.log")
    const state = path.join(dir, "ramp")
    fs.mkdirSync(state)
    fs.writeFileSync(path.join(state, "Gamma"), "1\n")
    fs.writeFileSync(path.join(state, "Temperature"), "6500\n")
    if (ramp) fs.writeFileSync(path.join(state, "up"), "")

    fakeCommand(dir, "ddcutil", `
printf '%s\\n' "ddcutil $*" >> "${log}"
case "$*" in
  *detect*)
    ${ddc ? `printf 'Display 1\\n   I2C bus:          /dev/i2c-7\\n   DRM connector:    card1-DP-1\\n'` : "printf 'No displays found\\\\n'"}
    ;;
  *getvcp*) ${ddc ? `printf 'VCP 10 C 45 100\\nVCP 12 C 30 60\\n'` : "exit 1"} ;;
  *setvcp*) exit 0 ;;
  *) exit 1 ;;
esac`)

    // Stands in for the D-Bus interface of wl-gammarelay-rs: a property per
    // file, and an "up" marker for whether the daemon is on the bus at all.
    fakeCommand(dir, "busctl", `
printf '%s\\n' "busctl $*" >> "${log}"
case "\${2:-}" in
  list) [[ -f "${state}/up" ]] && printf 'rs.wl-gammarelay 1234 wl-gammarelay-r joamag :1.1 user@1000.service - -\\n'; exit 0 ;;
  get-property)
    [[ -f "${state}/up" ]] || exit 1
    case "\${6:-}" in
      Gamma) printf 'd %s\\n' "$(cat "${state}/Gamma")" ;;
      Temperature) printf 'q %s\\n' "$(cat "${state}/Temperature")" ;;
      *) exit 1 ;;
    esac
    ;;
  set-property)
    [[ -f "${state}/up" ]] || exit 1
    printf '%s\\n' "\${8:-}" > "${state}/\${6:-unknown}"
    ;;
  *) exit 1 ;;
esac`)

    fakeCommand(dir, "hyprctl", `printf '%s\\n' '${MONITORS}'`)
    fakeCommand(dir, "omarchy-hyprland-monitor-scaling", 'echo 2')
    fakeCommand(dir, "omarchy-brightness-display", `printf '%s\\n' "omarchy-brightness-display $*" >> "${log}"; echo 40`)
    // The real wl-gammarelay-rs is not on the test PATH, but the launchers are
    // stubbed anyway: a test must never start a daemon on the machine running
    // it. `rampCanStart` decides whether the stub brings the fake bus up.
    fakeCommand(dir, "wl-gammarelay-rs", "exit 0")
    fakeCommand(dir, "setsid", `printf '%s\\n' "setsid $*" >> "${log}"; ${rampCanStart ? `touch "${state}/up"` : "true"}`)
    fakeCommand(dir, "uwsm-app", `printf '%s\\n' "uwsm-app $*" >> "${log}"; ${rampCanStart ? `touch "${state}/up"` : "true"}`)

    return { dir, log, state, env: { XDG_RUNTIME_DIR: dir, OMARCHY_GAMMA_START_ATTEMPTS: "2" } }
  }

  const run = (m, args) => runScript("joamag.display", "display.sh", args, { bin: m.dir, env: m.env })
  const snap = (m) => Model.parseSnapshot(run(m, ["snapshot"]).stdout)
  const calls = (m) => fs.readFileSync(m.log, "utf8")

  it("reports every control in one snapshot", (t) => {
    const m = fakeMachine(t)
    const result = run(m, ["snapshot"])
    assert.equal(result.status, 0)
    const parsed = Model.parseSnapshot(result.stdout)
    assert.equal(parsed.monitor, "DP-1")
    assert.equal(parsed.bus, "7")
    assert.equal(parsed.brightness, 45)
    // 30 of a 60 maximum is half, not 30%.
    assert.equal(parsed.contrast, 50)
    assert.equal(parsed.gamma, 1)
    assert.equal(parsed.temperature, 6500)
    assert.equal(parsed.scale, "2")
    assert.equal(parsed.displays[0].name, "DP-1")
  })

  it("reads brightness and contrast in a single exchange", (t) => {
    const m = fakeMachine(t)
    run(m, ["snapshot"])
    const getvcp = calls(m).split("\n").filter((l) => l.includes("getvcp"))
    assert.equal(getvcp.length, 1)
    assert.match(getvcp[0], /getvcp 10 12/)
  })

  it("caches the bus so a refresh does not re-probe every i2c bus", (t) => {
    const m = fakeMachine(t)
    run(m, ["snapshot"])
    run(m, ["snapshot"])
    assert.equal(calls(m).split("\n").filter((l) => l.includes("detect")).length, 1)
  })

  it("falls back to the Omarchy helper when the monitor has no DDC/CI", (t) => {
    const m = fakeMachine(t, { ddc: false })
    const parsed = snap(m)
    assert.equal(parsed.bus, "")
    assert.equal(parsed.brightness, 40)
    assert.ok(Number.isNaN(parsed.contrast))
    assert.match(calls(m), /omarchy-brightness-display --monitor DP-1/)
  })

  it("leaves gamma and temperature out when the ramp daemon is down", (t) => {
    const m = fakeMachine(t, { ramp: false })
    const parsed = snap(m)
    assert.ok(Number.isNaN(parsed.gamma))
    assert.ok(Number.isNaN(parsed.temperature))
    assert.equal(parsed.brightness, 45)
  })

  it("revives the ramp daemon from a snapshot without waiting for it", (t) => {
    const m = fakeMachine(t, { ramp: false, rampCanStart: true })
    // The first snapshot only fires the daemon off, so it reports nothing;
    // the next one finds it on the bus.
    assert.ok(Number.isNaN(snap(m).gamma))
    assert.match(calls(m), /uwsm-app -- wl-gammarelay-rs/)
    assert.equal(snap(m).gamma, 1)
  })

  it("does not respawn the ramp daemon on every refresh", (t) => {
    const m = fakeMachine(t, { ramp: false })
    run(m, ["snapshot"])
    run(m, ["snapshot"])
    run(m, ["snapshot"])
    assert.equal(calls(m).split("\n").filter((l) => l.includes("wl-gammarelay-rs")).length, 1)
  })

  it("writes contrast against the monitor's own maximum", (t) => {
    const m = fakeMachine(t)
    const result = run(m, ["contrast", "DP-1", "50"])
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "")
    // 50% of a 60 maximum is 30, not 50.
    assert.match(calls(m), /setvcp 12 30/)
  })

  it("clamps a contrast above the range", (t) => {
    const m = fakeMachine(t)
    run(m, ["contrast", "DP-1", "400"])
    assert.match(calls(m), /setvcp 12 60/)
  })

  it("reports a monitor that cannot take contrast", (t) => {
    const m = fakeMachine(t, { ddc: false })
    const result = run(m, ["contrast", "DP-1", "50"])
    assert.equal(result.status, 0)
    assert.match(result.stdout, /^error\tDP-1 does not answer DDC\/CI/)
  })

  it("hands brightness to the Omarchy helper rather than writing VCP 0x10", (t) => {
    const m = fakeMachine(t)
    assert.equal(run(m, ["brightness", "DP-1", "70"]).status, 0)
    assert.match(calls(m), /omarchy-brightness-display --no-osd --monitor DP-1 70%/)
    assert.ok(!/setvcp 10/.test(calls(m)))
  })

  it("floors brightness at 1 so the screen never goes black", (t) => {
    const m = fakeMachine(t)
    run(m, ["brightness", "DP-1", "0"])
    assert.match(calls(m), /--monitor DP-1 1%/)
  })

  it("sets gamma as a decimal exponent and reads it back", (t) => {
    const m = fakeMachine(t)
    const result = run(m, ["gamma", "1.35"])
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "")
    assert.match(calls(m), /set-property rs.wl-gammarelay \/ rs.wl.gammarelay Gamma d 1.35/)
    assert.equal(snap(m).gamma, 1.35)
  })

  it("clamps gamma to the range the NVIDIA control panel uses", (t) => {
    const m = fakeMachine(t)
    run(m, ["gamma", "5.0"])
    assert.equal(snap(m).gamma, 2.8)
    run(m, ["gamma", "0.1"])
    assert.equal(snap(m).gamma, 0.3)
  })

  it("sets the colour temperature", (t) => {
    const m = fakeMachine(t)
    assert.equal(run(m, ["temperature", "4500"]).status, 0)
    assert.match(calls(m), /Temperature q 4500/)
    assert.equal(snap(m).temperature, 4500)
  })

  it("clamps the colour temperature to a sane range", (t) => {
    const m = fakeMachine(t)
    run(m, ["temperature", "99999"])
    assert.equal(snap(m).temperature, 10000)
    run(m, ["temperature", "10"])
    assert.equal(snap(m).temperature, 1000)
  })

  it("probes the ramp without touching i2c", (t) => {
    const m = fakeMachine(t)
    const parsed = Model.parseSnapshot(run(m, ["ramp"]).stdout)
    assert.equal(parsed.gamma, 1)
    assert.equal(parsed.temperature, 6500)
    // The whole point of the probe: it must be cheap enough to run on a timer
    // while the popup is closed, which means no exchange with the monitor.
    assert.ok(!/ddcutil/.test(calls(m)), calls(m))
  })

  it("says nothing at all when the ramp daemon is down, and starts none", (t) => {
    const m = fakeMachine(t, { ramp: false })
    const result = run(m, ["ramp"])
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "")
    assert.ok(!/wl-gammarelay-rs/.test(calls(m)))
  })

  it("restores both ramp values in one run", (t) => {
    const m = fakeMachine(t)
    assert.equal(run(m, ["restore", "1.35", "4200"]).stdout, "")
    const parsed = Model.parseSnapshot(run(m, ["ramp"]).stdout)
    assert.equal(parsed.gamma, 1.35)
    assert.equal(parsed.temperature, 4200)
  })

  it("clamps what it restores, and defaults to neutral", (t) => {
    const m = fakeMachine(t)
    run(m, ["restore", "9", "99999"])
    let parsed = Model.parseSnapshot(run(m, ["ramp"]).stdout)
    assert.equal(parsed.gamma, 2.8)
    assert.equal(parsed.temperature, 10000)
    run(m, ["restore"])
    parsed = Model.parseSnapshot(run(m, ["ramp"]).stdout)
    assert.equal(parsed.gamma, 1)
    assert.equal(parsed.temperature, 6500)
  })

  it("starts the ramp daemon when restoring onto a dead one", (t) => {
    const m = fakeMachine(t, { ramp: false, rampCanStart: true })
    assert.equal(run(m, ["restore", "1.4", "4000"]).stdout, "")
    const parsed = Model.parseSnapshot(run(m, ["ramp"]).stdout)
    assert.equal(parsed.gamma, 1.4)
    assert.equal(parsed.temperature, 4000)
  })

  it("reports a restore onto a daemon that will not come up", (t) => {
    const m = fakeMachine(t, { ramp: false })
    assert.match(run(m, ["restore", "1.4", "4000"]).stdout, /^error\twl-gammarelay-rs is not available/)
  })

  it("reports when the ramp daemon cannot be brought up", (t) => {
    const m = fakeMachine(t, { ramp: false })
    const result = run(m, ["gamma", "1.2"])
    assert.match(result.stdout, /^error\twl-gammarelay-rs is not available/)
    // It tried to start one rather than giving up without looking.
    assert.match(calls(m), /uwsm-app -- wl-gammarelay-rs/)
  })

  it("starts the ramp daemon on demand before setting gamma", (t) => {
    const m = fakeMachine(t, { ramp: false, rampCanStart: true })
    assert.equal(run(m, ["gamma", "1.5"]).stdout, "")
    assert.equal(snap(m).gamma, 1.5)
  })

  it("rejects a missing or non-numeric value", (t) => {
    const m = fakeMachine(t)
    assert.match(run(m, ["contrast", "DP-1", "abc"]).stdout, /^error\t/)
    assert.match(run(m, ["gamma", "abc"]).stdout, /^error\t/)
    assert.match(run(m, ["gamma"]).stdout, /^error\t/)
    assert.match(run(m, ["temperature", "1.5"]).stdout, /^error\t/)
  })

  it("rejects a bad invocation", (t) => {
    const m = fakeMachine(t)
    const result = run(m, ["bogus"])
    assert.equal(result.status, 1)
    assert.match(result.stderr, /Usage: display.sh/)
  })
})
