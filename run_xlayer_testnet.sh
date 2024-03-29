#!/bin/bash
set -e

BASEDIR=$(pwd)
WORKSPACE="$BASEDIR/testnet"
XLAYER_NODE_IMAGE="${XLAYER_NODE_IMAGE:-okexchain/xlayer-node:origin_release_v0.3.0_20240321025324_7cbb58cf}"

rename() {
    prefixes=("x1" "X1")
    for prefix in "${prefixes[@]}"; do
      if [ -d "$WORKSPACE/${prefix}_testnet_data" ]; then
        mv "$WORKSPACE/${prefix}_testnet_data" "$WORKSPACE/xlayer_testnet_data"
      fi

      if [ -f "$WORKSPACE/.env" ]; then
        sed -i "s/${prefix}_NODE_ETHERMAN_URL/XLAYER_NODE_ETHERMAN_URL/g" "$WORKSPACE/.env"
        sed -i "s/${prefix}_NODE_STATEDB_DATA_DIR/XLAYER_NODE_STATEDB_DATA_DIR/g" "$WORKSPACE/.env"
        sed -i "s/${prefix}_NODE_POOLDB_DATA_DIR/XLAYER_NODE_POOLDB_DATA_DIR/g" "$WORKSPACE/.env"
        sed -i "s/${prefix}_testnet_data/xlayer_testnet_data/g" "$WORKSPACE/.env"
      fi
    done
}

download () {
    if command -v curl &> /dev/null; then
        curl -L -o "$2" "$1"
    elif command -v wget &> /dev/null; then
        wget -O "$2" "$1"
    else
        echo "Error: curl or wget is not installed." >&2
        exit 1
    fi
}

# Check if Docker and Docker Compose are installed
check_dependencies() {
    if docker ps > /dev/null 2>&1; then
        echo "Docker daemon is running."
    else
        echo "Docker daemon is not running."
        exit 1
    fi
    if ! command -v docker-compose &> /dev/null; then
        echo "Error: Docker Compose is not installed." >&2
        exit 1
    fi
    echo "Docker and Docker Compose are installed."
}


function remote_out(){
    if command -v curl &> /dev/null; then
        curl "$1"
    elif command -v wget &> /dev/null; then
        wget -q -O - "$1"
    else
        echo "Error: curl or wget is not installed." >&2
        exit 1
    fi
}

function download_init_file() {
  testnetrelease=$(remote_out https://static.okex.org/cdn/chain/xlayer/snapshot/testnet-latest-release)
  download https://static.okex.org/cdn/chain/xlayer/snapshot/"$testnetrelease" "$testnetrelease"
  tar -zxf "$testnetrelease"
}

function download_snapshot() {
  latest_snap=$(remote_out https://static.okex.org/cdn/chain/xlayer/snapshot/testnet-latest)
  download https://static.okex.org/cdn/chain/xlayer/snapshot/"$latest_snap" "$latest_snap"
  echo "download snapshot: $latest_snap"
  tar -zxvf "$latest_snap"
}

function do_restore() {
  docker-compose --env-file .env -f ./docker-compose.yml up -d xlayer-state-db
  sleep 20
  docker run --rm --network=xlayer -v "$WORKSPACE":/data "$XLAYER_NODE_IMAGE" /app/xlayer-node restore --cfg /data/config/node.config.toml -is /data/xlayer-testnet-snap/state_db.sql.tar.gz -ih /data/xlayer-testnet-snap/prover_db.sql.tar.gz
  sleep 5
  docker-compose --env-file .env -f ./docker-compose.yml down
}

function find_url() {
    case $(uname -s) in
        *[Dd]arwin* | *BSD* ) sed -n 's/^XLAYER_NODE_ETHERMAN_URL[[:space:]]*=[[:space:]]*"\([^"]*\)"$/\1/p' ".env";;
        *) sed -n 's/^XLAYER_NODE_ETHERMAN_URL\s*=\s*"\([^"]*\)"$/\1/p' ".env";;
    esac
}

function check_l1_rpc() {
  url=$(find_url)
  if [[ -z "$url" ]]; then
    echo "L1 RPC URL is empty, please set XLAYER_NODE_ETHERMAN_URL env variable"
    exit 1
  fi
}

function init() {
  download_init_file
}


function restore() {
  cd "$WORKSPACE" || exit 1
  check_l1_rpc
  download_snapshot
  do_restore
  cd "$BASEDIR" || exit 1
}


function start() {
  cd "$WORKSPACE" || exit 1
  check_l1_rpc
  docker-compose --env-file .env -f ./docker-compose.yml up -d
  cd "$BASEDIR" || exit 1
}

function stop() {
  cd "$WORKSPACE" || exit 1
  check_l1_rpc
  docker-compose --env-file .env -f ./docker-compose.yml down
  cd "$BASEDIR" || exit 1
}

function update() {
  download_init_file
  cd "$WORKSPACE" || exit 1
  check_l1_rpc
  stop
  start
  cd "$BASEDIR" || exit 1
}

function help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  init     Initialize the configuration."
    echo "  restore  Restore the system to a previous state."
    echo "  start    Start the rpc service."
    echo "  stop     Stop the rpc service."
    echo "  restart  Restart the rpc service."
    echo "  update   Update the rpc service to the latest version."
    echo "  rename   Rename the file to new name."
    echo ""
    echo "Examples:"
    echo "  $0 init"
    echo "  $0 restore"
    echo "  $0 start"
    echo "  $0 stop"
    echo "  $0 restart"
    echo "  $0 update"
    ehco "  $0 rename"
}



function op() {
    case "$1" in
        "init")
            echo "####### init config #######"
            init
            ;;
        "restore")
            echo "####### restore #######"
            restore
            ;;
        "start")
            echo "####### rpc service start #######"
            start
            ;;
        "stop")
            echo "####### rpc service down #######"
            stop
            ;;
        "restart")
            echo "####### rpc service restart #######"
            stop
            start
            ;;
        "update")
            echo "####### rpc service update #######"
            update
            ;;
        "rename")
            echo "####### rename file #######"
            rename
            ;;
        *)
            echo "Unknown operation: $1"
            echo "[init, restore, start, stop, restart, update, rename] flag are support!"
            ;;
    esac
}

check_dependencies
if [ $# -eq 0 ]; then
    help
else
    op "$1"
fi

