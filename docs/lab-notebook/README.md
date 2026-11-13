# Lab notebook (实验笔记)

The original working notes of the bring-up, kept as written: dated, with plans, expected results, pass criteria, results and the failures.
Mostly Chinese, with English in the later experiments. Experiment IDs (E001-E038) are cited from the code comments and from the main docs.

How to read it: start with [LOG.md](LOG.md) (chronological), then the experiment files. `EXPERIMENT-006` is the long one (display, touch, GPU, WiFi, Bluetooth, audio, first persistent root).
`DEVICE.md`, `STORAGE.md`, `RECOVERY.md`, `PANEL.md`, `GPU.md`, `TOUCH.md`, `WIFI-BT.md`, `AUDIO.md` are the per-topic engineering notes the summaries in `docs/en` and `docs/zh-CN` were distilled from.

Notes about the files:
- Paths starting with `private/` point to raw evidence (register dumps, device logs, partition backups, vendor files) that is **not published**.
- `tools/build-mN.sh`, `cycle-boot-mN.sh` and `gen-mN-dts.py` named in the notes were the per-milestone scripts; the repository ships the final consolidated flow in `tools/` instead.
- Statements are marked by evidence level: user statement, web lead, source evidence, verified on this phone.
- `E035` ([EXPERIMENT-011.md](EXPERIMENT-011.md)) is the clean-checkout verification run of the published build.
