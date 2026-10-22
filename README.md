```
__/\\\\\\\\\\\\__________/\\\\\_______/\\\\\\\\\\\\\\\_        
 _\/\\\////////\\\______/\\\///\\\____\///////\\\/////__       
  _\/\\\______\//\\\___/\\\/__\///\\\________\/\\\_______      
   _\/\\\_______\/\\\__/\\\______\//\\\_______\/\\\_______     
    _\/\\\_______\/\\\_\/\\\_______\/\\\_______\/\\\_______    
     _\/\\\_______\/\\\_\//\\\______/\\\________\/\\\_______   
      _\/\\\_______/\\\___\///\\\__/\\\__________\/\\\_______  
       _\/\\\\\\\\\\\\/______\///\\\\\/___________\/\\\_______ 
        _\////////////__________\/////_____________\///________
```

Dotfiles and related tools. Specifically designed for Bash 5.2+ on macOS.

# Install
Clone the repository, then run `install.sh` (_not_ `scripts/install.sh`). Then change your default shell and restart your terminal.
```bash
git clone git@github.com:wcarhart/dot.git
cd dot
./install.sh
echo '/opt/homebrew/bin/bash' | sudo tee -a /etc/shells
chsh -s /opt/homebrew/bin/bash
exec '/opt/homebrew/bin/bash' -l # or just open a new terminal
```
Installation is idempotent and will not overwrite existing configurations unless `--force` is provided. When overwritten, a backup of the existing configuration is saved to `~/.dot-backups/`.

# Usage
Once installed, you can interact with dot via `dot`. See `dot --help` to get started.

See `shell/functions/` for the latest custom functions, all of which support `--help`. See `bashrc` for the repo entrypoint once installed.
