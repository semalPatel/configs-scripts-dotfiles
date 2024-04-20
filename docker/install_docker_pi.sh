#!/usr/bin/env bash

# uninstall previous docker versions if installed
echo "Removing previous installation of docker if present"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
sudo apt-get purge $pkg;
done
echo "Removing images, containers, and volumes"
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd

# add docker's official GPG key:
echo "Adding docker's official GPG key"
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/raspbian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# set up docker's APT repository:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/raspbian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# install the latest version of docker
echo "Installing docker"
sudo apt-get install docker.io

# optionally ask for docker-compose installation
read -p 'Install docker-compose? [y/n] ' response
if [[ "$response" == "y" || "$response" == "Y" || "$response" == "yes" ]]; then
echo "Installing docker-compose"
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
else
echo "Skipping docker-compose"
fi

echo "Done with docker installation"
