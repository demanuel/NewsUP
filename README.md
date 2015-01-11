NewsUP
======

NewsUP a binary usenet uploader/poster. Backup your personal files to the usenet!
It will run on any platform that supports perl that matches the requirements

# Intro

This program will upload binary files to the usenet and generate a NZB file. It supports SSL, multiple connections and parity files.
This program is licensed with GPLv3.


## note
This is a completely rewrite of the previous version and some options changed... but now it supports SSL! :-D

## Alternatives
* newsmangler (https://github.com/madcowfred/newsmangler)
* newspost (https://github.com/joehillen/newspost)
* pan (http://pan.rebelbase.com/)
* sanguinews (https://github.com/tdobrovolskij/sanguinews)


# What does this program do

It will upload a file or folder to the usenet. 
If it is a folder it will create a 7zip archive (it can consist of multiple 10MiB file (passworded or not - please check the options)).
The compressed format will be 7z (although it won't really compress. The level of compression is 0). It can also create parity files and perform header checking (sometimes a segment upload will return success, but in reality the upload fail. This feature tries to prevent that).
A NZB file will be generated for later retrieving.

## What doesn't do

* Create compressed archive files to upload [1]
* Create rars [1]
* Create zips [1]


### Notes
1- If you are uploading a folder, or files bigger than 10MiB. it will create a 7zip file containing the folder and all the files inside. This 7zip will be split in 10 meg volumes. The 7zip will not have compression.

## Decisions and questions
*1- Why it was decided to compress folders?*

I decided that because, to keep the same file structure. Example if you upload a folder
```
my_folder
|- file1
|- file2
```

When you download you want the same filestructure. Unfortunately the yenc mechanism, doesn't allow that. So you would end up with two files (file1 and file2), but no folder.


*2- Why do you split the files in 10 MiB?*

The size 10 MiB, was decided so the download can be supported on more older clients (when decoding you need to load it to memory), and also as a treshold between speed and number of threads, discussed earlier. This size will increase to 50 megs if you're trying to upload more than 10GiB, 120MiB if more than 50GiB, 350MiB if you're trying to upload more than 120GiB.
The maximum file size allowed is 350 GiB.


* 3- Why 7zip and not rar?*

I have only 7zip installed and not rar on my system (I tend to use what i have available on my system - rar is shareware and 7zip is opensource). Please note that the archiving is done without any compression.


#Requirements:
* Perl (preferably 5.018 or higher)
* Perl modules: Config::Tiny, IO::Socket::SSL, String::CRC32, (all other modules should exist on core.)
* 7Zip
* par2repair
* Free disk space (Example: If you're uploading a 300MiB file, you'll need at least 301MiB free space minimum)

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

[parity]
enabled= 0 #If you want to enable parity creation. Switch -par
redundancy= 10 #percentage of redundancy for parity files. Switch -par2red

[generic]
tmp = /tmp #folder to where the compression and/or par files should go. All the files are removed after upload. Switch -tmp
randomize = 0 #0 or 1. To disable or enable the name change. If this is done, the person who download the files will required the parity files
headerCheck= 1 #0 or 1. If this is enable, after each thread finishes their uploads it will check if the header was uploaded to server through a stat command
```


Check sample newsup.conf for the available options

## Command line options

-username: credential for authentication on the server.

-password: credential for authentication on the server.

-server: server where the files will be uploaded to (SSL supported)

-port: port. For non SSL upload use 119, for SSL upload use 563 or 995

-file: the file or folder you want to upload. You can have as many as you want. If the you're uploading a folder then it will compress it and split it in files of 10Megs for uploading. These temp files are then removed. 

-comment: comment. Subject will have your comment. You can use two. The subject created will be something like "[first comment] my file's name [second comment]"

-uploader: the email of the one who is uploading, so it can be later emailed for whoever sees the post. Usually this value is a bogus one.

-newsgroup: newsgroups. You can have as many as you want. This will crosspost the file.

-tmp: folder. Full path to were the temporary files (the 7zip and par2) will be written. If the path doesn't exist it will be the current folder. All the files are removed after upload.

-randomize: If you want to randomly toggle the names of some files. This will require the par2 files to correct the name

-par2: enable parity files creation.

-par2red: percentage (withouth the % sign). This option represents the redundancy of the parity files.

-name: name of the compressed file. The name of the splitted file.

-cpass: password of the 7zip file.

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
$ perl newsup.pl -group alt.binaries.test -f <bin_file> -par2 -name <some_name>
```
If <bin_file> is bigger than 10 Megs (or it is a folder), it will create a 7zip file with name <some_name>.7z
If <bin_file> is smaller than 10 Megs and is not a folder a 7zip will NOT be created.
Parity volumes will then be created, and uploaded. A NZB file will then be created.


```bash
$ perl newsup.pl -group alt.binaries.test -f <bin_file> -par2 -name <some_name> -cpass my_passwd
```
It works exactly the same way as the previous example but if a 7zip file is created it will have the password 'my_passwd'


```bash
$ perl newsup.pl -group alt.binaries.test -f <bin_file> -par2
```
The same example as the first, but instead it will create a 7zip file with name newsup.7z



# END

Enjoy it. Email me at demanuel@ymail.com if you have any request, info or question. You're also free to ping me if you just use it.

Best regards!
