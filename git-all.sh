#!/bin/bash

declare version='0.2'

declare no_update=false
declare no_build=false
declare quiet=false

declare str=""
declare end=""
declare -i l=0

declare gitDir="$(dirname "$0")"
declare curDir="$PWD"
declare -i largestLen=0
declare project=""
declare file_name=".source.txt"

declare color_support=false
declare -A color=([none]="\e[0;0m" [red]="\e[0;91m" [green]="\e[0;92m" [blue]="\e[0;96m")

declare getoptsArgs="hvbuqc:"
declare -A shortArgs=(\
	[no-update]=b [force-build]=b \
	[no-build]=u [update-only]=u \
	[quiet]=q [color]=c \
	[version]=v [help]=h\
)

#output "\b\ \b" <1> times if <quiet>.  Returns 0 if output. Returns 1 if <quiet>
back(){
	$quiet && return 1

	eval "printf -- '\b \b%.0s' {1..$1}"
	return 0
}

#output <1> with color <2> if <2> is set.  Note: does not output newlines
output(){
	$quiet && return 1

	if [[ -n "$2" ]]
		then printf -- "${color["$2"]}""$1"
		else printf -- "${color[none]}""$1"
	fi
	return 0
}

#pull from .source.txt and update <str>, <end>, and <l>
pull(){
	str="$(eval git pull "$(cat ./.source.txt)" 2>&1)"
	end="$(echo "$str" | tail -1)"
	l=$(echo "$str" | wc -l)
}

#uses <str> and removes all incompatible merge files listed in <str>
clean(){
	while read -r i; do
		if [[ -f "$i" ]]; then
			rm --force "$i"
		fi
	done <<< \
		"$(echo "$str" | tail -$(( l - 3 )) | head -$(( l - 6 )))"
}

#fetch updates. returns 0 if updates successfully. returns 1 if already up to date or .source.txt doesn't exist. returns 2 couldn't remove merge files
updateRepo(){
	[[ ! -f .source.txt ]] && return 1

	output "fetching update"

	pull

	back 15

	if [[ "$end" == "Already up to date." ]]; then
		return 1
	fi

	#remove conflicting files
	if [[ "$end" == Aborting || "$end" == Updating* ]]; then
		output "removing merge files" "blue"

		clean

		pull

		back 20
		if [[ "$end" == Aborting || "$end" == Updating* ]]; then
			output "error, cannot remove merge files\n" "red"
			return 2
		fi
	fi

	return 0
}

#checks if git-all has an update before updating other repos. returns 0 if updated. returns 1 if up to date or .source.txt doesn't exist. otherwise, returns 2.
updateGitAll(){
	if [[ ! -d "$gitDir/git-all" || ! -f "$gitDir/git-all/.source.txt" ]]; then
		return 1
	fi

	cd "$gitDir/git-all"

	updateRepo &>/dev/null

	#$? is 0 if updated
	return $?
}

#builds git repo if .build.txt is present. returns 0 if builds successfully. returns 1 if <no_build> or .build.txt doesn't exist. returns 2 if build fails
buildRepo(){
	#skip build if no .build.txt or --update-only or --no-build is passed
	if [[ ! -f .build.txt ]] || $no_build; then
		if [[ -f .source.txt ]]; then
			output "update complete\n" "green"
		fi
		return 1
	fi

	output "building" "blue"

	built_successful=false
	source .build.txt &> .build.log && built_successful=true

	back 8
	if $build_successful; then
		output "build complete\n" "green"
		return 0
	else
		output "build failed" "red"
		return 2
	fi
}

helpText(){
	#A-array that holds strings of arguments where the value of <options>[<key>] is a list of options equivalent to "-<key>"
	declare -A options
	#A-array of bools where true means <key> requires an input
	declare -A needsFlag
	#A-array of descriptions of arguments equivalent to "-<key>"
	declare -A description=(
	    [h]="Display this message"
	    [b]="Don't fetch updates and build all repos with .build.txt file"
	    [u]="Don't build after fetching updates"
	    [q]="Disable terminal output"
	    [v]="Output version"
	    [c]="Set color status [auto, on, off]"
	)

	#length of longest string in <options>
	declare -i longest=0
	#list of all unique keys in alphabetical order seperated by '\n'
	declare alphaOrder=""

	#initialise options and needsFlag
	for i in $(seq 0 $(( ${#getoptsArgs} - 1 )) ); do
		declare char="${getoptsArgs:$i:1}"

		if [[ "$char" == ":" ]]; then
			needsFlag[${getoptsArgs:$(( i - 1 )):1}]=true
			continue
		fi

		#options+=([$char]="-$char")
		needsFlag+=([$char]=false)
	done

	#add "FLAG" to <options> that require input and add each key to <alphaOrder>
	for i in "${shortArgs[@]}"; do
		alphaOrder+="$i\n"
	done

	#put string in alphabetical order
	alphaOrder="$(printf -- "$alphaOrder" | sort --unique)"

	#set <options> values
	for i in $(printf -- "$alphaOrder") "${!shortArgs[@]}"; do
		key="${shortArgs["$i"]}"

		if [[ -n "$key" ]]; then
			options[$key]+=", --$i"
		else
			key="$i"
			options[$key]+="-$i"
		fi

		${needsFlag[$key]} && options[$key]+=" FLAG"
	done

	#set length of <longest>
	for i in "${options[@]}"; do
		(( ${#i} > longest )) && longest=${#i}
	done

	longest=$(( longest + 0 ))

	cat <<-'_EOF'
		git-all.sh:
		  Automatic update and build script for git.

		Update:
		  Address must be stored in ".source.txt" in project root.
		  File must be a single line.
		  Any relevant options such as '--recurse-submodules' may also be listed.

		Build:
		  Sources ".build.txt" in project root after a successful update if the file is present.
		  Instructions must be valid shell code.

		Options:
	_EOF

	for i in $(printf -- "$alphaOrder"); do
		printf -- "  ${options[$i]}"
		eval "printf -- ' %.0s' {${#options[$i]}..$longest}"
		printf -- " :  ${description[$i]}\n"
	done
}

#output "git-all.sh: $1\n".  Output is red if color is supported
fatal_error(){
	$color_support && printf -- "${color[red]}"
	printf -- "git-all.sh: $1\n"
	exit 1
}

#getopts implementation
options(){
	#replace long arguments with short args
	for arg in "$@"; do
		shift
		case "$arg" in
			--*)
				#modifies variables such that the original <arg> can be recreated with "--$arg" or "--$arg=$opt" if a '=' is present
				arg="$(printf -- "$arg" | cut -d '-' -f 3-)"
				opt="$(printf -- "$arg" | cut -d '=' -f 2-)"
				arg="$(printf -- "$arg" | cut -d '=' -f 1)"
				newArg="${shortArgs["$arg"]}"

				[[ -z "$newArg" ]] && fatal_error "unknown argument -- --$arg"

				#set -- "$@" "-$newArg"
				if [[ "$arg" == "$opt" ]]
					then set -- "$@" "-$newArg"
					else set -- "$@" "-$newArg" "$opt"
				fi
				;;
			*)
				set -- "$@" "$arg"
				;;
		esac
	done

	#set variables from args
	while getopts ":$getoptsArgs" arg; do
		case "$arg" in
			b)
				no_update=true
				;;
			u)
				no_build=true
				;;
			q)
				quiet=true
				;;
			c)
				case "$OPTARG" in
					on)
						color_support=true
						;;
					off)
						color_support=false
						;;
					auto)
						if [[ "$TERM" == "xterm-256color" ]]
							then color_support=true
							else color_support=false
						fi
						;;
					*)
						fatal_error "-c, invalid value -- $OPTARG"
						;;
				esac
				;;
			h)
				helpText
				exit 0
				;;
			v)
				output "git-all.sh $version\n"
				exit 0
				;;
			':')
				fatal_error "-$OPTARG missing argument"
				;;
			*)
				fatal_error "unknown argument -- $arg"
				;;
		esac
	done

	if ! $color_support; then
		for i in "${!color[@]}"; do
			color["$i"]=""
		done
	fi
}

options "--color=auto" "$@"

#check for internet connection
if ! $no_update; then
	#single ping occasionally erroneously errors so run a double ping to be sure
	if ! ping "www.google.com" -c 1 &>/dev/null && ! ping "www.google.com" -c 2 &>/dev/null; then
		fatal_error "Unable to connect to the internet"
	fi
fi

#get length of largest string for formatting and output format
if ! $quiet; then
	for i in "$gitDir"/*/"$file_name"; do
		if [[ "$i" == "$gitDir/*/$file_name" ]]; then
			continue
		fi

		tmp=$(echo -n "$i" | rev | cut -d '/' -f 2 | rev | wc -c)
		(( tmp > largestLen )) && largestLen=$tmp
	done

	output "  repository: $(eval "printf -- ' %.0s' {10..$largestLen}")status\n\n"
fi

#update and build process
for i in "$gitDir"/*/"$file_name"; do
	if [[ "$i" == "$gitDir/*/$file_name" ]]; then
		continue
	fi

	project="$(echo -n "$i" | rev | cut -d '/' -f 2 | rev)"
	cd "$gitDir/$project"

	output "  $project: $(eval "printf -- ' %.0s' {$(echo -n "$project" | wc -c)..$largestLen}")"

	updated=false
	built=false

	if ! $no_update; then
		updateRepo
		ret=$?
		(( ret == 2 )) && continue
		(( ret == 0 )) && updated=true
	fi

	if ! $no_build && ($updated || $no_update); then
		buildRepo
		ret=$?
		(( ret == 2 )) && continue
		(( ret == 0 )) && built=true
	fi

	! ($updated || $built) && output "up to date\n" "green"

	cd "$curDir"
done

