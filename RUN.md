# Paper A: rural runs still to do

Self-contained: the simulation code, the patched Sionna RT 1.2.1, and the inputs for the rural runs (same scenes as the runs already made on the first PC).

Still to run:

| Band | Elevations | Output folders |
|---|---|---|
| S (2 GHz, V and H ports from one ray trace) | 30, 50, 60, 70, 80, 90 | `runs/rural_S_V`, `runs/rural_S_H` |
| Ka (20 GHz) | 10–90 | `runs/rural_Ka` |
| Ku (12 GHz) | 10–90 | `runs/rural_Ku` |

S band 10°, 20° and 40° are already done on the first PC.

## Needs

- NVIDIA GPU with ≥ 10 GB (about 7 GB used). CUDA is required: the patched ray launcher only runs on the CUDA backend.
- Python 3.12.
- About 100 GB free disk.

## Setup (once)

```sh
cd paper_A_rural
python3.12 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt

# Check that the patched Sionna in site/ is the one loaded. Expected output:
#   sionna 1.2.1: beamforming=yes guard=1.0 mm cuda=yes archive=2026-09-24
PYTHONPATH=$PWD:$PWD/site python -c "import Ray_Tracing.src.sionna_patch_check as c; print(c.summary_line(c.require()))"
```

`run.sh` puts `site/` ahead of the pip-installed Sionna on the path. pip installs Sionna only to bring in mitsuba and drjit.

## Run

Usage is `./run.sh GPU BAND [ELEVATION...]`. Leaving out the elevations runs 10–90.

With 2 GPUs:

```sh
. .venv/bin/activate
nohup sh -c './run.sh 0 S 30 50 60 70 80 90; ./run.sh 0 Ka' > runs/gpu0.out 2>&1 &
nohup ./run.sh 1 Ku > runs/gpu1.out 2>&1 &
```

With 1 GPU:

```sh
. .venv/bin/activate
nohup sh -c './run.sh 0 S 30 50 60 70 80 90; ./run.sh 0 Ka; ./run.sh 0 Ku' > runs/gpu0.out 2>&1 &
```

- To resume after a crash or reboot, run the same command again. Finished elevations are skipped, and a partly done elevation restarts from its last finished scene.
- Dr.Jit sometimes aborts with `Assertion failed ... queue.cpp:357`. A rerun fixes it.

Rough timing on the first PC, which has 10 GB GPUs: S takes about 2.5 h per elevation, Ka and Ku about 1.5–2 h each.

## Check while running

```sh
cat runs/logs/failed.txt                           # failed elevations, plus a "done" line per band
grep -c "candidate cap hit" runs/logs/*.log        # must be 0: otherwise paths were dropped
tail -n 3 runs/logs/rural_Ka_e10.log
```

`ground ray missing N/N` in the logs is expected. The 10 cm rough ground leaves no mirror-like ground bounce at these bands and elevations.

## Bring the results back

Only the `results_elev*.pkl` files are needed. Each elevation's checkpoint is deleted once its results file is written. On the first PC they go in `/home/aaron/Ray_Tracing/jesse/Results/paper_A/` under the same folder names:

```sh
rsync -av --include='*/' --include='results_elev*.pkl' --include='*.log' --exclude='*' \
    runs/ jesse@<first-pc>:/home/aaron/Ray_Tracing/jesse/Results/paper_A/
```

## Contents

- `sim/run_stochastic_sim.py`: Aaron's stochastic runner with the Paper A per-UE values computed in-run. It keeps full paths for 1 UE in 50.
- `sim/make_paper_a_runs.py`: how `runs/` was built. For reference only; it reads Aaron's base config from a fixed path on the first PC.
- `Ray_Tracing/src/`: the repo modules the runner imports, copied as they were on 2026-10-14.
- `site/sionna/`: Sionna RT 1.2.1 with the project's two patches. The patch check verifies them against `Ray_Tracing/src/sionna_patch/MANIFEST.json`.
- `runs/`: run configs and scene lists. Rural solves 5 UEs at a time; with 25, the rough ground's diffuse paths overflowed Sionna's 10M-path buffer.
