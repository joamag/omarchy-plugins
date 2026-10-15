// Tests for joamag.rgb: Model.js in declaration order, then rgb.sh.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { loadModel, fixturePath, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.rgb")

// The fixture the way rgb.sh turns it into lines: the NZXT hub, a GPU, two
// identical RAM sticks without a serial and a fan hub with effects only.
const RAW_OK = [
  "state\tok",
  "device\t0\tNZXT Smart Device V2\tLED Strip\t00000000001A\t[Direct] Fixed Fading Spectrum 'Cover Marquee' 'Super Rainbow'",
  "device\t1\tASUS ROG STRIX RTX 2060\tGPU\t\tDirect Off Static Breathing 'Spectrum Cycle' ['Chase Fade']",
  "device\t2\tCorsair Vengeance RGB\tDRAM\t\tDirect [Static] 'Color Shift'",
  "device\t3\tCorsair Vengeance RGB\tDRAM\t\tDirect [Static] 'Color Shift'",
  "device\t4\tRainbow Fan Hub\tCooler\t\t[Rainbow] 'Spectrum Cycle'",
  "",
].join("\n")
const ok = Model.parseSnapshot(RAW_OK)
const [nzxt, gpu, ram, ram2, fanHub] = ok.devices

const LIGHTS = {
  "NZXT Smart Device V2": { on: true, color: "FF0000", brightness: 80 },
  "ASUS ROG STRIX RTX 2060": { on: false, color: "0000FF", brightness: 50 },
}

// A graphics card and a board the way OpenRGB lists them: a card whose only
// solid mode is Direct, with two effects, and a board with nothing but Direct.
const [pny, board] = Model.parseSnapshot([
  "state\tok",
  "device\t0\tPNY GeForce RTX 2060 XLR8 OC EDITION\tGPU\t\t[Off] Direct Cycle Strobe",
  "device\t2\tMSI B450I GAMING PLUS AC (MS-7A40)\tMotherboard\t\t[Direct]",
  "",
].join("\n")).devices

describe("num", () => {
  it("parses numbers and numeric strings", () => {
    assert.equal(Model.num(42), 42)
    assert.equal(Model.num(" 7.5 "), 7.5)
  })

  it("rejects what Number() would quietly turn into a value", () => {
    assert.ok(Number.isNaN(Model.num(null)))
    assert.ok(Number.isNaN(Model.num("")))
    assert.ok(Number.isNaN(Model.num("   ")))
    assert.ok(Number.isNaN(Model.num(true)))
    assert.ok(Number.isNaN(Model.num([])))
    assert.ok(Number.isNaN(Model.num("abc")))
    assert.ok(Number.isNaN(Model.num(Infinity)))
  })
})

describe("parseSnapshot", () => {
  it("reads the state and one entry per device", () => {
    assert.equal(ok.state, "ok")
    assert.equal(ok.devices.length, 5)
    assert.deepEqual(nzxt, {
      index: 0,
      key: "NZXT Smart Device V2",
      name: "NZXT Smart Device V2",
      type: "LED Strip",
      serial: "00000000001A",
      modes: ["Direct", "Fixed", "Fading", "Spectrum", "Cover Marquee", "Super Rainbow"],
      activeMode: "Direct",
    })
    assert.equal(gpu.activeMode, "Chase Fade")
  })

  it("tells two devices with the same name apart by key", () => {
    assert.equal(ram.key, "Corsair Vengeance RGB")
    assert.equal(ram2.key, "Corsair Vengeance RGB #2")
    assert.equal(ram2.name, "Corsair Vengeance RGB")
    assert.equal(ram2.index, 3)
  })

  it("names a nameless device after its index and keeps a missing serial and mode list empty", () => {
    const parsed = Model.parseSnapshot("state\tok\ndevice\t7\t\tGPU\t\t\ndevice\t8\tBare\tLight\n")
    assert.equal(parsed.devices[0].name, "Device 7")
    assert.equal(parsed.devices[0].serial, "")
    assert.deepEqual(parsed.devices[0].modes, [])
    assert.equal(parsed.devices[1].name, "Bare")
    assert.equal(parsed.devices[1].serial, "")
    assert.deepEqual(parsed.devices[1].modes, [])
  })

  it("skips rows without a whole numeric index or too few fields", () => {
    const parsed = Model.parseSnapshot("state\tok\ndevice\t\tEmpty index\tGPU\t\tStatic\ndevice\tx1\tWord\tGPU\t\tStatic\ndevice\t-1\tNegative\tGPU\t\tStatic\ndevice\t1.5\tFraction\tGPU\t\tStatic\ndevice\t2\tShort\n")
    assert.deepEqual(parsed.devices, [])
  })

  it("keeps the error message, tabs included", () => {
    const parsed = Model.parseSnapshot("state\terror\nerror\tno\tserver\n")
    assert.equal(parsed.state, "error")
    assert.equal(parsed.error, "no\tserver")
  })

  it("falls back to an error with a message when nothing usable arrives", () => {
    assert.deepEqual(Model.parseSnapshot(""), { state: "error", error: "OpenRGB returned no data", devices: [] })
    assert.equal(Model.parseSnapshot(null).state, "error")
    assert.equal(Model.parseSnapshot("state\t").state, "error")
  })
})

describe("assignKeys", () => {
  const keyed = (devices) => Model.assignKeys(devices).map((d) => d.key)
  const hub = (serial) => ({ name: "Hub", serial })

  it("keys a device by its name alone while no other shares it, serial or not", () => {
    assert.equal(nzxt.key, "NZXT Smart Device V2")
    assert.deepEqual(keyed([hub("A1"), { name: "Board", serial: "" }]), ["Hub", "Board"])
  })

  it("tells same-name devices apart by serial, whatever order they are detected in", () => {
    assert.deepEqual(keyed([hub("A1"), hub("B2")]), ["Hub #A1", "Hub #B2"])
    assert.deepEqual(keyed([hub("B2"), hub("A1")]), ["Hub #B2", "Hub #A1"])
  })

  it("numbers same-name devices without a serial in the order they are listed", () => {
    assert.deepEqual(keyed([hub(""), hub(""), hub("")]), ["Hub", "Hub #2", "Hub #3"])
    assert.deepEqual(keyed([hub(""), hub("A1"), hub("")]), ["Hub", "Hub #A1", "Hub #2"])
  })

  it("never hands out one key twice, for a shared serial or one that reads like a place", () => {
    assert.deepEqual(keyed([hub("000"), hub("000")]), ["Hub #000", "Hub #000 #2"])
    assert.deepEqual(keyed([hub(""), hub("2"), hub("")]), ["Hub", "Hub #2", "Hub #2 #2"])
  })

  it("keys the devices in place and hands the list back", () => {
    const devices = [hub("")]
    assert.equal(Model.assignKeys(devices), devices)
    assert.deepEqual(Model.assignKeys([]), [])
  })
})

describe("parseModes", () => {
  it("splits plain and quoted names and finds the active one", () => {
    assert.deepEqual(Model.parseModes("[Direct] Fixed 'Cover Marquee'"), { names: ["Direct", "Fixed", "Cover Marquee"], active: "Direct" })
  })

  it("recognises a quoted name in brackets as the active one", () => {
    assert.deepEqual(Model.parseModes("Static ['Super Rainbow'] Off"), { names: ["Static", "Super Rainbow", "Off"], active: "Super Rainbow" })
  })

  it("leaves active empty when no mode is bracketed, or only half of one", () => {
    assert.equal(Model.parseModes("Direct Static").active, "")
    assert.equal(Model.parseModes("[Direct Static]").active, "")
    assert.deepEqual(Model.parseModes("[Direct Static]").names, ["Direct", "Static"])
  })

  it("ignores empty quotes, stray brackets and extra spaces", () => {
    assert.deepEqual(Model.parseModes("  ''  [ ]  Static   "), { names: ["Static"], active: "" })
    assert.deepEqual(Model.parseModes(""), { names: [], active: "" })
    assert.deepEqual(Model.parseModes(undefined), { names: [], active: "" })
  })
})

describe("findMode", () => {
  it("matches without regard to case and answers in the device's spelling", () => {
    assert.equal(Model.findMode(gpu, "OFF"), "Off")
    assert.equal(Model.findMode(nzxt, "cover marquee"), "Cover Marquee")
  })

  it("reads the modes of a device handed over by a Repeater, which are not an Array", () => {
    // What a QVariantList looks like from JavaScript: indexed, with a length,
    // but rejected by Array.isArray.
    const modes = { length: 3, 0: "Off", 1: "Direct", 2: "Cycle" }
    assert.equal(Array.isArray(modes), false)
    assert.equal(Model.findMode({ modes }, "direct"), "Direct")
    assert.equal(Model.isControllable({ modes }), true)
    assert.deepEqual(Model.applyArgs({ index: 0, modes }, { on: false }), ["set", "0", "Off"])
  })

  it("returns an empty string for a missing mode or device", () => {
    assert.equal(Model.findMode(nzxt, "off"), "")
    assert.equal(Model.findMode(nzxt, ""), "")
    assert.equal(Model.findMode(null, "static"), "")
    assert.equal(Model.findMode({ modes: "Static" }, "static"), "")
    assert.equal(Model.findMode({ modes: { 0: "Static" } }, "static"), "")
  })
})

describe("solidMode", () => {
  it("prefers Static, then Fixed, then Direct", () => {
    assert.equal(Model.solidMode(gpu), "Static")
    assert.equal(Model.solidMode(nzxt), "Fixed")
    assert.equal(Model.solidMode({ modes: ["Rainbow", "Direct"] }), "Direct")
  })

  it("returns an empty string for a device with effects only", () => {
    assert.equal(Model.solidMode(fanHub), "")
    assert.equal(Model.solidMode(null), "")
  })
})

describe("offMode", () => {
  it("finds the device's own Off mode", () => {
    assert.equal(Model.offMode(gpu), "Off")
    assert.equal(Model.offMode(nzxt), "")
  })
})

describe("isControllable", () => {
  it("needs a single-colour mode", () => {
    assert.equal(Model.isControllable(nzxt), true)
    assert.equal(Model.isControllable(fanHub), false)
    assert.equal(Model.isControllable(undefined), false)
  })
})

describe("effectModes", () => {
  it("lists every mode but the solid one, Off and Direct, in the device's order", () => {
    assert.deepEqual(Model.effectModes(nzxt), ["Fading", "Spectrum", "Cover Marquee", "Super Rainbow"])
    assert.deepEqual(Model.effectModes(gpu), ["Breathing", "Spectrum Cycle", "Chase Fade"])
    assert.deepEqual(Model.effectModes(ram), ["Color Shift"])
  })

  it("does not take a second single-colour mode for an animation", () => {
    assert.deepEqual(Model.effectModes({ modes: ["Static", "Fixed", "Breathing", "OFF"] }), ["Breathing"])
  })

  it("keeps the effects of a device whose solid mode is Direct", () => {
    assert.deepEqual(Model.effectModes(pny), ["Cycle", "Strobe"])
    assert.deepEqual(Model.effectModes(board), [])
  })

  it("offers nothing on a device that cannot be set", () => {
    assert.deepEqual(Model.effectModes(fanHub), [])
    assert.deepEqual(Model.effectModes(null), [])
  })

  it("reads the modes of a device handed over by a Repeater", () => {
    assert.deepEqual(Model.effectModes({ modes: { length: 3, 0: "Off", 1: "Direct", 2: "Cycle" } }), ["Cycle"])
  })
})

describe("activeEffect", () => {
  it("answers in the device's own spelling", () => {
    assert.equal(Model.activeEffect(gpu, { effect: "chase fade" }), "Chase Fade")
    assert.equal(Model.activeEffect(pny, { effect: "Strobe" }), "Strobe")
  })

  it("is the solid colour for no effect, one the device lacks, or a mode that is no effect", () => {
    assert.equal(Model.activeEffect(gpu, { effect: "" }), "")
    assert.equal(Model.activeEffect(gpu, { effect: "Wings" }), "")
    assert.equal(Model.activeEffect(gpu, { effect: "Static" }), "")
    assert.equal(Model.activeEffect(gpu, { effect: "off" }), "")
    assert.equal(Model.activeEffect(fanHub, { effect: "Rainbow" }), "")
    assert.equal(Model.activeEffect(gpu, null), "")
  })
})

describe("nextEffect", () => {
  it("steps through the effects with the solid colour first in the ring", () => {
    assert.equal(Model.nextEffect(gpu, { effect: "" }, 1), "Breathing")
    assert.equal(Model.nextEffect(gpu, { effect: "Breathing" }, 1), "Spectrum Cycle")
    assert.equal(Model.nextEffect(gpu, { effect: "Chase Fade" }, 1), "")
    assert.equal(Model.nextEffect(gpu, { effect: "" }, -1), "Chase Fade")
    assert.equal(Model.nextEffect(gpu, { effect: "" }, 6), "Spectrum Cycle")
  })

  it("starts from the solid colour when the remembered effect is not offered", () => {
    assert.equal(Model.nextEffect(gpu, { effect: "Wings" }, 1), "Breathing")
  })

  it("stays put for a step that is not a number, and on a device without effects", () => {
    assert.equal(Model.nextEffect(gpu, { effect: "Breathing" }, "x"), "Breathing")
    assert.equal(Model.nextEffect(gpu, { effect: "Breathing" }, Infinity), "Breathing")
    assert.equal(Model.nextEffect(gpu, { effect: "Breathing" }, undefined), "Breathing")
    assert.equal(Model.nextEffect(board, { effect: "" }, 1), "")
  })
})

describe("effectLabel", () => {
  it("names the solid colour", () => {
    assert.equal(Model.effectLabel(""), "Solid")
    assert.equal(Model.effectLabel(undefined), "Solid")
    assert.equal(Model.effectLabel("Spectrum Cycle"), "Spectrum Cycle")
  })
})

describe("normalizeColor", () => {
  it("reads hex with or without a hash, short or long, as six upper-case digits", () => {
    assert.equal(Model.normalizeColor("#ff8000"), "FF8000")
    assert.equal(Model.normalizeColor("ff8000"), "FF8000")
    assert.equal(Model.normalizeColor(" #F80 "), "FF8800")
    assert.equal(Model.normalizeColor("0a0B0c"), "0A0B0C")
  })

  it("rejects anything else", () => {
    for (const bad of ["", "#", "ff800", "ff80000", "gg0000", "#ff 800", "red", "##ff8000", null, undefined, 16711680]) {
      assert.equal(Model.normalizeColor(bad), "", String(bad))
    }
  })
})

describe("clampBrightness", () => {
  it("rounds into the 5..100 range", () => {
    assert.equal(Model.clampBrightness(42.4), 42)
    assert.equal(Model.clampBrightness("80"), 80)
    assert.equal(Model.clampBrightness(0), Model.MIN_BRIGHTNESS)
    assert.equal(Model.clampBrightness(-20), Model.MIN_BRIGHTNESS)
    assert.equal(Model.clampBrightness(250), Model.MAX_BRIGHTNESS)
  })

  it("reads anything that is not a number as full brightness, a boolean included", () => {
    assert.equal(Model.clampBrightness(undefined), 100)
    assert.equal(Model.clampBrightness(null), 100)
    assert.equal(Model.clampBrightness(""), 100)
    assert.equal(Model.clampBrightness("dim"), 100)
    assert.equal(Model.clampBrightness(true), 100)
  })
})

describe("clampSpeed", () => {
  it("rounds into the 0..100 range, zero included", () => {
    assert.equal(Model.clampSpeed(0), 0)
    assert.equal(Model.clampSpeed("0"), 0)
    assert.equal(Model.clampSpeed(62.5), 63)
    assert.equal(Model.clampSpeed(-1), 0)
    assert.equal(Model.clampSpeed(180), 100)
  })

  it("reads anything that is not a number as the middle of the range", () => {
    assert.equal(Model.clampSpeed(undefined), Model.DEFAULT_SPEED)
    assert.equal(Model.clampSpeed("fast"), 50)
    assert.equal(Model.clampSpeed(true), 50)
  })
})

describe("scaleColor", () => {
  it("keeps the colour at full brightness", () => {
    assert.equal(Model.scaleColor("FF8000", 100), "FF8000")
  })

  it("scales every channel and pads the small ones", () => {
    assert.equal(Model.scaleColor("FF8000", 50), "804000")
    assert.equal(Model.scaleColor("FFFFFF", 5), "0D0D0D")
    assert.equal(Model.scaleColor("#1e1e1e", 50), "0F0F0F")
  })

  it("never scales below the minimum brightness, nor scales a bad colour to black", () => {
    assert.equal(Model.scaleColor("FF0000", 0), Model.scaleColor("FF0000", Model.MIN_BRIGHTNESS))
    assert.equal(Model.scaleColor("nonsense", 100), Model.DEFAULT_COLOR)
  })
})

describe("swatchIndex", () => {
  it("finds a swatch however the colour is written", () => {
    assert.equal(Model.swatchIndex("FFFFFF"), 0)
    assert.equal(Model.swatchIndex("#f00"), 1)
    assert.equal(Model.swatchIndex("123456"), -1)
    assert.equal(Model.swatchIndex(""), -1)
  })
})

describe("colorName", () => {
  it("names a swatch, shows the hex of any other colour, and nothing for no colour", () => {
    assert.equal(Model.colorName("0000ff"), "Blue")
    assert.equal(Model.colorName("123456"), "#123456")
    assert.equal(Model.colorName("bogus"), "")
  })
})

describe("lightState", () => {
  it("fills in what is remembered", () => {
    assert.deepEqual(Model.lightState(LIGHTS, "NZXT Smart Device V2"), { known: true, on: true, color: "FF0000", brightness: 80, effect: "", speed: 50 })
    assert.deepEqual(Model.lightState(LIGHTS, "ASUS ROG STRIX RTX 2060"), { known: true, on: false, color: "0000FF", brightness: 50, effect: "", speed: 50 })
    assert.deepEqual(Model.lightState({ x: { effect: "Breathing", speed: 75 } }, "x"), { known: true, on: true, color: "FFFFFF", brightness: 100, effect: "Breathing", speed: 75 })
  })

  it("is unknown, on and white at full brightness for a device never set", () => {
    const unknown = { known: false, on: true, color: "FFFFFF", brightness: 100, effect: "", speed: 50 }
    assert.deepEqual(Model.lightState(LIGHTS, "Rainbow Fan Hub"), unknown)
    assert.deepEqual(Model.lightState(null, "x"), unknown)
    assert.deepEqual(Model.lightState({ x: "on" }, "x"), unknown)
    assert.deepEqual(Model.lightState({ x: null }, "x"), unknown)
  })

  it("does not take inherited properties for remembered devices", () => {
    assert.equal(Model.lightState({}, "constructor").known, false)
    assert.equal(Model.lightState({}, "toString").known, false)
  })

  it("repairs a hand edit gone wrong field by field", () => {
    assert.deepEqual(Model.lightState({ x: { on: "false", color: "#0f0", brightness: "300", effect: " Candle ", speed: "-3" } }, "x"), { known: true, on: false, color: "00FF00", brightness: 100, effect: "Candle", speed: 0 })
    assert.deepEqual(Model.lightState({ x: {} }, "x"), { known: true, on: true, color: "FFFFFF", brightness: 100, effect: "", speed: 50 })
    assert.equal(Model.lightState({ x: { color: "red" } }, "x").color, "FFFFFF")
    assert.equal(Model.lightState({ x: { effect: 7 } }, "x").effect, "")
    assert.equal(Model.lightState({ x: { speed: "fast" } }, "x").speed, 50)
  })
})

describe("setLight", () => {
  it("changes one device and carries the others over", () => {
    const next = Model.setLight(LIGHTS, "NZXT Smart Device V2", { color: "#00ff00" })
    assert.deepEqual(next["NZXT Smart Device V2"], { on: true, color: "00FF00", brightness: 80, effect: "", speed: 50 })
    assert.deepEqual(next["ASUS ROG STRIX RTX 2060"], LIGHTS["ASUS ROG STRIX RTX 2060"])
  })

  it("leaves the object it was given untouched", () => {
    const before = JSON.stringify(LIGHTS)
    Model.setLight(LIGHTS, "NZXT Smart Device V2", { on: false })
    assert.equal(JSON.stringify(LIGHTS), before)
  })

  it("starts a new device from the defaults", () => {
    assert.deepEqual(Model.setLight({}, "new", { brightness: 30 }).new, { on: true, color: "FFFFFF", brightness: 30, effect: "", speed: 50 })
    assert.deepEqual(Model.setLight(null, "new").new, { on: true, color: "FFFFFF", brightness: 100, effect: "", speed: 50 })
  })

  it("keeps the current colour when the new one is not a colour, and clamps the brightness", () => {
    const next = Model.setLight(LIGHTS, "NZXT Smart Device V2", { color: "nope", brightness: 0 })
    assert.deepEqual(next["NZXT Smart Device V2"], { on: true, color: "FF0000", brightness: 5, effect: "", speed: 50 })
  })

  it("sets an effect and its speed, and a blank effect goes back to the solid colour", () => {
    const running = Model.setLight({}, "x", { effect: " Breathing ", speed: 120 })
    assert.deepEqual(running.x, { on: true, color: "FFFFFF", brightness: 100, effect: "Breathing", speed: 100 })
    const solid = Model.setLight(running, "x", { effect: "" })
    assert.equal(solid.x.effect, "")
    assert.equal(solid.x.speed, 100)
    assert.equal(Model.setLight(running, "x", { effect: null }).x.effect, "")
    assert.equal(Model.setLight(running, "x", { color: "FF0000" }).x.effect, "Breathing")
  })

  it("switches off for anything but a true on", () => {
    assert.equal(Model.setLight({}, "x", { on: false }).x.on, false)
    assert.equal(Model.setLight({}, "x", { on: "true" }).x.on, false)
    assert.equal(Model.setLight({ x: { on: false } }, "x", { on: true }).x.on, true)
  })

  it("does not copy a list in as remembered devices", () => {
    assert.deepEqual(Object.keys(Model.setLight(["stray"], "x", {})), ["x"])
  })
})

describe("applyArgs", () => {
  it("paints a lit device in its solid mode with the colour scaled", () => {
    assert.deepEqual(Model.applyArgs(nzxt, Model.lightState(LIGHTS, nzxt.key)), ["set", "0", "Fixed", "CC0000"])
  })

  it("switches off through the device's Off mode when it has one", () => {
    assert.deepEqual(Model.applyArgs(gpu, Model.lightState(LIGHTS, gpu.key)), ["set", "1", "Off"])
  })

  it("paints black in the solid mode when there is no Off mode", () => {
    assert.deepEqual(Model.applyArgs(ram2, { on: false, color: "FF0000", brightness: 100 }), ["set", "3", "Static", "000000"])
  })

  it("defaults to white at full brightness without a state", () => {
    assert.deepEqual(Model.applyArgs(ram, null), ["set", "2", "Static", "FFFFFF"])
  })

  it("runs an effect with the colour scaled and its speed", () => {
    const state = Model.lightState({ x: { color: "FF0000", brightness: 50, effect: "breathing", speed: 75 } }, "x")
    assert.deepEqual(Model.applyArgs(gpu, state), ["set", "1", "Breathing", "800000", "75"])
    assert.deepEqual(Model.applyArgs(pny, Model.lightState({ x: { effect: "Cycle", speed: 0 } }, "x")), ["set", "0", "Cycle", "FFFFFF", "0"])
  })

  it("clamps a speed handed over unchecked, and falls back to the solid colour for an effect not offered", () => {
    assert.deepEqual(Model.applyArgs(gpu, { on: true, color: "FFFFFF", brightness: 100, effect: "Breathing", speed: 500 }), ["set", "1", "Breathing", "FFFFFF", "100"])
    assert.deepEqual(Model.applyArgs(gpu, { on: true, color: "FFFFFF", brightness: 100, effect: "Breathing" }), ["set", "1", "Breathing", "FFFFFF", "50"])
    assert.deepEqual(Model.applyArgs(gpu, { on: true, color: "FFFFFF", brightness: 100, effect: "Wings", speed: 20 }), ["set", "1", "Static", "FFFFFF"])
  })

  it("switches off the same way while an effect is remembered", () => {
    assert.deepEqual(Model.applyArgs(gpu, { on: false, color: "FFFFFF", brightness: 100, effect: "Breathing", speed: 20 }), ["set", "1", "Off"])
  })

  it("has nothing to send to a device it cannot set", () => {
    assert.deepEqual(Model.applyArgs(fanHub, Model.lightState(null, fanHub.key)), [])
    assert.deepEqual(Model.applyArgs(null, null), [])
  })
})

describe("actionError", () => {
  it("returns the message of the first error line", () => {
    assert.equal(Model.actionError("error\tMode 'x' not available\nerror\tsecond\n"), "Mode 'x' not available")
    assert.equal(Model.actionError("error\ta\tb"), "a\tb")
  })

  it("names a failure that came without a message", () => {
    assert.equal(Model.actionError("error\t\n"), "OpenRGB failed")
  })

  it("is empty for a run that succeeded", () => {
    assert.equal(Model.actionError(""), "")
    assert.equal(Model.actionError(undefined), "")
    assert.equal(Model.actionError("Connected to local OpenRGB server.\n"), "")
  })
})

describe("visibleDevices", () => {
  it("lists every device without a filter", () => {
    assert.equal(Model.visibleDevices(ok, "").length, 5)
    assert.equal(Model.visibleDevices(ok, " , ,").length, 5)
  })

  it("matches part of a name or a whole type, without regard to case", () => {
    assert.deepEqual(Model.visibleDevices(ok, "nzxt, GPU").map((d) => d.key), ["NZXT Smart Device V2", "ASUS ROG STRIX RTX 2060"])
    assert.deepEqual(Model.visibleDevices(ok, "dram").map((d) => d.key), ["Corsair Vengeance RGB", "Corsair Vengeance RGB #2"])
  })

  it("does not take part of a type for the whole of it", () => {
    assert.deepEqual(Model.visibleDevices(ok, "led").map((d) => d.key), [])
    assert.deepEqual(Model.visibleDevices(ok, "led strip").map((d) => d.key), ["NZXT Smart Device V2"])
  })

  it("is empty without a snapshot", () => {
    assert.deepEqual(Model.visibleDevices(null, ""), [])
    assert.deepEqual(Model.visibleDevices({ devices: "x" }, "gpu"), [])
  })
})

describe("pendingRestore", () => {
  it("lists remembered devices that can be set and have not been restored", () => {
    assert.deepEqual(Model.pendingRestore(ok.devices, LIGHTS, {}).map((d) => d.key), ["NZXT Smart Device V2", "ASUS ROG STRIX RTX 2060"])
    assert.deepEqual(Model.pendingRestore(ok.devices, LIGHTS, { "NZXT Smart Device V2": true }).map((d) => d.key), ["ASUS ROG STRIX RTX 2060"])
  })

  it("skips a remembered device that cannot be set", () => {
    assert.deepEqual(Model.pendingRestore([fanHub], { "Rainbow Fan Hub": { on: true } }, null), [])
  })

  it("is empty without devices or memories", () => {
    assert.deepEqual(Model.pendingRestore(ok.devices, {}, {}), [])
    assert.deepEqual(Model.pendingRestore(null, LIGHTS, {}), [])
  })
})

describe("awaitingRestore", () => {
  const both = { "NZXT Smart Device V2": true, "ASUS ROG STRIX RTX 2060": true }

  it("waits for a remembered device that has not had its state back", () => {
    assert.equal(Model.awaitingRestore(ok, "", LIGHTS, {}), true)
    assert.equal(Model.awaitingRestore(ok, "", LIGHTS, { "NZXT Smart Device V2": true }), true)
    assert.equal(Model.awaitingRestore(ok, "", LIGHTS, both), false)
  })

  it("waits for one the snapshot does not list yet, or a failed or missing snapshot", () => {
    const gone = { "Lian Li Strip": { on: true } }
    assert.equal(Model.awaitingRestore(ok, "", gone, both), true)
    assert.equal(Model.awaitingRestore(Model.parseSnapshot("state\terror\nerror\tboom"), "", LIGHTS, {}), true)
    assert.equal(Model.awaitingRestore(null, "", LIGHTS, {}), true)
  })

  it("does not wait for one the devices setting hides or that cannot take a state", () => {
    assert.equal(Model.awaitingRestore(ok, "gpu", LIGHTS, { "ASUS ROG STRIX RTX 2060": true }), false)
    assert.equal(Model.awaitingRestore(ok, "", { "Rainbow Fan Hub": { on: true } }, {}), false)
  })

  it("has nothing to wait for without memories, or with entries that are not states", () => {
    assert.equal(Model.awaitingRestore(ok, "", {}, {}), false)
    assert.equal(Model.awaitingRestore(ok, "", null, {}), false)
    assert.equal(Model.awaitingRestore(ok, "", { "Lian Li Strip": "on" }, {}), false)
    assert.equal(Model.awaitingRestore(ok, "", Object.create({ inherited: { on: true } }), {}), false)
  })
})

describe("pruneRestored", () => {
  it("keeps the marks of devices a good snapshot still lists", () => {
    assert.deepEqual(Model.pruneRestored({ "NZXT Smart Device V2": true, "Lian Li Strip": true }, ok), { "NZXT Smart Device V2": true })
  })

  it("keeps every mark when the snapshot failed or is missing", () => {
    const done = { "NZXT Smart Device V2": true, "Lian Li Strip": true }
    assert.deepEqual(Model.pruneRestored(done, Model.parseSnapshot("state\terror")), done)
    assert.deepEqual(Model.pruneRestored(done, null), done)
  })

  it("drops marks that are not set, and leaves the marks it was given untouched", () => {
    const done = { "NZXT Smart Device V2": true, "ASUS ROG STRIX RTX 2060": false }
    assert.deepEqual(Model.pruneRestored(done, ok), { "NZXT Smart Device V2": true })
    assert.deepEqual(done, { "NZXT Smart Device V2": true, "ASUS ROG STRIX RTX 2060": false })
    assert.deepEqual(Model.pruneRestored(null, ok), {})
  })
})

describe("forgetRestored", () => {
  it("drops one device's mark and keeps the rest", () => {
    assert.deepEqual(Model.forgetRestored({ a: true, b: true }, "a"), { b: true })
    assert.deepEqual(Model.forgetRestored({ a: true, b: false }, "c"), { a: true })
  })

  it("is empty for no marks, and copies rather than changes what it was given", () => {
    const done = { a: true }
    Model.forgetRestored(done, "a")
    assert.deepEqual(done, { a: true })
    assert.deepEqual(Model.forgetRestored(undefined, "a"), {})
  })
})

describe("litCount", () => {
  it("counts devices that can be set and are on, a device never set counting as on", () => {
    assert.equal(Model.litCount(ok.devices, LIGHTS), 3)
    assert.equal(Model.litCount([gpu], LIGHTS), 0)
    assert.equal(Model.litCount([fanHub], {}), 0)
    assert.equal(Model.litCount(undefined, LIGHTS), 0)
  })
})

describe("requestedPower", () => {
  it("says on or off as asked, and flips what is lit for a toggle", () => {
    assert.equal(Model.requestedPower("on", true), true)
    assert.equal(Model.requestedPower("off", false), false)
    assert.equal(Model.requestedPower("toggle", true), false)
    assert.equal(Model.requestedPower("toggle", false), true)
  })

  it("is null when nothing was asked", () => {
    assert.equal(Model.requestedPower("", true), null)
    assert.equal(Model.requestedPower(undefined, false), null)
    assert.equal(Model.requestedPower("dim", true), null)
  })
})

describe("typeIcon", () => {
  it("maps known types without regard to case and falls back to a bulb", () => {
    assert.equal(Model.typeIcon(gpu), Model.TYPE_ICONS.gpu)
    assert.equal(Model.typeIcon(nzxt), Model.TYPE_ICONS["led strip"])
    assert.equal(Model.typeIcon(ram), Model.DEFAULT_TYPE_ICON)
    assert.equal(Model.typeIcon(null), Model.DEFAULT_TYPE_ICON)
  })
})

describe("isOk", () => {
  it("requires the ok state", () => {
    assert.equal(Model.isOk(ok), true)
    assert.equal(Model.isOk(Model.parseSnapshot("state\tmissing")), false)
    assert.equal(Model.isOk(null), false)
  })
})

describe("stateTitle", () => {
  it("names every state", () => {
    assert.equal(Model.stateTitle({ state: "missing" }), "OpenRGB is not installed")
    assert.equal(Model.stateTitle({ state: "error" }), "OpenRGB error")
    assert.equal(Model.stateTitle({ state: "ok" }), "No lighting found")
    assert.equal(Model.stateTitle(null), "Looking for lighting")
  })
})

describe("stateDetail", () => {
  it("explains how to install and echoes error text", () => {
    assert.match(Model.stateDetail({ state: "missing" }, ""), /systemctl enable --now openrgb/)
    assert.equal(Model.stateDetail({ state: "error", error: "boom" }, ""), "boom")
    assert.equal(Model.stateDetail({ state: "error" }, ""), "")
    assert.equal(Model.stateDetail(null, ""), "")
  })

  it("blames the filter when devices exist but none matches it", () => {
    assert.equal(Model.stateDetail(ok, " keyboard "), "None of the 5 devices OpenRGB found match \"keyboard\".")
  })

  it("points at access when OpenRGB found nothing at all", () => {
    assert.match(Model.stateDetail(Model.parseSnapshot("state\tok\n"), "gpu"), /udev rules/)
    assert.match(Model.stateDetail(Model.parseSnapshot("state\tok\n"), undefined), /udev rules/)
  })

  it("has nothing to explain when devices were found and no filter hides them", () => {
    assert.equal(Model.stateDetail(ok, "  "), "")
    assert.equal(Model.stateDetail(ok, undefined), "")
  })
})

describe("deviceDetail", () => {
  it("shows the colour and brightness of a lit device", () => {
    assert.equal(Model.deviceDetail(nzxt, Model.lightState(LIGHTS, nzxt.key)), "Red · 80%")
    assert.equal(Model.deviceDetail(nzxt, { known: true, on: true, color: "123456", brightness: 40 }), "#123456 · 40%")
  })

  it("puts the running effect in front, unless the device does not offer it", () => {
    assert.equal(Model.deviceDetail(nzxt, { known: true, on: true, color: "FF0000", brightness: 80, effect: "cover marquee" }), "Cover Marquee · Red · 80%")
    assert.equal(Model.deviceDetail(nzxt, { known: true, on: true, color: "FF0000", brightness: 80, effect: "Wings" }), "Red · 80%")
  })

  it("says off, never set, or why it cannot be set", () => {
    assert.equal(Model.deviceDetail(gpu, Model.lightState(LIGHTS, gpu.key)), "Off")
    assert.equal(Model.deviceDetail(ram, Model.lightState(LIGHTS, ram.key)), "Not set from here yet")
    assert.equal(Model.deviceDetail(ram, null), "Not set from here yet")
    assert.equal(Model.deviceDetail(fanHub, Model.lightState(null, fanHub.key)), "No single-colour mode in OpenRGB")
  })
})

describe("heroStatus", () => {
  it("summarises lit devices or the failing state", () => {
    assert.equal(Model.heroStatus(null, [], {}), "LOOKING FOR DEVICES")
    assert.equal(Model.heroStatus(Model.parseSnapshot("state\tmissing"), [], {}), "MISSING")
    assert.equal(Model.heroStatus(ok, [], {}), "NO DEVICES")
    assert.equal(Model.heroStatus(ok, null, {}), "NO DEVICES")
    assert.equal(Model.heroStatus(ok, [gpu], LIGHTS), "ALL OFF")
    assert.equal(Model.heroStatus(ok, [nzxt], LIGHTS), "1 ON · 1 DEVICE")
    assert.equal(Model.heroStatus(ok, [nzxt, gpu], LIGHTS), "1 ON · 2 DEVICES")
  })
})

describe("tooltip", () => {
  it("describes every device or the failing state", () => {
    assert.equal(Model.tooltip(null, [], {}), "RGB")
    assert.equal(Model.tooltip(Model.parseSnapshot("state\tmissing"), [], {}), "OpenRGB is not installed")
    assert.equal(Model.tooltip(ok, [], {}), "RGB · no devices")
    assert.equal(Model.tooltip(ok, undefined, {}), "RGB · no devices")
    assert.equal(
      Model.tooltip(ok, [nzxt, gpu, ram, fanHub], LIGHTS),
      "RGB · NZXT Smart Device V2 red 80% · ASUS ROG STRIX RTX 2060 off · Corsair Vengeance RGB not set · Rainbow Fan Hub not settable",
    )
  })

  it("names the effect a lit device runs", () => {
    assert.equal(Model.tooltip(ok, [nzxt], { "NZXT Smart Device V2": { color: "0000FF", brightness: 60, effect: "Fading" } }), "RGB · NZXT Smart Device V2 fading blue 60%")
  })
})

describe("rgb.sh", () => {
  // A stand-in for openrgb that logs its arguments and answers --list-devices
  // with the fixture; FAKE_OPENRGB_OUTPUT and FAKE_OPENRGB_STATUS replace what
  // it prints and how it exits.
  function fakes(t) {
    const dir = tmpdir(t)
    fakeCommand(dir, "openrgb", `
printf '%s\\n' "$*" >> "$FAKE_LOG"
if [[ -n \${FAKE_OPENRGB_OUTPUT+x} ]]; then
  printf '%s\\n' "$FAKE_OPENRGB_OUTPUT"
elif [[ $1 == --list-devices ]]; then
  cat "${fixturePath("openrgb-list-devices.txt")}"
fi
exit "\${FAKE_OPENRGB_STATUS:-0}"`)
    const env = { FAKE_LOG: path.join(dir, "openrgb.log") }
    return { dir, env, log: () => (fs.existsSync(env.FAKE_LOG) ? fs.readFileSync(env.FAKE_LOG, "utf8").trim().split("\n") : []) }
  }

  it("reports missing when openrgb is not installed", (t) => {
    const bin = tmpdir(t)
    const result = runScript("joamag.rgb", "rgb.sh", [], { path: bin })
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "state\tmissing\n")
  })

  it("lists every device OpenRGB prints, skipping what it says about its server", (t) => {
    const f = fakes(t)
    const result = runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: f.env })
    assert.equal(result.status, 0)
    assert.deepEqual(f.log(), ["--list-devices"])
    const parsed = Model.parseSnapshot(result.stdout)
    assert.equal(parsed.state, "ok")
    assert.deepEqual(parsed.devices.map((d) => [d.index, d.key, d.type]), [
      [0, "NZXT Smart Device V2", "LED Strip"],
      [1, "ASUS ROG STRIX RTX 2060", "GPU"],
      [2, "Corsair Vengeance RGB", "DRAM"],
      [3, "Corsair Vengeance RGB #2", "DRAM"],
      [4, "Rainbow Fan Hub", "Cooler"],
    ])
    assert.equal(parsed.devices[0].modes.length, 14)
    assert.equal(parsed.devices[0].activeMode, "Direct")
    assert.deepEqual(parsed.devices[0].modes.slice(4, 6), ["Marquee", "Cover Marquee"])
    assert.equal(parsed.devices[1].activeMode, "Chase Fade")
    assert.equal(Model.solidMode(parsed.devices[4]), "")
  })

  it("keeps each device's serial, an empty one padded with spaces read as none", (t) => {
    const f = fakes(t)
    const parsed = Model.parseSnapshot(runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: f.env }).stdout)
    assert.deepEqual(parsed.devices.map((d) => d.serial), ["00000000001A", "", "", "", ""])
  })

  it("asks for the detailed list when a newer OpenRGB lists the names alone", (t) => {
    const f = fakes(t)
    fakeCommand(f.dir, "openrgb", `
printf '%s\\n' "$*" >> "$FAKE_LOG"
case "$1" in
  --list-devices) printf 'Connected to server\\n0: NZXT Smart Device V2\\n1: ASUS ROG STRIX RTX 2060\\n' ;;
  --list-detailed) cat "${fixturePath("openrgb-list-devices.txt")}" ;;
esac`)
    const parsed = Model.parseSnapshot(runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: f.env }).stdout)
    assert.deepEqual(f.log(), ["--list-devices", "--list-detailed"])
    assert.equal(parsed.state, "ok")
    assert.equal(parsed.devices.length, 5)
    assert.equal(Model.solidMode(parsed.devices[0]), "Fixed")
  })

  it("reports the detailed list failing, and does not ask for it when nothing is listed", (t) => {
    const f = fakes(t)
    fakeCommand(f.dir, "openrgb", `
printf '%s\\n' "$*" >> "$FAKE_LOG"
case "$1" in
  --list-devices) printf '0: NZXT Smart Device V2\\n' ;;
  --list-detailed) echo "Error: Invalid option: --list-detailed"; exit 255 ;;
esac`)
    const failed = Model.parseSnapshot(runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: f.env }).stdout)
    assert.equal(failed.state, "error")
    assert.equal(failed.error, "Invalid option: --list-detailed")
    fakeCommand(f.dir, "openrgb", `printf '%s\\n' "$*" >> "$FAKE_LOG"; echo "Running standalone."`)
    assert.equal(runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: f.env }).stdout, "state\tok\n")
    assert.deepEqual(f.log(), ["--list-devices", "--list-detailed", "--list-devices"])
  })

  it("lists nothing when OpenRGB found no device", (t) => {
    const f = fakes(t)
    const result = runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: "Attempting to connect to local OpenRGB server.\nRunning standalone." } })
    assert.equal(result.stdout, "state\tok\n")
  })

  it("keeps a device whose block has no type or modes, and turns tabs in a name into spaces", (t) => {
    const f = fakes(t)
    const result = runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: "0: Odd\tname\n  Location:       HID: /dev/hidraw3\n1: Next\n  Type:           GPU\n  Modes: Static" } })
    assert.equal(result.stdout, "state\tok\ndevice\t0\tOdd name\t\t\t\ndevice\t1\tNext\tGPU\t\tStatic\n")
  })

  it("reports an error OpenRGB prints even when it exits 0", (t) => {
    const f = fakes(t)
    const result = runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: "Error: Unable to open\tdevice\nError: second" } })
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "state\terror\nerror\tUnable to open device\n")
  })

  it("reports a failure without words by its exit status, and a timeout by name", (t) => {
    const f = fakes(t)
    const failed = Model.parseSnapshot(runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: "", FAKE_OPENRGB_STATUS: "3" } }).stdout)
    assert.equal(failed.state, "error")
    assert.equal(failed.error, "openrgb exited 3")
    const slow = Model.parseSnapshot(runScript("joamag.rgb", "rgb.sh", [], { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: "", FAKE_OPENRGB_STATUS: "124" } }).stdout)
    assert.equal(slow.error, "OpenRGB took too long to answer")
  })

  it("sets a device's mode and colour", (t) => {
    const f = fakes(t)
    const result = runScript("joamag.rgb", "rgb.sh", ["set", "1", "Static", "ff8000"], { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: "Connected to local OpenRGB server." } })
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "")
    assert.deepEqual(f.log(), ["--device 1 --mode Static --color ff8000"])
  })

  it("passes an effect's speed, leading zeros dropped, with or without a colour", (t) => {
    const f = fakes(t)
    const env = { ...f.env, FAKE_OPENRGB_OUTPUT: "" }
    assert.equal(runScript("joamag.rgb", "rgb.sh", ["set", "1", "Breathing", "FF0000", "75"], { bin: f.dir, env }).stdout, "")
    assert.equal(runScript("joamag.rgb", "rgb.sh", ["set", "1", "Breathing", "FF0000", "008"], { bin: f.dir, env }).stdout, "")
    assert.equal(runScript("joamag.rgb", "rgb.sh", ["set", "1", "Spectrum Cycle", "", "100"], { bin: f.dir, env }).stdout, "")
    assert.deepEqual(f.log(), [
      "--device 1 --mode Breathing --color FF0000 --speed 75",
      "--device 1 --mode Breathing --color FF0000 --speed 8",
      "--device 1 --mode Spectrum Cycle --speed 100",
    ])
  })

  it("takes the arguments the model builds, the Off mode with no colour", (t) => {
    const f = fakes(t)
    const breathing = Model.lightState({ x: { color: "00FF00", effect: "Breathing", speed: 25 } }, "x")
    for (const args of [Model.applyArgs(nzxt, Model.lightState(LIGHTS, nzxt.key)), Model.applyArgs(gpu, Model.lightState(LIGHTS, gpu.key)), Model.applyArgs(gpu, breathing)]) {
      assert.equal(runScript("joamag.rgb", "rgb.sh", args, { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: "" } }).stdout, "")
    }
    assert.deepEqual(f.log(), ["--device 0 --mode Fixed --color CC0000", "--device 1 --mode Off", "--device 1 --mode Breathing --color 00FF00 --speed 25"])
  })

  it("passes a mode with a space in it as one argument", (t) => {
    const dir = tmpdir(t)
    const log = path.join(dir, "openrgb.log")
    fakeCommand(dir, "openrgb", `printf '%s|%s\\n' "$#" "$4" >> "$FAKE_LOG"`)
    runScript("joamag.rgb", "rgb.sh", ["set", "0", "Cover Marquee", "00FF00"], { bin: dir, env: { FAKE_LOG: log } })
    assert.equal(fs.readFileSync(log, "utf8"), "6|Cover Marquee\n")
  })

  it("refuses bad arguments without running openrgb", (t) => {
    const f = fakes(t)
    const cases = [
      [["set"], "device index required"],
      [["set", "one", "Static"], "device index required"],
      [["set", "-1", "Static"], "device index required"],
      [["set", "1"], "mode required"],
      [["set", "1", ""], "mode required"],
      [["set", "1", "Static", "#ff8000"], "colour must be six hex digits"],
      [["set", "1", "Static", "red"], "colour must be six hex digits"],
      [["set", "1", "Breathing", "FF0000", "101"], "speed must be 0 to 100"],
      [["set", "1", "Breathing", "FF0000", "0100"], "speed must be 0 to 100"],
      [["set", "1", "Breathing", "FF0000", "-1"], "speed must be 0 to 100"],
      [["set", "1", "Breathing", "FF0000", "1.5"], "speed must be 0 to 100"],
      [["set", "1", "Breathing", "FF0000", "fast"], "speed must be 0 to 100"],
      [["set", "1", "Breathing", "FF0000", "18446744073709551716"], "speed must be 0 to 100"],
    ]
    for (const [args, message] of cases) {
      const result = runScript("joamag.rgb", "rgb.sh", args, { bin: f.dir, env: f.env })
      assert.equal(result.status, 0, args.join(" "))
      assert.equal(result.stdout, `error\t${message}\n`, args.join(" "))
    }
    assert.deepEqual(f.log(), [])
  })

  it("says so when openrgb is not there to set anything", (t) => {
    const bin = tmpdir(t)
    const result = runScript("joamag.rgb", "rgb.sh", ["set", "0", "Static", "FFFFFF"], { path: bin })
    assert.equal(result.stdout, "error\topenrgb not found\n")
  })

  it("reports an unknown mode OpenRGB only mentions on its output", (t) => {
    const f = fakes(t)
    const result = runScript("joamag.rgb", "rgb.sh", ["set", "0", "Static", "FFFFFF"], { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: "Error: Mode 'Static' not available for device 'NZXT Smart Device V2'" } })
    assert.equal(result.status, 0)
    assert.equal(Model.actionError(result.stdout), "Mode 'Static' not available for device 'NZXT Smart Device V2'")
  })

  it("asks again with as many of the colour as an effect takes at least", (t) => {
    const f = fakes(t)
    // Complains until it is handed FAKE_MIN colours, the way OpenRGB does for a
    // mode that takes more than one.
    fakeCommand(f.dir, "openrgb", `
printf '%s\\n' "$*" >> "$FAKE_LOG"
colors=""; previous=""
for arg in "$@"; do [[ $previous == --color ]] && colors=$arg; previous=$arg; done
if [[ -n $colors ]] && (( $(tr ',' '\\n' <<<"$colors" | wc -l) >= FAKE_MIN )); then exit 0; fi
echo "Wrong number of colors specified for mode Alternating"
echo "Please provide between $FAKE_MIN and 8 colors"`)
    const result = runScript("joamag.rgb", "rgb.sh", ["set", "0", "Alternating", "FF0000", "50"], { bin: f.dir, env: { ...f.env, FAKE_MIN: "3" } })
    assert.equal(result.stdout, "")
    assert.deepEqual(f.log(), [
      "--device 0 --mode Alternating --color FF0000 --speed 50",
      "--device 0 --mode Alternating --color FF0000,FF0000,FF0000 --speed 50",
    ])
  })

  it("reports a number of colours the effect does not take, which OpenRGB exits 0 on", (t) => {
    const f = fakes(t)
    const output = "Connected to server\nWrong number of colors specified for mode Alternating\nPlease provide between 2 and 2 colors"
    const result = runScript("joamag.rgb", "rgb.sh", ["set", "0", "Alternating", "FF0000", "50"], { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: output } })
    assert.equal(result.status, 0)
    assert.equal(Model.actionError(result.stdout), "Wrong number of colors specified for mode Alternating")
    assert.deepEqual(f.log(), [
      "--device 0 --mode Alternating --color FF0000 --speed 50",
      "--device 0 --mode Alternating --color FF0000,FF0000 --speed 50",
    ])
  })

  it("asks only once when no colour was given or the least it takes is one, none or past reason", (t) => {
    const f = fakes(t)
    const wrong = (low, high) => `Wrong number of colors specified for mode Wings\nPlease provide between ${low} and ${high} colors`
    const cases = [
      [["set", "0", "Wings"], wrong(2, 2)],
      [["set", "0", "Wings", "FF0000"], wrong(0, 0)],
      [["set", "0", "Wings", "FF0000"], wrong(1, 1)],
      [["set", "0", "Wings", "FF0000"], wrong(100, 200)],
    ]
    for (const [args, output] of cases) {
      const result = runScript("joamag.rgb", "rgb.sh", args, { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: output } })
      assert.equal(Model.actionError(result.stdout), "Wrong number of colors specified for mode Wings", output)
    }
    assert.equal(f.log().length, cases.length)
  })

  it("reports a set that failed without words by its exit status", (t) => {
    const f = fakes(t)
    const result = runScript("joamag.rgb", "rgb.sh", ["set", "9", "Static", "FFFFFF"], { bin: f.dir, env: { ...f.env, FAKE_OPENRGB_OUTPUT: "", FAKE_OPENRGB_STATUS: "255" } })
    assert.equal(result.stdout, "error\topenrgb exited 255\n")
  })

  it("prints usage for an unknown command", () => {
    const result = runScript("joamag.rgb", "rgb.sh", ["paint"])
    assert.equal(result.status, 1)
    assert.match(result.stderr, /Usage: rgb.sh/)
  })
})
