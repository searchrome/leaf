"""Leaf's private Kokoro worker. stdout is JSON lines; diagnostics go to stderr."""
import base64
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import time

MODEL = "mlx-community/Kokoro-82M-bf16"
REVISION = "a71e4d38b236d968966a2002c4c895dbd12b1c3c"
SAMPLE = "Welcome to Leaf. Find a comfortable place, open a good book, and let me read to you."


def load_model(root):
    # Supply a bundled eSpeak library so English phonemization needs no system install
    # or network fallback. No third-party text/audio server is started.
    import espeakng_loader
    from phonemizer.backend.espeak.wrapper import EspeakWrapper
    EspeakWrapper.set_library(espeakng_loader.get_library_path())
    from kokoro_mlx import KokoroTTS
    return KokoroTTS.from_pretrained(root / "model")


def synthesize(tts, text, voice):
    import numpy as np
    import soundfile as sf
    if not text.strip() or len(text) > 20000:
        raise ValueError("The local speech passage is empty or too long.")
    if voice not in tts.list_voices() or voice[:2] not in ("af", "am", "bf", "bm"):
        raise ValueError("Choose an installed English Kokoro voice.")
    started = time.monotonic()
    result = tts.generate(text, voice=voice, sample_rate=24000)
    if result.duration <= 0 or not np.isfinite(result.audio).all() or np.max(np.abs(result.audio)) < 0.0001:
        raise ValueError("Kokoro did not generate usable audio.")
    audio = io.BytesIO()
    sf.write(audio, result.audio, result.sample_rate, format="WAV", subtype="PCM_16")
    return audio.getvalue(), result.duration, time.monotonic() - started


def install(root):
    from huggingface_hub import snapshot_download
    snapshot_download(MODEL, revision=REVISION, local_dir=root / "model", allow_patterns=[
        "config.json", "kokoro-v1_0.safetensors", "voices/af_*.safetensors",
        "voices/am_*.safetensors", "voices/bf_*.safetensors", "voices/bm_*.safetensors",
        "README.md", "VOICES.md", "LICENSE*",
    ])
    os.environ["HF_HUB_OFFLINE"] = "1"
    tts = load_model(root)
    # Exercise both phonemizers and validate audible output before declaring ready.
    synthesize(tts, "A little room for a good book.", "bf_emma")
    synthesize(tts, "Hello from Leaf.", "af_heart")
    _, duration, elapsed = synthesize(tts, SAMPLE, "af_heart")
    report = {"version": 1, "revision": REVISION, "voices": tts.list_voices(),
              "audioSeconds": duration, "generationSeconds": elapsed}
    temp = root / "ready.tmp"
    temp.write_text(json.dumps(report))
    temp.replace(root / "ready.json")
    return report


def serve(root):
    with contextlib.redirect_stdout(sys.stderr):
        tts = load_model(root)
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            with contextlib.redirect_stdout(sys.stderr):
                audio, _, _ = synthesize(tts, request["text"], request["voice"])
            response = {"id": request["id"], "audio": base64.b64encode(audio).decode("ascii")}
        except Exception as error:
            response = {"id": request.get("id", ""), "error": str(error)}
        print(json.dumps(response), flush=True)


if __name__ == "__main__":
    root = Path(sys.argv[2])
    try:
        if sys.argv[1] == "install":
            with contextlib.redirect_stdout(sys.stderr):
                report = install(root)
            print(json.dumps(report), flush=True)
        else:
            serve(root)
    except Exception as error:
        print(str(error), file=sys.stderr, flush=True)
        sys.exit(1)
