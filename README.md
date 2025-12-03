 # 🧨 Red Specter Offensive Framework
 [![Stars](https://img.shields.io/github/stars/RichardBarron27/red-specter-offensive-framework?style=flat&logo=github)](https://github.com/RichardBarron27/red-specter-offensive-framework/stargazers)
![Last Commit](https://img.shields.io/github/last-commit/RichardBarron27/red-specter-offensive-framework)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Kali%20-purple)
![License](https://img.shields.io/github/license/RichardBarron27/red-specter-offensive-framework)


> Companion tools: ScriptMap · Email OSINT

**Modular Offensive Security Toolkit for Ethical Hacking Labs & Authorized Penetration Testing**  
Version **1.4** • Created by **Richard B (Red Specter)**

---

## 🚩 Overview

**Red Specter** is a modular, menu-driven offensive security framework designed for:

- Ethical hacking labs  
- Red team training  
- Authorized penetration tests  
- Quick recon-to-report workflows  

It wraps core and advanced tooling in a clean workflow:

**Recon → Web Enumeration → Vulnerability Scanning → Exploitation → PrivEsc → Reporting**

Everything runs from a single launcher:

```bash
./redspecter.sh


| Module                 | Script                        | Description                               |
| ---------------------- | ----------------------------- | ----------------------------------------- |
| Core Recon             | `core/redspecter-recon.sh`    | Host + domain recon, passive footprinting |
| Web Enumeration        | `core/redspecter-webenum.sh`  | HTTP probing, tech detection              |
| Vulnerability Scanning | `core/redspecter-vulnscan.sh` | Nmap vuln scripts & baseline checks       |


| Module                      | Script                                           | Description                                       |
| --------------------------- | ------------------------------------------------ | ------------------------------------------------- |
| Advanced Recon              | `adv/adv-recon/redspecter-recon-adv.sh`          | DNS, subdomain pivoting, large-scope recon        |
| Advanced Web Enum           | `adv/adv-webenum/redspecter-webenum-adv.sh`      | Deep enumeration, optional fuzzing                |
| Advanced Vulnerability Scan | `adv/adv-vulnscan/redspecter-vulnscan-adv.sh`    | Multi-tool, deeper plugin-based scans             |
| Exploitation Support        | `adv/adv-exploitation/redspecter-exploit-adv.sh` | Controlled exploitation helpers (non-destructive) |
| PrivEsc / Post-Ex           | `adv/adv-privesc/redspecter-post-adv.sh`         | Local enumeration, privilege escalation flow      |


🕵️ Email OSINT Module (v1.1)

redspecter-osint-email.sh

Sources:

Website crawl (Safe / Normal / Aggressive)

Certificate Transparency (crt.sh)

Optional theHarvester integration

Outputs:

Unique email list

First-party vs third-party split

Markdown report

All raw data stored for auditability

Reports generated in:

reports/osint-email/


| Tool                        | Script                             | Description                                 |
| --------------------------- | ---------------------------------- | ------------------------------------------- |
| Kali Setup                  | `red_specter_kali_setup.sh`        | Optional environment bootstrap              |
| Update All Tools            | `utils/redspecter-update-tools.sh` | `apt update`, `apt upgrade`, tool installer |
| WiFi Modules (placeholders) | `utils/*`                          | Reserved for wireless tooling               |





📁 Project Structure

RedSpecter/
├── core/
├── adv/
│   ├── adv-recon/
│   ├── adv-webenum/
│   ├── adv-vulnscan/
│   ├── adv-exploitation/
│   └── adv-privesc/
├── utils/
├── reports/
├── redspecter.sh
├── redspecter-osint-email.sh
├── red_specter_kali_setup.sh
├── LICENSE
└── README.md

🔧 Installation

Clone the repository:

chmod +x redspecter.sh
chmod +x redspecter-osint-email.sh
chmod +x core/*.sh adv/*/*.sh utils/*.sh


Ensure scripts are executable:

chmod +x redspecter.sh
chmod +x redspecter-osint-email.sh
chmod +x core/*.sh adv/*/*.sh utils/*.sh

Install required tools:

./redspecter.sh
# Choose: 5) Utilities → 2) Update Red Specter Tools

▶️ Usage

Launch the framework:

./redspecter.sh


Main menu options:

1) Core Modules

2) Advanced Modules

3) OSINT / Email Intelligence

4) WiFi Tools

5) Utilities / Setup

0) Exit

Example: Running Email OSINT
3 → 1 → enter domain → choose crawl mode → report generated


Reports stored in:

reports/osint-email/

📌 Roadmap

Planned features:

 Credential Exposure OSINT (breach parsing)

 Screenshot Enumeration (gowitness-style module)

 Nuclei template updater

 JSON/Workspace Recon Mode (closer to recon-ng)

 Red Specter GitHub Release Automation

 GUI front-end (long-term)


⚖️ Legal Notice

Red Specter is for:

Ethical hacking, lab training, and authorized penetration testing only.

You must have explicit written permission from the system owner.

Misuse may violate laws such as the Computer Misuse Act (UK).

The author(s) assume no liability for unauthorized use.


🩸 About the Project

Red Specter is a personal offensive framework built by:

Richard B (Red Specter / Red-Specter.co.uk)

Vigil — the AI Co-Intelligence Partner

Aiming to combine:

Speed

Repeatability

Professional reporting

Ethical, controlled testing

📜 License

Released under the MIT License.
See LICENSE for details.

---

### 🔗 Explore the Red Specter tool suite

- 🗺 **ScriptMap** – Map, group, and document your security/automation scripts in seconds.  
  https://github.com/RichardBarron27/redspecter-scriptmap

- 🧨 **Red Specter Offensive Framework** – Modular bash framework for recon, web enum, vuln scanning, and more (Kali-friendly).  
  https://github.com/RichardBarron27/red-specter-offensive-framework

- 📧 **Red Specter Email OSINT** – Email-focused OSINT helper for investigators and defenders.  
  https://github.com/RichardBarron27/redspecter-emailosint

Follow the Red Specter project for more ethical cybersecurity tools and playbooks.



## ❤️ Support Red Specter

If these tools help you, you can support future development:

- ☕ Buy me a coffee: https://www.buymeacoffee.com/redspecter  
- 💼 PayPal: https://paypal.me/richardbarron1747  

Your support helps me keep improving Red Specter and building new tools. Thank you!




---



