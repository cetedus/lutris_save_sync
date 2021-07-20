#!/usr/bin/env sh

#the premise of the script is simple , invoke it both as a prerun and postrun script (In lutris -> preferences, check "show advanced options" , then go "System options" tab 
#with params set as described below
#restore_from_cloud - used for prerun, so before running the game we sync backed-up saves to game dir
#backup_to_cloud - used for postrun, so after game finished running we will copy saves to cloud-synced dir
#part of path where the savegames are stored must be separately added to lutris_save_sync.config file for each game  


#first basic check, no dirname - no go
dirname>/dev/null 2>&1
if [ "${?}" = "127" ]
then
    exit
fi

###CONFIG
debug_log="false"
dump_env_vars_to_log="true"
date_format="+%Y-%m-%d %H:%M:%S"
script_home="$(dirname ${0})"
lutris_db_path="/home/$(whoami)/.local/share/lutris/pga.db"
log_path="${script_home}/lutris_save_sync.log"
config_file_location="${script_home}/lutris_save_sync.config"

needed_binaries="dirname;touch;mkdir;tr;wc;grep;sed;whoami;printenv;rsync;sqlite3"






###FUNCTIONS

init()
{
    echo "===================================================">>"${log_path}"
    number_of_binaries_to_check=$(array_get_length "${needed_binaries}")
    init_counter=1
    while [ "${init_counter}" -le "${number_of_binaries_to_check}" ]
    do
        binary_to_check=$(array_get_element_at_index "${needed_binaries}" "${init_counter}")
        if [ "$(check_if_binary_is_available ${binary_to_check})" = "1" ]
        then
            logger "ERROR" "Binary ${binary_to_check} is not available. Aborting."
            exit 5
        fi
        init_counter=$(( init_counter + 1 ))
    done
    if [ "${dump_env_vars_to_log}" = true ]
    then
        env_var_dump="$(printenv)"
        logger "DEBUG" "Env variables: ${env_var_dump}"
    fi
}

#args
#1 - name of binary to check if available
#returns 0 if binary available, 1 if not 
#first we are checking if which is available
check_if_binary_is_available()
{
    which>/dev/null 2>&1
    if [ "${?}" != "255" ]
    then
        echo "ERROR - which command not available. Exiting."
        exit 5
    fi

    which "${1}">/dev/null 2>&1
    if [ "${?}" = 0 ]
    then
        logger "DEBUG" "Binary ${1} is available"
        echo "0"
    else
        logger "DEBUG" "Binary ${1} is not available"
        echo "1"
    fi
}

#args
#1 - log level , can by any string 
#2 - message to log
#expects 2 variables to be set , date_format and log_path
logger()
{
    if [ -d "$(dirname ${log_path})" ]
    then
        mkdir -p "$(dirname ${log_path})"
    fi

    if [ ! -f "${log_path}" ]
    then
        touch "${log_path}"
    fi


    if [ "${1}" != "DEBUG" ] || ( [ "${1}" = "DEBUG" ] && [ "${debug_log}" = "true" ] )
    then
        log_timestamp=$(date "${date_format}")
        echo "${log_timestamp} - [${1}] - ${2}">>"${log_path}" 2>&1
    else
        :
    fi
    
    
}

#args
#1 - pseudoarray string with array elements as substrings separated by semicolons
#2 - string to check if present inside the array
#returns element index if found (indexing starts from 1!) , NOT_FOUND otherwise
array_get_index_of_value()
{
    elem_at_index="NOT_FOUND"
    arr_len=$(array_get_length "${1}")
    counter=1
    while [ "${counter}" -le "${arr_len}" ]
    do
        curr_elem="$(array_get_element_at_index ${1} ${counter})"
        if [ "${curr_elem}" = "${2}" ]
        then
            elem_at_index="${counter}"
            break
        fi
        counter=$(( counter + 1 ))
    done
    echo "${elem_at_index}"
}

#args
#1 - pseudoarray string with array elements as substrings separated by semicolons
#returns number of elements of the array
array_get_length()
{
    len=$(( $(echo "${1}"|tr -dc ";"|wc -c) + 1 ))
    if [ "${len}" = "1" ]
    then
        echo "0"
    else 
        echo "${len}"
    fi
}

#args
#1 - pseudoarray string with array elements as substrings separated by semicolons
#2 - index of element to get, indexing starts from 1!
#returns number of elements of the array
array_get_element_at_index()
{
    arr_len=$(array_get_length "${1}")
    if [ "${arr_len}" -lt "${2}" ]
    then
        logger "ERROR" "Tried to get index ${2} of array ${1} whose length is ${arr_len}. Exiting."
        exit 5
    fi
    echo "${1}"|cut -f${2} -d";"
}

#args
#1 key name to get value of
#return the value or KEY_NOT_FOUND
get_value_of_key_from_config()
{
    value_for_key=$(grep -Po "(?<=^${1}\=).*$" "${config_file_location}")
    if [ "$(echo ${value_for_key}|wc -m)" -gt "1" ]
    then
        #proton wine uses "steamuser" dir instead of your local user dir so we need to adjust paths accordingly
        if [ "$(are_we_running_proton)" = "WE_ARE_RUNNING_PROTON" ]
        then
            whoami_output="steamuser"
        else
            whoami_output="$(whoami)"
        fi
        echo ${value_for_key}|sed s/WHOAMI_OUTPUT/${whoami_output}/g|sed s/\"//g
    else
        echo "KEY_NOT_FOUND"
    fi
}

#args
#1 notification title
#2 notification body
notify()
{
    if [ "$(check_if_binary_is_available 'notify-send')" = "0" ]
    then
        notify-send -t 10000 "${1}" "${2}"
    else
        logger "DEBUG" "Binary notify-send is not available, notification with subject \"${1}\" and body \"${2}\" has not been sent."
    fi
}

get_game_install_path_from_lutris_db()
{
    game_path_from_db=$(sqlite3 ${lutris_db_path} "SELECT directory FROM games WHERE installed=1 AND name=\"${game_name_from_env}\"" 2>&1)
    if [ "$(echo ${game_path_from_db}|wc -l)" != "1" ]
    then
        logger "ERROR" "Expected one row with game path, instead got: "
        logger "ERROR" "${game_path_from_db}"
        exit
    fi
    logger "DEBUG" "game_path_from_db: ${game_path_from_db}"
    echo "${game_path_from_db}"
}

get_game_name_from_lutris_db()
{
    game_name_from_db=$(sqlite3 ${lutris_db_path} "SELECT slug FROM games WHERE installed=1 AND name=\"${game_name_from_env}\"" 2>&1)
    if [ "$(echo ${game_name_from_db}|wc -l)" != "1" ]
    then
        logger "ERROR" "Expected one row with game name, instead got: "
        logger "ERROR" "${game_name_from_db}"
        exit
    fi
    logger "DEBUG" "game_name_from_db: ${game_name_from_db}"
    echo "${game_name_from_db}"
}

get_service_name_from_lutris_db()
{
    game_service_from_db=$(sqlite3 ${lutris_db_path} "SELECT service FROM games WHERE installed=1 AND name=\"${game_name_from_env}\"" 2>&1)
    if [ "$(echo ${game_service_from_db}|wc -l)" != "1" ]
    then
        logger "ERROR" "Expected one row with game name, instead got: "
        logger "ERROR" "${game_service_from_db}"
        exit
    fi
    logger "DEBUG" "game_service_from_db: ${game_service_from_db}"
    echo "${game_service_from_db}"
}

get_platform_name_from_lutris_db()
{
    game_platform_from_db=$(sqlite3 ${lutris_db_path} "SELECT platform FROM games WHERE installed=1 AND name=\"${game_name_from_env}\"" 2>&1)
    if [ "$(echo ${game_platform_from_db}|wc -l)" != "1" ]
    then
        logger "ERROR" "Expected one row with game platform, instead got: "
        logger "ERROR" "${game_platform_from_db}"
        exit
    fi
    logger "DEBUG" "game_platform_from_db: ${game_platform_from_db}"
    echo "${game_platform_from_db}"
}

are_we_running_proton()
{
    wine_env_value="$(printenv WINE)"
    echo "${wine_env_value}"|grep -iq "proton" 
    proton_check_result="${?}"
    if [ "${proton_check_result}" = "0" ]
    then
        logger "INFO" "Proton wine detected based on wine path."
        echo "WE_ARE_RUNNING_PROTON"
    else
        logger "INFO" "No proton wine detected based on wine path."
        echo "WE_ARE_NOT_RUNNING_PROTON"
    fi
}

###BODY

init

action_to_perform="${1}"

logger "INFO" "Parameter passed to script: ${action_to_perform}"

game_name_from_env="$(printenv game_name)"
logger "INFO" "Game name found in environment variable game_name: \"${game_name_from_env}\""

game_install_path="$(get_game_install_path_from_lutris_db)"

game_service="$(get_service_name_from_lutris_db)"
game_service_uppercase=$(echo $(get_service_name_from_lutris_db)|tr "[a-z]" "[A-Z]")
if [ -z "${game_service_uppercase}" ]
then
    game_service_uppercase="NOSERVICE"
fi

game_name="$(get_game_name_from_lutris_db)"

game_platform="$(get_platform_name_from_lutris_db)"
game_platform_uppercase=$(echo $(get_platform_name_from_lutris_db)|tr "[a-z]" "[A-Z]")

game_savegames_path_part_in_config="$(get_value_of_key_from_config ${game_service_uppercase}_${game_platform_uppercase}_${game_name}_SAVEGAMES)"

if [ "${game_savegames_path_part_in_config}" = "KEY_NOT_FOUND" ]
then
    logger "ERROR" "No savegame path found in config file for game ${game_name} installed from service ${game_service_uppercase} for platform ${game_platform_uppercase}. Exiting."
    notify "ERROR - $(basename ${0})" "No savegame path found in config file for game ${game_name} installed from service ${game_service_uppercase} for platform ${game_platform_uppercase}. Exiting."
    exit 5
fi

echo "${game_savegames_path_part_in_config}"|grep -Pq "/$"
if [ "${?}" = "0" ]
then
    backup_is_directory=1
    logger "DEBUG" "Backup is a directory, game_savegames_path_part_in_config set to \"${game_savegames_path_part_in_config}\""
else
    backup_is_directory=0
    file_to_backup=$(echo "${game_savegames_path_part_in_config}" |grep -Po "(?<=/)[a-zA-Z0-9\-_\.]{1,}$")
    game_savegames_path_part_in_config=$(echo "${game_savegames_path_part_in_config}" |grep -Po "^.*/")
    logger "DEBUG" "Backup is a single file, game_savegames_path_part_in_config set to \"${game_savegames_path_part_in_config}\" and file_to_backup set to \"${file_to_backup}\""
fi

if [ "${game_platform_uppercase}" = "WINDOWS" ]
then
    local_savegame_dir="${game_install_path}/${game_savegames_path_part_in_config}/"
    local_savegame_dir="$(echo ${local_savegame_dir}|sed 's|\/\/|\/|g')"
 else
    if [ "${game_platform_uppercase}" = "LINUX" ]
    then
        local_savegame_dir="/${game_savegames_path_part_in_config}/"
        local_savegame_dir="$(echo ${local_savegame_dir}|sed 's|\/\/|\/|g')"
    else
        logger "ERROR" "Platform can be either \"WINDOWS\" or \"LINUX\" . For game ${game_name} from service ${game_service_uppercase} found platform: ${game_platform_uppercase}. Exiting."
        notify "ERROR - $(basename ${0})" "Platform can be either \"WINDOWS\" or \"LINUX\" . For game ${game_name} from service ${game_service_uppercase} found platform: ${game_platform_uppercase}. Exiting."
        exit 5
    fi
fi

logger "DEBUG" "Local savegame dir is: ${local_savegame_dir}"

cloud_main_backup_dir="$(get_value_of_key_from_config CLOUD_MAIN_BACKUP_DIR)"

if [ "${cloud_main_backup_dir}" = "KEY_NOT_FOUND" ]
then
    logger "ERROR" "No cloud_main_backup_dir found in config file. Exiting."
    notify "ERROR - $(basename ${0})" "No cloud_main_backup_dir found in config file. Exiting."
    exit 5
fi

if [ -z "${game_service}" ]
then
    cloud_savegame_dir="${cloud_main_backup_dir}/${game_name}/"
else
    cloud_savegame_dir="${cloud_main_backup_dir}/${game_service}/${game_name}/"
fi
cloud_savegame_dir="$(echo ${cloud_savegame_dir}|sed 's|\/\/|\/|g')"
logger "DEBUG" "Cloud savegame dir is: ${cloud_savegame_dir}"

if [ "${action_to_perform}" = "backup_to_cloud" ]
then
    if [ -d "${local_savegame_dir}" ]
    then
        if [ ! -d "${cloud_savegame_dir}" ]
        then
            mkdir -p "${cloud_savegame_dir}"
        fi
        if [ "${backup_is_directory}" = 1 ]
        then
            rsync -avcr --delete --ignore-existing "${local_savegame_dir}" "${cloud_savegame_dir}" >>"${log_path}" 2>&1
        else
            rsync -avcr --delete --ignore-existing "${local_savegame_dir}/${file_to_backup}" "${cloud_savegame_dir}" >>"${log_path}" 2>&1
        fi
        if [ "${?}" = "0" ]
        then
            logger "INFO" "Rsync backup of saves of the game ${game_name} to the cloud has succeeded."
            notify "SUCCESS - $(basename ${0})" "Rsync backup of saves of the game ${game_name} to the cloud has succeeded."
        else
            logger "ERROR" "Rsync backup of saves of the game ${game_name} to the cloud has failed. Check the log: ${log_path} ."
            notify "ERROR - $(basename ${0})" "Rsync backup of saves of the game ${game_name} to the cloud has failed. Check the log: ${log_path} ."
        fi
    else
        logger "WARNING" "Directory ${local_savegame_dir} does not exist so could not be backed up."
        notify "WARNING - $(basename ${0})" "Directory ${local_savegame_dir} does not exist so could not be backed up."
    fi
fi


if [ "${action_to_perform}" = "restore_from_cloud" ]
then
    if [ -d "${cloud_savegame_dir}" ]
    then
        if [ ! -d "${local_savegame_dir}" ]
        then
            mkdir -p "${local_savegame_dir}"
        fi
        if [ "${backup_is_directory}" = 1 ]
        then
            rsync -avcr "${cloud_savegame_dir}" "${local_savegame_dir}" >>"${log_path}" 2>&1
        else
            rsync -avcr "${cloud_savegame_dir}/${file_to_backup}" "${local_savegame_dir}" >>"${log_path}" 2>&1
        fi
        if [ "${?}" = "0" ]
        then
            logger "INFO" "Rsync restore of saves of the game ${game_name} from the cloud has succeeded."
            notify "SUCCESS - $(basename ${0})" "Rsync restore of saves of the game ${game_name} from the cloud has succeeded."
        else
            logger "ERROR" "Rsync restore of saves of the game ${game_name} from the cloud has failed. Check the log: ${log_path} ."
            notify "ERROR - $(basename ${0})" "Rsync restore of saves of the game ${game_name} from the cloud has failed. Check the log: ${log_path} ."
        fi
    else
        logger "WARNING" "Directory ${cloud_savegame_dir} does not exist so could not be synced to local savegame dir."
        notify "WARNING - $(basename ${0})" "Directory ${cloud_savegame_dir} does not exist so could not be synced to local savegame dir."
    fi
fi

