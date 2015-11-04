#!/bin/bash

# Get ip and hostname from config.yml
ip=$1
hostname=$2

# run as root
sudo apt-get update -y
sudo apt-get upgrade -y

# Set vim as default editor
sudo apt-get install -y vim
sudo update-alternatives --set editor /usr/bin/vim.basic

# Install or required packages
sudo apt-get install -y build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev logrotate python-docutils pkg-config cmake nodejs

# Install python
sudo apt-get install -y python

# Dependency requirement for reStructuredText markup language support
sudo apt-get install -y python-docutils

# Install Git
sudo apt-get install -y git-core
# Dependencies for git
sudo apt-get install -y libcurl4-openssl-dev libexpat1-dev gettext libz-dev libssl-dev build-essential

# Postfix for mail !!!NOTE!!! How to automatically config postfix
sudo debconf-set-selections <<< "postfix postfix/mailname string $hostname"
sudo debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
sudo apt-get install -y postfix

# Remove old version of ruby
sudo apt-get remove ruby -y

# ============= Install ruby 2.1.* ============
mkdir /tmp/ruby && cd /tmp/ruby
curl -O --progress https://cache.ruby-lang.org/pub/ruby/2.1/ruby-2.1.7.tar.gz
echo 'e2e195a4a58133e3ad33b955c829bb536fa3c075  ruby-2.1.7.tar.gz' | shasum -c - && tar xzf ruby-2.1.7.tar.gz
cd ruby-2.1.7
./configure --disable-install-rdoc
make
sudo make install

sudo gem install bundler --no-ri --no-rdoc
# ==============

# ============== Make sure Golang is installed because git http need it
mkdir /tmp/golang && cd /tmp/golang
curl -O --progress https://storage.googleapis.com/golang/go1.5.1.linux-386.tar.gz
echo '6ce7328f84a863f341876658538dfdf10aff86ee  go1.5.1.linux-386.tar.gz' | shasum -c - && \
sudo tar -C /usr/local -xzf go1.5.1.linux-386.tar.gz
sudo ln -sf /usr/local/go/bin/{go,godoc,gofmt} /usr/local/bin/
rm go1.5.1.linux-amd64.tar.gz
# ==============

# Add default git user
sudo adduser --disabled-login --gecos 'GitLab' git

# =============== Install and configure postgresql
sudo apt-get install -y postgresql postgresql-client libpq-dev
sudo cat << EOF | sudo tee /tmp/postgres.sql
CREATE USER git CREATEDB;
CREATE DATABASE gitlabhq_production OWNER git;
EOF
# Login to PostgreSQL, and create User and Database for gitlab
sudo -u postgres psql -d template1 < /tmp/postgres.sql

# =============== Install redis ====================
sudo apt-get install redis-server

# Configure redis to use sockets
sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.orig

# Disable Redis listening on TCP by setting 'port' to 0
sudo sed 's/^port .*/port 0/' /etc/redis/redis.conf.orig | sudo tee /etc/redis/redis.conf

# Enable Redis socket for default Debian / Ubuntu path
sudo echo 'unixsocket /var/run/redis/redis.sock' | sudo tee -a /etc/redis/redis.conf
# Grant permission to the socket to all members of the redis group
sudo echo 'unixsocketperm 770' | sudo tee -a /etc/redis/redis.conf

# Create the directory which contains the socket
sudo mkdir /var/run/redis
sudo chown redis:redis /var/run/redis
sudo chmod 755 /var/run/redis
# Persist the directory which contains the socket, if applicable
if [ -d /etc/tmpfiles.d ]; then
  sudo echo 'd  /var/run/redis  0755  redis  redis  10d  -' | sudo tee -a /etc/tmpfiles.d/redis.conf
fi

# Activate the changes to redis.conf
sudo service redis-server restart

# Add git to the redis group
sudo usermod -aG redis git
# ===================

# =================== Gitlab configuration ====================
# We'll install GitLab into home directory of the user "git"
cd /home/git    
# Clone GitLab repository
sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b 8-1-stable gitlab 

# Go to GitLab installation folder
cd /home/git/gitlab

# Copy the example GitLab config
sudo -u git -H cp config/gitlab.yml.example config/gitlab.yml

# Update GitLab config file, follow the directions at top of file
# !!!!NOTE !!!! Need to config accordingly
# sudo -u git -H editor config/gitlab.yml
sudo sed -i "s/host: localhost/host: $hostname/" config/gitlab.yml
sudo sed -i "s/email_from: example@example.com/email_from: git@$hostname/" config/gitlab.yml
sudo sed -i "s/email_reply_to: noreply@example.com/email_reply_to: noreply@$hostname/" config/gitlab.yml

# Copy the example secrets file
# !!!NOTE!!! Secrets need to set here
sudo -u git -H cp config/secrets.yml.example config/secrets.yml
sudo -u git -H chmod 0600 config/secrets.yml

# Make sure GitLab can write to the log/ and tmp/ directories
sudo chown -R git log/
sudo chown -R git tmp/
sudo chmod -R u+rwX,go-w log/
sudo chmod -R u+rwX tmp/

# Make sure GitLab can write to the tmp/pids/ and tmp/sockets/ directories
sudo chmod -R u+rwX tmp/pids/
sudo chmod -R u+rwX tmp/sockets/

# Make sure GitLab can write to the public/uploads/ directory
sudo mkdir public/uploads
sudo chown -R git public/uploads
sudo chmod -R u+rwX  public/

# Change the permissions of the directory where CI build traces are stored
sudo chmod -R u+rwX builds/

# Copy the example Unicorn config
sudo -u git -H cp config/unicorn.rb.example config/unicorn.rb

# Enable cluster mode if you expect to have a high load instance
# Ex. change amount of workers to 3 for 2GB RAM server
# Set the number of workers to at least the number of cores
# sudo -u git -H editor config/unicorn.rb

# Copy the example Rack attack config
sudo -u git -H cp config/initializers/rack_attack.rb.example config/initializers/rack_attack.rb

# Configure Git global settings for git user, used when editing via web editor
sudo -u git -H git config --global core.autocrlf input

# Configure Redis connection settings
sudo -u git -H cp config/resque.yml.example config/resque.yml

# Change the Redis socket path if you are not using the default Debian / Ubuntu configuration
# sudo -u git -H editor config/resque.yml
# =====================

# ===================== Configure gitlab ===================
sudo -u git cp config/database.yml.postgresql config/database.yml
###
# !!!NOTE need to configure database settings properly
###

# Make config/database.yml readable to git only
sudo -u git -H chmod o-rwx config/database.yml
# =====================

# ===================== Install Gems, Shell and Http Server ============== 
# For PostgreSQL (note, the option says "without ... mysql")
sudo -u git -H bundle install --deployment --without development test mysql aws kerberos

# Run the installation task for gitlab-shell (replace `REDIS_URL` if needed):
sudo -u git -H bundle exec rake gitlab:shell:install[v2.6.6] REDIS_URL=unix:/var/run/redis/redis.sock RAILS_ENV=production

# http server 
cd /home/git
sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-git-http-server.git
cd gitlab-git-http-server
sudo -u git -H git checkout 0.3.0
sudo -u git -H make

cd /home/git/gitlab
sudo -u git -H bundle

# Go to Gitlab installation folder
# Type 'yes' to create the database tables.
cd /home/git/gilab
sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production << EOF
yes
EOF

# =====================

# ===================== Final steps =======================
# Install init script
sudo cp lib/support/init.d/gitlab /etc/init.d/gitlab

# Make gitlab start on boot
sudo update-rc.d gitlab defaults 21

# Setup logrotate
sudo cp lib/support/logrotate/gitlab /etc/logrotate.d/gitlab

# Check application status
sudo -u git -H bundle exec rake gitlab:env:info RAILS_ENV=production

# Compile assets
sudo -u git -H bundle exec rake assets:precompile RAILS_ENV=production

# Nginx settings 
sudo apt-get install -y nginx
sudo cp lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab

###
# !!! NOTE !!! need to setup nginx to correct hostname
###
sudo sed "s/server_name YOUR_SERVER_FQDN/server_name $hostname/" lib/support/nginx/gitlab | sudo tee /etc/nginx/sites-available/gitlab
sudo rm -rf /etc/nginx/sites-available/default

sudo nginx -t
sudo service nginx restart

# Fix permission issues
sudo chmod -R ug+rwX,o-rwx /home/git/repositories/
sudo chmod -R ug-s /home/git/repositories/
sudo find /home/git/repositories/ -type d -print0 | sudo xargs -0 chmod g+s
sudo chmod 0750 /home/git/gitlab/public/uploads

# Double check application status
sudo service gitlab restart
sudo -u git -H bundle exec rake gitlab:check RAILS_ENV=production
# =====================
# root login: root/5iveL!fe

# TODO: checkout hostname settings and secret.yml settings
