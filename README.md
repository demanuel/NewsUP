NewsUP
======

NewsUP a binary usenet uploader/poster. Backup your personal files to the usenet!
It will run on any platform that supports perl that matches the requirements

# Intro

This program will upload binary files to the usenet and generate a NZB file. It supports SSL, multiple connections.
This program is licensed with GPLv3.


## note
As i realized that most users already have scripts to create rars/7z and parity files i dropped the options to create 7zip and parity files. But if you want them, just send me an email i can restore them.

I changed the code to use processes instead of threads to improve performance.


## Alternatives
* newsmangler (https://github.com/madcowfred/newsmangler)
* newspost (https://github.com/joehillen/newspost)
* pan (http://pan.rebelbase.com/)
* sanguinews (https://github.com/tdobrovolskij/sanguinews)


# What does this program do

It will upload a file or folder to the usenet. 
If it is a folder it will search for files inside of the folder.
A NZB file will be generated for later retrieving.

## What doesn't do

* Create compressed archive files to upload (rar, zip, 7zip, etc...)
* Create parity files [1]


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

[generic]
headerCheck= 1 #0 or 1. If this is enable, after each thread finishes their uploads it will check if the header was uploaded to server through a stat command
```


Check sample newsup.conf for the available options

## Command line options

-username: credential for authentication on the server.

-password: credential for authentication on the server.

-server: server where the files will be uploaded to (SSL supported)

-port: port. For non SSL upload use 119, for SSL upload use 563 or 995

-file: the file or folder you want to upload. You can have as many as you want. If the you're uploading a folder then it will find the files inside of the folder

-comment: comment. Subject will have your comment. You can use two. The subject created will be something like "[first comment] my file's name [second comment]"

-uploader: the email of the one who is uploading, so it can be later emailed for whoever sees the post. Usually this value is a bogus one.

-newsgroup: newsgroups. You can have as many as you want. This will crosspost the file.

-nzb: name of the NZB file.

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

# Examples

```bash
$ perl newsup.pl -group alt.binaries.test -f <bin_file> -nzb <some_name>
```
If <bin_file> is a folder, it will transverse the folder searching for files.
The files will be uploaded. A NZB file with <some_name> will then be created.



# END

Enjoy it. Email me at demanuel@ymail.com if you have any request, info or question. You're also free to ping me if you just use it.

Best regards!
