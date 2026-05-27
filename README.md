Linux设置ROOT密钥登录 -自用

一个自动化配置SSH安全的Bash脚本，配置密钥登录、禁用密码登录。

## 功能特性</br>

- ✅ 自动创建并配置SSH密钥对
- ✅ 关闭密码登录，仅允许密钥认证
- ✅重新生成密钥对
- ✅显示现有密钥内容
- ✅保留现有密钥，仅配置 SSH

## 系统要求</br>

- Linux操作系统（支持CentOS 7+, Ubuntu 16.04+, Debian 9+）
- Root权限
- OpenSSH服务


## 手动保存私钥</br>

- 公钥和私钥都显示全部内容，自己手动保存。
- 之后私钥删不删随你。
- 手动复制整个内容（包括 -----BEGIN... 和 -----END... 全部内容），粘贴到一个新建的文本文件中，保存为 id_ed25519。


![Image text](https://s41.ax1x.com/2026/05/27/pmPjRfO.png)


## 一键命令下载脚本</br>

```
curl -o install.sh https://raw.githubusercontent.com/9izy/userkey/main/install.sh
```
运行脚本
```
bash install.sh
```
## 功能选项</br>

- 查看私钥或重新生成等等，都是运行脚本这个命令。 

![Image text](https://s41.ax1x.com/2026/05/27/pmii7He.png)

- 前提是没有改文件名！


运行脚本

```
bash install.sh
```


## 懒人专用</br>

我不想每次都手动配置，就这样。。。

如果服务器上有install.sh记得先把服务器的文件改名，不然就会覆盖掉！

下载好之后把下载的文件随便改个名，再把原来的install.sh改回来就行！

## 注意事项：</br>

先按回车键开始 60 秒倒计开始，再去【新终端】测试 SSH 能否登录！

如不需要密钥登录删除 sshd_config 然后把 sshd_config.bak 的.bak后缀删掉即可  路径:

```
/etc/ssh/sshd_config
```

密钥路径：

```
/root/.ssh
```

- 重启 SSH 服务

```
sudo systemctl restart sshd
```
