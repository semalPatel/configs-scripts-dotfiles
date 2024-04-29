#!/usr/bin/env sh

####### begin essential linux tools installation #######
sudo apt-get update
sudo apt-get install vim xclip
####### end essential linux tools installation #######

####### begin tmux installation #######
echo "Installing tmux"
sudo apt install tmux
echo "Done with tmux installation"
####### end tmux installation #######

####### begin docker installation #######
# uninstall previous docker versions if installed
echo "Installing docker"
echo "Removing previous installation of docker if present"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
sudo apt-get purge $pkg;
done
echo "Removing images, containers, and volumes"
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd

# install the latest version of docker, includes docker-compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

echo "Done with docker installation"
####### end docker installation #######

####### begin oh-my-zsh installation #######
echo "Installing oh my zsh"
sudo apt install zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
echo "Done with oh my zsh installation"
####### end oh-my-zsh installation #######
