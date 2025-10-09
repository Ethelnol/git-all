#!/bin/bash

declare forcebuild=0
declare quiet=0
declare file=".source.txt"

for i in "$@"; do
	[[ "$i" == "--force-build" ]] && forcebuild=1 && file=".build.txt" && continue
	[[ "$i" == "-q" || "$i" == "--quiet" ]] && quiet=1 && continue
	[[ "$i" != "-h" && "$i" != "--help" ]] && 1>&2 echo "unknown option - \"$i\"" && exit 1

	echo    "$(basename "$0"):"
	echo -e "Automatic update and build script for git\n"
	echo    "Update:"
	echo    "  File must be a single line."
	echo    "  Address must be stored in \".source.txt\" in project root."
	echo -e "  Any relevant options such as '--recurse-submodules' may also be listed.\n"
	echo    "Build:"
	echo    "  Sources \".build.txt\" in project root after a successful update if the file is present."
	echo -e "  Instructions must be valid shell code.\n"
	echo    "Options:"
	echo    "     -h, --help:  Display this message"
	echo    "  --force-build:  Don't fetch updates and build all repos with .build.txt file"
	echo    "    -q, --quiet:  Disable terminal output"
	exit 1
done

#single ping occasionally eroniously errors so run a double ping to be sure
if ! ping "github.com" -c 1 &>/dev/null && ! ping "github.com" -c 2 &>/dev/null; then
        echo "Unable to connect to GitHub"
        exit 1
fi

#if [[ "$(dirname "$0")" != "." ]]; then
#	1>&2 echo "Must be in the same directory as git-all.sh"
#	exit 1
#fi

declare gitDir="$(dirname "$0")"
declare curDir="$PWD"
declare str=""
declare end=""
declare l=0
declare largestLen=0
declare project=""
#declare logtime="$(date '+%Y%m%d')"

for i in "$gitDir/"*/$file; do
	[[ "$i" == "$gitDir/*/$file" ]] && continue;

	declare tmp
	tmp=$(echo -n "$(basename "$(dirname "$i")")" | wc -c)
	(( tmp > largestLen )) && largestLen=$tmp
done
largestLen=$(( largestLen + 1 ))

clean(){
	declare x=$1
	#eval "printf -- '\b %.0s' {0..$1}"
	while (( x > 0 )); do
		echo -ne "\b \b"
		x=$(( x - 1 ))
	done
	return 0
}

pull(){
	str="$(eval git pull "$(cat ./.source.txt)" 2>&1)"
	end="$(echo "$str" | tail -1)"
	l=$(echo "$str" | wc -l)
}

#main process here

(( ! quiet )) && echo -n "  repository:" &&\
	eval "printf -- ' %.0s' {10..$largestLen}" &&\
	echo -e "status\n"
for i in "$gitDir"/*/.source.txt; do
	project="$(dirname "$i")"
        [[ "$i" == "$gitDir/*/.source.txt" || ! -d "$project" ]] && continue
	cd "$project"

	if (( ! quiet )); then
		echo -n "  $(basename "$project"):"
		eval "printf -- ' %.0s' {$(echo -n "$(basename "$project")" | wc -c)..$largestLen}"
	fi

	if (( ! forcebuild )); then
		(( ! quiet )) && echo -n "fetching update"

		pull

		(( ! quiet )) && clean 15

		if [[ "$end" == "Already up to date." ]]; then
			(( ! quiet )) && echo "up to date"
			cd "$curDir"
			continue
		fi

		if [[ "$end" == Aborting || "$end" == Updating* ]]; then
			(( ! quiet )) && echo -n "removing merge files"
			for k in $(echo "$str" | tail -$(( l - 3 )) | head -$(( l - 6 ))); do
				[[ -f "$k" ]] && rm "$k"
			done

			pull

			(( ! quiet )) && clean 20
			if [[ "$end" == Aborting || "$end" == Updating* ]]; then
				(( ! quiet )) && 1>&2 echo "error, cannot remove merge files"
				cd "$curDir"
				continue
			fi
		fi
	fi

	if [[ ! -f .build.txt ]]; then
		(( ! quiet )) && echo "update complete"
		cd "$curDir"
		continue
	fi

	(( ! quiet )) && echo -n "building"

	[[ ! -f .build.log ]] && touch .build.log && chmod u+w .build.log
#	. .build.txt &> ".build.$(date '+%Y%m%d%H%M').log"
#	. .build.txt &> ".build.$logtime.log"
	. .build.txt &> .build.log
	declare failed=$?

	if (( ! quiet )); then
		clean 3
		(( ! failed )) && echo " complete" || 1>&2 echo " failed"
	fi

	cd "$curDir"
done
