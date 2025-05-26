How you can ensure that you are not running the script as root and some best practices:

1. **Check Current User**
You can check your current user status before running the script using:
```bash
whoami
```
If it shows "root", then you should switch to a regular user account.

2. **Switch to Regular User**
If you're currently root, you can switch to a regular user using:
```bash
su - username
# or
sudo -i -u username
```

3. **Verify User ID**
You can check your user ID:
```bash
id -u
```
If it returns 0, you're root. It should return your user ID (typically 1000 or higher for regular users).

4. **Best Practices for Running the Script**:

a) **Correct Way**:
```bash
# First, ensure you're a regular user
whoami  # Should show your username, not 'root'

# Then run the script
./install.sh
```

b) **If Sudo is Needed**:
```bash
# For specific commands that need sudo, the script will handle it
./install.sh
```

5. **Common Mistakes to Avoid**:

❌ **Don't do this**:
```bash
sudo ./install.sh  # Running entire script as root
```

❌ **Don't do this**:
```bash
su -  # Switching to root
./install.sh  # Running as root
```

✅ **Do this instead**:
```bash
# Run as regular user
./install.sh

# The script will use sudo internally when needed
```

6. **Troubleshooting**:

If you get the "This script should NOT be run as root" error, then you should:

1. Check your current user:
```bash
whoami
```

2. If you're root, switch to a regular user:
```bash
exit  # If you're in a root shell
# or
su - username  # Switch to specific user
```

3. Verify that you're not root:
```bash
id -u  # Should not return 0
```

4. Then run the script:
```bash
./install.sh
```

7. **Security Benefits**:

- Prevents accidental system-wide changes
- Reduces risk of system damage
- Follows principle of least privilege
- Allows better audit trail of sudo usage
- Makes it clear which operations need elevated privileges

8. **Example Workflow**:

```bash
# 1. Check current user
whoami
# Should show: username

# 2. Verify user ID
id -u
# Should show: 1000 (or similar, not 0)

# 3. Run the script
./install.sh

# 4. If prompted for sudo password, enter it
# The script will handle sudo commands internally
```

9. **For System Administrators**:

If you need to run this in a system administration context:

1. Create a dedicated service account:
```bash
sudo useradd -m -s /bin/bash corenode
```

2. Add necessary sudo permissions:
```bash
sudo visudo
# Add: corenode ALL=(ALL) NOPASSWD: /path/to/required/commands
```

3. Run the script as that user:
```bash
sudo -i -u corenode
./install.sh
```

This approach maintains security while allowing necessary administrative operations.
