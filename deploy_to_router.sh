#!/bin/bash

# Скрипт автоматизированного деплоя AmneziaWG на OpenWrt роутер
# Выполняется на локальной машине пользователя

ROUTER_IP="192.168.1.1"
ROUTER_USER="root"
LOCAL_PROJECT_DIR="/home/dom/.gemini_storage/1/amneziawg-openwrt-deploy"
DEPLOY_ARCHIVE="awg_deploy.tar.gz"

echo "-------------------------------------------------------"
echo "   AmneziaWG 2.0 Remote Deployer for OpenWrt"
echo "-------------------------------------------------------"

# 1. Проверка доступности роутера
echo "[*] Проверка связи с роутером $ROUTER_IP..."
if ! ping -c 1 -W 2 "$ROUTER_IP" > /dev/null; then
    echo "[!] ОШИБКА: Роутер $ROUTER_IP не доступен."
    exit 1
fi

# 2. Установка sshpass если его нет (для интерактивного ввода пароля)
if ! command -v sshpass &> /dev/null; then
    echo "[*] Утилита sshpass не найдена. Попробуем установить..."
    sudo apt-get update && sudo apt-get install -y sshpass
fi

# 3. Запрос пароля (один раз на сессию)
read -s -p "Введите пароль для $ROUTER_USER@$ROUTER_IP: " SSH_PASS
echo ""

# 4. Подготовка архива для деплоя
echo "[*] Подготовка файлов для отправки..."
cd "$LOCAL_PROJECT_DIR" || exit 1

# Создаем временный список файлов для упаковки, чтобы не тащить лишнее
tar -czf "/tmp/$DEPLOY_ARCHIVE" \
    amneziawg-go \
    awg-new \
    amneziawg-start.sh \
    amneziawg-stop.sh \
    awg-watchdog.sh \
    amneziawg_init \
    amneziawg.lua \
    install.sh

# 5. Копирование файлов на роутер
echo "[*] Копирование архива на роутер..."
sshpass -p "$SSH_PASS" scp -O -o StrictHostKeyChecking=no "/tmp/$DEPLOY_ARCHIVE" "$ROUTER_USER@$ROUTER_IP:/tmp/"

if [ $? -ne 0 ]; then
    echo "[!] ОШИБКА при копировании файлов."
    exit 1
fi

# 6. Запуск установки на роутере
echo "[*] Распаковка и запуск инсталлятора на роутере..."
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$ROUTER_USER@$ROUTER_IP" << EOF
    cd /tmp
    tar -xzf $DEPLOY_ARCHIVE
    chmod +x install.sh
    ./install.sh
    rm $DEPLOY_ARCHIVE install.sh
EOF

if [ $? -eq 0 ]; then
    echo "-------------------------------------------------------"
    echo "[SUCCESS] AmneziaWG успешно развернут на роутере!"
    echo "[INFO] Перейдите в веб-интерфейс: http://$ROUTER_IP/cgi-bin/luci/admin/services/amneziawg"
    echo "-------------------------------------------------------"
else
    echo "[!] Произошла ошибка во время выполнения скрипта на роутере."
fi

# Очистка локального временного файла
rm "/tmp/$DEPLOY_ARCHIVE"
