#!/bin/bash

# Ensure the script is run with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo." 
   exit 1
fi

# Log file and secure password storage
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.csv"

# Create secure directories if they do not exist
mkdir -p /var/secure
chmod 700 /var/secure

# Function to generate a random password
generate_password() {
    local password_length=12
    tr -dc A-Za-z0-9 </dev/urandom | head -c $password_length
}

# Ensure the log file exists
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Ensure the password file exists
touch "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

# Check if the input file is provided as an argument
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

input_file="$1"

# Check if the input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: File '$input_file' not found."
    exit 1
fi

# Loop through each line in the input file
while IFS=';' read -r username groups; do
    # Trim whitespace
    username=$(echo "$username" | xargs)
    groups=$(echo "$groups" | xargs)

    # Check if the username is empty
    if [ -z "$username" ]; then
        echo "Skipping invalid line with empty username."
        continue
    fi

    # Create the personal group for the user
    if ! getent group "$username" &>/dev/null; then
        groupadd "$username"
        echo "Group '$username' created." | tee -a "$LOG_FILE"
    fi

    # Check if the user already exists
    if id "$username" &>/dev/null; then
        echo "User '$username' already exists. Skipping user creation." | tee -a "$LOG_FILE"
    else
        # Create the user with the personal group and home directory
        password=$(generate_password)
        useradd -m -g "$username" -s /bin/bash "$username"
        echo "$username:$password" | chpasswd
        echo "User '$username' created with home directory." | tee -a "$LOG_FILE"

        # Set the appropriate permissions for the home directory
        chmod 700 "/home/$username"
        chown "$username:$username" "/home/$username"

        # Log the generated password securely
        echo "$username,$password" >> "$PASSWORD_FILE"
    fi

    # Split the groups by comma and add the user to each group
    IFS=',' read -r -a group_array <<< "$groups"
    for group in "${group_array[@]}"; do
        # Trim whitespace
        group=$(echo "$group" | xargs)

        # Skip if the group is empty
        if [ -z "$group" ]; then
            continue
        fi

        # Check if the group exists, if not, create it
        if ! getent group "$group" &>/dev/null; then
            groupadd "$group"
            echo "Group '$group' created." | tee -a "$LOG_FILE"
        fi

        # Add the user to the group
        usermod -aG "$group" "$username"
        echo "User '$username' added to group '$group'." | tee -a "$LOG_FILE"
    done
done < "$input_file"

echo "User and group creation completed." | tee -a "$LOG_FILE"
