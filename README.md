# Simple prerun/postrun script for lutris to backup/sync savegames
Written using (hopefully) POSIX-compliant shell script syntax.

## Purpose
Since currently Lutris does not have any kind of "cloud save" functionality, but it has an option to run a script on game run/exit I created this simple script which can:
* sync files from local cloud enabled folder (i.e. folder that you are syncing to any kind of cloud, Nextcloud,Dropbox,Mega - whatever works for you) to game save folder before the game starts
* sync files from game save folder to local cloud enabled folder after game exits 

## Requirements
The script currently requires (and checks if these are available):
* dirname
* touch
* mkdir
* tr
* wc
* grep
* sed
* whoami
* printenv
* rsync
* sqlite3

Make note especially of rsync and sqlite3 which are not usually available out-of-the-box on most systems, so you may have to install them manually using your distro's package manager.


## Configuration file
The first line in the file "lutris_save_sync.config" (CLOUD_MAIN_BACKUP_DIR) should contain the full path with trailing slash to the folder where saves are to be backed-up to / from where the saves are to be synced from .

Following lines contain per-game path part where the saves are being kept. I know that PCGamingWiki contains some paths for steam, but I am using GOG and have found no such list for those so you need to update the file for your games. Feel free to create a PR (or send me a message) with updated list of tested-and-working additional paths.

Each lines' key name should be built like this 
[uppercase_service_name]_[slug]_SAVEGAMES
where:
* uppercase_service_name - can be GOG , HUMBLEBUNDLE etc.
* slug - is the name of the game in the lutris db, the slug is usually visible in its install path , all lower case, spaces are replaced with dashes , e.g. hard-reset-redux 
The path stored in the key should be inside double quotes and should begin and end with a slash!

## Lutris configuration
Be sure to first make the script executable 
`chmod+x lutris_save_sync.sh` 
The in Lutris go to "Three vertical dots" -> "Preferences" -> check "Show advanced options" -> go to tab "System options"

* In the field "Pre-launch script" put the full path to lutris_save_sync.sh along with param restore_from_cloud 
e.g. 
`/home/my_user/scripts/lutris_save_sync/lutris_save_sync.sh restore_from_cloud`
* In the field "Post-exit script" put the full path to lutris_save_sync.sh along with param backup_to_cloud 
e.g.
`/home/my_user/scripts/lutris_save_sync/lutris_save_sync.sh backup_to_cloud`

## Possible bugs
The script was only tested with gog games, in theory should work with anything but I am not responsible for any damage (deleted saves) caused by this script so do not send your lawyers my way.