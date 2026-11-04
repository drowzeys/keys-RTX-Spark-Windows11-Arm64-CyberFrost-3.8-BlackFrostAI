# Credits

This repository is a packaging and measurement of other people's work. Thank you to all of them.

| Who | What we used | Licence |
|---|---|---|
| **Blackfrost-AI** | The model: [CYBER-FROST-3.8-FP4-Local](https://huggingface.co/Blackfrost-AI/CYBER-FROST-3.8-FP4-Local) (revision `15c68d90`), its security fine-tune, FP4-Local re-export, chat template and model card | Qwen Community License 1.0 (`licenses/model-LICENSE.txt`) |
| **Qwen team** | The foundation model, [Qwen3.8-Flash-Next](https://huggingface.co/Qwen/Qwen3.8-Flash-Next), its architecture, tokenizer and licence | Qwen Community License 1.0 |
| **Ash Hart** ([github.com/ashhart](https://github.com/ashhart)) and the engine's contributors | The inference engine, built unmodified from its v1.2.2 release (commit `00e7ddd`) for Windows ARM64 / sm_121, including its CSF-scale NVFP4 kernels, multi-token-prediction drafts and OpenAI-compatible server | Apache-2.0 (`licenses/engine-LICENSE.txt`, `engine-NOTICE.txt`, `engine-THIRD_PARTY_NOTICES.md`, `engine-LICENSES/`) |
| **Victor Cruz (vicruz, [vcruz305](https://github.com/vcruz305))** | The benchmark client in `bench/` (`bench_v1.py`, `concurrency.py`, `api_client.py`) from [Qwen3.8-Flash-Next-EXL3-DGX-Spark-recipe](https://github.com/vcruz305/Qwen3.8-Flash-Next-EXL3-DGX-Spark-recipe) @ `49850ef`, and the EXL3 recipe we ran as the baseline | MIT (`bench/LICENSE-vcruz305-MIT.txt`) |
| **NVIDIA** | The FP4-Local checkpoint format and compressed-scale (CSF) codec the model follows ([nvidia/Qwen3.8-Flash-Next-FP4-Local](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-FP4-Local)); CUDA 13.4 toolkit used to build; the RTX Spark platform and driver | NVIDIA licences (nothing of NVIDIA's is redistributed here) |
| **MiaAI-Lab** and the other projects listed in the engine's third-party notices | Parts of the engine (see `licenses/engine-THIRD_PARTY_NOTICES.md`) | as listed there |
| **turboderp** (ExLlamaV3) and **theroyallab** (TabbyAPI) | The EXL3 baseline engine and server we compared against | MIT / AGPL-3.0 (not redistributed) |
| **Zig** project | Zig 0.17 compiler used to build the engine | MIT |
| **Microsoft** | Visual Studio 2022 Build Tools (ARM64), Windows 11 on ARM, Windows' `curl.exe` used by the one-shot | Microsoft licences (not redistributed) |
| **HP** | The OmniBook X 14 RTX Spark N1X laptop the numbers come from | |

Put together by keys ([drowzeys](https://github.com/drowzeys)).
