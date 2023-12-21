```yml
                     __        __ 
  __  __ ____   ____/ /____ _ / /_
 / / / // __ \ / __  // __ `// __/
/ /_/ // /_/ // /_/ // /_/ // /_  
\__,_// .___/ \__,_/ \__,_/ \__/  
     /_/
```


## Get started
1. `cd` and run `updat init` to create a default `updat.yml` file inside your wrking directory
2. Run `updat` script

## Update script
To get the latest version of the script,run `updat self-update`

## Configuration
By default installation directory is `/home/username/www` and can be changed with the `web_dir` configuration property.

```yml
# EXAMPLE CONFIG (updat.yml file inside /home/{username})

user: username
# required

contao_password: abcdefg
# required

repository: vendor/repo:branch
# :branch is optionnal, defaults to master

domain: domain.com
# optionnal

php_ver: 7.3
# optionnal

web_dir: www
# optionnal defaults to www, take note that the real web_dir will be : "/home/{user}/{web_dir}"

backup:
  - files
  - config/parameters.yml
  - .env.local
# optionnal, those folders/files will be saved before update and re-installed after update completion
```


## Commands
```yml
  updat               : run the updat script
  updat init          : create a sample updat.yml file inside current directory
  updat self-update   : update the updat script
  
Options:
  help           : -h            : show this message
  force          : -f            : force launch, remove .updatlock file if existing
  no-interaction : -ni           : no interactions, don't prompt disk usage and do not ask to validate (old directory must be erased manually)
  no-yarn        : --no-yarn     : copy existing node_modules directory instead of running yarn install command
  no-composer    : --no-composer : copy existing vendor directory instead of running composer install command
  no-install     : --no-install  : alias for --no-yarn + --no-composer

```
