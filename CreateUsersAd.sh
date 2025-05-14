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
