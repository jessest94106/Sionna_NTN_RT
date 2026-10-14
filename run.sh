#!/bin/sh
# Paper A rural runs.  ./run.sh GPU BAND [ELEVATION...]   (BAND = S, Ka or Ku; default 10..90)
# Rerun the same command to resume: finished elevations are skipped, partial ones resume.
B=$(cd "$(dirname "$0")" && pwd)
R=$B/runs
export PYTHONPATH=$B:$B/site${PYTHONPATH:+:$PYTHONPATH}
mkdir -p $R/logs
sed -i "s#@ROOT@#$R#g" $R/groups/*.json

gpu=$1; band=$2; shift 2
[ $# -gt 0 ] || set -- 10 20 30 40 50 60 70 80 90
g=$R/groups/rural_$band.json
dirs=$(grep '"dir"' $g | cut -d'"' -f4)
for e in "$@"; do
    el=$(printf %03d $e)
    done_all=1
    for d in $dirs; do [ -f $d/results_elev${el}deg.pkl ] || done_all=0; done
    [ $done_all = 1 ] && continue
    CUDA_VISIBLE_DEVICES=$gpu ${PY:-python3} -W ignore $B/sim/run_stochastic_sim.py \
        --elevation $e --gpu_id $gpu --group $g --resume > $R/logs/rural_${band}_e$e.log 2>&1 \
        || echo "FAILED rural_$band e$e" >> $R/logs/failed.txt
    for d in $dirs; do   # results file holds the same data as the checkpoint
        [ -f $d/results_elev${el}deg.pkl ] && rm -f $d/checkpoint_elev${el}deg.pkl
    done
done
echo "rural_$band done $(date)" >> $R/logs/failed.txt
