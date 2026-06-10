#!/bin/sh
# Скрипт детальной диагностики логов
echo "--- [1] Проверка процесса ---"
pgrep amneziawg-go || echo "ОШИБКА: amneziawg-go не запущен!"

echo "--- [2] Системное время ---"
date

echo "--- [3] Доступность сервера (Ping) ---"
ping -c 2 167.17.183.41

echo "--- [4] Системный лог (logread) ---"
logread | tail -n 50

echo "--- [5] Ядерный лог (dmesg) ---"
dmesg | tail -n 20
