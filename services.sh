#!/usr/bin/env bash



_die() {
    echo "err: $*"
    exit 1
}


if which docker-compose >/dev/null; then
    COMPOSE="docker-compose"
elif docker compose >/dev/null; then
    COMPOSE="docker compose"
else
    _die "could not locate docker compose command or plugin"
fi
BCLI="$COMPOSE exec -T -u blits bitcoind bitcoin-cli -regtest"
DATA_DIR="data"
LOG_FILE="daemon.log" 

build() {
    $COMPOSE build ledger-api
}

start() {
    $COMPOSE down -v
    rm -fr $DATA_DIR
    $COMPOSE build ledger-api
    mkdir -p $DATA_DIR
    $COMPOSE up -d

    # wait for bitcoind to be up
    until $COMPOSE logs bitcoind |grep -q 'Bound to'; do
        sleep 1
    done

    # prepare bitcoin funds
    $BCLI createwallet miner >/dev/null
    mine 103 >/dev/null

    # wait for electrs to have completed startup
    until $COMPOSE logs electrs |grep -q 'finished full compaction'; do
        sleep 1
    done
    
    echo "Before proxy starting"

    # wait for proxy to have completed startup
    until $COMPOSE logs proxy |grep -q 'App is running at http://localhost:3000'; do
        sleep 1
    done
    
    #echo "This is before Jupyter container starting"

    # Start the Docker Compose services
    $COMPOSE up -d ledger-api 

    containerid="$(docker ps -qf 'name=^api_ledger-api_1$')"
    if [ -z "$containerid" ]
    then
        echo "No container found for central server application!"
    else
        docker logs $containerid --follow
    fi

    # Call mine() every 2 seconds
    #echo "-> Mining runs in background for every 2 seconds."
    #(while true; do
    #    mine
    #    sleep 10
    # done) & #>> "$LOG_FILE" &       Redirect both stdout and stderr to the log file and run in the background
}

stop() {
    $COMPOSE down -v --remove-orphans
    rm -fr $DATA_DIR
}

fund() {
    local address="$1"
    [ -n "$1" ] || _die "destination address required"
    $BCLI -rpcwallet=miner sendtoaddress "$address" 1
    mine
}

mine() {
    local blocks=1
    [ -n "$1" ] && blocks="$1"
    $BCLI -rpcwallet=miner -generate "$blocks"
}

[ -n "$1" ] || _die "command required"
case $1 in
    build|start|stop) "$1";;
    fund|mine) "$@";;
    *) _die "unrecognized command";;
esac
