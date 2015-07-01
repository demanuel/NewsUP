#!/bin/bash
#Program this to traverse folders and subfolders to infinite depth
#
# Author: Shillshocked
# Changed: David Santiago


totalfiles=$(find . -type f | wc -l)

for dir in "$PWD"/*
do
	cd "$dir"
	counter=1
	totalfiles=$(ls -1 | wc -l)
	MYBASENAME=$(basename "$dir")
	
	for file in "$dir"/*
	do
	  perl ../newsup.pl -f "$file" -comment "$1 - $MYBASENAME [$((counter++))/$totalfiles]"
	done
    xml_grep --pretty_print indented --wrap nzb --cond file *nzb > combine.xml
    rm -f *nzb
    mv combine.xml "$MYBASENAME.nzb"
done
