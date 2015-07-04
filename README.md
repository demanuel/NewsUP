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


# What does this program do

It will upload a file or folder to the usenet. 
If it is a folder it will search for files inside of the folder.
A NZB file will be generated for later retrieving.

## Supports
* SSL
* Multi connections
* Header Check (including to a different server from the one the article where upload)
* NZB Creation



## What doesn't do 
But it may exist a script with these functionalities on the scripts folder.

* Create compressed archive files to upload (rar, zip, 7zip, etc...)
* Create parity files


## Scripts
The folder scripts is a folder where NewsUP functionalities can be extended (please check the configuration section).
Scripts available:

*- uploadit.pl - this script will create splitted RARs, PAR2 files, a sfv file and a NZB file.
To run it you just need to:
```
perl uploadit.pl -directory my_folder -a "-com \"extra arguments for newsup.pl\"" -debug
```
This will create a bunch of rars (check the rar configuration) of the dirctory "my_folder". It will also print a bunch of debug messages. 

*- newsupseq.sh - this script will upload sequentially the files, and it will merge the nzb files into one. 


#Requirements:
* Perl (preferably 5.018 or higher)
* Perl modules: Config::Tiny, IO::Socket::SSL, String::CRC32, (all other modules should exist on core.)

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
username= My_username #If doesn't exist then it will use the user defined in auth section
password= my_password #If doesn't exist then it will use the password defined in auth section

[generic]
monitoringPort = 8675


[script_vars]
############################
#
# This section is variables only used by the scripts on the script folder
# The newsup.pl script doesn't use any of the variables here
############################
# Path to newsup script. Please make sure that the script is executable. Check it's permissions
PATH_TO_UPLOADER=../newsup.pl
# Path to RAR executable
PATH_TO_RAR=/usr/bin/rar
# RAR volume size in megabytes 
RAR_VOLUME_SIZE=50
# RAR compression level
RAR_COMPRESSION=0
# RAR Password
RAR_PASSWORD=newsup
# Path to PAR2 executable
PATH_TO_PAR2=/usr/bin/par2
# Folder to where the scripts files should be written
# It's obigatory to terminate on the separator folder char.
TEMP_DIR=/tmp/
# Par recovery %
PAR_REDUNDANCY=10
# Randomize Names
# The names are toggled. Imagine 3 files: a, b and c. The file a will keep the name. The file b  will exchange name with file c. This is done randomly.
RANDOMIZE_NAMES=1




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

-uploadsize <size>: size in KB, of the segment to be uploaded. **This option is not available on the configuration file**

# Examples

```bash
$ perl newsup.pl -group alt.binaries.test -f <bin_file> -nzb <some_name>
```
If <bin_file> is a folder, it will transverse the folder searching for files.
The files will be uploaded. A NZB file with <some_name> will then be created.


# Acknowledgements
* Cavalia88 <cavalier2888 AT outlook DOT com> for his suggesions and his testing on windows platform.



# END

Enjoy it. Email me at demanuel@ymail.com if you have any request, info or question. You're also free to ping me if you just use it.

Best regards!
