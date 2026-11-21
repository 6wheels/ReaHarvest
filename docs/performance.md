# Performance budgets

Measurable budgets of the desktop application. They make the performance
targets of SPEC §8 concrete, and the benchmarks below check them.

## Reference conditions

- **Library**: a synthetic library of **1,000 titles** with one `.RPP` each,
  built by the benchmark tool from the fixtures in `test/fixtures/`. Its media
  are sparse files totalling 100 GB, so the library weighs almost nothing on
  disk. The generator is seeded, so every run builds the same library.
- **Build**: release (`flutter build windows`); debug and profile timings do
  not count.
- **Machine**: the maintainer's Windows PC is the reference. The CI Windows
  runner gets twice each budget (×2), because its timings vary from one run
  to the next.
- **Cold start**: no running instance, and a data folder prepared with its
  settings and an up-to-date index. The operating system's file cache is not
  flushed.
- **Result**: the median of 5 runs, after one warm-up run that is not counted.

## Budgets

| # | Measure | From → to | Budget (reference) | Budget (CI) |
|---|---|---|---|---|
| B1 | Cold start | process start → first frame with the title list served from the index | < 1 s | < 2 s |
| B2 | First full scan | scan started → scan done, nothing indexed yet | < 30 s | < 60 s |
| B3 | Rescan with no change | scan started → scan done, library unchanged since the index | < 2 s | < 4 s |
| B4 | Scrolling the title list | each frame while scrolling the 1,000 titles from top to bottom | 90 % of frames < 16 ms, none > 50 ms | 90 % < 32 ms, none > 100 ms |
| B5 | Search | keystroke → filtered list displayed (one character added, 1,000 titles) | < 100 ms | < 200 ms |
| B6 | Interface during a scan | each frame while B2 runs | none > 50 ms | none > 100 ms |
| B7 | Quit | "Quit" chosen, no task running → process ended | < 500 ms | < 1 s |

Rules attached to the budgets:

- B3 reads no file content: dates and sizes only, checked by counting the
  files the scan opens (SPEC §8, cloud folders with on-demand files).
- B4 to B6 are measured on the frame build and raster times reported by the
  engine (`FrameTiming`).
- B7 is measured with the tray icon shown and with it hidden.

## Benchmarks

- One command runs every benchmark and prints each measure against its budget.
  A measure over its budget makes the command fail.
- The benchmarks do not run on every pull request. They run in a CI workflow
  started by hand or weekly on the Windows runner, which keeps each result as
  an artifact.
- They are added by #189, which also gives the command.

## Changing a budget

A budget changes only by a dated decision in `DECISIONS.md`, then in this file.
A slower result is never accepted by raising the budget in the same pull
request.
