from pathlib import Path

script_dir_path = Path(__file__).absolute().parent
log_file_path = Path(script_dir_path, "sync.log")

# TODO: вернуть
# proxy_domain_path = Path(streamd_dir_path, "PROXY_DOMAIN")
proxy_domain_path = Path(script_dir_path.parent, "PROXY_DOMAIN")

streamd_dir_path = Path("/etc/nginx/stream.d")
nginx_conf_path = Path(streamd_dir_path, "proxies.conf")
nginx_tmp_conf_path = Path(streamd_dir_path, "proxies.conf.tmp")
