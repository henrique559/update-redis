#!/bin/bash
# Projeto: Update Redis
# Descrição: Esse projeto tem como objetivo automatizar o update da versão 6.0.9 para 7.2 das instâncias de Redis dos ambientes Bradesco
# Versão: v1.2
# Log:
# - v1.0: Criação do esquema do algoritmo somente para o redis-server no contexto de um container dockerizado
# - v1.1: Adicionado opções nos parâmetros para modificar o estado do script
# - v1.2: Compilação e instalação dos binários 
# Autor: Pedro Henrique - Extractta

# VARIAVEIS
#
URL_DOWNLOAD="https://download.redis.io/releases" # Endereço de download
BACKUP_PATH="$(pwd)/backup" # Onde será feito o backup
CONF_PATH="/etc/redis/" # O path dos confs do redis
BIN_PATH="/usr/local/bin/" # O Path dos binarios do redis
DEFAULT_COMPILED_PATH="$(pwd)/bin"
REDIS_VERSION="7.2.7" # Versão desejada para atualizar o redis
HELP="usage: ./update-redis.sh
\n> version: -v [version]
\n> backup-path: -B /my/path/to/backup \t\t (default: $(pwd)/backup/)
\n> binary-path: -b /my/path/to/binary \t\t (default: /usr/local/bin/)
\n> conf-path: -c /my/path/to/binary \t\t (default: /etc/redis/conf/)
\n> download-url: -d https://downloadsite.test \t (default: https://download.redis.io/releases/)"

# Se não colocar nenhum parametro na linha de comando, printa um help
#

if [[ $EUID -ne 0 ]]; then
  echo "por favor, execute o script como root"
  exit 1
fi

while getopts "v:b:B:c:d:" opt; do
  # Em versões futuras planejo colocar um verificação dos argumentos para evitar erros.
  # Esse case vai pegar cada opção digitada no terminal (por exemplo: -v ) e colocar o valor do parametro dentro de variaveis que serão utilizadas para
  # modificar o script
  case $opt in
    h) 
      echo -e $HELP
      ;;
    v)
      if [[ ! "$REDIS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Versão inválida: $REDIS_VERSION"
        exit 1
      fi

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
      echo -e $HELP
      exit 1
      ;;
    :)
      echo -e $HELP
      exit 1
      ;;
  esac
done

# 1 - Parar os serviços
parar_servicos() {
  PID_REDIS=$(ps aux | grep '[r]edis-server' | head -n 1 | awk '{print $2}')  # PID DO SERVIÇO DO REDIS
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
  kill -9 "$PID_REDIS" && echo "Processo redis-server finalizado com sucesso" || echo "Falha ao finalizar o redis server"
  return 0
}

# 2 - Verificar a existência dos binários e realizar o backup em tar.gz
backup() {
  echo "Parando serviços do redis"
  parar_servicos
  [[ $? != 0 ]] && return 1

  # Chamada das funções de backup
  [[ -d $BACKUP_PATH ]] || mkdir -p $BACKUP_PATH
  backup_bin 
  backup_conf
}
# 2 - Verificar a existências dos arquivos binarios e realizar o backup em tar.gz
backup_bin() {
  echo "Inicializando o backup dos binarios"
  sleep 3
  # Nesse comando a gente procura no diretório "/usr/bin" os arquivos que são do tipo "file" e começando com "redis-", depois esses arquivos são 
  # compactados e enviados para o $BACKUP_PATH 
  find $BIN_PATH -type f -iname 'redis-*' -print 2> /dev/null | \
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
  find $CONF_PATH -type f -regex '.*/\(redis\|sentinel\)\.conf' -print 2>/dev/null | \
    tar -czf "$BACKUP_PATH/backup_conf.tar.gz" --files-from - && \

    echo "Backup dos arquivos de configuração realizado com sucesso em $BACKUP_PATH" || \
    { echo "Não foi possível realizar o backup dos arquivos de configuração"; return 1; } # Caso dê errado, sai do programa dando status code 1
    return 0
  }

# 4 - Dar GET nos binários atualizados em um servidor FTP 

download_binaries(){
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

  # Descompactando arquivo
  tar xfv ./redis-*.tar.gz && rm ./redis-*.tar.gz
  return 0;
}

yum_download(){
  yum install redis-$REDIS_VERSION
  if [[ $? -eq 1 ]]; then
    echo "não foi possivel instalar o redis pelo yum, tentando pelo codigo fonte"
    sleep 3
    return 1
  else 
    return 0
  fi
}

compile_binaries(){

  # tenta primeiro fazer o download pelo yum, se não dar certo, vai pra compilação
  # yum_download
  # if [[ $? -eq 0 ]]; then 
  # echo "update realizado pelo yum com sucesso."
  # return 0;
  # else
  # fi
  # Executa a função de download/compilação, se ocorrer um erro, cancela o update

  # Verificando se já existe binarios já compilados
 if [[ -d $DEFAULT_COMPILED_PATH ]]; then
    echo "Binários já compilados encontrados."

  else
    download_binaries
    mkdir -p $DEFAULT_COMPILED_PATH
    cd ./redis-* || exit 1
    make && mv ./src/redis-* $DEFAULT_COMPILED_PATH || { echo "Erro na compilação"; return 1; }
  fi

  replace_files
  [[ $? -eq 1 ]] && echo "Erro ao substituir os arquivos." && exit 1

  return 0

}

replace_files(){
  # Excluindo todos os binarios do redis
  echo "Substituindo os binarios e os confs"
  rm -f $BIN_PATH/redis-* $CONF_PATH/redis-* $CONF_PATH/sentinel-*
  cp -r $DEFAULT_COMPILED_PATH/* $BIN_PATH
      tar xfv "$BACKUP_PATH/backup_conf.tar.gz" -C $CONF_PATH
 }

update_redis(){
  # Executa a função de backup, se ocorrer um erro, cancela o update
  backup
  [[ $? -eq 1 ]] && echo "Erro ao realizar o backup." && exit 1

  compile_binaries
  [[ $? -eq 1 ]] && echo "Erro ao compilar os binários." && exit 1

  # inicializando o redis novamente
  service redis start
  systemctl daemon-reload
  systemctl start redis
}

update_redis
