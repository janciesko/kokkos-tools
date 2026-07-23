#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.."
LAMMPS=${LAMMPS:-../lammps/install/bin/lmp}
TOOLS=${TOOLS:-./build}
INPUT=${INPUT:-./scripts/in.lj.short}
KK=${KK:--k on g 1 -sf kk}
LOG=${LOG:-./lammps-sanity-logs}

LAMMPS=$(realpath "$LAMMPS")
TOOLS=$(realpath "$TOOLS")
INPUT=$(realpath "$INPUT")
mkdir -p "$LOG"
LOG=$(realpath "$LOG")

WD=$(mktemp -d)
echo '.*' >"$WD/filter.txt"

so() { find "$TOOLS" -name "lib$1.so" -print -quit; }

FAIL=0
run() { # name libs expect [EXTRA_ENV=val ...]
  local name=$1 libs=$2 expect=$3; shift 3
  local out=$LOG/$name.out
  unset KOKKOS_TOOLS_LIBS
  echo "+ env $* KOKKOS_TOOLS_LIBS=$libs $LAMMPS $KK -in $INPUT"
  (
    cd "$WD"
    export KOKKOS_TOOLS_LIBS=$libs
    env "$@" "$LAMMPS" $KK -in "$INPUT"
  ) >"$out" 2>&1
  if [[ $? -eq 0 ]] && { [[ -z $expect ]] || grep -Eq "$expect" "$out"; }; then
    echo "PASS $name"
  else
    echo "FAIL $name  ($out)"; FAIL=1
  fi
}

EXPECT_PARFOR='KokkosP: Executing parallel-for'
EXPECT_TIMER='\(ParFor\)|\(ParRed\)'
EXPECT_HWM='High water mark'
EXPECT_EVENTS='MemoryEvents loaded'
EXPECT_STS='BEGIN KOKKOS PROFILING REPORT'
EXPECT_FILTER='Kernel Filtering is enabled'

echo "LAMMPS=$LAMMPS TOOLS=$TOOLS KK=$KK"

run baseline           ""                                              ""
run kernel_logger      "$(so kp_kernel_logger)"                        "$EXPECT_PARFOR"
run kernel_timer       "$(so kp_kernel_timer)"                         "$EXPECT_TIMER"
run memory_hwm         "$(so kp_hwm)"                                  "$EXPECT_HWM"
run memory_events      "$(so kp_memory_events)"                        "$EXPECT_EVENTS"
run memory_usage       "$(so kp_memory_usage)"                         ""
run chrome_tracing     "$(so kp_chrome_tracing)"                       ""
run space_time_stack   "$(so kp_space_time_stack)"                     "$EXPECT_STS"
run kernel_filter      "$(so kp_kernel_filter);$(so kp_kernel_logger)" "$EXPECT_FILTER" \
  KOKKOSP_KERNEL_FILTER="$WD/filter.txt"
run kernel_sampler     "$(so kp_kokkos_sampler);$(so kp_kernel_logger)" "$EXPECT_PARFOR" \
  KOKKOS_TOOLS_SAMPLER_SKIP=10

exit $FAIL
