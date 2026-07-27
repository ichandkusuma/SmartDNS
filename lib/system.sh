#!/usr/bin/env bash

banner(){

cat << "EOF"

==========================================
      SMART DNS INSTALLER
 dnsdist + Unbound for ISP Environment
==========================================

EOF

}

check_root(){

[[ $EUID -ne 0 ]] && fatal "Run as root."

}