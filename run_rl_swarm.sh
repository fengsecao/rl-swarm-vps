#!/usr/bin/env bash

set -euo pipefail

# General arguments
ROOT=$PWD

# GenRL Swarm version to use
GENRL_TAG="0.1.9"

export IDENTITY_PATH
export GENSYN_RESET_CONFIG
export CONNECT_TO_TESTNET=true
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120  # 2 minutes
export SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2"
export PRG_CONTRACT="0x51D4db531ae706a6eC732458825465058fA23a35"
export HUGGINGFACE_ACCESS_TOKEN="None"
export PRG_GAME=true
export MODEL_NAME="Gensyn/Qwen2.5-0.5B-Instruct"  # 直接设置模型

# Path to an RSA private key. If this path does not exist, a new key pair will be created.
# Remove this file if you want a new PeerID.
DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

DOCKER=${DOCKER:-""}
GENSYN_RESET_CONFIG=${GENSYN_RESET_CONFIG:-""}

# Bit of a workaround for the non-root docker container.
if [ -n "$DOCKER" ]; then
    volumes=(
        /home/gensyn/rl_swarm/modal-login/temp-data
        /home/gensyn/rl_swarm/keys
        /home/gensyn/rl_swarm/configs
        /home/gensyn/rl_swarm/logs
    )

    for volume in ${volumes[@]}; do
        sudo chown -R 1001:1001 $volume
    done
fi

# Will ignore any visible GPUs if set.
CPU_ONLY=${CPU_ONLY:-""}

# Set if successfully parsed from modal-login/temp-data/userData.json.
ORG_ID=${ORG_ID:-""}

GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
RESET_TEXT="\033[0m"

echo_green() {
    echo -e "$GREEN_TEXT$1$RESET_TEXT"
}

echo_blue() {
    echo -e "$BLUE_TEXT$1$RESET_TEXT"
}

echo_red() {
    echo -e "$RED_TEXT$1$RESET_TEXT"
}

ROOT_DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

# Function to clean up the server process upon exit
cleanup() {
    echo_green ">> Shutting down trainer..."

    # Remove modal credentials if they exist
    # rm -r $ROOT_DIR/modal-login/temp-data/*.json 2> /dev/null || true

    # 优先使用记录的SERVER_PID
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo_green ">> Killing server process $SERVER_PID"
        kill "$SERVER_PID" 2>/dev/null || true
    fi
    
    # 稳健地尝试杀死进程组，先检查进程组是否存在
    if kill -0 -- -$$ 2>/dev/null; then
        echo_green ">> Killing process group $$"
        kill -- -$$ 2>/dev/null || true
    else
        echo_green ">> Process group $$ does not exist or already terminated"
    fi

    exit 0
}

errnotify() {
    echo_red ">> An error was detected while running rl-swarm. See $ROOT/logs for full logs."
}

trap cleanup EXIT
trap errnotify ERR

echo -e "\033[38;5;224m"
cat << "EOF"
    ██████  ██            ███████ ██     ██  █████  ██████  ███    ███
    ██   ██ ██            ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██████  ██      █████ ███████ ██  █  ██ ███████ ██████  ██ ████ ██
    ██   ██ ██                 ██ ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██   ██ ███████       ███████  ███ ███  ██   ██ ██   ██ ██      ██ v0.6.2

    From Gensyn

EOF

# Create logs directory if it doesn't exist
mkdir -p "$ROOT/logs"

if [ "$CONNECT_TO_TESTNET" = true ]; then
    # Run modal_login server.
    echo "Please login to create an Ethereum Server Wallet"
    cd modal-login
    # Check if the yarn command exists; if not, install Yarn.

    # Node.js + NVM setup
    if ! command -v node > /dev/null 2>&1; then
        echo "Node.js not found. Installing NVM and latest Node.js..."
        export NVM_DIR="$HOME/.nvm"
        if [ ! -d "$NVM_DIR" ]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        fi
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        nvm install node
    else
        echo "Node.js is already installed: $(node -v)"
    fi

    if ! command -v yarn > /dev/null 2>&1; then
        # Detect Ubuntu (including WSL Ubuntu) and install Yarn accordingly
        if grep -qi "ubuntu" /etc/os-release 2> /dev/null || uname -r | grep -qi "microsoft"; then
            echo "Detected Ubuntu or WSL Ubuntu. Installing Yarn via apt..."
            curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
            echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
            sudo apt update && sudo apt install -y yarn
        else
            echo "Yarn not found. Installing Yarn globally with npm (no profile edits)…"
            # This lands in $NVM_DIR/versions/node/<ver>/bin which is already on PATH
            npm install -g --silent yarn
        fi
    fi

    ENV_FILE="$ROOT"/modal-login/.env
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        sed -i '' "3s/.*/SWARM_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
        sed -i '' "4s/.*/PRG_CONTRACT_ADDRESS=$PRG_CONTRACT/" "$ENV_FILE"

    else
        # Linux version
        sed -i "3s/.*/SWARM_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
        sed -i "4s/.*/PRG_CONTRACT_ADDRESS=$PRG_CONTRACT/" "$ENV_FILE"
    fi


    # Docker image already builds it, no need to again.
    if [ -z "$DOCKER" ]; then
        yarn install --immutable
        echo "Starting development server"
        yarn dev >> "$ROOT/logs/yarn.log" 2>&1 & # Run in background and log output
    else
        # Docker环境下直接在后台启动开发服务器
        yarn dev >> "$ROOT/logs/yarn.log" 2>&1 &
    fi

    SERVER_PID=$!  # Store the process ID
    echo "Started server process: $SERVER_PID"
    sleep 5

    # Try to open the URL in the default browser
    #if [ -z "$DOCKER" ]; then
    #    if open http://localhost:3000 2> /dev/null; then
    #        echo_green ">> Successfully opened http://localhost:3000 in your default browser."
    #    else
    #        echo ">> Failed to open http://localhost:3000. Please open it manually."
    #    fi
    #else
    #     echo_green ">> Please open http://localhost:3000 in your host browser."
    # fi

#    cd ..
#
#    echo_green ">> Waiting for modal userData.json to be created..."
#    while [ ! -f "modal-login/temp-data/userData.json" ]; do
#        sleep 5  # Wait for 5 seconds before checking again
#    done
#    echo "Found userData.json. Proceeding..."
#
#    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
#    echo "Your ORG_ID is set to: $ORG_ID"
#
#    # Wait until the API key is activated by the client
#    echo "Waiting for API key to become activated..."
#    while true; do
#        STATUS=$(curl -s "http://localhost:3000/api/get-api-key-status?orgId=$ORG_ID")
#        if [[ "$STATUS" == "activated" ]]; then
#            echo "API key is activated! Proceeding..."
#            break
#        else
#            echo "Waiting for API key to be activated..."
#            sleep 5
#        fi
#    done

  #-----------------------use proxy port  start--------------------------
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  PURPLE='\033[0;95m'
  BLUE='\033[0;94m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'

  echo -e "\n${CYAN}${BOLD}[✓] Installing dependencies with npm. This may take a few minutes, depending on your internet speed...${NC}"
  yarn install --immutable

  echo -e "\n${CYAN}${BOLD}[✓] Starting the development server...${NC}"
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
      if ! command -v ss &>/dev/null; then
          echo -e "${YELLOW}[!] 'ss' not found. Attempting to install 'iproute2'...${NC}"
          if command -v apt &>/dev/null; then
              sudo apt update && sudo apt install -y iproute2
          elif command -v yum &>/dev/null; then
              sudo yum install -y iproute
          elif command -v pacman &>/dev/null; then
              sudo pacman -Sy iproute2
          else
              echo -e "${RED}[✗] Could not install 'ss'. Package manager not found.${NC}"
              exit 1
          fi
      fi
  fi

  # 根据系统类型选择端口检查命令
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
      PORT_LINE=$(ss -ltnp | grep ":3000 ")
      if [ -n "$PORT_LINE" ]; then
          PID=$(grep -oP 'pid=\K\d+' <<< "$PORT_LINE")
      fi
  elif [[ "$OSTYPE" == "darwin"* ]]; then
      # 使用 -F p 直接输出 PID 格式（p<pid>）
      PID_STR=$(lsof -i :3000 -sTCP:LISTEN -nP -F p | head -1)
      if [[ "$PID_STR" =~ ^p[0-9]+ ]]; then
          PID=${PID_STR#p}  # 移除前缀 'p'
      fi
  fi

  # 统一处理进程终止
  if [ -n "$PID" ]; then
      echo -e "${YELLOW}[!] Port 3000 is in use. Killing process: $PID${NC}"
      kill -9 "$PID"
      sleep 2
  fi

  echo "Building server"
  yarn build > "$ROOT/logs/yarn.log" 2>&1
  #start
  yarn start >> "$ROOT/logs/yarn.log" 2>&1 & # Run in background and log output

  SERVER_PID=$!
  echo "Started server process: $SERVER_PID"

  MAX_WAIT=30
  for ((i = 0; i < MAX_WAIT; i++)); do
      if grep -q "Local:        http://localhost:" $ROOT/logs/yarn.log; then
          PORT=$(grep "Local:        http://localhost:" $ROOT/logs/yarn.log | sed -n 's/.*http:\/\/localhost:\([0-9]*\).*/\1/p')
          if [ -n "$PORT" ]; then
              echo -e "${GREEN}${BOLD}[✓] Server is running successfully on port $PORT.${NC}"
              break
          fi
      fi
      sleep 1
  done

  if [ $i -eq $MAX_WAIT ]; then
      echo -e "${RED}${BOLD}[✗] Timeout waiting for server to start.${NC}"
      kill $SERVER_PID 2>/dev/null || true
      exit 1
  fi

  cd ..
  if [ -f "modal-login/temp-data/userData.json" ]; then

      ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)

  else
      echo -e "\n${CYAN}${BOLD}[✓] Detecting system architecture...${NC}"
      ARCH=$(uname -m)
      OS=$(uname -s | tr '[:upper:]' '[:lower:]')
      if [ "$ARCH" = "x86_64" ]; then
          NGROK_ARCH="amd64"
          CF_ARCH="amd64"
          echo -e "${GREEN}${BOLD}[✓] Detected x86_64 architecture.${NC}"
      elif [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
          NGROK_ARCH="arm64"
          CF_ARCH="arm64"
          echo -e "${GREEN}${BOLD}[✓] Detected ARM64 architecture.${NC}"
      elif [[ "$ARCH" == arm* ]]; then
          NGROK_ARCH="arm"
          CF_ARCH="arm"
          echo -e "${GREEN}${BOLD}[✓] Detected ARM architecture.${NC}"
      else
          echo -e "${RED}[✗] Unsupported architecture: $ARCH. Please use a supported system.${NC}"
          exit 1
      fi

      check_url() {
          local url=$1
          local max_retries=3
          local retry=0

          while [ $retry -lt $max_retries ]; do
              http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
              if [ "$http_code" = "200" ] || [ "$http_code" = "404" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
                  return 0
              fi
              retry=$((retry + 1))
              sleep 2
          done
          return 1
      }

      install_localtunnel() {
          if command -v lt >/dev/null 2>&1; then
              echo -e "${GREEN}${BOLD}[✓] Localtunnel is already installed.${NC}"
              return 0
          fi
          echo -e "\n${CYAN}${BOLD}[✓] Installing localtunnel...${NC}"
          npm install -g localtunnel >/dev/null 2>&1
          if [ $? -eq 0 ]; then
              echo -e "${GREEN}${BOLD}[✓] Localtunnel installed successfully.${NC}"
              return 0
          else
              echo -e "${RED}${BOLD}[✗] Failed to install localtunnel.${NC}"
              return 1
          fi
      }

      install_cloudflared() {
          if command -v cloudflared >/dev/null 2>&1; then
              echo -e "${GREEN}${BOLD}[✓] Cloudflared is already installed.${NC}"
              return 0
          fi
          echo -e "\n${YELLOW}${BOLD}[✓] Installing cloudflared...${NC}"
          CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CF_ARCH"
          wget -q --show-progress "$CF_URL" -O cloudflared
          if [ $? -ne 0 ]; then
              echo -e "${RED}${BOLD}[✗] Failed to download cloudflared.${NC}"
              return 1
          fi
          chmod +x cloudflared
          mv cloudflared /usr/local/bin/
          if [ $? -ne 0 ]; then
              echo -e "${RED}${BOLD}[✗] Failed to move cloudflared to /usr/local/bin/.${NC}"
              return 1
          fi
          echo -e "${GREEN}${BOLD}[✓] Cloudflared installed successfully.${NC}"
          return 0
      }

      install_ngrok() {
          if command -v ngrok >/dev/null 2>&1; then
              echo -e "${GREEN}${BOLD}[✓] ngrok is already installed.${NC}"
              return 0
          fi
          echo -e "${YELLOW}${BOLD}[✓] Installing ngrok...${NC}"
          NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-$OS-$NGROK_ARCH.tgz"
          wget -q --show-progress "$NGROK_URL" -O ngrok.tgz
          if [ $? -ne 0 ]; then
              echo -e "${RED}${BOLD}[✗] Failed to download ngrok.${NC}"
              return 1
          fi
          tar -xzf ngrok.tgz
          if [ $? -ne 0 ]; then
              echo -e "${RED}${BOLD}[✗] Failed to extract ngrok.${NC}"
              rm ngrok.tgz
              return 1
          fi
          mv ngrok /usr/local/bin/
          if [ $? -ne 0 ]; then
              echo -e "${RED}${BOLD}[✗] Failed to move ngrok to /usr/local/bin/.${NC}"
              rm ngrok.tgz
              return 1
          fi
          rm ngrok.tgz
          echo -e "${GREEN}${BOLD}[✓] ngrok installed successfully.${NC}"
          return 0
      }

      try_localtunnel() {
          echo -e "\n${CYAN}${BOLD}[✓] Trying localtunnel...${NC}"
          if install_localtunnel; then
              echo -e "\n${CYAN}${BOLD}[✓] Starting localtunnel on port $PORT...${NC}"
              TUNNEL_TYPE="localtunnel"
              lt --port $PORT >localtunnel_output.log 2>&1 &
              TUNNEL_PID=$!

              sleep 5
              URL=$(grep -o "https://[^ ]*" localtunnel_output.log | head -n1)

              if [ -n "$URL" ]; then
                  PASS=$(curl -s https://loca.lt/mytunnelpassword)
                  FORWARDING_URL="$URL"
                  echo -e "${GREEN}${BOLD}[✓] Success! Please visit this website : ${YELLOW}${BOLD}${URL}${GREEN}${BOLD} and then enter this password : ${YELLOW}${BOLD}${PASS}${GREEN}${BOLD} to access the website and then log in using your email.${NC}"
                  return 0
              else
                  echo -e "${RED}${BOLD}[✗] Failed to get localtunnel URL.${NC}"
                  kill $TUNNEL_PID 2>/dev/null || true
              fi
          fi
          return 1
      }

      try_cloudflared() {
          echo -e "\n${CYAN}${BOLD}[✓] Trying cloudflared...${NC}"
          if install_cloudflared; then
              echo -e "\n${CYAN}${BOLD}[✓] Starting cloudflared tunnel...${NC}"
              TUNNEL_TYPE="cloudflared"
              cloudflared tunnel --url http://localhost:$PORT >cloudflared_output.log 2>&1 &
              TUNNEL_PID=$!

              counter=0
              MAX_WAIT=10
              while [ $counter -lt $MAX_WAIT ]; do
                  CLOUDFLARED_URL=$(grep -o 'https://[^ ]*\.trycloudflare.com' cloudflared_output.log | head -n1)
                  if [ -n "$CLOUDFLARED_URL" ]; then
                      echo -e "${GREEN}${BOLD}[✓] Cloudflared tunnel is started successfully.${NC}"
                      echo -e "\n${CYAN}${BOLD}[✓] Checking if cloudflared URL is working...${NC}"
                      if check_url "$CLOUDFLARED_URL"; then
                          FORWARDING_URL="$CLOUDFLARED_URL"
                          return 0
                      else
                          echo -e "${RED}${BOLD}[✗] Cloudflared URL is not accessible.${NC}"
                          kill $TUNNEL_PID 2>/dev/null || true
                          break
                      fi
                  fi
                  sleep 1
                  counter=$((counter + 1))
              done
              kill $TUNNEL_PID 2>/dev/null || true
          fi
          return 1
      }

      get_ngrok_url_method1() {
          local url=$(grep -o '"url":"https://[^"]*' ngrok_output.log 2>/dev/null | head -n1 | cut -d'"' -f4)
          echo "$url"
      }

      get_ngrok_url_method2() {
          local try_port
          local url=""
          for try_port in $(seq 4040 4045); do
              local response=$(curl -s "http://localhost:$try_port/api/tunnels" 2>/dev/null)
              if [ -n "$response" ]; then
                  url=$(echo "$response" | grep -o '"public_url":"https://[^"]*' | head -n1 | cut -d'"' -f4)
                  if [ -n "$url" ]; then
                      break
                  fi
              fi
          done
          echo "$url"
      }

      get_ngrok_url_method3() {
          local url=$(grep -o "Forwarding.*https://[^ ]*" ngrok_output.log 2>/dev/null | grep -o "https://[^ ]*" | head -n1)
          echo "$url"
      }

      try_ngrok() {
          echo -e "\n${CYAN}${BOLD}[✓] Trying ngrok...${NC}"
          if install_ngrok; then
              TUNNEL_TYPE="ngrok"
              while true; do
                  echo -e "\n${YELLOW}${BOLD}To get your authtoken:${NC}"
                  echo "1. Sign up or log in at https://dashboard.ngrok.com"
                  echo "2. Go to 'Your Authtoken' section: https://dashboard.ngrok.com/get-started/your-authtoken"
                  echo "3. Click on the eye icon to reveal your ngrok auth token"
                  echo "4. Copy that auth token and paste it in the prompt below"
                  echo -e "\n${BOLD}Please enter your ngrok authtoken:${NC}"
                  read -p "> " NGROK_TOKEN

                  if [ -z "$NGROK_TOKEN" ]; then
                      echo -e "${RED}${BOLD}[✗] No token provided. Please enter a valid token.${NC}"
                      continue
                  fi
                  pkill -f ngrok || true
                  sleep 2

                  ngrok authtoken "$NGROK_TOKEN" 2>/dev/null
                  if [ $? -eq 0 ]; then
                      echo -e "${GREEN}${BOLD}[✓] Successfully authenticated ngrok!${NC}"
                      break
                  else
                      echo -e "${RED}[✗] Authentication failed. Please check your token and try again.${NC}"
                  fi
              done

              echo -e "\n${CYAN}${BOLD}[✓] Starting ngrok with method 1...${NC}"
              ngrok http "$PORT" --log=stdout --log-format=json >ngrok_output.log 2>&1 &
              TUNNEL_PID=$!
              sleep 5

              NGROK_URL=$(get_ngrok_url_method1)
              if [ -n "$NGROK_URL" ]; then
                  FORWARDING_URL="$NGROK_URL"
                  return 0
              else
                  echo -e "${RED}${BOLD}[✗] Failed to get ngrok URL (method 1).${NC}"
                  kill $TUNNEL_PID 2>/dev/null || true
              fi

              echo -e "\n${CYAN}${BOLD}[✓] Starting ngrok with method 2...${NC}"
              ngrok http "$PORT" >ngrok_output.log 2>&1 &
              TUNNEL_PID=$!
              sleep 5

              NGROK_URL=$(get_ngrok_url_method2)
              if [ -n "$NGROK_URL" ]; then
                  FORWARDING_URL="$NGROK_URL"
                  return 0
              else
                  echo -e "${RED}${BOLD}[✗] Failed to get ngrok URL (method 2).${NC}"
                  kill $TUNNEL_PID 2>/dev/null || true
              fi

              echo -e "\n${CYAN}${BOLD}[✓] Starting ngrok with method 3...${NC}"
              ngrok http "$PORT" --log=stdout >ngrok_output.log 2>&1 &
              TUNNEL_PID=$!
              sleep 5

              NGROK_URL=$(get_ngrok_url_method3)
              if [ -n "$NGROK_URL" ]; then
                  FORWARDING_URL="$NGROK_URL"
                  return 0
              else
                  echo -e "${RED}${BOLD}[✗] Failed to get ngrok URL (method 3).${NC}"
                  kill $TUNNEL_PID 2>/dev/null || true
              fi
          fi
          return 1
      }

      start_tunnel() {
          if try_localtunnel; then
              return 0
          fi

          if try_cloudflared; then
              return 0
          fi

          if try_ngrok; then
              return 0
          fi
          return 1
      }

      start_tunnel
      if [ $? -eq 0 ]; then
          if [ "$TUNNEL_TYPE" != "localtunnel" ]; then
              echo -e "${GREEN}${BOLD}[✓] Success! Please visit this website and log in using your email:${NC} ${CYAN}${BOLD}${FORWARDING_URL}${NC}"
          fi
      else
          echo -e "\n${BLUE}${BOLD}[✓] Don't worry, you can use this manual method. Please follow these instructions:${NC}"
          echo "1. Open this same WSL/VPS or GPU server on another tab"
          echo "2. Paste this command into this terminal: ngrok http $PORT"
          echo "3. It will show a link similar to this: https://xxxx.ngrok-free.app"
          echo "4. Visit this website and login using your email, this website may take 30 sec to load."
          echo "5. Now go back to the previous tab, you will see everything will run fine"
      fi

      cd ..

      echo -e "\n${CYAN}${BOLD}[↻] Waiting for you to complete the login process...${NC}"
      while [ ! -f "modal-login/temp-data/userData.json" ]; do
          sleep 3
      done

      echo -e "${GREEN}${BOLD}[✓] Success! The userData.json file has been created. Proceeding with remaining setups...${NC}"
      rm -f server.log localtunnel_output.log cloudflared_output.log ngrok_output.log

      ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)

  fi

  echo -e "\n${CYAN}${BOLD}[✓] ORG_ID has been set to: ${BOLD}$ORG_ID\n${NC}"

  echo -e "${CYAN}${BOLD}[✓] Waiting for API key to become activated...${NC}"
  while true; do
      STATUS=$(curl -s "http://localhost:3000/api/get-api-key-status?orgId=$ORG_ID")
      if [[ "$STATUS" == "activated" ]]; then
          echo -e "${GREEN}${BOLD}[✓] Success! API key is activated! Proceeding...\n${NC}"
          break
      else
          echo "[↻] Waiting for API key to be activated..."
          sleep 5
      fi
  done

  #-----------------------use proxy port  end--------------------------
fi

echo_green ">> Getting requirements..."
source .venv/bin/activate
pip install --upgrade pip

 echo_green ">> Installing GenRL..."
pip install gensyn-genrl==${GENRL_TAG}
pip install reasoning-gym>=0.1.20 # for reasoning gym env
pip install trl==0.19.1
pip install hivemind@git+https://github.com/gensyn-ai/hivemind@639c964a8019de63135a2594663b5bec8e5356dd # We need the latest, 1.1.11 is broken


if [ ! -d "$ROOT/configs" ]; then
    mkdir "$ROOT/configs"
fi  
if [ -f "$ROOT/configs/rg-swarm.yaml" ]; then
    # Use cmp -s for a silent comparison. If different, backup and copy.
    if ! cmp -s "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"; then
        if [ -z "$GENSYN_RESET_CONFIG" ]; then
            echo_green ">> Found differences in rg-swarm.yaml. If you would like to reset to the default, set GENSYN_RESET_CONFIG to a non-empty value."
        else
            echo_green ">> Found differences in rg-swarm.yaml. Backing up existing config."
            mv "$ROOT/configs/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml.bak"
            cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"
        fi
    fi
else
    # If the config doesn't exist, just copy it.
    cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"
fi

if [ -n "$DOCKER" ]; then
    # Make it easier to edit the configs on Linux systems.
    sudo chmod -R 0777 /home/gensyn/rl_swarm/configs
fi

echo_green ">> Done!"


# 移除交互式提问，改为非交互默认行为
# 1) 默认不上传到 Hugging Face
echo_green ">> Hugging Face push: disabled by default"
export HUGGINGFACE_ACCESS_TOKEN="None"

# 2) 模型选择：若未通过环境变量提供，则使用默认指定模型
if [ -z "${MODEL_NAME:-}" ]; then
    export MODEL_NAME="Qwen/Qwen3-0.6B"
fi
    echo_green ">> Using model: $MODEL_NAME"

# 3) PRG 游戏：默认参加
export PRG_GAME=true
    echo_green ">> Playing PRG game: true"


echo -en $RESET_TEXT
echo_green ">> Good luck in the swarm!"
echo_blue ">> And remember to star the repo on GitHub! --> https://github.com/gensyn-ai/rl-swarm"

python -m rgym_exp.runner.swarm_launcher \
    --config-path "$ROOT/rgym_exp/config" \
    --config-name "rg-swarm.yaml" 

wait  # Keep script running until Ctrl+C
