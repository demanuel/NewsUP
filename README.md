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

## note 2
This is developed in a Linux box. I can guarantee that it will work on it. I'm unable to guarantee that the latest version will work on windows.
For a working solution in windows (with minimal testing on the windows platform) please check the tags W (in the form of Wx.x)


## Alternatives
* newsmangler (https://github.com/madcowfred/newsmangler)
* newspost (https://github.com/joehillen/newspost)
* pan (http://pan.rebelbase.com/)
* sanguinews (https://github.com/tdobrovolskij/sanguinews)
* GoPostStuff (https://github.com/madcowfred/GoPostStuff/)

# What does this program do

It will upload a file or folder to the usenet.
If it is a folder it will search for files inside of the folder.
A NZB file will be generated for later retrieving.

## Supports
* SSL
* Multi connections
* Header Check (including to a different server from the one the article was uploaded)
* NZB Creation

### Functionalities extended by scripts
* NZB completion checker
* RAR creation
* PAR2 creation
* SFV creation
* IRC bot

## What doesn't do
But it may exist a script with these functionalities on the scripts folder.

* Create compressed archive files to upload (rar, zip, 7zip, etc...)
* Create parity files

## Scripts
The folder scripts is a folder where NewsUP functionalities can be extended (please check the configuration section).
Scripts available:

* uploadit.pl - this script will create splitted RARs, PAR2 files, a sfv file and a NZB file.
To run it you just need to:
```
perl uploadit.pl -directory my_folder -a "-com \"extra arguments for newsup.pl\"" -debug
```
This will create a bunch of rars (check the rar configuration) of the dirctory "my_folder". It will also print a bunch of debug messages.
You need to configure the path to the rar, par2 utilities, temporary folder and to newsup.pl on the newsup.conf file.

```
perl uploadit.pl -directory my_folder -a "-com \"extra arguments for newsup.pl\"" -debug -sfv -nfo <path to nfo file>
```
The same as the example above but this time it will create SFV file, and it will upload a nfo file.

```
perl uploadit.pl -directory my_folder -name hash1 -name hash2
```
This will upload the folder my_folder twice. The one upload will be named hash1 the other one will be named hash2.
Please note that only the nzb file from the first upload will be uploaded (if the upload nzb option is set to true). But both are
stored in the save_nzb_path.
This means that all the uploads with the exception of the first are considered backups.



* completion_checker.pl - this script will check the completion of all files in a NZB:
```
perl completion_checker.pl -nzb my_nzb_file.nzb -server my_server.com -port 444 -user newsup -passwd newsup
```
This will check all the segments of the nzb, to see if they are available. Only the -nzb switch is required, all the others
are optional, as they will be extracted from the newsup.conf

## IRC bot
A IRC bot is distributed with NewsUP.
This bot will listen only to public messages on the channel he is connected.

### Bot requirements
* All the modules required for newsup
* Extra perl modules File::Copy::Recursive and File::Path
* NewsUP
* The scripts uploadit and completion_checker and their requirements

### Commands
```
!upload <folder_to_be_uploaded> <upload name 1> <upload name 2> .... <upload name N>
```
This will rar, par2 (it will invoke the uploadit script) the folder <folder_to_be_uploaded> - It will look for that folder inside the
folders defined on the option PATH_TO_UPLOAD_ROOT on the conf file, and after that it will upload N times the <folder_to_be_uploaded>
with name "upload name 1" to "upload name N". This will also create a NZB file on the PATH_TO_SAVE_NZBS
(option on the newsup.conf file) and that NZB will also be uploaded to the same groups as the upload. The rest of the uploads will not
have a nzb file.

```
!check <NZB>
```
This will check the status of the NZB.
The NZB file must be on the location PATH_TO_SAVE_NZBS. This is usually used with the !upload command, when the user wants to check
if the status of a NZB is OK.

Note: The NZB in the command doesn't have the extension.


# Requirements:
* Perl (preferably 5.020 or higher)
* Perl modules: Config::Tiny, IO::Socket::SSL, Inline::C (all other modules should exist on core.)


# Installation
1. Check if you have all the requirements installed.
2. Download the source code (https://github.com/demanuel/NewsUP/archive/master.zip)
3. Copy the sample.conf file ~/.config/newsup.conf and edit the options as appropriate. This step is optional since everything can be done by command line.

If you have any issue installing/running this, not please send me an email so i can try to help you.

# Running
The most basic way to run it (please check the options section) is:
$ perl newsup.pl -file my_file -con 2 -news alt.binaries.test

Everytime the newsup runs, it will create a NZB file for later retrieval of the uploaded files. The NZB filename will consist on the unixepoch of the creation.


# Options

## Config file
**This config file needs to be in ~/.config/ folder**
This file doesn't support all the options of the command line. Everytime an option from the command line conflicts with an option from the config file, the command line option takes precedence.

Example ('#' denotes a comment. This example isn't a working conf. It's only for demonstration purposes):
```
[server]
server= <server address> #switch -server
port= <port> #every port that ain't 563 or 995 it will not use TLS. Switch -port
connections= <connection number> #Switch -connections

[auth]
user= <username> #Switch -username
password= <password> #switch -password

[metadata] #You can put here anything you want to appear on the nzb header. It must have the pattern: word= a big one line sentence. Switch -metadata
client= NewsUP
veryWeirdInfoIWantToPutOnTheNZBMetadata= it's really very weird!

[upload]
uploader= NewsUP <NewsUp@localhost.localdomain> #To identify de uploader and to receive replies. Usualy it's bogus. Switch -uploader
newsgroup= alt.binaries.test, alt.binaries.conspiracy #you can put here as many newsgroups you want. They need to be comma separated.

[headerCheck]
enabled= 1 #0 or 1. If this is enable, after each thread finishes their uploads it will check if the header was uploaded to server through a stat command
sleep= 20 # in Seconds. How much time it should wait before a segment header check
server= server_to_headerCheck #If doesn't exist then it will use the server defined in server section
port= 563 #If doesn't exist then it will use the port defined in server section
user= My_username #If doesn't exist then it will use the user defined in auth section
password= my_password #If doesn't exist then it will use the password defined in auth section
retries = 10 #Number of times it will perform the header check to confirm if the upload was successfull
connections = 4 #Number of connections it will use to connect to the headercheck server.

[extraHeaders]
extra-header= value1 #extra header. It will became X-extra-header
X-extra-header= value3 #extra header. Non valid because there's already one
extra-header2= value2 #second extra header
from= test #non valid. Non valid headers are: from, newsgroups, message-id and subject.


[uploadit]
# Path to upload root folder
upload_root=/home/demanuel/Downloads/Linux
#Reverse name
reverse=0
#reverse filter
files_filter=.*(\.mkv|\.avi|\.mp4|\.ogv|\.flv)
#rename par
rename_par=0
#rename par arguments
rename_par_arguments=par2 c -r0
#Archive the data to upload
archive=1
#Archive arguments
archive_arguments=/usr/bin/rar a -m0 -v50M -ep -ed -r
#for 7z: 7z a -r -mx=0 -v50m
#Archive filter
archive_filter=rar$
#for 7z: \.\d{3}$
#Create SFV
create_sfv=1
#force repair
force_repair=1
#create parity archives
par=1
#Parity archive arguments
par_arguments=par2 c -r15
#Par filter
par_filter=par2$
#save nzb
save_nzb=1
#save nzb
save_nzb_path=/home/demanuel/Uploads
#upload nzb
upload_nzb=1
#force repair - You need to identify a NFO in the command line
force_repair=0
#temp dir
temp_dir=/data/tmp
#uploader
uploader=newsup
#args for newsup
args="-comment 'Uploaded with NewsUP'"

[irc]
# IRC server
server=irc.server.com
# IRC port
port=6667
# IRC Channel (no #)
channel=MyOwnChannel
# IRC Nick
nick=NewsUP
# IRC Nick Password
password=
# IRC Nick Password
channel_password=

```


Check sample newsup.conf for the available options

## Command line options

-username <username>: credential for authentication on the server.

-password <passwd>: credential for authentication on the server.

-server <server>: server where the files will be uploaded to (SSL supported)

-port <port>: The port where you should connect. For non SSL upload use 119, for SSL upload use 563 or 995

-file <file>: the file or folder you want to upload. You can have as many as you want. If the you're uploading a folder then it will find the files inside of the folder

-comment <comment>: Subject will have your comment. You can use two (if you have more, they will be ignored). The subject created will be something like "first comment [1/1] "my file's name" yenc (1/100) [second comment]"

-uploader <uploader id>: the email of the one who is uploading, so it can be later emailed for whoever sees the post. Usually this value is a bogus one.

-newsgroup <groups>: newsgroups. You can have as many as you want. This will crosspost the file.

-nzb <name>: name of the NZB file.

-groups <groups>: alias for newsgroups option

-connections <connections>: number of connections (or threads) for uploading the files (default: 2). Tip: you can use this to throttle your bandwidth usage :-P

-metadata: metadata for the nzb. You can put every text you want! Example:
```bash
-metadata powered=NewsUP -metadata subliminar_message="NewsUp: the best usenet autoposter crossplatform"
```

The NZB file It will have on the ```<head>``` tag the childs:
```html
<metadata type="powered">NewsUP</metadata>
<metadata type="subliminar_message">NewsUp: the best usenet autoposter crossplatform</metadata>
```

-headerCheck: if you want to perform header check

-headerSleep <seconds>: Seconds, how much time it should wait before doing the header check.

-retries <number of retries> : The number of times the header check should be performed until all the segments are reported as ok on the server. This needs the option headerCheck enabled.

-headerCheckRetries <number of retries> : the same option as -retries. Consult above for the description.

-headerCheckConnections <number of connections>: the number of connections it will use to connect to the headercheck server

-uploadsize <size>: size in bytes, of the segment to be uploaded. **This option is not available on the configuration file**

-no_tls: If you want to use a different port from the default 119 without SSL. This will affect both uploading server and headercheck server. **This option is not available on the configuration file**

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
