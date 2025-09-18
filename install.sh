#   echo "🍺 Checking Homebrew..."
#   if ! command -v brew &>/dev/null; then
#     echo "📥 Installing Homebrew..."
#     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#   else
#     echo "✅ Homebrew 已安装，跳过安装。"
#   fi
#   # 配置 Brew 环境变量
#   BREW_ENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
#   if ! grep -q "$BREW_ENV" ~/.zshrc; then
#     echo "$BREW_ENV" >> ~/.zshrc
#   fi
#   eval "$(/opt/homebrew/bin/brew shellenv)"
  # 安装依赖
  echo "📦 检查并安装 Node.js, Python@3.10, curl, screen, git, yarn..."
  deps=(node python3.10 curl screen git yarn)
  brew_names=(node python@3.10 curl screen git yarn)
  for i in "${!deps[@]}"; do
    dep="${deps[$i]}"
    brew_name="${brew_names[$i]}"
    if ! command -v $dep &>/dev/null; then
      echo "📥 安装 $brew_name..."
      while true; do
        if brew install $brew_name; then
          echo "✅ $brew_name 安装成功。"
          break
        else
          echo "⚠️ $brew_name 安装失败，3秒后重试..."
          sleep 3
        fi
      done
    else
      echo "✅ $dep 已安装，跳过安装。"
    fi
  done
  # 自动清理.zshrc中python3.12配置，并写入3.10配置
  if grep -q "# Python3.12 Environment Setup" ~/.zshrc; then
    echo "🧹 清理旧的 Python3.12 配置..."
    sed -i '' '/# Python3.12 Environment Setup/,/^fi$/d' ~/.zshrc
  fi
  PYTHON_ALIAS="# Python3.10 Environment Setup"
  if ! grep -q "$PYTHON_ALIAS" ~/.zshrc; then
    cat << 'EOF' >> ~/.zshrc

# Python3.10 Environment Setup
if [[ $- == *i* ]]; then
  alias python="/opt/homebrew/bin/python3.10"
  alias python3="/opt/homebrew/bin/python3.10"
  alias pip="/opt/homebrew/bin/pip3.10"
  alias pip3="/opt/homebrew/bin/pip3.10"
fi
EOF
  fi
  source ~/.zshrc || true