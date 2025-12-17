# Custom-Outline-VPN
**Кастомный OutlineVPN для Shadow-God VPN**

---

## 🚀 Установка

### Базовая установка кастомного Outline
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/main/install_server.sh)"
```

### Оптимизация конфигурации сервера
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/refs/heads/main/enchant_outline.sh)"
```

По умолчанию используется образ:  
`lobzikfase2/shadowgodbox:latest`

---

## 🌐 Настройка сервера в качестве шлюза (gate)

Скрипт `install_gate_syncer.sh` используется для настройки сервера в качестве шлюза.

### Базовый запуск (интерактивный ввод домена)
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/refs/heads/main/install_gate_syncer.sh)"
```

### Запуск с указанием домена через аргумент `--domain`
Рекомендуется для автоматизированных и headless-установок:

```bash
wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/refs/heads/main/install_gate_syncer.sh | \
sudo bash -s -- --domain "example-proxy.com"
```

Если аргумент `--domain` не передан или передан пустым,  
скрипт запросит домен интерактивно.

---

## ⚙️ Использование конкретного тега образа

```bash
export SB_IMAGE=lobzikfase2/shadowgodbox:latest && \
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/main/install_server.sh)"
```

---

## 🛠 Аргументы запуска install_server.sh

- `--hostname` — hostname для доступа к API и ключам  
- `--api-port` — порт для Management API  
- `--keys-port` — порт для Access Keys  

Чтобы флаги применялись корректно, нужно вызывать установку так:

```bash
# (Опционально: указываем версию образа)
# export SB_IMAGE=lobzikfase2/shadowgodbox:1.1 && \

wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/main/install_server.sh | \
sudo -E bash -s -- --keys-port 21824 --api-port 420
```

❌ Неправильный вариант (флаги не сработают):
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/main/install_server.sh)" \
 --keys-port 21824 --api-port 420
```

---

## 📦 Установка через локальный архив образа

1. Переносим архив на сервер:
```bash
scp shadowgodbox.tar <server-data>:~/
```

2. Загружаем образ в Docker:
```bash
cd ~ && sudo docker load -i shadowgodbox.tar && rm -rf shadowgodbox.tar
```

3. Тегируем образ:
```bash
sudo docker tag <image_id> lobzikfase2/shadowgodbox:latest
```

Или задаём переменную `SB_IMAGE` перед установкой.

---

## ⬆️ Обновление Outline

Для обновления сервера до последней версии образа или конкретного тега используется скрипт `update_outline.sh`.

### Обновить до последнего `latest`
```bash
wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/main/update_outline.sh | \
sudo -E bash
```

### Обновить до конкретного тега
```bash
wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/main/update_outline.sh | \
sudo -E bash -s -- -t 1.1
```

### Указать свой репозиторий и тег
```bash
wget -qO- https://raw.githubusercontent.com/Lobzikfase2/Custom-Outline-VPN/main/update_outline.sh | \
sudo -E bash -s -- -i lobzikfase2/shadowgodbox -t 1.1
```

---

## 🗑 Полный снос Outline с сервера
```bash
sudo docker stop shadowgodbox && \
sudo docker container rm -f shadowgodbox && \
sudo docker system prune -af && \
sudo docker image prune -af && \
sudo rm -rf /opt/outline && \
sudo docker ps && sudo docker volume ls
```

---

## 🔎 Проверка версии сервера

### Удалённо
```bash
curl -sS -4k "https://<s-ip>:<s-api-port>/<s-api-password>/server" | grep -o '"version":"[^"]*"' | cut -d'"' -f4
```

### Локально

1) С запросом на свой реальный IP:
```bash
curl -sS -4k "$(sudo sed -n 's/^apiUrl:\s*//p' /opt/outline/access.txt)/server" | grep -o '"version":"[^"]*"' | cut -d'"' -f4
```

2) Через localhost:
```bash
eval $(sudo sed -n 's/^apiUrl:https:\/\/[^:]*:\([0-9]*\)\/\(.*\)/PORT=\1 PASS=\2/p' /opt/outline/access.txt) && \
curl -sS -4k "https://127.0.0.1:$PORT/$PASS/server" | grep -o '"version":"[^"]*"' | cut -d'"' -f4
```
