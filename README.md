# CYBER-FROST-3.8 on the NVIDIA RTX Spark: native Windows 11 ARM64, one shot

Run **[Blackfrost-AI's CYBER-FROST-3.8-FP4-Local](https://huggingface.co/Blackfrost-AI/CYBER-FROST-3.8-FP4-Local)**,
a security-tuned [Qwen3.8-Flash-Next](https://huggingface.co/Qwen/Qwen3.8-Flash-Next) model, on an NVIDIA RTX Spark laptop
natively on Windows 11 ARM64: no WSL, no Docker, no CUDA toolkit. One PowerShell command gets you an
OpenAI-compatible endpoint your agent can use.

```powershell
git clone https://github.com/drowzeys/keys-RTX-Spark-Windows11-Arm64-CyberFrost-3.8-BlackFrostAI
cd keys-RTX-Spark-Windows11-Arm64-CyberFrost-3.8-BlackFrostAI
powershell -ExecutionPolicy Bypass -File .\oneshot.ps1
```

Or hand it to your agent: **"Read AGENTS.md in this repo and set it up."** [AGENTS.md](AGENTS.md) walks an agent
through install, connection and day-to-day use.

## Performance

HP OmniBook X 14, NVIDIA RTX Spark N1X (128 GB), driver 617.21, Windows 11 ARM64 on the Balanced power plan.
Served with `--context 32768 --parallel 4`, thinking off, greedy. Client tokens per second include drafting
and all overheads (what your agent sees), not a decode-only clock.

| Measure | Native Windows 11 ARM64 |
|---|---:|
| Single request, code / devops / prose (tok/s) | **42.7-51.2 / 41.2-42.2 / 38.1-39.3** |
| Time to first token, short prompt | 0.24-0.26 s |
| 17,876-token prompt: time to first token | 10.6 s |
| 17,876-token prompt: tok/s including prefill | 14.2 |
| 1 / 2 / 4 requests at once, total tok/s | **39.5 / 55.4 / 70.7** |
| Load time (model on internal NVMe, warm) | 31.4 s |
| GPU while generating | ~2,160 MHz, ~44 W |
| Failed requests | 0 |

Single-request ranges are two runs with different prompt salts (the client's `--run-id`): greedy output differs
slightly with the salt, and so does how many drafted tokens are accepted, mostly on code.

Compared on the same laptop and model:

| Same laptop, same model | Native Windows (this repo) | Same engine in WSL | EXL3 3.87 bpw in WSL |
|---|---:|---:|---:|
| Single request, code / devops / prose (tok/s) | **42.7-51.2 / 41.2-42.2 / 38.1-39.3** | 43.8 / 42.2 / 35.7 | 36.2 / 30.0 / 26.0 |
| Time to first token, short prompt | **0.24-0.26 s** | 0.21-0.24 s | 0.81-0.84 s |
| ~17.9K-token prompt, time to first token | **10.6 s** | 10.2 s | 20.3 s |
| 1 / 2 / 4 requests at once, total tok/s | **39.5 / 55.4 / 70.7** | 36.4 / 50.2 / 65.6 | 29.9 / 34.2 / 35.4 |

- **Native vs WSL:** same engine source; native Windows sees the full ~113 GB GPU memory pool (WSL sees 96 GB)
  and is faster under load (4 requests: 70.7 vs 65.6 tok/s); single-request and first-token times are within run-to-run noise. WSL also needed an engine patch for its memory accounting; native needs none.
- **vs EXL3:** the EXL3 baseline is a 3.87 bpw EXL3 quant of the same Cyber-Frost weights, run with
  [vicruz's Qwen3.8-Flash-Next EXL3 recipe](https://github.com/vcruz305/Qwen3.8-Flash-Next-EXL3-DGX-Spark-recipe)
  (ExLlamaV3 `bccada04` + TabbyAPI) under WSL, measured with the same client.
- **DGX Spark reference:** Blackfrost-AI's model card reports 47-53 tok/s single-stream *decode* on a DGX Spark
  (GB10). That's a decode-only clock, so it isn't directly comparable with the client numbers above.

Raw JSON for every run is in [`perf/`](perf/). Reproduce with the client in [`bench/`](bench/) (vicruz's, MIT):

```powershell
python bench\bench_v1.py --base-url http://127.0.0.1:8000/v1 --model cyberfrost --suite all --output single.json
python bench\concurrency.py conc 1,2,4 3000 400 3 --base-url http://127.0.0.1:8000/v1 --model cyberfrost --output conc.json
python bench\bench_v1.py --base-url http://127.0.0.1:8000/v1 --model cyberfrost --suite code --context-tokens 24000 --max-tokens 200 --repeat 2 --warmup 0 --output long.json
```

## What you need

- An NVIDIA **RTX Spark** with **128 GB** (the weights alone are 95 GiB), Windows 11 ARM64.
- The NVIDIA driver with **CUDA 13** (`nvidia-smi` shows "CUDA Version: 13.x"). Nothing else: the engine is a single
  self-contained exe.
- About **100 GB free disk** for the model (`-ModelDir` can point at another drive).

## What the one-shot does

1. Checks the machine (ARM64, RTX Spark, CUDA 13 driver, memory, disk).
2. Downloads the prebuilt engine, `cyberfrost-engine-win-arm64-sm121.zip`, from this repo's
   [release](../../releases/tag/v1.0.0) and checks its SHA-256.
3. Downloads the model from Hugging Face at pinned revision `15c68d90`, resumable, and checks each large file's
   SHA-256 against the Hub's record.
4. Writes `start.cmd`, `stop.cmd` and `status.cmd` to `%LOCALAPPDATA%\CyberFrostRTX`, starts the server, waits for
   it and sends a test request.
5. Prints the endpoint, `http://127.0.0.1:8000/v1` with model `cyberfrost`, and saves it to `agent-endpoint.json`.

Options: `-ModelDir`, `-SkipModel` (already downloaded), `-Port`, `-Context`, `-Parallel`, `-Thinking`,
`-Lan -ApiKey <secret>` (serve on your network), `-NoStart`. See the top of [`oneshot.ps1`](oneshot.ps1).

## The prebuilt engine

The engine is Ash Hart's Apache-2.0 inference engine, built unmodified from its v1.2.2 release for Windows ARM64
and sm_121 with Zig 0.17, CUDA 13.4 and Visual Studio 2022 Build Tools, then renamed `cyberfrost-engine.exe`.
It needs only the NVIDIA driver at run time. Build details and the exe's SHA-256 are in the zip's `BUILD-INFO.txt`;
the engine's licence, NOTICE and third-party notices are in [`licenses/`](licenses/) and in the zip.

Known limit: the optional structured-output library isn't included, so requests that *force* a tool call
(`tool_choice: "required"`) or a JSON schema get HTTP 400. Normal tool calling (`"auto"`) works.

## Responsible use

Cyber-Frost is built for **authorized** security research, assessment, engineering and response work, and is
described by its authors as a public research release under active quality assessment. Read the
[model card](https://huggingface.co/Blackfrost-AI/CYBER-FROST-3.8-FP4-Local) before use. The model is under the
Qwen Community License 1.0 ([`licenses/model-LICENSE.txt`](licenses/model-LICENSE.txt)); this repository
doesn't redistribute the weights, it downloads them from Blackfrost-AI's repository.

## Credits

- **Blackfrost-AI**: the CYBER-FROST-3.8 model and its FP4-Local release.
- **Qwen team**: Qwen3.8-Flash-Next, the foundation model.
- **Ash Hart** and contributors: the inference engine (Apache-2.0).
- **Victor Cruz (vicruz)**: the benchmark client and the EXL3 recipe used as the baseline.
- **NVIDIA**: the FP4-Local format and CSF codec, CUDA, and the RTX Spark.
- Plus ExLlamaV3, TabbyAPI, Zig, Microsoft and HP: see [CREDITS.md](CREDITS.md) for everything used.

The engine's maintainers aren't affiliated with this repository and haven't endorsed or tested this model.

This repository's own scripts and docs are MIT ([LICENSE](LICENSE)).
