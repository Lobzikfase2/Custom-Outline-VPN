import os
import subprocess
import time
from typing import Optional

import requests

from .logger import logger  # type: ignore # noqa
from .pathes import (  # type: ignore # noqa
    script_dir_path,
    proxy_domain_path,
    streamd_dir_path,
    nginx_conf_path,
    nginx_tmp_conf_path,
)
from .utils import make_safe_request  # type: ignore # noqa


def read_proxy_domain() -> Optional[str]:
    # noinspection PyBroadException
    try:
        with open(proxy_domain_path, mode="r", encoding="utf-8") as f:
            proxy_domain = f.read().strip()
    except Exception:
        return None

    if proxy_domain:
        return proxy_domain
    return None


def get_sync_data(url: str) -> dict | None:
    logger.info(f"запрашиваю данные для синхронизации...")
    return make_safe_request(
        req_func=lambda: requests.get(url, timeout=5), json=True, retries_count=3
    )


def mark_as_synced(url: str, state_timestamp: float) -> None:
    logger.info(f"отмечаю шлюз, как синхронизированный по событию [{state_timestamp}]...")
    payload = {
        "state_timestamp": state_timestamp,
    }
    make_safe_request(
        req_func=lambda: requests.post(url, json=payload, timeout=5), json=False, retries_count=5
    )


def validate_sync_data(data: dict) -> bool:
    sync_required = data.get("sync_required", None)
    if sync_required is None:
        return False
    if not sync_required:
        return True

    state_timestamp = data.get("state_timestamp", None)
    if state_timestamp is None:
        return False

    servers = data.get("servers", None)
    if not isinstance(servers, list):
        return False
    server: dict
    for server in servers:
        ip = server.get("ip", None)
        vpn_port = server.get("vpn_port", None)
        gateway_port = server.get("gateway_port", None)
        if not (ip and vpn_port and gateway_port):
            return False
    return True


def build_nginx_conf_string(servers: list[dict]) -> str:
    logger.info("формирую новую строку конфигурации nginx...")
    conf_parts = []
    for server in servers:
        ip = server["ip"]
        vpn_port = server["vpn_port"]
        gateway_port = server["gateway_port"]
        conf_part = (
            "server {\n"
            f"    listen {gateway_port} reuseport;\n"  # noqa
            f"    proxy_pass {ip}:{vpn_port}\n"
            "}\n\n"
            "server {\n"
            f"    listen {gateway_port} udp reuseport;\n"  # noqa
            f"    proxy_pass {ip}:{vpn_port}\n"
            "}\n"
        )
        conf_parts.append(conf_part)
    return "\n".join(conf_parts)


def update_nginx_conf_file(new_conf: str) -> None:
    logger.info(f"обновляю конфигурационный файл nginx: {nginx_conf_path}...")
    nginx_tmp_conf_path.write_text(new_conf, encoding="utf-8")
    nginx_tmp_conf_path.replace(nginx_conf_path)
    logger.info("конфигурация nginx успешно обновлена")


def change_nginx_conf_file_owner() -> None:
    logger.info("изменяю владельца файла конфигурации на www-data...")
    subprocess.run(["chown", "www-data:www-data", str(nginx_conf_path)], check=True)
    logger.info("владелец файла конфигурации успешно изменен")


def restart_nginx() -> bool:
    logger.info("перезапускаю nginx...")
    subprocess.run(["systemctl", "restart", "nginx"], check=True)
    time.sleep(1)
    logger.info("проверяю состояние nginx...")
    result = subprocess.run(["systemctl", "is-active", "nginx"], capture_output=True, text=True)
    if result.returncode == 0:
        logger.info("nginx успешно перезапущен")
        return True
    else:
        logger.info("nginx не смог перезапуститься")
        return False


def main() -> None:
    if not streamd_dir_path.is_dir():
        logger.error(f"Ошибка: директория отсутствует: {streamd_dir_path}")
        return
    domain = read_proxy_domain()
    if not domain:
        logger.error("Ошибка: домен прокси сервера к боту не задан!")
        return
    sync_url = f"https://{domain}/sync-gateway"

    logger.info("========== ЗАПУСК СИНХРОНИЗАЦИИ ШЛЮЗА ==========")
    logger.info(f"адрес синхронизации: {sync_url}")

    sync_data = get_sync_data(url=sync_url)
    if not sync_data:
        logger.warning("данные для синхронизации не были получены!")
        return

    if not validate_sync_data(sync_data):
        logger.warning("данные для синхронизации не валидны!")
        return
    logger.debug("данные для синхронизации были успешно получены")

    sync_required = sync_data["sync_required"]
    if sync_required:
        logger.info("зафиксировано изменение в системе")
        state_timestamp = sync_data["state_timestamp"]
        logger.info(f"timestamp события: {state_timestamp}")

        update_nginx_conf_file(build_nginx_conf_string(sync_data["servers"]))
        change_nginx_conf_file_owner()
        if not restart_nginx():
            raise KeyboardInterrupt

        mark_as_synced(url=sync_url, state_timestamp=state_timestamp)
    else:
        logger.info("не зафиксировано изменений в системе")
    logger.info("================================================")


# cd /home/coder/Projects/Shadow_God_VPN/Main-Project/dev/gates
# PYTHONPATH=$(pwd) poetry run python -m gate_syncer.gate_syncer
# sudo -E env "PATH=$PATH" PYTHONPATH=$(pwd) poetry run python -m gate_syncer.gate_syncer
if __name__ == "__main__":
    logger.info("синхронизация шлюза...")
    # noinspection PyBroadException
    try:
        if os.geteuid() != 0:
            logger.error("Ошибка: скрипт должен быть запущен с sudo!")
            raise KeyboardInterrupt
        main()
        logger.info("синхронизация завершена")
    except KeyboardInterrupt:
        logger.warning("синхронизация остановлена")
    except Exception:
        logger.warning("синхронизация была прервана!")
