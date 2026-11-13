# fcitx5-zh-doctor

面向 Ubuntu / Debian 的 fcitx5 中文输入部署与诊断工具。

项目由安装脚本、自检工具和可独立分发的 `.deb` 包组成，用于将 fcitx5 配置为可直接使用的中文输入环境。

## 背景

Ubuntu 22.04 随附的 fcitx5（5.0.11 / 5.0.14）与 libime（1.0.11）存在三处默认配置问题，导致中文输入无法正常工作：

| 问题 | 表现 | 原因 |
| --- | --- | --- |
| 云拼音后端失效 | 候选列表中没有云输入结果 | 百度后端仍请求 `olime.baidu.com`，该接口已停止服务，返回 `{"status":"F","errno":"19"}` |
| 云拼音默认关闭 | 安装 `fcitx5-module-cloudpinyin` 后无效果 | `CloudPinyinEnabled` 默认为 `False` |
| 词库版本不匹配 | 词库文件已放入目录，候选词数量没有变化 | 上游 zhwiki 词库按新版 libime 编译，加载时报 `Invalid pinyin version` |

第三项尤其隐蔽：文件存在、权限正确、配置无误，但 fcitx5 启动日志中仅有单行错误，界面上没有任何提示。

现有教程与方案多聚焦于主题或词库单体，未覆盖上述版本适配问题，本项目对此提供自动化处理。

## 功能

- 安装依赖包，并将云拼音后端切换至 `GoogleCN`
- 启用云拼音（`CloudPinyinEnabled=True`），关闭下文联想（`Prediction=False`）
- 基于 zhwiki 源数据生成与本地 libime 版本匹配的词库，约 170 万条
- 安装绿色 Material 主题与文鼎楷体字体
- 提供 `doctor.sh`，逐项检测环境并输出对应修复命令
- 提供 `.deb`，安装时在目标机上编译词库，避免跨版本不兼容

## 安装

两种方式任选其一。

`.deb` 将词库写入系统目录 `/usr/share/fcitx5/pinyin/dictionaries/`，
脚本写入用户目录 `~/.local/share/fcitx5/pinyin/dictionaries/`。
同时使用会导致 fcitx5 加载两份词库；脚本会检测系统级词库并自动跳过，但仍建议只采用一种方式。

### 方式一：deb 包

适用于新机器或需要批量部署的场景。

```bash
sudo apt install ./fcitx5-zh-doctor_0.1.0_all.deb
```

`postinst` 会调用目标机上的 `libime_pinyindict` 编译词库，因此不受构建机 libime 版本影响。
安装完成后需注销并重新登录一次，使输入法环境变量生效。

### 方式二：安装脚本

```bash
git clone https://github.com/bingjiechen-THU/fcitx5-zh-doctor.git
cd fcitx5-zh-doctor
./install.sh
```

脚本为幂等操作，可重复执行：已安装的依赖包会跳过，版本兼容的词库会复用。
需要 apt 时会请求 sudo 权限。

## 自检

```bash
./doctor.sh
```

检查项包括：依赖包、fcitx5 进程、`~/.xinputrc`、输入法环境变量、云拼音开关与后端、
云接口连通性、词库与 libime 的兼容性、主题与字体。

每个失败项均附一条可执行的修复命令。退出码为失败项数量，可用于 CI 或自动化脚本。
部分环境（如尚未重新登录的会话）会出现环境变量告警，属预期行为。

## 默认配置

| 项目 | 值 |
| --- | --- |
| 云拼音后端 | `GoogleCN`（`www.google.cn/inputtools`） |
| 每页候选数 | 7 |
| 下文联想 | 关闭（`Prediction=False`） |
| 主题 | `Material-Color-green`，高亮色 `#43A047` |
| 字体 | `AR PL UKai CN 12`（文鼎楷体） |

## 自定义

| 配置项 | 文件 |
| --- | --- |
| 字体、主题 | `~/.config/fcitx5/conf/classicui.conf` |
| 间距、边距、高亮色 | `~/.local/share/fcitx5/themes/Material-Color-green/theme.conf` |
| 每页候选数、云拼音、联想 | `~/.config/fcitx5/conf/pinyin.conf` |

修改后重启输入法：

```bash
pkill -x fcitx5 && fcitx5 -d
```

必须先停止进程再修改文件。fcitx5 退出时会将内存中的配置写回磁盘，运行期间的修改会被覆盖。

### 更换楷体

系统软件源中仅提供文鼎楷体。如需使用方正楷体，将 `simkai.ttf` 复制到
`~/.local/share/fonts/`，执行 `fc-cache -fv`，再将上述配置中的 `AR PL UKai CN` 替换为 `KaiTi`。

## 卸载

```bash
# deb
sudo apt purge fcitx5-zh-doctor

# 脚本安装
./uninstall.sh                 # 保留输入法框架设置
./uninstall.sh --restore-im    # 同时将 im-config 切回自动检测
```

## 兼容性

- 主要适配 Ubuntu 22.04（fcitx5 5.0.14 / libime 1.0.11）
- Debian 12、Ubuntu 24.04 等较新发行版自带更新的 fcitx5，云拼音后端问题可能已修复
- 词库在安装时编译，更换 libime 版本无需重新打包

## 已知限制

- `GoogleCN` 接口在国内网络环境下可访问，但在出口策略严格的内网中可能被拦截，`doctor.sh` 可直接检测
- 词库约 170 万条，fcitx5 启动时间增加约 1 秒
- 仅支持拼音方案，不包含双拼与五笔

## 许可

- 代码：MIT，见 `LICENSE`
- 词库数据来自中文维基百科，遵循 CC BY-SA 4.0，见 `NOTICE`
- 主题基于 [fcitx5-material-color](https://github.com/hosxy/fcitx5-material-color) 修改，遵循其原许可

词库由 [felixonmars/fcitx5-pinyin-zhwiki](https://github.com/felixonmars/fcitx5-pinyin-zhwiki) 生成，本项目仅做格式转换与版本适配。
