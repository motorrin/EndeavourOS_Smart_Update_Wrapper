# Install this package for better update management (optional)
yay -S topgrade-bin

# Create the script file and paste the code
nano ~/EOS-up

# Make the script executable
chmod +x ~/EOS-up

# Make sure that your system uses bash
echo $0

# Open the bash configuration file
nano ~/.bashrc

# Add the following alias:
alias up="~/EOS-up"

# Reload the bash configuration
source ~/.bashrc

# Run the script using the new alias:
up
