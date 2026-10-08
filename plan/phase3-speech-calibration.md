# Phase 3 speech-ratio calibration (FR-VAD-004)

Measured 2026-10-08 with `scripts/speech_ratio.py`. Read-only on `~/Documents/Teams Recording`; no recording was modified.

Metric: decode to mono f32 16 kHz (2-track files mixed 0.8*t0 + 0.8*t1, 1-track as is); 100 ms frames (1600 samples); RMS to dBFS; `speechRatio` = frames with dBFS > -40 / total frames. Bin edges are lower-inclusive, upper-exclusive; a file moves when `speechRatio` < threshold.

Scope: 353 entries in the folder = 348 `.m4a` + 5 `.mp3`. The `.mp3` files are not measured (task scope is `*.m4a`). Of 348 `.m4a`: 4 skipped by name (3 `INCOMPLETE_`, 1 `(recovered)`), 6 failed to decode, **338 measured**.

Name classes used below (by file-name prefix only): **Short** = starts with `Teams Call (Short)` (8 measured); **Unnamed** = starts with `Teams Meeting` (placeholder, 4 measured); **Named** = anything else (326 measured) = named from calendar or screen, treated as real meetings per the task definition.

## 1. Distribution of speechRatio (338 files)

| speechRatio bin | files | Short | Unnamed | Named |
|---|---|---|---|---|
| 0 - 0.01 | 4 | 0 | 0 | 4 |
| 0.01 - 0.02 | 3 | 0 | 0 | 3 |
| 0.02 - 0.05 | 10 | 0 | 0 | 10 |
| 0.05 - 0.10 | 6 | 0 | 0 | 6 |
| 0.10 - 0.20 | 3 | 1 | 0 | 2 |
| 0.20 - 0.50 | 175 | 2 | 1 | 172 |
| 0.50 - 1.00 | 137 | 5 | 3 | 129 |
| total | 338 | 8 | 4 | 326 |

Finding: none of the 8 Short files falls below 0.10 (lowest 0.1033; the other 7 range 0.43 to 0.92). Short files are therefore not a silent positive class in this data; they are exempt under FR-VAD-003 in any case. The files the metric flags below 0.10 are all Named, including `test - 18-39_25-05-2026.m4a` (0.0974), the only file with 'test' in its name.

## 2. Files with speechRatio < 0.10 (23 files)

| # | file | duration | speechRatio | p50 dBFS | p95 dBFS | class |
|---|---|---|---|---|---|---|
| 1 | DX DSD - Design Operations - 16-00_07-08-2026.m4a | 0m15s (15s) | 0.0000 | -61.2 | -47.83 | Named |
| 2 | [Knowledge Transfer] Overview Bond & Corp Bond - 15-00_02-06-2026.m4a | 0m12s (12s) | 0.0000 | -75.95 | -71.87 | Named |
| 3 | [Sync] Design Principles - 14-00_20-07-2026.m4a | 0m22s (22s) | 0.0000 | -74.53 | -58.51 | Named |
| 4 | [UApp] Sync Onboarding with P'Pop - 14-58_22-07-2026.m4a | 0m12s (12s) | 0.0000 | -73.92 | -72.58 | Named |
| 5 | DX Lead Discuss & Operations - 14-00_23-07-2026.m4a | 1m18s (78s) | 0.0129 | -76.2 | -71.33 | Named |
| 6 | [Sync] Design Principles - 15-04_02-09-2026.m4a | 0m22s (22s) | 0.0137 | -50.09 | -43.54 | Named |
| 7 | [Daily] Paotang Investment - 09-43_15-06-2026.m4a | 1m10s (70s) | 0.0186 | -73.99 | -45.76 | Named |
| 8 | Weekly Sync 26 Aug 2026.m4a | 1h06m23s (3983s) | 0.0221 | -47.02 | -41.75 | Named |
| 9 | [Daily] UApp - 09-57_21-09-2026.m4a | 1m11s (71s) | 0.0225 | -68.87 | -48.25 | Named |
| 10 | DX DSD - Design Operations - 16-02_24-07-2026.m4a | 1m10s (70s) | 0.0228 | -73.56 | -45.0 | Named |
| 11 | UApp Requirement & Refinement - 15-13_02-07-2026.m4a | 1h54m11s (6851s) | 0.0233 | -52.13 | -42.29 | Named |
| 12 | [Gold Wallet] UXUI Multiday (Design Update) - 15-59_27-05-2026.m4a | 1m10s (70s) | 0.0298 | -74.97 | -50.44 | Named |
| 13 | [Daily] Paotang Investment - 14-33_08-10-2026.m4a | 0m15s (15s) | 0.0392 | -61.24 | -45.12 | Named |
| 14 | [UApp] Monday Weekly Update - 10-59_06-07-2026.m4a | 0m12s (12s) | 0.0400 | -60.94 | -46.94 | Named |
| 15 | [One on One] Pop - Mee - 15-00_01-09-2026.m4a | 0m34s (34s) | 0.0442 | -74.15 | -43.23 | Named |
| 16 | DX Lead Discuss & Operations - 13-30_25-08-2026.m4a | 1m14s (74s) | 0.0448 | -46.72 | -41.39 | Named |
| 17 | DX Lead Discuss & Operations - 16-02_31-08-2026.m4a | 0m12s (12s) | 0.0488 | -70.47 | -40.05 | Named |
| 18 | DX DSD - Design Operations - 16-42_12-06-2026.m4a | 0m15s (15s) | 0.0584 | -75.57 | -34.83 | Named |
| 19 | DX DSD - Design Operations - 16-06_07-08-2026.m4a | 0m12s (12s) | 0.0656 | -61.06 | -33.97 | Named |
| 20 | Design Principle Skill Review.m4a | 1h26m10s (5170s) | 0.0726 | -48.4 | -38.54 | Named |
| 21 | DX DSD - Design Operations - 16-49_12-06-2026.m4a | 0m31s (31s) | 0.0754 | -71.44 | -28.24 | Named |
| 22 | DX Lead Discuss & Operations - 16-03_31-08-2026.m4a | 0m12s (12s) | 0.0894 | -65.32 | -38.45 | Named |
| 23 | test - 18-39_25-05-2026.m4a | 0m15s (15s) | 0.0974 | -52.49 | -37.04 | Named |

All Short and Unnamed files, for reference (including those above 0.10):

| file | duration | speechRatio | class |
|---|---|---|---|
| Teams Call (Short) - 10-41_26-05-2026.m4a | 0m40s | 0.1033 | Short |
| Teams Meeting - 11-59_07-08-2026.m4a | 26m16s | 0.2298 | Unnamed |
| Teams Call (Short) - 12-26_07-08-2026.m4a | 0m43s | 0.4343 | Short |
| Teams Call (Short) - 14-22_10-08-2026.m4a | 2m09s | 0.4981 | Short |
| Teams Call (Short) - 13-33_02-06-2026.m4a | 1m35s | 0.5264 | Short |
| Teams Call (Short) - 14-27_10-08-2026.m4a | 0m49s | 0.5348 | Short |
| Teams Meeting - 11-00_25-05-2026.m4a | 1h46m17s | 0.6319 | Unnamed |
| Teams Call (Short) - 10-38_10-08-2026.m4a | 0m22s | 0.7176 | Short |
| Teams Meeting - 14-59_21-07-2026.m4a | 27m10s | 0.7280 | Unnamed |
| Teams Call (Short) - 17-29_08-06-2026.m4a | 0m24s | 0.7377 | Short |
| Teams Meeting - 10-46_23-06-2026.m4a | 1h02m28s | 0.8609 | Unnamed |
| Teams Call (Short) - 10-47_05-06-2026.m4a | 0m21s | 0.9155 | Short |

## 3. Candidate thresholds

Columns: files the metric alone would move (ratio < threshold); of those, Short (FR-VAD-003 exempts these, so they would not actually move), Unnamed, Named. Named is the false-move count (spec requires 0). Last two columns split Named by duration against `MIN_DURATION` = 180 s.

| threshold | metric flags | Short | Unnamed | Named (false moves) | Named < 180 s | Named >= 180 s | actually moved after FR-VAD-003 |
|---|---|---|---|---|---|---|---|
| 0.005 | 4 | 0 | 0 | 4 | 4 | 0 | 4 |
| 0.02 | 7 | 0 | 0 | 7 | 7 | 0 | 7 |
| 0.05 | 17 | 0 | 0 | 17 | 15 | 2 | 17 |
| 0.1 | 23 | 0 | 0 | 23 | 20 | 3 | 23 |

Named files that would be false moves, by threshold (cumulative; first appearing at the threshold shown):

| first flagged at | file | duration | speechRatio |
|---|---|---|---|
| 0.005 | DX DSD - Design Operations - 16-00_07-08-2026.m4a | 0m15s | 0.0000 |
| 0.005 | [Knowledge Transfer] Overview Bond & Corp Bond - 15-00_02-06-2026.m4a | 0m12s | 0.0000 |
| 0.005 | [Sync] Design Principles - 14-00_20-07-2026.m4a | 0m22s | 0.0000 |
| 0.005 | [UApp] Sync Onboarding with P'Pop - 14-58_22-07-2026.m4a | 0m12s | 0.0000 |
| 0.02 | DX Lead Discuss & Operations - 14-00_23-07-2026.m4a | 1m18s | 0.0129 |
| 0.02 | [Sync] Design Principles - 15-04_02-09-2026.m4a | 0m22s | 0.0137 |
| 0.02 | [Daily] Paotang Investment - 09-43_15-06-2026.m4a | 1m10s | 0.0186 |
| 0.05 | Weekly Sync 26 Aug 2026.m4a | 1h06m23s | 0.0221 |
| 0.05 | [Daily] UApp - 09-57_21-09-2026.m4a | 1m11s | 0.0225 |
| 0.05 | DX DSD - Design Operations - 16-02_24-07-2026.m4a | 1m10s | 0.0228 |
| 0.05 | UApp Requirement & Refinement - 15-13_02-07-2026.m4a | 1h54m11s | 0.0233 |
| 0.05 | [Gold Wallet] UXUI Multiday (Design Update) - 15-59_27-05-2026.m4a | 1m10s | 0.0298 |
| 0.05 | [Daily] Paotang Investment - 14-33_08-10-2026.m4a | 0m15s | 0.0392 |
| 0.05 | [UApp] Monday Weekly Update - 10-59_06-07-2026.m4a | 0m12s | 0.0400 |
| 0.05 | [One on One] Pop - Mee - 15-00_01-09-2026.m4a | 0m34s | 0.0442 |
| 0.05 | DX Lead Discuss & Operations - 13-30_25-08-2026.m4a | 1m14s | 0.0448 |
| 0.05 | DX Lead Discuss & Operations - 16-02_31-08-2026.m4a | 0m12s | 0.0488 |
| 0.10 | DX DSD - Design Operations - 16-42_12-06-2026.m4a | 0m15s | 0.0584 |
| 0.10 | DX DSD - Design Operations - 16-06_07-08-2026.m4a | 0m12s | 0.0656 |
| 0.10 | Design Principle Skill Review.m4a | 1h26m10s | 0.0726 |
| 0.10 | DX DSD - Design Operations - 16-49_12-06-2026.m4a | 0m31s | 0.0754 |
| 0.10 | DX Lead Discuss & Operations - 16-03_31-08-2026.m4a | 0m12s | 0.0894 |
| 0.10 | test - 18-39_25-05-2026.m4a | 0m15s | 0.0974 |

**Recommendation.** No positive threshold gives 0 Named files moved: 4 Named files have speechRatio = 0.0000 (12.3 s to 21.6 s long), so any threshold above 0 moves them. The only threshold with 0 Named moved is 0 (nothing moves, including the Short and Unnamed files). Closest: **0.02** moves 7 Named files, all shorter than 180 s (12 s to 77 s), 0 Named files of 180 s or longer. 0.05 adds 2 Named files longer than 180 s (Weekly Sync 26 Aug 2026, 3983 s, 0.0221; UApp Requirement & Refinement - 15-13_02-07-2026, 6851 s, 0.0233) plus 8 more files shorter than 180 s; 0.10 adds a third long one (Design Principle Skill Review, 5170 s, 0.0726). If the owner accepts a duration guard (do not move Named files >= 180 s) or accepts that Named files under 180 s with ratio under the threshold are not real meetings, then 0.02 is the highest threshold with 0 Named files >= 180 s moved. That is an owner decision; the data does not settle whether the 7 short Named files had real speech.

Note: the 3 long Named files above (Weekly Sync 26 Aug 2026, UApp Requirement & Refinement 15-13_02-07-2026, Design Principle Skill Review) have p50 -47.0 to -52.1 dBFS and p95 -38.5 to -42.3 dBFS, i.e. p95 within about 2 dB of the -40 dBFS frame threshold. Their ratios are sensitive to the -40 dBFS value; the spec's frame threshold was not varied in this run.

## 4. Five lowest-ratio Named files that are 180 s or longer (listen to these)

Named files shorter than 180 s are covered in section 2. The 5 lowest-ratio Named files of any duration are the first 5 rows of section 2 (all 0.0000, 12 s to 22 s). Because those are only seconds long, the list below restricts to >= 180 s so the check is worth a listen:

| rank | file | duration | speechRatio | p50 dBFS | p95 dBFS |
|---|---|---|---|---|---|
| 1 | Weekly Sync 26 Aug 2026.m4a | 1h06m23s | 0.0221 | -47.02 | -41.75 |
| 2 | UApp Requirement & Refinement - 15-13_02-07-2026.m4a | 1h54m11s | 0.0233 | -52.13 | -42.29 |
| 3 | Design Principle Skill Review.m4a | 1h26m10s | 0.0726 | -48.4 | -38.54 |
| 4 | Following DX Lead Discuss & Operations - 14-02_30-07-2026.m4a | 8m45s | 0.1348 | -70.28 | -25.65 |
| 5 | [Daily] UApp - 09-58_31-07-2026.m4a | 14m26s | 0.2324 | -69.51 | -25.16 |

The 5 lowest of any duration:

| rank | file | duration | speechRatio |
|---|---|---|---|
| 1 | DX DSD - Design Operations - 16-00_07-08-2026.m4a | 0m15s | 0.0000 |
| 2 | [Knowledge Transfer] Overview Bond & Corp Bond - 15-00_02-06-2026.m4a | 0m12s | 0.0000 |
| 3 | [Sync] Design Principles - 14-00_20-07-2026.m4a | 0m22s | 0.0000 |
| 4 | [UApp] Sync Onboarding with P'Pop - 14-58_22-07-2026.m4a | 0m12s | 0.0000 |
| 5 | DX Lead Discuss & Operations - 14-00_23-07-2026.m4a | 1m18s | 0.0129 |

## 5. Runtime and failures

Runtime: 6 min 52 s wall (567 s user, 502 s sys) for 344 files, serial, `python3 -I scripts/speech_ratio.py <dir>`. Track counts across all 348 `.m4a` by ffprobe: 313 with 2 audio tracks, 26 with 1, 9 with 0.

Failed to decode (6; ffprobe 'moov atom not found', 0 audio streams):

- DX Lead Discuss & Operations_16-08_31-08-2026.m4a
- DX Squad Lead Sync Up_16-51_26-08-2026.m4a
- Design Principle Skill MD_14-04_11-09-2026.m4a
- PT Design System_10-18_02-09-2026.m4a
- [DX Roundtable] Aug 2026_16-09_28-08-2026.m4a
- [UApp] Weekly Update_16-30_11-08-2026.m4a

Skipped by name (4; not measured):

- INCOMPLETE_14-01_28-09-2026.m4a
- INCOMPLETE_14-03_26-06-2026.m4a
- INCOMPLETE_16-59_28-05-2026.m4a
- [Gold wallet] Internal Sync up - Entry point WFO - 14-01_28-09-2026 (recovered).m4a

Not measured, out of scope: 5 `.mp3` files in the folder (e.g. `6CP Class Part 1 - min.mp3`).

## Caveats

- The spec says 352 recordings; the folder has 353 entries (348 m4a + 5 mp3), of which 338 were measured.
- Name class is taken from the file name only; no calendar or log lookup was done to confirm how a name was assigned.
- The 2-track mix is not clipped to [-1, 1]; clipping does not change frames near -40 dBFS.
- Full per-file CSV: rerun `python3 -I scripts/speech_ratio.py "$HOME/Documents/Teams Recording" > out.csv`.

---

## Cutoff sensitivity: -40 vs -45 vs -50 dBFS (requested 2026-10-08)

Same algorithm, only the frame cutoff changed (`python3 -I scripts/speech_ratio.py --cutoff -45|-50 <dir>`; default stays -40). Same 338 files as above; two runs in parallel, 8 min 33 s wall each. The -40 results are the section 1-5 numbers above. Two new files appeared in the folder between runs (`Teams Call (Short) - 15-56_08-10-2026.m4a`, `Teams Call (Short) - 15-57_08-10-2026.m4a`); they are excluded here so all three cutoffs cover identical files. Decode failures and skips are the same 6 and 4 as above. Spot check: `Weekly Sync 26 Aug 2026.m4a` at -40 re-ran to 0.022144, identical to the first run.

'Empty' reference set = the 4 Named files that scored exactly 0.0000 at -40 (all 12 to 22 s). 'Real >= 180 s' = Named files with duration >= 180 s (n = 294).

### Empty-reference files and the two long quiet meetings, by cutoff

| file | duration | ratio at -40 | ratio at -45 | ratio at -50 |
|---|---|---|---|---|
| DX DSD - Design Operations - 16-00_07-08-2026.m4a | 0m15s | 0.0000 | 0.0000 | 0.1765 |
| [Knowledge Transfer] Overview Bond & Corp Bond - 15-00_02-06-2026.m4a | 0m12s | 0.0000 | 0.0000 | 0.0000 |
| [Sync] Design Principles - 14-00_20-07-2026.m4a | 0m22s | 0.0000 | 0.0047 | 0.0047 |
| [UApp] Sync Onboarding with P'Pop - 14-58_22-07-2026.m4a | 0m12s | 0.0000 | 0.0000 | 0.0000 |
| Weekly Sync 26 Aug 2026.m4a | 1h06m23s | 0.0221 | 0.2005 | 0.9643 |
| UApp Requirement & Refinement - 15-13_02-07-2026.m4a | 1h54m11s | 0.0233 | 0.1108 | 0.3437 |

### Cutoff -40 dBFS

Bin table (338 files):

| speechRatio bin | files | Short | Unnamed | Named |
|---|---|---|---|---|
| 0 - 0.01 | 4 | 0 | 0 | 4 |
| 0.01 - 0.02 | 3 | 0 | 0 | 3 |
| 0.02 - 0.05 | 10 | 0 | 0 | 10 |
| 0.05 - 0.10 | 6 | 0 | 0 | 6 |
| 0.10 - 0.20 | 3 | 1 | 0 | 2 |
| 0.20 - 0.50 | 175 | 2 | 1 | 172 |
| 0.50 - 1.00 | 137 | 5 | 3 | 129 |

Files with ratio < 0.10 (23):

| file | duration | ratio | class |
|---|---|---|---|
| DX DSD - Design Operations - 16-00_07-08-2026.m4a | 0m15s (15s) | 0.0000 | Named |
| [Knowledge Transfer] Overview Bond & Corp Bond - 15-00_02-06-2026.m4a | 0m12s (12s) | 0.0000 | Named |
| [Sync] Design Principles - 14-00_20-07-2026.m4a | 0m22s (22s) | 0.0000 | Named |
| [UApp] Sync Onboarding with P'Pop - 14-58_22-07-2026.m4a | 0m12s (12s) | 0.0000 | Named |
| DX Lead Discuss & Operations - 14-00_23-07-2026.m4a | 1m18s (78s) | 0.0129 | Named |
| [Sync] Design Principles - 15-04_02-09-2026.m4a | 0m22s (22s) | 0.0137 | Named |
| [Daily] Paotang Investment - 09-43_15-06-2026.m4a | 1m10s (70s) | 0.0186 | Named |
| Weekly Sync 26 Aug 2026.m4a | 1h06m23s (3983s) | 0.0221 | Named |
| [Daily] UApp - 09-57_21-09-2026.m4a | 1m11s (71s) | 0.0225 | Named |
| DX DSD - Design Operations - 16-02_24-07-2026.m4a | 1m10s (70s) | 0.0228 | Named |
| UApp Requirement & Refinement - 15-13_02-07-2026.m4a | 1h54m11s (6851s) | 0.0233 | Named |
| [Gold Wallet] UXUI Multiday (Design Update) - 15-59_27-05-2026.m4a | 1m10s (70s) | 0.0298 | Named |
| [Daily] Paotang Investment - 14-33_08-10-2026.m4a | 0m15s (15s) | 0.0392 | Named |
| [UApp] Monday Weekly Update - 10-59_06-07-2026.m4a | 0m12s (12s) | 0.0400 | Named |
| [One on One] Pop - Mee - 15-00_01-09-2026.m4a | 0m34s (34s) | 0.0442 | Named |
| DX Lead Discuss & Operations - 13-30_25-08-2026.m4a | 1m14s (74s) | 0.0448 | Named |
| DX Lead Discuss & Operations - 16-02_31-08-2026.m4a | 0m12s (12s) | 0.0488 | Named |
| DX DSD - Design Operations - 16-42_12-06-2026.m4a | 0m15s (15s) | 0.0584 | Named |
| DX DSD - Design Operations - 16-06_07-08-2026.m4a | 0m12s (12s) | 0.0656 | Named |
| Design Principle Skill Review.m4a | 1h26m10s (5170s) | 0.0726 | Named |
| DX DSD - Design Operations - 16-49_12-06-2026.m4a | 0m31s (31s) | 0.0754 | Named |
| DX Lead Discuss & Operations - 16-03_31-08-2026.m4a | 0m12s (12s) | 0.0894 | Named |
| test - 18-39_25-05-2026.m4a | 0m15s (15s) | 0.0974 | Named |

Thresholds (file moves when ratio < threshold; Short files are exempt under FR-VAD-003 but counted in 'moved overall' as flagged by the metric):

| threshold | moved overall | of which >= 180 s | >= 180 s and Named (real meeting) | >= 180 s and Short/Unnamed |
|---|---|---|---|---|
| 0.01 | 4 | 0 | 0 | 0 |
| 0.02 | 7 | 0 | 0 | 0 |
| 0.05 | 17 | 2 | 2 | 0 |

### Cutoff -45 dBFS

Bin table (338 files):

| speechRatio bin | files | Short | Unnamed | Named |
|---|---|---|---|---|
| 0 - 0.01 | 4 | 0 | 0 | 4 |
| 0.01 - 0.02 | 1 | 0 | 0 | 1 |
| 0.02 - 0.05 | 4 | 0 | 0 | 4 |
| 0.05 - 0.10 | 6 | 0 | 0 | 6 |
| 0.10 - 0.20 | 8 | 1 | 0 | 7 |
| 0.20 - 0.50 | 126 | 1 | 1 | 124 |
| 0.50 - 1.00 | 189 | 6 | 3 | 180 |

Files with ratio < 0.10 (15):

| file | duration | ratio | class |
|---|---|---|---|
| DX DSD - Design Operations - 16-00_07-08-2026.m4a | 0m15s (15s) | 0.0000 | Named |
| [Knowledge Transfer] Overview Bond & Corp Bond - 15-00_02-06-2026.m4a | 0m12s (12s) | 0.0000 | Named |
| [UApp] Sync Onboarding with P'Pop - 14-58_22-07-2026.m4a | 0m12s (12s) | 0.0000 | Named |
| [Sync] Design Principles - 14-00_20-07-2026.m4a | 0m22s (22s) | 0.0047 | Named |
| DX Lead Discuss & Operations - 14-00_23-07-2026.m4a | 1m18s (78s) | 0.0155 | Named |
| [Daily] UApp - 09-57_21-09-2026.m4a | 1m11s (71s) | 0.0351 | Named |
| [Gold Wallet] UXUI Multiday (Design Update) - 15-59_27-05-2026.m4a | 1m10s (70s) | 0.0397 | Named |
| [Daily] Paotang Investment - 09-43_15-06-2026.m4a | 1m10s (70s) | 0.0429 | Named |
| [UApp] Monday Weekly Update - 10-59_06-07-2026.m4a | 0m12s (12s) | 0.0480 | Named |
| DX DSD - Design Operations - 16-02_24-07-2026.m4a | 1m10s (70s) | 0.0513 | Named |
| [Daily] Paotang Investment - 14-33_08-10-2026.m4a | 0m15s (15s) | 0.0523 | Named |
| [One on One] Pop - Mee - 15-00_01-09-2026.m4a | 0m34s (34s) | 0.0531 | Named |
| DX DSD - Design Operations - 16-42_12-06-2026.m4a | 0m15s (15s) | 0.0714 | Named |
| DX DSD - Design Operations - 16-06_07-08-2026.m4a | 0m12s (12s) | 0.0738 | Named |
| DX DSD - Design Operations - 16-49_12-06-2026.m4a | 0m31s (31s) | 0.0918 | Named |

Thresholds (file moves when ratio < threshold; Short files are exempt under FR-VAD-003 but counted in 'moved overall' as flagged by the metric):

| threshold | moved overall | of which >= 180 s | >= 180 s and Named (real meeting) | >= 180 s and Short/Unnamed |
|---|---|---|---|---|
| 0.01 | 4 | 0 | 0 | 0 |
| 0.02 | 5 | 0 | 0 | 0 |
| 0.05 | 9 | 0 | 0 | 0 |

### Cutoff -50 dBFS

Bin table (338 files):

| speechRatio bin | files | Short | Unnamed | Named |
|---|---|---|---|---|
| 0 - 0.01 | 3 | 0 | 0 | 3 |
| 0.01 - 0.02 | 0 | 0 | 0 | 0 |
| 0.02 - 0.05 | 2 | 0 | 0 | 2 |
| 0.05 - 0.10 | 5 | 0 | 0 | 5 |
| 0.10 - 0.20 | 4 | 1 | 0 | 3 |
| 0.20 - 0.50 | 103 | 0 | 1 | 102 |
| 0.50 - 1.00 | 221 | 7 | 3 | 211 |

Files with ratio < 0.10 (10):

| file | duration | ratio | class |
|---|---|---|---|
| [Knowledge Transfer] Overview Bond & Corp Bond - 15-00_02-06-2026.m4a | 0m12s (12s) | 0.0000 | Named |
| [UApp] Sync Onboarding with P'Pop - 14-58_22-07-2026.m4a | 0m12s (12s) | 0.0000 | Named |
| [Sync] Design Principles - 14-00_20-07-2026.m4a | 0m22s (22s) | 0.0047 | Named |
| DX Lead Discuss & Operations - 14-00_23-07-2026.m4a | 1m18s (78s) | 0.0206 | Named |
| [Gold Wallet] UXUI Multiday (Design Update) - 15-59_27-05-2026.m4a | 1m10s (70s) | 0.0496 | Named |
| [Daily] UApp - 09-57_21-09-2026.m4a | 1m11s (71s) | 0.0604 | Named |
| [One on One] Pop - Mee - 15-00_01-09-2026.m4a | 0m34s (34s) | 0.0619 | Named |
| DX DSD - Design Operations - 16-42_12-06-2026.m4a | 0m15s (15s) | 0.0909 | Named |
| [Daily] Paotang Investment - 09-43_15-06-2026.m4a | 1m10s (70s) | 0.0929 | Named |
| DX DSD - Design Operations - 16-49_12-06-2026.m4a | 0m31s (31s) | 0.0984 | Named |

Thresholds (file moves when ratio < threshold; Short files are exempt under FR-VAD-003 but counted in 'moved overall' as flagged by the metric):

| threshold | moved overall | of which >= 180 s | >= 180 s and Named (real meeting) | >= 180 s and Short/Unnamed |
|---|---|---|---|---|
| 0.01 | 3 | 0 | 0 | 0 |
| 0.02 | 3 | 0 | 0 | 0 |
| 0.05 | 5 | 0 | 0 | 0 |

### Margin: highest-ratio empty file vs lowest-ratio real meeting >= 180 s

| cutoff | highest empty-file ratio | lowest real >= 180 s ratio | absolute margin | lowest real >= 180 s file | duration |
|---|---|---|---|---|---|
| -40 | 0.0000 | 0.0221 | 0.0221 | Weekly Sync 26 Aug 2026.m4a | 1h06m23s |
| -45 | 0.0047 | 0.1108 | 0.1061 | UApp Requirement & Refinement - 15-13_02-07-2026.m4a | 1h54m11s |
| -50 | 0.1765 | 0.2305 | 0.0541 | Following DX Lead Discuss & Operations - 14-02_30-07-2026.m4a | 8m45s |

Largest absolute margin: cutoff -45 dBFS (0.1061). Margin is computed only from the 4 empty-reference files, which were selected by their -40 score.


### Lowest real (Named, >= 180 s) files per cutoff, for context

| cutoff | lowest five, ratio (duration) |
|---|---|
| -40 | Weekly Sync 26 Aug 2026 0.0221 (66m); UApp Requirement & Refinement 0.0233 (114m); Design Principle Skill Review 0.0726 (86m); Following DX Lead Discuss & Operations - 14-02_30-07-2026 0.1348 (9m); [Daily] UApp - 09-58_31-07-2026 0.2324 (14m) |
| -45 | UApp Requirement & Refinement 0.1108 (114m); Following DX Lead ... 14-02_30-07-2026 0.1807 (9m); Weekly Sync 26 Aug 2026 0.2005 (66m); Design Principle Skill Review 0.2363 (86m); [Daily] UApp - 09-58_31-07-2026 0.2684 (14m) |
| -50 | Following DX Lead ... 14-02_30-07-2026 0.2305 (9m); [Daily] UApp - 09-58_31-07-2026 0.2911 (14m); [Sync] Design Principles - 11-02_23-07-2026 0.3182 (40m); [Daily] UApp - 09-59_28-09-2026 0.3184 (34m); [Daily] UApp - 10-01_11-09-2026 0.3194 (9m) |

### Recommendation

**Cutoff -45 dBFS, threshold 0.05.**

- At -45 the empty-reference files score 0.0000, 0.0000, 0.0000 and 0.0047; the lowest real meeting >= 180 s scores 0.1108. The gap is 0.1061, the largest of the three cutoffs (-40: 0.0221; -50: 0.0541). Threshold 0.05 sits 0.0453 above the highest empty file and 0.0608 below the lowest real meeting.
- At -45 with threshold 0.05: 9 files move, 0 are >= 180 s, 0 real meetings >= 180 s move. At -40 the same threshold moves 2 real meetings >= 180 s (66 min and 114 min).
- At -50 one of the four empty-reference files (`DX DSD - Design Operations - 16-00_07-08-2026.m4a`, 15 s) scores 0.1765, so -50 no longer separates it from real meetings; the other three stay at 0.0000, 0.0000, 0.0047.
- Threshold 0.10 at -45 is not recommended: the lowest real meeting is 0.1108, a 0.0108 margin, and it is a single file.

Limits of this evidence:
- The empty reference is 4 files of 12 to 22 s, chosen because they scored 0 at -40. No file was listened to. The margin is measured against those 4 only.
- At -45, all 9 files under 0.05 are shorter than 180 s and carry real-meeting names (ratios 0.0000 to 0.0480 in the -45 table above). Whether they contain speech is not settled by these numbers; the three 0.0000 files and `UApp Requirement & Refinement` (0.1108) are the ones worth a listen.
- The conclusion rests on one file for the real-side minimum (`UApp Requirement & Refinement - 15-13_02-07-2026.m4a`, 0.1108 at -45).
- `kSpeechMinRatio` and the Swift cutoff constant must both change together; the spec text (-40, 0.05) is not updated by this run.
