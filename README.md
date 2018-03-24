NewsUP
======
NewsUP a binary usenet uploader/poster. Backup your personal files to the usenet!
It will run on any platform that supports perl that matches the requirements (check the wiki for on how to run in windows)

# Intro

This program will upload binary files to the usenet.
This program is licensed with GPLv3.

## note
This readme contains the basic info on how to run newsup and it's options.
For windows installation, or another stuff more specific to some environment/script please check the wiki.


## Alternatives
* newsmangler (https://github.com/madcowfred/newsmangler)
* newspost (https://github.com/joehillen/newspost)
* pan (http://pan.rebelbase.com/)
* sanguinews (https://github.com/tdobrovolskij/sanguinews)
* GoPostStuff (https://github.com/madcowfred/GoPostStuff/)
* Nyuu (https://github.com/animetosho/Nyuu)

# What does this program do

It will upload a file or folder to the usenet.
If it is a folder it will search for files inside of the folder.
A NZB file will be generated for later retrieving.

## Supports
* SSL
* Multi connections
* Header Check (including to a different server from the one the article was uploaded)
* NZB Creation
* Obfuscation
* RAR creation (you need *rar* command in your path)
* PAR2 creation (you need *par2cmdline* command in your path)

# Requirements:
* Perl (preferably 5.020 or higher)
* Perl modules: Config::Tiny, IO::Socket::SSL, Inline::C, File::Copy::Recursive (all other modules should exist on core.)
* rar and par2cmdline (**optional** only if you want to use the RARNPAR option)

If you have any issue installing/running this check the wiki, if you still have issues please open a ticket or send me an email so i can try to help you.

# Running
The most basic way to run it (please check the options section) is:
$ perl newsup.pl -file my_file -con 2 -news alt.binaries.test

If you have a nfo file:
$ perl newsup.pl -file my_file -con 2 -news alt.binaries.test -nfo nfo_file

If you have a bunch of files and you don't want to keep launching the newsup process:
$perl newsup.pl -list my_list -con 2 -news alt.binaries.test

The my_list file must have one file/folder per line.


# Advanced
NewsUP uses C code to do the yenc enconding. The code needs to be compiled.
You can change the C compiler (GCC, CLang,..) and the compiler flags by
setting the environment variables NEWSUP_CC (for the compiler to be used)
and NEWSUP_CCFLAGS (for the compiler flags).
By default it's set to use GCC with -O3 flag.

This can be a difference between being a bit faster or a bit slower.

Only set this options if you know what you're doing.
After this option is set or change you need to remove the inline folder
so that the code is recompiled again.

## Config file
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
rarnpar= 1
rar_password=newsup
# full path to par2 executable
par2_path = par2
# full path to rar executable
rar_path = rar
temp_folder = /data/tmp
# if the nzb is also uploaded
upload_nzb = 1
# The size of the split rars
split_size = 50
nzb_save_path = /data/uploads/
# enable or disable the par'ing
par2 = 0
# redundancy in %
par2_redundancy = 15

```

## Command line options
- help 
- file # string
- list # string
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
- rarnpar
- rarPassword # string
- splitSize # integer
- headers # string in the form key=val
- name # string
- progressBarSize # integer
- tempFolder # string
- nfo #string


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
