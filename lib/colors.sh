#!/usr/bin/env bash

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
WHITE='\033[97m'
NC='\033[0m'

info(){
    echo -e "${CYAN}[INFO]${NC} $1"
}

success(){
    echo -e "${GREEN}[ OK ]${NC} $1"
}

warn(){

    echo -e "${YELLOW}[WARN]${NC} $1" >&2

}

fatal(){

    echo -e "${RED}[FAIL]${NC} $1" >&2
    exit 1

}

error(){

    echo -e "${RED}[FAIL]${NC} $1" >&2

}
