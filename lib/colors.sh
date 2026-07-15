#!/usr/bin/env bash
#
# CHANGELOG:
# Standardized variable expansion by consistently using ${VAR} across all shell
# scripts to improve readability, consistency, and safety. This follows shell
# scripting best practices and helps prevent issues related to word splitting
# and pathname expansion (globbing). Additionally, fixed ShellCheck warnings,
# corrected Markdown formatting errors, added appropriate ShellCheck directives,
# removed unused color variables, improved shebang declarations, and performed
# general code quality and maintainability improvements.
#

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
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
