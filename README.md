# NEEM Stack Setup

Built and maintained by [Mohamed Aiman](https://darkguyaiman.com).

An interactive terminal setup assistant for a Node.js server stack:

- **N**ginx reverse proxy
- Nod**e**.js + PM2
- MySQL
- Micro terminal editor
- Glances system monitor
- Guided domain and HTTPS setup
- MySQL Workbench on Windows

It supports Linux, macOS, and Windows with native scripts—there is no runtime to
install before launching it.

## Interactive component picker

Choose **Install selected components** or **Remove selected components**, then
build a batch with the keyboard:

- **Up / Down** moves through the component list.
- **Space** ticks or unticks the focused component.
- **A** toggles every component.
- **Enter** reviews and confirms the batch.
- **Escape** cancels without making changes.

For example, you can tick MySQL, PM2, and Nginx and install all three in one
run. Removal uses the same picker and always asks for confirmation. Database
removal never deliberately deletes existing database files or configuration;
review your package manager's behavior and keep a backup before uninstalling.

## Quick start

### Windows — double-click

Double-click `Start-NEEM.cmd`. NEEM automatically asks for administrator access
when it is needed.

To make `neem-stack` available in every new terminal, run this once:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-NEEM-Command.ps1
```

Open a new PowerShell or Command Prompt window, then start NEEM from anywhere:

```powershell
neem-stack
```

### Linux

```bash
chmod +x install-neem-command.sh
./install-neem-command.sh
```

Open a new terminal, then start NEEM from anywhere:

```bash
neem-stack
```

The command installer writes only to your user folders and does not need root.
NEEM itself asks for `sudo` only when a system change needs root access.
Supported package managers are `apt`, `dnf`, `yum`, `pacman`, and `zypper`.

### macOS

Install [Homebrew](https://brew.sh), then install the command:

```bash
chmod +x install-neem-command.sh
./install-neem-command.sh
```

Open a new terminal and run:

```bash
neem-stack
```

For a public domain, NEEM switches Nginx from the user-level Homebrew service
to a privileged process so it can bind to ports 80 and 443.

### Windows — run the script directly

Open PowerShell as Administrator:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\neem.ps1
```

Windows needs either `winget` or Chocolatey. Nginx on Windows is suitable for
development and light workloads; for a production Internet server, Linux is the
recommended deployment target. MySQL Workbench is available as its own checkbox
and is included in the complete Windows stack.

## Guided deployment

1. Choose **Install complete stack** (or install only what you need).
2. Start your app, for example:

   ```bash
   cd /srv/my-app
   npm ci
   pm2 start npm --name my-app -- start
   ```

3. Choose **Configure PM2 startup**, then follow the command PM2 prints.
4. Point the domain's DNS `A` record to the server's public IPv4 address.
5. Choose **Connect a domain to a PM2 app**.
6. Select the PM2 process, enter its local port, and confirm the domain.
7. NEEM writes and validates the Nginx reverse-proxy configuration.
8. Choose SSL when prompted. Linux/macOS use Certbot; Windows uses win-acme.

NEEM checks the local app, DNS, and Nginx syntax before reloading the server. It
backs up an existing managed site file before replacing it.

## Command-line options

```text
./neem.sh --dry-run       # preview package/privileged commands
./neem.sh --health        # component and Nginx status
./neem.sh --help

.\neem.ps1 -DryRun
.\neem.ps1 -Health
.\neem.ps1 -Help
```

## What the scripts change

- Installs packages through the operating system's package manager.
- Installs PM2 globally with npm.
- Enables database and Nginx services where the operating system supports it.
- Writes one Nginx file per domain, named `neem-<domain>.conf`.
- Creates `/var/www/letsencrypt` on Linux/macOS for ACME challenges.
- Requests certificates only after explicit confirmation.
- Registers certificate renewal using Certbot or win-acme.

MySQL package names vary by distribution. On Arch Linux, the distribution's
MySQL-compatible MariaDB package is used. Always run `mysql_secure_installation`
and create a dedicated, least-privilege database user for each application.

## Security notes

- Review DNS and firewall rules before requesting a certificate. Ports 80 and
  443 must reach Nginx.
- Keep the application bound to `127.0.0.1`; expose it through Nginx.
- Do not run Node.js applications as root.
- The scripts never collect database passwords or place secrets in Nginx files.
- Use `--dry-run` / `-DryRun` to review installation commands first.

## Troubleshooting

Run the health check from the menu. Useful commands:

```bash
pm2 ls
pm2 logs <app-name>
curl http://127.0.0.1:<port>
sudo nginx -t
sudo certbot renew --dry-run
```

On Windows, reopen PowerShell after installing a component if its executable is
not yet on `PATH`.

## Creator

- **Email:** [mohamedaiman103@gmail.com](mailto:mohamedaiman103@gmail.com)
- **Portfolio:** [darkguyaiman.com](https://darkguyaiman.com)
- **LinkedIn:** [darkguyaiman](https://www.linkedin.com/in/darkguyaiman)
- **Instagram:** [darkguyaiman](https://www.instagram.com/darkguyaiman)
- **X (Twitter):** [thedarkguyaiman](https://x.com/thedarkguyaiman)

The interactive terminal also includes a creator screen with the supplied ASCII
portrait and these contact details.

## Support the project

<a href="https://ko-fi.com/darkguyaiman" target="_blank">
  <img src="https://img.shields.io/badge/Ko--fi-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Ko-fi" />
</a>
&nbsp;&nbsp;
<a href="https://paypal.me/thedarkguyaiman" target="_blank">
  <img src="https://img.shields.io/badge/Donate%20via%20PayPal-003087?style=for-the-badge&logo=paypal&logoColor=white" alt="PayPal" />
</a>

## Project validation

On Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\validate.ps1
```

On Linux/macOS, also validate the Bash script with:

```bash
bash -n neem.sh
```

## License

MIT
