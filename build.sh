#!/usr/bin/env bash
# https://github.com/nekwebdev/chocolate-template
# @nekwebdev
# LICENSE: GPLv3
# Inspiration: Erik Dubois
# https://www.alci.online
set -e

###### => variables ############################################################
buildFolder="/tmp/archiso-tmp"
outFolder="${HOME}/archlinux-chocoiso-out"

###### => functions ############################################################
# _echo_step() outputs a step collored in cyan, without outputing a newline.
function _echo_step() {
	tput setaf 6 # 6 = cyan
	echo -n "$1"
	tput sgr 0 0  # reset terminal
}

# _echo_equals() outputs a line with =
function _echo_equals() {
	local cnt=0
	while [  $cnt -lt "$1" ]; do
		printf '='
		(( cnt=cnt+1 ))
	done
}

# _echo_title() outputs a title padded by =, in yellow.
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

# _echo_step_info() outputs additional step info in white, without a newline.
function _echo_step_info() {
	tput setaf 7 # 7 = white
	echo -n " ($1)"
	tput sgr 0 0  # reset terminal
}

# _echo_right() outputs a string at the rightmost side of the screen.
function _echo_right() {
	local txt=$1
	echo
	tput cuu1
	tput cuf "$(tput cols)"
	tput cub ${#txt}
	echo "$txt"
}

# _echo_success() outputs [ OK ] in green, at the rightmost side of the screen.
function _echo_success() {
	tput setaf 2 # 2 = green
	_echo_right "[ OK ]"
	tput sgr 0 0  # reset terminal
}

function find_and_replace() {
	find ${buildFolder}/archiso/profiledef.sh -type f -exec sed -i "/$1/a $2" {} \;
}

function copy_dotfiles() {
  _echo_step_info "Set a password for root and enable sshd"
  cat <<EOF >> "${buildFolder}/archiso/airootfs/root/.automated_script.sh"
{
  echo "root";
  echo "root";
} | passwd
systemctl enable --now sshd
EOF
  _echo_success; echo

  _echo_step_info "Copy scripts to root home"
  cp chocolate.sh ${buildFolder}/archiso/airootfs/root
  cp chococinema.sh ${buildFolder}/archiso/airootfs/root
  cp extra.sh ${buildFolder}/archiso/airootfs/root
  cp packages.csv ${buildFolder}/archiso/airootfs/root
  FIND='livecd-sound'
  find_and_replace $FIND '  ["/root/chocolate.sh"]="0:0:755"'
  find_and_replace $FIND '  ["/root/chococinema.sh"]="0:0:755"'
  find_and_replace $FIND '  ["/root/extra.sh"]="0:0:755"'
  _echo_success
}

###### => main #################################################################
_echo_title "Arch Linux ISO builder"; echo
# change working directory to script directory
cd "$(dirname "$0")" || exit 1

###### => Step 1 ###############################################################
_echo_step "Step 1 -> Making archiso verbose..."; echo

_echo_step_info "Make mkarchiso verbose"; echo
sudo sed -i 's/quiet="y"/quiet="n"/g' /usr/bin/mkarchiso
_echo_success
echo

###### => Step 2 ###############################################################
_echo_step "Step 2 -> Setup the build folder"; echo
_echo_step_info "Build folder : ${buildFolder}"; _echo_success
_echo_step_info "Out folder : ${outFolder}"; _echo_success
_echo_step_info "Delete any previous build folder"
[[ -d $buildFolder ]] && sudo rm -rf "$buildFolder"
_echo_success

_echo_step_info "Copy the archiso releng folder to the build folder"
mkdir "$buildFolder"
cp -r /usr/share/archiso/configs/releng/ "${buildFolder}/archiso"; _echo_success
echo

###### => Step 3 ###############################################################
_echo_step "Step 3 -> Customize the iso"; echo
copy_dotfiles
echo

if [[ $1 == "--clear" ]]; then
  _echo_step "Extra Step -> Clear packman cache"
  yes | sudo pacman -Scc
  _echo_success
  echo
fi

###### => Step 4 ###############################################################
_echo_step "Step 4 -> Building the ISO - be patient"; echo
[[ -d $outFolder ]] || mkdir "$outFolder"
cd "${buildFolder}/archiso/" || exit 1

sudo mkarchiso -v -w "$buildFolder" -o "$outFolder" "${buildFolder}/archiso/"
_echo_step_info "ISO build"; _echo_success

_echo_step_info "Copying pkglist"
isolabel=archlinux-$(date +%Y.%m.%d)-x86_64
cp "${buildFolder}/iso/arch/pkglist.x86_64.txt"  "${outFolder}/${isolabel}-pkglist.txt"
_echo_success
cd "$outFolder"
isolabel="${isolabel}.iso"
_echo_step_info "Building sha1sum"; echo
sha1sum "$isolabel" | tee "$isolabel".sha1
_echo_success
_echo_step_info "Building sha256sum"; echo
sha256sum "$isolabel" | tee "$isolabel".sha256
_echo_success
_echo_step_info "Building md5sum"; echo
md5sum "$isolabel" | tee "$isolabel".md5
_echo_success
echo

###### => Step 5 ###############################################################
_echo_step "Step 5 -> Cleanup"; echo
sudo rm -rf "$buildFolder"
_echo_success
echo

_echo_title "Check your out folder : ${outFolder}"; echo

exit 0
