from typing import Optional

import requests

from ._logging import logger  # type: ignore # noqa
from .pathes import file_path, script_path, proxy_domain_path  # type: ignore # noqa


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


def send_post(url: str) -> None:
    res = requests.post(url)
    logger.warning(res.status_code)
    logger.warning(res.text)


def main() -> None:
    domain = read_proxy_domain()
    if not domain:
        logger.error("Ошибка: домен прокси сервера к боту не задан!")
        return
    proxy_url = f"https://{domain}/sync-gateway"
    send_post(proxy_url)
    write_script_dir()


def write_script_dir() -> None:
    with open(file_path, mode="w") as f:
        f.write(str(script_path))


if __name__ == "__main__":
    # noinspection PyBroadException
    try:
        main()
    except KeyboardInterrupt:
        logger.warning("Ctrl+C — остановка")
    except Exception:
        logger.exception("Произошла непредвиденная ошибка!")
    finally:
        logger.info("Завершение программы...")
