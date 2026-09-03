// Tests for joamag.sysmon: Model.js in declaration order, then stats.sh.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const { execSync } = require("node:child_process")
const { loadModel, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.sysmon")

// A snapshot the way stats.sh emits it, with a process name containing a tab.
const RAW = [
  "cpu_idle\t100",
  "cpu_total\t200",
  "cpu_mhz\t4164",
  "cpu_count\t12",
  "mem_total_kb\t65746004",
  "mem_avail_kb\t46898348",
  "swap_total_kb\t99300344",
  "swap_free_kb\t99300344",
  "load1\t0.58",
  "load5\t0.69",
  "load15\t0.99",
  "uptime_sec\t158162",
  "kernel_release\t7.1.9-arch1-2",
  "kernel_built\t1787350739",
  "cpu_temp_c\t55.6",
  "gpu_name\tNVIDIA GeForce GTX 1650",
  "gpu_util\t15",
  "gpu_temp_c\t42",
  "gpu_mem_used_mb\t3297",
  "gpu_mem_total_mb\t4096",
  "disk_total_kb\t247943168",
  "disk_used_kb\t102431720",
  "disk_pct\t42",
  "proc\t808239\t100\t0.0\tlocalsearch\text",
  "proc\t677079\t21.3\t1.5\tchrome",
  "proc\tshort",
  "",
].join("\n")

const snapshot = Model.parseSnapshot(RAW)
const noGpu = Model.parseSnapshot("cpu_idle\t1\ncpu_total\t2\nmem_total_kb\t100\nmem_avail_kb\t50\n")

describe("clamp", () => {
  it("keeps values inside the range", () => {
    assert.equal(Model.clamp(5, 0, 10), 5)
    assert.equal(Model.clamp(-1, 0, 10), 0)
    assert.equal(Model.clamp(11, 0, 10), 10)
  })
})

describe("num", () => {
  it("parses numeric strings and rejects the rest", () => {
    assert.equal(Model.num("4.5"), 4.5)
    assert.ok(Number.isNaN(Model.num("abc")))
    assert.ok(Number.isNaN(Model.num(undefined)))
    assert.ok(Number.isNaN(Model.num(Infinity)))
  })
})

describe("parseSnapshot", () => {
  it("maps scalar lines to string fields", () => {
    assert.equal(snapshot.cpu_total, "200")
    assert.equal(snapshot.gpu_name, "NVIDIA GeForce GTX 1650")
  })

  it("collects processes and keeps tabs inside a command name", () => {
    assert.equal(snapshot.procs.length, 2)
    assert.deepEqual(snapshot.procs[0], { pid: "808239", cpu: 100, mem: 0, name: "localsearch\text" })
    assert.equal(snapshot.procs[1].cpu, 21.3)
  })

  it("skips malformed process rows and empty input", () => {
    assert.deepEqual(Model.parseSnapshot(""), { procs: [] })
    assert.deepEqual(Model.parseSnapshot(null), { procs: [] })
  })
})

describe("cpuPercent", () => {
  it("needs two samples", () => {
    assert.equal(Model.cpuPercent(null, snapshot), -1)
    assert.equal(Model.cpuPercent(snapshot, null), -1)
  })

  it("derives the busy share from the jiffies delta", () => {
    const next = Model.parseSnapshot("cpu_idle\t150\ncpu_total\t400")
    assert.equal(Model.cpuPercent(snapshot, next), 75)
  })

  it("rejects a counter that did not move or went backwards", () => {
    assert.equal(Model.cpuPercent(snapshot, snapshot), -1)
    assert.equal(Model.cpuPercent(snapshot, Model.parseSnapshot("cpu_idle\t0\ncpu_total\t10")), -1)
  })

  it("clamps an idle delta larger than the total", () => {
    assert.equal(Model.cpuPercent(snapshot, Model.parseSnapshot("cpu_idle\t400\ncpu_total\t300")), 0)
  })
})

describe("ratioPercent", () => {
  it("returns -1 without a positive total or a numeric value", () => {
    assert.equal(Model.ratioPercent(1, 0), -1)
    assert.equal(Model.ratioPercent("x", 10), -1)
  })

  it("clamps to the 0..100 range", () => {
    assert.equal(Model.ratioPercent(150, 100), 100)
    assert.equal(Model.ratioPercent(25, 100), 25)
  })
})

describe("memPercent", () => {
  it("uses total minus available", () => {
    assert.equal(Math.round(Model.memPercent(snapshot) * 10) / 10, 28.7)
    assert.equal(Model.memPercent(null), -1)
  })
})

describe("swapPercent", () => {
  it("is zero when nothing is swapped and -1 without a snapshot", () => {
    assert.equal(Model.swapPercent(snapshot), 0)
    assert.equal(Model.swapPercent(null), -1)
  })
})

describe("diskPercent", () => {
  it("uses used over total", () => {
    assert.equal(Math.round(Model.diskPercent(snapshot)), 41)
    assert.equal(Model.diskPercent(undefined), -1)
  })
})

describe("gpuPercent", () => {
  it("reads the utilisation when present", () => {
    assert.equal(Model.gpuPercent(snapshot), 15)
    assert.equal(Model.gpuPercent(noGpu), -1)
    assert.equal(Model.gpuPercent(Model.parseSnapshot("gpu_util\tn/a")), -1)
    assert.equal(Model.gpuPercent(Model.parseSnapshot("gpu_util\t140")), 100)
  })
})

describe("gpuMemPercent", () => {
  it("uses used over total VRAM", () => {
    assert.equal(Math.round(Model.gpuMemPercent(snapshot)), 80)
    assert.equal(Model.gpuMemPercent(noGpu), -1)
  })
})

describe("cpuTemp", () => {
  it("parses the temperature or returns NaN", () => {
    assert.equal(Model.cpuTemp(snapshot), 55.6)
    assert.ok(Number.isNaN(Model.cpuTemp(noGpu)))
    assert.ok(Number.isNaN(Model.cpuTemp(null)))
  })
})

describe("gpuTemp", () => {
  it("parses the temperature or returns NaN", () => {
    assert.equal(Model.gpuTemp(snapshot), 42)
    assert.ok(Number.isNaN(Model.gpuTemp(noGpu)))
  })
})

describe("hasGpu", () => {
  it("depends on the utilisation field", () => {
    assert.equal(Model.hasGpu(snapshot), true)
    assert.equal(Model.hasGpu(noGpu), false)
    assert.equal(Model.hasGpu(null), false)
  })
})

describe("formatKb", () => {
  it("picks MB, one-decimal GB or whole GB", () => {
    assert.equal(Model.formatKb(512 * 1024), "512 MB")
    assert.equal(Model.formatKb(1.5 * 1024 * 1024), "1.5 GB")
    assert.equal(Model.formatKb(250 * 1024 * 1024), "250 GB")
    assert.equal(Model.formatKb("nope"), "—")
  })
})

describe("formatMb", () => {
  it("switches to GB above 1024", () => {
    assert.equal(Model.formatMb(512), "512 MB")
    assert.equal(Model.formatMb(3297), "3.2 GB")
    assert.equal(Model.formatMb(undefined), "—")
  })
})

describe("formatPercent", () => {
  it("rounds and refuses negatives", () => {
    assert.equal(Model.formatPercent(41.6), "42%")
    assert.equal(Model.formatPercent(-1), "—")
    assert.equal(Model.formatPercent("x"), "—")
  })
})

describe("formatTemp", () => {
  it("rounds to whole degrees", () => {
    assert.equal(Model.formatTemp(55.6), "56°C")
    assert.equal(Model.formatTemp(NaN), "—")
  })
})

describe("formatMhz", () => {
  it("shows GHz above 1000 MHz", () => {
    assert.equal(Model.formatMhz(4164), "4.16 GHz")
    assert.equal(Model.formatMhz(800), "800 MHz")
    assert.equal(Model.formatMhz(undefined), "—")
  })
})

describe("formatUptime", () => {
  it("scales from minutes to days", () => {
    assert.equal(Model.formatUptime(158162), "1d 19h")
    assert.equal(Model.formatUptime(3600 * 5 + 60 * 7), "5h 7m")
    assert.equal(Model.formatUptime(59), "0m")
    assert.equal(Model.formatUptime(-5), "—")
  })
})

describe("kernelRelease", () => {
  it("returns the running release or an empty string", () => {
    assert.equal(Model.kernelRelease(snapshot), "7.1.9-arch1-2")
    assert.equal(Model.kernelRelease(noGpu), "")
    assert.equal(Model.kernelRelease(null), "")
  })
})

describe("kernelBuilt", () => {
  it("parses the build timestamp or returns NaN", () => {
    assert.equal(Model.kernelBuilt(snapshot), 1787350739)
    assert.ok(Number.isNaN(Model.kernelBuilt(noGpu)))
    assert.ok(Number.isNaN(Model.kernelBuilt(Model.parseSnapshot("kernel_built\tunknown"))))
    assert.ok(Number.isNaN(Model.kernelBuilt(null)))
  })
})

describe("formatDate", () => {
  it("prints day, month and year in local time", () => {
    assert.equal(Model.formatDate(new Date(2026, 7, 21, 12).getTime() / 1000), "21 Aug 2026")
    assert.equal(Model.formatDate(new Date(2027, 0, 1, 12).getTime() / 1000), "1 Jan 2027")
    assert.equal(Model.formatDate(NaN), "—")
    assert.equal(Model.formatDate(undefined), "—")
  })
})

describe("normalizeMetric", () => {
  it("accepts known metrics case-insensitively and defaults to cpu", () => {
    assert.equal(Model.normalizeMetric("Memory"), "memory")
    assert.equal(Model.normalizeMetric("bogus"), "cpu")
    assert.equal(Model.normalizeMetric(undefined), "cpu")
  })
})

describe("nextMetric", () => {
  it("walks the ring and wraps", () => {
    assert.equal(Model.nextMetric("cpu", true), "memory")
    assert.equal(Model.nextMetric("disk", true), "cpu")
  })

  it("skips the gpu when none is available", () => {
    assert.equal(Model.nextMetric("temperature", false), "disk")
    assert.equal(Model.nextMetric("temperature", true), "gpu")
  })

  it("treats an unknown metric as cpu", () => {
    assert.equal(Model.nextMetric("nope", true), "memory")
  })
})

describe("barValue", () => {
  it("formats the configured metric", () => {
    assert.equal(Model.barValue("cpu", 12.4, snapshot), "12%")
    assert.equal(Model.barValue("memory", 0, snapshot), "29%")
    assert.equal(Model.barValue("temperature", 0, snapshot), "56°C")
    assert.equal(Model.barValue("gpu", 0, snapshot), "15%")
    assert.equal(Model.barValue("disk", 0, snapshot), "41%")
    assert.equal(Model.barValue("gpu", 0, noGpu), "—")
  })
})

describe("barLevel", () => {
  it("returns a 0..100 level per metric", () => {
    assert.equal(Model.barLevel("cpu", 33, snapshot), 33)
    assert.equal(Math.round(Model.barLevel("memory", 0, snapshot)), 29)
    assert.equal(Model.barLevel("temperature", 0, snapshot), 55.6)
    assert.equal(Model.barLevel("temperature", 0, noGpu), -1)
    assert.equal(Model.barLevel("gpu", 0, snapshot), 15)
    assert.equal(Math.round(Model.barLevel("disk", 0, snapshot)), 41)
  })

  it("clamps a temperature above 100 degrees", () => {
    assert.equal(Model.barLevel("temperature", 0, Model.parseSnapshot("cpu_temp_c\t120")), 100)
  })
})

describe("tooltip", () => {
  it("lists CPU, memory, temperature and GPU when known", () => {
    assert.equal(Model.tooltip(12, snapshot), "CPU 12% · Memory 29% · 56°C · GPU 15%")
    assert.equal(Model.tooltip(12, noGpu), "CPU 12% · Memory 50%")
    assert.equal(Model.tooltip(0, null), "System monitor")
  })
})

describe("stats.sh", () => {
  it("emits the core fields and the requested number of processes", () => {
    const result = runScript("joamag.sysmon", "stats.sh", ["3"])
    assert.equal(result.status, 0)
    const parsed = Model.parseSnapshot(result.stdout)
    for (const key of ["cpu_idle", "cpu_total", "cpu_count", "mem_total_kb", "mem_avail_kb", "load1", "uptime_sec", "disk_total_kb", "disk_pct"]) {
      assert.ok(key in parsed, `missing ${key}`)
      assert.ok(Number.isFinite(Number(parsed[key])), `${key} is not numeric: ${parsed[key]}`)
    }
    assert.ok(parsed.procs.length > 0 && parsed.procs.length <= 3)
    assert.ok(parsed.procs.every((p) => /^\d+$/.test(p.pid) && Number.isFinite(p.cpu) && Number.isFinite(p.mem) && p.name !== ""))
  })

  it("reports the running kernel and a plausible build time", () => {
    const parsed = Model.parseSnapshot(runScript("joamag.sysmon", "stats.sh", ["0"]).stdout)
    assert.equal(parsed.kernel_release, execSync("uname -r").toString().trim())
    const built = Model.kernelBuilt(parsed)
    assert.ok(Number.isFinite(built), `kernel_built missing or not numeric: ${parsed.kernel_built}`)
    // Built after Linux 6.0 shipped and not in the future.
    assert.ok(built > Date.UTC(2022, 9, 1) / 1000 && built <= Date.now() / 1000 + 86400)
  })

  it("omits the process list when zero rows are requested", () => {
    const result = runScript("joamag.sysmon", "stats.sh", ["0"])
    assert.equal(result.status, 0)
    assert.equal(Model.parseSnapshot(result.stdout).procs.length, 0)
  })

  it("parses nvidia-smi output for the GPU fields", (t) => {
    const bin = tmpdir(t)
    fakeCommand(bin, "nvidia-smi", 'echo "NVIDIA GeForce RTX 4070, 37, 61, 2048, 12282"')
    const parsed = Model.parseSnapshot(runScript("joamag.sysmon", "stats.sh", ["0"], { bin }).stdout)
    assert.equal(parsed.gpu_name, "NVIDIA GeForce RTX 4070")
    assert.equal(parsed.gpu_util, "37")
    assert.equal(parsed.gpu_temp_c, "61")
    assert.equal(parsed.gpu_mem_used_mb, "2048")
    assert.equal(parsed.gpu_mem_total_mb, "12282")
  })

  it("drops GPU fields when nvidia-smi answers garbage", (t) => {
    const bin = tmpdir(t)
    fakeCommand(bin, "nvidia-smi", 'echo "No devices were found"')
    const parsed = Model.parseSnapshot(runScript("joamag.sysmon", "stats.sh", ["0"], { bin }).stdout)
    assert.equal(Model.hasGpu(parsed), false)
  })
})
