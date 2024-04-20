#!/usr/bin/env bash

# uninstall previous docker versions if installed
echo "Removing previous installation of docker if present"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
sudo apt-get purge $pkg;
done
echo "Removing images, containers, and volumes"
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd

# install the latest version of docker
echo "Installing docker"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo bash get-docker.sh

# optionally ask for docker-compose installation
read -p 'Install docker-compose? [y/n] ' response
if [[ "$response" == "y" || "$response" == "Y" || "$response" == "yes" ]]; then
echo "Installing docker-compose"
sudo apt-get install libffi-dev libssl-dev
sudo apt install python3-dev
sudo apt-get install -y python3 python3-pip
sudo pip3 install docker-compose
else
echo "Skipping docker-compose"
fi

echo "Done with docker installation"
