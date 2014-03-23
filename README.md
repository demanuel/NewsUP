NewsUP
======

NewsUP a binary usenet uploader/poster. Backup your personal files to the usenet!

# Intro

This program will upload binary files to the usenet and generate a NZB file. It supports SSL and multiple connections.
This program is licensed with GPLv3.


## note
This is a completely rewrite of the previous version (some options changed) and the creation of the parity files was dropped amongst others... but now it supports SSL! :-D

## Alternatives
* newsmangler (https://github.com/madcowfred/newsmangler)
* newspost (https://github.com/joehillen/newspost)
* pan (http://pan.rebelbase.com/)
* sanguinews (https://github.com/tdobrovolskij/sanguinews)


# What does this program do

It will upload a file or folder to the usenet. 
If it is a folder it will create a 7zip archive (it can consist of multiple 10Megs file with *no password*).
The compressed format will be 7z (although it won't really compress. The level of compression is 0).
A NZB file will be generated for later retrieving.

## What doesn't do

* Create archive passworded files 
* Create compressed archive files to upload
* Create rars
* Create zips
* Create parity archives



#Requirements:
* Perl (5.018 -> i can change it to a version >= 5.10)
* Perl modules: Config::Tiny, IO::Socket::SSL, String::CRC32, XML::LibXML (all other modules should exist on core.)

# Installation
1. Check if you have all the requirements installed.
2. Download the source code (https://github.com/demanuel/NewsUP/archive/master.zip)
3. Copy the sample.conf file ~/.config/newsup.conf and edit the options as appropriate. This step is optional since everything can be done by command line.

# Running
The most basic way to run it (please check the options section) is:
$ perl newsup.pl -file my_file -con 2 -news alt.binaries.test

Everytime the newsup runs, it will create a NZB file for later retrieval of the uploaded files. The filename will consist on the unixepoch of the creation.


## Options

## Config file
This file doesn't support all the options of the command line. Everytime an option from the command line and an option from the config file, the command line takes precedence.
Check sample newsup.conf for the available options

### Command line options

-username: credential for authentication on the server.

-password: credential for authentication on the server.

-server: server where the files will be uploaded to (SSL supported)

-port: port. For non SSL upload use 119, for SSL upload use 563 or 995

-file: the file or folder you want to upload. You can have as many as you want. If the you're uploading a folder then it will compress it and split it in files of 10Megs for uploading. These temp files are then removed. 

-comment: comment. Subject will have your comment. You can use two. The subject created will be something like "[first comment] my file's name [second comment]"

-uploader: the email of the one who is uploading, so it can be later emailed for whoever sees the post. Usually this value is a bogus one.

-newsgroup: newsgroups. You can have as many as you want. This will crosspost the file.

-groups: alias for newsgroups option

-connections: number of connections (or threads) for uploading the files (default: 2). Tip: you can use this to throttle your bandwidth usage :-P

-metadata: metadata for the nzb. You can put every text you want! Example: 
```bash
-metadata powered=NewsUP -metadata subliminar_message="NewsUp: the best usenet autoposter crossplatform"
```

The NZB file It will have on the ```<head>``` tag the childs:
```html 
<metadata type="powered">NewsUP</metadata>
<metadata type="subliminar_message">NewsUp: the best usenet autoposter crossplatform</metadata>
```
# END

Enjoy it. Email me at demanuel@ymail.com if you have any request, info or question. You're also free to ping me if you just use it.

Best regards!
