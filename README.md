# TerraMA2Q Docker

Instruções de instalação e configuração do projeto TerraMA2Q com Docker.

## Requisitos

- Docker
- Docker-compose
- Git

## Configurações

Defina o arquivo `.env`:
```bash
# Para uso local
cp .env.example-local .env

# Para uso externo
cp .env.example-external .env
```

As configurações padrões são carregadas a partir do arquivo `.env.default`. Para sobreescrever tais configurações, defina as váriaveis no arquivo `.env`, por exemplo:
```bash
# Para definir uma nova senha para o banco de dados.
POSTGRES_PASSWORD="novasenha"
```

Com isso, a nova senha do banco será, `novasenha`.

### Configuração local

Caso a inteção seja apenas uso na máquina local, é necessários a configuração de hostnames.
No Windows, edite o arquivo `C:\Windows\system32\drivers\etc\hosts`, no linux , o arquivo `/etc/hosts`:
```bash
127.0.0.1       terrama2_geoserver
127.0.0.1       terrama2_webapp_1
127.0.0.1       terrama2_webmonitor_1
```

### Configuração externa

Para acesso via rede, configure um endereço IP ou nome de domínio válido no arquivo `.env`:
```bash
# EXEMPLO
# Por exemplo, caso seu endereço IP seja 192.168.15.13
PUBLIC_HOSTNAME=192.168.15.13
```

## Iniciando as instâncias

Para subir o projeto, execute:
```bash
./up-terrama2q.sh
```

Assim, todas as configurações serão executadas.

Para remover os _containers_:
```bash
# Esse comando NÃO APAGA os dados
./wipe-terrama2q.sh
```
O script `./wipe-terrama2q.sh` não remove os dados que já foram inseridos no banco de dados, servidor de mapas ou salvos pelo TerraMA2. Para apagá-los, deve-se remover os volumes criados, o comando `docker volume ls` permite que você saiba quais são esses volumes.

Para resetar os _containers_:
```bash
# Esse comando NÃO APAGA os dados
./reset-terrama2q.sh
```
