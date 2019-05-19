#!/bin/bash
# Author: David Santiago <demanuel@ymail>
# Note: This bash script sucks, but i don't care as long it does what i need without fuss

if [[ ! -d NewsUP ]]
then
    git clone https://github.com/demanuel/NewsUP.git
fi

mkdir -p newsup/DEBIAN
mkdir -p newsup/usr/local/bin newsup/usr/share/perl5/ newsup/etc/newsup
cp -r NewsUP/bin/newsup.pl newsup/usr/local/bin/newsup
chmod +x newsup/usr/local/bin/newsup
cp -r NewsUP/lib/NewsUP newsup/usr/share/perl5/
cp -r NewsUP/conf/newsup.conf newsup/etc/newsup/newsup.conf.example

version="`date +'%Y%m%d'`-`git rev-parse --short HEAD`"
#installed_perl_version=`apt-cache show perl|grep Version | tail -n 1 | cut -d ' ' -f 2`
installed_perl_version=5.26
required_perl_version=`awk 'NR==2{a=(($2+0)%5)*1000}END{print 5"."a}' ./bin/newsup.pl`

if (( $(echo "${installed_perl_version} == 5.26" | bc -l ) ))
then
    echo "MATCH"
        CURRENT_DIR=`pwd`
        cd newsup/usr/share/perl5/NewsUP/
        wget https://gist.githubusercontent.com/demanuel/87e0eac62dd6d0919031131dd8fbad3d/raw/2a9a9db3694c8622b1fb06d5a880db1fa3a62230/newsup.526.patch
        patch -p0 Utils.pm <newsup.526.patch
        rm -rf newsup.526.patch
        cd $CURRENT_DIR
        required_perl_version=${installed_perl_version}
fi
cat > newsup/DEBIAN/control << EOT
Package: NewsUP
Version: ${installed_perl_version}
Maintainer: David Santiago <demanuel@ymail.com>
Description: Fully featured binary usenet uploader/poster
Homepage: https://github.com/demanuel/NewsUP
Architecture: all
Depends: perl (>= ${required_perl_version}), libio-socket-ssl-perl, libnet-ssleay-perl, libxml-libxml-perl, libfile-copy-recursive-perl, libconfig-tiny-perl, libinline-c-perl, make
Recommends: par2, rar, p7zip
EOT

echo "echo \"Create a ~/.config/newsup.conf for the user\\nPlease check /etc/newsup/newsup.conf.example\"" >> newsup/DEBIAN/postinst
chmod 755 newsup/DEBIAN/postinst


dpkg-deb --build newsup

if [[ $? -eq 0 ]]
then
        sudo dpkg -i newsup.deb
        rm -rf NewsUP newsup newsup.deb
else
        echo "Creating the package failed! Please check the error message above."
        echo ""
        echo "Please make sure you have all the dependencies installed: "
        echo "perl, libio-socket-ssl-perl, libnet-ssleay-perl, libxml-libxml-perl, libfile-copy-recursive-perl, libconfig-tiny-perl, libinline-c-perl, make"
        echo ""
fi
