import logging
import time
from logging import Formatter, StreamHandler, FileHandler
from typing import Optional

from .pathes import log_file_path  # type: ignore # noqa

CONSOLE_LOG_FORMAT = "%(asctime)s | " "line: %(lineno)-3d | " "%(message)s"  # noqa
FILE_LOG_FORMAT = "%(asctime)s | %(levelname)-8s | " "%(filename)s:%(lineno)d - %(message)s"  # noqa

logging.getLogger("urllib3").setLevel(logging.WARNING)
logging.getLogger("requests").setLevel(logging.WARNING)


class UTCFormatter(Formatter):
    @staticmethod
    def converter(timestamp: Optional[float]) -> time.struct_time:
        return time.gmtime(timestamp)


def setup_logger() -> logging.Logger:
    _logger = logging.getLogger()
    _logger.setLevel(logging.DEBUG)

    console_handler = StreamHandler()
    console_handler.setLevel(logging.DEBUG)
    console_handler.setFormatter(
        UTCFormatter(
            CONSOLE_LOG_FORMAT,
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )

    file_handler = FileHandler(log_file_path)
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(
        UTCFormatter(
            FILE_LOG_FORMAT,
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )

    _logger.addHandler(console_handler)
    _logger.addHandler(file_handler)

    return _logger


# TODO: Сделать ещё ротацию логов как-нить
logger = setup_logger()
