#!/bin/bash 

# AUTHOR: Joseph Daniel 7/02/2024
# A bash script for find duplicate

usage(){
     cat << _EOF
 $(basename "$0") [OPTIONS..] [DIR...]
 Find duplicates between files in a directory. If delete option is not selected, print the duplicate only
 OPTIONS
     -d: delete duplicate immediately, accept 0, 1 or 2 to either delete first duplicate found or second duplicate found. If 0 is selected confirmation is asked on each file
     -s follow symbollic link
     -a search hidden files
     -H consider hardlinks as duplicate
     -e inclue empty files to search
_EOF
 }

boldred=$(tput bold; tput setaf 1)
tput_reset=$(tput sgr0)

DIR_LIST=(  )
# Error code
E_ACCESSERROR=99
E_HASHNOTFOUND=100
E_INVALID_OPTION=127
HASH_COMMAND=
RM_HARDLINKS=
EMPTY="! -empty" 
FOLLOW_SYMLINK=
HIDDEN=" -name \.\* -prune -o "
HASHLEN=
DUPLICATES= #Flag to track duplicates
# tmp_file="tmp/dedup_$$_$(date +%s)"
export LC_CTYPE=C 
export LC_COLLATE=C 


find_duplicate_size(){
    local current_size=0
    local current_file=
    local dup_count=0;

    while IFS= read -r; do
        size="${REPLY%% *}"
        file="${REPLY#* }"
        if [ "$size" -eq "$current_size" ]; then
            (( dup_count++ ))

            echo "$current_file"
            current_size="$size"
            current_file="$file"
        else
            [[ $dup_count -gt 0 ]] && echo "$current_file"
            dup_count=0
            current_file="$file"
            current_size="$size"
        fi
    done < <(eval "find $FOLLOW_SYMLINK '${DIR_LIST[@]}' $HIDDEN  -type f "$EMPTY" -printf '%s %p\n'" | sort -n -k 1 -t' ' 2>/dev/null)
     [[ "$dup_count" -gt 0 ]] && echo "$current_file"
}


get_hash(){
    { find_duplicate_size& echo gathering files... 1>&2; } | while IFS= read -r file; do
        hash="$($HASH_COMMAND "$file")"
        hash="${hash%% *}"
        [[ "$?" -ne 0 ]] && { echo "${boldred}Unable to calculate hash${tput_reset}" 1>&2; continue; }
        echo "$hash:$file"
    done
}


get_duplicate_hash(){
    local dup_count=0 
    local prev=
    get_hash | sort -k1 -t':' | {
        while IFS= read -r; do

            local prev_hash="${prev%%:*}"
            local cur_hash="${REPLY%%:*}"
            local cur_file="${REPLY#*:}"
            local prev_file="${prev#*:}"

            if [[ "$prev_hash" == "$cur_hash" ]] &&
            cmp -s "$cur_file" "$prev_file"; then
                if [[ "$RM_HARDLINKS" ]]; then
                    dup_count=1
                    echo "$prev"
                    prev="$REPLY"
                else
                    if [[ ! "$cur_file" -ef "$prev_file" ]]; then
                        dup_count=1
                        echo "$prev"
                        prev="$REPLY"
                        continue
                    fi
                    [[ "$dup_count" -gt 0 ]] && echo "$prev"
                    dup_count=0
                    prev="$REPLY"
                fi
            else
                [[ "$dup_count" -gt 0 ]] && echo "$prev"
                dup_count=0
                prev="$REPLY"
            fi
        done
        [[ "$dup_count" -gt 0 ]] && echo "$prev"
    }
  }


find_dup(){
    get_duplicate_hash | uniq --check-chars=$HASHLEN  --all-repeated=separate | cut -d':' -f2
}



process_option(){
    while [[ -n "$1" ]]; do
        case "$1" in
        -d) 
            shift
            if [[ "$1" -ne 1 ]] && [[ "$2" -ne 2 ]]; then
                echo "${boldred}You can only use value 1 or 2 for delete option$tput_reset" >&2
                exit $E_INVALID_OPTION
            fi
            DELETE_DUP="$1"
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -s)
            FOLLOW_SYMLINK="-L"
            ;;
        -a)
            HIDDEN=""
            ;;
        -e)
            EMPTY=""
            ;;

        -H)
            RM_HARDLINKS=1
            ;;
        -*)
            echo "${boldred}Invalid Option. Use $(basename "$0") --help for more information${tput_reset}" >&2
            exit $E_INVALID_OPTION
            ;;
        *)
            if [[ -d "$1" ]]; then
                #resolve logical directories
                DIR_LIST+=( "$(realpath -s "$1")" )
            else
                echo "${boldred}Invalid argument${tput_reset}"
                exit 1
            fi
            ;;
        esac
        shift
    done
}



main(){
    process_option "$@"
    [[ ${#DIR_LIST[@]} -eq 0 ]] && DIR_LIST+=( "$PWD" )

    if  command -v xxhsum &> /dev/null; then
        HASH_COMMAND="xxhsum"
    elif command -v md5sum &>/dev/null; then
        HASH_COMMAND="md5sum"
    elif command -v sha256sum &>/dev/null; then
        HASH_COMMAND="sha256"
    elif command -v sha512sum &>/dev/null; then
        HASH_COMMAND="sha512sum"
    elif command -v sha1sum &>/dev/null; then
        HASH_COMMAND="sha1sum"
    else 
        echo "${boldred}Hash function not found. please try installing md5, sha*sum on your system ${tput_reset}"
        exit $E_HASHNOTFOUND
    fi
    if ! command -v xxhsum &> /dev/null; then
     echo -e "xxhshash not found!\nxxhash is recommended for dedup.sh.\nSee https://repology.org/project/xxhash/versions for information on how to install.\nUsing fallback hashsum"
    fi
    # calculate the length of hash generated by the hash function.
    HASHLEN=$(echo "test"| $HASH_COMMAND | cut -d' ' -f1| wc -c)
    # wc -c count new line so HASHLEN is reduced by 1
    (( HASHLEN-- ))
    find_dup 
}
main "$@"
