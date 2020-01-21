NewsUP
======
NewsUP is a fully feature high performance binary usenet uploader/poster. Backup your personal files to the usenet!


It runs on any platform that supports perl that matches the requirements (check the wiki for on how to run in windows, ubuntu/debian and arch linux installation scripts provided)

# Intro

This program will upload binary files to the usenet.
This program is licensed with GPLv3.

## note
This readme contains the basic info on how to run newsup and it's options.

For windows installation, or another stuff more specific to some environment/script please check the wiki.

# What does this program do

It will upload a file or folder to the usenet.
If it is a folder it will search for files inside of the folder.
It can obfuscate the uploads.
A NZB file will be generated for later retrieving.

## Extra functionalities - Wiki
On the wiki there's also instructions on how to monitor a folder for new content and upload it automatically, and how to launch the upload via torrent client (after the download is completed).
Please check the wiki in https://github.com/demanuel/NewsUP/wiki


## Obfuscation warning

Some servers, might block you if you use this option. The servers and the users only see "normal" posts and are unable to determine any file you are uploading. So they consider it spamming.

This produces non 100% correct nzbs, although nzbget and sabnzb supports them. This is because with 100% compliance doesn't allow obfuscation.

Use this feature at your own responsability!

## Supports
* SSL
* Multi connections
* Header Check (including to a different server from the one the article was uploaded)
* NZB Creation
* Obfuscation
* RAR creation (you need *rar* command in your path)
* PAR2 creation (you need *par2cmdline* command in your path)
* Multiple nzb checking

# Requirements:
* Perl (5.020 or higher. Ideally 5.030)
* Perl modules: Config::Tiny, IO::Socket::SSL, Inline::C, File::Copy::Recursive (all other modules should exist on core.)
* rar and par2cmdline (**optional** only if you want to use the RARNPAR option)

If you have any issue installing/running this check the wiki, if you still have issues please open a ticket or send me an email so i can try to help you.

# Installing

NewsUP is distributed with two build scripts for linux systems based on Arch Linux and Debian to make it easier to install.
NewsUP can also be installed in windows.

Please check the wiki for more info.
For linux: https://github.com/demanuel/NewsUP/wiki/Installation
For windows: https://github.com/demanuel/NewsUP/wiki/Running-on-windows


# Running
The most basic way to run it (please check the options section) is:
$ perl newsup.pl -file my_file -con 2 -news alt.binaries.test

If you have a nfo file:
$ perl newsup.pl -file my_file -con 2 -news alt.binaries.test -nfo nfo_file

If you have a bunch of files and you don't want to keep launching the newsup process:
$ perl newsup.pl -list my_list -con 2 -news alt.binaries.test

The my_list file must have one file/folder per line.

If you want to check the status of a nzb:
$ perl newsup.pl -check my_nzb.nzb

In this example it will use the headercheck server settings defined in the config file.

# Advanced
NewsUP uses C code to do the yenc enconding. C is much faster than Perl. The code needs to be compiled.
You can change the C compiler (GCC, CLang,..) and the compiler flags by
setting the *environment variables* NEWSUP_CC (for the compiler to be used)
and NEWSUP_CCFLAGS (for the compiler flags).

This can be a difference between being a bit faster or a bit slower.

*Only set this options if you know what you're doing*

Example for GCC: `-Ofast -march=native -mcpu=native -mtune=native`

*After this option is set or change you need to remove the inline folder
so that the code is recompiled again.*

## Note
Because the C encoding is done with the C language, it will create a directory named `_Inline`.
The `_Inline` folder is where the compiled code is saved. Since we don't want to compile it everytime you run it
(because compiling is slow) the _Inline folder is kept. It can be removed without any problems.

If you want to know how to change the location of this folder, please check the  oficial documentation
for Inline: https://metacpan.org/pod/distribution/Inline/lib/Inline.pod#The-Inline-directory

    The Inline 'directory'

    Inline needs a place to build your code and to install the results of the build. It uses a single directory named '.Inline/' under normal circumstances. If you create this directory in your home directory, the current directory or in the directory where your program resides, Inline will find and use it. You can also specify it in the environment variable PERL_INLINE_DIRECTORY or directly in your program, by using the directory keyword option. If Inline cannot find the directory in any of these places it will create a '_Inline/' directory in either your current directory or the directory where your script resides.

    One of the key factors to using Inline successfully, is understanding this directory. When developing code it is usually best to create this directory (or let Inline do it) in your current directory. Remember that there is nothing sacred about this directory except that it holds your compiled code. Feel free to delete it at any time. Inline will simply start from scratch and recompile your code on the next run. If you have several programs that you want to force to recompile, just delete your '.Inline/' directory.

    It is probably best to have a separate '.Inline/' directory for each project that you are working on. You may want to keep stable code in the <.Inline/> in your home directory. On multi-user systems, each user should have their own '.Inline/' directories. It could be a security risk to put the directory in a shared place like /tmp/.


# Scripting
If the option before_upload is defined and points to a script, it will invoke it and the user can do whatever it wants with the generated files.

Such script should be prepared to received all the processed files as input and it should print to the output one file per line. The output will be then uploaded.

Example:
```
#!/bin/bash

TEMP_FOLDER=`perl -n -e '/temp_folder\s*=\s*(.*)/ && print $1' ~/.config/newsup.conf`

cd ${TEMP_FOLDER}/

for f in $@
do
	mv "$f" $(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1);
done

for f in ${TEMP_FOLDER}/*
do
    echo $f
done
```

This example will rename the files to a random string. (Similar to what the --name switch would do, but in this no extension is set)
Please also note that these files can be temporary (according to what options the user defined) and as such will be deleted.

# Config file
**This config file needs to be in ~/.config/ folder**
```
[server]
server= nntp.server.com
port= 443
connections= 6
tls = 1
tls_ignore_certificate = 0
# To generate random ids or to use the returned ones from the server. Note: Some servers don't return anything. In that case change this option to 1
generate_ids = 0

[auth]
user= myLogin
password= myPassword

[upload]
uploader= NewsUP <NewsUP@somewhere.cbr>
newsgroups= alt.binaries.test
obfuscate = 0
# default value 750KBytes
size = 768000

[headerCheck]
enabled= 1
sleep= 20
retries= 3
connections = 3
server = nntp.server2.com
port = 119
user = myUser
password = myPassword

[metadata]
#You can put here anything you want to appear on the nzb header. It must have the pattern: word= a big one line sentence
client= NewsUP
veryWeirdInfoIWantToPutOnTheNZBMetadata= it's really very weird!

[extraHeaders]
#extra header. It will became X-extra-header
extra-header= value1
#extra header. Non valid because there's already one
X-extra-header= value3
#second extra header
extra-header2= value2
#non valid. Non valid headers are: from, newsgroups, message-id and subject.
from= test


[options]
skip_copy = 0 # If you want to copy the files first to the `temp_folder` option.
splitnpar= 1
# Command that will be used to generate the splitted files
# For rar files use:
# rar a -m0 -v50m -ed -ep1
split_cmd = 7z a -mx0 -v50m -t7z --
# pattern of the files generated with the split_cmd.
# If splitnpar is set to 1, these are the files that
# are going to be uploaded.
# For rar files use:
# *rar
split_pattern = *7z *[0-9][0-9][0-9]
par2 = 1
# full path to par2 executable
par2_path = par2
# this will be used if you use the obfuscation option
par2_rename_settings = c -s768000 -r0
par2_settings = c -s768000 -r15
temp_folder = /data/tmp # Make sure this folder exists. Even if the skip_copy is set to 1. This folder is still used for the split and par files
# if the nzb is also uploaded
upload_nzb = 1
nzb_save_path = /data/uploads/
no_nzb = 1
before_upload = /script/to/run/before_upload.sh # Make sure the file is executable
```

## Command line options
- help
- file # string
- list # string
- checkNZB # string
- uploadsize # integer
- obfuscate # integer
- newsgroup|group # string
- username # string
- password # string
- connections # integer
- server # string
- port # integer
- TLS
- generateIDs
- ignoreCert
- headerCheck
- headerCheckServer # string
- headerCheckPort # integer
- headerCheckRetries|retries=i
- headerCheckSleep # integer
- headerCheckUsername # string
- headerCheckPassword # string
- headerCheckConnections # integer
- comment # string. You can pass only two
- uploader # string
- metadata # string in the form key=val
- nzb # string
- unzb
- nzbSavePath # string
- splitnpar # negatable
- par2 # negatable
- headers # string in the form key=val
- name # string
- skip_copy # negatable
- tempFolder # string
- nfo #string
- noNzb

# Examples

```bash
$ perl newsup.pl -group alt.binaries.test -f <bin_file> -nzb <some_name>
```
If <bin_file> is a folder, it will transverse the folder searching for files.
The files will be uploaded. A NZB file with <some_name> will then be created.


# Gratitude
I want to express my gratitude to:

* All the users who use newsup.

* All the users who report bugs, features.

* All the users who send me info for the wiki (or anyone who updates the wiki)

* All the users who spread the word about this project.

* Everyone who sends me an email about this project.

* [XS News](https://www.xsnews.nl/en/index.html) for giving me a test account for free.

* [Newsbin](https://www.newsbin.com) for helping me with small yenc encoding warning.



# END

Enjoy it. Email me at demanuel@ymail.com if you have any request, info or question. You're also free to ping me if you just use it.

Best regards!
