# binary-only 发布说明

这个目录用于准备公开的 binary-only 仓库内容，不要把业务源码同步出去。

## 建议的公开仓内容

- 根目录 `install.sh`
- `examples/config.json.example`
- GitHub Releases:
  - `dist-register-inbucket-linux-amd64`
  - `SHA256SUMS.txt`

## 建议流程

1. 在源码仓执行：

   ```bash
   bash dist_register_inbucket/release/scripts/build_linux_amd64.sh
   ```

2. 将以下文件复制到公开 binary-only 仓：

   - `dist_register_inbucket/release/install.sh`
   - `dist_register_inbucket/release/examples/config.json.example`

3. 将 `dist_register_inbucket/release/out/` 里的二进制与 `SHA256SUMS.txt` 上传到 GitHub Releases。

## 一键安装命令

```bash
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/digduggog/cpa-inbucket-worker-binaries/main/install.sh | bash -s -- \
--install-dir "/dan-runtime" \
--systemd \
--proxy "socks5://127.0.0.1:7890" \
--mail-provider "gptmail_vip_moe_temp_org_mix" \
--gptmail-rate-limit-rps "8" \
--gptmail-rate-limit-burst "16" \
--cpa-base-url "https://cpa.example.com/" \
--cpa-token "replace-me" \
--threads 20'
```

说明：

- 不传 `--domains-api-url` 时，会自动使用  
  ``${cpa_base_url%/}/v0/management/domains``
- 不传 `--mail-provider` 时，默认就是 `gptmail_vip_moe_temp_org_mix`
- 不传 `--gptmail-rate-limit-rps` / `--gptmail-rate-limit-burst` 时，默认 `8 / 16`
- `--proxy` 只用于 OpenAI 注册 / OAuth，邮件 provider 请求默认直连
- 传了真实 `--mail-api-url` / `--mail-api-key` 后，默认 mix 会额外轮到 `inbucket_web`
- 只有 `--mail-provider inbucket_web` 时，`--mail-api-url` / `--mail-api-key` 是硬性必填

## 重要约束

- 公开仓只放 installer / examples / binaries / checksums
- 不要把 `dist_register_inbucket/` 源码、`ncs_register.py`、其它 Python 源码推到公开仓
