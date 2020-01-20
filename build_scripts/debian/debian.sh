#!/bin/bash
# Author: David Santiago <demanuel@ymail>
# Note: This bash script sucks, but i don't care as long it does what i need without fuss

miss_deps=0
use_sudo=1
downloader='git'
minimum_version='5.30'
system_install=1
local_path='.'
cleanup_afterwards=0
build_only=0

function usage {
    echo "Usage: $0 [ -l PATH ] [ -c ] [ -b ]" 1>&2
    echo ""
    echo "Options:"
    echo "   -l PATH           install locally on path. It will create the folder PATH/bin and PATH/lib if they don't exist!"
    echo "   -c                cleanup all the downloaded/created files"
    echo "   -b                build only and don't install"
}

function check_deps {
    if [[ ! -x "$(command -v bc)" ]]
    then
	echo "To use this script install: bc"
	miss_deps=1
    fi

    if [[ ! -x "$(command -v git)" ]]
    then
	if [[ ! -x "$(command -v wget)" ]]
	then
	    
	    if [[ ! -x "$(command -v curl)" ]]
	    then
		echo "To use this script install: git/wget or curl"
		miss_deps=1
	    else
		downloader='curl'
	    fi
	else
	    downloader='wget'
	fi
    fi

    if [[ ! -x "$(command -v sed)" ]]
    then
	echo "To use this script install: sed"
	miss_deps=1
    fi

    if [[ ! -x "$(command -v awk)" ]]
    then
	echo "To use this script install: awk"
	miss_deps=1
    fi

    if [[ ! -x "$(command -v patch)" ]]
    then
	echo "To use this script install: patch"
	miss_deps=1
    fi

    if [[ ! -x "$(command -v wget)" ]]
    then
	echo "To use this script install: wget"
	miss_deps=1
    fi

    if [[ ! -x "$(command -v date)" ]]
    then
	echo "To use this script install: date"
	miss_deps=1
    fi

    if [[ ! -x "$(command -v sudo)" ]]
    then
	use_sudo=0
    fi


    if [[ miss_deps -eq 1 ]]
    then
	echo ""
	echo "Please install the utilities mentioned above"
	exit 1
    fi
}

function download_newsup {
    if [ "$downloader" = "git" ]
    then
	if [[ ! -d NewsUP ]]
	then
	    git clone https://github.com/demanuel/NewsUP.git
	fi
    else
	if [ "$downloader" = "wget" ]
	then
	    wget https://github.com/demanuel/NewsUP/archive/master.zip
	else
	    curl -O -L https://github.com/demanuel/NewsUP/archive/master.zip
	fi
	unzip master.zip
	mv NewsUP-master NewsUP
    fi
  
}


function check_minimum_version {
    minimum_version=`find . -type f -exec awk '/use 5./{v=(($2+0)%5)*1000; print 5"."v}' {} + | sort -r | head -n 1`
    current_version=`perl -e 'print join(".", @{$^V->{version}}[0,1])'`
    (( $(echo "$current_version < $minimum_version" | bc -l)  )) && echo "Please update your perl version" && exit 1
}

function create_package {
    #declare -A versions=( ["debian"]="5.24" ["ubuntu"]="5.28" )
    mkdir -p newsup/DEBIAN
    mkdir -p newsup/usr/local/bin newsup/usr/share/perl5/ newsup/etc/newsup
    cp -r bin/newsup.pl newsup/usr/local/bin/newsup
    chmod +x newsup/usr/local/bin/newsup
    cp -r lib/NewsUP newsup/usr/share/perl5/
    cp -r conf/newsup.conf newsup/etc/newsup/newsup.conf.example

    installed_perl_version=`apt-cache show perl|grep Version | tail -n 1 | awk '{print substr($2, 1, 4)}'`
    #installed_perl_version=5.26

    version="`date +'%Y%m%d'`-`git rev-parse --short HEAD`"
    cat > newsup/DEBIAN/control << EOT
Package: NewsUP
Version: ${version}
Maintainer: David Santiago <demanuel@ymail.com>
Description: Fully featured binary usenet uploader/poster
Homepage: https://github.com/demanuel/NewsUP
Architecture: all
Depends: perl, libio-socket-ssl-perl, libnet-ssleay-perl, libxml-libxml-perl, libfile-copy-recursive-perl, libconfig-tiny-perl, libinline-c-perl, make
Recommends: par2, rar, p7zip
EOT

    echo "echo \"Create a ~/.config/newsup.conf for the user\\nPlease check /etc/newsup/newsup.conf.example\"" >> newsup/DEBIAN/postinst
    chmod 755 newsup/DEBIAN/postinst


    dpkg-deb --build newsup
}

function install_package {

    if [[ $use_sudo -eq 1 ]]
    then

	sudo apt-get install $packages
	sudo apt --fix-broken install
	sudo dpkg -i newsup.deb
    else
	su -c "apt-get install $packages && apt --fix-broken install && dpkg -i newsup.deb"
    fi

    if [[ $? -eq 0 ]]
    then

	echo "Installation successfull!"

	#  rm -rf NewsUP newsup newsup.deb

    else
        echo "Creating the package failed! Please check the error message above."
        echo ""
        echo "Please make sure you have all the dependencies installed: "
        echo "perl, libio-socket-ssl-perl, libnet-ssleay-perl, libxml-libxml-perl, libfile-copy-recursive-perl, libconfig-tiny-perl, libinline-c-perl, make"
        echo ""
    fi
}

while getopts "l:cb" options
do
    case "${options}" in
	l)
	    system_install=0
	    if [[ -d "${OPTARG}" ]]
	    then
		pushd "${OPTARG}" >/dev/null
		local_path="$(pwd)"
		popd >/dev/null
		mkdir -p "${local_path}/bin/" &>/dev/null
		mkdir -p "${local_path}/lib/" &>/dev/null
	    else
		echo "The folder ${OPTARG} doesn't exist! Please make sure it exists!"
		exit 1
	    fi
	    ;;
	c)
	    cleanup_afterwards=1
	    ;;
	b)
	    build_only=1
	    ;;
	*)
	    usage
	    exit 1
	    ;;
    esac
done

check_deps
download_newsup

cd NewsUP
check_minimum_version

if [[ ${system_install} -eq 1 ]]
then
    create_package
    if [[ ${build_only} -eq 0 ]]
    then
	install_package
    fi
else
    cp bin/newsup.pl ${local_path}/bin/newsup
    chmod +x ${local_path}/bin/newsup
    cp -r lib/NewsUP/ ${local_path}/lib/
    echo "Please make sure that ${local_path}/bin/ is in your PATH environment variable"
    echo "Please make sure that ${local_path}/lib/ is in your PERL5LIB environment variable"
fi

cd -

if [[ ${cleanup_afterwards} -eq 1 ]]
then
    rm -rf NewsUP
fi


