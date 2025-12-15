from pathlib import Path

script_path = Path(__file__).absolute().parent
streamd_dir_path = script_path.parent
file_path = Path(script_path, "file_with_path")
proxy_domain_path = Path(script_path, "PROXY_DOMAIN")
log_file_path = Path(streamd_dir_path, "sync.log")
