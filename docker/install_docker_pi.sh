#!/usr/bin/env bash

# uninstall previous docker versions if installed
echo "Removing previous installation of docker if present"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
sudo apt-get purge $pkg;
done
echo "Removing images, containers, and volumes"
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd

sudo apt-get update

# install the latest version of docker, includes docker-compose
echo "Installing docker"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo bash get-docker.sh

echo "Done with docker installation"
