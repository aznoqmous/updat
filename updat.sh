#!/bin/bash

home=$(echo $HOME)
user=""
type=""
admin_username="admin"
admin_password=""
repository=""
domain=""
php_ver=""
web_dir="www"
destination="www"
backup_files=""
post_install_cmd=""
composer_version=""
git_username=""
git_token=""
rsa_file="$home/.ssh/id_rsa"
tstamp=$(date +"%s")

min_disk_usage=5000000 # ~ 5GB, used inside check_server_disk_usage

export COMPOSER_ALLOW_SUPERUSER=1

###############
# DEFINITIONS #
###############
RETURN="\r\033[1A\033[0K"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
NC="\033[0m"
lock_file="$(pwd)/.updatlock"
RUNNING="⏳ "
COMPLETED="✅"
ERROR="❌"


lock_updat() {
  if [[ -f "$lock_file" ]]; then
    echo "Update prevented by $lock_file"
    exit
  fi
  echo "$$" >"$lock_file"
}
unlock_updat() {
  rm -f "$lock_file"
}

trap "exit 1" TERM
export TOP_PID=$$
kill_self(){
  unlock_updat
  kill -s TERM "$TOP_PID"
}


check_args() {
  for arg in $@; do
    if [[ $arg == "-h" ]]; then
      echo "Usage: updat [-h] [-f] [-ni] [--no-pnpm] [--no-composer] [--no-install]"
      echo "  updat               : run the updat script"
      echo "  updat init          : create a sample updat.yml file inside current directory"
      echo "  updat self-update   : update the updat script"
      echo "Options:"
      echo "  -h                  : show this message"
      echo "  -f                  : force launch, remove .updatlock file if existing"
      echo "  -ni                 : no interactions, don't prompt disk usage and do not ask to validate (old directory must be erased manually)"
      echo "  --no-pnpm           : copy existing node_modules directory instead of running pnpm install command"
      echo "  --no-composer       : copy existing vendor directory instead of running composer install command"
      echo "  --no-install        : alias for --no-pnpm + --no-composer"
      echo "  --no-status         : wont perform and show git status"
      kill_self
    fi
    if [[ $arg == "-f" ]]; then
      force=1
    fi
    if [[ $arg == "-ni" ]]; then
      no_interaction=1
    fi
    if [[ $arg == "--no-pnpm" ]]; then
      no_pnpm=1
    fi
    if [[ $arg == "--no-composer" ]]; then
      no_composer=1
    fi
    if [[ $arg == "--no-install" ]]; then
      no_pnpm=1
      no_composer=1
    fi
    if [[ $arg == "--no-status" ]]; then
      no_status=1
    fi
  done
}

check_args $@

if [[ "$force" ]]; then
  unlock_updat
fi

current_directory=$(pwd)
log_dir="$current_directory/_logs"
rm -rf "$log_dir"
mkdir -p "$log_dir"

log() {
  log_name="$1"
  log_content="$2"
  log_file="$log_dir/$log_name.log"
  if [[ -f "$log_file" ]]; then
    echo "$log_content" >>"$log_file"
  else
    echo "$log_content" >"$log_file"
  fi
}

check_variable() {
  variable="$1"
  if [[ -z "$variable" ]]; then
    exit
    #echo -e "\e[32m$variable:\e[0m "${!variable}
  fi
  if [[ -z ${!variable} ]]; then
    echo "Updat fatal error : $variable is not defined !"
    exit
  fi
}

get_php_version() {
  # Get PHP version from running php -v with user
  php_version=$(php -v | tr " " "\n" | head -n 2 | tail -n 1)
  version=$(echo "$php_version" | tr "." "\n" | head -n 1)
  major_version=$(echo "$php_version" | tr "." "\n" | head -n 2 | tail -n 1)
  echo "$version.$major_version"
}

check_server_disk_usage() {
  mkdir -p "$install_dir"

  project_size=$(du -s "$install_dir" | tr "\t" "\n" | head -n 1)
  project_size_h=$(du -hs "$install_dir" | tr "\t" "\n" | head -n 1)

  df_infos=$(quota 2>&1 | tail -n 1 | tr " " "\n" | grep -Ev "^$")
  df_h_infos=$(quota -s 2>&1 | tail -n 1 | tr " " "\n" | grep -Ev "^$")

  space_used=$(echo "$df_infos" | head -n 1 | tail -n 1)
  space_used_h=$(echo "$df_h_infos" | head -n 1 | tail -n 1)
  space_total=$(echo "$df_infos" | head -n 2 | tail -n 1)
  space_total_h=$(echo "$df_h_infos" | head -n 2 | tail -n 1)

  spacestring="[ Disk space : \e[31m$space_used_h used\e[0m | \e[33m~$project_size_h project size\e[0m | \e[32m$space_total_h total\e[0m ]"
  space_string_escaped="[ Disk space : $space_used_h used | ~$project_size_h project size | $space_total_h total ]"

  length=${#space_string_escaped}
  length_used=$(awk "BEGIN {print $space_used / $space_total * $length}" | sed -E "s/\..*$//g")
  length_project=$(awk "BEGIN {print $project_size / $space_total * $length}" | sed -E "s/\..*$//g")
  length_project=$(($length_used + $length_project + 1))


  for i in $(seq 1 $length);
  do
    if [[ "$i" -lt "$length_used" ]]; then
            echo -en "\e[31m▬\e[0m"
          else
            if [[ "$i" -lt "$length_project" ]]; then
                 echo -en "\e[33m▬\e[0m"
               else
                 echo -en "\e[32m▬\e[0m"
             fi
        fi
  done
  echo ""

  echo -e "$spacestring"
}

parse_yml() {
  yml_file="$1"

  if [[ -n $(cat "$yml_file" | tail -n 1) ]]; then
    echo "" >>"$yml_file"
    echo "" >>"$yml_file"
  fi

  while read var value; do
    value=$(echo "$value" | sed -E "s/#.*$//g" | xargs)
    if [[ -z $(echo "$var" | grep -v ":") ]]; then
      # basic key: value
      current_var=$(echo "$var" | sed "s/://g")
      lastValue="$value"
    else
      # set - items
      lastValue="$lastValue $value"
      lastValue=$(echo "$lastValue" | sed -E "s/^ //g")
    fi

    if [[ -z $(echo "$lastValue") ]]; then
      continue
    else
      export "$current_var"="$lastValue"
    fi
  done <"$yml_file"
}

load_config() {
  config_file="updat.yml"

  if [[ -f "$config_file" ]]; then
    echo "" >/dev/null
  else
    echo "No updat.yml file found"
    exit
  fi

  parse_yml "$config_file"

  # check required variables
  check_variable "user"
  check_variable "type"
  check_variable "domain"
  check_variable "destination"
  destination=$(echo $destination | sed "s#~#$home#g")

  if [[ -z "$php_ver" ]]; then
    php_ver=$(get_php_version "$user")
  fi

  # parse repository branch if given
  if [[ -z $(echo "$repository" | sed -e "s/^[^:]*//g") ]]; then
    repository_branch="master"
  else
    repository_branch=$(echo "$repository" | sed -e "s/^[^:]*//g")
    repository_branch=$(echo "$repository_branch" | sed "s/://g")
    repository=$(echo "$repository" | sed -e "s/:.*$//g")
  fi
  check_variable "repository"
  check_variable "repository_branch"

  install_dir=$(dirname "$destination")
  backup_folder="$install_dir/_backup"
  web_dir=$(basename "$destination")
  temp_install_dir="$install_dir/$web_dir""_$tstamp"
  temp_old_install_dir="$install_dir/old_$web_dir""_$tstamp"

  # Show git status
  if [[ -d "$destination" ]]; then
    cd "$destination"
    if [[ -z "$no_status" ]]; then
      git fetch 2>&1 > /dev/null | hilite "Fetching $repository:$repository_branch"
      git_status=$(git status -sb)
      if [[ $(echo "$git_status" | grep "\[") ]]; then
          echo -e "${YELLOW}Projet non à jour avec${NC} $repository:$repository_branch"
          git status -sb
        else
          echo -e "${GREEN}Projet à jour sur ${NC} $repository:$repository_branch"
      fi
    fi
  else
    echo "Nouveau projet"
  fi
  cd "$current_directory"

  if [[ -z "$no_interaction" ]]; then
    disk_usage=$(check_server_disk_usage)
    echo "$disk_usage"
    read -ep $'Updating \e[32m'$domain$'\e[0m, a \e[32mphp'$php_ver-$type$'\e[0m project \e[32m'$user'@'$destination$'\e[0m (Press <Enter> to continue)'
  fi
}

php_ver_composer() {
  composer $@ -n
  # "/usr/local/share/php$php_ver/bin/php" -d memory_limit=-1 "/usr/local/bin/composer" $@ -n
}

backup_save() {
  # Copy files directory
  backup_path="$1"
  backup_source="$destination/$backup_path"
  backup_destination="$backup_folder/$backup_path"

  if [ -d "$backup_source" ] || [ -f "$backup_source" ]; then
    echo "Saving $backup_source to $backup_destination"
  fi

  if [[ -d "$backup_source" ]]; then
    mkdir -p $(dirname "$backup_destination")
    backup_destination=$(dirname "$backup_destination")
    cp -R "$backup_source" "$backup_destination"
  fi
  if [[ -f "$backup_source" ]]; then
    mkdir -p $(dirname "$backup_destination")
    cp "$backup_source" "$backup_destination"
  fi
}

backup_load() {
  backup_path="$1"
  backup_source="$backup_folder/$backup_path"
  backup_destination="$temp_install_dir/$backup_path"

  if [ -d "$backup_source" ] || [ -f "$backup_source" ]; then
    echo "Loading $backup_source to $backup_destination"
  fi

  if [[ -d "$backup_source" ]]; then
    mkdir -p $(dirname "$backup_destination")
    backup_destination=$(dirname "$backup_destination")
    cp -R "$backup_source" "$backup_destination"
  fi

  if [[ -f "$backup_source" ]]; then
    mkdir -p $(dirname "$backup_destination")
    cp "$backup_source" "$backup_destination"
  fi

}

save_local_files() {
  rm -rf "$backup_folder"
  mkdir -p "$backup_folder"
  for files in $backup; do
    backup_save "$files"
  done
  chown -R $user. "$install_dir"
}

load_local_files() {
  for files in $backup; do
    backup_load "$files"
  done
}

# nicer output for composer/pnpm installs
hilite() {
  error=""
  name="$1"
  log_name="$2"
  echo -e "$RUNNING $name"
  echo ""
  error_lines=""
  loader="⣷⣯⣟⡿⢿⣻⣽⣾"
  while read line; do
    if [[ -z "$log_name" ]]; then
      echo "" > /dev/null
    else
      log "$log_name" "$line"
    fi
    if [[ -z $(echo "$line" | grep -E "access right|not found|fatal|Fatal|Problem|RuntimeException") ]]; then
      echo "" > /dev/null
    else
      error="1"
    fi
    if [[ -z "$error" ]]; then
      echo -e "${RETURN}\b ${CYAN}${loader:i++%${#loader}:1}${NC} $line"
    else
      error_lines="$error_lines$line"
      kill_self
    fi
  done

  if [[ -z "$error" ]]; then
    echo -e "${RETURN}${RETURN}$COMPLETED ${GREEN} $name${NC}"
  else
    echo -e "${RETURN}${RETURN}$ERROR ${RED} $name${NC}"
    echo "$error_lines"

  fi
}

contao_post_install() {
  "/usr/local/share/php$php_ver/bin/php" vendor/bin/contao-console contao:migrate -n >/dev/null 2>&1
  if [[ -z "$admin_password" ]]; then
    echo "" >/dev/null
  else
    "/usr/local/share/php$php_ver/bin/php" vendor/bin/contao-console contao:user:password "$admin_username" -p "$admin_password" >/dev/null 2>&1
  fi
  php_ver_composer run post-install-cmd -n
}
bedrock_post_install() {
  if [[ -z "$admin_password" ]]; then
    echo "" >/dev/null
  else
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    if [[ -z $(php wp-cli.phar --allow-root user list | sed "s/administrator//g" | grep "$admin_username") ]]; then
      echo "Creating user $admin_username"
      php wp-cli.phar --allow-root user create "$admin_username" support@addictic.fr --user_pass="$admin_password" --role="administrator"
    else
      echo "Updating $admin_username"
      php wp-cli.phar --allow-root user update "$admin_username" --user_pass="$admin_password"
      php wp-cli.phar --allow-root user update "$admin_username" --role="administrator"
    fi
  fi
}
post_install() {
  if [[ "$type" == "contao" ]]; then
    contao_post_install 2>&1 | hilite "Contao post install" "contao"
  fi
  if [[ "$type" == "bedrock" ]]; then
    bedrock_post_install 2>&1 | hilite "Bedrock post install" "bedrock"
  fi

  if [[ ! -z "$post_install_cmd" ]]; then
    eval "$post_install_cmd"
  fi

  chown -R $user. "$install_dir"
}
contao_last_log() {
  project_dir="$1"
  log_dir="$project_dir/var/logs"

  if [[ -d "$log_dir" ]]; then
    error_log_file=$(ls "$log_dir" | tr " " "\n" | tail -n 1)
    error_log_file="$log_dir/$error_log_file"
    if [[ -f "$error_log_file" ]]; then
      log=$(cat "$error_log_file" | grep -E "ERROR|CRITICAL" | tail -n 1)
      if [[ -z "$log" ]]; then
        echo "" >/dev/null
      else
        echo "CONTAO LOGS ($error_log_file)"
        echo " $log"
      fi
    fi
  fi
}
custom_log() {
  if [[ "$type" == "contao" ]]; then
    contao_last_log "$destination"
  fi
}

apache_last_error_log() {
  log_dir="/home/$user/log/apache2"
  if [[ -d "$log_dir" ]]; then
    error_log_file=$(ls "$log_dir" | tr " " "\n" | grep "error" | head -n 1)
    error_log_file="$log_dir/$error_log_file"
    if [[ -f "$error_log_file" ]]; then
      log=$(cat "$error_log_file" | tail -n 1)
      if [[ -z "$log" ]]; then
        echo "" >/dev/null
      else
        echo "APACHE LOGS ($error_log_file)"
        echo " $log"
      fi
    fi
  fi
}
deployment_test(){
  rm -rf "$temp_old_install_dir"
  mv "$destination" "$temp_old_install_dir"
  mv "$temp_install_dir" "$destination"
  cd "$destination"

  echo "Await response from $domain..."
  response=$(curl -L -k --write-out '%{http_code}' --silent --output /dev/null "$domain")
  echo "$domain http status code [$response]"

  unlock_updat

  if [[ "$response" -ne "200" ]]; then
    echo "Fatal error : [$response] response while loading updated site, reverting..."

#    custom_log
#    apache_last_error_log

    mv "$destination" "$temp_install_dir"
    mv "$temp_old_install_dir" "$destination"
  else
    if [[ "$no_interaction" ]]; then
      echo "" >/dev/null
    else
      if [[ -d "$temp_old_install_dir" ]]; then
        read -p "Do you want to remove previous version website files ? (Press <Enter> to continue, <CTRL+C> to cancel)"
        rm -rf "$temp_old_install_dir"
      fi
    fi
  fi
}
main(){
  ###########################
  # DEPLOYMENT SCRIPT START #
  ###########################
  start=$(date +"%s")
  current_directory=$(pwd)

  # Init Bitbucket SSH Key
  eval $(ssh-agent -s -t 120) > /dev/null 2>&1
  ssh-add "$rsa_file" 2>&1 | hilite "Initializing SSH Agent" "ssh"

  # Load config duh
  load_config 2>&1

  lock_updat

  # Save local files
  save_local_files 2>&1 | hilite "Saving local files"

  # Clone project
  rm -rf "$temp_install_dir"
  if [[ -z "$git_token" ]]; then
    git clone "git@bitbucket.org:$repository" -b "$repository_branch" "$temp_install_dir" -vvv 2>&1 | hilite "Git clone $repository" "git"
  else
    git clone "https://$git_username:$git_token@bitbucket.org/$repository" -b "$repository_branch" "$temp_install_dir" -vvv 2>&1 | hilite "Git clone $repository" "git"
  fi

  # Load saved local files
  load_local_files 2>&1 | hilite "Loading local files"

  # Composer build
  cd "$temp_install_dir"
  if [[ -f "composer.json" ]]; then

    if [[ -n "$no_composer" ]]; then
      cp -r "$destination/vendor" "$temp_install_dir/vendor" | hilite "Composer copy" "composer"
    else
      # install using user's php version
      php_ver_composer install --no-dev 2>&1 | hilite "Composer install using php$php_ver" "composer"
    fi
  fi

  # Npm build
  if [[ -f "package.json" ]]; then
    if [[ -n "$no_pnpm" ]]; then
      cp -r "$destination/node_modules" "$temp_install_dir/node_modules" | hilite "PNPM copy" "pnpm"
    else
      pnpm install 2>&1 | hilite "PNPM install" "pnpm"
    fi

    pnpm run build 2>&1 | hilite "PNPM build" "pnpm"
  fi

  # post install scripts
  post_install

  end=$(date +"%s")
  spent=$(($end - $start))

  # test installation
  deployment_test | hilite "Deployment"

  echo "Update completed in $spent seconds"
}

script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
update_available=""
check_for_updates(){
  cd "$script_dir"
  git remote update > /dev/null 2>&1
  update_available=$(git rev-list HEAD...origin/master --count)
  cd "$current_directory"
  if [[ "$update_available" != "0" ]]; then
    echo "Update available for updat, run 'updat self-update' to update the script"
    sleep 2
  fi
}
update_self(){
  cd "$script_dir"
  git fetch --all 2>&1
  git reset --hard origin/master 2>&1
  cd "$current_directory"
}
show_head(){
  cd "$script_dir"
  hash=$(git log --pretty=format:'%h' -n 1)
  cd "$current_directory"
  echo -e '\e[1;32m                     __        __ 
  __  __ ____   ____/ /____ _ / /_
 / / / // __ \ / __  // __ `// __/
/ /_/ // /_/ // /_/ // /_/ // /_  
\__,_// .___/ \__,_/ \__,_/ \__/  
     /_/\e[0m '$hash'
';
}
init(){
  cp "$script_dir/updat.yml" "updat.yml"
  echo -e "Created default \e[32mupdat.yml\e[0m at $current_directory"
  cat "updat.yml"
}

show_head
case $1 in
  "self-update")
    update_self | hilite "Performing self-update";
  ;;
  "init")
    init;
  ;;
  *)
    check_for_updates;
    main;
  ;;
esac
