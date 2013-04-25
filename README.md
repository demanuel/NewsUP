NewsUP
======

Backup your personal files to the usenet!

# Intro


This program will upload binary files to the usenet (with some rules) and generates a NZB file.
This program is licensed with GPLv3.

# What does this program do

It will upload a file or folder to the usenet. If the file is bigger than 30MiB
the file will be compressed and split in volumes of 30, 50 or 100 MiBs, depending
on how many volumes will be required to be created.
The compressed format will be 7z (although it won't really compress. The level of compression is 0).
If you choose format zip the file won't be splitted and it won't be possible to set
a password.
After the "file compression" takes place the parity files will be generated and all the files will be 
uploaded (all the files *generated* will be later *removed*)


## Options

-fo: format. At this moment only 7z or zip are supported (default: 7z)
-passwd: password. It will set the password of the 7zip file. It only be setted if the format is 7z and if the file is bigger than 30MiB.
-s: server where the files will be uploaded to (SSL server not supported) REQUIRED
-p: port. If the server doesn't use the traditional 119 port (SSL port not supported)
-n: newsgroups. You can have as many as you want. This will crosspost the file. REQUIRED
-t: number of threads or connections for uploading the files (default: 2). Tip: you can use this to throttle your bandwidth usage :-P
-r: the redundancy of the parity archives (default: 0.2 - or 20% :-) )
-e: email of the uploader (default: 'Anonymous Coward <anonymous.coward@mailinator.com>')
-c: comment (you can have 2!) (default: ['Enjoy','Powered by NewsUp'])


A NZB file will be generated.

## Examples:
$ perl newsup.pl -f archlinux-2013.04.01-dual.iso -s <upload server> -n alt.binaries.test -fo zip
This command will create a archlinux-2013.04.01-dual.iso.zip file and the respective parity files. It 
will uploading them to the server


$ perl newsup.pl -f archlinux-2013.04.01-dual.iso -s <upload server> -n alt.binaries.test
This command will perform the same as the command above but it will create several .7z files (each
one with 30, 50 or 100 MiB) and upload them.

$ perl newsup.pl -f archlinux-2013.04.01-dual.iso -s <upload server> -n alt.binaries.test -passwd <my password>
This command will perform the same as the command above but the upload 7zip file will be passworded. *The password
will be on the NZB file!*

$ perl newsup.pl -f /some/folder -s <upload server> -n alt.binaries.test
This command will create an archive with all the contents inside de folder (split it, if it's recommended) and upload it.

$ perl newsup.pl -f /some/folder -s <upload server> -n alt.binaries.test -t 50
This command will perform the same as the command above but it will use 50 connections


# What doesn't do
At this moment it doesn't support SSL. It will in a future release!

# Requirements (besides perl and some libraries)
1- 7zip (http://p7zip.sourceforge.net/)
2- par2cmdline (https://github.com/BlackIkeEagle/par2cmdline)

# END

Enjoy it. Email me at demanuel@ymail.com if you have Any request, info or question.

Best regards!
