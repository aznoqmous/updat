# aznoqmous/updat

1. `cd` and place a `updat.yml` file inside your user directory
2. Run `updat.sh` script

By default installation directory is `/home/username/www` and can be changed with the `web_dir` configuration property.

```yml
# EXAMPLE CONFIG (updat.yml file inside /home/username)

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
# optionnal defaults to www, take note that the real web_dir will be : "/home/$user/$web_dir"

backup:
  - files
  - config/parameters.yml
  - .env.local
# optionnal, those folders/files will be saved before update and re-installed after update completion
```
