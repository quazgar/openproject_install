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
USER_PWD=""
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

source ~/.bash_profile


##################
## Get OpenProject

rm -r openproject
git clone https://github.com/opf/openproject-ce.git --branch stable/7 --depth 1 openproject || die
cd openproject || die

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

######################
## Create, save and load a new secret
NEW_SECRET=$(./bin/rake secret)

# Either replace or create from scratch
if grep -q "^export SECRET_KEY_BASE=.*" ~/.bash_profile ; then
    sed -i -E 's/^(export SECRET_KEY_BASE=).*/\1'"$NEW_SECRET"'/g' ~/.bash_profile
else
    echo "export SECRET_KEY_BASE=${NEW_SECRET}" >> ~/.bash_profile
fi
source ~/.bash_profile

#############
## Install assets

# Is this really necessary?
cp -r public/* ~/html/

###############################
## Create and start services

test -d ~/service || uberspace-setup-svscan

# create openproject-web
cat <<__EOF__ > ~/bin/openproject-web
#!/bin/sh
# This is needed to find gems installed with --user-install
export HOME=$HOME
source \$HOME/.bash_profile
# Get into the project directory and start the Rails server
cd \$HOME/apps/openproject
exec bundle exec unicorn --port ${PORT} --env production
__EOF__
chmod +x ~/bin/openproject-web
# create openproject-worker
cat <<__EOF__ > ~/bin/openproject-worker
#!/bin/sh
# This is needed to find gems installed with --user-install
export HOME=$HOME
source \$HOME/.bash_profile
# we're faster and use the right database in production
export RAILS_ENV=production
# Get into the project directory and start the Rails server
cd \$HOME/apps/openproject
exec bundle exec rake jobs:work
__EOF__
chmod +x ~/bin/openproject-worker

# Setup and start services
uberspace-setup-service openproject-web ~/bin/openproject-web
uberspace-setup-service openproject-worker ~/bin/openproject-worker

# Redirect requests to the local service
cat > ~/html/.htaccess <<__EOF__
RewriteEngine On
RewriteCond %{HTTPS} !=on
RewriteCond %{ENV:HTTPS} !=on
RewriteRule .* https://%{SERVER_NAME}%{REQUEST_URI} [R=302,L]

RewriteRule (.*) http://localhost:${PORT}/\$1 [P]
__EOF__


#################################
## We should be finished now

echo <<__EOF__

Congratulations!  OpenProject should be running now on your machine.

You should be able to access it in a web browser at

https://${USER}.$(hostname)

Logs are in $PWD/log/production.log.

For restarting the services later, type:

svc -du ~/service/openproject-web
svc -du ~/service/openproject-worker

__EOF__

