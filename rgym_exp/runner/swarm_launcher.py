#!/usr/bin/env python3

import os
import sys

# 强制禁用CUDA和GPU检测
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["CUDA_DEVICE_ORDER"] = ""
os.environ["CUDA_LAUNCH_BLOCKING"] = ""
os.environ["PYTORCH_CUDA_ALLOC_CONF"] = ""
os.environ["CPU_ONLY"] = "1"
os.environ["USE_CPU"] = "1"
os.environ["PYTORCH_NO_CUDA_MEMORY_CACHING"] = "1"
os.environ["FORCE_CUDA"] = "0"
os.environ["CUDA_HOME"] = ""

# 在导入torch之前设置
import torch
torch.cuda.is_available = lambda: False
torch.cuda.device_count = lambda: 0

import hydra
from genrl.communication.communication import Communication
from genrl.communication.hivemind.hivemind_backend import (
    HivemindBackend,
    HivemindRendezvouz,
)
from hydra.utils import instantiate
from omegaconf import DictConfig, OmegaConf

from rgym_exp.src.utils.omega_gpu_resolver import (
    gpu_model_choice_resolver,
)  # necessary for gpu_model_choice resolver in hydra config


@hydra.main(version_base=None)
def main(cfg: DictConfig):
    is_master = False
    HivemindRendezvouz.init(is_master=is_master)

    game_manager = instantiate(cfg.game_manager)
    game_manager.run_game()


if __name__ == "__main__":
    os.environ["HYDRA_FULL_ERROR"] = "1"
    Communication.set_backend(HivemindBackend)
    main()
