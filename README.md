# L4D2 服务器与插件管理器 (Linux 版)

## 简介

这是一款为 **Linux 平台**上的求生之路2（Left 4 Dead 2）专用服务器量身打造的全能管理工具。它使用稳定可靠的 Bash 语言编写，旨在提供从服务器部署、实例管理到插件维护的一站式解决方案，彻底终结手动管理的繁琐、易错和低效。

通过本工具，您可以轻松部署和更新服务器，管理多个服务器实例的启停，通过 Cron 设置定时任务，并以模块化的方式干净、无损地安装和移除 SourceMod 插件。

## 主要功能

  * **服务器部署与更新**
    脚本内置 SteamCMD 自动化功能。无论是首次安装还是日常更新 L4D2 服务器，只需一键即可完成，无需手动操作 SteamCMD。

  * **多实例管理**
    可以同时启动和管理多个服务器实例。您可以在配置中预设不同游戏模式（如战役、对抗）的启动参数，并通过菜单轻松启动或关闭它们。脚本通过 `screen` 会话进行管理，稳定且易于调试。

  * **自动化定时任务**
    内置强大的定时任务管理器，可以为任何预设的服务器实例创建“定时启动”和“定时关闭”的 Cron 任务。例如，实现服务器在每天晚上7点自动开启，凌晨2点自动关闭。

  * **一键安装/更新 SourceMod 与 MetaMod**
    只需将从官网下载的 `.tar.gz` 安装包放入指定文件夹，脚本即可自动识别最新版本并完成解压、安装以及关键引导文件 (`metamod.vdf`) 的创建。

  * **模块化的插件管理**
    每个插件（及其所有相关文件，如 `.smx`, `.cfg`, `.txt` 等）都存放于一个独立的文件夹中，管理思路清晰，插件之间互不干扰。

  * **可逆的安装与移除**
    安装插件时，脚本会自动记录该插件包含的所有文件清单。当你选择移除插件时，脚本会根据这份清单，精确地将服务器中对应的文件一一安全地移回其原始位置，确保服务器文件纯净。

  * **强大的兼容性与交互界面**
    所有操作均通过清晰的、支持键盘导航的可视化菜单完成，对新手服主非常友好。

## 使用方法

### 第一步：准备工作

1.  **系统要求：** 一台运行主流 Linux 发行版（如 Debian, Ubuntu, CentOS）的服务器。

2.  **依赖安装：** 脚本运行需要以下组件。请使用你的包管理器进行安装。

      * `bash` (需要 4.0 或更高版本)
      * `screen` (用于后台运行服务器实例)
      * `wget` (用于下载 SteamCMD)
      * `tar` (用于解压)
      * `rsync` (用于高效复制插件文件)

    **在 Debian / Ubuntu 上:**

    ```bash
    sudo apt-get update
    sudo apt-get install bash screen wget tar rsync
    ```

    **在 CentOS / RHEL 上:**

    ```bash
    sudo yum install bash screen wget tar rsync
    ```

3.  **创建目录结构：** 在你喜欢的位置（例如 `/home/steam/manager`）创建一个主管理文件夹，并将 `L4D2_Manager.sh` 脚本文件放入其中。

    ```
    /home/steam/manager/
    └── L4D2_Manager.sh     (本脚本)
    ```

      * 当你第一次运行脚本时，它会自动在同级目录下创建以下三个文件夹：
          * `Available_Plugins/`: 用于存放所有**待安装**的插件文件夹。
          * `Installed_Receipts/`: 用于存放已安装插件的回执文件（脚本自动管理，请勿手动修改）。
          * `SourceMod_Installers/`: 用于存放 SourceMod 和 MetaMod 的 `.tar.gz` 安装包。

### 第二步：配置脚本

1.  用 `nano`、`vim` 或任何文本编辑器打开 `L4D2_Manager.sh` 脚本文件。

    ```bash
    nano L4D2_Manager.sh
    ```

2.  找到脚本最上方的 **`用户配置区`**，并根据你的实际情况修改以下设置：

    ```bash
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
    # 4. (可选) 您的 Steam 用户名。
    #    如果在此处填写, 部署服务器时将自动使用此账户。
    #    留空则会在部署时询问您使用匿名还是个人账户登录。
    SteamLoginUser=""
    #
    # #################################################################
    ```

      * `ServerRoot`: **必须修改。** 这是你的 L4D2 专用服务器的根目录路径（即包含 `srcds_run` 的那个文件夹的路径）。
      * `SteamCMDDir`: **必须修改。** 这是 `steamcmd` 的目录。如果目录下的 `steamcmd.sh` 不存在，脚本在执行部署功能时会尝试自动下载。
      * `ServerInstances`: **强烈建议配置。** 在这里预设你想要运行的服务器实例。你可以自行调整启动参数，方便后续通过菜单一键启动或设置定时任务。
      * `SteamLoginUser`: **可选配置。** 留空则默认使用 `anonymous` 匿名登录。若要使用个人 Steam 账户更新（例如需要访问创意工坊内容），请在此处填写你的 Steam 用户名。

3.  保存并关闭文件。

### 第三步：运行脚本

1.  **添加执行权限** (首次使用，仅需操作一次):
    在终端中，进入脚本所在目录，并运行以下命令：

    ```bash
    chmod +x L4D2_Manager.sh
    ```

2.  **启动管理器**:

    ```bash
    ./L4D2_Manager.sh
    ```

### 第四步：使用菜单

脚本启动后，你会看到一个清晰的主菜单。根据屏幕上的提示输入对应的数字即可执行相应操作：

  * **操作 [1] 部署/更新 L4D2 服务器文件：**
    执行此项后，脚本将调用 SteamCMD 自动下载或更新 L4D2 专用服务器到你在配置中指定的 `ServerRoot` 目录。

  * **操作 [2] 管理服务器实例 (启动/关闭/定时)：**

      * **启动实例：** 从你在配置中预设的 `ServerInstances` 列表或手动模式中选择一个来启动。服务器将运行在独立的 `screen` 会话中。
      * **关闭实例：** 优雅地关闭一个由本脚本启动的、正在运行的服务器实例。
      * **定时任务管理：** 为预设的实例创建、查看或删除 `cron` 定时开关机任务。
      * **提示：** 你可以使用 `screen -r <会话名>` 连接到服务器后台控制台。

  * **操作 [3] 安装 / 更新 SourceMod 和 MetaMod：**
    将从官网下载的 **Linux 版本**的 `sourcemod-xxx.tar.gz` 和 `mmsource-xxx.tar.gz` 文件直接放入 `SourceMod_Installers` 文件夹内，然后执行此选项。

  * **操作 [4] 安装插件：**
    将插件文件夹放入 `Available_Plugins` 目录中，然后执行此选项。
    为确保能正确安装，每个插件的目录结构必须符合标准（根目录应包含 `addons`、`cfg` 等文件夹）：

    ```
    Available_Plugins/
    └── [插件名]/
        ├── addons/
        ├── cfg/
        └── ...等其他文件
    ```

  * **操作 [5] 移除插件：**
    脚本会列出所有已安装的插件。选择你想移除的插件即可。脚本会自动将其所有相关文件安全地移回 `Available_Plugins` 文件夹中，实现完美卸载。
