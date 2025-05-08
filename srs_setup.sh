#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 配置变量
SCRIPT_DIR="$(pwd)"
SRS_DIR="$HOME/srs-server"
SRS_CONF="$SRS_DIR/srs/trunk/conf/drone.conf"
LOG_DIR="$SCRIPT_DIR/srs_install_logs"
RTMP_URL=""

# 创建独立的日志目录
mkdir -p $LOG_DIR

# 日志记录函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_DIR/install.log
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1" >> $LOG_DIR/install.log
    exit 1
}

# 检查系统类型
check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        error "无法确定操作系统"
    fi
    
    log "系统检测: $OS $VER"
    
    if [[ "$OS" != *"Ubuntu"* ]] && [[ "$OS" != *"Debian"* ]]; then
        log "警告: 当前系统不是Ubuntu或Debian，某些功能可能不适用"
    fi
}

# 安装依赖
install_dependencies() {
    log "开始安装依赖..."
    
    # 检查是否已安装
    INSTALLED=1
    for pkg in git build-essential unzip automake gcc g++ make cmake pkg-config libssl-dev ffmpeg; do
        if ! dpkg -s $pkg >/dev/null 2>&1; then
            INSTALLED=0
            break
        fi
    done
    
    if [ $INSTALLED -eq 1 ]; then
        log "依赖已安装"
        return 0
    fi
    
    # 更新软件包列表
    log "更新软件包列表..."
    sudo apt update || error "无法更新软件包列表"
    
    # 安装依赖
    log "安装必要依赖..."
    sudo apt install -y git build-essential automake unzip gcc g++ make cmake pkg-config libssl-dev ffmpeg || error "依赖安装失败"
    
    log "所有依赖安装完成"
}

# 检查FFmpeg是否存在
check_ffmpeg() {
    if command -v ffmpeg >/dev/null 2>&1; then
        FFMPEG_PATH=$(which ffmpeg)
        log "FFmpeg已安装: $FFMPEG_PATH"
        return 0
    else
        error "找不到FFmpeg，请安装FFmpeg"
    fi
}

# 检查SRS是否已安装
check_srs() {
    if [ -d "$SRS_DIR/srs" ] && [ -f "$SRS_DIR/srs/trunk/objs/srs" ]; then
        log "SRS已安装"
        return 0
    else
        return 1
    fi
}

# 安装SRS (修复goto问题)
install_srs() {
    log "开始安装SRS..."
    
    # 声明一个函数代替goto
    compile_srs() {
        # 编译SRS
        log "编译SRS(这可能需要几分钟)..."
        cd $SRS_DIR/srs/trunk || error "无法进入SRS源码目录"
        
        # 配置和编译
        ./configure --prefix=$SRS_DIR/install --with-hls --with-ssl --with-ffmpeg || error "SRS配置失败"
        make || error "SRS编译失败"
        
        # 创建必要目录
        sudo mkdir -p $SRS_DIR/srs/trunk/logs
        sudo mkdir -p $SRS_DIR/srs/trunk/objs/nginx/html/hls/live
        sudo chmod -R 777 $SRS_DIR/srs/trunk/objs/nginx/html/hls
        sudo chmod -R 777 $SRS_DIR/srs/trunk/logs
        
        log "SRS安装成功！"
    }
    
    # 检查是否已安装
    if check_srs; then
        log "SRS已经安装且编译完成，跳过安装步骤"
        return 0
    fi
    
    # 创建工作目录
    mkdir -p $SRS_DIR
    cd $SRS_DIR || error "无法进入工作目录 $SRS_DIR"
    
    # 检查srs目录是否已存在
    if [ -d "$SRS_DIR/srs" ]; then
        echo -e "${YELLOW}检测到srs目录已存在，请选择操作:${NC}"
        echo -e "1) 删除现有目录并重新克隆"
        echo -e "2) 使用现有目录继续安装"
        echo -e "3) 取消安装"
        read -p "请选择 [1-3]: " dir_choice
        
        case $dir_choice in
            1)
                log "删除现有srs目录..."
                sudo rm -rf $SRS_DIR/srs
                # 继续执行克隆步骤
                ;;
            2)
                log "使用现有srs目录..."
                cd srs/trunk || error "无法进入srs/trunk目录，可能不是完整的SRS仓库"
                # 直接调用编译函数
                compile_srs
                return 0
                ;;
            3)
                log "取消安装"
                return 1
                ;;
            *)
                log "无效选择，取消安装"
                return 1
                ;;
        esac
    fi
    
    # 仓库源选择
    echo -e "${YELLOW}请选择SRS仓库源:${NC}"
    echo -e "1) GitHub (国际网络较好)"
    echo -e "2) Gitee (中国大陆网络较好)"
    read -p "请选择 [1-2]: " repo_choice
    
    case $repo_choice in
        1)
            REPO_URL="https://github.com/ossrs/srs.git"
            log "使用GitHub源: $REPO_URL"
            ;;
        2)
            REPO_URL="https://gitee.com/ossrs/srs.git"
            log "使用Gitee源: $REPO_URL"
            ;;
        *)
            log "无效选择，默认使用Gitee源"
            REPO_URL="https://gitee.com/ossrs/srs.git"
            ;;
    esac
    
    # 克隆SRS仓库
    log "克隆SRS仓库 ($REPO_URL)..."
    git clone $REPO_URL || error "克隆SRS仓库失败"
    
    # 调用编译函数
    compile_srs
}

# 创建低延迟配置文件 - 最小化配置
create_config() {
    log "开始创建配置..."
    
    # 先询问RTMP URL
    echo -e "${YELLOW}请输入您的RTMP源地址：${NC}"
    read -p "(例如: rtmp://ns8.indexforce.com/home/mystream): " user_rtmp
    
    if [ -z "$user_rtmp" ]; then
        error "RTMP地址不能为空！"
    fi
    
    RTMP_URL=$user_rtmp
    log "使用RTMP源: $RTMP_URL"
    
    # 检查ffmpeg路径
    check_ffmpeg
    
    # 创建配置目录
    sudo mkdir -p $(dirname $SRS_CONF)
    
    # 写入最小化的配置文件，兼容性最佳
    sudo tee $SRS_CONF > /dev/null << EOF
# 最小化基本配置
listen              1935;
max_connections     1000;
daemon              off;
srs_log_tank        file;
srs_log_file        ./logs/srs.log;
srs_log_level       trace;

# HTTP服务器配置
http_server {
    enabled         on;
    listen          8080;
    dir             ./objs/nginx/html;
}

# RTMP虚拟主机配置
vhost __defaultVhost__ {
    # HLS配置 - 修改优化
    hls {
        enabled             on;
        hls_fragment        2;   # 使用2秒片段，更容易生成文件
        hls_window          5;   # 增加窗口大小
        hls_path            ./objs/nginx/html/hls;
        hls_m3u8_file       [app]/[stream].m3u8;
        hls_ts_file         [app]/[stream]-[seq].ts;
        hls_cleanup         off; # 关闭自动清理方便调试
    }
    
    # HTTP-FLV支持
    http_remux {
        enabled     on;
        mount       [vhost]/[app]/[stream].flv;
    }
    
    # 从现有RTMP拉流配置 - 简化配置
    ingest drone {
        enabled      on;
        input {
            type    stream;
            url     $RTMP_URL;
        }
        ffmpeg      $FFMPEG_PATH;
        engine {
            enabled     on;
            vcodec      copy;
            acodec      copy;
            output      rtmp://127.0.0.1:1935/live/drone;
        }
    }
}
EOF
    
    log "配置文件已创建: $SRS_CONF"
    log "HLS播放地址将是: http://$(hostname -I | awk '{print $1}'):8080/hls/live/drone.m3u8"
    log "HTTP-FLV播放地址将是: http://$(hostname -I | awk '{print $1}'):8080/live/drone.flv"
}

# 启动SRS - 全部使用sudo，简化流程
start_srs() {
    log "使用sudo启动SRS服务..."
    
    # 检查SRS是否安装
    if ! check_srs; then
        error "SRS未安装，请先安装"
    fi
    
    # 检查配置文件
    if [ ! -f "$SRS_CONF" ]; then
        error "配置文件不存在，请先配置"
    fi
    
    # 确保先停止之前的实例
    sudo pkill -f "objs/srs -c" >/dev/null 2>&1
    
    # 确保目录存在和权限正确
    sudo mkdir -p $SRS_DIR/srs/trunk/logs
    sudo mkdir -p $SRS_DIR/srs/trunk/objs/nginx/html/hls/live
    sudo chmod -R 777 $SRS_DIR/srs/trunk/logs
    sudo chmod -R 777 $SRS_DIR/srs/trunk/objs/nginx/html
    
    # 进入SRS目录
    cd $SRS_DIR/srs/trunk || error "无法进入SRS目录"
    
    # 测试配置文件语法
    log "测试配置文件语法..."
    CONFIG_CHECK=$(sudo ./objs/srs -t -c $SRS_CONF 2>&1)
    if echo "$CONFIG_CHECK" | grep -q "test is successful"; then
        log "配置文件语法正确"
    else
        log "配置文件语法错误:"
        echo "$CONFIG_CHECK"
        error "配置测试失败，请修复配置文件"
    fi
    
    # 简化：直接用sudo启动SRS
    log "直接用sudo启动SRS..."
    sudo ./objs/srs -c $SRS_CONF > ./logs/srs.log 2>&1 &
    
    # 等待启动
    sleep 3
    
    # 检查是否成功启动
    if sudo pgrep -f "objs/srs -c" >/dev/null; then
        log "SRS启动成功！"
        log "HLS播放地址: http://$(hostname -I | awk '{print $1}'):8080/hls/live/drone.m3u8"
        log "HTTP-FLV播放地址: http://$(hostname -I | awk '{print $1}'):8080/live/drone.flv"
        log "HTML播放器: http://$(hostname -I | awk '{print $1}'):8080/player.html"
    else
        log "SRS启动失败，查看日志:"
        sudo tail -n 20 ./logs/srs.log
        error "SRS启动失败"
    fi
}

# 停止SRS - 使用sudo
stop_srs() {
    log "停止SRS服务..."
    
    if sudo pgrep -f "objs/srs -c" >/dev/null; then
        sudo pkill -f "objs/srs -c"
        # 也停止可能存在的ffmpeg进程
        sudo pkill -f "ffmpeg.*rtmp://127.0.0.1:1935/live/drone" >/dev/null 2>&1
        sudo pkill -f "ffmpeg.*rtmp://127.0.0.1:1935/live/test" >/dev/null 2>&1
        log "SRS已停止"
    else
        log "SRS未运行"
    fi
}

# 检查SRS状态 - 使用sudo
status_srs() {
    if sudo pgrep -f "objs/srs -c" >/dev/null; then
        echo -e "${GREEN}SRS正在运行${NC}"
        sudo ps aux | grep "objs/srs -c" | grep -v grep
        
        # 检查拉流状态
        echo -e "\n${YELLOW}拉流状态:${NC}"
        curl -s http://localhost:1985/api/v1/streams | grep -i drone
        
        # 检查ffmpeg进程
        echo -e "\n${YELLOW}FFmpeg进程:${NC}"
        sudo ps aux | grep ffmpeg | grep -v grep
        
        echo -e "\n${YELLOW}可用流地址:${NC}"
        echo "HLS: http://$(hostname -I | awk '{print $1}'):8080/hls/live/drone.m3u8"
        echo "FLV: http://$(hostname -I | awk '{print $1}'):8080/live/drone.flv"
        echo "播放器: http://$(hostname -I | awk '{print $1}'):8080/player.html"
    else
        echo -e "${RED}SRS未运行${NC}"
    fi
}

# 显示完整状态信息 - 新增函数
show_full_status() {
    log "获取完整状态信息..."
    
    # 检查SRS是否运行
    if ! sudo pgrep -f "objs/srs -c" >/dev/null; then
        log "${RED}SRS未运行，无法获取状态${NC}"
        return 1
    fi
    
    # 检查API是否可用
    echo -e "\n${YELLOW}SRS API状态:${NC}"
    curl -s http://localhost:1985/api/v1/versions | grep -v "server_id"
    
    # 检查当前的流
    echo -e "\n${YELLOW}所有活跃流:${NC}"
    curl -s http://localhost:1985/api/v1/streams | grep -v "total"
    
    # 检查ffmpeg进程
    echo -e "\n${YELLOW}FFmpeg拉流进程:${NC}"
    sudo ps aux | grep ffmpeg | grep -v grep
    
    # 检查HLS文件夹内容
    echo -e "\n${YELLOW}HLS目录内容:${NC}"
    sudo find $SRS_DIR/srs/trunk/objs/nginx/html/hls -type f | sort
    
    # 检查HTTP服务器
    echo -e "\n${YELLOW}HTTP服务器状态:${NC}"
    curl -I http://localhost:8080/ 2>/dev/null | head -n 1
    
    # 显示最近的日志
    echo -e "\n${YELLOW}最近的SRS日志:${NC}"
    sudo tail -n 20 $SRS_DIR/srs/trunk/logs/srs.log
}

# 修复HLS目录和权限
fix_hls_folder() {
    log "修复HLS目录结构和权限..."
    
    # 创建完整的HLS路径结构
    sudo mkdir -p $SRS_DIR/srs/trunk/objs/nginx/html/hls/live
    
    # 设置广泛权限
    sudo chmod -R 777 $SRS_DIR/srs/trunk/objs/nginx/html
    
    log "HLS目录权限已修复"
}

# 手动测试推流
test_rtmp_hls() {
    log "进行FFmpeg测试推流..."
    
    # 停止之前的测试流
    sudo pkill -f "ffmpeg.*rtmp://127.0.0.1:1935/live/test" >/dev/null 2>&1
    
    # 生成测试视频 - 使用测试源推流
    sudo $FFMPEG_PATH -re -f lavfi -i testsrc=duration=60:size=640x360:rate=30 -pix_fmt yuv420p \
           -f lavfi -i sine=frequency=1000:duration=60 \
           -c:v libx264 -b:v 800k -c:a aac -b:a 128k \
           -f flv rtmp://127.0.0.1:1935/live/test > $SRS_DIR/srs/trunk/logs/test_stream.log 2>&1 &
    
    TEST_PID=$!
    
    # 等待HLS生成
    log "等待HLS文件生成，请稍候..."
    sleep 10
    
    # 检查文件是否生成
    TS_FILES=$(sudo find $SRS_DIR/srs/trunk/objs/nginx/html/hls -name "test-*.ts" | wc -l)
    
    if [ "$TS_FILES" -gt 0 ]; then
        log "测试成功! HLS文件已生成"
        sudo find $SRS_DIR/srs/trunk/objs/nginx/html/hls -type f | grep test | sort
        log "请访问: http://$(hostname -I | awk '{print $1}'):8080/hls/live/test.m3u8"
    else
        log "未检测到HLS文件生成，可能存在问题"
    fi
}

# 手动启动RTMP拉流
manual_start_ingest() {
    log "手动启动RTMP拉流..."
    
    # 检查RTMP URL是否设置
    if [ -z "$RTMP_URL" ]; then
        # 如果未设置，尝试从配置文件读取
        if [ -f "$SRS_CONF" ]; then
            RTMP_URL=$(grep -o "url.*rtmp://[^;]*" $SRS_CONF | head -1 | sed 's/url[[:space:]]*//g')
        fi
        
        # 如果仍未设置，提示用户
        if [ -z "$RTMP_URL" ]; then
            echo -e "${YELLOW}请输入RTMP源地址:${NC}"
            read -p "RTMP地址: " RTMP_URL
            
            if [ -z "$RTMP_URL" ]; then
                log "RTMP地址不能为空"
                return 1
            fi
        fi
    fi
    
    # 停止旧进程
    sudo pkill -f "ffmpeg.*rtmp://127.0.0.1:1935/live/drone" >/dev/null 2>&1
    
    # 使用ffmpeg手动拉流
    log "从 $RTMP_URL 拉流..."
    cd $SRS_DIR/srs/trunk
    sudo $FFMPEG_PATH -i "$RTMP_URL" -c copy -f flv rtmp://127.0.0.1:1935/live/drone > ./logs/ffmpeg_drone.log 2>&1 &
    
    # 等待启动
    sleep 3
    
    # 检查是否成功
    if sudo pgrep -f "ffmpeg.*rtmp://127.0.0.1:1935/live/drone" >/dev/null; then
        log "手动拉流启动成功!"
    else
        log "手动拉流可能失败，请查看日志:"
        sudo tail -n 20 ./logs/ffmpeg_drone.log
    fi
}

# HLS问题诊断和修复 - 一站式解决方案
diagnose_and_fix_hls() {
    log "开始诊断与修复HLS问题..."
    
    # 1. 确保SRS正在运行
    if ! sudo pgrep -f "objs/srs -c" >/dev/null; then
        log "SRS没有运行，尝试启动..."
        start_srs
    fi
    
    # 2. 修复HLS目录
    fix_hls_folder
    
    # 3. 检查拉流状态
    log "检查拉流状态..."
    INGEST_STATUS=$(curl -s http://localhost:1985/api/v1/streams | grep -i drone)
    if [ -z "$INGEST_STATUS" ]; then
        log "未检测到drone流，尝试手动启动拉流..."
        manual_start_ingest
    fi
    
    # 4. 尝试测试推流以验证HLS功能
    log "测试HLS功能..."
    test_rtmp_hls
    
    # 5. 验证M3U8文件是否存在
    sleep 5
    DRONE_M3U8="$SRS_DIR/srs/trunk/objs/nginx/html/hls/live/drone.m3u8"
    if sudo test -f "$DRONE_M3U8"; then
        log "找到drone.m3u8文件："
        sudo ls -la "$DRONE_M3U8"
        
        # 检查内容
        log "文件内容:"
        sudo cat "$DRONE_M3U8"
    else
        log "未找到drone.m3u8文件，问题可能是:"
        log "1. 拉流未成功"
        log "2. HLS转换失败"
        log "3. 文件路径错误"
        
        # 创建空目录确保路径正确
        sudo mkdir -p "$(dirname "$DRONE_M3U8")"
        sudo chmod -R 777 "$(dirname "$DRONE_M3U8")"
    fi
    
    # 6. 显示当前状态
    show_full_status
    
    # 7. 最终建议
    log "诊断与修复完成，请尝试以下地址:"
    log "- 手动拉流地址: http://$(hostname -I | awk '{print $1}'):8080/hls/live/drone.m3u8"
    log "- 测试流地址: http://$(hostname -I | awk '{print $1}'):8080/hls/live/test.m3u8"
    log "- HTTP-FLV地址: http://$(hostname -I | awk '{print $1}'):8080/live/drone.flv"
    log "- 请使用HTML播放器: http://$(hostname -I | awk '{print $1}'):8080/player.html"
    
    # 8. 如果测试流成功但实际流失败，提供进一步建议
    log "如果测试流能播放但实际流不能，请检查RTMP源是否可访问。"
}

# 创建简单的HTML播放器
create_player() {
    log "创建HTML播放器..."
    
    PLAYER_DIR="$SRS_DIR/srs/trunk/objs/nginx/html"
    sudo mkdir -p $PLAYER_DIR
    
    sudo tee $PLAYER_DIR/player.html > /dev/null << EOF
<!DOCTYPE html>
<html>
<head>
    <title>SRS流媒体播放器</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f0f0f0;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            text-align: center;
        }
        .player-container {
            margin: 20px 0;
        }
        video {
            width: 100%;
            background-color: #000;
        }
        .tabs {
            display: flex;
            margin-bottom: 10px;
        }
        .tab {
            padding: 10px 15px;
            background-color: #e0e0e0;
            margin-right: 5px;
            cursor: pointer;
            border-radius: 3px 3px 0 0;
        }
        .tab.active {
            background-color: #007BFF;
            color: white;
        }
        .url-display {
            margin: 10px 0;
            padding: 10px;
            background-color: #f8f8f8;
            border: 1px solid #ddd;
            border-radius: 3px;
            word-break: break-all;
        }
        .streams-selector {
            margin: 10px 0;
            padding: 10px;
            background-color: #f8f8f8;
            border: 1px solid #ddd;
            border-radius: 3px;
        }
        select {
            padding: 5px;
            border-radius: 3px;
        }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
    <script src="https://cdn.jsdelivr.net/npm/flv.js@latest"></script>
</head>
<body>
    <div class="container">
        <h1>SRS流媒体播放器</h1>
        
        <div class="tabs">
            <div class="tab active" id="tab-hls">HLS</div>
            <div class="tab" id="tab-flv">HTTP-FLV</div>
        </div>
        
        <div class="streams-selector">
            <label for="stream-select">选择流: </label>
            <select id="stream-select">
                <option value="drone">正常流 (drone)</option>
                <option value="test">测试流 (test)</option>
            </select>
        </div>
        
        <div class="player-container">
            <video id="video" controls></video>
            <div class="url-display" id="url-display"></div>
        </div>
    </div>
    
    <script>
        // 获取服务器域名/IP
        const host = window.location.hostname;
        const port = "8080";
        
        // DOM元素
        const video = document.getElementById('video');
        const urlDisplay = document.getElementById('url-display');
        const tabHls = document.getElementById('tab-hls');
        const tabFlv = document.getElementById('tab-flv');
        const streamSelect = document.getElementById('stream-select');
        
        let hlsPlayer = null;
        let flvPlayer = null;
        let currentMode = 'hls';
        let currentStream = 'drone';
        
        // 获取当前URL
        function getCurrentUrl() {
            if (currentMode === 'hls') {
                return "http://" + host + ":" + port + "/hls/live/" + currentStream + ".m3u8";
            } else {
                return "http://" + host + ":" + port + "/live/" + currentStream + ".flv";
            }
        }
        
        // 初始化HLS播放器
        function initHlsPlayer() {
            if (hlsPlayer) {
                hlsPlayer.destroy();
                hlsPlayer = null;
            }
            
            if (flvPlayer) {
                flvPlayer.destroy();
                flvPlayer = null;
            }
            
            currentMode = 'hls';
            const hlsUrl = getCurrentUrl();
            
            if (Hls.isSupported()) {
                hlsPlayer = new Hls({
                    liveSyncDuration: 1,
                    liveMaxLatencyDuration: 2,
                    liveDurationInfinity: true,
                    lowLatencyMode: true,
                    backBufferLength: 0
                });
                hlsPlayer.loadSource(hlsUrl);
                hlsPlayer.attachMedia(video);
                hlsPlayer.on(Hls.Events.MANIFEST_PARSED, function() {
                    video.play();
                });
                urlDisplay.textContent = hlsUrl;
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                video.src = hlsUrl;
                video.addEventListener('loadedmetadata', function() {
                    video.play();
                });
                urlDisplay.textContent = hlsUrl;
            } else {
                urlDisplay.textContent = "您的浏览器不支持HLS播放";
            }
        }
        
        // 初始化FLV播放器
        function initFlvPlayer() {
            if (hlsPlayer) {
                hlsPlayer.destroy();
                hlsPlayer = null;
            }
            
            if (flvPlayer) {
                flvPlayer.destroy();
                flvPlayer = null;
            }
            
            currentMode = 'flv';
            const flvUrl = getCurrentUrl();
            
            if (flvjs.isSupported()) {
                flvPlayer = flvjs.createPlayer({
                    type: 'flv',
                    url: flvUrl,
                    isLive: true,
                    hasAudio: true,
                    hasVideo: true
                }, {
                    enableStashBuffer: false,
                    stashInitialSize: 128,
                    lazyLoad: false
                });
                flvPlayer.attachMediaElement(video);
                flvPlayer.load();
                flvPlayer.play();
                urlDisplay.textContent = flvUrl;
            } else {
                urlDisplay.textContent = "您的浏览器不支持FLV播放";
            }
        }
        
        // 初始默认为HLS播放
        initHlsPlayer();
        
        // 标签切换事件
        tabHls.addEventListener('click', function() {
            tabHls.classList.add('active');
            tabFlv.classList.remove('active');
            initHlsPlayer();
        });
        
        tabFlv.addEventListener('click', function() {
            tabFlv.classList.add('active');
            tabHls.classList.remove('active');
            initFlvPlayer();
        });
        
        // 流选择变更事件
        streamSelect.addEventListener('change', function() {
            currentStream = streamSelect.value;
            if (currentMode === 'hls') {
                initHlsPlayer();
            } else {
                initFlvPlayer();
            }
        });
    </script>
</body>
</html>
EOF
    
    # 设置正确的权限
    sudo chmod 644 $PLAYER_DIR/player.html
    
    log "播放器已创建: http://$(hostname -I | awk '{print $1}'):8080/player.html"
}

# 使用更简单的纯ASCII菜单格式
show_menu() {
    echo -e "\n=========== SRS RTMP转HLS一键脚本 ============"
    echo -e "1. 安装SRS及依赖"
    echo -e "2. 配置SRS(设置RTMP源)"
    echo -e "3. 启动SRS服务"
    echo -e "4. 停止SRS服务"
    echo -e "5. 查看SRS状态"
    echo -e "6. 创建HTML播放器"
    echo -e "7. 诊断和修复HLS问题"
    echo -e "0. 退出"
    echo -e "===============================================\n"
    
    read -p "请输入选项 [0-7]: " choice
    
    case $choice in
        1)
            check_system
            install_dependencies
            install_srs
            ;;
        2)
            create_config
            ;;
        3)
            start_srs
            ;;
        4)
            stop_srs
            ;;
        5)
            status_srs
            ;;
        6)
            create_player
            ;;
        7)
            diagnose_and_fix_hls
            ;;
        0)
            echo -e "感谢使用，再见！"
            exit 0
            ;;
        *)
            echo -e "无效选项，请重新选择"
            ;;
    esac
}

# 脚本入口点
while true; do
    show_menu
    echo
    read -p "按回车键继续..."
done
