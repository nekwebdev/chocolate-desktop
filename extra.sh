#!/usr/bin/env bash
# https://github.com/nekwebdev/chocolate-template
# @nekwebdev
# LICENSE: GPLv3
# Copied lots of tricks: https://github.com/LukeSmithxyz/LARBS
set -e

# flags:
# --user username
# --aur paru or yay
# --dots url to a bare git repository, more info: https://www.saintsjd.com/2011/01/what-is-a-bare-git-repository/
# --pkgs path to the packages csv file
# required flags: none, will use defaults, ask or skip

###### => variables ############################################################
CHOCO_USER="" # will ask if left empty
CHOCO_AUR="paru" # default
CHOCO_DOTS="" # will skip if empty
CHOCO_PKGS="packages.csv" # default
CHOCO_CONFIG="" # specify a config file path
# use local repository for dotfiles
CHOCO_DEV=false

###### => files templates ######################################################
# exmple file templates
# /usr/share/libalpm/hooks/shtodash.hook
DASH_HOOK="$(cat <<-EOF
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = bash

[Action]
Description = Re-pointing /bin/sh symlink to dash...
When = PostTransaction
Exec = /usr/bin/ln -sfT /usr/bin/dash /usr/bin/sh
Depends = dash
EOF
)"

###### => echo helpers #########################################################
# _echo_step() outputs a step collored in cyan (6), without outputing a newline.
function _echo_step() { tput setaf 6;echo -n "$1";tput sgr 0 0; }
# _exit_with_message() outputs and logs a message in red (1) before exiting the script.
function _exit_with_message() { echo;tput setaf 1;echo "$1";tput sgr 0 0;echo;exit 1; }
# _echo_right() outputs a string at the rightmost side of the screen.
function _echo_right() { local T=$1;echo;tput cuu1;tput cuf "$(tput cols)";tput cub ${#T};echo "$T"; }
# _echo_success() outputs [ OK ] in green (2), at the rightmost side of the screen.
function _echo_success() { tput setaf 2;_echo_right "[ OK ]";tput sgr 0 0; }
# _echo_failure() outputs [ OK ] in red (1), at the rightmost side of the screen.
function _echo_failure() { tput setaf 1;_echo_right "[ FAILED ]";tput sgr 0 0; }

###### => install helpers ######################################################
function installpkg() { pacman --noconfirm --needed -S "$1" >/dev/null 2>&1; }

function aurInstall() {
	_echo_step "  (Installing \`$1\` ($((n-1)) of $TOTAL_PKG) from the AUR. $1 $2)"
	echo "$AUR_CHECK" | grep -q "^$1$" && _echo_success && return 0
	sudo -u "$CHOCO_USER" "$CHOCO_AUR" -S --noconfirm "$1" >/dev/null 2>&1 || { _echo_failure && return 0; }
  _echo_success
}

function gitMakeInstall() {
	local progname="$(basename "$1" .git)"
	local dir="/home/$CHOCO_USER/.local/src/$progname"
	_echo_step "  (Installing \`$progname\` ($((n-1)) of $TOTAL_PKG) via \`git\` and \`make\`. $(basename "$1") $2)"
	sudo -u "$CHOCO_USER" git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return 0 ; sudo -u "$CHOCO_USER" git pull --force origin master >/dev/null 2>&1; } || { _echo_failure && return 0; }
	cd "$dir" || exit 1
	make >/dev/null 2>&1 || { _echo_failure && cd /tmp && return 0; }
	make install >/dev/null 2>&1 || { _echo_failure && cd /tmp && return 0; }
	cd /tmp
  _echo_success
}

function pipInstall() { \
	_echo_step "  (Installing the Python package \`$1\` ($((n-1)) of $TOTAL_PKG). $1 $2)"
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1" || { _echo_failure && return 0; }
  _echo_success
}

function pacmanInstall() {
	_echo_step "  (Installing \`$1\` ($((n-1)) of $TOTAL_PKG). $1 $2)"
	installpkg "$1"|| { _echo_failure && return 0; }
  _echo_success
}

function installPackages() {
  _echo_step "Installing required packages"; echo
	([ -f "$1" ] && cp "$1" /tmp/packages.csv) || curl -Ls "$1" | sed '/^#/d' > /tmp/packages.csv
  TOTAL_PKG=$(wc -l < /tmp/packages.csv)
  # remove header line from total
  TOTAL_PKG=$((TOTAL_PKG-1))
	AUR_CHECK=$(pacman -Qqm)
  # ensure src directories exist
  mkdir -p "/home/$CHOCO_USER/.local/src"
	while IFS=, read -r tag program comment; do
		n=$((n+1))
    # skip header line, account for that with $((n-1)) in outputs
    [[ "$n" == '1' ]] && continue
    # shellcheck disable=SC2001
		echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"A") aurInstall "$program" "$comment" ;;
			"G") gitMakeInstall "$program" "$comment" ;;
			"P") pipInstall "$program" "$comment" ;;
			"#") ;; # comment do nothing
			*) pacmanInstall "$program" "$comment" ;;
		esac
	done < /tmp/packages.csv
  echo
}

function installXdgUserDirs() {
  _echo_step "Install xdg-user-dirs"; echo
  _echo_step "  (Configure xdg-user-dirs defaults)"
  sed -i "/DESKTOP/d" /etc/xdg/user-dirs.defaults
  sed -i "s/Downloads/downloads/" /etc/xdg/user-dirs.defaults
  sed -i "s+Templates+documents/templates+" /etc/xdg/user-dirs.defaults
  sed -i "/PUBLICSHARE/d" /etc/xdg/user-dirs.defaults
  sed -i "s/Documents/documents/" /etc/xdg/user-dirs.defaults
  sed -i "s+Music+documents/music+" /etc/xdg/user-dirs.defaults
  sed -i "s+Pictures+documents/pictures+" /etc/xdg/user-dirs.defaults
  sed -i "s+Videos+documents/videos+" /etc/xdg/user-dirs.defaults
  _echo_success

  _echo_step "  (Add .local/src folder to /etc/skel)"
  mkdir -p /etc/skel/.local/src
  _echo_success; echo
}

###### => functions ############################################################
function checkRootAndNetwork() {
  _echo_step "Ensure we are root and have internet by installing script dependencies"; echo
  _echo_step "  (Set pacman parallel downloads to 15 and use Colors with ILoveCandy)"
  sed -i "s/^#ParallelDownloads = 5$/ParallelDownloads = 15/;s/^#Color$/Color/" /etc/pacman.conf
  grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
  _echo_success
  _echo_step "  (Install dialog, xdg-user-dirs, base-devel and git)"
  pacman --noconfirm --needed -S dialog xdg-user-dirs base-devel git >/dev/null 2>&1 || _exit_with_message \
  "Are you root and with an internet connection?"
  _echo_success; echo
}

function configurePrivilegedUser() {
  installXdgUserDirs
  if id -u "$CHOCO_USER" >/dev/null 2>&1; then
    _echo_step "$CHOCO_USER user already exists"
    _echo_success; echo
  else
    # prompts
    if [[ -z "$CHOCO_USER" ]]; then
      CHOCO_USER=$(dialog --inputbox "Enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
      while ! echo "$CHOCO_USER" | grep -q "^[a-z_][a-z0-9_-]*$"; do
        CHOCO_USER=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
      done
    fi
    local pass1=$(dialog --no-cancel --passwordbox "Enter a password for $CHOCO_USER." 10 60 3>&1 1>&2 2>&3 3>&1)
    local pass2=$(dialog --no-cancel --passwordbox "Retype $CHOCO_USER password." 10 60 3>&1 1>&2 2>&3 3>&1)
    while ! [ "$pass1" = "$pass2" ]; do
      unset pass2
      pass1=$(dialog --no-cancel --passwordbox "Passwords do not match for $CHOCO_USER.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
      pass2=$(dialog --no-cancel --passwordbox "Retype $CHOCO_USER password." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
    unset pass2

    printf '\033c'; echo
    _echo_step "Create $CHOCO_USER user"; echo
    useradd -g wheel -s /bin/bash -d /home/"$CHOCO_USER" -m -k /etc/skel "$CHOCO_USER"
    {
      echo "$pass1";
      echo "$pass1";
    } | passwd "$CHOCO_USER" >/dev/null 2>&1
    unset pass1
    _echo_step "  (User created)"
    _echo_success
  fi

  _echo_step "  (Generate $CHOCO_USER xdg-user-dirs)"
  /bin/su - "$CHOCO_USER" -c "xdg-user-dirs-update"
  _echo_success

  _echo_step "  (Add wheel group to sudoers)"
  mkdir -p /etc/sudoers.d/
  echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel
  chmod 640 /etc/sudoers.d/10-wheel
  _echo_success; echo
}

function prePackagesConfig() {
  _echo_step "System configuration before packages are installed"; echo
  _echo_step "  (Add wheel group to sudoers with NOPASSWD)"
  echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
  _echo_success

  _echo_step "  (Use all cores when compressing packages and for compilation)"
  sed -i "s/^COMPRESSXZ=(.*/COMPRESSXZ=(xz -c -z - --threads=0)/" /etc/makepkg.conf
  sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
  _echo_success

  _echo_step "  (Configure journald to be persistent at a 500M limit)"
  mkdir -p /etc/systemd/journald.conf.d
	local persist_conf=/etc/systemd/journald.conf.d/00-persistent-storage.conf
	echo "[Journal]" > "$persist_conf"
	echo "Storage=persistent" >> "$persist_conf"
	local size_conf=/etc/systemd/journald.conf.d/00-journal-size.conf
	echo "[Journal]" > "$size_conf"
	echo "SystemMaxUse=500M" >> "$size_conf"
  _echo_success; echo
}

function installAurHelper() {
  command -v /usr/bin/"$CHOCO_AUR" >/dev/null 2>&1 && return

  _echo_step "Install $CHOCO_AUR AUR helper"; echo
  _echo_step "  (Install dependencies base-devel and git)"
  installpkg base-devel git
  _echo_success

  _echo_step "  (Download $CHOCO_AUR source and build package, this can take a few minutes)"
  /bin/sudo -u "$CHOCO_USER" /bin/bash -c "git clone $AUR_URL /home/$CHOCO_USER/.local/src/$CHOCO_AUR" >/dev/null 2>&1
  /bin/sudo -u "$CHOCO_USER" /bin/bash -c "cd /home/$CHOCO_USER/.local/src/$CHOCO_AUR && makepkg --noconfirm --needed -si" >/dev/null 2>&1
  _echo_success; echo
}

function cloneBareDotfiles() {
  [[ -z $CHOCO_DOTS ]] && return

  local work_tree="/home/$CHOCO_USER"
  local git_dir="$work_tree/.config/dotfiles"
  local dots="/usr/bin/git --git-dir=$git_dir --work-tree=$work_tree"

  _echo_step "Deploying dotfiles"; echo
  if $CHOCO_DEV; then
    _echo_step "  (Dev mode, copy from /root/chocodots-local)"
    cp -af /root/chocodots-local/. "$work_tree"/
    _echo_success
  else
    [[ -d $git_dir ]] && return

    _echo_step "  (Initialize local bare git repository)"
    mkdir -p "$git_dir"
    git init --bare "$git_dir" >/dev/null 2>&1
    $dots config status.showUntrackedFiles no
    _echo_success

    _echo_step "  (Pull from $CHOCO_DOTS)"
    $dots remote add origin "$CHOCO_DOTS"
    $dots branch -m main
    $dots pull origin main >/dev/null 2>&1
    _echo_success
  fi

  _echo_step "  (Cleanup README.md and LICENSE)"
  for file in README.md LICENSE; do
    if [[ -f "$work_tree/$file" ]]; then
      rm -f "$work_tree/$file"
      $dots update-index --assume-unchanged "$work_tree/$file"
    fi
  done

  chown -R "$CHOCO_USER":wheel "$work_tree"

  _echo_success; echo

  # check for extra cocoa!
  local cocoa="$work_tree/.config/cocoa/cocoa.sh"
  if [[ -f $cocoa ]]; then
    source "$cocoa"
    addCocoa
  fi
}

function postPackagesConfig() {
  _echo_step "System configuration after packages are installed"; echo

  _echo_step "  (Enable ntpd service)"
  systemctl enable -f ntpd.service >/dev/null 2>&1
  _echo_success

  _echo_step "  (Remove wheel group from passwordless sudo)"
  sed -i "/%wheel ALL=(ALL) NOPASSWD: ALL/d" /etc/sudoers
  _echo_success

	if command -v /usr/bin/dash >/dev/null 2>&1; then
    _echo_step "  (Set dash as symlink for sh instead of bash)"
    ln -sfT /usr/bin/dash /usr/bin/sh
    echo "$DASH_HOOK" > /usr/share/libalpm/hooks/shtodash.hook
    _echo_success
  fi
}

###### => main #################################################################
function main() {
  # main steps
  checkRootAndNetwork

  configurePrivilegedUser

  prePackagesConfig

  installAurHelper

  installPackages $CHOCO_PKGS

  cloneBareDotfiles

  postPackagesConfig

  # clean up and save log
  rm -rf "$0" "$CHOCO_PKGS" /root/chocodots-local
  [[ -f /root/chocolate.extra.log ]] && mv -f /root/chocolate.extra.log /var/log/chocolate.extra.log
  exit 0
}

###### => parse flags ##########################################################
CHOCO_DEV=false
while (( "$#" )); do
  case "$1" in
    --config)
      if [[ -n "$2" ]] && [[ "${2:0:1}" != "-" ]] && [[ -f "$2" ]]; then
        CHOCO_CONFIG=$2; shift
      else
        _exit_with_message "when using --config a path must be specified. Example: '--config ./myconfig.conf'"
      fi ;;
    --user)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        CHOCO_USER=$2; shift
      fi ;;
    --aur)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        CHOCO_AUR=$2; shift
      else
        _exit_with_message "when using --aur a program name must be specified. Example: '--aur paru'"
      fi ;;
    --dots)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        CHOCO_DOTS=$2; shift
      else
        _exit_with_message "when using --dots an url to a bare git repository must be specified. Example: '--dots https://github.com/myname/chocodots'"
      fi ;;
    --pkgs)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        CHOCO_PKGS=$2; shift
      else
        _exit_with_message "when using --pkgs a path to the packages csv file must be specified. Example: '--pkgs ./mypkgs.csv'"
      fi ;;
    --dev) CHOCO_DEV=true; shift ;;
    *)
      shift ;;
  esac
done

# source config file for default values
[[ -f $CHOCO_CONFIG ]] && source "$CHOCO_CONFIG"

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

[[ ! -f $CHOCO_PKGS ]] && _exit_with_message "$CHOCO_PKGS does not exists, either move your packages.csv to this path or edit 'CHOCO_PKGS' in extra.sh"

main "$@" | tee /root/chocolate.extra.log

exit 0