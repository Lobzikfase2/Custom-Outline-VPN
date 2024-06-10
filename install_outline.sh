#!/bin/bash

echo "======== Outline Shadow-God Installation ========"

# Проверка отсутствия git lfs
if ! command -v git-lfs >/dev/null 2>&1; then
    # Скачиваем архив с git-lfs
    wget https://github.com/git-lfs/git-lfs/releases/download/v3.5.1/git-lfs-linux-amd64-v3.5.1.tar.gz
    # Распаковываем и удаляем архив
    tar -xf git-lfs-linux-amd64-v3.5.1.tar.gz && rm git-lfs-linux-amd64-v3.5.1.tar.gz
    # Выполняем скрипт установки
    cd git-lfs-3.5.1 && sudo chmod ugo+x install.sh && sudo ./install.sh
    # Удаляем установочные файлы git-lfs
    cd ../ && rm -rf git-lfs-3.5.1
    # Инициализируем git-lfs
    #git lfs install
fi

# Скачиваем репозиторий к себе
git clone "https://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@github.com/Lobzikfase2/Custom-Outline-VPN.git" && cd Custom-Outline-VPN && git lfs pull
# Устанавливаем кастомный docker образ shadowbox из архива
docker load -i shadowgodbox.tar
# Выполняем установку Outline
sudo chmod ugo+x install_server.sh && ./install_server.sh
# Удаляем установочные файлы Outline
cd ../ && rm -rf Custom-Outline-VPN

echo "====== Installation completed successfully ======"
