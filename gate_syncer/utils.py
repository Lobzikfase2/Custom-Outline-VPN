import time
from typing import Callable

import requests


def make_safe_request(
    req_func: Callable[[], requests.Response], json: bool, retries_count: int
) -> dict | None:
    errors_count = 0
    while errors_count < retries_count:
        try:
            response = req_func()
        except requests.exceptions.RequestException:
            errors_count += 1
            time.sleep(3)
            continue
        match response.status_code:
            case 200:
                pass
            case 404:
                return None
            case _:
                errors_count += 1
                time.sleep(3)
                continue
        if not json:
            return None
        try:
            data = response.json()
            if not data or not isinstance(data, dict):
                raise requests.exceptions.InvalidJSONError
            break
        except requests.exceptions.InvalidJSONError:
            errors_count += 1
            time.sleep(3)
            continue
    # Если успешный ответ так и не был получен
    else:
        return None
    return data
