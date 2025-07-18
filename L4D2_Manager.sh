#!/bin/bash

# =================================================================
# L4D2 服务器与插件管理器 2300.P (Linux 移植版)
# 作者: Q1en
# 功能: 部署/更新L4D2服务器, 安装/更新 SourceMod & MetaMod, 并管理插件、服务器实例。
# =================================================================

# --- Bash 版本检查 ---
if ((BASH_VERSINFO[0] < 4)); then
    echo "错误: 此脚本需要 Bash 4.0 或更高版本才能运行。"
    exit 1
fi

# #################### 用户配置区 (请务必修改!) ####################
#
# 1. 设置您的L4D2服务器安装目录 (此目录将包含 srcds_run 等文件)
#    例如: "/home/steam/l4d2server"
ServerRoot="/home/steam/l4d2server"
#
# 2. 设置 steamcmd.sh 的脚本目录。脚本将使用它来下载和更新服务器。
#    如果文件不存在，脚本会尝试自动下载。
#    例如: "/home/steam/steamcmd"
SteamCMDDir="/home/steam/steamcmd"
#
# 3. (可选) 预定义服务器实例配置
#    您可以在这里预设多个服务器的启动参数。
#    注意: 这是Bash的关联数组语法。
declare -A ServerInstances=(
    ["主服_战役"]="
        Port=27015
        HostName='[CN] My L4D2 Campaign Server'
        MaxPlayers=8
        StartMap='c1m1_hotel'
        ExtraParams='+sv_gametypes \"coop,realism,survival\"'
    "
    ["副服_对抗"]="
        Port=27016
        HostName='[CN] My L4D2 Versus Server'
        MaxPlayers=8
        StartMap='c5m1_waterfront'
        ExtraParams='+sv_gametypes \"versus,teamversus,scavenge\"'
    "
)
#
# #################################################################


# --- 脚本变量定义 ---
L4d2Dir="$ServerRoot/left4dead2" # L4D2游戏内容目录
ScriptDir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
InstallerDir="$ScriptDir/SourceMod_Installers"
PluginSourceDir="$ScriptDir/Available_Plugins"
ReceiptsDir="$ScriptDir/Installed_Receipts"
declare -A RunningProcesses # 用于存储正在运行的服务器进程信息 [InstanceName]="PID|Port"
ScriptVersion="2300.P"
IsSourceModInstalled=false
CronJobPrefix="L4D2Manager" # Cron定时任务的注释前缀

# --- 颜色定义 ---
C_RESET='\e[0m'
C_RED='\e[0;31m'
C_GREEN='\e[0;32m'
C_YELLOW='\e[0;33m'
C_CYAN='\e[0;36m'
C_WHITE_BG='\e[47m'
C_BLACK_FG='\e[30m'

# --- 初始化检查 ---
if [ ! -d "$L4d2Dir" ]; then
    echo -e "${C_CYAN}提示: 未找到求生之路2服务器的游戏目录 ($L4d2Dir)。${C_RESET}"
    echo -e "您可以稍后使用菜单中的 [部署服务器] 功能进行安装。"
    echo -e "配置的服务器安装目录: $ServerRoot"
    read -p "按回车键继续..."
fi

if [ -f "$L4d2Dir/addons/sourcemod/bin/sourcemod_mm.so" ]; then
    IsSourceModInstalled=true
fi

mkdir -p "$InstallerDir" "$PluginSourceDir" "$ReceiptsDir"


# --- 交互式菜单核心函数 ---
# $1: Title, $2: Array of items, $3: Single/Multi, $4: Confirm Key Char, $5: Confirm Key Name
function Show-InteractiveMenu {
    local title="$1"
    local -n items=$2 # Pass array by reference
    local selection_mode="$3"
    local confirm_key_char="$4"
    local confirm_key_name="$5"
    
    local current_index=0
    local -a selected_indices=()

    # Helper to check if an index is selected
    is_selected() {
        for sel_idx in "${selected_indices[@]}"; do
            if [[ $sel_idx -eq $1 ]]; then return 0; fi
        done
        return 1
    }

    while true; do
        clear
        echo -e "${C_YELLOW}$title${C_RESET}\n"
        for i in "${!items[@]}"; do
            local pointer="  "
            local display_item="${items[$i]}"
            
            if [[ $i -eq $current_index ]]; then pointer="> "; fi

            if [[ "$selection_mode" == "multi" ]]; then
                local checkbox="[ ]"
                if is_selected "$i"; then checkbox="[✓]"; fi
                display_item="$checkbox ${items[$i]}"
            fi

            if [[ $i -eq $current_index ]]; then
                echo -e "${C_WHITE_BG}${C_BLACK_FG}$pointer$display_item${C_RESET}"
            else
                echo -e "$pointer$display_item"
            fi
        done

        echo ""
        echo "-----------------------------------------------------------------"
        echo "  导航:        ↑ / ↓"
        if [[ "$selection_mode" == "multi" ]]; then
            echo "  选择/取消:   空格键 (Spacebar)"
            echo "  全选/反选:   A"
        fi
        echo "  确认操作:    $confirm_key_name (${confirm_key_char^^}) 或 Enter"
        echo "  返回:        Q"
        echo "-----------------------------------------------------------------"

        IFS= read -rsn1 key
        # Arrow keys are multi-byte sequences
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key
        fi

        case "$key" in
            '[A') # Up arrow
                current_index=$(( (current_index - 1 + ${#items[@]}) % ${#items[@]} ))
                ;;
            '[B') # Down arrow
                current_index=$(( (current_index + 1) % ${#items[@]} ))
                ;;
            ' ') # Spacebar for multi-selection
                if [[ "$selection_mode" == "multi" ]]; then
                    if is_selected "$current_index"; then
                        local new_selected=()
                        for idx in "${selected_indices[@]}"; do
                            if [[ $idx -ne $current_index ]]; then new_selected+=("$idx"); fi
                        done
                        selected_indices=("${new_selected[@]}")
                    else
                        selected_indices+=("$current_index")
                    fi
                fi
                ;;
            'a'|'A') # 'A' for select/deselect all
                 if [[ "$selection_mode" == "multi" ]]; then
                    if [[ ${#selected_indices[@]} -lt ${#items[@]} ]]; then
                        selected_indices=()
                        for i in "${!items[@]}"; do selected_indices+=("$i"); done
                    else
                        selected_indices=()
                    fi
                 fi
                ;;
            'q'|'Q') # Quit
                # To return an empty array, we echo nothing. The caller checks for empty string.
                return 1 
                ;;
            ''|$'\n'|"$confirm_key_char") # Enter or Confirm Key
                if [[ "$selection_mode" == "single" ]]; then
                    # Return the single selected item's text
                    echo "${items[$current_index]}"
                    return 0
                else
                    # Return a newline-separated list of selected items
                    for i in "${selected_indices[@]}"; do
                        echo "${items[$i]}"
                    done
                    return 0
                fi
                ;;
        esac
    done
}


# --- 辅助函数 ---
function Invoke-PluginInstallation {
    local pluginName="$1"
    local pluginPath="$PluginSourceDir/$pluginName"
    local receiptPath="$ReceiptsDir/$pluginName.receipt"
    echo -e "\n--- 开始安装 '$pluginName' ---"
    
    echo " > 正在创建文件清单..."
    # Create file list relative to the plugin directory
    (cd "$pluginPath" && find . -type f | sed 's|^\./||') > "$receiptPath"
    
    echo " > 正在将文件复制到服务器目录..."
    # rsync is great for this, preserving structure
    rsync -a "$pluginPath/" "$ServerRoot/"
    
    # Check rsync exit code
    if [ $? -eq 0 ]; then
        rm -rf "$pluginPath"
        echo -e "   ${C_GREEN}成功! 插件 '$pluginName' 已安装。${C_RESET}"
    else
        echo -e "   ${C_RED}错误! 安装插件 '$pluginName' 时复制文件失败。${C_RESET}"
    fi
}

function Invoke-PluginUninstallation {
    local pluginName="$1"
    local receiptPath="$ReceiptsDir/$pluginName.receipt"
    echo -e "\n--- 开始移除 '$pluginName' ---"
    
    local pluginReclaimFolder="$PluginSourceDir/$pluginName"
    mkdir -p "$pluginReclaimFolder"
    
    # Read each file from the receipt and move it
    while IFS= read -r relativePath || [[ -n "$relativePath" ]]; do
        local serverFile="$ServerRoot/$relativePath"
        local destinationFile="$pluginReclaimFolder/$relativePath"
        
        if [ -f "$serverFile" ]; then
            mkdir -p "$(dirname "$destinationFile")"
            mv "$serverFile" "$destinationFile"
        fi
    done < "$receiptPath"
    
    # Attempt to remove now-empty directories
    while IFS= read -r relativePath || [[ -n "$relativePath" ]]; do
        local dirOnServer="$ServerRoot/$(dirname "$relativePath")"
        # Check if dir exists and is empty
        if [ -d "$dirOnServer" ] && [ -z "$(ls -A "$dirOnServer")" ]; then
            rmdir "$dirOnServer" 2>/dev/null
        fi
    done < <(sort -r "$receiptPath") # Process deeper paths first

    rm -f "$receiptPath"
    echo -e " > ${C_GREEN}成功! 插件 '$pluginName' 的所有文件已被移回。${C_RESET}"
}


function Update-RunningProcessList {
    local pids_to_remove=()
    for instance_name in "${!RunningProcesses[@]}"; do
        local pid=$(echo "${RunningProcesses[$instance_name]}" | cut -d'|' -f1)
        # Check if process with PID exists
        if ! ps -p "$pid" > /dev/null; then
            pids_to_remove+=("$instance_name")
        fi
    done

    if [ ${#pids_to_remove[@]} -gt 0 ]; then
        echo -e "\n\n${C_YELLOW}检测到有 ${#pids_to_remove[@]} 个实例已在外部关闭，正在更新列表...${C_RESET}"
        for name in "${pids_to_remove[@]}"; do
            unset RunningProcesses["$name"]
        done
        sleep 1
    fi
}

# --- 核心功能函数 ---

function Deploy-L4D2Server {
    clear
    echo "==================== 部署L4D2专用服务器 ===================="
    echo -e "\n此功能将使用 SteamCMD 下载或更新 Left 4 Dead 2 Dedicated Server。"
    echo -e "${C_YELLOW}服务器将被安装到您配置的目录: $ServerRoot${C_RESET}"
    echo -e "将使用 SteamCMD 目录: $SteamCMDDir"
    echo ""
    
    local steamcmd_executable="$SteamCMDDir/steamcmd.sh"

    if [ ! -f "$steamcmd_executable" ]; then
        echo -e "${C_YELLOW}未找到 SteamCMD，将尝试自动下载...${C_RESET}"
        mkdir -p "$SteamCMDDir"
        local zip_path="$SteamCMDDir/steamcmd_linux.tar.gz"
        wget -O "$zip_path" "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
        if [ $? -ne 0 ]; then
            echo -e "${C_RED}下载 SteamCMD 失败。${C_RESET}"
            read -p "请手动下载 SteamCMD 并将其放置在 '$SteamCMDDir'。按回车键返回。"
            return
        fi
        tar -xvzf "$zip_path" -C "$SteamCMDDir"
        rm "$zip_path"
        echo -e "${C_GREEN}SteamCMD 下载并解压成功!${C_RESET}"
    fi

    mkdir -p "$ServerRoot"

    echo -e "\n准备就绪，即将开始执行 SteamCMD..."
    read -p "按回车键开始部署..."

    "$steamcmd_executable" +force_install_dir "$ServerRoot" +login anonymous +app_update 222860 validate +quit
    
    if [ $? -eq 0 ]; then
        echo -e "\n${C_GREEN}L4D2 服务器文件部署/更新成功!${C_RESET}"
    else
        echo -e "\n${C_YELLOW}SteamCMD 执行过程中可能出现问题。请检查上面的日志输出。${C_RESET}"
    fi

    echo "=========================================================="
    read -p $'\n按回车键返回主菜单...'
}


function Manage-ServerInstances {
    while true; do
        Update-RunningProcessList
        clear
        echo "==================== 服务器实例管理 ===================="
        echo -e "\n当前正在运行的实例:"
        if [ ${#RunningProcesses[@]} -eq 0 ]; then
            echo "  (无)"
        else
            for name in "${!RunningProcesses[@]}"; do
                local pid=$(echo "${RunningProcesses[$name]}" | cut -d'|' -f1)
                local port=$(echo "${RunningProcesses[$name]}" | cut -d'|' -f2)
                echo -e "  - ${C_GREEN}$name (端口: $port, PID: $pid)${C_RESET}"
            done
        fi
        echo -e "\n请选择操作:"
        echo "  1. 启动一个新的服务器实例"
        echo "  2. 关闭一个正在运行的实例"
        echo "  3. 服务器定时任务管理 (Cron)"
        echo -e "\n  Q. 返回主菜单"
        echo "========================================================"
        
        read -p "请输入选项编号并按回车: " choice
        case "$choice" in
            1) Start-L4D2ServerInstance ;;
            2) Stop-L4D2ServerInstance ;;
            3) Manage-ScheduledTasks ;;
            q|Q) return ;;
        esac
    done
}

function Start-L4D2ServerInstance {
    local srcds_path="$ServerRoot/srcds_run"
    if [ ! -f "$srcds_path" ]; then 
        echo -e "\n${C_RED}错误: 找不到 srcds_run。请先部署服务器。${C_RESET}"; read -p "按回车键返回..."; return 
    fi

    local -a instanceOptions
    for name in "${!ServerInstances[@]}"; do
        eval "${ServerInstances[$name]}" # Load variables Port, etc.
        instanceOptions+=("$name (端口: $Port)")
    done
    instanceOptions+=("手动配置新实例")

    local selected_str
    selected_str=$(Show-InteractiveMenu "请选择要启动的服务器实例配置" instanceOptions "single" "s" "启动")
    if [ -z "$selected_str" ]; then return; fi

    local Port HostName MaxPlayers StartMap ExtraParams Name
    if [[ "$selected_str" == "手动配置新实例" ]]; then
        echo -e "\n--- ${C_YELLOW}手动配置新实例${C_RESET} ---"
        read -p "请输入端口号 (例如 27015): " Port
        read -p "请输入服务器名称: " HostName
        read -p "请输入最大玩家数 (例如 8): " MaxPlayers
        read -p "请输入初始地图 (例如 c1m1_hotel): " StartMap
        read -p "请输入其他启动参数 (可留空): " ExtraParams
        Name="手动实例_port$Port"
    else
        # --- CORRECTED LINE ---
        local instanceName=$(echo "$selected_str" | awk '{print $1}')
        eval "${ServerInstances[$instanceName]}"
        Name="$instanceName"
    fi

    # Check if port is in use by a managed process
    for val in "${RunningProcesses[@]}"; do
        local running_port=$(echo "$val" | cut -d'|' -f2)
        if [[ "$running_port" == "$Port" ]]; then
            echo -e "\n${C_RED}错误: 端口 $Port 已被占用。${C_RESET}"; read -p "按回车键返回..."; return
        fi
    done

    local launchArgs="-console -game left4dead2 -insecure +sv_lan 0 +ip 0.0.0.0 -port $Port +maxplayers $MaxPlayers +map $StartMap +hostname \"$HostName\" $ExtraParams"
    echo -e "\n${C_CYAN}即将使用以下参数启动服务器:${C_RESET}"
    echo " $srcds_path $launchArgs"
    
    # Use nohup to detach the process, run in the server's root directory
    (cd "$ServerRoot" && nohup ./srcds_run $launchArgs >/dev/null 2>&1 &)
    local pid=$!
    
    if kill -0 $pid 2>/dev/null; then
        RunningProcesses["$Name"]="$pid|$Port"
        echo -e "\n${C_GREEN}服务器实例 '$Name' 已成功启动! (PID: $pid)${C_RESET}"
    else
        echo -e "\n${C_RED}启动服务器失败。${C_RESET}"
    fi
    read -p "按回车键返回..."
}

function Stop-L4D2ServerInstance {
    if [ ${#RunningProcesses[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}当前没有由本脚本启动的正在运行的实例。${C_RESET}"; read -p "按回车键返回..."; return
    fi
    
    local -a runningNames
    for name in "${!RunningProcesses[@]}"; do
        local pid=$(echo "${RunningProcesses[$name]}" | cut -d'|' -f1)
        runningNames+=("$name (PID: $pid)")
    done

    local selected_str
    selected_str=$(Show-InteractiveMenu "请选择要关闭的服务器实例" runningNames "single" "k" "关闭")
    if [ -z "$selected_str" ]; then return; fi
    
    # --- CORRECTED LINE ---
    local instanceNameToStop=$(echo "$selected_str" | awk '{print $1}')
    local pidToStop=$(echo "${RunningProcesses[$instanceNameToStop]}" | cut -d'|' -f1)

    echo -n "正在尝试关闭实例 '$instanceNameToStop' (PID: $pidToStop)..."
    kill -9 "$pidToStop" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${C_GREEN}进程已成功关闭。${C_RESET}"
    else
        echo -e "${C_RED}关闭进程失败，可能已被手动关闭。${C_RESET}"
    fi
    unset RunningProcesses["$instanceNameToStop"]
    read -p "按回车键返回..."
}

function Manage-ScheduledTasks {
    while true; do
        clear
        echo -e "${C_YELLOW}==================== 服务器定时任务管理 (Cron) ====================${C_RESET}"
        echo -e "\n此功能允许您创建、查看和删除服务器的定时任务 (cron jobs)。"
        echo -e "${C_CYAN}状态说明: [服务状态] - 任务注释 | 触发时间${C_RESET}"
        echo -e "\n现有任务:"
        
        local existing_tasks
        existing_tasks=$(crontab -l 2>/dev/null | grep "# $CronJobPrefix")
        
        if [ -n "$existing_tasks" ]; then
            while IFS= read -r task; do
                local comment=$(echo "$task" | sed "s/.*# //")
                local type=$(echo "$comment" | cut -d'_' -f2)
                local name=$(echo "$comment" | cut -d'_' -f3)
                local port=$(echo "$comment" | cut -d'_' -f4 | sed 's/Port//')
                local time_spec=$(echo "$task" | awk '{print $2 ":" $1}') # H:M

                # Check process status
                local status_text status_color
                if pgrep -f "srcds_run.*-port $port" > /dev/null; then
                    status_text="运行中"
                    status_color=$C_CYAN
                else
                    status_text="未运行"
                    status_color=$C_RED
                fi
                
                echo -e "[服务: ${status_color}${status_text}${C_RESET}] - $comment | 触发器: 每天 $time_spec"
            done <<< "$existing_tasks"
        else
            echo "  (未找到由本工具创建的定时任务)"
        fi
        
        echo -e "\n请选择操作:"
        echo "  1. 新建 - 定时启动任务"
        echo "  2. 新建 - 定时停止任务"
        echo "  3. 查看并删除现有任务"
        echo -e "\n  Q. 返回服务器实例管理"
        echo "==========================================================="

        read -p "请输入选项编号并按回车: " choice
        case "$choice" in
            "1") New-ServerScheduledTask "Start" ;;
            "2") New-ServerScheduledTask "Stop" ;;
            "3") View-DeleteScheduledTasks ;;
            "q"|"Q") return ;;
        esac
    done
}


function New-ServerScheduledTask {
    local actionType="$1"
    local actionTypeDisplay="启动"
    if [[ "$actionType" == "Stop" ]]; then actionTypeDisplay="停止"; fi

    clear
    local -a instanceOptions=("${!ServerInstances[@]}")
    if [ ${#instanceOptions[@]} -eq 0 ]; then
        echo -e "${C_RED}错误: 脚本中未预定义任何服务器实例 (\`ServerInstances\`)。${C_RESET}"; read -p "按回车键返回..."; return
    fi

    local selectedInstanceName
    selectedInstanceName=$(Show-InteractiveMenu "请选择要为其创建定时 [${actionTypeDisplay}] 任务的实例" instanceOptions "single" "c" "选择")
    if [ -z "$selectedInstanceName" ]; then return; fi

    eval "${ServerInstances[$selectedInstanceName]}" # Load Port, etc.

    local time regex="^([01]?[0-9]|2[0-3]):[0-5][0-9]$"
    while true; do
        read -p $"\n请输入每天定时${actionTypeDisplay}的时间 (24小时制, 格式 HH:mm, 例如 22:30): " time
        if [[ $time =~ $regex ]]; then
            break
        else
            echo -e "${C_RED}时间格式错误，请输入有效的 HH:mm 格式。${C_RESET}"
        fi
    done

    local minute=$(echo "$time" | cut -d: -f2)
    local hour=$(echo "$time" | cut -d: -f1)
    # Cron needs leading zeros removed for some implementations, so let's strip them
    minute=$((10#$minute))
    hour=$((10#$hour))

    local taskComment="$CronJobPrefix_${actionType}_${selectedInstanceName}_Port${Port}"
    local command_to_run
    
    if [[ "$actionType" == "Start" ]]; then
        local srcdsFullPath="$ServerRoot/srcds_run"
        local srcdsArgs="-console -game left4dead2 -insecure +sv_lan 0 +ip 0.0.0.0 -port $Port +maxplayers $MaxPlayers +map $StartMap +hostname \"$HostName\" $ExtraParams"
        # The command needs to cd to the right directory
        command_to_run="cd \"$ServerRoot\" && ./srcds_run $srcdsArgs"
    else # Stop
        # pkill is perfect for this, -f checks the full command line
        command_to_run="pkill -f \"srcds_run.*-port $Port\""
    fi
    
    local cron_line="$minute $hour * * * $command_to_run # $taskComment"

    echo -e "\n--- ${C_CYAN}任务详情预览${C_RESET} ---"
    echo "任务注释: $taskComment"
    echo "执行用户: $(whoami)"
    echo "执行命令: $command_to_run"
    echo "触发时间: 每天 $time"
    echo "----------------------"
    
    # Remove existing task with the same comment before adding the new one
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null | grep -v "# $taskComment")
    
    echo "$current_crontab" > mycron
    echo "$cron_line" >> mycron
    crontab mycron
    rm mycron
    
    echo -e "\n${C_GREEN}成功创建/更新了定时任务 '$taskComment'!${C_RESET}"
    read -p "按回车键返回..."
}

function View-DeleteScheduledTasks {
    while true; do
        clear
        echo -e "${C_YELLOW}==================== 查看并删除定时任务 ====================${C_RESET}"
        
        local -a taskDisplayList
        # Read tasks into an array
        while IFS= read -r task; do
            if [[ -n "$task" ]]; then
                local comment=$(echo "$task" | sed "s/.*# //")
                local time_spec=$(echo "$task" | awk '{print $2 ":" $1}')
                taskDisplayList+=("$comment | 触发器: 每天 $time_spec")
            fi
        done < <(crontab -l 2>/dev/null | grep "# $CronJobPrefix")

        if [ ${#taskDisplayList[@]} -eq 0 ]; then
            echo -e "\n没有找到由本工具创建的定时任务。"
            read -p "按回车键返回..."
            return
        fi
        
        local selected_output
        selected_output=$(Show-InteractiveMenu "请选择要删除的定时任务 (可多选)" taskDisplayList "multi" "d" "删除")
        if [ -z "$selected_output" ]; then return; fi
        
        local -a selectedToDelete
        mapfile -t selectedToDelete <<< "$selected_output"

        clear
        echo "--- 开始删除任务 ---"
        local crontab_content=$(crontab -l 2>/dev/null)

        for item in "${selectedToDelete[@]}"; do
            local taskCommentToDelete=$(echo "$item" | cut -d'|' -f1 | sed 's/ *$//g')
            echo -n "正在删除任务: '$taskCommentToDelete'..."
            # Use grep -v to filter out the line with the matching comment
            crontab_content=$(echo "$crontab_content" | grep -v "# $taskCommentToDelete")
            echo -e "${C_GREEN}  成功!${C_RESET}"
        done
        
        # Install the new, filtered crontab
        if [[ -z "$crontab_content" ]]; then
            crontab -r # Remove crontab if it's empty
        else
            echo "$crontab_content" | crontab -
        fi
        
        echo "--------------------"
        read -p $'\n删除操作已完成，按回车键返回...'
    done
}


function Install-SourceModAndMetaMod {
    clear
    echo "==================== 安装 SourceMod & MetaMod ===================="
    if [ ! -f "$ServerRoot/srcds_run" ]; then
        echo -e "\n${C_RED}错误: 服务器尚未部署 (找不到srcds_run)。${C_RESET}"
        echo "请先从主菜单选择 [部署服务器] 选项。"
        read -p "按回车键返回..."; return
    fi
    echo -e "\n此功能将自动解压并安装最新版的 SourceMod 和 MetaMod。\n请确保您已完成以下步骤:"
    echo "1. 从官网下载了 SourceMod 和 MetaMod:Source 的 ${C_YELLOW}Linux 版本${C_RESET}。"
    echo "   - MetaMod: https://www.sourcemm.net/downloads.php"
    echo "   - SourceMod: https://www.sourcemod.net/downloads.php"
    echo -e "2. 将下载的 .tar.gz 文件放入以下目录: \n   $InstallerDir"
    read -p $'\n准备就绪后，按回车键开始安装...' ; echo ""

    # Note: Use -maxdepth 1 to avoid searching in subdirs. Sort to get latest version.
    local metamod_tar=$(find "$InstallerDir" -maxdepth 1 -name "mmsource-*.tar.gz" | sort -V | tail -n 1)
    if [ -n "$metamod_tar" ]; then
        echo "发现 MetaMod 安装包: $(basename "$metamod_tar")"
        echo "正在解压到服务器目录..."
        if tar -xzf "$metamod_tar" -C "$L4d2Dir"; then
            echo -e "${C_GREEN}解压完成。${C_RESET}"
            echo "正在创建 'metamod.vdf' 以引导服务器加载..."
            # Using -e to interpret the escape sequences
            echo -e "\"Plugin\"\n{\n\t\"file\"\t\"addons/metamod/bin/server\"\n}" > "$L4d2Dir/metamod.vdf"
            echo -e "${C_GREEN}'metamod.vdf' 创建成功!${C_RESET}\n"
        else
            echo -e "${C_RED}解压 MetaMod 时出错。${C_RESET}\n"
        fi
    else
        echo -e "${C_YELLOW}警告: 在 '$InstallerDir' 中未找到 MetaMod 的 .tar.gz 安装包。${C_RESET}\n"
    fi
    
    local sourcemod_tar=$(find "$InstallerDir" -maxdepth 1 -name "sourcemod-*.tar.gz" | sort -V | tail -n 1)
    if [ -n "$sourcemod_tar" ]; then
        echo "发现 SourceMod 安装包: $(basename "$sourcemod_tar")"
        echo "正在解压到服务器目录..."
        if tar -xzf "$sourcemod_tar" -C "$L4d2Dir"; then
            echo -e "${C_GREEN}解压完成。${C_RESET}\n"
        else
            echo -e "${C_RED}解压 SourceMod 时出错。${C_RESET}\n"
        fi
    else
        echo -e "${C_YELLOW}警告: 在 '$InstallerDir' 中未找到 SourceMod 的 .tar.gz 安装包。${C_RESET}\n"
    fi

    echo -e "${C_CYAN}=======================================================\n 安装流程执行完毕!${C_RESET}"
    echo " 请重启您的L4D2服务器以应用所有更改。"
    echo " 重启后, 您可以重新运行此脚本来管理插件。"
    echo "======================================================="

    if [ -f "$L4d2Dir/addons/sourcemod/bin/sourcemod_mm.so" ]; then 
        IsSourceModInstalled=true 
    fi
    read -p "按回车键返回主菜单..."
}

function Install-L4D2Plugin {
    if ! $IsSourceModInstalled; then 
        echo -e "\n${C_RED}错误: SourceMod尚未安装，无法管理插件。${C_RESET}"; read -p "请先安装SourceMod。按回车键返回..."; return 
    fi
    
    local -a availablePlugins
    for d in "$PluginSourceDir"/*/; do
        # Check if it's a directory
        [ -d "$d" ] || continue
        local dirname=$(basename "$d")
        if [ ! -f "$ReceiptsDir/$dirname.receipt" ]; then
            availablePlugins+=("$dirname")
        fi
    done

    if [ ${#availablePlugins[@]} -eq 0 ]; then
        clear; echo "没有找到可安装的新插件。"; echo "请将插件文件夹放入 '$PluginSourceDir' 目录中。"; read -p "按回车键返回主菜单..."; return
    fi
    
    local selected_output
    selected_output=$(Show-InteractiveMenu "请选择要安装的插件" availablePlugins "multi" "i" "安装")
    clear
    if [ -z "$selected_output" ]; then 
        echo "未选择任何插件或操作已取消。"; read -p "按回车键返回主菜单..."; return
    fi

    while IFS= read -r pluginName; do
        Invoke-PluginInstallation "$pluginName"
    done <<< "$selected_output"

    echo -e "\n\n${C_CYAN}所有选定的插件均已处理完毕。${C_RESET}"; read -p "按回车键返回主菜单..."
}

function Uninstall-L4D2Plugin {
    if ! $IsSourceModInstalled; then
        echo -e "\n${C_RED}错误: SourceMod尚未安装，无法管理插件。${C_RESET}"; read -p "请先安装SourceMod。按回车键返回..."; return
    fi
    
    local -a installedPlugins
    for f in "$ReceiptsDir"/*.receipt; do
        # Check if file exists to prevent issues with empty dir
        [ -e "$f" ] || continue
        installedPlugins+=("$(basename "$f" .receipt)")
    done

    if [ ${#installedPlugins[@]} -eq 0 ]; then
        clear; echo "当前没有任何已安装的插件。"; read -p "按回车键返回主菜单..."; return
    fi

    local selected_output
    selected_output=$(Show-InteractiveMenu "请选择要移除的插件" installedPlugins "multi" "r" "移除")
    clear
    if [ -z "$selected_output" ]; then
        echo "未选择任何插件或操作已取消。"; read -p "按回车键返回主菜单..."; return
    fi

    while IFS= read -r pluginName; do
        Invoke-PluginUninstallation "$pluginName"
    done <<< "$selected_output"
    
    echo -e "\n\n${C_CYAN}所有选定的插件均已处理完毕。${C_RESET}"; read -p "按回车键返回主菜单..."
}

# --- 主菜单与循环 ---
function Show-Menu {
    clear
    echo "========================================================"
    echo "   L4D2 服务器与插件管理器 $ScriptVersion"
    echo "========================================================"
    echo ""
    echo " 服务器安装目录: $ServerRoot"

    if [ -f "$ServerRoot/srcds_run" ]; then
        echo -e " ${C_GREEN}服务器状态: 已部署${C_RESET}"
    else
        echo -e " ${C_YELLOW}服务器状态: 未部署${C_RESET}"
    fi

    if [ -f "$L4d2Dir/addons/sourcemod/bin/sourcemod_mm.so" ]; then
        IsSourceModInstalled=true
        echo -e " ${C_GREEN}SourceMod 状态: 已安装${C_RESET}"
    else
        IsSourceModInstalled=false
        echo -e " ${C_YELLOW}SourceMod 状态: 未找到!${C_RESET}"
    fi

    if [ ${#RunningProcesses[@]} -gt 0 ]; then
        echo -e " ${C_CYAN}运行中实例数: ${#RunningProcesses[@]}${C_RESET}"
    fi

    echo -e "\n ================ 服务器管理 ================"
    echo "   1. 部署/更新 L4D2 服务器文件"
    echo "   2. 管理服务器实例 (启动/关闭/定时)"
    echo -e "\n ================ 插件管理 ================"
    echo "   3. 安装 / 更新 SourceMod 和 MetaMod"
    echo "   4. 安装插件"
    echo "   5. 移除插件"
    echo -e "\n   Q. 退出\n"
    echo "========================================================"
}

# 脚本主循环
while true; do
    Show-Menu
    read -p "请输入选项编号并按回车: " choice
    case "$choice" in
        "1") Deploy-L4D2Server ;;
        "2") Manage-ServerInstances ;;
        "3") Install-SourceModAndMetaMod ;;
        "4") Install-L4D2Plugin ;;
        "5") Uninstall-L4D2Plugin ;;
        "q"|"Q") 
            if [ ${#RunningProcesses[@]} -gt 0 ]; then
                echo -e "\n${C_YELLOW}警告: 有 ${#RunningProcesses[@]} 个服务器实例仍在运行。${C_RESET}"
                read -p "退出脚本不会关闭这些服务器。确认退出吗? (y/n): " confirm
                if [[ "$confirm" != "y" ]]; then
                    continue
                fi
            fi
            echo "正在退出..."; exit 0 
            ;;
    esac
done