# Paper A run kit

The ray-tracing sweep for Paper A covers:

- 2 scenarios (urban, rural)
- 3 bands (S 2 GHz, Ku 12 GHz, Ka 20 GHz)
- 9 elevations (10°–90°)

Each run uses 10 random scenes × 1000 UEs. Each scenario, band and elevation writes one `results_elevXXXdeg.pkl` per output folder.

| PC | Runs |
|---|---|
| First PC (lambda-dual, 2 × 10 GB GPUs) | urban, all bands |
| Second PC | rural, all bands |

Both PCs run the same code from this repo: the runner, the repo modules it imports, and the patched Sionna RT 1.2.1 in `site/`. Do not swap in another Sionna. The project's patches fix the line-of-sight test and the ray launch toward a distant satellite, and the patch check below must pass.

## 1. Prepare the environment

**Needs**
- Linux.
- NVIDIA GPU with ≥ 10 GB. CUDA is required; the patched ray launcher does not run on CPU.
- Python 3.12.
- About 220 GB of free disk for rural (results about 110 GB, plus checkpoints of the same size until deleted).

```sh
git clone -b dev git@github.com:jessest94106/Sionna_NTN_RT.git paper_A_kit
cd paper_A_kit
python3.12 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt

PYTHONPATH=$PWD:$PWD/site python -c "import Ray_Tracing.src.sionna_patch_check as c; print(c.summary_line(c.require()))"
```

The check must print:

```
sionna 1.2.1: beamforming=yes guard=1.0 mm cone=exact cuda=yes archive=2026-10-14
```

If it shows an error, `cuda=no` or an older archive date, stop and fix the setup first.

**Smoke test** (about 5 min, 1 scene × 50 UEs):

```sh
PYTHONPATH=$PWD:$PWD/site python sim/make_paper_a_runs.py smoke --smoke
RUNS=$PWD/smoke ./run.sh 0 rural Ka 30
grep -E "sionna 1.2.1|candidate cap hit|scene=1/1" smoke/logs/rural_Ka_e30.log
ls smoke/rural_Ka/results_elev030deg.pkl
```

It passes if the log shows `cone=exact`, there is no `candidate cap hit` line, and the results file exists. Then delete `smoke/`.

## 2. Run

`./run.sh GPU SCENARIO BAND [ELEVATION...]`. Elevations default to 10–90.

Second PC (rural) with 2 GPUs, about 26 h each:

```sh
. .venv/bin/activate
nohup sh -c './run.sh 0 rural S;  ./run.sh 0 rural Ku 10 20 30 40'    > runs/gpu0.out 2>&1 &
nohup sh -c './run.sh 1 rural Ka; ./run.sh 1 rural Ku 50 60 70 80 90' > runs/gpu1.out 2>&1 &
```

With 1 GPU, about 52 h:

```sh
nohup sh -c './run.sh 0 rural S; ./run.sh 0 rural Ka; ./run.sh 0 rural Ku' > runs/gpu0.out 2>&1 &
```

**Rules**
- **To resume** after a crash or reboot, run the same command again. Finished elevations are skipped, and a partly done elevation restarts from its last finished scene.
- **Never run the same scenario, band and elevation on two GPUs at once.** Both would write the same checkpoint.
- **Known crash:** Dr.Jit sometimes aborts with `Assertion failed ... queue.cpp:357`. The elevation then appears in `runs/logs/failed.txt`; rerun the command.

**Check while running**

```sh
cat runs/logs/failed.txt                          # failures, plus a "finished" line per band
grep -c "candidate cap hit" runs/logs/*.log       # must be 0, otherwise paths were dropped
grep -o "scene=[0-9]*/10" runs/logs/rural_S_e10.log | tail -1
ls runs/rural_*/results_elev*.pkl | wc -l         # 36 when rural is done
```

`ground ray missing N/N` in the logs is expected for rough ground, which has no mirror-like ground bounce. The check only means something when N is small and the count is not N/N.

## 3. Collect the data

Layout, the same on both PCs:

```
runs/<scenario>_<band>[_<pol>]/results_elevXXXdeg.pkl     the data: keep
runs/<scenario>_<band>[_<pol>]/checkpoint_elevXXXdeg.pkl  same content as results: delete once results exist
runs/<scenario>_<band>[_<pol>]/scratch_elevXXX/           generated scene files: delete
runs/logs/<scenario>_<band>_eXX.log                       keep
```

Output folders, each with 9 results files:

- urban: `urban_S_V`, `urban_S_H`, `urban_Ka`, `urban_Ku`
- rural: `rural_S_V`, `rural_S_H`, `rural_Ka`, `rural_Ku`

S band has one folder per UE port (V, H), both from the same ray trace.

**Check every results file before copying.** Each must hold 10000 UEs. The patch date must be 2026-10-14, except for urban S and urban Ka 10°–70° (2026-09-24; see "Settings worth knowing"):

```sh
PYTHONPATH=$PWD:$PWD/site python - <<'EOF'
import glob, pickle
for f in sorted(glob.glob("runs/*/results_elev*.pkl")):
    r = pickle.load(open(f, "rb"))
    print(f, len(r["P_los"]), r["cfg_snapshot"]["_SIONNA_PATCH"]["archive_rev"])
EOF
```

**Gather everything on the second PC for post-processing.** Pull the first PC's urban results into the second PC's `runs/`:

```sh
rsync -av --include='urban_*/' --include='urban_*/results_elev*.pkl' \
      --include='logs/' --include='logs/urban_*.log' --exclude='*' \
      jesse@128.95.30.53:/home/aaron/Ray_Tracing/jesse/Results/paper_A/ runs/
```

`runs/` then holds all 72 results files. The rsync filter copies only `urban_*`, so it cannot overwrite rural data.

**What a results file holds**
- **Per-UE values** (lists of 10000) in top-level keys, for example `los_probability`, `P_los`, `P_nlos_2us`, `DS_ns`, `sigma_nu_Hz`, `P_nlos_panel`, `heading_deg` and `scene_seeds`.
- **Full paths for 1 UE in 50** in `raw_results` (200 per file).
- The run settings in `cfg_snapshot`.

## Contents

- `run.sh`: the queue for one GPU, one scenario and one band.
- `sim/run_stochastic_sim.py`: Aaron's stochastic runner with the Paper A per-UE values computed during the run.
- `sim/make_paper_a_runs.py` and `sim/base_config.json`: rebuild `runs/` exactly (configs and scene lists).
- `runs/`: run inputs for both scenarios. Group files carry an `@ROOT@` placeholder that `run.sh` fills in.
- `Ray_Tracing/src/`: the repo modules the runner imports, as of 2026-10-14. `Ray_Tracing/sionna_patch/` holds the patch archive the check verifies against.
- `site/sionna/`: Sionna RT 1.2.1 with the three project patches.

**Settings worth knowing**
- **Rural solves 5 UEs at a time.** The rough rural ground (10 cm) makes about 0.5M diffuse paths per UE; with 25 UEs per solve, Sionna's 10M-path buffer overflowed and dropped paths without an error.
- **Patch fixed 2026-10-14.** Before then, the beam-cone width was rounded in float32. That biased diffuse power by about 1–2 dB at 10° and ≤ 0.2 dB elsewhere. Results with `archive_rev` 2026-09-24 have this bias.
- **Urban results made with the old patch are kept, by decision; they were not rerun.** They are urban S (all elevations) and urban Ka 10°–70°. Urban Ka 80°–90°, urban Ku and all rural use the fixed patch. In post-processing, keep in mind the diffuse-power bias at 10° (and to a lesser degree 20°) in urban S and Ka. Each file's `archive_rev` shows which patch made it. The results-file check in section 3 therefore expects 2026-09-24 for those urban files.
