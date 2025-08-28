#!/bin/bash

echo "🚀 开始安装 Dria..."

# 检查并安装 Ollama
if [ -d "/Applications/Ollama.app" ]; then
    echo "✅ Ollama 已存在，跳过安装"
    echo "🚀 正在启动 Ollama..."
    open /Applications/Ollama.app
else
    echo "📥 正在下载 Ollama..."
    curl -L -o ~/Downloads/Ollama.dmg https://ollama.com/download/Ollama.dmg

    if [ $? -eq 0 ]; then
        echo "✅ Ollama 下载完成"
        echo "🔧 正在挂载 Ollama.dmg..."
        
        # 挂载 DMG 文件
        hdiutil attach ~/Downloads/Ollama.dmg
        
        # 复制应用到 Applications 文件夹
        echo "📦 正在安装 Ollama 到 Applications 文件夹..."
        cp -R "/Volumes/Ollama/Ollama.app" /Applications/
        
        # 卸载 DMG
        echo "🗑️ 清理临时文件..."
        hdiutil detach "/Volumes/Ollama"
        rm ~/Downloads/Ollama.dmg
        
        echo "✅ Ollama 安装完成！"
        echo "💡 你可以在 Applications 文件夹中找到 Ollama"
        
        # 启动 Ollama
        echo "🚀 正在启动 Ollama..."
        open /Applications/Ollama.app
        
        # 等待几秒让 Ollama 启动
        echo "⏳ 等待 Ollama 启动完成..."
        sleep 5
    else
        echo "❌ Ollama 下载失败，但继续安装 Dria..."
    fi
fi

echo ""
echo "📱 现在开始安装 Dria..."

# 检查 Dria 是否已安装
if command -v dkn-compute-launcher &> /dev/null; then
    echo "✅ Dria 已存在，跳过安装"
else
    # 使用官方安装脚本
    echo "📥 正在下载并安装 Dria..."
    curl -fsSL https://dria.co/launcher | bash
    
    # 重新加载 zsh 配置
    echo "🔄 重新加载 shell 配置..."
    source ~/.zshrc
fi

echo "✅ Dria 安装完成！"
echo ""
echo "🔗 获取邀请码步骤："
echo "请在新的终端窗口中运行以下命令获取你的邀请码："
echo ""
echo "   dkn-compute-launcher referrals"
echo ""
echo "然后选择：Get referral code to refer someone"
echo ""
echo "请在新的终端窗口中运行以下命令更改端口："
echo ""
echo "   dkn-compute-launcher settings"
echo ""
echo "📝 全部设置完成后，请回到这里按回车键继续..."
read -p "按回车键继续..."

# # 生成桌面启动文件
# echo "📝 正在生成桌面启动文件..."
# cat > ~/Desktop/dria_start.command <<'EOF'
# #!/bin/bash

# # 颜色定义
# GREEN='\033[0;32m'
# BLUE='\033[0;34m'
# RED='\033[0;31m'
# YELLOW='\033[1;33m'
# NC='\033[0m'

# echo -e "${BLUE}🚀 启动 Dria 节点...${NC}"

# # 检查 dkn-compute-launcher 是否可用
# if ! command -v dkn-compute-launcher &> /dev/null; then
#     echo -e "${RED}❌ dkn-compute-launcher 命令未找到，请检查安装${NC}"
#     echo "按任意键退出..."
#     read -n 1 -s
#     exit 1
# fi

# # 启动 Dria 节点
# echo -e "${BLUE}📡 正在启动 Dria 计算节点...${NC}"
# dkn-compute-launcher start

# # 如果启动失败，保持终端打开
# if [ $? -ne 0 ]; then
#     echo -e "${RED}❌ 节点启动失败${NC}"
#     echo "按任意键退出..."
#     read -n 1 -s
# fi
# EOF

# chmod +x ~/Desktop/dria_start.command
# echo "✅ 桌面启动文件已创建: ~/Desktop/dria_start.command"

echo "✅ 安装和配置完成！"
echo "🚀 正在启动 Dria 节点..."
dkn-compute-launcher start