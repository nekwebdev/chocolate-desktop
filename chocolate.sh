#!/usr/bin/env bash
# https://github.com/nekwebdev/chocolate-template
# @nekwebdev
# LICENSE: GPLv3
# shellcheck source=/dev/null
set -e

###### => user variables #######################################################
# drives
CHOCO_DRIVE="" # name of the drive: sda, vda, nvme0n1 etc...
CHOCO_PARTITION=true # do paritioning
CHOCO_PARTONLY=false # only do partitioning
CHOCO_SWAP="2G" # size of swap partition, use G or M: 3G or 2000M
CHOCO_SWAPFILE=false # use a swapfile
CHOCO_ROOT="" # size of root partition, use G or M: 15G or 42500M
CHOCO_DATA=false # create a data ext4 partition mounted in /data that uses the rest of the available space on the disk
CHOCO_LUKS=false # LUKS encrypt swap and root partitions
CHOCO_BTRFS=false # use btrfs for root, @root, @home, @var_log and @snapshots subvolumes will be setup
CHOCO_SNAPPER=false # configure snapper for automatic snapshots of the @root subvolume.
CHOCO_PROBER=false # probe for other os when configuring grub
CHOCO_EFI="" # windows efi partition to mount to /boot/efi in chroot for dual boot

# system
CHOCO_ZEN=false # use the zen kernel
CHOCO_LTS=false # use the lts kernel, only one can be chose or you'll get an error.

# localization
CHOCO_MIRRORS="United States"
CHOCO_REGION="Etc/UTC"
CHOCO_KEYMAP="us"
CHOCO_LANG="en_US.UTF-8"
CHOCO_LOCALE="UTF-8"
CHOCO_VFONT="lat1-14" # ter-132n large terminus-font find them with /usr/share/kbd/consolefonts | grep ...
CHOCO_FONTMAP="8859-1"
CHOCO_HOSTNAME="chocolate"

# beyond vanilla
CHOCO_AUR="" # install an aur helper, yay or paru, will not install if empty
CHOCO_VM=false # install vm drivers
CHOCO_XORG=false # install xorg-server with vga drivers
CHOCO_NVIDIA=false # use NVIDIA proprietary drivers
CHOCO_EXTRA=false # run extra script chrooted as root in /mnt at the end of the install, all arguments given to chocolate.sh will be passed to that script.
CHOCO_PKGS="/root/packages.csv" # path to the packages list csv file for extra.sh
CHOCO_CONFIG="" # specify a config file path

# copy local repository for dotfiles in extra.sh
CHOCO_DEV=false

###### => display help screen ##################################################
function displayHelp() {
    echo "  Description:"
    echo "    Arch linux Chocolate install script."
    echo
    echo "  Usage:"
    echo "    chocolate.sh"
    echo "    chocolate.sh --config settings.conf"
    echo "    chocolate.sh --drive nvme0n1 [--nopart] [--onlypart]" 
    echo "                [--swap] $CHOCO_SWAP [--swapfile] [--root] 1000M [--data]"
    echo "                [--luks] [--btrfs] [--snapper] [--prober]"
    echo "                [--efi] sda1 [--zen] [--lts]"
    echo "                [--mirrors] $CHOCO_MIRRORS [--timezone] $CHOCO_REGION"
    echo "                [--keymap] $CHOCO_KEYMAP [--lang] $CHOCO_LANG [--locale] $CHOCO_LOCALE"
    echo "                [--vfont] $CHOCO_VFONT [--fontmap] $CHOCO_FONTMAP"
    echo "                [--hostname] $CHOCO_HOSTNAME"
    echo "                [--aur] paru [--vm] [--xorg] [--nvidia] [--extra]"
    echo
    echo "  Options:"
    echo "    -h --help    Show this screen."
    echo "    --config     Replace script default variables by those from a config file."
    echo
    echo "    ############ Paritions setup:"
    echo
    echo "    --drive      REQUIRED - Drive to install the system on. List drives with lsblk"
    echo "    --nopart     Skips the partitioning part."
    echo "                 Chocolate expects your partitions to be mounted in /mnt"
    echo "    --onlypart   Only format, partition and mount the drive."
    echo "    --swap       Swap partition size in G/M, defaults to '$CHOCO_SWAP'"
    echo "    --swapfile   Create a swapfile instead of a partition."
    echo "    --root       Root partition size in G/M, defaults to all remaining space"
    echo "    --data       Create ext4 partition with the remaining space in /mnt/data."
    echo "                 --root must also be set to use data, defaults to off."
    echo "    --luks       Encrypt the root filesystem, defaults to off."
    echo "    --btrfs      Use the btrfs filesystem with @root, @home, @var_log and @snapshots subvolumes, defaults to off."
    echo "    --snapper    Install and setup snapper for managing btrfs automatic snapshots, defaults to off."
    echo "    --prober     Setup grub to use os-prober for multiboot, defaults to off."
    echo "    --efi        Mount an existing windows EFI partition before creating the grub config."
    echo
    echo "    ############ System setup:"
    echo
    echo "    --zen        Install the linux-zen kernel, defaults to linux kernel."
    echo "    --lts        Install the linux-lts kernel, defaults to linux kernel."
    echo
    echo "    ############ Localization setup:"
    echo
    echo "    --mirrors    Country for reflector mirrors search, defaults to '$CHOCO_MIRRORS'."
    echo "    --timezone   Region/City for timezone (timedatectl list-timezones | grep ...), defaults to '$CHOCO_REGION'."
    echo "    --keymap     Keyboard keymap code (ls /usr/share/kbd/keymaps/**/*.map.gz | grep ...), defaults to '$CHOCO_KEYMAP'."
    echo "    --lang       Lang code for locale.conf(ls /usr/share/i18n/locales | grep ...), defaults to '$CHOCO_LANG'."
    echo "    --locale     List of other locales to generate along with '$CHOCO_LANG', defaults to '$CHOCO_LOCALE'."
    echo "    --vfont      Font in use in virtual consoles second number is size, defaults to '$CHOCO_VFONT'."
    echo "    --fontmap    Map in the ISO characters set, defaults to '$CHOCO_FONTMAP'."
    echo "    --hostname   System hostname, defaults to '$CHOCO_HOSTNAME'."
    echo
    echo "    ############ Options to go slightly past vanilla:"
    echo
    echo "    --aur        Install an aur helper, either 'paru' or 'yay', defaults to off."
    echo "    --vm         Install virtual machine drivers, defaults to off."
    echo "    --xorg       Install xorg-server and vga drivers, defaults to off."
    echo "    --nvidia     Use proprietary NVIDIA drivers, defaults to off."
    echo "    --extra      Run an extra script chrooted as root in /mnt at the end, defaults to off."
    echo "                 All arguments given to chocolate.sh will be passed to that script."
    echo "    --pkgs       Path to packages csv file for the extra script, defaults to '$CHOCO_PKGS'."
    echo
    exit 0
}

###### => echo helpers #########################################################
# _echo_equals() outputs =
function _echo_equals() { local cnt=0;while [ $cnt -lt "$1" ];do printf '=';(( cnt=cnt+1 ));done; }

# _echo_equals() outputs ' '
function _echo_blanks() { local cnt=0;while [ $cnt -lt "$1" ];do printf ' ';(( cnt=cnt+1 ));done; }

# _echo_title() outputs a title padded by =, in yellow (3).
function _echo_title() {
	local title=$1
	local ncols=$(tput cols)
	local nequals=$(((ncols-${#title})/2-1))
	tput setaf 3 # 3 = yellow
	_echo_equals "$nequals"
	printf " %s " "$title"
	_echo_equals "$nequals"
	tput sgr 0 0  # reset terminal
	echo
}

# _echo_middle() outputs a centered text padded by ' ', in yellow (3).
function _echo_middle() {
	local title=$1
	local ncols=$(tput cols)
	local nequals=$(((ncols-${#title})/2-1))
	tput setaf 3 # 3 = yellow
	_echo_blanks "$nequals"
	printf " %s " "$title"
	_echo_blanks "$nequals"
	tput sgr 0 0  # reset terminal
	echo
}

# _echo_step() outputs a step collored in cyan (6), without outputing a newline.
function _echo_step() { tput setaf 6;echo -n "$1";tput sgr 0 0; }

# _echo_step_info() outputs additional step info in cyan (6), without a newline.
function _echo_step_info() { tput setaf 6;echo -n "  ($1)";tput sgr 0 0; }

# _echo_success() outputs [ OK ] in green (2), at the rightmost side of the screen.
function _echo_success() { tput setaf 2;local T="[ OK ]";echo;tput cuu1;tput cuf "$(tput cols)";tput cub ${#T};echo "$T";tput sgr 0 0; }

# _exit_with_message() outputs and logs a message in red (1) before exiting the script.
function _exit_with_message() { echo;tput setaf 1;echo "$1";tput sgr 0 0;echo;exit 1; }

function _fix_length() {
  FIX_LENGTH_TXT="$1"
  local target_length=47
  # fix length
  local extra_spaces=$((target_length-${#FIX_LENGTH_TXT}))
  local counter=1
  while [ $counter -le "$extra_spaces" ]; do
    FIX_LENGTH_TXT="$FIX_LENGTH_TXT "
    ((counter++))
  done
}

function _echo_banner() {
  printf '\033c'
  _echo_title "Arch Linux Chocolate"
  echo
  echo

  local install_text="Installing on $CHOCO_DRIVE with:"
  $CHOCO_PARTONLY && install_text="Only format and partition $CHOCO_DRIVE with:"
  _fix_length "$install_text"
  install_text="$FIX_LENGTH_TXT"

  _fix_length "* 550M fat32 boot EFI partition"
  local boot_text="$FIX_LENGTH_TXT"

  _fix_length "* $CHOCO_SWAP swap partition"
  local swap_text="$FIX_LENGTH_TXT"

  local root_text="ext4 root partition"
  $CHOCO_LUKS && root_text="LUKS encrypted ext4 root partition"
  $CHOCO_BTRFS && root_text="btrfs root partition"
  $CHOCO_BTRFS && $CHOCO_LUKS && root_text="LUKS encrypted btrfs root partition"
  if [[ -n $CHOCO_ROOT ]]; then
    root_text="* $CHOCO_ROOT $root_text"
  else
    root_text="* Remaining space as $root_text"
  fi
  _fix_length "$root_text"
  root_text="$FIX_LENGTH_TXT"

  local data_text=""
  $CHOCO_DATA && data_text="* Remaining space as ext4 mounted in /data"
  _fix_length "$data_text"
  data_text="$FIX_LENGTH_TXT"

  if ! $CHOCO_PARTITION; then
    _fix_length "* User partitioning"
    boot_text="$FIX_LENGTH_TXT"

    _fix_length "* Partitions must be mounted in /mnt"
    swap_text="$FIX_LENGTH_TXT"
    
    local cfg_extra=""
    $CHOCO_LUKS && cfg_extra="$cfg_extra * LUKS"
    $CHOCO_BTRFS && cfg_extra="$cfg_extra * btrfs"
    local root_text=""
    [[ -n $cfg_extra ]] && root_text="* Extra configurations:$cfg_extra"
    _fix_length "$root_text"
    root_text="$FIX_LENGTH_TXT"

    if [[ -n $CHOCO_EFI ]]; then
      local efi_text=""
      _fix_length "* Mount /dev/$CHOCO_EFI in /boot/efi for grub"
      efi_text="$FIX_LENGTH_TXT"
    fi

    _fix_length ""
    data_text="$FIX_LENGTH_TXT"
  fi

  _echo_middle "      ██    ██    ██                                                            "
  _echo_middle "    ██      ██  ██                                                              "
  _echo_middle "    ██    ██    ██                                                              "
  _echo_middle "      ██  ██      ██             $install_text"
  _echo_middle "      ██    ██    ██                                                            "
  _echo_middle "                                 $boot_text"
  _echo_middle "  ████████████████████                                                          "
  _echo_middle "  ██                ██████       $swap_text"
  _echo_middle "  ██                ██  ██                                                      "
  _echo_middle "  ██                ██  ██       $root_text"  
  _echo_middle "  ██                ██████                                                      "
  _echo_middle "    ██            ██             $data_text"
  _echo_middle "████████████████████████                                                        "
  _echo_middle "██                    ██         $efi_text"
  _echo_middle "  ████████████████████                                                          "
  
  echo; echo
  $CHOCO_PARTONLY && return

  _echo_middle "https://wiki.archlinux.org/title/installation_guide"
  echo
  _echo_middle "Kernel: $CHOCO_KERNEL * Hostname: $CHOCO_HOSTNAME * Keymap: $CHOCO_KEYMAP * Mirrors: $CHOCO_MIRRORS"
  _echo_middle "Timezone: $CHOCO_REGION * Lang: $CHOCO_LANG * Locale: $CHOCO_LOCALE * Vfont: $CHOCO_VFONT * Fontmap: $CHOCO_FONTMAP"
  echo
  local add_text=""
  $CHOCO_SNAPPER && add_text="$add_text * snapper"
  $CHOCO_VM && add_text="$add_text * vm drivers"
  [[ -n $CHOCO_AUR ]] && add_text="$add_text * $CHOCO_AUR"
  $CHOCO_XORG && add_text="$add_text * xorg-server"
  $CHOCO_NVIDIA && add_text="$add_text * NVIDIA prorietary drivers" || $CHOCO_XORG && add_text="$add_text * opensource vga drivers"
  $CHOCO_EXTRA && add_text="$add_text * extra script"
  [[ -n $add_text ]] && _echo_middle "Post vanilla:$add_text" && echo
  _echo_middle "* This is the way *"
  echo
}

function _echo_exit_chocolate() {
  [[ -f /root/chocolate.log ]] && cp -f /root/chocolate.log /mnt/var/log
  echo
  _echo_title "Chocolate is done, time to reboot"
  echo
  _echo_step "You will find logs of the install in the new system at /var/log/chocolate*"
  echo
  echo
  exit 0
}

###### => functions ############################################################
function parseArguments() {
  while (( "$#" )); do
    case "$1" in
      -h|--help) displayHelp; shift ;;
      --config)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]] && [[ -f "$2" ]]; then
          CHOCO_CONFIG=$2; shift
        else
          _exit_with_message "when using --config a path must be specified. Example: '--config /root/myconfig.conf'"
        fi ;;
      --drive)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_DRIVE=$2; shift
        else
          _exit_with_message "when using --drive a disk must be specified. Example: '--drive sda'"
        fi ;;
      --nopart) CHOCO_PARTITION=false; shift ;;
      --onlypart) CHOCO_PARTONLY=true; shift ;;
      --swap)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_SWAP=$2; shift
        else
          _exit_with_message "when using --swap a size must be specified. Example: '--swap 4G'"
        fi ;;
      --swapfile) CHOCO_SWAPFILE=true; shift ;;
      --root)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_ROOT=$2; shift
        else
          _exit_with_message "when using --root a size must be specified. Example: '--root 15G'"
        fi ;;
      --data) CHOCO_DATA=true; shift ;;
      --luks) CHOCO_LUKS=true; shift ;;
      --btrfs) CHOCO_BTRFS=true; shift ;;
      --snapper) CHOCO_SNAPPER=true; shift ;;
      --prober) CHOCO_PROBER=true; shift ;;
      --efi)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_EFI=$2; shift
        else
          _exit_with_message "when using --efi a drive needs to be specified. Example: '--efi sda1'"
        fi ;;
      --zen) CHOCO_ZEN=true; shift ;;
      --lts) CHOCO_LTS=true; shift ;;
      --mirrors)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_MIRRORS=$2; shift
        else
          _exit_with_message "when using --mirrors a country to look for mirrors must be specified. Example: '--mirrors 'Switzerland''"
        fi ;;
      --timezone)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_REGION=$2; shift
        else
          _exit_with_message "when using --timezone a Region/City to set the timezone must be specified. Example: '--timezone 'Pacific/Tahiti''"
        fi ;;
      --keymap)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_KEYMAP=$2; shift
        else
          _exit_with_message "when using --keymap a keyboard code must be specified. Example: '--keymap us'"
        fi ;;
      --lang)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_LANG=$2; shift
        else
          _exit_with_message "when using --lang a language code must be specified. Example: '--lang en_US.UTF-8'"
        fi ;;
      --locale)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_LOCALE=$2; shift
        else
          _exit_with_message "when using --locale a list of additional locales to be generated with the lang locale must be specifed. Example: '--locale 'UTF-8''"
        fi ;;
      --vfont)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_VFONT=$2; shift
        else
          _exit_with_message "when using --vfont a font code must be specified. Example: '--vfont lat1-14'"
        fi ;;
      --fontmap)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_FONTMAP=$2; shift
        else
          _exit_with_message "when using --fontmap a map in the ISO characters set must be specified. Example: '--fontmap 8859-1'"
        fi ;;
      --hostname)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_HOSTNAME=$2; shift
        else
          _exit_with_message "when using --hostname a hostname must be specified. Example: '--hostname myhostname'"
        fi ;;
      --aur)
        if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]]; then
          CHOCO_AUR=$2; shift
        else
          _exit_with_message "when using --aur a program name must be specified, either yay or paru. Example: '--aur paru'"
        fi ;;
      --vm) CHOCO_VM=true; shift ;;
      --xorg) CHOCO_XORG=true; shift ;;
      --nvidia) CHOCO_NVIDIA=true; shift ;;
      --extra) CHOCO_EXTRA=true; shift ;;
      --pkgs)
        if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
          CHOCO_PKGS=$2; shift
        else
          _exit_with_message "when using --pkgs a path to the packages csv file must be specified. Example: '--pkgs /root/mypkgs.csv'"
        fi ;;
      --dev) CHOCO_DEV=true; shift ;;
      --*|-*=) shift ;; # unsupported flags ignored to be passed to extra
      *) shift ;;
    esac
  done
}

# edits a config file of this format key="value"
function set_config() {
    sudo sed -i "s+^\($2\s*=\s*\).*\$+\1$3+" "$1"
}

function installChrootPkg() { arch-chroot /mnt pacman --noconfirm --needed -S "$@"; }

function checkRootAndNetwork() {
  _echo_step "Ensure we are root and have internet by installing script dependencies"; echo; echo
  _echo_step_info "Set parallel downloads to 15"
  sed -i "s/^#ParallelDownloads = 5$/ParallelDownloads = 15/" /etc/pacman.conf
  _echo_success
  
  pacman --noconfirm --needed -Sy archlinux-keyring expect dialog dmidecode pacman-contrib || _exit_with_message "Are you root, on Archlinux ISO and with an internet connection?"
  _echo_success
}

function getPasswords() {
  _echo_step "System disks list:"; echo
  echo
  local grep_target="disk"
  ! $CHOCO_PARTITION && grep_target="part"
  lsblk -o name,size,type,partlabel,mountpoints | grep "$grep_target"
  echo
	tput setaf 1 # 1 = red
  read -p "Review the settings, chocolate will ask for passwords next, ready? [y/N] " -n 1 -r
	tput sgr 0 0  # reset terminal
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && echo && _exit_with_message "Fair enough..."
  # prompt user for root password
  ROOT_PWD=$(dialog --passwordbox "Enter a password for the root user." 8 60 3>&1 1>&2 2>&3 3>&1) || exit 1
  local ROOT_PWD2=$(dialog --no-cancel --passwordbox "Retype root password." 8 60 3>&1 1>&2 2>&3 3>&1)
  while ! [ "$ROOT_PWD" = "$ROOT_PWD2" ]; do
		unset ROOT_PWD2
		ROOT_PWD=$(dialog --no-cancel --passwordbox "No match, Enter root password again." 8 60 3>&1 1>&2 2>&3 3>&1)
		ROOT_PWD2=$(dialog --no-cancel --passwordbox "Retype root password." 8 60 3>&1 1>&2 2>&3 3>&1)
	done
  unset ROOT_PWD2

  if $CHOCO_LUKS; then
    # prompt user for LUKS encryption password
    LUKS_PWD=$(dialog --passwordbox "Enter a password for LUKS encryption." 8 60 3>&1 1>&2 2>&3 3>&1) || exit 1
    local LUKS_PWD2=$(dialog --no-cancel --passwordbox "Retype LUKS encryption password." 8 60 3>&1 1>&2 2>&3 3>&1)
    while ! [ "$LUKS_PWD" = "$LUKS_PWD2" ]; do
      unset LUKS_PWD2
      LUKS_PWD=$(dialog --no-cancel --passwordbox "No match, Enter LUKS encryption password again." 8 60 3>&1 1>&2 2>&3 3>&1)
      LUKS_PWD2=$(dialog --no-cancel --passwordbox "Retype LUKS encryption password." 8 60 3>&1 1>&2 2>&3 3>&1)
    done
    unset LUKS_PWD2
  fi
}

function lastChance() {
  _echo_step "System disks list:"; echo
  echo
  local grep_target="disk"
  ! $CHOCO_PARTITION && grep_target="part"
  lsblk -o name,size,type,partlabel,mountpoints | grep "$grep_target"
  echo
	tput setaf 1 # 1 = red
  local warn_text=""
  if $CHOCO_PARTONLY; then
    warn_text="Chocolate will fragpuccino $CHOCO_DRIVE, this will be real quick, are you ready? [y/N]"
  elif ! $CHOCO_PARTITION; then
    warn_text="Chocolate will install Arch Linux on $CHOCO_DRIVE so you can go grab a nice hot coco, are you ready? [y/N]"
  else
    warn_text="Chocolate will fragpuccino $CHOCO_DRIVE and install Arch Linux so you can go grab a nice hot coco, are you ready? [y/N]"
  fi
  read -p "$warn_text " -n 1 -r
  tput sgr 0 0  # reset terminal
  [[ ! $REPLY =~ ^[Yy]$ ]] && echo && _exit_with_message "Fair enough..."
  echo; echo
}

function partitionDisk() {
  # https://wiki.archlinux.org/title/User:Altercation/Bullet_Proof_Arch_Install#Our_partition_plans
  # https://wiki.archlinux.org/title/User:Altercation/Bullet_Proof_Arch_Install#Partition_Drive
  _echo_step_info "fragpuccino $1, bye bye baby"; echo
  sgdisk --zap-all --clear "$1"
  _echo_success

  _echo_step_info "Create 550 MiB EFI partition"; echo
  sgdisk --new=1:0:+550MiB --typecode=1:ef00 --change-name=1:EFI-NIX "$1"
  _echo_success

  if ! $CHOCO_SWAPFILE; then
    _echo_step_info "Create $CHOCO_SWAP swap partition"; echo
    sgdisk --new=2:0:+"$CHOCO_SWAP"iB --typecode=2:8200 --change-name=2:"$($CHOCO_LUKS && echo 'cryptswap' || echo 'swap')" "$1"
    _echo_success
  fi

  # shellcheck disable=SC2015
  [[ -n $CHOCO_ROOT ]] && local root_text="Create $CHOCO_ROOT root partition" || local root_text="Create root partition with the remaining space"

  _echo_step_info "$root_text"; echo
  # sgdisk --new=3:0:+"$CHOCO_ROOT" --typecode=3:8300 --change-name=3:cryptsystem "$1"
  sgdisk --new=3:0:"$([[ -n $CHOCO_ROOT ]] && echo "+${CHOCO_ROOT}iB" || echo "0")" --typecode=3:8300 --change-name=3:"$($CHOCO_LUKS && echo 'cryptsystem' || echo 'system')" "$1"
  _echo_success

  if ($CHOCO_DATA && [[ -n $CHOCO_ROOT ]]); then
    _echo_step_info "Create data partition with the remaining space"; echo
    sgdisk --new=4:0:0 --typecode=4:8300 --change-name=4:data "$1"
    _echo_success
  fi
  # print new partitions and pause to let system reload partition information
  # it would always fails on the mkfs without a 0.1s pause...
  sleep 0.1s && lsblk -o name,size,type,partlabel; echo
}

function encryptRoot() {
  # https://wiki.archlinux.org/title/User:Altercation/Bullet_Proof_Arch_Install#Format_EFI_Partition
  _echo_step_info "Encrypt system partition"; echo
  /usr/bin/expect <<EOD
spawn cryptsetup luksFormat --align-payload=8192 -s 256 -c aes-xts-plain64 /dev/disk/by-partlabel/cryptsystem
expect "letters):"
send -- "YES\r"
expect "cryptsystem:"
send -- "$LUKS_PWD\r"
expect "passphrase:"
send -- "$LUKS_PWD\r"
expect eof
EOD

  /usr/bin/expect <<EOD
spawn cryptsetup open /dev/disk/by-partlabel/cryptsystem system
expect "cryptsystem:"
send -- "$LUKS_PWD\r"
expect eof
EOD
  unset LUKS_PWD
  _echo_success

  _echo_step_info "Bring up encrypted swap"; echo
  cryptsetup open --type plain --key-file /dev/urandom /dev/disk/by-partlabel/cryptswap swap
  _echo_success

  ROOT_LABEL="/dev/mapper/system"
  SWAP_LABEL="/dev/mapper/swap"
}

function formatDisk() {
  _echo_step_info "Format EFI partition to FAT32"; echo
  mkfs.fat -F32 -n EFI-NIX /dev/disk/by-partlabel/EFI-NIX
  _echo_success

  ROOT_LABEL="/dev/disk/by-partlabel/system"
  SWAP_LABEL="/dev/disk/by-partlabel/swap"

  $CHOCO_LUKS && encryptRoot

  local root_format="ext4"
  $CHOCO_BTRFS && root_format="btrfs"

  _echo_step_info "Format root partition to $root_format"; echo
  if $CHOCO_BTRFS; then
    mkfs.btrfs -f -L system "$ROOT_LABEL"
  else
    mkfs.ext4 -F -L system "$ROOT_LABEL"
  fi
  _echo_success

  if ! $CHOCO_SWAPFILE; then
    _echo_step_info "Format swap volume"; echo
    mkswap -L swap "$SWAP_LABEL"
    _echo_success
  fi

  if $CHOCO_DATA; then
    _echo_step_info "Format data partition to ext4"; echo
    mkfs.ext4 -q -L data /dev/disk/by-partlabel/data
    _echo_success
  fi
  lsblk -o name,size,type,fstype,partlabel,label
  echo
}

function btrfsSubvols() {
  # https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout
  _echo_step_info "Mount the btrfs root subvolume"; echo
  mount -t btrfs LABEL=system /mnt
  _echo_success

  # create btrfs subvolumes
  _echo_step_info "Create btrfs @root subvolume"; echo
  btrfs subvolume create /mnt/@root
  _echo_success

  _echo_step_info "Create btrfs @home subvolume"; echo
  btrfs subvolume create /mnt/@home
  _echo_success

  _echo_step_info "Create btrfs @var_log subvolume"; echo
  btrfs subvolume create /mnt/@var_log
  _echo_success

  _echo_step_info "Create btrfs @snapshots subvolume"; echo
  btrfs subvolume create /mnt/@snapshots
  _echo_success

  _echo_step_info "Unmount everything"; echo
  umount -R /mnt
  _echo_success

  # https://wiki.archlinux.org/title/User:Altercation/Bullet_Proof_Arch_Install#Create_and_mount_BTRFS_subvolumes
  # set btrfs mount options
  local o=defaults,x-mount.mkdir
  local o_btrfs=$o,compress=lzo,ssd,noatime

  _echo_step_info "Mount btrfs subvolumes under top-level"; echo
  mount -t btrfs -o subvol=@root,$o_btrfs LABEL=system /mnt
  mount -t btrfs -o subvol=@home,$o_btrfs LABEL=system /mnt/home
  mount -t btrfs -o subvol=@var_log,$o_btrfs LABEL=system /mnt/var/log
  mount -t btrfs -o subvol=@snapshots,$o_btrfs LABEL=system /mnt/.snapshots
  _echo_success
}

function mountParts() {
  if $CHOCO_BTRFS; then
    btrfsSubvols
  else
    _echo_step_info "Mount the etx4 root partition to /mnt"
    mount LABEL=system /mnt
    _echo_success; echo
  fi

  _echo_step_info "Mount EFI boot partition to /mnt/boot"
  mkdir /mnt/boot
  mount LABEL=EFI-NIX /mnt/boot
  _echo_success; echo

  if ! $CHOCO_SWAPFILE; then
    _echo_step_info "Enable swap volume"
    swapon -L swap
    _echo_success; echo
  fi

  if $CHOCO_DATA; then
    _echo_step_info "Mount data partition to /mnt/data"
    mkdir /mnt/data
    mount LABEL=data /mnt/data
    _echo_success; echo
  fi
}

function essentialPkgs() {
  _echo_step_info "pacstrap with base $CHOCO_KERNEL linux-firmware"; echo
  pacstrap -K /mnt base "$CHOCO_KERNEL" linux-firmware
  _echo_success

  # export a package list at current step
  arch-chroot /mnt pacman -Qe > /mnt/var/log/chocolate_packages_list_01_pacstrap.log

  _echo_step_info "Copy pacman mirrorlist to the new system"
  cp -f /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
  cp -f /etc/pacman.d/mirrorlist.bak /mnt/etc/pacman.d/mirrorlist.bak
  _echo_success

  _echo_step_info "Set parallel downloads to 15 in new system"
  sed -i "s/^#ParallelDownloads = 5$/ParallelDownloads = 15/" /mnt/etc/pacman.conf
  _echo_success

  _echo_step_info "Install userspace utilities for the management of file systems"; echo
  # https://wiki.archlinux.org/title/File_systems
  installChrootPkg dosfstools e2fsprogs
  $CHOCO_BTRFS && installChrootPkg btrfs-progs
  _echo_success

  _echo_step_info "Install software necessary for networking"; echo
  installChrootPkg networkmanager
  _echo_success

  _echo_step_info "Install a text editor"; echo
  installChrootPkg vi vim
  _echo_success

  _echo_step_info "Install packages for accessing documentation in man and info pages"; echo
  installChrootPkg man-db man-pages texinfo
  _echo_success

  # check for microcode
  local microcode=""
  dmidecode | grep -i amd && microcode="amd-ucode"
  dmidecode | grep -i intel && microcode="intel-ucode"
  if [[ -n $microcode ]]; then
    _echo_step_info "Install microcode: $microcode"; echo
    installChrootPkg "$microcode"
    _echo_success
  else
    echo
  fi
  
  # export a package list at current step
  arch-chroot /mnt pacman -Qe > /mnt/var/log/chocolate_packages_list_02_essentials.log
}

function configureSys() {
  # https://wiki.archlinux.org/title/installation_guide#Fstab
  _echo_step_info "Fstab"; echo
  genfstab -L -p /mnt >> /mnt/etc/fstab
  _echo_success

  if $CHOCO_LUKS; then
    # https://wiki.archlinux.org/title/Dm-crypt/Swap_encryption#UUID_and_LABEL
    _echo_step_info "Fix cryptswap LABEL in fstab"; echo
    sed -i s+LABEL=swap+/dev/mapper/swap+ /mnt/etc/fstab
    _echo_success
  fi

  # setup swap file now
  # https://wiki.archlinux.org/title/Swap#Swap_file
  if $CHOCO_SWAPFILE; then
    _echo_step_info "Setting up /swapfile of $CHOCO_SWAP"; echo
    arch-chroot /mnt fallocate -l "$CHOCO_SWAP" /swapfile
    arch-chroot /mnt chmod 0600 /swapfile
    arch-chroot /mnt mkswap -U clear /swapfile
    arch-chroot /mnt swapon /swapfile
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
    _echo_success
  fi

  # https://wiki.archlinux.org/title/installation_guide#Time_zone
  _echo_step "Timezone"; echo; echo
  ln -sf /usr/share/zoneinfo/"$CHOCO_REGION" /mnt/etc/localtime
  _echo_step_info "Sending hwclock command to arch-chroot"; echo
  arch-chroot /mnt hwclock --systohc
  _echo_success

  # https://wiki.archlinux.org/title/installation_guide#Localization
  _echo_step "Localization"; echo; echo
  _echo_step_info "Generating locales"; echo
  echo "$CHOCO_LANG $CHOCO_LOCALE" >> /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  _echo_success

  _echo_step_info "Setting LANG and LC_COLLATE"; echo
  echo "LANG=$CHOCO_LANG" > /mnt/etc/locale.conf
  echo "LC_COLLATE=C" >> /mnt/etc/locale.conf
  _echo_success

  # more info https://wiki.archlinux.org/title/Linux_console#Persistent_configuration
  _echo_step_info "Making keymap setting persistent"; echo
  echo "KEYMAP=$CHOCO_KEYMAP" > /mnt/etc/vconsole.conf
  echo "FONT=$CHOCO_VFONT" >> /mnt/etc/vconsole.conf
  echo "FONT_MAP=$CHOCO_FONTMAP" >> /mnt/etc/vconsole.conf
  _echo_success

  # https://wiki.archlinux.org/title/installation_guide#Network_configuration
  _echo_step "Network configuration"; echo; echo
  _echo_step_info "Set hostname to $CHOCO_HOSTNAME"; echo
  echo "$CHOCO_HOSTNAME" > /mnt/etc/hostname
  {
    echo "127.0.0.1       localhost";
    echo "::1             localhost";
    echo "127.0.1.1       $CHOCO_HOSTNAME.localdomain $CHOCO_HOSTNAME";
  } >> /mnt/etc/hosts
  _echo_success

  _echo_step_info "Install and enable networkmanager"; echo
  arch-chroot /mnt systemctl enable NetworkManager
  _echo_success

  # https://wiki.archlinux.org/title/installation_guide#Initramfs
  _echo_step "Initramfs"; echo; echo
  _echo_step_info "Edit mkinitcpio.conf"; echo
  # https://wiki.archlinux.org/title/Mkinitcpio#MODULES
  # no filesystem modules because of the filesystems hook
  # no btrfs module because of udev hook
  # no dm-crypt module because of encrypt hook

  # keyboard keymap consolefont before autodetect
  local new_modules="MODULES=(usbhid xhci_hcd)"
  sed -i "s/^MODULES=(.*/$new_modules/" /mnt/etc/mkinitcpio.conf

  if $CHOCO_BTRFS; then
    # https://wiki.archlinux.org/title/Btrfs#Corruption_recovery
    local new_binaries="BINARIES=(/usr/bin/btrfs)"
    sed -i "s+^BINARIES=(.*+$new_binaries+" /mnt/etc/mkinitcpio.conf
  fi

  # https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
  local new_hooks="HOOKS=(base udev keyboard keymap consolefont autodetect modconf block filesystems fsck)"
  # more info https://wiki.archlinux.org/title/Dm-crypt/System_configuration#mkinitcpio
  $CHOCO_LUKS && new_hooks="${new_hooks//filesystems/encrypt filesystems}"
  sed -i "s/^HOOKS=(.*/$new_hooks/" /mnt/etc/mkinitcpio.conf
  _echo_success

  _echo_step_info "Recreate the initramfs image"; echo
  arch-chroot /mnt mkinitcpio -p "$CHOCO_KERNEL" 
  _echo_success

  # https://wiki.archlinux.org/title/installation_guide#Root_password
  _echo_step_info "Root password"; echo
  {
    echo "$ROOT_PWD";
    echo "$ROOT_PWD";
  } | arch-chroot /mnt passwd
  unset ROOT_PWD
  _echo_success

  # https://wiki.archlinux.org/title/installation_guide#Boot_loader
  # https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#Configuring_the_boot_loader_5
  # https://wiki.archlinux.org/title/GRUB#Encrypted_/boot
  _echo_step_info "Boot loader packages"; echo

  # shellcheck disable=SC2015
  $CHOCO_BTRFS && installChrootPkg grub-btrfs || installChrootPkg grub
  $CHOCO_PROBER && installChrootPkg os-prober
  installChrootPkg dosfstools e2fsprogs efibootmgr
  _echo_success

  # check if we need to mount an efi partition
  local efi_dir="/boot"
  if [[ -n $CHOCO_EFI ]]; then
    _echo_step_info "Mounting /dev/${CHOCO_EFI} to /boot/efi in chroot"; echo
    arch-chroot /mnt mkdir /boot/efi
    arch-chroot /mnt mount /dev/"$CHOCO_EFI" /boot/efi
    efi_dir="/boot/efi"
    _echo_success
  fi

  _echo_step_info "Run grub-install"; echo
  arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory="$efi_dir" --bootloader-id=GRUB
  _echo_success

  if $CHOCO_LUKS; then
    _echo_step_info "Edit grub config for cryptodisk"; echo
    sed -i "s/.*GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/" /mnt/etc/default/grub
    sed -i "s/.*GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/" /mnt/etc/default/grub
    sed -i "s+.*GRUB_CMDLINE_LINUX=.*+GRUB_CMDLINE_LINUX=\"cryptdevice=${CHOCO_DRIVE}3:cryptsystem:allow-discards\"+" /mnt/etc/default/grub
    _echo_success
  fi

  if $CHOCO_PROBER; then
    _echo_step_info "Edit grub config for os-prober"; echo
    sed -i "s/.*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/" /mnt/etc/default/grub
    _echo_success
  fi

  _echo_step_info "Generate new grub config"; echo
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
  _echo_success

  # create grub pacman hooks
#   _echo_step_info "Create pacman hook to recreate bootloader on grub updates"; echo
#   mkdir -p /mnt/usr/share/libalpm/hooks
#   cat <<EOF > /mnt/usr/share/libalpm/hooks/grub.hook 
# [Trigger]
# Operation = Install
# Operation = Upgrade
# Operation = Remove
# Type = File
# Target = usr/lib/modules/*/vmlinuz

# [Action]
# Description = Updating GRUB Config
# Depends = grub
# When = PostTransaction
# Exec = /bin/sh -c "/usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB && /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg" 
# Exec = /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg
# EOF



  # https://wiki.archlinux.org/title/System_backup#Snapshots_and_/boot_partition
  # https://wiki.archlinux.org/title/Pacman#Hooks
  if $CHOCO_BTRFS; then
    _echo_step_info "Create pacman hook to backup /boot"; echo
    mkdir -p /mnt/usr/share/libalpm/hooks
    cat <<EOF > /mnt/usr/share/libalpm/hooks/50-bootbackup.hook 
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Depends = rsync
Description = Backing up /boot...
When = PostTransaction
Exec = /usr/bin/rsync -a --delete /boot /.bootbackup
EOF
    _echo_success
  fi
}

function installVanilla() {
  # https://wiki.archlinux.org/title/installation_guide#Pre-installation
  # catching up to make it look like the wiki :P
  _echo_step "Pre-installation"; echo; echo
  _echo_step_info "Connect to the internet"; _echo_success # also done
  
  # https://wiki.archlinux.org/title/installation_guide#Update_the_system_clock
  _echo_step_info "Update the system clock"; echo
  timedatectl set-ntp true; sleep 12s && timedatectl status
  _echo_success

  if $CHOCO_PARTITION; then
    # https://wiki.archlinux.org/title/installation_guide#Partition_the_disks
    _echo_step "Partition the disk $CHOCO_DRIVE"; echo; echo
    partitionDisk "$CHOCO_DRIVE"

    # https://wiki.archlinux.org/title/installation_guide#Format_the_partitions
    _echo_step "Format the partitions"; echo; echo
    formatDisk

    # https://wiki.archlinux.org/title/installation_guide#Mount_the_file_systems
    _echo_step "Mount the file systems"; echo; echo
    mountParts
  fi

  $CHOCO_PARTONLY && _echo_exit_chocolate

  # https://wiki.archlinux.org/title/installation_guide#Installation
  _echo_step "Installation"; echo; echo

  # https://wiki.archlinux.org/title/installation_guide#Select_the_mirrors
  # _echo_step_info "Select the mirrors in $CHOCO_MIRRORS"; echo
  # [[ ! -f .reflector_done ]] && reflector --country "$CHOCO_MIRRORS" --latest 20 --sort rate --save /etc/pacman.d/mirrorlist --protocol https --download-timeout 5
  # touch .reflector_done
  # _echo_success

  # different method
  _echo_step_info "Select fastest 10 mirrors"; echo
  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
  rankmirrors -n 10 /etc/pacman.d/mirrorlist.bak > /etc/pacman.d/mirrorlist
  _echo_success

  # https://wiki.archlinux.org/title/installation_guide#Install_essential_packages
  _echo_step_info "Install essential packages"; echo
  essentialPkgs

  # https://wiki.archlinux.org/title/installation_guide#Configure_the_system
  _echo_step "Configure the system"; echo; echo
  configureSys

  # export a package list at current step
  arch-chroot /mnt pacman -Qe > /mnt/var/log/chocolate_packages_list_03_vanilla.log
}

function snapperConfig() {
  ! $CHOCO_SNAPPER && return
  # https://wiki.archlinux.org/title/Snapper#Installation
  # https://bbs.archlinux.org/viewtopic.php?id=194491
  _echo_step "Install snapper and snap-pac"; echo; echo
  installChrootPkg snapper snap-pac
  _echo_success

   # https://wiki.archlinux.org/title/Snapper#Creating_a_new_configuration
  _echo_step_info "Create snapper config"; echo
  arch-chroot /mnt umount /.snapshots
	rm -rf /mnt/.snapshots
	arch-chroot /mnt snapper -v --no-dbus -c root create-config /
	arch-chroot /mnt btrfs subvolume delete /.snapshots
	mkdir /mnt/.snapshots
	chmod 750 /mnt/.snapshots
	chmod a+rx /mnt/.snapshots
	arch-chroot /mnt chown :wheel /.snapshots
	arch-chroot /mnt mount -a
  _echo_success

  # https://wiki.archlinux.org/title/Snapper#Automatic_timeline_snapshots
  _echo_step_info "Editing automatic timeline snapshots, 5 hourly, 5 daily"; echo
	set_config "/mnt/etc/snapper/configs/root" ALLOW_GROUPS "\"wheel\""
	set_config "/mnt/etc/snapper/configs/root" TIMELINE_LIMIT_HOURLY 5
	set_config "/mnt/etc/snapper/configs/root" TIMELINE_LIMIT_DAILY 5
	set_config "/mnt/etc/snapper/configs/root" TIMELINE_LIMIT_WEEKLY 0
	set_config "/mnt/etc/snapper/configs/root" TIMELINE_LIMIT_MONTHLY 0
	set_config "/mnt/etc/snapper/configs/root" TIMELINE_LIMIT_YEARLY 0
  _echo_success

  # https://wiki.archlinux.org/title/Snapper#Enable/disable
  _echo_step_info "Enable snapper timeline and cleanup systemd timers"; echo
  arch-chroot /mnt systemctl enable snapper-timeline.timer
	arch-chroot /mnt systemctl enable snapper-cleanup.timer
  _echo_success
}

function vmguestDrivers() {
  ! $CHOCO_VM && return
  if lspci -k | grep -i "qemu" >/dev/null; then
    _echo_step "Add drivers for qemu"; echo; echo
    installChrootPkg qemu-guest-agent spice-vdagent
    _echo_success

    _echo_step_info "Enable qemu-guest-agent service"; echo
    arch-chroot /mnt systemctl enable -f qemu-guest-agent.service
  fi

  if lspci -k | grep -i "virtualbox" >/dev/null; then
    _echo_step "Add drivers for virtualbox"; echo; echo
    installChrootPkg virtualbox-guest-utils
    _echo_success

    _echo_step_info "Enable vboxservice service"; echo; echo
    arch-chroot /mnt systemctl enable -f vboxservice.service
    _echo_success
  fi

  if lspci -k | grep -i "VMware" >/dev/null; then
    _echo_step "Add drivers for VMware"; echo; echo
    installChrootPkg open-vm-tools xf86-input-vmmouse xf86-video-vmware
    _echo_success
  fi
  # export a package list at current step
  arch-chroot /mnt pacman -Qe > /mnt/var/log/chocolate_packages_list_04_vm.log
}

function installAurHelper() {
  [[ -z $CHOCO_AUR ]] && return
  # Install aur helper
  # https://github.com/Morganamilo/paru
  _echo_step_info "Install $CHOCO_AUR dependencies base-devel and git"; echo
  installChrootPkg base-devel git
  _echo_success

  _echo_step_info "Create /home/build and make it nobody user's home"; echo
  mkdir /mnt/home/build
  arch-chroot /mnt chgrp nobody /home/build
  arch-chroot /mnt chmod g+ws /home/build
  arch-chroot /mnt setfacl -m u::rwx,g::rwx /home/build
  arch-chroot /mnt setfacl -d --set u::rwx,g::rwx,o::- /home/build
  arch-chroot /mnt usermod -d /home/build nobody
  _echo_success

   _echo_step_info "Add nobody to passwordless sudo"; echo
  echo "nobody ALL=(ALL) NOPASSWD: ALL" >> /mnt/etc/sudoers
  _echo_success

  _echo_step_info "Install $CHOCO_AUR AUR helper"; echo
  arch-chroot /mnt /bin/sudo -u nobody /bin/bash -c "git clone $AUR_URL /home/build/$CHOCO_AUR"
  arch-chroot /mnt /bin/sudo -u nobody /bin/bash -c "cd /home/build/$CHOCO_AUR && makepkg --noconfirm --needed -si"
  _echo_success

  _echo_step_info "Remove nobody from passwordless sudo, set it's home back to / and delete /home/build"; echo
  sed -i "s/nobody ALL=(ALL) NOPASSWD: ALL//" /mnt/etc/sudoers
  arch-chroot /mnt usermod -d / nobody
  rm -rf /mnt/home/build
  _echo_success
}

function vgaDrivers() {
  _echo_step "Install vga drivers"; echo; echo

  if lspci -k | grep -A 2 -E "(VGA|3D)" | grep NVIDIA; then
    if $CHOCO_NVIDIA; then
      # https://wiki.archlinux.org/title/NVIDIA
      _echo_step_info "Install NVIDIA prorietary gpu drivers"; echo
      installChrootPkg linux-headers nvidia-dkms nvidia-utils nvidia-settings 
      _echo_success

      _echo_step_info "Add nvidia_drm to bootloader"; echo
      sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& nvidia_drm.modeset=1/' /mnt/etc/default/grub
      _echo_success

      _echo_step_info "Generate new grub config"; echo
      arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
      _echo_success

      _echo_step_info "Add NVIDIA modules to mkinitcpio and generate /boot/initramfs-custom.img"; echo
      sed -i "s/^MODULES=(/&nvidia nvidia_modeset nvidia_uvm nvidia_drm /" /mnt/etc/mkinitcpio.conf
      arch-chroot /mnt mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img
      _echo_success

      _echo_step_info "Add nvidia-drm settings to modeprobe.d"; echo
      echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia.conf
      echo 'options nvidia "NVreg_UsePageAttributeTable=1"' >> /etc/modprobe.d/nvidia.conf
      echo 'options nvidia "NVreg_PreserveVideoMemoryAllocations=1"' >> /etc/modprobe.d/nvidia.conf
      echo 'options nvidia "NVreg_TemporaryFilePath=/var/tmp"' >> /etc/modprobe.d/nvidia.conf
      echo 'options nvidia "NVreg_EnableS0ixPowerManagement=1"' >> /etc/modprobe.d/nvidia.conf
      _echo_success

      _echo_step_info "Create pacman hook to update nvidia module in initcpio"
      mkdir -p /mnt/usr/share/libalpm/hooks
      # shellcheck disable=SC2154
      cat <<EOF > /mnt/usr/share/libalpm/hooks/50-nvidia.hook 
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia
Target=$CHOCO_KERNEL

[Action]
Description=Update Nvidia module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case $trg in $CHOCO_KERNEL) exit 0; esac; done; /usr/bin/mkinitcpio -P'
EOF
      _echo_success; echo
    else
      # https://wiki.archlinux.org/title/Nouveau
      _echo_step_info "Install NVIDIA nouveau open source gpu drivers"; echo
      installChrootPkg xf86-video-nouveau
      _echo_success

      _echo_step_info "Add nouveau module to mkinitcpio.conf"; echo
      sed -i "s/^MODULES=(/&nouveau /" /mnt/etc/mkinitcpio.conf
      arch-chroot /mnt mkinitcpio -p "$CHOCO_KERNEL"
      _echo_success
    fi
  fi

  if lspci -k | grep -A 2 -E "(VGA|3D)" | grep AMD; then
    # https://wiki.archlinux.org/title/AMDGPU#Selecting_the_right_driver
    # https://wiki.archlinux.org/title/AMDGPU
    _echo_step_info "Install AMD gpu drivers"; echo
    installChrootPkg xf86-video-amdgpu
    _echo_success

    _echo_step_info "Add amdgpu and radeon module to mkinitcpio.conf"; echo
    sed -i "s/^MODULES=(/&amdgpu radeon /" /mnt/etc/mkinitcpio.conf
    echo "options amdgpu si_support=1" > /etc/modprobe.d/amdgpu.conf
    echo "options amdgpu cik_support=1" >> /etc/modprobe.d/amdgpu.conf
    echo "options radeon si_support=0" > /etc/modprobe.d/radeon.conf
    echo "options radeon cik_support=0" >> /etc/modprobe.d/radeon.conf
    arch-chroot /mnt mkinitcpio -p "$CHOCO_KERNEL"
    _echo_success
  fi
}

function installXorg() {
  ! $CHOCO_XORG && return
  _echo_step "Install xorg server"; echo; echo
  installChrootPkg xorg-server
  _echo_success
  vgaDrivers
  # export a package list at current step
  arch-chroot /mnt pacman -Qe > /mnt/var/log/chocolate_packages_list_05_xorg.log
}

function extraScript() {
  ! $CHOCO_EXTRA && return
  $CHOCO_DEV && cp -rf /root/chocodots-local /mnt/root
  cp -f /root/extra.sh /mnt/root
  cp -f "$CHOCO_PKGS" /mnt/root
  chmod +x /mnt/root/extra.sh
  echo
  _echo_title "Run extra script in arch-chroot as root"; echo
  arch-chroot /mnt /root/extra.sh "$@"
}

###### => main #################################################################

function main() {
  # Chocolate follows the arch way
  # https://wiki.archlinux.org/title/installation_guide

  printf '\033c'
  _echo_title "Arch Linux Chocolate"
  echo

  # downloads script dependencies, which has the added advantage of testing root and internet
  checkRootAndNetwork

  _echo_banner

  # prompt the user for ALL the passwords, ensure keymap is correct at that point
  # https://wiki.archlinux.org/title/installation_guide#Set_the_console_keyboard_layout
  loadkeys "$CHOCO_KEYMAP"
  getPasswords

  # print banner again before the last warning pause
  _echo_banner

  # big bad warning
  lastChance

  installVanilla

  echo; _echo_title "Vanilla install done"; echo

  vmguestDrivers

  installAurHelper

  installXorg

  extraScript "$@"

  snapperConfig

  if [[ -n $CHOCO_EFI ]]; then
    _echo_step "Unmounting /dev/${CHOCO_EFI} from /boot/efi in chroot"; echo
    arch-chroot /mnt umount /boot/efi
    _echo_success
  fi

  _echo_exit_chocolate
}

# update user variables from command line arguments
parseArguments "$@"

# source config file for default values
[[ -f $CHOCO_CONFIG ]] && source "$CHOCO_CONFIG"

# check arguments sanity
# check for --drive being set

$CHOCO_PARTONLY && ! $CHOCO_PARTITION && _exit_with_message "how do you want to only run partitioning with --onlypart and also skip partitioning with --nopart. More hot coco maybe?"

[[ -n $CHOCO_DRIVE ]] && CHOCO_DRIVE="/dev/$CHOCO_DRIVE"

! $CHOCO_PARTITION && CHOCO_DRIVE="your drive"

if [[ -z $CHOCO_DRIVE ]]; then
  echo
  lsblk -o name,size,type,label,partlabel
  echo
  _exit_with_message "--drive is required, for example '--drive nvme0n1"
fi

# if CHOCO_DATA set and not CHOCO_ROOT throw error
# shellcheck disable=SC2015
$CHOCO_DATA && [[ -z $CHOCO_ROOT ]] && _exit_with_message "if using the --data flag, root size parition must also be set with --root 20G"

$CHOCO_ZEN && $CHOCO_LTS && _exit_with_message "zen or lts?? I am not installing both sorry!"

CHOCO_KERNEL="linux"
$CHOCO_ZEN && CHOCO_KERNEL="linux-zen"
$CHOCO_LTS && CHOCO_KERNEL="linux-lts"

[[ -n "$CHOCO_AUR" ]] && case "$CHOCO_AUR" in
  yay)
    AUR_URL="https://aur.archlinux.org/yay.git"
    ;;
  paru)
    AUR_URL="https://aur.archlinux.org/paru.git"
    ;;
  *)
    _exit_with_message "Unknown aur helper, use paru or yay"
    ;;
esac
main "$@" | tee /root/chocolate.log

exit
