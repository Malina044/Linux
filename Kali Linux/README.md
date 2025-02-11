Kali Linux



________________________________________

Брутфорс

_________________


Извлечь хеш пароля из ZIP-файла
Для работы с John the Ripper нам нужен хеш пароля архива. Извлеки его с помощью утилиты zip2john:

zip2john example.zip > hash.txt

Это создаст файл hash.txt с хешем пароля.

john --incremental hash.txt

john --show hash.txt
