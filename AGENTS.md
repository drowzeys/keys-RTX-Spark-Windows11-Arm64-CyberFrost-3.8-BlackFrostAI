# AGENTS.md: set this up for your user

You are an AI agent on an NVIDIA RTX Spark laptop (Windows 11 ARM64, 128 GB). Your user wants
Blackfrost-AI's **CYBER-FROST-3.8-FP4-Local** served on this machine as an OpenAI-compatible endpoint,
and then wants you (or another agent) to use it. Do this:

## 1. Run the one-shot

In PowerShell, from a clone or download of this repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\oneshot.ps1
```

What to expect:

| Step | Time | Notes |
|---|---|---|
| Machine checks | seconds | Stops if this isn't Windows ARM64, an RTX Spark, CUDA 13 driver, ~128 GB |
| Engine download (zip, SHA-256 checked) | under a minute | Installs to `%LOCALAPPDATA%\CyberFrostRTX` |
| Model download, 95.24 GiB | network-bound; ~15 min at 1 Gbit/s | Resumable: if it stops, run the same command again |
| SHA-256 of every large model file | ~5-10 min | Skipped on re-runs once a file has passed |
| Server load | ~1-3 min | |
| Test request | seconds | Prints `Test reply: cyberfrost ready` |

The script exits non-zero with a red `[cyberfrost]` line if anything fails. Read that line; most
failures say what to do (free disk, update driver, re-run to resume).

Useful options:

- `-ModelDir D:\models\CYBER-FROST-3.8-FP4-Local` put the 95 GiB on another drive.
- `-SkipModel` the model is already in `-ModelDir` (no download, no hashing).
- `-Port 8000 -Context 32768 -Parallel 4` serving settings (these defaults are what was benchmarked).
- `-Lan -ApiKey <secret>` serve to other machines on the network; always set a key with `-Lan`.
- `-Thinking` turn reasoning on (off by default: faster, and cleaner for tool-calling agents).

## 2. Connect

After success, `%LOCALAPPDATA%\CyberFrostRTX\agent-endpoint.json` holds:

```json
{ "provider": "openai-compatible", "base_url": "http://127.0.0.1:8000/v1", "model": "cyberfrost" }
```

Any OpenAI-compatible client works: set the base URL and model name above; the API key can be any
string unless `-ApiKey` was used. Check it with:

```powershell
curl.exe -s http://127.0.0.1:8000/v1/models
```

## 3. Day to day

- Start: `%LOCALAPPDATA%\CyberFrostRTX\start.cmd`
- Stop (frees ~100 GB of GPU memory): `%LOCALAPPDATA%\CyberFrostRTX\stop.cmd`
- Status: `%LOCALAPPDATA%\CyberFrostRTX\status.cmd`
- Log: `%LOCALAPPDATA%\CyberFrostRTX\server.log`

## Notes for agents

- The server holds about 100 GB of the shared memory while running. Stop it before your user runs other
  large GPU jobs, and don't run two copies.
- If you run the one-shot over SSH, Windows ends the server when the SSH session closes. Start it from a
  local session (or have the user double-click `start.cmd`) for a server that stays up.
- Use the power plan your user prefers; the published numbers were measured on Windows' Balanced plan.
- This model is for **authorized** security research, assessment, engineering and response work.
  Follow its [model card](https://huggingface.co/Blackfrost-AI/CYBER-FROST-3.8-FP4-Local) and the
  Qwen Community License in `licenses/`.
