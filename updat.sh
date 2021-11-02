#!/bin/bash

# EXAMPLE CONFIG (updat.conf file inside /home/username)
# user username
# admin_password abcdefg
# repository vendor/repo:branch # branch is facultative
# domain domain.com
# php_ver 7.3 # facultative

user=""
type=""
admin_username="admin"
admin_password=""
repository=""
domain=""
php_ver=""
web_dir="www"
backup_files=""

tstamp=$(date +"%s")
min_disk_usage=5000000 # ~ 5GB, used inside check_server_disk_usage

###############
# DEFINITIONS #
###############
lock_file="$(pwd)/.updatlock"
lock_updat(){
  if [[ -f "$lock_file" ]]; then
    echo "Update prevented by $lock_file"
    exit;
  fi
  echo "" > "$lock_file"
}
unlock_updat(){
  rm -f "$lock_file"
}
check_args(){
  for arg in $@; do
    if [[ $arg == "-f" ]]; then
      force=1
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
log(){
  log_name="$1"
  log_content="$2"
  log_file="$log_dir/$log_name.log"
  if [[ -f "$log_file" ]]
  then
    echo "$log_content" >> "$log_file"
  else
    echo "$log_content" > "$log_file"
  fi
}

check_variable(){
  variable="$1"
  if [[ -z "$variable" ]];
  then
    exit;
  else
    echo $variable: ${!variable}
  fi
  if [[ -z ${!variable} ]];
  then
    echo "$variable is not defined !"
    exit;
  fi
}

get_php_version(){
  # Get PHP version from user apache conf
  user="$1"
  conf="/etc/apache2/sites-available/$user.conf"
  php_ver=$(cat "$conf" | grep "define PHP_VERSION" | sed -e "s#define PHP_VERSION##g" | sed -e "s#\"##g" | sed "s/ //g")
  if [[ -z php_ver ]]
  then
    php_ver=$(cat "$conf" | grep "php-fpm" | sed -e "s#^.*php##g" | sed -e "s#-fpm.*\$##g" | sed "s/ //g")
  fi
  echo "$php_ver"
}

check_server_disk_usage(){
  mkdir -p "$install_dir"

  project_size=$(du -s "$install_dir" | tr "\t" "\n" | head -n 1)
  project_size_h=$(du -hs "$install_dir" | tr "\t" "\n" | head -n 1)
  space_left=$(df "/home/$user" | tail -n 1 | tr " " "\n" | tail -n 4 | head -n 1)
  space_left_h=$(df -h "/home/$user" | tail -n 1 | tr " " "\n" | tail -n 4 | head -n 1)

  echo "Space left on /home/$user : $space_left_h "
  echo "Project estimated size : $project_size_h"

  if [[ $(($space_left - $project_size)) -gt $min_disk_usage ]]
  then
    echo "" > /dev/null
  else
    echo "Not enough disk space to perform update !"
    exit;
  fi
}

parse_yml(){
  yml_file="$1"

  if [[ -n $(cat "$yml_file" | tail -n 1) ]]
  then
    echo "" >> "$yml_file"
    echo "" >> "$yml_file"
  fi

  while read var value
  do
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
      continue;
    else
      export "$current_var"="$lastValue"
    fi
  done < "$yml_file"
}

load_config(){
  config_file="updat.yml"

  if [[ -f "$config_file" ]]
  then
    echo "" > /dev/null;
  else
    echo "$(pwd)/updat.yml doesnt exists";
    exit;
  fi

  parse_yml "$config_file"

  echo "#################"
  echo "# UPDATE CONFIG #"
  echo "#################"

  # check required variables
  check_variable "user"
  check_variable "type"
  check_variable "domain"
  check_variable "web_dir"

  # parse repository branch if given
  if [[ -z $(echo "$repository" | sed -e "s/^[^:]*//g") ]]
  then
      repository_branch="master"
  else
      repository_branch=$(echo "$repository" | sed -e "s/^[^:]*//g")
      repository_branch=$(echo "$repository_branch" | sed "s/://g")
      repository=$(echo "$repository" | sed -e "s/:.*$//g")
  fi
  check_variable "repository"
  check_variable "repository_branch"

  if [[ -z "$php_ver" ]]
  then
    php_ver=$(get_php_version "$user")
  fi
  check_variable "php_ver"

  backup_folder="/home/$user/_backup"
  install_dir="/home/$user/$web_dir"
  temp_install_dir="/home/$user/$web_dir""_$tstamp"
  temp_old_install_dir="/home/$user/old_$web_dir""_$tstamp"

  echo "backup:"
  for files in $backup
  do
    echo " - $files"
  done

  echo ""

  disk_usage=$(check_server_disk_usage)
  echo "$disk_usage";

  read -p "Is it ok ?";
}

php_ver_composer(){
   "/usr/local/share/php$php_ver/bin/php" -d memory_limit=-1 "/usr/local/bin/composer" $@
}

backup_save(){
  # Copy files directory
  path="$1";
  source="$install_dir/$path"
  destination="$backup_folder/$path"
  if [ -d "$source" ] || [ -f "$source" ]
  then
    echo "Saving $source to $destination";
  fi

  if [[ -d "$source" ]]
  then
    mkdir -p $(dirname "$destination");
    destination=$(dirname "$destination");
    cp -R "$source" "$destination";
  fi
  if [[ -f "$source" ]]
  then
    mkdir -p $(dirname "$destination");
    cp "$source" "$destination";
  fi
}

backup_load(){
  path="$1";
  source="$backup_folder/$path";
  destination="$temp_install_dir/$path";

  if [ -d "$source" ] || [ -f "$source" ]
  then
    echo "Loading $source to $destination";
  fi

  if [[ -d "$source" ]]
  then
    mkdir -p $(dirname "$destination");
    destination=$(dirname "$destination");
    cp -R "$source" "$destination";
  fi

  if [[ -f "$source" ]]
  then
    mkdir -p $(dirname "$destination");
    cp "$source" "$destination";
  fi

}

save_local_files(){
  for files in $backup
  do
    backup_save "$files"
  done
}

load_local_files(){
  for files in $backup
  do
    backup_load "$files"
  done
}

# nicer output for composer/npm installs
hilite(){
  error=""
  name="$1"
  log_name="$2"
  echo "$name..."
  echo ""
  while read line
  do
    if [[ -z "$log_name" ]]; then
        echo "" > /dev/null
      else
        log "$log_name" "$line"
    fi
    if [[ -z $(echo "$line" | grep -E "access right|not found|fatal|Problem|RuntimeException") ]]
    then
      echo "" > /dev/null
    else
      error="1"
    fi
    if [[ -z "$error" ]]
    then
      echo -e "\r\033[1A\033[0K $line";
    else
      echo "$line"
    fi
  done
  RED="\033[0;31m"
  GREEN="\033[0;32m"
  NC="\033[0m"
  if [[ -z "$error" ]]
    then
      echo -e "\r\033[1A\033[0K\r\033[1A\033[0K[${GREEN}completed${NC}] $name";
    else
      echo -e "\r\033[1A\033[0K\r\033[1A\033[0K[${RED}error${NC}] $name";
      exit
  fi
}

contao_post_install(){
  vendor/bin/contao-console contao:migrate -n > /dev/null 2>&1;
  if [[ -z "$admin_password" ]]; then
    echo "" > /dev/null
  else
      vendor/bin/contao-console contao:user:password "$admin_username" -p "$admin_password" > /dev/null 2>&1;
  fi
  composer run post-install-cmd --no-interaction
}
bedrock_post_install(){
  if [[ -z "$admin_password" ]]; then
    echo "" > /dev/null
  else
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    if [[ -z $(php wp-cli.phar --allow-root user list | sed "s/administrator//g" | grep "$admin_username") ]]
    then
      echo "Creating user $admin_username"
      php wp-cli.phar --allow-root user create "$admin_username" support@addictic.fr --user_pass="$admin_password" --role="administrator"
    else
      echo "Updating $admin_username"
      php wp-cli.phar --allow-root user update "$admin_username" --user_pass="$admin_password"
      php wp-cli.phar --allow-root user update "$admin_username" --role="administrator"
    fi
  fi
}
post_install(){
  if [[ "$type" == "contao" ]]; then
    contao_post_install 2>&1 | hilite "Contao post install" "contao";
  fi
  if [[ "$type" == "bedrock" ]]; then
    bedrock_post_install 2>&1 | hilite "Bedrock post install" "bedrock";
  fi
  chown -R $user. "/home/$user";
}
contao_last_log(){
  project_dir="$1"
  log_dir="$project_dir/var/logs"

  if [[ -d "$log_dir" ]]; then
    error_log_file=$(ls "$log_dir" | tr " " "\n" | tail -n 1)
    error_log_file="$log_dir/$error_log_file"
    if [[ -f "$error_log_file" ]]; then
      log=$(cat "$error_log_file" | grep -E "ERROR|CRITICAL" | tail -n 1)
      if [[ -z "$log" ]]; then
        echo "" > /dev/null
      else
        echo "CONTAO LOGS ($error_log_file)"
        echo " $log"
      fi
    fi
  fi
}
custom_log(){
  if [[ "$type" == "contao" ]]; then
    contao_last_log "$install_dir"
  fi
}

apache_last_error_log(){
  log_dir="/home/$user/log/apache2"
  if [[ -d "$log_dir" ]]; then
    error_log_file=$(ls "$log_dir" | tr " " "\n" | grep "error" | head -n 1)
    error_log_file="$log_dir/$error_log_file"
    if [[ -f "$error_log_file" ]]; then
      log=$(cat "$error_log_file" | tail -n 1)
      if [[ -z "$log" ]]; then
        echo "" > /dev/null
      else
        echo "APACHE LOGS ($error_log_file)"
        echo " $log"
      fi
    fi
  fi
}

###########################
# DEPLOYMENT SCRIPT START #
###########################
start=$(date +"%s")
current_directory=$(pwd)
load_config

lock_updat

# Init Bitbucket SSH Key
eval $(ssh-agent) > /dev/null 2>&1;
ssh-add /root/.ssh/bitbucket_rsa > /dev/null 2>&1;

# Save local files
save_local_files 2>&1 | hilite "Saving local files"

# Clone project
rm -rf "$temp_install_dir";
git clone "git@bitbucket.org:$repository" -b "$repository_branch" "$temp_install_dir" 2>&1 | hilite "Git clone $repository" "git";

# Load saved local files
load_local_files 2>&1 | hilite "Loading local files"

# Composer build
cd "$temp_install_dir";
if [[ -f "composer.json" ]]; then
  php_ver_composer install --no-interaction 2>&1 | hilite "Composer install using php$php_ver" "composer";
fi

# Npm build
if [[ -f "package.json" ]]; then
  npm install 2>&1 | hilite "NPM install" "npm";
  npm run build 2>&1 | hilite "NPM build" "npm";
fi

# post install scripts
post_install

# test installation
rm -rf "$temp_old_install_dir"
mv "$install_dir" "$temp_old_install_dir"
mv "$temp_install_dir" "$install_dir"
cd "$install_dir"

response=$(curl -L --write-out '%{http_code}' --silent --output /dev/null "$domain");
echo "$domain http status code [$response]";

end=$(date +"%s");
spent=$(($end - $start));
echo "Update took $spent seconds";
unlock_updat

if [[ "$response" -ne "200" ]]
then
  echo "Status [$response] detected while loading updated site, reverting..."

  custom_log
  apache_last_error_log

  mv "$install_dir" "$temp_install_dir"
  mv "$temp_old_install_dir" "$install_dir"
else
  read -p "Do you want to remove previous version website files ? (CTRL+C to cancel)";
  rm -rf "$temp_old_install_dir"
fi

