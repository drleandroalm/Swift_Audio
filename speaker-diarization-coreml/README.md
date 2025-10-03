---
license: apache-2.0
tags:
- speech
- audio
- voice
- speaker-diarization
- speaker-change-detection
- coreml
- speaker-segmentation
base_model:
- pyannote/speaker-diarization-3.1
- pyannote/wespeaker-voxceleb-resnet34-LM
pipeline_tag: voice-activity-detection
---


# **<span style="color:#5DAF8D">🧃 Speaker Diarization CoreML </span>**
[![Discord](https://img.shields.io/badge/Discord-Join%20Chat-7289da.svg)](https://discord.gg/WNsvaCtmDe)
[![GitHub Repo stars](https://img.shields.io/github/stars/FluidInference/FluidAudio?style=flat&logo=github)](https://github.com/FluidInference/FluidAudio)

Speaker diarization based on [pyannote ](https://github.com/pyannote) models optimized for Apple Neural Engine.

Models are trained on acoustic signatures so it supports any lanugage.

## Usage

See the SDK for more details [https://github.com/FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio)

### Technical Specifications
- **Input**: 16kHz mono audio
- **Output**: Speaker segments with timestamps and IDs
- **Framework**: CoreML (converted from PyTorch)
- **Optimization**: Apple Neural Engine (ANE) optimized operations
- **Precision**: FP32 on CPU/GPU, FP16 on ANE


## Performance

See the [origianl model](https://huggingface.co/pyannote/speaker-diarization-community-1) for detailed DER benchmark, for the purpose of our conversion, we tried to match the original model as much as possible: 

The models on CoreML exhibit a ~10x Speedup on CPU and ~20x speed up on GPU. 

![plots/pipeline_timing.png](plots/pipeline_timing.png)

Due to different precisions, there are minor differences in the values generated but the differences are mostly negilible, though it does account for some errors that needs to be adjusted during clustering:

![plots/metrics_timeseries.png](plots/metrics_timeseries.png)


We see this when running the end to end pipeline with the Pytorch model versus the Core ML model (patched the Pyannote pipeline to run the Core ML model instead)
![plots/pipeline_overview.png](plots/pipeline_overview.png)



## Citations (from original model)

1. Speaker segmentation model

```bibtex
@inproceedings{Plaquet23,
  author={Alexis Plaquet and Hervé Bredin},
  title={{Powerset multi-class cross entropy loss for neural speaker diarization}},
  year=2023,
  booktitle={Proc. INTERSPEECH 2023},
}
```

2. Speaker embedding model

```bibtex
@inproceedings{Wang2023,
  title={Wespeaker: A research and production oriented speaker embedding learning toolkit},
  author={Wang, Hongji and Liang, Chengdong and Wang, Shuai and Chen, Zhengyang and Zhang, Binbin and Xiang, Xu and Deng, Yanlei and Qian, Yanmin},
  booktitle={ICASSP 2023, IEEE International Conference on Acoustics, Speech and Signal Processing (ICASSP)},
  pages={1--5},
  year={2023},
  organization={IEEE}
}
```


3. Speaker clustering

```bibtex
@article{Landini2022,
  author={Landini, Federico and Profant, J{\'a}n and Diez, Mireia and Burget, Luk{\'a}{\v{s}}},
  title={{Bayesian HMM clustering of x-vector sequences (VBx) in speaker diarization: theory, implementation and analysis on standard tasks}},
  year={2022},
  journal={Computer Speech \& Language},
}