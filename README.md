#  Automated Docker Deployment Script
A production-ready Bash automation tool that takes your Dockerized application from Git to a live server with just one command.

##  What Does This Do?
Ever spent hours manually deploying your Docker app? SSH-ing into servers, installing dependencies, configuring Nginx, troubleshooting port conflicts... it's exhausting, right? This script does all of that for you. Just answer a few prompts, grab a coffee, and watch your application deploy itself to a remote Linux server with proper logging, error handling, and validation at every step.

##  Key Features
- **Fully Interactive**: Prompts you for everything it needs—no config files, no hassle
- **Production-Ready**: Built-in error handling, validation, and comprehensive logging
- **Idempotent**: Run it multiple times safely—it won't break existing setups
- **Smart Deployment**: Automatically handles updates, container recreation, and Nginx configuration
- **Zero Downtime**: Gracefully stops old containers before deploying new ones
- **Complete Logging**: Every action gets timestamped and logged for debugging

##  What It Actually Does
Here's the journey your app takes when you run this script:
### 1. **Collects Your Input** 
You'll be asked for:
- Your Git repository URL (where your code lives)
- A Personal Access Token (so it can access private repos)
- Which branch to deploy (defaults to `main` if you just hit Enter)
- SSH credentials for your remote server (username, IP, key location)
- The port your app runs on inside its container
### 2. **Grabs Your Code** 
- Clones your repository using the PAT for authentication
- If it already exists locally, pulls the latest changes instead
- Switches to your chosen branch
- Verifies a `Dockerfile` or `docker-compose.yml` exists
### 3. **Connects to Your Server** 
- Tests SSH connectivity first (no surprises!)
- Establishes a secure connection to your remote Linux machine
- All the magic happens on this remote server from here on
### 4. **Prepares the Environment** 
On your remote server, it:
- Updates system packages (`apt update && upgrade`)
- Installs Docker, Docker Compose, and Nginx if they're missing
- Adds your user to the Docker group (no more `sudo docker` every time!)
- Starts and enables all services
- Confirms everything installed correctly with version checks
### 5. **Deploys Your Application** 
- Transfers your project files to the server (using `rsync` for efficiency)
- Navigates to the project directory
- Stops and removes any old containers gracefully
- Builds your Docker image (or uses `docker-compose` if that's your setup)
- Starts fresh containers in detached mode
- Checks container health and logs to confirm success
- Validates your app is responding on the specified port
### 6. **Configures Nginx** ️
- Generates a custom Nginx configuration file
- Sets up reverse proxy from port 80 to your app's internal port
- Includes SSL readiness (ready for Let's Encrypt later)
- Tests the config for syntax errors
- Reloads Nginx to apply changes
### 7. **Validates Everything** 
Final checks to make sure it all worked:
- Docker service is running? ✓
- Your container is active and healthy? ✓
- Nginx is proxying traffic correctly? ✓
- App responds to HTTP requests? ✓
### 8. **Logs Everything** 
Every single action—success or failure gets logged with timestamps to a file like `deploy_20251022.log`. If something goes wrong at 3 AM, you'll know exactly where.

## 🚦 Prerequisites
Before running this script, make sure you have:
- A **Linux/Mac environment** (or WSL on Windows)
- **Bash 4.0+** installed
- **SSH access** to your remote server with a key-based authentication
- A **Git repository** with a Dockerfile or docker-compose.yml
- A **Personal Access Token** from your Git provider (GitHub, GitLab, Bitbucket, etc.)
- **Basic familiarity** with your app's container port
Your remote server should be:
- Running a **Debian-based Linux** (Ubuntu, Debian, etc.)
- Accessible via SSH
- Fresh or with minimal setup (the script installs what it needs)

##  Installation
Just download the script and make it executable:
```bash
# Clone this repository
git clone <your-repo-url>
cd <repo-directory>
# Make the script executable
chmod +x deploy.sh
```
That's it. No dependencies to install locally—the script handles everything on the remote server.

##  Usage
### Basic Deployment
Run the script and follow the prompts:
```bash
./deploy.sh
```
You'll be asked for:
1. **Git Repository URL**: `https://github.com/username/my-app.git`
2. **Personal Access Token**: Your PAT (input is hidden for security)
3. **Branch name**: Press Enter for `main`, or type another branch
4. **SSH Username**: Usually `ubuntu`, `root`, or your custom user
5. **Server IP**: Like `192.168.1.100` or `example.com`
6. **SSH Key Path**: Usually `~/.ssh/id_rsa`
7. **Application Port**: The port your container exposes (e.g., `3000`, `8080`)

Then sit back and watch the magic happen! 

### Cleanup Mode (Optional)
Want to remove everything and start fresh?
```bash
./deploy.sh --cleanup
```
This will:
- Stop and remove all containers
- Delete Nginx configurations
- Remove project files from the server
- Leave Docker/Nginx installed (in case you want to redeploy)

##  Project Structure
```
.
├── deploy.sh              # The main deployment script
├── deploy_YYYYMMDD.log    # Auto-generated log file (timestamped)
└── README.md              # You are here!
```
After deployment, your remote server will have:
```
/opt/deployments/
└── your-app/              # Your project files
    ├── Dockerfile
    ├── docker-compose.yml (if applicable)
    └── ... (rest of your code)
/etc/nginx/sites-available/
└── your-app.conf          # Generated Nginx config
```

##  Example Run
Here's what a successful deployment looks like:
```
Docker Deployment Automation Script
========================================

 Please provide the following information:
Git Repository URL: https://github.com/myuser/awesome-app.git
Personal Access Token: ••••••••••••••
Branch name [main]: develop
SSH Username: ubuntu
Server IP Address: 192.168.1.50
SSH Key Path [~/.ssh/id_rsa]: 
Application Port: 8080

✅ Cloning repository...
✅ Switched to branch 'develop'
✅ Dockerfile found
✅ SSH connectivity confirmed
✅ Installing Docker and dependencies...
✅ Transferring project files...
✅ Building Docker image...
✅ Container started successfully
✅ Nginx configured and reloaded
✅ Deployment validated successfully!

 Your application is live at http://192.168.1.50

 Full logs available at: deploy_20251022_143022.log
```

##  Error Handling

This script doesn't just fail silently. It:

- **Validates every input** before proceeding
- **Checks connectivity** before attempting remote operations
- **Verifies file existence** (Dockerfile, SSH keys, etc.)
- **Uses trap handlers** to catch unexpected errors
- **Provides meaningful exit codes** for each failure type
- **Logs everything** so you can debug issues quickly

If something goes wrong, you'll see exactly what failed and where.

##  Idempotency

You can run this script multiple times safely:

- **Re-cloning**: Pulls latest changes if repo exists
- **Re-installation**: Skips packages already installed
- **Re-deployment**: Stops old containers gracefully before starting new ones
- **Nginx config**: Overwrites safely without duplicates
- **No port conflicts**: Cleans up properly between runs

##  Security Notes

- **PAT handling**: Your token is never logged or displayed
- **SSH keys**: Uses your existing keys—no password prompts
- **Input hiding**: Sensitive inputs use `read -s` (silent mode)
- **Log sanitization**: Tokens and passwords won't appear in logs

**Important**: Keep your PAT secure! Consider using environment variables for automation:

```bash
export GIT_PAT="your-token-here"
./deploy.sh
```

##  Troubleshooting

### "SSH connection failed"
- Verify your SSH key has correct permissions (`chmod 600 ~/.ssh/id_rsa`)
- Ensure your key is added to the server's `~/.ssh/authorized_keys`
- Check if the server IP is correct and accessible

### "Docker build failed"
- Check the log file for specific error messages
- Verify your Dockerfile syntax
- Ensure all required files are in the repository

### "Port already in use"
- The script should handle this, but if not, manually stop conflicting containers:
  ```bash
  ssh user@server "docker ps -a"
  ssh user@server "docker stop <container-id>"
  ```

### "Nginx test failed"
- Check `/var/log/nginx/error.log` on the server
- Verify port isn't blocked by firewall
- Ensure no syntax errors in generated config

##  Contributing
Found a bug? Have an idea? Contributions are welcome!
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

##  License
This project is open source 

##  Acknowledgments
Built with love for developers who are tired of manual deployments. May your deploys be swift and your downtime be zero! 

---

