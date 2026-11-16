# Experiments

Each folder here is one experiment: the question, the data it ran on, the method, the script
that ran it, and what came out. [RESULTS.md](../RESULTS.md) puts every experiment's numbers
side by side.

## Index

<!-- index:start -->
| ID | Experiment | Data | Status | Last run | Conclusion |
| --- | --- | --- | --- | --- | --- |
| [E01](E01-imu01-haar-gmwm/) | E01: Haar GMWM from step 1 on the real gyro | imu_static_01, 2.8 to 9.5 h | draft | 2026-11-04, current | White noise is 3.3 to 3.6 mdps/sqrt(Hz) on every axis, under the datasheet's typical 5. White noise + 2 Gauss-Markov + random walk leaves gy and gz outside their 95% intervals between about 20 and 500 s. |
| [E02](E02-imu01-simts-gmwm/) | E02: simts GMWM on the real gyro, with intervals and a fit test | imu_static_01, 2.8 to 9.5 h | draft | 2026-11-06, current | simts matches E01's white noise on gy and gz to about 1% (3.30 and 3.64 mdps/sqrt(Hz)), but its weights let gx's 34 Hz tone set gx's (4.56). The J test rejects white noise + 2 Gauss-Markov + random walk on every axis (p ≈ 0), so the model needs another term whichever implementation fits it. |
<!-- index:end -->

## Run

From the repository root:

```sh
python experiments/run.py E01        # one experiment, by ID or folder name
python experiments/run.py --all      # every experiment
python experiments/run.py --report   # only rebuild RESULTS.md and the index above
python experiments/run.py --check    # is everything ready to commit?
```

It needs the `gmwm` package installed (`pip install -e .`), since it reads the logs with the
same tables as the recorder, MATLAB for `main.m` experiments, and R for `main.R` experiments
(see [R](#r)). The datasets go in `data/` (see [data/README.md](../data/README.md)).

For each run, `run.py`:

1. Reads `config.json` and finds the dataset in `data/README.md`, checking its SHA-256.
2. Decodes the window once into `data/cache/`, so every method and language reads the same samples.
   For `main.R`, it also installs each R package submodule the script names, built from the
   submodule's checked-out commit, unless the installed copy already is.
3. Runs the entry script from the experiment folder, with its outputs going to `out.tmp/`
   and its console output to `log.txt`.
4. Checks the outputs' columns and units, adds `run.json`, then replaces `out/`. A failed run
   leaves `out/` as it was, and git keeps the outputs of earlier runs.
5. Rebuilds `RESULTS.md` and the index.

`run.json` holds only what the run alone knows: when it ran, how long it took, the commit it started
from, and `inputs`, the SHA-256 of everything its outputs follow from: `config.json`, the entry
script, the helpers in `lib/` in its language, every path the entry script names with `exp_path(...)`,
and the dataset (its checksum from `data/README.md`). A submodule it names, such as `external/simts`,
is pinned by its commit instead, with `-dirty` when its files differ from that commit. A run cannot name the commit that will hold it, so `inputs` is what pins
it: once those files are committed, they say exactly which code and data made the outputs. That is
also how `--check` knows when outputs are stale.

## Before committing

`python experiments/run.py --check` reports, from the working tree:

| Problem | Draft | Final |
| --- | --- | --- |
| never run, or an input changed since the run (it names the files) | warns | blocks |
| README without its `# E01: ...` title or `**Conclusion:**` line | blocks | blocks |
| `RESULTS.md` or the index above out of date | blocks | blocks |

The git pre-commit hook runs it, so a blocked check stops the commit. `run.json` is the record of
one run. Editing it or `config.json` by hand leaves that record as it is; rerun the experiment to
change either. A conclusion that disagrees with the outputs is for a reader to catch. In Claude
Code, `.claude/hooks/commit_check.py` adds this report, and that reminder, whenever a prompt
mentions committing.

## An experiment folder

```
E01-imu01-haar-gmwm/
├── README.md      question, setup, results, conclusion
├── config.json    the run's settings
├── main.m         the entry script, or main.R
└── out/           written by run.py; committed
    ├── params.csv     fitted parameters
    ├── wv.csv         wavelet variance: measured, its 95% interval, and the fitted model's
    ├── fit.csv        objective, scales, run time, per axis
    ├── *.png          figures
    ├── log.txt        the script's console output
    └── run.json       date, run time, base commit, inputs
```

The README starts with `# E01: <title>` and has one line starting with `**Conclusion:**`;
the index shows both.

`config.json` always has `status` (`draft` or `final`), `method` (the label RESULTS.md shows),
`dataset`, and `window_h` (`[from, to]` in hours since the log's first sample; leave it out for
the whole log). Everything else is the experiment's own, such as `sensor` and `model`.

## Draft and final

A draft can run with uncommitted changes. A final run needs its inputs committed first, so a commit
holds exactly what it ran: commit the code, run, then commit the outputs. `run.py` will not run a
final experiment again while its outputs are current, unless `--force`. Once a final experiment is
done, leave it: a changed method is a new experiment with a new ID.

## What an entry script gets

`run.py` passes everything through environment variables, and a small helper per language reads them.

| Variable | |
| --- | --- |
| `EXP_ID` | the experiment ID, e.g. `E01` |
| `EXP_ROOT` | the repository root |
| `EXP_CONFIG` | `config.json` |
| `EXP_DATA` | the decoded window's header in `data/cache/`; the samples sit next to it |
| `EXP_OUT` | where outputs go |

MATLAB (`main.m`, helpers in `lib/`, which `run.py` adds to the path):

| Helper | |
| --- | --- |
| `cfg = exp_config()` | `config.json` as a struct |
| `d = exp_data()` | the window: `d.gyro` [dps], `d.accel` [g], `d.fs`, `d.t0`, `d.lost` |
| `addpath(exp_path("matlab/wavelets"))` | a path in the repository |
| `exp_write("params.csv", T)` | writes a table as CSV, a missing value as an empty field |
| `exp_figure(fig, "gyro_wv")` | saves `gyro_wv.png`, light theme |

R (`main.R`, helpers in `lib/exp.R`, which `run.py` sources first):

| Helper | |
| --- | --- |
| `cfg <- exp_config()` | `config.json` as a list |
| `d <- exp_data()` | the window: `d$gyro` [dps], `d$accel` [g], `d$fs`, `d$t0`, `d$lost` |
| `exp_package(exp_path("external/simts"))` | loads the R package in a submodule, after checking it was built from the submodule's commit |
| `exp_write("params.csv", df)` | writes a data frame as CSV, `NA` as an empty field |
| `exp_figure("gyro_wv", function() ...)` | draws with base graphics and saves `gyro_wv.png` |

### R

R 4.5 with Rtools45, which compiles the C++ in R packages from source. The R installer does not
add R to PATH, so `run.py` also finds it through the registry. Install the packages that
`external/simts` needs once:

```sh
Rscript -e "install.packages(c('Rcpp','RcppArmadillo','broom','dplyr','magrittr','purrr','tidyr','robcor','scales','rlang','jsonlite'), repos = 'https://cloud.r-project.org')"
```

`run.py` builds simts itself from `external/simts` (`git submodule update --init` fetches it) and
records the commit as `RemoteSha` in the installed package, which `exp_package()` checks.

## Output formats

Each row holds only what varies between rows; the experiment, its data and its method are in
`config.json`.

| File | Columns |
| --- | --- |
| `params.csv` | `sensor, axis, term, parameter, value, unit, ci_low, ci_high` |
| `wv.csv` | `sensor, axis, scale_s, nu2, ci_low, ci_high, nu2_model` (`nu2` in the sensor's unit below) |
| `fit.csv` | `sensor, axis, objective, scales, seconds` |

An empty `ci_low` or `ci_high` means the method gave no interval. `run.py` rejects any other
columns or units, so every experiment's numbers compare directly.

### Parameters and units

| Term | Parameter | Gyro | Accelerometer | Meaning |
| --- | --- | --- | --- | --- |
| `WN` | `density` | mdps/sqrt(Hz) | ug/sqrt(Hz) | one-sided white noise density D, as datasheets give it: Haar WV D²/(2T) at T seconds |
| `GM1`, `GM2`, … | `tc` | s | s | Gauss-Markov correlation time; GM1 is the fastest |
| | `std` | mdps | ug | Gauss-Markov stationary standard deviation |
| `RW` | `K` | mdps/sqrt(s) | ug/sqrt(s) | random walk: its standard deviation grows as K√t |
| (wavelet variance) | `nu2` | mdps² | ug² | |

`scale_s` is the Haar filter's width, 2^j samples, in seconds: twice the Allan variance's averaging
time. The Haar wavelet variance is half the Allan variance at that averaging time.

Converting to Allan-variance conventions: angle random walk N = D/√2 (times 60 for °/√h from
dps/√Hz), and K is the rate random walk.
