"""
Wrapper Demucs : remplace torchaudio.save par soundfile avant l'import de Demucs.
torchaudio >= 2.6 exige torchcodec (DLL indisponible sur certains Windows) ;
ce script court-circuite ce backend problématique.
"""
import sys
import numpy as np
import soundfile as sf
import torchaudio

def _save_via_soundfile(filepath, wav, sample_rate, **kwargs):
    # wav : Tensor [channels, samples]  ou  [1, channels, samples]
    data = wav.squeeze(0)                     # → [channels, samples]
    if data.ndim == 2:
        data = data.T                         # → [samples, channels]
    sf.write(str(filepath), data.numpy(), sample_rate)

# Patch avant tout import de Demucs
torchaudio.save = _save_via_soundfile

from demucs.separate import main
sys.exit(main())
