#!/bin/bash
# Projeto: Update Redis
# Descrição: Esse projeto tem como objetivo automatizar o update da versão 6.0.9 para 7.2 das instâncias de Redis dos ambientes Bradesco
# Versão: v1.0
# Log:
# - v1.0: Criação do esquema do algoritmo somente para o redis-server no contexto de um container dockerizado
# - v1.1: Perguntar por paths de onde está instalado e o path dos confs/bin + downloads e escolher versao
# > ./script.sh --version=7.2 --backup=/backup --bin=/usr/local/bin --conf=/etc/redis --download=ftp://blablabla.net
# Autor: Pedro Henrique - Extractta

# VARIAVEIS
PID_REDIS=$(ps aux | grep '[r]edis-server' | head -n 1 | awk '{print $2}')
URL_DOWNLOAD="https://download.redis.io/releases"
BACKUP_PATH="$(pwd)/backup"
CONF_PATH="/etc/redis/"
BIN_PATH="/usr/local/bin/"
REDIS_VERSION="7.2.7"
HELP="usage: ./update-redis.sh
\n> version: -v [version]
\n> backup-path: -B /my/path/to/backup \t\t (default: $(pwd)/backup/)
\n> binary-path: -b /my/path/to/binary \t\t (default: /usr/local/bin/)
\n> conf-path: -c /my/path/to/binary \t\t (default: /etc/redis/conf/)
\n> download-url: -d https://downloadsite.test \t (default: https://download.redis.io/releases/)"

# Se não colocar nenhum parametro na linha de comando, printa um help

while getopts "v:b:B:c:d:" opt; do
  # Em versões futuras planejo colocar um verificação dos argumentos para evitar erros.
  # Esse case vai pegar cada opção digitada no terminal (por exemplo: -v ) e colocar o valor do parametro dentro de variaveis que serão utilizadas para
  # modificar o script
  case $opt in
    h) 
      echo -e $HELP
      ;;
    v)
      
      REDIS_VERSION="$OPTARG"
      ;;
    b)
      BIN_PATH="$OPTARG"
      ;;
    B)
      BACKUP_PATH="$OPTARG"
      ;;
    c)
      CONF_PATH="$OPTARG"
      ;;
    d)
      URL_DOWNLOAD="$OPTARG"
      ;;
    \?)
      echo "Opção inválida: -$OPTARG" >&2
      echo -e $HELP
      exit 1
      ;;
    :)
      echo "Opção -$OPTARG requer um argumento." >&2
      echo -e $HELP
      exit 1
      ;;
  esac
done

# Chamada de funções





# Roadmap:
# 1 - Parar os serviços
parar_servicos() {
  # A POC será testada em um container docker sem systemctl, portanto, a única forma de 
  # parar um serviço será matando o processo do redis-server.
  # Em futuras versões, será usado o systemctl ou outro

  # Verificação se a variavel está vazia, retornando 1 se sim
  if [[ -z "$PID_REDIS" ]]; then
    echo "Nenhum processo encontrado."
    return 1
  fi
  echo "PID do redis-server encontrado: $PID_REDIS "

  # Finalizando o serviço do redis
  sudo kill -9 "$PID_REDIS" && echo "Processo redis-server finalizado com sucesso" || echo "Falha ao finalizar o redis server"
  return 0
}

# 2 - Verificar a existência dos binários e realizar o backup em tar.gz
backup() {
  parar_servicos
  # Verificando o status code da função "parar_serviços", caso seja diferente de 0 (sucesso), retorne 1
  if [[ $? != 0 ]]; then
    return 1; 
  fi

  # Criando a pasta no diretório atual, futuramente colocar em alguma pasta da raiz.
  if [[ -d $BACKUP_PATH ]]; then
    echo "$BACKUP_PATH já existe"
  else # Caso não exista, cria uma pasta
    echo "Criando pasta em $BACKUP_PATH"
    mkdir $BACKUP_PATH
  fi

  backup_bin 
  backup_conf
}
# 2 - Verificar a existências dos arquivos binarios e realizar o backup em tar.gz
backup_bin() {
  echo "Inicializando o backup dos binarios"
  sleep 3

  # Nesse comando a gente procura no diretório "/usr/bin" os arquivos que são do tipo "file" e começando com "redis-", depois esses arquivos são 
  # compactados e enviados para o $BACKUP_PATH 
  find /usr/bin -type f -iname 'redis-*' -print 2> /dev/null | \
    tar -czf "$BACKUP_PATH/backup_bin.tar.gz" --files-from - && \
    echo "Backup dos arquivos binarios realizado com sucesso em $BACKUP_PATH" || \
    { echo "Não foi possível realizar o backup dos arquivos binarios"; return 1; } # Caso dê errado, sai do programa dando status code 1

    return 0
  }

# 3 - Verificar a existências dos arquivos .conf e realizar o backup em tar.gz
backup_conf(){
  echo "Inicializando o backup dos arquivos de configuração"
  sleep 3

  # Nesse comando a gente procura no diretório "/etc" os arquivos que são do tipo "file" e começando com "redis/sentinel.conf", depois esses arquivos são 
  # compactados e enviados para o $BACKUP_PATH 
  find /etc -type f -regex '.*/\(redis\|sentinel\)\.conf' -print 2>/dev/null | \
    tar -czf "$BACKUP_PATH/backup_conf.tar.gz" --files-from - && \

    echo "Backup dos arquivos de configuração realizado com sucesso em $BACKUP_PATH" || \
    { echo "Não foi possível realizar o backup dos arquivos de configuração"; return 1; } # Caso dê errado, sai do programa dando status code 1
    return 0
  }

# 4 - Dar GET nos binários atualizados em um servidor FTP 

download_binaries(){
  # Tenta fazer download primeiro no yum, se não der certo, vai para baixar os binarios.
  # TODO: Download pelo YUM

  # Faz download do redis no URL e versão padrão e com 
  if [[ $URL_DOWNLOAD == "https://download.redis.io/releases" ]]; then
    wget -O ./redis-$REDIS_VERSION.tar.gz $URL_DOWNLOAD/redis-$REDIS_VERSION.tar.gz && \
      echo "Download feito com sucesso!" || \
      { echo "Falha no download"; exit 1; }
  else 
    # Faz download do redis em um link alternativo
    wget -O ./redis.tar.gz $URL_DOWNLOAD && \
      echo "Download feito com sucesso!" || \
      { echo "Falha no download"; exit 1; }
  fi
  return 0;
}

compile_binaries(){

  # Verificando se não existe uma pasta chamada download, se não tiver, cria uma. 
  download_binaries
  tar xfv download/*.tar.gz

}

compile_binaries

# 4.1 - (OPT) Fazer a compilação dos binários caso seja necessário
# pergunta path, se for nulo -> yum


# 4 - Fazer a substituição dos binários em versões antigas para versões novas

# 5 - Fazer Daemon Reload nos serviços redis (server e sentinel)
# 6 - Subir os serviços novamente


