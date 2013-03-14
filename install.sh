#!/bin/bash
#
# This is the installation script for Gitlab CI.
# See the github repository at: http://git.io/Adg92Q
# 
# Install Gitlab CI by running this command:
# sudo bash install.sh

echo "
#################################################################
#                      Gitlab CI Installer                      #
#                          Version 2.1                          #
#################################################################
This script will attempt to install Gitlab CI according to the
instructions provided at http://git.io/Ilu6qQ

This script will need to be run as root in which you'll be asked
to provide your 'sudo'-priviledged account user password for this
script to install the necessary dependencies required by Gitlab
CI.

Technology used in this installation:
- Web Server      : Nginx (used as proxy)
- Database Server : PostgreSQL
- Ruby Web Server : Unicorn

You'll be asked to enter the Fully Qualified Domain Name which
will be the virtual host this Gitlab CI installation used by
Nginx.

You'll also be asked to enter the database password which will
be used to create the database and for Gitlab CI to access the
database.
"

read -p \
"Continue (anything other than 'yes' will cancel): " \
CANIGO

if [[ $CANIGO != "yes" ]]; then
	exit 1
fi

sudo echo "
Initializing ...
"

read -p "Please enter your FQDN: " FQDN
read -s -p "Please enter your DB password: " DBPASS

# Create a new user for our Gitlab CI
sudo adduser --disabled-login --gecos 'GitLab CI' gitlab_ci

# Update packages
sudo apt-get update

# Upgrade packages
sudo apt-get -y upgrade

# Pre set config
echo "postfix postfix/mailname string $FQDN" | sudo debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | sudo debconf-set-selections

# Install the necessary depedencies
sudo apt-get install -y wget curl gcc checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libreadline6-dev libc6-dev libssl-dev make build-essential zlib1g-dev openssh-server git libyaml-dev postfix libpq-dev libicu-dev
sudo apt-get install -y redis-server 

# Install RVM + Ruby
sudo su - gitlab_ci -c "curl -L https://get.rvm.io | bash -s stable --ruby"

# Load RVM
sudo su - gitlab_ci -c "echo 'source /home/gitlab_ci/.rvm/scripts/rvm' >> ~/.bashrc"

# Install PostgreSQL
sudo apt-get install -y postgresql-9.1

# Create a new database
sudo -u postgres psql -d template1 -c "CREATE USER gitlab_ci WITH PASSWORD '$DBPASS'"
sudo -u postgres psql -d template1 -c "CREATE DATABASE gitlab_ci_production OWNER gitlab_ci"

# Clone Gitlab CI
cd /home/gitlab_ci
sudo -u gitlab_ci -H git clone https://github.com/gitlabhq/gitlab-ci.git
cd gitlab-ci
sudo -u gitlab_ci -H git checkout 2-1-stable

# Create a temporary folder inside the application
sudo -u gitlab_ci -H mkdir -p tmp/pids

# Install depedencies
sudo su - gitlab_ci -c "cd ~/gitlab-ci; bundle --without development test mysql"

# Copy PostgreSQL config
sudo -u gitlab_ci -H cp config/database.yml.postgresql config/database.yml

# Change the username/password combination
sudo -u gitlab_ci -H sed -i "s/username: postgres/username: gitlab_ci/g" config/database.yml
sudo -u gitlab_ci -H sed -i "s/password:/password: $DBPASS/g" config/database.yml
sudo -u gitlab_ci -H sed -i "s/# host: localhost/host: localhost/g" config/database.yml

# Setup database
sudo su - gitlab_ci -c "cd ~/gitlab-ci; RAILS_ENV=production rake db:setup"

# Setup cron
sudo su - gitlab_ci -c "cd ~/gitlab-ci; RAILS_ENV=production whenever -w"

# Get init script
sudo wget https://raw.github.com/gitlabhq/gitlab-ci/master/lib/support/init.d/gitlab_ci -P /etc/init.d/
sudo chmod +x /etc/init.d/gitlab_ci

# Register on startup
sudo update-rc.d gitlab_ci defaults 21

# Start Gitlab CI
sudo service gitlab_ci start

# Install Nginx
sudo apt-get install -y nginx

# Sample configuration
sudo wget https://raw.github.com/gitlabhq/gitlab-ci/master/lib/support/nginx/gitlab_ci -P /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/gitlab_ci /etc/nginx/sites-enabled/gitlab_ci

# Change the FQDN serving this instance
sudo sed -i "s/ci.gitlab.org/$FQDN/g" /etc/nginx/sites-available/gitlab_ci

# Restart Nginx
sudo service nginx restart
