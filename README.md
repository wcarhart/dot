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

Dotfiles and related tools. Specifically designed for Bash 5.2+ on macOS. Evolved from [konphig](https://github.com/wcarhart/konphig).

# Install
If you're on a fresh machine or haven't ever installed dot, clone the repository and then run `install.sh` (_not_ `scripts/install.sh`). Then change your default shell and restart your terminal.
```bash
git clone git@github.com:wcarhart/dot.git
cd dot
./install.sh
echo '/opt/homebrew/bin/bash' | sudo tee -a /etc/shells
chsh -s /opt/homebrew/bin/bash
exec '/opt/homebrew/bin/bash' -l # or just open a new terminal
```
Installation is idempotent and will not overwrite existing configurations unless `--force` is provided. When overwritten, a backup of the existing configuration is saved to `~/.dot/backups/`.

Once dot is installed, you never need to perform the installation manually ever again. Going forward you can just use `dot install`.

# Usage
Once installed, you can interact with dot via `dot`. See `dot --help` to get started.

See `shell/functions/` for the latest custom functions, all of which support `--help`. See `bashrc` for the repo entrypoint once installed. Third-party app-specific configurations live under `config/<app>/`.

To have dot manage repositories on your local machine, add them to `repos.txt`. You can configure other local options in `~/.dotrc`, specifically:
- `DOT_DIR` - the path to the local dot repository
- `CODE_DIR` - the path to your code parent directory, in which repositories will be cloned and tracked
- `DOT_MACHINE_ROLE` - `workstation` (default when omitted) or `server`

## Roles
Dot can manage certain settings based on the desired _role_ for a machine. For instance, you may want a Mac mini to be a _server_ while a MacBook is a _workstation_. You can specify the machine role in your `~/.dotrc`, set or change it via `dot install -r ROLE`, and view it via `dot role [-v]`. Server roles by default do not sleep.
