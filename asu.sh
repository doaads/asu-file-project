#!/bin/sh

# command line arg parsing
if [ $# -lt 2 ]; then
	echo "Usage: $0 <option> <directories to search>"
	echo "Available options:"
	echo "\t -a - modify all files at once"
	echo "\t -e - decide for each file"
	exit 0
fi

# config dir creation
if [ ! -f ".check_files/config.cfg" ]; then
	echo "config.cfg not found"
	echo "do you want to create it? (y/n)"
	stty_state=$(stty -g)  # save stty config
	stty raw -echo; ans=$(head -c 1); stty $stty_state  # get head and restore config
	if [ "$ans" != "${ans#[Yy]}" ]; then
		mkdir .check_files
		printf "DIR=\nACC=\nSPC=\nTMP=" > ./.check_files/config.cfg
		echo ".check_files directory created"
	else
		echo "exitting..."
		exit 1
	fi
fi

# store parameters
OPTION=$1; shift
DIRS=$@

FILES="$(find $DIRS -type f)"

DIR=$(grep "^DIR=" .check_files/config.cfg | awk -F'=' '{ print $2 }')
ACC=$(grep "^ACC=" .check_files/config.cfg | awk -F'=' '{ print $2 }')
SPC=$(grep "^SPC=" .check_files/config.cfg | awk -F'=' '{ print $2 }')
TMP=$(grep "^TMP=" .check_files/config.cfg | awk -F'=' '{ print $2 }')

move_all_to_dir()
{
	for searchdir in $DIRS; do
		if [ $(basename $searchdir) != $DIR ]; then
			mv $searchdir/* ./$DIR
		fi
	done

	echo "files moved"
	exit
}

remove_duplicates()
{
	oldest_flag=$1; shift

	FILES="$(find $DIRS -type f)"

	# calculate md5 checksum for all files
	# print, null terimnate, and process with xargs (-0 flag will ensure correct processing of special chars)
	echo "$FILES" | tr '$\n' '\0' | xargs -0 md5sum > ./.check_files/checksums.txt

	# empty IFS and process every file
	echo "$FILES" | while IFS= read -r file; do

		# check if file exists (could be deleted in previous iterations)
		if [ ! -f "$file" ]; then continue; fi

		echo "--- file: $file ---"

		# calculate md5 checksum and store it
		sum=$(md5sum "$file" | awk '{ print $1 }')

		# get all occurences of the checksum (strip md5 sums with sed, and enclose in quotes for safety)
		matches=$(grep $sum ./.check_files/checksums.txt | sed "s/^.\{34\}//; s/^./'&/; s/$/'/")

		# sort matches via date and remove oldest entry
		matches=$(echo "$matches" | xargs ls -tQ)
		match_num=$(echo "$matches" | wc -l)
		matches=$(echo "$matches" | head -$((match_num - 1)) | tr '\n' ' ')
		echo "remove: $matches"

	done
	exit
}

remove_temporary_empty()
{
	if [ -z "$TMP" ]; then
		echo "error: TMP config not set!"
		exit 1
	fi

	for file in $FILES; do
		if [ $(du $file | awk '{ print $1 }') = 0 ]; then
			echo "$file removed (empty)"
			#rm $file
		elif [ $(echo $(basename $file) | awk -F'.' '{ print $NF }') = $TMP ]; then
			echo "$file removed (temp)"
			#rm $file
		fi
	done
}

chmod_all()
{
	# check if value is valid (octal)
	if [ -z $(echo "$ACC" | grep -o '^[0-7]\{3\}') ]; then
		echo "access values are not in a valid octal format"
		exit 1
	fi

	for file in $@; do
		echo "chmod $ACC $file"
		#chmod $ACC $file
	done

}

remove_older_versions()
{
	for file in $FILES; do
		if [ ! -f $file ]; then continue; fi

		matches=$(echo "$FILES" | grep "$(basename $file)$" | xargs ls -t)
		set $matches; shift

		if [ $# -lt 1 ]; then
			echo "for $file no duplicates were found"
		else 
			echo "for $file: $@ removed";
		fi
	done
	exit
}

if [ $OPTION = "-a" ]; then
	echo ""
	echo "\t1) - move all found files to [DIR]"
	echo "\t2) - remove duplicates (same contents)"  # This should only be in -e
	echo "\t3) - remove duplicates (same contents), preserve oldest"
	echo "\t4) - remove temporary .[TMP] and empty files"
	echo "\t5) - remove duplicates (same name), preserve newest"
	echo "\t6) - chmod all files to [ACC] (octal)"
	echo "\t7) - substitute special characters [SPC]"
	echo "\t8) - exit"
	echo "Pick operation: "
	read op

	case $op in
		"1") move_to_dir;;
		"2") remove_duplicates 0;;
		"3") remove_duplicates 1;;
		"4") remove_temporary_empty;;
		"5") remove_older_versions;;
		"6") chmod_all $FILES;;
		"8") exit;;
		*) echo "invalid option"; exit;;
	esac
fi
