# Secure-Deploy-3-Tier-DevOps-Pipeline
Designed and implemented a secure CI/CD pipeline using Jenkins, Gogs, and Ansible across three provisioned  Linux VMs. Automated user management, Apache deployment, system hardening, and monitoring using Bash scripting and audit configurations.

### Infrastructure:

- **VM1**: Jenkins server
- **VM2**: Gogs server (Git repo)     
- **VM3**: Linux deployment server (Ansible + Bash + hardening)

---

## Phase 1: VM Provisioning

1. Provision 3 VMs.
2. Set hostnames:
   ```bash
   hostnamectl set-hostname jenkins.local   # VM1
   hostnamectl set-hostname gogs.local      # VM2
   hostnamectl set-hostname linux.local    # VM3
   ```
3. Update `/etc/hosts` on all VMs:
   ```
   172.20.132.125 jenkins.local
   172.20.130.157 gogs.local
   172.20.140.103 linux.local
   ```

---

## Phase 2: User Management on VM3

### Script: CreateUsersAd.sh

```bash
#!/bin/bash

# Variables
GROUP="deployG"
BASE_DIR="/opt/deploy_users"
LOG_FILE="/var/log/deploy_user_creation.log"
USERS=("Devo" "Testo" "Prodo")
RBASH="/bin/rbash"

# Ensure log file exists
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"

# Ensure rbash exists
if [ ! -f "$RBASH" ]; then
    sudo ln -s /bin/bash "$RBASH"
fi

# Create group if it doesn't exist
if ! getent group "$GROUP" >/dev/null; then
    sudo groupadd "$GROUP"
    echo "$(date): Group $GROUP created" | sudo tee -a "$LOG_FILE"
else
    echo "$(date): Group $GROUP already exists" | sudo tee -a "$LOG_FILE"
fi

# Create users
for user in "${USERS[@]}"; do
    HOME_DIR="$BASE_DIR/$user"
    
    if id "$user" &>/dev/null; then
        echo "$(date): User $user already exists. Skipping..." | sudo tee -a "$LOG_FILE"
        continue
    fi

    sudo useradd -m -d "$HOME_DIR" -s "$RBASH" -g "$GROUP" "$user"
    sudo mkdir -p "$HOME_DIR/.ssh"
    sudo chmod 700 "$HOME_DIR/.ssh"
    sudo chown -R "$user:$GROUP" "$HOME_DIR"

    # Generate key pair
    sudo -u "$user" ssh-keygen -t rsa -b 2048 -N "" -f "$HOME_DIR/.ssh/id_rsa" >/dev/null
    sudo cp "$HOME_DIR/.ssh/id_rsa.pub" "$HOME_DIR/.ssh/authorized_keys"
    sudo chmod 600 "$HOME_DIR/.ssh/authorized_keys"
    sudo chown "$user:$GROUP" "$HOME_DIR/.ssh/authorized_keys"

    # Lock password (enforce SSH key only)
    sudo passwd -l "$user"

    echo "$(date): User $user created with rbash and SSH key-only login" | sudo tee -a "$LOG_FILE"
done

```

**Commands:**

```bash
chmod +x CreateUsersAd.sh
./CreateUsersAd.sh
```

Upload each user’s SSH public key to `/opt/deploy_users/<user>/.ssh/authorized_keys`.

---

## Phase 3: Script to List Users Not in a Group

### Script: NotGroupMembers.sh

```bash
#!/bin/bash

GROUP="deployG"
COUNT=0

echo "Users not in group $GROUP:"
echo "---------------------------------------------"
printf "%-15s %-10s %-25s %-20s\n" "Username" "UID" "Shell" "Last Login"
echo "---------------------------------------------"

while IFS=: read -r user _ uid _ _ _ home shell; do
    if [ "$uid" -ge 1000 ] && ! id -nG "$user" | grep -qw "$GROUP"; then
        last_login=$(lastlog -u "$user" | awk 'NR==2 {print $4, $5, $6, $7}')
        printf "%-15s %-10s %-25s %-20s\n" "$user" "$uid" "$shell" "$last_login"
        ((COUNT++))
    fi
done < /etc/passwd

echo "---------------------------------------------"
echo "Total users not in $GROUP: $COUNT"

```

**Command:**

```bash
chmod +x NotGroupMembers.sh
./NotGroupMembers.sh
```

---

## Phase 4: Git & Automation (Gogs + Ansible)

### 1. Install Gogs on VM2

```bash
sudo yum install git -y
wget https://dl.gogs.io/0.12.10/gogs_0.12.10_linux_amd64.tar.gz
tar -xzf gogs_0.12.10_linux_amd64.tar.gz
cd gogs
./gogs web
```

Access Gogs: `http://172.20.130.157:3000`

- Create admin user
- Create private repo: `dev-project`

### 2. Clone Repo & Push Scripts into Gogs

From my local machine:
```bash
git clone http://172.20.130.157:3000/alaa.atef11/dev-project.git
cd dev-project
scp CreateUsersAd.sh devadmin@linux.local:/home/devadmin/
ssh devadmin@linux.local
chmod +x CreateUsersAd.sh
./NotGroupMembers.sh 
git commit -m "initial commit"
git push
scp NotGroupMembers.sh devadmin@linux.local:/home/devadmin/
ssh devadmin@linux.local
chmod +x NotGroupMembers.sh
./NotGroupMembers.sh 
git commit -m "initial commit"
git push
```

### 3. Install Ansible on VM3

```bash
sudo yum install epel-release -y
sudo yum install ansible -y
```

Create inventory:

```ini
# /etc/ansible/hosts
[webservers]
172.20.140.103   ansible_user=devadmin ansible_become=true ansible_become_password=admin
```

### 4. Ansible Playbook: InstallApache.yml

```yaml
---
- name: Install and harden Apache
  hosts: webservers
  become: true
  become_user: root  # This ensures that Ansible runs commands as the root user
  tasks:

    - name: Install Apache
      yum:
        name: httpd
        state: present

    - name: Ensure Apache is started and enabled
      service:
        name: httpd
        state: started
        enabled: true

    - name: Create custom document root
      file:
        path: /srv/www
        state: directory
        owner: apache
        group: apache
        mode: '0755'

    - name: Update Apache config to use custom root
      lineinfile:
        path: /etc/httpd/conf/httpd.conf
        regexp: '^DocumentRoot '
        line: 'DocumentRoot "/srv/www"'
        backup: yes

    - name: Update Directory directive to match new root
      blockinfile:
        path: /etc/httpd/conf/httpd.conf
        marker: "# {mark} Ansible managed block for /srv/www"
        block: |
          <Directory "/srv/www">
              AllowOverride None
              Require ip 172.20.132.125
          </Directory>

    - name: Disable ServerSignature
      lineinfile:
        path: /etc/httpd/conf/httpd.conf
        line: 'ServerSignature Off'
        create: yes

    - name: Disable ServerTokens
      lineinfile:
        path: /etc/httpd/conf/httpd.conf
        line: 'ServerTokens Prod'
        create: yes

    - name: Add custom log format
      lineinfile:
        path: /etc/httpd/conf/httpd.conf
        insertafter: EOF
        line: 'LogFormat "%h %l %u %t \"%r\" %>s %b" custom'

    - name: Set custom log format for access log
      lineinfile:
        path: /etc/httpd/conf/httpd.conf
        regexp: '^CustomLog '
        line: 'CustomLog "logs/access_log" custom'

    - name: Create logrotate config for Apache
      copy:
        dest: /etc/logrotate.d/httpd
        content: |
          /var/log/httpd/*log {
              daily
              missingok
              rotate 14
              compress
              delaycompress
              notifempty
              create 0640 root root
              sharedscripts
              postrotate
                  /bin/systemctl reload httpd.service > /dev/null 2>/dev/null || true
              endscript
          }

    - name: Restart Apache to apply changes
      service:
        name: httpd
        state: restarted

```

Run:

```bash
ansible-playbook InstallApache.yml
```

---

## Phase 5: CI/CD with Jenkins

### 1. Install Jenkins on VM1

```bash
sudo dnf install java-11-openjdk -y
sudo wget -O /etc/yum.repos.d/jenkins.repo   https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo dnf install jenkins -y
sudo systemctl enable --now jenkins
```

Access Jenkins: `http://172.20.132.125:8080`


Install plugins + create admin user.

### 2. Connect Gogs & Jenkins

- Install and configure ngrok in VM1 and VM2:
  ```
  wget https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip
  unzip ngrok.zip
  sudo mv ngrok /usr/local/bin/
  ngrok http 8080  # VM1
  ngrok http 3000  # VM2
  ```
- Add Webhook in Gogs:
  ```
  https://4567efgh.ngrok.io/github-webhook
  ```

- In Jenkins: create a **Pipeline** job.

### 3. Jenkinsfile

```groovy
pipeline {
    agent any

    triggers {
        GenericTrigger(
            genericVariables: [
                [key: 'GIT_COMMIT', value: '$GIT_COMMIT'],
                [key: 'GOGS_REPO', value: '$GOGS_REPO']
            ],
            causeString: 'Triggered by Gogs commit',
            token: 'your-jenkins-webhook-token'
        )
    }

    stages {
        stage('Run Apache Playbook') {
            steps {
                script {
                    ansiblePlaybook(
                        playbook: 'InstallApache.yml',
                        inventory: 'path/to/inventory/file',
                        extraVars: [ansible_user: 'your_user']
                    )
                }
            }
        }

        stage('Docker Image Build') {
            steps {
                script {
                    // Build Docker Image
                    def image = docker.build("nginx-custom")

                    // Save the Docker image to a tar file
                    sh 'docker save nginx-custom > nginx-custom.tar'
                }
            }
        }

        stage('Email Notification') {
            steps {
                script {
                    // List users in the 'deployG' group (customize as needed)
                    def users = sh(script: 'getent group deployG | cut -d: -f4', returnStdout: true).trim()

                    // Get the current date and time
                    def dateTime = new Date().format('yyyy-MM-dd HH:mm:ss')

                    // Send email with the required details
                    emailext(
                        subject: "Jenkins Pipeline Status: ${currentBuild.currentResult}",
                        body: """
                            Pipeline execution status: ${currentBuild.currentResult}
                            List of users in deployG: ${users}
                            Date and time of execution: ${dateTime}
                            Path to the .tar file: ${env.WORKSPACE}/nginx-custom.tar
                        """,
                        to: 'lulu.atef12@gmail.com',
                        from: 'alaa.atef.hassann@gmail.com'
                    )
                }
            }
        }
    }
}

```

---

## Phase 6: Build Docker Image

### Dockerfile

```Dockerfile
FROM nginx
COPY index.html /usr/share/nginx/html/index.html
```

**Commands:**

```bash
# Build Docker image
docker build -t nginx-custom .
# Save the Docker image to a tar file
docker save nginx-custom > nginx-custom.tar
```

---

## Phase 7: Email Notification from Jenkins

1. Install **Email Extension Plugin** in Jenkins.
2. Configure SMTP:
   - `Manage Jenkins` → `Configure System` → `Email Notification`
   - Use alaa.atef.hassann@gmail.com.

3. Add `emailext` step to Jenkinsfile:

```groovy
post {
  success {
    emailext (
      subject: "Build SUCCESSFUL",
      body: "Docker image nginx-custom saved to nginx-custom.tar. Users not in group:\n${BUILD_LOG}",
      to: 'your@email.com'
    )
  }
}
```

---

## Phase 8: Linux System Hardening on VM3

### Disable unused services

```bash
sudo systemctl disable --now avahi-daemon
sudo systemctl disable --now cups
sudo systemctl disable --now postfix
```

### Open necessary ports only

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
```
### Service Monitoring Script
```bash
sudo vi /usr/local/bin/services_status.sh
```
```bash
#!/bin/bash

# Print the header
echo -e "Service Name | Memory Usage (KB)"
echo "-------------------------------"

# Loop through each active service and display memory usage
for service in $(systemctl list-units --type=service --state=running | awk '{print $1}' | grep '.service'); do
    # Get the memory usage of the service by using 'systemctl show' to get its memory usage
    mem_usage=$(systemctl show "$service" -p MemoryCurrent --value)
    # Display the service name and its memory usage
    echo -e "$service | $mem_usage"
done

```
```bash
sudo chmod +x /usr/local/bin/services_status.sh
sudo /usr/local/bin/services_status.sh
```
### Auditd Rules

```bash
dnf install audit -y

# Monitor changes to /srv/www
-w /srv/www -p wa -k www_changes

# Monitor changes to /etc/passwd
-w /etc/passwd -p wa -k passwd_changes

# Monitor changes to /etc/group
-w /etc/group -p wa -k group_changes

```

### Cron Job to Monitor Disk Usage
```bash
sudo vi /usr/local/bin/check_disk_usage.sh
```
```bash
#!/bin/bash

# Get the current disk usage percentage for the root filesystem
disk_usage=$(df / | grep / | awk '{ print $5 }' | sed 's/%//g')

# Check if the disk usage is greater than 80%
if [ $disk_usage -gt 80 ]; then
    echo "$(date) - WARNING: Disk usage exceeded 80% (current usage: ${disk_usage}%)" >> /var/log/deploy_alerts.log
fi

```

**Crontab:**

```bash
chmod +x /usr/local/bin/check_disk_usage.sh
crontab -e
# Add:
0 * * * * /usr/local/bin/cron_monitor.sh
```

---
