Ниже алгоритм установки openvpn сервера с веб-панелью pritunl и базой mongodb 6.0 на VPS сервер c ОС Ubuntu 22.04 Jammy.
Подключаем репозиторий для pritunl на Ubuntu 22.04 Jammy:

# tee /etc/apt/sources.list.d/pritunl.list << EOF
deb http://repo.pritunl.com/stable/apt jammy main
EOF
# apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv 7568D9BB55FF9E5287D586017AE645C0CF8E292A
Подключаем репозиторий для mongoDB 6.x на Ubuntu 22.04 Jammy:

# tee /etc/apt/sources.list.d/mongodb-org-6.0.list << EOF
deb https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse
EOF
# wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
Обновляем базу пакетов и включаем поддержку wireguard (на всякий случай):

# apt update
# apt -y install wireguard wireguard-tools
Отключаем фаеврол по-умолчанию:

# ufw disable
Устанавливаем mongodb/pritunl/openvpn сервер, включаем их и добавляем в автозагрузку ОС:

# apt -y install pritunl mongodb-org
# systemctl enable mongod pritunl
# systemctl start mongod pritunl
Завершаем установку через веб-интерфейс в браузере по IP сервера:

https://server_ip/
Проверить версию mongodb базы можно командой по ssh:

# mongod --version
db version v6.0.4
Build Info: {
   "version": "6.0.4",
   "gitVersion": "44ff59461c1353638a71e710f385a566bcd2f547",
   "openSSLVersion": "OpenSSL 3.0.2 15 Mar 2022",
   "modules": [],
   "allocator": "tcmalloc",
   "environment": {
       "distmod": "ubuntu2204",
       "distarch": "x86_64",
       "target_arch": "x86_64"
