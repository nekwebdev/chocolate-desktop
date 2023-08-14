#!/usr/bin/env bash
# https://github.com/nekwebdev/chocolate-template
# @nekwebdev
# LICENSE: GPLv3
pacman --noconfirm --needed -Sy asciinema
rm -rf ~/chocolate.cast
asciinema rec --stdin -i 5 ~/chocolate.cast
