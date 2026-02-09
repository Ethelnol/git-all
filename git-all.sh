#!/bin/bash

declare version='0.1'

declare force_build=false
declare no_build=false
declare quiet=false

declare str=""
declare end=""
declare -i l=0

#output "\b\ \b" $1 times
clean(){
	eval "printf -- '\b \b%.0s' {1..$1}"
	return 0
}

#pull from .source.txt and update str, end, and l
pull(){
	str="$(eval git pull "$(cat ./.source.txt)" 2>&1)"
	end="$(echo "$str" | tail -1)"
	l=$(echo "$str" | wc -l)
}

#fetch updates. returns 0 if updates successfully. returns 1 if already up to date, couldn't remove merge files, or .source.txt doesn't exist
updateRepo(){
	[[ ! -f .source.txt ]] && return 1

	! $quiet && echo -n "fetching update"

	pull

	! $quiet && clean 15

	if [[ "$end" == "Already up to date." ]]; then
		return 1
	fi

	#remove conflicting files
	if [[ "$end" == Aborting || "$end" == Updating* ]]; then
		! $quiet && echo -n "removing merge files"
		for k in $(echo "$str" | tail -$(( l - 3 )) | head -$(( l - 6 ))); do
			[[ -f "$k" ]] && rm --force "$k"
		done

		pull

		! $quiet && clean 20
		if [[ "$end" == Aborting || "$end" == Updating* ]]; then
			! $quiet && echo "error, cannot remove merge files"
			return 1
		fi
	fi

	return 0
}

#builds git repo if .build.txt is present. returns 0 if builds successfully. returns 1 if $no_build, no .build.txt
buildRepo(){
	#skip build if no .build.txt or --update-only or --no-build is passed
	if [[ ! -f .build.txt ]]; then
		if [[ -f .source.txt ]] && ! $quiet; then
			echo "update complete"
		fi
		return 1
	fi

	! $quiet && echo -n "building"

	built_successful=false
	source .build.txt &> .build.log && built_successful=true

	if ! $quiet; then
		clean 3
		$built_successful && echo " complete" || echo " failed"
	fi

	return 0
}

helpText(){
	echo    "git-all.sh:"
	echo -e "Automatic update and build script for git.\n"
	echo    "Update:"
	echo    "  Address must be stored in \".source.txt\" in project root."
	echo    "  File must be a single line."
	echo -e "  Any relevant options such as '--recurse-submodules' may also be listed.\n"
	echo    "Build:"
	echo    "  Sources \".build.txt\" in project root after a successful update if the file is present."
	echo -e "  Instructions must be valid shell code.\n"
	echo    "Options:"
	echo    "                  -h, --help:  Display this message"
	echo    "   --update-only, --no-build:  Don't build after fetching updates"
	echo    "  --no-update, --force-build:  Don't fetch updates and build all repos with .build.txt file"
	echo    "                 -q, --quiet:  Disable terminal output"
	echo    "                   --version:  Output version"
}

for i in "$@"; do
	if [[ "$i" == "--no-update" || "$i" == "--force-build" ]]; then
		force_build=true
	elif [[ "$i" == "--update-only" || "$i" == "--no-build" ]]; then
		build=true
	elif [[ "$i" == "-q" || "$i" == "--quiet" ]]; then
		quiet=true
	elif [[ "$i" == "-h" || "$i" == "--help" ]]; then
		helpText
		exit 0
	elif [[ "$i" == "--version" ]]; then
		echo "git-all.sh $version"
		exit 0
	else
		1>&2 echo "Unknown option - \"$i\""
		exit 1
	fi
done

if $no_build && $force_build; then
	1>&2 echo "--no-update or --force-build cannot be passed with --update-only or --no-build."
	exit 1
fi

#single ping occasionally eroniously errors so run a double ping to be sure
if ! $force_build && ! ping "www.google.com" -c 1 &>/dev/null && ! ping "www.google.com" -c 2 &>/dev/null; then
        echo "Unable to connect to the internet"
        exit 1
fi

declare gitDir="$(dirname "$0")"
declare curDir="$PWD"
declare -i largestLen=0
declare project=""
declare file_name=".$($force_build && printf 'build' || printf 'source').txt"

#get length of largest string for formatting
for i in "$gitDir/"*"/$file_name"; do
	[[ "$i" == "$gitDir/*/$file_name" ]] && continue;

	tmp=$(echo -n "$(basename "$(dirname "$i")")" | wc -c)
	(( tmp > largestLen )) && largestLen=$tmp
done

#output text format
if ! $quiet; then
	echo -n "  repository: "
	eval "printf -- ' %.0s' {10..$largestLen}"
	echo -e "status\n"
fi

#update and build process
for i in "$gitDir/"*"/$file_name"; do
	if [[ "$i" == "$gitDir/*/$file_name" ]] || [[ "$i" != *.source.txt && "$i" != *.build.txt ]]; then
		continue
	fi

	project="$(dirname "$i")"
	cd "$project"

	if ! $quiet; then
		echo -n "  $(basename "$project"): "
		eval "printf -- ' %.0s' {$(echo -n "$(basename "$project")" | wc -c)..$largestLen}"
	fi

	updated=false
	built=false

	if ! $force_build; then
		updateRepo && updated=true
	fi

	if (! $no_build && $updated) || $force_build; then
		buildRepo && built=true
	fi


	! $updated && ! $built && echo "up to date"

	cd "$curDir"
done

