#!/bin/bash

# Author: David Santiago <demanuel@ymail>

# Note: This bash script sucks, but i don't care as long it does what i need without fuss

git clone https://github.com/demanuel/NewsUP.git

mkdir -p newsup/DEBIAN
mkdir -p newsup/usr/local/bin newsup/usr/share/perl5/ newsup/etc/newsup
cp -r NewsUP/bin/newsup.pl newsup/usr/local/bin/newsup
chmod +x newsup/usr/local/bin/newsup
cp -r NewsUP/lib/NewsUP newsup/usr/share/perl5/
cp -r NewsUP/conf/newsup.conf newsup/etc/newsup/newsup.conf.example

cd NewsUP
echo "Package: NewsUP" > ../newsup/DEBIAN/control
echo "Version: "$(date +"%Y%m%d")"-"$(git rev-parse --short HEAD) >> ../newsup/DEBIAN/control
echo "Maintainer: David Santiago <demanuel@ymail.com>" >> ../newsup/DEBIAN/control
echo "Description: Binary usenet uploader/poster with support to multiple connections, SSL and NZB" >> ../newsup/DEBIAN/control
echo "Homepage: https://github.com/demanuel/NewsUP" >> ../newsup/DEBIAN/control
echo "Architecture: all" >> ../newsup/DEBIAN/control
echo "Depends: perl (>= "$(apt-cache show perl|grep Version | tail -n 1 | cut -d ' ' -f 2)"), libio-socket-ssl-perl, libnet-ssleay-perl, libxml-libxml-perl, libfile-copy-recursive-perl, libconfig-tiny-perl, libinline-c-perl, make" >> ../newsup/DEBIAN/control
echo "Recommends: par2, rar, p7zip" >> ../newsup/DEBIAN/control
echo "echo \"Create a ~/.config/newsup.cfg for the user\\nPlease check /etc/newsup/newsup.conf.example\"" >> ../newsup/DEBIAN/postinst
chmod 755 ../newsup/DEBIAN/postinst
cd ..
sed -i "s/use 5.026/use 5.022/" newsup/usr/local/bin/newsup
sed -i "s/use 5.026/use 5.022/" newsup/usr/share/perl5/NewsUP/*


dpkg-deb --build newsup

echo "Trying to install the package. Please make sure you have all the dependencies installed: "
echo "perl, libio-socket-ssl-perl, libnet-ssleay-perl, libxml-libxml-perl, libfile-copy-recursive-perl, libconfig-tiny-perl, libinline-c-perl, make"
echo ""
echo "Warning: if you don't have all the dependencies, the installation will fail and you'll need to run this again!"
echo ""
echo "Press enter to continue"
read

sudo dpkg -i newsup.deb

rm -rf NewsUP newsup newsup.deb
