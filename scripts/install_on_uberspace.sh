#!/bin/bash
#################################
##
## Call this script from anywhere, it will try to install OpenProject into a
## subfolder named ""openproject".  It will also try to create and start
## uberspace services.
##
#################################

function die() {
  echo $1
  exit 1
}

############################################################
### User variables (change these yourselves, if you want to)
NODE_PATH=/package/host/localhost/nodejs-9/bin
RUBYVERSION=2.4.3
PORT=61987
# Needed for email sending
USER_PWD="o5zfCQ6iimr9yASC"
OP_LOCALE=de

###########################
#### pre-installation stuff

# Set the best nodejs version in ~/.bash_profile
sed -i 's#^NODE_PATH=.*#NODE_PATH="'"${NODE_PATH}"'"#' ~/.bash_profile
PATH_LINE='PATH="$NODE_PATH:$PATH"'
grep -Fxq "${PATH_LINE}" ~/.bash_profile || echo "$PATH_LINE" >> ~/.bash_profile
EXPORT_LINE='export PATH'
grep -Fxq "${EXPORT_LINE}" ~/.bash_profile || echo "$EXPORT_LINE" >> ~/.bash_profile

echo "gem: --user-install --no-rdoc --no-ri" > ~/.gemrc
echo "RUBYVERSION=${RUBYVERSION}" > ~/etc/rubyversion


rm -r openproject
git clone https://github.com/opf/openproject-ce.git --branch stable/7 --depth 1 openproject || die
cd openproject || die



# echo "export SECRET_KEY_BASE=$(./bin/rake secret)" >> ~/.bash_profile
source ~/.bash_profile

gem install bundler || die
bundle install --deployment --without postgres sqlite development test therubyracer docker || die
npm install || die

##################
### Config files

# Database
cp config/database.yml.example config/database.yml
sed -i 's/  username: .*/  username:: '"$USER"'/g' config/database.yml
PASSWD=$(grep -A 5 '\[client]' ~/.my.cnf | grep "password=" \
             | sed -E 's/.*=([0-9a-zA-Z]*).*/\1/')
sed -i 's/  password:.*/  password: '"$PASSWD"'/g' config/database.yml
sed -i -E 's/  database: (.*)/  database: '"${USER}_"'\1/g' config/database.yml

# General config
cat <<__EOF__ > config/configuration.yml
production:
   email_delivery_method: "smtp"
   smtp_address: "$USER@$(hostname)"
   smtp_port: 587
   smtp_authentication: :login
   smtp_domain: '$(hostname)'
   smtp_user_name: '$USER'
   smtp_password: '$USER_PWD'
   # host_name: 'localhost:<geöffneter Port>' # unklar, ob benötigt; im Zweifel übernehmen
   protocol: https
rails_cache_store: :memcache
__EOF__

########
## Initializing the database and server
mysql -e "DROP DATABASE IF EXISTS quazgar2_openproject" || die
RAILS_ENV="production" ./bin/rake db:create || die
RAILS_ENV="production" ./bin/rake db:migrate || die
RAILS_ENV="production" LOCALE="$OP_LOCALE" ./bin/rake db:seed || die
RAILS_ENV="production" ./bin/rake assets:precompile || die

# RAILS_ENV=production LOCALE=de bundle exec rake generate_secret_token db:create db:migrate db:seed

# npm install -g bower
# npm install
# RAILS_ENV=production bundle exec rake assets:precompile


rm -r ~/html/assets/ || die
cp -r public/* ~/html/ || die
svc -du ~/service/openproject-web
svc -du ~/service/openproject-worker
