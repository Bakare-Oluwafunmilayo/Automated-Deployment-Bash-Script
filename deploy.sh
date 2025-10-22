#!/bin/bash

# ===============================================================================================================================================================
#Description:A robust, production-grade Bash script that automates the setup, deployment, and configuration of a Dockerized application on a remote Linux server.
#================================================================================================================================================================

set -e #Makes the script exit immediately if any command fails...it helps prevent continuing after an error.

LOG="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
trap 'echo " Error on line $LINENO (see $LOG)"; exit 1' ERR

# --- Handle Cleanup Flag ---
if [[ $1 == "--cleanup" ]]; then
  read -p "Enter your Server username: " SSH_USER
  read -p "Input your Server IP: " SERVER_IP
  read -p "Enter SSH key path: " SSH_KEY
  read -p "Enter your App name: " APP
  echo " Cleaning up $APP..."
  ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
docker rm -f \$(docker ps -aq --filter "name=${APP,,}") 2>/dev/null || true
docker network rm ${APP,,}_net 2>/dev/null || true
sudo rm -f /etc/nginx/sites-{available,enabled}/$APP
sudo systemctl reload nginx || true
EOF
echo " Cleanup complete."
exit 0
fi

# 1️⃣ Collect Parameters from User Input and validate them

#Git Repository URL details
read -p " Enter your Git repo URL (e.g. https://github.com/username/repo.git): " GIT_URL #Prompts user for the Git repository URL and stores it in GIT_URL
#Check if GIT_URL is empty; if so, prints error and exits.
[[ -z "$GIT_URL" ]] && { echo "Invalid Git URL format."; exit 1; }

#Personal Access Token (PAT) details
read -s -p " Enter your Personal Access Token(PAT): " PAT; echo  #Reads Personal Access Token silently (-s hides input), then prints a newline.
#Ensures PAT isn’t empty.
[[ -z "$PAT" ]] && { echo "PAT compulsory."; exit 1; }

#Branch name
read -p " Enter the Branch name [press Enter for 'main']: " BRANCH
BRANCH=${BRANCH:-main} #Prompts for branch name; if user presses Enter, defaults to main.

#Remote Server SSH Details
echo "Enter your remote server SSH details:"
read -p " Enter your remote server username: " SSH_USER  #Prompts for SSH username, ensures it’s not blank.
[[ -z "$SSH_USER" ]] && { echo " Username cannot be empty."; exit 1; }

#IP address
read -p " Enter your remote server IP address: " SERVER_IP   #Asks for the server’s IP address.
[[ ! "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "IP address format not supported."; exit 1; }

#SSH Key
read -p " Enter your SSH key file path (e.g. ~/.ssh/id_rsa) : " SSH_KEY  #Prompts for SSH private key path and checks if file exists.
[[ ! -f "$SSH_KEY" ]] && { echo "SSH key not found."; exit 1; }

#Application port
read -p "   Enter your application port (e.g. 8080): " APP_PORT #Asks for application port number.
#Validates port is numeric and within 1–65535 range
if [[ ! "$APP_PORT" =~ ^[0-9]+$ || $APP_PORT -lt 1 || $APP_PORT -gt 65535 ]]; then
  echo " Enter correct port."
  exit 1
fi

read -p "Enter your domain name (leave blank to use server IP): " DOMAIN
DOMAIN=${DOMAIN:-_}

#Makes all collected variables available to later scripts (e.g., a deployment script).
export GIT_URL PAT BRANCH SSH_USER SERVER_IP SSH_KEY APP_PORT DOMAIN

REPO_NAME=$(basename -s .git "$GIT_URL")

# --- Summary of Collected Inputs ---
echo
echo "=============================================="
echo "Parameters Collected Successfully!"
echo "=============================================="
echo "Git Repository URL:   $GIT_URL"
echo "Branch:               $BRANCH"
echo "SSH Username:         $SSH_USER"
echo "Server IP:            $SERVER_IP"
echo "SSH Key Path:         $SSH_KEY"
echo "Application Port:     $APP_PORT"
echo "Personal Access Token: $PAT"
echo "=============================================="
echo #Nicely prints a summary of all collected and validated values for review.


## === 2️⃣ Clone or Update Repository ===
if [ -d "$REPO_NAME" ]; then  #check if if the repo folder is already on your system.
    echo " '$REPO_NAME' already exists — pulling latest changes..."
    cd "$REPO_NAME"
    git pull origin "$BRANCH" #If it already exists, updates it with the latest code from GitHub
else
    echo " Cloning the repository..."
    # Use PAT to authenticate the clone
    GIT_URL_WITH_PAT=$(echo "$GIT_URL" | sed "s#https://#https://$PAT@#")
    git clone -b "$BRANCH" "$GIT_URL_WITH_PAT" #If it’s not found, clones the repo and checks out the branch automatically. The sed command inserts your PAT into the URL for authentication.
    cd "$REPO_NAME"
fi

# ===  Switch to the Correct Branch ===
echo " Switching to branch '$BRANCH'..."
git checkout "$BRANCH" #Ensures you’re on the right branch after cloning or pulling

# === 3️⃣ Navigate into the Cloned Directory ===
echo " Checking for Docker setup..."
if [ -f "Dockerfile" ]; then
    echo "There is Dockerfile in this repo!"
    LOG_MSG="Dockerfile found in project."
elif [ -f "docker-compose.yml" ]; then
    echo " docker-compose.yml exist!"
    LOG_MSG="docker-compose.yml found in project."
else
    echo " No Dockerfile or docker-compose.yml found!"
    LOG_MSG="No Docker configuration files found."
fi

# Log result
LOG_FILE="../deployment_check.log"
echo "$(date): $LOG_MSG (Project: $REPO_NAME)" >> "$LOG_FILE"
echo "  Log saved to: $LOG_FILE"
echo

cd ..

# === 4️⃣ SSH into the Remote Server ===
echo "==============================================="
echo " Testing SSH Connection to Remote Server..."
echo "==============================================="
echo

# Ping test
echo " Checking if server is reachable..."
ping -c 2 "$SERVER_IP" > /dev/null && echo " Ping OK" || echo "  Ping failed"
ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$SERVER_IP" "echo ' SSH connected'" || {
  echo " SSH failed. Check credentials or key path."
  exit 1
}

echo " All checks passed! Ready for deployment."

# === 5️⃣ Prepare remote environment ===
echo "  Preparing remote environment on $SERVER_IP..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<'EOF'
set -e
echo " Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

echo " Installing Docker, Docker Compose & Nginx..."
sudo apt install -y docker.io nginx
sudo apt install -y docker-compose-plugin || true

echo " Adding user to Docker group..."
sudo usermod -aG docker $USER

echo "  Enabling and starting services..."
sudo systemctl enable docker nginx
sudo systemctl start docker nginx

echo " Confirming installations..."
docker --version
docker-compose --version
nginx -v || true

echo " Remote environment ready!"
EOF

echo " All steps completed successfully!"

# === 6️⃣ Deploy Dockerized app ===
echo " Deploying project files to remote server..."
scp -i "$SSH_KEY" -r "$REPO_NAME" "${SSH_USER}@${SERVER_IP}:/home/${SSH_USER}"

ssh -i "$SSH_KEY" "${SSH_USER}@${SERVER_IP}" bash <<EOF
set -e
cd /home/$SSH_USER/$REPO_NAME

echo " Building and running containers..."
if [ -f "docker-compose.yml" ]; then
  docker-compose up -d --build
else
  docker build -t ${REPO_NAME,,}:latest .
  docker run -d -p $APP_PORT:$APP_PORT ${REPO_NAME,,}:latest
fi

echo " Checking running containers..."
docker ps

echo " Checking container logs..."
CID=\$(docker ps -q --filter "ancestor=${REPO_NAME,,}:latest" | head -n 1)
[ -n "\$CID" ] && docker logs \$CID | tail -n 10 || echo "No logs found for container."

echo " Checking app on port $APP_PORT..."
sudo netstat -tuln | grep $APP_PORT && echo " App running on port $APP_PORT"
EOF

echo " Deployment complete! Access your app at http://$SERVER_IP:$APP_PORT"

# === 6️⃣ Configure Nginx Reverse Proxy ===
echo " Configuring Nginx on $SERVER_IP..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
set -e
sudo tee /etc/nginx/sites-available/$REPO_NAME > /dev/null <<NGINX
server {
    listen 80;
    server_name ${DOMAIN:-_};
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    # SSL Placeholder (Certbot or self-signed cert can go here)
}
NGINX

sudo ln -sf /etc/nginx/sites-available/$REPO_NAME /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
EOF

echo " Nginx reverse proxy configured!"
echo " App live at: http://${DOMAIN:-$SERVER_IP}"

# === 7️⃣ Validate Deployment ===
echo " Validating deployment on $SERVER_IP..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
echo " Checking Docker & container status..."
sudo systemctl is-active --quiet docker && echo " Docker running" || echo " Docker not running"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "${REPO_NAME,,}" && echo " Container active" || echo " Container not found"
echo " Checking Nginx..."
sudo systemctl is-active --quiet nginx && echo " Nginx running" || echo " Nginx not running"
echo " Testing local endpoint..."
curl -I http://localhost:$APP_PORT >/dev/null 2>&1 && echo " Local response OK" || echo " Local test failed"
EOF

echo " Testing remote access..."
curl -I http://${DOMAIN:-$SERVER_IP} >/dev/null 2>&1 && echo " Remote site accessible" || echo " Remote access failed"

echo " Deployment and validation complete! Visit: http://${DOMAIN:-$SERVER_IP}"
echo " Logs saved to: $LOG_FILE"
