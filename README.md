# SelfSSLGen

Bash script that generates a **10-year self-signed certificate** for the current PC's IP address, with optional fields for company details, and exports ready-to-use **IIS (.pfx)** and **PEM** bundles.

## Requirements

- `openssl` in `PATH`
- Bash (Linux, macOS, WSL, or **Git Bash** on Windows)
- On Windows, `powershell.exe` is used to detect the real LAN IP (default-route adapter)

## Quick start

On Windows (no Git Bash knowledge needed) — double-click or run from cmd/PowerShell:

```bat
run.bat
```

With options:

```bat
run.bat --yes --name "Acme Corp"
```

`run.bat` finds Git Bash automatically, runs the script from its own folder, and passes all arguments through. If Git Bash is missing, it prints the download link.

Linux / macOS / WSL / Git Bash:

```bash
./genssl.sh
```

Git Bash users can also right-click the folder → **Open Git Bash here** → `./genssl.sh`.

Edit `company.json` with your company details, then run fully automated:

```bash
./genssl.sh --yes
```

Or override fields on the fly:

```bash
./genssl.sh --yes --name "Acme Corp"
```

## Interactive prompts

Defaults below apply when `company.json` and flags are absent; JSON values and flags replace them.

| Prompt | Default | Notes |
|---|---|---|
| Company / Organization | — | Falls back to `Self-Signed` if blank |
| Department / OU | `IT` | |
| Country code | `US` | Two letters |
| State / Province | blank | |
| City / Locality | blank | |
| Email address | blank | Optional |
| Common Name (CN) | detected IP | Can be a hostname |
| Extra SANs | blank | Comma separated, e.g. `192.168.1.5,host.local` |
| Validity in days | `3650` | 10 years |
| RSA key size | `2048` | `4096` supported |
| PFX password | blank | Blank is accepted by modern IIS |

## Options

| Flag | Description |
|---|---|
| `-o, --out DIR` | Output directory (default: `output`) |
| `-n, --name NAME` | Company / Organization name |
| `-c, --cn NAME` | Common Name (default: detected IP) |
| `-s, --san LIST` | Extra SANs, comma separated |
| `-d, --days N` | Validity in days (default: `3650`) |
| `-b, --bits N` | RSA key size (default: `2048`) |
| `-p, --pfx-pass P` | Password for the IIS `.pfx` bundle (default: empty) |
| `-f, --config FILE` | Company JSON file (default: `company.json` if present) |
| `-y, --yes` | Accept defaults without prompting |
| `-h, --help` | Show help |

## Company JSON config

Edit `company.json` next to the script and it is loaded automatically. Every value becomes the prompt default; anything missing or blank is asked normally. Command-line flags always win over the JSON.

```json
{
  "organization": "Acme Corp",
  "organizational_unit": "IT",
  "country": "US",
  "state": "California",
  "locality": "San Francisco",
  "email": "admin@acme.local",
  "common_name": "",
  "san": "",
  "days": 3650,
  "key_bits": 2048,
  "pfx_password": "",
  "out_dir": "output"
}
```

| Key | Description |
|---|---|
| `organization` | Company name (O) |
| `organizational_unit` | Department (OU) |
| `country` | Two-letter country code (C) |
| `state` | State / province (ST), optional |
| `locality` | City (L), optional |
| `email` | Email address, optional |
| `common_name` | CN; blank means detected IP |
| `san` | Extra SANs, comma separated |
| `days` | Validity in days |
| `key_bits` | RSA key size |
| `pfx_password` | Password for the `.pfx` |
| `out_dir` | Output directory |

Notes:

- The JSON must be **flat** (simple key/value pairs); nested objects are not supported.
- Use forward slashes in paths (`output`), and avoid `"` inside values.
- Use a different file with `--config path\to\file.json`.
- Fully unattended run using the JSON: `run.bat --yes` (or `./genssl.sh --yes`).

## IP detection

The script finds the IP of the adapter used for the default route:

1. Linux: `ip -4 route get 1.1.1.1`
2. Windows (Git Bash): PowerShell `Get-NetRoute` + `Get-NetIPAddress`
3. Fallbacks: `Get-NetIPAddress` filtered against virtual adapters, `ipconfig`, `hostname -I`
4. Last resort: `127.0.0.1`

## Generated files

Files are written to the output directory (`output` by default), named after the CN. The `output/` folder is kept in the repo via `.gitkeep`; generated files inside it are ignored by Git.

| File | Format | Use |
|---|---|---|
| `<cn>.crt` | PEM certificate | Web servers, trust store |
| `<cn>.key` | PEM private key (600) | Web servers |
| `<cn>-bundle.pem` | PEM cert + key (600) | Apps expecting one PEM file |
| `<cn>.pfx` | PKCS#12 cert + key (600) | **IIS import** |
| `<cn>.cnf` | OpenSSL config | Reproducing / inspecting |

## Certificate details

- Self-signed, SHA-256, RSA (2048 by default)
- Validity: 3650 days (10 years)
- `basicConstraints = critical,CA:TRUE`
- `keyUsage = critical,digitalSignature,keyEncipherment,keyCertSign`
- `extendedKeyUsage = serverAuth`
- SubjectAltName automatically includes: CN, detected IP (if CN differs), `localhost`, `127.0.0.1`, hostname, plus any extra SANs

## Import into IIS

IIS Manager:

1. Open **IIS Manager** → select the server node
2. **Server Certificates** → **Import...**
3. Choose `<cn>.pfx`, enter the password, click **OK**
4. Bind it to your site under **Sites** → *your site* → **Bindings** → **Add** → `https`

Command line (elevated prompt):

```powershell
certutil -f -p "<password>" -importpfx "output\<cn>.pfx"
```

## Trust the certificate (optional)

To avoid browser warnings, add `<cn>.crt` to **Trusted Root Certification Authorities**:

- Windows: `certmgr.msc` → *Trusted Root Certification Authorities* → *Certificates* → **All Tasks → Import**
- Or: `certutil -addstore -f Root "output\<cn>.crt"` (elevated)

## Examples

Hostname certificate:

```bash
./genssl.sh --name "Acme Corp" --cn "app.acme.local" --san "192.168.1.20,app.acme.local"
```

4096-bit key and custom output directory:

```bash
./genssl.sh --bits 4096 --out "output"
```

Non-interactive with PFX password:

```bash
./genssl.sh --yes --name "Acme Corp" --pfx-pass "ChangeMe123"
```

## Security notes

- The private key and `.pfx` are not encrypted at rest by default; keep them out of version control and share carefully.
- Self-signed certificates are for internal/LAN use only. Use a real CA for public sites.
- Keep the validity at 10 years only for internal systems; public CAs cap at ~398 days.
