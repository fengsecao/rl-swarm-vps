import os
import time
import json
import os
from collections import defaultdict

from genrl.blockchain import SwarmCoordinator
from genrl.communication import Communication
from genrl.communication.hivemind.hivemind_backend import HivemindBackend
from genrl.data import DataManager
from genrl.game import BaseGameManager
from genrl.game.game_manager import DefaultGameManagerMixin
from genrl.logging_utils.global_defs import get_logger
from genrl.logging_utils.system_utils import get_system_info
from genrl.rewards import RewardManager
from genrl.roles import RoleManager
from genrl.state import GameState
from genrl.trainer import TrainerModule
from huggingface_hub import login, whoami

from rgym_exp.src.utils.name_utils import get_name_from_peer_id
from rgym_exp.src.prg_module import PRGModule


class SwarmGameManager(BaseGameManager, DefaultGameManagerMixin):
    """GameManager that orchestrates a game using a SwarmCoordinator."""

    def __init__(
        self,
        coordinator: SwarmCoordinator,
        max_stage: int,
        max_round: int,
        game_state: GameState,
        reward_manager: RewardManager,
        trainer: TrainerModule,
        data_manager: DataManager,
        communication: Communication,
        role_manager: RoleManager | None = None,
        run_mode: str = "train",
        log_dir: str = "logs",
        hf_token: str | None = None,
        hf_push_frequency: int = 20,
        **kwargs,
    ):

        super().__init__(
            max_stage=max_stage,
            max_round=max_round,
            game_state=game_state,
            reward_manager=reward_manager,
            trainer=trainer,
            data_manager=data_manager,
            communication=communication,
            role_manager=role_manager,
            run_mode=run_mode,
        )

        assert isinstance(self.communication, HivemindBackend)
        self.train_timeout = 60 * 60 * 24 * 31  # 1 month

        # Logging Setup
        self.peer_id = self.communication.get_id()
        self.state.peer_id = self.peer_id
        self.animal_name = get_name_from_peer_id(self.peer_id, True)

        # Register peer_id and get current round from the chain
        self.coordinator = coordinator
        self.coordinator.register_peer(self.peer_id)
        round, _ = self.coordinator.get_round_and_stage()
        self.state.round = round

        self.communication.step_ = (
            self.state.round
        )  # initialize communication module to contract's round

        # enable push to HF if token was provided
        self.hf_token = hf_token
        if self.hf_token not in [None, "None"]:
            self._configure_hf_hub(hf_push_frequency)

        get_logger().info(
            f"🐱 Hello 🐈 [{get_name_from_peer_id(self.peer_id)}] 🦮 [{self.peer_id}]!"
        )
        get_logger().info(f"bootnodes: {kwargs.get('bootnodes', [])}")
        get_logger().info(f"Using Model: {self.trainer.model.config.name_or_path}")

        with open(os.path.join(log_dir, f"system_info.txt"), "w") as f:
            f.write(get_system_info())

        # 奖励持久化相关
        self.reward_save_file = os.path.join(log_dir, f"pending_rewards_{self.peer_id}.json")
        # 初始化奖励并尝试从文件加载未提交的奖励
        self.batched_signals = self._load_pending_rewards()
        self.time_since_submit = time.time()  # seconds
        # self.submit_period = 0.5  # hours  # 已废弃，使用submit_interval_minutes代替
        self.submitted_this_round = False
        self.min_reward_threshold = 1.0  # 最小奖励阈值，只有当累积奖励超过这个值时才提交
        self.submit_interval_minutes = 15  # 最小提交间隔（分钟）

        # PRG Game
        self.prg_module = PRGModule(log_dir, **kwargs)
        self.prg_game = self.prg_module.prg_game

    def _get_total_rewards_by_agent(self):
        rewards_by_agent = defaultdict(int)
        for stage in range(self.state.stage):
            rewards = self.rewards[stage]
            for agent_id, agent_rewards in rewards.items():
                for batch_id, batch_rewards in agent_rewards.items():
                    tot = 0
                    for generation_rewards in batch_rewards:
                        tot += sum(generation_rewards)
                    rewards_by_agent[agent_id] += tot

        return rewards_by_agent

    def _get_my_rewards(self, signal_by_agent):
        if len(signal_by_agent) == 0:
            return 1  # 即使没有其他智能体，也给予基础奖励
        if self.peer_id in signal_by_agent:
            my_signal = signal_by_agent[self.peer_id]
        else:
            my_signal = 0
        # 确保每轮至少获得1的基础奖励
        return max(my_signal, 1)

    def _try_submit_to_chain(self, signal_by_agent):
        elapsed_time_seconds = time.time() - self.time_since_submit
        elapsed_time_minutes = elapsed_time_seconds / 60
        
        # 只有当满足以下两个条件之一时才提交奖励：
        # 1. 时间间隔超过submit_interval_minutes，并且有奖励可以提交
        # 2. 累积奖励超过min_reward_threshold，以防止奖励长时间积累
        should_submit = (
            (elapsed_time_minutes >= self.submit_interval_minutes and self.batched_signals > 0) or
            (self.batched_signals >= self.min_reward_threshold)
        )
        
        if should_submit:
            try:
                # 提交累积的奖励信号
                reward_to_submit = int(max(self.batched_signals, 0))  # 确保奖励是非负的
                if reward_to_submit > 0:
                    self.coordinator.submit_reward(
                        self.state.round, 0, reward_to_submit, self.peer_id
                    )
                    self.batched_signals = 0.0
                    # 奖励提交成功后清空持久化存储
                    self._save_pending_rewards(0.0)
                     
                    # 提交获胜者
                    if len(signal_by_agent) > 0:
                        max_agent, max_signal = max(
                            signal_by_agent.items(), key=lambda x: x[1]
                        )
                        # 只在有明显优势时才提交获胜者
                        if max_signal > 0.5 * sum(signal_by_agent.values()):
                            self.coordinator.submit_winners(
                                self.state.round, [max_agent], self.peer_id
                            )
                    else:  # 如果没有其他智能体信号，就提交自己
                        self.coordinator.submit_winners(
                            self.state.round, [self.peer_id], self.peer_id
                        )
                     
                    self.time_since_submit = time.time()
                    self.submitted_this_round = True
            except Exception as e:
                get_logger().debug(str(e))

    def _hook_after_rewards_updated(self):
        signal_by_agent = self._get_total_rewards_by_agent()
        self.batched_signals += self._get_my_rewards(signal_by_agent)
        # 保存更新后的未提交奖励
        self._save_pending_rewards(self.batched_signals)
        self._try_submit_to_chain(signal_by_agent)

    def _hook_after_round_advanced(self):
        if self.prg_game:
            # TODO: Ideally I think the judge client request question bit should come in the manager and the trainer should be doing only PyTorch-y stuff, 
            # but I have kept it consistent with the evaluate function for now.
            prg_history_dict = self.prg_module.prg_history_dict
            results_dict = self.trainer.play_prg_game_logits(prg_history_dict)
            self.prg_module.play_prg_game(results_dict, self.peer_id)

        self._save_to_hf()

        # Try to submit to chain again if necessary, but don't update our signal twice
        if not self.submitted_this_round:
            signal_by_agent = self._get_total_rewards_by_agent()
            self._try_submit_to_chain(signal_by_agent)

        # Reset flag for next round
        self.submitted_this_round = False

        # Block until swarm round advances
        self.agent_block()

    def _hook_after_game(self):
        self._save_to_hf()

    def _configure_hf_hub(self, hf_push_frequency):
        username = whoami(token=self.hf_token)["name"]
        model_name = self.trainer.model.config.name_or_path.split("/")[-1]
        model_name += "-Gensyn-Swarm"
        model_name += f"-{self.animal_name}"
        self.trainer.args.hub_model_id = f"{username}/{model_name}"
        self.hf_push_frequency = hf_push_frequency
        get_logger().info("Logging into Hugging Face Hub...")
        login(self.hf_token)
        
    def _save_pending_rewards(self, rewards):
        """将未提交的奖励保存到文件中"""
        try:
            # 确保目录存在
            os.makedirs(os.path.dirname(self.reward_save_file), exist_ok=True)
            with open(self.reward_save_file, 'w') as f:
                json.dump({
                    'pending_rewards': rewards,
                    'timestamp': time.time()
                }, f)
        except Exception as e:
            get_logger().debug(f"Failed to save pending rewards: {e}")
            
    def _load_pending_rewards(self):
        """从文件中加载未提交的奖励"""
        try:
            if os.path.exists(self.reward_save_file):
                with open(self.reward_save_file, 'r') as f:
                    data = json.load(f)
                    pending_rewards = data.get('pending_rewards', 0.0)
                    get_logger().info(f"Loaded pending rewards: {pending_rewards}")
                    return pending_rewards
        except Exception as e:
            get_logger().debug(f"Failed to load pending rewards: {e}")
        return 0.0

    def _save_to_hf(self):
        if (
            self.hf_token not in [None, "None"]
            and self.state.round % self.hf_push_frequency == 0
        ):
            get_logger().info(f"pushing model to huggingface")
            try:
                repo_id = self.trainer.args.hub_model_id

                self.trainer.model.push_to_hub(
                    repo_id=repo_id,
                    token=self.hf_token,
                    commit_message=f"rl-swarm: round {self.state.round}, agent {self.animal_name}",
                    tags=[
                        "rl-swarm",
                        "genrl-swarm",
                        "grpo",
                        "gensyn",
                        f"I am {self.animal_name}",
                    ],
                )
            except Exception:
                get_logger().exception(
                    "Failed to push model to the Hugging Face Hub. When you conclude training please try manually pushing it yourself using the instructions here: https://huggingface.co/docs/hub/en/models-uploading",
                    stack_info=True,
                )

    def agent_block(
        self, check_interval=5.0, log_timeout=10.0, max_check_interval=60.0 * 15
    ):
        start_time = time.monotonic()
        fetch_log_time = start_time
        check_backoff = (
            check_interval  # Exponential backoff for already finished rounds.
        )
        while time.monotonic() - start_time < self.train_timeout:
            curr_time = time.monotonic()
            _ = self.communication.dht.get_visible_maddrs(latest=True)

            # Retrieve current round and stage.
            try:
                round_num, stage = self.coordinator.get_round_and_stage()
            except Exception as e:
                if curr_time - fetch_log_time > log_timeout:
                    get_logger().debug(
                        f"Could not fetch round and stage: {e}. Next check in {check_interval}s."
                    )
                    fetch_log_time = curr_time

                time.sleep(check_interval)
                continue

            if round_num >= self.state.round:
                get_logger().info(f"🐝 Joining round: {round_num}")
                check_backoff = check_interval  # Reset backoff after successful round
                self.state.round = round_num  # advance to swarm's round.
                return
            else:
                get_logger().info(
                    f"Already finished round: {round_num}. Next check in {check_backoff}s."
                )
                time.sleep(check_backoff)
                check_backoff = check_interval #查询轮次时间固定位5秒

            if round_num == self.max_round - 1:
                return

        get_logger().info("Training timed out!")
